# PLAN-006 — Presentación de la cola y orden de controles

- Fecha: 2026-10-10 (America/Montevideo).
- Estado: corrección adicional FIX-145 implementada, verificada en fixture y compilada en build-0009; aceptación física pendiente. Build-0008 conserva el estado anterior.
- Objetivo: acercar la presentación de la cola Windows a la cola específica de macOS, especialmente el orden de botones, sin cambiar su funcionamiento.
- Pedido confirmado: la cola funciona bien. Este trabajo trata de apariencia, distribución, iconos, hover y foco; no de algoritmos de cola, reproducción ni audio.
- Resultado: orden de controles y presentación exclusiva de cola implementados en Windows; algoritmos/runtime/audio/Apple conservados. El integrador coordina la revisión visual, registro final y build.

## Alcance y exclusiones

La implementación se concentra en `src/lib/components/fullscreen/QueuePanel.svelte`. La cápsula de pestañas y las dimensiones del panel se inspeccionan en `FullscreenNowPlaying.svelte`, pero sólo deben ajustarse si una comparación de áreas equivalentes demuestra que afectan a la cola. Los componentes compartidos de portada, actividad y créditos necesitan una variante exclusiva de cola si su presentación actual impide el resultado; no trasladar estos cambios a las demás listas.

Quedan fuera: `core/`, Apple, Rust/Tauri, DTOs, player/controller, menú/executor, persistencia, carga progresiva, radio, historial, shuffle, selección de ocurrencias, algoritmos de arrastre y comandos. No crear una segunda cola ni cambiar el orden de sus canciones. Sidebar y navegación Windows se conservan. No reabrir la presentación de Genius ni de las otras pestañas.

## Referencias y evidencia

Las líneas siguientes corresponden al árbol de trabajo consultado el 2026-10-10; son evidencia de implementación, no capturas ni validación nativa nueva.

| Referencia | Evidencia útil |
|---|---|
| [NativeQueueTrackCellView.swift](../../apple/Sources/SideB/Views/Common/NativeQueueTrackCellView.swift), líneas 225–278, 341–347 y 370–466 | Restricciones, orden físico, visibilidad y perfil compacto exclusivo de cola. |
| [NativeTrackTableView.swift](../../apple/Sources/SideB/Views/Common/NativeTrackTableView.swift), líneas 279–297, 729–746, 875–887, 980–987 y 1142–1164 | Tabla reciclada, separación vertical, celda `.queue`, menú contextual y fondo de fila. |
| [FullscreenNowPlayingView.swift](../../apple/Sources/SideB/Views/Fullscreen/FullscreenNowPlayingView.swift), líneas 440–483 y 504–585 | Pestañas, cabecera, vacío y conexión de acciones de cola. |
| [QueueManager.swift](../../apple/Sources/SideB/Services/Player/QueueManager.swift), líneas 35–47 y 87–94 | Sólo metadatos de presentación: icono y título según contexto. No trasladar su lógica de cola. |
| [AppTheme.swift](../../apple/Sources/SideB/UI/AppTheme.swift), líneas 8 y 41–47 | Radio de portada 2, borde 0,5 y colores neutros de fila AppKit. |
| [NativeQueueTrackCellTests.swift](../../apple/Tests/SideBTests/NativeQueueTrackCellTests.swift), líneas 26–98 | Casos existentes de geometría 350/576/900, créditos conjuntos, hover/foco, ausencia de overlay y callbacks/reutilización. No ejecutados en esta revisión Windows. |
| [QueuePanel.svelte](../src/lib/components/fullscreen/QueuePanel.svelte), líneas 15–29, 41–80, 98–129 y 212–330 | Contratos actuales, ventana de filas, activación, cabecera, orden DOM y estilos Windows. |
| [FullscreenNowPlaying.svelte](../src/lib/components/fullscreen/FullscreenNowPlaying.svelte), líneas 84–88, 171–184 y 220–266 | Orden de pestañas, props existentes, dimensiones del panel y cápsula Windows. |
| [TrackArtwork.svelte](../src/lib/components/common/TrackArtwork.svelte), [TrackActivity.svelte](../src/lib/components/common/TrackActivity.svelte), [ArtistCredits.svelte](../src/lib/components/ArtistCredits.svelte) | Overlay Play/Pause, barras de actividad y créditos navegables compartidos que hoy consume la cola. |

Antecedentes contrastados con el código:

- [FIX-113 Apple](../../FIXES.md#fix-113) restaura una excepción explícita a las cartas comunes de FIX-111: cola con título y subtítulo conjunto, Like/Dislike, duración/grip, sin Play flotante ni puntos. Mantiene menú contextual y player autoritativo.
- [FIX-121-2 Windows](../../FIXES.md#fix-121-2) incorporó filas 46/paso 48, portada 36, créditos navegables, controles compartidos y ventana de filas. Esas mejoras se conservan. Las diferencias visuales actuales se verifican en el código; no se atribuye una regresión histórica a este fix sin evidencia adicional.
- [FIX-057 Apple](../../FIXES.md#fix-057) documenta el perfil compacto histórico. El código actual confirma fila 46, portada 36 y tipografía compacta. Su cantidad histórica de canciones visibles dependía del alto de panel; no es un objetivo fijo para cualquier ventana.
- [PAR-009](../../PARIDAD.md) ya distingue la excepción de cola Apple; [PAR-016-2 / PAR-017-2](../../PARIDAD.md) conservan pendientes visuales del reproductor y del sistema de UI. No cerrar paridad con esta lectura.
- [PLAN-002](PLAN-002-ui-lists-shell.md) conserva los cambios anteriores de cola Windows; este plan acota una nueva comparación de presentación.

## Comparación actual

### Orden y acciones por fila

| Zona | macOS actual | Windows actual |
|---|---|---|
| Inicio | Índice alineado a la derecha; en la ocurrencia actual, altavoz con ondas reproduciendo y altavoz sin ondas en pausa. | Índice centrado; en la ocurrencia actual, barras de actividad animadas o atenuadas en pausa. |
| Portada | Imagen 36 × 36, radio 2; sin botón Play flotante. La tabla activa la fila. | `TrackArtwork` 36 × 36, radio 2; botón independiente y overlay Play/Pause de 28 × 28 al hover/foco; spinner durante carga. |
| Texto | Título; debajo, una línea `artista • álbum`. No columna separada de álbum. | Título; debajo, `ArtistCredits` con artistas/álbum navegables cuando tienen ID y callback. |
| Extremo derecho, de izquierda a derecha | **Dislike → Like → duración**, sustituida por **grip** al hover/foco. | **Duración/grip → Like → Dislike → menú de puntos**. Like depende de sesión/callback y Dislike del callback disponible. |
| Menú | Clic derecho mediante el coordinador; la celda no agrega botón de puntos. | Clic derecho y botón de puntos invocan `onQueueContextMenu` con la misma entrada. |
| Activación | Callback de índice de cola desde la tabla existente. | `activateEntry` resuelve `entryId` en la cola vigente; la actual alterna pausa, otra activa su índice. |

El cambio prioritario es el orden del grupo derecho. No hace falta cambiar el funcionamiento de las acciones para conseguirlo. El orden visual y el orden DOM/foco deben coincidir; no resolverlo sólo con `order` CSS.

### Geometría y tratamiento visual

Valores Apple en puntos lógicos; Windows en píxeles CSS. Comparar áreas lógicas equivalentes y después la rasterización/DPI, sin exigir igualdad de píxeles físicos entre sistemas.

| Elemento | macOS actual | Windows actual | Objetivo de presentación |
|---|---|---|---|
| Altura / paso | 46 / 48 (intercelda 2). | 46 / 48. | Conservar; no variar `rowPitch` ni la ventana de filas. |
| Fondo de fila | Rectángulo inset horizontal 10 y vertical 1; radio 6. | Fondo de todo el rectángulo de fila; radio 7; borde 1. | Reproducir el inset/radio mediante una capa visual, conservando el área de activación. |
| Activa / hover | AppKit: blanco 6,5 %, borde 9 % a 0,5; hover 4,5 %. | Blanco 6,5 %, borde 9 % a 1; hover 4 %. | Mantener el color activo ya alineado; ajustar borde, hover y geometría exclusivos de cola. |
| Posiciones izquierdas | Índice x=16, ancho 24; portada x=50; texto x=98. | Flex con padding 10, borde 1, índice 24 y gaps 10; no las mismas anclas. | Llevar las anclas a las de Apple sin hacer depender el texto del ancho del nombre. Medir el resultado real. |
| Texto | Título 13 medium/semibold activo; subtítulo e índice 11,5. | Título 13, peso 500/650 activo; subtítulo 11,5; índice compartido 12. | Conservar título/subtítulo compactos; índice 11,5 y alineación derecha en variante de cola. |
| Votos | Botones 18 × 18; símbolos 12. Dislike separado 6 de Like; Like separado 8 de duración. | Botones 24 × 28, símbolos 16 y gap 2 dentro de acciones. | Acercar tamaño visible y espaciado a Apple; definir cajas de interacción sin solapar controles ni perder foco. |
| Like marcado | Corazón relleno blanco y siempre visible. | Corazón relleno rojo `#D06C70` y siempre visible. | Blanco en cola; no cambiar el estado de Like ni su petición. |
| Duración / grip | Slot 44; margen final 18; grip 16 × 14 centrado en ese slot. | Slot 44 antes de acciones; hitbox 44 × 30; grip SVG 18 × 16. | Slot 44 al extremo derecho, margen 18; glifo 16 × 14 y hitbox conservada si no invade otros botones. |
| Iconos | SF Symbols `hand.thumbsdown`, `heart`, `heart.fill`, `line.3.horizontal`; altavoz 12. | SVG propios de votos/grip; barras compartidas. | Vectores Windows de orientación/peso equivalentes; altavoz como variante visual exclusiva de cola. Verificar el pulgar con captura, no sólo por nombre del botón. |

En el grupo compacto Apple, para ancho de celda `W`: duración ocupa `W−62…W−18`, Like `W−88…W−70`, Dislike `W−112…W−94`; el texto termina como máximo en `W−124`. Son restricciones del código, no una medición nueva en ventana. Los elementos extra Windows deben resolverse antes de fijar el ancho final del texto.

### Hover, foco y estados

- Apple revela votos/grip por hover o foco; sustituye duración por grip. Un Like marcado permanece visible en reposo. La selección persistente por sí sola no revela controles. Windows ya revela controles con `:hover`/`:focus-within` y conserva Like marcado; se debe mantener esa interacción al mover los elementos.
- La fila actual conserva fondo y peso de título tanto en reproducción como en pausa. Cambiar barras por altavoz sería sólo presentación de `isPlaying`; no consultar ni mutar el reproductor.
- Windows tiene estados de carga/bloqueo, Like pendiente, error de movimiento, radio y fuente progresiva con Reintentar. Apple no muestra exactamente la misma composición de mensajes. Se conserva toda la información/recuperación Windows, ajustando ubicación y tamaño.
- Los créditos Windows tienen navegación adicional a la etiqueta plana Apple. Conservar IDs, nombres completos accesibles, callbacks y enlaces independientes de la activación de fila. Aproximar la línea conjunta/truncado sin quitar navegación ni reemplazar los datos.

### Cabecera, pestañas y vacío

| Elemento | macOS actual | Windows actual | Objetivo |
|---|---|---|---|
| Pestañas externas | **Cola → Letras → Relacionado**; icono + texto; cápsula centrada, padding 4; icono 12,5, texto 13, gap 7, padding botón 16/8. | Mismo orden, icono 14, texto 13, gap 7, padding 16/8; cápsula 40 y fondo sólido `#343437`. | Conservar el orden y selección; comparar material/tamaño sólo si la captura equivalente lo requiere. No cambiar contenido ni acciones de otras pestañas. |
| Contexto | Icono según origen → título → `•` → cantidad → espacio flexible → carga compacta. | Icono genérico de tres líneas → título → `·` → cantidad; avisos en líneas separadas. | Mismo orden Apple; iconos radio/álbum/playlist/manual usando `queue.source.kind` existente; título localizado sólo de presentación. |
| Medidas de cabecera | Padding horizontal 8/top 2; gap 8; título 12 semibold blanco 90 %; cantidad 11 medium blanco 50 %; icono 11; separador 10 blanco 30 %. | Padding 2/8/8; gap 8; título 12/peso 650; cantidad 11/blanco 53 %; icono 14. | Alinear icono/separador/pesos y mantener conteo legible sin truncarlo. |
| Carga / errores | Carga de radio/autoplay a la derecha de la cabecera, texto 10. | Fuente preparando, cantidad parcial, carga radio, errores/reintento y error de movimiento en líneas propias. | Compactar estados normales en el espacio trailing cuando quepan; reservar línea adicional para errores/parcial si hace falta. No ocultar ni fusionar causas diferentes, ni presentar cantidad cargada como total definitivo. |
| Vacío | Sólo icono `music.note.list` 38 blanco 25 % y texto 14 medium blanco 55 %, gap 12, centrados; sin contexto arriba. | Cabecera presente incluso sin canciones; icono genérico 36 blanco 28 % y texto 14 regular. | Vacío equivalente, omitiendo contexto normal redundante. Conservar cualquier error/carga/reintento real aunque no haya filas. |

Apple reserva aproximadamente 28 para cabecera/lista en el caso normal y agrega insets de tabla top 2/bottom 4. No forzar altura fija 28 cuando Windows tiene un error o mensaje parcial que requiere más espacio.

## Decisiones de integración y pendientes visuales

1. **Accesos extra Windows.** Referencia Apple: sin overlay Play flotante ni botón visible de puntos. La integración futura conserva las acciones Windows y su acceso accesible; no necesita modificar la cola funcional. El pedido prioritario es el orden de botones; los demás ajustes de apariencia se verifican después.
2. **Decisión vigente tras reporte de build-0008: retirar puntos explícitos** (FIX-145). Menú sólo mediante clic derecho y Shift+F10/ContextMenu desde botón de fila. Grupo visible Dislike → Like → duración/grip con centros uniformes36 y eje vertical común. Reemplaza decisión anterior de FIX-142; conserva las acciones del menú.
3. **Portada interactiva sin overlay.** Implementado mediante `showPlayOverlay={false}` sólo en cola; el componente compartido mantiene `true` por defecto. Conserva botón, nombre accesible, disabled durante carga, callback y `aria-busy`.
4. **Créditos navegables.** Conservarlos como adaptación Windows; el objetivo es composición compacta `artista • álbum`, no convertirlos en texto inerte. Si se necesita controlar truncado, hacerlo mediante variante local y comprobar colaboradores/álbum largo.
5. **Geometría del panel completo.** Medir primero ancho y alto útiles. Las fórmulas del contenedor fullscreen y el espacio de sidebar difieren; no atribuir diferencias de cantidad visible a filas cuando el viewport es distinto. Ampliar cambios al contenedor sólo con evidencia y manteniendo las otras pestañas.

## Orden objetivo y contratos que se conservan

- Cabecera de panel: **icono contextual → título → • → cantidad → carga compacta al extremo derecho**. Errores y Reintentar siguen disponibles en una línea adicional cuando corresponda. No agregar botones Shuffle, Clear, Next ni una nueva toolbar.
- Fila objetivo Apple: **índice/altavoz → portada → título y artista • álbum → Dislike → Like → duración/grip**. Adaptación Windows: menú antes del grupo común, según decisión anterior.
- Pestañas: **Cola → Letras → Relacionado**, sin cambios de comportamiento.
- Mantener las props existentes: `playback`, `onSelectQueue`, `onTogglePlayback`, `onOpenArtist`, `onOpenAlbum`, `onMoveQueue`, `onQueueContextMenu`, `onRetryRadio`, `onRetrySource`, `loggedIn`, `likedIds`, `pendingIds`, `likesLoading`, `onToggleLike` y `onDislike`.
- Mantener las condiciones actuales de disponibilidad/disabled y la resolución de la entrada vigente por `entryId`. No cambiar indexación, revisiones, generaciones, identidad de duplicados ni mutaciones de cola.
- Conservar selección como botón hermano de créditos/acciones, propagación de eventos, foco, etiquetas accesibles, anuncios, drag/drop y flechas del asa. Alinear el recorrido de teclado con la nueva distribución sin reescribir su algoritmo.
- Conservar virtualización y retención de fila enfocada/arrastrada, altura total, scroll y overscan. El cambio es de composición/estilo; no requiere nuevo DTO ni comando.

## Pasos de implementación

- [x] Leer instrucciones, antecedentes y presentación actual de ambas plataformas.
- [x] Identificar orden real, medidas, estados, diferencias y contratos que deben conservarse.
- [x] Integrador revisó constraints Apple y markup Windows; conservar menú antes del grupo común y portada accesible sin overlay, sin perder acciones. Usuario autorizó implementación posterior.
- [ ] Preparar referencia con datos ficticios idénticos: títulos, colaboradores, álbumes, duraciones, likes, origen y ocurrencia actual. Capturar baseline Windows y referencia macOS con áreas útiles medidas.
- [x] Reorganizar markup de fila en `QueuePanel.svelte`: menú → Dislike → Like → timing al extremo derecho; foco coherente con DOM. Callbacks y condiciones existentes conservados.
- [x] Aplicar geometría/tipografía/iconos/estados exclusivamente a la cola; fondo inset en pseudo-elemento del botón de activación. Fila 46/paso 48 conservados; hitboxes de votos/menú 24 × 28 y asa 44 × 30 conservadas, símbolos compactos 12 y grip 16 × 14. No modifica las demás listas.
- [x] Ajustar cabecera contextual y vacío conservando estados recuperables, información parcial y reintentos; sólo omite cabecera en vacío sin mensajes reales.
- [x] Añadir variantes opt-in `TrackArtwork.showPlayOverlay` y `TrackActivity.presentation='queue'`; valores predeterminados conservan overlay/barras de otros consumidores. Créditos navegables conservados sin editar su componente.
- [x] Revisar diff contra baseline y confirmar que no contiene cambios de runtime, algoritmos o audio. Script de QueuePanel idéntico salvo `queueTitle` de presentación, tras normalizar finales de línea.
- [x] Ejecutar comprobaciones automáticas y fixture visual; registrar diferencias residuales y límites. Matriz física completa pendiente.
- [x] Integrador actualizó FIXES/PARIDAD/este plan/índice (FIX-142/144). Build numerada integrada build-0008 aprobada; el subagente no la ejecuta.

## Comprobaciones de cierre

1. **Geometría equivalente:** paneles de 350, 576 y 900 unidades lógicas como referencia de la prueba Apple, además del panel real disponible en ventanas 1440 × 900 y 850 × 700. Registrar tamaño útil del panel/lista, escala de SO, zoom WebView y sidebar Windows expandida/colapsada (230/60 si esos son los valores efectivos). No confundir fullscreen del reproductor con fullscreen del sistema.
2. **Matriz de estados:** fila normal/actual reproduciendo/actual pausada, hover, foco por Tab/Shift+Tab, Like marcado/no marcado/pendiente, invitado, carga de pista, sin portada, títulos y álbumes largos, múltiples artistas, duplicados con `entryId` distinto, origen radio/álbum/playlist/manual y cola vacía. Capturar al menos reposo + hover + foco con el mismo contenido.
3. **Estados del panel:** radio cargando/error, fuente preparando/parcial/error, Reintentar y error de movimiento. Verificar que el header compacto no tapa cantidad ni reintentos y que la lista conserva scroll. Comparar DPI 100/125/150 % disponibles y foco visible.
4. **Conservación de acciones con fixture:** cada clic/Enter/Space de control dispara exactamente el callback actual con la misma entrada; créditos y menú no activan reproducción; activar la actual alterna pausa; otro duplicado selecciona su ocurrencia. Comprobar arrastre/flechas/Tab a través de ventana virtual sin modificar el algoritmo. Son verificaciones de integración del markup, no una nueva auditoría del funcionamiento de la cola.
5. **Larga y estrecha:** comprobar virtualización con 1000 entradas ficticias, fila enfocada retenida, sin clipping horizontal, sin saltos de texto al revelar botones y sin perder el destino de menú/reordenado. No exigir una cantidad fija de canciones visibles sin medir el alto útil.
6. **Automático tras implementar:** `pnpm check`, `pnpm test` y `pnpm build` desde `windows/`; agregar sólo regresiones observables de presentación/eventos si aportan cobertura. Compilar no acredita apariencia nativa, audio audible ni FPS.
7. **Aceptación visual separada:** fixture de navegador primero; WebView2 real después. La comparación macOS nativa requiere captura/ejecución en Mac y queda pendiente mientras no exista esa evidencia. Si se solicita build local, aplicar el protocolo numerado y registrar su ruta; este plan no ejecuta build.

## Evidencia de implementación y límites

- Baseline del árbol sucio conservada antes de editar en `windows/.cache/plan-006-baseline/`, excluida de Git; incluye QueuePanel, TrackArtwork, TrackActivity y este plan. No se revierten cambios anteriores.
- Archivos de implementación: `QueuePanel.svelte`, `common/TrackArtwork.svelte`, `common/TrackActivity.svelte`; regresiones nuevas en `windows/scripts/queue-presentation.test.mjs`.
- `pnpm check`: **0 errores / 0 advertencias**, ejecutado nuevamente tras recuperar la sesión.
- `node --test scripts/queue-presentation.test.mjs`: **6/6 aprobadas**. Compila/renderiza componentes reales con Svelte server: orden DOM de ocurrencias duplicadas; controles disponibles para invitado/callbacks opcionales; vacío con errores y reintentos; disabled y carga accesible; variantes opt-in frente a consumidores predeterminados; títulos contextuales/cargas independientes/conteo parcial.
- Harness inicial con Vite SSR no terminó y se detuvo; fue reemplazado por compilación server directa y resolución local de dependencias en caché ignorada. No agrega dependencias ni modifica configuración compartida. Una colisión inicial de nombre `presentation` en TrackActivity se corrigió renombrando el servicio de contexto `presentationService`; check posterior aprobado.
- Diff/whitespace contra las tres copias baseline revisado; funciones de activación, foco/Tab, virtualización y arrastre sin cambios. Los tests de render no ejecutan clics reales ni prueban layout CSS del navegador.
- No se modificaron controller, DTOs, runtime, core, Apple ni FullscreenNowPlaying; no se corrió cargo ni build standalone. Suite frontend completa y protocolo numerado quedan a cargo del integrador.
- Aceptación visual WebView2/macOS, acciones físicas, DPI, foco al cruzar la ventana virtual, FPS y audio siguen pendientes de evidencia. El panel completo y sus otras pestañas permanecen conservados.

## Revisión de integración 2026-10-10

Seis tests de render Svelte aprobados y check 0/0. Fixture de 1000 ocurrencias con IDs distintos, incluyendo videos duplicados, comprobada en navegador: ventanas 1280×720, 850×700 y 1440×900; sidebar 230/60; paneles medidos 306,875/369,5625/492,484375/600. Fila 46/paso48, portada36, origen de portada x+50 y texto x+98; controles 24×28 y asa44×30 sin solapamiento. Menú → Dislike → Like → duración/grip coincide en DOM y geometría. Selección, flecha de movimiento por entryId, menú, Like, Dislike, créditos/foco y Reintentar conservan callbacks; no usan audio. Filas montadas acotadas 18–19. Otros estados vacíos/carga/guest/pending/defaults cubiertos por render automático. Baseline y fixture conservadas ignoradas en windows/.cache.

Corazón/información fullscreen (FIX-144): hitbox36 y símbolos20–22, centrado óptico medido y apertura/cierre de reverso y Like comprobados. La fórmula Apple se tomó del código actual; sin nueva ejecución AppKit. Screenshot de evidencia ignorada: windows/.cache/plan006-icons-ui/review-queue.png. Build integrada build-0008 release aprobada. No afirmar la matriz física 350/576/900 ni DPI/Narrator/AppKit/WebView2 como completada; la preparación comparada de capturas sigue abierta.

Cierre automatizado 2026-10-10 14:42: check0/0, frontend273 + nativas358 = **631 aprobadas**, cero fallos/14 live ignoradas. `builds/windows/build-0008/sideb-windows.exe`; BUILD.json compiled, fuentes estables y cuatro SHA256 verificados. DLL y licencia acompañan al EXE; versiones anteriores conservadas. FIX-142/144, PAR-009/016-2/017-2. Sin ejecutar EXE/cuenta/audio reales, commit, push o release pública.

## Corrección solicitada tras probar build-0008 — FIX-145

- [x] Contrastar captura con CSS y FIX-142: botones24, asa44, margen5 y tiempo a derecha explican centros irregulares y cambio de posición al hover.
- [x] Retirar botón/import/estilos de puntos. Conservar menú contextual y teclado; sin cambios del motor ni cola nativa.
- [x] Dar hitboxes28×30 y separaciones8: centros36/36. Duración de ancho intrínseco y asa comparten centro. Asa16×14 dibujada en viewBox16×14, corazón centrado ópticamente.
- [x] Actualizar seis expectativas de render existentes; check0/0. Fixture1280×720 y850×700: ejes coincidentes y36/36, sin overflow. Probar clic derecho, Shift+F10, Like y flecha con entryId correcto;18 filas montadas. Captura local ignorada `windows/.cache/fix145-baseline/review.png`.
- [x] Registrar FIX-145/PAR-009/016-2/017-2 e índice. Las anotaciones anteriores son evidencia histórica de build-0008, no aceptación de estos defectos.
- [x] Completar build nueva integrada y registrar resultado. Aceptación WebView2 física separada y pendiente.

Cierre FIX-145 2026-10-10 15:09: protocolo exit0; check0/0, frontend273+nativas358=**631 aprobadas**, cero fallos/14live ignoradas. `builds/windows/build-0009/sideb-windows.exe`; BUILD.json compiled/sourceChangedDuringBuild=false y cuatro hashes comprobados. EXE y dependencias conservados juntos, versiones previas intactas. Sólo documentos de cierre editados después de compilar; Apple/core intactos. No abierto EXE ni sesión/audio real.
