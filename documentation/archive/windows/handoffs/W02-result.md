> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W02 — Shell Tauri 2 + Svelte + TypeScript en Windows (M1)

**Fecha:** 2026-09-29.  
**Estado:** Hecho. Ventana Tauri comprobada en Windows x64; dependencia por ruta a `sideb-core` compilada; tests de `innertube` y `sideb-core` aprobados (7 pruebas en vivo ignoradas). Iconos generados desde el logo del proyecto. La captura verifica contenido renderizado y una llamada IPC de diagnóstico. M1 queda cubierto a nivel de shell; la instancia funcional del core empieza en M2.

---

## 1. Alcance implementado

- **Scaffold oficial:** Creado en [`windows/`](../../../../windows) con Tauri 2, Svelte 5, TypeScript y pnpm v12 (template `svelte-ts` de `create-tauri-app`).
- **Identidad de la app:**
  - `productName`: `Side B`
  - `identifier`: `com.fefucho.sideb.windows`
  - Título de ventana: `Side B` (1100x720, min 800x600).
- **Iconos y Favicon:**
  - Generados con `pnpm tauri icon` a partir de [`apple/Resources/AppIcon copy.icon/Assets/NUEVO LOGO.png`](../../../../apple/Resources/AppIcon%20copy.icon/Assets/NUEVO%20LOGO.png) (sin modificar ningún archivo de `apple/`).
  - Producidos todos los tamaños de Windows Appx, `icon.ico`, `icon.icns` y PNGs en [`windows/src-tauri/icons/`](../../../../windows/src-tauri/icons).
  - Favicon web generado en [`windows/static/favicon.png`](../../../../windows/static/favicon.png) y logotipo web en [`windows/static/logo.png`](../../../../windows/static/logo.png).
- **Dependencia compartida con `core/`:**
  - En [`windows/src-tauri/Cargo.toml`](../../../../windows/src-tauri/Cargo.toml): dependencia de ruta real `sideb-core = { path = "../../core/crates/sideb-core" }`.
  - En [`windows/src-tauri/src/lib.rs`](../../../../windows/src-tauri/src/lib.rs): comando IPC `get_backend_status` que referencia un tipo de `sideb-core` (`sideb_core::SideBError`). Es una prueba de compilación e IPC; aún no inicializa ni consulta `SideBCore`.
  - No se implementó búsqueda, login ni audio (reservados para M2 y M3 en adelante).
- **Documentación y CI:**
  - Creado [`windows/README.md`](../../../../windows/README.md) con prerrequisitos, comandos, iconos y arquitectura.
  - Creado [`.github/workflows/windows.yml`](../../../../.github/workflows/windows.yml) con pipeline para Windows x64 (`windows-latest`, test de crates de `core` y compilación de `windows/`).

---

## 2. Entorno y hardware de ejecución

- **SO:** Windows 11 Pro x64 (build 26200).
- **CPU:** AMD Ryzen 5 5500 (6 núcleos, 12 hilos).
- **RAM:** 16 GB.
- **DPI:** 96 (100 %).
- **Almacenamiento C:** ~7.92 GB libres tras limpieza de artefactos temporales y `cargo clean`.
- **Herramientas:**
  - MSVC v143 (Visual Studio Build Tools 2022 v17.14.26).
  - Rust 1.98.1 (`stable-x86_64-pc-windows-msvc`), cargo 1.98.1.
  - Node.js v24.13.1, pnpm v12.6.0.
  - WebView2 Runtime 153.0.4234.48.

---

## 3. Comandos ejecutados y resultados exactos

| Paso | Comando | Resultado exacto |
| --- | --- | --- |
| Scaffold Tauri | `pnpm create tauri-app windows -m pnpm -t svelte-ts --tauri-version 2 --identifier com.sideb.app -y` | Código 0. Estructura creada en `windows/`; después se corrigió `tauri.conf.json` a `com.fefucho.sideb.windows`. |
| Iconos nativos y web | `pnpm tauri icon "../apple/Resources/AppIcon copy.icon/Assets/NUEVO LOGO.png"` | Código 0. Generados Appx, `icon.ico`, `icon.icns`, PNGs y `favicon.png`. |
| Dependencias frontend | `pnpm install` en `windows/` | Código 0. 61 paquetes instalados en 7.2s. |
| Build frontend | `pnpm build` en `windows/` | Código 0. Generó `windows/build/` estático con SvelteKit adapter-static en 3.85s. |
| Chequeo Rust | `cargo check` en `windows/src-tauri/` | Código 0. Crate `sideb-windows` y `sideb-core` validados en 8.98s. |
| Compilación nativa | `cargo build` en `windows/src-tauri/` | Código 0. Binario nativo generado: `windows/src-tauri/target/debug/sideb-windows.exe` (44.6 MB). Enlace de iconos y dependencias en 1.68s tras incremental. |
| Ejecución y ventana | `pnpm tauri dev` en `windows/` | Sesión de desarrollo iniciada; Vite respondió `HTTP 200`, corrieron `sideb-windows.exe` y WebView2. El proceso es de larga duración, por lo que no se atribuye código de salida 0. La captura CDP de la ventana confirmó el contenido. |
| Inspección DOM y captura visual | Chrome DevTools Protocol (`Page.captureScreenshot` / `Runtime.evaluate`) | Código 0. Contenido renderizado verificado (título, logo, estado IPC activo `sideb-core connected`) y captura guardada en `windows/rendered_window.png`. |
| Regresión core `innertube` | `cargo test -p innertube` en `core/` | Código 0. 87 pasadas, 0 falladas. |
| Regresión core `sideb-core` | `cargo test -p sideb-core` en `core/` | Código 0. 79 pasadas, 0 falladas, 7 ignoradas (live providers). |

---

## 4. Evidencia visual y contenido renderizado

La verificación de la ventana renderizada arrojó el siguiente contenido textual e interactivo extraído directamente del WebView2 activo:

- **Encabezado:** Logo oficial de Side B renderizado (`/logo.png`), etiqueta `Side B v0.1.0 • Windows M1 Scaffold`, título `Side B Windows`.
- **Estado de conexión Rust:** `sideb-core connected (sideb_core::SideBError)` con indicador lumínico activo (verde).
- **Interacción IPC:** Tarjeta con campo de entrada `Ingresá tu nombre...` y botón `Saludar`.
- **Pie de página:** Referencia de arquitectura compartida `core/crates/sideb-core`.
- **Evidencia gráfica:** Archivo de captura PNG guardado en [`windows/rendered_window.png`](../screenshots/rendered_window.png), sin datos de usuario, cuentas ni URLs privadas.

---

## 5. Incidencias resueltas durante W02

1. **Almacenamiento en disco (Error 112 / `no space on device`):**
   - La unidad `C:` alcanzó 0 bytes libres durante la compilación inicial de los artefactos de depuración de Rust/V8/Tauri.
   - **Solución:** Se liberaron artefactos de depuración con `cargo clean` en `core/` y se redirigió `windows\src-tauri\target` mediante una unión NTFS local a `S:\sideb-target\windows`. La unión no forma parte de los archivos fuente ni es un requisito para otros equipos; allí se necesita espacio suficiente para los artefactos Rust.
2. **Identificador del paquete:**
   - Se ajustó el bundle identifier a `com.fefucho.sideb.windows` en [`windows/src-tauri/tauri.conf.json`](../../../../windows/src-tauri/tauri.conf.json) y [`windows/README.md`](../../../../windows/README.md).
3. **Iconos nativos:**
   - Sustituidos los iconos genéricos del scaffold ejecutando `tauri icon` a partir del arte original de Side B sin tocar `apple/`.

---

## 6. Verificaciones pendientes para los siguientes paquetes

- **W03 / M2:** Instanciar un `Arc<SideBCore>` global con la ruta de datos `%APPDATA%/com.fefucho.sideb.windows` y exponer comandos Tauri tipados para búsqueda y catálogo (`get_home_page`, `search_all`, `get_album`, `resolve_stream`).
- **M3:** Prototipado e integración de `libmpv` / motor de audio en Windows x64.
