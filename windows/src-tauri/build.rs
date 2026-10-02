use std::env;
use std::fs;
use std::path::{Path, PathBuf};

fn main() {
    tauri_build::build();

    #[cfg(target_os = "windows")]
    {
        println!("cargo:rerun-if-env-changed=SIDEB_MPV_DIR");
        if let Ok(mpv_dir_str) = env::var("SIDEB_MPV_DIR") {
            let mpv_dir = Path::new(&mpv_dir_str);
            if !mpv_dir.exists() {
                panic!("SIDEB_MPV_DIR está definido ({mpv_dir_str}) pero la ruta no existe");
            }

            println!("cargo:rustc-link-search=native={}", mpv_dir.display());

            for dll_name in ["libmpv-2.dll", "vulkan-1.dll", "VulkanRT-License.txt"] {
                let dll_src = mpv_dir.join(dll_name);
                if !dll_src.exists() {
                    panic!(
                        "No se encontró {dll_name} en el directorio SIDEB_MPV_DIR ({mpv_dir_str})"
                    );
                }

                if let Ok(out_dir) = env::var("OUT_DIR") {
                    let out_path = PathBuf::from(out_dir);
                    if let Some(profile_dir) = out_path.ancestors().nth(3) {
                        let dll_dst = profile_dir.join(dll_name);
                        // The running development app can hold the destination DLL open. Reuse it
                        // when it is already the same build instead of attempting a needless copy.
                        let already_current = dll_dst.exists()
                            && matches!((fs::read(&dll_src), fs::read(&dll_dst)),
                            (Ok(source), Ok(destination)) if source == destination);
                        if !already_current {
                            fs::copy(&dll_src, &dll_dst).unwrap_or_else(|err| {
                                panic!(
                                    "Error crítico al copiar {dll_name} de {} a {}: {err}",
                                    dll_src.display(),
                                    dll_dst.display()
                                );
                            });
                        }
                    }
                }
            }
        }
    }
}
