use std::sync::atomic::Ordering;
use crate::commands::account::account_core;
use crate::{AppState, AlbumCardDto, AlbumDetailDto, ArtistDetailDto, BrowseCardDto, CommandError, HomePageDto, PlaylistDetailDto, SearchResultsDto, SearchSuggestionsDto, SearchCatalogDto, SearchCorrectionDto, SongDto};

const SEARCH_CATEGORIES: [&str; 3] = ["albums", "artists", "playlists"];

fn search_core(state: &AppState) -> Result<std::sync::Arc<sideb_core::SideBCore>, CommandError> {
    state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?
        .clone().ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))
}

fn validate_search_query(query: &str) -> Result<&str, CommandError> {
    let query = query.trim();
    if query.is_empty() { Err(CommandError::new("EMPTY_QUERY", "La consulta de búsqueda no puede estar vacía.")) } else { Ok(query) }
}

#[tauri::command]
pub(crate) async fn search_suggestions(state: tauri::State<'_, AppState>, query: String) -> Result<SearchSuggestionsDto, CommandError> {
    let query = validate_search_query(&query)?;
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let core = search_core(&state)?;
    let result = core.search_suggestions(query.to_owned()).await
        .map_err(|_| CommandError::new("SEARCH_FAILED", "No se pudieron obtener sugerencias de YouTube Music."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(SearchSuggestionsDto { queries: result.queries, results: result.results.into() })
}

#[tauri::command]
pub(crate) async fn search_catalog(state: tauri::State<'_, AppState>, query: String, record_history: bool, ignore_spelling: bool) -> Result<SearchCatalogDto, CommandError> {
    let query = validate_search_query(&query)?;
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = if record_history { Some(state.auth_operation.read().await) } else { None };
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió antes de completar la búsqueda.")); }
    let core = search_core(&state)?;
    let result = core.search_catalog(query.to_owned(), record_history, ignore_spelling).await
        .map_err(|_| CommandError::new("SEARCH_FAILED", "No se pudo completar la búsqueda en YouTube Music."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(SearchCatalogDto {
        results: result.results.into(),
        correction: result.correction.map(|c| SearchCorrectionDto { query: c.query, applied: c.applied }),
    })
}

#[tauri::command]
pub(crate) async fn search_all(state: tauri::State<'_, AppState>, query: String, record_history: bool) -> Result<SearchResultsDto, CommandError> {
    let query = validate_search_query(&query)?;
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = if record_history { Some(state.auth_operation.read().await) } else { None };
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió antes de completar la búsqueda.")); }
    let core = search_core(&state)?;
    let result = core.search_all(query.to_owned(), record_history).await
        .map(SearchResultsDto::from)
        .map_err(|_| CommandError::new("SEARCH_FAILED", "No se pudo completar la búsqueda en YouTube Music. Comprobá tu conexión a internet."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn search_videos(state: tauri::State<'_, AppState>, query: String) -> Result<Vec<SongDto>, CommandError> {
    let query = validate_search_query(&query)?;
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let core = search_core(&state)?;
    let result = core.search_videos(query.to_owned()).await
        .map(|items| items.into_iter().map(SongDto::from).collect())
        .map_err(|_| CommandError::new("SEARCH_FAILED", "No se pudo completar la búsqueda de videos en YouTube Music. Comprobá tu conexión a internet."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn search_cards(state: tauri::State<'_, AppState>, query: String, category: String) -> Result<Vec<BrowseCardDto>, CommandError> {
    let query = validate_search_query(&query)?;
    let category = category.trim().to_ascii_lowercase();
    if !SEARCH_CATEGORIES.contains(&category.as_str()) { return Err(CommandError::new("INVALID_CATEGORY", "La categoría de búsqueda no es válida.")); }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let core = search_core(&state)?;
    let result = core.search_cards(query.to_owned(), category).await
        .map(|items| items.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("SEARCH_FAILED", "No se pudo completar la búsqueda de la categoría en YouTube Music. Comprobá tu conexión a internet."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn search_songs(
    state: tauri::State<'_, AppState>,
    query: String,
) -> Result<Vec<SongDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return Err(CommandError::new(
            "EMPTY_QUERY",
            "La consulta de búsqueda no puede estar vacía.",
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

    match core.search_songs(trimmed.to_string(), false).await {
        Ok(results) => {
            if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
            Ok(results.into_iter().map(SongDto::from).collect())
        },
        Err(_) => Err(CommandError::new(
            "SEARCH_FAILED",
            "No se pudo completar la búsqueda en YouTube Music. Comprobá tu conexión a internet.",
        )),
    }
}

#[tauri::command]
pub(crate) async fn search_albums(
    state: tauri::State<'_, AppState>,
    query: String,
) -> Result<Vec<AlbumCardDto>, CommandError> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return Err(CommandError::new(
            "EMPTY_QUERY",
            "La consulta de búsqueda no puede estar vacía.",
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

    match core
        .search_cards(trimmed.to_string(), "albums".to_string())
        .await
    {
        Ok(results) => Ok(results.into_iter().map(AlbumCardDto::from).collect()),
        Err(_) => Err(CommandError::new(
            "SEARCH_FAILED",
            "No se pudo completar la búsqueda de álbumes en YouTube Music. Comprobá tu conexión a internet.",
        )),
    }
}

#[tauri::command]
pub(crate) async fn get_album(
    state: tauri::State<'_, AppState>,
    browse_id: String,
) -> Result<AlbumDetailDto, CommandError> {
    let trimmed = browse_id.trim();
    if trimmed.is_empty() {
        return Err(CommandError::new(
            "INVALID_ID",
            "El identificador de álbum no puede estar vacío.",
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

    match core.get_album(trimmed.to_string()).await {
        Ok(record) => Ok(AlbumDetailDto::from(record)),
        Err(_) => Err(CommandError::new(
            "ALBUM_FAILED",
            "No se pudo cargar el detalle del álbum. Comprobá tu conexión a internet o el identificador.",
        )),
    }
}

#[tauri::command]
pub(crate) async fn get_home_page(
    state: tauri::State<'_, AppState>,
    chip_params: Option<String>,
) -> Result<HomePageDto, CommandError> {
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

    let params = chip_params.and_then(|p| {
        let trimmed = p.trim().to_string();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    });

    match core.get_home_page(params).await {
        Ok(page) => Ok(HomePageDto::from(page)),
        Err(_) => Err(CommandError::new(
            "HOME_FAILED",
            "No se pudo cargar la página de inicio de YouTube Music. Comprobá tu conexión a internet.",
        )),
    }
}

#[tauri::command]
pub(crate) async fn get_home_continuation(state: tauri::State<'_, AppState>, token: String) -> Result<HomePageDto, CommandError> {
    let token = token.trim();
    if token.is_empty() { return Err(CommandError::new("INVALID_TOKEN", "El token de continuación no puede estar vacío.")); }
    let core = state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))?;
    core.get_home_continuation(token.to_owned()).await.map(HomePageDto::from)
        .map_err(|_| CommandError::new("HOME_FAILED", "No se pudo cargar más contenido de Inicio. Comprobá tu conexión a internet."))
}

#[tauri::command]
pub(crate) async fn get_artist(state: tauri::State<'_, AppState>, browse_id: String) -> Result<ArtistDetailDto, CommandError> {
    let id = browse_id.trim();
    if id.is_empty() { return Err(CommandError::new("INVALID_ID", "El identificador del artista no puede estar vacío.")); }
    let core = state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))?;
    core.get_artist(id.to_owned()).await.map(ArtistDetailDto::from)
        .map_err(|_| CommandError::new("ARTIST_FAILED", "No se pudo cargar el perfil del artista. Comprobá tu conexión a internet o el identificador."))
}

#[tauri::command]
pub(crate) async fn get_browse_grid(state: tauri::State<'_, AppState>, browse_id: String, params: Option<String>) -> Result<Vec<BrowseCardDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let id = browse_id.trim();
    if id.is_empty() { return Err(CommandError::new("INVALID_ID", "El identificador de la sección no puede estar vacío.")); }
    let params = params.and_then(|p| { let p = p.trim().to_owned(); (!p.is_empty()).then_some(p) });
    let core = state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))?;
    let result = core.get_browse_grid(id.to_owned(), params).await.map(|items| items.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("BROWSE_FAILED", "No se pudo cargar esta sección. Comprobá tu conexión a internet."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn get_playlist(state: tauri::State<'_, AppState>, playlist_id: String) -> Result<PlaylistDetailDto, CommandError> {
    let id = playlist_id.trim();
    if id.is_empty() { return Err(CommandError::new("INVALID_ID", "El identificador de la lista no puede estar vacío.")); }
    if matches!(id.to_ascii_uppercase().as_str(), "LM" | "VLLM") {
        let generation = state.auth_generation.load(Ordering::SeqCst);
        let _operation = state.auth_operation.read().await;
        let core = account_core(&state, generation)?;
        let result = core.get_playlist(id.to_owned()).await.map(PlaylistDetailDto::from)
            .map_err(|_| CommandError::new("PLAYLIST_FAILED", "No se pudo cargar la lista. Comprobá tu conexión a internet o el identificador."))?;
        if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
        return Ok(result);
    }
    let core = state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))?;
    core.get_playlist(id.to_owned()).await.map(PlaylistDetailDto::from)
        .map_err(|_| CommandError::new("PLAYLIST_FAILED", "No se pudo cargar la lista. Comprobá tu conexión a internet o el identificador."))
}

/// Load the same initial artist-radio queue that macOS gets from getNext(nil, playlistId).
/// The returned first song is the queue's first/current candidate; the frontend owns playback.
#[tauri::command]
pub(crate) async fn get_artist_radio(state: tauri::State<'_, AppState>, playlist_id: String) -> Result<Vec<SongDto>, CommandError> {
    let id = playlist_id.trim();
    if id.is_empty() { return Err(CommandError::new("INVALID_ID", "El identificador de radio no puede estar vacío.")); }
    let core = state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))?;
    core.get_next(None, Some(id.to_owned())).await
        .map(|result| result.items.into_iter().map(SongDto::from).collect())
        .map_err(|_| CommandError::new("ARTIST_RADIO_FAILED", "No se pudo cargar la radio del artista. Comprobá tu conexión a internet."))
}

#[tauri::command]
pub(crate) async fn search_page(
    state: tauri::State<'_, AppState>,
    query: String,
    params: Option<String>,
    record_history: bool,
    ignore_spelling: bool,
) -> Result<crate::search_page::SearchPageDto, CommandError> {
    let query = validate_search_query(&query)?.to_owned();
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = if record_history {
        Some(state.auth_operation.read().await)
    } else {
        None
    };
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió."));
    }
    let result = search_core(&state)?
        .search_page(query, params, record_history, ignore_spelling)
        .await
        .map_err(|_| CommandError::new("SEARCH_FAILED", "No se pudo completar la búsqueda."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió."));
    }
    Ok(result.into())
}
#[tauri::command]
pub(crate) async fn search_page_continuation(
    state: tauri::State<'_, AppState>,
    continuation: String,
) -> Result<crate::search_page::SearchPageDto, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let result = search_core(&state)?
        .search_page_continuation(continuation)
        .await
        .map_err(|_| CommandError::new("SEARCH_FAILED", "No se pudieron cargar más resultados."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió."));
    }
    Ok(result.into())
}
#[tauri::command]
pub(crate) async fn search_suggestions_page(
    state: tauri::State<'_, AppState>,
    query: String,
) -> Result<crate::search_page::SearchSuggestionsPageDto, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let result = search_core(&state)?
        .search_suggestions_page(query)
        .await
        .map_err(|_| CommandError::new("SEARCH_FAILED", "No se pudieron obtener sugerencias."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió."));
    }
    Ok(result.into())
}
#[tauri::command]
pub(crate) async fn remove_search_suggestion(
    state: tauri::State<'_, AppState>,
    token: String,
) -> Result<(), CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.read().await;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió."));
    }
    search_core(&state)?
        .remove_search_suggestion(token)
        .await
        .map_err(|_| {
            CommandError::new(
                "SEARCH_FAILED",
                "No se pudo eliminar la búsqueda del historial.",
            )
        })
}

#[tauri::command]
pub(crate) async fn search_action(
    state: tauri::State<'_, AppState>,
    video_id: Option<String>,
    playlist_id: Option<String>,
    params: Option<String>,
) -> Result<crate::search_page::SearchNextDto, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let result = search_core(&state)?
        .search_action(video_id, playlist_id, params)
        .await
        .map_err(|_| {
            CommandError::new(
                "SEARCH_ACTION_FAILED",
                "No se pudo reproducir el resultado.",
            )
        })?;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió."));
    }
    Ok(result.into())
}
