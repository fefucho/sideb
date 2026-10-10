use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use tauri::{Emitter, Manager};

mod dto;
#[cfg(windows)]
mod media_controls;
mod playback_runtime;
mod volume;
mod queue;
mod commands {
    pub(crate) mod account;
    pub(crate) mod catalog;
    pub(crate) mod explore;
    pub(crate) mod genius;
    pub(crate) mod lyrics;
    pub(crate) mod playback;
    pub(crate) mod recommendations;
    pub(crate) mod system;
    pub(crate) mod updater;
}
pub use dto::*;
use queue::{next_owner_epoch, QueueStateDto};

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SearchResultsDto {
    pub top: Vec<SearchTopCardDto>,
    pub top_songs: Vec<SongDto>,
    pub songs: Vec<SongDto>,
    pub albums: Vec<BrowseCardDto>,
    pub artists: Vec<BrowseCardDto>,
    pub playlists: Vec<BrowseCardDto>,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SearchTopCardDto {
    pub kind: String,
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub thumbnail: Option<String>,
    pub duration: Option<String>,
    pub artists: Option<String>,
    pub artist_id: Option<String>,
    pub album: Option<String>,
    pub album_id: Option<String>,
    pub artist_runs: Vec<HomeArtistRunDto>,
    pub is_video: bool,
    pub explicit: bool,
}

impl From<sideb_core::BrowseCardRecord> for SearchTopCardDto {
    fn from(r: sideb_core::BrowseCardRecord) -> Self {
        Self {
            kind: r.kind,
            id: r.id,
            title: r.title,
            subtitle: r.subtitle,
            thumbnail: r.thumbnail,
            duration: r.duration,
            artists: r.artists,
            artist_id: r.artist_id,
            album: r.album,
            album_id: r.album_id,
            artist_runs: r
                .artist_runs
                .into_iter()
                .map(HomeArtistRunDto::from)
                .collect(),
            is_video: r.is_video,
            explicit: r.explicit,
        }
    }
}

impl From<sideb_core::SearchResultsRecord> for SearchResultsDto {
    fn from(result: sideb_core::SearchResultsRecord) -> Self {
        Self {
            top: result.top.into_iter().map(SearchTopCardDto::from).collect(),
            top_songs: result.top_songs.into_iter().map(SongDto::from).collect(),
            songs: result.songs.into_iter().map(SongDto::from).collect(),
            albums: result.albums.into_iter().map(BrowseCardDto::from).collect(),
            artists: result
                .artists
                .into_iter()
                .map(BrowseCardDto::from)
                .collect(),
            playlists: result
                .playlists
                .into_iter()
                .map(BrowseCardDto::from)
                .collect(),
        }
    }
}

#[cfg(target_os = "windows")]
mod session;
#[cfg(target_os = "windows")]
mod session_store;

pub struct PlaybackManager {
    pub(crate) runtime: playback_runtime::PlaybackRuntime,
    pub is_playing: bool,
    pub is_loading: bool,
    pub is_ended: bool,
    pub is_shuffle: bool,
    pub is_repeat: bool,
    pub position: f64,
    pub duration: f64,
    pub volume: f64,
    pub current_track: Option<PlaybackTrackDto>,
    pub error: Option<String>,
    pub generation: u64,
    pub loaded_generation: Option<u64>,
    pub queue: QueueStateDto,
    pub(crate) queue_epoch: u64,
    pub(crate) observed_auth_generation: u64,
    pub(crate) radio_playlist_id: Option<String>,
    pub(crate) radio_cursor_video_id: Option<String>,
    pub(crate) radio_exhausted: bool,
    pub(crate) eof_waiting: Option<(u64, u64)>,
}

impl PlaybackManager {
    pub fn new() -> Self {
        Self {
            runtime: Default::default(),
            is_playing: false,
            is_loading: false,
            is_ended: false,
            is_shuffle: false,
            is_repeat: false,
            position: 0.0,
            duration: 0.0,
            volume: 100.0,
            current_track: None,
            error: None,
            generation: 0,
            loaded_generation: None,
            queue: QueueStateDto::default(),
            queue_epoch: 0,
            observed_auth_generation: 0,
            radio_playlist_id: None,
            radio_cursor_video_id: None,
            radio_exhausted: false,
            eof_waiting: None,
        }
    }

    /// Changing the queue's order never loads audio or changes the active occurrence.
    pub fn set_shuffle_mode(&mut self, enabled: bool) {
        if self.is_shuffle == enabled {
            return;
        }
        if enabled {
            self.queue.shuffle_after_current();
        } else {
            self.queue.restore_original_order();
        }
        self.is_shuffle = enabled;
    }

    fn can_next(&self) -> bool {
        let Some(index) = self
            .queue
            .current_index
            .filter(|index| *index < self.queue.items.len())
        else {
            return false;
        };
        index + 1 < self.queue.items.len()
            || self.is_repeat
            || self
                .runtime
                .source
                .as_ref()
                .is_some_and(|source| source.continuation.is_some() || source.needs_restart)
            || self
                .queue
                .source
                .as_ref()
                .is_some_and(|source| source.kind == "radio")
                && !self.radio_exhausted
    }

    pub fn to_dto(&self) -> PlaybackStateDto {
        self.runtime.persist(self);
        PlaybackStateDto {
            can_next: self.can_next(),
            source_load: self.runtime.source_load(self.queue.items.len()),
            is_playing: self.is_playing,
            is_loading: self.is_loading,
            is_ended: self.is_ended,
            is_shuffle: self.is_shuffle,
            is_repeat: self.is_repeat,
            position: self.position,
            duration: self.duration,
            volume: self.volume,
            exponential_volume: self.runtime.exponential_volume,
            current_track: self.current_track.clone(),
            error: self.error.clone(),
            generation: self.generation,
            queue: self.queue.snapshot(),
        }
    }
}

#[cfg(test)]
mod playback_manager_tests {
    use super::*;
    use crate::queue::{QueueEntryDto, QueueSourceDto};

    #[test]
    fn next_availability_includes_progressive_radio_and_repeat_without_exposing_tokens() {
        let mut pb = PlaybackManager::new();
        assert!(!pb.to_dto().can_next);
        pb.queue.replace(
            vec![QueueEntryDto::new(
                "a".into(),
                "A".into(),
                "".into(),
                None,
                None,
            )],
            0,
            QueueSourceDto {
                kind: "playlist".into(),
                id: Some("list".into()),
                title: None,
            },
        );
        assert!(!pb.to_dto().can_next);
        pb.is_repeat = true;
        assert!(pb.to_dto().can_next);
        pb.is_repeat = false;
        pb.runtime.source = Some(playback_runtime::ProgressiveSource {
            kind: "playlist".into(),
            id: Some("list".into()),
            continuation: Some("private-token".into()),
            loading: true,
            error: false,
            needs_restart: false,
            loaded_prefix: vec!["a".into()],
            consumed_continuations: Default::default(),
        });
        assert!(pb.to_dto().can_next);
        assert!(!serde_json::to_string(&pb.to_dto())
            .unwrap()
            .contains("private-token"));
        let source = pb.runtime.source.as_mut().unwrap();
        source.continuation = None;
        source.needs_restart = true;
        source.error = true;
        assert!(pb.to_dto().can_next);
        pb.runtime.source = None;
        pb.queue.source.as_mut().unwrap().kind = "radio".into();
        assert!(pb.to_dto().can_next);
        pb.radio_exhausted = true;
        assert!(!pb.to_dto().can_next);
        pb.queue.append_source(
            vec![QueueEntryDto::new(
                "b".into(),
                "B".into(),
                "".into(),
                None,
                None,
            )],
            false,
        );
        assert!(pb.to_dto().can_next);
    }

    #[test]
    fn playback_snapshot_carries_shuffle_and_repeat_flags_without_changing_generation() {
        let mut playback = PlaybackManager::new();
        playback.generation = 17;
        playback.is_shuffle = true;
        playback.is_repeat = true;

        let snapshot = playback.to_dto();
        let json = serde_json::to_value(&snapshot).unwrap();
        assert_eq!(json["isShuffle"], true);
        assert_eq!(json["isRepeat"], true);
        assert_eq!(snapshot.generation, 17);
        assert_eq!(playback.generation, 17);
    }

    #[test]
    fn playback_snapshots_publish_a_playlist_batch_without_copying_the_complete_catalog() {
        let mut playback = PlaybackManager::new();
        let items = (0..2000)
            .map(|index| {
                QueueEntryDto::new(
                    index.to_string(),
                    index.to_string(),
                    String::new(),
                    None,
                    None,
                )
            })
            .collect();
        playback.queue.replace(
            items,
            0,
            QueueSourceDto {
                kind: "playlist".into(),
                id: Some("LM".into()),
                title: Some("Likes".into()),
            },
        );
        let snapshot = playback.to_dto();
        assert_eq!(snapshot.queue.items.len(), 100);
        assert_eq!(playback.queue.items.len(), 2000);
        let json = serde_json::to_value(&snapshot).unwrap();
        assert_eq!(json["queue"]["items"].as_array().unwrap().len(), 100);
        assert!(json["queue"].get("visibleLen").is_none());
        assert_eq!(
            snapshot.queue.items[0].entry_id,
            playback.queue.current().unwrap().entry_id
        );
    }

    #[test]
    fn shuffle_transitions_preserve_audio_and_manual_next_with_the_full_catalog() {
        let mut playback = PlaybackManager::new();
        playback.queue.replace(
            (0..2000)
                .map(|index| {
                    QueueEntryDto::new(
                        index.to_string(),
                        index.to_string(),
                        String::new(),
                        None,
                        None,
                    )
                })
                .collect(),
            2,
            QueueSourceDto {
                kind: "playlist".into(),
                id: Some("LM".into()),
                title: None,
            },
        );
        let active = playback.queue.current().unwrap();
        playback.current_track = Some(PlaybackTrackDto {
            is_upload: false,
            video_id: active.video_id.clone(),
            title: active.title.clone(),
            artists: active.artists.clone(),
            thumbnail: None,
            duration: Some(201.0),
            artist_id: None,
            album_id: None,
            album: None,
            artist_runs: vec![],
        });
        playback.generation = 17;
        playback.loaded_generation = Some(17);
        playback.queue_epoch = 42;
        playback.position = 31.5;
        playback.duration = 201.0;
        playback.is_playing = true;
        playback.is_repeat = true;
        playback.eof_waiting = Some((42, 17));
        playback.queue.enqueue(
            vec![QueueEntryDto::new(
                "manual".into(),
                "Manual".into(),
                String::new(),
                None,
                None,
            )],
            true,
        );
        let original = playback.queue.items.clone();
        let mut transport = serde_json::to_value(playback.to_dto()).unwrap();
        transport.as_object_mut().unwrap().remove("queue");
        transport.as_object_mut().unwrap().remove("isShuffle");
        for enabled in [true, false, true, false] {
            playback.set_shuffle_mode(enabled);
            assert_eq!(playback.queue.items.len(), 2001);
            assert_eq!(playback.queue.items[..4], original[..4]);
            assert_eq!(playback.queue.current().unwrap().entry_id, active.entry_id);
            assert_eq!(playback.loaded_generation, Some(17));
            assert_eq!(playback.queue_epoch, 42);
            assert_eq!(playback.eof_waiting, Some((42, 17)));
            assert_eq!(playback.is_shuffle, enabled);
            let mut current_transport = serde_json::to_value(playback.to_dto()).unwrap();
            current_transport.as_object_mut().unwrap().remove("queue");
            current_transport
                .as_object_mut()
                .unwrap()
                .remove("isShuffle");
            assert_eq!(current_transport, transport);
            let revision = playback.queue.revision;
            let order = playback.queue.items.clone();
            playback.set_shuffle_mode(enabled);
            assert_eq!(playback.queue.revision, revision);
            assert_eq!(playback.queue.items, order);
            if !enabled {
                assert_eq!(playback.queue.items, original);
            }
        }
        let json = serde_json::to_value(playback.to_dto()).unwrap();
        assert!(json["queue"].get("sourceRanks").is_none());
        assert!(json["queue"].get("nextSourceRank").is_none());
        assert!(json["queue"].get("explicitPlacements").is_none());
        assert!(json["queue"]["items"].as_array().unwrap().len() < 2001);
    }

    #[test]
    fn disabling_shuffle_restores_the_album_above_and_below_the_active_audio() {
        let mut playback = PlaybackManager::new();
        playback.queue.replace(
            (0..12)
                .map(|index| {
                    QueueEntryDto::new(
                        index.to_string(),
                        index.to_string(),
                        String::new(),
                        None,
                        None,
                    )
                })
                .collect(),
            0,
            QueueSourceDto {
                kind: "album".into(),
                id: Some("album".into()),
                title: None,
            },
        );
        let canonical = playback.queue.items.clone();
        // The screenshot's source order: the first album track is playing in row six.
        playback.queue.items = [7, 5, 10, 8, 6, 0, 9, 4, 3, 11, 1, 2]
            .into_iter()
            .map(|index| canonical[index].clone())
            .collect();
        playback.queue.select(5);
        let active = playback.queue.current().unwrap();
        playback.current_track = Some(PlaybackTrackDto {
            is_upload: false,
            video_id: active.video_id.clone(),
            title: active.title.clone(),
            artists: String::new(),
            thumbnail: None,
            duration: Some(201.0),
            artist_id: None,
            album_id: None,
            album: None,
            artist_runs: vec![],
        });
        playback.is_shuffle = true;
        playback.is_playing = true;
        playback.generation = 17;
        playback.loaded_generation = Some(17);
        playback.position = 62.25;
        let mut before = serde_json::to_value(playback.to_dto()).unwrap();
        before.as_object_mut().unwrap().remove("queue");
        before.as_object_mut().unwrap().remove("isShuffle");

        playback.set_shuffle_mode(false);

        assert_eq!(playback.queue.items, canonical);
        assert_eq!(playback.queue.current_index, Some(0));
        assert_eq!(playback.queue.current().unwrap().entry_id, active.entry_id);
        assert_eq!(playback.loaded_generation, Some(17));
        let mut after = serde_json::to_value(playback.to_dto()).unwrap();
        after.as_object_mut().unwrap().remove("queue");
        after.as_object_mut().unwrap().remove("isShuffle");
        assert_eq!(after, before);
        assert_eq!(
            playback.queue.next_or_first(false),
            Some(canonical[1].clone())
        );
    }
}

pub struct AppState {
    pub core: RwLock<Option<Arc<sideb_core::SideBCore>>>,
    pub init_error: RwLock<Option<String>>,
    pub player: RwLock<Option<Arc<player::Player>>>,
    pub player_error: RwLock<Option<String>>,
    pub playback: Arc<Mutex<PlaybackManager>>,
    pub auth: RwLock<AuthStatusDto>,
    pub auth_generation: AtomicU64,
    pub auth_operation: tokio::sync::Mutex<()>,
}

fn set_auth_status(app: &tauri::AppHandle, status: AuthStatusDto) {
    let state = app.state::<AppState>();
    if let Ok(mut lock) = state.auth.write() {
        *lock = status.clone();
    }
    playback_runtime::sync_account(app, &status);
    let _ = app.emit("auth-status-changed", status);
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let playback_snapshot = if let Ok(mut playback) = state.playback.lock() {
        if playback.observed_auth_generation != generation {
            playback.observed_auth_generation = generation;
            playback_runtime::interrupt_auth_owner(&mut playback);
            Some(playback.to_dto())
        } else {
            None
        }
    } else {
        None
    };
    if let Some(dto) = playback_snapshot {
        let _ = app.emit("playback-state-changed", &dto);
    }
}

pub(crate) fn invalidate_queue_owner(playback: &mut PlaybackManager) {
    playback.queue_epoch = next_owner_epoch(playback.queue_epoch);
    playback.radio_playlist_id = None;
    playback.radio_cursor_video_id = None;
    playback.radio_exhausted = false;
    playback.eof_waiting = None;
    playback.runtime.source = None;
    playback.runtime.pending_next = None;
    playback.runtime.disliked.clear();
}

fn auth_generation(app: &tauri::AppHandle) -> u64 {
    app.state::<AppState>()
        .auth_generation
        .load(Ordering::SeqCst)
}

#[tauri::command]
fn get_auth_status(state: tauri::State<'_, AppState>) -> Result<AuthStatusDto, CommandError> {
    state.auth.read().map(|status| status.clone()).map_err(|_| {
        CommandError::new(
            "AUTH_STATE_ERROR",
            "No se pudo leer el estado de la sesión.",
        )
    })
}

#[cfg(target_os = "windows")]
#[tauri::command]
// Keep this command async: WebViewWindowBuilder can deadlock Windows when invoked from a
// synchronous Tauri command (the blank, unclosable login window seen in W12).
async fn login_webview(app: tauri::AppHandle) -> Result<(), CommandError> {
    session::open_login(app).map_err(|message| CommandError::new("LOGIN_WINDOW_ERROR", message))
}

#[cfg(target_os = "windows")]
#[tauri::command]
async fn cancel_login(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<AuthStatusDto, CommandError> {
    state.auth_generation.fetch_add(1, Ordering::SeqCst);
    set_auth_status(&app, AuthStatusDto::guest());
    session::close_login_window(&app)
        .map_err(|message| CommandError::new("LOGIN_WINDOW_ERROR", message))?;
    Ok(AuthStatusDto::guest())
}

#[cfg(target_os = "windows")]
#[tauri::command]
async fn sign_out(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<AuthStatusDto, CommandError> {
    state.auth_generation.fetch_add(1, Ordering::SeqCst);
    let _auth_operation = state.auth_operation.lock().await;
    let dir = app.path().app_data_dir().map_err(|_| {
        CommandError::new("STORAGE_ERROR", "No se pudo resolver el almacén de sesión.")
    })?;
    session_store::delete(&dir).map_err(|message| CommandError::new("STORAGE_ERROR", message))?;
    let core = state
        .core
        .read()
        .map_err(|_| CommandError::new("AUTH_STATE_ERROR", "No se pudo cerrar la sesión."))?
        .clone();
    if let Some(core) = core {
        core.set_cookie_memory(None);
    }
    if let Ok(Some(player)) = state.player.read().map(|lock| lock.clone()) {
        let _ = player.stop();
        let _ = player.clear_playlist();
    }
    set_auth_status(&app, AuthStatusDto::guest());
    session::clear_login_cookies(&app)
        .await
        .map_err(|message| CommandError::new("PROFILE_CLEANUP_ERROR", message))?;
    Ok(AuthStatusDto::guest())
}

#[tauri::command]
fn get_backend_status(state: tauri::State<'_, AppState>) -> Result<BackendStatusDto, CommandError> {
    let core_opt = state.core.read().map_err(|_| {
        CommandError::new(
            "LOCK_ERROR",
            "Error de concurrencia al leer el estado del core.",
        )
    })?;

    if core_opt.is_some() {
        Ok(BackendStatusDto {
            ready: true,
            status: "Motor Side B conectado".to_string(),
        })
    } else {
        let err_guard = state.init_error.read().map_err(|_| {
            CommandError::new(
                "LOCK_ERROR",
                "Error de concurrencia al leer el estado del core.",
            )
        })?;
        let msg = err_guard
            .as_deref()
            .unwrap_or("Motor Side B no inicializado");
        Ok(BackendStatusDto {
            ready: false,
            status: msg.to_string(),
        })
    }
}

#[tauri::command]
fn retry_init_core(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<BackendStatusDto, CommandError> {
    let app_data_dir = app.path().app_data_dir().map_err(|_| {
        CommandError::new(
            "STORAGE_ERROR",
            "No se pudo determinar el directorio de datos de la aplicación.",
        )
    })?;

    let data_dir_str = app_data_dir.to_string_lossy().to_string();
    match sideb_core::SideBCore::new_windows(data_dir_str) {
        Ok(core) => {
            let mut core_lock = state.core.write().map_err(|_| {
                CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar el core.")
            })?;
            let mut err_lock = state.init_error.write().map_err(|_| {
                CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar el core.")
            })?;
            *core_lock = Some(core);
            *err_lock = None;

            if let Some(core) = core_lock.clone() {
                tauri::async_runtime::spawn(session::restore(app.clone(), core.clone()));
                tauri::async_runtime::spawn(session::watch_rotations(app.clone(), core));
            }

            Ok(BackendStatusDto {
                ready: true,
                status: "Motor Side B conectado".to_string(),
            })
        }
        Err(_) => {
            let mut err_lock = state.init_error.write().map_err(|_| {
                CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar el core.")
            })?;
            *err_lock = Some("Error al inicializar el almacenamiento local de Side B.".to_string());
            Err(CommandError::new(
                "INIT_FAILED",
                "No se pudo inicializar el almacenamiento local de Side B.",
            ))
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            #[cfg(target_os = "windows")]
            {
                // Si SIDEB_MPV_DIR está definido en el entorno, se agrega a PATH para desarrollo local.
                // En ejecución normal, Windows carga automáticamente libmpv-2.dll desde la carpeta del ejecutable.
                if let Ok(mpv_dir) = std::env::var("SIDEB_MPV_DIR") {
                    if let Ok(current_path) = std::env::var("PATH") {
                        if !current_path.contains(&mpv_dir) {
                            std::env::set_var("PATH", format!("{mpv_dir};{current_path}"));
                        }
                    }
                }
                if std::env::var("LIMUSIC_MPV_LOG").is_err() {
                    std::env::set_var("LIMUSIC_MPV_LOG", "no");
                }
            }

            let playback_manager = Arc::new(Mutex::new(PlaybackManager::new()));
            let state = AppState {
                core: RwLock::new(None),
                init_error: RwLock::new(None),
                player: RwLock::new(None),
                player_error: RwLock::new(None),
                playback: playback_manager.clone(),
                auth: RwLock::new(AuthStatusDto::guest()),
                auth_generation: AtomicU64::new(0),
                auth_operation: tokio::sync::Mutex::new(()),
            };

            match app.path().app_data_dir() {
                Ok(app_data_dir) => {
                    let data_dir_str = app_data_dir.to_string_lossy().to_string();
                    match sideb_core::SideBCore::new_windows(data_dir_str) {
                        Ok(core) => {
                            *state.core.write().unwrap() = Some(core);
                        }
                        Err(_) => {
                            *state.init_error.write().unwrap() = Some(
                                "Error al inicializar el almacenamiento local de Side B."
                                    .to_string(),
                            );
                        }
                    }
                }
                Err(_) => {
                    *state.init_error.write().unwrap() = Some(
                        "No se pudo resolver el directorio de datos de la aplicación.".to_string(),
                    );
                }
            }

            let mut player_event_rx = None;
            match app.path().app_cache_dir() {
                Ok(cache_dir) => {
                    let audio_cache = cache_dir.join("audio_cache");
                    if let Err(e) = std::fs::create_dir_all(&audio_cache) {
                        *state.player_error.write().unwrap() = Some(format!(
                            "Error al crear el directorio de caché de audio: {e}"
                        ));
                    } else {
                        let cache_str = audio_cache.to_string_lossy().to_string();
                        match player::Player::new(&cache_str) {
                            Ok(mut p) => {
                                player_event_rx = p.take_events();
                                *state.player.write().unwrap() = Some(Arc::new(p));
                            }
                            Err(_) => {
                                *state.player_error.write().unwrap() = Some(
                                    "No se pudo inicializar el motor de audio (libmpv)."
                                        .to_string(),
                                );
                            }
                        }
                    }
                }
                Err(_) => {
                    *state.player_error.write().unwrap() =
                        Some("No se pudo resolver el directorio de caché de audio.".to_string());
                }
            }

            if let Some(mut rx) = player_event_rx {
                let app_handle = app.handle().clone();
                let pb_ref = playback_manager.clone();
                tauri::async_runtime::spawn(async move {
                    let mut last_progress_emit = std::time::Instant::now();
                    while let Some(ev) = rx.recv().await {
                        match ev {
                            player::PlayerEvent::Position(pos) => {
                                let should_emit = last_progress_emit.elapsed()
                                    >= std::time::Duration::from_millis(200);
                                if let Ok(mut pb) = pb_ref.lock() {
                                    // Sólo procesar eventos de posición si hay una pista efectivamente cargada para la generación activa
                                    if pb.loaded_generation.is_some() && !pb.is_ended {
                                        pb.position = pos;
                                        if pb.is_loading && pos > 0.0 {
                                            pb.is_loading = false;
                                            pb.is_playing = true;
                                        }
                                        let dur = pb.duration;
                                        let gen = pb.generation;
                                        drop(pb);
                                        playback_runtime::record_progress(
                                            &app_handle,
                                            gen,
                                            pos,
                                            dur,
                                        );
                                        if should_emit {
                                            let prog = PlaybackProgressDto {
                                                position: pos,
                                                duration: dur,
                                                generation: gen,
                                            };
                                            let _ = app_handle.emit("playback-progress", &prog);
                                            last_progress_emit = std::time::Instant::now();
                                        }
                                    }
                                }
                            }
                            player::PlayerEvent::Duration(dur) => {
                                if dur > 0.0 {
                                    if let Ok(mut pb) = pb_ref.lock() {
                                        // Sólo aplicar si hay una pista cargada activa
                                        if pb.loaded_generation.is_some() {
                                            pb.duration = dur;
                                            let dto = pb.to_dto();
                                            drop(pb);
                                            let _ = app_handle.emit("playback-state-changed", &dto);
                                        }
                                    }
                                }
                            }
                            player::PlayerEvent::Playing(playing) => {
                                if let Ok(mut pb) = pb_ref.lock() {
                                    if playing {
                                        // Sólo pasar a playing si la pista está cargada en el motor
                                        if pb.loaded_generation.is_some() {
                                            pb.is_playing = true;
                                            pb.is_loading = false;
                                            pb.is_ended = false;
                                            let dto = pb.to_dto();
                                            drop(pb);
                                            let _ = app_handle.emit("playback-state-changed", &dto);
                                        }
                                    } else {
                                        if pb.is_playing {
                                            pb.is_playing = false;
                                            let dto = pb.to_dto();
                                            drop(pb);
                                            let _ = app_handle.emit("playback-state-changed", &dto);
                                        }
                                    }
                                }
                            }
                            player::PlayerEvent::TrackEnded => {
                                commands::playback::handle_track_ended(app_handle.clone());
                            }
                            player::PlayerEvent::TrackFailed(_) => {
                                if let Ok(mut pb) = pb_ref.lock() {
                                    if pb.loaded_generation.is_some() {
                                        pb.is_playing = false;
                                        pb.is_loading = false;
                                        pb.is_ended = false;
                                        pb.error = Some(
                                            "Error al reproducir la pista en el motor de audio."
                                                .to_string(),
                                        );
                                        pb.loaded_generation = None;
                                        let dto = pb.to_dto();
                                        drop(pb);
                                        let _ = app_handle.emit("playback-state-changed", &dto);
                                    }
                                }
                            }
                            player::PlayerEvent::Error(_) => {
                                if let Ok(mut pb) = pb_ref.lock() {
                                    if pb.loaded_generation.is_some() {
                                        pb.is_playing = false;
                                        pb.is_loading = false;
                                        pb.error =
                                            Some("Error en el reproductor de audio.".to_string());
                                        pb.loaded_generation = None;
                                        let dto = pb.to_dto();
                                        drop(pb);
                                        let _ = app_handle.emit("playback-state-changed", &dto);
                                    }
                                }
                            }
                        }
                    }
                });
            }

            let core_to_restore = state.core.read().ok().and_then(|lock| lock.clone());
            app.manage(state);
            #[cfg(windows)]
            {
                let _ = media_controls::initialize(app.handle());
            }
            playback_runtime::sync_account(app.handle(), &AuthStatusDto::guest());
            if let Some(core) = core_to_restore {
                tauri::async_runtime::spawn(session::restore(app.handle().clone(), core.clone()));
                tauri::async_runtime::spawn(session::watch_rotations(app.handle().clone(), core));
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if window.label() == "main"
                && matches!(event, tauri::WindowEvent::CloseRequested { .. })
            {
                playback_runtime::flush();
            }
            if window.label() == "sideb-login" && matches!(event, tauri::WindowEvent::Destroyed) {
                let app = window.app_handle();
                let state = app.state::<AppState>();
                let authorizing = state
                    .auth
                    .read()
                    .map(|status| status.state == "authorizing")
                    .unwrap_or(false);
                if authorizing {
                    state.auth_generation.fetch_add(1, Ordering::SeqCst);
                    set_auth_status(app, AuthStatusDto::guest());
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            get_backend_status,
            get_auth_status,
            login_webview,
            cancel_login,
            sign_out,
            retry_init_core,
            commands::system::open_external_url,
            commands::explore::detect_music_country,
            commands::explore::get_charts,
            commands::genius::genius_cached,
            commands::genius::genius_resolve,
            commands::genius::genius_search,
            commands::genius::genius_choose,
            commands::genius::genius_clear_choice,
            commands::genius::genius_report_miss,
            commands::genius::genius_annotations,
            commands::genius::genius_lyrics,
            commands::genius::genius_metrics,
            commands::playback::begin_queue_source,
            commands::playback::retry_queue_source,
            commands::playback::start_source_radio,
            commands::playback::set_playback_muted,
            commands::playback::filter_disliked_recommendations,
            commands::catalog::search_all,
            commands::catalog::search_videos,
            commands::catalog::search_cards,
            commands::catalog::search_songs,
            commands::catalog::search_albums,
            commands::catalog::get_album,
            commands::catalog::get_home_page,
            commands::catalog::get_home_continuation,
            commands::catalog::get_artist,
            commands::catalog::get_browse_grid,
            commands::catalog::get_playlist,
            commands::account::get_library_playlists,
            commands::account::get_library_albums,
            commands::account::get_library_artists,
            commands::account::get_library_songs,
            commands::account::get_playlist_continuation,
            commands::account::get_history,
            commands::account::rate_song,
            commands::account::apply_song_library_action,
            commands::account::create_playlist,
            commands::account::edit_playlist_details,
            commands::account::set_playlist_sort,
            commands::account::delete_playlist,
            commands::account::add_to_playlist,
            commands::account::remove_from_playlist,
            commands::account::move_playlist_track,
            commands::catalog::get_artist_radio,
            commands::account::toggle_album_library,
            commands::account::set_artist_subscription,
            commands::playback::play_song,
            commands::playback::start_song_radio,
            commands::playback::retry_radio,
            commands::playback::enqueue_tracks,
            commands::playback::remove_queue_entry,
            commands::playback::move_queue_entry,
            commands::lyrics::get_lyrics,
            commands::recommendations::get_related_tracks,
            commands::recommendations::get_related_artists,
            commands::playback::next_track,
            commands::playback::previous_track,
            commands::playback::pause_playback,
            commands::playback::resume_playback,
            commands::playback::seek_playback,
            commands::playback::set_playback_volume,
            commands::playback::set_exponential_volume,
            commands::playback::set_shuffle,
            commands::playback::set_repeat,
            commands::playback::get_playback_state,
            commands::playback::stop_playback,
            commands::updater::check_for_updates,
            commands::updater::download_and_install_update,
            commands::updater::get_app_version,
            commands::updater::get_skipped_version,
            commands::updater::skip_version,
            commands::updater::reset_skipped_version
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
