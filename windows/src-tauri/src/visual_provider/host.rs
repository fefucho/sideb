//! Provider host state machine, independent of Tauri so its flows run under `cargo test` on any OS
//! (Tauri-specific effects arrive through `Notifier`; web views through `TokenSource`).
//! Equivalent of `VisualProviderHost.swift` in its final macOS form (FIX-283/285/287/300).

use super::credential::CredentialStore;
use super::job::Job;
use super::policy::{self, BundledAction};
use super::protocol::{
    cache_key, validate_credential, Auth, Failure, Manifest, Outcome, Reply, Request, RequestTrack,
    MAX_EXECUTABLE_BYTES, MAX_MANIFEST_BYTES, OUTPUT_FILE_NAME, REQUEST_DEADLINE_SECS,
};
use super::singleflight::SingleFlight;
use super::{lease, mp4};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeSet, HashMap, VecDeque};
use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant, SystemTime};
use tauri::async_runtime::{spawn, spawn_blocking, JoinHandle};

pub const CACHE_MAX_BYTES: u64 = 200 * 1024 * 1024;
pub const CACHE_TARGET_BYTES: u64 = 150 * 1024 * 1024;

pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Obtains a fresh credential without user interaction, reusing the session the user created once
/// in the login window. `rejected` is a token the provider already refused: never return it again.
pub trait TokenSource: Send + Sync {
    fn acquire<'a>(
        &'a self,
        auth: &'a Auth,
        rejected: Option<&'a str>,
    ) -> BoxFuture<'a, Option<String>>;
}

/// Everything the host needs from the application shell.
pub trait Notifier: Send + Sync {
    /// Consumers must detach the video BEFORE its files are released.
    fn will_change(&self);
    fn changed(&self, state: &StateDto);
    /// Let the asset protocol serve this file (cache folder is allowed once; fallbacks per file).
    fn allow_asset(&self, path: &Path);
    /// Drop the provider's web session (cookies) from the shared WebView2 profile.
    fn forget_session(&self, auth: &Auth);
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderInfoDto {
    pub id: String,
    pub name: String,
    pub version: String,
    /// The provider can sign in through a web view (otherwise only a manual token exists).
    pub web_login: bool,
}

/// Safe to publish: never carries the credential, login URLs or file paths.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StateDto {
    pub installed: bool,
    pub bundled_available: bool,
    pub provider: Option<ProviderInfoDto>,
    pub enabled: bool,
    pub has_credential: bool,
    pub auth_blocked: bool,
    pub revision: u64,
    pub status_key: String,
    /// Mixed into the sidebar artwork identity so providers' videos are per track.
    pub identity_salt: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ArtworkRequest {
    pub video_id: String,
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub duration_seconds: Option<u64>,
    pub explicit: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AssetDto {
    pub asset_id: String,
    pub local_path: String,
    pub codec: String,
    pub width: u32,
    pub height: u32,
    pub frame_rate: f64,
    pub size_bytes: u64,
}

#[derive(Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct Prefs {
    enabled: bool,
    credential_saved_at_ms: Option<u64>,
    /// Provider ids the user uninstalled on purpose: a preinstalled copy never comes back for them.
    #[serde(default)]
    removed_ids: Vec<String>,
}

struct Inner {
    manifest: Option<Manifest>,
    enabled: bool,
    has_credential: bool,
    revision: u64,
    status_key: String,
    cached_credential: Option<String>,
    credential_read: bool,
    auth_blocked: bool,
    backoff_until: Option<Instant>,
    /// The last token the provider refused. A "new" token equal to it is not a recovery.
    rejected: Option<String>,
    next_proactive: Option<Instant>,
    last_foreground_retry: Option<Instant>,
    saved_at: Option<SystemTime>,
    removed_ids: BTreeSet<String>,
    jobs: HashMap<String, Arc<Job>>,
    tombstones: VecDeque<String>,
    background_recovery: Option<JoinHandle<()>>,
    recovery_generation: u64,
}

enum Step {
    Done(Option<AssetDto>),
    Retry,
}

pub struct Host {
    root: PathBuf,
    bundled_dir: Box<dyn Fn() -> Option<PathBuf> + Send + Sync>,
    credentials: Arc<dyn CredentialStore>,
    tokens: Arc<dyn TokenSource>,
    notifier: Arc<dyn Notifier>,
    inner: Mutex<Inner>,
    recovery: Arc<SingleFlight<Option<String>>>,
    /// Install, preinstall and uninstall never interleave (the preinstall runs at start-up).
    install_gate: tokio::sync::Mutex<()>,
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

impl Host {
    /// `root` is `<app local data>/VisualProviders` with `Installed/`, `Sessions/`, `Cache/`.
    pub fn new(
        root: PathBuf,
        bundled_dir: Box<dyn Fn() -> Option<PathBuf> + Send + Sync>,
        credentials: Arc<dyn CredentialStore>,
        tokens: Arc<dyn TokenSource>,
        notifier: Arc<dyn Notifier>,
    ) -> Arc<Self> {
        let prefs = Self::load_prefs(&root);
        let manifest = Self::read_manifest(&root.join("Installed")).ok();
        let has_credential = manifest.is_some() && credentials.exists();
        let status_key = match (&manifest, has_credential) {
            (Some(_), false) => "visualProvider.status.tokenRequired",
            _ => "visualProvider.status.idle",
        };
        let host = Arc::new(Self {
            bundled_dir,
            credentials,
            tokens,
            notifier,
            recovery: Arc::new(SingleFlight::default()),
            install_gate: tokio::sync::Mutex::new(()),
            inner: Mutex::new(Inner {
                enabled: prefs.enabled && manifest.is_some(),
                has_credential,
                manifest,
                revision: 0,
                status_key: status_key.into(),
                cached_credential: None,
                credential_read: false,
                auth_blocked: false,
                backoff_until: None,
                rejected: None,
                next_proactive: None,
                last_foreground_retry: None,
                saved_at: prefs
                    .credential_saved_at_ms
                    .map(|ms| SystemTime::UNIX_EPOCH + Duration::from_millis(ms)),
                removed_ids: prefs.removed_ids.into_iter().collect(),
                jobs: HashMap::new(),
                tombstones: VecDeque::new(),
                background_recovery: None,
                recovery_generation: 0,
            }),
            root,
        });
        let sessions = host.sessions_dir();
        // Crash leftovers only; never a lease that another running instance may still hold.
        drop(spawn_blocking(move || {
            lease::sweep_abandoned(&sessions, SystemTime::now(), &lease::process_exists)
        }));
        host
    }

    // MARK: Paths

    pub fn installed_dir(&self) -> PathBuf {
        self.root.join("Installed")
    }
    pub fn sessions_dir(&self) -> PathBuf {
        self.root.join("Sessions")
    }
    pub fn cache_root(&self) -> PathBuf {
        self.root.join("Cache")
    }
    fn prefs_path(root: &Path) -> PathBuf {
        root.join("state.json")
    }

    fn lock(&self) -> MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    // MARK: Persistence of non-secret preferences

    fn load_prefs(root: &Path) -> Prefs {
        std::fs::read(Self::prefs_path(root))
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default()
    }

    fn save_prefs(&self, inner: &Inner) {
        let prefs = Prefs {
            enabled: inner.enabled,
            credential_saved_at_ms: inner
                .saved_at
                .and_then(|at| at.duration_since(SystemTime::UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as u64),
            removed_ids: inner.removed_ids.iter().cloned().collect(),
        };
        if let Ok(bytes) = serde_json::to_vec(&prefs) {
            let _ = std::fs::create_dir_all(&self.root);
            let temp = self.root.join("state.json.tmp");
            if std::fs::write(&temp, bytes).is_ok() {
                let _ = std::fs::rename(&temp, Self::prefs_path(&self.root));
            }
        }
    }

    // MARK: Manifest

    /// Manifest and executable must be plain files (no symlinks), within size limits.
    pub fn read_manifest(package: &Path) -> Outcome<Manifest> {
        mp4::plain_file_size(&package.join("manifest.json"), MAX_MANIFEST_BYTES)?;
        let bytes = std::fs::read(package.join("manifest.json")).map_err(|_| Failure::Invalid)?;
        let manifest = Manifest::parse(&bytes)?;
        Self::executable_in(package, &manifest)?;
        Ok(manifest)
    }

    /// Windows packages name the file `*.exe`; a manifest written without the extension still works.
    fn executable_in(package: &Path, manifest: &Manifest) -> Outcome<PathBuf> {
        let direct = package.join(&manifest.executable);
        if mp4::plain_file_size(&direct, MAX_EXECUTABLE_BYTES).is_ok() {
            return Ok(direct);
        }
        if cfg!(windows) && !manifest.executable.to_ascii_lowercase().ends_with(".exe") {
            let with_extension = package.join(format!("{}.exe", manifest.executable));
            if mp4::plain_file_size(&with_extension, MAX_EXECUTABLE_BYTES).is_ok() {
                return Ok(with_extension);
            }
        }
        Err(Failure::Invalid)
    }

    // MARK: State

    pub fn state(&self) -> StateDto {
        let bundled_available =
            (self.bundled_dir)().is_some_and(|dir| Self::read_manifest(&dir).is_ok());
        Self::state_of(&self.lock(), bundled_available)
    }

    fn state_of(inner: &Inner, bundled_available: bool) -> StateDto {
        let identity = match (&inner.manifest, inner.enabled && inner.has_credential) {
            (Some(manifest), true) => Some(format!("{}:{}", manifest.id, inner.revision)),
            _ => None,
        };
        StateDto {
            installed: inner.manifest.is_some(),
            bundled_available,
            provider: inner.manifest.as_ref().map(|m| ProviderInfoDto {
                id: m.id.clone(),
                name: m.name.clone(),
                version: m.version.clone(),
                web_login: m.uses_webview_auth(),
            }),
            enabled: inner.enabled,
            has_credential: inner.has_credential,
            auth_blocked: inner.auth_blocked,
            revision: inner.revision,
            status_key: inner.status_key.clone(),
            identity_salt: identity,
        }
    }

    fn publish(&self) {
        self.notifier.changed(&self.state());
    }

    fn set_status(&self, key: impl Into<String>) {
        let key = key.into();
        {
            let mut inner = self.lock();
            if inner.status_key == key {
                return;
            }
            inner.status_key = key;
        }
        self.publish();
    }

    pub fn manifest(&self) -> Option<Manifest> {
        self.lock().manifest.clone()
    }

    // MARK: Invalidation, enable, install, uninstall

    /// Consumers detach their players synchronously-enough (event) before files are released.
    fn invalidate(&self) {
        self.notifier.will_change();
        let mut inner = self.lock();
        let active: Vec<Arc<Job>> = inner.jobs.drain().map(|(_, job)| job).collect();
        inner.auth_blocked = false;
        inner.backoff_until = None;
        if let Some(task) = inner.background_recovery.take() {
            task.abort();
        }
        inner.revision = inner.revision.wrapping_add(1);
        drop(inner);
        for job in active {
            spawn_blocking(move || job.cancel());
        }
    }

    /// Enabling requires an installed provider with a credential; the UI disables the switch otherwise.
    pub fn set_enabled(&self, enabled: bool) -> bool {
        {
            let inner = self.lock();
            if enabled == inner.enabled
                || (enabled && (inner.manifest.is_none() || !inner.has_credential))
            {
                return enabled == inner.enabled;
            }
        }
        self.lock().enabled = enabled;
        self.invalidate();
        self.save_prefs(&self.lock());
        self.publish();
        true
    }

    /// Only the manifest and one executable are installed: no symlinks, extra files or arguments.
    pub async fn install_from(self: &Arc<Self>, source: PathBuf) -> Outcome<()> {
        let _gate = self.install_gate.lock().await;
        let next = Self::read_manifest(&source)?;
        let id = next.id.clone();
        self.install_unlocked(source, next).await?;
        // Installing again is an explicit decision that revokes an earlier removal.
        let mut inner = self.lock();
        inner.removed_ids.remove(&id);
        self.save_prefs(&inner);
        Ok(())
    }

    async fn install_unlocked(self: &Arc<Self>, source: PathBuf, next: Manifest) -> Outcome<()> {
        let executable = Self::executable_in(&source, &next)?;
        let is_upgrade = self
            .lock()
            .manifest
            .as_ref()
            .is_some_and(|m| m.id == next.id);
        if !is_upgrade {
            self.lock().enabled = false;
        }
        self.invalidate();
        let (root, destination) = (self.root.clone(), self.installed_dir());
        let manifest_json = serde_json::to_vec(&next).map_err(|_| Failure::Invalid)?;
        let name = next.executable.clone();
        spawn_blocking(move || -> Outcome<()> {
            std::fs::create_dir_all(&root).map_err(|_| Failure::Unavailable)?;
            let staging = root.join(lease::unique_name());
            std::fs::create_dir(&staging).map_err(|_| Failure::Unavailable)?;
            let result = (|| {
                std::fs::copy(&executable, staging.join(&name))
                    .map_err(|_| Failure::Unavailable)?;
                std::fs::write(staging.join("manifest.json"), manifest_json)
                    .map_err(|_| Failure::Unavailable)?;
                // A just-cancelled provider process can hold its executable for a moment.
                let mut attempt = 0;
                while destination.exists() {
                    match std::fs::remove_dir_all(&destination) {
                        Ok(()) => break,
                        Err(_) if attempt < 8 => {
                            attempt += 1;
                            std::thread::sleep(Duration::from_millis(250));
                        }
                        Err(_) => return Err(Failure::Unavailable),
                    }
                }
                std::fs::rename(&staging, &destination).map_err(|_| Failure::Unavailable)
            })();
            let _ = std::fs::remove_dir_all(&staging);
            result
        })
        .await
        .map_err(|_| Failure::Unavailable)??;
        if !is_upgrade {
            self.credentials.delete().map_err(|_| Failure::Credential)?;
        }
        {
            let mut inner = self.lock();
            if !is_upgrade {
                inner.cached_credential = None;
                inner.credential_read = true;
                inner.has_credential = false;
                inner.saved_at = None;
            }
            inner.status_key = if inner.has_credential {
                "visualProvider.status.idle".into()
            } else {
                "visualProvider.status.tokenRequired".into()
            };
            inner.manifest = Some(next);
            inner.revision = inner.revision.wrapping_add(1);
            self.save_prefs(&inner);
        }
        self.publish();
        Ok(())
    }

    /// First launch of a build that ships the provider: install it, never enable it.
    pub async fn ensure_bundled(self: &Arc<Self>) {
        let Some(dir) = (self.bundled_dir)() else {
            return;
        };
        let _gate = self.install_gate.lock().await;
        let bundled = Self::read_manifest(&dir).ok();
        let (installed, removed) = {
            let inner = self.lock();
            let removed = bundled
                .as_ref()
                .is_some_and(|m| inner.removed_ids.contains(&m.id));
            (inner.manifest.clone(), removed)
        };
        match (
            policy::bundled_action(installed.as_ref(), bundled.as_ref(), removed),
            bundled,
        ) {
            (BundledAction::Nothing, _) | (_, None) => self.publish(),
            // A failed preinstall leaves the app exactly as it was; the manual installer remains.
            (_, Some(next)) => drop(self.install_unlocked(dir, next).await),
        }
    }

    /// Install the preinstalled package on explicit request (also after an uninstall).
    pub async fn install_bundled(self: &Arc<Self>) -> Outcome<()> {
        let dir = (self.bundled_dir)().ok_or(Failure::Invalid)?;
        self.install_from(dir).await
    }

    /// Deletes the plugin, its token, its cached videos and its web session. It is not reinstalled
    /// by itself afterwards (the decision persists).
    pub async fn uninstall(self: &Arc<Self>) -> Outcome<()> {
        let _gate = self.install_gate.lock().await;
        let bundled_id = (self.bundled_dir)()
            .and_then(|dir| Self::read_manifest(&dir).ok())
            .map(|m| m.id);
        let auth = {
            let mut inner = self.lock();
            if let Some(id) = inner.manifest.as_ref().map(|m| m.id.clone()).or(bundled_id) {
                inner.removed_ids.insert(id);
            }
            inner.enabled = false;
            inner.recovery_generation = inner.recovery_generation.wrapping_add(1);
            inner.manifest.as_ref().and_then(|m| m.auth.clone())
        };
        self.invalidate();
        let credential_result = self.credentials.delete();
        {
            let mut inner = self.lock();
            inner.saved_at = None;
            inner.cached_credential = None;
            inner.credential_read = true;
            inner.manifest = None;
            inner.has_credential = false;
            inner.rejected = None;
            inner.status_key = "visualProvider.status.idle".into();
            self.save_prefs(&inner);
        }
        if let Some(auth) = auth {
            self.notifier.forget_session(&auth);
        }
        let (installed, cache) = (self.installed_dir(), self.cache_root());
        spawn_blocking(move || {
            for dir in [installed, cache] {
                let mut attempt = 0;
                while dir.exists() && std::fs::remove_dir_all(&dir).is_err() && attempt < 8 {
                    attempt += 1;
                    std::thread::sleep(Duration::from_millis(250));
                }
            }
        })
        .await
        .map_err(|_| Failure::Unavailable)?;
        {
            let mut inner = self.lock();
            inner.revision = inner.revision.wrapping_add(1);
        }
        self.publish();
        credential_result.map_err(|_| Failure::Credential)
    }

    // MARK: Credential

    /// Manual token or a fresh login. Tears down running players (the identity changed).
    pub fn save_credential(&self, raw: &str) -> Outcome<()> {
        let token = validate_credential(raw)?;
        if self.lock().manifest.is_none() {
            return Err(Failure::Invalid);
        }
        self.invalidate();
        self.credentials
            .save(&token)
            .map_err(|_| Failure::Credential)?;
        {
            let mut inner = self.lock();
            inner.cached_credential = Some(token);
            inner.credential_read = true;
            inner.rejected = None;
            inner.saved_at = Some(SystemTime::now());
            inner.has_credential = true;
            inner.revision = inner.revision.wrapping_add(1);
            inner.status_key = "visualProvider.status.idle".into();
            self.save_prefs(&inner);
        }
        self.publish();
        Ok(())
    }

    /// Replaces the stored token with one that is not the rejected one. Unlike `save_credential`
    /// it does not tear down players: only consumers waiting for a working session re-run.
    fn store_recovered(&self, token: &str) -> Outcome<()> {
        let token = validate_credential(token)?;
        let had_working_session = {
            let inner = self.lock();
            inner.has_credential && !inner.auth_blocked
        };
        self.credentials
            .save(&token)
            .map_err(|_| Failure::Credential)?;
        {
            let mut inner = self.lock();
            inner.cached_credential = Some(token);
            inner.credential_read = true;
            inner.rejected = None;
            inner.saved_at = Some(SystemTime::now());
            inner.has_credential = true;
            inner.auth_blocked = false;
            if let Some(task) = inner.background_recovery.take() {
                task.abort();
            }
            inner.status_key = "visualProvider.status.idle".into();
            if !had_working_session {
                inner.revision = inner.revision.wrapping_add(1);
            }
            self.save_prefs(&inner);
        }
        self.publish();
        Ok(())
    }

    /// One recovery at a time: concurrent requests share the same web view attempt.
    pub async fn recover_credential(self: &Arc<Self>) -> Option<String> {
        let (auth, provider_id, rejected, generation) = {
            let inner = self.lock();
            let manifest = inner.manifest.as_ref()?;
            let auth = manifest.auth.clone().filter(|a| a.kind == "webview")?;
            (
                auth,
                manifest.id.clone(),
                inner.rejected.clone(),
                inner.recovery_generation,
            )
        };
        let host = self.clone();
        self.recovery
            .run(move || async move {
                let token = host.tokens.acquire(&auth, rejected.as_deref()).await?;
                let still_valid = {
                    let inner = host.lock();
                    inner.recovery_generation == generation
                        && inner.manifest.as_ref().is_some_and(|m| m.id == provider_id)
                };
                if !still_valid || Some(token.as_str()) == rejected.as_deref() {
                    return None;
                }
                host.store_recovered(&token).ok()?;
                Some(token)
            })
            .await
    }

    async fn refresh_if_stale(self: &Arc<Self>) {
        let due = {
            let mut inner = self.lock();
            let age = inner
                .saved_at
                .and_then(|at| SystemTime::now().duration_since(at).ok());
            let allowed = inner.next_proactive.is_none_or(|at| Instant::now() >= at);
            let has_auth = inner.manifest.as_ref().is_some_and(|m| m.auth.is_some());
            let due = policy::proactive_refresh_due(
                age,
                allowed,
                has_auth,
                inner.has_credential,
                inner.auth_blocked,
            );
            if due {
                // If this fails the current token may still work; ask again later, not per track.
                inner.next_proactive = Some(Instant::now() + policy::PROACTIVE_RETRY);
            }
            due
        };
        if due {
            let _ = self.recover_credential().await;
        }
    }

    /// While the session stays rejected keep looking for a working token, with growing pauses.
    fn schedule_background_recovery(self: &Arc<Self>) {
        let mut inner = self.lock();
        if inner.background_recovery.is_some()
            || inner.manifest.as_ref().is_none_or(|m| m.auth.is_none())
        {
            return;
        }
        let host = self.clone();
        inner.background_recovery = Some(spawn(async move {
            let mut attempt = 0;
            loop {
                tokio::time::sleep(policy::recovery_delay(attempt)).await;
                let keep_going = {
                    let inner = host.lock();
                    inner.enabled && inner.auth_blocked
                };
                if !keep_going {
                    host.lock().background_recovery = None;
                    return;
                }
                if host.recover_credential().await.is_some() {
                    return;
                }
                attempt += 1;
            }
        }));
    }

    /// Window focus: a rejected session retries at most once a minute.
    pub fn retry_after_returning_to_app(self: &Arc<Self>) {
        {
            let mut inner = self.lock();
            let recently = inner
                .last_foreground_retry
                .is_some_and(|at| at.elapsed() <= policy::FOREGROUND_RETRY_MIN);
            if !inner.enabled
                || !inner.auth_blocked
                || recently
                || inner.manifest.as_ref().is_none_or(|m| m.auth.is_none())
            {
                return;
            }
            inner.last_foreground_retry = Some(Instant::now());
        }
        let host = self.clone();
        spawn(async move {
            let _ = host.recover_credential().await;
        });
    }

    fn ensure_credential_loaded(&self) {
        let mut inner = self.lock();
        if inner.credential_read {
            return;
        }
        inner.cached_credential = self.credentials.read();
        inner.credential_read = true;
        if inner.cached_credential.is_none() {
            inner.has_credential = false;
        }
    }

    // MARK: Leases

    /// Dropping the lease: the provider process (if any) ends first, then its directory goes.
    pub fn release(&self, request_id: &str) {
        let job = {
            let mut inner = self.lock();
            let job = inner.jobs.remove(request_id);
            if job.is_none() {
                // A cancel can overtake the prepare that has not registered its job yet.
                inner.tombstones.push_back(request_id.to_owned());
                while inner.tombstones.len() > 64 {
                    inner.tombstones.pop_front();
                }
            }
            job
        };
        if let Some(job) = job {
            spawn_blocking(move || job.cancel());
        }
    }

    fn was_cancelled(&self, request_id: &str) -> bool {
        let mut inner = self.lock();
        match inner.tombstones.iter().position(|id| id == request_id) {
            Some(index) => {
                inner.tombstones.remove(index);
                true
            }
            None => false,
        }
    }

    // MARK: Prepare

    pub async fn prepare(
        self: &Arc<Self>,
        request: ArtworkRequest,
        request_id: String,
    ) -> Outcome<Option<AssetDto>> {
        let mut is_retry = false;
        loop {
            match self.prepare_once(&request, &request_id, is_retry).await? {
                Step::Done(asset) => return Ok(asset),
                Step::Retry => is_retry = true,
            }
        }
    }

    async fn prepare_once(
        self: &Arc<Self>,
        request: &ArtworkRequest,
        request_id: &str,
        is_retry: bool,
    ) -> Outcome<Step> {
        let ready = {
            let inner = self.lock();
            inner.enabled
                && !inner.auth_blocked
                && inner
                    .backoff_until
                    .is_none_or(|until| until <= Instant::now())
                && inner.manifest.is_some()
                && inner.has_credential
                && inner.jobs.len() < policy::MAX_CONCURRENT_JOBS
        };
        if !ready {
            return Ok(Step::Done(None));
        }
        if self.was_cancelled(request_id) {
            return Err(Failure::Cancelled);
        }
        self.ensure_credential_loaded();
        self.refresh_if_stale().await;
        let (manifest, credential) = {
            let inner = self.lock();
            match (inner.manifest.clone(), inner.cached_credential.clone()) {
                (Some(manifest), Some(credential)) => (manifest, credential),
                _ => return Ok(Step::Done(None)),
            }
        };

        // 1. Persistent cache: a valid file answers without network or subprocess.
        let provider_cache = self.cache_root().join(&manifest.id);
        let cached = provider_cache.join(format!("{}.mp4", cache_key(&request.video_id)));
        if cached.exists() {
            let path = cached.clone();
            match spawn_blocking(move || mp4::validate_file(&path)).await {
                Ok(Ok(video)) => {
                    self.set_status("visualProvider.status.ready");
                    return Ok(Step::Done(Some(asset_dto(request_id, &cached, &video))));
                }
                _ => {
                    let _ = std::fs::remove_file(&cached);
                }
            }
        }

        let epoch = self.lock().revision;
        let directory =
            lease::create_session_dir(&self.sessions_dir()).map_err(|_| Failure::Unavailable)?;
        let job = Job::new(directory.clone());
        {
            let mut inner = self.lock();
            if let Some(previous) = inner.jobs.insert(request_id.to_owned(), job.clone()) {
                spawn_blocking(move || previous.cancel());
            }
        }
        if self.was_cancelled(request_id) {
            self.release(request_id);
            return Err(Failure::Cancelled);
        }

        let outcome = self
            .run_job(
                &manifest,
                &credential,
                request,
                request_id,
                &job,
                &directory,
                epoch,
                is_retry,
                &provider_cache,
                &cached,
            )
            .await;
        match outcome {
            Ok(step) => Ok(step),
            Err(failure) => {
                if self.lock().revision == epoch && failure != Failure::Cancelled {
                    self.set_status("visualProvider.status.unavailable");
                }
                self.release(request_id);
                Err(failure)
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    async fn run_job(
        self: &Arc<Self>,
        manifest: &Manifest,
        credential: &str,
        request: &ArtworkRequest,
        request_id: &str,
        job: &Arc<Job>,
        directory: &Path,
        epoch: u64,
        is_retry: bool,
        provider_cache: &Path,
        cached: &Path,
    ) -> Outcome<Step> {
        let wire = Request::new(
            request_id.to_owned(),
            credential.to_owned(),
            directory.to_string_lossy().into_owned(),
            RequestTrack {
                video_id: request.video_id.clone(),
                title: request.title.clone(),
                artist: request.artist.clone(),
                album: request.album.clone(),
                duration_seconds: request.duration_seconds,
                explicit: request.explicit,
            },
        );
        let input = wire.encode()?;
        drop(wire);
        let executable = Self::executable_in(&self.installed_dir(), manifest)?;
        let runner = job.clone();
        let data = spawn_blocking(move || {
            runner.run(
                &executable,
                &input,
                Duration::from_secs(REQUEST_DEADLINE_SECS),
            )
        })
        .await
        .map_err(|_| Failure::Unavailable)??;
        self.ensure_current(request_id, job, epoch)?;
        let reply = Reply::parse(&data, request_id)?;

        if reply.status == "authRequired" {
            self.lock().rejected = Some(credential.to_owned());
            if !is_retry && manifest.uses_webview_auth() {
                // The provider refused this token: fetch another in the background, retry once.
                self.release(request_id);
                if self.recover_credential().await.is_some() {
                    return Ok(Step::Retry);
                }
            }
        }
        self.set_status(format!("visualProvider.status.{}", reply.status));
        if reply.status == "authRequired" {
            self.lock().auth_blocked = true;
            self.schedule_background_recovery();
            self.publish();
        }
        if reply.status == "rateLimited" {
            self.lock().backoff_until = Some(Instant::now() + policy::RATE_LIMIT_PAUSE);
        }
        if reply.status != "ready" {
            self.release(request_id);
            return Ok(Step::Done(None));
        }

        let produced = directory.join(OUTPUT_FILE_NAME);
        let probe = produced.clone();
        let video = spawn_blocking(move || mp4::validate_file(&probe))
            .await
            .map_err(|_| Failure::Unavailable)??;
        self.ensure_current(request_id, job, epoch)?;

        // Keep it: repeated playback and seeks are instant. A failed copy keeps the leased file.
        let (from, to, folder) = (
            produced.clone(),
            cached.to_path_buf(),
            provider_cache.to_path_buf(),
        );
        let stored = spawn_blocking(move || store_in_cache(&from, &to, &folder))
            .await
            .unwrap_or(false);
        let asset_path = if stored {
            cached.to_path_buf()
        } else {
            produced
        };
        self.notifier.allow_asset(&asset_path);
        let folder = provider_cache.to_path_buf();
        spawn_blocking(move || prune_cache(&folder, CACHE_MAX_BYTES, CACHE_TARGET_BYTES));
        Ok(Step::Done(Some(asset_dto(request_id, &asset_path, &video))))
    }

    fn ensure_current(&self, request_id: &str, job: &Arc<Job>, epoch: u64) -> Outcome<()> {
        let inner = self.lock();
        let registered = inner
            .jobs
            .get(request_id)
            .is_some_and(|current| Arc::ptr_eq(current, job));
        if inner.revision == epoch && registered && !job.is_cancelled() {
            Ok(())
        } else {
            Err(Failure::Cancelled)
        }
    }

    // MARK: Cache

    pub async fn cache_size(&self) -> u64 {
        let root = self.cache_root();
        spawn_blocking(move || dir_size(&root)).await.unwrap_or(0)
    }

    pub async fn clear_cache(&self) -> u64 {
        let size = self.cache_size().await;
        let root = self.cache_root();
        let _ = spawn_blocking(move || std::fs::remove_dir_all(root)).await;
        size
    }
}

fn asset_dto(request_id: &str, path: &Path, video: &mp4::VideoAsset) -> AssetDto {
    AssetDto {
        asset_id: format!("visual-extension:{request_id}"),
        local_path: path.to_string_lossy().into_owned(),
        codec: video.codec.into(),
        width: video.width,
        height: video.height,
        frame_rate: video.frame_rate,
        size_bytes: video.size_bytes,
    }
}

fn store_in_cache(from: &Path, to: &Path, folder: &Path) -> bool {
    if std::fs::create_dir_all(folder).is_err() {
        return false;
    }
    let temp = to.with_extension("mp4.tmp");
    let _ = std::fs::remove_file(&temp);
    let ok = std::fs::copy(from, &temp).is_ok() && {
        let _ = std::fs::remove_file(to);
        std::fs::rename(&temp, to).is_ok()
    };
    if !ok {
        let _ = std::fs::remove_file(&temp);
    }
    ok
}

pub fn dir_size(root: &Path) -> u64 {
    let mut total = 0;
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            match entry.metadata() {
                Ok(meta) if meta.is_dir() => stack.push(entry.path()),
                Ok(meta) => total += meta.len(),
                Err(_) => {}
            }
        }
    }
    total
}

/// Oldest first, down to the target, once the budget is exceeded. Files in use are skipped.
pub fn prune_cache(folder: &Path, max_bytes: u64, target_bytes: u64) {
    let Ok(entries) = std::fs::read_dir(folder) else {
        return;
    };
    let mut files: Vec<(PathBuf, u64, SystemTime)> = entries
        .flatten()
        .filter(|e| e.path().extension().is_some_and(|ext| ext == "mp4"))
        .filter_map(|e| {
            let meta = e.metadata().ok()?;
            Some((e.path(), meta.len(), meta.modified().ok()?))
        })
        .collect();
    let mut total: u64 = files.iter().map(|f| f.1).sum();
    if total <= max_bytes {
        return;
    }
    files.sort_by_key(|f| f.2);
    for (path, size, _) in files {
        if total <= target_bytes {
            break;
        }
        if std::fs::remove_file(path).is_ok() {
            total = total.saturating_sub(size);
        }
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::super::credential::MemoryCredentialStore;
    use super::super::mp4::fixture;
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    use std::sync::atomic::{AtomicUsize, Ordering};

    const GOOD: &str = "GOOD-token-0000000000000000000";
    const OLD: &str = "OLD0-token-0000000000000000000";
    const FRESH: &str = "GOOD-fresh-000000000000000000";

    #[derive(Default)]
    struct Recorder {
        will_change: AtomicUsize,
        changed: AtomicUsize,
        allowed: Mutex<Vec<PathBuf>>,
        forgotten: AtomicUsize,
        last: Mutex<Option<StateDto>>,
    }
    impl Notifier for Recorder {
        fn will_change(&self) {
            self.will_change.fetch_add(1, Ordering::SeqCst);
        }
        fn changed(&self, state: &StateDto) {
            self.changed.fetch_add(1, Ordering::SeqCst);
            *self.last.lock().unwrap() = Some(state.clone());
        }
        fn allow_asset(&self, path: &Path) {
            self.allowed.lock().unwrap().push(path.to_path_buf());
        }
        fn forget_session(&self, _: &Auth) {
            self.forgotten.fetch_add(1, Ordering::SeqCst);
        }
    }

    #[derive(Default)]
    struct FakeTokens {
        answers: Mutex<VecDeque<Option<String>>>,
        rejected_seen: Mutex<Vec<Option<String>>>,
        calls: AtomicUsize,
        delay_ms: u64,
    }
    impl TokenSource for FakeTokens {
        fn acquire<'a>(
            &'a self,
            _: &'a Auth,
            rejected: Option<&'a str>,
        ) -> BoxFuture<'a, Option<String>> {
            Box::pin(async move {
                self.calls.fetch_add(1, Ordering::SeqCst);
                self.rejected_seen
                    .lock()
                    .unwrap()
                    .push(rejected.map(str::to_owned));
                tokio::time::sleep(Duration::from_millis(self.delay_ms)).await;
                self.answers.lock().unwrap().pop_front().flatten()
            })
        }
    }

    struct Fixture {
        root: PathBuf,
        package: PathBuf,
        counter: PathBuf,
        mode: PathBuf,
        recorder: Arc<Recorder>,
        tokens: Arc<FakeTokens>,
        store: Arc<MemoryCredentialStore>,
        host: Arc<Host>,
    }

    fn manifest_json(version: &str) -> String {
        format!(
            r#"{{"protocolVersion":1,"id":"fake","name":"Fake","version":"{version}","executable":"provider.sh","credentialLabel":"c","auth":{{"type":"webview","loginUrl":"https://login.example.com/","targetHost":"example.com","tokenUrl":"https://example.com/token"}}}}"#
        )
    }

    fn write_package(dir: &Path, version: &str, mp4: &Path, counter: &Path, mode: &Path) {
        std::fs::create_dir_all(dir).unwrap();
        std::fs::write(dir.join("manifest.json"), manifest_json(version)).unwrap();
        let script = format!(
            r#"#!/bin/sh
IN=$(cat)
RID=$(printf '%s' "$IN" | sed 's/.*"requestId":"\([^"]*\)".*/\1/')
OUT=$(printf '%s' "$IN" | sed 's/.*"outputDirectory":"\([^"]*\)".*/\1/')
CRED=$(printf '%s' "$IN" | sed 's/.*"credential":"\([^"]*\)".*/\1/')
echo "$CRED" >> '{counter}'
MODE=$(cat '{mode}')
case "$MODE" in
  slow) sleep 30 ;;
  rate) printf '{{"protocolVersion":1,"requestId":"%s","status":"rateLimited"}}' "$RID" ;;
  absent) printf '{{"protocolVersion":1,"requestId":"%s","status":"absent"}}' "$RID" ;;
  foreign) printf '{{"protocolVersion":1,"requestId":"someone-else","status":"absent"}}' ;;
  badfile) printf '{{"protocolVersion":1,"requestId":"%s","status":"ready","fileName":"../x.mp4"}}' "$RID" ;;
  junk) echo junk > "$OUT/visual.mp4"; printf '{{"protocolVersion":1,"requestId":"%s","status":"ready","fileName":"visual.mp4"}}' "$RID" ;;
  *) case "$CRED" in
       GOOD*) cp '{mp4}' "$OUT/visual.mp4"; printf '{{"protocolVersion":1,"requestId":"%s","status":"ready","fileName":"visual.mp4"}}' "$RID" ;;
       *) printf '{{"protocolVersion":1,"requestId":"%s","status":"authRequired"}}' "$RID" ;;
     esac ;;
esac
"#,
            counter = counter.display(),
            mode = mode.display(),
            mp4 = mp4.display()
        );
        let exe = dir.join("provider.sh");
        std::fs::write(&exe, script).unwrap();
        std::fs::set_permissions(&exe, std::fs::Permissions::from_mode(0o700)).unwrap();
    }

    fn fixture(name: &str) -> Fixture {
        let root = std::env::temp_dir().join(format!("sideb-host-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let mp4 = root.join("canvas.mp4");
        std::fs::write(&mp4, fixture::build(&fixture::Spec::canvas())).unwrap();
        let (counter, mode) = (root.join("calls.txt"), root.join("mode.txt"));
        std::fs::write(&counter, "").unwrap();
        std::fs::write(&mode, "ok").unwrap();
        let package = root.join("package");
        write_package(&package, "0.1.5", &mp4, &counter, &mode);
        let recorder = Arc::new(Recorder::default());
        let tokens = Arc::new(FakeTokens::default());
        let store = Arc::new(MemoryCredentialStore::default());
        let bundled = package.clone();
        let host = Host::new(
            root.join("VisualProviders"),
            Box::new(move || Some(bundled.clone())),
            store.clone(),
            tokens.clone(),
            recorder.clone(),
        );
        Fixture {
            root,
            package,
            counter,
            mode,
            recorder,
            tokens,
            store,
            host,
        }
    }

    fn request(video: &str) -> ArtworkRequest {
        ArtworkRequest {
            video_id: video.into(),
            title: "Title".into(),
            artist: "Artist".into(),
            album: Some("Album".into()),
            duration_seconds: Some(200),
            explicit: None,
        }
    }

    fn calls(fx: &Fixture) -> Vec<String> {
        std::fs::read_to_string(&fx.counter)
            .unwrap()
            .lines()
            .map(str::to_owned)
            .collect()
    }

    async fn ready_host(name: &str) -> Fixture {
        let fx = fixture(name);
        fx.host.install_from(fx.package.clone()).await.unwrap();
        fx.host.save_credential(GOOD).unwrap();
        assert!(fx.host.set_enabled(true));
        fx
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn nothing_runs_until_the_user_installs_signs_in_and_enables() {
        let fx = fixture("gates");
        // Preinstall installs but does not enable, and there is no token yet.
        fx.host.ensure_bundled().await;
        let state = fx.host.state();
        assert!(state.installed && !state.enabled && !state.has_credential);
        assert_eq!(state.status_key, "visualProvider.status.tokenRequired");
        assert!(
            !fx.host.set_enabled(true),
            "cannot enable without a credential"
        );
        assert_eq!(fx.host.prepare(request("v1"), "r1".into()).await, Ok(None));
        fx.host.save_credential(GOOD).unwrap();
        assert!(!fx.host.state().enabled, "signing in does not enable");
        assert_eq!(fx.host.prepare(request("v1"), "r2".into()).await, Ok(None));
        assert!(calls(&fx).is_empty(), "no process ran while disabled");
        assert!(fx.host.set_enabled(true));
        assert!(fx.host.state().identity_salt.is_some());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn ready_reply_is_validated_cached_and_served_without_a_second_process() {
        let fx = ready_host("ready").await;
        let first = fx
            .host
            .prepare(request("dQw4w9WgXcQ"), "r1".into())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            (first.codec.as_str(), first.width, first.height),
            ("h264", 720, 1280)
        );
        assert!(first.local_path.contains("Cache"), "{}", first.local_path);
        assert!(first.local_path.ends_with("dQw4w9WgXcQ.mp4"));
        assert_eq!(first.asset_id, "visual-extension:r1");
        assert_eq!(fx.host.state().status_key, "visualProvider.status.ready");
        assert!(fx
            .recorder
            .allowed
            .lock()
            .unwrap()
            .iter()
            .any(|p| p.ends_with("dQw4w9WgXcQ.mp4")));
        // The leased session directory is released on cancel; the cached copy survives.
        fx.host.release("r1");
        let second = fx
            .host
            .prepare(request("dQw4w9WgXcQ"), "r2".into())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(second.local_path, first.local_path);
        assert_eq!(calls(&fx).len(), 1, "second request came from the cache");
        assert!(fx.host.cache_size().await > 0);
        assert!(fx.host.clear_cache().await > 0);
        assert_eq!(fx.host.cache_size().await, 0);
        // A corrupt cache entry is dropped and fetched again.
        let again = fx
            .host
            .prepare(request("dQw4w9WgXcQ"), "r3".into())
            .await
            .unwrap()
            .unwrap();
        std::fs::write(&again.local_path, b"corrupt").unwrap();
        let healed = fx
            .host
            .prepare(request("dQw4w9WgXcQ"), "r4".into())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(healed.width, 720);
        assert_eq!(calls(&fx).len(), 3);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn session_directory_is_leased_until_released_and_credential_goes_through_stdin_only() {
        let fx = ready_host("lease").await;
        fx.host
            .prepare(request("v1"), "r1".into())
            .await
            .unwrap()
            .unwrap();
        let sessions = fx.host.sessions_dir();
        let count = || std::fs::read_dir(&sessions).map(|d| d.count()).unwrap_or(0);
        assert_eq!(
            count(),
            1,
            "the lease keeps the private folder while the player has the asset"
        );
        fx.host.release("r1");
        for _ in 0..100 {
            if count() == 0 {
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        assert_eq!(count(), 0);
        let state = serde_json::to_string(&fx.host.state()).unwrap();
        assert!(
            !state.contains(GOOD) && !state.contains("example.com"),
            "{state}"
        );
        let prefs = std::fs::read_to_string(fx.root.join("VisualProviders/state.json")).unwrap();
        assert!(!prefs.contains(GOOD));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn rejected_session_recovers_once_with_a_new_token_and_retries_the_request() {
        let fx = fixture("recover");
        fx.host.install_from(fx.package.clone()).await.unwrap();
        fx.host.save_credential(OLD).unwrap();
        fx.host.set_enabled(true);
        fx.tokens
            .answers
            .lock()
            .unwrap()
            .push_back(Some(FRESH.into()));
        let asset = fx.host.prepare(request("v1"), "r1".into()).await.unwrap();
        assert!(asset.is_some(), "the retried request succeeds");
        assert_eq!(calls(&fx), vec![OLD, FRESH]);
        assert_eq!(
            fx.tokens.rejected_seen.lock().unwrap().as_slice(),
            &[Some(OLD.to_owned())]
        );
        let state = fx.host.state();
        assert!(!state.auth_blocked && state.has_credential && state.enabled);
        assert_eq!(fx.store.read().as_deref(), Some(FRESH));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn recovery_does_not_unmount_players() {
        let fx = fixture("nounmount");
        fx.host.install_from(fx.package.clone()).await.unwrap();
        fx.host.save_credential(OLD).unwrap();
        fx.host.set_enabled(true);
        fx.tokens
            .answers
            .lock()
            .unwrap()
            .push_back(Some(FRESH.into()));
        let before = fx.recorder.will_change.load(Ordering::SeqCst);
        fx.host.prepare(request("v1"), "r1".into()).await.unwrap();
        assert_eq!(
            fx.recorder.will_change.load(Ordering::SeqCst),
            before,
            "recovery keeps consumers mounted"
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn failed_recovery_blocks_until_a_new_token_arrives() {
        let fx = fixture("blocked");
        fx.host.install_from(fx.package.clone()).await.unwrap();
        fx.host.save_credential(OLD).unwrap();
        fx.host.set_enabled(true);
        assert_eq!(fx.host.prepare(request("v1"), "r1".into()).await, Ok(None));
        let state = fx.host.state();
        assert!(state.auth_blocked);
        assert_eq!(state.status_key, "visualProvider.status.authRequired");
        assert_eq!(calls(&fx).len(), 1);
        // Blocked: no more processes, no more web views.
        assert_eq!(fx.host.prepare(request("v2"), "r2".into()).await, Ok(None));
        assert_eq!(calls(&fx).len(), 1);
        assert_eq!(fx.tokens.calls.load(Ordering::SeqCst), 1);
        // Returning to the app retries; a token equal to the rejected one is not a recovery.
        fx.tokens
            .answers
            .lock()
            .unwrap()
            .push_back(Some(OLD.into()));
        fx.host.retry_after_returning_to_app();
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert!(
            fx.host.state().auth_blocked,
            "the rejected token is never accepted again"
        );
        // Foreground retries are throttled to one a minute.
        fx.tokens
            .answers
            .lock()
            .unwrap()
            .push_back(Some(FRESH.into()));
        fx.host.retry_after_returning_to_app();
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert_eq!(fx.tokens.calls.load(Ordering::SeqCst), 2);
        assert!(fx.host.state().auth_blocked);
        // A manual token replaces the session and unblocks.
        fx.host.save_credential(GOOD).unwrap();
        assert!(!fx.host.state().auth_blocked);
        assert!(fx
            .host
            .prepare(request("v3"), "r3".into())
            .await
            .unwrap()
            .is_some());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn concurrent_recoveries_share_one_web_view_attempt() {
        let mut fx = fixture("single");
        fx.tokens = Arc::new(FakeTokens {
            delay_ms: 200,
            ..Default::default()
        });
        let bundled = fx.package.clone();
        fx.host = Host::new(
            fx.root.join("VisualProviders"),
            Box::new(move || Some(bundled.clone())),
            fx.store.clone(),
            fx.tokens.clone(),
            fx.recorder.clone(),
        );
        fx.host.install_from(fx.package.clone()).await.unwrap();
        fx.host.save_credential(OLD).unwrap();
        fx.tokens
            .answers
            .lock()
            .unwrap()
            .push_back(Some(FRESH.into()));
        let (a, b, c) = tokio::join!(
            fx.host.recover_credential(),
            fx.host.recover_credential(),
            fx.host.recover_credential()
        );
        assert_eq!(
            (a.as_deref(), b.as_deref(), c.as_deref()),
            (Some(FRESH), Some(FRESH), Some(FRESH))
        );
        assert_eq!(fx.tokens.calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn rate_limit_pauses_and_other_statuses_map_to_keys() {
        let fx = ready_host("rate").await;
        std::fs::write(&fx.mode, "rate").unwrap();
        assert_eq!(fx.host.prepare(request("v1"), "r1".into()).await, Ok(None));
        assert_eq!(
            fx.host.state().status_key,
            "visualProvider.status.rateLimited"
        );
        std::fs::write(&fx.mode, "ok").unwrap();
        assert_eq!(fx.host.prepare(request("v2"), "r2".into()).await, Ok(None));
        assert_eq!(calls(&fx).len(), 1, "paused for 60 s: nothing launched");
        let fx = ready_host("absent").await;
        std::fs::write(&fx.mode, "absent").unwrap();
        assert_eq!(fx.host.prepare(request("v1"), "r1".into()).await, Ok(None));
        assert_eq!(fx.host.state().status_key, "visualProvider.status.absent");
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn foreign_or_malformed_replies_and_bad_videos_are_failures_not_absence() {
        for (mode, name) in [("foreign", "m1"), ("badfile", "m2"), ("junk", "m3")] {
            let fx = ready_host(name).await;
            std::fs::write(&fx.mode, mode).unwrap();
            let result = fx.host.prepare(request("v1"), "r1".into()).await;
            assert_eq!(result, Err(Failure::Invalid), "{mode}");
            assert_eq!(
                fx.host.state().status_key,
                "visualProvider.status.unavailable",
                "{mode}"
            );
            assert!(fx.host.lock().jobs.is_empty(), "{mode}: lease released");
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn cancelling_kills_the_provider_process() {
        let fx = ready_host("cancel").await;
        std::fs::write(&fx.mode, "slow").unwrap();
        let host = fx.host.clone();
        let pending = tokio::spawn(async move { host.prepare(request("v1"), "r1".into()).await });
        tokio::time::sleep(Duration::from_millis(500)).await;
        let started = Instant::now();
        fx.host.release("r1");
        assert_eq!(pending.await.unwrap(), Err(Failure::Cancelled));
        assert!(started.elapsed() < Duration::from_secs(5));
        // A cancel that overtakes the request is remembered.
        fx.host.release("early");
        std::fs::write(&fx.mode, "ok").unwrap();
        assert_eq!(
            fx.host.prepare(request("v2"), "early".into()).await,
            Err(Failure::Cancelled)
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn changing_configuration_detaches_consumers_before_releasing_files() {
        let fx = ready_host("invalidate").await;
        fx.host
            .prepare(request("v1"), "r1".into())
            .await
            .unwrap()
            .unwrap();
        let before = fx.recorder.will_change.load(Ordering::SeqCst);
        let revision = fx.host.state().revision;
        assert!(fx.host.set_enabled(false));
        assert!(fx.recorder.will_change.load(Ordering::SeqCst) > before);
        assert!(fx.host.state().revision > revision);
        assert!(fx.host.lock().jobs.is_empty());
        assert_eq!(fx.host.prepare(request("v1"), "r2".into()).await, Ok(None));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn uninstall_deletes_plugin_token_cache_and_session_and_is_not_undone() {
        let fx = ready_host("uninstall").await;
        fx.host
            .prepare(request("v1"), "r1".into())
            .await
            .unwrap()
            .unwrap();
        assert!(fx.host.installed_dir().exists() && fx.host.cache_root().exists());
        fx.host.uninstall().await.unwrap();
        let state = fx.host.state();
        assert!(!state.installed && !state.enabled && !state.has_credential);
        assert!(!fx.host.installed_dir().exists() && !fx.host.cache_root().exists());
        assert!(!fx.store.exists(), "the token is really deleted");
        assert_eq!(
            fx.recorder.forgotten.load(Ordering::SeqCst),
            1,
            "web session cleared"
        );
        // The preinstalled copy does NOT come back by itself...
        fx.host.ensure_bundled().await;
        assert!(!fx.host.state().installed);
        let reborn = Host::new(
            fx.root.join("VisualProviders"),
            Box::new({
                let dir = fx.package.clone();
                move || Some(dir.clone())
            }),
            fx.store.clone(),
            fx.tokens.clone(),
            fx.recorder.clone(),
        );
        reborn.ensure_bundled().await;
        assert!(
            !reborn.state().installed,
            "the decision persists across restarts"
        );
        // ...but an explicit install works, again without enabling or a token.
        reborn.install_bundled().await.unwrap();
        let state = reborn.state();
        assert!(state.installed && !state.enabled && !state.has_credential);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn upgrade_keeps_token_and_enabled_but_a_different_provider_resets_them() {
        let fx = ready_host("upgrade").await;
        let newer = fx.root.join("newer");
        write_package(
            &newer,
            "0.2.0",
            &fx.root.join("canvas.mp4"),
            &fx.counter,
            &fx.mode,
        );
        let bundled = newer.clone();
        let host = Host::new(
            fx.root.join("VisualProviders"),
            Box::new(move || Some(bundled.clone())),
            fx.store.clone(),
            fx.tokens.clone(),
            fx.recorder.clone(),
        );
        assert!(host.state().enabled && host.state().has_credential);
        host.ensure_bundled().await; // automatic upgrade of the same id
        let state = host.state();
        assert_eq!(state.provider.unwrap().version, "0.2.0");
        assert!(state.enabled && state.has_credential && fx.store.exists());
        let other = fx.root.join("other");
        write_package(
            &other,
            "9.0.0",
            &fx.root.join("canvas.mp4"),
            &fx.counter,
            &fx.mode,
        );
        std::fs::write(
            other.join("manifest.json"),
            manifest_json("9.0.0").replace("\"fake\"", "\"other\""),
        )
        .unwrap();
        host.install_from(other).await.unwrap();
        let state = host.state();
        assert!(state.installed && !state.enabled && !state.has_credential);
        assert!(!fx.store.exists());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn removal_is_remembered_per_provider_id() {
        let fx = fixture("perid");
        let other = fx.root.join("other");
        write_package(
            &other,
            "1.0.0",
            &fx.root.join("canvas.mp4"),
            &fx.counter,
            &fx.mode,
        );
        std::fs::write(
            other.join("manifest.json"),
            manifest_json("1.0.0").replace("\"fake\"", "\"other\""),
        )
        .unwrap();
        fx.host.install_from(other).await.unwrap();
        fx.host.uninstall().await.unwrap();
        // Removing "other" says nothing about the preinstalled "fake": it is provisioned.
        fx.host.ensure_bundled().await;
        assert_eq!(fx.host.state().provider.unwrap().id, "fake");
        // A provider the user installed by hand is never replaced by the preinstalled one.
        let again = fx.root.join("again");
        write_package(
            &again,
            "1.0.0",
            &fx.root.join("canvas.mp4"),
            &fx.counter,
            &fx.mode,
        );
        std::fs::write(
            again.join("manifest.json"),
            manifest_json("1.0.0").replace("\"fake\"", "\"mine\""),
        )
        .unwrap();
        fx.host.install_from(again).await.unwrap();
        fx.host.ensure_bundled().await;
        assert_eq!(fx.host.state().provider.unwrap().id, "mine");
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn install_rejects_symlinked_or_missing_executables() {
        let fx = fixture("badpkg");
        let broken = fx.root.join("broken");
        std::fs::create_dir_all(&broken).unwrap();
        std::fs::write(broken.join("manifest.json"), manifest_json("1.0.0")).unwrap();
        assert_eq!(
            fx.host.install_from(broken.clone()).await,
            Err(Failure::Invalid)
        );
        std::os::unix::fs::symlink(fx.package.join("provider.sh"), broken.join("provider.sh"))
            .unwrap();
        assert_eq!(fx.host.install_from(broken).await, Err(Failure::Invalid));
        assert!(!fx.host.state().installed);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn proactive_refresh_renews_an_old_token_before_the_request() {
        let fx = ready_host("proactive").await;
        fx.tokens
            .answers
            .lock()
            .unwrap()
            .push_back(Some(FRESH.into()));
        fx.host.lock().saved_at = Some(SystemTime::now() - Duration::from_secs(55 * 60));
        let asset = fx.host.prepare(request("v1"), "r1".into()).await.unwrap();
        assert!(asset.is_some());
        assert_eq!(
            calls(&fx),
            vec![FRESH],
            "the first request already used the renewed token"
        );
        assert_eq!(fx.tokens.calls.load(Ordering::SeqCst), 1);
        // A fresh token is not renewed again.
        fx.host.prepare(request("v2"), "r2".into()).await.unwrap();
        assert_eq!(fx.tokens.calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn cache_pruning_removes_oldest_first_down_to_the_target() {
        let dir = std::env::temp_dir().join(format!("sideb-prune-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        for index in 0..5 {
            let path = dir.join(format!("{index}.mp4"));
            std::fs::write(&path, vec![0u8; 100]).unwrap();
            let when = SystemTime::now() - Duration::from_secs(1000 - index * 100);
            std::fs::File::options()
                .write(true)
                .open(&path)
                .unwrap()
                .set_modified(when)
                .unwrap();
        }
        std::fs::write(dir.join("keep.txt"), vec![0u8; 100]).unwrap();
        prune_cache(&dir, 1000, 100); // under budget: untouched
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 6);
        prune_cache(&dir, 400, 200);
        let left: Vec<String> = {
            let mut names: Vec<String> = std::fs::read_dir(&dir)
                .unwrap()
                .flatten()
                .map(|e| e.file_name().to_string_lossy().into_owned())
                .collect();
            names.sort();
            names
        };
        assert_eq!(left, ["3.mp4", "4.mp4", "keep.txt"]);
    }
}
