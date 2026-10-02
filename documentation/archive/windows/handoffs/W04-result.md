> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W04 — Búsqueda y Detalle de Álbumes en Windows (M2 parcial)

**Fecha:** 2026-09-29.  
**Estado:** Hecho. Implementada la búsqueda de álbumes (`search_albums`) y la consulta de detalle con pistas reales (`get_album`) consumiendo directamente `SideBCore::search_cards` y `SideBCore::get_album` desde el motor compartido Rust. DTOs tipados en Rust y TypeScript; UI Svelte 5 con selector de modo por pestañas (Canciones / Álbumes), grilla de tarjetas de álbum, vista de detalle con pistas reales sin botones falsos de reproducción, botón de navegación Atrás, control de concurrencia e invalidación de respuestas obsoletas. Ambos modos verificados en la ventana nativa de Windows con evidencia visual limpia sin datos privados. `core/` y `apple/` intactos; M2 continúa abierto.

---

## 1. Alcance implementado y contratos vigentes

- **Contratos del core y comandos IPC añadidos:**
  - En [`windows/src-tauri/src/lib.rs`](../../../../windows/src-tauri/src/lib.rs):
    - `search_albums(query: String) -> Result<Vec<AlbumCardDto>, CommandError>`: consume `state.core.search_cards(trimmed, "albums")`. Valida consultas no vacías (`EMPTY_QUERY`).
    - `get_album(browse_id: String) -> Result<AlbumDetailDto, CommandError>`: consume `state.core.get_album(trimmed)`. Valida identificadores no vacíos (`INVALID_ID`).
    - Conservado intacto `search_songs` (W03), `get_backend_status` y `retry_init_core`.
- **DTOs tipados (Rust & TypeScript):**
  - **Álbum (tarjeta):** `AlbumCardDto` en Rust y [`windows/src/lib/types.ts`](../../../../windows/src/lib/types.ts): `id`, `title`, `subtitle`, `thumbnail`.
  - **Detalle de álbum:** `AlbumDetailDto` en Rust y TypeScript: `browseId`, `title`, `artist`, `subtitle`, `secondSubtitle`, `description`, `thumbnail`, y `items: SongDto[]`.
  - Los ítems de pista (`SongDto`) se exponen estrictamente con campos de presentación (`videoId`, `title`, `artists`, `duration`, `thumbnail`, `isVideo`), sin exponer tokens de biblioteca ni datos de sesión.
  - **Manejo de errores seguro:** Reutilización de `CommandError { code: String, message: String }` con mensajes genéricos protegidos ante contingencias de red, sin registrar datos privados ni filtrar errores crudos `format!("{e}")`.
- **Interfaz Svelte 5 y experiencia de navegación:**
  - En [`windows/src/routes/+page.svelte`](../../../../windows/src/routes/+page.svelte):
    - **Pestañas de modo visibles:** Selector entre **Canciones** y **Álbumes**. Al cambiar de pestaña, se preserva y ejecuta inmediatamente la búsqueda para el nuevo modo.
    - **Grilla responsiva de álbumes:** Tarjetas interactivas con carátula remota, título y subtítulo (artista/año), con soporte para foco y teclado.
    - **Vista de detalle de álbum:** Carátula grande, título, artista, metadatos de duración/año, descripción si está disponible y lista de pistas numeradas con duración. Sin botones de reproducción simulados.
    - **Botón Atrás («Volver a resultados»):** Restaura inmediatamente la grilla de álbumes preservando los resultados previos.
    - **Protección contra respuestas obsoletas:** Cada petición genera un `currentRequestId`; las respuestas desordenadas o de navegación previa se descartan de forma segura.
    - **Desinfección visual:** La ventana muestra únicamente *"Motor Side B conectado"* con punto verde; no existen rutas del sistema de archivos, nombres de usuario ni datos privados.
- **Límites estrictos respetados:**
  - No se modificó ningún archivo en `core/` ni en `apple/`.
  - No se añadió login, audio, Home ni resolución de streams.
  - No se declara M2 completo; W04 cubre la compuerta de búsqueda y detalle de álbumes.

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
| Diagnósticos TypeScript / Svelte | `corepack pnpm check` (en `windows/`) | **Código 0.** `svelte-check found 0 errors and 0 warnings`. |
| Empaquetado frontend | `corepack pnpm build` (en `windows/`) | **Código 0 en 3.75s.** Artefactos estáticos generados en `windows/build/`. |
| Chequeo Rust MSVC | `cargo check` (en `windows/src-tauri/`) | **Código 0 en 5.02s.** Crate `sideb-windows` validado con `search_albums` y `get_album`. |
| Compilación nativa | `cargo build` (en `windows/src-tauri/`) | **Código 0 en 1m 28s.** Binario `sideb-windows.exe` generado y enlazado con `sideb-core`. |
| Validación IPC consulta vacía | `invoke('search_albums', { query: '   ' })` | Rechazado con `CommandError { code: 'EMPTY_QUERY', message: 'La consulta de búsqueda no puede estar vacía.' }`. |
| Validación IPC id inválido | `invoke('get_album', { browseId: '   ' })` | Rechazado con `CommandError { code: 'INVALID_ID', message: 'El identificador de álbum no puede estar vacío.' }`. |
| Búsqueda de canciones (W03) | `search_songs("Daft Punk")` | **20 canciones reales** obtenidas de YouTube Music (*"Instant Crush"*, *"Giorgio by Moroder"*, etc.). Modo W03 conservado. |
| Búsqueda de álbumes (W04) | `search_albums("Daft Punk")` | **20 álbumes reales** obtenidos de YouTube Music (*"Random Access Memories"*, *"Discovery"*, *"Alive 2007"*, etc.). |
| Detalle de álbum real (W04) | `get_album("MPREb_...")` | **13 pistas reales** cargadas de *Random Access Memories* (*"Give Life Back to Music"*, *"The Game of Love"*, *"Giorgio by Moroder"*, etc.) con metadata completa. |
| Navegación Atrás | Clic en «Volver a resultados» | Grilla de 20 álbumes restaurada inmediatamente sin recargar. |
| Captura visual álbumes | CDP `Page.captureScreenshot` | Captura limpia guardada en `windows/album_search_results.png`. |
| Captura visual detalle | CDP `Page.captureScreenshot` | Captura limpia guardada en `windows/album_detail.png` (178 KB) sin datos privados. |

---

## 4. Evidencia visual de la búsqueda y detalle real

- **Captura histórica W03 conservada:** [`windows/search_results.png`](../screenshots/search_results.png).
- **Captura W04 - Búsqueda de álbumes:** [`windows/album_search_results.png`](../screenshots/album_search_results.png).
  - Pestañas visibles con *Álbumes* activo en rojo.
  - Grilla de tarjetas con carátulas remotas de YouTube Music y subtítulo (*Album • Daft Punk • 2013*).
- **Captura W04 - Detalle de álbum:** [`windows/album_detail.png`](../screenshots/album_detail.png) (respaldada en artefactos).
  - Encabezado con carátula de *Random Access Memories*, título, artista *Daft Punk*, metadatos (*Album • 2013 • 13 songs • 1 hour, 14 minutes*), descripción del álbum y badge de 13 pistas.
  - Lista de pistas numeradas con título y duración exacta.
  - Botón interactivo *Volver a resultados*.
  - Indicador verde *Motor Side B conectado* sin rutas ni datos personales.

---

## 5. Archivos modificados o agregados en W04

- [`windows/src-tauri/src/lib.rs`](../../../../windows/src-tauri/src/lib.rs): Comandos `search_albums` y `get_album`, DTOs `AlbumCardDto` y `AlbumDetailDto`.
- [`windows/src/lib/types.ts`](../../../../windows/src/lib/types.ts): Interfaces TypeScript `AlbumCardDto` y `AlbumDetailDto`.
- [`windows/src/routes/+page.svelte`](../../../../windows/src/routes/+page.svelte): Pestañas Canciones/Álbumes, grilla de tarjetas de álbum, vista de detalle con pistas, botón Atrás y control de concurrencia.
- [`windows/README.md`](../../../../windows/README.md): Actualizado con las capacidades vigentes de W04 y límites del proyecto.
- [`windows/album_search_results.png`](../screenshots/album_search_results.png): Captura visual de la grilla de álbumes.
- [`windows/album_detail.png`](../screenshots/album_detail.png): Captura visual del detalle de álbum con pistas reales.
- [`documentation/handoffs/W04-result.md`](W04-result.md): Informe de entrega de W04.

---

## 6. Próximos pasos hacia el cierre de M2

- Implementar los flujos restantes del hito M2 según `PLAN-013`: comandos y vistas para página de inicio (`get_home_page`) y resolución de stream (`resolve_stream`).
- No se declara M2 completo hasta cumplir la totalidad de los paquetes correspondientes.
