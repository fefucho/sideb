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
/// Transition files kept in `<cache_dir>/transitions` (and any younger than `TRANSITION_GRACE`).
const KEEP_TRANSITIONS: usize = 6;
/// A transition file younger than this is never deleted, however many newer
/// ones there are: the player may still be playing it (or about to), and a
/// song is at most 12 minutes long.
const TRANSITION_GRACE: Duration = Duration::from_secs(20 * 60);
/// Size at which the event log is cut down to its newest half.
const LOG_BYTES: u64 = 256 << 10;
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
    /// Wall-clock seconds this call took, downloads included (0 when
    /// `reused`).
    pub elapsed_seconds: f64,
    /// True when this is the result of an earlier (or a concurrent) request
    /// for the same pair, quality and gains rather than new work: see
    /// [`SideBCore::prepare_automix`].
    pub reused: bool,
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
    /// Whether the shell should stick to "fast" (and pass `allow_stems:
    /// false` to `prefetch_automix`) when on battery. Off by default. The
    /// core only stores the rule; platform state is the shell's.
    pub fast_on_battery: bool,
    /// Whether the shell should not transition between two songs of the same
    /// album.
    pub skip_same_album: bool,
    /// "auto", "gpu" or "cpu": where the model may run.
    pub compute: String,
    /// How many upcoming songs are prefetched, 1 to 3.
    pub lookahead: u8,
    /// Keep the model in memory between transitions; otherwise it is
    /// released after 15 seconds without use (it holds 2-3 GB while loaded).
    pub keep_model_loaded: bool,
}

impl Default for AutomixSettings {
    fn default() -> Self {
        AutomixSettings {
            quality: "auto".into(),
            fast_on_battery: false,
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

/// Identity of a preparation: two requests with the same key are the same
/// work. Gains are part of it because they are baked into the file.
#[derive(Clone, PartialEq, Eq, Hash, Debug)]
pub(crate) struct Key {
    from: String,
    to: String,
    quality: String,
    gains: (Option<u64>, Option<u64>),
}

impl Key {
    fn new(request: &Request, from: &str, to: &str) -> Self {
        Key {
            from: from.to_owned(),
            to: to.to_owned(),
            quality: request.quality.clone(),
            gains: (request.from_gain_db.map(f64::to_bits), request.to_gain_db.map(f64::to_bits)),
        }
    }

    fn same_pair(&self, other: &Key) -> bool {
        self.from == other.from && self.to == other.to
    }
}

/// How a shared job ended, in a form every waiter can have its own copy of.
#[derive(Clone)]
struct Outcome(Result<AutomixTransitionRecord, (u8, String)>);

fn outcome_of(result: &Result<AutomixTransitionRecord, SideBError>) -> Outcome {
    Outcome(match result {
        Ok(record) => Ok(record.clone()),
        Err(SideBError::NetworkError { message }) => Err((0, message.clone())),
        Err(SideBError::StreamError { message }) => Err((1, message.clone())),
        Err(other) => Err((2, other.to_string())),
    })
}

impl Outcome {
    fn into_result(self, request_id: &str) -> Result<AutomixTransitionRecord, SideBError> {
        match self.0 {
            Ok(mut record) => {
                record.request_id = request_id.to_owned();
                Ok(record)
            }
            Err((0, message)) => Err(SideBError::NetworkError { message }),
            Err((1, message)) => Err(SideBError::StreamError { message }),
            Err((_, message)) => Err(SideBError::Other { message }),
        }
    }
}

/// A preparation running (or about to), and everyone waiting for it.
struct Flight {
    token: u64,
    cancel: Arc<AtomicBool>,
    /// The request ids that want its result. Cancelling one removes it; the
    /// job stops only when none is left.
    waiters: Vec<String>,
    result: tokio::sync::watch::Sender<Option<Outcome>>,
    changed: Arc<tokio::sync::Notify>,
}

/// Preparations in progress, results kept, and the other bookkeeping of the
/// automix jobs.
///
/// The rule for shells: **asking again for the same pair, quality and gains
/// never restarts anything.** If that job is running you wait for it (a second
/// request is a second waiter); if its file is already rendered and still on
/// disk you get that record at once (`reused`); cancelling one of several
/// waiters leaves the job running for the others. A request for a *different*
/// pair supersedes (cancels) the jobs of every other pair; a request for the
/// same pair at another quality runs alongside.
#[derive(Default)]
pub(crate) struct AutomixState {
    counter: AtomicU64,
    flights: Mutex<std::collections::HashMap<Key, Flight>>,
    /// The newest results, for `reused` (most recent last).
    rendered: Mutex<Vec<(Key, AutomixTransitionRecord)>>,
    /// Held by the blocking part of a preparation: at most one at a time. A
    /// superseded job gives it up at its next checkpoint.
    engine: Arc<Mutex<()>>,
    /// Request ids that stopped waiting, until their waiter notices.
    cancelled_ids: Mutex<Vec<String>>,
    /// The prefetch in progress, if any: its token and cancel flag.
    prefetch: Mutex<Option<(u64, Arc<AtomicBool>)>>,
    /// Preparations in progress (the prefetch waits for them to end).
    preparing: Arc<std::sync::atomic::AtomicUsize>,
}

/// How many rendered results are remembered.
const KEEP_RENDERED: usize = 12;

enum Entry {
    /// Nobody was working on it: this caller starts the job.
    Start { token: u64, cancel: Arc<AtomicBool>, result: tokio::sync::watch::Sender<Option<Outcome>> },
    /// A job for it is running: wait for it.
    Join,
}

impl AutomixState {
    /// A rendered result for `key` whose file is still on disk.
    fn rendered_for(&self, key: &Key) -> Option<AutomixTransitionRecord> {
        let rendered = self.rendered.lock().unwrap_or_else(|e| e.into_inner());
        let (_, record) = rendered.iter().rev().find(|(k, _)| k == key)?;
        std::fs::metadata(&record.file_path).is_ok_and(|m| m.len() > 0).then(|| record.clone())
    }

    fn remember_rendered(&self, key: &Key, record: &AutomixTransitionRecord) {
        let mut rendered = self.rendered.lock().unwrap_or_else(|e| e.into_inner());
        rendered.retain(|(k, _)| k != key);
        rendered.push((key.clone(), record.clone()));
        let excess = rendered.len().saturating_sub(KEEP_RENDERED);
        rendered.drain(..excess);
    }

    /// Joins the job for `key` or starts one, superseding the jobs of other
    /// pairs. Returns what the caller must do and the channel to wait on.
    fn enter(&self, key: &Key, request_id: &str) -> (Entry, tokio::sync::watch::Receiver<Option<Outcome>>, Arc<tokio::sync::Notify>) {
        let mut flights = self.flights.lock().unwrap_or_else(|e| e.into_inner());
        // Jobs of other pairs are superseded: stop them, and tell their waiters.
        for (_, flight) in flights.iter_mut().filter(|(other, _)| !other.same_pair(key)) {
            flight.cancel.store(true, Ordering::SeqCst);
            self.cancelled_ids.lock().unwrap_or_else(|e| e.into_inner()).append(&mut flight.waiters);
            flight.changed.notify_waiters();
        }
        flights.retain(|other, _| other.same_pair(key));
        if let Some(flight) = flights.get_mut(key) {
            flight.waiters.push(request_id.to_owned());
            return (Entry::Join, flight.result.subscribe(), flight.changed.clone());
        }
        let token = self.counter.fetch_add(1, Ordering::SeqCst) + 1;
        let cancel = Arc::new(AtomicBool::new(false));
        let (result, receiver) = tokio::sync::watch::channel(None);
        let changed = Arc::new(tokio::sync::Notify::new());
        flights.insert(
            key.clone(),
            Flight { token, cancel: cancel.clone(), waiters: vec![request_id.to_owned()], result: result.clone(), changed: changed.clone() },
        );
        (Entry::Start { token, cancel, result }, receiver, changed)
    }

    /// Whether `request_id` was cancelled (or superseded) while waiting; asking
    /// forgets it.
    fn was_cancelled(&self, request_id: &str) -> bool {
        let mut ids = self.cancelled_ids.lock().unwrap_or_else(|e| e.into_inner());
        match ids.iter().position(|id| id == request_id) {
            Some(at) => {
                ids.remove(at);
                true
            }
            None => false,
        }
    }

    /// Whether `request_id` is among the waiters of a job (tests).
    #[cfg(test)]
    fn waiting(&self, key: &Key, request_id: &str) -> bool {
        self.flights.lock().unwrap_or_else(|e| e.into_inner()).get(key).is_some_and(|f| f.waiters.iter().any(|w| w == request_id))
    }

    /// Ends the job `token` for `key`.
    fn finish(&self, key: &Key, token: u64) {
        let mut flights = self.flights.lock().unwrap_or_else(|e| e.into_inner());
        if flights.get(key).is_some_and(|f| f.token == token) {
            flights.remove(key);
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

    /// Stops waiting for `request_id`; the job it was waiting for stops only
    /// if nobody else is.
    pub(crate) fn cancel(&self, request_id: &str) {
        let mut flights = self.flights.lock().unwrap_or_else(|e| e.into_inner());
        let mut empty = Vec::new();
        for (key, flight) in flights.iter_mut() {
            let before = flight.waiters.len();
            flight.waiters.retain(|w| w != request_id);
            if flight.waiters.len() != before {
                self.cancelled_ids.lock().unwrap_or_else(|e| e.into_inner()).push(request_id.to_owned());
                flight.changed.notify_waiters();
                if flight.waiters.is_empty() {
                    flight.cancel.store(true, Ordering::SeqCst);
                    empty.push(key.clone());
                }
            }
        }
        for key in empty {
            flights.remove(&key);
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

/// Appends one line to `<cache>/automix.log`: what was asked, what came out,
/// how long it took, why it failed. Ids and numbers only, never URLs or
/// headers. The shells' own diagnostics live in memory; this survives.
fn log_event(root: &Path, line: &str) {
    use std::io::Write;
    let path = root.join("automix.log");
    if std::fs::metadata(&path).is_ok_and(|m| m.len() > LOG_BYTES) {
        if let Ok(text) = std::fs::read_to_string(&path) {
            // Error messages are Spanish: cut on a character boundary.
            let mut half = text.len() / 2;
            while !text.is_char_boundary(half) {
                half += 1;
            }
            let tail = &text[half..];
            let tail = tail.split_once('\n').map_or("", |(_, rest)| rest);
            let _ = std::fs::write(&path, tail);
        }
    }
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs());
    let _ = std::fs::create_dir_all(root);
    if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{secs} {line}");
    }
}

/// Like [`prune_files`] for transition files: nothing younger than `grace` is
/// deleted, whatever the count.
fn prune_transitions(dir: &Path, keep: usize, grace: Duration, protect: &[&Path]) {
    let now = std::time::SystemTime::now();
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    let mut files: Vec<(std::time::SystemTime, PathBuf)> = entries
        .flatten()
        .filter_map(|e| {
            let meta = e.metadata().ok()?;
            meta.is_file().then(|| (meta.modified().unwrap_or(std::time::UNIX_EPOCH), e.path()))
        })
        .collect();
    files.sort_by(|a, b| b.0.cmp(&a.0));
    for (modified, path) in files.into_iter().skip(keep) {
        let young = now.duration_since(modified).is_ok_and(|age| age < grace);
        if !young && !protect.contains(&path.as_path()) {
            let _ = std::fs::remove_file(path);
        }
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

#[derive(Clone)]
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
    automix::model::set_idle_release(if settings.keep_model_loaded { None } else { Some(automix::model::DEFAULT_IDLE) });
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

/// Stems for the end of `from` and the start of `to` are in the cache and the
/// model is on disk: a "stems" preparation of the pair separates nothing. Looks
/// only at files, never at audio.
pub(crate) fn pair_ready(core: &SideBCore, from: &str, to: &str) -> bool {
    let Some(root) = cache_dir(core) else { return false };
    automix::model::ready() && stems_cached(&root.join("stems"), from, to)
}

/// The files half of [`pair_ready`].
fn stems_cached(stems_dir: &Path, from: &str, to: &str) -> bool {
    let (Ok(from), Ok(to)) = (safe_id(from), safe_id(to)) else { return false };
    automix::stems::has_entry(stems_dir, &format!("{from}-tail"), automix::prefetch::TAIL_SECONDS)
        && automix::stems::has_entry(stems_dir, &format!("{to}-head"), automix::prefetch::HEAD_SECONDS)
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

pub(crate) async fn prepare(core: Arc<SideBCore>, request: Request) -> Result<AutomixTransitionRecord, SideBError> {
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
    remember(&core, &request.cache_dir);
    let root = PathBuf::from(&request.cache_dir);
    let key = Key::new(&request, &from, &to);

    // The same work again: already rendered (and the file is still there)...
    if let Some(mut record) = core.automix.rendered_for(&key) {
        log_event(&root, &format!("prepare {} {from} -> {to} quality={} reused the rendered file", request.request_id, request.quality));
        record.request_id = request.request_id.clone();
        record.reused = true;
        record.elapsed_seconds = 0.0;
        return Ok(record);
    }
    // ...or being done right now: wait for it. Otherwise, do it.
    let (entry, mut result, changed) = core.automix.enter(&key, &request.request_id);
    match entry {
        Entry::Join => log_event(&root, &format!("prepare {} {from} -> {to} quality={} joined the job in progress", request.request_id, request.quality)),
        Entry::Start { token, cancel, result } => {
            log_event(&root, &format!("prepare #{token} {} {from} -> {to} quality={}", request.request_id, request.quality));
            let (core, request, key) = (core.clone(), request.clone(), key.clone());
            // The job outlives any one caller: it belongs to everyone waiting.
            tokio::spawn(async move {
                // Background separations make way while this runs.
                let _busy = automix::model::busy();
                let _preparing = Counted::new(core.automix.preparing.clone());
                let root = PathBuf::from(&request.cache_dir);
                let outcome = run(&core, &request, &from, &to, stems, &cancel).await;
                match &outcome {
                    Ok(r) => {
                        log_event(
                            &root,
                            &format!(
                                "prepare #{token} ok kind={} quality={} stems_model={} same_cut={} separated={:.1}s elapsed={:.1}s a_cut={:.2} file={:.1}s",
                                r.kind, r.quality, r.stems_model, r.same_cut_as_fast, r.separated_seconds, r.elapsed_seconds, r.a_cut_seconds, r.file_duration_seconds
                            ),
                        );
                        if !cancel.load(Ordering::SeqCst) {
                            core.automix.remember_rendered(&key, r);
                        }
                    }
                    Err(e) => log_event(&root, &format!("prepare #{token} failed: {e}")),
                }
                // The result first, then the job's removal: a waiter that sees
                // the job gone must find the result.
                let _ = result.send(Some(outcome_of(&outcome)));
                core.automix.finish(&key, token);
            });
        }
    }
    loop {
        if core.automix.was_cancelled(&request.request_id) {
            return Err(cancelled());
        }
        if let Some(outcome) = result.borrow().clone() {
            return outcome.into_result(&request.request_id);
        }
        tokio::select! {
            _ = result.changed() => {}
            _ = changed.notified() => {}
            _ = tokio::time::sleep(Duration::from_millis(250)) => {}
        }
    }
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
    let rendered = tokio::task::spawn_blocking(move || -> Result<(automix::Transition, f64, f64), SideBError> {
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
        // The rendered file can be 100 MB of samples: let go of them now.
        let file_seconds = transition.file_seconds();
        let mut transition = transition;
        transition.audio = Default::default();
        transition.baseline = Default::default();
        Ok((transition, decoded, file_seconds))
    })
    .await
    .map_err(|e| SideBError::Other { message: format!("la preparación de automix se interrumpió: {e}") })??;
    let (transition, decoded, file_seconds) = rendered;

    // Everyone stopped waiting, or a request for another pair superseded
    // this one, while it was working.
    if cancel.load(Ordering::SeqCst) {
        let _ = std::fs::remove_file(&wav_path);
        return Err(cancelled());
    }
    prune_transitions(&transitions_dir, KEEP_TRANSITIONS, TRANSITION_GRACE, &[&wav_path]);
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
        file_duration_seconds: file_seconds,
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
        reused: false,
        detail: transition.detail,
    })
}

// ------------------------------------------------------------------ prefetch

/// Downloads the queue's songs in order and, if `allow_stems`, separates, at
/// low priority, the stretch of each a transition could read, so that the transition itself is
/// only a render. A new call replaces the previous list. Stops at the first
/// song it cannot get; songs fetched before that stay cached.
pub(crate) async fn prefetch(core: Arc<SideBCore>, items: Vec<AutomixQueueItem>, allow_stems: bool) -> Result<(), SideBError> {
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
    // The model is only worth having (and its memory, and its battery) if
    // the shell allows stems now and the user's quality does not forbid them.
    let stems = allow_stems && settings.quality != "fast";
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
        log_event(root, &format!("prefetch #{token} {} ({} of {})", item.video_id, index + 1, items.len()));
        let path = match fetch_audio(core, &item.video_id, item.is_upload, &audio_dir, cancel).await {
            Ok(path) => path,
            Err(e) => {
                log_event(root, &format!("prefetch #{token} {} failed: {e}", item.video_id));
                return Err(e);
            }
        };
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
        match &done {
            Ok(()) => {
                automix::stems::prune_cache(&stems_dir, STEMS_CACHE_BYTES);
                remember_speed(core);
                log_event(root, &format!("prefetch #{token} {} stems ready (tail={tail} head={head})", item.video_id));
            }
            Err(e) => log_event(root, &format!("prefetch #{token} {} stems failed: {e}", item.video_id)),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(from: &str, to: &str, quality: &str) -> Key {
        Key { from: from.into(), to: to.into(), quality: quality.into(), gains: (None, None) }
    }

    fn record(path: &Path) -> AutomixTransitionRecord {
        AutomixTransitionRecord {
            request_id: "x".into(),
            from_video_id: "a".into(),
            to_video_id: "b".into(),
            kind: "mix".into(),
            file_path: path.to_string_lossy().into_owned(),
            file_duration_seconds: 10.0,
            a_cut_seconds: 1.0,
            overlap_start_seconds: 8.0,
            overlap_end_seconds: 20.0,
            b_offset_seconds: 5.0,
            b_entry_seconds: 0.0,
            handover_seconds: 14.0,
            bpm_from: 120.0,
            bpm_to: 120.0,
            bars: 8,
            stems_model: false,
            quality: "fast".into(),
            same_cut_as_fast: true,
            separated_seconds: 0.0,
            elapsed_seconds: 3.0,
            reused: false,
            detail: String::new(),
        }
    }

    #[test]
    fn the_same_request_joins_the_job_instead_of_restarting_it() {
        let state = AutomixState::default();
        let k = key("a", "b", "fast");
        let (first, _rx, _) = state.enter(&k, "one");
        let Entry::Start { cancel, .. } = first else { panic!("the first request starts the job") };
        // Asking again, twice, with other request ids: nothing restarts.
        assert!(matches!(state.enter(&k, "two").0, Entry::Join));
        assert!(matches!(state.enter(&k, "three").0, Entry::Join));
        assert!(!cancel.load(Ordering::SeqCst));
        assert!(state.waiting(&k, "one") && state.waiting(&k, "two") && state.waiting(&k, "three"));

        // One waiter cancelling leaves the job running for the others...
        state.cancel("two");
        assert!(state.was_cancelled("two") && !state.was_cancelled("two"), "told once");
        assert!(!cancel.load(Ordering::SeqCst));
        state.cancel("one");
        assert!(!cancel.load(Ordering::SeqCst));
        // ...and the last one stops it.
        state.cancel("three");
        assert!(cancel.load(Ordering::SeqCst));
        // A request after that starts afresh.
        assert!(matches!(state.enter(&k, "four").0, Entry::Start { .. }));
    }

    #[test]
    fn another_pair_supersedes_but_the_same_pair_at_another_quality_does_not() {
        let state = AutomixState::default();
        let fast = key("a", "b", "fast");
        let Entry::Start { cancel: fast_cancel, .. } = state.enter(&fast, "r1").0 else { panic!() };
        // Same pair, stems: runs alongside, the fast job is left alone.
        let stems = key("a", "b", "stems");
        let Entry::Start { cancel: stems_cancel, .. } = state.enter(&stems, "r2").0 else { panic!() };
        assert!(!fast_cancel.load(Ordering::SeqCst) && !stems_cancel.load(Ordering::SeqCst));
        // Another pair: both are superseded and their waiters are told.
        let other = key("b", "c", "fast");
        assert!(matches!(state.enter(&other, "r3").0, Entry::Start { .. }));
        assert!(fast_cancel.load(Ordering::SeqCst) && stems_cancel.load(Ordering::SeqCst));
        assert!(state.was_cancelled("r1") && state.was_cancelled("r2") && !state.was_cancelled("r3"));
    }

    #[test]
    fn a_rendered_file_is_returned_while_it_is_still_on_disk() {
        let dir = std::env::temp_dir().join(format!("automix-rendered-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("a__b.fast.wav");
        std::fs::write(&file, b"riff").unwrap();
        let state = AutomixState::default();
        let k = key("a", "b", "fast");
        assert!(state.rendered_for(&k).is_none());
        state.remember_rendered(&k, &record(&file));
        assert_eq!(state.rendered_for(&k).unwrap().a_cut_seconds, 1.0);
        // Another quality or other gains are other work.
        assert!(state.rendered_for(&key("a", "b", "stems")).is_none());
        let mut louder = k.clone();
        louder.gains = (Some(1.5f64.to_bits()), None);
        assert!(state.rendered_for(&louder).is_none());
        // The file pruned (or deleted): the record is no longer valid.
        std::fs::remove_file(&file).unwrap();
        assert!(state.rendered_for(&k).is_none());
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn only_the_newest_results_are_remembered() {
        let dir = std::env::temp_dir().join(format!("automix-keep-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("f.wav");
        std::fs::write(&file, b"riff").unwrap();
        let state = AutomixState::default();
        for i in 0..(KEEP_RENDERED + 3) {
            state.remember_rendered(&key(&format!("a{i}"), "b", "fast"), &record(&file));
        }
        assert!(state.rendered_for(&key("a0", "b", "fast")).is_none());
        assert!(state.rendered_for(&key(&format!("a{}", KEEP_RENDERED + 2), "b", "fast")).is_some());
        std::fs::remove_dir_all(dir).ok();
    }

    #[tokio::test]
    async fn a_shared_job_gives_every_waiter_its_own_copy_of_the_result() {
        let (core, dir) = core_in("shared");
        let cache = dir.join("cache");
        std::fs::create_dir_all(cache.join("transitions")).unwrap();
        let file = cache.join("transitions").join("a__b.fast.wav");
        std::fs::write(&file, b"riff").unwrap();
        // A rendered result already there: two requests get it at once, each
        // under its own id, flagged as reused, and nothing is started.
        let k = Key { from: "AAAAAAAAAAA".into(), to: "BBBBBBBBBBB".into(), quality: "fast".into(), gains: (None, None) };
        core.automix.remember_rendered(&k, &record(&file));
        let ask = |id: &str| {
            core.clone().prepare_automix(id.into(), "AAAAAAAAAAA".into(), false, None, "BBBBBBBBBBB".into(), false, None, "fast".into(), cache.to_string_lossy().into_owned())
        };
        let (one, two) = (ask("first").await.unwrap(), ask("second").await.unwrap());
        assert!(one.reused && two.reused);
        assert_eq!((one.request_id.as_str(), two.request_id.as_str()), ("first", "second"));
        assert_eq!(one.file_path, two.file_path);
        assert!(core.automix.flights.lock().unwrap().is_empty());
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn a_prefetch_is_cancelled_by_the_next_one() {
        let state = AutomixState::default();
        let (first, first_cancel) = state.begin_prefetch();
        let (second, _) = state.begin_prefetch();
        assert!(first_cancel.load(Ordering::SeqCst) && !state.prefetch_is_current(first) && state.prefetch_is_current(second));
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
            .clone()
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
        assert!(core.clone().prepare_automix("live2".into(), "OsfAnsMY21M".into(), false, None, "2nR1zrNzgcY".into(), false, None, "fast".into(), dir.join("automix").to_string_lossy().into_owned()).await.is_ok());
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
        assert!(!defaults.fast_on_battery && defaults.skip_same_album && !defaults.keep_model_loaded);
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
        assert_eq!((read.quality.as_str(), read.lookahead, read.fast_on_battery), ("fast", 2, false));
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
            core.clone().prepare_automix("r".into(), from.into(), false, None, "2nR1zrNzgcY".into(), false, None, quality.into(), cache.clone())
        };
        let message = |r: Result<AutomixTransitionRecord, SideBError>| match r {
            Err(SideBError::StreamError { message }) => message,
            other => panic!("{other:?}"),
        };
        assert!(message(ask("best", "OsfAnsMY21M").await).starts_with(ERR_BAD_QUALITY));
        assert!(message(ask("fast", "../../x").await).starts_with(ERR_BAD_ID));
        // Prefetch needs somewhere to put things, and valid ids.
        let item = |id: &str| AutomixQueueItem { video_id: id.into(), is_upload: false };
        assert!(matches!(core.clone().prefetch_automix(vec![item("OsfAnsMY21M")], true).await, Err(SideBError::StreamError { message }) if message.starts_with(ERR_NO_CACHE_DIR)));
        core.set_automix_cache_dir(cache);
        assert!(matches!(core.clone().prefetch_automix(vec![item("a/b")], true).await, Err(SideBError::StreamError { message }) if message.starts_with(ERR_BAD_ID)));
        assert!(core.clone().prefetch_automix(vec![], true).await.is_ok());
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
        // Two requests for the same work at once: one job, two results.
        let (one, two) = tokio::join!(ask("stems, joined (first)", fein, highest, "stems"), ask("stems, joined (second)", fein, highest, "stems"));
        assert_eq!(one.a_cut_seconds, two.a_cut_seconds);
        let again = ask("stems, asked again", fein, highest, "stems").await;
        assert!(again.reused, "the rendered file is returned, not re-rendered");
        println!("same cut as fast: {} (fast a_cut {:.3}, stems {:.3})", one.same_cut_as_fast, cold.a_cut_seconds, one.a_cut_seconds);
        let _ = cached;
        println!("capability after one stems run: {:?}", core.automix_capability());
        ask("stems, warm model, other pair", highest, fein, "stems").await;

        // Prefetch Queen -> Levitating, wait for it, then ask.
        assert!(!core.automix_pair_ready(queen.into(), levitating.into()));
        let t = std::time::Instant::now();
        core.clone()
            .prefetch_automix(vec![
                AutomixQueueItem { video_id: queen.into(), is_upload: false },
                AutomixQueueItem { video_id: levitating.into(), is_upload: false },
            ], true)
            .await
            .unwrap();
        while !core.automix_pair_ready(queen.into(), levitating.into()) {
            tokio::time::sleep(Duration::from_millis(500)).await;
            assert!(t.elapsed() < Duration::from_secs(600), "the prefetch never finished");
        }
        println!("prefetch (download + 2 stretches of stems) finished in {:.1}s", t.elapsed().as_secs_f64());
        ask("stems, prefetched pair", queen, levitating, "stems").await;
        println!("usage: {:?}", core.automix_cache_usage());
        let log = std::fs::read_to_string(dir.join("automix").join("automix.log")).unwrap_or_default();
        println!("jobs started for fein->highest stems: {}", log.lines().filter(|l| l.contains("prepare #") && l.contains("quality=stems") && l.contains(fein)).count());
        std::fs::remove_dir_all(dir).ok();
    }
}
