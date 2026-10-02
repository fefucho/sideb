fn main() {
    #[cfg(target_os = "windows")]
    {
        println!("cargo:rerun-if-env-changed=SIDEB_MPV_DIR");
        if let Ok(mpv_dir) = std::env::var("SIDEB_MPV_DIR") {
            let path = std::path::Path::new(&mpv_dir);
            if path.exists() {
                println!("cargo:rustc-link-search=native={}", path.display());
            } else {
                panic!("SIDEB_MPV_DIR está definido ({mpv_dir}) pero el directorio no existe");
            }
        }
    }
}
