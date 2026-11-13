//! Commands of the Spotify Jam runtime (`src/jam`, contract in `src/lib/jam/types.ts`). The
//! Spotify token never crosses IPC: the runtime obtains it and writes it to the plugin itself.

use crate::jam::{JamClock, JamRuntime, JamStatus};
use crate::queue::QueueEntryDto;
use crate::{AppState, CommandError, PlaybackStateDto};
use serde_json::Value;
use std::sync::Arc;
use tauri::{AppHandle, Emitter, State};

type Runtime<'a> = State<'a, Arc<JamRuntime>>;

#[tauri::command]
pub(crate) async fn jam_status(runtime: Runtime<'_>) -> Result<JamStatus, CommandError> {
    Ok(runtime.status())
}

#[tauri::command]
pub(crate) async fn jam_join(runtime: Runtime<'_>, link: String) -> Result<(), CommandError> {
    runtime.inner().join(link).await
}

/// Only `command` and `resolve` messages are accepted.
#[tauri::command]
pub(crate) async fn jam_send(runtime: Runtime<'_>, message: Value) -> Result<(), CommandError> {
    runtime.send(&message)
}

#[tauri::command]
pub(crate) async fn jam_leave(runtime: Runtime<'_>) -> Result<(), CommandError> {
    runtime.inner().leave().await;
    Ok(())
}

// Async on purpose: building a WebView window from a synchronous command can deadlock Windows.
#[tauri::command]
pub(crate) async fn jam_open_spotify_login(
    runtime: Runtime<'_>,
    title: Option<String>,
) -> Result<bool, CommandError> {
    Ok(runtime.inner().open_login(title).await)
}

#[tauri::command]
pub(crate) fn jam_cancel_spotify_login(app: AppHandle) {
    crate::visual_provider::webview::close_login(&app);
}

#[tauri::command]
pub(crate) async fn jam_spotify_sign_out(runtime: Runtime<'_>) -> Result<(), CommandError> {
    runtime.sign_out();
    Ok(())
}

#[tauri::command]
pub(crate) async fn jam_set_speed(runtime: Runtime<'_>, speed: f64) -> Result<(), CommandError> {
    runtime.set_speed(speed)
}

#[tauri::command]
pub(crate) async fn jam_clock(runtime: Runtime<'_>) -> Result<JamClock, CommandError> {
    runtime.clock()
}

/// Replaces everything after the current entry with `items`, without touching the audio and
/// without starting radio or recommendation fetches. Only valid while the queue belongs to a Jam.
#[tauri::command]
pub(crate) async fn jam_replace_upcoming(
    app: AppHandle,
    state: State<'_, AppState>,
    items: Vec<QueueEntryDto>,
) -> Result<PlaybackStateDto, CommandError> {
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
        if playback
            .queue
            .source
            .as_ref()
            .is_none_or(|source| source.kind != crate::jam::QUEUE_SOURCE_KIND)
        {
            return Err(CommandError::new(
                "JAM_QUEUE_NOT_ACTIVE",
                "La cola actual no pertenece a un Jam.",
            ));
        }
        playback.queue.replace_upcoming(
            items
                .into_iter()
                .map(|mut item| {
                    item.video_id = item.video_id.trim().to_owned();
                    item
                })
                .collect(),
        );
        // Persisting happens inside `to_dto`, as for every other queue edit.
        playback.to_dto()
    };
    let _ = app.emit("playback-state-changed", &snapshot);
    Ok(snapshot)
}
