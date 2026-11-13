//! Spotify Jam runtime (PAR-062, `windows/plans/PLAN-028-spotify-jam.md`): owns the long-lived
//! `sideb-spotify-jam.exe` process (JSON lines over stdio, `extensions/README.md`), the Spotify
//! web-player token it needs, the libmpv speed used for sync corrections and the clock the sync
//! engine samples. The frontend (`src/lib/jam`) decides everything else.
//!
//! The Spotify session is independent of the Canvas plugin: the same WebView2 session and token
//! source are used, with their own constant `Auth`. The token never crosses IPC and is never logged.

use crate::dto::CommandError;
use crate::visual_provider::host::{Host, TokenSource};
use crate::visual_provider::protocol::Auth;
use crate::visual_provider::webview::WebViewTokenSource;
use crate::AppState;
use serde::Serialize;
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tauri::async_runtime::spawn_blocking;
use tauri::{AppHandle, Emitter, Manager};
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};

pub const EVENT: &str = "jam-event";
pub const EVENT_LOGIN: &str = "jam-spotify-login";
/// Relative location of the preinstalled plugin (same layout as the Canvas package).
pub const PLUGIN_RELATIVE: &str = "provider/spotify-jam";
pub const PLUGIN_EXECUTABLE: &str = "sideb-spotify-jam.exe";
/// `queue.source.kind` of the mirrored queue (`JAM_QUEUE_SOURCE_KIND` in the contract).
pub const QUEUE_SOURCE_KIND: &str = "jam";

/// Same values as `extensions/spotify-canvas/package/manifest.windows-x64.json` (`auth`); a test
/// keeps them from drifting, so the Jam never depends on the Canvas plugin being installed.
const AUTH_LOGIN_URL: &str = "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F";
const AUTH_TARGET_HOST: &str = "open.spotify.com";
const AUTH_TOKEN_URL: &str =
    "https://open.spotify.com/get_access_token?reason=transport&productType=web_player";

pub fn spotify_auth() -> Auth {
    Auth {
        kind: "webview".into(),
        login_url: AUTH_LOGIN_URL.into(),
        target_host: AUTH_TARGET_HOST.into(),
        token_url: AUTH_TOKEN_URL.into(),
    }
}

/// Web-player bearers live about an hour: renew well before that.
const RENEW_EVERY: Duration = Duration::from_secs(40 * 60);
/// Minimum spacing between two renewal attempts, however many errors arrive.
const RENEW_MIN_GAP: Duration = Duration::from_secs(30);
const RENEW_BACKOFF_CAP: Duration = Duration::from_secs(10 * 60);
/// A token younger than this is reused to join instead of opening web views again.
const TOKEN_REUSE: Duration = Duration::from_secs(30 * 60);
/// Time the plugin gets to leave on its own before it is killed.
const LEAVE_GRACE: Duration = Duration::from_secs(2);
const EXIT_GRACE: Duration = Duration::from_millis(300);
const MAX_OUTGOING_BYTES: usize = 16 * 1024;
const MAX_LINK_CHARS: usize = 2048;

pub const MIN_SPEED: f64 = 0.9;
pub const MAX_SPEED: f64 = 1.1;

// MARK: Pure helpers

pub fn clamp_speed(speed: f64) -> f64 {
    if speed.is_finite() {
        speed.clamp(MIN_SPEED, MAX_SPEED)
    } else {
        1.0
    }
}

/// Ordered candidates for `sideb-spotify-jam.exe`; nothing else is ever consulted.
pub fn plugin_candidates(
    resource_dir: Option<&Path>,
    exe_dir: Option<&Path>,
    debug_manifest_dir: Option<&Path>,
) -> Vec<PathBuf> {
    crate::visual_provider::candidates_under(
        PLUGIN_RELATIVE,
        resource_dir,
        exe_dir,
        debug_manifest_dir,
    )
    .into_iter()
    .map(|dir| dir.join(PLUGIN_EXECUTABLE))
    .collect()
}

pub fn first_plugin(candidates: &[PathBuf]) -> Option<PathBuf> {
    candidates.iter().find(|path| path.is_file()).cloned()
}

pub fn resolve_plugin(app: &AppHandle) -> Option<PathBuf> {
    let resources = app.path().resource_dir().ok();
    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(Path::to_path_buf));
    let debug_dir = cfg!(debug_assertions).then(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")));
    first_plugin(&plugin_candidates(
        resources.as_deref(),
        exe_dir.as_deref(),
        debug_dir.as_deref(),
    ))
}

/// A Jam link or bare token: one line, bounded, no control characters.
pub fn clean_link(link: &str) -> Option<String> {
    let link = link.trim();
    (!link.is_empty()
        && link.chars().count() <= MAX_LINK_CHARS
        && !link.chars().any(char::is_control))
    .then(|| link.to_owned())
}

/// The only messages the frontend may write: `command` and `resolve`. `join`, `credential` and
/// `leave` belong to the runtime. Returns the line to write (without the newline).
pub fn outgoing_line(message: &Value) -> Option<String> {
    let kind = message.as_object()?.get("type")?.as_str()?;
    if !matches!(kind, "command" | "resolve") {
        return None;
    }
    let line = serde_json::to_string(message).ok()?;
    (line.len() <= MAX_OUTGOING_BYTES).then_some(line)
}

/// `Some(true)` when a token is cached or the Canvas host holds a credential; otherwise what the
/// last attempt decided (`None` = unknown, `Some(false)` = failed or signed out).
pub fn signed_in_state(
    token_cached: bool,
    canvas_credential: bool,
    remembered: Option<bool>,
) -> Option<bool> {
    if token_cached || canvas_credential {
        Some(true)
    } else {
        remembered
    }
}

/// 30 s, 1 min, 2 min, ... capped.
pub fn renew_backoff(failures: u32) -> Duration {
    let factor = 1u32 << failures.saturating_sub(1).min(8);
    (RENEW_MIN_GAP * factor).min(RENEW_BACKOFF_CAP)
}

/// The plugin asks for a new credential with `error{code:"authRequired"}` (`extensions/spotify-jam`).
pub fn is_token_rejection(event: &Value) -> bool {
    event.get("type").and_then(Value::as_str) == Some("error")
        && event.get("code").and_then(Value::as_str) == Some("authRequired")
}

/// The instant a position was true: when the player reported it if it is still the playing
/// position (so the consumer can extrapolate), otherwise now.
pub fn position_sample_ms(
    position: f64,
    observed: Option<(f64, SystemTime)>,
    is_playing: bool,
    now: SystemTime,
) -> u64 {
    let at = match observed {
        Some((observed_position, at))
            if is_playing && observed_position == position && at <= now =>
        {
            at
        }
        _ => now,
    };
    at.duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_millis() as u64)
}

// MARK: DTOs

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JamStatus {
    pub plugin_available: bool,
    pub running: bool,
    pub signed_in: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JamClock {
    pub position_secs: f64,
    pub at_epoch_ms: u64,
    pub is_playing: bool,
    pub is_loading: bool,
    pub video_id: Option<String>,
    pub entry_id: Option<String>,
    pub generation: u64,
    pub auth_generation: u64,
    pub speed: f64,
}

// MARK: Runtime

struct CachedToken {
    value: String,
    at: Instant,
}

struct Session {
    id: u64,
    stdin: Sender<String>,
    child: Arc<Mutex<Child>>,
}

#[derive(Default)]
struct Inner {
    token: Option<CachedToken>,
    signed_in: Option<bool>,
    session: Option<Session>,
    speed: f64,
    next_id: u64,
    /// Bumped by `leave`, so a `join` that was still acquiring its token does not start afterwards.
    leave_epoch: u64,
}

pub struct JamRuntime {
    app: AppHandle,
    tokens: Arc<dyn TokenSource>,
    inner: Mutex<Inner>,
    /// Joins run one at a time (the token acquisition can take a while).
    join_lock: tokio::sync::Mutex<()>,
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn error(code: &str, message: &str) -> CommandError {
    CommandError::new(code, message)
}

/// Registers the runtime as managed state. Call once from `setup`.
pub fn init(app: &AppHandle) {
    app.manage(Arc::new(JamRuntime::new(app.clone())));
}

/// Stops the plugin when the app exits (stdin EOF would also make it leave).
pub fn shutdown(app: &AppHandle) {
    if let Some(runtime) = app.try_state::<Arc<JamRuntime>>() {
        let session = lock(&runtime.inner).session.take();
        if let Some(session) = session {
            stop_session(session, EXIT_GRACE);
        }
    }
}

impl JamRuntime {
    fn new(app: AppHandle) -> Self {
        Self {
            tokens: Arc::new(WebViewTokenSource::new(app.clone())),
            app,
            inner: Mutex::new(Inner {
                speed: 1.0,
                ..Default::default()
            }),
            join_lock: tokio::sync::Mutex::new(()),
        }
    }

    // MARK: Status

    pub fn status(&self) -> JamStatus {
        let canvas_credential = self
            .app
            .try_state::<Arc<Host>>()
            .is_some_and(|host| host.state().has_credential);
        let inner = lock(&self.inner);
        JamStatus {
            plugin_available: resolve_plugin(&self.app).is_some(),
            running: inner.session.is_some(),
            signed_in: signed_in_state(inner.token.is_some(), canvas_credential, inner.signed_in),
        }
    }

    // MARK: Token

    fn store_token(&self, token: String) {
        let mut inner = lock(&self.inner);
        inner.token = Some(CachedToken {
            value: token,
            at: Instant::now(),
        });
        inner.signed_in = Some(true);
    }

    fn fresh_token(&self) -> Option<String> {
        lock(&self.inner)
            .token
            .as_ref()
            .filter(|cached| cached.at.elapsed() < TOKEN_REUSE)
            .map(|cached| cached.value.clone())
    }

    fn cached_token(&self) -> Option<String> {
        lock(&self.inner)
            .token
            .as_ref()
            .map(|cached| cached.value.clone())
    }

    pub fn sign_out(&self) {
        {
            let mut inner = lock(&self.inner);
            inner.token = None;
            inner.signed_in = Some(false);
        }
        crate::visual_provider::webview::forget_session(&self.app, &spotify_auth());
    }

    /// Opens the Spotify login window; progress arrives as `jam-spotify-login` events. The token
    /// is kept for the Jam and, when the Canvas host has its package installed, saved there too
    /// so one login serves both.
    pub async fn open_login(self: &Arc<Self>, title: Option<String>) -> bool {
        use crate::visual_provider::webview::{self, LoginState};
        let title = title
            .map(|t| t.chars().take(100).collect::<String>())
            .filter(|t| !t.trim().is_empty())
            .unwrap_or_else(|| "Spotify".into());
        let runtime = self.clone();
        let state_app = self.app.clone();
        webview::open_login(
            &self.app,
            spotify_auth(),
            title,
            Arc::new(move |token| {
                if let Some(host) = runtime.app.try_state::<Arc<Host>>() {
                    let _ = host.save_credential(&token);
                }
                runtime.store_token(token);
                true
            }),
            Arc::new(move |state: LoginState| {
                let _ = state_app.emit(EVENT_LOGIN, json!({ "state": state.as_str() }));
            }),
        )
        .await
    }

    // MARK: Join / leave / send

    pub async fn join(self: &Arc<Self>, link: String) -> Result<(), CommandError> {
        let link = clean_link(&link)
            .ok_or_else(|| error("JAM_START_FAILED", "El enlace del Jam no es válido."))?;
        let epoch = lock(&self.inner).leave_epoch;
        let _serial = self.join_lock.lock().await;
        let exe = resolve_plugin(&self.app).ok_or_else(|| {
            error(
                "JAM_PLUGIN_MISSING",
                "No se encontró el componente de Spotify Jam.",
            )
        })?;
        let token = match self.fresh_token() {
            Some(token) => token,
            None => match self.tokens.acquire(&spotify_auth(), None).await {
                Some(token) => {
                    self.store_token(token.clone());
                    token
                }
                None => {
                    lock(&self.inner).signed_in = Some(false);
                    return Err(error(
                        "JAM_NOT_SIGNED_IN",
                        "Iniciá sesión en Spotify para unirte a un Jam.",
                    ));
                }
            },
        };
        let runtime = self.clone();
        let (id, renew) = spawn_blocking(move || runtime.start(exe, token, link, epoch))
            .await
            .map_err(|_| error("JAM_START_FAILED", "No se pudo iniciar Spotify Jam."))??;
        tauri::async_runtime::spawn(self.clone().renew_loop(id, renew));
        Ok(())
    }

    /// Blocking: replaces any running plugin, spawns the new one and starts its reader.
    fn start(
        self: &Arc<Self>,
        exe: PathBuf,
        token: String,
        link: String,
        epoch: u64,
    ) -> Result<(u64, UnboundedReceiver<()>), CommandError> {
        let failed = || error("JAM_START_FAILED", "No se pudo iniciar Spotify Jam.");
        let previous = {
            let mut inner = lock(&self.inner);
            if inner.leave_epoch != epoch {
                return Err(error("JAM_START_FAILED", "Se canceló la unión al Jam."));
            }
            inner.session.take()
        };
        if let Some(previous) = previous {
            stop_session(previous, LEAVE_GRACE);
        }
        self.reset_speed();

        let mut child = spawn_plugin(&exe).map_err(|_| failed())?;
        let (Some(stdin), Some(stdout)) = (child.stdin.take(), child.stdout.take()) else {
            let _ = child.kill();
            let _ = child.wait();
            return Err(failed());
        };
        let (line_tx, line_rx) = channel::<String>();
        let join = json!({ "type": "join", "credential": token, "link": link });
        if line_tx.send(join.to_string()).is_err() {
            let _ = child.kill();
            let _ = child.wait();
            return Err(failed());
        }
        let child = Arc::new(Mutex::new(child));
        let id = {
            let mut inner = lock(&self.inner);
            inner.next_id += 1;
            let id = inner.next_id;
            inner.session = Some(Session {
                id,
                stdin: line_tx,
                child: child.clone(),
            });
            id
        };
        spawn_writer(stdin, line_rx);
        let (renew_tx, renew_rx) = unbounded_channel();
        let runtime = self.clone();
        let reader = std::thread::Builder::new()
            .name("jam-stdout".into())
            .spawn(move || runtime.read_loop(id, stdout, child, renew_tx));
        if reader.is_err() {
            if let Some(session) = lock(&self.inner).session.take() {
                stop_session(session, Duration::ZERO);
            }
            return Err(failed());
        }
        Ok((id, renew_rx))
    }

    pub async fn leave(self: &Arc<Self>) {
        let session = {
            let mut inner = lock(&self.inner);
            inner.leave_epoch += 1;
            inner.session.take()
        };
        self.reset_speed();
        if let Some(session) = session {
            let _ = spawn_blocking(move || stop_session(session, LEAVE_GRACE)).await;
        }
    }

    pub fn send(&self, message: &Value) -> Result<(), CommandError> {
        let line = outgoing_line(message).ok_or_else(|| {
            error(
                "JAM_INVALID_MESSAGE",
                "El mensaje para Spotify Jam no es válido.",
            )
        })?;
        let inner = lock(&self.inner);
        let session = inner
            .session
            .as_ref()
            .ok_or_else(|| error("JAM_NOT_RUNNING", "No hay un Jam en curso."))?;
        session
            .stdin
            .send(line)
            .map_err(|_| error("JAM_NOT_RUNNING", "No hay un Jam en curso."))
    }

    fn is_current(&self, id: u64) -> bool {
        lock(&self.inner)
            .session
            .as_ref()
            .is_some_and(|session| session.id == id)
    }

    fn send_to(&self, id: u64, line: String) {
        if let Some(session) = lock(&self.inner)
            .session
            .as_ref()
            .filter(|session| session.id == id)
        {
            let _ = session.stdin.send(line);
        }
    }

    // MARK: Process output

    /// Runs on its own thread: forwards every stdout line as `jam-event` while this session is the
    /// current one, and cleans up when the process ends.
    fn read_loop(
        self: Arc<Self>,
        id: u64,
        stdout: ChildStdout,
        child: Arc<Mutex<Child>>,
        renew: UnboundedSender<()>,
    ) {
        let mut reader = BufReader::new(stdout);
        let mut buffer = Vec::new();
        let mut ended = false;
        loop {
            buffer.clear();
            match reader.read_until(b'\n', &mut buffer) {
                Ok(0) | Err(_) => break,
                Ok(_) => {}
            }
            let Ok(event) = serde_json::from_slice::<Value>(&buffer) else {
                continue;
            };
            let Some(kind) = event.get("type").and_then(Value::as_str) else {
                continue;
            };
            if !self.is_current(id) {
                continue;
            }
            if kind == "ended" {
                ended = true;
            }
            if is_token_rejection(&event) {
                let _ = renew.send(());
            }
            let _ = self.app.emit(EVENT, &event);
        }
        let code = reap(&child, Duration::from_secs(3));
        let current = {
            let mut inner = lock(&self.inner);
            if inner.session.as_ref().is_some_and(|session| session.id == id) {
                inner.session = None;
                true
            } else {
                false
            }
        };
        // Replaced or left on purpose: the owner already restored the speed and nobody listens.
        if current {
            self.reset_speed();
            if !ended {
                let _ = self.app.emit(EVENT, json!({ "type": "exited", "code": code }));
            }
        }
    }

    // MARK: Token renewal

    /// One attempt at a time: every 40 minutes, and whenever the plugin reports a rejected token
    /// (then the rejected token is never handed back). Failures back off; errors that pile up
    /// while waiting are coalesced into one attempt.
    async fn renew_loop(self: Arc<Self>, id: u64, mut rejections: UnboundedReceiver<()>) {
        let mut failures = 0u32;
        let mut wait = RENEW_EVERY;
        let mut pending = false;
        loop {
            let rejected = if pending {
                true
            } else {
                match tokio::time::timeout(wait, rejections.recv()).await {
                    Ok(Some(())) => true,
                    Ok(None) => return,
                    Err(_) => false,
                }
            };
            pending = false;
            while rejections.try_recv().is_ok() {}
            if !self.is_current(id) {
                return;
            }
            let previous = if rejected { self.cached_token() } else { None };
            match self
                .tokens
                .acquire(&spotify_auth(), previous.as_deref())
                .await
            {
                Some(token) => {
                    failures = 0;
                    wait = RENEW_EVERY;
                    self.store_token(token.clone());
                    self.send_to(
                        id,
                        json!({ "type": "credential", "credential": token }).to_string(),
                    );
                }
                None => {
                    failures = failures.saturating_add(1);
                    wait = renew_backoff(failures);
                }
            }
            tokio::time::sleep(RENEW_MIN_GAP).await;
            while rejections.try_recv().is_ok() {
                pending = true;
            }
            if !self.is_current(id) {
                return;
            }
        }
    }

    // MARK: Speed and clock

    fn player(&self) -> Option<Arc<player::Player>> {
        self.app
            .state::<AppState>()
            .player
            .read()
            .ok()
            .and_then(|player| player.clone())
    }

    /// libmpv keeps its speed across files: it returns to 1 whenever no Jam is running.
    fn reset_speed(&self) {
        lock(&self.inner).speed = 1.0;
        if let Some(player) = self.player() {
            let _ = player.set_speed(1.0);
        }
    }

    pub fn set_speed(&self, speed: f64) -> Result<(), CommandError> {
        let target = {
            let mut inner = lock(&self.inner);
            let target = if inner.session.is_some() {
                clamp_speed(speed)
            } else {
                1.0
            };
            inner.speed = target;
            target
        };
        let player = self.player().ok_or_else(|| {
            error(
                "PLAYER_NOT_INITIALIZED",
                "El reproductor de audio no está listo.",
            )
        })?;
        player
            .set_speed(target)
            .map_err(|_| error("JAM_SPEED_FAILED", "No se pudo cambiar la velocidad."))
    }

    /// The freshest audible position the runtime tracks (the `time-pos` the player last reported;
    /// the `player` crate has no synchronous getter), with the instant it was true.
    pub fn clock(&self) -> Result<JamClock, CommandError> {
        let speed = lock(&self.inner).speed;
        let state = self.app.state::<AppState>();
        let playback = state
            .playback
            .lock()
            .map_err(|_| error("LOCK_ERROR", "No se pudo leer el reproductor."))?;
        let now = SystemTime::now();
        Ok(JamClock {
            position_secs: playback.position,
            at_epoch_ms: position_sample_ms(
                playback.position,
                playback.position_observed,
                playback.is_playing,
                now,
            ),
            is_playing: playback.is_playing,
            is_loading: playback.is_loading,
            video_id: playback
                .current_track
                .as_ref()
                .map(|track| track.video_id.clone()),
            entry_id: playback.queue.current().map(|entry| entry.entry_id),
            generation: playback.generation,
            auth_generation: playback.observed_auth_generation,
            speed,
        })
    }
}

// MARK: Process plumbing

fn spawn_plugin(exe: &Path) -> std::io::Result<Child> {
    let mut command = Command::new(exe);
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .env_clear();
    for name in [
        "SystemRoot",
        "SystemDrive",
        "windir",
        "HTTPS_PROXY",
        "HTTP_PROXY",
        "ALL_PROXY",
        "NO_PROXY",
    ] {
        if let Some(value) = std::env::var_os(name) {
            command.env(name, value);
        }
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        command.creation_flags(CREATE_NO_WINDOW);
    }
    command.spawn()
}

/// Writes queued lines to the plugin so no caller ever blocks on the pipe. Dropping the sender
/// ends the thread, which closes stdin (EOF = leave).
fn spawn_writer(mut stdin: ChildStdin, lines: Receiver<String>) {
    let _ = std::thread::Builder::new()
        .name("jam-stdin".into())
        .spawn(move || {
            for line in lines {
                if stdin
                    .write_all(line.as_bytes())
                    .and_then(|_| stdin.write_all(b"\n"))
                    .and_then(|_| stdin.flush())
                    .is_err()
                {
                    break;
                }
            }
        });
}

/// Waits for the process to exit (polling, so the child lock is never held while waiting) and
/// kills it after `grace`. Returns its exit code if it had one.
fn reap(child: &Arc<Mutex<Child>>, grace: Duration) -> Option<i32> {
    let started = Instant::now();
    loop {
        {
            let mut child = lock(child);
            match child.try_wait() {
                Ok(Some(status)) => return status.code(),
                Ok(None) if started.elapsed() >= grace => {
                    let _ = child.kill();
                    return child.wait().ok().and_then(|status| status.code());
                }
                Ok(None) => {}
                Err(_) => return None,
            }
        }
        std::thread::sleep(Duration::from_millis(40));
    }
}

/// `leave`, close stdin, give the plugin `grace` to exit, then kill it. Blocking.
fn stop_session(session: Session, grace: Duration) {
    let Session { stdin, child, .. } = session;
    let _ = stdin.send(json!({ "type": "leave" }).to_string());
    drop(stdin);
    reap(&child, grace);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spotify_auth_matches_the_canvas_manifest() {
        let manifest: Value = serde_json::from_str(include_str!(
            "../../../../extensions/spotify-canvas/package/manifest.windows-x64.json"
        ))
        .unwrap();
        let canvas: Auth = serde_json::from_value(manifest["auth"].clone()).unwrap();
        assert_eq!(spotify_auth(), canvas);
        assert!(spotify_auth().validate().is_ok());
    }

    #[test]
    fn only_command_and_resolve_may_be_sent() {
        for kind in ["command", "resolve"] {
            let line = outgoing_line(&json!({ "type": kind, "action": "pause" })).unwrap();
            assert!(!line.contains('\n'));
            assert_eq!(serde_json::from_str::<Value>(&line).unwrap()["type"], kind);
        }
        for message in [
            json!({ "type": "join", "credential": "x", "link": "y" }),
            json!({ "type": "credential", "credential": "x" }),
            json!({ "type": "leave" }),
            json!({ "type": 5 }),
            json!({ "action": "pause" }),
            json!("command"),
            json!(["command"]),
            Value::Null,
        ] {
            assert_eq!(outgoing_line(&message), None, "{message}");
        }
        let huge = json!({ "type": "resolve", "title": "x".repeat(MAX_OUTGOING_BYTES) });
        assert_eq!(outgoing_line(&huge), None);
    }

    #[test]
    fn links_are_one_bounded_line() {
        assert_eq!(
            clean_link("  https://open.spotify.com/socialsession/abc  ").as_deref(),
            Some("https://open.spotify.com/socialsession/abc")
        );
        assert_eq!(clean_link("abc").as_deref(), Some("abc"));
        assert_eq!(clean_link("   "), None);
        assert_eq!(clean_link("a\nb"), None);
        assert_eq!(clean_link(&"a".repeat(MAX_LINK_CHARS + 1)), None);
    }

    #[test]
    fn speed_is_clamped_to_the_correction_range() {
        assert_eq!(clamp_speed(0.5), 0.9);
        assert_eq!(clamp_speed(2.0), 1.1);
        assert_eq!(clamp_speed(1.05), 1.05);
        assert_eq!(clamp_speed(f64::NAN), 1.0);
        assert_eq!(clamp_speed(f64::INFINITY), 1.0);
    }

    #[test]
    fn plugin_candidates_follow_the_canvas_order() {
        let (res, exe, dbg) = (Path::new("R"), Path::new("E"), Path::new("D"));
        let at = |base: &str, extra: &str| {
            let mut path = PathBuf::from(base);
            if !extra.is_empty() {
                path.push(extra);
            }
            path.join(PLUGIN_RELATIVE).join(PLUGIN_EXECUTABLE)
        };
        assert_eq!(
            plugin_candidates(Some(res), Some(exe), Some(dbg)),
            vec![
                at("R", ""),
                at("E", ""),
                at("R", "resources"),
                at("E", "resources"),
                at("D", "")
            ]
        );
        assert!(plugin_candidates(None, None, None).is_empty());
    }

    #[test]
    fn first_plugin_skips_missing_files_and_directories() {
        let base = std::env::temp_dir().join(format!("sideb-jam-plugin-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        std::fs::create_dir_all(base.join("a")).unwrap();
        std::fs::create_dir_all(base.join("b")).unwrap();
        std::fs::write(base.join("b").join(PLUGIN_EXECUTABLE), b"MZ").unwrap();
        // A directory named like the executable is not a plugin.
        std::fs::create_dir_all(base.join("a").join(PLUGIN_EXECUTABLE)).unwrap();
        let candidates = [
            base.join("missing").join(PLUGIN_EXECUTABLE),
            base.join("a").join(PLUGIN_EXECUTABLE),
            base.join("b").join(PLUGIN_EXECUTABLE),
        ];
        assert_eq!(first_plugin(&candidates), Some(candidates[2].clone()));
        assert_eq!(first_plugin(&candidates[..2]), None);
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn signed_in_prefers_evidence_over_the_remembered_answer() {
        assert_eq!(signed_in_state(true, false, Some(false)), Some(true));
        assert_eq!(signed_in_state(false, true, None), Some(true));
        assert_eq!(signed_in_state(false, false, None), None);
        assert_eq!(signed_in_state(false, false, Some(false)), Some(false));
    }

    #[test]
    fn renewal_backs_off_and_never_loops_tightly() {
        assert_eq!(renew_backoff(1), Duration::from_secs(30));
        assert_eq!(renew_backoff(2), Duration::from_secs(60));
        assert_eq!(renew_backoff(3), Duration::from_secs(120));
        assert_eq!(renew_backoff(50), RENEW_BACKOFF_CAP);
        assert!(renew_backoff(0) >= RENEW_MIN_GAP);
    }

    #[test]
    fn only_auth_required_errors_trigger_a_renewal() {
        assert!(is_token_rejection(
            &json!({ "type": "error", "code": "authRequired", "retryable": true })
        ));
        assert!(!is_token_rejection(
            &json!({ "type": "error", "code": "network", "retryable": true })
        ));
        assert!(!is_token_rejection(&json!({ "type": "notice", "code": "authRequired" })));
    }

    #[test]
    fn clock_instant_is_the_observation_only_while_it_is_still_the_position() {
        let now = UNIX_EPOCH + Duration::from_millis(10_000);
        let seen = UNIX_EPOCH + Duration::from_millis(9_950);
        assert_eq!(position_sample_ms(12.5, Some((12.5, seen)), true, now), 9_950);
        // A seek moved the position without a fresh observation: sample "now".
        assert_eq!(position_sample_ms(30.0, Some((12.5, seen)), true, now), 10_000);
        // Paused: the position is as true now as it was.
        assert_eq!(position_sample_ms(12.5, Some((12.5, seen)), false, now), 10_000);
        assert_eq!(position_sample_ms(0.0, None, true, now), 10_000);
        // An observation "from the future" (clock change) is not trusted.
        let future = UNIX_EPOCH + Duration::from_millis(11_000);
        assert_eq!(position_sample_ms(1.0, Some((1.0, future)), true, now), 10_000);
    }

    #[test]
    fn jam_status_and_clock_serialize_in_camel_case() {
        let status = serde_json::to_value(JamStatus {
            plugin_available: true,
            running: false,
            signed_in: None,
        })
        .unwrap();
        assert_eq!(
            status,
            json!({ "pluginAvailable": true, "running": false, "signedIn": null })
        );
        let clock = serde_json::to_value(JamClock {
            position_secs: 1.5,
            at_epoch_ms: 7,
            is_playing: true,
            is_loading: false,
            video_id: Some("v".into()),
            entry_id: None,
            generation: 2,
            auth_generation: 3,
            speed: 1.0,
        })
        .unwrap();
        for key in [
            "positionSecs",
            "atEpochMs",
            "isPlaying",
            "isLoading",
            "videoId",
            "entryId",
            "generation",
            "authGeneration",
            "speed",
        ] {
            assert!(clock.get(key).is_some(), "{key}");
        }
    }
}
