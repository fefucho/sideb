//! Windows sign-in window. Google credentials stay in WebView2; only YouTube cookies cross into Rust.
//!
//! The exported jar has to keep working inside the Rust core, which can only follow the rotations
//! that arrive as `Set-Cookie`. Chromium's Device Bound Session Credentials break that: Google
//! binds the short-lived `__Secure-*PSIDTS` cookies to a key that never leaves WebView2, so the
//! copy in the core expires and only the browser can renew it. Two defences live here:
//! [`WEBVIEW_BROWSER_ARGS`] keeps new sign-ins unbound, and the silent renewal asks WebView2 for a
//! fresh jar whenever YouTube rejects the stored one, without showing a window.

use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Duration;

use tauri::webview::{cookie::Cookie, PageLoadEvent};
use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};

use crate::{auth_generation, session_store, set_auth_status, AppState, AuthStatusDto};

const LOGIN_LABEL: &str = "sideb-login";
const RENEWAL_LABEL: &str = "sideb-session-renewal";
/// Every WebView2 window of the app shares one user data folder, so they must all be created with
/// the same arguments: a mismatch makes WebView2 refuse to create the second environment. The
/// main window repeats this string in `tauri.conf.json`; a test keeps both in step.
///
/// `DeviceBoundSessions` is the only addition to what wry passes by default.
pub(crate) const WEBVIEW_BROWSER_ARGS: &str = "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection,DeviceBoundSessions --autoplay-policy=no-user-gesture-required";
/// A hidden renewal either lands signed in within seconds or is waiting for a password.
const RENEWAL_TIMEOUT: Duration = Duration::from_secs(25);
/// Waits before repeating a validation that failed without an answer from YouTube.
const VALIDATION_RETRY_DELAYS: [Duration; 2] = [Duration::from_secs(3), Duration::from_secs(8)];
const HEALTH_TICK: Duration = Duration::from_secs(30);
const HEALTH_VALIDATION_INTERVAL: Duration = Duration::from_secs(600);
/// `Display` of the core's `SessionExpired`, which reaches the host inside `NetworkError`.
const SESSION_EXPIRED_MARKER: &str = "session expired";
const LOGIN_URL: &str =
    "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://music.youtube.com/";

pub fn open_login(app: AppHandle) -> Result<(), String> {
    let state = app.state::<AppState>();
    let current = state
        .auth
        .read()
        .map_err(|_| "No se pudo leer la sesión.")?
        .state
        .clone();
    if current == "authorizing" || current == "ready" {
        return Err("Ya hay una sesión activa o un acceso en curso.".into());
    }
    let generation = state.auth_generation.fetch_add(1, Ordering::SeqCst) + 1;
    set_auth_status(&app, AuthStatusDto::authorizing());

    let (tx, rx) = tokio::sync::mpsc::unbounded_channel::<()>();
    let task_app = app.clone();
    tauri::async_runtime::spawn(async move {
        if let Some(cookie) = wait_for_session_cookies(&task_app, LOGIN_LABEL, rx, generation).await
        {
            finish_login(task_app.clone(), generation, cookie).await;
        }
    });

    let create_app = app.clone();
    if app
        .run_on_main_thread(move || {
            if !create_session_window(&create_app, LOGIN_LABEL, true, tx) {
                set_auth_status(
                    &create_app,
                    AuthStatusDto::error("No se pudo abrir la ventana de acceso."),
                );
            }
        })
        .is_err()
    {
        set_auth_status(
            &app,
            AuthStatusDto::error("No se pudo abrir la ventana de acceso."),
        );
        return Err("No se pudo abrir la ventana de acceso.".into());
    }
    Ok(())
}

/// Opens the Google sign-in flow in a WebView2 window and reports each finished load of
/// music.youtube.com through `loaded`. Must run on the main thread. A hidden window is used for
/// renewals: WebView2 still navigates and still owns the profile that can refresh the session.
fn create_session_window(
    app: &AppHandle,
    label: &'static str,
    visible: bool,
    loaded: tokio::sync::mpsc::UnboundedSender<()>,
) -> bool {
    if let Some(old) = app.get_webview_window(label) {
        let _ = old.destroy();
    }
    let Ok(url) = tauri::Url::parse(LOGIN_URL) else {
        return false;
    };
    // WebView2's default Windows/Edge user agent agrees with its client hints.
    WebviewWindowBuilder::new(app, label, WebviewUrl::External(url))
        .title("Iniciar sesión en YouTube Music")
        .inner_size(480.0, 720.0)
        .visible(visible)
        .focused(visible)
        .skip_taskbar(!visible)
        .additional_browser_args(WEBVIEW_BROWSER_ARGS)
        .on_page_load(move |_window, payload| {
            if matches!(payload.event(), PageLoadEvent::Finished)
                && payload.url().host_str() == Some("music.youtube.com")
            {
                let _ = loaded.send(());
            }
        })
        .build()
        .is_ok()
}

/// Resolves with the exported jar once the window has loaded music.youtube.com signed in.
/// Ends with `None` when the window goes away or another sign-in, sign-out or cancel takes over.
async fn wait_for_session_cookies(
    app: &AppHandle,
    label: &'static str,
    mut loaded: tokio::sync::mpsc::UnboundedReceiver<()>,
    generation: u64,
) -> Option<String> {
    loop {
        // Wake up between loads so a superseded wait ends without needing the window to close.
        loop {
            if auth_generation(app) != generation {
                return None;
            }
            if let Ok(page) =
                tokio::time::timeout(Duration::from_millis(200), loaded.recv()).await
            {
                page?;
                break;
            }
        }
        for _ in 0..6 {
            if auth_generation(app) != generation {
                return None;
            }
            if let Ok(cookie) = read_login_cookies(app, label).await {
                if has_sapisid(&cookie) {
                    return Some(cookie);
                }
            }
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
    }
}

/// Asks WebView2 for a fresh jar without showing anything. Its profile keeps the Google sign-in
/// and, for a device-bound session, the key that renews it, so this is the same thing the user
/// did by pressing "Iniciar sesión" and watching the popup sign in on its own.
async fn silent_session_cookies(app: &AppHandle, generation: u64) -> Option<String> {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel::<()>();
    let (created_tx, created_rx) = tokio::sync::oneshot::channel();
    let create_app = app.clone();
    app.run_on_main_thread(move || {
        let _ = created_tx.send(create_session_window(&create_app, RENEWAL_LABEL, false, tx));
    })
    .ok()?;
    let cookie = if created_rx.await.unwrap_or(false) {
        tokio::time::timeout(
            RENEWAL_TIMEOUT,
            wait_for_session_cookies(app, RENEWAL_LABEL, rx, generation),
        )
        .await
        .ok()
        .flatten()
    } else {
        None
    };
    let close_app = app.clone();
    let _ = app.run_on_main_thread(move || {
        if let Some(window) = close_app.get_webview_window(RENEWAL_LABEL) {
            let _ = window.destroy();
        }
    });
    cookie
}

/// What YouTube said about the jar installed in the core.
enum Validation {
    Ready(sideb_core::AccountInfoRecord),
    /// YouTube answered and does not recognise the session.
    Rejected,
    /// No answer to judge the session by: offline, timeout, server error.
    Unreachable,
}

fn classify_validation(
    result: Result<sideb_core::AccountInfoRecord, sideb_core::SideBError>,
) -> Validation {
    match result {
        Ok(info) if info.name.is_some() => Validation::Ready(info),
        // A 200 carrying the signed-out account menu.
        Ok(_) => Validation::Rejected,
        Err(error)
            if error
                .to_string()
                .to_ascii_lowercase()
                .contains(SESSION_EXPIRED_MARKER) =>
        {
            Validation::Rejected
        }
        Err(_) => Validation::Unreachable,
    }
}

/// Validates the installed jar, giving a connection that is still coming up time to settle so a
/// slow network at startup is not mistaken for a dead session.
async fn validate_session(
    app: &AppHandle,
    core: &sideb_core::SideBCore,
    generation: u64,
) -> Validation {
    let mut delays = VALIDATION_RETRY_DELAYS.iter();
    loop {
        let validation = classify_validation(core.get_account_info().await);
        if !matches!(validation, Validation::Unreachable) {
            return validation;
        }
        let Some(delay) = delays.next() else {
            return validation;
        };
        tokio::time::sleep(*delay).await;
        if auth_generation(app) != generation {
            return validation;
        }
    }
}

/// Replaces a rejected jar with one renewed by WebView2 and validates it.
async fn renew_session(
    app: &AppHandle,
    core: &sideb_core::SideBCore,
    generation: u64,
) -> Validation {
    let Some(cookie) = silent_session_cookies(app, generation).await else {
        return Validation::Rejected;
    };
    if auth_generation(app) != generation {
        return Validation::Unreachable;
    }
    core.set_cookie_memory(Some(cookie));
    validate_session(app, core, generation).await
}

async fn finish_login(app: AppHandle, generation: u64, cookie: String) {
    let state = app.state::<AppState>();
    let _auth_operation = state.auth_operation.write().await;
    if auth_generation(&app) != generation {
        return;
    }
    let core = match app.state::<AppState>().core.read() {
        Ok(lock) => lock.clone(),
        Err(_) => None,
    };
    let Some(core) = core else {
        set_auth_status(
            &app,
            AuthStatusDto::error("El motor de Side B no está listo."),
        );
        close_login(&app);
        return;
    };
    core.set_cookie_memory(Some(cookie.clone()));
    let result = core.get_account_info().await;
    if auth_generation(&app) != generation {
        return;
    }
    match result {
        Ok(info) if info.name.is_some() => {
            let latest_cookie = core.get_cookie().unwrap_or(cookie);
            let saved = app
                .path()
                .app_data_dir()
                .map_err(|_| "No se encontró el almacén local.".to_string())
                .and_then(|dir| session_store::save(&dir, &latest_cookie));
            if saved.is_ok() {
                set_auth_status(&app, AuthStatusDto::ready(info));
            } else {
                core.set_cookie_memory(None);
                set_auth_status(
                    &app,
                    AuthStatusDto::error("No se pudo guardar la sesión de forma segura."),
                );
            }
        }
        _ => {
            core.set_cookie_memory(None);
            set_auth_status(
                &app,
                AuthStatusDto::error("La sesión no pudo validarse. Probá iniciar sesión de nuevo."),
            );
        }
    }
    close_login(&app);
}

fn close_login(app: &AppHandle) {
    if let Some(window) = app.get_webview_window(LOGIN_LABEL) {
        let _ = window.destroy();
    }
}

pub fn close_login_window(app: &AppHandle) -> Result<(), String> {
    let app2 = app.clone();
    app.run_on_main_thread(move || close_login(&app2))
        .map_err(|_| "No se pudo cerrar la ventana de acceso.".to_string())
}

fn has_sapisid(cookie: &str) -> bool {
    cookie.split(';').any(|part| {
        let name = part
            .trim()
            .split_once('=')
            .map(|(name, _)| name)
            .unwrap_or("");
        matches!(name, "SAPISID" | "__Secure-3PAPISID")
    })
}

async fn read_login_cookies(app: &AppHandle, label: &'static str) -> Result<String, String> {
    let (tx, rx) = tokio::sync::oneshot::channel();
    let app2 = app.clone();
    app.run_on_main_thread(move || {
        let result = app2
            .get_webview_window(label)
            .ok_or_else(|| "La ventana de acceso se cerró.".to_string())
            .and_then(|window| {
                window
                    .cookies()
                    .map_err(|_| "No se pudieron leer las cookies.".to_string())
            })
            .map(youtube_cookie_header);
        let _ = tx.send(result);
    })
    .map_err(|_| "No se pudieron consultar las cookies.".to_string())?;
    rx.await
        .map_err(|_| "No se pudieron consultar las cookies.".to_string())?
}

fn youtube_cookie_header(mut cookies: Vec<Cookie<'static>>) -> String {
    cookies.sort_by_key(|cookie| cookie.domain().unwrap_or_default().len());
    let mut jar = std::collections::BTreeMap::new();
    for cookie in cookies {
        let domain = cookie.domain().unwrap_or_default().trim_start_matches('.');
        if domain == "youtube.com" || domain.ends_with(".youtube.com") {
            jar.insert(cookie.name().to_string(), cookie.value().to_string());
        }
    }
    jar.into_iter()
        .map(|(name, value)| format!("{name}={value}"))
        .collect::<Vec<_>>()
        .join("; ")
}

pub async fn clear_login_cookies(app: &AppHandle) -> Result<(), String> {
    let (tx, rx) = tokio::sync::oneshot::channel();
    let app2 = app.clone();
    app.run_on_main_thread(move || {
        close_login(&app2);
        let result = app2
            .get_webview_window("main")
            .ok_or_else(|| "No se encontró la ventana principal.".to_string())
            .and_then(|window| {
                let cookies = window
                    .cookies()
                    .map_err(|_| "No se pudo leer el perfil de acceso.".to_string())?;
                for cookie in cookies {
                    let domain = cookie.domain().unwrap_or_default().trim_start_matches('.');
                    if domain == "google.com"
                        || domain.ends_with(".google.com")
                        || domain == "youtube.com"
                        || domain.ends_with(".youtube.com")
                    {
                        window
                            .delete_cookie(cookie)
                            .map_err(|_| "No se pudo borrar el perfil de acceso.".to_string())?;
                    }
                }
                Ok(())
            });
        let _ = tx.send(result);
    })
    .map_err(|_| "No se pudo limpiar el perfil de acceso.".to_string())?;
    rx.await
        .map_err(|_| "No se pudo limpiar el perfil de acceso.".to_string())?
}

pub async fn restore(app: AppHandle, core: Arc<sideb_core::SideBCore>) {
    let generation = auth_generation(&app);
    let dir = match app.path().app_data_dir() {
        Ok(dir) => dir,
        Err(_) => return,
    };
    let state = app.state::<AppState>();
    let _auth_operation = state.auth_operation.write().await;
    let guest = state
        .auth
        .read()
        .map(|status| status.state == "guest")
        .unwrap_or(false);
    if !guest || auth_generation(&app) != generation {
        return;
    }
    match session_store::load(&dir) {
        Ok(Some(cookie)) if has_sapisid(&cookie) => {
            core.set_cookie_memory(Some(cookie));
            let mut validation = validate_session(&app, &core, generation).await;
            if matches!(validation, Validation::Rejected) && auth_generation(&app) == generation {
                validation = renew_session(&app, &core, generation).await;
            }
            if auth_generation(&app) != generation {
                return;
            }
            match validation {
                Validation::Ready(info) => {
                    if let Some(latest_cookie) = core.get_cookie() {
                        let _ = session_store::save(&dir, &latest_cookie);
                    }
                    set_auth_status(&app, AuthStatusDto::ready(info));
                }
                Validation::Rejected => {
                    core.set_cookie_memory(None);
                    set_auth_status(
                        &app,
                        AuthStatusDto::error(
                            "No se pudo restaurar la sesión. Iniciá sesión de nuevo.",
                        ),
                    );
                }
                // The stored jar stays on disk untouched: the next start tries it again.
                Validation::Unreachable => {
                    core.set_cookie_memory(None);
                    set_auth_status(
                        &app,
                        AuthStatusDto::error(
                            "No se pudo conectar para restaurar la sesión. Revisá la conexión e iniciá sesión de nuevo.",
                        ),
                    );
                }
            }
        }
        Ok(Some(_)) => set_auth_status(
            &app,
            AuthStatusDto::error("La sesión guardada no es válida."),
        ),
        Err(_) => set_auth_status(
            &app,
            AuthStatusDto::error("No se pudo abrir la sesión protegida."),
        ),
        Ok(None) => {}
    }
}

pub async fn watch_rotations(app: AppHandle, core: Arc<sideb_core::SideBCore>) {
    loop {
        if core.wait_for_cookie_rotation().await.is_none() {
            break;
        }
        let state = app.state::<AppState>();
        let _auth_operation = state.auth_operation.read().await;
        let ready = state
            .auth
            .read()
            .map(|status| status.state == "ready")
            .unwrap_or(false);
        // Read the jar after the lock: a sign-in or renewal that was holding it has since
        // replaced the one this rotation belonged to, and that older jar must not be saved over it.
        if let (true, Some(cookie), Ok(dir)) = (ready, core.get_cookie(), app.path().app_data_dir())
        {
            let _ = session_store::save(&dir, &cookie);
        }
    }
}

/// What the health watcher should do with a session the app still shows as signed in.
#[derive(Debug, PartialEq)]
enum HealthStep {
    Wait,
    /// Ask YouTube whether the jar still authenticates.
    Validate,
    /// The core already dropped the jar after a rejection: renew without asking again.
    Renew,
}

fn health_step(core_has_cookie: bool, since_validation: Duration) -> HealthStep {
    if !core_has_cookie {
        HealthStep::Renew
    } else if since_validation >= HEALTH_VALIDATION_INTERVAL {
        HealthStep::Validate
    } else {
        HealthStep::Wait
    }
}

/// Keeps a signed-in session alive while the app stays open. Nothing else notices a jar that
/// YouTube stops accepting mid-run: requests just start failing, and the core answers a rejected
/// Home by dropping the jar and serving the anonymous feed under a "ready" account.
pub async fn watch_health(app: AppHandle, core: Arc<sideb_core::SideBCore>) {
    let mut since_validation = Duration::ZERO;
    loop {
        tokio::time::sleep(HEALTH_TICK).await;
        let state = app.state::<AppState>();
        let current = state.core.read().ok().and_then(|lock| lock.clone());
        if !current.is_some_and(|current| Arc::ptr_eq(&current, &core)) {
            break;
        }
        let ready = state
            .auth
            .read()
            .map(|status| status.state == "ready")
            .unwrap_or(false);
        if !ready {
            since_validation = Duration::ZERO;
            continue;
        }
        since_validation += HEALTH_TICK;
        let generation = auth_generation(&app);
        let rejected = match health_step(core.is_logged_in(), since_validation) {
            HealthStep::Wait => continue,
            HealthStep::Renew => true,
            // Without the exclusive lock: a healthy session must not stall other requests.
            HealthStep::Validate => matches!(
                classify_validation(core.get_account_info().await),
                Validation::Rejected
            ),
        };
        since_validation = Duration::ZERO;
        if rejected {
            recover_session(&app, &core, generation).await;
        }
    }
}

/// Renews a rejected session in place. Requests wait on the lock instead of failing against the
/// dead jar; the same account keeps its generation, so playback and the queue are not interrupted.
async fn recover_session(app: &AppHandle, core: &sideb_core::SideBCore, generation: u64) {
    let state = app.state::<AppState>();
    let _auth_operation = state.auth_operation.write().await;
    let previous = state
        .auth
        .read()
        .ok()
        .filter(|status| status.state == "ready")
        .map(|status| status.channel_id.clone());
    let Some(previous_channel) = previous else {
        return;
    };
    if auth_generation(app) != generation {
        return;
    }
    let validation = renew_session(app, core, generation).await;
    if auth_generation(app) != generation {
        return;
    }
    match validation {
        Validation::Ready(info) => {
            if let (Some(cookie), Ok(dir)) = (core.get_cookie(), app.path().app_data_dir()) {
                let _ = session_store::save(&dir, &cookie);
            }
            if info.channel_id != previous_channel {
                state.auth_generation.fetch_add(1, Ordering::SeqCst);
            }
            set_auth_status(app, AuthStatusDto::ready(info));
        }
        Validation::Rejected => {
            state.auth_generation.fetch_add(1, Ordering::SeqCst);
            core.set_cookie_memory(None);
            set_auth_status(
                app,
                AuthStatusDto::error("La sesión venció. Iniciá sesión de nuevo."),
            );
        }
        // Renewed jar installed but unconfirmed: the next tick validates it again.
        Validation::Unreachable => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn account(name: Option<&str>) -> sideb_core::AccountInfoRecord {
        sideb_core::AccountInfoRecord {
            name: name.map(str::to_owned),
            handle: None,
            email: None,
            thumbnail: None,
            channel_id: None,
        }
    }

    #[test]
    fn only_an_answer_from_youtube_counts_as_a_rejected_session() {
        assert!(matches!(
            classify_validation(Ok(account(Some("Listener")))),
            Validation::Ready(_)
        ));
        // The signed-out account menu parses fine and simply has no account in it.
        assert!(matches!(
            classify_validation(Ok(account(None))),
            Validation::Rejected
        ));
        // Exactly what the core builds from a 401/403: `innertube::Error::SessionExpired` through
        // `From<innertube::Error> for SideBError`.
        let expired = sideb_core::SideBError::NetworkError {
            message:
                "Your YouTube Music session expired — open the account menu and sign in again."
                    .into(),
        };
        assert!(matches!(
            classify_validation(Err(expired)),
            Validation::Rejected
        ));
        let offline = sideb_core::SideBError::NetworkError {
            message: "http: error sending request for url (https://music.youtube.com/youtubei/v1/account/account_menu)".into(),
        };
        assert!(matches!(
            classify_validation(Err(offline)),
            Validation::Unreachable
        ));
        let server = sideb_core::SideBError::NetworkError {
            message: "HTTP 503 Service Unavailable: ".into(),
        };
        assert!(matches!(
            classify_validation(Err(server)),
            Validation::Unreachable
        ));
    }

    #[test]
    fn health_watcher_validates_on_schedule_and_renews_a_dropped_jar_at_once() {
        assert_eq!(health_step(true, HEALTH_TICK), HealthStep::Wait);
        assert_eq!(
            health_step(true, HEALTH_VALIDATION_INTERVAL),
            HealthStep::Validate
        );
        assert_eq!(health_step(false, HEALTH_TICK), HealthStep::Renew);
    }

    #[test]
    fn every_webview_shares_the_arguments_that_keep_sign_ins_unbound() {
        let config: serde_json::Value =
            serde_json::from_str(include_str!("../tauri.conf.json")).unwrap();
        let windows = config["app"]["windows"].as_array().unwrap();
        assert!(!windows.is_empty());
        for window in windows {
            assert_eq!(
                window["additionalBrowserArgs"].as_str(),
                Some(WEBVIEW_BROWSER_ARGS)
            );
        }
        let disabled: Vec<&str> = WEBVIEW_BROWSER_ARGS
            .split_whitespace()
            .find_map(|argument| argument.strip_prefix("--disable-features="))
            .unwrap()
            .split(',')
            .collect();
        assert!(disabled.contains(&"DeviceBoundSessions"));
        // What wry passes when no arguments are given; overriding them must not drop any.
        for default in ["msWebOOUI", "msPdfOOUI", "msSmartScreenProtection"] {
            assert!(disabled.contains(&default));
        }
        assert!(WEBVIEW_BROWSER_ARGS.contains("--autoplay-policy=no-user-gesture-required"));
    }

    #[test]
    fn exports_youtube_cookies_only() {
        let parse = |value: &str| Cookie::parse(value.to_string()).unwrap();
        let header = youtube_cookie_header(vec![
            parse("SAPISID=main; Domain=.youtube.com"),
            parse("SID=video; Domain=music.youtube.com"),
            parse("SAPISID=google; Domain=.google.com"),
            parse("UNSCOPED=other"),
        ]);
        assert_eq!(header, "SAPISID=main; SID=video");
        assert!(has_sapisid(&header));
        assert!(!has_sapisid("SID=video; VISITOR_INFO1_LIVE=test"));
    }
}
