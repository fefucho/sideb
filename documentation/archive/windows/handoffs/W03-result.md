> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W03 — Instancia única de SideBCore y Búsqueda Pública Real en Windows (M2)

**Fecha:** 2026-09-29.  
**Estado:** Hecho. Instancia de `SideBCore` en los datos propios de Tauri; `search_songs` con DTOs Rust/TypeScript y errores estructurados; UI Svelte con estados de carga, vacío y error. La búsqueda pública real y el estado de carga se comprobaron en la ventana Windows con captura sin datos privados. Las fallas de red y de inicialización no se provocaron manualmente. Core y Apple intactos; M2 sigue abierto.

---

## 1. Alcance implementado y revisiones aplicadas

- **Instancia singleton de `SideBCore` no bloqueante y recuperable:**
  - En [`windows/src-tauri/src/lib.rs`](../../../../windows/src-tauri/src/lib.rs): el hook `.setup()` de Tauri inicializa `AppState` con `RwLock<Option<Arc<SideBCore>>>` e `init_error: RwLock<Option<String>>`. Si la inicialización del core o del almacenamiento falla, **la ventana no se cierra**; se registra el error y se expone un comando de recuperación (`retry_init_core`).
  - Base de datos SQLite (`sideb.db`) y cachés aisladas en el directorio de datos propio de la app resuelto vía `app.path().app_data_dir()`.
- **DTOs tipados y desinfección de datos privados:**
  - **DTO de canciones:** `SongDto` en Rust y TypeScript mapeando `videoId`, `title`, `artists`, `album`, `duration`, `thumbnail`, `isVideo`.
  - **DTO de estado higienizado:** `BackendStatusDto { ready: bool, status: String }`. No expone rutas locales del sistema (`dataDir`), nombres de usuario de Windows, versión del shell ni banderas de sesión (`isLoggedIn`).
  - **DTO de error seguro:** `CommandError { code: String, message: String }`. La consulta vacía se rechaza explícitamente (`EMPTY_QUERY`). Los fallos de red retornan un mensaje genérico seguro sin filtrar cadenas internas crudas (`format!("{e}")`) ni volcar trazas a la UI.
- **Comandos Tauri IPC:**
  - `search_songs(query: String) -> Result<Vec<SongDto>, CommandError>`: valida consultas no vacías y consume `state.core.search_songs(query, false)`.
  - `get_backend_status() -> Result<BackendStatusDto, CommandError>`: informa si el motor está listo y su estado.
  - `retry_init_core() -> Result<BackendStatusDto, CommandError>`: permite reconectar o reintentar la inicialización del motor en caliente si falló al arrancar.
- **Interfaz Svelte 5 y control de concurrencia:**
  - En [`windows/src/routes/+page.svelte`](../../../../windows/src/routes/+page.svelte):
    - **ID de petición (Token de generación):** Cada búsqueda incrementa `currentRequestId`; las respuestas desordenadas o viejas se descartan silenciosamente para evitar condiciones de carrera.
    - **Protección de chips y formulario:** Tanto los chips de sugerencias como el input y botón de envío quedan deshabilitados (`disabled={isLoading}`) mientras se resuelve una consulta activa, impidiendo búsquedas concurrentes superpuestas.
    - **Barra de estado segura:** Indicador con punto verde y mensaje descriptivo (`Motor Side B conectado`) sin mostrar rutas de archivo ni nombres de usuario. Si falla, ofrece botón interactivo de reconexión.
    - **Estados UI completos:** Spinner animado durante la carga, estado inicial informativo, estado sin resultados para consultas vacías/sin match, y cuadro de error con reintento ante fallos.
    - **Lista de resultados:** Fichas de canciones con carátula remota, títulos, artistas, álbum, duración y badge de video.
- **Límites estrictos respetados:**
  - No se modificó ningún archivo en `core/` ni en `apple/`.
  - No se implementó login, audio, Home ni detalles de álbum (reservados para los hitos siguientes de M2/M3).
  - No se declara M2 completo; W03 cubre exclusivamente la primera compuerta de búsqueda pública real.

---

## 2. Entorno de compilación y ejecución

- **SO:** Windows 11 Pro x64 (build 26200).
- **CPU:** AMD Ryzen 5 5500 (6 núcleos, 12 hilos).
- **RAM:** 16 GB.
- **DPI:** 96 (100 %).
- **Herramientas:** Visual Studio Build Tools 2022 (MSVC v143), Rust 1.98.1 MSVC, Node.js v24.13.1, pnpm v12.6.0.
- **Target Dir:** `S:\sideb-target\windows` (vía unión NTFS para preservar espacio en `C:`).

---

## 3. Comandos ejecutados y resultados exactos

| Paso | Comando | Resultado exacto |
| --- | --- | --- |
| Diagnósticos TypeScript / Svelte | `corepack pnpm check` (en `windows/`) | Código 0. `svelte-check` encontró 0 errores y 0 advertencias tras remover la directiva obsoleta `@ts-expect-error` en `vite.config.js`. |
| Empaquetado frontend | `corepack pnpm build` (en `windows/`) | Código 0 en 3.84s. Artefactos estáticos generados en `windows/build/`. |
| Chequeo Rust | `cargo check` (en `windows/src-tauri/`) | Código 0 en 4.93s. Crate `sideb-windows` validado con DTOs de error y estado seguro. |
| Compilación nativa | `cargo build` (en `windows/src-tauri/`) | Código 0 en 1m 29s. Binario `sideb-windows.exe` generado y enlazado con `sideb-core`. |
| Validación IPC consulta vacía | `invoke('search_songs', { query: '   ' })` | Rechazado con `CommandError { code: 'EMPTY_QUERY', message: 'La consulta de búsqueda no puede estar vacía.' }`. |
| Concurrencia y chips | Clic en chip *"Daft Punk"* | `chipsDisabled: true` y `hasSpinner: true` validados en el DOM mientras la búsqueda estuvo en vuelo. |
| Búsqueda real en vivo | `search_songs("Daft Punk")` | 20 canciones reales obtenidas de YouTube Music (*"Instant Crush"*, *"Giorgio by Moroder"*, *"One More Time"*, *"Harder, Better, Faster, Stronger"*, etc.). |
| Captura visual sin datos privados | CDP `Page.captureScreenshot` | Captura limpia guardada en `windows/search_results.png` (145 KB) evidenciando los 20 resultados renderizados en el tema oscuro de Side B con cero rutas o datos privados. |

---

## 4. Evidencia visual de la búsqueda real

- **Captura guardada:** [`windows/search_results.png`](../screenshots/search_results.png) (y respaldada en el directorio de artefactos de la sesión).
- **Elementos visibles en la ventana:**
  - Header: Logo de Side B, badge `Side B • Windows W03`, título `Side B`, subtítulo `Búsqueda nativa consumiendo SideBCore::search_songs`.
  - Estado: Indicador verde activo con `Motor Side B conectado` (completamente libre de rutas de usuario o directorios del sistema).
  - Formulario: Consulta `Daft Punk` en el campo de texto con botón de borrado rápido y botón *"Buscar"*.
  - Resultados: Encabezado `Resultados para «Daft Punk»` con badge `20 canciones` y filas de canciones con carátula remota de YouTube Music, artista, álbum y duración.

---

## 5. Archivos modificados o agregados en W03

- [`windows/vite.config.js`](../../../../windows/vite.config.js): Remoción de la directiva `@ts-expect-error` obsoleta para `node:process`.
- [`windows/src-tauri/src/lib.rs`](../../../../windows/src-tauri/src/lib.rs): Inicialización tolerante a fallos de `SideBCore`, DTO `SongDto`, `BackendStatusDto` higienizado, `CommandError` estructurado y comandos `search_songs`, `get_backend_status`, `retry_init_core`.
- [`windows/src/lib/types.ts`](../../../../windows/src/lib/types.ts): Interfaces TypeScript `SongDto`, `BackendStatusDto` y `CommandError`.
- [`windows/src/routes/+page.svelte`](../../../../windows/src/routes/+page.svelte): UI de búsqueda completa con control de concurrencia por ID de petición, sugerencias deshabilitadas durante la carga, estados de carga, vacío, error y resultados.
- [`windows/search_results.png`](../screenshots/search_results.png): Captura visual limpia de la búsqueda real en la ventana nativa.
- [`documentation/handoffs/W03-result.md`](W03-result.md): Informe de entrega de W03.

---

## 6. Próximos pasos hacia el cierre de M2

- Implementar los flujos restantes del hito M2 según `PLAN-013`: comandos y vistas para página de inicio (`get_home_page`), detalle de álbum (`get_album`) y resolución de stream (`resolve_stream`).
- Validar manualmente recuperación de una falla de inicialización y presentación de una falla de red; W03 comprobó el éxito y la consulta vacía, pero no indujo esos fallos.
- No se declara M2 completo hasta cumplir la totalidad de los paquetes correspondientes.
