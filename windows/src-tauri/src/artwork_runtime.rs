//! Motion-only policy. Windows has no public macOS thermal-state equivalent.
//! DWM cloaking is reported; overlap by other windows is not inferred from focus.
use serde::Serialize;
use std::sync::{Mutex, OnceLock};
use tauri::{Emitter, Manager};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ArtworkRuntimeState {
    visible: bool,
    minimized: bool,
    cloaked: bool,
    power_saver: bool,
    memory_pressure: bool,
}
impl Default for ArtworkRuntimeState {
    fn default() -> Self {
        Self {
            visible: true,
            minimized: false,
            cloaked: false,
            power_saver: false,
            memory_pressure: false,
        }
    }
}
fn state() -> &'static Mutex<ArtworkRuntimeState> {
    static STATE: OnceLock<Mutex<ArtworkRuntimeState>> = OnceLock::new();
    STATE.get_or_init(|| Mutex::new(ArtworkRuntimeState::default()))
}
fn update(app: &tauri::AppHandle, change: impl FnOnce(&mut ArtworkRuntimeState)) {
    if let Ok(mut current) = state().lock() {
        let before = *current;
        change(&mut current);
        if before != *current {
            let _ = app.emit("animated-artwork-runtime-changed", *current);
        }
    }
}
#[tauri::command]
pub(crate) fn get_animated_artwork_runtime_state(app: tauri::AppHandle) -> ArtworkRuntimeState {
    refresh_window(&app);
    state().lock().map(|state| *state).unwrap_or_default()
}
pub(crate) fn on_window_event(window: &tauri::Window, event: &tauri::WindowEvent) {
    if window.label() != "main" {
        return;
    }
    if matches!(
        event,
        tauri::WindowEvent::Destroyed | tauri::WindowEvent::CloseRequested { .. }
    ) {
        update(window.app_handle(), |state| state.visible = false);
    } else {
        refresh_window(window.app_handle());
    }
}
fn refresh_window(app: &tauri::AppHandle) {
    #[cfg(windows)]
    if let Some(window) = app.get_webview_window("main") {
        if let Ok(hwnd) = window.hwnd() {
            use windows_sys::Win32::{
                Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED},
                UI::WindowsAndMessaging::{IsIconic, IsWindowVisible},
            };
            let hwnd = hwnd.0 as windows_sys::Win32::Foundation::HWND;
            // All APIs are read-only. Focus is intentionally absent from this policy.
            unsafe {
                let mut cloaked: u32 = 0;
                let _ = DwmGetWindowAttribute(
                    hwnd,
                    DWMWA_CLOAKED as u32,
                    (&mut cloaked as *mut u32).cast(),
                    std::mem::size_of::<u32>() as u32,
                );
                update(app, |state| {
                    state.visible = IsWindowVisible(hwnd) != 0;
                    state.minimized = IsIconic(hwnd) != 0;
                    state.cloaked = cloaked != 0;
                });
            }
        }
    }
    #[cfg(not(windows))]
    let _ = app;
}
pub(crate) fn initialize(app: &tauri::AppHandle) {
    refresh_window(app);
    #[cfg(windows)]
    native::initialize(app);
}

#[cfg(windows)]
mod native {
    use super::*;
    use windows_sys::Win32::{
        Foundation::{CloseHandle, WAIT_OBJECT_0},
        System::{
            Memory::{
                CreateMemoryResourceNotification, HighMemoryResourceNotification,
                LowMemoryResourceNotification, QueryMemoryResourceNotification,
            },
            Power::{
                GetSystemPowerStatus, PowerSettingRegisterNotification,
                DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS, SYSTEM_POWER_STATUS,
            },
            SystemServices::GUID_POWER_SAVING_STATUS,
            Threading::{WaitForSingleObject, INFINITE},
        },
        UI::WindowsAndMessaging::DEVICE_NOTIFY_CALLBACK,
    };
    static APP: OnceLock<tauri::AppHandle> = OnceLock::new();
    fn refresh_power() {
        if let Some(app) = APP.get() {
            unsafe {
                let mut status: SYSTEM_POWER_STATUS = std::mem::zeroed();
                if GetSystemPowerStatus(&mut status) != 0 {
                    update(app, |state| {
                        state.power_saver = status.SystemStatusFlag != 0
                    });
                }
            }
        }
    }
    unsafe extern "system" fn power_changed(
        _: *const core::ffi::c_void,
        _: u32,
        _: *const core::ffi::c_void,
    ) -> u32 {
        refresh_power();
        0
    }
    pub(super) fn initialize(app: &tauri::AppHandle) {
        if APP.set(app.clone()).is_err() {
            return;
        }
        refresh_power();
        unsafe {
            // Callback and AppHandle have process lifetime. The registration deliberately
            // lasts for that same lifetime, without storing a borrowed callback context.
            let mut params = DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS {
                Callback: Some(power_changed),
                Context: std::ptr::null_mut(),
            };
            let mut registration = std::ptr::null_mut();
            let _ = PowerSettingRegisterNotification(
                &GUID_POWER_SAVING_STATUS,
                DEVICE_NOTIFY_CALLBACK,
                (&mut params as *mut DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS).cast(),
                &mut registration,
            );
        }
        // Alternating low/high notifications avoids spinning on a signalled low-memory
        // handle. Both waits sleep in the kernel; there is no timer or polling loop.
        let _ = std::thread::Builder::new()
            .name("artwork-memory-policy".into())
            .spawn(|| unsafe {
                let low = CreateMemoryResourceNotification(LowMemoryResourceNotification);
                let high = CreateMemoryResourceNotification(HighMemoryResourceNotification);
                if low.is_null() || high.is_null() {
                    if !low.is_null() {
                        CloseHandle(low);
                    }
                    if !high.is_null() {
                        CloseHandle(high);
                    }
                    return;
                }
                let mut pressure = 0;
                if QueryMemoryResourceNotification(low, &mut pressure) != 0 {
                    if let Some(app) = APP.get() {
                        update(app, |state| state.memory_pressure = pressure != 0);
                    }
                }
                let mut waiting_for_low = pressure == 0;
                loop {
                    if WaitForSingleObject(if waiting_for_low { low } else { high }, INFINITE)
                        != WAIT_OBJECT_0
                    {
                        break;
                    }
                    if let Some(app) = APP.get() {
                        update(app, |state| state.memory_pressure = waiting_for_low);
                    }
                    waiting_for_low = !waiting_for_low;
                }
                CloseHandle(low);
                CloseHandle(high);
            });
    }
}
