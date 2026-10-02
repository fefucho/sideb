//! Windows sign-in window. Google credentials stay in WebView2; only YouTube cookies cross into Rust.

use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Duration;

use tauri::webview::{cookie::Cookie, PageLoadEvent};
use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};

use crate::{auth_generation, session_store, set_auth_status, AppState, AuthStatusDto};

const LOGIN_LABEL: &str = "sideb-login";
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

    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<()>();
    let task_app = app.clone();
    tauri::async_runtime::spawn(async move {
        while rx.recv().await.is_some() && auth_generation(&task_app) == generation {
            for _ in 0..6 {
                if auth_generation(&task_app) != generation {
                    return;
                }
                if let Ok(cookie) = read_login_cookies(&task_app, LOGIN_LABEL).await {
                    if has_sapisid(&cookie) {
                        finish_login(task_app.clone(), generation, cookie).await;
                        return;
                    }
                }
                tokio::time::sleep(Duration::from_millis(500)).await;
            }
        }
    });

    let create_app = app.clone();
    if app
        .run_on_main_thread(move || {
            if let Some(old) = create_app.get_webview_window(LOGIN_LABEL) {
                let _ = old.destroy();
            }
            let url = match tauri::Url::parse(LOGIN_URL) {
                Ok(url) => url,
                Err(_) => {
                    set_auth_status(
                        &create_app,
                        AuthStatusDto::error("No se pudo preparar el acceso."),
                    );
                    return;
                }
            };
            // WebView2's default Windows/Edge user agent agrees with its client hints.
            let result =
                WebviewWindowBuilder::new(&create_app, LOGIN_LABEL, WebviewUrl::External(url))
                    .title("Iniciar sesión en YouTube Music")
                    .inner_size(480.0, 720.0)
                    .on_page_load(move |_window, payload| {
                        if matches!(payload.event(), PageLoadEvent::Finished)
                            && payload.url().host_str() == Some("music.youtube.com")
                        {
                            let _ = tx.send(());
                        }
                    })
                    .build();
            if result.is_err() {
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

async fn finish_login(app: AppHandle, generation: u64, cookie: String) {
    let state = app.state::<AppState>();
    let _auth_operation = state.auth_operation.lock().await;
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
    let _auth_operation = state.auth_operation.lock().await;
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
            match core.get_account_info().await {
                Ok(info) if info.name.is_some() && auth_generation(&app) == generation => {
                    if let Some(latest_cookie) = core.get_cookie() {
                        let _ = session_store::save(&dir, &latest_cookie);
                    }
                    set_auth_status(&app, AuthStatusDto::ready(info));
                }
                _ if auth_generation(&app) == generation => {
                    core.set_cookie_memory(None);
                    set_auth_status(
                        &app,
                        AuthStatusDto::error(
                            "No se pudo restaurar la sesión. Iniciá sesión de nuevo.",
                        ),
                    );
                }
                _ => {}
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
        let Some(cookie) = core.wait_for_cookie_rotation().await else {
            break;
        };
        let state = app.state::<AppState>();
        let _auth_operation = state.auth_operation.lock().await;
        let ready = state
            .auth
            .read()
            .map(|status| status.state == "ready")
            .unwrap_or(false);
        if ready {
            if let Ok(dir) = app.path().app_data_dir() {
                let _ = session_store::save(&dir, &cookie);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
