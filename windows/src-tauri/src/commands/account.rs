use crate::{AppState, BrowseCardDto, CommandError, HistoryGroupDto, PlaylistContinuationDto};
use std::sync::atomic::Ordering;
use std::sync::Arc;

pub(crate) fn account_core(
    state: &AppState,
    generation: u64,
) -> Result<Arc<sideb_core::SideBCore>, CommandError> {
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    let ready = state.auth.read().map(|a| a.state == "ready").map_err(|_| {
        CommandError::new(
            "AUTH_STATE_ERROR",
            "No se pudo comprobar el estado de la sesión.",
        )
    })?;
    if !ready {
        return Err(CommandError::new(
            "AUTH_REQUIRED",
            "Iniciá sesión para acceder a tu biblioteca.",
        ));
    }
    state
        .core
        .read()
        .map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?
        .clone()
        .ok_or_else(|| {
            CommandError::new(
                "CORE_NOT_INITIALIZED",
                "El motor de Side B no está listo. Reintentá la inicialización.",
            )
        })
}

fn canonical_playlist_id(id: &str) -> Result<String, CommandError> {
    let id = id.trim();
    if id.is_empty() {
        return Err(CommandError::new(
            "INVALID_PLAYLIST_ID",
            "El identificador de playlist no puede estar vacío.",
        ));
    }
    let unprefixed = id.strip_prefix("VL").unwrap_or(id);
    if matches!(unprefixed, "LM" | "VLLM") {
        return Err(CommandError::new(
            "PROTECTED_PLAYLIST",
            "Me Gusta se modifica valorando la canción.",
        ));
    }
    if unprefixed.starts_with("RD") {
        return Err(CommandError::new(
            "PROTECTED_PLAYLIST",
            "La radio dinámica no se puede modificar.",
        ));
    }
    Ok(unprefixed.to_owned())
}

async fn owned_playlist(
    core: &sideb_core::SideBCore,
    playlist_id: &str,
    require_sort_editable: bool,
) -> Result<sideb_core::PlaylistDetailRecord, CommandError> {
    let playlist = core
        .get_playlist(playlist_id.to_owned())
        .await
        .map_err(|_| {
            CommandError::new(
                "PLAYLIST_LOOKUP_FAILED",
                "No se pudo comprobar la playlist.",
            )
        })?;
    if !playlist.owned {
        return Err(CommandError::new(
            "PLAYLIST_NOT_OWNED",
            "Sólo se pueden modificar playlists propias.",
        ));
    }
    if require_sort_editable && !playlist.sort_editable {
        return Err(CommandError::new(
            "PLAYLIST_SORT_NOT_EDITABLE",
            "Esta playlist no permite cambiar el orden.",
        ));
    }
    Ok(playlist)
}

fn check_operation_generation(state: &AppState, generation: u64) -> Result<(), CommandError> {
    if state.auth_generation.load(Ordering::SeqCst) == generation {
        Ok(())
    } else {
        Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ))
    }
}

#[tauri::command]
pub(crate) async fn get_library_playlists(
    state: tauri::State<'_, AppState>,
) -> Result<Vec<BrowseCardDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let result = core
        .get_library_playlists()
        .await
        .map(|v| v.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("LIBRARY_FAILED", "No se pudieron cargar tus playlists."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn get_library_albums(
    state: tauri::State<'_, AppState>,
) -> Result<Vec<BrowseCardDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let result = core
        .get_library_albums()
        .await
        .map(|v| v.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("LIBRARY_FAILED", "No se pudieron cargar tus álbumes."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn get_library_artists(
    state: tauri::State<'_, AppState>,
) -> Result<Vec<BrowseCardDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let result = core
        .get_library_artists()
        .await
        .map(|v| v.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("LIBRARY_FAILED", "No se pudieron cargar tus artistas."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn get_library_songs(
    state: tauri::State<'_, AppState>,
) -> Result<PlaylistContinuationDto, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let result = core
        .get_library_songs()
        .await
        .map(PlaylistContinuationDto::from)
        .map_err(|_| CommandError::new("LIBRARY_FAILED", "No se pudieron cargar tus canciones."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn get_playlist_continuation(
    state: tauri::State<'_, AppState>,
    token: String,
) -> Result<PlaylistContinuationDto, CommandError> {
    let token = token.trim();
    if token.is_empty() {
        return Err(CommandError::new(
            "INVALID_TOKEN",
            "El token de continuación no puede estar vacío.",
        ));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    let core = state
        .core
        .read()
        .map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?
        .clone()
        .ok_or_else(|| {
            CommandError::new(
                "CORE_NOT_INITIALIZED",
                "El motor de Side B no está listo. Reintentá la inicialización.",
            )
        })?;
    let result = core
        .get_playlist_continuation(token.to_owned())
        .await
        .map(PlaylistContinuationDto::from)
        .map_err(|_| {
            CommandError::new(
                "CONTINUATION_FAILED",
                "No se pudieron cargar más canciones.",
            )
        })?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn get_history(
    state: tauri::State<'_, AppState>,
) -> Result<Vec<HistoryGroupDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    let core = state
        .core
        .read()
        .map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?
        .clone()
        .ok_or_else(|| {
            CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo.")
        })?;
    let result = core
        .get_history()
        .await
        .map(|v| v.into_iter().map(HistoryGroupDto::from).collect())
        .map_err(|_| CommandError::new("HISTORY_FAILED", "No se pudo cargar el historial."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn rate_song(
    state: tauri::State<'_, AppState>,
    video_id: String,
    rating: String,
) -> Result<(), CommandError> {
    let id = video_id.trim();
    if id.is_empty() {
        return Err(CommandError::new(
            "INVALID_ID",
            "El identificador de canción no puede estar vacío.",
        ));
    }
    let rating = rating.trim().to_ascii_uppercase();
    if !matches!(rating.as_str(), "LIKE" | "DISLIKE" | "INDIFFERENT") {
        return Err(CommandError::new(
            "INVALID_RATING",
            "La valoración no es válida.",
        ));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    core.rate_song(id.to_owned(), rating)
        .await
        .map_err(|_| CommandError::new("RATE_FAILED", "No se pudo actualizar Me Gusta."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    Ok(())
}

#[tauri::command]
pub(crate) async fn apply_song_library_action(
    state: tauri::State<'_, AppState>,
    token: String,
) -> Result<(), CommandError> {
    let token = token.trim();
    if token.is_empty() {
        return Err(CommandError::new(
            "INVALID_ACTION",
            "La acción de biblioteca no es válida.",
        ));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    core.apply_song_library_action(token.to_owned())
        .await
        .map_err(|_| {
            CommandError::new(
                "LIBRARY_ACTION_FAILED",
                "No se pudo actualizar la biblioteca de la canción.",
            )
        })?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    Ok(())
}

#[tauri::command]
pub(crate) async fn create_playlist(
    state: tauri::State<'_, AppState>,
    title: String,
    description: String,
    privacy: Option<String>,
) -> Result<String, CommandError> {
    let title = title.trim();
    let description = description.trim();
    if title.is_empty() || title.len() > 150 || title.contains(['<', '>']) {
        return Err(CommandError::new(
            "INVALID_TITLE",
            "El nombre de la playlist debe tener entre 1 y 150 caracteres válidos.",
        ));
    }
    if description.len() > 5000 {
        return Err(CommandError::new(
            "INVALID_DESCRIPTION",
            "La descripción es demasiado larga.",
        ));
    }
    let privacy = privacy
        .unwrap_or_else(|| "PRIVATE".into())
        .trim()
        .to_ascii_uppercase();
    if !matches!(privacy.as_str(), "PRIVATE" | "UNLISTED" | "PUBLIC") {
        return Err(CommandError::new(
            "INVALID_PRIVACY",
            "La privacidad de la playlist no es válida.",
        ));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let id = core
        .create_playlist(title.to_owned(), description.to_owned(), privacy)
        .await
        .map_err(|_| {
            CommandError::new("PLAYLIST_CREATE_FAILED", "No se pudo crear la playlist.")
        })?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    Ok(id)
}

#[tauri::command]
pub(crate) async fn edit_playlist_details(
    state: tauri::State<'_, AppState>,
    playlist_id: String,
    name: String,
    description: String,
    privacy: String,
) -> Result<(), CommandError> {
    let name = name.trim();
    let description = description.trim();
    let privacy = privacy.trim().to_ascii_uppercase();
    if name.is_empty() || name.len() > 150 || name.contains(['<', '>']) {
        return Err(CommandError::new(
            "INVALID_TITLE",
            "El nombre debe tener entre 1 y 150 caracteres válidos.",
        ));
    }
    if description.len() > 5000 {
        return Err(CommandError::new(
            "INVALID_DESCRIPTION",
            "La descripción es demasiado larga.",
        ));
    }
    if !matches!(privacy.as_str(), "PRIVATE" | "UNLISTED" | "PUBLIC") {
        return Err(CommandError::new(
            "INVALID_PRIVACY",
            "La privacidad de la playlist no es válida.",
        ));
    }
    let playlist_id = canonical_playlist_id(&playlist_id)?;
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    owned_playlist(&core, &playlist_id, false).await?;
    check_operation_generation(&state, generation)?;
    core.edit_playlist_details(
        playlist_id,
        Some(name.to_owned()),
        Some(description.to_owned()),
        Some(privacy),
    )
    .await
    .map_err(|_| {
        CommandError::new(
            "PLAYLIST_EDIT_FAILED",
            "No se pudieron guardar los cambios de la playlist.",
        )
    })?;
    check_operation_generation(&state, generation)
}

#[tauri::command]
pub(crate) async fn set_playlist_sort(
    state: tauri::State<'_, AppState>,
    playlist_id: String,
    sort: String,
) -> Result<(), CommandError> {
    let sort = sort.trim().to_ascii_lowercase();
    if !matches!(
        sort.as_str(),
        "default" | "newest" | "oldest" | "title" | "artist" | "album"
    ) {
        return Err(CommandError::new(
            "INVALID_PLAYLIST_SORT",
            "El orden solicitado no es válido.",
        ));
    }
    let playlist_id = canonical_playlist_id(&playlist_id)?;
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    owned_playlist(&core, &playlist_id, true).await?;
    check_operation_generation(&state, generation)?;
    core.set_playlist_sort(playlist_id, sort)
        .await
        .map_err(|_| {
            CommandError::new(
                "PLAYLIST_SORT_FAILED",
                "No se pudo cambiar el orden de la playlist.",
            )
        })?;
    check_operation_generation(&state, generation)
}

#[tauri::command]
pub(crate) async fn delete_playlist(
    state: tauri::State<'_, AppState>,
    playlist_id: String,
) -> Result<(), CommandError> {
    let playlist_id = canonical_playlist_id(&playlist_id)?;
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    owned_playlist(&core, &playlist_id, false).await?;
    check_operation_generation(&state, generation)?;
    core.delete_playlist(playlist_id).await.map_err(|_| {
        CommandError::new("PLAYLIST_DELETE_FAILED", "No se pudo eliminar la playlist.")
    })?;
    check_operation_generation(&state, generation)
}

#[tauri::command]
pub(crate) async fn add_to_playlist(
    state: tauri::State<'_, AppState>,
    playlist_id: String,
    video_id: String,
) -> Result<(), CommandError> {
    let playlist_id = canonical_playlist_id(&playlist_id)?;
    let video_id = video_id.trim();
    if video_id.is_empty() {
        return Err(CommandError::new(
            "INVALID_VIDEO_ID",
            "El identificador de la canción no puede estar vacío.",
        ));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    owned_playlist(&core, &playlist_id, false).await?;
    check_operation_generation(&state, generation)?;
    core.add_to_playlist(playlist_id, video_id.to_owned())
        .await
        .map_err(|_| {
            CommandError::new(
                "PLAYLIST_ADD_FAILED",
                "No se pudo agregar la canción a la playlist.",
            )
        })?;
    check_operation_generation(&state, generation)
}

#[tauri::command]
pub(crate) async fn remove_from_playlist(
    state: tauri::State<'_, AppState>,
    playlist_id: String,
    video_id: String,
    set_video_id: String,
) -> Result<(), CommandError> {
    let playlist_id = canonical_playlist_id(&playlist_id)?;
    let video_id = video_id.trim();
    let set_video_id = set_video_id.trim();
    if video_id.is_empty() || set_video_id.is_empty() {
        return Err(CommandError::new(
            "INVALID_PLAYLIST_ENTRY",
            "La ocurrencia de playlist no es válida.",
        ));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    owned_playlist(&core, &playlist_id, false).await?;
    check_operation_generation(&state, generation)?;
    core.remove_from_playlist(playlist_id, video_id.to_owned(), set_video_id.to_owned())
        .await
        .map_err(|_| {
            CommandError::new(
                "PLAYLIST_REMOVE_FAILED",
                "No se pudo quitar la canción de la playlist.",
            )
        })?;
    check_operation_generation(&state, generation)
}

#[tauri::command]
pub(crate) async fn move_playlist_track(
    state: tauri::State<'_, AppState>,
    playlist_id: String,
    set_video_id: String,
    successor_set_video_id: Option<String>,
) -> Result<(), CommandError> {
    let playlist_id = canonical_playlist_id(&playlist_id)?;
    let set_video_id = set_video_id.trim();
    let successor_set_video_id = successor_set_video_id
        .map(|id| id.trim().to_owned())
        .filter(|id| !id.is_empty());
    if set_video_id.is_empty() || successor_set_video_id.as_deref() == Some(set_video_id) {
        return Err(CommandError::new(
            "INVALID_PLAYLIST_ENTRY",
            "La ocurrencia que se quiere mover no es válida.",
        ));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let playlist = owned_playlist(&core, &playlist_id, false).await?;
    if playlist
        .sort
        .as_deref()
        .is_some_and(|sort| sort != "default")
    {
        return Err(CommandError::new(
            "PLAYLIST_SORT_ACTIVE",
            "Sólo se pueden mover canciones con el orden manual.",
        ));
    }
    check_operation_generation(&state, generation)?;
    core.move_playlist_track(playlist_id, set_video_id.to_owned(), successor_set_video_id)
        .await
        .map_err(|_| {
            CommandError::new("PLAYLIST_MOVE_FAILED", "No se pudo reordenar la playlist.")
        })?;
    check_operation_generation(&state, generation)
}

#[tauri::command]
pub(crate) async fn toggle_album_library(
    state: tauri::State<'_, AppState>,
    playlist_id: String,
    save: bool,
) -> Result<(), CommandError> {
    let id = playlist_id.trim();
    if id.is_empty() {
        return Err(CommandError::new(
            "INVALID_ID",
            "El identificador del álbum no puede estar vacío.",
        ));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    core.like_playlist(id.to_owned(), save).await.map_err(|_| {
        CommandError::new(
            "ALBUM_LIBRARY_FAILED",
            "No se pudo actualizar la biblioteca del álbum.",
        )
    })?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    Ok(())
}

#[tauri::command]
pub(crate) async fn set_artist_subscription(
    state: tauri::State<'_, AppState>,
    channel_id: String,
    subscribe: bool,
) -> Result<(), CommandError> {
    let id = channel_id.trim();
    if id.is_empty() {
        return Err(CommandError::new(
            "INVALID_ID",
            "El identificador del artista no puede estar vacío.",
        ));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    core.subscribe_artist(id.to_owned(), subscribe)
        .await
        .map_err(|_| {
            CommandError::new(
                "ARTIST_SUBSCRIPTION_FAILED",
                "No se pudo actualizar la suscripción al artista.",
            )
        })?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la operación.",
        ));
    }
    Ok(())
}
