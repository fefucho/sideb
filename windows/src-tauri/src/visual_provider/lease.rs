//! Per-request private directories and their leases. A directory is owned by the process that
//! created it (`.owner` holds its PID). Leftovers older than 24 h are removed at start-up only when
//! that PID no longer exists: another running instance may still hold a recent (or long) lease.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime};

pub const OWNER_FILE: &str = ".owner";
pub const ABANDONED_AFTER: Duration = Duration::from_secs(24 * 60 * 60);

/// Unique, non-guessable-enough directory name without extra dependencies.
pub fn unique_name() -> String {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let nanos = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!(
        "{:x}-{:x}-{:x}",
        nanos,
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    )
}

pub fn create_session_dir(sessions: &Path) -> std::io::Result<PathBuf> {
    let dir = sessions.join(unique_name());
    std::fs::create_dir_all(&dir)?;
    std::fs::write(dir.join(OWNER_FILE), std::process::id().to_string())?;
    Ok(dir)
}

/// Removes a directory tree. WebView2 can keep a just-detached video open for a moment, so a
/// failure is retried in the background instead of blocking or being forgotten.
pub fn remove_dir_with_retries(dir: PathBuf) {
    if remove_dir_if_present(&dir) {
        return;
    }
    let _ = std::thread::Builder::new()
        .name("visual-provider-cleanup".into())
        .spawn(move || {
            for delay_ms in [250u64, 500, 1000, 2000, 4000, 8000, 15000] {
                std::thread::sleep(Duration::from_millis(delay_ms));
                if remove_dir_if_present(&dir) {
                    return;
                }
            }
        });
}

fn remove_dir_if_present(dir: &Path) -> bool {
    match std::fs::remove_dir_all(dir) {
        Ok(()) => true,
        Err(error) => error.kind() == std::io::ErrorKind::NotFound,
    }
}

/// `pid_alive` and `now` are injected so the policy is testable on any OS.
pub fn sweep_abandoned(sessions: &Path, now: SystemTime, pid_alive: &dyn Fn(u32) -> bool) -> usize {
    let Ok(entries) = std::fs::read_dir(sessions) else {
        return 0;
    };
    let mut removed = 0;
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(meta) = entry.metadata() else { continue };
        if !meta.is_dir() || meta.file_type().is_symlink() {
            continue;
        }
        let Some(age) = meta
            .modified()
            .ok()
            .and_then(|modified| now.duration_since(modified).ok())
        else {
            continue;
        };
        if age <= ABANDONED_AFTER {
            continue;
        }
        let Some(pid) = std::fs::read_to_string(path.join(OWNER_FILE))
            .ok()
            .and_then(|text| text.trim().parse::<u32>().ok())
            .filter(|pid| *pid > 0)
        else {
            continue;
        };
        if !pid_alive(pid) && std::fs::remove_dir_all(&path).is_ok() {
            removed += 1;
        }
    }
    removed
}

/// True when a process with this PID exists (Access Denied still means it exists).
pub fn process_exists(pid: u32) -> bool {
    #[cfg(windows)]
    {
        use windows_sys::Win32::Foundation::{CloseHandle, GetLastError, ERROR_ACCESS_DENIED};
        use windows_sys::Win32::System::Threading::{
            GetExitCodeProcess, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION,
        };
        const STILL_ACTIVE: u32 = 259;
        unsafe {
            let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
            if handle.is_null() {
                return GetLastError() == ERROR_ACCESS_DENIED;
            }
            let mut code = 0u32;
            let ok = GetExitCodeProcess(handle, &mut code);
            CloseHandle(handle);
            ok == 0 || code == STILL_ACTIVE
        }
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        Path::new("/proc").join(pid.to_string()).exists() || !Path::new("/proc/self").exists()
    }
    #[cfg(target_os = "macos")]
    {
        // Development hosts only: assume alive unless it is clearly this process' own stale id.
        pid == std::process::id()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp_root(name: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!("sideb-lease-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        root
    }

    fn make(root: &Path, name: &str, owner: Option<&str>) -> PathBuf {
        let dir = root.join(name);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("visual.mp4"), b"x").unwrap();
        if let Some(owner) = owner {
            fs::write(dir.join(OWNER_FILE), owner).unwrap();
        }
        dir
    }

    #[test]
    fn session_dirs_are_unique_and_record_the_owner() {
        let root = temp_root("create");
        let a = create_session_dir(&root).unwrap();
        let b = create_session_dir(&root).unwrap();
        assert_ne!(a, b);
        assert_eq!(
            fs::read_to_string(a.join(OWNER_FILE)).unwrap(),
            std::process::id().to_string()
        );
    }

    #[test]
    fn sweep_removes_only_old_directories_whose_owner_is_gone() {
        let root = temp_root("sweep");
        let dead = make(&root, "dead", Some("4242"));
        let alive = make(&root, "alive", Some("7"));
        let no_owner = make(&root, "no-owner", None);
        let garbage = make(&root, "garbage", Some("not-a-pid"));
        let zero = make(&root, "zero", Some("0"));
        let loose_file = root.join("stray.txt");
        fs::write(&loose_file, b"x").unwrap();
        let pid_alive = |pid: u32| pid == 7;
        // Nothing is older than 24 h yet.
        assert_eq!(sweep_abandoned(&root, SystemTime::now(), &pid_alive), 0);
        assert!(dead.exists());
        // 25 h later every directory is "old"; only the one with a dead owner goes.
        let later = SystemTime::now() + Duration::from_secs(25 * 3600);
        assert_eq!(sweep_abandoned(&root, later, &pid_alive), 1);
        assert!(!dead.exists());
        assert!(alive.exists(), "a live owner keeps its lease however old");
        assert!(no_owner.exists() && garbage.exists() && zero.exists());
        assert!(loose_file.exists());
    }

    #[test]
    fn recent_directories_are_never_swept() {
        let root = temp_root("recent");
        let dir = make(&root, "fresh", Some("4242"));
        assert_eq!(
            sweep_abandoned(
                &root,
                SystemTime::now() + Duration::from_secs(23 * 3600),
                &|_| false
            ),
            0
        );
        assert!(dir.exists());
    }

    #[test]
    fn removal_helper_is_idempotent() {
        let root = temp_root("remove");
        let dir = make(&root, "gone", Some("1"));
        remove_dir_with_retries(dir.clone());
        assert!(!dir.exists());
        remove_dir_with_retries(dir); // already absent: no panic, no thread
    }

    #[test]
    fn current_process_exists() {
        #[cfg(any(windows, all(unix, not(target_os = "macos"))))]
        assert!(process_exists(std::process::id()));
        #[cfg(target_os = "macos")]
        let _ = process_exists(std::process::id());
    }
}
