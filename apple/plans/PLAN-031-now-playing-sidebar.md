# PLAN-031: panel lateral Ahora suena y transición de la barra

- Estado: iteración6/FIX-282 implementada en build0185 Release compiled;855Swift+298Rust aprobadas, firma/10hashes y fuentes estables. Aceptación visual/animaciones pendiente; PAR-046 abierta.
- Fecha: 2026-10-31 (America/Montevideo).
- Objetivo: navegar por Side B con un reproductor lateral derecho como el de la captura; al abrirlo, la barra inferior cede sus controles al panel con una transición reversible, y vuelve al cerrarlo.
- Ámbito inicial: macOS, SwiftUI/AppKit. Windows debe recibir el mismo comportamiento en una etapa posterior, con validación propia. Core Rust protegido, sin cambios previstos.
- Referencia principal: captura del usuario `Captura de pantalla 2026-10-03 a la(s) 02.07.19.png`, adjunta al pedido. Referencias Side B: `AppTheme.swift`, `ShellLayout.swift`, `PlayerBarView.swift` y `FullscreenNowPlayingView.swift` actuales; screenshots del README como apoyo, sin tratarlos como medidas vigentes.
- Antecedentes: FIX-090/095 (geometría y capas), FIX-264/265 (barra y acciones), FIX-270/271 y PLAN-019 (cola continua). El árbol contiene trabajo previo sin guardar: conservarlo y no atribuirlo a este plan.

## Dirección visual

Panel flotante a la derecha, de casi toda la altura útil, independiente de la sidebar izquierda. Se adopta de la captura la jerarquía: selector superior, contenido protagonista y reproductor fijo abajo. Se conserva la identidad Side B: tipografía actual, controles en cápsulas, acento rojo mate para selección/Like y superficies oscuras con borde fino. El azul de la captura procede de esa canción; aquí el tinte debe venir de la carátula, con oscurecimiento suficiente para leer letras y controles. Sin imagen, usar fondo neutro.

Medidas iniciales de diseño, sujetas a medición nativa: ancho ideal 380 pt, rango 350–420 pt; separación exterior 6 pt como el shell, radio inicial 16 pt, padding interior 20 pt. No trasladar píxeles de la captura directamente a puntos. Verificar la cola existente a 350 pt antes de cerrar estas medidas.

En ventana amplia, reservar el ancho del panel y redistribuir sólo el contenido central; no mover sidebar izquierda ni controles de ventana. Determinar viabilidad con ancho real: reserva izquierda + panel + márgenes + mínimo útil de la página. Si no cabe, mantener el panel superpuesto sin comprimir tablas ni expulsar la navegación; cierre explícito/Escape y ninguna capa modal bloqueando toda la página. En poca altura, reducir portada y espacios antes de sacrificar controles: sólo el cuerpo desplaza; cabecera y transporte siguen visibles. No cerrar el panel automáticamente durante resize.

## Funciones y destinos

| Zona | Comportamiento previsto |
|---|---|
| Cabecera | Cerrar/volver a la barra; selector Letras / Ahora suena / Cola; expandir al reproductor completo. Nombres accesibles y tooltips para todos los iconos. |
| Letras | Letras sincronizadas, pulsar una línea para buscar posición cuando haya timing, seguimiento/reanudar y opciones actuales. Preservar originales/nuevas, Genius/anotaciones, estados carga/vacío/error y reintento. No inventar sincronización donde no existe. |
| Ahora suena | Portada protagonista, título y créditos con enlaces existentes; acceso a Relacionado y créditos/detalles actuales. Portada animada sólo si la infraestructura actual la permite, pausada cuando deja de verse. |
| Cola | Reutilizar la cola continua vigente: anteriores/actual/pendientes/recomendaciones, scroll vertical, reproducción, reordenar, quitar, agregar, votos, menús y teclado. Conservar identidad de ocurrencias y contrato de PLAN-018/019. |
| Metadata fija | Título, artista/álbum, Like de Side B, Dislike y menú con las acciones actuales. El corazón conserva nuestra semántica; no sustituirlo por una estrella sólo por la captura. |
| Progreso | Tiempo actual y duración; scrubbing y teclado sobre la misma posición del reproductor. Estado indeterminado si falta duración; sin seek falso. |
| Transporte fijo | Anterior, play/pausa, siguiente, shuffle y repeat con estados distinguibles, incluyendo repetir una. Conservar audio/carga y comandos del reproductor existente. |
| Utilidades | Volumen/mute y salida AirPlay existente en Mac, visibles o en popover accesible según ancho. El icono de dispositivo de la captura no demuestra un protocolo nuevo: no prometer Cast/Connect ni mini ventana nueva. |

Los accesos Letras/Cola de la barra abrirán este panel en la sección pedida. Genius abrirá Letras con Genius seleccionado. La flecha de expandir conservará acceso directo al reproductor completo. El panel recordará su última sección dentro de la sesión; abrirlo sin canción mostrará un vacío útil, sin disparar reproducción. Navegar al artista/álbum no lo cierra.

## Animación de apertura y cierre

Una sola transición gobierna la entrada del panel y la retirada de la barra, con progreso visual compartido y objetivo reversible. Primera propuesta: spring de unos 380 ms, amortiguación alta, sin rebote visible.

- Apertura: la barra baja aproximadamente 20 pt, reduce levemente su escala (1 → 0,97) y se desvanece en el tramo inicial. El panel entra desde la derecha con un recorrido corto de unos 32 pt y opacidad progresiva, mientras la reserva de ancho llega a su destino. Ambos movimientos se solapan suavemente.
- Cierre: misma trayectoria en sentido inverso; el panel se retira y la barra recupera posición, tamaño y opacidad, centrada en el área útil actual.
- Apertura/cierre repetidos: invertir desde la posición animada actual, sin saltos ni colas de callbacks. No encadenar `asyncAfter`, timers ni dos booleanos independientes que puedan mostrar ambas presentaciones por error.
- Un solo destino interactivo para los controles duplicados y una sola representación accesible. Transferir foco a la sección solicitada al abrir, y devolverlo al disparador al cerrar. Desactivar hit testing de la superficie que se retira.
- Con Reducir movimiento: fundido breve sin desplazamiento ni escala. Mantener legibilidad con Reducir transparencia y Aumentar contraste.
- Fullscreen: transición lateral → completo preserva canción, cola, sección y contexto; al contraer vuelve al lateral si ése fue el origen, o a la barra si se abrió directamente desde ella. Escape cierra primero popover/anotación y después la presentación activa.

Evitar un morph literal de todos los controles: el diseño horizontal y el vertical tienen geometrías distintas. La continuidad se consigue con movimiento, color y estado compartidos; no con duplicar motores, cargas o hosts de listas.

## Integración prevista

- Introducir estado de presentación exclusivo (`bar`, `sidebar`, `fullscreen`) y selección lateral independiente de `FullscreenPanel`: Ahora suena no equivale al actual Relacionado. Preservar entradas de menús, atajos y gestos que hoy dependen de `isFullscreenPresented`; migrar de forma coordinada o mantener adaptador derivado, nunca dos fuentes autoritativas.
- `SideBApp.swift`: componer reserva derecha, panel y visibilidad de barra; reconciliar Home Settings (ocupa hoy el borde derecho), Spotlight, navegación y orden de capas. Home Settings y Ahora suena no se superponen en el mismo espacio: abrir uno cierra el otro; Spotlight queda por encima y restaura foco.
- `WindowNavigationToolbarView.swift`: actualizar el anclaje derecho del historial/ajustes junto con la reserva del panel. Hoy se calcula desde `content.bounds.maxX - 18`; sin esta adaptación, los controles superiores pueden quedar sobre la cabecera lateral. Reutilizar el mecanismo de posiciones visibles del compositor al invertir la animación.
- `PlayerViewModel.swift`: dirigir intenciones de abrir/cerrar/expandir y conservar estado del reproductor. No guardar progreso de animación por tick en el modelo de audio.
- Separar «página cubierta por fullscreen» de «superficie de reproducción visible»: el lateral no debe suspender Inicio/Explorar ni desactivar sus interacciones, pero sí debe permitir letras/Genius. Auditar las condiciones actuales de `isFullscreenPresented` para cada responsabilidad.
- Componentes candidatos nuevos: `NowPlayingSidebarView`, `NowPlayingSidebarLayout` y coordinador de presentación; extraer hosts reutilizables de letras/metadata/transporte donde hoy son privados, sin incrustar todo el fullscreen en el panel estrecho.
- `FullscreenNowPlayingView.swift`: compartir controlador de letras y presentación relevante para que lateral ↔ fullscreen no recargue letras, pierda Genius o duplique la suscripción al reloj. Montar un solo host activo de cola/letras, conservando scroll por ocurrencia/documento al transferir.
- Reutilizar `NativeSeparatedQueueView`, `NativeQueueTrackCellView`, menús comunes, `AirPlayButton`, políticas de volumen, caché de imágenes y colores existentes. Reducir efectos costosos al panel y a su carátula; no añadir blur global de Home.
- Evaluar el muestreo cacheado de carátulas de `HomeAmbientBackground.swift` y la política de luminancia de `GeniusAnnotationPalette.swift` como base del tinte, evitando un segundo blur grande. Medir específicamente scroll de Inicio con karaoke activo al lado: el escenario consume recursos de ambas vistas simultáneamente, a diferencia del fullscreen.
- Revisar reservas inferiores de feeds/tablas al retirar la barra: recuperar espacio sin cambiar el ancla de scroll ni provocar saltos. No sustituir todos los insets por una constante sin medir cada contenedor.

## Revisión con Argon High

Consulta de arquitectura y diseño completada el 2026-10-31, sin modificaciones del delegado. Argon inspeccionó el código, pero sus herramientas rechazaron el adjunto por estar fuera de su workspace: no constituye una segunda validación visual de la captura. La referencia visual de este plan sigue siendo la captura proporcionada al integrador.

Se incorporan sus hallazgos sobre anclaje superior derecho, separación entre páginas cubiertas y superficie activa, paleta cacheada, reservas inferiores y coste de Inicio + karaoke. La cabecera nativa de Windows y su botonera derecha requieren su propia reserva; AirPlay es una integración Mac y no debe representarse como un selector disponible en Windows sin implementación.

Se mantiene el ancho inicial de 350–420 pt con fallback superpuesto: las propuestas alternativas de 300–312 pt requieren verificar todas las acciones y letras, no sólo que una cola previa funcione a 320 pt. No se sube el mínimo de ventana ni se colapsa automáticamente la sidebar izquierda. La ventana principal declara actualmente un mínimo de 960 × 640 pt; ese tamaño es un caso obligatorio de comprobación, no evidencia de que dos paneles ya quepan correctamente.

Para Relacionado, preferir un acceso explícito que expanda directamente a la vista existente; no comprimir sus estantes dentro del lateral. El volumen tendrá prioridad visible en el pie cuando quepa; un popover sigue siendo alternativa en medidas reducidas. Mantener un único criterio para Home Settings (exclusión mutua) y para volver de fullscreen (presentación de origen), en vez de combinar variantes incompatibles de la propuesta.

## Etapas y comprobaciones de cierre

- [x] Inspeccionar shell, barra, fullscreen, tokens y antecedentes; formular propuesta basada en la captura.
- [x] Integrar revisión de Argon High, contrastar hallazgos con fuentes y documentar límites/discrepancias.
- [x] Integrar directamente una primera versión nativa revisable de Letras/Ahora suena/Cola a380pt; sustituye la maqueta HTML prevista. Frames nativos verificados a380×628, apariencia/animación en app pendiente.
- [x] Implementar presentación y geometría; comprobar transiciones reversibles, ventanas amplias/estrechas y conflicto con Home Settings/Spotlight antes de conectar contenidos complejos.
- [x] Reutilizar un host común de fullscreen/lateral y conectar acciones existentes; preservar Relacionado, Genius y las operaciones actuales de cola.
- [ ] Probar estados exclusivos, origen/retorno de fullscreen, alternancias rápidas, resize y geometría con/sin sidebar izquierda. Regresiones funcionales: no reiniciar audio ni alterar ocurrencias, buscar posición correctamente y no duplicar solicitudes.
- [ ] Verificar ES/EN, títulos largos, sin canción, sin portada/letras/duración, carga/error, Genius, cola larga, foco/VoiceOver, teclado, scrubbing y preferencias de accesibilidad. Verificar alturas reducidas y ventana mínima real.
- [x] Ejecutar pruebas focales y suite completa Release mediante `sideb-build-macos`: build0175 compiled,803Swift+287Rust aprobadas, firma y10hashes revalidados; fuentes estables durante build.
- [ ] Revisar apariencia y animación en la app nativa y medir rendimiento en escenario real; no afirmar FPS por compilación.
- [x] Registrar FIX-272, build0175 y PAR-046 en registros comunes.
- [ ] Adaptar Windows con los mismos estados/acciones, comprobaciones frontend y validación nativa propia. No declarar paridad cerrada por pruebas Mac.

## Primera implementación

FIX-272 implementa el panel directamente en la app nativa, conservando `FullscreenNowPlayingView` como host de estado y contenidos. No se hizo una maqueta HTML independiente. El pie usa las mismas acciones de `PlayerBarView` en distribución vertical; fullscreen conserva su barra de transporte actual. El control repeat conserva el contrato existente (no se añade un nuevo modo de motor).

El tamaño queda en380pt; en960×640 con sidebar izquierda abierta se superpone, y en ancho suficiente reserva392pt manteniendo480pt de contenido. Las letras arrancan a28pt cuando el primer host abierto es lateral y conservan luego los ajustes del usuario al expandir. El espacio inferior histórico de cada feed se conserva por ahora para evitar alterar sus anclas: requiere medición/QA propia antes de ajustarlo.

Pruebas focales y frames nativos verificados; las capturas bitmap sin ventana no permiten validar fielmente todas las capas AppKit. Quedan pendientes revisión humana de la animación, interacción con sesión/audio reales, VoiceOver completo e Instruments. Registro y port en PAR-046; Windows/core sin cambios de esta entrega.

Intento build0174: conserva diagnóstico del fallo de un test de gestos fullscreen, por falta del marcador `volumeExcluded` al adaptar el canvas. Restaurado sólo para fullscreen; las seis pruebas nuevas del lateral y las287pruebas Rust pasaron. Revalidación específica Release:12pruebas de volumen aprobadas tras la corrección. Build0175 final compiled:272XCTest+531SwiftTesting y287Rust aprobadas, firma y10hashes revalidados, sin cambio de fuentes durante compilación;0174 conserva únicamente diagnóstico.

Entrega: `builds/macos/build-0175/Side B.app`. No se abrió sesión ni se verificó audio real/fluidez visual por esta compilación.


## Iteración 2 — portada inmersiva y corrección de letras

Pedido del usuario del2026-10-31, posterior a la prueba de0175. Esta sección reemplaza, para la siguiente implementación, las decisiones anteriores sobre portada cuadrada con márgenes, botón Info/flip, rueda de volumen sobre portada y acceso a recomendaciones mediante expansión.

### Lectura de las referencias

- Captura1 (`0ed84e23-6c8d-4f1d-9ace-0c9fdbf00bf6`): la portada ocupa todo el ancho del panel y domina la altura inicial. Sus bordes superior e inferior se funden con un fondo de la misma familia de color; la cabecera queda por encima y los controles descansan en una zona legible abajo. No hay marco de tarjeta alrededor de la portada.
- Captura2 (`789686bf-fa54-4cf0-bc18-c4e82b4fd29d`): las recomendaciones aparecen al desplazarse; la portada sigue dando continuidad al fondo y cabecera/controles permanecen disponibles. Artistas y vídeos son ejemplos de secciones reales del proveedor, no una obligación de inventar categorías que Side B no recibe.
- Captura3 (`6f7c064f-6165-43be-87e3-8fc837f04886`): la cola deja espacio al contenido y el pie muestra título/artista/acciones sin miniatura. Conservar nuestra cola continua y sus acciones; no reemplazar su contrato funcional por la lista simplificada del ejemplo.
- Ninguna de estas tres imágenes muestra letras. El descentrado y el salto se registran a partir del reporte del usuario y del código inspeccionado; una captura estática no demuestra la causa temporal.

Interpretación de «cover en fullscreen»: portada inmersiva dentro del panel derecho, manteniendo la navegación de Side B. No implica abrir automáticamente el fullscreen de la ventana ni agrandar toda la app.

### Composición prevista

**Ahora suena.** Un único viewport vertical contiene portada y recomendaciones. La portada inicial llena el ancho útil, sin padding horizontal, borde de tarjeta ni sombra propia. Su altura responde al espacio entre cabecera y controles; el primer bloque ocupa al menos esa altura para que ninguna recomendación asome por defecto, también en ventanas altas y al terminar una carga.

La imagen mantiene su proporción con recorte `aspectFill` centrado, sin deformación. El centro conserva detalle; sólo las zonas superior/inferior se extienden y desenfocan, mediante una copia de menor resolución del mismo artwork y máscaras graduales, hasta mezclarse con la paleta común del panel. Color, imagen y degradados cambian juntos al cambiar de canción; no utilizar un azul fijo ni fundir hacia negro cuando el fondo es de otro tono. El blur no debe afectar texto, transporte ni toda la página de Inicio.

La cabecera se superpone sobre el borde superior del hero, con fondo local suficiente para leer los iconos. El pie permanece fijo. Al bajar, la portada sale del flujo visible y da paso a recomendaciones sobre una base teñida con continuidad de artwork; no se estira su contenido ni se mueve el transporte. Con Reducir transparencia/contraste alto, ofrecer superficie opaca legible; con Reducir movimiento, reducir transiciones decorativas.

**Recomendaciones.** Aparecen debajo del hero únicamente al hacer scroll. Cargar al aproximarse al final del hero, usando contexto/caché/cancelación existentes; que un `LazyVStack` monte una vista por anticipado no basta como señal de visibilidad. No disparar solicitudes por cada pixel ni esperar a que el usuario vea un hueco vacío. Carga, vacío y reintento viven debajo del hero y no aparecen sobre la portada inicial.

Reutilizar los datos y acciones de Relacionado en una composición estrecha, con artistas/álbumes/canciones/vídeos sólo cuando existan datos compatibles. Evitar meter `RecommendedContentView` entero dentro de otro scroll: hoy tiene altura fija y un viewport nativo que ya administra desplazamiento/reciclado. Adaptar el renderer o crear filas/secciones compactas que compartan datos y acciones, bajo un solo dueño del scroll vertical. La reserva de recomendaciones de la cola es un contrato distinto: no promover, agregar ni reproducir nada por visitar este contenido.

Al cambiar de canción, invalidar respuestas viejas, volver al hero y no conservar recomendaciones de la pista anterior. Al alternar pestañas, conservar el desplazamiento de Ahora suena para la misma ocurrencia. Volver al hero no cambia el volumen ni inicia reproducción. Los enlaces a artistas/álbumes y las acciones de pistas conservan sus destinos reales.

**Carátula e interacciones.** Retirar el botón Info y el giro de carátula de la presentación revisada. El código compartido debe impedir estados `flipped` residuales al expandir/contraer; al retirar el flip, mantener Genius, créditos y acciones válidas mediante sus accesos explícitos o menús. Auditar también el botón Info del fullscreen compartido para que la función retirada no reaparezca por otra entrada de la misma carátula.

La rueda sobre la portada pasa a desplazar contenido. Retirar su región de volumen, feedback flotante y arbitraje específico del lateral; mantener slider/mute, AirPlay y la rueda de volumen en la cápsula/slider donde corresponda. Preservar el marcador protector `volumeExcluded` del fullscreen y comprobar que las superficies retenidas detrás no capturen la rueda: fue una regresión detectada durante0174, no se debe reabrir.

**Pie de Letras y Cola.** Ocultar la miniatura y eliminar también su slot y separación. Título, artista/álbum e indicadores aprovechan ese ancho; Like/Dislike/menú conservan alineación y área de interacción. La portada grande sólo corresponde a Ahora suena. Empezar manteniendo la altura del pie para que cambiar de pestaña no mueva el centro de las letras; reducirla después sólo si las medidas y el diseño lo justifican. Mantener metadata, retry, progreso accesible, transporte, volumen y salida disponibles.

### Letras: evidencia y diagnóstico

**Confirmado en el código actual:** ambos renderers calculan el ancho como viewport menos padding lateral y una reserva adicional de48pt en karaoke. A380pt, el padding32 por lado y esa reserva dejan268pt para el texto, con más espacio sobrante a la derecha. La escala de contexto también usa ancla izquierda. La reserva está comentada como protección para el dibujo de palabras: no borrarla sin comprobar glows/lift y el medidor de wrapping.

**Objetivo de geometría:** bloque de texto centrado con márgenes simétricos iniciales de20pt y uso del resto del ancho; versos alineados a la izquierda como en la referencia original, sin una columna angosta desplazada. La línea/grupo activo se centra verticalmente respecto del viewport real de letras, excluyendo cabecera, selector y pie. Separar margen tipográfico de la expansión visual de palabras, que debe resolverse en dibujo/overlay o mediante protección simétrica. Medición, wrapping, traducciones y renderer deben recibir el mismo ancho.

**Hipótesis para el salto, pendientes de reproducción:**

1. Conviven `.scrollPosition(id:, anchor: .center)` para memoria de lectura y `ScrollViewReader.scrollTo` para seguimiento. Confirmar si el ancla retenida compite con la línea activa en un cambio de foco, un seek o un remonte.
2. Cambiar el target pide centrado animado; cambiar geometría/fuente/modo/revisión puede pedir un centrado inmediato. Las revisiones descartan solicitudes diferidas antiguas, pero no equivalen a cancelar una animación ya iniciada. Instrumentar cuál gana en cada transición.
3. `LazyVStack` resuelve alturas de frases partidas/traducciones a medida que se montan. Confirmar si corrige estimaciones durante el centrado y si el ancho actual agrava ese efecto. La escala/blur visual puede acentuar la percepción, pero no es prueba de un cambio de altura de layout.

El antecedente de rendimiento del2026-10-21 ya distinguía centrados repetidos de un salto histórico causado por timestamps casi cero (FIX-234). No atribuir este reporte a aquel fallo ni modificar tiempos del proveedor sin evidencia.

**Corrección prevista:** un coordinador exclusivo de posición con estados seguimiento, lectura manual, seek y restauración. Durante seguimiento, una sola orden por cambio de grupo activo desde la posición actualmente visible; durante lectura manual, el reloj no recentra. «Volver a la línea actual» transfiere el control una vez. Resize/restauración/seek invalidan órdenes viejas y no encadenan un salto instantáneo detrás de la animación. La memoria de lectura sólo restaura cuando corresponde y nunca fuerza otro target durante seguimiento. Mantener identidades por ocurrencia/documento, no volver a montar todo el renderer en cada línea.

La transición de opacidad/escala de las frases no debe alterar la altura medida. Mantener el layout de una frase estable mientras canta; invalidar medidas con ancho/fuente/traducción/documento, no con cada tick. No reemplazar todo por una pila sin virtualización ni reescribir el reloj antes de medir el problema.

### Orden de trabajo y aceptación

- [x] Leer las tres referencias y contrastar geometría, scroll, pie y recomendaciones con las fuentes actuales.
- [ ] Reproducir el salto con una secuencia sintética de líneas cortas/largas, cambios rápidos y seek; registrar target, motivo de centrado, ancla, altura y posición visible antes/durante/después. Distinguir petición duplicada, corrección de altura y fallo de timing. Añadir pruebas observables del caso encontrado.
- [ ] Corregir ancho/centrado y exclusividad del scroll en letras nuevas y clásicas; comprobar seguimiento, pausa, interludios, última línea, lectura manual, reanudar, traducción, zoom y expansión lateral/fullscreen.
- [ ] Separar composición del pie y de la portada respecto de la barra existente; quitar miniatura en Letras/Cola sin hueco ni cambio accidental de acciones.
- [ ] Retirar Info/flip y volumen sobre portada, con regresiones de arbitraje de rueda y protección del fullscreen.
- [ ] Implementar hero inmersivo y blend de ambos bordes; verificar recorte con portadas cuadradas/no cuadradas, claras/oscuras y sin imagen, sin deformación ni costura al color de fondo.
- [ ] Integrar recomendaciones debajo con un único scroll vertical, carga próxima al umbral y respuestas invalidadas por canción/cuenta. Primer frame y posición inicial sin recomendaciones visibles; cabecera/pie fijos durante todo el recorrido.
- [ ] Comprobar380pt a alturas640/800/1000, sidebar izquierda abierta/cerrada, ventana amplia/estrecha, ES/EN, títulos largos y preferencias de accesibilidad. Revisar un recorrido nativo real: las capturas bitmap sin ventana de la primera versión no sirven como única evidencia visual.
- [x] Ejecutar pruebas focales y suite Mac, generar build numerada por la skill habitual, registrar el fix y actualizar PAR-046. Build0176 `compiled`:272XCTest+559SwiftTesting (831Swift) y287Rust aprobadas,10live ignoradas; firma y hashes revalidados, fuentes estables.
- [ ] Medir fluidez con Instruments en un recorrido real y completar la aceptación visual/audio; Windows continúa pendiente de port.

## Iteración 2 — implementación y verificación

La implementación quedó integrada en `NowPlayingSidebarArtwork.swift`, `NowPlayingSidebarRecommendations.swift`, `FullscreenNowPlayingView.swift`, `FullscreenBackdrop.swift` y `Lyrics/LyricsScrollCoordinator.swift`, con localización y pruebas nuevas (`NowPlayingSidebarArtworkTests`, `NowPlayingSidebarRecommendationsTests`, `PlaybackSidebarPaletteEdgeTests`, `LyricsScrollCoordinatorTests`). La portada deja de ser cuadrada con márgenes: el scroll pasa por encima con blur creciente y el fondo toma tinte de las franjas superior e inferior de la carátula. Las recomendaciones viven en el mismo scroll vertical, con cabecera y pie fijos, y el pie de Letras/Cola pierde la miniatura. Se retiraron Info, flip y la rueda de volumen sobre la portada.

Verificación build0176: 272 XCTest + 559 SwiftTesting (831 Swift) y 287 Rust aprobadas, 10 live ignoradas; `BUILD.json: compiled`, firma ad hoc y hashes revalidados, `sourceChangedDuringBuild: false`. Ejecutar la suite en paralelo puede exceder la espera de 2 s de los mocks y dejar el runner idle con una continuación sin reanudar; la corrida oficial en serie no registra fallos. Entrega: `builds/macos/build-0176/Side B.app`. No se abrió sesión ni se verificó audio real, fluidez visual ni VoiceOver por esta compilación. No se editó el core Rust.

## Iteración 3 — video vertical, rendimiento de recomendaciones y blur del hero

Pedido del usuario posterior a build0176 (2026-10-31): usar el video vertical de Apple Music en el hero, eliminar el lag al cargar/desplazar recomendaciones y corregir el blur superior/inferior de la portada, que se ve con una costura dura y una mancha estirada de baja resolución.

### Video vertical 3:4

La página de álbum de Apple Music entrega `videoArtwork.dictionary.motionDetailSquare.video` y `tallVideoArtwork.dictionary.motionDetailTall.video` en `serialized-server-data`. Toxic/In the Zone (`album 251947909`) expone tall 3:4 de hasta 1080×1440, 24 fps, SDR, H.264/HEVC; Eternal Sunshine, After Hours y SOUR también lo tienen. El core actual sólo lee `motionDetailSquare`, `parse_master` rechaza `w != h` y `select_variant` exige `width == height`.

Decisión: agregar `prefer_tall: bool` a `AnimatedArtworkRequest` (UniFFI), actualizar Swift y el DTO Windows con `#[serde(default)]`, parsear ambos masters con fallback cuadrado, separar `request_key` por orientación sin invalidar claves existentes, aceptar tall 3:4 aproximado (`w/h` 0.70–0.80, `w<=1080`, `h<=1440`) y exponer `preferTall`/aspecto resuelto en `AnimatedArtworkView`. El hero usa escenario 3:4 sólo cuando el asset resuelto es tall; si no, conserva el cuadrado.

Ámbito confirmado por el usuario (2026-10-31): el soporte tall queda en el core como capacidad compartida opcional, con default `false`. Windows hoy mantiene su validación cuadrada (`AnimatedArtwork.svelte` exige `videoWidth === videoHeight`) y sólo actualiza el DTO; no se declara que Windows consuma tall hasta que su UI lo adopte. No es un fork Apple ni cambia el comportamiento actual de Windows.

### Recomendaciones

El lag se aborda sin cambiar el contrato de datos: una sola fuente de scroll, carga próxima al umbral con cancelación, identidades estables, filas/secciones diferidas y observación acotada. No duplicar solicitudes por canción/cuenta ni montar todo el feed de Relacionado dentro del scroll del panel.

### Blur del hero

Causas confirmadas en `NowPlayingSidebarArtwork.swift`:

1. `HeroGeometryMetrics.sharpMaskGradient` sólo desvanece izquierda/derecha; el borde superior e inferior de la carátula nítida queda con corte duro. El feather horizontal además está limitado a 32 pt.
2. `lowResBlurredArtwork` usa una miniatura de 96 px, `scaleEffect(1.08)` y `blur(radius: 28)`, insuficiente para Retina; el `aspectRatio(.fill)` dentro del hero alto agranda la carátula cuadrada y la desalinea, generando un “fantasma” gigante.
3. `topTintFade`/`bottomTintFade` se anclan a `heroHeight` y no a los bordes reales de la carátula, así que pueden terminar justo en la costura.

Decisión: fuente de blur de 300 px, radio ~52 pt, overscan ~1.15–1.28 y capa alineada con la carátula (frame cuadrado centrado, sin `aspectRatio(.fill)` sobre el hero alto). Máscara vertical sigmoidal de ~10 stops con feather de ~22% del lado (clamp 72–96 pt) y zona central nítida ≥50%. Tintes anclados a `artworkTopOffset`/`artworkBottomOffset` más el feather. El blur de fondo queda estático/cacheado; al scrollear no se recalcula por frame sobre el `AVPlayerLayer`.

### Cierre pendiente

- [x] Integrar video tall con fallback y regenerar bindings/XCFramework mediante runner oficial (build0178).
- [x] Integrar recomendaciones optimizadas y verificar mediante pruebas que un solo scroll gobierna el panel (build0178).
- [ ] Verificar el blur en app real con portadas claras/oscuras y texto pegado al borde; los tests sólo cubren geometría.
- [x] Core y Swift aprobados en runner oficial Release serial de build0178; Core con windows-bridge también aprobado.
- [x] Generar build0178, registrar FIX-275 y PAR-046 y actualizar este plan.
- [x] Mantener DTO Windows con default false y verificar Core con windows-bridge, sin declarar validación nativa Windows.


## Cierre de iteración 3 — consolidación (FIX-275)

Pedido de implementación y compilación del usuario. Se mantienen el pie actual y el blur provisional; rediseño visual diferido. Fuentes consolidadas: suspensión de video por scroll sin desmontaje, geometría por identidad de asset/álbum/sesión, resolución estática adaptada al tamaño, artistas diferidos y limitados a diez, activación positiva en heroes bajos y retorno de fullscreen según sección activa. Composición lateral y coordinador de scroll extraídos a `Views/PlaybackSidebar/`, conservando el host común. Core filtra orientación en master y variantes cacheadas; tall opcional con fallback cuadrado y DTO Windows predeterminado false. Parser de campos parciales conservado.

- [x] Implementar consolidación y preparar regresiones de suspensión/retorno/umbral/orientación.
- [x] Regenerar bindings mediante el runner oficial y completar pruebas/build0178 Release.
- [ ] Aceptación del usuario en app: video tall, fallback, scroll, letras y cola.
- [ ] Medir Inicio + karaoke y recomendaciones con Instruments; no inferir FPS de tests/build.

No se atribuyen a este cierre los cambios previos de cola, letras o Windows. PAR-046 continúa abierto; UI tall Windows no implementada.


Resultado final de consolidación: build0178 `compiled`;272XCTest+568SwiftTesting y297Rust aprobadas,10live omitidas. Core con windows-bridge:187aprobadas/10live omitidas. Firma ad hoc y10hashes revalidados, fuentes estables durante build.0177 conserva el diagnóstico de las expectativas anteriores de artistas montados en reposo; los tests corregidos verifican diferimiento, montaje tras scroll y restauración de posición. Prueba con video local sintético verifica identidad de AVPlayer al suspender/reanudar y liberación al cerrar. Se añadió fixture de master mixto para filtrar orientación antes de elegir calidad. Se preserva el aspecto resuelto al cambiar de pista dentro del mismo álbum porque el controlador nativo reutiliza ese asset; cambiar álbum/sesión lo invalida.

Entrega: `builds/macos/build-0178/Side B.app`. Pendientes: prueba del usuario con contenido real y medición de rendimiento/VoiceOver. Rediseño del pie y alternativa estética al blur cuando no hay tall quedan diferidos por decisión del usuario. Sin commit/push/publicación.


## Iteración 4 — rediseño tras prueba de0178 (FIX-277)

Reemplaza las decisiones de mantener pie/blur provisional de la iteración3. Referencias del usuario: adjuntos `e8fe3765-fa17-4925-a14a-c65b1171cf6a-3677a16d-60d2-4db0-a39f-44d7e97a670d` (app) y `e8fe3765-fa17-4925-a14a-c65b1171cf6a-5d89b0c2-7567-49d0-8a6e-e2dfcfc00ff1` (objetivo). Tarjeta cuadrada centrada para carátula/motion1:1; video vertical inmersivo desde arriba con máscara nativa inferior y superficie común con controles. Mostrar carátula inmediatamente y sustituir al llegar primer frame: animación elaborada queda para después, no bloquear UI esperando resolver orientación. Mantener Like/Dislike/menú/volumen/AirPlay y semánticas Side B.

- [x] Pie específico adaptativo256–320pt, progreso ancho y tiempos debajo; barra horizontal conservada.
- [x] Dos composiciones de portada, máscara dentro de AVPlayerLayer, preview pequeño derivado una vez del asset y color continuo; pausa/preparación separadas.
- [x] Renderer único NSTableView, artistas NSCollectionView, celdas/acciones reutilizadas y retirada del feed/bridge SwiftUI anterior.
- [x] Endpoints progresivos, revisión de datos, diffs/ancla al insertar, controles de request/cuenta, vacío/error/reintento y conservación de hover/refresh.
- [x] Regresiones focales de viewport, payload10000, identidad, scroll, preparación pausada, cancelación y presentación por formato.
- [x] Suite completa y build0181 Release mediante runner oficial;840Swift+298Rust aprobadas,10live omitidas, firma/10hashes y fuentes estables verificadas.
- [x] Revisión parcial en app nueva: tarjeta cuadrada centrada, pie más alto, tiempos debajo y fondo cromático continuo; fuentes de letras preservadas y adaptador probado.
- [ ] Revisión física completa: video vertical, mínimo960×640, scroll/recomendaciones, selector de fuentes y audio/VoiceOver; interacción automatizada de pestañas alcanzó timeout sin demostrar un bloqueo de la app.
- [ ] Comparación controlada de rendimiento en mismo Mac/escenario/build; trazas0178 no bastan para afirmar FPS ni ausencia de hitches.
- [ ] Aceptación del usuario y rediseño posterior de la animación de sustitución.

La tarea fue pausada por el usuario y retomada; no hay commit/push. FIX-276 (fuentes de letras) se conserva como trabajo concurrente terminado por otro chat. PAR-046 sigue abierto; esta etapa no modifica core ni UI Windows.


Entrega de iteración4: `builds/macos/build-0181/Side B.app`, `BUILD.json: compiled`, fuente estable durante build.0179 conserva crash del fixture sin puntero Rust al no interceptar el nuevo setSetting de FIX-276; se corrige sólo el mock y se prueba la fuente auto.0180 pasa840Swift+298Rust pero frena el empaquetado por catálogo generado desactualizado.823claves ES/EN regeneradas/verificadas y0181 cierra toda la secuencia. Sin modificaciones nuevas de core en esta iteración, commit, push ni publicación. La animación elaborada de reemplazo de carátula por video permanece diferida por decisión del usuario.

## Revisión posterior a build0181 — fullscreen y cierre lateral

- Restaurar Info y reverso de portada exclusivamente en fullscreen desde la implementación anterior.
- Corregir origen del foreground con sidebar de navegación abierta (evitar centrado adicional del canvas reducido).
- Entrada a Letras vuelve a seguimiento automático; cambios de renderer/documento dentro de la visita conservan lectura manual.
- Diseño lateral solicitado: título grande bajo portada cuadrada, transporte mayor, tarjeta con miniatura/título/artista/álbum sobre progreso en Letras. Distribución de Like/Dislike/menú consultada al usuario antes del cierre visual.
- Estado: FIX-278 implementa restauración y seguimiento; pruebas focales aprobadas antes del ajuste final de altura. El usuario pidió ejemplos visuales antes de cerrar distribución; tres variantes en work/player-ui-options/options.html. Sin nueva build; revalidación de UI/altura y entrega pendientes.

## Iteración 5 — diseño aprobado y regresiones de build0181

Decisión del usuario: `work/player-ui-options/selected-layout.html` y captura George Michael aprobados. Portada y metadata forman un bloque, con16pt de separación, título grande y artista/álbum debajo; corazón/menú a la derecha. Letras muestra la misma metadata sobre el progreso, sin miniatura ni tarjeta. Dislike permanece accesible desde el menú. Controles laterales grandes; barra horizontal conserva su distribución.

Plan de implementación:

1. [x] Metadata lateral compartida, sin observar el reloj; título/artist links/álbum/rating, corazón/menú, errores/retry y accesibilidad.
2. [x] Reservar metadata en la geometría de portada cuadrada. Mostrarla en una única celda hero SwiftUI dentro del viewport nativo para que los controles reciban clics y scroll sin introducir un segundo viewport ni tocar el ciclo del video. Para portrait, ubicarla sobre la zona inferior difuminada. Portada/video se mantienen en su host persistente.
3. [x] Pie adaptativo: controles solos en Ahora suena; metadata sobre progreso en Letras/Cola. Conservar botones de reproducción ampliados, volumen y AirPlay.
4. [x] Verificar Info/reverso y centrado fullscreen restaurados por FIX-278; seguimiento automático al volver a Letras preservando lectura manual dentro de una visita y fuentes FIX-276.
5. [x] Pruebas de geometría, acciones/viewport y seguimiento; suite/build oficial numerada con sideb-build-macos; registrar resultados y límites sin afirmar audio/FPS/VoiceOver.

Ámbito Apple. Core y Windows no se modifican; PAR-046 sigue abierta. Conservar trabajo previo sin commit/push. La animación elaborada de cuadrado a portrait permanece diferida.

Cierre técnico de iteración5: build0183,841Swift+298Rust aprobadas,10live omitidas,823claves verificadas, firma/10hashes correctos y fuentes estables.0182 se conserva como intermedia; corrección final de safe area/insets nativos en0183. Pruebas de restauración fullscreen y seguimiento aprobadas; QA física completa pendiente. Sin commit/push.

## Feedback del01/11 — distribución vertical

Usuario considera aceptable portrait, pero ve demasiado vacío con portada cuadrada. Pide controles aún mayores y propuestas para ocupar el espacio. Mantener portada/título unidos16pt y corazón a la derecha. Evaluar agrupación más compacta de portada/datos/progreso/transporte y un bloque «A continuación» con1–2entradas existentes de la cola, sólo si hay altura suficiente. Es propuesta, no implementación aprobada todavía. Evitar otra carga de recomendaciones o un segundo reloj/render de letras sólo para llenar espacio.

## Iteración 6 — composición aprobada, capas fijas y transiciones

Estado: implementación en curso, 2026-11-01. El usuario aprobó `work/player-ui-options/space-and-queue.html` y pidió corregir que artista/álbum se desplazan con recomendaciones. Esta decisión reemplaza explícitamente la fila hero de metadata de iteración5: portada y metadata quedan ancladas detrás del feed. La build0183 sigue siendo la última compilada de este hilo; las fuentes de esta iteración aún no están verificadas.

### Composición y contratos

- Cuadrada: portada íntegra redondeada, título a16pt con corazón/menú, progreso cercano y transporte mayor (Play78pt, saltos alrededor32pt). A continuación muestra hasta dos ocurrencias siguientes de la cola ya existente, debajo del transporte y encima del volumen. No añade fetch, reproducción ni una copia completa de la cola por tick.
- Portrait: conserva video inmersivo y metadata inferior. No muestra A continuación; la orientación proviene del asset listo existente. No deducir formato por título/álbum ni demorar carátula estática esperando la red.
- Altura reducida: retirar primero A continuación, conservar controles y metadata legibles. Letras/Cola mantienen metadata sin miniatura sobre progreso.
- Recomendaciones: viewport/celdas nativos conservados. Portada y metadata fijas; feed se desplaza por delante con blur/tinte que preserve contraste. Material acotado al área cubierta, sin capturas por frame ni segundo blur costoso sobre video. Reduce Transparency/contraste usan superficie opaca. Clics de metadata y scroll sobre ella deben conservarse.
- Botón de apertura: independiente a la derecha de la barra inferior (interpretación comunicada de «barra de navegación»), centrado verticalmente en sus74pt, margen derecho20pt igual al inferior. Mantener centrado sobre contenido y evitar solapamientos en ventanas estrechas. Retirar sólo el acceso duplicado dentro de la barra.

### Plan de movimiento

- Abrir: barra pierde opacidad y baja hasta12pt durante unos120ms; panel entra desde la derecha hasta24pt y gana opacidad durante260–320ms, sin rebote. Cierre inverso. Un solo estado autoritativo de reproducción; presentación transitoria cancelable/reversible.
- Alternar formato: A continuación hace fade de unos180ms y desplazamiento máximo8pt; altura se ajusta coordinadamente. No recrear AVPlayer ni animar la resolución de imágenes/fetches. Una sola geometría entre hero y pie.
- Reducir movimiento: sólo fundidos cortos. No capturar eventos/foco en superficies invisibles, ni producir anuncios AX duplicados.
- Reentrada, doble clic rápido, cambio a fullscreen/regreso y resize deben converger al estado actual sin timers obsoletos. No prolongar red/video oculto para sostener una animación.

### Reparto y cierre

- [x] Subagente6.1: hero/metadata anclados, capa de recomendaciones y geometría de escena.
- [x] Subagente6.1: pie, preview de cola y política por altura/formato; retirar botón interno.
- [x] Subagente6.1: botón exterior y animación coordinada del shell.
- [x] Integrador: revisar contratos, recursos/identidades, gestos/AX y preservar fullscreen/fuentes de letras. Registrar causa de regresión de metadata sin atribuir cambios ajenos.
- [x] Pruebas focales de capas/hit testing/cola/estado/layout; suite y build oficial una vez finalizadas las escrituras concurrentes.
- [x] Registrar FIX nuevo y PAR-046; entregar artefacto y límites de QA real. Sin afirmar FPS/audio/VoiceOver por compilar. No commit/push; core/Windows fuera de esta implementación Apple.

Cierre técnico de iteración6: integración de tres subagentes6.1 revisada por root. Build0184 conserva fallo inicial del fixture de volumen fullscreen; corregido montaje inicial sin task diferido. Build0185 compiled con855Swift+298Rust,10live omitidas,827claves, firma/10hashes correctos y fuentes estables. Metadata fija/material, preview de cola, botón exterior y transiciones implementados. Checklist de implementación/integración y suite completado; QA física del blur, animaciones/reversión rápida, audio/FPS/VoiceOver pendiente. Sin commit/push.

- [x] FIX-291: alinear la distancia vertical entre la barra de progreso y los controles de transporte en portada estática cuadrada con la distancia del modo portrait animado, sin mover controles, cola ni volumen. Build oficial Release `build-0201` (`Side B.app`) compilada y empaquetada con `status: compiled`.

## Auditoría de rendimiento (FIX-294, 2026-11-08)

Revisión del conjunto lateral tras build-0217. Corregidos por código: sombra del panel sobre contenido vivo, trabajo por tick en `layoutHeroLayers`, reevaluación a 10 Hz de las letras clásicas y peticiones de letras repetidas. Suite completa (599) aprobada.

- [ ] Medir con Instruments (Animation Hitches, Core Animation) apertura/cierre, scroll de recomendaciones y letras karaoke con el panel abierto; no se afirma FPS.
- [ ] Decidir si animar la reserva de ancho de la página (hoy salta) midiendo el coste de relayout en Inicio.
- [ ] Revisión visual en app real de los puntos pendientes de iteraciones 4–6.
