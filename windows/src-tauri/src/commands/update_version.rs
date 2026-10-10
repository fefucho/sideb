pub fn clean_version(raw: &str) -> &str {
    raw.trim_matches(|c: char| c == 'v' || c == 'V' || c.is_whitespace())
}

fn numeric_components(raw: &str) -> Option<Vec<u64>> {
    let base = clean_version(raw).split(['-', '+']).next()?;
    base.split('.')
        .map(|part| {
            if part.is_empty() || !part.bytes().all(|byte| byte.is_ascii_digit()) {
                return None;
            }
            part.parse().ok()
        })
        .collect()
}

/// Compare the numeric app versions shipped in both bundles. Release labels
/// (-beta.1) and build metadata (+build.13) do not identify a newer app version.
pub fn is_version_newer(remote: &str, current: &str) -> bool {
    let (Some(remote), Some(current)) = (numeric_components(remote), numeric_components(current))
    else {
        return false;
    };
    let count = remote.len().max(current.len());
    for i in 0..count {
        match remote
            .get(i)
            .unwrap_or(&0)
            .cmp(current.get(i).unwrap_or(&0))
        {
            std::cmp::Ordering::Greater => return true,
            std::cmp::Ordering::Less => return false,
            std::cmp::Ordering::Equal => {}
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_clean_version() {
        assert_eq!(clean_version("v1.2.3"), "1.2.3");
        assert_eq!(clean_version("V0.1.0"), "0.1.0");
        assert_eq!(clean_version("  1.0.0 \n"), "1.0.0");
        assert_eq!(
            clean_version("v1.2.0-beta.1+build.13"),
            "1.2.0-beta.1+build.13"
        );
    }

    #[test]
    fn test_is_version_newer() {
        assert!(is_version_newer("0.2.0", "0.1.0"));
        assert!(is_version_newer("v1.0.0", "0.9.9"));
        assert!(is_version_newer("0.1.1", "0.1.0"));
        assert!(is_version_newer("1.0.0.1", "1.0.0"));
        assert!(!is_version_newer("0.1.0", "0.1.0"));
        assert!(!is_version_newer("0.0.9", "0.1.0"));
        assert!(!is_version_newer("0.1.0", "0.2.0"));
        assert!(!is_version_newer("1.0", "1.0.0"));
        assert!(is_version_newer("1.0.1", "1.0"));
    }

    #[test]
    fn release_labels_do_not_offer_an_installed_app_version_again() {
        for remote in [
            "v1.2.0-beta.1",
            "1.2.0-beta.999",
            "V1.2.0-rc.99",
            "1.2.0+build.999",
            "1.2.0-beta.1+build.13",
        ] {
            assert!(!is_version_newer(remote, "1.2.0"), "{remote}");
            assert!(!is_version_newer("1.2.0", remote), "{remote}");
        }
    }

    #[test]
    fn labels_do_not_hide_real_updates_or_offer_downgrades() {
        for (remote, current, expected) in [
            ("v1.2.0-beta.1", "1.1.8", true),
            ("v1.2.1-beta.1", "1.2.0", true),
            ("1.3.0-beta.1", "1.2.9", true),
            ("1.2.0-beta.999", "1.2.1", false),
            ("1.2.0+build.999", "1.2.1", false),
            ("v1.1.9-beta.999", "1.2.0", false),
        ] {
            assert_eq!(
                is_version_newer(remote, current),
                expected,
                "{remote} vs {current}"
            );
        }
    }

    #[test]
    fn malformed_versions_do_not_trigger_an_update() {
        for invalid in [
            "",
            "garbage",
            "1..2",
            "1.beta.999",
            "1.2.3trailing",
            "1.-2.0",
            "-1.2.0",
            "18446744073709551616.0.0",
        ] {
            assert!(!is_version_newer(invalid, "1.2.0"), "{invalid}");
            assert!(!is_version_newer("1.2.1", invalid), "{invalid}");
        }
    }
}
