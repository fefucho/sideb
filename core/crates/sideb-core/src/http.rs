//! The app's one outbound HTTP client.
//!
//! There used to be six of these inside `src-tauri` (orchestrator, PoToken, cipher fetcher, cipher
//! config, lyrics, and Last.fm twice), each built from its own `Client::builder()`. `reqwest` pools
//! connections and holds its TLS config per client, so that was six rustls configs, six connection
//! pools and six sets of idle sockets to the same handful of Google hosts.
//!
//! Everything the separate clients were configured for (a User-Agent, a timeout) is per-request
//! state, so it moved to the call sites. The User-Agent is deliberately NOT a default here: what
//! YouTube serves for `player.js` depends on it, so it should be visible at the fetch rather than
//! inherited from somewhere else and quietly lost in a later edit.
//!
//! `crates/innertube` keeps its own client on purpose. It is the other side of the transport
//! boundary (context/11) and it configures a proxy per session, which is client-level state.

use std::sync::OnceLock;

/// Desktop Chrome. YouTube serves the web `player.js` and the BotGuard endpoints against this, so
/// the cipher fetcher and the PoToken minter both send it.
pub const WEB_UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

pub fn client() -> &'static reqwest::Client {
    static HTTP: OnceLock<reqwest::Client> = OnceLock::new();
    HTTP.get_or_init(|| {
        // No default User-Agent and no default timeout: both are set per request, by the callers
        // that actually need them.
        reqwest::Client::builder().build().unwrap_or_default()
    })
}

/// Client for genius.com.
///
/// `reqwest` has both TLS backends enabled in this workspace (other crates pull in `default-tls`),
/// so `Client::builder()` picks the platform's native stack. On Windows that is Schannel, and Genius
/// answers its ClientHello with HTTP 403 while accepting rustls. Only the Windows shell (the
/// optional `windows-bridge` feature) pins rustls here; everywhere else this is `client()`, so the
/// Apple build keeps its native stack. Deliberately scoped to Genius: rustls does not read the
/// Windows certificate store, so moving the other consumers could break HTTPS-inspecting setups.
pub fn genius_client() -> &'static reqwest::Client {
    #[cfg(feature = "windows-bridge")]
    {
        static GENIUS: OnceLock<reqwest::Client> = OnceLock::new();
        GENIUS.get_or_init(|| {
            reqwest::Client::builder()
                .use_rustls_tls()
                .build()
                .unwrap_or_else(|_| client().clone())
        })
    }
    #[cfg(not(feature = "windows-bridge"))]
    {
        client()
    }
}
