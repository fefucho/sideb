# Auditoría independiente de rendimiento de la cola

- Fecha: 2026-10-30; base nativa `f7fc479`, rama `experiment/queue-recommendations`.
- Revisor independiente: Gemini 4 Argon (High), proveedor Antigravity, separado de la revisión de contrato/UI y de Luna, que produjo el prototipo inicial.
- Estado: informe recibido y contrastado por el integrador. El primer intento falló por HTTP 502; el reintento terminó y entregó el informe en su respuesta, sin crear archivo. Este documento conserva su síntesis revisada; la respuesta original queda como evidencia local en `temp/queue-design-qa/argon-performance-original.md`.
- Método: lectura de código/antecedentes y revisión del diseño. No se ejecutó una comparativa nativa ni se midieron FPS, CPU, memoria o audio.

## Veredicto

**La propuesta puede conservar las optimizaciones actuales si reutiliza el renderer y sus límites de publicación. Aún no se puede afirmar que la futura cola nativa rinda igual: todavía no está implementada.** El HTML no constituye evidencia de rendimiento de AppKit/WebView2.

La revisión independiente requerida por el usuario está realizada para la etapa de diseño. La aprobación de igualdad de rendimiento queda como condición de la implementación y debe demostrarse con la comparación siguiente antes de integrar el cambio funcional.

## Optimización actual que debe preservarse

| Componente | Evidencia comprobada en el código vigente | Condición para el cambio |
|---|---|---|
| Mac: reciclaje y hover | `NativeTrackTableView.swift`, callbacks `rowViewForRow`/`viewFor` reutilizan vistas por identificador. `hoveredRowIndex` actualiza filas implicadas sin crearlas innecesariamente | Un NSTableView y un scroll; no sustituir por una pila que materialice la colección |
| Mac: vida de celda e imágenes | `NativeQueueTrackCellView.prepareForReuse` cancela `imageFetchTask`, invalida identidad de petición y limpia callbacks/metadata. `ImageCache.image` tiene caché, coalescencia de solicitudes y carga de disco en tarea detached | Preservar guardas de identidad y reciclaje de imágenes al promover/reordenar; medir solicitudes/decodificación, sin asumir que toda la canalización está fuera del hilo principal |
| Mac: actividad fuera de página | `NativeTrackTableView.updateNSView` suspende trabajo de tabla con `pageIsActive == false`; pausa enlaces destacados y los reanuda al volver | No introducir observación de progreso que reactive proyecciones ocultas |
| Mac: publicación por tandas | `QueueManager.tracks`, `initialVisibleCount` y `extendVisibleBatch`: catálogo autoritativo distinto del prefijo publicado, con lotes de 100 para playlists | Separar secciones no debe convertir el catálogo completo en el array de UI por cada cambio |
| Mac: actualización visible | `updateNSView` usa `enumerateAvailableRowViews` para cambios de activa, isPlaying, reordenabilidad y duración cuando no cambian filas/likes/alturas | Mantener cambios de reproducción acotados; comprobar por separado el camino de Like que actualmente puede recargar la tabla |
| Windows: filas acotadas | `QueuePanel.svelte` usa `visibleTrackRange` y `trackSegments` (`trackList.ts`), con `rowPitch = 48`, overscan y anclas de `focusedEntryId`/`draggingId` | Conservar ventana y filas fijadas al proyectar secciones; no montar todo Anteriores al expandir |
| Windows: autoridad y transporte | `queue.rs` mantiene orden/identidad y `snapshot()` publica sólo `visible_len` para playlists, sin sourceRanks/placements internos | No crear otra cola autoritativa en Svelte; distinguir N autoritativo de V publicado |
| Windows: persistencia | `playback_runtime.rs`, tupla dirty y worker `sideb-playback-store`, con coalescencia de 350 ms para serialización/escritura | Preservar guardas y worker; no añadir guardados por progreso ni bloqueos de UI |

Antecedentes contrastados: FIX-097 (catálogo/batching/shuffle), FIX-113 y FIX-158/159/160 (celdas, controles y duración), FIX-134 Windows (persistencia/autoridad), FIX-201 Windows (ocurrencia activa). Sus afirmaciones históricas de fluidez no son una medición nueva.

## Riesgos encontrados y confirmados por lectura

1. **Publicación y proyección no son celdas vivas.** `TrackTableRowProjection.make` recorre todas las pistas que recibe y crea arrays de tracks/rows. `updateNSView` compara arrays para detectar cambios. `addTracksToQueue` y mover al final pueden llevar `visibleCount` a `queue.count`. Son rutas que amplían el costo de datos/proyección; no demuestran que AppKit instancie N celdas. La nueva UI no debe agravarlas ni quitar batching para mostrar una sola inserción manual al final.
2. **Persistencia Mac.** `schedulePlaybackSave()` calcula `playbackSnapshot()` antes de entrar al debounce. Ese snapshot mapea toda la cola y metadata. `PlaybackStateStore` es MainActor y `flush()` codifica/escribe el archivo atómico allí. El camino y su complejidad son verificables; su impacto temporal con 2.000/10.000 ocurrencias no fue medido. El nuevo historial de radio no debe hacer crecer este trabajo indefinidamente.
3. **Ticks Windows.** `acceptProgress` publica un snapshot; el getter llama `cloneState`, que vuelve a copiar `queue.items` y créditos. Los eventos de progreso están acotados a 200 ms. El costo es O(V), con V = elementos publicados, no necesariamente todo el catálogo N porque `queue.snapshot()` limita playlists. Debe evitarse que la reserva o el nuevo render aumenten V o clonen ese contenido en cada tick.
4. **Actualizaciones no estructurales.** En Mac, el camino actual de `likedChanged` puede ejecutar `reloadData()`; en Windows, `to_dto` llama `queue.snapshot()` también en estados de transporte. Medir antes de cambiar: reutilizar una revisión estructural y actualizar vistas visibles es una opción para el adaptador de cola, no una autorización para refactorizar otras pantallas en este plan.
5. **Alturas/secciones.** La tabla Mac ya tiene filas tipadas y cálculo de alturas por tipo; conservarlo O(1). En Windows, el virtualizador actual supone altura uniforme: cabeceras o estados de distinto alto necesitan una proyección de offsets coherente. No introducir un segundo scroll ni un `<details>` que monte miles de filas por fuera de la ventana.
6. **Identidad.** El índice visual de la tabla deja de coincidir con el índice de reproducción al plegar Anteriores e incluir propuestas. Payloads de drag/menú y resaltado deben llevar ID y generación; fijar foco/drag por esa identidad aunque cambie de sección. No aceptar un drop si la sesión cambió.
7. **Radio prolongada.** Evitar reconstruir `Set(queue.map(videoId))` por cada admisión/promoción. Evaluar contadores incrementales de pendientes y sets de reserva/exclusión más ventana reciente acotada. Conservar duplicados manuales y sincronizar esos índices en restore/move/remove, no añadir cachés sin invariantes.

Estas observaciones identifican caminos y riesgos; no se etiquetan como regresiones reproducidas ni se afirma un tiempo de bloqueo concreto.

## Condiciones incorporadas al plan

- Una superficie virtualizada por plataforma con filas tipadas por ID; cabeceras/estado no cuentan como canciones. Proyección acotada de fuente, manuales finales visibles y reserva, sin exponer de golpe N canciones para mostrar «Al final».
- Revisión estructural para cachear proyecciones y evitar comparaciones/copias completas cuando sólo cambia el progreso. Tiempo vivo aislado en vistas hoja. Comprobar que una revisión nueva se emita también al cambiar metadata/capacidades que afecten la presentación.
- Mantener semántica de autoridad, focos y cancelación. El diseño visual del HTML no se traslada como múltiples listas nativas ni como reconstrucción global por acción.
- Snapshot de reproducción sólo por cambios relevantes y después de coalescer. Evaluar snapshot inmutable y codificación/escritura fuera del hilo principal, conservando orden por cuenta/generación, flush al cerrar y aislamiento del archivo estable. No mover acceso mutable de QueueManager fuera de su actor.
- Definir en la etapa de baseline una cota de anteriores de radio y de propuestas visibles/retenidas, con poda en lotes y anclas saneadas. No recortar colección activa ni manuales elegidas para cumplir una cota de radio.
- No hacer una refactorización general de rendimiento de Windows o tablas de catálogo dentro del piloto Mac. Si una ruta heredada impide aprobar la comparación del piloto, corregir la dependencia concreta con su propio registro y pruebas.

## Protocolo de comparación nativa

Comparar `f7fc479` y la futura implementación en la misma máquina física por plataforma, configuración Release, mismos fixtures, geometría, escala, frecuencia de pantalla y energía. Alternar baseline/experimental para reducir sesgo de caché o temperatura. Registrar versiones/commit, límites publicados, actividad de red y contador de operaciones. No iniciar sesión ni medir cuentas reales por este informe.

| Escenario | Carga controlada | Operaciones |
|---|---|---|
| Playlist grande | 2.000 ocurrencias con duplicados identificados | Abrir Cola, scroll ida/vuelta, siguiente/final, mover/quitar, Like/Unlike, shuffle ON/OFF |
| Catálogo y páginas | 10.000 ocurrencias, páginas de 100 y manuales `.end` | Nueva página con shuffle, localizar manual final, extremo a extremo, restore, abrir/cerrar fullscreen |
| Radio prolongada | 500 avances sintéticos, lotes de 25 y manuales intercaladas | Promoción, EOF duplicado, Dislike actual, drag entre secciones y expandir/plegar Anteriores |
| Reposo con progreso | Las dos cargas, viewport estable y reloj equivalente al nativo | Contar reconstrucciones, copias, configuración de celdas, imágenes y guardados sin mutaciones estructurales |

Las cantidades anteriores definen fixtures de prueba, no resultados medidos ni límites del producto. Usar audio/reloj deterministas para aislar el renderer; validar audio real por separado en QA.

Métricas: CPU del hilo principal por segundo, latencia y dispersión de mutaciones, pausas de layout/scroll, vistas/nodos vivos, memoria y memoria retenida al cerrar, solicitudes/decodificaciones de imágenes, tiempo y bytes/frecuencia de persistencia. En Mac, Time Profiler/Allocations y contadores de proyección/celda/guardado; en Windows, trazas WebView2 y comandos nativos. Las mediciones nativas de Windows requieren esa plataforma.

Medir N lógico, V publicado y vistas/nodos vivos por separado. En Windows contar `.queue-row[data-entry-id]` dentro del panel, que es el selector real; en Mac contar vistas instanciadas, sin confundir `numberOfRows` con vistas. Al aumentar N, las vistas vivas deben seguir la geometría/overscan/foco/drag y no crecer proporcionalmente al catálogo.

Antes de fijar tolerancias, repetir el baseline hasta conocer su variabilidad y estabilización. Comparar medianas/percentiles adecuados al número de muestras, con las mismas unidades y método en ambas ramas. Aumentar repeticiones si la dispersión no permite decidir. No aceptar una fórmula con un mínimo de milisegundos arbitrario ni cuantificar p99 con muestras insuficientes.

Fallas de aceptación: materializar la cola completa en vistas; rehacer proyecciones o guardados completos por progreso; perder foco o drag por cambio de sección; invadir el archivo estable; crecimiento no acotado de radio; empeoramiento repetible de scroll/latencia/memoria fuera de la variabilidad del baseline. Los costos heredados se registran por separado y no se presentan como causados por esta función.

## Correcciones al informe original del subagente

El integrador contrastó los nombres y caminos antes de aceptar las recomendaciones:

- El código real de Windows usa `visibleTrackRange`/`trackSegments`, no `windowedSlice`, y fija foco/drag con `focusedEntryId`/`draggingId`; no contiene los mapas `rowIds/indexByEntryId` descritos por el informe original. Se retiraron esas afirmaciones.
- El clonado de progreso recorre la cola **publicada**. El catálogo completo puede ser mayor que ese DTO. Se retiró la estimación de objetos por segundo para N = 10.000 porque V no estaba establecido ni medido.
- No se certifican «15–20» o «30» celdas vivas sin instrumentación. Los comentarios del renderer explican la intención; el límite observado se mide con la geometría usada.
- Las propuestas de cota 200/220, reserva 25 visible y presupuestos de 1 ms eran sugerencias del revisor, no datos ni requisitos del usuario. No se fijan como umbrales de aceptación sin baseline.
- Insertar incrementalmente en un array Swift puede seguir copiando el backing store por copy-on-write. Se retiró la promesa de costo O(batch + manuales) y se mantiene la obligación de medir asignaciones/proyección.
- La propuesta de Fisher-Yates parcial y offsets acumulados queda como opción de implementación a evaluar, no como una solución aprobada sin pruebas de distribución, identidad y medición.

## Cierre de esta auditoría de diseño

Hallazgos de diseño incorporados a [PLAN-018](../PLAN-018-queue-recommendations.md). No se modificó código nativo ni se creó build. La revisión independiente está entregada; el rendimiento de la futura implementación permanece **sin certificar** hasta ejecutar y aprobar la comparación nativa anterior.
