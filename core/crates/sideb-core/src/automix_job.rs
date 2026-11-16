//! Automix preparation (PLAN-024): two videoIds in, one WAV out.
//!
//! The shells play the current song as they always do. While it plays they
//! ask [`SideBCore::prepare_automix`] for the transition into the next one:
//! the core resolves both streams through the orchestrator, downloads them
//! whole, runs the `automix` engine and writes a file that holds the current
//! song untouched, the transition and all the rest of the next song. A shell
//! switches its player to that file once, at a moment the current song is
//! playing, and the next song plays out of it.
//!
//! This path never records playback history: it resolves through the
//! orchestrator directly and leaves `current_playback` alone. Nothing here
//! logs a stream URL, a header or a cookie.
//!
//! Failures that a shell may want to tell apart carry a stable prefix in the
//! message of [`SideBError::StreamError`] (adding a variant would break
//! exhaustive matches in the shells): [`ERR_CANCELLED`], [`ERR_UNSUPPORTED_FORMAT`],
//! [`ERR_TOO_LONG`], [`ERR_BAD_ID`].

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use innertube::AudioQuality;

use crate::{orchestrator, SideBCore, SideBError};

pub const ERR_CANCELLED: &str = "automix:cancelled";
pub const ERR_UNSUPPORTED_FORMAT: &str = "automix:unsupported-format";
pub const ERR_TOO_LONG: &str = "automix:too-long";
pub const ERR_BAD_ID: &str = "automix:bad-id";

/// Songs kept downloaded in `<cache_dir>/audio`.
const KEEP_AUDIO_FILES: usize = 12;
/// Transition files kept in `<cache_dir>/transitions`.
const KEEP_TRANSITIONS: usize = 3;
/// Size the stems cache is pruned to (a separated window is ~50 MB).
const STEMS_CACHE_BYTES: u64 = 400 << 20;
/// A song longer than this is not worth holding in memory twice over.
const MAX_SONG_SECONDS: f64 = 12.0 * 60.0;
/// Bytes of a download beyond which a song is refused outright.
const MAX_DOWNLOAD_BYTES: usize = 40 << 20;
const CHUNK: usize = 1 << 20;
/// AAC itags: the only streams the engine can decode (YouTube's other audio
/// is Opus in WebM).
const AAC_ITAGS: [i64; 7] = [139, 140, 141, 256, 258, 325, 328];

/// The rendered transition and where everything sits in it. Seconds named
/// "file" are into the WAV at `file_path`; the others are into the song.
#[derive(Clone, Debug, uniffi::Record)]
pub struct AutomixTransitionRecord {
    /// The id the request was made with.
    pub request_id: String,
    pub from_video_id: String,
    pub to_video_id: String,
    /// "mix" (beat-matched bass swap), "cut" (filter and echo out, clean
    /// entry on the downbeat) or "fade" (no reliable beat grid).
    pub kind: String,
    /// 16-bit stereo 44.1 kHz WAV (32-bit float when baked-in gains push it
    /// over full scale). Holds, in order: the current song untouched from
    /// `a_cut_seconds`, the transition, then all the rest of the next song
    /// untouched. It is not deleted until newer transitions push it out.
    pub file_path: String,
    pub file_duration_seconds: f64,
    /// Second of the current song heard at file second 0: where the player
    /// seeks the file to when it takes over from the song.
    pub a_cut_seconds: f64,
    /// File seconds between which the file is neither the plain current song
    /// nor the plain next one. Before `overlap_start_seconds` the file is the
    /// current song sample for sample.
    pub overlap_start_seconds: f64,
    pub overlap_end_seconds: f64,
    /// File second minus next-song second. Exact for file times from
    /// `overlap_end_seconds` on, where the file is the next song untouched.
    pub b_offset_seconds: f64,
    /// Second of the next song at which it enters the file; its earlier
    /// seconds are not in the file.
    pub b_entry_seconds: f64,
    /// File second at which the UI should switch to the next song: the bass
    /// swap of a mix, the next song's entry otherwise.
    pub handover_seconds: f64,
    /// Tempos as measured (0 when there was no usable estimate), in the
    /// engine's counting (a half or double tempo is possible).
    pub bpm_from: f64,
    pub bpm_to: f64,
    /// Bars between the start of the change and the next song being fully in.
    pub bars: u32,
    /// Whether the HT-Demucs model separated the stems (otherwise a
    /// frequency split, or no stems at all for "cut" and "fade").
    pub stems_model: bool,
    /// One line, in Spanish, about what was done and why.
    pub detail: String,
}

/// Which preparation is the current one. A newer request supersedes the
/// older; cancelling or superseding sets the older one's flag, which the
/// engine checks between its stages.
#[derive(Default)]
pub(crate) struct AutomixState {
    counter: AtomicU64,
    current: Mutex<Option<Job>>,
    /// Held by the blocking part of a preparation: at most one at a time. A
    /// superseded job gives it up at its next checkpoint.
    engine: Arc<Mutex<()>>,
}

struct Job {
    request_id: String,
    token: u64,
    cancel: Arc<AtomicBool>,
}

impl AutomixState {
    fn begin(&self, request_id: &str) -> (u64, Arc<AtomicBool>) {
        let token = self.counter.fetch_add(1, Ordering::SeqCst) + 1;
        let cancel = Arc::new(AtomicBool::new(false));
        let mut current = self.current.lock().unwrap_or_else(|e| e.into_inner());
        let job = Job { request_id: request_id.to_owned(), token, cancel: cancel.clone() };
        if let Some(older) = current.replace(job) {
            older.cancel.store(true, Ordering::SeqCst);
        }
        (token, cancel)
    }

    fn is_current(&self, token: u64) -> bool {
        self.current.lock().unwrap_or_else(|e| e.into_inner()).as_ref().is_some_and(|j| j.token == token)
    }

    fn finish(&self, token: u64) {
        let mut current = self.current.lock().unwrap_or_else(|e| e.into_inner());
        if current.as_ref().is_some_and(|j| j.token == token) {
            *current = None;
        }
    }

    pub(crate) fn cancel(&self, request_id: &str) {
        let mut current = self.current.lock().unwrap_or_else(|e| e.into_inner());
        if current.as_ref().is_some_and(|j| j.request_id == request_id) {
            if let Some(job) = current.take() {
                job.cancel.store(true, Ordering::SeqCst);
            }
        }
    }
}

fn stream_error(message: impl Into<String>) -> SideBError {
    SideBError::StreamError { message: message.into() }
}

fn cancelled() -> SideBError {
    stream_error(ERR_CANCELLED)
}

/// A videoId as a file name: the ids YouTube uses, and nothing that could
/// walk out of the cache directory.
fn safe_id(id: &str) -> Result<&str, SideBError> {
    let ok = !id.is_empty() && id.len() <= 64 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    if ok { Ok(id) } else { Err(stream_error(format!("{ERR_BAD_ID}: identificador no válido para automix"))) }
}

fn linear(gain_db: Option<f64>) -> f32 {
    gain_db.map_or(1.0, |db| 10f32.powf(db.clamp(-30.0, 30.0) as f32 / 20.0))
}

/// Resolves `video_id` to an AAC stream. The orchestrator's pick is AAC
/// almost always; when it is not (an Opus-only answer) the client that gave
/// it is excluded and the chain tried again, which lands on another client's
/// formats.
async fn resolve_aac(core: &SideBCore, video_id: &str, is_upload: bool) -> Result<orchestrator::PlaybackData, SideBError> {
    let mut disabled: HashSet<String> = HashSet::new();
    for _ in 0..3 {
        let playback = core.orchestrator.resolve(video_id, is_upload, AudioQuality::High, &disabled).await?;
        if AAC_ITAGS.contains(&playback.itag) && playback.stream_url.starts_with("http") {
            return Ok(playback);
        }
        disabled.insert(playback.stream_client.clone());
    }
    Err(stream_error(format!("{ERR_UNSUPPORTED_FORMAT}: ningún cliente ofreció audio AAC para esta canción")))
}

/// Downloads the whole stream with ranged 1 MB requests (an unranged GET of
/// a media URL is throttled hard), with the headers the orchestrator
/// resolved it with.
async fn download(playback: &orchestrator::PlaybackData, cancel: &AtomicBool) -> Result<Vec<u8>, SideBError> {
    let http = crate::http::client();
    let mut data: Vec<u8> = Vec::new();
    loop {
        if cancel.load(Ordering::Relaxed) {
            return Err(cancelled());
        }
        let range = format!("bytes={}-{}", data.len(), data.len() + CHUNK - 1);
        let mut attempt = 0;
        let response = loop {
            let mut request = http.get(&playback.stream_url).header("Range", &range).timeout(Duration::from_secs(30));
            for (name, value) in &playback.headers {
                if !name.eq_ignore_ascii_case("range") {
                    request = request.header(name, value);
                }
            }
            match request.send().await {
                Ok(r) => break r,
                Err(e) if attempt < 1 => {
                    attempt += 1;
                    tracing::debug!(error = %e.without_url(), "automix: chunk retry");
                }
                Err(e) => return Err(SideBError::NetworkError { message: e.without_url().to_string() }),
            }
        };
        let status = response.status();
        if status.as_u16() == 416 {
            break;
        }
        if !status.is_success() {
            return Err(SideBError::NetworkError { message: format!("descarga de audio: HTTP {status}") });
        }
        let total = response
            .headers()
            .get(reqwest::header::CONTENT_RANGE)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.rsplit('/').next())
            .and_then(|v| v.parse::<usize>().ok());
        let whole = status.as_u16() == 200;
        let bytes = response
            .bytes()
            .await
            .map_err(|e| SideBError::NetworkError { message: e.without_url().to_string() })?;
        let got = bytes.len();
        if whole {
            // The server ignored the range and sent everything.
            data = bytes.to_vec();
            break;
        }
        data.extend_from_slice(&bytes);
        if data.len() > MAX_DOWNLOAD_BYTES {
            return Err(stream_error(format!("{ERR_TOO_LONG}: la canción pesa demasiado para automix")));
        }
        if got < CHUNK || total.is_some_and(|t| data.len() >= t) {
            break;
        }
    }
    if data.is_empty() {
        return Err(SideBError::NetworkError { message: "descarga de audio vacía".into() });
    }
    Ok(data)
}

/// The song's audio on disk, downloading it if it is not there yet.
async fn fetch_audio(
    core: &SideBCore,
    video_id: &str,
    is_upload: bool,
    audio_dir: &Path,
    cancel: &AtomicBool,
) -> Result<PathBuf, SideBError> {
    let path = audio_dir.join(format!("{}.m4a", safe_id(video_id)?));
    if std::fs::metadata(&path).is_ok_and(|m| m.len() > 0) {
        touch(&path);
        return Ok(path);
    }
    let playback = resolve_aac(core, video_id, is_upload).await?;
    let data = download(&playback, cancel).await?;
    // Written under another name and renamed: a half-written file must never
    // be mistaken for a song.
    let io = |e: std::io::Error| SideBError::Other { message: format!("caché de automix: {e}") };
    std::fs::create_dir_all(audio_dir).map_err(io)?;
    let part = path.with_extension("m4a.part");
    std::fs::write(&part, &data).map_err(io)?;
    std::fs::rename(&part, &path).map_err(io)?;
    Ok(path)
}

fn touch(path: &Path) {
    if let Ok(file) = std::fs::OpenOptions::new().write(true).open(path) {
        let _ = file.set_modified(std::time::SystemTime::now());
    }
}

/// Deletes the oldest files of `dir` beyond `keep`, never those in `protect`.
fn prune_files(dir: &Path, keep: usize, protect: &[&Path]) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    let mut files: Vec<(std::time::SystemTime, PathBuf)> = entries
        .flatten()
        .filter_map(|e| {
            let meta = e.metadata().ok()?;
            meta.is_file().then(|| (meta.modified().unwrap_or(std::time::UNIX_EPOCH), e.path()))
        })
        .collect();
    files.sort_by(|a, b| b.0.cmp(&a.0));
    for (_, path) in files.into_iter().skip(keep) {
        if !protect.contains(&path.as_path()) {
            let _ = std::fs::remove_file(path);
        }
    }
}

fn decode(path: &Path, key: &str) -> Result<automix::Track, SideBError> {
    let audio = automix::audio::load(path).map_err(|e| stream_error(format!("no se pudo decodificar el audio: {e}")))?;
    if audio.seconds() > MAX_SONG_SECONDS {
        return Err(stream_error(format!("{ERR_TOO_LONG}: la canción dura más de {} minutos", MAX_SONG_SECONDS / 60.0)));
    }
    Ok(automix::Track::new(key.to_owned(), key.to_owned(), audio))
}

pub(crate) struct Request {
    pub request_id: String,
    pub from_video_id: String,
    pub from_is_upload: bool,
    pub from_gain_db: Option<f64>,
    pub to_video_id: String,
    pub to_is_upload: bool,
    pub to_gain_db: Option<f64>,
    pub cache_dir: String,
}

pub(crate) async fn prepare(core: &SideBCore, request: Request) -> Result<AutomixTransitionRecord, SideBError> {
    let from = safe_id(&request.from_video_id)?.to_owned();
    let to = safe_id(&request.to_video_id)?.to_owned();
    let (token, cancel) = core.automix.begin(&request.request_id);
    let outcome = run(core, &request, &from, &to, token, &cancel).await;
    core.automix.finish(token);
    outcome
}

async fn run(
    core: &SideBCore,
    request: &Request,
    from: &str,
    to: &str,
    token: u64,
    cancel: &Arc<AtomicBool>,
) -> Result<AutomixTransitionRecord, SideBError> {
    let started = std::time::Instant::now();
    let root = PathBuf::from(&request.cache_dir);
    let audio_dir = root.join("audio");

    let from_path = fetch_audio(core, from, request.from_is_upload, &audio_dir, cancel).await?;
    let to_path = fetch_audio(core, to, request.to_is_upload, &audio_dir, cancel).await?;
    prune_files(&audio_dir, KEEP_AUDIO_FILES, &[&from_path, &to_path]);
    if cancel.load(Ordering::SeqCst) {
        return Err(cancelled());
    }
    let downloaded = started.elapsed();

    let transitions_dir = root.join("transitions");
    let stems_dir = root.join("stems");
    // Named per request: a superseded job deleting its own file must never take
    // a newer job's file for the same pair with it.
    let wav_path = transitions_dir.join(format!("{from}__{to}__{token}.wav"));
    let options = automix::Options {
        a_gain: linear(request.from_gain_db),
        b_gain: linear(request.to_gain_db),
        baseline: false,
        cancel: Some(cancel.clone()),
        ..automix::Options::default()
    };

    let engine = core.automix.engine.clone();
    let job_cancel = cancel.clone();
    let (from_key, to_key, wav) = (from.to_owned(), to.to_owned(), wav_path.clone());
    let rendered = tokio::task::spawn_blocking(move || -> Result<(automix::Transition, f64), SideBError> {
        // One preparation at a time. A superseded one is waiting for its next
        // checkpoint to give this up, so the wait is bounded by one stage.
        let _turn = engine.lock().unwrap_or_else(|e| e.into_inner());
        if job_cancel.load(Ordering::SeqCst) {
            return Err(cancelled());
        }
        let a = decode(&from_path, &from_key)?;
        let b = decode(&to_path, &to_key)?;
        let decoded = started.elapsed().as_secs_f64();
        let transition = automix::prepare(&a, &b, &stems_dir, &options).map_err(|e| {
            if e.downcast_ref::<automix::Cancelled>().is_some() {
                cancelled()
            } else {
                stream_error(format!("no se pudo preparar la transición: {e}"))
            }
        })?;
        drop((a, b));
        if job_cancel.load(Ordering::SeqCst) {
            return Err(cancelled());
        }
        automix::audio::save_for_playback(&wav, &transition.audio)
            .map_err(|e| SideBError::Other { message: format!("no se pudo escribir la transición: {e}") })?;
        automix::stems::prune_cache(&stems_dir, STEMS_CACHE_BYTES);
        Ok((transition, decoded))
    })
    .await
    .map_err(|e| SideBError::Other { message: format!("la preparación de automix se interrumpió: {e}") })??;
    let (transition, decoded) = rendered;

    // A newer request, or a cancel, arrived while this one was working.
    if !core.automix.is_current(token) {
        let _ = std::fs::remove_file(&wav_path);
        return Err(cancelled());
    }
    prune_files(&transitions_dir, KEEP_TRANSITIONS, &[&wav_path]);

    tracing::info!(
        from,
        to,
        kind = transition.kind.as_str(),
        stems_model = transition.stems_model,
        download_s = downloaded.as_secs_f64(),
        decoded_s = decoded,
        total_s = started.elapsed().as_secs_f64(),
        "automix: transition ready"
    );
    Ok(AutomixTransitionRecord {
        request_id: request.request_id.clone(),
        from_video_id: from.to_owned(),
        to_video_id: to.to_owned(),
        kind: transition.kind.as_str().to_owned(),
        file_path: wav_path.to_string_lossy().into_owned(),
        file_duration_seconds: transition.file_seconds(),
        a_cut_seconds: transition.a_cut,
        overlap_start_seconds: transition.overlap_start,
        overlap_end_seconds: transition.overlap_end,
        b_offset_seconds: transition.b_offset,
        b_entry_seconds: transition.b_entry,
        handover_seconds: transition.handover,
        bpm_from: transition.bpm_a,
        bpm_to: transition.bpm_b,
        bars: transition.bars,
        stems_model: transition.stems_model,
        detail: transition.detail,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn newer_request_supersedes_older() {
        let state = AutomixState::default();
        let (first, first_cancel) = state.begin("one");
        assert!(state.is_current(first));
        let (second, second_cancel) = state.begin("two");
        assert!(first_cancel.load(Ordering::SeqCst), "the older one is told to stop");
        assert!(!state.is_current(first) && state.is_current(second));
        assert!(!second_cancel.load(Ordering::SeqCst));
        // Cancelling an id that is not the current one changes nothing.
        state.cancel("one");
        assert!(state.is_current(second));
        state.cancel("two");
        assert!(second_cancel.load(Ordering::SeqCst) && !state.is_current(second));
    }

    #[test]
    fn ids_cannot_leave_the_cache() {
        assert!(safe_id("dQw4w9WgXcQ").is_ok());
        assert!(safe_id("../etc/passwd").is_err());
        assert!(safe_id("a/b").is_err());
        assert!(safe_id("").is_err());
    }

    #[test]
    fn gains_are_decibels() {
        assert_eq!(linear(None), 1.0);
        assert!((linear(Some(-6.0)) - 0.501).abs() < 0.001);
        assert!((linear(Some(500.0)) - 31.6).abs() < 0.1, "absurd gains are clamped to +30 dB");
    }

    #[test]
    fn pruning_keeps_the_newest_and_the_protected() {
        let dir = std::env::temp_dir().join(format!("automix-prune-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for (i, name) in ["a", "b", "c", "d"].iter().enumerate() {
            let path = dir.join(name);
            std::fs::write(&path, b"x").unwrap();
            let file = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
            file.set_modified(std::time::UNIX_EPOCH + Duration::from_secs(1000 + i as u64)).unwrap();
        }
        let oldest = dir.join("a");
        prune_files(&dir, 2, &[&oldest]);
        let mut left: Vec<String> =
            std::fs::read_dir(&dir).unwrap().flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
        left.sort();
        assert_eq!(left, ["a", "c", "d"]);
        std::fs::remove_dir_all(dir).ok();
    }

    /// Live smoke test of the whole path (network): two real songs, anonymous.
    /// `cargo test -p sideb-core automix_live -- --ignored --nocapture`
    #[tokio::test(flavor = "multi_thread")]
    #[ignore = "network: resolves and downloads two songs from YouTube Music"]
    async fn automix_live() {
        let dir = std::env::temp_dir().join(format!("automix-live-{}", std::process::id()));
        let core = SideBCore::new(dir.join("data").to_string_lossy().into_owned()).unwrap();
        let record = core
            .prepare_automix(
                "live".into(),
                "OsfAnsMY21M".into(),
                false,
                Some(-1.5),
                "2nR1zrNzgcY".into(),
                false,
                None,
                dir.join("automix").to_string_lossy().into_owned(),
            )
            .await
            .expect("prepare_automix");
        println!("{record:#?}");
        assert_eq!(record.kind, "cut", "{}", record.detail);
        assert!(std::fs::metadata(&record.file_path).unwrap().len() > 1_000_000);
        // A second call hits the audio cache and replaces the file.
        assert!(core.prepare_automix("live2".into(), "OsfAnsMY21M".into(), false, None, "2nR1zrNzgcY".into(), false, None, dir.join("automix").to_string_lossy().into_owned()).await.is_ok());
        // A cancelled request reports it.
        core.cancel_automix("never-started".into());
        std::fs::remove_dir_all(dir).ok();
    }
}
