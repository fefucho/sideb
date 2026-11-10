//! The provider Bearer token lives in its own namespace: a user-scoped DPAPI blob bound to an
//! application-specific entropy value (so the YouTube session blob cannot be swapped in), written
//! atomically, with no plaintext or YTM-session fallback. Same primitives as `session_store.rs`.

use std::path::PathBuf;
use std::sync::Mutex;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StoreError;

pub trait CredentialStore: Send + Sync {
    fn exists(&self) -> bool;
    fn read(&self) -> Option<String>;
    fn save(&self, value: &str) -> Result<(), StoreError>;
    fn delete(&self) -> Result<(), StoreError>;
}

/// Deterministic store for tests and non-Windows development; never touches disk.
#[derive(Default)]
pub struct MemoryCredentialStore {
    value: Mutex<Option<String>>,
    pub reads: std::sync::atomic::AtomicUsize,
}

impl CredentialStore for MemoryCredentialStore {
    fn exists(&self) -> bool {
        self.value.lock().map(|v| v.is_some()).unwrap_or(false)
    }
    fn read(&self) -> Option<String> {
        self.reads.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        self.value.lock().ok().and_then(|v| v.clone())
    }
    fn save(&self, value: &str) -> Result<(), StoreError> {
        *self.value.lock().map_err(|_| StoreError)? = Some(value.to_owned());
        Ok(())
    }
    fn delete(&self) -> Result<(), StoreError> {
        *self.value.lock().map_err(|_| StoreError)? = None;
        Ok(())
    }
}

const FILE_NAME: &str = "visual-provider.dpapi";
const ENTROPY: &[u8] = b"sideb.visual-provider.credential.v1";

/// `dir` is the provider root (`<app local data>/VisualProviders`).
pub struct DpapiCredentialStore {
    dir: PathBuf,
}

impl DpapiCredentialStore {
    pub fn new(dir: PathBuf) -> Self {
        Self { dir }
    }
    fn path(&self) -> PathBuf {
        self.dir.join(FILE_NAME)
    }
    fn temp_path(&self) -> PathBuf {
        self.dir.join("visual-provider.dpapi.tmp")
    }
}

impl CredentialStore for DpapiCredentialStore {
    fn exists(&self) -> bool {
        std::fs::metadata(self.path())
            .map(|m| m.is_file())
            .unwrap_or(false)
    }

    fn read(&self) -> Option<String> {
        let bytes = std::fs::read(self.path()).ok()?;
        let plain = dpapi::unprotect(&bytes, ENTROPY)?;
        String::from_utf8(plain).ok()
    }

    fn save(&self, value: &str) -> Result<(), StoreError> {
        let encrypted = dpapi::protect(value.as_bytes(), ENTROPY).ok_or(StoreError)?;
        std::fs::create_dir_all(&self.dir).map_err(|_| StoreError)?;
        std::fs::write(self.temp_path(), encrypted).map_err(|_| StoreError)?;
        std::fs::rename(self.temp_path(), self.path()).map_err(|_| StoreError)
    }

    fn delete(&self) -> Result<(), StoreError> {
        for target in [self.path(), self.temp_path()] {
            match std::fs::remove_file(target) {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(_) => return Err(StoreError),
            }
        }
        Ok(())
    }
}

#[cfg(windows)]
mod dpapi {
    use windows_sys::Win32::Foundation::LocalFree;
    use windows_sys::Win32::Security::Cryptography::{
        CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
    };

    struct Output(CRYPT_INTEGER_BLOB);
    impl Drop for Output {
        fn drop(&mut self) {
            if !self.0.pbData.is_null() {
                unsafe { std::ptr::write_bytes(self.0.pbData, 0, self.0.cbData as usize) };
                unsafe { LocalFree(self.0.pbData.cast()) };
            }
        }
    }

    fn blob(bytes: &[u8]) -> Option<CRYPT_INTEGER_BLOB> {
        Some(CRYPT_INTEGER_BLOB {
            cbData: u32::try_from(bytes.len()).ok()?,
            pbData: bytes.as_ptr() as *mut u8,
        })
    }

    pub fn protect(plain: &[u8], entropy: &[u8]) -> Option<Vec<u8>> {
        let (input, salt) = (blob(plain)?, blob(entropy)?);
        let mut output = Output(CRYPT_INTEGER_BLOB::default());
        let ok = unsafe {
            CryptProtectData(
                &input,
                std::ptr::null(),
                &salt,
                std::ptr::null(),
                std::ptr::null(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output.0,
            )
        };
        if ok == 0 {
            return None;
        }
        Some(
            unsafe { std::slice::from_raw_parts(output.0.pbData, output.0.cbData as usize) }
                .to_vec(),
        )
    }

    pub fn unprotect(encrypted: &[u8], entropy: &[u8]) -> Option<Vec<u8>> {
        let (input, salt) = (blob(encrypted)?, blob(entropy)?);
        let mut output = Output(CRYPT_INTEGER_BLOB::default());
        let ok = unsafe {
            CryptUnprotectData(
                &input,
                std::ptr::null_mut(),
                &salt,
                std::ptr::null(),
                std::ptr::null(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output.0,
            )
        };
        if ok == 0 {
            return None;
        }
        Some(
            unsafe { std::slice::from_raw_parts(output.0.pbData, output.0.cbData as usize) }
                .to_vec(),
        )
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn roundtrip_binds_entropy_and_hides_plaintext() {
            let secret = b"BQD-test-token-value-0123456789";
            let sealed = protect(secret, b"a").unwrap();
            assert!(!sealed.windows(secret.len()).any(|w| w == secret));
            assert_eq!(unprotect(&sealed, b"a").as_deref(), Some(&secret[..]));
            assert!(unprotect(&sealed, b"b").is_none());
        }
    }
}

/// Non-Windows builds (development hosts, unit tests) have no DPAPI: nothing is ever persisted.
#[cfg(not(windows))]
mod dpapi {
    pub fn protect(_: &[u8], _: &[u8]) -> Option<Vec<u8>> {
        None
    }
    pub fn unprotect(_: &[u8], _: &[u8]) -> Option<Vec<u8>> {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn memory_store_round_trips_and_deletes() {
        let store = MemoryCredentialStore::default();
        assert!(!store.exists() && store.read().is_none());
        store.save("token").unwrap();
        assert!(store.exists());
        assert_eq!(store.read().as_deref(), Some("token"));
        store.delete().unwrap();
        assert!(!store.exists());
    }

    #[cfg(windows)]
    #[test]
    fn dpapi_file_store_never_writes_plaintext() {
        let dir = std::env::temp_dir().join(format!("sideb-vp-dpapi-{}", std::process::id()));
        let store = DpapiCredentialStore::new(dir.clone());
        let secret = "BQD-local-fixture-value-9876543210";
        store.save(secret).unwrap();
        let on_disk = std::fs::read(store.path()).unwrap();
        assert!(!on_disk
            .windows(secret.len())
            .any(|w| w == secret.as_bytes()));
        assert_eq!(store.read().as_deref(), Some(secret));
        store.delete().unwrap();
        assert!(!store.exists());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[cfg(not(windows))]
    #[test]
    fn without_dpapi_nothing_is_persisted_in_plaintext() {
        let dir = std::env::temp_dir().join(format!("sideb-vp-noplain-{}", std::process::id()));
        let store = DpapiCredentialStore::new(dir.clone());
        assert!(store.save("secret-secret-secret-secret").is_err());
        assert!(!store.exists() && !dir.join(FILE_NAME).exists());
    }
}
