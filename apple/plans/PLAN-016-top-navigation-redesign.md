# PLAN-016: rediseño de topnav e historial

- Fecha: 2026-10-12 (America/Montevideo).
- Estado: **Rediseño suspendido; topnav de build-0091 restaurada —2026-10-13, FIX-184**. App0091 conservada abierta, sin nueva build.
- Objetivo vigente: conservar navegación anterior0091 junto a los arreglos del resto de UI. Rediseño para más adelante.
- Alcance vigente: restauración de componentes y conexiones de toolbar; sin isla ni demo integrada. Los apartados siguientes conservan antecedentes suspendidos.
- Ámbito implementado: shell y búsqueda Apple; sin nuevas fuentes del core protegido ni Windows. PAR-007/PAR-027 actualizados, conservando la exclusión previa del selector/transición Mac del port.

## Evidencia y antecedentes

Se observó build-0091 con la sidebar abierta y cerrada, restaurando su estado original. `NavPresentation` muestra la topnav cuando sidebar y fullscreen están cerrados. `NativeNavigationBar` mide un `NSSegmentedControl`, con ancho preferido 262 pt y símbolos de 14 pt. `NativeHistoryBar` declara altura 34 pt, botones 28 pt y símbolos de 13 pt; cambia de ancho con las acciones de Inicio. `NativeNavigationHeader` centra el grupo de historial sobre la ubicación del panel derecho. Son decisiones vigentes; la sensación de piezas independientes motiva una nueva propuesta, sin atribuir regresiones.

Antecedentes: FIX-090 (tamaño medido, lente nativa y transición con sidebar), FIX-105/106 (acciones de Inicio), FIX-107 (centrado estable sobre panel abierto/cerrado). PAR-007 registra la adaptación Windows y la exclusión previa del selector Mac; esta exploración Apple no reabre ese port.

## Dirección elegida

El usuario eligió **Isla única** sobre las alternativas Integrada y Editorial. Pide que la topnav aparezca con una animación cuidada, se conecte con Atrás/Adelante y que su lupa abra un buscador en la propia isla; ⌘K conserva el Spotlight.

La isla mantiene historial y destinos/campo en una sola silueta. **Refinamiento pedido:** con sidebar abierta, el historial se sitúa en el área de contenido, a la derecha del borde exterior de sidebar, con el mismo margen que separa la isla del techo de ventana. Al cambiar sidebar, el ancla horizontal acompaña su borde durante la transición; reemplaza la regla anterior de centros fijos respecto de la ventana. Dentro de cada estado, abrir/cerrar búsqueda no desplaza las flechas: sólo cambia el área derecha. Actualizar/Personalizar Inicio permanecen como acciones contextuales separadas a la derecha.

Conservar del prototipo la escala compacta y una sola silueta exterior. Punto de partida: controles de 36 pt, símbolos de 14–16 pt; medir bezel, texto localizado y áreas de interacción reales antes de fijar dimensiones. La selección debe poder mostrar su etiqueta sin provocar saltos del conjunto; reservar y medir ese espacio. Calibrar la geometría en la ventana mínima real de la app, actualmente 960 × 640, además de tamaños amplios. Los 320 px del prototipo web no representan el mínimo nativo.

## Estados de presentación

| Estado | Presentación | Propietario de la entrada |
|---|---|---|
| Sidebar abierta | Historial compacto fuera de sidebar, en área de contenido y con márgenes iguales | Campo de página si se está en Buscar |
| Sidebar cerrada, navegación | Historial + separador + Inicio/Explorar/Biblioteca/Buscar | Ninguno |
| Edición desde topnav | Historial + campo Buscar + control para cerrar; sugerencias debajo | Campo de la isla |
| Resultados de búsqueda, sin foco | Historial + consulta confirmada compacta; clic para editar | Isla; página presenta resultados y filtros |
| Fullscreen de reproducción | Isla retirada junto a los demás controles de shell | Presentación fullscreen existente |

Spotlight es una presentación superpuesta y exclusiva, no otro estado visual de la isla. Sólo una superficie controla foco y sugerencias a la vez. La consulta confirmada y el borrador son distintos: cerrar un editor no confirma lo escrito.

## Coreografía propuesta

Los tiempos siguientes son objetivos de diseño iniciales, no mediciones ni promesas de rendimiento. La crítica posterior a0099 invalida considerarlos calibrados: revisar duración, respuesta inmediata y uso de animaciones del sistema antes de una siguiente implementación.

| Transición | Movimiento y continuidad | Tiempo inicial |
|---|---|---|
| Cerrar sidebar → mostrar destinos | El ancla acompaña el borde de sidebar hasta el área después de los controles de ventana; la cápsula se extiende hacia la derecha sin sumar otro desplazamiento al historial. Destinos con desplazamiento corto de4–6pt y opacidad dentro del contorno | 380–420 ms, coordinado con los420ms actuales de sidebar |
| Abrir sidebar → contraer destinos | Recorrido inverso desde la posición visible actual, hasta dejar sólo el historial; sin salto entre dos controles independientes | Misma curva y duración de referencia |
| Cambiar destino | Indicador/lente se desplaza a la selección nueva; la altura y el ancho global no cambian sólo por seleccionar | 180–220 ms |
| Lupa → edición en isla | La zona de destinos se transforma en un campo horizontal; el icono de búsqueda actúa como referencia visual. Historial y altura se conservan; sólo crece el área derecha disponible | 260–320 ms |
| Mostrar sugerencias | Panel anclado al campo, debajo de la isla; pequeño desplazamiento vertical de 4–6 pt y opacidad. Sin oscurecer la ventana | 160–200 ms |
| Confirmar consulta / salir de edición | El campo se contrae a la consulta compacta o a los destinos según la ruta; el panel se cierra conservando el contorno de la isla | 220–280 ms |

Preferir aceleración/deceleración suave y asentamiento breve, con rebote mínimo. Hover con realce local discreto; pulsación responde en el botón, no estirando toda la isla. Una animación se puede invertir desde su progreso actual; clics rápidos no encolan secuencias ni fuerzan terminar una transición antes de responder.

Con Reduce Motion: cambios de geometría inmediatos y fundidos de 100–120 ms, conservando foco/acciones. Con Reduce Transparency: superficie opaca legible con la misma geometría y estados. No usar animaciones permanentes ni iniciar trabajo de red en cada frame.

## Búsqueda integrada y Spotlight

### Entradas y navegación

- Clic en Buscar de la topnav: abrir edición en la isla y enfocar el campo en cuanto esté montado; no esperar a que termine la animación ni navegar todavía.
- Campo vacío: recientes existentes. Mientras se escribe: sugerencias textuales y entidades del motor actual, con el mismo debounce, caché, correcciones e invalidación por cuenta.
- Enter o selección de sugerencia: aplicar la intención existente, confirmar la consulta y navegar una sola vez a `.search(query:)`. Escribir o abrir/cerrar el campo no añade entradas de historial.
- Resultados completos: aparecen en el contenido principal. La isla conserva la consulta confirmada en formato compacto; clic vuelve a edición. Loading usa un indicador dentro de un espacio reservado, sin cambiar dimensiones.
- Escape con sugerencias abiertas: cerrar primero el panel. Escape posterior o Cerrar búsqueda: contraer edición, guardar el borrador y restituir foco al control de origen. En una ruta de búsqueda queda la consulta confirmada compacta; en otras rutas vuelven los destinos. Borrar texto es una acción distinta de cerrar la presentación.
- Clic fuera de la isla completa y su desplegable: salir de edición, cerrar sugerencias y contraer a destinos o consulta confirmada, guardando borrador/selección. No enviar consulta ni modificar la ruta. El clic mantiene su acción/foco original; no devolver foco a la lupa después de pulsar otro control. Atrás/Adelante: cerrar edición transitoria y ejecutar exactamente un paso del router; no perder consultas confirmadas del historial. El seguimiento reemplaza el comportamiento anterior que sólo retiraba foco.
- Abrir sidebar durante edición: cerrar el panel y transferir texto/selección/foco al campo de página sólo si la ruta actual es Buscar. Si se estaba editando desde otra página, guardar el borrador y contraer a historial, sin confirmar ni navegar. Al cerrar sidebar en resultados, la isla recupera la consulta confirmada.
- Evitar dos campos visibles para la misma búsqueda: cuando la isla posee la entrada, `SearchView` presenta título/filtros/resultados y omite su campo local. Con sidebar abierta o sin isla disponible, conserva el campo local. Transferir el propietario, no recrear resultados ni reiniciar búsquedas por el cambio de sidebar.

### Atajos y arbitraje de foco

- **⌘K y su comando de menú conservan Spotlight**, con presentación centrada, resultados rápidos y restauración de foco actuales.
- Abrir Spotlight mientras se edita en la isla: guardar borrador/estado, cerrar sugerencias de isla y ceder foco. Escape del Spotlight restaura el contexto previo; confirmar desde Spotlight conduce a la misma página de resultados y actualiza la consulta compacta.
- La llamada actual `openSearch()` sirve a topnav, sidebar y ⌘F; separar callbacks en lugar de cambiarla globalmente. En esta etapa topnav adopta búsqueda integrada, y sidebar/⌘F conservan su comportamiento vigente salvo una decisión posterior explícita. El comando ⌘K permanece cableado al Spotlight.
- Flechas arriba/abajo y Enter pertenecen a sugerencias mientras el campo tenga foco. Espacio y atajos de edición no deben activar reproducción durante entrada de texto. Conservar ⌘[ / ⌘] y los gestos de historial donde estén disponibles.

### Reutilización y solicitudes

`SearchViewModel` ya distingue `query` y `committedQuery`; `SpotlightSearchModal` también tiene un borrador local. Reutilizar el motor y proyecciones, pero mantener borradores/foco por presentación y un único propietario activo de sugerencias. Invalidar la generación de resultados rápidos al transferir esa propiedad para que una respuesta tardía de una superficie no se pinte en otra. No duplicar solicitudes al enviar y montar `SearchView`, ni añadir persistencia por cada pulsación. Preservar la intención actual de recientes: query al confirmar búsqueda, pista al confirmar Play rápido.

## Implementación inicial (FIX-181)

1. Crear una presentación explícita de la isla y un coordinador de búsqueda por ventana. Separar ruta, modo de isla, propietario de foco y datos del motor; impedir estados simultáneos imposibles.
2. Sustituir los dos contenedores independientes de topnav/historial por un host de isla persistente con una única superficie exterior. Reutilizar acciones/router/localización; animar frames, recorte y opacidad, sin escalar texto ni símbolos.
3. Mantener controles de historial y campo montados con identidad estable durante transiciones; ocultos fuera de su estado deben quedar fuera de hit testing y accesibilidad. Usar APIs públicas y comprobar el control nativo elegido sin volver a introducir bezel/material doble.
4. Incorporar campo nativo y panel de sugerencias anclado a coordenadas de ventana; limitar ancho a espacio real después de controles de ventana y antes de acciones contextuales. Si faltan etiquetas, compactarlas antes de reducir targets. Limitar alto del panel para mantener visible el player.
5. Conectar edición/confirmación a `SearchViewModel`, proyecciones y rutas actuales; definir explícitamente la propiedad del campo de `SearchView` y el arbitraje con Spotlight.
6. Calibrar animaciones con reversión rápida, resize y cambios de foco en preview nativo; integrar después en la app completa.

Archivos de referencia: `TopNavigationView.swift`, `HistoryToolbarView.swift`, `WindowNavigationToolbarView.swift`, `ShellLayout.swift`, `NavPresentation.swift`, `SideBApp.swift`, `SearchView.swift`, `SpotlightSearchModal.swift`, `SearchViewModel.swift`, `SearchProjection.swift` y pruebas de navegación/búsqueda. Los nombres de nuevos tipos se fijarán al implementar.

El SDK local declara `NSGlassEffectView` y `NSGlassEffectContainerView` desde macOS 26, y `effectIsInteractive` desde 27. Ambas clases están en `NSGlassEffectView.h`. Apple documenta morphing de efectos coordinados; no asumir que animar una vista AppKit reproduce automáticamente un ejemplo SwiftUI. Comprobar la unión visual con las APIs elegidas. macOS 15 conserva el material fallback y la transformación geométrica equivalente.

## Resultado implementado

`NavigationIslandToolbarView` mantiene un solo host nativo para sidebar, isla y acciones de Inicio; incluir toggle e isla en el mismo ToolbarItem evita que NSToolbar omita el control por colisión de tamaños. `AnimatedNavigationIslandToolbarView` comparte el progreso de420ms con sidebar, conserva centros de historial y revela destinos hacia la derecha. Altura36pt, targets30pt, símbolos14pt, slots medidos por etiqueta localizada más larga y lente200ms. La edición anima geometría280ms/opacidad240ms, reversible desde el progreso actual. No hay bezel segmentado dentro de un segundo cristal. Acciones de Inicio conservan centro sobre el panel derecho y fullscreen mantiene sólo toggle.

`NavigationIslandSearchState` separa ruta confirmada, borrador, selección y propietario de preview. `NavigationIslandSuggestionsView` comparte motor/proyección/intenciones, presupuesto8 y callbacks de teclado/puntero; monitor local de clic fuera no consume eventos. El campo de página se omite con sidebar cerrada. Ambos editores son NSTextField con NSRange acotado a UTF-16, preservan marked text y comandos nativos. Un UUID por instancia de página impide que cleanup de una vista retirada cancele la transferencia al nuevo editor. `NavigationSearchTextField` observa foco real separado de la primera edición y reintenta al adjuntarse a ventana. Spotlight cancela su preview antes de devolver propiedad/foco; confirmar mantiene una sola navegación. Los atajos ⌘K/sidebar/⌘F conservan la presentación centrada.

La revisión de subagentes e integrador y el preview nativo corrigieron cuatro problemas observados antes de entregar: toolbar omitida por ancho propuesto, foco oculto en primer frame de morph, crash por selección SwiftUI String.Index obsoleta y pérdida de propiedad al desmontar la página previa. Los diagnósticos opcionales de foco sólo se activan en HomeLab y no guardan consultas.

Build-0098:675 pruebas ejecutadas aprobadas (188Rust/163XCTest/324Swift Testing;7Swift live omitidas y7Rust ignoradas),29 nuevas. `compiled`, fuentes estables durante build, firma estricta y10hashes verificados. CUA sobre preview aislado con mismo código ejecutable: edición/confirmación, selección sin modificar texto, cancelación ⌘K desde isla y página, transferencia por sidebar, Escape doble e historial. Build-0097 comprobó además inversión rápida, Configuración y fullscreen mediante botón;0098 repitió las rutas afectadas por ajustes finales de foco. Ventanas960×680 y1512×949 observadas; pruebas de geometría960/1200/1920. Capturas `builds/macos/build-0098/diagnostics/island-{home,search}.png`.

La app normal0093 quedó esperando llavero en SecItemCopyMatching; no se concedieron permisos ni se alteró la cuenta. La revisión visual usa copia con ID/firma/datos HomeLab separados y búsqueda anónima real. No demuestra cuenta/audio/FPS, comportamiento físico15/26, preferencias reales de accesibilidad, IME humano, VoiceOver completo ni960×640 físicos. El foco vuelve al completarse la desaparición de Spotlight; typing durante esa transición no está garantizado. Fullscreen sin pista no cerró con Escape en0097, sí con botón explícito; ruta previa no modificada. El recorte de Home a960 con sidebar cerrada también aparece en baseline0091 y queda fuera de este rediseño.

## Refinamiento visual solicitado después de build-0098

### Evidencia y diagnóstico

El usuario conserva la dirección Isla única y las animaciones, pero señala posición del historial dentro de sidebar, contenido desalineado en la botonera, desplegable desplazado a la derecha, editor que queda abierto al hacer clic fuera, lupa azul/deformada después de usarla y ausencia de selección por arrastre. Las tres capturas adjuntas motivaron primero planificación y después implementación autorizada. Las pruebas de0098 no cubrían esos defectos; la evidencia nueva se registra en FIX-182.

| Síntoma | Evidencia en código vigente | Certeza / siguiente comprobación |
|---|---|---|
| Historial situado sobre sidebar | `NativeNavigationIslandHeader.layout()` deriva leading de controles de ventana/toggle +12, sin tomar el borde de sidebar | Causa de anclaje confirmada; medir borde exterior real y animación |
| Iconos/títulos no quedan bien dentro del segmento | Slots y lente se calculan manualmente; `NSButton` alterna `imageOnly`/`imageLeading` y título sólo del seleccionado; la lente se anima aparte | Desalineación visible; aislar dibujo real de NSButtonCell, insets y estado durante selección antes de atribuir una causa única |
| Desplegable empieza bajo el texto y excede la isla | `onSearchFrameChanged` informa sólo `bar.field`; overlay usa `field.minX` y ancho independiente hasta440pt | Causa confirmada; falta rectángulo de la isla completa |
| Clic exterior deja editor abierto | Monitor llama `focusChanged(false)` y `cancelPreview()`, conservando `isEditing=true` | Causa confirmada; cambiar transición de presentación, no sólo foco |
| Lupa azul/deformada al regresar | Destino Buscar recibe `.state=.on`; close restaura firstResponder en ese botón; además conviven icono de destino, glyph de editor y botón de consulta durante morph | Hipótesis de conflicto entre selección/highlight/foco y dibujo; comprobar secuencia abrir→cerrar sin cursor encima y con teclado antes de fijar solución |
| No se puede arrastrar selección entre opciones | Cuatro `NavigationIslandDestinationButton: NSButton` independientes; sólo se agregó `keyDown`, no tracking de grupo | Pérdida respecto de `NativeNavigationBar` con NSSegmentedControl confirmada |

### 1. Ubicación y margen común

Mantener Atrás/Adelante dentro de la isla única, pero colocar esa isla fuera del panel de sidebar. Punto de partida **m=12pt**: `island.minY=windowTop+m`, `island.minX=sidebarOuterRect.maxX+m` con sidebar abierta. Tomar el borde exterior de la superficie, no la reserva de contenido: el panel actual mide230pt con inset6, mientras la reserva242 incluye espacio adicional. Usar rectángulos en un mismo sistema de coordenadas de ventana; medir el panel real o compartir su geometría efectiva con el shell, sin replicar números en toolbar.

Con sidebar cerrada, anclar después del conjunto real de controles de ventana/toggle más m, conservando sus acciones y región de arrastre. Interpolar el ancla con el mismo progreso/curva de sidebar; apertura/cierre rápido invierte desde la posición visible. Separar este movimiento del reveal de destinos para no mover historial dos veces. Abrir búsqueda conserva el ancla y altura; sólo se extiende la parte derecha. Mantener margen mínimo hacia las acciones de Inicio, compactación y geometría útil a960pt. Comprobar que el host NSToolbar no omita/recorte la isla al desplazarla; si su viewport es insuficiente, ajustar el host al área efectiva, no pintar fuera de un rect recortado.

### 2. Contenido y estado de la botonera

Usar una única geometría para segmento, superficie de selección, contenido visible y target de interacción. Iconos solos centrados en ambas direcciones; icono+etiqueta tratados como grupo centrado con separación medida y padding simétrico. Mantener36pt de superficie y símbolo14pt como punto de partida; medir el bezel/contenido nativo antes de imponer30pt a un control. Reservar ancho estable para ES/EN y todas las selecciones; truncar/compactar etiqueta antes de invadir el segmento vecino. Alinear en backing pixels y comprobar centros con tolerancia0.5pt, además de capturas reales.

Separar destino seleccionado, segmento bajo el puntero durante tracking, foco de teclado y acción momentánea Buscar. La lupa abre edición; cerrar no debe dejar un highlight azul persistente ni una selección visual huérfana. En ruta Buscar, la consulta compacta representa el estado confirmado. En otras rutas vuelve el destino real anterior. No eliminar el indicador legítimo de foco de teclado para esconder el defecto. Sólo un icono de búsqueda participa visualmente en cada estado; el morph no superpone glyphs, símbolos activos o imágenes alternativas. Mantener identidades/foco de los campos nativos y semántica de accesibilidad.

### 3. Desplegable que abarca la isla completa

Añadir reporte separado `onIslandFrameChanged` de la superficie exterior completa; conservar rect del campo para edición y controles. Calcular overlay con `panel.minX=island.minX`, `panel.width=island.width`, `panel.maxX=island.maxX` y `panel.minY=island.maxY+8pt`: empieza antes de Atrás y termina al borde final del buscador. Es también el centro horizontal de toda la isla. El ancho deja de depender del límite arbitrario440 y del campo interno. Si falta espacio, ajustar la geometría de la isla y el desplegable conjuntamente antes de situarlos.

Panel y cápsula comparten geometría de presentación durante resize/morph, sin salto a coordenadas antiguas ni frames de0. Limitar alto sobre el player y permitir scroll; mantener filas/acciones existentes y ausencia de dim. Invalidar rects al ocultar/desmontar y no aceptar callbacks de una ventana/estado retirado. Proteger isla completa y panel visible en detección de clic exterior; interactuar con recientes/entidades/menús no cierra antes de entregar la acción.

### 4. Salida por clic exterior

El clic fuera de ambas superficies ejecuta cierre de edición y cancelación del preview, guarda borrador/selección y contrae hacia navegación o consulta confirmada. No confirma, no agrega historial/recientes y no cancela resultados completos vigentes. El monitor devuelve el evento; la canción, filtro o control pulsado conserva su acción exactamente una vez. No restaurar foco al botón de origen en este camino: ese comportamiento queda para Escape/cerrar con teclado. Clic dentro del campo/panel no provoca cierre.

Acciones explícitas de shell mantienen su arbitraje: historial cierra y avanza una vez; sidebar termina edición de isla y conserva la transferencia a página cuando corresponde; abrir Spotlight suspende el editor antes de enfocar el modal. Evitar que un mouseDown genérico cierre el estado antes de que esas acciones capturen borrador/selección. Sólo observar eventos de la misma ventana. Escape en dos niveles y ⌘K centrado se conservan.

### 5. Tracking de grupo y selección de macOS27

Preparar primero un ensayo nativo con un solo **NSSegmentedControl**, tracking `.selectOne` y role `.tabs` desde27, tomando `NativeNavigationBar`/`NativePanelSegmentControl` como referencias de interacción. La documentación de Apple confirma que el control agrupa segmentos, permite selección única y distribuye imágenes/etiquetas; el SDK27 confirma role.tabs. La apariencia y el comportamiento de arrastre concretos deben observarse en el mismo contexto de toolbar, no inferirse de la disponibilidad de la API.

Probar control/celda nativos con contenido medido y una sola superficie de la isla. Gate obligatorio: no introducir una segunda cápsula/bezel como en los intentos FIX-175/176. Si ocultar el bezel elimina el tratamiento nativo necesario, evaluar una NSSegmentedCell con dibujo interior adaptado, reteniendo tracking/teclado/AX del control. Sólo si el ensayo demuestra que no conserva el contorno único, usar un NSControl de grupo con tracking explícito de mouseDown/Dragged/Up; no volver a cuatro botones aislados. Registrar cuál variante real se eligió y sus límites, sin afirmar que una lente dibujada sea el efecto nativo27.

Interacción requerida: al mantener pulsado, feedback sigue el segmento bajo el puntero; arrastrar cruza destinos sin ejecutar rutas intermedias. Al soltar dentro, confirmar una sola acción del destino final; al salir y soltar fuera, cancelar/restaurar selección; segmentos disabled/ocultos no reciben acción. Arrastrar a Buscar abre el campo una vez y le entrega foco después de terminar tracking. Resize, apertura de sidebar o desmontaje durante tracking lo cancelan limpiamente. Historial no participa del selector y mantiene su semántica de un paso.

### Orden y aceptación

1. Ensayo nativo del selector/dibujo y medición de márgenes; comprobar las capturas antes de integrar.
2. Unificar geometría y mover historial/isla respecto del borde de sidebar; integrar selector que pase el gate de una superficie.
3. Reportar isla completa y alinear panel; corregir cierre exterior y ciclo de lupa/foco.
4. Probar visualmente estados y secuencias en app/preview de producción; después ejecutar runner y registrar nuevo fix con ID libre entonces. No cerrar por tests de frames solamente.

- [x] Sidebar abierta: isla fuera de panel y márgenes techo/lateral iguales (tolerancia0.5pt); estado cerrado/progreso inverso probados en ventana real y tests.
- [ ] Cada destino ES/EN: icono/etiqueta dentro de selección, centrados; sin recortes ni cambio de ancho al seleccionar, con captura de estado estable y tracking.
- [x] Diez ciclos de apertura/cierre desde Biblioteca/ruta Buscar, más Inicio con Spotlight: borrador conservado, glyph único y sin azul persistente en estados observados; teclado/roles probados.
- [ ] Panel vacío/recientes/consulta/entity/loading: bordes y centro coinciden con isla completa a ventana mínima y amplia, también después de resize.
- [x] Clic físico exterior en espacio vacío/filtro cierra edición y conserva borrador/acción, sin enviar; protección de isla/panel/toggle y passthrough verificados automáticamente. Menús existentes conservados.
- [ ] Arrastre Inicio→Explorar→Biblioteca y reverso, salida/reentrada, soltar fuera, destino disabled y arrastre a Buscar: feedback continuo y sólo una acción final, sin nuevas entradas intermedias de historial.
- [x] Transferencias de selección/foco isla↔página↔Spotlight, Escape doble y fullscreen por botón comprobados; pruebas de generaciones/privacidad anteriores aprobadas.
- [ ] Comprobar reduce motion/transparency y fallback15/26 cuando haya runtime disponible; macOS27 debe tener evidencia real de tracking, no sólo `performClick`.
- [x] Pruebas actualizadas; runner0099, diff, firma/10hashes, FIX-182 y PAR-007/PAR-027 completos; exclusión Windows conservada.

Ámbito final: `NavigationIslandToolbarView.swift`, nuevo `NavigationIslandDestinationControl.swift`, `SideBApp.swift`, `NavigationIslandDismissalMonitor.swift` y sus pruebas. NavigationIslandSearchState, ShellLayout, SearchView/Spotlight y motor conservados sin nuevas fuentes editadas; sin port Windows.

### Cierre del refinamiento — 2026-10-13

Elegido NSSegmentedControl con celda que sólo dibuja interior/lens propio sobre una superficie exterior. Ensayos reprodujeron selección azul y segundo bezel al quitar borde o delegar dibujo; clip vacío + drawSegment obtiene los rects reales de tracking/AX. Native labels vacías y descripciones de símbolos conservan nombres accesibles sin mínimos de ancho distintos. Se conserva super.mouseDown; entrega de acción al finalizar evita navegación por cada segmento cruzado y cancela fuera/resize/movimiento/disabled. No se declara una lente líquida nativa27.

Margen12pt comprobado en ventana real; expansión de sidebar independiente de reveal. Panel sigue rect completo de la isla y deja8pt de separación. Monitor físico cierra edición, devuelve evento y protege toggle para transferencia. Reviewer detectó dos glyphs durante morph: uno montado interpola desde el último segmento al campo y sirve al query compacto. Lupa neutral al cerrar, sin doble símbolo ni estado azul persistente en estados observados.

Runner0099:188Rust+170XCTest+324Swift Testing=682 ejecutadas aprobadas;7Swift live omitidas y7Rust ignoradas. Siete tests nuevos. Focales previas35 aprobadas tras corregir helper de test que intentaba mutar let. Buildcompiled/fuentes estables, firma estricta/10hashes verificados. Revisión independiente sin bloqueantes.

CUA: selector aislado EN con contador de acciones, app de producción en copia HomeLab ES y búsquedas anónimas; drag hacia Biblioteca sin rutas intermedias, canceloutside y drag hacia Buscar; diez ciclos de apertura/cierre conservan draft; clic físico cambia filtro y cierra; panel y márgenes observados a960×680 y1512×949; Escape doble, transferencia física de sidebar con rango, cancelación Spotlight desde página e isla (Inicio, selección probe→probz), fullscreen por botón. Capturas en diagnostics de0099. AXpress virtual no prueba monitor de mouseDown; los casos exteriores se repitieron por coordenadas reales.

Criterios implementados y comprobados: ubicación/margen, cluster centrado, panel completo, cierre físico y acciones intactas, drag/end/cancel y preservación de borrador/selección. Pendientes de QA ampliada: todos los estados visuales ES/EN en app real, reentrada de drag en un solo gesto, cuenta real, IME humano/VoiceOver completo, preferencias físicas15/26 y960×640. No nueva medición FPS/audio ni reproducción. Recorte Home previo a960 no se modifica. La espera de llavero de sesión normal anterior motivó copia diagnóstica con identidad/firma/datos distintos, misma sección de código ejecutable.

## Referencias

- [Apple: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars?changes=la): ubicación y agrupación funcional de historial, destinos y acciones.
- [Linear: UI refresh](https://linear.app/changelog/2026-03-12-ui-refresh): alineación y consistencia de cabeceras, navegación y escala de iconos.
- [Raycast: A fresh look and feel](https://www.raycast.com/blog/a-fresh-look-and-feel): consolidación de acciones y jerarquía visual.
- [Sketch: Toolbar](https://www.sketch.com/docs/interface-and-settings/the-mac-app-interface/the-toolbar/): acciones contextuales.
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views?changes=latest_major): contenedores, identidad y transiciones de efectos coordinados.
- [Apple: NSSegmentedControl](https://developer.apple.com/documentation/appkit/nssegmentedcontrol): control de grupo, segmentos, tamaños, accesibilidad y tracking; no equivale a probar su render en nuestra toolbar.
- [Apple: SwitchTracking](https://developer.apple.com/documentation/appkit/nssegmentedcontrol/switchtracking): selección única y modos momentáneos.
- [Apple: NSControl.ImagePosition](https://developer.apple.com/documentation/appkit/nscontrol/imageposition): distinguir disposición de imagen/texto del rect del segmento.

## Investigación posterior a0099: controles originales y rendimiento

Fecha:2026-10-13. El usuario pide investigar la barra de iOS y su equivalente nativo de Mac y ver referencias antes de otra modificación. Se repartieron lectura del selector/animaciones, API nativa y carga de páginas entre subagentes; el integrador revisó las conclusiones y observó una referencia independiente con CUA. No se modificaron fuentes de producción, core, Windows ni FIXES; no se generó otra build de Side B.

### APIs verificadas y referencia visual

El entorno observado es macOS27.0(26A428), Xcode27.0(27A266a), SDK27.0. **SwiftUI `Picker.tabs`, `NSSegmentedControl.role=.tabs` y `NSToolbarItemGroup.role=.tabs` existen desde macOS27**. `TabsPickerStyle` distingue visualmente navegación por pestañas de selección de valores, y anuncia pestañas a VoiceOver. Esto es una alternativa real al dibujo propio de la celda actual; no implica que la barra de iPhone se traslade con idéntica geometría a Mac. En15/26 se necesita el control estándar disponible y comprobación específica.

Apple muestra dos patrones relacionados: barra de pestañas flotante con búsqueda en iPhone, y toolbar con controles agrupados y búsqueda en Mac. La pestaña de búsqueda puede sustituir la barra en iPhone; en iPad/Mac el patrón de búsqueda dedicada coloca el campo sobre las sugerencias. `TabView.sidebarAdaptable` se presenta como sidebar en Mac; no usarlo como prueba de una barra flotante idéntica a la de iOS. `ControlGroup.navigation` ofrece historial momentáneo nativo desdeMac12. `NSGlassEffectContainerView`(26) coordina material/unión por proximidad, pero no implementa selección ni navegación. `effectIsInteractive`(27) aporta respuesta del vidrio al clic; no sustituye la lente de un control.

Fuentes primarias para ver el comportamiento:

- [UIKit: tab bar y búsqueda,16:17](https://developer.apple.com/videos/play/wwdc2025/284/?time=977), y [navigation bars/toolbars,7:19](https://developer.apple.com/videos/play/wwdc2025/284/?time=439).
- [SwiftUI: búsqueda dedicada y adaptación Mac,13:17](https://developer.apple.com/videos/play/wwdc2025/323/?time=797).
- [AppKit: agrupación original de toolbar,1:48–2:16](https://developer.apple.com/videos/play/wwdc2025/310/?time=108), controles11:10 y vidrio17:30.
- [AppKit27: respuesta interactiva del vidrio,14:24](https://developer.apple.com/videos/play/wwdc2026/289/?time=864).
- [TabsPickerStyle](https://developer.apple.com/documentation/swiftui/tabspickerstyle), [role del grupo de toolbar](https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/role), [ControlGroup.navigation](https://developer.apple.com/documentation/swiftui/controlgroupstyle/navigation), [Glass container](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview).

Referencia independiente conservada en `builds/macos/build-0099/diagnostics/native-navigation-research-2026-10-13/`: fuenteSwift, app`SideBNativeNavigationResearch.app`, metadata`reference.json` y capturas`sideb-native-controls-{183,selected-183}.png`. **No es un nuevo bundle de Side B**. Usa `NSToolbar` real, historial momentáneo, grupo de pestañas conrole.tabs, `NSSearchToolbarItem`, `Picker.tabs`, `Picker.segmented` y `ControlGroup.navigation`. Sin celda, material exterior ni animación propios; sin red/cuenta. Compilación y firma ad hoc verificadas. El integrador comprobó clic enBiblioteca delPicker y arrastre Inicio→Biblioteca de la toolbar, con selección AX y texto de estado correctos. Las capturas muestran el estado final; no prueban FPS ni la transformación de búsqueda de iOS. El aspecto de controles en el contenido tampoco es idéntico a su aspecto dentro deNSToolbar.

### Evidencia del problema de interacción y costo potencial

| Evidencia | Conclusión y límite |
|---|---|
| `NavigationIslandToolbarView.Coordinator.select` exige`revealProgress>=0.999`; el control también queda deshabilitado durante reveal. La transición configurada dura420ms | Un clic durante aparición puede ignorarse. Demora de respuesta explícita, independiente de una caída deFPS |
| `NavigationIslandDestinationCell` reemplaza dibujo de la celda original y mueve una lente con`NSAnimation` propia | El tracking/AX del grupo son nativos, pero la lente y su movimiento no son el render original de Apple |
| `onIslandFrameChanged` publica cada rectángulo cambiante al`@State` de`WindowRootView` | El shell se actualiza durante la geometría animada. Candidato al costo adicional, todavía sin atribución medida de hitches |
| Dos`NSAnimation` independientes fuerzan`layoutSubtreeIfNeeded` para ancho/edición y relayout de superficies | Trabajo repetido potencial. Ya existía en el snapshot previo aFIX-182; no permite atribuir por sí solo una regresión de0098→0099 |
| Snapshot`/tmp/navigation-island-before-182.swift` no tiene callbacks de isla/toggle ni`AnimatablePair`; lente usa animador AppKit | Permite comparación del header anterior al refinamiento. No equivale a un snapshot completo/verificado de las builds0091/0098 |
| `NSAnimation.frameRate` empieza en0. Prueba mínima local de300ms produjo36–37callbacks(~8.3ms de mediana) solicitando0/30/60/120 | Apple no garantiza la frecuencia. Cambiar el número a60 no es un arreglo demostrado; callbacks de un timer vacío no son FPS de Side B |

Se conservan protecciones existentes: títulos cacheados, `lensTarget` evita reiniciar la lente al actualizar, el vidrio no se recrea continuamente y el foco usa token. No atribuir churn a estas partes sin evidencia. [Apple: NSAnimation.frameRate](https://developer.apple.com/documentation/appkit/nsanimation/framerate).

### Carga de páginas y medición pendiente

Las acciones del selector llaman al router de forma síncrona; no se encontró pausa/red previa a enrutar. Repetir Biblioteca cuando ya está seleccionada invalida catálogo y solicita refresh(`SideBApp.navigateMain`, `LibraryView.reloadSelectedPageTab`), mientras entrar desde otro destino usa guards/secciones cargadas. Home carga sólo si sus secciones están vacías; Explore reutiliza caché. Estos comportamientos existen en el código vigente, pero metadata con árbol dirty global no demuestra un cambio exacto de loaders entre0098/0099. No asumir que toda demora al mostrar una página nace en la barra.

La muestra de3s de la app normal0099(PID50211,01:34UY) encontró el hilo principal esperando eventos; sólo descarta bloqueo constante en ese intervalo. No mide navegación, animaciones ni latencia de red. La captura posterior deTimeProfiler sobre la copia aislada(PID57983) se guardó en`/tmp/sideb-0099-sidebar-research.trace`, pero no completó los ciclos previstos: la app anterior había terminado y CUA notificó cambio del usuario en la nueva. Se dejó de enviar acciones. **No usar esta captura como benchmark controlado ni presentar una causa/FPS a partir de ella.**

Siguiente comprobación: mismas ventana, frecuencia de pantalla, fixture y contenido precargado en0091/0098/0099; reposo, sidebar, búsqueda y navegación caliente por separado. Medir clic→ruta, ruta→primer contenido y fin de animación; usarTimeProfiler/SwiftUI/AnimationHitches y contar actualizaciones/layouts del header/shell. Inspeccionar AX fuera del intervalo medido. Las plantillas existen en Xcode local.

### Dirección propuesta para la siguiente iteración

1. Comparar con el usuario el control de pestañas original dentro de toolbar y el patrón de búsqueda de iOS. Conservar ⌘K/Spotlight y semántica de historial.
2. Priorizar celda/lente/interacción original y respuesta inmediata; verificar si una silueta única puede mantenerse sin reemplazar el dibujo del selector ni duplicar superficies. La toolbar nativa agrupa según tipo/función; no prometer automáticamente una sola cápsula con historial+pestañas+búsqueda.
3. Mantener la geometría transitoria dentro del host/overlay aislado, reducir relojes/layouts y evitar publicar al shell por tick. Ensayar y comparar, sin declarar mejora antes de medir.
4. Separar el perfil de carga de contenido del de animaciones y revisar caché/remontaje/refresh únicamente donde la traza lo justifique.

La aprobación visual y la implementación posterior siguen pendientes. El éxito funcional deFIX-182 no cierra esta revisión.

### Demo animada y corrección del usuario

El usuario confirmó el ejemplo de búsqueda de iOS y autorizó una demo animada para ver cómo se integra con Atrás/Adelante. Se creó una app independiente con contenido local, historial real sobre rutas de muestra, campos nativos, Spotlight para⌘K, sidebar, repetición de entrada y movimiento reducido. UsaNSAnimationContext para geometría/fundidos locales; no incorporaNSAnimation timers ni estado del shell por tick. No cambia fuentes de Side B, core o Windows ni genera una nueva build de producción.

Las primeras variantes envolvían el selector original en vidrio, conservando lente/tracking pero mostrando un fondo extra. Buscar estaba como acción separada. El usuario pidió quitar ese fondo e integrar Buscar como cuarta pestaña. El ensayo v5/v6 extendió el fondo del selector sobre la isla y reservó slots para las flechas; el usuario lo rechazó porque seguía gris y cambiaba la interacción de historial. Se descartó como dirección vigente. Una prueba de filtrado AX de v5 ocultó el grupo; no se usa en la variante entregada.

**Variante transparente anterior: v7**, en`builds/macos/build-0099/diagnostics/animated-navigation-demo-2026-10-13/v7/Side B Island Demo.app`. Fuente`NavigationIslandDemo.swift`, metadata`reference.json`, capturas`island-{navigation,final}.png` y recorte`navigation-detail.png`. Recupera composición/NSButtons de historial de v4. El selector tiene cuatro segmentos originales: Inicio, Explorar, Biblioteca, Buscar; seleccionar o arrastrar hasta Buscar abre el editor. `cell.isBordered=false` deja transparentes los destinos, sin subclass, slots de prefijo ni dibujo propio. **Límite observado y comunicado al usuario: AppKit también elimina la lente seleccionada al quitar ese bezel.** No afirmar lente nativa visible en v7; sí conserva tracking/teclado/AX originales.

La investigación de ocho estilos públicos, con y sin contenedor de vidrio, no encontró una variante que quite sólo el fondo y conserve la lente. Laboratorio aislado`/tmp/SideBSelectorStylesLab.app`; el cambio de estilo no resuelve por sí solo esa combinación. El usuario pidió transparencia tras rechazar el fondo extendido; no volver a ese ensayo ni modificar las flechas para resolver el selector.

Compilación Swift27 arm64 conwarnings-as-errors y firma estricta verificadas. CUA v7: cuatro pestañas AX presentes, clic enExplorar, arrastreExplorar→Buscar con foco de campo, escrituraRadio, Escape y Atrás→Inicio en un paso. Captura confirma ausencia de la pastilla gris en destinos. V3 verificó Spotlight con texto propio y cancelación que restauraRadio→Radiohead, zoom1120×780→1512×949 y modo reducido; v4 añadió invalidación de layout durante resize y altura de panel según sugerencias, conservadas en v7. No presentar una captura durante resize del usuario como benchmark; live-resize exhaustivo, VoiceOver/IME humanos y carga de páginas reales siguen pendientes.

**Última variante rechazada: v8.** El usuario adjuntó el laboratorio y eligió el primer `automatic` de la columna izquierda, con la selección visible, descartando la variante sin lente. Se restauró el bezel/celda original y el selector se colocó en un host ordinario, hermano del contenedor de vidrio de la isla, sin ser descendiente deNSGlassEffectView. Un carrier local común mantiene continuidad de entrada/sidebar. El control conserva cuatro pestañas y Atrás/Adelante no cambian. El fondo propio del selector original se conserva; no interpretar nuevamente esta elección como quitar su bezel y perder la marca.

Bundle`builds/macos/build-0099/diagnostics/animated-navigation-demo-2026-10-13/v8/Side B Island Demo.app`; fuente/metadata y capturas en esa carpeta. Swiftwarnings-as-errors y firma estricta verificados. CUA: marca nativa visible enInicio, arrastreInicio→Biblioteca, arrastreBiblioteca→Buscar con foco, escrituraRadio, Escape y Atrás→Inicio con marca restaurada. Captura y recorte`navigation-preview.png` guardados. Demo solamente, sin integración o build nueva de Side B, sin medición de FPS/carga real.

Las demos de esta exploración fueron cerradas y eliminadas al cancelar el diseño en FIX-183. Sus rutas y comprobaciones anteriores son antecedentes, no entregables vigentes.

## Pasos y cierre

- [x] Revisar instrucciones, código vigente y fixes relacionados.
- [x] Observar ambos estados de sidebar en la app abierta y restaurar el original.
- [x] Investigar referencias primarias y preparar tres alternativas.
- [x] Verificar navegación local a detalle, atrás/adelante y sidebar en el prototipo.
- [x] Elegir dirección visual con el usuario: Isla única.
- [x] Planificar aparición conectada, transformación a búsqueda y conservación de ⌘K/Spotlight.
- [x] Preparar preview nativo animado y calibrar forma, tiempos, interacción e inversión de progreso.
- [x] Implementar isla y búsqueda con historial, comandos nativos, propiedad de foco, roles accesibles, hit testing y acciones contextuales.
- [ ] Comprobar tamaño nativo real y variantes de transparencia/movimiento reducido en macOS 15 y APIs disponibles.
- [x] Verificar manualmente ciclos sidebar, Escape en dos niveles, borrador/foco/selección y ⌘K cancelado; cubrir entidades, IME/UTF-16 y estados de presentación con pruebas.
- [ ] Ampliar QA manual a consultas largas/correcciones/loading/error/Play rápido, IME humano y VoiceOver.
- [x] Verificar historial de un paso, cierre de editor al navegar y fullscreen con botón; pruebas de respuestas tardías y reset de cuenta.
- [ ] Comprobar cuenta real, mínimo960×640 físico, ES/EN e inactividad/arrastre reales en sistemas15/26. Ventanas960×680/1512×949 y geometría automatizada comprobadas; no afirmar FPS/audio.
- [x] Ejecutar suites Rust/Swift con skill/runner versionado; conservar todas las builds anteriores.
- [x] Registrar FIX-181 y evaluar PAR-007/PAR-027, manteniendo exclusiones Windows.
- [x] Investigar APIs nativas27 y mostrar referencia original con clic/arrastre después de la crítica a0099.
- [ ] Revisar dirección visual con el usuario a partir de los controles originales y los ejemplos de búsqueda de Apple.
- [ ] Capturar un perfil controlado de animaciones y clic→ruta→contenido; comprobar mejoras antes de otra entrega.
- [ ] Implementar la siguiente iteración y verificar aceptación visual, fluidez y respuesta durante transiciones.

El prototipo de alternativas permanece como referencia de elección. Primera implementación: FIX-181/build0098. Refinamiento: [FIX-182](../../FIXES.md#fix-182), bundle `builds/macos/build-0099/Side B.app` y preview diagnóstico abierto. Versiones anteriores conservadas, sin instalación, publicación ni commit. Sólo documentación modificada después de la compilación final.


## Reinicio completo solicitado el 2026-10-13 — FIX-183

El usuario pidió «nukea todo lo que hicimos, detona totalmente la topnav, vamos de cero». Se retiraron la isla y también las implementaciones visuales anteriores de TopNavigation/History/WindowNavigation/FloatingNavigationCapsule. No se recuperó una barra anterior ni se eligió una alternativa nueva.

WindowRootView ya no guarda geometría o estado de edición de isla, ni publica frames del header, ni monta sugerencias/monitor de cierre, ni transfiere foco/borrador entre topnav/página/Spotlight. SearchView vuelve a un campo estándar siempre visible, conservando el motor y funcionalidades de búsqueda independientes. Spotlight mantiene su restauración normal de foco, sin callback de isla. Sidebar y acciones de Inicio quedan como utilidades separadas; el router y los gestos/menús de historial continúan disponibles.

Se eliminaron doce fuentes exclusivas y siete suites de los controles retirados; se limpiaron las comprobaciones mixtas de localización/presentación/geometría que instanciaban la barra. Se conservaron MainNavigationDestination para SidebarView, geometría de shell/ventana y las pruebas del router/gestos. Ninguna referencia a las implementaciones retiradas permanece en Sources o Tests.

Los prototipos dedicados de apple/prototypes/NativeTopNavTest, .cache/navigation-island-demo-2026-10-13, diagnósticos de demos animadas/referencias originales y laboratorios temporales fueron eliminados. Las builds de producción previas y evidencia funcional de FIX-181/182 permanecen; historial y cambios ajenos no se revierten.

Verificación: parse Swift aprobado; búsqueda de referencias retiradas vacía. Runner detenido a pedido explícito del usuario antes de empaquetar una app. No se harán más builds ni validaciones de UI en esta etapa. Ninguna medición de FPS ni nuevo diseño se declara logrado. Windows y core sin fuentes nuevas modificadas por este reset; PAR-007 conserva su exclusión y registra la retirada Apple, PAR-027 conserva el motor de búsqueda y retira únicamente la integración de isla.


## Nueva prueba independiente: concepto enviado por el usuario —2026-10-13

Después del reset, el usuario suministró código SwiftUI y pidió probarlo. Se preparó `apple/prototypes/ThreeClustersConcept/` fuera de los targets de Side B, con un ejecutable temporal `/tmp/SideBThreeClustersConcept.app`. No se restauró la barra descartada, no se modificó producción y no se ejecutó el runner de Side B.

La prueba reproduce tres cápsulas separadas: historial a la izquierda, Home/New/Library con icono sobre texto en el centro, y búsqueda circular/expandible a la derecha. Altura62pt, slots102×54pt, padding4pt y separación12pt, según el documento. El componente sólo añade metadatos de accesibilidad y disponibilidad26. El host local añade una ventana única, posición arriba/abajo mediante botón/⌘T y Escape. La selección y hover siguen siendo dibujos SwiftUI del concepto; el vidrio lo renderiza glassEffect. No es un selector AppKit original ni provee seguimiento por arrastre entre botones.

Compilación aislada SDK27/target26 conwarnings-as-errors y firma estricta aprobadas. CUA comprobó cambio de destinos, historial Atrás/Adelante, foco inmediato al expandir búsqueda, textoRadiohead y cierre, ambas posiciones, conservación de selección/historial al moverla y scroll detrás del vidrio. Captura en `.cache/three-clusters-concept-2026-10-13/preview.png`. Física26, FPS, VoiceOver humano y resultados de búsqueda reales no comprobados; este ejemplo usa sólo contenido local. No implica elección final o integración.

### Suspensión y retorno a build0091 — FIX-184

El usuario pidió detener el trabajo y volver a build0091. La demo presentó bloqueos repetidos de foco/AutoFill (80/80 muestras del hilo principal en FocusNavigationSequence); cambiar el editor no resolvió todas las interacciones. Prueba suspendida, sin declarar aceptación ni estabilidad.

- [x] Detener demo y trabajo de agentes.
- [x] Recuperar once fuentes/helpers/pruebas de GitHub y restaurar sólo conexiones de navegación en SideBApp.
- [x] Confirmar mismo commit y archivos de navegación sin modificaciones en el manifiesto0091.
- [x] Conservar119 archivos de otros cambios por hash; Root sólo cambió navegación.
- [x] Parse/diffcheck, diez hashes y firma0091 aprobados.
- [x] Abrir0091 y mostrar selector original al cerrar sidebar.
- [x] Registrar FIX-184; rediseño suspendido, sin runner nuevo ni port Windows.
