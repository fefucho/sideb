# PLAN-019 — Queue continua y desplazamiento sólo vertical

- Fecha: 2026-10-31 (America/Montevideo).
- Estado: Continua integrada en fuentes Mac/Windows; proyección, geometría y viewport comprobados con fixtures. Build Mac0173 release compilada, firma y10hashes verificados, fuentes estables durante compilación. QA humana y Windows nativo pendientes.
- Objetivo: presentar la cola en dos bloques, reducir texto y eliminar desplazamiento horizontal sin alterar el contrato de reproducción de PLAN-018.
- Ámbito: presentación Mac/Windows, localización y pruebas de UI/proyección. Core, reserva/promoción, persistencia y resolución de audio conservan sus contratos.
- Antecedente funcional: [PLAN-018](PLAN-018-queue-recommendations.md). El usuario confirmó funcionamiento de la build Mac 0170 y luego eligió «Continua». Esa confirmación no certifica Windows, rendimiento ni todos los casos límite.
- Referencia visual: `../../output/queue-ui-options/queue-ui-options.html`, variante Continua, mostrada en esta conversación. Artefacto local de exploración, no dependencia del producto.

## Diseño decidido

Una única superficie de scroll vertical contiene:

1. **Now playing / Ahora suena:** cabecera única del bloque. Debajo, anteriores en orden, actual resaltada y pendientes de playlist/manuales según su orden autoritativo. No existe cabecera «Anteriores», plegador, cabecera «Up next» ni contador de pendientes vacío. La actual aparece una sola vez.
2. **Recommendations / Recomendaciones:** separador discreto y cabecera; propuestas de la reserva en el orden existente. Sin explicación permanente sobre cuándo se reproducen.

La cabecera contextual de playlist/álbum/radio existente se conserva una sola vez arriba del panel, con truncado. No repetir la semilla de radio junto a Recomendaciones si ya la informa esa cabecera. Conservar pestañas, transporte, artwork, tamaños de fila iniciales de 46 pt y enlaces a créditos.

- Anteriores: atenuar texto/carátula lo suficiente para distinguirlas, manteniendo legibilidad y acciones. No llamarlas «escuchadas» en accesibilidad: el prefijo puede incluir canciones saltadas o previas al índice inicial de una playlist.
- Actual: conservar resaltado e indicador de reproducción/pausa. La selección de teclado y la actual son estados distintos; no trasladar foco automáticamente al avanzar.
- Arrastre: todas las canciones comprometidas sirven como origen. Anteriores y actual se reinsertan como una ocurrencia manual nueva; pendientes se mueven conservando su ID. Sólo se admiten destinos entre pendientes y al final de la cola elegida; anteriores y actual no aceptan inserciones antes de sí mismas.
- Propuestas: misma celda, ancho y posiciones que las elegidas. En reposo se ve duración; al pasar el mouse o enfocar, el slot de las tres rayitas se convierte en «+» para agregar al final, con etiqueta accesible y tooltip. Sin botón/columna adicional. «Reproducir siguiente», reproducir ahora, quitar, Like/Dislike y demás acciones conservan su menú contextual y equivalentes de teclado. Mantener Like y el acceso vigente a Dislike; no eliminar funcionalidad para ganar ancho. No agregar puntos redundantes a cada fila sólo por copiarlos del boceto.
- Radio sin pendientes elegidas: anteriores/actual seguidas directamente por Recomendaciones. No mostrar «0», «No hay canciones agregadas» ni una fila vacía de drop. Mantener drop al final mediante el límite tras la actual/última pendiente y un indicador temporal sólo durante arrastre.
- Reserva vacía e inactiva: omitir cabecera y explicación vacías. Si hay carga, error, agotamiento confirmado o bloqueo por repetir, mostrar un único estado pertinente junto a Recomendaciones; conservar reintento y accesibilidad. Eliminar texto rutinario no significa ocultar errores.
- Paginación de playlist: indicador contextual de colección distinto del de reserva. Conservar acceso progresivo a canciones aún no publicadas; no confundir fin de ventana local con fin de playlist.

## Scroll y foco

- Al montar/volver a abrir la queue, localizar la ocurrencia actual y posicionarla con hasta dos anteriores visibles encima. Si no hay actual, mantener una posición útil para pendientes/estado vacío.
- Durante avance, seguir la actual sólo si el usuario ya estaba siguiéndola. Explorar anteriores/recomendaciones o mover foco suspende ese seguimiento. No recentrar por ticks de audio, Like, llegada de recomendaciones o actualización de metadata.
- Conservar ancla por ID y desplazamiento relativo al cargar filas encima, redimensionar o cambiar proyección. Una promoción puede modificar la altura de dos bloques, pero no debe saltar la posición de quien lee.
- Una acción explícita que agrega/promueve/reordena mantiene el foco en la ocurrencia resultante; no usar `videoId` como identidad, ni índices visuales como comandos de reproducción.
- Mac: anteriores visibles inicialmente en una ventana acotada (hasta 100, como límite de publicación vigente), situada **antes** de la actual. Al acercarse al borde superior, revelar un lote previo y compensar el offset por ID. No restaurar el plegador ni copiar todo el prefijo a cada tick. Mantener `visiblePendingIndices`, cola autoritativa completa y acceso progresivo a huecos/lotes pendientes.
- Windows: representar anteriores/actual/pendientes como rangos internos del mismo bloque con sólo una cabecera; preservar slots absolutos, snapshots dispersos, `queueIndex` frente a índice local, solicitud de ventanas y DOM acotado. Quitar el estado visual `previousExpanded`, sin crear una cola paralela en TypeScript.

## Diagnóstico del scroll horizontal

Evidencia y reproducción: [QUEUE-HORIZONTAL-SCROLL-2026-10-31.md](research/QUEUE-HORIZONTAL-SCROLL-2026-10-31.md).

Dos diferencias concretas del nuevo contenedor Mac frente a `NativeTrackTableView`:

1. `NativeSeparatedQueueView.makeNSView` no fija `table.style = .plain`. En el AppKit local, el estilo automático añade 32 pt al ancho de documento respecto de la columna. `updateNSView` asigna a la columna todo el ancho visible, por lo que el documento excede ese ancho en 32 pt. Reproducido en 350 y 600 pt con la configuración de geometría nueva; `.plain` elimina ese exceso en la prueba aislada.
2. Oculta la barra con `hasHorizontalScroller = false`, pero no fija `horizontalScrollElasticity = .none` como la tabla anterior. Ocultar la barra no corrige geometría ni garantiza ausencia de rebote.

Corrección prevista:

- Fijar estilo `.plain`, elasticidad horizontal `.none` y mantener desplazamiento vertical nativo.
- Ajustar columna/documento al ancho efectivo del clip durante layout/redimensionado, no sólo cuando SwiftUI entrega otro estado. Comprobar primero qué resuelve el estilo; añadir adaptación de layout sólo si persiste diferencia, evitando bucles de relayout.
- Verificar y normalizar un offset X residual al redimensionar si lo requiere el contenedor. No interceptar toda rueda ni bloquear el scroll vertical para ocultar el síntoma.
- Revisar compresión/truncado de títulos, metadatos y acciones, particularmente `ProposalCell`, que hoy reserva espacio para dos botones adicionales. Ningún ancho mínimo de texto debe empujar el documento.
- Windows presenta un riesgo distinto: `.queue-list` declara `overflow-y:auto` sin política explícita de X. Revisar ancho real de grid/filas/cabeceras y añadir `overflow-x:hidden` con columnas adaptables; no usar el recorte para dejar controles inaccesibles. No se afirma que el mismo exceso AppKit exista en Windows.

## Archivos y secuencia de integración

- [x] Elegir la variante y definir estructura, estados, acciones y scroll.
- [x] Contrastar implementación con tabla anterior y FIX-036; aislar el exceso AppKit.
- [x] **1. Baseline:** ejecutar pruebas focales vigentes de cola, proyección, shuffle y persistencia. Conservar resultados y verificar las fuentes locales existentes sin revertir trabajo previo.
- [x] **2. Geometría Mac:** corregir el contenedor en `apple/Sources/SideB/Views/Common/NativeSeparatedQueueView.swift` y comprobar anchos efectivos/gestos. Esta corrección es separable de la proyección visual.
- [x] **3. Proyección Mac:** ordenar anteriores/actual/pendientes bajo `queue.now`; retirar plegador, `queue.upNext`, vacío elegido y explicación rutinaria. Añadir publicación progresiva de anteriores con ancla; preservar paginación pendiente. Usar identidades estables en selección/drag/menús.
- [x] **4. Filas y navegación Mac:** ajustar `ProposalCell`/`NativeQueueTrackCellView` sólo en los controles/estados necesarios, conservando celda reciclada y foco; conectar posicionamiento inicial desde `FullscreenNowPlayingView` sin reconstruir la queue al cambiar pestaña innecesariamente.
- [x] **5. Windows:** modificar `queueProjection.ts` y `QueuePanel.svelte` juntos, proyección de dos cabeceras, rango de anteriores siempre navegable, foco/offset por ID y política de ancho. Reutilizar DTOs y comandos existentes; evaluar si alguna ventana requerida necesita ajuste del consumidor actual antes de tocar runtime.
- [x] **6. Localización/accesibilidad:** actualizar el fragmento editorial `apple/Localization/fragments/queue-recommendations.json` y `windows/src/lib/i18n/windows.json`. Regenerar/checkear recursos Apple según flujo existente; retirar claves sólo si no tienen otros consumidores. VoiceOver/Narrator describen actual/propuesta/acciones sin cabeceras artificiales.
- [x] **7. Verificación y entrega:** pruebas indicadas debajo, revisión de diff, registro de FIX y paridad con evidencia propia. Build Mac numerada mediante skill habitual al entregar app; Windows nativo se reporta por separado. No implica commit, push o publicación.

## Aceptación y comprobaciones

- Sólo dos cabeceras en estado normal con reserva; anteriores arriba y actual una sola vez. Radio sin manuales no genera mensajes/cabeceras vacías; playlist y Play next se mezclan por orden real.
- Validar selección de inicial intermedia, duplicados, radio prolongada, actual manual, shuffle ON/OFF, repetir, restauración pausada, carga/error/reintento y promoción durante scroll manual.
- Mantener el orden funcional confirmado: playlist A→B→C + X siguiente + Y final produce A→X→B→C→Y→recomendación; radio R1 + X/Y produce R1→X→Y→R2.
- Proyección y vistas: 10.000 canciones, actual cerca del final, inserción al final visible y ventanas dispersas Windows; no perder filas anteriores al extender ventana, no crear/copiar/renderizar 10.000 celdas para abrir el panel. Separar prueba de corrección de medición de rendimiento nativo.
- AppKit: comprobar `document.frame.width <= contentView.bounds.width + 1` tras layout, estrechar/ampliar, alternar pestañas, cambiar sidebar y actualizar reserva. Probar títulos largos y localización ES/EN. Anchos de panel 350/480/600 pt y mínimo realmente alcanzable en app; 320 pt como prueba de estrés si el layout lo permite.
- Gestos: X permanece en origen sin desplazamiento/rebote con gesto horizontal/diagonal; Y sigue desplazándose con rueda, trackpad, teclado y arrastre al borde. No activar navegación atrás/adelante accidental sobre la queue. La prueba aislada no sustituye esta QA en ventana real.
- Windows: geometría DOM `scrollWidth <= clientWidth + 1`, controles visibles, grid que comprime texto, rueda/teclado y virtualización en ancho mínimo/normal. Validación WebView2/Narrator nativa pendiente hasta ejecutarla en destino.
- Swift: ampliar `SeparatedQueueIntegrationTests.swift` para orden de filas, ancla/foco y geometría usando el constructor real del contenedor (el fixture actual crea otra tabla y omite configuración de producción); ejecutar focales y suite en serie por el antecedente de estado global compartido.
- Windows: actualizar `queue-projection.test.mjs` (hoy exige cuatro cabeceras y plegado) y `queue-presentation.test.mjs`; ejecutar `pnpm check`, `pnpm test`, `pnpm build`. Pruebas de layout/gestos deben medir el resultado, no limitarse a buscar cadenas CSS.

## Implementación y verificación — 2026-10-31

Entrega inicial de Continua: [build-0172/BUILD.json](../builds/macos/build-0172/BUILD.json), release `compiled`, fuentes estables, firma ad hoc y10hashes comprobados.272XCTest +519SwiftTesting aprobadas. La build0171 queda conservada como intermedia: sólo documentación cambió durante su compilación. La documentación de cierre se actualiza después de terminar0172; no cambia fuentes de producto.

- Se implementó la variante Continua en `NativeSeparatedQueueView` y `QueuePanel`/`queueProjection`, conservando comandos, ocurrencias, paginación y celdas recicladas. No se cambió el core ni la lógica de reproducción en esta entrega; las modificaciones funcionales de PLAN-018 ya estaban en el árbol al comenzar.
- Mac: estilo plain, clip que restringe X, ajuste de columna/documento en layout y elasticidad horizontal desactivada. Anteriores en lotes de100 por encima de actual, ancla/offset por ocurrencia y posicionamiento inicial con dos anteriores. Scroll manual/teclado interrumpen seguimiento; foco explícito se conserva tras mutaciones. Propuestas usan un plus, con acciones completas en menú y hover/foco conservados.
- Windows: sólo dos cabeceras virtuales, rangos anteriores/actual/pendientes conservados internamente y snapshots dispersos íntegros. Se abre cerca de actual y respeta exploración manual; la continuidad se deriva de ocurrencias, **no** de generation, que también cambia al avanzar de pista. `overflow-x:hidden` acompañado de verificación real de contenido/controles.
- Refinamiento sobre el boceto: conservar la cabecera contextual existente una sola vez y mantener los avisos excepcionales de carga/error/repetir. Windows conserva sus avisos en la cabecera contextual para no duplicarlos dentro de las filas virtuales; Mac los sitúa junto a Recomendaciones. Reserva vacía inactiva no crea bloque de explicación. No hay un indicador autoritativo de agotamiento confirmado nuevo; no se infiere agotamiento de una reserva momentáneamente vacía.
- Localización: se retiraron cinco claves Apple y tres Windows sin consumidores y se unificó «Ahora suena / Now playing». Recursos de ambas plataformas regenerados; `sync-localizations --check` verifica la fuente editorial.
- Baseline antes de editar:10 pruebas Swift focales y15 Node de proyección/presentación aprobadas. Después:10 pruebas Swift de proyección/integración/geometría (incluyen cuatro nuevas), suite completa791Swift aprobadas (272XCTest y519SwiftTesting) durante build0171. Windows517 pruebas totales:515 aprobadas,2 omitidas,0fallos. Check:0errores/1advertencia CSS previa en SearchPrimaryRow; build frontend aprobado.
- `node windows/scripts/queue-continuous-browser.mjs`:8 combinaciones de ancho320/350/480/600 y ES/EN con Svelte/CSS reales en Chrome sobre archivo local. `scrollWidth == clientWidth` en todas; acciones dentro de la fila, una acción de propuesta,17–18 filas montadas al final de una cola de1000 y scroll manual conservado al avanzar/actualizar reserva. El fixture normaliza rAF a temporizador para `--dump-dom` con tiempo virtual; no mide FPS ni simula trackpad físico. Resultados en `.cache/queue-continuous-browser/result.html` (ignorado por Git).
- `queue-continuous-runtime.test.mjs` monta el componente real y verifica apertura, seguimiento inicial, suspensión por scroll manual, generaciones de reproducción nuevas, reserva y reemplazo de cola con nuevas ocurrencias.
- Registro: [FIX-270](../FIXES.md#fix-270), [PAR-045](../PARIDAD.md). Build0171 compiled con sólo documentación cambiada durante ejecución; entrega final0172 compiled con árbol estable, firma y10hashes verificados. QA humana pendiente; no hay commit/push/release.
- [ ] Aceptación física: trackpad/gestos diagonales, lector de pantalla y cuenta/audio en app; Windows nativo en destino. No se marca completada por pruebas sintéticas.


## Ajuste solicitado tras probar build0172 — FIX-271

- [x] Quitar selección azul al clicar canciones, conservando selección interna/teclado y resaltado de la canción actual.
- [x] Cabeceras Now playing/Recomendaciones sin hover de canción ni selección.
- [x] Eliminar el contenedor distinto de propuestas: mismas columnas y controles de la celda normal; plus sólo en el slot de duración/grip con hover/foco.
- [x] Preservar Add to queue, votos, menús, foco, reuso y descarte de callbacks de otra cola/sesión.
- [x] Verificar16focales Swift,515frontend Windows y8escenarios Chrome de geometría/alternancia de controles ES/EN. Check/build frontend aprobados; una advertencia CSS previa de búsqueda permanece fuera del ámbito.
- [x] Runner oficial Mac0173 release `compiled`, fuentes estables, firma ad hoc/10hashes aprobados;272XCTest +521SwiftTesting sin fallos. [BUILD.json](../builds/macos/build-0173/BUILD.json).
- [ ] Aceptación humana de la nueva presentación; Windows nativo pendiente.

Este ajuste reemplaza el plus adicional del primer refinamiento. No modifica la cola autoritativa, reserva, audio ni persistencia. Registro [FIX-271](../FIXES.md#fix-271), seguimiento PAR-045.


## Reinserción por arrastre — FIX-273 (2026-10-31)

Pedido posterior del usuario: anteriores y canción actual también deben poder volver a la queue mediante drag, en Mac/Windows, **sin compilar**.

- [x] Modelo Mac `placeQueueOccurrence` y propietario Rust `place_entry`: crear nueva ocurrencia al reelegir anteriores/actual; mover pendientes con su ID; mantener propietario activo, orden previo y reserva; rechazar IDs/destinos inválidos antes de mutar.
- [x] Habilitar asas/orígenes en ambas vistas, cursor copy/move, drop al comenzar/terminar pendientes y en el separador de recomendaciones; foco por ID nuevo. Mantener origen y destino resueltos por ocurrencia, incluso con videos duplicados.
- [x] Teclado: Abajo desde una anterior/actual la vuelve a elegir como siguiente; las pendientes se siguen reordenando dentro de su rango. Menús Play next/Add to queue conservados.
- [x] Pruebas frontend518:516aprobadas/2omitidas; componente montado cubre los destinos y foco. Check0errores/1warning CSS previo; parser Rust sin errores. No se generan paquetes de app.
- [x] Añadir4pruebas Swift y2Rust que cubren identidad activa, duplicados, reserva, shuffle/restore, IDs inválidos y wiring nativo.
- [ ] Ejecutar esas pruebas nativas y QA física cuando se autorice compilar. No se ejecutaron `swift test`, `cargo test`, `pnpm build` ni builds numeradas en esta tarea.

[FIX-273](../FIXES.md#fix-273), PAR-045. Estos cambios son posteriores a build0173 y requieren una build futura para probarlos en la app. La documentación del panel lateral/FIX-272 concurrente se conserva sin adjudicarla a esta tarea.


## Selección de recomendaciones configurable — FIX-274 (2026-10-31)

- [x] Configuración → Cola, en Mac/Windows y ES/EN: «Al seleccionar una recomendación».
- [x] Predeterminado «Avanzar hasta esa canción»: R8 seleccionada deja R1–R7 en anteriores, reproduce R8 y mantiene R9+ en reserva. No emite escuchas por las saltadas. Las canciones elegidas pendientes se reproducen después de R8.
- [x] Alternativa «Reproducir sólo la elegida»: conserva las anteriores en reserva. Persistencia por instalación, fallback a avanzar y efecto sólo sobre futuras selecciones; fila y menú comparten política. Siguiente/Al final/drag conservados.
- [x] Mutación en los propietarios nativos con IDs/anclas nuevos; prefijo automático sujeto a la poda existente, sufijo/pendientes preservados, validación de sesión/generación antes de actuar. Sin nuevo propietario de cola frontend.
- [x] Frontend521:519aprobadas/2omitidas; persistencia, selector montado/remontado y argumentos del controller. Check0errores/1warning CSS previo, localizaciones820claves, parser Rust y diff sin errores.
- [x] Añadir3pruebas Swift y2Rust: selección de prefijo, alternativa, cola vacía/reserva, IDs obsoletos, pendientes, shuffle/restauración y preferencia.
- [ ] Ejecutar pruebas nativas y QA Mac/Windows en una build futura. No se compilaron apps ni frontend y no se generaron builds, respetando el pedido vigente.

Este pedido reemplaza la decisión intermedia original de PLAN-018. Registro [FIX-274](../FIXES.md#fix-274), seguimiento PAR-045. Build0173 no incluye FIX-273/274.
