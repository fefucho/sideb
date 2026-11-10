//! Commands of the optional visual provider host. No command ever returns, logs or accepts back a
//! stored credential; the only secret that crosses IPC is a token the user pastes in manually.

use crate::visual_provider::host::{ArtworkRequest, AssetDto, Host, StateDto};
use crate::visual_provider::protocol::Failure;
use crate::visual_provider::webview::{self, LoginState};
use crate::CommandError;
use serde::Deserialize;
use std::path::PathBuf;
use std::sync::Arc;
use tauri::{AppHandle, Emitter, State};

type HostState<'a> = State<'a, Arc<Host>>;

/// Same shape as `AnimatedArtworkRequest` (extra fields are ignored), plus `explicit`.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct VisualProviderRequestDto {
    video_id: String,
    title: String,
    /// The principal artist, exactly what is sent to `prepare_animated_artwork`.
    artists: String,
    album: Option<String>,
    duration_secs: Option<u64>,
    explicit: Option<bool>,
}

fn failed(failure: Failure) -> CommandError {
    match failure {
        Failure::Cancelled => CommandError::new(
            "VISUAL_PROVIDER_CANCELLED",
            "La solicitud visual fue cancelada.",
        ),
        Failure::Credential => CommandError::new(
            "VISUAL_PROVIDER_CREDENTIAL",
            "No se pudo guardar el token del proveedor.",
        ),
        Failure::Invalid => CommandError::new(
            "VISUAL_PROVIDER_INVALID",
            "El proveedor visual devolvió algo no válido.",
        ),
        Failure::Unavailable => CommandError::new(
            "VISUAL_PROVIDER_FAILED",
            "El proveedor visual no está disponible.",
        ),
    }
}

#[tauri::command]
pub(crate) async fn get_visual_provider_state(
    host: HostState<'_>,
) -> Result<StateDto, CommandError> {
    Ok(host.state())
}

#[tauri::command]
pub(crate) async fn set_visual_provider_enabled(
    host: HostState<'_>,
    enabled: bool,
) -> Result<StateDto, CommandError> {
    host.set_enabled(enabled);
    Ok(host.state())
}

#[tauri::command]
pub(crate) async fn install_visual_provider_bundled(
    host: HostState<'_>,
) -> Result<StateDto, CommandError> {
    host.install_bundled().await.map_err(failed)?;
    Ok(host.state())
}

/// Installs a package folder (manifest + one executable). Validated like the preinstalled one.
#[tauri::command]
pub(crate) async fn install_visual_provider_from_folder(
    host: HostState<'_>,
    path: String,
) -> Result<StateDto, CommandError> {
    let folder = PathBuf::from(path.trim().trim_matches('"'));
    if !folder.is_absolute() || !folder.is_dir() {
        return Err(failed(Failure::Invalid));
    }
    host.install_from(folder).await.map_err(failed)?;
    Ok(host.state())
}

/// Deletes the plugin, its token, cached videos and web session. It does not come back by itself.
#[tauri::command]
pub(crate) async fn uninstall_visual_provider(
    host: HostState<'_>,
) -> Result<StateDto, CommandError> {
    host.uninstall().await.map_err(failed)?;
    Ok(host.state())
}

/// Manual token entry (advanced); the web login is the normal path.
#[tauri::command]
pub(crate) async fn save_visual_provider_token(
    host: HostState<'_>,
    token: String,
) -> Result<StateDto, CommandError> {
    host.save_credential(&token).map_err(failed)?;
    Ok(host.state())
}

/// Opens the provider's login window once. Progress arrives as `visual-provider-login` events.
#[tauri::command]
pub(crate) async fn open_visual_provider_login(
    app: AppHandle,
    host: HostState<'_>,
    title: Option<String>,
) -> Result<bool, CommandError> {
    let manifest = host.manifest().ok_or_else(|| failed(Failure::Invalid))?;
    let auth = manifest
        .auth
        .clone()
        .filter(|a| a.kind == "webview")
        .ok_or_else(|| failed(Failure::Invalid))?;
    let title = title
        .map(|t| t.chars().take(100).collect::<String>())
        .filter(|t| !t.trim().is_empty())
        .unwrap_or(manifest.name);
    let sink_host = host.inner().clone();
    let state_app = app.clone();
    Ok(webview::open_login(
        &app,
        auth,
        title,
        Arc::new(move |token| sink_host.save_credential(&token).is_ok()),
        Arc::new(move |state: LoginState| {
            let _ = state_app.emit(
                crate::visual_provider::EVENT_LOGIN,
                serde_json::json!({ "state": state.as_str() }),
            );
        }),
    )
    .await)
}

#[tauri::command]
pub(crate) fn cancel_visual_provider_login(app: AppHandle) {
    webview::close_login(&app);
}

/// Fallback visual for the sidebar's vertical player. `Ok(None)` = nothing usable (status in state).
/// The returned file is leased until `cancel_visual_provider_artwork` is called for the same id.
#[tauri::command]
pub(crate) async fn prepare_visual_provider_artwork(
    host: HostState<'_>,
    request: VisualProviderRequestDto,
    request_id: String,
) -> Result<Option<AssetDto>, CommandError> {
    host.prepare(
        ArtworkRequest {
            video_id: request.video_id,
            title: request.title,
            artist: request.artists,
            album: request.album,
            duration_seconds: request.duration_secs,
            explicit: request.explicit,
        },
        request_id,
    )
    .await
    .map_err(failed)
}

/// Cancels a pending request or drops the lease of a delivered asset (idempotent).
#[tauri::command]
pub(crate) fn cancel_visual_provider_artwork(host: HostState<'_>, request_id: String) {
    host.release(&request_id);
}

#[tauri::command]
pub(crate) async fn get_visual_provider_cache_size(
    host: HostState<'_>,
) -> Result<u64, CommandError> {
    Ok(host.cache_size().await)
}

#[tauri::command]
pub(crate) async fn clear_visual_provider_cache(host: HostState<'_>) -> Result<u64, CommandError> {
    Ok(host.clear_cache().await)
}
