use crate::{AppState, BrowseCardDto, CommandError, SongDto};
use std::sync::atomic::Ordering;
use std::sync::Arc;

fn recommendations_core(
    state: &AppState,
    video_id: &str,
) -> Result<(Arc<sideb_core::SideBCore>, u64), CommandError> {
    if video_id.trim().is_empty() {
        return Err(CommandError::new("INVALID_ID", "El identificador de canción no puede estar vacío."));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let core = state.core.read()
        .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo acceder al motor de Side B."))?
        .clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo."))?;
    Ok((core, generation))
}

fn check_generation(state: &AppState, generation: u64) -> Result<(), CommandError> {
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación."));
    }
    Ok(())
}

/// Reuses the same Related endpoint (with radio fallback) as the macOS player.
#[tauri::command]
pub(crate) async fn get_related_tracks(
    state: tauri::State<'_, AppState>,
    video_id: String,
) -> Result<Vec<SongDto>, CommandError> {
    let (core, generation) = recommendations_core(&state, &video_id)?;
    let result = core.get_related_tracks(video_id.trim().to_owned()).await;
    check_generation(&state, generation)?;
    result.map(|items| items.into_iter().map(SongDto::from).collect())
        .map_err(|_| CommandError::new("RECOMMENDATIONS_FAILED", "No se pudieron cargar las canciones parecidas. Comprobá tu conexión y reintentá."))
}

#[tauri::command]
pub(crate) async fn get_related_artists(
    state: tauri::State<'_, AppState>,
    video_id: String,
) -> Result<Vec<BrowseCardDto>, CommandError> {
    let (core, generation) = recommendations_core(&state, &video_id)?;
    let result = core.get_related_artists(video_id.trim().to_owned()).await;
    check_generation(&state, generation)?;
    result.map(|items| items.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("RECOMMENDATIONS_FAILED", "No se pudieron cargar los artistas relacionados. Comprobá tu conexión y reintentá."))
}
