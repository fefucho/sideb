//! Windows facade over the protected, shared Genius engine. No provider URLs or auth are logged.
use crate::{AppState, CommandError};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::sync::{atomic::Ordering, Arc};

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct GeniusTrackDto {
    video_id: String,
    title: String,
    artists: String,
    album: Option<String>,
    duration_seconds: Option<u64>,
    #[serde(default)]
    is_upload: bool,
}
impl From<GeniusTrackDto> for sideb_core::GeniusTrackRecord {
    fn from(t: GeniusTrackDto) -> Self { Self { video_id: t.video_id, title: t.title, artists: t.artists, album: t.album, duration_seconds: t.duration_seconds, is_upload: t.is_upload } }
}
fn core(state: &AppState) -> Result<Arc<sideb_core::SideBCore>, CommandError> {
    state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo acceder a Genius."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo."))
}
fn same_session(state: &AppState, generation: u64) -> Result<(), CommandError> {
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la consulta.")); }
    Ok(())
}
fn failed(_: sideb_core::SideBError) -> CommandError { CommandError::new("GENIUS_FAILED", "No se pudo cargar Genius. Intentá de nuevo.") }
// Records already serialize all nested values; only the platform boundary changes field casing.
fn camel(value: Value) -> Value {
    match value {
        Value::Object(fields) => Value::Object(fields.into_iter().map(|(key, value)| {
            let mut parts = key.split('_');
            let mut name = parts.next().unwrap_or_default().to_owned();
            for part in parts { let mut chars = part.chars(); if let Some(c) = chars.next() { name.extend(c.to_uppercase()); name.extend(chars); } }
            (name, camel(value))
        }).collect()),
        Value::Array(items) => Value::Array(items.into_iter().map(camel).collect()),
        other => other,
    }
}
fn dto<T: Serialize>(value: T) -> Result<Value, CommandError> {
    let mut value = camel(serde_json::to_value(value).map_err(|_| CommandError::new("GENIUS_FAILED", "Datos de Genius no disponibles."))?);
    if let Some(status) = value.get_mut("status") {
        *status = json!(match status.as_str() { Some("Matched") => "matched", Some("Ambiguous") => "ambiguous", _ => "notFound" });
    }
    Ok(value)
}

#[tauri::command]
pub(crate) async fn genius_cached(state: tauri::State<'_, AppState>, track: GeniusTrackDto) -> Result<Value, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst); let core = core(&state)?;
    let value = core.get_genius_cached(track.into()).await; same_session(&state, generation)?; dto(value)
}
#[tauri::command]
pub(crate) async fn genius_resolve(state: tauri::State<'_, AppState>, track: GeniusTrackDto, force: bool) -> Result<Value, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst); let core = core(&state)?;
    let value = core.resolve_genius(track.into(), force).await.map_err(failed)?; same_session(&state, generation)?; dto(value)
}
#[tauri::command]
pub(crate) async fn genius_search(state: tauri::State<'_, AppState>, query: String) -> Result<Value, CommandError> {
    if query.trim().is_empty() { return Err(CommandError::new("EMPTY_QUERY", "Escribí título y artista.")); }
    let generation = state.auth_generation.load(Ordering::SeqCst); let core = core(&state)?;
    let value = core.search_genius(query).await.map_err(failed)?; same_session(&state, generation)?; dto(value)
}
#[tauri::command]
pub(crate) async fn genius_choose(state: tauri::State<'_, AppState>, track: GeniusTrackDto, song_id: i64) -> Result<Value, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst); let _operation = state.auth_operation.lock().await;
    same_session(&state, generation)?; let core = core(&state)?;
    let value = core.choose_genius(track.into(), song_id).await.map_err(failed)?; same_session(&state, generation)?; dto(value)
}
#[tauri::command]
pub(crate) async fn genius_clear_choice(state: tauri::State<'_, AppState>, track: GeniusTrackDto) -> Result<(), CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst); let _operation = state.auth_operation.lock().await;
    same_session(&state, generation)?; core(&state)?.clear_genius_choice(track.into()); Ok(())
}
#[tauri::command]
pub(crate) async fn genius_report_miss(state: tauri::State<'_, AppState>, track: GeniusTrackDto, status: String, candidate_ids: Vec<i64>) -> Result<(), CommandError> {
    let status = match status.as_str() { "ambiguous" => sideb_core::GeniusMatchStatusRecord::Ambiguous, "notFound" => sideb_core::GeniusMatchStatusRecord::NotFound, _ => return Err(CommandError::new("INVALID_STATUS", "La pista ya está identificada.")) };
    let generation = state.auth_generation.load(Ordering::SeqCst); let _operation = state.auth_operation.lock().await;
    same_session(&state, generation)?; core(&state)?.report_genius_miss(track.into(), status, candidate_ids).map_err(failed)
}
#[tauri::command]
pub(crate) async fn genius_annotations(state: tauri::State<'_, AppState>, song_id: i64, page: u32, force: bool, cached: bool) -> Result<Value, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst); let core = core(&state)?;
    let result = if cached { core.get_genius_cached_annotations(song_id, page.max(1)).await } else { Some(core.get_genius_annotations(song_id, page.max(1), force).await.map_err(failed)?) };
    same_session(&state, generation)?; dto(result)
}
#[tauri::command]
pub(crate) async fn genius_lyrics(state: tauri::State<'_, AppState>, song_id: i64, song_url: Option<String>, force: bool, cached: bool) -> Result<Value, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst); let core = core(&state)?;
    let result = if cached { core.get_genius_cached_lyrics(song_id).await } else {
        let url = song_url.ok_or_else(|| CommandError::new("INVALID_URL", "La canción no tiene enlace Genius."))?;
        // The core validates the Genius origin before issuing a request.
        Some(core.get_genius_lyrics(song_id, url, force).await.map_err(failed)?)
    };
    same_session(&state, generation)?; dto(result)
}
#[tauri::command]
pub(crate) fn genius_metrics(state: tauri::State<'_, AppState>) -> Result<Value, CommandError> {
    let m = core(&state)?.get_genius_metrics();
    Ok(json!({"requests":m.requests,"responseHeaderMs":m.response_header_ms,"cacheHits":m.cache_hits,"http429":m.http_429,"http403":m.http_403,"http5xx":m.http_5xx,"transportErrors":m.transport_errors,"parseErrors":m.parse_errors}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn nested_records_keep_spans_and_normalize_only_fields() {
        let resolution = sideb_core::GeniusResolutionRecord { status: sideb_core::GeniusMatchStatusRecord::NotFound, song: None, candidates: vec![], chosen_by_user: false };
        assert_eq!(dto(resolution).unwrap()["status"], "notFound");
        let value = camel(json!({"referent_id":42,"body_spans":[{"text":"a_b","url":null}]}));
        assert_eq!(value["referentId"], 42); assert_eq!(value["bodySpans"][0]["text"], "a_b");
    }
}
