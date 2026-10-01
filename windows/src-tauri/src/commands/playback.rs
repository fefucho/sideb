use crate::queue::{QueueEntryDto, QueueSourceDto, QueueStateDto};
use crate::{
    invalidate_queue_owner, AppState, CommandError, PlaybackStateDto, PlaybackTrackDto, SongDto,
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
    QueueEntryDto::with_metadata_and_runs(
        song.video_id,
        song.title,
        song.artists,
        song.thumbnail,
        song.duration.as_deref().and_then(parse_duration_to_seconds),
        song.artist_id,
        song.album_id,
        song.album,
        song.artist_runs,
    )
}

fn queue_entry_from_record(song: sideb_core::SongItemRecord) -> QueueEntryDto {
    QueueEntryDto::with_metadata_and_runs(
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
    )
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
                        .collect::<Vec<_>>();
                    let cursor = playback.queue.merge_radio(recommendations);
                    let current_entry = playback.queue.current();
                    if let (Some(current_track), Some(current_entry)) =
                        (playback.current_track.as_mut(), current_entry.as_ref())
                    {
                        current_track.enrich_missing_metadata(current_entry);
                    }
                    if cursor.is_none() {
                        playback.radio_exhausted = true;
                        playback.queue.end_radio(None, false);
                        playback.eof_waiting = None;
                    } else {
                        playback.radio_exhausted = false;
                        playback.radio_cursor_video_id = cursor;
                        playback.queue.end_radio(None, false);
                        if let Some((expected_generation, expected_epoch)) = playback.eof_waiting {
                            if expected_epoch == playback.queue_epoch
                                && expected_generation == playback.generation
                                && playback.is_ended
                                && playback.loaded_generation.is_none()
                            {
                                let next_entry_id = playback
                                    .queue
                                    .current_index
                                    .and_then(|index| index.checked_add(1))
                                    .and_then(|index| playback.queue.items.get(index))
                                    .map(|entry| entry.entry_id.clone());
                                if let Some(entry_id) = next_entry_id {
                                    playback.eof_waiting = None;
                                    next_to_play = Some((entry_id, expected_generation));
                                }
                            } else {
                                playback.eof_waiting = None;
                            }
                        }
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
    maybe_prefetch_radio(app);
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

    let my_gen = {
        let mut pb = state.playback.lock().map_err(|_| {
            CommandError::new(
                "LOCK_ERROR",
                "Error de concurrencia al actualizar reproducción.",
            )
        })?;
        // EOF schedules the next entry off the player event pump. A newer manual
        // selection must win even if that scheduled task starts later.
        if expected_generation.is_some_and(|expected| pb.generation != expected) {
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
            let entry = QueueEntryDto::with_metadata_and_runs(
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
        let dto = pb.to_dto();
        let _ = app.emit("playback-state-changed", &dto);
        pb.generation
    };

    let resolve_res = core.resolve_stream(trimmed_id.to_string(), false).await;

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
            if pb.generation == my_gen {
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
    if pb.generation != my_gen {
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
        .map(|t| t.artists.clone())
        .filter(|artists| !artists.is_empty())
        .or_else(|| stream_info.artists.clone())
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
            CommandError::new("PAUSE_FAILED", "No se pudo conservar la pausa al cambiar de pista.")
        })?;
    }
    if player
        .load(
            &stream_info.stream_url,
            &stream_info.headers,
            stream_info.loudness_db,
        )
        .is_err()
    {
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
    maybe_prefetch_radio(app);
    Ok(dto)
}

async fn start_queue_entry(
    app: tauri::AppHandle,
    entry_id: String,
    expected_generation: u64,
    start_paused: bool,
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
    let player = state.player.read().map_err(|_| {
        CommandError::new("LOCK_ERROR", "No se pudo acceder al reproductor.")
    })?.clone();
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
            let (expected_generation, start_paused) = prepare_dismissed_current(&mut playback, &entry);
            (playback.to_dto(), Some((entry.entry_id, expected_generation, start_paused)))
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

fn prepare_dismissed_current(playback: &mut crate::PlaybackManager, entry: &QueueEntryDto) -> (u64, bool) {
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
        return Err(CommandError::new("INVALID_QUEUE_ENTRY", "El identificador de ocurrencia no puede estar vacío."));
    }
    let (snapshot, changed) = {
        let mut playback = state.playback.lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo actualizar la cola."))?;
        let changed = playback.queue.move_entry(entry_id, before_entry_id).map_err(|error| {
            match error {
                crate::queue::QueueMoveError::EntryNotFound => CommandError::new("QUEUE_ENTRY_NOT_FOUND", "La canción ya no está en la cola."),
                crate::queue::QueueMoveError::TargetNotFound => CommandError::new("QUEUE_TARGET_NOT_FOUND", "La posición de destino ya no está en la cola."),
            }
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
        let playback = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
        let next = playback
            .queue
            .next_or_first(playback.is_repeat)
            .map(|entry| entry.entry_id);
        (next, playback.generation)
    };
    match next {
        Some(entry_id) => start_queue_entry(app, entry_id, generation, false).await,
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
        let mut playback = state
            .playback
            .lock()
            .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo cambiar el modo aleatorio."))?;
        if enabled && !playback.is_shuffle {
            playback.queue.shuffle_after_current();
        }
        playback.is_shuffle = enabled;
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
            CommandError::new("PLAYER_NOT_INITIALIZED", "El reproductor de audio no está listo.")
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
    start_queue_entry(app, target, generation, false).await
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

    player
        .set_volume(clamped.round() as i64)
        .map_err(|_| CommandError::new("VOLUME_FAILED", "No se pudo cambiar el volumen."))?;

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new(
            "LOCK_ERROR",
            "Error de concurrencia al actualizar reproducción.",
        )
    })?;
    pb.volume = clamped;
    let dto = pb.to_dto();
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
    pb.queue = QueueStateDto::default();
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

#[cfg(test)]
mod dismissal_tests {
    use super::*;

    #[test]
    fn active_dismissal_replaces_track_metadata_and_invalidates_old_generation() {
        let source = QueueSourceDto { kind: "playlist".into(), id: None, title: None };
        let mut playback = crate::PlaybackManager::new();
        playback.generation = 8;
        playback.loaded_generation = Some(8);
        playback.position = 42.0;
        let current = QueueEntryDto::new("same".into(), "Current".into(), "Artist A".into(), None, None);
        let next = QueueEntryDto::new("same".into(), "Next occurrence".into(), "Artist B".into(), None, Some(120.0));
        playback.queue.replace(vec![current, next], 0, source);
        let next = playback.queue.items[1].clone();

        let active_id = playback.queue.current().unwrap().entry_id;
        let (was_current, selected) = playback.queue.dismiss_entry(&active_id).unwrap();
        assert!(was_current);
        let selected = selected.unwrap();
        assert_eq!(selected.entry_id, next.entry_id);
        let old_generation = playback.generation;
        let (expected_generation, start_paused) = prepare_dismissed_current(&mut playback, &selected);

        assert!(start_paused);
        assert_eq!(expected_generation, old_generation + 1);
        assert_ne!(expected_generation, old_generation);
        assert_eq!(playback.loaded_generation, None);
        assert!(playback.is_loading);
        assert_eq!(playback.position, 0.0);
        assert_eq!(playback.current_track.as_ref().unwrap().title, "Next occurrence");
        assert_eq!(playback.current_track.as_ref().unwrap().artists, "Artist B");
        assert_eq!(playback.duration, 120.0);
    }
}
