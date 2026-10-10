//! Windows SMTC observes native playback and dispatches back to the same authoritative commands.
#[derive(Default)]
struct PublicationGate {
    generation: u64,
    revision: u64,
    metadata: Option<String>,
}
impl PublicationGate {
    fn accept(&mut self, generation: u64, revision: u64, metadata: Option<String>) -> Option<bool> {
        if generation < self.generation || generation == self.generation && revision < self.revision
        {
            return None;
        }
        let changed = metadata != self.metadata;
        self.generation = generation;
        self.revision = revision;
        self.metadata = metadata;
        Some(changed)
    }
    fn owns_artwork(&self, generation: u64, key: &str) -> bool {
        self.generation == generation && self.metadata.as_deref() == Some(key)
    }
}
#[cfg(windows)]
mod native {
    use super::PublicationGate;
    use crate::{AppState, PlaybackProgressDto, PlaybackStateDto};
    use souvlaki::{
        MediaControlEvent, MediaControls, MediaMetadata, MediaPlayback, MediaPosition,
        PlatformConfig, SeekDirection,
    };
    use std::{
        sync::{Arc, Mutex},
        time::Duration,
    };
    use tauri::{Listener, Manager};
    use windows_media::{
        Media::{SystemMediaTransportControls, SystemMediaTransportControlsDisplayUpdater},
        Win32::{Foundation::HWND, System::WinRT::ISystemMediaTransportControlsInterop},
    };
    struct Controls {
        controls: MediaControls,
        updater: SystemMediaTransportControlsDisplayUpdater,
        native: SystemMediaTransportControls,
        publication: PublicationGate,
        playing: bool,
        artwork_path: Option<std::path::PathBuf>,
    }
    fn duration(value: f64) -> Duration {
        Duration::try_from_secs_f64(value.max(0.0)).unwrap_or_default()
    }
    fn fetch_artwork(
        app: tauri::AppHandle,
        controls: Arc<Mutex<Controls>>,
        snapshot: PlaybackStateDto,
        key: String,
    ) {
        let Some(track) = snapshot.current_track else {
            return;
        };
        let Some(url) = track.thumbnail.clone() else {
            return;
        };
        let Ok(url) = reqwest::Url::parse(&url) else {
            return;
        };
        if url.scheme() != "https" {
            return;
        }
        let Ok(cache) = app.path().app_cache_dir() else {
            return;
        };
        tauri::async_runtime::spawn(async move {
            let Ok(client) = reqwest::Client::builder()
                .timeout(Duration::from_secs(12))
                .build()
            else {
                return;
            };
            let Ok(mut response) = client.get(url).send().await else {
                return;
            };
            if !response.status().is_success()
                || response
                    .content_length()
                    .is_some_and(|size| size > 5 * 1024 * 1024)
                || !response
                    .headers()
                    .get(reqwest::header::CONTENT_TYPE)
                    .and_then(|mime| mime.to_str().ok())
                    .is_some_and(|mime| mime.starts_with("image/"))
            {
                return;
            }
            let mut bytes = Vec::new();
            loop {
                match response.chunk().await {
                    Ok(Some(chunk)) if bytes.len() + chunk.len() <= 5 * 1024 * 1024 => {
                        bytes.extend_from_slice(&chunk)
                    }
                    Ok(None) => break,
                    _ => return,
                }
            }
            {
                let Ok(current) = controls.lock() else {
                    return;
                };
                if !current.publication.owns_artwork(snapshot.generation, &key) {
                    return;
                }
            }
            use sha2::{Digest, Sha256};
            let directory = cache.join("media-artwork");
            let path = directory.join(format!("{:x}.image", Sha256::digest(key.as_bytes())));
            if std::fs::create_dir_all(&directory).is_err() || std::fs::write(&path, bytes).is_err()
            {
                return;
            }
            // Use the same lock order as command publication (playback -> SMTC).
            // Validate against native playback as well as the last delivered event.
            let state = app.state::<AppState>();
            let Ok(playback) = state.playback.lock() else {
                let _ = std::fs::remove_file(&path);
                return;
            };
            let live_key = playback.current_track.as_ref().and_then(|track| {
                serde_json::to_string(&(track, playback.duration, playback.generation)).ok()
            });
            if playback.generation != snapshot.generation
                || live_key.as_deref() != Some(key.as_str())
            {
                let _ = std::fs::remove_file(&path);
                return;
            }
            let Ok(mut current) = controls.lock() else {
                return;
            };
            if !current.publication.owns_artwork(snapshot.generation, &key) {
                let _ = std::fs::remove_file(&path);
                return;
            }
            // Local file is fully downloaded. WinRT never races a remote URI from a previous generation.
            let cover = format!("file://{}", path.to_string_lossy());
            let published = current.controls.set_metadata(MediaMetadata {
                title: Some(&track.title),
                artist: Some(&track.artists),
                album: Some(track.album.as_deref().unwrap_or("")),
                cover_url: Some(&cover),
                duration: Some(duration(
                    snapshot.duration.max(track.duration.unwrap_or(0.0)),
                )),
            });
            if published.is_ok() {
                if let Some(previous) = current.artwork_path.replace(path) {
                    let _ = std::fs::remove_file(previous);
                }
            } else {
                let _ = std::fs::remove_file(path);
            }
        });
    }
    pub fn initialize(app: &tauri::AppHandle) -> Result<(), String> {
        let window = app
            .get_webview_window("main")
            .ok_or("No hay ventana principal para SMTC")?;
        let hwnd = window
            .hwnd()
            .map_err(|_| "No se pudo obtener HWND para SMTC")?;
        let interop: ISystemMediaTransportControlsInterop = windows_media::core::factory::<
            SystemMediaTransportControls,
            ISystemMediaTransportControlsInterop,
        >()
        .map_err(|_| "SMTC no disponible")?;
        let native: SystemMediaTransportControls =
            unsafe { interop.GetForWindow(HWND(hwnd.0 as isize)) }
                .map_err(|_| "SMTC no disponible para ventana")?;
        let updater = native
            .DisplayUpdater()
            .map_err(|_| "SMTC display no disponible")?;
        let mut controls = MediaControls::new(PlatformConfig {
            dbus_name: "sideb",
            display_name: "Side B",
            hwnd: Some(hwnd.0 as *mut std::ffi::c_void),
        })
        .map_err(|_| "No se pudo inicializar SMTC")?;
        let handle = app.clone();
        controls
            .attach(move |event| {
                let app = handle.clone();
                tauri::async_runtime::spawn(async move {
                    let state = app.state::<AppState>();
                    let (playing, position) = state
                        .playback
                        .lock()
                        .map(|pb| (pb.is_playing || pb.is_loading, pb.position))
                        .unwrap_or((false, 0.0));
                    use crate::commands::playback as p;
                    match event {
                        MediaControlEvent::Play => {
                            let _ = p::resume_playback(app.clone(), state).await;
                        }
                        MediaControlEvent::Pause => {
                            let _ = p::pause_playback(app.clone(), state).await;
                        }
                        MediaControlEvent::Toggle => {
                            if playing {
                                let _ = p::pause_playback(app.clone(), state).await;
                            } else {
                                let _ = p::resume_playback(app.clone(), state).await;
                            }
                        }
                        MediaControlEvent::Next => {
                            let _ = p::next_track(app.clone(), state).await;
                        }
                        MediaControlEvent::Previous => {
                            let _ = p::previous_track(app.clone(), state).await;
                        }
                        MediaControlEvent::Stop => {
                            let _ = p::stop_playback(app.clone(), state).await;
                        }
                        MediaControlEvent::SetPosition(position) => {
                            let _ = p::seek_playback(app.clone(), state, position.0.as_secs_f64())
                                .await;
                        }
                        MediaControlEvent::Seek(direction) => {
                            let target = (position
                                + if direction == SeekDirection::Forward {
                                    10.0
                                } else {
                                    -10.0
                                })
                            .max(0.0);
                            let _ = p::seek_playback(app.clone(), state, target).await;
                        }
                        MediaControlEvent::SeekBy(direction, amount) => {
                            let target = (position
                                + amount.as_secs_f64()
                                    * if direction == SeekDirection::Forward {
                                        1.0
                                    } else {
                                        -1.0
                                    })
                            .max(0.0);
                            let _ = p::seek_playback(app.clone(), state, target).await;
                        }
                        MediaControlEvent::Raise => {
                            if let Some(window) = app.get_webview_window("main") {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                        _ => {}
                    }
                });
            })
            .map_err(|_| "No se pudieron conectar controles SMTC")?;
        let _ = native.SetIsEnabled(false);
        let controls = Arc::new(Mutex::new(Controls {
            controls,
            updater,
            native,
            publication: PublicationGate::default(),
            playing: false,
            artwork_path: None,
        }));
        let state_controls = controls.clone();
        let artwork_app = app.clone();
        app.listen("playback-state-changed", move |event| {
            let Ok(snapshot) = serde_json::from_str::<PlaybackStateDto>(event.payload()) else {
                return;
            };
            let Ok(mut current) = state_controls.lock() else {
                return;
            };
            let key = snapshot.current_track.as_ref().and_then(|track| {
                serde_json::to_string(&(track, snapshot.duration, snapshot.generation)).ok()
            });
            let Some(changed) = current.publication.accept(
                snapshot.generation,
                snapshot.queue.revision,
                key.clone(),
            ) else {
                return;
            };
            current.playing = snapshot.is_playing;
            if changed {
                // Clear the previous artwork before publishing metadata for this occurrence.
                let _ = current.updater.ClearAll();
                if let Some(previous) = current.artwork_path.take() {
                    let _ = std::fs::remove_file(previous);
                }
                let _ = current
                    .native
                    .SetIsEnabled(snapshot.current_track.is_some());
                if let Some(track) = snapshot.current_track.as_ref() {
                    let _ = current.controls.set_metadata(MediaMetadata {
                        title: Some(&track.title),
                        artist: Some(&track.artists),
                        album: Some(track.album.as_deref().unwrap_or("")),
                        cover_url: None,
                        duration: Some(duration(
                            snapshot.duration.max(track.duration.unwrap_or(0.0)),
                        )),
                    });
                } else {
                    let _ = current.updater.Update();
                }
                if let Some(key) = key {
                    fetch_artwork(
                        artwork_app.clone(),
                        state_controls.clone(),
                        snapshot.clone(),
                        key,
                    );
                }
            }
            let progress = Some(MediaPosition(duration(snapshot.position)));
            let playback = if snapshot.current_track.is_none() {
                MediaPlayback::Stopped
            } else if snapshot.is_playing {
                MediaPlayback::Playing { progress }
            } else {
                MediaPlayback::Paused { progress }
            };
            let _ = current.controls.set_playback(playback);
        });
        app.listen("playback-progress", move |event| {
            let Ok(progress) = serde_json::from_str::<PlaybackProgressDto>(event.payload()) else {
                return;
            };
            let Ok(mut current) = controls.lock() else {
                return;
            };
            if progress.generation != current.publication.generation {
                return;
            }
            let progress = Some(MediaPosition(duration(progress.position)));
            let playback = if current.playing {
                MediaPlayback::Playing { progress }
            } else {
                MediaPlayback::Paused { progress }
            };
            let _ = current.controls.set_playback(playback);
        });
        Ok(())
    }
}
#[cfg(windows)]
pub(crate) use native::initialize;

#[cfg(test)]
mod tests {
    use super::PublicationGate;
    #[test]
    fn downloaded_artwork_cannot_publish_after_new_track_or_stop() {
        let mut gate = PublicationGate::default();
        assert_eq!(gate.accept(10, 4, Some("track-A".into())), Some(true));
        assert!(gate.owns_artwork(10, "track-A"));
        assert_eq!(gate.accept(11, 5, Some("track-B".into())), Some(true));
        assert!(!gate.owns_artwork(10, "track-A"));
        assert!(!gate.owns_artwork(11, "track-A"));
        assert!(gate.owns_artwork(11, "track-B"));
        gate.accept(12, 0, None);
        assert!(!gate.owns_artwork(11, "track-B"));
    }
    #[test]
    fn old_snapshots_and_old_metadata_in_same_attempt_do_not_replace_artwork_owner() {
        let mut gate = PublicationGate::default();
        gate.accept(12, 9, Some("resolved-art".into()));
        assert_eq!(gate.accept(11, 100, Some("old-track".into())), None);
        assert_eq!(gate.accept(12, 8, Some("old-art".into())), None);
        assert!(gate.owns_artwork(12, "resolved-art"));
        gate.accept(12, 10, Some("enriched-art".into()));
        assert!(!gate.owns_artwork(12, "resolved-art"));
        assert!(gate.owns_artwork(12, "enriched-art"));
    }
}
