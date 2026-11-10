//! Time and decision rules of the host, as pure functions so they are testable on any OS.

use super::protocol::{is_newer_version, validate_credential, Manifest};
use std::time::Duration;

/// Growing pauses while the session stays rejected (FIX-300): 20 s ... 30 min.
pub const RECOVERY_DELAYS_SECS: [u64; 5] = [20, 90, 300, 900, 1800];
/// Web Player tokens last about an hour: renew quietly before that.
pub const MAX_CREDENTIAL_AGE: Duration = Duration::from_secs(50 * 60);
/// A failed proactive refresh is not retried on every track.
pub const PROACTIVE_RETRY: Duration = Duration::from_secs(5 * 60);
/// HTTP 429 from the provider pauses every query.
pub const RATE_LIMIT_PAUSE: Duration = Duration::from_secs(60);
/// Coming back to the app retries a rejected session at most once a minute.
pub const FOREGROUND_RETRY_MIN: Duration = Duration::from_secs(60);
/// Two local requests may coexist while the surface changes.
pub const MAX_CONCURRENT_JOBS: usize = 2;

pub fn recovery_delay(attempt: usize) -> Duration {
    Duration::from_secs(RECOVERY_DELAYS_SECS[attempt.min(RECOVERY_DELAYS_SECS.len() - 1)])
}

pub fn proactive_refresh_due(
    saved_age: Option<Duration>,
    since_last_attempt_allowed: bool,
    has_auth: bool,
    has_credential: bool,
    auth_blocked: bool,
) -> bool {
    has_auth
        && has_credential
        && !auth_blocked
        && since_last_attempt_allowed
        && saved_age.is_some_and(|age| age > MAX_CREDENTIAL_AGE)
}

/// Only the sidebar's vertical player may fall back to an optional provider, and only enabled.
pub fn allow_secondary(vertical_player: bool, provider_enabled: bool) -> bool {
    vertical_player && provider_enabled
}

/// A token the provider already rejected, or an empty/odd one, is not progress.
pub fn accept_token(candidate: &str, rejected: Option<&str>) -> Option<String> {
    let trimmed = candidate.trim();
    let bare = trimmed
        .get(..7)
        .filter(|prefix| prefix.eq_ignore_ascii_case("bearer "))
        .map_or(trimmed, |_| trimmed[7..].trim());
    if bare.len() <= 20 {
        return None;
    }
    let token = validate_credential(bare).ok()?;
    (Some(token.as_str()) != rejected).then_some(token)
}

/// The hook keeps every distinct token it saw, oldest first; the newest usable one wins.
pub fn pick_token(tokens: &[String], rejected: Option<&str>) -> Option<String> {
    tokens
        .iter()
        .rev()
        .find_map(|token| accept_token(token, rejected))
}

/// `eval_with_callback` hands back JSON text: an array of strings, a string, or `null`.
pub fn tokens_from_eval(json: &str) -> Vec<String> {
    match serde_json::from_str::<serde_json::Value>(json) {
        Ok(serde_json::Value::Array(items)) => items
            .into_iter()
            .filter_map(|item| item.as_str().map(str::to_owned))
            .collect(),
        Ok(serde_json::Value::String(token)) => vec![token],
        _ => Vec::new(),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BundledAction {
    Nothing,
    Install,
    Upgrade,
}

/// First launch installs the preinstalled package WITHOUT enabling it; an explicit uninstall is
/// remembered and never undone silently; the same provider id is upgraded in place.
pub fn bundled_action(
    installed: Option<&Manifest>,
    bundled: Option<&Manifest>,
    removed_by_user: bool,
) -> BundledAction {
    match (installed, bundled) {
        (_, None) => BundledAction::Nothing,
        (None, Some(_)) if removed_by_user => BundledAction::Nothing,
        (None, Some(_)) => BundledAction::Install,
        (Some(old), Some(new))
            if old.id == new.id && is_newer_version(&new.version, &old.version) =>
        {
            BundledAction::Upgrade
        }
        _ => BundledAction::Nothing,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest(id: &str, version: &str) -> Manifest {
        Manifest {
            protocol_version: 1,
            id: id.into(),
            name: "P".into(),
            version: version.into(),
            executable: "p.exe".into(),
            credential_label: "c".into(),
            platform: None,
            auth: None,
        }
    }

    #[test]
    fn backoff_grows_from_20_seconds_to_30_minutes_and_stays() {
        let secs: Vec<u64> = (0..8).map(|i| recovery_delay(i).as_secs()).collect();
        assert_eq!(secs, [20, 90, 300, 900, 1800, 1800, 1800, 1800]);
        assert_eq!(recovery_delay(usize::MAX).as_secs(), 1800);
    }

    #[test]
    fn proactive_refresh_needs_an_old_token_a_working_session_and_no_recent_attempt() {
        let old = Some(Duration::from_secs(51 * 60));
        assert!(proactive_refresh_due(old, true, true, true, false));
        assert!(!proactive_refresh_due(
            Some(Duration::from_secs(50 * 60)),
            true,
            true,
            true,
            false
        ));
        assert!(!proactive_refresh_due(None, true, true, true, false));
        assert!(!proactive_refresh_due(old, false, true, true, false));
        assert!(!proactive_refresh_due(old, true, false, true, false));
        assert!(!proactive_refresh_due(old, true, true, false, false));
        assert!(!proactive_refresh_due(old, true, true, true, true));
    }

    #[test]
    fn only_the_enabled_vertical_player_may_use_a_provider() {
        assert!(allow_secondary(true, true));
        assert!(!allow_secondary(false, true)); // fullscreen never asks
        assert!(!allow_secondary(true, false));
        assert!(!allow_secondary(false, false));
    }

    #[test]
    fn rejected_and_malformed_tokens_are_not_progress() {
        let good = "BQD".to_owned() + &"x".repeat(60);
        assert_eq!(accept_token(&good, None).as_deref(), Some(good.as_str()));
        assert_eq!(
            accept_token(&format!("Bearer {good}"), None).as_deref(),
            Some(good.as_str())
        );
        assert_eq!(
            accept_token(&format!("  bearer   {good} "), None).as_deref(),
            Some(good.as_str())
        );
        assert_eq!(accept_token(&good, Some(&good)), None);
        assert_eq!(accept_token(&format!("Bearer {good}"), Some(&good)), None);
        assert_eq!(accept_token("short", None), None);
        assert_eq!(accept_token("", None), None);
        assert_eq!(accept_token(&format!("{good}\n{good}"), None), None);
        assert_eq!(accept_token(&"é".repeat(40), None), None);
    }

    #[test]
    fn newest_unrejected_token_wins() {
        let (a, b, c) = ("A".repeat(30), "B".repeat(30), "C".repeat(30));
        let all = vec![a.clone(), b.clone(), c.clone()];
        assert_eq!(pick_token(&all, None), Some(c.clone()));
        assert_eq!(pick_token(&all, Some(&c)), Some(b.clone()));
        assert_eq!(pick_token(std::slice::from_ref(&c), Some(&c)), None);
        assert_eq!(pick_token(&[], None), None);
    }

    #[test]
    fn eval_results_are_parsed_defensively() {
        let tok = "T".repeat(30);
        assert_eq!(
            tokens_from_eval(&format!(r#"["{tok}","{tok}x"]"#)),
            vec![tok.clone(), format!("{tok}x")]
        );
        assert_eq!(tokens_from_eval(&format!(r#""{tok}""#)), vec![tok]);
        assert!(tokens_from_eval("null").is_empty());
        assert!(tokens_from_eval("garbage{").is_empty());
        assert!(tokens_from_eval("[1,{\"a\":2}]").is_empty());
    }

    #[test]
    fn preinstall_policy() {
        let bundled = manifest("spotify-canvas", "0.1.5");
        let same = manifest("spotify-canvas", "0.1.5");
        let older = manifest("spotify-canvas", "0.1.4");
        let other = manifest("other", "9.9.9");
        assert_eq!(
            bundled_action(None, Some(&bundled), false),
            BundledAction::Install
        );
        assert_eq!(
            bundled_action(None, Some(&bundled), true),
            BundledAction::Nothing
        );
        assert_eq!(bundled_action(None, None, false), BundledAction::Nothing);
        assert_eq!(
            bundled_action(Some(&older), Some(&bundled), true),
            BundledAction::Upgrade
        );
        assert_eq!(
            bundled_action(Some(&same), Some(&bundled), false),
            BundledAction::Nothing
        );
        assert_eq!(
            bundled_action(Some(&other), Some(&bundled), false),
            BundledAction::Nothing
        );
        assert_eq!(
            bundled_action(Some(&same), None, false),
            BundledAction::Nothing
        );
    }
}
