# PLAN-023 — Paridad Mac → Windows para Side B 1.4.0

- Fecha: 2026-11-08 (America/Montevideo).
- Estado: implementado en fuentes e integrado 2026-11-09; verify/build/QA en PC pendientes. Línea base verificada: `windows/` svelte-check 0 errores/1 warning previo; `node --test scripts/*.test.mjs` 522 tests, 520 aprobadas, 2 omitidas, 0 fallos; catálogo 871 claves sincronizado (se eliminaron 3 claves `lyrics.source.*` duplicadas de `windows.json` y se regeneró `catalog.json`).
- Objetivo: llevar a Windows el **estado final actual de macOS** (no su historia) para publicar 1.4.0 con ambas apps equivalentes, incluido el reproductor lateral y Spotify Canvas preinstalado y retirable.
- Decisiones del usuario (2026-11-08): versión **1.4.0**; todo el reproductor lateral entra; Spotify Canvas viaja **instalado de fábrica en Mac y Windows**, como plugin separable (si hay problemas con Spotify se borra el plugin y la app sigue igual); el trabajo se escribe aquí en macOS; los bugs ya corregidos en Mac **no deben reaparecer**: se porta la versión final, no los pasos intermedios.
- Referencias: [PARIDAD](../../PARIDAD.md) PAR-045…053, [PLAN-031 Apple](../../apple/plans/PLAN-031-now-playing-sidebar.md), [PLAN-034 Apple](../../apple/plans/PLAN-034-home-continuous-cards.md), [PLAN-022 general](../../plans/PLAN-022-optional-visual-providers.md), [extensions/README](../../extensions/README.md).

## Qué ya está en Windows (no se rehace)

PAR-045 (cola continua, reinserción, preferencia de recomendaciones) y PAR-047 (LyricsPlus + selector por canción) existen en fuentes; sólo requieren verificación nativa en la PC.

## Regla de oro del port

1. Leer el **código Swift vigente** y su plan Apple; replicar comportamiento, medidas y estados finales. Consultar `FIXES.md` sólo para conocer trampas ya resueltas (buscar por nombre de archivo/componente) y no reintroducirlas; no portar pasos intermedios ni experimentos descartados.
2. Mac es **solo lectura** para los agentes Windows, excepto el agente W7 (autorizado por el usuario para Mac + `extensions/` + CI).
3. La cola nativa es autoritativa (no duplicarla en TS); preservar `entryId`, `generation`, EOF. Credenciales nunca en DTO/logs. Invalidar al cambiar de cuenta. Estados vacío/carga/error.
4. Textos: reutilizar claves compartidas existentes de `apple/Localization/fragments/*.json` (ya en `catalog.json`: `playback-sidebar`, `settings-categories`, `search-video-preferences`, `visual-providers`, `queue-recommendations`, `lyrics-sources`); claves nuevas propias de Windows van a `src/lib/i18n/windows.json` con prefijo `windows.`, añadidas con una edición pequeña anclada (varios agentes editan ese archivo). Regenerar con `node scripts/sync-localizations.mjs` (idempotente); **nunca editar `catalog.json` a mano**.
5. No hay `pnpm`: usar `node --test scripts/*.test.mjs` y `node_modules/.bin/svelte-check --tsconfig ./tsconfig.json` (tras `node_modules/.bin/svelte-kit sync`) desde `windows/`. Rust nativo Windows (`src-tauri`) no compila en Mac: validar con `rustfmt --check`/parseo y tests de lógica que no dependan de Windows; declarar el límite. Core: `cargo test --locked --manifest-path core/Cargo.toml -p innertube -p sideb-core` sí corre en Mac.
6. **No usar worktrees** (el árbol tiene 150+ archivos sin commitear que un worktree no contiene). Todos escriben en el mismo árbol: respetar la propiedad de archivos de abajo; ante un archivo compartido, releer justo antes de editar y usar ediciones pequeñas ancladas.
7. **No ejecutar git commit/push/tag ni builds numeradas ni publicar.** No tocar `FIXES.md`, `PARIDAD.md`, `plans/README.md`, `windows/plans/README.md`, `version.env`: los consolida el integrador.
8. Cierre de cada agente: escribir su borrador de entrada FIX en `windows/plans/PLAN-023-drafts/Wn.md` (problema/causa, cambio y motivo, componente, archivos, pruebas ejecutadas con cifras reales, límites/QA pendiente, paridad) y devolver un reporte con: archivos tocados, comandos ejecutados con resultado, lo no verificado, y dudas. No afirmar FPS/audio/WebView2 por fixtures.

## Archivos compartidos y propietarios

| Archivo | Propietario | Los demás |
|---|---|---|
| `windows/src/routes/+page.svelte` | W3 (composición del lateral) | W1/W2 sólo lo tocan si es imprescindible, con edición mínima anclada |
| `windows/src/lib/components/home/HomeSettings.svelte` y `components/settings/*` (excepto los 3 stubs) | W8 | — |
| `components/settings/SearchVideoSettings.svelte` | W2 | stub ya creado; W8 lo importa tal cual |
| `components/settings/SidebarLyricsSettings.svelte` | W4 | idem |
| `components/settings/VisualProviderSettings.svelte` (+ login) | W6 | idem |
| `components/playback-sidebar/PlaybackSidebar.svelte` | W3 | stub ya creado |
| `playback-sidebar/{SidebarArtwork,SidebarTrackMetadata,SidebarUpcomingQueue,SidebarLyricsPreview}.svelte` | W4 | stubs ya creados; W3 los compone |
| `playback-sidebar/{SidebarRecommendations,SidebarArtistShelf}.svelte` | W5 | idem |
| `components/player/PlayerBar.svelte` | W3 | — |
| `components/fullscreen/*` (Lyrics/Queue/AnimatedArtwork/Recommended) | W4 en `AnimatedArtwork.svelte` y `LyricsPanel` sólo si el preview lo exige; W3 en `FullscreenNowPlaying.svelte` | W5 reutiliza `Recommended*` sin modificarlos salvo extraer helpers acordados en su reporte |
| `components/home/*` (salvo HomeSettings), `lib/featured`, `lib/horizontal`, `lib/home` | W1 | — |
| `lib/search/*`, `components/search/*`, `components/detail/ArtistDetailView.svelte` | W2 | — |
| `src-tauri/src/lib.rs` (registro de comandos), `dto.rs`, `lib/types.ts` | compartido | edición mínima anclada; relear antes |
| `src-tauri/src/commands/animated_artwork.rs` | W4 (+W6 para el fallback) | coordinar vía reporte |
| `src-tauri/src/visual_provider/**`, `commands/visual_provider.rs`, `lib/visualProvider/**` | W6 | — |
| `extensions/**`, `Scripts/**`, `.github/workflows/**`, `apple/**` (sólo host/bundle de proveedores), `windows/src-tauri/tauri.conf.json` (recursos/bundle) | W7 | W6 no toca tauri.conf; pide recursos a W7 en su reporte |

## Contratos entre agentes

- **Componentes del lateral** reciben las convenciones de `FullscreenNowPlaying`: `session: number`, `playback: PlaybackStateDto` y callbacks que cada dueño declare en su `Props`. W3 compone **al final** leyendo el `Props` real de cada archivo; si un archivo sigue siendo el stub, lo omite y lo informa.
- **Preferencias nuevas** (mismo patrón que `queuePreferences.ts`: localStorage con fallback seguro, clave `sideb.<area>.<nombre>.v1`): `lib/search/searchPreferences.ts` (W2, `showVideos`, default true), `lib/player/sidebarPreferences.ts` (W4, `lyricsPreview`, default según Mac). W8 no define preferencias: sólo importa los componentes de sección.
- **Proveedor visual**: W7 define el paquete (`manifest.json` + `sideb-spotify-canvas.exe`), el layout de instalación preinstalada y el protocolo JSON/stdio v1 sin cambios incompatibles; W6 implementa el host Windows sobre ese contrato. Política (Mac y Windows): Apple primero; la alternativa Spotify **solo en el lateral vertical**; fullscreen no la consulta; desactivado hasta que el usuario inicia sesión/activa; quitar el plugin no afecta nada más.

## Partes (ola única, paralelas)

### W1 — Inicio (PAR-051)
Replicar Inicio apilado con dos rieles continuos (Speed Dial hasta 27 canciones, filas, ancho 156–202; álbumes/playlists en una fila con portada cuadrada redondeada, título/creador/detalle debajo, sin marco ni pie teñido; encabezados «Ver todo ›»; alto de texto fijo y hueco inferior), flechas/fades sólo donde hay contenido fuera de vista, hoja «Ver todo», metadata por viewport con ancla por ID, tarjetas de tamaño fijo al redimensionar, y espacio correcto cuando el lateral está abierto (el lateral lo aporta W3: exponer una variable CSS/prop `sidebarOpen` en `HomeView`). Fuentes Mac: `Views/Home/HomeFeaturedView.swift`, `HomeFeaturedNativeRail.swift`, `HomeFeedCollectionView.swift`, `HomeView.swift`, `apple/plans/PLAN-034`. Pruebas: tests node de presentación + fixture Chrome si hay patrón existente.

### W2 — Búsqueda y artista (PAR-048, PAR-049)
(a) Preferencia «Mostrar videos en búsquedas» (default activado): filtra tarjetas/payloads de video en resultados mixtos y sugerencias, también historial remoto de sugerencias; conserva originales y continuaciones; reactivar los devuelve; remapea roles/payloads por ocurrencia; no afecta Inicio, biblioteca ni cola. Fuentes: `Models/SearchPreferences.swift`, `ViewModels/SearchViewModel.swift`, `Views/Search/ProviderSearchPageView.swift`, tests `SearchVideoPreferencesTests`. Entregar `SearchVideoSettings.svelte` real. (b) Perfil de artista: reciclado de filas/tarjetas y propiedad del scroll horizontal (wheel ordinario no navega historial dentro de carruseles; Alt explícito), según `Views/Detail/ArtistDetailView.swift`, `ArtistProfileViewport.swift`, PLAN-033. Reutilizar `VirtualStack`/viewports existentes.

### W3 — Lateral: carcasa y transición (PAR-046, parte 1)
Panel flotante derecho (ancho ideal 380, rango 350–420, radio 16, padding 20, separación exterior 6; reserva de ancho del contenido o superposición si no cabe), selector Letras / Ahora suena / Cola con foco y Escape, reproductor fijo abajo (progreso, transporte, volumen/mute; **salida de audio propia de Windows**, sin AirPlay), transición reversible barra↔panel (spring ~380 ms, sin timers encadenados, Reduce Motion = fundido), botón exterior flotante circular de sidebar (esquina inferior derecha) y atajos de la barra que abren fullscreen (cola/letras) sin abrir el lateral, coordinación fullscreen↔lateral (volver al origen), respeto del titlebar/botonera Windows, y componer los componentes de W4/W5 al final. Fuentes: `Views/PlaybackSidebar/PlaybackSidebarScene.swift`, `Views/Components/PlaybackBarShell.swift`, `PlayerBarView.swift`, `FullscreenNowPlayingView.swift`, PLAN-031. Dueño de `PlaybackSidebar.svelte`, `PlayerBar.svelte`, `+page.svelte` (cambios del lateral).

### W4 — Lateral: contenido A (PAR-046 parte 2, PAR-052)
`SidebarArtwork` (portada protagonista con adopción **tall**: pedir `prefer_tall` al comando de carátula animada; fallback cuadrado; video suspendido por política de scroll/idle y no desmontado en scroll breve; paleta de fondo armónica con gradiente vertical, saturación/calidez preservadas), `SidebarTrackMetadata` (título/créditos con enlaces, Like/Dislike/+cola/menú, metadata anclada), `SidebarUpcomingQueue` (próximas dos), `SidebarLyricsPreview` (muestra de letras sincronizadas con el **renderer real** de karaoke, tipografía/estilo Side B, botón «Mostrar más», abre Letras completas, sin salto), `sidebarPreferences.ts` + `SidebarLyricsSettings.svelte`. Cambios de comando/DTO de carátula animada en Tauri (`commands/animated_artwork.rs`) son suyos. Fuentes: `NowPlayingSidebarArtwork.swift`, `SidebarArtworkScrollCoordinator.swift`, `SidebarTrackMetadata.swift`, `SidebarUpcomingQueue.swift`, `SidebarLyricsPreview.swift`, `PlaybackPresentation.swift`, `Services/.../AnimatedArtwork*`.

### W5 — Lateral: recomendaciones (PAR-046 parte 3)
`SidebarRecommendations` y `SidebarArtistShelf`: recomendaciones legibles con desenfoque de carátula, acciones ordenadas dislike · like · +, clics correctos en filas, visibilidad/reciclado de celdas, estantes de artista diferidos (tope diez) activados al montar recomendaciones, reutilizando datos/comandos de Relacionado (`recommendations.rs`, `RecommendedPanel`). Fuentes: `NativeSidebarRecommendationsView.swift`, `NativeSidebarArtistShelf.swift`, `NowPlayingSidebarRecommendations.swift`. Sin duplicar la cola nativa.

### W6 — Proveedor visual en Windows (PAR-050, host + UI)
Host Tauri/Rust genérico equivalente al de Mac: protocolo JSON/stdio v1 (un proceso por solicitud, stdin ≤32 KiB, stdout ≤16 KiB, plazo 22 s, kill al cancelar, sin secretos en argv/env/logs, carpeta privada por solicitud, validación del MP4: H.264 vertical 720–1920 px de alto, 2,5–8,5 s, ≤60,1 fps, ≤24 MiB, limpieza por PID huérfano), credencial del token **protegida con DPAPI** como `session_store.rs`, ventana de login Spotify (WebView2) una sola vez y **renovación autónoma del Bearer** (equivalente a `VisualProviderTokenSource/Extractor`: tres estrategias, ignorar anónimos, descartar rechazado, backoff 20 s–30 min, preventiva >50 min), enrutado Apple primero/Spotify solo lateral, y `VisualProviderSettings.svelte` real (instalar/activar/reconectar/desinstalar; con preinstalación de W7, «desinstalar» borra el plugin). Fuentes: `Services/VisualProviders/*.swift`, `Views/Home/VisualProvider*.swift`, `extensions/README.md`, PLAN-022. Coordina con W4 (carátula) sólo por reporte.

### W7 — Empaquetado de Spotify Canvas, Mac y Windows, CI (PAR-050, distribución)
Autorizado a tocar Mac. (1) Que `extensions/spotify-canvas` compile y se pruebe para macOS arm64 **y** Windows x64 (`.exe`, rutas, manifiesto multiplataforma, tests/clippy/fmt; cross-check con `cargo check --target x86_64-pc-windows-msvc` si el toolchain lo permite, si no declarar el límite). (2) Preinstalación: la app Mac incluye el proveedor en `Contents/Resources` y el host lo instala/ubica al primer arranque **sin activarlo** (activar exige login/token); desinstalar lo borra de verdad y no se reinstala solo (marcar decisión del usuario persistente). Idéntico en Windows vía `tauri.conf.json` resources e instalador/zip portable. (3) Scripts/CI: `Scripts/build-macos.sh`/`build-version.mjs` y workflows `macos.yml`/`windows.yml`/`release.yml` construyen y empaquetan el proveedor; checksums. (4) Documentar en `extensions/README.md` y `THIRD_PARTY_NOTICES`. No toca el host Windows (W6) ni UI. Pruebas Swift existentes de proveedor deben seguir pasando (`swift test --package-path apple --filter VisualProvider`).

### W8 — Configuración (PAR-053)
Rediseñar `HomeSettings.svelte` al estilo del modal Mac final: panel hasta 1240×860 (mín. 780×520) según ventana, barra lateral con secciones Aplicación / Contenido / Cuenta, iconos monocromos de contorno, búsqueda en la barra, listas agrupadas con separadores, interruptores en lugar de casillas, títulos grandes, Inicio en dos columnas cuando hay ancho, todos los atajos en la categoría Atajos, siete categorías de `SettingsCategory`. Debe incluir **todas** las opciones vigentes: Cola (selección de recomendaciones), letras (fuente), videos en búsqueda (importa `SearchVideoSettings`), muestra de letras del lateral (`SidebarLyricsSettings`), proveedores visuales (`VisualProviderSettings`), idioma, actualización, cuenta, caché, etc. Sin cambios de lógica ni preferencias existentes. Fuentes: `Views/Settings/SettingsModalView.swift`, `Views/Home/HomeSettingsPanel.swift`, fragmento `settings-categories.json`. Los tres componentes de sección ya existen como stubs: importarlos por ruta.

## Integrador (yo), tras las 8 partes

- Reconciliar `+page.svelte`, `lib.rs`, `dto.rs`, `types.ts`, `windows.json`; regenerar y verificar catálogo.
- `svelte-check`, suite node completa, `cargo test` del core, `swift test` filtrado/total de Mac si W7 tocó Mac, `rustfmt --check` de `src-tauri`.
- Consolidar borradores en `FIXES.md` (IDs desde FIX-302; Windows `[Windows]`, empaquetado `[Compartido]`); resolver IDs duplicados 285/286/287 sin romper referencias; actualizar PARIDAD (PAR-046/048/049/050/051/052/053 a «Implementado / validación pendiente») y los índices de planes.
- Versión **1.4.0**: `version.env`, `tauri.conf.json`, notas `release-notes/1.4.0.md`, `plans/RELEASE-1.4.0.md`, README (funciones, Spotify opcional), `release.yml` default tag; build number según contador.
- No commit/push/tag/release sin pedido explícito.

## Pendiente en la PC Windows (no cerrable desde Mac)

`windows/scripts/windows.ps1 -Action verify` (frontend, core con/sin `windows-bridge`, player, Tauri: toda la Rust de `queue.rs`/`playback.rs`/host de proveedores se compila por primera vez ahí), build x64, instalación/actualización real, audio, libmpv, WebView2 (login/renovación de Spotify, scroll, transiciones), QA humana de lateral/Inicio/Configuración. Ese resultado cierra la paridad; hasta entonces las filas quedan «Implementado / validación pendiente».

## Cierre

- [x] W1 Inicio (FIX-302) · [x] W2 Búsqueda/artista (FIX-303) · [x] W3 Lateral carcasa (FIX-304) · [x] W4 Lateral contenido A + ruteo del proveedor (FIX-305) · [x] W5 Lateral recomendaciones (FIX-306) · [x] W6 Host Windows proveedor (FIX-307) · [x] W7 Empaquetado/CI/Mac preinstalado (FIX-308) · [x] W8 Configuración (FIX-309)
- [x] Integración + suites (2026-11-09: svelte-check 0 errores/1 warning previo; 608 pruebas, 605 aprobadas, 3 omitidas, 0 fallos; 871 claves) · [x] FIXES/PARIDAD/índices (duplicados 285/286/287 de proveedor renumerados a FIX-310/311/312) · [x] Versión 1.4.0/build 22 y notas ([RELEASE-1.4.0](../../plans/RELEASE-1.4.0.md)) · [ ] Verify/build/QA en PC
