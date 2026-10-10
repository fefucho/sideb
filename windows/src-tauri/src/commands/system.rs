use crate::CommandError;

#[tauri::command]
pub(crate) fn open_external_url(url: String) -> Result<(), CommandError> {
    let parsed = reqwest::Url::parse(&url).map_err(|_| CommandError::new("INVALID_URL", "Enlace no válido."))?;
    if !matches!(parsed.scheme(), "https" | "http") || parsed.host_str().is_none() || !parsed.username().is_empty() || parsed.password().is_some() {
        return Err(CommandError::new("INVALID_URL", "Enlace no válido."));
    }
    #[cfg(windows)] {
        use std::os::windows::ffi::OsStrExt;
        let operation:Vec<u16> = std::ffi::OsStr::new("open").encode_wide().chain(Some(0)).collect();
        let target:Vec<u16> = std::ffi::OsStr::new(parsed.as_str()).encode_wide().chain(Some(0)).collect();
        let result = unsafe { windows_sys::Win32::UI::Shell::ShellExecuteW(std::ptr::null_mut(), operation.as_ptr(), target.as_ptr(), std::ptr::null(), std::ptr::null(), 1) };
        if result as isize <= 32 { return Err(CommandError::new("OPEN_URL_FAILED", "No se pudo abrir el enlace.")); }
    }
    #[cfg(not(windows))] return Err(CommandError::new("UNSUPPORTED_PLATFORM", "Esta acción requiere Windows."));
    #[cfg(windows)] Ok(())
}
