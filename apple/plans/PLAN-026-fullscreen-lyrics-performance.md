# PLAN-026 — Rendimiento de Fullscreen y Letras: plan consolidado

- Fecha: 2026-10-21, America/Montevideo.
- Estado: consolidación completada y primera implementación de Etapas 2A/3 entregada en FIX-236/build0150 Release. Pruebas aprobadas; aceptación de FPS y comparación posterior pendientes por espera del Llavero y bloqueo de SecurityAgent en la herramienta. [Resultados, baseline y límites](research/LYRICS-PLAN026-RESULTS-2026-10-21.md).
- Objetivo principal aclarado por el usuario: corregir la pérdida sostenida de FPS y los tirones al desplazar Letras, incluso con la letra ya cargada. Conservar sincronización, diseño, voces, accesibilidad y estado de navegación. La demora inicial de carga queda como trabajo secundario separado.
- Pedido vigente: implementar el plan desde el 21/10 a las 03:50 America/Montevideo, con subagentes Luna/Sol medio, revisión del integrador y medición antes/después. Objetivo: lag de FPS al scrollear siempre, no sólo al abrir Letras o cambiar de frase. Se distingue código implementado de rendimiento aceptado.
- Base de la consolidación original: fuentes de build 0146 Release, versión 1.2.6/build 19, checkout 907ac01 con cambios locales previos. La ejecución posterior usa baseline 0147 y entrega 0150; detalle abajo.
- Fuentes: borrador PLAN-026 de Gemini (`implementation_plan.md`) y [auditoría de Codex](research/LYRICS-PERFORMANCE-2026-10-21.md). Ambos originales se conservan sin modificar; copia exacta y huellas en `.cache/lyrics-performance-consolidation-2026-10-21/`, ignorada por Git.
- Antecedente funcional: [PLAN-025](PLAN-025-word-synced-lyrics.md), FIX-228 a234, PAR-037/038. FIX-233/234 ya implementan la coordinación de seek y la conversión numérica; se verifican como regresión, sin presentarlos como trabajo nuevo de rendimiento.
- Límite de evidencia actualizado: baseline de CPU real sobre el bundle0147 intacto, con documento cargado y scroll continuo pausado/reproduciendo; microbenchmarks y paridad visual aislada antes/después. No hay frames presentados válidos ni comparación de CPU posterior de0150: Computer Use devuelve timeouts también en Finder. No se asume aceptación del usuario ni se equiparan tests/CPU con FPS. La baseline válida se obtuvo después de iniciar ediciones de fuentes, sobre el ejecutable0147 sin recompilar; las primeras capturas se descartaron.
- Fuera de alcance: optimizar Recomendados, cambiar proveedores por otros nuevos, sustituir el motor de audio, publicar, modificar preferencias del usuario o hacer un port visual Windows. Una eventual corrección de red/core debe justificar su alcance compartido.

## Prioridad corregida: FPS durante scroll continuo

El síntoma que se busca resolver es **pérdida de fluidez durante todo el desplazamiento de Letras**, tanto manual como de seguimiento, con el contenido ya cargado. Abrir más rápido, reducir consultas o corregir el destino de un clic no constituye por sí mismo una solución de ese fallo.

Orden de ejecución propuesto: **Etapa 1 → Etapa 2A junto con Etapa 3 → Etapa 4 según las trazas**. La Etapa 2B de red/carga queda aplazada respecto de este objetivo y no cuenta como mejora de FPS.

- Medir primero30–60s de scroll manual continuo arriba/abajo sobre el mismo documento y la misma escena, con caché caliente y carga de contenido terminada. Registrar periodos estables, no sólo aparición inicial o cambios de verso.
- Repetir con la canción pausada y reproduciendo. Si el scroll sigue mal pausado con texto presente, investigar filas/contexto, montaje de vistas, layout y composición sin atribuirlo automáticamente al Timer del karaoke.
- Priorizar el coste de las filas visibles/contextuales que entran y salen del viewport, su texto atribuido, renderer inactivo, blur/máscaras y reutilización de layout. Después separar el coste adicional de palabras activas, efectos y actualizaciones del reloj.
- Comparar clásico/Lectura/Karaoke, sidebar abierta/cerrada quieta y página de fondo, manteniendo fuente/ancho/contenido comparables cuando la prueba lo permita. La animación de apertura de sidebar se mide por separado: no explica por sí sola el lag sostenido al scrollear con ella quieta.
- Usar tiempos de frame presentados, hitches, P95/P99 y trabajo de main/layout/composición. Los intervalos de Timer, tests y snapshots aislados no sustituyen FPS de la app durante un gesto real; no consultar AX continuamente mientras se mide.
- Criterio de cierre: scroll continuo claramente más fluido y mejora instrumental reproducible frente a la baseline, en pausa y reproducción, sin perder seguimiento, identidad de frases, voces o estado. Una búsqueda más rápida o un seek correcto no cierra esta prioridad.

## 1. En qué coinciden y qué aporta cada documento

Coinciden en que Letras no es una pantalla de texto estático: hay actualizaciones de audio, texto enriquecido, composición gráfica y vistas/servicios retenidos. Ambos señalan composición y geometría por palabra, efectos de contexto, observadores de tiempo solapados, reverso de información montado y Genius automático. Coinciden también en que los perfiles antiguos de reposo/Cola vacía no prueban el comportamiento de Letras reproduciendo audio.

Gemini aporta una propuesta más concreta para aislar las lecturas frecuentes del panel clásico y de la barra, agrupar la distancia visual de las filas y experimentar con la composición del fondo. Codex añade la distinción entre demora de red y lag de dibujo, carga clásica/experimental duplicable, respaldo disponible que se entrega tarde, cancelación que no llega a Rust, actividad de sidebar y microbenchmarks reproducibles.

La consolidación incorpora ambas aportaciones, corrigiendo afirmaciones que exceden la evidencia o describen APIs/constantes que ya no corresponden al código.

| Tema | Comparación contra código actual | Decisión consolidada |
|---|---|---|
| Frecuencia alta en panel clásico y barra | Gemini detecta lecturas que el reporte anterior no desarrolló: `nativeLyricsPanel` lee tiempo dentro de un helper de la escena; la barra construye contenido con `formattedElapsed` y progreso | Incorporar hosts pequeños y medir su alcance real de invalidación. No prometer0 evaluaciones de toda la escena ni que todos los hijos se redibujen10 veces/s |
| Lectura `currentTime > 3` del botón Anterior | Está en la acción del botón, no en la construcción de su label/body | No contar esa lectura como dependencia de dibujo por tick |
| Texto compuesto y geometría | Ambos detectan reconstrucción de atributos, diccionarios, ordenación y comparación de anclas por renglón | Prioridad alta: reutilizar la parte estática; conservar Unicode, wrapping y tiempos reales |
| Filas contextuales con renderer | Las filas word-timed montadas usan renderer aun inactivas, pero están en `LazyVStack`; no se demostró que todas las filas vivan a la vez | Probar texto simple para contexto con geometría idéntica. No presupuestar80 superficies ni limitar el karaoke a una única voz: puede haber voces simultáneas |
| Distancia visual | Gemini propone cubetas, aporte útil. En el código actual el blur satura desde distancia 3 y la opacidad contextual normal es0,40; no hay opacidad 0,22 por distancia | Derivar una clave visual saturada y comparar filas según sus entradas reales. No reutilizar constantes desactualizadas ni prometer coste cero por `Equatable` |
| Sombras por palabra | El renderer dibuja base/relleno, pero `wordEffect` devuelve identidad fuera del intervalo de esa palabra; el brillo sólo se añade si glowOpacity>0 | Descartar el cálculo de600 sombras/s por diez palabras ya cantadas. Agrupar efectos sólo si se conserva el comportamiento por palabra/voz |
| Timer, observer periódico y fronteras | Son mecanismos solapados, pero hay un observador de fronteras con un array de tiempos deduplicados; no cientos de observadores independientes | Contar callbacks reales y coalescer con cuidado. No eliminar fronteras de palabra sin preservar despertares tras gaps y sílabas cortas |
| Blur del fondo y composición | Ambos son candidatos gráficos. Gemini afirma raster completo por tick y coste casi cero al precalcularlo; eso no está medido | Añadir un experimento A/B. No equiparar `compositingGroup` a `drawingGroup`, ni garantizar identidad visual con un bitmap de 160 × 160 |
| Páginas de fondo | El host seleccionado puede seguir montado y no ocultarse en su raíz. Pero `NativeTrackTableView.updateNSView` sí oculta su scroll y retorna al recibir actividadfalse | Corregir la afirmación de que esas tablas siguen normalmente activas bajo fullscreen. Auditar consumidores restantes antes de añadir un nuevo mecanismo de ocultación |
| Sidebar | El reporte de Codex la estudia: sigue montada cerrada y no recibe suspensión de imágenes; usa colecciones lazy | Incorporar actividad explícita y medición, conservando colección/scroll. No atribuirle el lag sostenido sin perfilado |
| Carga de letras | Codex demuestra dos rutas independientes, cascadas y respaldo tardío; Gemini se concentra en dibujo | Añadir una línea de trabajo completa de carga/red, distinta del renderer |
| Scroll y `LazyVStack` | Gemini atribuye saltos a alturas estimadas y propone reemplazo general. Sigue siendo una hipótesis; el bug que mandaba al final se explicó por conversión de tiempos | Comparar contenedores con geometría medida y letras pequeñas/grandes. El parser permite hasta 5000 líneas; no sustituirlo todo a ciegas |
| Seek y sincronización | Gemini los incorpora como acciones; ya hay implementación y tests en0146 | Mantenerlos como invariantes/regresiones, con aceptación manual a cargo del usuario |

## 2. Mapa de trabajo y evidencia actual

### A. Tiempo hasta el primer texto

En cada reproducción `PlayerViewModel` inicia la carga clásica. Al abrir el experimento se activa otro fetch, con caché y API propias. Si ambas rutas fallan en caché pueden consultar los mismos servicios sin compartir petición en vuelo.

La carga clásica consulta `next()` de YouTube antes de Boidu y puede continuar por varios proveedores. La experimental consulta Boidu y luego LRCLIB, con límites de 8 s y 5 s. Su respaldo clásico se lee antes de la red, pero se devuelve después de intentar fuentes frescas. Esos 13 s son presupuestos de petición, no latencia observada ni duración de cada canción.

El controller descarta resultados antiguos correctamente, pero la cancelación de Swift no está conectada a cancelación del futuro Rust en el bridge generado. Cambios de metadata provisional pueden iniciar otra petición y otra clave de caché. La solución debe coordinar carga, visibilidad y calidad sin eliminar la comparación entre panel clásico y experimento.

Evidencia: [PlayerViewModel](../Sources/SideB/ViewModels/PlayerViewModel.swift), líneas885–897 y1249–1284; [controller](../Sources/SideB/ViewModels/ExperimentalLyricsController.swift), líneas73–164; [lyrics clásico](../../core/crates/sideb-core/src/lyrics.rs), líneas126–308; [karaoke](../../core/crates/sideb-core/src/lyrics/karaoke.rs), líneas145–205; [bridge](../SideBCore/Sources/SideBCore/sideb_core.swift), líneas7095–7123.

### B. Coste del panel clásico, barra y escena

El panel clásico se construye con `currentTime` desde un helper de `FullscreenNowPlayingView`; recibe tiempo cambiante, busca foco y crea un array enumerado para un `VStack`. La barra también combina reloj/progreso y controles en su construcción. Aislar esas lecturas en vistas dedicadas es una propuesta razonable de Gemini que se incorpora como prioridad.

Hay que distinguir leer una propiedad, evaluar un body, actualizar un hijo y rasterizar una capa: no son el mismo evento. SwiftUI puede conservar subárboles o seguir dependencias dentro de closures de contenedores. Los conteos exactos deben registrarse con instrumentos o un harness de diagnóstico, no deducirse de `@Bindable`. Tampoco se puede asegurar 0 updates en Cola/Relacionado: siguen existiendo cambios de pista, playback, metadata, cuenta y geometría.

Propuesta: host clásico que observe reloj y publique/pase foco estable al contenido; subvistas de progreso/tiempos de barra; acciones de transporte conservadas. Extraer una propiedad helper no basta: deben existir límites de vistas y dependencias medibles.

Evidencia: [FullscreenNowPlayingView](../Sources/SideB/Views/Fullscreen/FullscreenNowPlayingView.swift), líneas712–729 y778–918; [PlayerBarView](../Sources/SideB/Views/Components/PlayerBarView.swift), líneas26–74,87–133 y153–169. El macro Observable limita dependencias según las lecturas; [Apple explica este modelo y los costes por evaluación](https://developer.apple.com/videos/play/wwdc2023/10160/).

### C. Coste del karaoke y sus filas

La parte costosa candidata es la ruta rica: composición de `Text` al evaluar el body y cálculo de geometría al llamar a `draw`. Para filas activas se dibujan base y relleno; el segmento parcial usa una capa con gradiente y máscara. Hay blur/escala de contexto, máscara de scroll y animaciones al cambiar foco.

La comparación entre palabras puede ser cuadrática por renglón visual; no lo es respecto a toda la canción. Guardar geometría exige una clave correcta por contenido, fuente, ancho, dirección y demás inputs de layout. Reemplazarlo por una pasada lineal sin respetar fragments, RTL y palabras que cruzan renglones puede romper el dibujo.

El padre experimental no lee `positionMS` directamente: las filas activas/enfocadas lo hacen. No hace falta reconstruir desde cero esa separación. Sí quedan casos evitables: la última frase enfocada puede seguir suscrita durante gaps/outro; scroll manual no detiene el pulso aunque la frase quede fuera de vista; el montaje calcula secuencias/esperas varias veces; distance cambia aunque su resultado visual ya esté saturado.

Contexto simple es una prueba prometedora: mantener fuente, tracking, saltos, traducción, padding y alturas cuando una fila cambia de renderer. Cualquier fila vocal simultánea con tiempos propios conserva su animación, no sólo la voz principal. Agrupar glow requiere equivalencia de efectos: no se ilumina toda la frase con el brillo de la palabra actual.

Evidencia: [panel](../Sources/SideB/Views/Fullscreen/Lyrics/ExperimentalLyricsPanel.swift), líneas27–33,136–180,248–303 y350–403; [renderer](../Sources/SideB/Views/Fullscreen/Lyrics/ExperimentalKaraokeText.swift), líneas20–49,69–126 y149–194; [estilo](../Sources/SideB/Views/Fullscreen/Lyrics/ExperimentalLyricsStyle.swift), líneas30–55 y65–97.

### D. Relojes, fronteras y seguimiento

El audio y el panel tienen observers periódicos de 0,1 s; el karaoke añade un pulso de 60 Hz mientras cambia una palabra con ventana visible,30 Hz en ahorro/esperas. Además registra un array de tiempos únicos para un único boundary observer. Se pueden solapar llamadas a sample, pero registrar800 tiempos no crea800 timers ni800 callbacks por frame. [AVPlayer llama al bloque al atravesar los tiempos registrados](https://developer.apple.com/documentation/avfoundation/avplayer/addboundarytimeobserver%28fortimes%3Aqueue%3Ausing%3A%29).

Quitar todas las fronteras de palabra puede hacer perder segmentos breves entre dos muestras periódicas o no despertar el pulso después de un hueco sin línea nueva. La optimización debe preservar esos casos, pausas, buffering, offset, seeks y callbacks obsoletos.

Hay centrado inmediato al clicar y otro posible al cambiar foco; las revisiones cancelan solicitudes diferidas anteriores, no necesariamente la animación ya iniciada. También hay transiciones de contexto/scroll de 0,788 s. Separar duración deliberada de animación, pérdida de frames, error de destino y reflow. No congelar el tiempo musical para solucionar scroll manual: éste debe suspender el seguimiento, conservando el audio y el relleno de voces visibles.

Evidencia: [clock](../Sources/SideB/Views/Fullscreen/Lyrics/ExperimentalLyricsClock.swift), líneas33–69 y146–208; [panel](../Sources/SideB/Views/Fullscreen/Lyrics/ExperimentalLyricsPanel.swift), líneas196–215,248–283 y305–328.

### E. Fondo, información, sidebar y páginas retenidas

- Fullscreen conserva carátula grande, backdrop de imagen/blur 75, barra flotante y reverso de información oculto con opacidad/rotación. Retener el árbol del reverso no prueba que se rasterice completo estando transparente.
- El backdrop es estático por pista, pero no se midió cuánto trabajo reutiliza el compositor. Un preblur de baja resolución puede ahorrar trabajo; debe conservar escala del radio, crop, zoom 1,4, color, bordes y resize.160 × 160 es una variante para comparar, no garantía de resultado100 % idéntico ni GPU cero.
- `compositingGroup()` agrupa cómo se aplican efectos. No es sinónimo de una imagen offscreen nueva a tamaño ventana en cada tick. Apple documenta por separado [compositingGroup](https://developer.apple.com/documentation/swiftui/view/compositinggroup%28%29) y [drawingGroup](https://developer.apple.com/documentation/swiftui/view/drawinggroup%28opaque%3Acolormode%3A%29). Retirarlo puede cambiar opacidades, mezclas o transiciones: se prueba, no se borra por una cuenta hipotética de filtros.
- La sidebar sigue montada cerrada y no suspende sus imágenes por visibilidad. Usa LazyVStack/LazyVGrid y tarjetas equatable; no se probó que monte toda la biblioteca. Su animación cambia el ancho disponible y puede generar nuevo wrapping/arte según sus límites.
- Inicio tiene suspensión de feed, saludo y fondo ambiental al ser cubierto. Las tablas nativas de detalle también ocultan `NSScrollView` y retornan en update al recibir actividadfalse. El host superior retenido puede seguir presente y algunas cargas globales pueden finalizar: montado, oculto y activo son estados distintos.
- Genius puede consultar caché y programar datos automáticamente aproximadamente 1 s después de solicitar play. El setting ya representa una preferencia: separar caché, metadata y precarga de anotaciones/letra sin desactivar silenciosamente lo elegido por el usuario.
- Recomendados se desmonta como panel al seleccionar Letras. Una petición anterior puede finalizar. Queda fuera de modificaciones.

Evidencia: [escena](../Sources/SideB/Views/Fullscreen/FullscreenNowPlayingView.swift), líneas147–185,214–275,440–480; [backdrop](../Sources/SideB/Views/Fullscreen/FullscreenBackdrop.swift), líneas33–65; [shell](../Sources/SideB/SideBApp.swift), líneas518–638 y776–797; [retención](../Sources/SideB/Views/Components/RetainedMainPages.swift), líneas34–71 y131–173; [tabla nativa](../Sources/SideB/Views/Common/NativeTrackTableView.swift), líneas363–369; [Genius](../Sources/SideB/ViewModels/GeniusViewModel.swift), líneas62–104.

## 3. Qué aportan las mediciones disponibles

Los perfiles históricos de FIX-122/123 y FIX-185 a192 sirven para diseñar las comparaciones. Sus valores de CPU/layout no se trasladan a esta build ni demuestran que el blur se recalcule por cada tick. La referencia antigua de Cola vacía/invitado no incluía la combinación actual de pista, arte y palabras animadas.

El reporte de Codex sí conserva ensayos nuevos aislados en M1Pro/macOS27.0/Swift6.4, probes compilados con swiftc -O:

| Ensayo | Mediana | Interpretación permitida |
|---|---:|---|
| Búsquedas/conjuntos del modelo,80 líneas / 480 palabras | 0,720 µs | Algoritmo puro replicado; excluye Observation, AVPlayer y SwiftUI |
| Preparar secuencia,80 líneas | 47,35 µs | Montaje puro; trabajo repetido posible, pequeño en ese tamaño |
| Raster Text nativo | 1,995 ms | Snapshot aislado |
| Raster TextRenderer contextual | 10,924 ms | Snapshot aislado, active=false |
| Raster de barrido sin movimiento | 11,297 ms | Snapshot aislado |
| Raster de barrido con efectos | 11,640 ms | Snapshot aislado |

Raster: tres frases sintéticas, seis segmentos cada una,36 pt, ancho 420 más padding, escala 2,25 muestras por variante descartando cinco iniciales. Se recrean renderer/layout/bitmap; la app puede reutilizarlos. No son FPS, tiempo de GPU, coste por frame real ni una comparación completa entre paneles. Que contexto ya cueste más invita a medir composición/layout antes de culpar exclusivamente al brillo. El estudio y P95 completos están en la auditoría enlazada; no se ejecutaron nuevamente para unir los documentos.

La caché local observada tenía diez payloads experimentales de unos25,5 KB de mediana y45 KB de máximo. No demuestra una tasa de aciertos ni consumo de RAM, pero tampoco sugiere que una letra deba ser enorme para reproducir el problema.

## 4. Plan de trabajo integrado

### Ejecución 21/10 — FIX-236

Se preservó FIX-235/build0147 y el resto del árbol previo mediante snapshot de 678 archivos. Dos agentes Luna implementaron host clásico/barra y políticas de reloj/filas; Sol medio preparó renderer/geometría y revisó reloj, con revisión del integrador y cruzada. Build 0150 oficial: 900 ejecutadas aprobadas/15 omitidas, fuentes estables, firma/diez hashes verificados. Las builds 0148/0149 fallidas se conservan con sus diagnósticos; correcciones limitadas a fixtures/sincronización de tests, sin audio/core nuevos.

- [x] Capturar baseline de CPU de scroll continuo con letras presentes, en pausa y reproducción, sin compilación ni AX dentro del intervalo de gestos.
- [x] Implementar hosts reales que acotan las lecturas frecuentes del panel clásico y de progreso de la barra.
- [x] Preparar/reutilizar Text por fila y usar contexto nativo con tipografía/geometría equivalentes; optimizar vecinos físicos sin retener Text.Layout obsoletos.
- [x] Saturar distancia visual y eliminar lectura por tick del foco completado; implementar pulso por voz/interludio visible conservando fronteras y seek.
- [x] Verificar renderer, Unicode/RTL/wrapping, voces y políticas del reloj mediante pruebas; build oficial numerada, revisión de diff, FIXES y paridad.
- [ ] Completar QA de callbacks reales del ScrollView y perfil posterior de0150 en la misma escena. App nueva esperando al Llavero al restaurar sesión; SecurityAgent bloqueado por la herramienta, escena no preparada/comparada.
- [ ] Obtener FPS/hitches/P95/P99 válidos y aceptar o reabrir según resultados. CPU y snapshots no cierran esta condición.
- [ ] Medir clásico/Lectura/seguimiento y sidebar antes de modificar composición o actividad secundaria. Mantener pendientes los experimentos no realizados abajo.

Baseline continua 0147: main 8,405 s/35,475 s de pared en pausa y 16,497 s/49,388 s reproduciendo. Snapshots contextuales 14,778→7,530 ms; el raster activo no mostró mejora en ese ensayo. Resultados/protocolo/fallos de instrumentos detallados en el reporte enlazado. Etapa 2B sigue aplazada; Recomendados permanece fuera de modificaciones. El plan no se marca completado.

Las listas originales de etapas se conservan como criterios de cierre completo; las tareas implementadas figuran arriba. No se marcan etapas completas con una verificación parcial.

### Etapa 0 — Consolidación

- [x] Leer ambos documentos y preservar originales/huellas.
- [x] Contrastar diferencias con el código de 0146 y documentación primaria de Apple.
- [x] Incorporar hosts clásicos/barra y claves visuales de Gemini; incorporar carga/red/sidebar y ensayos de Codex.
- [x] Corregir afirmaciones sobre tablas ocultas, filtros, fronteras, filas lazy y comportamiento ya implementado.
- [x] Crear este PLAN-026 como referencia de trabajo; enlazar ambos análisis sin duplicar el backlog.

### Etapa 1 — Baseline de FPS durante scroll continuo

- [ ] Misma build/Mac/canción/documento/ancho/escala/caché y ajustes de movimiento/energía; sin compilación concurrente.
- [ ] Registrar por ocurrencia: hit/miss, proveedor y tiempo, parseo, bridge, adaptación/modelo, primer texto visible y petición obsoleta/cancelada.
- [ ] Medir bodies/dependencias, layout, asignaciones, CPU y composición en clásico, Lectura y Karaoke con audio real. No asumir que diferentes modos tienen layout idéntico.
- [ ] Contar callbacks de Timer/periódicos/boundaries y órdenes de scroll. No hacer polling AX durante el intervalo perfilado.
- [ ] Capturar scroll manual continuo30–60s con documento cargado, en pausa y play, y compararlo con seguimiento automático. Apertura, clics y transición de sidebar son escenarios separados.
- [ ] Registrar frame times/hitches/P95/P99 durante ese desplazamiento; identificar si el cuello de botella es main/layout, dibujo/composición o ambos.

Cierre: baseline reproducible con al menos repeticiones comparables y distribución/P95; no una captura aislada ni un número de tests.

### Etapa 2A — Filas, layout y dibujo durante scroll: prioridad principal

- [ ] Medir primero montaje, layout y dibujo de filas visibles/contextuales durante el gesto, incluso con audio pausado. Reducir el coste demostrado antes de centrar toda la optimización en el tick de la fila activa.
- [ ] Crear límites de observación medibles para host clásico, tiempos y progreso de la barra; el contenido clásico recibe foco estable cuando corresponda.
- [ ] Reutilizar texto atribuido/segmentos y geometría por layout, con invalidación correcta por fuente/ancho/dirección/traducción.
- [ ] Usar contexto simple o renderer asentado equivalente en las filas montadas que no requieren barrido; conservar todas las voces activas.
- [ ] Saturar la clave visual de distancia según el estilo vigente y evaluar filas equatable con todas las entradas necesarias, sin cerrar callbacks/tiempos incorrectos.
- [ ] Evitar que una frase completada se reconstruya por los puntos de interludio; limitar pulso a contenido vocal/interludio realmente visible.

Cierre: menos trabajo medido respecto de baseline sin cambio de composición, alturas, animación vocal, traducción ni controles. No exigir 0 bodies globales ante cualquier evento; exigir aislamiento frente a los cambios de tiempo ensayados.

### Etapa 2B — Carga y cancelación: secundaria y aplazada para este objetivo

- [ ] Compartir o coordinar solicitudes en vuelo de ambas rutas sin eliminar APIs/paneles clásicos ni mezclar calidades de caché.
- [ ] Mostrar un respaldo usable disponible mientras se busca la versión detallada, diferenciando respaldo y actualización fresca.
- [ ] Acotar reinicios por metadata provisional y trabajo obsoleto tras cambio de pista/cuenta/cierre.
- [ ] Revisar cancelación efectiva en Rust y presupuesto global por consulta; preservar matching, precedencia, errores recuperables y opciones existentes.
- [ ] Separar caché/metadata de Genius de la precarga pesada respetando el setting del usuario.

Cierre: menor tiempo hasta primer texto y menos duplicados/huérfanos, con cobertura y calidad conservadas. Si requiere core/bridge, documentar problema compartido, paridad y comprobaciones apropiadas antes del cambio; no retocar bindings a mano.

### Etapa 3 — Scroll manual continuo y seguimiento, junto con Etapa 2A

- [ ] Coalescer muestreos redundantes sólo si el conteo los justifica, conservando despertares para segmentos cortos y gaps.
- [ ] Unificar peticiones de centrado para clic/foco/montaje; manual y momentum tienen prioridad hasta Volver.
- [ ] Comparar LazyVStack, contenedor con alturas preparadas o VStack limitado a documentos pequeños. Incluir80,400 y5000 líneas, traducciones, voces y renglones variables.
- [ ] No cambiar padding/fuente/altura entre contexto y activo. Distinguir scaleEffect de un cambio real de layout; comprobar también peso tipográfico del clásico.

Cierre: destino visible correcto tras saltos adelante/atrás, sin oscilación de offset o reflow demostrados, manteniendo memoria/montaje acotados para letras largas. No prometer scroll 100 % smooth o120 FPS antes de medir.

### Etapa 4 — Composición y actividad secundaria

- [ ] Probar preblur cacheado y composición de backdrop con variante visualmente comparable; incluir crop/zoom/resize/escala/color y cuenta/pista en la política de invalidación necesaria.
- [ ] Comparar el efecto real de compositingGroup con trazas y transiciones antes de retirarlo.
- [ ] Montar/diferir el reverso de información de forma compatible con la animación de giro y su contenido disponible.
- [ ] Propagar actividad a imágenes de sidebar oculta sin perder scroll, selección, colección o cambios en vivo.
- [ ] Auditar consumidores de actividad que falten en páginas cubiertas, preservando los que ya suspenden, los gestos de retorno y sus previews.

Cierre: reducción medida de composición/cargas secundarias, sin degradación visual ni pérdida de estado. Recomendados permanece fuera de los cambios.

## 5. Verificación y límites de cierre

Mantener como regresión lo ya implementado: conversión numérica UInt64→Double, segundos absolutos, duración desconocida, seek diferido de pista restaurada, último cue gana, pausa conservada, cuenta/ocurrencia y respuestas viejas. No reintroducir pisos temporales, compensaciones globales ni un reloj musical simulado.

Pruebas existentes para ampliar según cada cambio: `ExperimentalLyricsFetchIntegrationTests`, `ExperimentalLyricsControllerTests`, `ExperimentalLyricsTests`, `ExperimentalLyricsStyleTests`, `ExperimentalLyricsVoiceTests`, `ExperimentalLyricsInterludeTests`, `ExperimentalLyricsClockInterludeTests`, `ExperimentalLyricsSequenceTests`, `ExperimentalLyricsSeekTests`, `AudioPlayerSeekTests`, `LyricSeekPlaybackTests`, `HomeFullscreenSuspensionTests` y `RetainedMainPagesTests`. Los nombres alternativos del borrador Gemini no se asumen suites existentes.

Matriz mínima de comparación:

| Eje | Casos |
|---|---|
| Ruta | Clásico, Lectura, Karaoke; line-only y word-sync |
| Estado | Caché caliente/fría controlada, pausa/play/buffering, interludio/outro, cambio/repetición de pista/cuenta |
| Texto | Normal/largo, multilínea, traducción, RTL, emoji/ligaduras, sílabas y fondos/dúos simultáneos |
| Interacción | Cinco cues por canción adelante/atrás, clics consecutivos, pista restaurada, manual/Volver, resize |
| Escena | Sidebar abierta/cerrada y transición; Inicio/Biblioteca/detalle debajo; ocultar/restaurar ventana; reverso/retorno de portada |

Usar SwiftUI Instruments/Time Profiler/Allocations y herramientas de composición adecuadas. Los tests comprueban invariantes y regresiones; no certifican FPS ni audio audible. Hacer comprobación visual y escucha por separado. Al implementar un fix: diff, suites apropiadas, build numerada por skill, FIXES/PARIDAD y estado del plan, sin publicar por defecto.

Se cierra cada etapa sólo con evidencia de su objetivo. Las metas visuales y de latencia se fijan desde la baseline; no se heredan porcentajes de perfiles viejos ni promesas de GPU cero/imagen100%idéntica. La prioridad final se puede ajustar con mediciones sin perder los hallazgos de esta comparación.

## Seguimiento FIX-239 — estilo compartido y scroll manual

Pedido2026-10-21: originales con el mismo tamaño/fuente/blur/layout que las nuevas y blur únicamente siguiendo automáticamente en ambos renderers. Implementado en Mac mediante presentación compartida (tamaño/modo/manual) y helpers comunes, sin publicar tiempo de audio en el host. Original como respaldo mientras falta el documento rico; ajustes/manual conservados al cambiar renderer de la misma ocurrencia. Blur se quita en scroll manual y vuelve con Volver/clic/nueva ocurrencia. No se generan timings de palabras ausentes. Tres regresiones nuevas aprobadas y revisión Luna/integrador; build0155 Release aprobada,959 ejecutadas/17 omitidas, fuentes estables/firma/diez hashes. [Paquete](../../builds/macos/build-0155/Side%20B.app). QA visible del usuario pendiente; sin perfiles de FPS. Ver [FIX-239](../../FIXES.md#fix-239) y [guía Windows](../../PARIDAD.md#lyrics-windows-handoff). Rendimiento instrumental y port Windows pendientes.
