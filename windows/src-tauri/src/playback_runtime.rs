//! Account-scoped durable playback and history. No streams, cookies or audio generations are serialized.
use crate::queue::DurableQueue;
use crate::{AppState, AuthStatusDto, PlaybackManager, PlaybackTrackDto};
use serde::{Deserialize, Serialize};
use std::{
    path::PathBuf,
    sync::{atomic::Ordering, mpsc, Mutex, OnceLock},
};
use tauri::{Emitter, Manager};

#[derive(Default)]
pub(crate) struct PlaybackRuntime {
    pub identity: Option<String>,
    pub directory: Option<PathBuf>,
    pub last_audible: f64,
    pub exponential_volume: bool,
    pub track_gain: Option<f64>,
    pub recorded_generation: Option<u64>,
    pub source: Option<ProgressiveSource>,
    pub pending_next: Option<(u64, u64)>,
    pub disliked: std::collections::HashSet<String>,
    last_saved: Mutex<Option<(u64, u64, u64, bool, bool, u64, u64, bool, Option<(usize, bool)>)>>,
}
#[derive(Clone)]
pub(crate) struct ProgressiveSource {
    pub kind: String,
    pub id: Option<String>,
    pub continuation: Option<String>,
    pub loading: bool,
    pub error: bool,
    pub needs_restart: bool,
    pub loaded_prefix: Vec<String>,
    pub consumed_continuations: std::collections::HashSet<String>,
}
#[derive(Clone, Serialize, Deserialize)]
struct SourceResume {
    kind: String,
    id: Option<String>,
    loaded_prefix: Vec<String>,
}
impl ProgressiveSource {
    pub(crate) fn advance_continuation(&mut self, next: Option<String>) -> Result<(), ()> {
        if next.as_ref().is_some_and(|token| {
            self.continuation.as_ref() == Some(token) || self.consumed_continuations.contains(token)
        }) {
            return Err(());
        }
        if let Some(previous) = self.continuation.take() {
            self.consumed_continuations.insert(previous);
        }
        self.continuation = next;
        self.needs_restart = false;
        Ok(())
    }
}
impl SourceResume {
    fn into_progressive(self) -> ProgressiveSource {
        ProgressiveSource {
            kind: self.kind,
            id: self.id,
            continuation: None,
            loading: false,
            error: true,
            needs_restart: true,
            loaded_prefix: self.loaded_prefix,
            consumed_continuations: Default::default(),
        }
    }
}
#[derive(Serialize, Deserialize)]
struct SavedPlayback {
    version: u32,
    queue: DurableQueue,
    current_track: Option<PlaybackTrackDto>,
    shuffle: bool,
    repeat: bool,
    radio_playlist_id: Option<String>,
    radio_cursor_video_id: Option<String>,
    volume: f64,
    last_audible: f64,
    #[serde(default)]
    exponential_volume: bool,
    #[serde(default)]
    source_resume: Option<SourceResume>,
}
fn identity(auth: &AuthStatusDto) -> Option<String> {
    match auth.state.as_str() {
        "guest" => Some("guest".into()),
        "ready" => auth
            .channel_id
            .as_ref()
            .filter(|value| !value.is_empty())
            .or(auth.email.as_ref().filter(|value| !value.is_empty()))
            .or(auth.handle.as_ref().filter(|value| !value.is_empty()))
            .map(|value| format!("account:{value}")),
        _ => None,
    }
}
fn filename(identity: &str) -> String {
    use sha2::{Digest, Sha256};
    format!("queue-{:x}.json", Sha256::digest(identity.as_bytes()))
}
fn atomic_write(path: &std::path::Path, data: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    let pending = path.with_extension("pending");
    let mut file = std::fs::File::create(&pending)?;
    file.write_all(data)?;
    file.sync_all()?;
    drop(file);
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;
        let from = pending
            .as_os_str()
            .encode_wide()
            .chain(Some(0))
            .collect::<Vec<_>>();
        let to = path
            .as_os_str()
            .encode_wide()
            .chain(Some(0))
            .collect::<Vec<_>>();
        let ok = unsafe {
            windows_sys::Win32::Storage::FileSystem::MoveFileExW(
                from.as_ptr(),
                to.as_ptr(),
                windows_sys::Win32::Storage::FileSystem::MOVEFILE_REPLACE_EXISTING
                    | windows_sys::Win32::Storage::FileSystem::MOVEFILE_WRITE_THROUGH,
            )
        };
        if ok == 0 {
            return Err(std::io::Error::last_os_error());
        }
    }
    #[cfg(not(windows))]
    std::fs::rename(pending, path)?;
    Ok(())
}
enum SaveJob {
    Save(PathBuf, SavedPlayback),
    Flush(mpsc::SyncSender<()>),
}
fn writer() -> &'static mpsc::Sender<SaveJob> {
    static WRITER: OnceLock<mpsc::Sender<SaveJob>> = OnceLock::new();
    WRITER.get_or_init(|| {
        let (sender, receiver) = mpsc::channel();
        std::thread::Builder::new()
            .name("sideb-playback-store".into())
            .spawn(move || {
                let mut pending = std::collections::HashMap::<PathBuf, SavedPlayback>::new();
                loop {
                    let flush = match receiver.recv_timeout(std::time::Duration::from_millis(350)) {
                        Ok(SaveJob::Save(path, saved)) => {
                            pending.insert(path, saved);
                            continue;
                        }
                        Ok(SaveJob::Flush(done)) => Some(done),
                        Err(mpsc::RecvTimeoutError::Timeout) => None,
                        Err(mpsc::RecvTimeoutError::Disconnected) => break,
                    };
                    for (path, saved) in pending.drain() {
                        if let Some(directory) = path.parent() {
                            if std::fs::create_dir_all(directory).is_ok() {
                                if let Ok(data) = serde_json::to_vec(&saved) {
                                    let _ = atomic_write(&path, &data);
                                }
                            }
                        }
                    }
                    if let Some(done) = flush {
                        let _ = done.send(());
                    }
                }
            })
            .expect("playback store worker");
        sender
    })
}
pub(crate) fn flush() {
    let (sender, receiver) = mpsc::sync_channel(0);
    if writer().send(SaveJob::Flush(sender)).is_ok() {
        let _ = receiver.recv();
    }
}
impl PlaybackRuntime {
    pub(crate) fn interrupt_source(&mut self) {
        if let Some(source) = self.source.as_mut() {
            if source.continuation.is_some() || source.needs_restart {
                source.continuation = None;
                source.consumed_continuations.clear();
                source.loading = false;
                source.error = true;
                source.needs_restart = true;
            }
        }
        self.pending_next = None;
    }
    pub(crate) fn source_load(&self, loaded_count: usize) -> Option<crate::PlaybackSourceLoadDto> {
        self.source
            .as_ref()
            .map(|source| crate::PlaybackSourceLoadDto {
                loaded_count,
                loading: source.loading,
                error: source.error.then(|| {
                    if source.needs_restart {
                        "La fuente guardada está incompleta. Reintentá para actualizarla.".into()
                    } else {
                        "No se pudieron cargar las siguientes canciones.".into()
                    }
                }),
                can_retry: source.error && (source.continuation.is_some() || source.needs_restart),
                has_more: source.continuation.is_some() || source.needs_restart,
            })
    }
    pub(crate) fn persist(&self, playback: &PlaybackManager) {
        let (Some(identity), Some(directory)) = (&self.identity, &self.directory) else {
            return;
        };
        let dirty = (
            playback.queue_epoch,
            playback.queue.revision,
            playback.generation,
            playback.is_shuffle,
            playback.is_repeat,
            playback.volume.to_bits(),
            self.last_audible.to_bits(),
            self.exponential_volume,
            self.source.as_ref().map(|source| {
                (
                    source.loaded_prefix.len(),
                    source.continuation.is_some() || source.needs_restart,
                )
            }),
        );
        if let Ok(mut last) = self.last_saved.lock() {
            if last.as_ref() == Some(&dirty) {
                return;
            }
            // Clone only on actual state mutations; serialize/fsync on the worker.
            let saved = SavedPlayback {
                version: 1,
                queue: playback.queue.durable(),
                current_track: playback.current_track.clone().map(|mut track| {
                    track.thumbnail = crate::queue::durable_thumbnail(&track.thumbnail);
                    track
                }),
                shuffle: playback.is_shuffle,
                repeat: playback.is_repeat,
                radio_playlist_id: playback.radio_playlist_id.clone(),
                radio_cursor_video_id: playback.radio_cursor_video_id.clone(),
                volume: playback.volume,
                last_audible: self.last_audible,
                exponential_volume: self.exponential_volume,
                source_resume: self
                    .source
                    .as_ref()
                    .filter(|source| source.continuation.is_some() || source.needs_restart)
                    .map(|source| SourceResume {
                        kind: source.kind.clone(),
                        id: source.id.clone(),
                        loaded_prefix: source.loaded_prefix.clone(),
                    }),
            };
            if writer()
                .send(SaveJob::Save(directory.join(filename(identity)), saved))
                .is_ok()
            {
                *last = Some(dirty);
            }
        }
    }
}
/// Invalidate authenticated requests without discarding a resumable source owned
/// by the retained account/guest queue (login may fail or be cancelled).
pub(crate) fn interrupt_auth_owner(playback: &mut PlaybackManager) {
    if playback.is_loading && playback.loaded_generation.is_none() {
        playback.generation = playback.generation.wrapping_add(1);
        playback.is_loading = false;
        playback.is_playing = false;
    }
    playback.runtime.interrupt_source();
    let source = playback.runtime.source.take();
    crate::invalidate_queue_owner(playback);
    playback.runtime.source = source;
    if playback.queue.radio.is_some() {
        playback.queue.end_radio(None, true);
    }
}

/// Invoke after the auth status has been committed, and before resetting playback on logout.
pub(crate) fn sync_account(app: &tauri::AppHandle, auth: &AuthStatusDto) {
    let Some(identity) = identity(auth) else {
        return;
    };
    let state = app.state::<AppState>();
    let Ok(mut pb) = state.playback.lock() else {
        return;
    };
    if pb.runtime.identity.as_ref() == Some(&identity) {
        return;
    }
    pb.runtime.persist(&pb);
    flush();
    if let Ok(Some(player)) = state.player.read().map(|p| p.clone()) {
        let _ = player.stop();
        let _ = player.clear_playlist();
    }
    let directory = app
        .path()
        .app_data_dir()
        .ok()
        .map(|path| path.join("Playback"));
    let saved = directory
        .as_ref()
        .and_then(|dir| std::fs::read(dir.join(filename(&identity))).ok())
        .and_then(|bytes| serde_json::from_slice::<SavedPlayback>(&bytes).ok())
        .filter(|saved| saved.version == 1);
    let generation = pb.generation.wrapping_add(1);
    let epoch = pb.queue_epoch.wrapping_add(1);
    *pb = PlaybackManager::new();
    pb.generation = generation;
    pb.queue_epoch = epoch;
    pb.observed_auth_generation = state.auth_generation.load(Ordering::SeqCst);
    pb.runtime.identity = Some(identity);
    pb.runtime.directory = directory;
    pb.runtime.last_audible = 100.0;
    if let Some(saved) = saved {
        pb.runtime.exponential_volume = saved.exponential_volume;
        if saved.volume.is_finite() && saved.last_audible.is_finite() {
            if let Some(queue) = saved.queue.restore() {
                pb.queue = queue;
                pb.current_track = saved.current_track.filter(|track| {
                    pb.queue
                        .current()
                        .is_some_and(|entry| entry.video_id == track.video_id)
                });
                let entry = pb.queue.current();
                if let (Some(track), Some(entry)) = (pb.current_track.as_mut(), entry) {
                    track.enrich_missing_metadata(&entry);
                }
                if let Some(source) = saved.source_resume {
                    pb.runtime.source = Some(source.into_progressive());
                }
                pb.is_shuffle = saved.shuffle;
                pb.is_repeat = saved.repeat;
                pb.radio_playlist_id = saved.radio_playlist_id;
                pb.radio_cursor_video_id = saved.radio_cursor_video_id;
                pb.volume = saved.volume.clamp(0.0, 100.0);
                pb.runtime.last_audible = saved.last_audible.clamp(1.0, 100.0);
                pb.duration = pb
                    .current_track
                    .as_ref()
                    .and_then(|track| track.duration)
                    .unwrap_or(0.0);
            }
        }
    }
    if let Ok(Some(player)) = state.player.read().map(|p| p.clone()) {
        let _ = player.set_gain(crate::volume::combined_gain(pb.volume, pb.runtime.exponential_volume, None));
        let _ = player.set_volume(pb.volume.round() as i64);
        let _ = player.set_loop_file(pb.is_repeat);
    }
    let dto = pb.to_dto();
    drop(pb);
    let _ = app.emit("playback-state-changed", dto);
}
pub(crate) fn threshold(duration: f64) -> f64 {
    if duration.is_finite() && duration > 1.0 {
        (duration / 2.0).clamp(1.0, 30.0)
    } else {
        30.0
    }
}
fn claim_history(playback: &mut PlaybackManager, generation: u64, auth_generation: u64) -> bool {
    if playback.observed_auth_generation != auth_generation
        || playback.generation != generation
        || playback.loaded_generation != Some(generation)
        || !playback.is_playing
        || playback.current_track.is_none()
        || playback.runtime.recorded_generation == Some(generation)
    {
        return false;
    }
    playback.runtime.recorded_generation = Some(generation);
    true
}
/// Called with accepted engine progress outside the playback lock.
pub(crate) fn record_progress(
    app: &tauri::AppHandle,
    generation: u64,
    position: f64,
    duration: f64,
) {
    if !position.is_finite() || position < threshold(duration) {
        return;
    }
    let state = app.state::<AppState>();
    let auth_generation = state.auth_generation.load(Ordering::SeqCst);
    let request = {
        let Ok(mut pb) = state.playback.lock() else {
            return;
        };
        if !claim_history(&mut pb, generation, auth_generation) {
            return;
        }
        let Some(track) = pb.current_track.clone() else {
            return;
        };
        let playlist_id = pb
            .queue
            .source
            .as_ref()
            .filter(|source| source.kind == "playlist")
            .and_then(|source| source.id.clone());
        (track, playlist_id, pb.runtime.identity.clone())
    };
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let state = app.state::<AppState>();
        // Serialize against account cookie replacement, not against transport.
        let _operation = state.auth_operation.lock().await;
        if state.auth_generation.load(Ordering::SeqCst) != auth_generation
            || !state
                .playback
                .lock()
                .is_ok_and(|pb| pb.runtime.identity == request.2)
        {
            return;
        }
        let core = state.core.read().ok().and_then(|core| core.clone());
        let Some(core) = core else {
            return;
        };
        let track = request.0;
        let metadata = serde_json::json!({ "video_id": track.video_id, "title": track.title, "artists": track.artists,
            "duration": track.duration.map(|duration| format!("{}:{:02}", duration.max(0.0) as u64 / 60, duration.max(0.0) as u64 % 60)).unwrap_or_default(), "thumbnail": track.thumbnail,
            "album": track.album, "album_id": track.album_id, "artist_id": track.artist_id, "artist_runs": track.artist_runs,
            "is_upload": track.is_upload });
        if core
            .record_playback(
                track.video_id.clone(),
                Some(metadata.to_string()),
                request.1,
            )
            .await
            .is_ok()
            && state.auth_generation.load(Ordering::SeqCst) == auth_generation
            && state
                .playback
                .lock()
                .is_ok_and(|pb| pb.runtime.identity == request.2)
        {
            let _ = app.emit("playback-recorded", serde_json::json!({"track":track,"generation":generation,"authGeneration":auth_generation,"accountKey":request.2}));
        }
    });
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn history_threshold_matches_apple_short_unknown_and_long_tracks() {
        assert_eq!(threshold(40.0), 20.0);
        assert_eq!(threshold(400.0), 30.0);
        assert_eq!(threshold(0.0), 30.0);
        assert_eq!(threshold(f64::NAN), 30.0);
        assert_eq!(threshold(1.5), 1.0);
    }
    #[test]
    fn identity_prefers_channel_and_keeps_guest_separate() {
        let mut auth = AuthStatusDto::guest();
        assert_eq!(identity(&auth).as_deref(), Some("guest"));
        auth.state = "ready".into();
        auth.email = Some("email".into());
        auth.channel_id = Some("channel".into());
        assert_eq!(identity(&auth).as_deref(), Some("account:channel"));
        assert!(!filename("account:email").contains("email"));
        auth.channel_id = Some(String::new());
        auth.email = Some(String::new());
        auth.handle = Some("@handle".into());
        assert_eq!(identity(&auth).as_deref(), Some("account:@handle"));
        auth.state = "authorizing".into();
        assert!(identity(&auth).is_none());
    }
    #[test]
    fn worker_saves_accounts_separately_and_atomically_recovers_after_corruption() {
        let directory = std::env::temp_dir().join(format!(
            "sideb-playback-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let mut pb = PlaybackManager::new();
        pb.runtime.directory = Some(directory.clone());
        pb.runtime.identity = Some("account:A".into());
        pb.volume = 0.0;
        pb.runtime.last_audible = 37.0;
        let mut upload = crate::queue::QueueEntryDto::new(
            "same".into(),
            "Upload".into(),
            "Artist".into(),
            None,
            Some(120.0),
        );
        upload.is_upload = true;
        pb.queue.replace(
            vec![upload.clone(), upload],
            1,
            crate::queue::QueueSourceDto {
                kind: "playlist".into(),
                id: Some("source".into()),
                title: None,
            },
        );
        pb.is_shuffle = true;
        pb.current_track = Some(PlaybackTrackDto {
            is_upload: true,
            video_id: "same".into(),
            title: "Upload".into(),
            artists: "Artist".into(),
            thumbnail: Some("https://image.test/a?signature=private-cover-signature".into()),
            duration: Some(120.0),
            artist_id: None,
            album_id: None,
            album: None,
            artist_runs: vec![],
        });
        let mut source = SourceResume {
            kind: "playlist".into(),
            id: Some("source".into()),
            loaded_prefix: vec!["same".into(), "same".into()],
        }
        .into_progressive();
        source.continuation = Some("private-provider-token".into());
        source.error = false;
        source.needs_restart = false;
        pb.runtime.source = Some(source);
        pb.runtime.persist(&pb);
        flush();
        let path_a = directory.join(filename("account:A"));
        let bytes = std::fs::read(&path_a).unwrap();
        assert!(!String::from_utf8_lossy(&bytes).contains("private-provider-token"));
        assert!(!String::from_utf8_lossy(&bytes).contains("private-cover-signature"));
        assert!(pb.current_track.as_ref().unwrap().thumbnail.is_some());
        assert!(!String::from_utf8_lossy(&bytes).contains("continuation"));
        let saved: SavedPlayback = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(
            saved.source_resume.as_ref().unwrap().loaded_prefix,
            vec!["same", "same"]
        );
        assert_eq!(saved.volume, 0.0);
        assert_eq!(saved.last_audible, 37.0);
        assert!(!saved.exponential_volume);
        let mut legacy = serde_json::to_value(&saved).unwrap();
        legacy.as_object_mut().unwrap().remove("exponential_volume");
        assert!(!serde_json::from_value::<SavedPlayback>(legacy).unwrap().exponential_volume);
        // A mode-only change must invalidate the persisted signature, without changing volume.
        pb.runtime.exponential_volume = true;
        pb.runtime.persist(&pb);
        flush();
        let mode_saved: SavedPlayback = serde_json::from_slice(&std::fs::read(&path_a).unwrap()).unwrap();
        assert!(mode_saved.exponential_volume);
        assert_eq!(mode_saved.volume, 0.0);
        let restored = saved.queue.restore().unwrap();
        assert_eq!(restored.current_index, Some(1));
        assert_ne!(restored.items[0].entry_id, restored.items[1].entry_id);
        assert!(restored.items[1].is_upload);
        pb.runtime.identity = Some("account:B".into());
        pb.runtime.exponential_volume = false;
        *pb.runtime.last_saved.lock().unwrap() = None;
        pb.volume = 50.0;
        pb.runtime.persist(&pb);
        flush();
        let saved_b: SavedPlayback =
            serde_json::from_slice(&std::fs::read(directory.join(filename("account:B"))).unwrap())
                .unwrap();
        assert_eq!(saved_b.volume, 50.0);
        assert!(!saved_b.exponential_volume);
        assert!(serde_json::from_slice::<SavedPlayback>(&std::fs::read(&path_a).unwrap()).unwrap().exponential_volume);
        assert_eq!(
            serde_json::from_slice::<SavedPlayback>(&std::fs::read(&path_a).unwrap())
                .unwrap()
                .volume,
            0.0
        );
        pb.runtime.identity = Some("guest".into());
        *pb.runtime.last_saved.lock().unwrap() = None;
        pb.volume = 12.0;
        pb.runtime.persist(&pb);
        flush();
        let guest: SavedPlayback =
            serde_json::from_slice(&std::fs::read(directory.join(filename("guest"))).unwrap())
                .unwrap();
        assert_eq!(guest.volume, 12.0);
        assert_eq!(
            serde_json::from_slice::<SavedPlayback>(&std::fs::read(&path_a).unwrap())
                .unwrap()
                .volume,
            0.0
        );
        std::fs::write(&path_a, b"broken").unwrap();
        assert!(serde_json::from_slice::<SavedPlayback>(&std::fs::read(&path_a).unwrap()).is_err());
        pb.runtime.identity = Some("account:A".into());
        *pb.runtime.last_saved.lock().unwrap() = None;
        pb.runtime.persist(&pb);
        flush();
        assert!(serde_json::from_slice::<SavedPlayback>(&std::fs::read(&path_a).unwrap()).is_ok());
        // Remove only explicitly created test files, never a recursive computed path.
        for entry in std::fs::read_dir(&directory).unwrap() {
            std::fs::remove_file(entry.unwrap().path()).unwrap();
        }
        std::fs::remove_dir(directory).unwrap();
    }
    #[test]
    fn incomplete_source_roundtrip_keeps_prefix_without_private_continuation() {
        let mut pb = PlaybackManager::new();
        pb.runtime.source = Some(ProgressiveSource {
            kind: "playlist".into(),
            id: Some("playlist".into()),
            continuation: Some("private-provider-token".into()),
            loading: true,
            error: false,
            needs_restart: false,
            loaded_prefix: vec!["same".into(), "same".into(), "third".into()],
            consumed_continuations: Default::default(),
        });
        let source = pb.runtime.source.as_ref().unwrap();
        let resume = SourceResume {
            kind: source.kind.clone(),
            id: source.id.clone(),
            loaded_prefix: source.loaded_prefix.clone(),
        };
        let encoded = serde_json::to_string(&resume).unwrap();
        assert!(!encoded.contains("private-provider-token"));
        assert!(!encoded.contains("continuation"));
        let decoded: SourceResume = serde_json::from_str(&encoded).unwrap();
        let source = decoded.into_progressive();
        assert_eq!(source.loaded_prefix, vec!["same", "same", "third"]);
        assert!(source.needs_restart);
        assert!(source.error);
        assert!(source.continuation.is_none());
        pb.runtime.source = Some(source);
        let state = pb.runtime.source_load(3).unwrap();
        assert!(state.can_retry);
        assert!(state.has_more);
        assert!(state.error.unwrap().contains("incompleta"));
    }
    #[test]
    fn repeated_provider_tokens_remain_retryable_without_silent_exhaustion() {
        let mut source = SourceResume {
            kind: "playlist".into(),
            id: Some("list".into()),
            loaded_prefix: vec!["a".into()],
        }
        .into_progressive();
        assert!(source.advance_continuation(Some("first".into())).is_ok());
        assert!(source.advance_continuation(Some("first".into())).is_err());
        assert_eq!(source.continuation.as_deref(), Some("first"));
        assert!(source.advance_continuation(Some("second".into())).is_ok());
        assert!(source.advance_continuation(Some("first".into())).is_err());
        assert_eq!(source.continuation.as_deref(), Some("second"));
        assert_eq!(source.loaded_prefix, vec!["a"]);
        assert!(source.advance_continuation(None).is_ok());
        assert!(source.continuation.is_none());
    }

    #[test]
    fn failed_or_cancelled_login_preserves_guest_source_and_invalidates_private_requests() {
        let mut pb = PlaybackManager::new();
        pb.runtime.identity = Some("guest".into());
        pb.queue_epoch = 4;
        pb.is_loading = true;
        pb.runtime.source = Some(ProgressiveSource {
            kind: "library".into(),
            id: None,
            continuation: Some("old-private-token".into()),
            loading: true,
            error: false,
            needs_restart: false,
            loaded_prefix: vec!["same".into(), "same".into()],
            consumed_continuations: Default::default(),
        });
        pb.runtime.pending_next = Some((0, 4));
        pb.eof_waiting = Some((0, 4));
        interrupt_auth_owner(&mut pb); // authorizing changes auth generation
        assert_eq!(pb.runtime.identity.as_deref(), Some("guest"));
        assert_eq!(pb.queue_epoch, 5);
        assert_eq!(pb.generation, 1);
        assert!(!pb.is_loading);
        assert!(pb.runtime.pending_next.is_none());
        assert!(pb.eof_waiting.is_none());
        let source = pb.runtime.source.as_ref().unwrap();
        assert!(source.continuation.is_none());
        assert!(!source.loading);
        assert!(source.needs_restart);
        assert_eq!(source.loaded_prefix, vec!["same", "same"]);
        let mut auth = AuthStatusDto::guest();
        auth.state = "error".into();
        assert!(identity(&auth).is_none()); // failed login retains guest identity
        assert_eq!(identity(&AuthStatusDto::guest()), pb.runtime.identity); // cancel
        interrupt_auth_owner(&mut pb); // repeated cancellation/error remains resumable
        assert_eq!(pb.queue_epoch, 6);
        let load = pb.runtime.source_load(2).unwrap();
        assert!(load.can_retry && load.has_more);
        assert_eq!(
            pb.runtime.source.as_ref().unwrap().loaded_prefix,
            vec!["same", "same"]
        );
    }

    #[test]
    fn history_claim_rejects_stale_account_and_attempt_and_records_once() {
        let mut pb = PlaybackManager::new();
        pb.generation = 5;
        pb.observed_auth_generation = 2;
        pb.loaded_generation = Some(5);
        pb.is_playing = true;
        pb.current_track = Some(PlaybackTrackDto {
            is_upload: false,
            video_id: "video".into(),
            title: "Title".into(),
            artists: "Artist".into(),
            thumbnail: None,
            duration: Some(60.0),
            artist_id: None,
            album_id: None,
            album: None,
            artist_runs: vec![],
        });
        assert!(!claim_history(&mut pb, 4, 2));
        assert!(!claim_history(&mut pb, 5, 3));
        assert!(claim_history(&mut pb, 5, 2));
        assert!(!claim_history(&mut pb, 5, 2));
        pb.generation = 6;
        pb.loaded_generation = Some(6);
        pb.is_playing = false;
        assert!(!claim_history(&mut pb, 6, 2));
        pb.is_playing = true;
        assert!(claim_history(&mut pb, 6, 2));
    }
}
