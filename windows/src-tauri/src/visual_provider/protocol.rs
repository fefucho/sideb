//! JSON/stdio v1 boundary shared with the optional provider executable. Pure logic, no I/O.
//! Mirrors `VisualProviderProtocol.swift`; no Spotify type enters the player or the core.

use serde::{Deserialize, Serialize};

pub const PROTOCOL_VERSION: u32 = 1;
pub const MAX_INPUT_BYTES: usize = 32 * 1024;
pub const MAX_OUTPUT_BYTES: usize = 16 * 1024;
pub const REQUEST_DEADLINE_SECS: u64 = 22;
pub const MAX_MANIFEST_BYTES: u64 = 8192;
pub const MAX_EXECUTABLE_BYTES: u64 = 128 * 1024 * 1024;
pub const MAX_CREDENTIAL_BYTES: usize = 8192;
/// The only file a `ready` reply may refer to.
pub const OUTPUT_FILE_NAME: &str = "visual.mp4";
pub const STATUSES: [&str; 7] = [
    "ready",
    "absent",
    "authRequired",
    "rateLimited",
    "unresolved",
    "unsupported",
    "unavailable",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Failure {
    Invalid,
    Unavailable,
    Cancelled,
    Credential,
}

pub type Outcome<T> = Result<T, Failure>;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Auth {
    #[serde(rename = "type")]
    pub kind: String,
    pub login_url: String,
    pub target_host: String,
    pub token_url: String,
}

fn https_url(value: &str) -> Option<tauri::Url> {
    tauri::Url::parse(value)
        .ok()
        .filter(|url| url.scheme() == "https" && url.host_str().is_some())
}

impl Auth {
    pub fn validate(&self) -> Outcome<()> {
        let host_ok = !self.target_host.is_empty()
            && self.target_host.chars().count() <= 100
            && self
                .target_host
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-');
        if self.kind == "webview"
            && host_ok
            && https_url(&self.login_url).is_some()
            && https_url(&self.token_url).is_some()
        {
            Ok(())
        } else {
            Err(Failure::Invalid)
        }
    }

    /// True for the target host and its subdomains only (never a look-alike suffix).
    pub fn is_target_host(&self, host: &str) -> bool {
        let host = host.to_ascii_lowercase();
        let target = self.target_host.to_ascii_lowercase();
        host == target || host.ends_with(&format!(".{target}"))
    }

    /// Parent domain that owns the provider session cookies (`open.spotify.com` -> `spotify.com`).
    pub fn cookie_domain(&self) -> String {
        let labels: Vec<&str> = self.target_host.split('.').collect();
        if labels.len() <= 2 {
            self.target_host.to_ascii_lowercase()
        } else {
            labels[labels.len() - 2..].join(".").to_ascii_lowercase()
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub protocol_version: u32,
    pub id: String,
    pub name: String,
    pub version: String,
    pub executable: String,
    pub credential_label: String,
    /// `macos-arm64`, `windows-x64`... Optional (0.1.x packages lack it); unknown fields are ignored.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub platform: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auth: Option<Auth>,
}

/// The platform string packages declare for the machine this build runs on.
pub const CURRENT_PLATFORM: &str = if cfg!(all(windows, target_arch = "x86_64")) {
    "windows-x64"
} else if cfg!(all(windows, target_arch = "aarch64")) {
    "windows-arm64"
} else if cfg!(target_os = "macos") {
    "macos-arm64"
} else {
    "other"
};

/// A package for another platform is rejected instead of failing when it is executed.
pub fn platform_matches(declared: Option<&str>, current: &str) -> bool {
    declared.is_none_or(|platform| platform == current)
}

pub fn safe_component(value: &str) -> bool {
    !value.is_empty()
        && value.chars().count() <= 64
        && value != "."
        && value != ".."
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_'))
}

impl Manifest {
    pub fn validate(&self) -> Outcome<()> {
        if self.protocol_version != PROTOCOL_VERSION
            || !safe_component(&self.id)
            || !safe_component(&self.executable)
            || self.name.is_empty()
            || self.name.chars().count() > 100
            || self.version.chars().count() > 40
            || self.credential_label.chars().count() > 100
        {
            return Err(Failure::Invalid);
        }
        if !platform_matches(self.platform.as_deref(), CURRENT_PLATFORM) {
            return Err(Failure::Invalid);
        }
        if let Some(auth) = &self.auth {
            auth.validate()?;
        }
        Ok(())
    }

    pub fn parse(bytes: &[u8]) -> Outcome<Self> {
        if bytes.is_empty() || bytes.len() as u64 > MAX_MANIFEST_BYTES {
            return Err(Failure::Invalid);
        }
        let manifest: Self = serde_json::from_slice(bytes).map_err(|_| Failure::Invalid)?;
        manifest.validate()?;
        Ok(manifest)
    }

    pub fn uses_webview_auth(&self) -> bool {
        self.auth
            .as_ref()
            .is_some_and(|auth| auth.kind == "webview")
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RequestTrack {
    pub video_id: String,
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub duration_seconds: Option<u64>,
    pub explicit: Option<bool>,
}

/// Holds the credential: its `Debug` output is deliberately redacted and it is never logged.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Request {
    pub protocol_version: u32,
    pub request_id: String,
    pub credential: String,
    pub output_directory: String,
    pub track: RequestTrack,
}

impl std::fmt::Debug for Request {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Request")
            .field("request_id", &self.request_id)
            .field("credential", &"<redacted>")
            .finish_non_exhaustive()
    }
}

impl Request {
    pub fn new(
        request_id: String,
        credential: String,
        output_directory: String,
        track: RequestTrack,
    ) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            request_id,
            credential,
            output_directory,
            track,
        }
    }

    /// Serialised stdin payload, bounded to 32 KiB.
    pub fn encode(&self) -> Outcome<Vec<u8>> {
        let bytes = serde_json::to_vec(self).map_err(|_| Failure::Invalid)?;
        if bytes.len() > MAX_INPUT_BYTES {
            return Err(Failure::Invalid);
        }
        Ok(bytes)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Reply {
    pub protocol_version: u32,
    pub request_id: String,
    pub status: String,
    #[serde(default)]
    pub file_name: Option<String>,
}

impl Reply {
    /// A reply must belong to this request and `ready` may only refer to `visual.mp4`.
    pub fn validate(&self, request_id: &str) -> Outcome<()> {
        let status_ok = STATUSES.contains(&self.status.as_str());
        let file_ok = self.status != "ready" || self.file_name.as_deref() == Some(OUTPUT_FILE_NAME);
        if self.protocol_version == PROTOCOL_VERSION
            && self.request_id == request_id
            && status_ok
            && file_ok
        {
            Ok(())
        } else {
            Err(Failure::Invalid)
        }
    }

    pub fn parse(bytes: &[u8], request_id: &str) -> Outcome<Self> {
        let reply: Self = serde_json::from_slice(bytes).map_err(|_| Failure::Invalid)?;
        reply.validate(request_id)?;
        Ok(reply)
    }
}

/// Bearer tokens are short printable ASCII. Applied to manual and recovered tokens alike.
pub fn validate_credential(raw: &str) -> Outcome<String> {
    let token = raw.trim();
    if token.is_empty()
        || token.len() > MAX_CREDENTIAL_BYTES
        || !token.bytes().all(|b| (32..127).contains(&b))
    {
        return Err(Failure::Credential);
    }
    Ok(token.to_owned())
}

/// Dotted-number comparison used to upgrade the installed copy from the bundled one.
pub fn is_newer_version(candidate: &str, installed: &str) -> bool {
    /// Dotted integers only ("0.10.0" > "0.9.3"); anything else is never an upgrade.
    fn parts(value: &str) -> Option<Vec<u64>> {
        value.split('.').map(|part| part.parse().ok()).collect()
    }
    let (Some(a), Some(b)) = (parts(candidate), parts(installed)) else {
        return false;
    };
    for i in 0..a.len().max(b.len()) {
        let (x, y) = (
            a.get(i).copied().unwrap_or(0),
            b.get(i).copied().unwrap_or(0),
        );
        if x != y {
            return x > y;
        }
    }
    false
}

/// Cache file stem for a YouTube video id: safe characters only, hashed when it does not fit.
pub fn cache_key(video_id: &str) -> String {
    use sha2::{Digest, Sha256};
    let sanitized: String = video_id
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
        .collect();
    if !sanitized.is_empty() && sanitized.chars().count() <= 64 {
        return sanitized;
    }
    Sha256::digest(video_id.as_bytes())
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const MANIFEST: &str = r#"{"protocolVersion":1,"id":"spotify-canvas","name":"Spotify Canvas","version":"0.1.5","executable":"sideb-spotify-canvas.exe","credentialLabel":"Spotify Web Player Bearer","auth":{"type":"webview","loginUrl":"https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F","targetHost":"open.spotify.com","tokenUrl":"https://open.spotify.com/get_access_token?reason=transport&productType=web_player"}}"#;

    #[test]
    fn real_manifest_parses_and_round_trips() {
        let manifest = Manifest::parse(MANIFEST.as_bytes()).unwrap();
        assert!(manifest.uses_webview_auth());
        let again = Manifest::parse(&serde_json::to_vec(&manifest).unwrap()).unwrap();
        assert_eq!(manifest, again);
    }

    #[test]
    fn manifest_rejects_paths_versions_and_insecure_auth() {
        let with = |from: &str, to: &str| MANIFEST.replace(from, to);
        for bad in [
            with("sideb-spotify-canvas.exe", "..\\evil.exe"),
            with("sideb-spotify-canvas.exe", "dir/evil"),
            with("\"protocolVersion\":1", "\"protocolVersion\":2"),
            with(
                "https://accounts.spotify.com",
                "http://accounts.spotify.com",
            ),
            with("\"type\":\"webview\"", "\"type\":\"other\""),
            with("open.spotify.com\",\"tokenUrl", "\",\"tokenUrl"),
            with("\"id\":\"spotify-canvas\"", "\"id\":\"\""),
        ] {
            assert_eq!(
                Manifest::parse(bad.as_bytes()),
                Err(Failure::Invalid),
                "{bad}"
            );
        }
        assert_eq!(Manifest::parse(&[b' '; 9000]), Err(Failure::Invalid));
        assert_eq!(Manifest::parse(b""), Err(Failure::Invalid));
    }

    #[test]
    fn platform_is_optional_checked_and_unknown_fields_are_ignored() {
        assert!(platform_matches(None, "windows-x64"));
        assert!(platform_matches(Some("windows-x64"), "windows-x64"));
        assert!(!platform_matches(Some("macos-arm64"), "windows-x64"));
        let extra = MANIFEST.replace("\"id\"", "\"futureField\":{\"a\":1},\"id\"");
        assert!(Manifest::parse(extra.as_bytes()).is_ok());
        let current = MANIFEST.replace(
            "\"id\"",
            &format!("\"platform\":\"{CURRENT_PLATFORM}\",\"id\""),
        );
        assert_eq!(
            Manifest::parse(current.as_bytes())
                .unwrap()
                .platform
                .as_deref(),
            Some(CURRENT_PLATFORM)
        );
        let foreign = MANIFEST.replace("\"id\"", "\"platform\":\"plan9-mips\",\"id\"");
        assert_eq!(Manifest::parse(foreign.as_bytes()), Err(Failure::Invalid));
    }

    #[test]
    fn target_host_matches_subdomains_but_not_lookalikes() {
        let auth = Manifest::parse(MANIFEST.as_bytes()).unwrap().auth.unwrap();
        assert!(auth.is_target_host("open.spotify.com"));
        assert!(auth.is_target_host("www.open.spotify.com"));
        assert!(!auth.is_target_host("evilopen.spotify.com"));
        assert!(!auth.is_target_host("open.spotify.com.evil.net"));
        assert_eq!(auth.cookie_domain(), "spotify.com");
    }

    fn reply(status: &str, file: Option<&str>) -> Reply {
        Reply {
            protocol_version: 1,
            request_id: "r1".into(),
            status: status.into(),
            file_name: file.map(str::to_owned),
        }
    }

    #[test]
    fn reply_is_bound_to_request_status_and_file() {
        assert!(reply("ready", Some("visual.mp4")).validate("r1").is_ok());
        assert!(reply("absent", None).validate("r1").is_ok());
        assert!(reply("ready", Some("visual.mp4")).validate("r2").is_err());
        assert!(reply("ready", None).validate("r1").is_err());
        assert!(reply("ready", Some("../visual.mp4"))
            .validate("r1")
            .is_err());
        assert!(reply("ready", Some("https://x/visual.mp4"))
            .validate("r1")
            .is_err());
        assert!(reply("exploded", None).validate("r1").is_err());
        for status in STATUSES.iter().filter(|s| **s != "ready") {
            assert!(reply(status, None).validate("r1").is_ok());
        }
        let mut wrong = reply("absent", None);
        wrong.protocol_version = 2;
        assert!(wrong.validate("r1").is_err());
    }

    #[test]
    fn reply_parse_rejects_garbage_and_missing_fields() {
        assert!(Reply::parse(
            br#"{"protocolVersion":1,"requestId":"r1","status":"absent"}"#,
            "r1"
        )
        .is_ok());
        assert!(Reply::parse(b"not json", "r1").is_err());
        assert!(Reply::parse(br#"{"protocolVersion":1,"status":"absent"}"#, "r1").is_err());
    }

    #[test]
    fn request_uses_exact_wire_names_and_is_bounded() {
        let track = RequestTrack {
            video_id: "v".into(),
            title: "t".into(),
            artist: "a".into(),
            album: None,
            duration_seconds: Some(200),
            explicit: Some(true),
        };
        let request = Request::new(
            "r1".into(),
            "secret".into(),
            "C:\\out".into(),
            track.clone(),
        );
        let json: serde_json::Value = serde_json::from_slice(&request.encode().unwrap()).unwrap();
        assert_eq!(json["protocolVersion"], 1);
        assert_eq!(json["requestId"], "r1");
        assert_eq!(json["outputDirectory"], "C:\\out");
        assert_eq!(json["track"]["videoId"], "v");
        assert_eq!(json["track"]["durationSeconds"], 200);
        assert_eq!(json["track"]["explicit"], true);
        assert!(!format!("{request:?}").contains("secret"));
        let huge = Request::new(
            "r1".into(),
            "x".into(),
            "o".into(),
            RequestTrack {
                title: "x".repeat(40_000),
                ..track
            },
        );
        assert_eq!(huge.encode(), Err(Failure::Invalid));
    }

    #[test]
    fn credential_validation_matches_the_mac_host() {
        assert_eq!(
            validate_credential("  BQAbc-123_def  ").unwrap(),
            "BQAbc-123_def"
        );
        for bad in ["", "   ", "tok\nen", "tóken", &"a".repeat(8193)] {
            assert_eq!(validate_credential(bad), Err(Failure::Credential));
        }
        assert!(validate_credential(&"a".repeat(8192)).is_ok());
    }

    #[test]
    fn version_comparison_and_cache_key() {
        assert!(is_newer_version("0.1.5", "0.1.4"));
        assert!(is_newer_version("0.2", "0.1.9"));
        assert!(is_newer_version("1.0.0", "0.9.9"));
        assert!(!is_newer_version("0.1.5", "0.1.5"));
        assert!(!is_newer_version("0.1.4", "0.1.5"));
        assert!(is_newer_version("0.10.0", "0.9.3"));
        assert!(
            !is_newer_version("0.2.0-beta", "0.1.0"),
            "non numeric is never an upgrade"
        );
        assert!(!is_newer_version("1.0.0", ""));
        assert_eq!(cache_key("dQw4w9WgXcQ"), "dQw4w9WgXcQ");
        assert_eq!(cache_key("a/b\\c:d"), "abcd");
        let hashed = cache_key(&"é".repeat(70));
        assert_eq!(hashed.len(), 64);
        assert!(hashed.bytes().all(|b| b.is_ascii_hexdigit()));
    }
}
