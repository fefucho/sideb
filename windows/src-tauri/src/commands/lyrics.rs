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
    let duration_secs = duration
        .filter(|seconds| seconds.is_finite() && *seconds > 0.0)
        .map(|seconds| seconds.round() as u64);
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
