# PLAN-010 — Bugs Windows: buscador, Explorar, colecciones y streams

- Fecha: 2026-10-18 (America/Montevideo).
- Estado: implementación Windows realizada en FIX-216/217/218/219; fixture Edge y verify completo aprobados. Build-0015 Release compilada con776pruebas, fuentes estables y cuatro hashes revalidados. Pedido posterior «compila así pruebo» autoriza esta build; se entrega sin abrir ni reproducir audio. Prueba de la pista y aceptación visual a cargo del usuario, pendientes.
- Pedido inicial: detallar los bugs mostrados y comparar con macOS antes de corregirlos. Pedido posterior2026-10-18: ejecutar este plan con subagentes; tres encargos6.1Sol/medio integrados. El análisis inicial siguiente se conserva como referencia, con resultados actuales al final.
- Base consultada: `0ca3f64dd7398c850164a7069f1e84d0aa424972`, árbol limpio al comenzar. Código Windows1.2.4; la versión del proceso mostrado en las capturas no se puede certificar por las imágenes.
- Objetivo: corregir la presentación Windows conservando acciones y comportamiento, y recuperar la reproducción de las pistas afectadas a partir de una causa comprobada.
- Ámbito: `windows/src/`, integración Tauri `windows/src-tauri/` y sus pruebas. Apple/core se consultan como referencia; no se modifican por una necesidad exclusiva de Windows.
- Exclusiones: rediseño general, nuevo selector superior Mac, cambios de cuentas/cookies, cola propia en TypeScript, modificación de releases anteriores, commit/push/publicación automáticos. La prueba de cuenta/audio fue autorizada posteriormente y luego pospuesta por el usuario antes de ejecutarse.

## Evidencia y lectura de las capturas

Las referencias C1–C5 corresponden al orden de los cinco adjuntos del pedido. Los archivos originales están en el directorio temporal del usuario; no se copian ni incorporan a Git porque contienen datos de su biblioteca/cuenta. Los píxeles de captura no se equiparan a puntos Mac ni a píxeles CSS: faltan escala/DPI, tamaño cliente y confirmación de si hay recorte.

| Ref. | Qué se ve | Qué demuestra y qué falta |
|---|---|---|
| C1, `1519b5f6…png` | Spotlight abierto sobre Inicio; banda superior claramente más luminosa que el resto, incluida la franja sobre la sidebar. Diálogo, página y reproductor por debajo. | El oscurecimiento empieza debajo del borde de ventana. No es un hueco dentro de los resultados. Se puede contrastar directamente con el offset CSS. |
| C2, `a5e7dd4d…png` | Chips Descubrir/Lanzamientos/Rankings/Géneros/Momentos arriba; después «Explorar», eslogan y descripción; accesos rápidos y novedades. Scrollbar horizontal visible bajo el carrusel. | La jerarquía sigue la versión Windows anterior. La scrollbar del carrusel no demuestra por sí sola desborde global: el desplazamiento horizontal del carrusel es válido. Comprobar si se propaga al documento. |
| C3, `0d7d4ae8…png` | Liked Music con portada izquierda y datos derecha; Play/Aleatorio/puntos quedan bajo el texto, todavía a la derecha de la portada. Ordenar y Buscar caen en líneas posteriores. Un velo azulado/gris reduce el contraste del primer plano. Barra flotante sobre filas inferiores. | Confirma distribución distinta de Mac y poco espacio útil. El velo es compatible con superposición del ambiente, pero falta aislar capas en el runtime. La barra también flota en Mac: estar sobre filas durante scroll no es, por sí solo, el bug; comprobar recortes y acceso al final. |
| C4, `d899cf89…png` | Playlist Mac: portada y metadatos en una fila; Play/Shuffle/puntos debajo del conjunto, alineados con el borde izquierdo de la portada. Buscar/orden a la derecha de esa segunda fila. Fondo detrás del contenido y filas legibles. | Referencia de estructura y jerarquía, confirmada por Swift actual. Es una playlist distinta de C3 y una ventana diferente: no permite comparar colores ni tamaños absolutos uno a uno. |
| C5, `0dadb2ec…png` | Pista «One Dance (feat. …)», 0:00 y mensaje «No se pudo obtener el flujo d…», con control de reintento. | Acredita fallo de resolución presentado en Windows. No identifica el videoId/versión de la canción ni expone la causa del proveedor. No basta para atribuirlo a libmpv, Premium, cookies o una URL expirada. |

El usuario también reporta el velo y el layout en álbumes. No hay una captura independiente de álbum entre los cinco adjuntos: se incluye como escenario obligatorio por el reporte y porque comparte cabecera/ambiente, sin atribuirle una observación visual inexistente.

## 1. Buscador: franja superior fuera del oscurecimiento

**Confirmado en código:** [SpotlightSearch.svelte](../src/lib/components/search/SpotlightSearch.svelte) fija `.scrim` con `inset:40px 0 0`; `.positioner` también reserva40px. El shell usa `--titlebar-height:32px`; Inicio llega hasta el techo. El hueco de40px explica la banda de C1. No confundir cobertura del scrim con la reserva necesaria para colocar el diálogo.

**Cambio propuesto:** cubrir toda la superficie visual del cliente con el scrim; calcular la zona del diálogo por separado con las medidas del shell. Definir orden entre scrim, diálogo, controles nativos de ventana y menús sin dejar el historial/página operativos detrás del modal. Mantener cerrar/minimizar/restaurar utilizables según el contrato Windows y conservar Escape, clic exterior, foco y restauración del foco. No resolverlo sólo cambiando el40 por32: eso mantendría una banda sin oscurecer.

**Archivos previstos:** Spotlight, integración de `+page.svelte` y TitleBar sólo si la composición lo requiere. Antecedentes de búsqueda: FIX-165/168/169/172 y pruebas actuales de recents/preview/navegación; no atribuirles una regresión sin contrastar Git.

- [ ] Medir límites reales del scrim y de la barra con sidebar expandida/compacta, ventana normal/maximizada y escala100/125/150%.
- [x] Corregir cobertura y separar la zona útil del diálogo; viewport bajo nativo pendiente de QA.
- [x] Regresión Edge del borde superior y Escape/clic exterior/Tab/retorno de foco, sin navegación de fondo; no reemplaza WebView2 físico.

## 2. Explorar: port incompleto de la cabecera y orden de categorías

**Confirmado:** [ExploreView.svelte](../src/lib/components/explore/ExploreView.svelte) coloca `nav` antes y fuera de `.explore-scroll`; dentro conserva eyebrow, título «Algo nuevo para escuchar» de30px y descripción. En [ExploreView.swift](../../apple/Sources/SideB/Views/Explore/ExploreView.swift), `ExplorePageHeading` muestra «Explorar» localizado de40pt/caja52, sin eslogan/eyebrow/descripcion; `header` precede a `tabs` dentro del documento que se desplaza. Usa ancho completo y28pt laterales. Lanzamientos/categorías incluyen cabecera y tabs en su catálogo nativo. Es el contrato de [FIX-208](../../FIXES.md#fix-208)/[PLAN-022 Apple](../../apple/plans/PLAN-022-page-width-and-scrolling-headers.md), posterior a la integración Windows de FIX-133.

«Categorías abajo» se concreta como los chips de destinos debajo del título, dentro del scroll. Los bloques «Para cada momento» y géneros permanecen después de novedades, como en Swift; no moverlos arbitrariamente al pie. Los accesos Mac también incluyen icono, título y subtítulo, frente a los rectángulos de texto Windows; incluir esa diferencia en el port acotado de Explorar.

**Cambio propuesto:** trasladar jerarquía, anchura y espaciado de Mac con tokens Windows; mantener títulos reales de subrutas, navegación, refresh y estados de carga/error/vacío. Preservar Global+región/selector, posición por ruta y virtualización; comprobar que el carrusel siga desplazándose horizontalmente dentro de sus límites, con un solo viewport vertical efectivo.

**Archivos previstos:** ExploreView, VirtualCatalog si la geometría lo exige, estilos/localización sólo si falta alguna clave. Referencias: [PLAN-011 Apple](../../apple/plans/PLAN-011-explore.md), FIX-120/121/133/208, PAR-012. No trasladar AppKit ni el selector superior excluido de PAR-007.

- [x] Pasar título→chips→contenido al mismo documento vertical en todas las rutas; shell con altura explícita delega scroll a Explorar.
- [x] Retirar sólo textos propios obsoletos y usar la clave localizada existente de Explorar; conservar metadata del proveedor.
- [ ] Alinear márgenes/título/accesos con Mac y verificar Descubrir, Lanzamientos, Rankings, país, Géneros, Momentos y categoría concreta.
- [ ] Probar restauración de scroll/ruta, refresh, error y cambio de cuenta sin respuestas tardías ni desborde global.

## 3. Colecciones: ambiente y velo sobre el primer plano

**Observado/reportado:** velo en C3 y reporte en playlist/álbum. **Hipótesis pendiente de reproducción:** orden de pintado/stacking entre el ambiente y el contenido. En `+page.svelte`, [HomeAmbient](../src/lib/components/home/HomeAmbient.svelte) es hermano del shell, `position:fixed;z-index:0`, y contiene `.shade`. `.content-column` no establece una capa de primer plano explícita; playlist y álbum tampoco tienen exactamente la misma estructura de posicionamiento: `.album-page` es `position:relative`, playlist no. No se afirma aún qué subcapa produce todo el efecto ni que ambas rutas fallen por idéntica razón.

Mac aloja [CollectionWindowBackground](../../apple/Sources/SideB/Views/Detail/CollectionWindowBackground.swift) detrás del shell y [CollectionAmbientBackground](../../apple/Sources/SideB/Views/Detail/CollectionAmbientBackground.swift) detrás del contenido. FIX-114/115/116/117/118 y el port Windows FIX-132/139 ya establecen ambiente ligado a header/scroll, continuidad superior, fade y ausencia de hit testing. FIX-139 quitó un fondo opaco del álbum: no reintroducirlo para ocultar este síntoma.

**Cambio propuesto:** primero reproducir con portadas/fondo de referencia; alternar luces/humo/shade y examinar stacking/composición en WebView2. Luego dar propietario y orden explícitos a fondo decorativo, contenido, player, TitleBar y modales. Mantener ambiente detrás de texto/portada/filas, cobertura superior, fade a140px bajo el header, movimiento/reducción de movimiento y suspensión por fullscreen/inactividad/viewport. No aclarar textos ni reducir globalmente opacidades para tapar una capa colocada delante.

**Archivos previstos:** HomeAmbient y shell; detalle de álbum/playlist sólo si corresponde al contrato de primer plano. PAR-011 y [PLAN-010 Apple](../../apple/plans/PLAN-010-collection-detail-ui.md).

- [x] Fixture con CSS vigente del shell y ambos detalles reales; píxeles del primer plano de playlist comprobados al desactivar sólo la decoración. Sidebar/dock de referencia; no fixture de la lógica completa de +page.
- [x] Implementar ambiente detrás del flujo normal dentro de shell aislado; scroll/resize en fixture aprobados. Carátula tardía, cuenta y fullscreen nativos pendientes.
- [ ] Comparar fondo y primer plano a geometría equivalente; conservar contraste del contenido y evitar fondos opacos nuevos.

## 4. Álbumes/playlists: botones debajo de la portada

**Confirmado:** [CollectionHeader.svelte](../src/lib/components/detail/CollectionHeader.svelte) renderiza `.toolbar` dentro de `.metadata`, por lo que acciones y filtros están confinados a la columna derecha. Lo comparten `DetailHeader`/AlbumDetail y PlaylistDetail. La referencia Swift [CollectionDetailHeaderView](../../apple/Sources/SideB/Views/Detail/CollectionDetailHeaderView.swift) pone `toolbar` después de la fila portada+datos, dentro de un VStack común; coincide con C4.

**Cambio propuesto:** separar cabecera en fila portada+metadatos y toolbar inferior de ancho completo: Play/Aleatorio/Guardar/puntos a la izquierda bajo la portada; Buscar y Ordenar a la derecha. Mantener las capacidades por tipo: álbum sin ordenar ni columna de álbum; playlists con orden y permisos existentes, LM sin acciones inválidas. El toolbar debe poder pasar de fila a disposición compacta/varias filas cuando el ancho útil lo exija. El buscador conserva su nodo/foco/query durante filtrado y cambios de tamaño.

**Archivos previstos:** CollectionHeader, TrackFilter y adaptadores de álbum/playlist si deben pasar capacidades. No duplicar header ni rehacer controllers/cola. Referencias FIX-114/115/117/118/132/139, PAR-011.

- [x] Extraer toolbar de metadata conservando snippets, eventos, menús, guardar, descripción y créditos enlazados.
- [ ] Comparar álbum, playlist propia, ajena, LM, título largo, portada ausente y catálogo paginado.
- [ ] Comprobar reproducción desde ocurrencia filtrada, orden de fuente completa, duplicados, shuffle, drag permitido y permisos de edición; conservar proyección existente.

## 5. Ventana pequeña: adaptación por ancho disponible

**Evidencia:** C3 muestra toolbar partida y muy poco aire en los datos. Hay causas de fragilidad confirmadas, pero no una medición de la ventana capturada: media queries de CollectionHeader usan el ancho de toda la ventana a680/480, no el ancho útil tras sidebar; portada fija216, gaps/paddings y tools con base380 compiten en la columna derecha. La configuración Tauri declara mínimo960×640; no asumir que C3 es una ventana de732px CSS ni bajar ese mínimo sin una necesidad comprobada.

La barra ya usa container queries y reduce medidas bajo760; se revisa su comportamiento real antes de cambiarla. TrackList usa tabla fija y columnas de índice/álbum/duración/acciones que también necesitan presupuestos al reducir el contenido. La flotación sobre canciones es deliberada en ambas plataformas; el cierre exige que la última fila pueda desplazarse por encima de la barra.

**Cambio propuesto:** basar decisiones de la cabecera, filtros y filas en el contenedor disponible; cubrir sidebar expandida/compacta y escalado. Seguir la degradación de Mac: portada+datos se apilan cuando no caben (`ViewThatFits`); toolbar primero compacta acciones y luego pasa a varias filas. Establecer prioridades de metadatos/columnas sin perder acciones o destinos. No arreglar por `overflow:hidden` que esconda controles ni por elevar el mínimo de ventana.

**Matriz:** cliente960×640,1100×720 y1440×900; sidebar230/60; escala100/125/150%; ES/EN y títulos largos. Confirmar tamaño lógico real tras DPI. Fixture adicional de contenedores de480/600/730px para fronteras, sin afirmar que todos son tamaños de ventana permitidos. Altura baja, normal/maximizada y abrir/cerrar buscador/menús incluidos.

- [ ] Medir rectángulos de portada/metadatos/toolbar/filtro/tabla/player y distinguir wrap válido de intersección/recorte.
- [x] Implementar adaptación del contenedor; límites Edge y acciones/foco DOM aprobados. Ratón/teclado nativos pendientes.
- [ ] Verificar un solo scroll vertical de detalle; sin scroll horizontal global, sin controles fuera de ventana y última fila accesible sobre player.
- [ ] Probar player y panel de volumen en el ancho mínimo, conservando progreso, metadatos y todos los comandos; modificar sólo si se reproduce fallo.

## 6. Algunas pistas no reproducen: diferencia real con el fix Mac

**Confirmado en lectura:** el mensaje de C5 sale de [commands/playback.rs](../src-tauri/src/commands/playback.rs) al fallar `core.resolve_stream`; esa rama usa `Err(_)` y descarta el detalle del error. Ocurre antes de cargar esa URL en libmpv, por lo que esta captura no acredita un fallo de decodificación de mpv.

Antecedente especialmente relevante: [FIX-083](../../FIXES.md#fix-083), ID original de Feel No Ways. Ciertos temas sólo traían `signatureCipher` en WEB_REMIX y fallaban los clientes alternativos; Mac lo resolvió registrando `NativeCipherJsRuntime` mediante `setCipherJsRuntime`. **Diferencia vigente confirmada:** `SideBApp.swift` registra ese runtime; Windows crea `SideBCore::new_windows` en arranque y reinicialización, sin llamada a `set_cipher_js_runtime` ni implementación Windows de `CipherJsRuntime`. `new_windows` sólo delega en `build(...,false)`; el cipher nace sin runtime y `ensure_runtime` devuelve «cipher runtime unavailable». BotGuard/PoToken usa otro runtime y no equivale a registrar el callback de cipher.

Esto explica una clase concreta de fallos cuando no hay URL directa/alternativa válida; es una hipótesis fuerte para C5, todavía sin videoId ni error técnico de esa pista. FIX-007/077/134 son antecedentes de headers/fallback, selección/cancelación y sesión; no aplicar sus soluciones a ciegas ni cambiar a otra grabación por título.

**Primer paso de implementación:** obtener el enlace/videoId exacto de una pista afectada y una de control; reproducir con diagnóstico acotado y sanitizado que distinga runtime/cipher, disponibilidad/autenticación, red/validación y error de carga. No guardar cookies, headers privados ni URLs firmadas; conservar mensaje comprensible al usuario. Prueba de cuenta/red/audio real se coordina al empezar esa fase, no se ejecuta en este análisis.

**Si se confirma la ruta cipher:** implementar en la integración Windows el contrato `CipherJsRuntime` ya existente y registrarlo antes del primer resolve tanto al iniciar como al reintentar inicialización. Elegir un motor/contexto JS aislado tras evaluar dependencias existentes, serialización/afinidad de hilos, límites y empaquetado. No evaluar player.js en el WebView de la UI ni darle IPC/Tauri, credenciales, filesystem o red del host. No asumir que compartir aislamientos con BotGuard es válido. Usar el setter actual sin cambiar core por esta carencia exclusiva Windows; si aparece un defecto compartido distinto, documentar evidencia de ambas plataformas antes de proponer tocar core.

- [ ] Confirmar identidad exacta, etapa y causa del fallo; no sustituir canción ni marcar fijo por recibir sólo un URL.
- [x] Fixtures sin cuenta del callback: carga/firma/n, errores, contexto reemplazado y concurrencia; comprobación estructural de registro inicio/retry. La cadena completa del proveedor sigue pendiente y no se acredita con estos fixtures.
- [x] Conservar `generation`, `loaded_generation`, `auth_generation`, cola nativa, headers, isUpload y descarte de resultados tardíos; cambios de runtime y categoría diagnóstica sin nuevos reintentos.
- [ ] Verificar pista afectada y control en build Windows con progreso y audio audible; documentar disponibilidad/cuenta/región sin publicar datos sensibles. Prueba Mac nueva sólo si hay host disponible; FIX-083 histórico no sustituye evidencia actual.

## Orden de trabajo y cierre

1. Reproducción dirigida del audio para confirmar la causa de mayor impacto y elegir la integración; diagnóstico primero, sin cambiar proveedor a ciegas.
2. Corregir la cobertura del buscador como cambio aislado.
3. Portar la cabecera/scroll de Explorar desde el contrato Mac actual.
4. Corregir orden del ambiente, después estructura de CollectionHeader y adaptación estrecha; separar esos diffs para verificar qué arregla cada síntoma.
5. Completar integración de audio confirmada y ejecutar su verificación nativa. Validación final de la matriz visual y regresiones de reproducción.

- [x] Inspeccionar C1–C5 y separar lo visible del reporte y las hipótesis.
- [x] Contrastar código actual de ambas apps y antecedentes relevantes de FIXES/PARIDAD/Git.
- [x] Escribir este plan y enlazarlo en el índice, sin corregir código.
- [x] Empezar implementación por pedido posterior del usuario.
- [x] Diff revisado y FIX-216/217/218/219 registrados con regresiones y límites; PAR-011/012 actualizadas, PAR-033 para cipher. Apple sin modificar ni QA física cerrada.
- [x] Frontend:387pruebas aprobadas,check0/0,build frontend aprobado y fixture visual Edge con componentes reales. No acredita WebView2 nativo ni audio.
- [x] Runtime: `windows/scripts/windows.ps1 -Action verify` en Windows aprobado dentro del protocolo de build;776pruebas,14live Rust ignoradas. Incluye callback y suite Tauri.
- [ ] Prueba audible de pista exacta/control y aceptación nativa por el usuario.
- [x] Build local con skill Windows y `Scripts/build-version.mjs`:build-0015,Release,compiled,fuentes estables y cuatro hashes revalidados; no equivale a apariencia correcta ni audio audible.
- [ ] Comparar capturas antes/después con misma geometría, portada y estado; confirmar cobertura superior, orden título/chips, primer plano sin velo y controles sin recortes. Repetir wheel en portada/barra para conservar FIX-213/214.
- [x] Entregar avance de código, comprobaciones y límites; plan actualizado. Cierre funcional pendiente de verify/build/prueba real. Commit/push/release sólo mediante pedido específico posterior.

## Implementación y evidencia — 2026-10-18

| Frente | Resultado actual | Pendiente |
|---|---|---|
| Spotlight / FIX-216 | Scrim desde techo, diálogo separado, sólo controles de ventana por encima; Edge verifica hit testing, Tab, Escape, clic exterior y retorno de foco | WebView2 normal/maximizado, DPI real, altura baja y comandos nativos de ventana |
| Explorar / FIX-217 | Título40/52→chips→contenido, accesos con icono/subtítulo, viewport acotado; tres escenarios DOM internos recorren siete rutas y catálogo5000 reciclado | Conexión regional, input físico, FPS; restore y cambio de cuenta completos con runtime |
| Colecciones / FIX-218 | Toolbar hermana de identidad, container queries/filtro flexible. Ambiente z−1 dentro de app-frame aislado; velo de playlist reproducido con orden anterior y portada corregida idéntica al ocultar decoración | Aceptación nativa con portada real; confirmar reporte de álbum sin extrapolar la causa de playlist; carátula tardía/fullscreen/cuenta |
| Streams / FIX-219 | QuickJS ya transitivo, worker propio sin host APIs, límites/interrupt y contexto reemplazado. Fábrica común registra callback inicio/retry; diagnósticos de categorías finitas | player.js actual, cadena del proveedor, verify completo, build y reproducción exacta/control |

- Frontend: `pnpm check`0errores/0avisos, `pnpm test`387aprobadas/0fallos/0omitidas y `pnpm build` correcto. Las siete pruebas DOM internas nuevas se encapsulan en dos wrappers del total, no se suman otra vez.
- Nativo focal: `cargo test --offline --manifest-path windows/src-tauri/Cargo.toml --lib cipher_runtime::tests -- --nocapture`:10aprobadas,93filtradas. No equivale a verify completo. Rustfmt del runtime y `git diff --check` aprobados.
- Fixture optativa: desde `windows/`, `node scripts/plan010-browser.mjs`. Genera sólo contenido de prueba bajo `.cache/plan010-browser`, monta componentes reales y copia CSS vigente de +page; no incorpora ruta de producto. Edge155 headless aprobó144combinaciones(cliente960×640/1100×720/1440×900,sidebar230/60,ES/EN,DPR1/1.25/1.5),y fronteras de contenedor480/600/730; toolbar/controles/última fila y modal comprobados. DPR es densidad de raster emulada, no certifica escala de Windows ni normal/maximizado. Sidebar y dock son de referencia; no prueba el player real.
- Tabla editable: celda de acciones136px y grupo127px en fixture con cinco botones. El control de bordes realizado mide el grupo, no el extremo de cada botón; revisar esos rectángulos antes de descartar colisión con duración. No se cambió TrackList ni se ocultaron acciones sin reproducir el defecto.
- Pista exacta suministrada: `5LFB3qdmZBM`. Se observó la instalación previa con One Dance/0:00/error de stream. Se cerró normalmente para liberar el perfil antes de un futuro arranque; no se llegó a reproducir la pista ni a abrir un ejecutable nuevo. El usuario autorizó sesión/audio y luego pidió no usar la PC mientras juega y probar él después. No continuar interacción ni audio ahora. Fixture finalizada y sin procesos propios de navegador/diagnóstico activos al detener el uso de la PC.
- Build: no hay una nueva build standalone de este plan; no entregar build0014 ni la instalación1.2.4 como si contuvieran estos cambios. Aplicar skill Windows/`node Scripts/build-version.mjs windows` cuando el usuario retome pruebas y registrar ruta/estado/hashes. No se inició verify pesado para evitar competir con el juego.
- Paridad: PAR-011/012 conservan validación física pendiente; PAR-033 sigue el runtime del contrato FIX-083 sin certificar Mac por lectura estática. Sin cambios Apple/core, cuentas/cookies, versión pública, commit/push ni publicación.

El plan queda implementado parcialmente validado, con los pendientes anteriores explícitos; el fallo de la pista reportada no se declara resuelto por la sola instalación del callback.

## Build para prueba del usuario — 2026-10-18

- Pedido posterior: «compila así pruebo». Se retoma únicamente compilación/verificaciones, sin abrir la app ni probar la sesión/audio automáticamente.
- Comando: `node Scripts/build-version.mjs windows`; verify completo y build Release terminados correctamente.
- Ejecutable: `builds/windows/build-0015/sideb-windows.exe`. Conservar junto a `libmpv-2.dll`, `vulkan-1.dll` y `VulkanRT-License.txt`; versiones anteriores intactas.
- Procedencia: `builds/windows/build-0015/BUILD.json`, `status:compiled`, `sourceChangedDuringBuild:false`,base0ca3f64 con cambios locales del plan. Registro `build.log` en la misma carpeta. Esta actualización documental se escribe después del empaquetado; sin cambios funcionales posteriores.
- Verificaciones:776aprobadas(387frontend/97InnerTube/91core/93bridge/5player/103Tauri),14live Rust ignoradas,cero fallos; check0errores/0avisos,build frontend y nativo correctos. Conserva avisos de dead_code,LNK4098 y chunk grande, sin errores.
- Cuatro hashes de artefactos revalidados. EXE SHA256 `efae455c6d425d0dac18ea5be1c35ae2fa1b618c31f529f145a3e0742e3c1fca`.
- Pendiente: arranque/WebView2, apariencia física, bordes individuales de botones de tabla editable, rueda de volumen y reproducción de `5LFB3qdmZBM`/control con escucha. No se declara la pista reparada por compilar. Sin instalación, cambio de versión pública, commit/push ni publicación.

## Integración con GitHub — 2026-10-19

- Pedido posterior: guardar/subir el trabajo local y combinarlo con lo realizado desde macOS. Este pedido autoriza commit y push de código; la prueba física sigue pendiente.
- Objetivo: conservar FIX-216/217/218/219 e incorporar `origin/main` `ff36ce7`, con FIX-221/222/223 y versión 1.2.5. Los arreglos de volumen FIX-213/214/215 ya estaban compartidos desde la base `0ca3f64`.
- [x] Respaldar fuera del repositorio los veinte archivos locales, parche y hashes; conservar un commit local descriptivo antes de actualizar `main`.
- [x] Integrar ambas versiones: conservar todos los fixes/filas de paridad/planes, ambos módulos Tauri (sesión y cipher), y navegación de Explorar dentro del scroll con el icono SVG nuevo de refresh. Sin cambios en Apple, core ni versiones respecto de GitHub.
- [x] Frontend integrado: `pnpm check` sin errores/advertencias, 399 pruebas aprobadas y `pnpm build` aprobado, con el aviso existente de chunk grande.
- [x] Repetir `node scripts/plan010-browser.mjs`: 144 configuraciones de colecciones, fronteras de contenedor, scrim/foco y Explorar aprobados, sin excepciones. Evidencia ignorada en `.cache/plan010-browser/`; no equivale a aceptación humana ni a audio.
- [x] Completar `windows/scripts/windows.ps1 -Action verify`: 792 pruebas aprobadas (399 frontend, 97 InnerTube, 91 core, 93 bridge, 5 player, 107 Tauri); 14 live Rust ignoradas, sin fallos. Avisos existentes de dead_code, LNK4098 y chunk grande conservados.
- [x] Revisar diff final y preparar el commit descriptivo en `main` para el push autorizado, conservando los commits remotos. Los veinte archivos revisados sólo contienen fuentes/pruebas/planes Windows y registros FIXES/PARIDAD; respaldo, builds, cachés y datos de cuenta fuera del commit. Diff check aprobado y todos los FIX-216…219/221…223 conservados una vez.
- Límites: no hay build standalone nueva, instalación ni prueba de cuenta/audio en esta integración. Las builds anteriores y la release 1.2.5 conservan su procedencia; no contienen retroactivamente este trabajo local.
