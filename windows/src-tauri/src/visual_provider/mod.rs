//! Optional visual providers (PAR-050): a generic host for a separately installed executable that
//! speaks JSON/stdio v1 (see `extensions/README.md`). Nothing here knows about Spotify beyond the
//! provider's own manifest; the core, the queue and the audio path are untouched.
//!
//! Layout on disk (`<app local data>/VisualProviders/`): `Installed/` (manifest + one executable),
//! `Sessions/<uuid>/` (private per-request output + `.owner` PID lease), `Cache/<provider>/<id>.mp4`,
//! `visual-provider.dpapi` (DPAPI-protected token) and `state.json` (non-secret preferences).
//!
//! Policy: Apple first; the provider is a fallback ONLY for the sidebar's vertical player and only
//! when enabled (`src/lib/visualProvider/routing.ts`); fullscreen never asks. Disabled until the user
//! signs in and turns it on.

pub mod credential;
pub mod host;
pub mod job;
pub mod lease;
pub mod mp4;
pub mod policy;
pub mod protocol;
pub mod singleflight;
pub mod webview;

use credential::DpapiCredentialStore;
use host::{Host, Notifier, StateDto};
use protocol::Auth;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tauri::{AppHandle, Emitter, Manager};
use webview::WebViewTokenSource;

pub const EVENT_CHANGED: &str = "visual-provider-changed";
pub const EVENT_WILL_CHANGE: &str = "visual-provider-will-change";
pub const EVENT_LOGIN: &str = "visual-provider-login";

/// Relative location of the preinstalled package (`extensions/README.md`, W7 contract).
pub const PACKAGE_RELATIVE: &str = "provider/spotify-canvas";

/// Ordered candidates, nothing else is ever consulted: (1) Tauri resource dir, (2) the folder of
/// `sideb-windows.exe` (NSIS install and portable zip; also under `resources/` if Tauri used it),
/// (3) debug builds only: `<CARGO_MANIFEST_DIR>/provider/spotify-canvas` (prepared by `windows.ps1`).
pub fn provider_candidates(
    resource_dir: Option<&Path>,
    exe_dir: Option<&Path>,
    debug_manifest_dir: Option<&Path>,
) -> Vec<PathBuf> {
    candidates_under(PACKAGE_RELATIVE, resource_dir, exe_dir, debug_manifest_dir)
}

/// The same candidate order for any bundled `provider/<name>` folder (the Jam plugin reuses it).
pub fn candidates_under(
    relative: &str,
    resource_dir: Option<&Path>,
    exe_dir: Option<&Path>,
    debug_manifest_dir: Option<&Path>,
) -> Vec<PathBuf> {
    let mut found = Vec::new();
    for base in [resource_dir, exe_dir].into_iter().flatten() {
        found.push(base.join(relative));
    }
    for base in [resource_dir, exe_dir].into_iter().flatten() {
        found.push(base.join("resources").join(relative));
    }
    if let Some(manifest_dir) = debug_manifest_dir {
        found.push(manifest_dir.join(relative));
    }
    found
}

/// First candidate whose manifest, platform and executable validate (same checks as a manual install).
pub fn first_valid_package(candidates: &[PathBuf]) -> Option<PathBuf> {
    candidates
        .iter()
        .find(|dir| dir.join("manifest.json").is_file() && Host::read_manifest(dir).is_ok())
        .cloned()
}

/// THE single place that knows where the preinstalled provider lives.
pub fn resolve_provider_dir(app: &AppHandle) -> Option<PathBuf> {
    let resources = app.path().resource_dir().ok();
    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(Path::to_path_buf));
    let debug_dir = cfg!(debug_assertions).then(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")));
    first_valid_package(&provider_candidates(
        resources.as_deref(),
        exe_dir.as_deref(),
        debug_dir.as_deref(),
    ))
}

struct TauriNotifier {
    app: AppHandle,
}

impl Notifier for TauriNotifier {
    fn will_change(&self) {
        let _ = self.app.emit(EVENT_WILL_CHANGE, ());
    }
    fn changed(&self, state: &StateDto) {
        let _ = self.app.emit(EVENT_CHANGED, state);
    }
    fn allow_asset(&self, path: &Path) {
        let _ = self.app.asset_protocol_scope().allow_file(path);
    }
    fn forget_session(&self, auth: &Auth) {
        webview::forget_session(&self.app, auth);
    }
}

/// Registers the host as managed state. Call once from `setup`.
pub fn init(app: &AppHandle) {
    let Ok(local) = app.path().app_local_data_dir() else {
        return;
    };
    let root = local.join("VisualProviders");
    let cache = root.join("Cache");
    if std::fs::create_dir_all(&cache).is_ok() {
        // Cached videos are served through the asset protocol (the static scope only knows the
        // Apple artwork cache); fallbacks inside Sessions/ are allowed one file at a time.
        let _ = app.asset_protocol_scope().allow_directory(&cache, true);
    }
    let resolver_app = app.clone();
    let host = Host::new(
        root.clone(),
        Box::new(move || resolve_provider_dir(&resolver_app)),
        Arc::new(DpapiCredentialStore::new(root)),
        Arc::new(WebViewTokenSource::new(app.clone())),
        Arc::new(TauriNotifier { app: app.clone() }),
    );
    app.manage(host.clone());

    // "Back to the app": a rejected session retries at most once a minute.
    if let Some(main) = app.get_webview_window("main") {
        let focus_host = host.clone();
        main.on_window_event(move |event| {
            if matches!(event, tauri::WindowEvent::Focused(true)) {
                focus_host.retry_after_returning_to_app();
            }
        });
    }
    // Preinstalled package: install it (never enable it) unless the user removed it before.
    tauri::async_runtime::spawn(async move { host.ensure_bundled().await });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn package(base: &Path, name: &str, valid: bool) -> PathBuf {
        let dir = base.join(name);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("manifest.json"),
            br#"{"protocolVersion":1,"id":"p","name":"P","version":"1.0.0","executable":"p.exe","credentialLabel":"c"}"#,
        )
        .unwrap();
        if valid {
            std::fs::write(dir.join("p.exe"), b"MZ").unwrap();
        }
        dir
    }

    #[test]
    fn candidates_follow_the_documented_order_and_nothing_else() {
        let (res, exe, dbg) = (Path::new("R"), Path::new("E"), Path::new("D"));
        let rel = |base: &str, extra: &str| {
            let mut p = PathBuf::from(base);
            if !extra.is_empty() {
                p.push(extra);
            }
            p.join(PACKAGE_RELATIVE)
        };
        assert_eq!(
            provider_candidates(Some(res), Some(exe), Some(dbg)),
            vec![
                rel("R", ""),
                rel("E", ""),
                rel("R", "resources"),
                rel("E", "resources"),
                rel("D", "")
            ]
        );
        assert_eq!(
            provider_candidates(None, Some(exe), None),
            vec![rel("E", ""), rel("E", "resources")]
        );
        assert!(provider_candidates(None, None, None).is_empty());
    }

    #[test]
    fn picks_the_first_valid_package_and_skips_broken_or_foreign_ones() {
        let base = std::env::temp_dir().join(format!("sideb-find-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let broken = package(&base, "a-broken", false);
        let good = package(&base, "b-good", true);
        let foreign = package(&base, "c-foreign", true);
        let manifest = std::fs::read_to_string(foreign.join("manifest.json")).unwrap();
        std::fs::write(
            foreign.join("manifest.json"),
            manifest.replace("\"id\"", "\"platform\":\"plan9-mips\",\"id\""),
        )
        .unwrap();
        let missing = base.join("missing");
        assert_eq!(
            first_valid_package(&[
                missing.clone(),
                broken.clone(),
                foreign.clone(),
                good.clone()
            ]),
            Some(good.clone())
        );
        assert_eq!(first_valid_package(&[foreign, broken, missing]), None);
    }
}
