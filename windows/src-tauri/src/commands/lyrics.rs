use crate::{AppState, CommandError};
use std::sync::atomic::Ordering;

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct LyricLineDto {
    time_ms: Option<u64>,
    end_time_ms: Option<u64>,
    text: String,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct LyricsDto {
    provider: String,
    is_synced: bool,
    lines: Vec<LyricLineDto>,
}

impl From<sideb_core::LyricsInfo> for LyricsDto {
    fn from(info: sideb_core::LyricsInfo) -> Self {
        Self {
            provider: info.provider,
            is_synced: info.is_synced,
            lines: info
                .lines
                .into_iter()
                .map(|line| LyricLineDto {
                    time_ms: line.time_ms,
                    end_time_ms: line.end_time_ms,
                    text: line.text,
                })
                .collect(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct KaraokeWordDto {
    text: String,
    start_ms: u64,
    end_ms: u64,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct KaraokeLineDto {
    time_ms: Option<u64>,
    end_time_ms: Option<u64>,
    text: String,
    words: Vec<KaraokeWordDto>,
    translation: Option<String>,
    role: Option<String>,
    agent: Option<String>,
    group_id: Option<String>,
    section: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct KaraokeLyricsDto {
    provider: String,
    is_synced: bool,
    instrumental: bool,
    lines: Vec<KaraokeLineDto>,
}

impl From<sideb_core::KaraokeLyricsInfo> for KaraokeLyricsDto {
    fn from(info: sideb_core::KaraokeLyricsInfo) -> Self {
        Self {
            provider: info.provider,
            is_synced: info.is_synced,
            instrumental: info.instrumental,
            lines: info
                .lines
                .into_iter()
                .map(|line| KaraokeLineDto {
                    time_ms: line.time_ms,
                    end_time_ms: line.end_time_ms,
                    text: line.text,
                    words: line
                        .words
                        .into_iter()
                        .map(|word| KaraokeWordDto {
                            text: word.text,
                            start_ms: word.start_ms,
                            end_ms: word.end_ms,
                        })
                        .collect(),
                    translation: line.translation,
                    role: line.role,
                    agent: line.agent,
                    group_id: line.group_id,
                    section: line.section,
                })
                .collect(),
        }
    }
}

fn duration_seconds(duration: Option<f64>) -> Option<u64> {
    duration
        .filter(|seconds| seconds.is_finite() && *seconds > 0.0)
        .map(|seconds| seconds.round().max(1.0) as u64)
}

/// Additive rich endpoint: the shared core owns providers, parsing and cache policy.
#[tauri::command]
pub(crate) async fn get_karaoke_lyrics(
    state: tauri::State<'_, AppState>,
    video_id: String,
    title: String,
    artists: String,
    album: Option<String>,
    duration: Option<f64>,
    force_refresh: bool,
) -> Result<Option<KaraokeLyricsDto>, CommandError> {
    let video_id = video_id.trim();
    if video_id.is_empty() {
        return Err(CommandError::new(
            "INVALID_ID",
            "La canción no tiene un identificador válido.",
        ));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let core = state
        .core
        .read()
        .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo acceder al motor de letras."))?
        .clone()
        .ok_or_else(|| {
            CommandError::new(
                "CORE_NOT_INITIALIZED",
                "El motor de Side B todavía no está listo.",
            )
        })?;
    let result = core
        .get_karaoke_lyrics(
            video_id.to_owned(),
            title,
            artists,
            album,
            duration_seconds(duration),
            force_refresh,
        )
        .await;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la carga de letras.",
        ));
    }
    result
        .map(|info| info.map(KaraokeLyricsDto::from))
        .map_err(|_| {
            CommandError::new(
                "LYRICS_FAILED",
                "No se pudieron cargar las letras. Intentá de nuevo.",
            )
        })
}

#[tauri::command]
pub(crate) async fn get_lyrics(
    state: tauri::State<'_, AppState>,
    video_id: String,
    title: String,
    artists: String,
    album: Option<String>,
    duration: Option<f64>,
) -> Result<Option<LyricsDto>, CommandError> {
    let video_id = video_id.trim();
    if video_id.is_empty() {
        return Err(CommandError::new(
            "INVALID_ID",
            "La canción no tiene un identificador válido.",
        ));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let core = state
        .core
        .read()
        .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo acceder al motor de letras."))?
        .clone()
        .ok_or_else(|| {
            CommandError::new(
                "CORE_NOT_INITIALIZED",
                "El motor de Side B todavía no está listo.",
            )
        })?;
    let duration_secs = duration_seconds(duration);
    // The shared core owns the same provider chain and cache used by macOS.
    let result = core
        .get_lyrics(video_id.to_owned(), title, artists, album, duration_secs)
        .await;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la carga de letras.",
        ));
    }
    result.map(|info| info.map(LyricsDto::from)).map_err(|_| {
        CommandError::new(
            "LYRICS_FAILED",
            "No se pudieron cargar las letras. Intentá de nuevo.",
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rich_roundtrip_keeps_milliseconds_unicode_and_voice_metadata() {
        let json = serde_json::to_value(KaraokeLyricsDto::from(sideb_core::KaraokeLyricsInfo {
            provider: "TTML".into(),
            is_synced: true,
            instrumental: false,
            lines: vec![
                sideb_core::KaraokeLineInfo {
                    time_ms: Some(3418),
                    end_time_ms: Some(9000),
                    text: "¡Sí 👩🏽‍🚀! שלום".into(),
                    words: vec![sideb_core::KaraokeWordInfo {
                        text: "¡Sí 👩🏽‍🚀!".into(),
                        start_ms: 3418,
                        end_ms: 4800,
                    }],
                    translation: Some("Yes!".into()),
                    role: Some("x-bg".into()),
                    agent: Some("v2".into()),
                    group_id: Some("g1".into()),
                    section: Some("chorus".into()),
                },
                sideb_core::KaraokeLineInfo {
                    time_ms: None,
                    end_time_ms: None,
                    text: "Plain".into(),
                    words: vec![],
                    translation: None,
                    role: None,
                    agent: None,
                    group_id: None,
                    section: None,
                },
            ],
        }))
        .unwrap();
        let decoded: serde_json::Value =
            serde_json::from_str(&serde_json::to_string(&json).unwrap()).unwrap();
        let line = &decoded["lines"][0];
        assert_eq!(line["timeMs"], 3418);
        assert_eq!(line["timeMs"].as_f64().unwrap() / 1000.0, 3.418);
        assert_eq!(line["endTimeMs"], 9000);
        assert_eq!(line["words"][0]["startMs"], 3418);
        assert_eq!(line["words"][0]["endMs"], 4800);
        assert_eq!(line["text"], "¡Sí 👩🏽‍🚀! שלום");
        assert_eq!(line["translation"], "Yes!");
        assert_eq!(line["role"], "x-bg");
        assert_eq!(line["agent"], "v2");
        assert_eq!(line["groupId"], "g1");
        assert_eq!(line["section"], "chorus");
        assert!(decoded["lines"][1]["timeMs"].is_null());
        assert_eq!(decoded["isSynced"], true);
        assert_eq!(decoded["instrumental"], false);
    }

    #[test]
    fn instrumental_and_unknown_duration_are_not_coerced_to_empty_or_zero() {
        let json = serde_json::to_value(KaraokeLyricsDto::from(sideb_core::KaraokeLyricsInfo {
            provider: "LRCLIB".into(),
            is_synced: false,
            instrumental: true,
            lines: vec![],
        }))
        .unwrap();
        assert_eq!(json["instrumental"], true);
        assert_eq!(json["lines"].as_array().unwrap().len(), 0);
        for duration in [
            None,
            Some(0.0),
            Some(-1.0),
            Some(f64::NAN),
            Some(f64::INFINITY),
        ] {
            assert_eq!(duration_seconds(duration), None);
        }
        assert_eq!(duration_seconds(Some(0.1)), Some(1));
        assert_eq!(duration_seconds(Some(240.6)), Some(241));
    }

    #[test]
    fn preserves_provider_timing_and_plain_lines_in_camel_case() {
        let info = sideb_core::LyricsInfo {
            provider: "LRCLIB".to_owned(),
            is_synced: true,
            lines: vec![
                sideb_core::LyricLineInfo {
                    time_ms: Some(1250),
                    end_time_ms: Some(4000),
                    text: "Timed".to_owned(),
                },
                sideb_core::LyricLineInfo {
                    time_ms: None,
                    end_time_ms: None,
                    text: "Plain".to_owned(),
                },
            ],
        };
        let json = serde_json::to_value(LyricsDto::from(info)).unwrap();
        assert_eq!(json["provider"], "LRCLIB");
        assert_eq!(json["isSynced"], true);
        assert_eq!(json["lines"][0]["timeMs"], 1250);
        assert_eq!(json["lines"][0]["endTimeMs"], 4000);
        assert!(json["lines"][1]["timeMs"].is_null());
        assert_eq!(json["lines"][1]["text"], "Plain");
    }
}
