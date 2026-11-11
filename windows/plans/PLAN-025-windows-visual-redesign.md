# PLAN-025 — Rediseño visual de Windows: shell y acabado estilo macOS / Apple Music

- Fecha: 2026-11-10 (America/Montevideo).
- Estado: **en curso**. El 2026-11-10 el usuario aprobó el plan y pidió D1 y D4 como opciones de Configuración: implementadas en FIX-324 y FIX-325, validación nativa pendiente. D2 rechazada (botones de ventana sin cambios). D5 probada con un prototipo; recomendación de no adoptar, decisión pendiente. D3 y D6 sin respuesta. Etapas 1, 3 y 4 sin empezar.
- Objetivo: que la app Windows se vea más cuidada y más cercana a la app Mac (y al lenguaje de Apple Music): shell flotante de vidrio, materiales coherentes, geometría única, scrollbars discretas y movimiento, **sin cambiar funciones**.
- Alcance: `windows/src/` (estilos, shell y componentes de presentación), `windows/src-tauri/tauri.conf.json` sólo en la etapa 5, pruebas/fixtures Windows y registros. Apple se consulta como referencia, no se edita. Sin cambios de `core/`, cola, controllers, DTOs, audio ni proveedor.
- Base inspeccionada: `main` `d0b5549` con cambios locales de PLAN-010/023 sin commit, que se conservan.
- Referencias: [AUDIT-002](AUDIT-002-ui-parity.md) (UI-025/027/028), [PLAN-011](PLAN-011-button-polish.md), [PLAN-015](PLAN-015-sidebar-hidden-topnav.md), [PLAN-020](PLAN-020-horizontal-scroll-controls.md), [PLAN-022](PLAN-022-player-bar-space-marquee.md); PAR-007, PAR-008, PAR-017-2, PAR-030, PAR-036 en [PARIDAD](../../PARIDAD.md); capturas Mac en [docs/screenshots](../../docs/screenshots/).

## 1. Diagnóstico

Comparación de código y de capturas: Mac en `docs/screenshots/`, Windows en fixtures de Edge (`windows/.cache/plan016-browser/home.png`, `search-1440-closed.png`, `plan010-browser/final.png`). Los fixtures son navegador con datos sintéticos, no WebView2 nativo; no se abrió ninguna build para este plan.

**El contenido ya está cerca; lo que delata a Windows es el marco y el acabado.** La barra de reproducción (74/820/radio 38), la cabecera de colección (arte 216, título 38), la fila activa (6.5 %/9 %) y los colores base ya coinciden con Mac. Las diferencias que más pesan, en orden de impacto visual:

| # | Diferencia | Windows hoy | Mac (referencia) |
|---|---|---|---|
| 1 | Sidebar | Columna plana a sangre, `#24242a` sólido, 253 px, línea interior ([Sidebar.svelte](../src/lib/components/sidebar/Sidebar.svelte)). El ambiente de Inicio/detalle empieza en `left: var(--sidebar-width)`: corte vertical duro | Panel flotante: inset 6, radio 10, borde 0.5 blanco 10 %, sombra 0.18/12/y4, vidrio sobre el ambiente ([ShellLayout.swift](../../apple/Sources/SideB/UI/ShellLayout.swift), [SidebarView.swift](../../apple/Sources/SideB/Views/Sidebar/SidebarView.swift)) |
| 2 | Scrollbars | Clásicas con flechas en la columna de contenido y en la lista de la sidebar; no hay estilo global, sólo `scrollbar-width: thin` en algunos contenedores (que en Chromium/Windows conserva las flechas) | Superpuestas, sin flechas, aparecen al desplazar |
| 3 | Barra superior | Atrás/Adelante de 32 px sin superficie, pegados a los botones de ventana ([TitleBar.svelte](../src/lib/components/shell/TitleBar.svelte)) | Cápsulas de vidrio de 42: búsqueda 42, historial 76, separación 10 |
| 4 | Geometría | 27 valores distintos de `border-radius` en 46 archivos y ~140 colores hex sueltos. Arte de cartas 10/12, hero 10 | `AppTheme`: miniatura 2, carta 5, hero 8; panel 10 |
| 5 | Materiales | Un solo acrílico (`--sideb-acrylic-*`) para barra y controles. Menú contextual, popover de cuenta, avisos y diálogos son sólidos (`#29292f`, `#303036`, `#303038`, `#24242a`) con radios 9/10/12 | Vidrio/material en todo lo flotante, con fallback opaco |
| 6 | Movimiento | ~20 duraciones distintas sin curva común; cambio de página y de ancho de sidebar sin transición | Transiciones reversibles y consistentes |
| 7 | Filas de pista | Like y ⋯ ocultos hasta hover (`opacity:0` en [TrackList.svelte](../src/lib/components/common/TrackList.svelte)); título 14 | Like y ⋯ siempre visibles; sólo Play y asa dependen de hover; título 15.5 ([NativeCollectionTrackCellView.swift](../../apple/Sources/SideB/Views/Common/NativeCollectionTrackCellView.swift)) |

Dato de ventana: `tauri.conf.json` usa `decorations: false` sin `shadow` explícito; en Tauri 2 `shadow` vale `true` por defecto y en Windows 11 da esquinas redondeadas y borde de 1 px a ventanas sin decoración. No se comprobó en una ventana real: se verifica en la etapa 2, no se asume.

## 2. Dirección de diseño

1. **Mac es la referencia de forma; Windows conserva sus convenciones de sistema.** Medidas y proporciones salen del código Swift vigente, no de capturas viejas ni del blueprint histórico.
2. **Vidrio en el marco, no en el contenido.** Material sólo en sidebar, barra superior, reproductor, menús, popovers y diálogos. Listas y cartas siguen sobre fondo opaco para no perder legibilidad ni rendimiento.
3. **Una sola tabla de tokens.** Cada etapa migra a tokens los archivos que toca; no hay barrido masivo de 46 archivos en un solo cambio.
4. **Nada de assets de Apple.** Inter se queda (SF Pro no es redistribuible, PAR-025); iconos SVG propios, sin SF Symbols ni iconografía de Apple Music.
5. **Accesibilidad no negociable:** `prefers-reduced-transparency`, `prefers-reduced-motion` y `forced-colors` ya están cubiertos en [controls.css](../src/lib/styles/controls.css); cada superficie nueva hereda esos fallbacks.

## 3. Decisiones pendientes del usuario

| ID | Decisión | Recomendación | Motivo |
|---|---|---|---|
| D1 | Sidebar como panel flotante de vidrio, con el ambiente continuando detrás | **Sí** | Es el cambio que más acerca a Mac. Conserva expandida/compacta. Toca el alcance que PAR-008 dejó excluido (fondo detrás de sidebar): requiere reabrirlo expresamente |
| D2 | Botones de ventana | **Windows a la derecha, restilizados** | Semáforo a la izquierda rompe el hábito de Windows y la zona de arrastre/maximizar; se puede lograr el aire Mac sin eso |
| D3 | Radios de arte | **Adoptar 2/5/8 de Mac** | Hoy 10/12 se ve más "web"; no se encontró en FIXES una decisión explícita a favor de 12 |
| D4 | PLAN-015 (sidebar oculta + topnav) | **Integrarlo como etapa 2b** | Comparte las cápsulas de vidrio de la etapa 2; hacerlo aparte duplicaría el trabajo de la barra superior |
| D5 | Material nativo Mica (Windows 11) | **Prototipo medido al final, opcional** | Da translucidez real de escritorio, pero tiene riesgos de rendimiento y de nitidez de texto |
| D6 | Like y ⋯ siempre visibles en filas de detalle | **Sí, como Mac** | Menos "saltos" al pasar el mouse; coincide con la referencia |

Sin decisión, D2 y D5 quedan como están hoy; D1, D3, D4 y D6 bloquean sus etapas.

**Respuesta del usuario, 2026-11-10** («me gusta, ¿te animás a poner D1 y D4 como opcionales en configuración? … D2 no, D5 podés mandar un subagente a hacer un test a ver cómo quedaría simple»):

| ID | Resultado |
|---|---|
| D1 | Aprobada **como opción**: «Estilo de la barra lateral» Sólida (default) / Flotante de vidrio. [FIX-324](../../FIXES.md#fix-324) |
| D2 | **No.** Los botones de ventana quedan como están; no se restilizan |
| D3 | Sin respuesta; pendiente |
| D4 | Aprobada **como opción**: «Al contraer la barra lateral» Mostrar sólo iconos (default) / Ocultar completamente. [FIX-325](../../FIXES.md#fix-325), [PLAN-015](PLAN-015-sidebar-hidden-topnav.md) |
| D5 | Prototipo hecho (ver etapa 5); recomendación de no adoptar; decisión pendiente |
| D6 | Sin respuesta; pendiente |

Los valores por defecto de D1 y D4 conservan el aspecto anterior: elección del integrador para que «opcional» no cambie nada sin activarlo; es una línea si el usuario prefiere otro default.

## 4. Etapas

Cada etapa se entrega sola, con su FIX, su fixture y su build numerada si se pide. El orden va de menor a mayor riesgo.

### Etapa 0 — Línea base

- [ ] Resolver D1–D6.
- [ ] Fixture de shell completo (base: `scripts/plan016-browser.mjs`) con capturas de Inicio, álbum, playlist, búsqueda, Explorar, Biblioteca y fullscreen a 960×640, 1440×900 y 1920×1080, sidebar expandida/compacta. Guardarlas como "antes".
- [ ] Tabla lado a lado con las seis capturas Mac de `docs/screenshots/` para aceptar cada etapa contra la misma referencia.

### Etapa 1 — Fundaciones (riesgo bajo, visible en toda la app)

Archivos: [tokens.css](../src/lib/styles/tokens.css), [controls.css](../src/lib/styles/controls.css), estilos globales de [+page.svelte](../src/routes/+page.svelte).

- [ ] **Radios semánticos:** `thumb 2`, `card 5`, `hero 8`, `row 7`, `panel 10`, `popover 12`, `control 999`. Los tokens `--home-card-artwork-radius` y similares pasan a derivar de éstos.
- [ ] **Materiales en tres niveles**, cada uno con su fallback opaco: `chrome` (sidebar, barra superior), `floating` (reproductor, menús, popovers, flechas), `sheet` (diálogos). El acrílico actual pasa a ser `floating` sin cambiar su aspecto.
- [ ] **Texto y líneas:** escala primaria/secundaria/terciaria que reemplace los grises sueltos (`#aaaab1`, `#a6a6ad`, `#b6b6bf`, `#a4a4a8`…); una sola línea fina (1 px blanco 8–10 %).
- [ ] **Movimiento:** tres duraciones (120/200/320 ms) y dos curvas como tokens. Se mantiene la regla vigente: nunca animar `backdrop-filter`.
- [ ] **Scrollbars globales:** pulgar redondeado sin flechas ni pista, más visible en hover. Nota técnica: en Chromium las propiedades estándar `scrollbar-width/color` tienen prioridad sobre `::-webkit-scrollbar` y conservan las flechas, así que hay que quitar los `thin` sueltos donde se quiera el estilo nuevo. Confirmar comportamiento en WebView2 real.
- [ ] Prueba: test de tokens (existencia y consumo) y capturas "después" sin cambios de layout medibles (mismas cajas, distinto acabado).

### Etapa 2 — Shell estilo Mac (riesgo medio; depende de D1, D2)

Archivos: [Sidebar.svelte](../src/lib/components/sidebar/Sidebar.svelte), [TitleBar.svelte](../src/lib/components/shell/TitleBar.svelte), [HomeAmbient.svelte](../src/lib/components/home/HomeAmbient.svelte), [HomeBackground.svelte](../src/lib/components/home/HomeBackground.svelte), [+page.svelte](../src/routes/+page.svelte).

- [x] **Sidebar flotante** (opcional, FIX-324): panel con inset 6, radio 10, borde fino y sombra; tinte 72 % + blur acrílico existente (el material `chrome` como token queda para la etapa 1). La reserva `--sidebar-width` pasa a 265/72 px en este modo para que el interior conserve 253/60; sus consumidores no cambiaron.
- [x] **Ambiente detrás de la sidebar** (FIX-324): `--sidebar-bleed` extiende el fondo al borde izquierdo y las luces viven en un `.stage` con la caja anterior, así el foco de color no se mueve. Comprobado en fixture Edge, no en WebView2.
- [x] **Modo compacto:** mismo panel flotante en formato riel (FIX-324).
- [ ] Pendiente de D1: fullscreen del reproductor junto al panel flotante (posible corte, sin capturar), franja de 6 px que no arrastra la ventana, costo del blur a alto completo en WebView2.
- [ ] **Interior de la sidebar:** ya está cerca de Mac (fila 8 de radio, seleccionado 10 %/borde 10 %). Sólo ajustar a tokens y contrastar tamaños con `SidebarMetrics` usando Inter.
- [ ] **Barra superior:** cápsula de vidrio de 42 para Atrás/Adelante (76 de ancho en Mac), fuera de la franja de botones de ventana. Zonas de arrastre y los 138 px de botones de ventana intactos.
- [x] **Botones de ventana** según D2: el usuario respondió «D2 no»; quedan como están. FIX-325 sólo fija su alto en 32 px cuando la franja crece a 54.
- [ ] **Ventana:** verificar en Windows 11 real esquinas redondeadas, borde y sombra con `shadow` por defecto. Sólo cambiar config si la verificación lo pide.
- [x] **Etapa 2b (D4, opcional):** PLAN-015 implementado en FIX-325: búsqueda 42→298 anclada, destinos 246, historial 76, franja de 54 px. Contrato, estados y matriz pendiente siguen en ese plan. La cápsula de historial sólo existe en el modo oculto; en los demás modos la barra superior conserva las flechas actuales (punto anterior sin hacer).
- [ ] Prueba: fixture de shell en las cuatro combinaciones sidebar×ancho; hit-testing de botones de ventana y arrastre; foco y Tab sin elementos ocultos alcanzables; `sidebar-appearance` y `window-controller` en verde.

### Etapa 3 — Superficies de contenido (riesgo bajo-medio; depende de D3, D6)

- [ ] **Arte:** cartas 10/12 → 5, hero 10 → 8, compactas según su equivalente Mac; línea interior muy tenue para que las portadas oscuras no se fundan con el fondo ([MediaArtwork.svelte](../src/lib/components/common/MediaArtwork.svelte), [MediaCard.svelte](../src/lib/components/common/MediaCard.svelte), [CollectionHeader.svelte](../src/lib/components/detail/CollectionHeader.svelte)).
- [ ] **Hover de carta:** Play y ⋯ con material `floating` y transición común; misma política de abrir vs reproducir (PAR-009), sin tocar handlers.
- [ ] **Filas** (D6): Like y ⋯ visibles en reposo en detalle; Play y asa siguen en hover. Título 14 → 15 midiendo truncado con Inter. Selección, teclado, arrastre y `entryId` sin cambios.
- [ ] **Menús, popover de cuenta, avisos y tooltips:** material `floating`, radio `popover`, sombra única y entrada de 120 ms ([ContextMenu.svelte](../src/lib/components/menu/ContextMenu.svelte), popover en Sidebar, `.menu-notice`/`.shell-error`/`.gesture-progress` en +page).
- [ ] **Diálogos:** material `sheet`, scrim y radio comunes en editor/borrado de playlist, descripción, actualización y Configuración. Sólo presentación; el manejo de foco no se reescribe (UI-028 queda aparte).
- [ ] **Explorar:** comprobar si la scrollbar horizontal visible de la captura del 19/10 sigue existiendo tras FIX-261; si sigue, ocultarla y usar las flechas flotantes ya elegidas.
- [ ] Prueba: `track-list-dom`, `collection-header-dom`, `horizontal-navigation-dom`, `controls` y fixtures de contenido explícito sin regresiones; capturas a 100/150 % de escala.

### Etapa 4 — Movimiento (riesgo medio)

- [ ] **Cambio de página:** fundido corto con leve desplazamiento de la página entrante en [RetainedPage.svelte](../src/lib/components/shell/RetainedPage.svelte), sólo `opacity/transform`, sin remontar páginas retenidas ni perder scroll.
- [ ] **Sidebar expandir/contraer:** animar el panel sin provocar layout del contenido en cada frame; medir antes de elegir técnica.
- [ ] **Micro-interacciones:** presión en cartas y controles prominentes; entrada/salida de menús y diálogos.
- [ ] Todo desactivado bajo `prefers-reduced-motion`.
- [ ] Prueba: traza de rendimiento en Edge con Inicio poblado; sin tareas largas nuevas atribuibles a las transiciones. Esto no certifica FPS en WebView2: se mide aparte en la build.

### Etapa 5 — Material nativo Mica (opcional; depende de D5)

- [ ] Prototipo en rama: `transparent: true` + `windowEffects` con Mica en `tauri.conf.json` (Tauri 2.12 y `window-vibrancy` 0.8.1 ya están en el lockfile; confirmar la API en la documentación vigente antes de escribir). El panel `chrome` deja ver el material.
- [ ] Medir: fluidez al redimensionar y arrastrar, nitidez del texto sobre transparencia, estado al perder foco, Windows 10 (sin Mica → sólido).
- [ ] Si se aprueba: preferencia en Apariencia «Material de ventana: Automático / Sólido», por instalación, en `sideb.appearance.v1` como campo aditivo.
- [ ] Si no convence: se descarta sin afectar las etapas 1–4. Un prototipo rechazado queda registrado como investigación, no como fix.

**Prototipo del 2026-11-10 (investigación, no fix; pedido «un test a ver cómo quedaría simple»).** Subagente Sonnet 5.5, sin tocar archivos versionados: frontend ya compilado copiado a `windows/.cache/plan024-mica/dist/` con overrides CSS/JS externos (F8 alterna `solid`/`chrome`/`full`), parche `--config` (`transparent: true`, `windowEffects.effects: ["mica"]`, `identifier` propio `com.fefucho.sideb.windows.micaproto` para arrancar como invitado, `beforeBuildCommand` vacío) y `pnpm tauri build --no-bundle` release. No es build numerada. EXE en `windows/.cache/plan024-mica/app/sideb-mica-proto.exe`; capturas `solid.png`, `chrome.png`, `full.png`, `chrome-nofocus.png` en la misma carpeta.

- La ventana sin decoración arranca y dibuja con `transparent` + Mica. Que el material sea Mica y no simple transparencia se infiere de una medición de color (fondo gris neutro ~31–33 bajo el tinte, compatible con Mica oscuro `#202020`), no de un contraste visible.
- **Resultado visual: casi indistinguible del modo sólido.** Sidebar `chrome` (34,34,37) contra `solid` (36,36,42). Mica oscuro es un gris uniforme; no aporta color.
- **Efecto secundario observado:** en las tres variantes, incluida la de control sin overrides, la barra de reproducción aparece sin desenfoque (el contenido se ve nítido a través). No se comparó contra una build normal en el mismo estado de invitado, así que la causa (ventana transparente) es probable, no confirmada. Si se confirma, la ventana transparente rompería el acrílico de la barra y el vidrio de la sidebar flotante.
- Sin evaluar: franja superior (el ambiente la cubrió), esquinas/sombra (píxeles negros en la captura), fluidez al redimensionar/arrastrar, GPU, maximizada. `full` y `chrome-nofocus` no son comparables al 100 %: cambió el estado de la UI entre capturas.
- El parche reemplaza `app.windows[0]` entero y es anterior al `additionalBrowserArgs` que otro trabajo agregó a `tauri.conf.json`; el prototipo no lo incluye. `frontendDist` absoluto falla con rutas con espacios (`ERR_FILE_NOT_FOUND`); relativo funciona. El build pisó `release\sideb-windows.exe` de la caché mutable de D:.
- **Recomendación: no adoptar Mica.** La sidebar flotante (D1) ya da color real de las carátulas, que es lo que Mica no da, y Mica pone en riesgo el desenfoque. D5 queda pendiente de la decisión del usuario.

### Etapa 6 — Cierre por etapa

- [ ] `pnpm check`, `pnpm test`, `pnpm build` en `windows/`; `windows/scripts/windows.ps1 -Action verify` antes de cada build.
- [ ] Build numerada con `sideb-build-windows` cuando se pida, con ruta exacta en la entrega.
- [ ] Un FIX `[Windows]` por etapa entregada en [FIXES.md](../../FIXES.md).
- [ ] Paridad: PAR-017-2 (sistema visual), PAR-007 (barra superior), PAR-008 (fondo tras sidebar, si D1) y PAR-036 si cambia la sidebar. Mica es exclusivo de Windows: se explica en su fix, sin fila de port.
- [ ] Actualizar este plan y el índice.

## 5. Fuera de alcance

- Funciones, cola, controllers, core, Apple, proveedor, credenciales.
- Fullscreen, letras, karaoke y Genius: ya alineados por PLAN-008/013/016; sólo heredan tokens.
- Decisiones ya tomadas que **no** se reabren: jerarquía de botones de FIX-221, E negra de FIX-116-2, flechas flotantes de FIX-261, layout de barra de FIX-265, página de búsqueda de FIX-248.
- Virtualización de listas, helper de imágenes y helpers de modal (UI-007/026/028 de AUDIT-002): son trabajo estructural, no visual.

## 6. Riesgos

| Riesgo | Mitigación |
|---|---|
| `backdrop-filter` sobre una sidebar de alto completo cuesta más que sobre la barra | Medir en la etapa 2; si pesa, tinte translúcido sin blur sobre el ambiente (que ya es difuso) |
| Ambiente detrás del vidrio baja el contraste del texto de la sidebar | Tinte mínimo del material `chrome` y comprobación de contraste con las carátulas más claras |
| Cambiar radios y tamaños rompe fixtures con geometría fijada | Actualizar esas pruebas en el mismo cambio, justificando cada medida nueva; no relajarlas |
| Animar ancho de sidebar recalcula Home (canvas/virtualización) | Animar el panel, no la reserva; contenido salta al ancho final |
| Ventana transparente (etapa 5) degrada redimensionado o texto | Etapa aislada, opcional y reversible |
| Edge en fixture ≠ WebView2 | Cada etapa separa evidencia de navegador de aceptación nativa; no se cierra paridad sin la segunda |

## 7. Estado y enlaces

- Fixes: [FIX-324](../../FIXES.md#fix-324) (D1, sidebar flotante opcional) y [FIX-325](../../FIXES.md#fix-325) (D4, sidebar oculta + barra superior opcional). Paridad: PAR-007, PAR-008 y PAR-036.
- Builds: ninguna numerada. El prototipo Mica de `windows/.cache/plan024-mica/` no es una build entregable.
- Ejecución 2026-11-10: tres subagentes Sonnet 5.5 (esfuerzo medio) con encargo escrito y revisión del integrador. D1 y D5 en paralelo, D4 después de D1 por compartir archivos.
- Validación del conjunto (integrador): `pnpm check` 458 archivos 0/0, `pnpm test` 514 aprobadas/0 fallos, `pnpm build` correcto; capturas Edge en `windows/.cache/plan024-d1/` y `windows/.cache/plan024-d4/`. Sin `verify`, sin build y sin WebView2: la aceptación en la app queda pendiente.
