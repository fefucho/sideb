# PLAN-022 — Barra de reproducción: ancho útil y título desplazable en Windows

- Fecha: 2026-10-27 (America/Montevideo).
- Estado: implementación frontend y fixture Edge sintética verificadas; QA nativo WebView2/Narrator pendiente.
- Objetivo: aprovechar el espacio a la derecha de la información musical, destacar Like y apilar dislike sobre ⋯ y permitir leer el título largo con desplazamiento automático y pausa bajo el mouse.
- Plan espejo y contrato común: [Apple PLAN-030](../../apple/plans/PLAN-030-player-bar-space-marquee.md#contrato-común-con-windows). Seguimiento: [PAR-044](../../PARIDAD.md).
- Alcance: barra inferior Svelte y presentación optativa de su título; sin cambios Rust/Tauri/core, cola, audio o fullscreen completo.

## Hallazgos y antecedentes

1. La captura del usuario muestra metadata truncada mientras queda una banda libre entre ⋯ y Letras. `PlayerBar.svelte:384` declara `208px minmax(0, 1fr) 16px 232px` y tres gaps de 14 px. Los cinco controles derechos actuales ocupan 192 px (5×32 + 4×8), alineados al extremo de una columna de 232 px: quedan 40 px internos sin usar. A ello se suman la columna de 16 px y los gaps entre track/spacer/controles. El presupuesto sobrante no llega al texto.
2. En compacto, las reservas cambian a 168/0/176 y gaps de 6 px. El plan debe cubrir también esa rama, no sólo arreglar la captura a ancho máximo.
3. Like está en `.title-line`, consumiendo ancho del título; ⋯ es un hermano horizontal de `.metadata`, consumiendo ancho de ambas líneas. Se pueden sustituir esos dos lugares por una única columna de acciones.
4. `.title` y `FeaturedTrackTitle.svelte .title-parts` usan ellipsis y overflow hidden. No se encontró implementación de marquee en la ruta vigente Windows. Se necesita añadirla; no hay evidencia suficiente para afirmar qué versión Windows la perdió.
5. Mac conserva `ScrollingTrackTitle`, pero dejó de usarlo con una canción activa al integrar `FeaturedTrackTitle` en `63b896b`; [FIX-167](../../FIXES.md#fix-167) documenta los invitados enlazados. El arreglo debe conservar esa capacidad también en Svelte.
6. [FIX-038](../../FIXES.md#fix-038), [FIX-039](../../FIXES.md#fix-039) y [FIX-059](../../FIXES.md#fix-059) explican la distribución Apple anterior y la estabilidad del volumen overlay. El seguimiento de compactación está en PAR-016-2. Son antecedentes, no validaciones nuevas de esta propuesta.

## Resultado común requerido

Transporte → separación existente → portada → título y artista • álbum flexibles → Like destacado junto a dislike encima de ⋯ → hueco fijo invisible → Letras/Genius/cola/volumen/fullscreen.

Aplicar el contrato completo del [plan Mac](../../apple/plans/PLAN-030-player-bar-space-marquee.md#contrato-común-con-windows), con px como unidades de interfaz Windows:

- Cápsula 74 px / máximo 820 px. Controles derechos al ancho real de su contenido; metadata recibe el resto.
- Hueco invisible de17px antes de Letras; retirar también el trazo antes de portada, conservando sus márgenes y controles anclados.
- Like32×44/icon25 a la izquierda de columna dislike/⋯24×46: blancos24×22/gap2; gap4 entre corazón y columna, conjunto60. Acciones a10px del máximo ancho natural de título o artista/álbum, limitado por espacio real. El transporte y grupo derecho quedan anclados.
- Título y artista/álbum comparten ancho máximo disponible. Segunda línea permanece estática y conserva navegación.
- Título largo: medición real, espera1s, velocidad24px/s con mínimo3,5s por recorrido, pausa final1,3s y reinicio. Hover/foco/menú congelan en el offset visible y permiten continuar; no resetean al entrar.
- Pista/texto/ancho nuevos reinician medición; progreso de audio y Like no. Texto corto, Reduce Motion y superficie oculta/segundo plano no mantienen movimiento activo.
- Conservar invitados enlazados y una sola representación accesible. La revisión de E de [PLAN-021](PLAN-021-explicit-content-indicators.md) sigue pendiente por separado; admitir su futura ubicación secundaria sin introducirla incidentalmente.

## Implementación prevista

- [ ] Medir baseline del componente real a 620/700/760/820 px de barra, con sidebar expandida/compacta y escalado de Windows 100/125/150/200%; distinguir ancho CSS de píxeles físicos.
- [x] Reorganizar `src/lib/components/player/PlayerBar.svelte`: tres zonas de transporte/track flexible/controles intrínsecos, eliminando `control-spacer` y reserva232. Añadir columna de acciones y separador de ancho fijo. Revisar también `@container (max-width:760px)`.
- [x] Revisar volumen overlay y su ancho: conservar su huella fija, capas, foco, hit testing e inert de accesos tapados; abrir volumen no debe quitar ancho al texto.
- [x] Añadir modo optativo sólo para la barra en `src/lib/components/FeaturedTrackTitle.svelte`; conservar valores predeterminados de otros consumidores. Reutilizar sus enlaces y resolución/prefetch, sin convertir el título en texto plano.
- [x] Medir viewport y ancho intrínseco del contenido mediante ResizeObserver; esperar fuentes listas y repetir por texto, resize o cambios reales de contenido resuelto. Desactivar ellipsis en las capas internas únicamente en este modo para poder leer todo el título.
- [x] Animar el único contenedor de texto con Web Animations/CSS compositor, sin actualizar estado Svelte por frame. Conservar currentTime en pause/play y las pausas del ciclo. Limpiar observers/listeners/animación al desmontar; suspender por document.visibilityState y foco de ventana.
- [x] Mantener viewport recortado y enlaces moviéndose junto a su dibujo; un enlace fuera del viewport no debe interceptar clics ni quedar inaccesible al enfocarlo. Pausar/revelar el enlace enfocado sin scroll global del shell.
- [x] Añadir fixture real y regresiones observables en `windows/scripts/player-bar-layout.test.mjs` y `player-bar-title-motion.test.mjs`, con helper/harness existente cuando sirva. Revisar `featured-consumers.test.mjs`, `controls.test.mjs`, `volume-scroll.test.mjs` e `integration-review.test.mjs` sin reemplazar pruebas por búsquedas triviales de CSS.

## Verificación y cierre

- [ ] Datos sintéticos sin cuenta: título corto y muy largo, feat/ft enlazado, acentos/emoji, artista/álbum largos/vacíos, carga/error/reintentar y estados Like.
- [x] Asegurar geometría: no hay banda elástica tras ⋯; el separador queda a distancia fija de Letras; texto llega hasta la columna de acciones; Like arriba y ⋯ abajo con centros horizontales coincidentes y hitboxes separadas.
- [x] Demostrar desplazamiento en el tiempo y lectura hasta el final; hover intermedio mantiene offset por al menos2s y salida continúa. Repetir foco, menú de invitado, resize a mitad de ciclo, cambio rápido de pista y metadata tardía del mismo ID. Progreso periódico de audio no reinicia animación.
- [x] Texto corto sin movimiento; Reduce Motion con tooltip/texto accesible completo; segundo plano/ocultación sin animaciones ni callbacks continuos. No usar copias duplicadas enfocables.
- [ ] Probar enlaces de invitados/artista/álbum, menú contextual y ⋯, Like/errores, transporte, scrubber, volumen por rueda/drag/Escape y accesos Letras/Genius/cola/fullscreen, ES/EN y teclado.
- [x] Ejecutar `pnpm check`, `pnpm test`, `pnpm build` desde windows y verificar layout/ciclo en Edge con componente real.0errores/1warning previo,498pruebas aprobadas y build frontend aprobado; QA WebView2/Narrator/DPI permanece pendiente por separado.
- [x] Entrega compilada por pedido posterior: runner oficial `node Scripts/build-version.mjs windows` conservó build0023 Release, estado compiled/fuentes estables y cuatro hashes revalidados. Verify1084pruebas aprobadas/20live ignoradas/0fallos. Ruta: `builds/windows/build-0023/sideb-windows.exe`, con DLL/licencia/BUILD.json/build.log. App no abierta; QA WebView2/audio pendiente. Build0022 anterior conservada.
- [x] Revisar diff y registrar [FIX-264](../../FIXES.md#fix-264), ambos planes y PAR-044 con pruebas/límites por destino. Mac mantiene compilación/QA pendientes; no se cierra paridad por resultados de Windows.

## Evidencia de FIX-264 y límites nativos

Se implementaron las tres zonas de ancho intrínseco/flexible, columna de acciones24×46 y separador17px, conservando insignia secundaria, créditos, callbacks y overlay de volumen. `FeaturedTrackTitle` activa el desplazamiento únicamente mediante `scrollTitle` en la barra; la acción `player/title-motion.ts` mide viewport/contenido y usa Web Animations sin estado ni callbacks por frame. Pausa/reanuda tiempo real por hover, foco, menú/búsqueda de invitado, foco de ventana, visibilidad de documento e intersección. El menú de invitado opta por portal fuera del clip y recibe foco de teclado; Escape vuelve al crédito. Motores sin las APIs de medida/animación conservan título estático.

Fixture real: `node scripts/player-bar-browser.mjs`, sin cuenta ni audio. Comprueba16 geometrías (620/700/760/820 CSS px × DPR1/1,25/1,5/2), altura74, columna24, blancos22, gap2 y separación17 antes de Letras. Comprueba pausa hover2100ms, reanudación desde offset visible, identidad tras progreso/Like, foco/revelado local de crédito, enlace/menú, final/retorno del ciclo, resize, segundo plano e intersección, volumen overlay/Escape, texto corto y Reduce Motion. El factor DPR de Edge simula píxeles físicos; no certifica escalado/DPI real de Windows ni geometría del shell con sidebar.

Evidencia local excluida de Git: `windows/.cache/player-bar-browser/results.json`, captura `player-bar.png` y captura nativa recortada de820px `player-bar-820.png`. Regresiones automáticas en `player-bar-title-motion.test.mjs` y runner de navegador `player-bar-layout.test.mjs` (omite sólo si no hay Edge/SIDEB_BROWSER). `pnpm check` aprobado con0errores/1advertencia preexistente de selector `.metadata-line p` de MediaCard; `pnpm test`:498aprobadas/0fallos/0omitidas, incluida la fixture Edge real; `pnpm build` frontend aprobado. Log completo local en `windows/.cache/player-bar-full-tests.log`. El primer pase detectó falta de APIs de layout en la fixture antigua de volumen; se resolvió conservando fallback estático para motores sin APIs y el segundo pase completo pasó.

Pendientes: QA nativo WebView2/Narrator, sidebar real, DPI/contraste de sistema, interacciones de cuenta real y audio. No se compiló EXE, no se modificó Rust/core ni se hicieron commits. Resultados Windows no validan Mac.


## Revisión FIX-265 — 2026-10-28

Implementación frontend completada: corazón32×44/icon25 más dislike/⋯24×22/gap2, conjunto60. `.metadata` adopta ancho natural máximo de ambas líneas y se contrae ante textos largos; conserva marquee/pausa y acciones a10px. Se reutiliza `account.dislike` con videoId/entryId capturados, eliminación en recomendaciones, filtrado nativo y remoción de la ocurrencia concreta sólo si sesión sigue vigente. Fallos no quitan la ocurrencia y errores tardíos no se publican en otra sesión.

Ambos trazos antes de portada y Letras se retiran, conservando márgenes invisibles. Portada inferior y TrackArtwork/cola comparten `--sideb-track-artwork-radius:2px`. HorizontalNavigation deja de dibujar gradientes laterales rectangulares; conserva círculos, hit testing, paginado, RTL y foco. FullscreenNowPlaying opta por `ArtistCredits showContentRating={false}`: canción activa sin E en título ni créditos; barra, cola y Relacionado mantienen sus indicadores.

Comprobaciones propias de esta revisión (distintas de FIX-264): `pnpm check`0errores/1advertencia previa MediaCard;16pruebas focales dislike/marquee/navegación/créditos aprobadas;17pruebas controles/volumen/invitados aprobadas. Fixture content-rating Edge12casos aprobados, cuatro alternancias fullscreen conservando identidad/badges restantes; fixture navegación Edge26casos aprobados con scroll/clic real, RTL, máscaras ausentes y sin bandas/blur. Primeros intentos Edge perdieron pipe por compat-layer relaunch; flags de harness conservan proceso y plazo de montaje ampliado a45s para grafo Vite frío, sin reducir assertions. Fixture player Edge16geometrías aprobadas (620/700/760/820×DPR1/1,25/1,5/2), sin errores:60px/32×44/24×22/gap2, gap10 con metadata corta dominada por artista o título, controles anclados y sin movimiento ante ticks, ambos huecos invisibles, radio2; ciclo/pausahover2100ms/foco/enlace/portal/resize/volumen/Reduce Motion conservados. Evidencia y capturas renovadas en `windows/.cache/player-bar-browser/{results.json,player-bar.png,player-bar-820.png}`.

El integrador ejecutó `node Scripts/build-version.mjs windows`: build0024 Release compiled, sourceChangedDuringBuild:false y cuatro SHA256 revalidados. Verify1089pruebas aprobadas (503frontend/112InnerTube/175core/177bridge/5player/117Tauri),0fallos/20live ignoradas; check0errores/1warning CSS previo. Conservada en `builds/windows/build-0024/sideb-windows.exe` con DLL/licencia/BUILD.json/build.log; anteriores intactas. App sin abrir. [FIX-265](../../FIXES.md#fix-265)/PAR-044 registrados. Persisten QA WebView2/Narrator, DPI físico/sidebar, cuenta real y audio; fixtures sintéticas no certifican Mac ni FPS.
