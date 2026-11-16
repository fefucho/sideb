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
/// `quality: "stems"` was asked for and the model is not on disk (it starts
/// downloading); the shell keeps the fast transition.
pub const ERR_MODEL_UNAVAILABLE: &str = "automix:model-unavailable";
pub const ERR_BAD_QUALITY: &str = "automix:bad-quality";
pub const ERR_NO_CACHE_DIR: &str = "automix:no-cache-dir";

/// Songs kept downloaded in `<cache_dir>/audio`.
const KEEP_AUDIO_FILES: usize = 12;
/// Transition files kept in `<cache_dir>/transitions`.
const KEEP_TRANSITIONS: usize = 3;
/// Size the stems cache is pruned to (the two stretches of one song are ~70 MB).
const STEMS_CACHE_BYTES: u64 = 500 << 20;
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
    /// The quality asked for: "fast" or "stems". A "stems" request for a pair
    /// that ends up as "cut" or "fade" has `stems_model == false`: there was
    /// nothing to separate.
    pub quality: String,
    /// Whether this render cuts at the same place the "fast" one does, so a
    /// shell that swapped to the fast file can swap again without the cut
    /// moving. Always true today: both renders share one plan (made on the
    /// frequency split) and "stems" only re-renders it with the model's stems.
    pub same_cut_as_fast: bool,
    /// Seconds of audio the model ran on for this call (0 for "fast", and
    /// when a prefetch had separated the stretches already).
    pub separated_seconds: f64,
    /// Wall-clock seconds this call took, downloads included.
    pub elapsed_seconds: f64,
    /// One line, in Spanish, about what was done and why.
    pub detail: String,
}

/// A song of the queue, for [`SideBCore::prefetch_automix`].
#[derive(Clone, Debug, uniffi::Record)]
pub struct AutomixQueueItem {
    pub video_id: String,
    pub is_upload: bool,
}

/// User-facing settings, shared by both apps and kept in the core's database.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct AutomixSettings {
    /// "auto" (the shell decides from `automix_capability`), "fast" or "stems".
    pub quality: String,
    /// Whether the shell should stick to "fast" when on battery or in low
    /// power mode. The core only stores the rule; platform state is the
    /// shell's.
    pub fast_on_battery: bool,
    /// Whether the shell should not transition between two songs of the same
    /// album.
    pub skip_same_album: bool,
    /// "auto", "gpu" or "cpu": where the model may run.
    pub compute: String,
    /// How many upcoming songs are prefetched, 1 to 3.
    pub lookahead: u8,
    /// Keep the model in memory between transitions; otherwise it is
    /// released after 60 seconds without use.
    pub keep_model_loaded: bool,
}

impl Default for AutomixSettings {
    fn default() -> Self {
        AutomixSettings {
            quality: "auto".into(),
            fast_on_battery: true,
            skip_same_album: true,
            compute: "auto".into(),
            lookahead: 1,
            keep_model_loaded: false,
        }
    }
}

impl AutomixSettings {
    /// The same settings with every field forced into its valid range.
    fn sanitised(mut self) -> Self {
        if !["auto", "fast", "stems"].contains(&self.quality.as_str()) {
            self.quality = "auto".into();
        }
        if !["auto", "gpu", "cpu"].contains(&self.compute.as_str()) {
            self.compute = "auto".into();
        }
        self.lookahead = self.lookahead.clamp(1, 3);
        self
    }
}

/// What this machine can do, for a shell to choose between "fast" and "stems".
#[derive(Clone, Debug, uniffi::Record)]
pub struct AutomixCapability {
    /// The stem model is on disk.
    pub model_ready: bool,
    pub model_downloading: bool,
    /// Seconds of audio the model separates per second of wall clock, once
    /// loaded, from the real separations this machine has done (prefetches and
    /// "stems" transitions); `None` until it has done one.
    pub realtime_factor: Option<f64>,
    /// The model is there and fast enough that a "stems" transition arrives
    /// in time: `realtime_factor >= 2` (a typical one separates ~40 s of
    /// audio, so about 20 s or less). False while unmeasured.
    pub stems_recommended: bool,
    /// What the model runs on: "CoreML (CPUOnly MLProgram)", "DirectML",
    /// "CPU"; empty until the model has been loaded once.
    pub provider: String,
}

/// Disk used by the automix caches, in bytes.
#[derive(Clone, Debug, uniffi::Record)]
pub struct AutomixCacheUsage {
    pub audio_bytes: u64,
    pub stems_bytes: u64,
    pub transitions_bytes: u64,
    pub model_bytes: u64,
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
    /// The prefetch in progress, if any: its token and cancel flag.
    prefetch: Mutex<Option<(u64, Arc<AtomicBool>)>>,
    /// Preparations in progress (the prefetch waits for them to end).
    preparing: Arc<std::sync::atomic::AtomicUsize>,
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

    /// Replaces the prefetch in progress (cancelling it) with a new one.
    fn begin_prefetch(&self) -> (u64, Arc<AtomicBool>) {
        let token = self.counter.fetch_add(1, Ordering::SeqCst) + 1;
        let cancel = Arc::new(AtomicBool::new(false));
        let mut current = self.prefetch.lock().unwrap_or_else(|e| e.into_inner());
        if let Some((_, older)) = current.replace((token, cancel.clone())) {
            older.store(true, Ordering::SeqCst);
        }
        (token, cancel)
    }

    fn prefetch_is_current(&self, token: u64) -> bool {
        self.prefetch.lock().unwrap_or_else(|e| e.into_inner()).as_ref().is_some_and(|(t, _)| *t == token)
    }

    pub(crate) fn cancel_prefetch(&self) {
        if let Some((_, flag)) = self.prefetch.lock().unwrap_or_else(|e| e.into_inner()).take() {
            flag.store(true, Ordering::SeqCst);
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
    // Unique, because a prefetch and a preparation may fetch the same song.
    static PARTS: AtomicU64 = AtomicU64::new(0);
    let part = path.with_extension(format!("m4a.part{}", PARTS.fetch_add(1, Ordering::SeqCst)));
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
    pub quality: String,
    pub cache_dir: String,
}

const KEY_SETTINGS: &str = "automix.settings";
const KEY_CACHE_DIR: &str = "automix.cache_dir";
const KEY_REALTIME: &str = "automix.realtime_factor";
const KEY_PROVIDER: &str = "automix.provider";
/// A "stems" transition separates about 40 s of audio; at this factor that is
/// 20 s or less.
const STEMS_RECOMMENDED_FACTOR: f64 = 2.0;

// ------------------------------------------------------------------ settings

pub(crate) fn load_settings(core: &SideBCore) -> AutomixSettings {
    core.db
        .get_setting(KEY_SETTINGS)
        .and_then(|raw| serde_json::from_str::<StoredSettings>(&raw).ok())
        .map(AutomixSettings::from)
        .unwrap_or_default()
        .sanitised()
}

/// What is in the database: every field optional, so settings written by an
/// older or newer core still read.
#[derive(serde::Serialize, serde::Deserialize, Default)]
struct StoredSettings {
    quality: Option<String>,
    fast_on_battery: Option<bool>,
    skip_same_album: Option<bool>,
    compute: Option<String>,
    lookahead: Option<u8>,
    keep_model_loaded: Option<bool>,
}

impl From<StoredSettings> for AutomixSettings {
    fn from(s: StoredSettings) -> Self {
        let d = AutomixSettings::default();
        AutomixSettings {
            quality: s.quality.unwrap_or(d.quality),
            fast_on_battery: s.fast_on_battery.unwrap_or(d.fast_on_battery),
            skip_same_album: s.skip_same_album.unwrap_or(d.skip_same_album),
            compute: s.compute.unwrap_or(d.compute),
            lookahead: s.lookahead.unwrap_or(d.lookahead),
            keep_model_loaded: s.keep_model_loaded.unwrap_or(d.keep_model_loaded),
        }
    }
}

/// Puts the settings the engine cares about into effect.
pub(crate) fn apply_settings(settings: &AutomixSettings) {
    use automix::model::Compute;
    automix::model::set_compute(match settings.compute.as_str() {
        "gpu" => Compute::Gpu,
        "cpu" => Compute::Cpu,
        _ => Compute::Auto,
    });
    automix::model::set_idle_release(if settings.keep_model_loaded { None } else { Some(Duration::from_secs(60)) });
}

pub(crate) fn save_settings(core: &SideBCore, settings: AutomixSettings) -> AutomixSettings {
    let settings = settings.sanitised();
    let stored = StoredSettings {
        quality: Some(settings.quality.clone()),
        fast_on_battery: Some(settings.fast_on_battery),
        skip_same_album: Some(settings.skip_same_album),
        compute: Some(settings.compute.clone()),
        lookahead: Some(settings.lookahead),
        keep_model_loaded: Some(settings.keep_model_loaded),
    };
    if let Ok(raw) = serde_json::to_string(&stored) {
        core.db.set_setting(KEY_SETTINGS, &raw);
    }
    apply_settings(&settings);
    settings
}

/// Called once when the core is built: where the model lives, the settings in
/// effect, and the speed measured on an earlier run.
pub(crate) fn init(core: &SideBCore) {
    automix::model::configure(&core.data_dir.join("automix").join("model"));
    apply_settings(&load_settings(core));
    if let Some(factor) = core.db.get_setting(KEY_REALTIME).and_then(|v| v.parse::<f64>().ok()) {
        automix::model::seed_realtime_factor(factor);
    }
}

/// Remembers what the next preparation will want to know: where the caches
/// are, and how fast the model has turned out to be.
fn remember(core: &SideBCore, cache_dir: &str) {
    if core.db.get_setting(KEY_CACHE_DIR).as_deref() != Some(cache_dir) {
        core.db.set_setting(KEY_CACHE_DIR, cache_dir);
    }
}

fn remember_speed(core: &SideBCore) {
    if let Some(factor) = automix::model::realtime_factor() {
        core.db.set_setting(KEY_REALTIME, &format!("{factor:.3}"));
    }
    if let Some(info) = automix::model::info() {
        core.db.set_setting(KEY_PROVIDER, &format!("{} ({})", info.provider, info.detail));
    }
}

pub(crate) fn set_cache_dir(core: &SideBCore, cache_dir: &str) {
    remember(core, cache_dir);
}

fn cache_dir(core: &SideBCore) -> Option<PathBuf> {
    core.db.get_setting(KEY_CACHE_DIR).filter(|d| !d.is_empty()).map(PathBuf::from)
}

pub(crate) fn capability(core: &SideBCore) -> AutomixCapability {
    let model_ready = automix::model::ready();
    let realtime_factor = automix::model::realtime_factor();
    let provider = automix::model::info()
        .map(|i| format!("{} ({})", i.provider, i.detail))
        .or_else(|| core.db.get_setting(KEY_PROVIDER))
        .unwrap_or_default();
    AutomixCapability {
        model_ready,
        model_downloading: automix::model::downloading(),
        realtime_factor,
        stems_recommended: model_ready && realtime_factor.is_some_and(|f| f >= STEMS_RECOMMENDED_FACTOR),
        provider,
    }
}

fn dir_bytes(dir: &Path) -> u64 {
    std::fs::read_dir(dir)
        .map(|entries| entries.flatten().filter_map(|e| e.metadata().ok()).filter(|m| m.is_file()).map(|m| m.len()).sum())
        .unwrap_or(0)
}

pub(crate) fn cache_usage(core: &SideBCore) -> AutomixCacheUsage {
    let root = cache_dir(core);
    let size = |name: &str| root.as_ref().map_or(0, |r| dir_bytes(&r.join(name)));
    AutomixCacheUsage {
        audio_bytes: size("audio"),
        stems_bytes: size("stems"),
        transitions_bytes: size("transitions"),
        model_bytes: automix::model::model_bytes(),
    }
}

/// Deletes the audio, stems and transitions caches (not the model), and stops
/// the prefetch that would be filling them.
pub(crate) fn clear_cache(core: &SideBCore) {
    core.automix.cancel_prefetch();
    if let Some(root) = cache_dir(core) {
        for name in ["audio", "stems", "transitions"] {
            let _ = std::fs::remove_dir_all(root.join(name));
        }
    }
}

pub(crate) fn delete_model(core: &SideBCore) -> Result<(), SideBError> {
    core.automix.cancel_prefetch();
    automix::model::delete().map_err(|e| SideBError::Other { message: format!("no se pudo borrar el modelo: {e}") })
}

// ------------------------------------------------------------------- prepare

pub(crate) async fn prepare(core: &SideBCore, request: Request) -> Result<AutomixTransitionRecord, SideBError> {
    let from = safe_id(&request.from_video_id)?.to_owned();
    let to = safe_id(&request.to_video_id)?.to_owned();
    let stems = match request.quality.as_str() {
        "fast" => false,
        "stems" => true,
        other => return Err(stream_error(format!("{ERR_BAD_QUALITY}: «{other}» no es fast ni stems"))),
    };
    if stems && !automix::model::ready() {
        automix::model::start_download();
        return Err(stream_error(format!("{ERR_MODEL_UNAVAILABLE}: el modelo de stems no está en disco")));
    }
    remember(core, &request.cache_dir);
    let (token, cancel) = core.automix.begin(&request.request_id);
    // Background separations make way while this runs.
    let _busy = automix::model::busy();
    let _preparing = Counted::new(core.automix.preparing.clone());
    let outcome = run(core, &request, &from, &to, stems, token, &cancel).await;
    core.automix.finish(token);
    outcome
}

/// Counts something in progress for as long as it lives.
struct Counted(Arc<std::sync::atomic::AtomicUsize>);

impl Counted {
    fn new(counter: Arc<std::sync::atomic::AtomicUsize>) -> Self {
        counter.fetch_add(1, Ordering::SeqCst);
        Counted(counter)
    }
}

impl Drop for Counted {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::SeqCst);
    }
}

async fn run(
    core: &SideBCore,
    request: &Request,
    from: &str,
    to: &str,
    stems: bool,
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
    // One file per pair and quality: the fast one stays on disk (and in use)
    // while the stems one is being made.
    let wav_path = transitions_dir.join(format!("{from}__{to}.{}.wav", if stems { "stems" } else { "fast" }));
    let options = automix::Options {
        a_gain: linear(request.from_gain_db),
        b_gain: linear(request.to_gain_db),
        baseline: false,
        stem_mode: if stems { automix::StemMode::Model } else { automix::StemMode::Frequency },
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
    if transition.stems_model {
        remember_speed(core);
    }

    tracing::info!(
        from,
        to,
        kind = transition.kind.as_str(),
        quality = if stems { "stems" } else { "fast" },
        stems_model = transition.stems_model,
        separated_s = transition.separated_seconds,
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
        quality: if stems { "stems" } else { "fast" }.to_owned(),
        same_cut_as_fast: transition.same_cut_as_fast,
        separated_seconds: transition.separated_seconds,
        elapsed_seconds: started.elapsed().as_secs_f64(),
        detail: transition.detail,
    })
}

// ------------------------------------------------------------------ prefetch

/// Downloads the queue's songs in order and separates, at low priority, the
/// stretch of each a transition could read, so that the transition itself is
/// only a render. A new call replaces the previous list. Stops at the first
/// song it cannot get; songs fetched before that stay cached.
pub(crate) async fn prefetch(core: Arc<SideBCore>, items: Vec<AutomixQueueItem>) -> Result<(), SideBError> {
    for item in &items {
        safe_id(&item.video_id)?;
    }
    let root = cache_dir(&core).ok_or_else(|| stream_error(format!("{ERR_NO_CACHE_DIR}: falta la carpeta de caché de automix")))?;
    let settings = load_settings(&core);
    let (token, cancel) = core.automix.begin_prefetch();
    let wanted = settings.lookahead as usize + 1;
    let items: Vec<_> = items.into_iter().take(wanted).collect();
    if items.is_empty() {
        return Ok(());
    }
    // The model is only worth having if stems may be asked for.
    let stems = settings.quality != "fast";
    if stems && !automix::model::ready() {
        automix::model::start_download();
    }
    tokio::spawn(async move {
        let _ = prefetch_run(&core, &items, &root, stems, token, &cancel).await;
    });
    Ok(())
}

async fn prefetch_run(
    core: &Arc<SideBCore>,
    items: &[AutomixQueueItem],
    root: &Path,
    stems: bool,
    token: u64,
    cancel: &Arc<AtomicBool>,
) -> Result<(), SideBError> {
    let audio_dir = root.join("audio");
    let stems_dir = root.join("stems");
    for (index, item) in items.iter().enumerate() {
        // Never compete with a preparation: wait until none is running.
        while core.automix.preparing.load(Ordering::SeqCst) > 0 {
            if cancel.load(Ordering::SeqCst) || !core.automix.prefetch_is_current(token) {
                return Err(cancelled());
            }
            tokio::time::sleep(Duration::from_millis(300)).await;
        }
        if cancel.load(Ordering::SeqCst) {
            return Err(cancelled());
        }
        let path = fetch_audio(core, &item.video_id, item.is_upload, &audio_dir, cancel).await?;
        prune_files(&audio_dir, KEEP_AUDIO_FILES, &[&path]);
        // Stems are worth separating once the model is there, and only for
        // the ends a transition can read: the first song is playing (its
        // tail is the one wanted), the last has nothing after it (its head).
        if !stems || !automix::model::ready() {
            continue;
        }
        let (tail, head) = (index + 1 < items.len(), index > 0);
        let key = item.video_id.clone();
        let (job_cancel, dir) = (cancel.clone(), stems_dir.clone());
        let done = tokio::task::spawn_blocking(move || -> Result<(), SideBError> {
            let track = decode(&path, &key)?;
            automix::prefetch::prefetch(&track, &dir, tail, head, Some(&job_cancel))
                .map(|_| ())
                .map_err(|e| stream_error(format!("separación anticipada: {e}")))
        })
        .await
        .map_err(|e| SideBError::Other { message: format!("la separación anticipada se interrumpió: {e}") })?;
        if done.is_ok() {
            automix::stems::prune_cache(&stems_dir, STEMS_CACHE_BYTES);
            remember_speed(core);
        }
    }
    Ok(())
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
                "fast".into(),
                dir.join("automix").to_string_lossy().into_owned(),
            )
            .await
            .expect("prepare_automix");
        println!("{record:#?}");
        assert_eq!(record.kind, "cut", "{}", record.detail);
        assert!(std::fs::metadata(&record.file_path).unwrap().len() > 1_000_000);
        // A second call hits the audio cache and replaces the file.
        assert!(core.prepare_automix("live2".into(), "OsfAnsMY21M".into(), false, None, "2nR1zrNzgcY".into(), false, None, "fast".into(), dir.join("automix").to_string_lossy().into_owned()).await.is_ok());
        // A cancelled request reports it.
        core.cancel_automix("never-started".into());
        std::fs::remove_dir_all(dir).ok();
    }

    fn core_in(name: &str) -> (Arc<SideBCore>, PathBuf) {
        let dir = std::env::temp_dir().join(format!("automix-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        (SideBCore::new(dir.join("data").to_string_lossy().into_owned()).unwrap(), dir)
    }

    #[test]
    fn settings_default_clamp_and_persist() {
        let (core, dir) = core_in("settings");
        let defaults = core.get_automix_settings();
        assert_eq!(defaults, AutomixSettings::default());
        assert!(defaults.fast_on_battery && defaults.skip_same_album && !defaults.keep_model_loaded);
        assert_eq!((defaults.quality.as_str(), defaults.compute.as_str(), defaults.lookahead), ("auto", "auto", 1));

        // Nonsense is corrected, not stored.
        let stored = core.set_automix_settings(AutomixSettings {
            quality: "ultra".into(),
            fast_on_battery: false,
            skip_same_album: false,
            compute: "tpu".into(),
            lookahead: 9,
            keep_model_loaded: true,
        });
        assert_eq!((stored.quality.as_str(), stored.compute.as_str(), stored.lookahead), ("auto", "auto", 3));
        assert_eq!(core.set_automix_settings(AutomixSettings { lookahead: 0, ..stored.clone() }).lookahead, 1);

        // It survives a new core on the same database.
        core.set_automix_settings(AutomixSettings { quality: "stems".into(), compute: "cpu".into(), ..stored });
        drop(core);
        let again = SideBCore::new(dir.join("data").to_string_lossy().into_owned()).unwrap();
        let read = again.get_automix_settings();
        assert_eq!((read.quality.as_str(), read.compute.as_str(), read.keep_model_loaded, read.fast_on_battery), ("stems", "cpu", true, false));
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn older_or_partial_settings_still_read() {
        let (core, dir) = core_in("partial");
        core.db.set_setting(KEY_SETTINGS, r#"{"quality":"fast","lookahead":2}"#);
        let read = core.get_automix_settings();
        assert_eq!((read.quality.as_str(), read.lookahead, read.fast_on_battery), ("fast", 2, true));
        core.db.set_setting(KEY_SETTINGS, "not json");
        assert_eq!(core.get_automix_settings(), AutomixSettings::default());
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn cache_usage_and_clearing() {
        let (core, dir) = core_in("cache");
        let cache = dir.join("cache");
        // Unknown cache directory: nothing to count, nothing to clear.
        assert_eq!(core.automix_cache_usage().audio_bytes, 0);
        core.set_automix_cache_dir(cache.to_string_lossy().into_owned());
        for (name, bytes) in [("audio", 3000usize), ("stems", 5000), ("transitions", 700)] {
            std::fs::create_dir_all(cache.join(name)).unwrap();
            std::fs::write(cache.join(name).join("x"), vec![0u8; bytes]).unwrap();
            std::fs::write(cache.join(name).join("y"), vec![0u8; bytes]).unwrap();
        }
        let usage = core.automix_cache_usage();
        assert_eq!((usage.audio_bytes, usage.stems_bytes, usage.transitions_bytes), (6000, 10_000, 1400));
        core.clear_automix_cache();
        let usage = core.automix_cache_usage();
        assert_eq!((usage.audio_bytes, usage.stems_bytes, usage.transitions_bytes), (0, 0, 0));
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn capability_recommends_stems_only_when_fast_enough() {
        let (core, dir) = core_in("capability");
        let c = core.automix_capability();
        assert_eq!(c.model_ready, core.automix_model_ready());
        assert!(!c.stems_recommended || c.realtime_factor.is_some_and(|f| f >= STEMS_RECOMMENDED_FACTOR));
        // The rule itself.
        let rule = |ready: bool, factor: Option<f64>| ready && factor.is_some_and(|f| f >= STEMS_RECOMMENDED_FACTOR);
        assert!(!rule(true, None) && !rule(true, Some(1.1)) && rule(true, Some(5.0)) && !rule(false, Some(5.0)));
        std::fs::remove_dir_all(dir).ok();
    }

    #[tokio::test]
    async fn bad_requests_fail_before_any_network() {
        let (core, dir) = core_in("badreq");
        let cache = dir.join("cache").to_string_lossy().into_owned();
        let ask = |quality: &str, from: &str| {
            core.prepare_automix("r".into(), from.into(), false, None, "2nR1zrNzgcY".into(), false, None, quality.into(), cache.clone())
        };
        let message = |r: Result<AutomixTransitionRecord, SideBError>| match r {
            Err(SideBError::StreamError { message }) => message,
            other => panic!("{other:?}"),
        };
        assert!(message(ask("best", "OsfAnsMY21M").await).starts_with(ERR_BAD_QUALITY));
        assert!(message(ask("fast", "../../x").await).starts_with(ERR_BAD_ID));
        // Prefetch needs somewhere to put things, and valid ids.
        let item = |id: &str| AutomixQueueItem { video_id: id.into(), is_upload: false };
        assert!(matches!(core.clone().prefetch_automix(vec![item("OsfAnsMY21M")]).await, Err(SideBError::StreamError { message }) if message.starts_with(ERR_NO_CACHE_DIR)));
        core.set_automix_cache_dir(cache);
        assert!(matches!(core.clone().prefetch_automix(vec![item("a/b")]).await, Err(SideBError::StreamError { message }) if message.starts_with(ERR_BAD_ID)));
        assert!(core.clone().prefetch_automix(vec![]).await.is_ok());
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn a_new_prefetch_cancels_the_old_one() {
        let state = AutomixState::default();
        let (first, first_cancel) = state.begin_prefetch();
        assert!(state.prefetch_is_current(first));
        let (second, second_cancel) = state.begin_prefetch();
        assert!(first_cancel.load(Ordering::SeqCst) && !state.prefetch_is_current(first));
        assert!(state.prefetch_is_current(second) && !second_cancel.load(Ordering::SeqCst));
        state.cancel_prefetch();
        assert!(second_cancel.load(Ordering::SeqCst) && !state.prefetch_is_current(second));
    }

    /// Timings of every way of asking (network, model on disk):
    /// `cargo test --release -p sideb-core automix_live_timing -- --ignored --nocapture`
    #[tokio::test(flavor = "multi_thread")]
    #[ignore = "network and model: resolves and downloads songs, runs HT-Demucs"]
    async fn automix_live_timing() {
        let dir = std::env::temp_dir().join(format!("automix-timing-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let cache = dir.join("automix").to_string_lossy().into_owned();
        let core = SideBCore::new(dir.join("data").to_string_lossy().into_owned()).unwrap();
        assert!(core.automix_model_ready(), "the model has to be on disk for this test");
        core.set_automix_cache_dir(cache.clone());
        let ask = |id: &str, from: &str, to: &str, quality: &str| {
            let core = core.clone();
            let (id, from, to, quality, cache) = (id.to_owned(), from.to_owned(), to.to_owned(), quality.to_owned(), cache.clone());
            async move {
                let t = std::time::Instant::now();
                let r = core.prepare_automix(id.clone(), from, false, None, to, false, None, quality.clone(), cache).await.expect("prepare");
                println!(
                    "{id:<28} {quality:<5} {:<4} stems_model={:<5} separated={:>5.1}s  total={:>6.2}s  a_cut={:.3} bars={}",
                    r.kind, r.stems_model, r.separated_seconds, t.elapsed().as_secs_f64(), r.a_cut_seconds, r.bars
                );
                r
            }
        };
        let (fein, highest, queen, levitating) = ("2nR1zrNzgcY", "Gs5WlUzk_Ec", "b72gdhV_rXM", "OsfAnsMY21M");

        let cold = ask("fast, downloads cold", fein, highest, "fast").await;
        let cached = ask("fast, audio cached", fein, highest, "fast").await;
        let stems = ask("stems, cold process", fein, highest, "stems").await;
        assert_eq!(cold.a_cut_seconds, stems.a_cut_seconds, "the upgrade moved the cut");
        assert_eq!(cached.a_cut_seconds, stems.a_cut_seconds);
        println!("capability after one stems run: {:?}", core.automix_capability());
        ask("stems, warm model", highest, fein, "stems").await;

        // Prefetch Queen -> Levitating, wait for it, then ask.
        let t = std::time::Instant::now();
        core.clone()
            .prefetch_automix(vec![
                AutomixQueueItem { video_id: queen.into(), is_upload: false },
                AutomixQueueItem { video_id: levitating.into(), is_upload: false },
            ])
            .await
            .unwrap();
        let wanted = ["b72gdhV_rXM-tail_other.wav", "OsfAnsMY21M-head_other.wav"];
        let stems_dir = dir.join("automix").join("stems");
        while !wanted.iter().all(|f| stems_dir.join(f).exists() && stems_dir.join(f.replace("_other.wav", ".meta")).exists()) {
            tokio::time::sleep(Duration::from_millis(500)).await;
            assert!(t.elapsed() < Duration::from_secs(600), "the prefetch never finished");
        }
        println!("prefetch (download + 2 stretches of stems) finished in {:.1}s", t.elapsed().as_secs_f64());
        ask("stems, prefetched pair", queen, levitating, "stems").await;
        println!("usage: {:?}", core.automix_cache_usage());
        std::fs::remove_dir_all(dir).ok();
    }
}
