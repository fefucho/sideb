use crate::queue::{QueueEntryDto, QueueSourceDto, QueueStateDto};
use crate::{
    invalidate_queue_owner, AppState, CommandError, PlaybackManager, PlaybackStateDto,
    PlaybackTrackDto, SongDto,
};
use std::sync::atomic::Ordering;
use tauri::{Emitter, Manager};

fn parse_duration_to_seconds(s: &str) -> Option<f64> {
    if let Ok(sec) = s.parse::<f64>() {
        return Some(sec);
    }
    let parts: Vec<&str> = s.split(':').collect();
    if parts.len() == 2 {
        let m = parts[0].trim().parse::<f64>().ok()?;
        let s = parts[1].trim().parse::<f64>().ok()?;
        Some(m * 60.0 + s)
    } else if parts.len() == 3 {
        let h = parts[0].trim().parse::<f64>().ok()?;
        let m = parts[1].trim().parse::<f64>().ok()?;
        let s = parts[2].trim().parse::<f64>().ok()?;
        Some(h * 3600.0 + m * 60.0 + s)
    } else {
        None
    }
}

#[derive(Clone)]
enum RadioFetch {
    Initial {
        seed_video_id: String,
    },
    Continuation {
        last_video_id: String,
        playlist_id: String,
    },
}

fn queue_entry_from_song(song: SongDto) -> QueueEntryDto {
    let mut entry = QueueEntryDto::with_metadata_and_runs(
        song.video_id,
        song.title,
        song.artists,
        song.thumbnail,
        song.duration.as_deref().and_then(parse_duration_to_seconds),
        song.artist_id,
        song.album_id,
        song.album,
        song.artist_runs,
    );
    entry.is_upload = song.is_upload;
    entry
}

fn queue_entry_from_record(song: sideb_core::SongItemRecord) -> QueueEntryDto {
    let mut entry = QueueEntryDto::with_metadata_and_runs(
        song.video_id,
        song.title,
        song.artists,
        song.thumbnail,
        song.duration.as_deref().and_then(parse_duration_to_seconds),
        song.artist_id,
        song.album_id,
        song.album,
        song.artist_runs
            .into_iter()
            .map(crate::HomeArtistRunDto::from)
            .collect(),
    );
    entry.is_upload = song.is_upload;
    entry
}

fn maybe_prefetch_radio(app: tauri::AppHandle) {
    let state = app.state::<AppState>();
    let core = match state.core.read() {
        Ok(core) => core.clone(),
        Err(_) => None,
    };
    let Some(core) = core else {
        return;
    };
    let auth_generation = state.auth_generation.load(Ordering::SeqCst);
    let request = {
        let Ok(mut playback) = state.playback.lock() else {
            return;
        };
        if playback
            .queue
            .source
            .as_ref()
            .is_none_or(|source| source.kind != "radio")
            || playback.radio_exhausted
            || playback
                .queue
                .radio
                .as_ref()
                .is_some_and(|radio| radio.loading || radio.error.is_some())
        {
            return;
        }
        let remaining = playback
            .queue
            .items
            .len()
            .saturating_sub(playback.queue.current_index.unwrap_or(0));
        if remaining > 3 {
            return;
        }
        let fetch = match (
            playback.radio_playlist_id.clone(),
            playback.radio_cursor_video_id.clone(),
        ) {
            (Some(playlist_id), Some(last_video_id)) => RadioFetch::Continuation {
                last_video_id,
                playlist_id,
            },
            _ => {
                let Some(seed_video_id) = playback
                    .queue
                    .source
                    .as_ref()
                    .and_then(|source| source.id.clone())
                else {
                    return;
                };
                RadioFetch::Initial { seed_video_id }
            }
        };
        playback.queue.begin_radio();
        (playback.queue_epoch, playback.to_dto(), fetch)
    };
    let _ = app.emit("playback-state-changed", &request.1);
    tauri::async_runtime::spawn(fetch_radio(
        app,
        core,
        request.0,
        auth_generation,
        request.2,
    ));
}

async fn fetch_radio(
    app: tauri::AppHandle,
    core: std::sync::Arc<sideb_core::SideBCore>,
    queue_epoch: u64,
    auth_generation: u64,
    request: RadioFetch,
) {
    let fetched = match &request {
        RadioFetch::Initial { seed_video_id } => core.get_radio(seed_video_id.clone()).await,
        RadioFetch::Continuation {
            last_video_id,
            playlist_id,
        } => {
            core.get_radio_continuation(last_video_id.clone(), Some(playlist_id.clone()))
                .await
        }
    };
    let state = app.state::<AppState>();
    let session_is_current = state.auth_generation.load(Ordering::SeqCst) == auth_generation;
    let mut next_to_play = None;
    let snapshot = {
        let Ok(mut playback) = state.playback.lock() else {
            return;
        };
        if playback.queue_epoch != queue_epoch
            || playback
                .queue
                .source
                .as_ref()
                .is_none_or(|source| source.kind != "radio")
        {
            return;
        }
        if !session_is_current {
            invalidate_queue_owner(&mut playback);
            if playback.queue.radio.is_some() {
                playback.queue.end_radio(None, true);
            }
            playback.to_dto()
        } else {
            match fetched {
                Ok(page) => {
                    if let RadioFetch::Initial { seed_video_id } = &request {
                        playback.radio_playlist_id = Some(
                            page.automix_playlist_id
                                .unwrap_or_else(|| format!("RDAMVM{seed_video_id}")),
                        );
                    }
                    let recommendations = page
                        .items
                        .into_iter()
                        .map(queue_entry_from_record)
                        .filter(|entry| !playback.runtime.disliked.contains(&entry.video_id))
                        .collect::<Vec<_>>();
                    let cursor = merge_radio_metadata(&mut playback, recommendations);
                    if cursor.is_none() {
                        playback.radio_exhausted = true;
                        playback.queue.end_radio(None, false);
                        playback.eof_waiting = None;
                        playback.runtime.pending_next = None;
                    } else {
                        playback.radio_exhausted = false;
                        playback.radio_cursor_video_id = cursor;
                        playback.queue.end_radio(None, false);
                        next_to_play = consume_waiting_next(&mut playback);
                    }
                    playback.to_dto()
                }
                Err(_) => {
                    playback
                        .queue
                        .end_radio(Some("No se pudieron cargar recomendaciones.".into()), true);
                    playback.to_dto()
                }
            }
        }
    };
    let _ = app.emit("playback-state-changed", &snapshot);
    if let Some((entry_id, generation)) = next_to_play {
        tauri::async_runtime::spawn(start_queue_entry(app.clone(), entry_id, generation, false));
    }
    maybe_hydrate_current_album(app.clone());
    maybe_prefetch_radio(app);
}

fn merge_radio_metadata(
    playback: &mut PlaybackManager,
    recommendations: Vec<QueueEntryDto>,
) -> Option<String> {
    let cursor = playback.queue.merge_radio(recommendations);
    if let (Some(track), Some(entry)) = (playback.current_track.as_mut(), playback.queue.current())
    {
        track.enrich_missing_metadata(&entry);
    }
    cursor
}

#[derive(Clone)]
struct AlbumMetadataRequest {
    auth_generation: u64,
    generation: u64,
    queue_epoch: u64,
    queue_revision: u64,
    entry_id: String,
    video_id: String,
    album_id: String,
    album_label: Option<String>,
}

fn album_metadata_request(
    playback: &PlaybackManager,
    auth_generation: u64,
) -> Option<AlbumMetadataRequest> {
    if playback.observed_auth_generation != auth_generation {
        return None;
    }
    let entry = playback.queue.current()?;
    let track = playback.current_track.as_ref()?;
    if entry.video_id != track.video_id
        || entry.album_id != track.album_id
        || entry.album != track.album
    {
        return None;
    }
    let album_id = entry
        .album_id
        .as_ref()
        .filter(|id| !id.trim().is_empty())?
        .clone();
    // A heuristic can request verification of legacy metadata, but can never
    // erase a canonical title. Albums actually named "100 Plays" remain valid.
    if entry
        .album
        .as_ref()
        .is_some_and(|label| !label.trim().is_empty() && !crate::queue::provider_statistic(label))
    {
        return None;
    }
    Some(AlbumMetadataRequest {
        auth_generation,
        generation: playback.generation,
        queue_epoch: playback.queue_epoch,
        queue_revision: playback.queue.revision,
        entry_id: entry.entry_id,
        video_id: entry.video_id,
        album_id,
        album_label: entry.album,
    })
}

fn apply_album_metadata(
    playback: &mut PlaybackManager,
    request: &AlbumMetadataRequest,
    auth_generation: u64,
    browse_id: &str,
    title: &str,
    contains_video: bool,
) -> bool {
    if playback.observed_auth_generation != auth_generation
        || auth_generation != request.auth_generation
        || playback.generation != request.generation
        || playback.queue_epoch != request.queue_epoch
        || playback.queue.revision != request.queue_revision
        || browse_id != request.album_id
        || !contains_video
        || title.trim().is_empty()
    {
        return false;
    }
    let Some(entry) = playback.queue.current() else {
        return false;
    };
    let Some(track) = playback.current_track.as_ref() else {
        return false;
    };
    if entry.entry_id != request.entry_id
        || entry.video_id != request.video_id
        || entry.album_id.as_deref() != Some(request.album_id.as_str())
        || track.video_id != request.video_id
        || track.album_id.as_deref() != Some(request.album_id.as_str())
        || entry.album != request.album_label
        || track.album != request.album_label
    {
        return false;
    }
    let title = title.trim().to_owned();
    if entry.album.as_ref() == Some(&title) && track.album.as_ref() == Some(&title) {
        return false;
    }
    // Metadata-only mutation: preserve occurrence/order, generation, stream,
    // position and pause state. Never invoke play_song or reload the engine.
    if let Some(entry) = playback
        .queue
        .items
        .iter_mut()
        .find(|entry| entry.entry_id == request.entry_id)
    {
        entry.album = Some(title.clone());
    }
    playback.current_track.as_mut().unwrap().album = Some(title);
    playback.queue.revision += 1;
    true
}

fn apply_album_metadata_after_queue_update(
    playback: &mut PlaybackManager,
    request: &AlbumMetadataRequest,
    auth_generation: u64,
    browse_id: &str,
    title: &str,
    contains_video: bool,
) -> bool {
    if apply_album_metadata(
        playback,
        request,
        auth_generation,
        browse_id,
        title,
        contains_video,
    ) {
        return true;
    }
    // A radio append or reorder can advance only the queue revision while the
    // lookup is in flight. Re-capture ownership instead of ignoring revision;
    // never rebase across a track/account/occurrence/destination/label change.
    let Some(fresh) = album_metadata_request(playback, auth_generation) else {
        return false;
    };
    if fresh.auth_generation != request.auth_generation
        || fresh.generation != request.generation
        || fresh.queue_epoch != request.queue_epoch
        || fresh.entry_id != request.entry_id
        || fresh.video_id != request.video_id
        || fresh.album_id != request.album_id
        || fresh.album_label != request.album_label
    {
        return false;
    }
    apply_album_metadata(
        playback,
        &fresh,
        auth_generation,
        browse_id,
        title,
        contains_video,
    )
}

fn maybe_hydrate_current_album(app: tauri::AppHandle) {
    let state = app.state::<AppState>();
    let auth_generation = state.auth_generation.load(Ordering::SeqCst);
    let Some(request) = state
        .playback
        .lock()
        .ok()
        .and_then(|pb| album_metadata_request(&pb, auth_generation))
    else {
        return;
    };
    let Some(core) = state.core.read().ok().and_then(|core| core.clone()) else {
        return;
    };
    tauri::async_runtime::spawn(async move {
        let Ok(album) = core.get_album(request.album_id.clone()).await else {
            return;
        };
        let state = app.state::<AppState>();
        let snapshot = {
            let Ok(mut pb) = state.playback.lock() else {
                return;
            };
            if !apply_album_metadata_after_queue_update(
                &mut pb,
                &request,
                state.auth_generation.load(Ordering::SeqCst),
                &album.browse_id,
                &album.title,
                album
                    .items
                    .iter()
                    .any(|song| song.video_id == request.video_id),
            ) {
                return;
            }
            pb.to_dto()
        };
        let _ = app.emit("playback-state-changed", &snapshot);
    });
}

fn begin_radio_fetch(app: tauri::AppHandle, force: bool) -> Result<PlaybackStateDto, CommandError> {
    let state = app.state::<AppState>();
    let core = state
        .core
        .read()
        .map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?
        .clone()
        .ok_or_else(|| {
            CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo.")
        })?;
    let auth_generation = state.auth_generation.load(Ordering::SeqCst);
    let (snapshot, epoch, request) = {
        let mut playback = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer el reproductor."))?;
        if playback
            .queue
            .source
            .as_ref()
            .is_none_or(|source| source.kind != "radio")
        {
            return Err(CommandError::new(
                "NO_RADIO_QUEUE",
                "La cola actual no es una radio.",
            ));
        }
        if playback
            .queue
            .radio
            .as_ref()
            .is_some_and(|radio| radio.loading)
        {
            return Ok(playback.to_dto());
        }
        if !force
            && playback
                .queue
                .radio
                .as_ref()
                .is_some_and(|radio| !radio.can_retry)
        {
            return Ok(playback.to_dto());
        }
        if playback.radio_exhausted {
            return Err(CommandError::new(
                "RADIO_EXHAUSTED",
                "La radio no tiene más canciones.",
            ));
        }
        let request = match (
            playback.radio_playlist_id.clone(),
            playback.radio_cursor_video_id.clone(),
        ) {
            (Some(playlist_id), Some(last_video_id)) => RadioFetch::Continuation {
                last_video_id,
                playlist_id,
            },
            _ => {
                let seed_video_id = playback
                    .queue
                    .source
                    .as_ref()
                    .and_then(|source| source.id.clone())
                    .ok_or_else(|| {
                        CommandError::new(
                            "RADIO_SEED_MISSING",
                            "No se encontró la canción de inicio de la radio.",
                        )
                    })?;
                RadioFetch::Initial { seed_video_id }
            }
        };
        playback.queue.begin_radio();
        (playback.to_dto(), playback.queue_epoch, request)
    };
    let _ = app.emit("playback-state-changed", &snapshot);
    tauri::async_runtime::spawn(fetch_radio(app, core, epoch, auth_generation, request));
    Ok(snapshot)
}

fn stream_attempt_current(
    playback: &PlaybackManager,
    generation: u64,
    auth_generation: u64,
    current_auth_generation: u64,
) -> bool {
    playback.generation == generation && auth_generation == current_auth_generation
}

#[tauri::command]
pub(crate) async fn play_song(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    video_id: String,
    title: Option<String>,
    artists: Option<String>,
    thumbnail: Option<String>,
    queue_items: Option<Vec<QueueEntryDto>>,
    queue_current_index: Option<usize>,
    queue_source: Option<QueueSourceDto>,
    preserve_queue: Option<bool>,
    expected_generation: Option<u64>,
    artist_id: Option<String>,
    album_id: Option<String>,
    album: Option<String>,
    artist_runs: Option<Vec<crate::HomeArtistRunDto>>,
    queue_entry_id: Option<String>,
    start_paused: Option<bool>,
    shuffle: Option<bool>,
    is_upload: Option<bool>,
    coalesce: Option<bool>,
) -> Result<PlaybackStateDto, CommandError> {
    let trimmed_id = video_id.trim();
    if trimmed_id.is_empty() {
        return Err(CommandError::new(
            "EMPTY_ID",
            "El identificador de la canción no puede estar vacío.",
        ));
    }

    let core = {
        let lock = state.core.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor.")
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new(
                "CORE_NOT_INITIALIZED",
                "El motor de Side B no está listo. Reintentá la inicialización.",
            )
        })?
    };

    let player = {
        let lock = state.player.read().map_err(|_| {
            CommandError::new(
                "LOCK_ERROR",
                "Error de concurrencia al acceder al reproductor.",
            )
        })?;
        lock.clone().ok_or_else(|| {
            let err_guard = state.player_error.read().ok();
            let msg = err_guard
                .as_deref()
                .and_then(|e| e.as_deref())
                .unwrap_or("El reproductor de audio no está listo.");
            CommandError::new("PLAYER_NOT_INITIALIZED", msg)
        })?
    };

    let my_auth_generation = state.auth_generation.load(Ordering::SeqCst);
    let my_gen = {
        let mut pb = state.playback.lock().map_err(|_| {
            CommandError::new(
                "LOCK_ERROR",
                "Error de concurrencia al actualizar reproducción.",
            )
        })?;
        // EOF schedules the next entry off the player event pump. A newer manual
        // selection must win even if that scheduled task starts later.
        if expected_generation.is_some_and(|expected| pb.generation != expected)
            || state.auth_generation.load(Ordering::SeqCst) != my_auth_generation
        {
            return Ok(pb.to_dto());
        }
        if let Some(items) = queue_items {
            let index = queue_current_index.unwrap_or(0);
            if items.get(index).map(|entry| entry.video_id.as_str()) != Some(trimmed_id) {
                return Err(CommandError::new(
                    "QUEUE_TRACK_MISMATCH",
                    "La pista no coincide con la ocurrencia seleccionada.",
                ));
            }
            let source = queue_source.unwrap_or(QueueSourceDto {
                kind: "song".into(),
                id: Some(trimmed_id.into()),
                title: title.clone(),
            });
            if pb.queue.replace(items, index, source).is_none() {
                return Err(CommandError::new(
                    "INVALID_QUEUE",
                    "La posición inicial no pertenece a la cola.",
                ));
            }
            invalidate_queue_owner(&mut pb);
            pb.is_shuffle = shuffle.unwrap_or(false);
            if pb.is_shuffle {
                pb.queue.shuffle_on_start();
            }
        } else if let Some(entry_id) = queue_entry_id.as_deref() {
            pb.queue.select_entry(entry_id).ok_or_else(|| {
                CommandError::new(
                    "QUEUE_ENTRY_NOT_FOUND",
                    "La ocurrencia seleccionada ya no está en la cola.",
                )
            })?;
        } else if let Some(index) = queue_current_index {
            if pb
                .queue
                .items
                .get(index)
                .map(|entry| entry.video_id.as_str())
                != Some(trimmed_id)
            {
                return Err(CommandError::new(
                    "QUEUE_TRACK_MISMATCH",
                    "La pista no coincide con la ocurrencia seleccionada.",
                ));
            }
            pb.queue.select(index).ok_or_else(|| {
                CommandError::new("INVALID_QUEUE_INDEX", "La pista ya no está en la cola.")
            })?;
        } else if preserve_queue != Some(true) {
            let mut entry = QueueEntryDto::with_metadata_and_runs(
                trimmed_id.to_owned(),
                title.clone().unwrap_or_else(|| "Canción".into()),
                artists.clone().unwrap_or_default(),
                thumbnail.clone(),
                None,
                artist_id.clone(),
                album_id.clone(),
                album.clone(),
                artist_runs.unwrap_or_default(),
            );
            entry.is_upload = is_upload.unwrap_or(false);
            let _ = pb.queue.replace(
                vec![entry],
                0,
                QueueSourceDto {
                    kind: "song".into(),
                    id: Some(trimmed_id.into()),
                    title: title.clone(),
                },
            );
            invalidate_queue_owner(&mut pb);
            pb.is_shuffle = false;
        }
        let active_entry = pb.queue.current().ok_or_else(|| {
            CommandError::new("INVALID_QUEUE", "No hay una pista activa en la cola.")
        })?;
        if active_entry.video_id != trimmed_id {
            return Err(CommandError::new(
                "QUEUE_TRACK_MISMATCH",
                "La pista no coincide con la ocurrencia seleccionada.",
            ));
        }
        // Serializar parada y anuncio con la carga de otros play_song. Si se detiene fuera
        // de este cerrojo, una petición anterior puede cargar después de la parada y
        // seguir sonando mientras la nueva todavía se resuelve.
        if player.set_loop_file(pb.is_repeat).is_err() {
            return Err(CommandError::new(
                "REPEAT_FAILED",
                "No se pudo preparar la repetición para esta pista.",
            ));
        }
        player.stop().map_err(|_| {
            CommandError::new("STOP_FAILED", "No se pudo detener la pista anterior.")
        })?;
        if player.clear_playlist().is_err() {
            pb.loaded_generation = None;
            pb.is_playing = false;
            pb.is_loading = false;
            pb.error = Some("No se pudo preparar el reproductor para otra pista.".to_string());
            let _ = app.emit("playback-state-changed", &pb.to_dto());
            return Err(CommandError::new(
                "CLEAR_FAILED",
                "No se pudo preparar el reproductor para otra pista.",
            ));
        }
        pb.generation += 1;
        pb.loaded_generation = None;
        pb.is_loading = true;
        pb.is_playing = false;
        pb.is_ended = false;
        pb.position = 0.0;
        pb.duration = 0.0;
        pb.error = None;
        pb.current_track = Some(PlaybackTrackDto {
            is_upload: active_entry.is_upload || is_upload.unwrap_or(false),
            video_id: trimmed_id.to_string(),
            title: active_entry.title,
            artists: active_entry.artists,
            thumbnail: active_entry.thumbnail,
            duration: None,
            artist_id: active_entry.artist_id,
            album_id: active_entry.album_id,
            album: active_entry.album,
            artist_runs: active_entry.artist_runs,
        });
        pb.eof_waiting = None;
        pb.runtime.pending_next = None;
        let dto = pb.to_dto();
        let _ = app.emit("playback-state-changed", &dto);
        pb.generation
    };

    if coalesce == Some(true) {
        tokio::time::sleep(std::time::Duration::from_millis(180)).await;
    }
    // Cookie validation/replacement and an authenticated upload resolution must
    // never overlap. Recheck the attempt after waiting for this operation lock.
    let _auth_operation = state.auth_operation.lock().await;
    let upload = {
        let pb = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer el reproductor."))?;
        if !stream_attempt_current(
            &pb,
            my_gen,
            my_auth_generation,
            state.auth_generation.load(Ordering::SeqCst),
        ) {
            return Ok(pb.to_dto());
        }
        pb.current_track
            .as_ref()
            .is_some_and(|track| track.is_upload)
    };
    let resolve_res = core.resolve_stream(trimmed_id.to_string(), upload).await;

    let stream_info = match resolve_res {
        Ok(info) => info,
        Err(_) => {
            let mut pb = state.playback.lock().map_err(|_| {
                CommandError::new(
                    "LOCK_ERROR",
                    "Error de concurrencia al actualizar reproducción.",
                )
            })?;
            // Sólo registrar el error si este intento sigue siendo la selección más reciente
            if stream_attempt_current(
                &pb,
                my_gen,
                my_auth_generation,
                state.auth_generation.load(Ordering::SeqCst),
            ) {
                pb.is_loading = false;
                pb.is_playing = false;
                pb.is_ended = false;
                pb.error =
                    Some("No se pudo obtener el flujo de audio para esta pista.".to_string());
                pb.loaded_generation = None;
                let dto = pb.to_dto();
                let _ = app.emit("playback-state-changed", &dto);
            }
            return Err(CommandError::new(
                "STREAM_RESOLVE_FAILED",
                "No se pudo obtener el flujo de audio para esta canción.",
            ));
        }
    };

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new(
            "LOCK_ERROR",
            "Error de concurrencia al actualizar reproducción.",
        )
    })?;
    if !stream_attempt_current(
        &pb,
        my_gen,
        my_auth_generation,
        state.auth_generation.load(Ordering::SeqCst),
    ) {
        return Ok(pb.to_dto());
    }

    let parsed_duration = stream_info
        .duration
        .as_deref()
        .and_then(parse_duration_to_seconds)
        .unwrap_or(0.0);

    let resolved_title = pb
        .current_track
        .as_ref()
        .map(|t| t.title.clone())
        .filter(|title| !title.is_empty() && title != "Canción")
        .or_else(|| stream_info.title.clone())
        .unwrap_or_else(|| "Canción".to_string());
    let resolved_artists = pb
        .current_track
        .as_ref()
        .map(|t| crate::queue::metadata_credit_with_runs(&t.artists, &t.artist_runs))
        .filter(|artists| !artists.is_empty())
        .or_else(|| {
            stream_info
                .artists
                .as_ref()
                .map(|value| crate::queue::metadata_credit(value))
        })
        .unwrap_or_default();
    // La portada de la ocurrencia elegida tiene prioridad; los metadatos del stream
    // pueden pertenecer a una versión/edición distinta del mismo video.
    let resolved_thumbnail = pb
        .current_track
        .as_ref()
        .and_then(|t| t.thumbnail.clone())
        .or_else(|| stream_info.thumbnail.clone());

    // The queue row and the two now-playing surfaces must show the same metadata.
    // A stream response may fill gaps, but it never changes the selected occurrence.
    if let Some(index) = pb.queue.current_index {
        if let Some(entry) = pb.queue.items.get_mut(index) {
            if entry.video_id == trimmed_id {
                let resolved_duration = (parsed_duration > 0.0)
                    .then_some(parsed_duration)
                    .or(entry.duration);
                let changed = entry.title != resolved_title
                    || entry.artists != resolved_artists
                    || entry.thumbnail != resolved_thumbnail
                    || entry.duration != resolved_duration;
                entry.title = resolved_title.clone();
                entry.artists = resolved_artists.clone();
                entry.thumbnail = resolved_thumbnail.clone();
                entry.duration = resolved_duration;
                if changed {
                    pb.queue.revision += 1;
                }
            }
        }
    }

    let artist_id = pb
        .current_track
        .as_ref()
        .and_then(|track| track.artist_id.clone());
    let album_id = pb
        .current_track
        .as_ref()
        .and_then(|track| track.album_id.clone());
    let album = pb
        .current_track
        .as_ref()
        .and_then(|track| track.album.clone());
    let artist_runs = pb
        .current_track
        .as_ref()
        .map(|track| track.artist_runs.clone())
        .unwrap_or_default();
    pb.current_track = Some(PlaybackTrackDto {
        is_upload: upload,
        video_id: trimmed_id.to_string(),
        title: resolved_title,
        artists: resolved_artists,
        thumbnail: resolved_thumbnail,
        duration: if parsed_duration > 0.0 {
            Some(parsed_duration)
        } else {
            None
        },
        artist_id,
        album_id,
        album,
        artist_runs,
    });
    if parsed_duration > 0.0 {
        pb.duration = parsed_duration;
    }

    if start_paused == Some(true) {
        player.pause().map_err(|_| {
            CommandError::new(
                "PAUSE_FAILED",
                "No se pudo conservar la pausa al cambiar de pista.",
            )
        })?;
    }
    let track_gain = stream_info.loudness_db.filter(|gain| gain.is_finite());
    let previous_gain = crate::volume::combined_gain(pb.volume, pb.runtime.exponential_volume, pb.runtime.track_gain);
    if player
        .load(
            &stream_info.stream_url,
            &stream_info.headers,
            crate::volume::combined_gain(pb.volume, pb.runtime.exponential_volume, track_gain),
        )
        .is_err()
    {
        // load applies filters before opening the stream; undo them when loadfile fails.
        let _ = player.set_gain(previous_gain);
        pb.is_loading = false;
        pb.is_playing = false;
        pb.is_ended = false;
        pb.error = Some("Error al cargar la pista en el motor de audio.".to_string());
        pb.loaded_generation = None;
        let dto = pb.to_dto();
        let _ = app.emit("playback-state-changed", &dto);
        return Err(CommandError::new(
            "LOAD_FAILED",
            "Error al cargar la pista en el motor de audio.",
        ));
    }

    pb.runtime.track_gain = track_gain;
    if start_paused != Some(true) && player.play().is_err() {
        pb.is_loading = false;
        pb.is_playing = false;
        pb.is_ended = false;
        pb.error = Some("Error al iniciar reproducción en el motor de audio.".to_string());
        pb.loaded_generation = None;
        let dto = pb.to_dto();
        let _ = app.emit("playback-state-changed", &dto);
        return Err(CommandError::new(
            "PLAY_FAILED",
            "Error al iniciar reproducción en el motor de audio.",
        ));
    }

    // Mantener is_loading = true e is_playing = false hasta recibir el evento real Playing(true).
    // Se activa loaded_generation para que sólo a partir de ahora se procesen eventos del motor para este intento.
    pb.is_loading = start_paused != Some(true);
    pb.is_playing = false;
    pb.is_ended = false;
    pb.error = None;
    pb.loaded_generation = Some(my_gen);
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    drop(pb);
    // Radio may finish before the stream installs current_track. Always start
    // metadata hydration after a successful load as well as after radio; neither
    // request delays audio, and ownership guards reject obsolete responses.
    maybe_hydrate_current_album(app.clone());
    maybe_prefetch_radio(app);
    Ok(dto)
}

async fn start_queue_entry(
    app: tauri::AppHandle,
    entry_id: String,
    expected_generation: u64,
    start_paused: bool,
) -> Result<PlaybackStateDto, CommandError> {
    start_queue_entry_mode(app, entry_id, expected_generation, start_paused, false).await
}

async fn start_queue_entry_mode(
    app: tauri::AppHandle,
    entry_id: String,
    expected_generation: u64,
    start_paused: bool,
    coalesce: bool,
) -> Result<PlaybackStateDto, CommandError> {
    let state = app.state::<AppState>();
    let entry = {
        let playback = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
        if playback.generation != expected_generation {
            return Ok(playback.to_dto());
        }
        playback
            .queue
            .items
            .iter()
            .find(|entry| entry.entry_id == entry_id)
            .cloned()
            .ok_or_else(|| {
                CommandError::new(
                    "QUEUE_ENTRY_NOT_FOUND",
                    "La ocurrencia ya no está en la cola.",
                )
            })?
    };
    play_song(
        app.clone(),
        state,
        entry.video_id,
        Some(entry.title),
        Some(entry.artists),
        entry.thumbnail,
        None,
        None,
        None,
        Some(true),
        Some(expected_generation),
        entry.artist_id,
        entry.album_id,
        entry.album,
        Some(entry.artist_runs),
        Some(entry.entry_id),
        Some(start_paused),
        None,
        Some(entry.is_upload),
        Some(coalesce),
    )
    .await
}

#[tauri::command]
pub(crate) async fn start_song_radio(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    song: SongDto,
) -> Result<PlaybackStateDto, CommandError> {
    if song.video_id.trim().is_empty() {
        return Err(CommandError::new(
            "EMPTY_ID",
            "El identificador de la canción no puede estar vacío.",
        ));
    }
    let seed = song.video_id.trim().to_owned();
    let entry = queue_entry_from_song(song);
    let title = entry.title.clone();
    play_song(
        app,
        state,
        seed.clone(),
        Some(entry.title.clone()),
        Some(entry.artists.clone()),
        entry.thumbnail.clone(),
        Some(vec![entry.clone()]),
        Some(0),
        Some(QueueSourceDto {
            kind: "radio".into(),
            id: Some(seed),
            title: Some(title),
        }),
        Some(true),
        None,
        entry.artist_id,
        entry.album_id,
        entry.album,
        None,
        None,
        None,
        None,
        Some(entry.is_upload),
        None,
    )
    .await
}

#[tauri::command]
pub(crate) async fn retry_radio(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    {
        let playback = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer el reproductor."))?;
        if playback
            .queue
            .source
            .as_ref()
            .is_none_or(|source| source.kind != "radio")
        {
            return Err(CommandError::new(
                "NO_RADIO_QUEUE",
                "La cola actual no es una radio.",
            ));
        }
        if playback
            .queue
            .radio
            .as_ref()
            .is_none_or(|radio| !radio.can_retry)
        {
            return Err(CommandError::new(
                "RADIO_NOT_RETRYABLE",
                "No hay ningún error de radio para reintentar.",
            ));
        }
    }
    begin_radio_fetch(app, true)
}

#[tauri::command]
pub(crate) fn enqueue_tracks(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    items: Vec<QueueEntryDto>,
    position: String,
) -> Result<PlaybackStateDto, CommandError> {
    let at_next = match position.as_str() {
        "next" => true,
        "end" => false,
        _ => {
            return Err(CommandError::new(
                "INVALID_QUEUE_POSITION",
                "La posición debe ser next o end.",
            ))
        }
    };
    if items.iter().any(|item| item.video_id.trim().is_empty()) {
        return Err(CommandError::new(
            "INVALID_QUEUE_TRACK",
            "La cola contiene una canción sin identificador.",
        ));
    }
    let snapshot = {
        let mut playback = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo actualizar la cola."))?;
        let items = items
            .into_iter()
            .map(|mut item| {
                item.video_id = item.video_id.trim().to_owned();
                item
            })
            .collect();
        playback.queue.enqueue(items, at_next);
        playback.to_dto()
    };
    let _ = app.emit("playback-state-changed", &snapshot);
    maybe_prefetch_radio(app);
    Ok(snapshot)
}

#[tauri::command]
pub(crate) async fn remove_queue_entry(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    entry_id: String,
) -> Result<PlaybackStateDto, CommandError> {
    let entry_id = entry_id.trim();
    if entry_id.is_empty() {
        return Err(CommandError::new(
            "INVALID_QUEUE_ENTRY",
            "El identificador de ocurrencia no puede estar vacío.",
        ));
    }
    let player = state
        .player
        .read()
        .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo acceder al reproductor."))?
        .clone();
    let (snapshot, next) = {
        let mut playback = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo actualizar la cola."))?;
        let (was_current, selected) = playback.queue.dismiss_entry(entry_id).ok_or_else(|| {
            CommandError::new("QUEUE_ENTRY_NOT_FOUND", "La canción ya no está en la cola.")
        })?;
        if !was_current {
            (playback.to_dto(), None)
        } else if let Some(entry) = selected {
            if let Some(player) = &player {
                let _ = player.stop();
                let _ = player.clear_playlist();
            }
            let (expected_generation, start_paused) =
                prepare_dismissed_current(&mut playback, &entry);
            (
                playback.to_dto(),
                Some((entry.entry_id, expected_generation, start_paused)),
            )
        } else {
            invalidate_queue_owner(&mut playback);
            if let Some(player) = &player {
                let _ = player.stop();
                let _ = player.clear_playlist();
            }
            playback.generation = playback.generation.wrapping_add(1);
            playback.loaded_generation = None;
            playback.is_playing = false;
            playback.is_loading = false;
            playback.is_ended = false;
            playback.position = 0.0;
            playback.duration = 0.0;
            playback.current_track = None;
            playback.error = None;
            playback.queue = QueueStateDto::default();
            (playback.to_dto(), None)
        }
    };
    let _ = app.emit("playback-state-changed", &snapshot);
    if let Some((entry_id, expected_generation, start_paused)) = next {
        return start_queue_entry(app, entry_id, expected_generation, start_paused).await;
    }
    maybe_prefetch_radio(app);
    Ok(snapshot)
}

fn prepare_dismissed_current(
    playback: &mut crate::PlaybackManager,
    entry: &QueueEntryDto,
) -> (u64, bool) {
    let start_paused = !playback.is_playing && !playback.is_loading && !playback.is_ended;
    playback.generation = playback.generation.wrapping_add(1);
    playback.loaded_generation = None;
    playback.is_loading = true;
    playback.is_playing = false;
    playback.is_ended = false;
    playback.position = 0.0;
    playback.duration = entry.duration.unwrap_or(0.0);
    playback.error = None;
    playback.current_track = Some(PlaybackTrackDto {
        is_upload: entry.is_upload,
        video_id: entry.video_id.clone(),
        title: entry.title.clone(),
        artists: entry.artists.clone(),
        thumbnail: entry.thumbnail.clone(),
        duration: entry.duration,
        artist_id: entry.artist_id.clone(),
        album_id: entry.album_id.clone(),
        album: entry.album.clone(),
        artist_runs: entry.artist_runs.clone(),
    });
    playback.eof_waiting = None;
    (playback.generation, start_paused)
}

#[tauri::command]
pub(crate) fn move_queue_entry(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    entry_id: String,
    before_entry_id: Option<String>,
) -> Result<PlaybackStateDto, CommandError> {
    let entry_id = entry_id.trim();
    let before_entry_id = before_entry_id.as_deref().map(str::trim);
    if entry_id.is_empty() || before_entry_id.is_some_and(str::is_empty) {
        return Err(CommandError::new(
            "INVALID_QUEUE_ENTRY",
            "El identificador de ocurrencia no puede estar vacío.",
        ));
    }
    let (snapshot, changed) = {
        let mut playback = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo actualizar la cola."))?;
        let changed = playback
            .queue
            .move_entry(entry_id, before_entry_id)
            .map_err(|error| match error {
                crate::queue::QueueMoveError::EntryNotFound => {
                    CommandError::new("QUEUE_ENTRY_NOT_FOUND", "La canción ya no está en la cola.")
                }
                crate::queue::QueueMoveError::TargetNotFound => CommandError::new(
                    "QUEUE_TARGET_NOT_FOUND",
                    "La posición de destino ya no está en la cola.",
                ),
            })?;
        (playback.to_dto(), changed)
    };
    // Reordering only changes the list: it must not reload audio or consume its generation.
    if changed {
        let _ = app.emit("playback-state-changed", &snapshot);
        maybe_prefetch_radio(app);
    }
    Ok(snapshot)
}

/// One manual intention can survive a provider fetch; EOF requires its ended attempt.
fn consume_waiting_next(playback: &mut crate::PlaybackManager) -> Option<(String, u64)> {
    let manual = playback.runtime.pending_next.is_some();
    let (generation, epoch) = playback.runtime.pending_next.or(playback.eof_waiting)?;
    if generation != playback.generation
        || epoch != playback.queue_epoch
        || !manual && (!playback.is_ended || playback.loaded_generation.is_some())
    {
        playback.runtime.pending_next = None;
        playback.eof_waiting = None;
        return None;
    }
    let entry = playback.queue.next_or_first(false)?;
    playback.runtime.pending_next = None;
    playback.eof_waiting = None;
    Some((entry.entry_id, generation))
}

pub(crate) fn handle_track_ended(app: tauri::AppHandle) {
    let state = app.state::<AppState>();
    let (snapshot, next) = {
        let Ok(mut playback) = state.playback.lock() else {
            return;
        };
        // Ignore duplicate EOF notifications after the active load has been consumed.
        if playback.loaded_generation.is_none() {
            return;
        }
        let generation = playback.generation;
        playback.is_playing = false;
        playback.is_loading = false;
        playback.is_ended = true;
        playback.position = playback.duration;
        playback.loaded_generation = None;
        let next_entry_id = if playback.is_repeat {
            playback.queue.current().map(|entry| entry.entry_id)
        } else {
            playback
                .queue
                .current_index
                .and_then(|index| index.checked_add(1))
                .and_then(|index| playback.queue.items.get(index))
                .map(|entry| entry.entry_id.clone())
        };
        let next = if let Some(entry_id) = next_entry_id {
            playback.eof_waiting = None;
            Some((entry_id, generation))
        } else if playback
            .runtime
            .source
            .as_ref()
            .is_some_and(|source| source.continuation.is_some() || source.needs_restart)
        {
            playback.eof_waiting = Some((generation, playback.queue_epoch));
            None
        } else if playback
            .queue
            .source
            .as_ref()
            .is_some_and(|source| source.kind == "radio")
            && !playback.radio_exhausted
        {
            playback.eof_waiting = Some((generation, playback.queue_epoch));
            None
        } else {
            playback.eof_waiting = None;
            None
        };
        (playback.to_dto(), next)
    };
    let _ = app.emit("playback-state-changed", &snapshot);
    if let Some((entry_id, generation)) = next {
        tauri::async_runtime::spawn(start_queue_entry(app, entry_id, generation, false));
    } else {
        maybe_prefetch_radio(app);
    }
}

#[tauri::command]
pub(crate) async fn next_track(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    let (next, generation) = {
        let mut playback = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
        let extensible = playback
            .runtime
            .source
            .as_ref()
            .is_some_and(|source| source.continuation.is_some() || source.needs_restart)
            || playback
                .queue
                .source
                .as_ref()
                .is_some_and(|source| source.kind == "radio")
                && !playback.radio_exhausted;
        let at_edge = playback
            .queue
            .current_index
            .is_some_and(|index| index + 1 >= playback.queue.items.len());
        if extensible && at_edge {
            playback.runtime.pending_next = Some((playback.generation, playback.queue_epoch));
            let dto = playback.to_dto();
            drop(playback);
            maybe_prefetch_radio(app);
            return Ok(dto);
        }
        let next = playback
            .queue
            .next_or_first(playback.is_repeat)
            .map(|entry| entry.entry_id);
        (next, playback.generation)
    };
    match next {
        Some(entry_id) => start_queue_entry_mode(app, entry_id, generation, false, true).await,
        None => get_playback_state(state).await,
    }
}

#[tauri::command]
pub(crate) fn set_shuffle(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    enabled: bool,
) -> Result<PlaybackStateDto, CommandError> {
    let snapshot = {
        let mut playback = state.playback.lock().map_err(|_| {
            CommandError::new("LOCK_ERROR", "No se pudo cambiar el modo aleatorio.")
        })?;
        playback.set_shuffle_mode(enabled);
        playback.to_dto()
    };
    let _ = app.emit("playback-state-changed", &snapshot);
    maybe_prefetch_radio(app);
    Ok(snapshot)
}

#[tauri::command]
pub(crate) fn set_repeat(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    enabled: bool,
) -> Result<PlaybackStateDto, CommandError> {
    let player = state
        .player
        .read()
        .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo acceder al reproductor."))?
        .clone()
        .ok_or_else(|| {
            CommandError::new(
                "PLAYER_NOT_INITIALIZED",
                "El reproductor de audio no está listo.",
            )
        })?;
    let snapshot = {
        let mut playback = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo cambiar la repetición."))?;
        player.set_loop_file(enabled).map_err(|_| {
            CommandError::new("REPEAT_FAILED", "No se pudo cambiar el modo de repetición.")
        })?;
        playback.is_repeat = enabled;
        playback.to_dto()
    };
    let _ = app.emit("playback-state-changed", &snapshot);
    Ok(snapshot)
}

#[tauri::command]
pub(crate) async fn previous_track(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    let (target, generation) = {
        let playback = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
        let index = playback.queue.current_index.ok_or_else(|| {
            CommandError::new("EMPTY_QUEUE", "No hay una pista activa en la cola.")
        })?;
        let target = if playback.position > 3.0 || index == 0 {
            index
        } else {
            index - 1
        };
        (
            playback
                .queue
                .items
                .get(target)
                .map(|entry| entry.entry_id.clone()),
            playback.generation,
        )
    };
    let target = target.ok_or_else(|| {
        CommandError::new("INVALID_QUEUE_INDEX", "La pista ya no está en la cola.")
    })?;
    start_queue_entry_mode(app, target, generation, false, true).await
}

fn cancel_waiting_next(playback: &mut PlaybackManager) -> bool {
    // Both owners must be cleared, including when manual Next and EOF overlap.
    let manual = playback.runtime.pending_next.take().is_some();
    let natural = playback.eof_waiting.take().is_some();
    manual || natural
}

#[tauri::command]
pub(crate) async fn pause_playback(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    let player = {
        let lock = state.player.read().map_err(|_| {
            CommandError::new(
                "LOCK_ERROR",
                "Error de concurrencia al acceder al reproductor.",
            )
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new(
                "PLAYER_NOT_INITIALIZED",
                "El reproductor de audio no está listo.",
            )
        })?
    };

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new(
            "LOCK_ERROR",
            "Error de concurrencia al actualizar reproducción.",
        )
    })?;

    let waiting = cancel_waiting_next(&mut pb);
    if waiting && pb.loaded_generation.is_none() && !pb.is_loading {
        pb.is_playing = false;
        let dto = pb.to_dto();
        let _ = app.emit("playback-state-changed", &dto);
        return Ok(dto);
    }
    if pb.is_loading && pb.loaded_generation.is_none() {
        pb.generation = pb.generation.wrapping_add(1);
        pb.is_loading = false;
        pb.is_playing = false;
        pb.runtime.pending_next = None;
        pb.eof_waiting = None;
        let _ = player.pause();
        let dto = pb.to_dto();
        let _ = app.emit("playback-state-changed", &dto);
        return Ok(dto);
    }
    // Bloquear si no hay pista efectivamente cargada, si está cargando, o si ya no está sonando
    if pb.loaded_generation.is_none() || pb.is_loading || !pb.is_playing || player.is_idle() {
        return Err(CommandError::new(
            "NOT_PLAYING",
            "No hay reproducción activa para pausar.",
        ));
    }

    player
        .pause()
        .map_err(|_| CommandError::new("PAUSE_FAILED", "No se pudo pausar la reproducción."))?;

    pb.is_playing = false;
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

#[tauri::command]
pub(crate) async fn resume_playback(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    let restored = {
        let pb = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer el reproductor."))?;
        if pb.loaded_generation.is_none() && !pb.is_loading && pb.current_track.is_some() {
            pb.queue
                .current()
                .map(|entry| (entry.entry_id, pb.generation))
        } else {
            None
        }
    };
    if let Some((entry, generation)) = restored {
        return start_queue_entry(app, entry, generation, false).await;
    }
    let player = {
        let lock = state.player.read().map_err(|_| {
            CommandError::new(
                "LOCK_ERROR",
                "Error de concurrencia al acceder al reproductor.",
            )
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new(
                "PLAYER_NOT_INITIALIZED",
                "El reproductor de audio no está listo.",
            )
        })?
    };

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new(
            "LOCK_ERROR",
            "Error de concurrencia al actualizar reproducción.",
        )
    })?;

    // Bloquear reanudar si no hay pista cargada, si está en carga, si finalizó o si hay error
    if pb.loaded_generation.is_none()
        || pb.is_loading
        || pb.is_ended
        || pb.error.is_some()
        || player.is_idle()
    {
        return Err(CommandError::new(
            "IDLE_PLAYER",
            "La pista ha finalizado, está cargando o no hay reproducción activa para reanudar.",
        ));
    }

    player
        .play()
        .map_err(|_| CommandError::new("RESUME_FAILED", "No se pudo reanudar la reproducción."))?;

    pb.is_playing = true;
    pb.is_ended = false;
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

#[tauri::command]
pub(crate) async fn seek_playback(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    seconds: f64,
) -> Result<PlaybackStateDto, CommandError> {
    if !seconds.is_finite() || seconds < 0.0 {
        return Err(CommandError::new(
            "INVALID_SEEK",
            "La posición de seek debe ser un número finito no negativo.",
        ));
    }

    let player = {
        let lock = state.player.read().map_err(|_| {
            CommandError::new(
                "LOCK_ERROR",
                "Error de concurrencia al acceder al reproductor.",
            )
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new(
                "PLAYER_NOT_INITIALIZED",
                "El reproductor de audio no está listo.",
            )
        })?
    };

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new(
            "LOCK_ERROR",
            "Error de concurrencia al actualizar reproducción.",
        )
    })?;

    // Bloquear seek si no hay pista cargada o está cargando
    if pb.loaded_generation.is_none()
        || pb.is_loading
        || pb.current_track.is_none()
        || player.is_idle()
    {
        return Err(CommandError::new(
            "NOT_READY",
            "No se puede cambiar la posición: no hay pista cargada en reproducción.",
        ));
    }

    player.seek(seconds).map_err(|_| {
        CommandError::new(
            "SEEK_FAILED",
            "No se pudo cambiar la posición de reproducción.",
        )
    })?;

    pb.position = seconds;
    pb.is_ended = false;
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

#[tauri::command]
pub(crate) async fn set_playback_volume(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    volume: f64,
) -> Result<PlaybackStateDto, CommandError> {
    if !volume.is_finite() {
        return Err(CommandError::new(
            "INVALID_VOLUME",
            "El nivel de volumen debe ser un número finito.",
        ));
    }
    let clamped = volume.clamp(0.0, 100.0);

    let player = {
        let lock = state.player.read().map_err(|_| {
            CommandError::new(
                "LOCK_ERROR",
                "Error de concurrencia al acceder al reproductor.",
            )
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new(
                "PLAYER_NOT_INITIALIZED",
                "El reproductor de audio no está listo.",
            )
        })?
    };

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new(
            "LOCK_ERROR",
            "Error de concurrencia al actualizar reproducción.",
        )
    })?;
    let exponential = pb.runtime.exponential_volume;
    let dto = apply_volume_preferences(&mut pb, &player, clamped, exponential)?;
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

// Caller holds playback for both reading old preferences and applying them, also during load.
fn apply_volume_preferences(
    pb: &mut crate::PlaybackManager,
    player: &player::Player,
    volume: f64,
    exponential: bool,
) -> Result<PlaybackStateDto, CommandError> {
    let previous_gain = crate::volume::combined_gain(pb.volume, pb.runtime.exponential_volume, pb.runtime.track_gain);
    let next_gain = crate::volume::combined_gain(volume, exponential, pb.runtime.track_gain);
    // Mute first: removing attenuation before reaching zero could briefly raise the sound.
    // Standard volume changes need no filter rewrite when the gain remains unchanged.
    let set_gain = || if next_gain != previous_gain { player.set_gain(next_gain) } else { Ok(()) };
    let applied = if volume == 0.0 {
        player.set_volume(0).and_then(|_| set_gain())
    } else {
        set_gain().and_then(|_| player.set_volume(volume.round() as i64))
    };
    if applied.is_err() {
        let _ = player.set_gain(previous_gain);
        let _ = player.set_volume(pb.volume.round() as i64);
        return Err(CommandError::new("VOLUME_FAILED", "No se pudo cambiar el volumen."));
    }
    if volume > 0.0 { pb.runtime.last_audible = volume; }
    pb.volume = volume;
    pb.runtime.exponential_volume = exponential;
    Ok(pb.to_dto())
}

#[tauri::command]
pub(crate) fn set_exponential_volume(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    enabled: bool,
) -> Result<PlaybackStateDto, CommandError> {
    let mut pb = state.playback.lock().map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer el volumen."))?;
    let player = state.player.read().ok().and_then(|player| player.clone())
        .ok_or_else(|| CommandError::new("PLAYER_NOT_INITIALIZED", "El reproductor de audio no está listo."))?;
    let volume = pb.volume;
    let dto = apply_volume_preferences(&mut pb, &player, volume, enabled)?;
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

#[tauri::command]
pub(crate) async fn get_playback_state(
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    let pb = state.playback.lock().map_err(|_| {
        CommandError::new(
            "LOCK_ERROR",
            "Error de concurrencia al leer el estado de reproducción.",
        )
    })?;
    Ok(pb.to_dto())
}

#[tauri::command]
pub(crate) async fn stop_playback(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    let player = {
        let lock = state.player.read().map_err(|_| {
            CommandError::new(
                "LOCK_ERROR",
                "Error de concurrencia al acceder al reproductor.",
            )
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new(
                "PLAYER_NOT_INITIALIZED",
                "El reproductor de audio no está listo.",
            )
        })?
    };

    let _ = player.stop();
    let _ = player.clear_playlist();

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new(
            "LOCK_ERROR",
            "Error de concurrencia al actualizar reproducción.",
        )
    })?;
    pb.generation += 1;
    pb.loaded_generation = None;
    pb.is_playing = false;
    pb.is_loading = false;
    pb.is_ended = false;
    pb.position = 0.0;
    pb.duration = 0.0;
    pb.current_track = None;
    pb.error = None;
    invalidate_queue_owner(&mut pb);
    pb.queue = QueueStateDto::default();
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

#[cfg(test)]
mod dismissal_tests {
    use super::*;

    fn missing_album_playback() -> PlaybackManager {
        let mut pb = PlaybackManager::new();
        pb.observed_auth_generation = 9;
        pb.generation = 77;
        pb.loaded_generation = Some(77);
        pb.position = 15.0;
        pb.duration = 180.0;
        pb.is_playing = true;
        let entry = QueueEntryDto::with_metadata(
            "seed".into(),
            "Original".into(),
            "Artist".into(),
            None,
            Some(180.0),
            None,
            Some("MPRE-album".into()),
            None,
        );
        pb.queue.replace(
            vec![entry.clone(), entry.clone()],
            0,
            QueueSourceDto {
                kind: "radio".into(),
                id: Some("seed".into()),
                title: None,
            },
        );
        pb.current_track = Some(PlaybackTrackDto {
            is_upload: false,
            video_id: "seed".into(),
            title: "Original".into(),
            artists: "Artist".into(),
            thumbnail: None,
            duration: Some(180.0),
            artist_id: None,
            album_id: Some("MPRE-album".into()),
            album: None,
            artist_runs: vec![],
        });
        pb
    }

    #[test]
    fn album_detail_hydrates_current_occurrence_without_reloading_or_reordering() {
        let mut pb = missing_album_playback();
        let request = album_metadata_request(&pb, 9).unwrap();
        let queue_before = pb.queue.clone();
        assert!(apply_album_metadata(
            &mut pb,
            &request,
            9,
            "MPRE-album",
            "Blonde",
            true
        ));
        assert_eq!(
            pb.current_track.as_ref().unwrap().album.as_deref(),
            Some("Blonde")
        );
        assert_eq!(pb.queue.current().unwrap().album.as_deref(), Some("Blonde"));
        assert_eq!(
            pb.queue
                .items
                .iter()
                .map(|item| &item.entry_id)
                .collect::<Vec<_>>(),
            queue_before
                .items
                .iter()
                .map(|item| &item.entry_id)
                .collect::<Vec<_>>()
        );
        assert_eq!(pb.queue.current_index, queue_before.current_index);
        assert_eq!(pb.queue.source, queue_before.source);
        assert_eq!(pb.queue.items[1].album, queue_before.items[1].album);
        assert_eq!(pb.queue.revision, queue_before.revision + 1);
        assert_eq!(pb.generation, 77);
        assert_eq!(pb.loaded_generation, Some(77));
        assert_eq!(pb.position, 15.0);
        assert_eq!(pb.duration, 180.0);
        assert!(pb.is_playing);
        assert_eq!(pb.current_track.as_ref().unwrap().title, "Original");
    }

    #[test]
    fn album_detail_preserves_a_canonical_title_that_looks_like_a_statistic() {
        let mut pb = missing_album_playback();
        let request = album_metadata_request(&pb, 9).unwrap();
        assert!(apply_album_metadata(
            &mut pb,
            &request,
            9,
            "MPRE-album",
            "100 Plays",
            true
        ));
        assert_eq!(
            pb.queue.current().unwrap().album.as_deref(),
            Some("100 Plays")
        );
        assert_eq!(
            pb.current_track.as_ref().unwrap().album.as_deref(),
            Some("100 Plays")
        );
        let mut canonical = pb.queue.current().unwrap();
        canonical.normalize_metadata();
        assert_eq!(canonical.album.as_deref(), Some("100 Plays"));
    }

    #[test]
    fn album_lookup_is_available_after_radio_failure_and_captures_its_final_revision() {
        let mut pb = missing_album_playback();
        let stale = album_metadata_request(&pb, 9).unwrap();
        pb.queue.begin_radio();
        pb.queue
            .end_radio(Some("Recommendations unavailable".into()), true);
        assert!(!apply_album_metadata(
            &mut pb,
            &stale,
            9,
            "MPRE-album",
            "Blonde",
            true
        ));
        let fresh = album_metadata_request(&pb, 9).unwrap();
        pb.position = 18.0; // progress is unrelated to metadata ownership/revision
        assert!(apply_album_metadata(
            &mut pb,
            &fresh,
            9,
            "MPRE-album",
            "Blonde",
            true
        ));
        assert_eq!(pb.position, 18.0);
        assert!(pb.queue.radio.as_ref().unwrap().can_retry);
        assert_eq!(
            pb.queue.radio.as_ref().unwrap().error.as_deref(),
            Some("Recommendations unavailable")
        );
    }

    #[test]
    fn album_lookup_remains_available_when_radio_finishes_before_stream_load() {
        let mut pb = missing_album_playback();
        let loaded_track = pb.current_track.take().unwrap();
        pb.queue.begin_radio();
        pb.queue.end_radio(None, false);
        assert!(album_metadata_request(&pb, 9).is_none());
        // A successful stream load installs the active track after the radio
        // completion. Its unconditional hook must now obtain the missing name.
        pb.current_track = Some(loaded_track);
        let request = album_metadata_request(&pb, 9).unwrap();
        assert!(apply_album_metadata_after_queue_update(
            &mut pb,
            &request,
            9,
            "MPRE-album",
            "Blonde",
            true
        ));
        assert_eq!(
            pb.current_track.as_ref().unwrap().album.as_deref(),
            Some("Blonde")
        );
        assert_eq!(pb.queue.current().unwrap().album.as_deref(), Some("Blonde"));
        assert_eq!(pb.loaded_generation, Some(77));
        assert_eq!(pb.position, 15.0);
    }

    #[test]
    fn album_detail_requires_the_requested_destination_and_video_membership() {
        for (id, title, contains_video) in [
            ("MPRE-other", "Other", true),
            ("MPRE-album", "", true),
            ("MPRE-album", "Unrelated", false),
        ] {
            let mut pb = missing_album_playback();
            let before = pb.queue.clone();
            let request = album_metadata_request(&pb, 9).unwrap();
            assert!(!apply_album_metadata(
                &mut pb,
                &request,
                9,
                id,
                title,
                contains_video
            ));
            assert_eq!(pb.queue, before);
            assert!(pb.current_track.as_ref().unwrap().album.is_none());
        }
    }

    #[test]
    fn album_result_revalidates_radio_revision_but_cannot_replace_new_metadata() {
        let mut pb = missing_album_playback();
        let request = album_metadata_request(&pb, 9).unwrap();
        pb.queue.begin_radio();
        pb.queue.end_radio(None, false);
        assert!(apply_album_metadata_after_queue_update(
            &mut pb,
            &request,
            9,
            "MPRE-album",
            "Blonde",
            true
        ));
        let mut pb = missing_album_playback();
        let request = album_metadata_request(&pb, 9).unwrap();
        pb.queue.revision += 1;
        pb.queue.items[0].album = Some("100 Plays".into());
        pb.current_track.as_mut().unwrap().album = Some("100 Plays".into());
        assert!(!apply_album_metadata_after_queue_update(
            &mut pb,
            &request,
            9,
            "MPRE-album",
            "Blonde",
            true
        ));
        assert_eq!(
            pb.current_track.as_ref().unwrap().album.as_deref(),
            Some("100 Plays")
        );
    }

    #[test]
    fn stale_album_metadata_cannot_cross_auth_generation_epoch_revision_or_occurrence() {
        for change in 0..8 {
            let mut pb = missing_album_playback();
            let request = album_metadata_request(&pb, 9).unwrap();
            match change {
                0 => pb.generation += 1,
                1 => pb.queue_epoch += 1,
                2 => pb.queue.revision += 1,
                3 => pb.queue.items[0].entry_id = "replacement-occurrence".into(),
                4 => pb.current_track.as_mut().unwrap().video_id = "other-video".into(),
                5 => pb.queue.items[0].album_id = Some("MPRE-other".into()),
                7 => pb.observed_auth_generation = 8,
                _ => {}
            }
            let before = pb.queue.clone();
            let auth = if change == 6 { 10 } else { 9 };
            assert!(!apply_album_metadata(
                &mut pb,
                &request,
                auth,
                "MPRE-album",
                "Blonde",
                true
            ));
            assert_eq!(pb.queue, before);
            assert!(pb.current_track.as_ref().unwrap().album.is_none());
        }
        let mut old_owner = missing_album_playback();
        old_owner.observed_auth_generation = 8;
        assert!(album_metadata_request(&old_owner, 9).is_none());
    }

    #[test]
    fn legacy_statistic_is_replaced_only_by_verified_detail_and_known_names_need_no_lookup() {
        let mut pb = missing_album_playback();
        pb.queue.items[0].album = Some("337M plays".into());
        pb.current_track.as_mut().unwrap().album = Some("337M plays".into());
        let request = album_metadata_request(&pb, 9).unwrap();
        assert!(!apply_album_metadata(
            &mut pb,
            &request,
            9,
            "MPRE-album",
            "Blonde",
            false
        ));
        assert_eq!(
            pb.current_track.as_ref().unwrap().album.as_deref(),
            Some("337M plays")
        );
        assert!(apply_album_metadata(
            &mut pb,
            &request,
            9,
            "MPRE-album",
            "Blonde",
            true
        ));
        assert!(album_metadata_request(&pb, 9).is_none());
    }

    #[test]
    fn radio_metadata_hydrates_clean_and_legacy_seeds_without_restarting_audio() {
        for old_album in [None, Some("337M plays".to_owned())] {
            let mut pb = PlaybackManager::new();
            pb.generation = 77;
            pb.loaded_generation = Some(77);
            pb.position = 15.0;
            pb.is_playing = true;
            pb.queue.replace(
                vec![QueueEntryDto::new(
                    "seed".into(),
                    "Original title".into(),
                    "Artist".into(),
                    None,
                    Some(180.0),
                )],
                0,
                QueueSourceDto {
                    kind: "radio".into(),
                    id: Some("seed".into()),
                    title: None,
                },
            );
            pb.queue.items[0].album = old_album.clone();
            let id = pb.queue.items[0].entry_id.clone();
            pb.current_track = Some(PlaybackTrackDto {
                is_upload: false,
                video_id: "seed".into(),
                title: "Original title".into(),
                artists: "Song • Artist • 337M plays".into(),
                thumbnail: None,
                duration: Some(180.0),
                artist_id: None,
                album_id: None,
                album: old_album,
                artist_runs: vec![],
            });
            let dirty_runs = vec![
                crate::HomeArtistRunDto {
                    text: "Artist".into(),
                    id: Some("UC-artist".into()),
                },
                crate::HomeArtistRunDto {
                    text: " • ".into(),
                    id: None,
                },
                crate::HomeArtistRunDto {
                    text: "337M".into(),
                    id: None,
                },
                crate::HomeArtistRunDto {
                    text: " plays".into(),
                    id: None,
                },
            ];
            pb.queue.items[0].artist_runs = dirty_runs.clone();
            pb.current_track.as_mut().unwrap().artist_runs = dirty_runs.clone();
            let mut radio = QueueEntryDto::with_metadata(
                "seed".into(),
                "Provider title".into(),
                "Artist".into(),
                None,
                Some(200.0),
                Some("UC-artist".into()),
                Some("MPRE-album".into()),
                Some("Actual Album".into()),
            );
            radio.artist_runs = dirty_runs;
            assert_eq!(merge_radio_metadata(&mut pb, vec![radio]), None);
            let current = pb.current_track.as_ref().unwrap();
            assert_eq!(current.album.as_deref(), Some("Actual Album"));
            assert_eq!(current.album_id.as_deref(), Some("MPRE-album"));
            assert_eq!(current.artists, "Artist");
            assert_eq!(pb.queue.items[0].album, current.album);
            assert_eq!(pb.queue.items[0].artists, current.artists);
            assert_eq!(current.artist_runs.len(), 1);
            assert_eq!(current.artist_runs[0].id.as_deref(), Some("UC-artist"));
            assert_eq!(pb.queue.items[0].artist_runs, current.artist_runs);
            assert_eq!(current.title, "Original title");
            assert_eq!(current.duration, Some(180.0));
            assert_eq!(pb.queue.items[0].entry_id, id);
            assert_eq!(pb.generation, 77);
            assert_eq!(pb.loaded_generation, Some(77));
            assert_eq!(pb.position, 15.0);
            assert!(pb.is_playing);
        }
    }

    #[test]
    fn next_intention_waits_for_suffix_and_is_consumed_once() {
        let mut pb = crate::PlaybackManager::new();
        pb.generation = 5;
        pb.queue_epoch = 7;
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
        pb.runtime.pending_next = Some((5, 7));
        assert!(consume_waiting_next(&mut pb).is_none());
        assert_eq!(pb.runtime.pending_next, Some((5, 7)));
        pb.queue.append_source(
            vec![
                QueueEntryDto::new("b".into(), "B".into(), "".into(), None, None),
                QueueEntryDto::new("c".into(), "C".into(), "".into(), None, None),
            ],
            false,
        );
        let next = consume_waiting_next(&mut pb).unwrap();
        assert_eq!(next.0, pb.queue.items[1].entry_id);
        assert_eq!(next.1, 5);
        assert!(consume_waiting_next(&mut pb).is_none());
        assert_eq!(pb.queue.current_index, Some(0));
        pb.runtime.pending_next = Some((4, 7));
        assert!(consume_waiting_next(&mut pb).is_none());
        assert!(pb.runtime.pending_next.is_none());
        pb.runtime.pending_next = Some((5, 6));
        assert!(consume_waiting_next(&mut pb).is_none());
        assert!(pb.runtime.pending_next.is_none());
    }
    #[test]
    fn authenticated_stream_waiter_rejects_account_and_selection_changes() {
        let mut pb = PlaybackManager::new();
        pb.generation = 7;
        assert!(stream_attempt_current(&pb, 7, 4, 4));
        assert!(!stream_attempt_current(&pb, 7, 4, 5)); // same selection, cookie generation changed
        assert!(!stream_attempt_current(&pb, 6, 4, 4)); // skipped while waiting for auth lock
        pb.generation = 8;
        assert!(!stream_attempt_current(&pb, 7, 4, 4)); // response arrived after a newer selection
    }

    #[test]
    fn pause_cancels_both_overlapping_next_intentions() {
        let mut pb = PlaybackManager::new();
        pb.generation = 5;
        pb.queue_epoch = 7;
        pb.runtime.pending_next = Some((5, 7));
        pb.eof_waiting = Some((5, 7));
        assert!(cancel_waiting_next(&mut pb));
        assert!(pb.runtime.pending_next.is_none());
        assert!(pb.eof_waiting.is_none());
        assert!(consume_waiting_next(&mut pb).is_none());
        assert!(!cancel_waiting_next(&mut pb));
    }

    #[test]
    fn natural_eof_waiter_requires_ended_unloaded_generation() {
        let mut pb = crate::PlaybackManager::new();
        pb.generation = 5;
        pb.queue_epoch = 7;
        pb.queue.replace(
            vec![
                QueueEntryDto::new("a".into(), "A".into(), "".into(), None, None),
                QueueEntryDto::new("b".into(), "B".into(), "".into(), None, None),
            ],
            0,
            QueueSourceDto {
                kind: "radio".into(),
                id: Some("seed".into()),
                title: None,
            },
        );
        pb.eof_waiting = Some((5, 7));
        pb.loaded_generation = Some(5);
        assert!(consume_waiting_next(&mut pb).is_none());
        pb.eof_waiting = Some((5, 7));
        pb.is_ended = true;
        pb.loaded_generation = None;
        assert!(consume_waiting_next(&mut pb).is_some());
        assert!(pb.eof_waiting.is_none());
    }
    #[test]
    fn source_refetch_prefix_compares_duplicate_occurrences_and_provider_order() {
        let prefix = vec!["same".into(), "same".into(), "third".into()];
        assert!(source_prefix_matches(
            ["same", "same", "third", "suffix"].into_iter(),
            &prefix
        ));
        assert!(source_prefix_matches(["same", "same"].into_iter(), &prefix)); // first page still needs continuation
        assert!(!source_prefix_matches(
            ["same", "third", "same", "suffix"].into_iter(),
            &prefix
        ));
        assert!(!source_prefix_matches(
            ["same", "different", "third"].into_iter(),
            &prefix
        ));
    }
    #[test]
    fn active_dismissal_replaces_track_metadata_and_invalidates_old_generation() {
        let source = QueueSourceDto {
            kind: "playlist".into(),
            id: None,
            title: None,
        };
        let mut playback = crate::PlaybackManager::new();
        playback.generation = 8;
        playback.loaded_generation = Some(8);
        playback.position = 42.0;
        let current = QueueEntryDto::new(
            "same".into(),
            "Current".into(),
            "Artist A".into(),
            None,
            None,
        );
        let next = QueueEntryDto::new(
            "same".into(),
            "Next occurrence".into(),
            "Artist B".into(),
            None,
            Some(120.0),
        );
        playback.queue.replace(vec![current, next], 0, source);
        let next = playback.queue.items[1].clone();

        let active_id = playback.queue.current().unwrap().entry_id;
        let (was_current, selected) = playback.queue.dismiss_entry(&active_id).unwrap();
        assert!(was_current);
        let selected = selected.unwrap();
        assert_eq!(selected.entry_id, next.entry_id);
        let old_generation = playback.generation;
        let (expected_generation, start_paused) =
            prepare_dismissed_current(&mut playback, &selected);

        assert!(start_paused);
        assert_eq!(expected_generation, old_generation + 1);
        assert_ne!(expected_generation, old_generation);
        assert_eq!(playback.loaded_generation, None);
        assert!(playback.is_loading);
        assert_eq!(playback.position, 0.0);
        assert_eq!(
            playback.current_track.as_ref().unwrap().title,
            "Next occurrence"
        );
        assert_eq!(playback.current_track.as_ref().unwrap().artists, "Artist B");
        assert_eq!(playback.duration, 120.0);
    }
}

#[tauri::command]
pub(crate) async fn set_playback_muted(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    muted: bool,
) -> Result<PlaybackStateDto, CommandError> {
    let mut pb = state.playback.lock()
        .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer el volumen."))?;
    let volume = if muted {
            0.0
        } else if pb.runtime.last_audible > 0.0 {
            pb.runtime.last_audible
        } else {
            100.0
        };
    let player = state.player.read().ok().and_then(|player| player.clone())
        .ok_or_else(|| CommandError::new("PLAYER_NOT_INITIALIZED", "El reproductor de audio no está listo."))?;
    let exponential = pb.runtime.exponential_volume;
    let dto = apply_volume_preferences(&mut pb, &player, volume, exponential)?;
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

#[tauri::command]
pub(crate) fn begin_queue_source(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    kind: String,
    id: Option<String>,
    continuation: Option<String>,
    expected_generation: u64,
) -> Result<PlaybackStateDto, CommandError> {
    if kind != "playlist" && kind != "library" {
        return Err(CommandError::new(
            "INVALID_SOURCE",
            "La fuente progresiva no es válida.",
        ));
    }
    let snapshot = {
        let mut pb = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
        if pb.generation != expected_generation {
            return Ok(pb.to_dto());
        }
        if pb
            .queue
            .source
            .as_ref()
            .is_none_or(|source| source.kind != kind || source.id != id)
        {
            return Err(CommandError::new(
                "SOURCE_MISMATCH",
                "La fuente ya no pertenece a esta cola.",
            ));
        }
        let loaded_prefix = pb.queue.source_prefix();
        pb.runtime.source = Some(crate::playback_runtime::ProgressiveSource {
            kind,
            id,
            continuation,
            loading: false,
            error: false,
            needs_restart: false,
            loaded_prefix,
            consumed_continuations: Default::default(),
        });
        pb.to_dto()
    };
    fetch_source_background(app);
    Ok(snapshot)
}
#[tauri::command]
pub(crate) fn retry_queue_source(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    {
        let mut pb = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
        if let Some(source) = pb.runtime.source.as_mut() {
            source.error = false;
        }
    }
    fetch_source_background(app);
    let pb = state
        .playback
        .lock()
        .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
    Ok(pb.to_dto())
}
fn source_prefix_matches<'a>(items: impl Iterator<Item = &'a str>, prefix: &[String]) -> bool {
    items
        .take(prefix.len())
        .zip(prefix)
        .all(|(id, expected)| id == expected)
}
async fn refresh_source_prefix(
    core: std::sync::Arc<sideb_core::SideBCore>,
    source: &crate::playback_runtime::ProgressiveSource,
) -> Result<sideb_core::PlaylistContinuationRecord, ()> {
    let mut page = if source.kind == "library" {
        core.get_library_songs().await.map_err(|_| ())?
    } else {
        let playlist = core
            .get_playlist(source.id.clone().ok_or(())?)
            .await
            .map_err(|_| ())?;
        sideb_core::PlaylistContinuationRecord {
            items: playlist.items,
            continuation: playlist.continuation,
        }
    };
    let mut seen = std::collections::HashSet::new();
    loop {
        if !source_prefix_matches(
            page.items.iter().map(|item| item.video_id.as_str()),
            &source.loaded_prefix,
        ) {
            return Err(());
        }
        if page.items.len() >= source.loaded_prefix.len() {
            page.items.drain(..source.loaded_prefix.len());
            return Ok(page);
        }
        let token = page.continuation.take().ok_or(())?;
        if !seen.insert(token.clone()) {
            return Err(());
        }
        let next = core
            .get_playlist_continuation(token)
            .await
            .map_err(|_| ())?;
        page.items.extend(next.items);
        page.continuation = next.continuation;
    }
}
fn fetch_source_background(app: tauri::AppHandle) {
    let state = app.state::<AppState>();
    let auth_generation = state.auth_generation.load(Ordering::SeqCst);
    let request = {
        let Ok(mut pb) = state.playback.lock() else {
            return;
        };
        let epoch = pb.queue_epoch;
        let Some(source) = pb.runtime.source.as_mut() else {
            return;
        };
        if source.loading || source.error {
            return;
        }
        if source.continuation.is_none() && !source.needs_restart {
            return;
        }
        source.loading = true;
        (epoch, source.clone())
    };
    if let Ok(pb) = state.playback.lock() {
        let _ = app.emit("playback-state-changed", pb.to_dto());
    }
    tauri::async_runtime::spawn(async move {
        let state = app.state::<AppState>();
        let fetched = {
            let _operation = state.auth_operation.lock().await;
            if state.auth_generation.load(Ordering::SeqCst) != auth_generation {
                return;
            }
            let core = state.core.read().ok().and_then(|core| core.clone());
            if let Some(core) = core {
                if request.1.needs_restart {
                    refresh_source_prefix(core, &request.1).await
                } else {
                    core.get_playlist_continuation(
                        request.1.continuation.clone().unwrap_or_default(),
                    )
                    .await
                    .map_err(|_| ())
                }
            } else {
                Err(())
            }
        };
        let mut next = None;
        let snapshot = {
            let Ok(mut pb) = state.playback.lock() else {
                return;
            };
            if pb.queue_epoch != request.0
                || state.auth_generation.load(Ordering::SeqCst) != auth_generation
            {
                return;
            }
            if pb.runtime.source.as_ref().is_none_or(|source| {
                source.continuation != request.1.continuation
                    || source.kind != request.1.kind
                    || source.id != request.1.id
                    || source.needs_restart != request.1.needs_restart
            }) {
                return;
            }
            let fetched = fetched.and_then(|page| {
                let source = pb.runtime.source.as_mut().ok_or(())?;
                source.advance_continuation(page.continuation.clone())?;
                Ok(page)
            });
            match fetched {
                Ok(page) => {
                    if let Some(source) = pb.runtime.source.as_mut() {
                        source
                            .loaded_prefix
                            .extend(page.items.iter().map(|entry| entry.video_id.clone()));
                    }
                    let shuffled = pb.is_shuffle;
                    pb.queue.append_source(
                        page.items
                            .into_iter()
                            .map(queue_entry_from_record)
                            .collect(),
                        shuffled,
                    );
                    if let Some(source) = pb.runtime.source.as_mut() {
                        source.loading = false;
                        source.error = false;
                        source.needs_restart = false;
                    }
                    next = consume_waiting_next(&mut pb);
                    if next.is_none()
                        && pb.runtime.source.as_ref().is_some_and(|source| {
                            source.continuation.is_none() && !source.needs_restart
                        })
                    {
                        pb.runtime.pending_next = None;
                        pb.eof_waiting = None;
                    }
                }
                Err(_) => {
                    if let Some(source) = pb.runtime.source.as_mut() {
                        source.loading = false;
                        source.error = true;
                    }
                }
            }
            pb.to_dto()
        };
        let _ = app.emit("playback-state-changed", snapshot);
        if let Some((entry, generation)) = next {
            let _ = start_queue_entry(app.clone(), entry, generation, false).await;
        }
        fetch_source_background(app);
    });
}
#[tauri::command]
pub(crate) async fn start_source_radio(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    items: Vec<QueueEntryDto>,
    source: QueueSourceDto,
    playlist_id: String,
) -> Result<PlaybackStateDto, CommandError> {
    let Some(entry) = items.first().cloned() else {
        return Err(CommandError::new(
            "EMPTY_RADIO",
            "La radio no contiene canciones.",
        ));
    };
    if playlist_id.trim().is_empty() {
        return Err(CommandError::new(
            "EMPTY_RADIO",
            "La radio no tiene endpoint.",
        ));
    }
    // Start using the provider's radio page, retaining the collection's actual radio endpoint.
    let auth_generation = state.auth_generation.load(Ordering::SeqCst);
    let generation = state
        .playback
        .lock()
        .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?
        .generation;
    play_song(
        app.clone(),
        state.clone(),
        entry.video_id.clone(),
        Some(entry.title),
        Some(entry.artists),
        entry.thumbnail,
        Some(items),
        Some(0),
        Some(QueueSourceDto {
            kind: "radio-source".into(),
            id: source.id,
            title: source.title,
        }),
        Some(false),
        Some(generation),
        entry.artist_id,
        entry.album_id,
        entry.album,
        None,
        None,
        None,
        None,
        Some(entry.is_upload),
        None,
    )
    .await?;
    let snapshot = {
        let mut pb = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
        if pb.generation != generation.wrapping_add(1)
            || state.auth_generation.load(Ordering::SeqCst) != auth_generation
        {
            return Ok(pb.to_dto());
        }
        if let Some(source) = pb.queue.source.as_mut() {
            source.kind = "radio".into();
        }
        pb.queue.revision += 1;
        pb.radio_playlist_id = Some(playlist_id);
        pb.radio_cursor_video_id = pb.queue.items.last().map(|entry| entry.video_id.clone());
        pb.to_dto()
    };
    let _ = app.emit("playback-state-changed", &snapshot);
    maybe_prefetch_radio(app);
    Ok(snapshot)
}
#[tauri::command]
pub(crate) fn filter_disliked_recommendations(
    state: tauri::State<'_, AppState>,
    app: tauri::AppHandle,
    video_id: String,
    expected_generation: u64,
) -> Result<PlaybackStateDto, CommandError> {
    let mut pb = state
        .playback
        .lock()
        .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
    if pb.generation != expected_generation {
        return Ok(pb.to_dto());
    }
    pb.runtime.disliked.insert(video_id.clone());
    // Explicit/manual occurrences are retained; the caller dismisses the selected entry by entryId.
    if pb
        .queue
        .source
        .as_ref()
        .is_some_and(|source| source.kind == "radio")
    {
        pb.queue.filter_radio_recommendations(&video_id);
    }
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}
