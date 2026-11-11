//! WebView2 pieces of the host: the one-time login window and the silent token source.
//!
//! The provider's web page is the only thing that can mint a Web Player Bearer, so both use the
//! provider's own pages inside the app's WebView2 profile (shared with the rest of the app; the
//! session the user creates once in the login window is reused by the silent web views).
//! Nothing here sends the token anywhere: an injected hook (`js/hook.js`) remembers the tokens the
//! page itself uses and Rust polls that slot with `eval_with_callback`. These web views have no
//! IPC capability (capabilities only name the `main` window), so a remote page cannot call commands.

use super::host::{BoxFuture, TokenSource};
use super::lease;
use super::policy;
use super::protocol::Auth;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tauri::webview::PageLoadEvent;
use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindow, WebviewWindowBuilder};

pub const HOOK_JS: &str = include_str!("js/hook.js");
pub const BODY_JS: &str = include_str!("js/body.js");
pub const READ_JS: &str = include_str!("js/read.js");
pub const LOGIN_LABEL: &str = "sideb-vp-login";

const SILENT_TIMEOUT: Duration = Duration::from_secs(14);
const SILENT_POLL: Duration = Duration::from_millis(500);
const EXTRACT_EVERY: Duration = Duration::from_secs(1);
const EXTRACT_ATTEMPTS: u32 = 6;
const LOGIN_POLL: Duration = Duration::from_millis(1200);
const LOGIN_FAST_ATTEMPTS: u32 = 40;

fn pull_script(token_url: &str) -> String {
    let url = serde_json::to_string(token_url).unwrap_or_else(|_| "\"\"".into());
    format!("(function(){{var s=window.__sidebVp;if(s&&s.pull)s.pull({url});return null;}})()")
}

/// Build on the main thread (as `session.rs` does) and hand the window back to async code.
async fn build_on_main<F>(app: &AppHandle, build: F) -> Option<WebviewWindow>
where
    F: FnOnce(&AppHandle) -> tauri::Result<WebviewWindow> + Send + 'static,
{
    let (tx, rx) = tokio::sync::oneshot::channel();
    let handle = app.clone();
    app.run_on_main_thread(move || {
        let _ = tx.send(build(&handle).ok());
    })
    .ok()?;
    rx.await.ok().flatten()
}

fn destroy_on_main(app: &AppHandle, label: String) {
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        if let Some(window) = handle.get_webview_window(&label) {
            let _ = window.destroy();
        }
    });
}

/// Destroys its window however the owning future ends (including being dropped).
struct WindowGuard {
    app: AppHandle,
    label: String,
}

impl Drop for WindowGuard {
    fn drop(&mut self) {
        destroy_on_main(&self.app, std::mem::take(&mut self.label));
    }
}

async fn eval_json(window: &WebviewWindow, js: &str) -> Option<String> {
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<String>();
    window
        .eval_with_callback(js, move |json| {
            let _ = tx.send(json);
        })
        .ok()?;
    tokio::time::timeout(Duration::from_secs(3), rx.recv())
        .await
        .ok()
        .flatten()
}

async fn eval_tokens(window: &WebviewWindow, js: &str) -> Vec<String> {
    eval_json(window, js)
        .await
        .map(|json| policy::tokens_from_eval(&json))
        .unwrap_or_default()
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Strategy {
    /// Load the site root: its own scripts request a token, which the injected hook observes.
    HomePage,
    /// Load another page so a different set of authenticated requests is issued.
    SearchPage,
    /// Navigate straight to the token endpoint and read its JSON body.
    TokenEndpoint,
}

/// Tries three independent strategies in order. Each runs in its own throw-away web view so a page
/// that is stuck, cached or served a different layout cannot poison the next attempt.
pub struct WebViewTokenSource {
    app: AppHandle,
}

impl WebViewTokenSource {
    pub fn new(app: AppHandle) -> Self {
        Self { app }
    }

    async fn refresh(
        &self,
        auth: &Auth,
        strategy: Strategy,
        rejected: Option<&str>,
    ) -> Option<String> {
        let target = match strategy {
            Strategy::HomePage => format!("https://{}/", auth.target_host),
            Strategy::SearchPage => format!("https://{}/search", auth.target_host),
            Strategy::TokenEndpoint => auth.token_url.clone(),
        };
        let url = tauri::Url::parse(&target).ok()?;
        let label = format!("sideb-vp-r-{}", lease::unique_name());
        let (loaded_tx, loaded) = tokio::sync::watch::channel(false);
        let page_auth = auth.clone();
        let window_label = label.clone();
        let window = build_on_main(&self.app, move |app| {
            let mut builder =
                WebviewWindowBuilder::new(app, window_label, WebviewUrl::External(url))
                    .additional_browser_args(crate::session::WEBVIEW_BROWSER_ARGS)
                    .title("Side B")
                    .inner_size(1100.0, 800.0)
                    .visible(false)
                    .skip_taskbar(true)
                    .focused(false)
                    .on_page_load(move |_, payload| {
                        if matches!(payload.event(), PageLoadEvent::Finished)
                            && payload
                                .url()
                                .host_str()
                                .is_some_and(|host| page_auth.is_target_host(host))
                        {
                            let _ = loaded_tx.send(true);
                        }
                    });
            if strategy != Strategy::TokenEndpoint {
                builder = builder.initialization_script(HOOK_JS);
            }
            builder.build()
        })
        .await?;
        let _guard = WindowGuard {
            app: self.app.clone(),
            label,
        };

        let started = Instant::now();
        let (mut extractions, mut last_extraction) = (0u32, None::<Instant>);
        while started.elapsed() < SILENT_TIMEOUT {
            tokio::time::sleep(SILENT_POLL).await;
            if !*loaded.borrow() {
                continue;
            }
            let tokens = if strategy == Strategy::TokenEndpoint {
                eval_tokens(&window, BODY_JS).await
            } else {
                // The page issues its own token request a moment after load: poll briefly.
                if extractions < EXTRACT_ATTEMPTS
                    && last_extraction.is_none_or(|at| at.elapsed() >= EXTRACT_EVERY)
                {
                    extractions += 1;
                    last_extraction = Some(Instant::now());
                    let _ = window.eval(pull_script(&auth.token_url));
                }
                eval_tokens(&window, READ_JS).await
            };
            if let Some(token) = policy::pick_token(&tokens, rejected) {
                return Some(token);
            }
        }
        None
    }
}

impl TokenSource for WebViewTokenSource {
    fn acquire<'a>(
        &'a self,
        auth: &'a Auth,
        rejected: Option<&'a str>,
    ) -> BoxFuture<'a, Option<String>> {
        Box::pin(async move {
            for strategy in [
                Strategy::HomePage,
                Strategy::SearchPage,
                Strategy::TokenEndpoint,
            ] {
                if let Some(token) = self.refresh(auth, strategy, rejected).await {
                    return Some(token);
                }
            }
            None
        })
    }
}

// MARK: Login window

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LoginState {
    Waiting,
    Extracting,
    Connected,
    Failed,
    Closed,
}

impl LoginState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Waiting => "waiting",
            Self::Extracting => "extracting",
            Self::Connected => "connected",
            Self::Failed => "failed",
            Self::Closed => "closed",
        }
    }
}

pub type TokenSink = Arc<dyn Fn(String) -> bool + Send + Sync>;
pub type StateSink = Arc<dyn Fn(LoginState) + Send + Sync>;

pub fn login_is_open(app: &AppHandle) -> bool {
    app.get_webview_window(LOGIN_LABEL).is_some()
}

pub fn close_login(app: &AppHandle) {
    destroy_on_main(app, LOGIN_LABEL.to_owned());
}

/// Opens the provider's login page once. An already open window is brought to the front.
/// `on_token` stores the credential and returns whether it was accepted.
pub async fn open_login(
    app: &AppHandle,
    auth: Auth,
    title: String,
    on_token: TokenSink,
    on_state: StateSink,
) -> bool {
    if let Some(existing) = app.get_webview_window(LOGIN_LABEL) {
        let handle = app.clone();
        let _ = app.run_on_main_thread(move || {
            let _ = existing.set_focus();
            drop(handle);
        });
        return true;
    }
    let Ok(url) = tauri::Url::parse(&auth.login_url) else {
        return false;
    };
    let loaded = Arc::new(AtomicBool::new(false));
    let load_generation = Arc::new(AtomicU64::new(0));
    let alive = Arc::new(AtomicBool::new(true));
    let finished = Arc::new(AtomicBool::new(false));
    let (page_auth, page_loaded, page_generation) =
        (auth.clone(), loaded.clone(), load_generation.clone());
    let (close_alive, close_finished, close_state) =
        (alive.clone(), finished.clone(), on_state.clone());

    let window = build_on_main(app, move |app| {
        let window = WebviewWindowBuilder::new(app, LOGIN_LABEL, WebviewUrl::External(url))
            .additional_browser_args(crate::session::WEBVIEW_BROWSER_ARGS)
            .title(title)
            .inner_size(540.0, 680.0)
            .min_inner_size(480.0, 600.0)
            .center()
            .initialization_script(HOOK_JS)
            .on_page_load(move |_, payload| {
                let on_target = payload
                    .url()
                    .host_str()
                    .is_some_and(|host| page_auth.is_target_host(host));
                match payload.event() {
                    // Leaving the provider's site (e.g. to the login form) pauses extraction.
                    PageLoadEvent::Started => page_loaded.store(false, Ordering::SeqCst),
                    PageLoadEvent::Finished if on_target => {
                        page_generation.fetch_add(1, Ordering::SeqCst);
                        page_loaded.store(true, Ordering::SeqCst);
                    }
                    PageLoadEvent::Finished => page_loaded.store(false, Ordering::SeqCst),
                }
            })
            .build()?;
        window.on_window_event(move |event| {
            if matches!(event, tauri::WindowEvent::Destroyed) {
                close_alive.store(false, Ordering::SeqCst);
                if !close_finished.swap(true, Ordering::SeqCst) {
                    close_state(LoginState::Closed);
                }
            }
        });
        Ok(window)
    })
    .await;
    let Some(window) = window else {
        on_state(LoginState::Failed);
        return false;
    };
    on_state(LoginState::Waiting);

    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let (mut seen_generation, mut attempts) = (0u64, 0u32);
        let mut announced = false;
        while alive.load(Ordering::SeqCst) {
            tokio::time::sleep(LOGIN_POLL).await;
            if !alive.load(Ordering::SeqCst) || !loaded.load(Ordering::SeqCst) {
                continue;
            }
            let generation = load_generation.load(Ordering::SeqCst);
            if generation != seen_generation {
                seen_generation = generation;
                attempts = 0;
            }
            if !announced {
                announced = true;
                on_state(LoginState::Extracting);
            }
            // The same page keeps getting asked for a while after each load; then it only listens.
            if attempts < LOGIN_FAST_ATTEMPTS {
                attempts += 1;
                let _ = window.eval(pull_script(&auth.token_url));
            }
            let tokens = eval_tokens(&window, READ_JS).await;
            if let Some(token) = policy::pick_token(&tokens, None) {
                finished.store(true, Ordering::SeqCst);
                if on_token(token) {
                    on_state(LoginState::Connected);
                    tokio::time::sleep(Duration::from_millis(1100)).await;
                } else {
                    on_state(LoginState::Failed);
                }
                close_login(&app);
                return;
            }
        }
    });
    true
}

/// Deletes the provider's cookies from the shared WebView2 profile (uninstall = really signed out).
pub fn forget_session(app: &AppHandle, auth: &Auth) {
    let domain = auth.cookie_domain();
    let handle = app.clone();
    // `cookies()` deadlocks on the main thread / sync handlers: use a plain worker thread.
    let _ = std::thread::Builder::new()
        .name("visual-provider-forget".into())
        .spawn(move || {
            let Some(window) = handle.get_webview_window("main") else {
                return;
            };
            let Ok(cookies) = window.cookies() else {
                return;
            };
            for cookie in cookies {
                let cookie_domain = cookie
                    .domain()
                    .unwrap_or_default()
                    .trim_start_matches('.')
                    .to_ascii_lowercase();
                if cookie_domain == domain || cookie_domain.ends_with(&format!(".{domain}")) {
                    let _ = window.delete_cookie(cookie);
                }
            }
        });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pull_script_embeds_the_url_as_a_json_literal() {
        let script = pull_script("https://open.spotify.com/get_access_token?a=1&b=\"2\"");
        assert!(script.contains(r#""https://open.spotify.com/get_access_token?a=1&b=\"2\"""#));
        assert!(script.starts_with("(function(){") && script.ends_with("})()"));
    }

    #[test]
    fn scripts_neither_exfiltrate_nor_touch_the_ipc_bridge() {
        for script in [HOOK_JS, BODY_JS, READ_JS] {
            for forbidden in [
                "__TAURI",
                "postMessage",
                "sendBeacon",
                "XMLHttpRequest.prototype.open",
                "localStorage",
                "document.cookie",
            ] {
                assert!(!script.contains(forbidden), "{forbidden}");
            }
        }
        // The only network call the hook may start is the token endpoint it is given.
        assert_eq!(HOOK_JS.matches("fetch(tokenUrl").count(), 1);
    }
}
