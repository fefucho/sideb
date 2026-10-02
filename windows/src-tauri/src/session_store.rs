//! User-scoped Windows DPAPI storage for the YouTube session. Only encrypted bytes touch disk.

use std::path::{Path, PathBuf};
use windows_sys::Win32::Foundation::LocalFree;
use windows_sys::Win32::Security::Cryptography::{
    CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
};

const FILE_NAME: &str = "youtube-session.dpapi";

fn path(dir: &Path) -> PathBuf {
    dir.join(FILE_NAME)
}

struct ProtectedBlob(CRYPT_INTEGER_BLOB);

impl Drop for ProtectedBlob {
    fn drop(&mut self) {
        if !self.0.pbData.is_null() {
            unsafe { std::ptr::write_bytes(self.0.pbData, 0, self.0.cbData as usize) };
            unsafe { LocalFree(self.0.pbData.cast()) };
        }
    }
}

fn input_blob(bytes: &[u8]) -> Result<CRYPT_INTEGER_BLOB, String> {
    let len = u32::try_from(bytes.len())
        .map_err(|_| "La sesión excede el tamaño admitido.".to_string())?;
    Ok(CRYPT_INTEGER_BLOB {
        cbData: len,
        pbData: bytes.as_ptr() as *mut u8,
    })
}

pub fn save(dir: &Path, cookie: &str) -> Result<(), String> {
    let input = input_blob(cookie.as_bytes())?;
    let mut output = ProtectedBlob(CRYPT_INTEGER_BLOB::default());
    let ok = unsafe {
        CryptProtectData(
            &input,
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut output.0,
        )
    };
    if ok == 0 {
        return Err("Windows no pudo proteger la sesión.".into());
    }
    let encrypted =
        unsafe { std::slice::from_raw_parts(output.0.pbData, output.0.cbData as usize) };
    std::fs::create_dir_all(dir).map_err(|_| "No se pudo preparar el almacén de sesión.")?;
    let temp = dir.join("youtube-session.dpapi.tmp");
    std::fs::write(&temp, encrypted).map_err(|_| "No se pudo guardar la sesión protegida.")?;
    std::fs::rename(&temp, path(dir))
        .map_err(|_| "No se pudo confirmar la sesión protegida.".to_string())
}

pub fn load(dir: &Path) -> Result<Option<String>, String> {
    let bytes = match std::fs::read(path(dir)) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err("No se pudo leer la sesión protegida.".into()),
    };
    let input = input_blob(&bytes)?;
    let mut output = ProtectedBlob(CRYPT_INTEGER_BLOB::default());
    let ok = unsafe {
        CryptUnprotectData(
            &input,
            std::ptr::null_mut(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut output.0,
        )
    };
    if ok == 0 {
        return Err("Windows no pudo abrir la sesión protegida.".into());
    }
    let decrypted =
        unsafe { std::slice::from_raw_parts(output.0.pbData, output.0.cbData as usize) };
    String::from_utf8(decrypted.to_vec())
        .map(Some)
        .map_err(|_| "La sesión protegida no contiene texto válido.".into())
}

pub fn delete(dir: &Path) -> Result<(), String> {
    for target in [path(dir), dir.join("youtube-session.dpapi.tmp")] {
        match std::fs::remove_file(target) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(_) => return Err("No se pudo borrar la sesión protegida.".into()),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dpapi_roundtrip_and_delete() {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("sideb-dpapi-{}-{unique}", std::process::id()));
        let fixture = "SAPISID=local-test-value; SID=another-test-value";
        save(&dir, fixture).unwrap();
        let encrypted = std::fs::read(path(&dir)).unwrap();
        assert!(!encrypted
            .windows(fixture.len())
            .any(|part| part == fixture.as_bytes()));
        assert_eq!(load(&dir).unwrap().as_deref(), Some(fixture));
        let rotated = "SAPISID=local-test-value; SID=rotated-test-value";
        save(&dir, rotated).unwrap();
        assert_eq!(load(&dir).unwrap().as_deref(), Some(rotated));
        delete(&dir).unwrap();
        assert_eq!(load(&dir).unwrap(), None);
        std::fs::remove_dir(&dir).unwrap();
    }
}
