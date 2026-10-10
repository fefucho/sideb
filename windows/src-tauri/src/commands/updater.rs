use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Emitter, Manager};

const DEFAULT_REPO_OWNER: &str = "fefucho";
const DEFAULT_REPO_NAME: &str = "SIDE-B-CLIENT-NATIVE";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct UpdateInfoDto {
    pub tag_name: String,
    pub version: String,
    pub release_notes: String,
    pub download_url: String,
    pub published_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "status", content = "data", rename_all = "camelCase")]
pub enum UpdateCheckResultDto {
    UpToDate { current_version: String },
    Available(UpdateInfoDto),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadProgressDto {
    pub percentage: f64,
    pub downloaded_bytes: u64,
    pub total_bytes: Option<u64>,
}

#[derive(Debug, Serialize, Deserialize, Default)]
struct UpdateSettings {
    skipped_version: Option<String>,
}

pub fn clean_version(raw: &str) -> &str {
    raw.trim_matches(|c: char| c == 'v' || c == 'V' || c.is_whitespace())
}

pub fn is_version_newer(remote: &str, current: &str) -> bool {
    let clean_remote = clean_version(remote);
    let clean_current = clean_version(current);

    let parts_remote: Vec<u64> = clean_remote
        .split('.')
        .filter_map(|s| s.parse().ok())
        .collect();
    let parts_current: Vec<u64> = clean_current
        .split('.')
        .filter_map(|s| s.parse().ok())
        .collect();

    let count = parts_remote.len().max(parts_current.len());
    for i in 0..count {
        let p_rem = parts_remote.get(i).copied().unwrap_or(0);
        let p_cur = parts_current.get(i).copied().unwrap_or(0);
        if p_rem > p_cur {
            return true;
        }
        if p_rem < p_cur {
            return false;
        }
    }
    false
}

fn get_settings_path(app: &AppHandle) -> Result<PathBuf, String> {
    let data_dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("No se pudo obtener directorio de datos: {e}"))?;
    fs::create_dir_all(&data_dir)
        .map_err(|e| format!("No se pudo crear directorio de datos: {e}"))?;
    Ok(data_dir.join("update_settings.json"))
}

fn read_update_settings(app: &AppHandle) -> UpdateSettings {
    if let Ok(path) = get_settings_path(app) {
        if let Ok(contents) = fs::read_to_string(path) {
            if let Ok(settings) = serde_json::from_str::<UpdateSettings>(&contents) {
                return settings;
            }
        }
    }
    UpdateSettings::default()
}

fn write_update_settings(app: &AppHandle, settings: &UpdateSettings) -> Result<(), String> {
    let path = get_settings_path(app)?;
    let serialized = serde_json::to_string_pretty(settings)
        .map_err(|e| format!("Error serializando ajustes de actualización: {e}"))?;
    fs::write(path, serialized)
        .map_err(|e| format!("Error guardando ajustes de actualización: {e}"))?;
    Ok(())
}

#[tauri::command]
pub fn get_app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[tauri::command]
pub fn get_skipped_version(app: AppHandle) -> Option<String> {
    read_update_settings(&app).skipped_version
}

#[tauri::command]
pub fn skip_version(app: AppHandle, version: String) -> Result<(), String> {
    let mut settings = read_update_settings(&app);
    settings.skipped_version = Some(version);
    write_update_settings(&app, &settings)
}

#[tauri::command]
pub fn reset_skipped_version(app: AppHandle) -> Result<(), String> {
    let mut settings = read_update_settings(&app);
    settings.skipped_version = None;
    write_update_settings(&app, &settings)
}

#[derive(Deserialize)]
pub(crate) struct GitHubAsset {
    pub name: String,
    pub browser_download_url: String,
}

#[derive(Deserialize)]
struct GitHubRelease {
    tag_name: String,
    body: Option<String>,
    published_at: Option<String>,
    assets: Vec<GitHubAsset>,
}

pub fn select_best_windows_asset(assets: &[GitHubAsset]) -> Option<String> {
    // 1. Priorizar instalador NSIS setup (.exe)
    for asset in assets {
        let name_lower = asset.name.to_lowercase();
        if name_lower.ends_with(".exe") && (name_lower.contains("setup") || name_lower.contains("installer")) {
            return Some(asset.browser_download_url.clone());
        }
    }
    // 2. Cualquier ejecutable .exe
    for asset in assets {
        if asset.name.to_lowercase().ends_with(".exe") {
            return Some(asset.browser_download_url.clone());
        }
    }
    // The download/launch path handles EXE installers only.
    None
}

#[tauri::command]
pub async fn check_for_updates(
    app: AppHandle,
    manual: bool,
) -> Result<UpdateCheckResultDto, String> {
    let current_version = env!("CARGO_PKG_VERSION");
    let skipped = read_update_settings(&app).skipped_version;

    let url = format!(
        "https://api.github.com/repos/{}/{}/releases/latest",
        DEFAULT_REPO_OWNER, DEFAULT_REPO_NAME
    );

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .map_err(|e| format!("No se pudo inicializar cliente HTTP: {e}"))?;

    let response = client
        .get(&url)
        .header(
            "User-Agent",
            format!("SideB/{} (Windows)", current_version),
        )
        .header("Accept", "application/vnd.github.v3+json")
        .send()
        .await
        .map_err(|e| format!("Error de conexión al consultar actualizaciones: {e}"))?;

    if response.status() == reqwest::StatusCode::NOT_FOUND {
        return Err("Aún no hay ningún release publicado en el repositorio.".to_string());
    }

    if !response.status().is_success() {
        return Err(format!(
            "GitHub respondió con código de error {}",
            response.status()
        ));
    }

    let release = response
        .json::<GitHubRelease>()
        .await
        .map_err(|e| format!("Formato de respuesta de release no reconocido: {e}"))?;

    let remote_version = clean_version(&release.tag_name).to_string();

    let download_url = select_best_windows_asset(&release.assets).ok_or_else(|| {
        format!(
            "El release {} no contiene un archivo instalador (.exe) para Windows.",
            release.tag_name
        )
    })?;

    if is_version_newer(&remote_version, current_version) {
        if !manual {
            if let Some(ref skipped_ver) = skipped {
                if skipped_ver == &remote_version {
                    return Ok(UpdateCheckResultDto::UpToDate {
                        current_version: current_version.to_string(),
                    });
                }
            }
        }

        let info = UpdateInfoDto {
            tag_name: release.tag_name,
            version: remote_version,
            release_notes: release
                .body
                .unwrap_or_else(|| "No se incluyeron notas para este release.".to_string()),
            download_url,
            published_at: release.published_at,
        };

        Ok(UpdateCheckResultDto::Available(info))
    } else {
        Ok(UpdateCheckResultDto::UpToDate {
            current_version: current_version.to_string(),
        })
    }
}

#[tauri::command]
pub async fn download_and_install_update(
    app: AppHandle,
    download_url: String,
) -> Result<(), String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(300))
        .build()
        .map_err(|e| format!("Error configurando cliente HTTP: {e}"))?;

    let response = client
        .get(&download_url)
        .send()
        .await
        .map_err(|e| format!("Error conectando con la descarga: {e}"))?;

    if !response.status().is_success() {
        return Err(format!(
            "Error al descargar la actualización (HTTP {})",
            response.status()
        ));
    }

    let total_size = response.content_length();
    let updates_dir = std::env::temp_dir().join("SideB-Updates");
    fs::create_dir_all(&updates_dir)
        .map_err(|e| format!("No se pudo crear carpeta de actualizaciones temporal: {e}"))?;

    let installer_path = updates_dir.join("SideB-Windows-Update.exe");
    if installer_path.exists() {
        let _ = fs::remove_file(&installer_path);
    }

    let mut file = fs::File::create(&installer_path)
        .map_err(|e| format!("No se pudo crear archivo temporal del instalador: {e}"))?;

    let mut stream = response.bytes_stream();
    let mut downloaded: u64 = 0;

    use std::io::Write;

    while let Some(chunk_result) = stream.next().await {
        let chunk = chunk_result.map_err(|e| format!("Error durante la descarga: {e}"))?;
        file.write_all(&chunk)
            .map_err(|e| format!("Error escribiendo datos al disco: {e}"))?;

        downloaded += chunk.len() as u64;

        let percentage = if let Some(total) = total_size {
            if total > 0 {
                (downloaded as f64) / (total as f64)
            } else {
                0.0
            }
        } else {
            0.0
        };

        let _ = app.emit(
            "update-download-progress",
            DownloadProgressDto {
                percentage,
                downloaded_bytes: downloaded,
                total_bytes: total_size,
            },
        );
    }

    file.flush()
        .map_err(|e| format!("Error finalizando guardado de la actualización: {e}"))?;
    drop(file);

    // Ejecutar el script trampoline desacoplado que espera a que la app cierre,
    // ejecuta el instalador silenciosamente y vuelve a lanzar Side B.
    execute_trampoline_update(&installer_path)?;

    Ok(())
}

fn execute_trampoline_update(installer_path: &Path) -> Result<(), String> {
    let current_pid = std::process::id();
    let current_exe = std::env::current_exe()
        .map_err(|e| format!("No se pudo obtener la ruta del ejecutable actual: {e}"))?;
    let updates_dir = installer_path.parent().unwrap_or_else(|| Path::new("."));

    let batch_path = updates_dir.join("relaunch_and_update.bat");

    // Script trampoline para Windows:
    // 1. Espera a que el PID de Side B actual termine
    // 2. Ejecuta el instalador NSIS en modo silencioso (/S)
    // 3. Relanza el ejecutable
    let batch_script = format!(
        r#"@echo off
setlocal
set WAIT_PID={current_pid}
set INSTALLER="{installer}"
set APP_EXE="{app_exe}"

:wait_pid
timeout /t 1 /nobreak >nul
tasklist /fi "PID eq %WAIT_PID%" 2>nul | findstr /i "%WAIT_PID%" >nul
if not errorlevel 1 (
    goto wait_pid
)

:: Ejecutar instalador NSIS silenciosamente
start "" /wait %INSTALLER% /S

:: Esperar un instante y reabrir la aplicacion
timeout /t 1 /nobreak >nul
if exist %APP_EXE% (
    start "" %APP_EXE%
)
"#,
        current_pid = current_pid,
        installer = installer_path.to_string_lossy(),
        app_exe = current_exe.to_string_lossy()
    );

    fs::write(&batch_path, batch_script)
        .map_err(|e| format!("No se pudo crear script de actualización: {e}"))?;

    // Lanzar el script en segundo plano sin ventana de consola (CREATE_NO_WINDOW = 0x08000000)
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x08000000;

        std::process::Command::new("cmd.exe")
            .args(["/C", &batch_path.to_string_lossy()])
            .creation_flags(CREATE_NO_WINDOW)
            .spawn()
            .map_err(|e| format!("No se pudo lanzar el instalador de actualización: {e}"))?;
    }

    #[cfg(not(target_os = "windows"))]
    {
        return Err("La actualización de Windows solo está disponible en Windows.".to_string());
    }

    // Salir del proceso inmediatamente para permitir que el instalador sobrescriba los binarios
    std::process::exit(0);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_clean_version() {
        assert_eq!(clean_version("v1.2.3"), "1.2.3");
        assert_eq!(clean_version("V0.1.0"), "0.1.0");
        assert_eq!(clean_version("  1.0.0 \n"), "1.0.0");
    }

    #[test]
    fn test_is_version_newer() {
        assert!(is_version_newer("0.2.0", "0.1.0"));
        assert!(is_version_newer("v1.0.0", "0.9.9"));
        assert!(is_version_newer("0.1.1", "0.1.0"));
        assert!(is_version_newer("1.0.0.1", "1.0.0"));
        assert!(!is_version_newer("0.1.0", "0.1.0"));
        assert!(!is_version_newer("0.0.9", "0.1.0"));
        assert!(!is_version_newer("0.1.0", "0.2.0"));
    }

    #[test]
    fn zip_is_not_mislabelled_as_executable_installer() {
        let assets=vec![GitHubAsset{name:"SideB-Windows-x64.zip".into(),browser_download_url:"https://example.com/windows.zip".into()}];
        assert_eq!(select_best_windows_asset(&assets),None);
    }
    #[test]
    fn test_select_best_windows_asset() {
        let assets = vec![
            GitHubAsset {
                name: "SideB-macOS.zip".to_string(),
                browser_download_url: "https://example.com/SideB-macOS.zip".to_string(),
            },
            GitHubAsset {
                name: "SideB-Windows-Setup.exe".to_string(),
                browser_download_url: "https://example.com/SideB-Windows-Setup.exe".to_string(),
            },
        ];

        let selected = select_best_windows_asset(&assets);
        assert_eq!(
            selected,
            Some("https://example.com/SideB-Windows-Setup.exe".to_string())
        );
    }
}
