> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W05 — Inicio con Secciones y Chips Reales en Windows (M2 parcial)

**Fecha:** 2026-09-29.  
**Estado:** Hecho. Implementada la página de Inicio con secciones y chips interactivos reales consumiendo `SideBCore::get_home_page` desde el backend Tauri 2 en Windows. DTOs tipados en Rust y TypeScript; interfaz Svelte 5 con barra de navegación principal (Inicio / Buscar), chips dinámicos de estado de ánimo y categorías, renderizado de secciones reales de YouTube Music con tarjetas interactivas e informativas, preservación íntegra de las búsquedas de canciones y álbumes (W03/W04). Encabezado higienizado sin textos técnicos ni badges de depuración, gestión de IDs de petición desacoplados por dominio (`homeRequestId`, `searchRequestId`, `albumRequestId`) y navegación rápida Inicio→Buscar→Inicio verificada sin bloqueos. `core/` y `apple/` intactos; M2 continúa abierto.

---

## 1. Alcance implementado y revisiones aplicadas

- **Contratos del core y comando IPC:**
  - En [`windows/src-tauri/src/lib.rs`](../../../../windows/src-tauri/src/lib.rs):
    - `get_home_page(chip_params: Option<String>) -> Result<HomePageDto, CommandError>`: consume directamente `state.core.get_home_page(params)`. Maneja parámetros opcionales y normaliza cadenas vacías a `None`.
    - Conservados íntegramente los comandos previos: `search_songs`, `search_albums`, `get_album`, `get_backend_status` y `retry_init_core`.
- **DTOs tipados (Rust & TypeScript):**
  - **Chips de Inicio:** `HomeChipDto` en Rust y [`windows/src/lib/types.ts`](../../../../windows/src/lib/types.ts): `title: String`, `params: String`.
  - **Ítems de sección:** `HomeItemDto`: `kind`, `id`, `title`, `subtitle`, `thumbnail`, `duration`, `artists`, `albumId`.
  - **Secciones:** `HomeSectionDto`: `title`, `format` (`"largeCards"` / `"compactSongs"` / `"mixed"`), `items: Vec<HomeItemDto>`.
  - **Página completa:** `HomePageDto`: `chips: Vec<HomeChipDto>`, `sections: Vec<HomeSectionDto>`.
  - Sin tokens de biblioteca, cookies, URLs firmadas ni campos de sesión privada.
  - **Manejo de errores:** Reutilización de `CommandError` con mensaje genérico seguro (`HOME_FAILED`) ante contingencias de red, sin registrar datos privados ni filtrar errores crudos `format!("{e}")`.
- **Interfaz Svelte 5 y correcciones de revisión temprana:**
  - En [`windows/src/routes/+page.svelte`](../../../../windows/src/routes/+page.svelte):
    - **Encabezado limpio para el usuario:** Se eliminaron la insignia técnica *"Windows W05"*, el texto *"consumiendo SideBCore"* del subtítulo (ahora *"Página de inicio y búsqueda nativa"*) y la píldora verde *"Motor Side B conectado"*. Si el backend entra en fallo o no está listo, se muestra la barra de advertencia con el botón interactivo de reconexión.
    - **Desacoplamiento de IDs de petición por dominio:** Se reemplazó el ID global compartido por contadores independientes: `homeRequestId`, `searchRequestId` y `albumRequestId`. Cada bloque `finally` apaga su propio indicador (`isHomeLoading`, `isSearchLoading`, `isAlbumLoading`) si coincide con la última petición emitida en su dominio, evitando que peticiones concurrentes dejen vistas bloqueadas.
    - **Navegación fluida no bloqueante:** Las pestañas principales *Inicio* y *Buscar* permanecen accesibles en todo momento sin deshabilitarse. Se probó la secuencia rápida Inicio→Buscar→Inicio durante la carga en vuelo, comprobando que Inicio resuelve y renderiza su contenido normalmente sin quedar trabado en el spinner.
    - **Fila de chips dinámicos:** Muestra los filtros provistos por YouTube Music (*"Todos"*, *"Energize"*, *"Feel good"*, *"Relax"*, *"Workout"*, *"Commute"*, etc.). Al hacer clic, recarga el feed con `chip.params` y bloquea los chips durante la carga.
    - **Secciones reales:** Renderiza carátulas y títulos reales. Las tarjetas de tipo álbum abren su detalle real mediante el flujo W04; los elementos sin navegación implementada se muestran como tarjetas puramente informativas, sin botones falsos de reproducción.
    - **Navegación y botón Atrás:** El detalle de álbum reconoce si provino de Inicio o de Buscar y regresa al origen correspondiente (*"Volver a Inicio"* o *"Volver a resultados"*).
- **Límites estrictos respetados:**
  - No se modificó ningún archivo en `core/` ni en `apple/`.
  - No se añadió audio, login, resolución de streams ni paginación continua simulada.
  - No se declara M2 completo; W05 cubre la compuerta de la página de inicio.

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
| Empaquetado frontend | `corepack pnpm build` (en `windows/`) | **Código 0 en 3.92s.** Artefactos estáticos generados en `windows/build/`. |
| Chequeo Rust MSVC | `cargo check` (en `windows/src-tauri/`) | **Código 0 en 5.13s.** Crate `sideb-windows` validado con `get_home_page`. |
| Compilación nativa | `cargo build` (en `windows/src-tauri/`) | **Código 0 en 1m 54s.** Binario `sideb-windows.exe` generado y enlazado con `sideb-core`. |
| Verificación encabezado limpio | Inspección DOM vía CDP | Badge ausente, subtítulo sin mención a SideBCore, barra verde oculta en estado saludable (`hasBadge: false, hasStatusBar: false`). |
| Navegación rápida durante carga | Secuencia Inicio→Buscar→Inicio | `isHomeLoading` resuelto limpiamente sin bloqueos (`isSpinnerPresent: false, sectionCount: 3`). |
| Carga de Inicio y filtros | Clic en chips (*"Energize"*, *"Feel good"*) | Secciones especializadas cargadas de YouTube Music (*"Power boost"*, *"Fun throwbacks"*). |
| Búsquedas conservadas | Búsqueda canciones y álbumes | **20 canciones** y **20 álbumes** para *"Daft Punk"*. Detalle de álbum con 13 pistas verificado. |
| Captura visual Inicio | CDP `Page.captureScreenshot` | Captura limpia guardada en `windows/home_feed.png` (262 KB) sin detalles técnicos ni datos privados. |

---

## 4. Evidencia visual

- **Captura histórica W03:** [`windows/search_results.png`](../screenshots/search_results.png) (búsqueda de canciones).
- **Capturas históricas W04:** [`windows/album_search_results.png`](../screenshots/album_search_results.png) (búsqueda de álbumes) y [`windows/album_detail.png`](../screenshots/album_detail.png) (detalle de pistas).
- **Captura W05 actualizada - Inicio con encabezado limpio:** [`windows/home_feed.png`](../screenshots/home_feed.png) (respaldada en artefactos):
  - Encabezado depurado para usuario final: Logo, título *Side B*, subtítulo *Página de inicio y búsqueda nativa*. Sin badges técnicos ni indicadores verdes de diagnóstico.
  - Pestañas *Inicio* (activa en rojo) y *Buscar*.
  - Fila interactiva de chips de estado de ánimo (*Todos*, *Energize*, *Feel good*, *Workout*, *Relax*, *Party*, *Romance*, *Commute*, *Focus*, *Sad*, *Sleep*).
  - Sección real del feed (*"Fun throwbacks"*) con carátulas remotas.
  - Cero rutas del sistema de archivos o datos privados expuestos.

---

## 5. Archivos modificados o agregados en W05

- [`windows/src-tauri/src/lib.rs`](../../../../windows/src-tauri/src/lib.rs): Comando `get_home_page`, DTOs `HomeChipDto`, `HomeItemDto`, `HomeSectionDto`, `HomePageDto`.
- [`windows/src/lib/types.ts`](../../../../windows/src/lib/types.ts): Interfaces TypeScript equivalentes para el feed de inicio.
- [`windows/src/routes/+page.svelte`](../../../../windows/src/routes/+page.svelte): Navegación Inicio / Buscar, chips dinámicos, renderizado de feed, IDs desacoplados (`homeRequestId`, `searchRequestId`, `albumRequestId`) y encabezado limpio.
- [`windows/README.md`](../../../../windows/README.md): Actualizado con las capacidades vigentes de W05 y límites del proyecto.
- [`windows/home_feed.png`](../screenshots/home_feed.png): Captura visual limpia de la página de inicio en la ventana nativa.
- [`documentation/handoffs/W05-result.md`](W05-result.md): Informe de entrega de W05 con las correcciones aplicadas.

---

## 6. Próximos pasos hacia el cierre de M2

- Implementar la resolución de stream (`resolve_stream`) según `PLAN-013` para completar la totalidad de las compuertas de datos reales de M2 antes de abordar la capa de audio nativa (M3).
- No se declara M2 completo hasta cumplir la totalidad de los paquetes correspondientes.
