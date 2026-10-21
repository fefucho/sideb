use crate::{AppState, CommandError};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    sync::{atomic::Ordering, Arc, Mutex, OnceLock},
};
use tauri::Manager;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AnimatedArtworkRequestDto {
    video_id: String,
    title: String,
    artists: String,
    album: Option<String>,
    album_id: Option<String>,
    duration_secs: Option<u64>,
    storefront: String,
    prefer_hevc: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AnimatedArtworkAssetDto {
    asset_id: String,
    local_path: String,
    codec: String,
    width: u32,
    height: u32,
    frame_rate: f64,
    size_bytes: u64,
}
impl From<sideb_core::AnimatedArtworkAsset> for AnimatedArtworkAssetDto {
    fn from(a: sideb_core::AnimatedArtworkAsset) -> Self {
        Self {
            asset_id: a.asset_id,
            local_path: a.local_path,
            codec: a.codec,
            width: a.width,
            height: a.height,
            frame_rate: a.frame_rate,
            size_bytes: a.size_bytes,
        }
    }
}

fn core(state: &AppState) -> Result<Arc<sideb_core::SideBCore>, CommandError> {
    state
        .core
        .read()
        .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo acceder al motor multimedia."))?
        .clone()
        .ok_or_else(|| {
            CommandError::new(
                "CORE_NOT_INITIALIZED",
                "El motor de Side B todavía no está listo.",
            )
        })
}
// Cancellation must reach the core that owns this request even after an account/core replacement.
fn requests() -> &'static Mutex<HashMap<String, Arc<sideb_core::SideBCore>>> {
    static REQUESTS: OnceLock<Mutex<HashMap<String, Arc<sideb_core::SideBCore>>>> = OnceLock::new();
    REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}
fn release_request(id: &str) {
    let owner = requests()
        .lock()
        .ok()
        .and_then(|mut requests| requests.remove(id));
    if let Some(owner) = owner {
        owner.cancel_animated_artwork(id.to_owned());
    }
}
fn cache_dir(app: &tauri::AppHandle) -> Result<String, CommandError> {
    let path = app
        .path()
        .app_cache_dir()
        .map_err(|_| CommandError::new("CACHE_UNAVAILABLE", "La caché no está disponible."))?
        .join("AnimatedArtwork");
    Ok(path.to_string_lossy().into_owned())
}
fn failed(_: sideb_core::SideBError) -> CommandError {
    CommandError::new(
        "ANIMATED_ARTWORK_FAILED",
        "No se pudo preparar la carátula animada.",
    )
}

#[tauri::command]
pub(crate) async fn prepare_animated_artwork(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    request: AnimatedArtworkRequestDto,
    request_id: String,
) -> Result<Option<AnimatedArtworkAssetDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let id = request_id.clone();
    let _requested_preference = request.prefer_hevc;
    let cache = cache_dir(&app)?;
    let original_core = core(&state)?;
    requests()
        .lock()
        .map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo preparar la carátula."))?
        .insert(id.clone(), original_core.clone());
    let result = original_core
        .prepare_animated_artwork(
            sideb_core::AnimatedArtworkRequest {
                video_id: request.video_id,
                title: request.title,
                artists: request.artists,
                album: request.album,
                album_id: request.album_id,
                duration_secs: request.duration_secs,
                storefront: request.storefront,
                // WebView2 variants are H.264. Do not rely on HEVC support on Windows.
                prefer_hevc: false,
            },
            request_id,
            cache,
        )
        .await;
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        original_core.cancel_animated_artwork(id.clone());
        release_request(&id);
        return Err(CommandError::new(
            "SESSION_CHANGED",
            "La sesión cambió durante la carga.",
        ));
    }
    match result {
        Ok(Some(asset)) => Ok(Some(asset.into())),
        Ok(None) => {
            release_request(&id);
            Ok(None)
        }
        Err(error) => {
            release_request(&id);
            Err(failed(error))
        }
    }
}

#[tauri::command]
pub(crate) fn cancel_animated_artwork(state: tauri::State<'_, AppState>, request_id: String) {
    release_request(&request_id);
    // A cancel invoke can arrive before prepare registers its owner. Record the
    // UUID tombstone in the shared engine too, so that late registration cannot
    // start a download after the consumer has gone away.
    if let Ok(current_core) = core(&state) {
        current_core.cancel_animated_artwork(request_id);
    }
}

#[tauri::command]
pub(crate) async fn get_animated_artwork_cache_size(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<u64, CommandError> {
    core(&state)?
        .get_animated_artwork_cache_size(cache_dir(&app)?)
        .await
        .map_err(failed)
}

#[tauri::command]
pub(crate) async fn clear_animated_artwork_cache(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<u64, CommandError> {
    core(&state)?
        .clear_animated_artwork_cache(cache_dir(&app)?)
        .await
        .map_err(failed)
}
