use std::sync::atomic::Ordering;
use crate::{AppState, BrowseCardDto, CommandError};

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ChartCountryDto { pub code: String, pub title: String }

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ChartsPageDto {
    pub selected_country: Option<String>,
    pub countries: Vec<ChartCountryDto>,
    pub items: Vec<BrowseCardDto>,
}

fn core(state: &AppState) -> Result<std::sync::Arc<sideb_core::SideBCore>, CommandError> {
    state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?
        .clone().ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo."))
}

#[tauri::command]
pub(crate) async fn detect_music_country(state: tauri::State<'_, AppState>) -> Result<Option<String>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let detected = core(&state)?.detect_music_country().await
        .map_err(|_| CommandError::new("REGION_FAILED", "No se pudo detectar la región de música."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(detected)
}

#[tauri::command]
pub(crate) async fn get_charts(state: tauri::State<'_, AppState>, country_code: String) -> Result<ChartsPageDto, CommandError> {
    let code = country_code.trim().to_ascii_uppercase();
    if code.len() != 2 || !code.bytes().all(|b| b.is_ascii_uppercase()) {
        return Err(CommandError::new("INVALID_COUNTRY", "El código de país no es válido."));
    }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let page = core(&state)?.get_charts(code.clone()).await
        .map_err(|_| CommandError::new("CHARTS_FAILED", "No se pudieron cargar los rankings."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    // Never label a provider fallback as the country the user requested.
    if page.selected_country.as_deref() != Some(code.as_str()) {
        return Err(CommandError::new("COUNTRY_NOT_CONFIRMED", "YouTube Music no confirmó el país seleccionado."));
    }
    Ok(ChartsPageDto { selected_country: page.selected_country,
        countries: page.countries.into_iter().map(|c| ChartCountryDto { code: c.code, title: c.title }).collect(),
        items: page.items.into_iter().map(BrowseCardDto::from).collect() })
}
