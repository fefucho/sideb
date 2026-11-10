# PLAN-018 — Cola elegida y recomendaciones separadas

> Actualización 2026-10-31: el usuario confirmó el funcionamiento de Mac build-0170 y eligió la variante visual «Continua». [PLAN-019](PLAN-019-continuous-queue.md) reemplaza el diseño original de cuatro secciones y documenta el diagnóstico del scroll horizontal. Las secciones originales de planificación/verificación de este documento se conservan como antecedente; no describen por sí solas el estado actual de implementación ni certifican Windows/performance.

- Fecha: 2026-10-30 (America/Montevideo).
- Estado: implementación experimental real en fuentes Mac/Windows; revisión final y build Mac en preparación. El estado de verificación de diseño de abajo se conserva como antecedente; el refinamiento visual posterior se registra en FIX-270/PLAN-019; la implementación funcional ya estaba en el árbol al comenzar ese trabajo.
- Rama: `experiment/queue-recommendations`, base `f7fc479`.
- Objetivo: que «Agregar al final de la cola» coloque canciones detrás de las elegidas y antes de cualquier recomendación pendiente. Las radios aportan una canción por transición, aunque YouTube Music entregue lotes.
- Entrega de esta etapa: plan y prototipo interactivo local. No constituye una implementación Swift/Svelte ni una validación de audio.
- Ámbito propuesto: piloto Mac; contrato común y porte posterior a Windows con pruebas nativas. No modificar `core/` para resolver una necesidad exclusiva de Mac.

## Evidencia y antecedentes

- `apple/Sources/SideB/Services/Player/QueueManager.swift`: `appendRadioTracks` agrega el lote recomendado al array autoritativo; `addTracksToQueue` agrega manuales al final del mismo array. Conserva IDs de ocurrencia, rangos de origen y anclas para shuffle reversible. `tracks` es un prefijo visible: no usar ese prefijo como frontera entre origen y recomendaciones.
- `apple/Sources/SideB/ViewModels/PlayerViewModel.swift`: `fetchRadio`, `extendRadioIfNeeded`, `checkAutomixTrigger`, `playNext` y `resumeAfterQueueExtension` coordinan red/EOF. `activateProviderSearchAction` y `extendProviderActionIfNeeded` cargan `/next` tanto para radio como para colecciones: el endpoint no basta para clasificar canciones.
- `recommendedTracks` también recibe contenido de recomendaciones relacionadas. Crear una reserva específica de reproducción; no reutilizar esta propiedad sin separar antes sus consumidores.
- `PlaybackStateStore.swift`: formato v2, sesiones por cuenta y guardado diferido. No se puede inferir con certeza el origen de cada canción de una cola antigua mezclada.
- `FullscreenNowPlayingView.swift`: cabecera contextual y tabla nativa de 46 pt; menús, arrastre, likes y dislikes. `NativeQueueTrackCellView.swift` conserva duración, artista/álbum y controles de fila.
- Windows: `windows/src-tauri/src/queue.rs` es autoritativo; `windows/src/lib/components/fullscreen/QueuePanel.svelte` presenta filas con identidad `entryId`, navegación de teclado y renderizado acotado. No crear una segunda cola autoritativa en Svelte.
- Antecedentes: FIX-097 (catálogo completo, ocurrencias, shuffle y persistencia v2); FIX-113 (presentación propia de cola); FIX-158/159/160 (duración y Like); FIX-134 Windows (persistencia y cola autoritativa); FIX-201 Windows (identidad activa). Este plan no atribuye regresiones a esos cambios.

## Modelo de estado

Un único propietario de reproducción por plataforma administra:

1. **Anteriores y canción actual:** prefijo de navegación y actual, con identidad estable. Ese prefijo puede incluir canciones saltadas o anteriores al índice inicial de una colección: no presentarlo como prueba de escucha real ni enviarlo al historial del proveedor.
2. **Pendientes elegidas:** canciones restantes de la colección y agregados manuales. Conservan rangos, anclas y duplicados intencionales.
3. **Reserva de recomendaciones:** propuestas automáticas todavía no comprometidas. IDs propios, semilla, estado de carga y continuación de radio separados de la continuación de la colección.

No hacen falta tres motores ni tres colas de transporte. Historial/actual/pendientes pueden seguir en el array existente; la reserva se almacena aparte. Publicar secciones derivadas con IDs, no copias editables en la UI.

Metadatos propuestos para diseñar al implementar: `origin` (colección/manual/radio), `recommendationSessionID`, revisiones y un cursor de continuación tipado por propósito y endpoint. Mantener `queueToken`, ocurrencia y generación de cuenta existentes. La procedencia de una ocurrencia no cambia al moverla dentro de la cola.

La etiqueta de procedencia es distinta de la participación en shuffle: arrastrar una canción de colección conserva su origen descriptivo, pero la quita del conjunto reordenable y le asigna un `placement` explícito, igual que el contrato actual de `moveTrack`. No inferir si una fila está anclada mirando sólo `origin`.

## Reglas de reproducción

| Situación | Resultado propuesto |
|---|---|
| Playlist A/B/C, suena A; X siguiente; Y al final | A → X → B → C → Y → primera recomendación |
| Radio R1; X siguiente; Y al final | R1 → X → Y → R2; R3 continúa en la reserva |
| Cola elegida vacía al avanzar | Promover una recomendación y comenzar su reproducción en una transición serializada |
| Recomendación precargada; llega un agregado manual antes de promoverla | El agregado manual tiene prioridad; la precarga no ocupa lugar en la cola |
| «Siguiente» varias veces | Conservar la semántica vigente: cada nueva inserción queda inmediatamente después de la actual; las inserciones por lote conservan su orden interno |
| «Al final» varias veces | Mantener orden de agregado después de todos los pendientes elegidos, antes de la reserva |
| Playlist todavía paginando | Sus siguientes páginas siguen siendo colección; los manuales con ancla `.end` permanecen al final de esa colección |
| Seleccionar una fila ya existente | Respetar la navegación vigente y su ocurrencia; no reinsertar ni duplicar |
| Anterior después de una recomendación | Volver por ocurrencias ya comprometidas en la navegación; la reserva nunca es parte de Anteriores |
| Repetir | Preservar el comportamiento actual: EOF repite la canción y el salto manual conserva la navegación existente. No agregar un nuevo modo de repetición en este trabajo |
| Shuffle | Aplicar el contrato reversible actual a las pendientes elegidas; la radio conserva el orden recibido. Cambiar shuffle no resuelve ni reinicia audio |

**Punto de compromiso:** la recomendación sale de la reserva cuando el coordinador la selecciona para reproducir, inmediatamente antes de iniciar la resolución del stream. Desde ese momento es la actual y una nueva inserción manual va después de ella. Si el stream falla, conservar la ocurrencia fallida, ofrecer reintento manual y permitir Siguiente; mantener el manejo vigente sin introducir autosaltos silenciosos. No devolverla a la reserva ni perder la canción manual que seguía.

**Colección incompleta:** no activar radio porque el lote local esté agotado. Esperar la siguiente página o mostrar el error recuperable. La falta de red no prueba que terminó la playlist. No permitir que la radio adelante canciones de la colección pendientes de cargar.

**EOF y saltos rápidos:** un avance es una intención identificada, no una consecuencia de cada callback. EOF, clic en siguiente y llegada de una respuesta no deben promover dos recomendaciones por el mismo avance. Serializar en el propietario y validar generación/ocurrencia; invalidar la intención al pausar, cambiar de contexto/cuenta o iniciar otra reproducción. Definir expresamente si dos clics manuales distintos consumen dos pasos; mantener el comportamiento de saltos rápidos existente.

**Disponibilidad de siguiente:** la reserva no se añade al array comprometido para habilitar controles. Derivar una disponibilidad de avance que considere pendientes elegidas, reserva y una continuación válida que pueda solicitarse. Actualizar los consumidores actuales: `PlayerBarView.swift:144–149` y `AppMenuCommands.swift:151` dependen de `queueManager.hasNext`; si conserva sólo la longitud del array, la radio parecerá agotada aun teniendo reserva. Probar además botones fullscreen, atajos, controles del sistema y siguiente mientras se espera red. La habilitación no constituye una promoción ni un inicio de audio.

## Recomendaciones, duplicados y errores

- Obtener lotes y preparar la siguiente canción anticipadamente; transferir una sola ocurrencia al reproducir. Un umbral inicial de reserva baja de 3 canciones es una hipótesis ajustable, no una medición de latencia.
- Una solicitud en curso por sesión; cursores repetidos, lotes vacíos o completamente filtrados tienen presupuesto finito. Tras un número acotado de intentos, mostrar «No hay más recomendaciones» o «No se pudieron cargar» con reintento. Nunca un bucle inmediato.
- Conservar la semilla de radio cuando se intercalen manuales. La canción manual no reinicia por sí sola la radio ni reemplaza su cursor. No usar `queue.last` como cursor del proveedor una vez separada la reserva.
- Los duplicados manuales y de playlist son válidos, con IDs de ocurrencia distintos. Filtrar propuestas automáticas contra pendientes elegidas, reserva y una ventana acotada del historial reciente; no bloquear una canción para siempre por haber sonado en una radio larga.
- Si se elige una propuesta con «Siguiente» o «Al final», quitar esa propuesta de la reserva y crear una ocurrencia manual. No ejecutar el filtro automático sobre esa elección explícita.
- La revalidación por duplicados se aplica a la **promoción automática**. Una elección manual explícita siempre se respeta, aunque cree otra ocurrencia de un video ya elegido. No descartar silenciosamente una acción del usuario por el filtro automático.
- Quitar una propuesta evita que reaparezca dentro de la sesión actual; no envía Dislike. Dislike conserva la acción actual sobre YouTube Music y además excluye la propuesta de esa sesión. Like no implica agregarla a la cola.
- Cuenta, cola y sesión de recomendación deben coincidir antes de aplicar una respuesta. Cancelar tareas ayuda, pero no reemplaza las guardas. Respuestas tardías de metadatos tampoco deben mutar otra ocurrencia con el mismo videoId.
- Capturar cancelaciones y errores sin exponer tokens, URLs firmadas ni cookies en logs nuevos.

## Decisiones incorporadas de la revisión independiente

Revisión de contrato/UI por Gemini 4 Argon (High), recibida el 2026-10-30. Se contrastaron los caminos citados con las funciones actuales; las condiciones de carrera descritas son escenarios de regresión para la futura implementación, no fallos reproducidos durante esta entrega de diseño.

1. **Selección inmediata y orden:** insertar la recomendación elegida con ID manual nuevo inmediatamente después de la actual, con ancla `.after(currentOccurrenceID)` o antes de la primera pendiente si no hay actual. Comprometer después la nueva ocurrencia. No dejarla como manual sin ancla que `restoreSourceOrder` mande al final. La proyección usada cuando la actual es manual/radio debe mantener la partición de anteriores/actual/pendientes: ordenar fuentes no puede convertir pendientes no reproducidas en anteriores. El simple anclaje al padre no basta si el padre tenía un rango tardío tras shuffle; probar también ese caso. Preservar y comprobar el contrato vigente de shuffle para actual de colección; añadir explícitamente pruebas de actual manual/radio en vez de reutilizar a ciegas la proyección global existente.
2. **Seleccionar una propuesta intermedia (actualizado por FIX-274):** preferencia persistente en Configuración → Cola. Predeterminado «Avanzar hasta esa canción»: retirar el prefijo hasta la elegida, dejar las anteriores como navegación de cola sin registrarlas como escuchadas y reproducir sólo la elegida; el sufijo sigue reservado y los pendientes elegidos conservan su orden. Alternativa «Reproducir sólo la elegida»: extraer únicamente esa propuesta y conservar las anteriores en reserva, como el contrato inicial. Sólo afecta selección directa/Reproducir del menú; Siguiente/Al final/drag no consumen el prefijo. Implementado Mac/Windows sin compilar; pruebas nativas pendientes. [FIX-274](../FIXES.md#fix-274), [PLAN-019](PLAN-019-continuous-queue.md).
3. **Inicios y clasificación:** todos los caminos de radio (canción, artista/colección, mix y acción del proveedor) comprometen sólo la pista inicial seleccionada; el sufijo del lote es reserva, no colección elegida. El prefijo anterior a la pista inicial de una respuesta de radio se descarta como propuestas previas no reproducidas. En álbum/playlist sí se conserva el catálogo/índice inicial y navegación vigentes. Clasificar usando el destino normalizado, `source.kind` y los discriminadores reales de radio/mix, no sólo «vino de /next» ni «source es nil». Para un destino ambiguo, resolver metadatos de la colección antes de atribuirle recomendaciones; probar PL/OLAK, RD y mixes sin tarjeta `source`.
4. **Cursores y semilla:** el estado distingue colección `/browse`, continuación opaca `/next` y extensión de radio por `lastVideoId + radioSeed`, porque los métodos actuales del core tienen contratos distintos. Guardar el último video aceptado del flujo de radio (o última fuente de colección al iniciarlo) independientemente de los agregados manuales. Conservar `automixPlaylistId` cuando venga en la respuesta. Enriquecer metadatos de la actual usando el lote original antes de filtrar la semilla repetida; excluir la actual al admitir propuestas en reserva.
5. **Nuevas páginas, shuffle y `.end`:** insertar las nuevas ocurrencias de colección antes de los manuales anclados al final de esa colección, incluso con shuffle activado. Elegir sus posiciones entre el conjunto de fuentes pendientes sin mover actual/anteriores ni manuales fijados; no rebarajar gratuitamente las posiciones ya publicadas de la página anterior. Las invariantes son `colección restante → manuales .end → radio`, con ocurrencias duplicadas conservadas. Cubrir ON/OFF, lote en vuelo y varias inserciones al final.
6. **Visibilidad y catálogo:** `visibleCount` es una optimización de publicación, no el tamaño lógico de la cola. Una inserción al final no debe exigir publicar/copiar todo el catálogo. Usar proyección de filas por rangos/IDs y una representación de la inserción reciente que permita localizarla sin exponer todas las filas. La elección concreta de ventanas/scroll queda sujeta al inventario de la auditoría de rendimiento; no quitar el batching existente alegando sólo que NSTableView recicla celdas. Separar costo de crear celdas del costo de construir arrays/snapshots completos.
7. **Repetir:** conservar el comportamiento vigente de EOF y salto manual, incluido volver al comienzo de la cola comprometida al llegar al final con repetir activo. Por ello la sección muestra «Desactivá repetir para continuar con las recomendaciones» mientras esté activo. No hacer que una promoción implícita cambie ese comportamiento. El borrado/Dislike de la actual es una transición de exclusión distinta de repetir: buscar pendientes elegidas, luego reserva y luego espera/parada; nunca reproducir automáticamente una anterior ni volver a la excluida por el modo repetir.
8. **Borrado y Dislike:** quitar una ocurrencia por ID, no la primera coincidencia de videoId. Dislike excluye propuestas del mismo video en esta sesión y conserva el rating/rollback actual; las demás ocurrencias manuales no se eliminan por accidente. Resolver actual a siguiente y actualización de cola en una mutación; no usar el fallback `selectTrack(at: 0)` cuando falta una pendiente elegida pero hay radio.
9. **Carreras e identidad:** fijar la ocurrencia activa antes de resolver/reproducir el stream, evitando `syncCurrentIndex(videoId)` ambiguo con duplicados. El EOF pendiente sólo puede consumirse por la intención y playbackID vigentes; una respuesta durante el debounce de resolución no puede usar un `hasReachedEnd` viejo para avanzar otra vez. Probar la ventana de salto rápido de 180 ms presente en `playSongNow`. Umbrales de carga separados para colección y reserva; el fin local no es fin remoto.
10. **Menús por origen:** crear un origen específico para propuesta de cola, con sessionID e ID estable; no reutilizar `.recommendations`, que también usa Explorar/Relacionado. Evolucionar `.queue(occurrenceIndex:)` o su adaptador para capturar generación/ID. En una fila ya elegida, «Reproducir siguiente» y «Agregar al final» conservan la creación intencional de otra ocurrencia; «Mover al comienzo/final» y drag reubican la misma. No unir esos comandos bajo la misma mutación.
11. **Persistencia e historial:** subdirectorio de reproducción experimental y claves propias; importar v2 sólo si esa identidad todavía no tiene sesión experimental. No habilitar HomeLab como atajo ni escribir el mapeo estable de identidad como efecto del piloto. Para radio prolongada, definir una cota explícita de anteriores de radio retenidos/persistidos durante la etapa de baseline, sin recortar ocurrencias de colección/manuales activas. Al podar, desanclar y sanear referencias antes de publicar/guardar. Nunca serializar el crecimiento ilimitado por tick.

Regresiones obligatorias adicionales: actual manual con padre de rango tardío + shuffle OFF; recomendación intermedia; radio inicial por cada vía del proveedor; PL/OLAK sin `source`; semilla usada para enriquecer y luego filtrada; página 2 con manual `.end` y shuffle ON; Dislike actual sin pendientes pero con reserva; respuesta durante debounce con EOF viejo; comando de menú sobre duplicado después de un avance.

## Diseño de la interfaz

Prototipo: [queue-recommendations.html](design/queue-recommendations.html). Datos ficticios; simulación local sin red ni audio.

### Propuesta principal: secciones en el mismo panel

- Conservar el panel Cola dentro del fullscreen, con su navegación y contexto actual. No introducir otra pantalla ni una configuración técnica en el flujo de escucha.
- **Ahora suena:** una fila activa, con créditos enlazables, duración y Like/Dislike. Evitar duplicarla al mismo tiempo dentro de las pendientes.
- **A continuación · N canciones:** sólo pendientes elegidas. Si hay páginas pendientes, usar «N cargadas» y señal de carga; no prometer un total desconocido. Mostrar la duración sólo cuando se conozca, sin sumar la reserva.
- **Recomendaciones:** debajo, con texto «Se reproducen cuando termine tu cola». Vista inicial acotada; no publicar el tamaño del lote como si fuese una cola comprometida.
- **Anteriores:** grupo plegable para conservar el prefijo de navegación sin ocupar el comienzo de la cola. «Anterior» funciona aunque esté cerrado. Se usa este nombre porque la cola actual también permite volver a canciones saltadas; no equivale al historial de escucha del proveedor.
- Reutilizar la celda actual, geometría de duración y asa, indicadores de contenido explícito y metadatos. Conservar altura inicial de 46 pt; cualquier alternativa de densidad se evalúa con el ancho real.
- En pendientes: reproducir, mover, eliminar, Like/Dislike y menú contextual con las acciones vigentes, enlaces a artista/álbum/biblioteca, siguiente/final.
- En recomendaciones: acción principal «Siguiente», opción «Al final», Like/Dislike y menú. Reproducir ahora convierte esa elección en manual y conserva las pendientes elegidas para después; no reemplaza toda la sesión. Arrastrar de recomendaciones a pendientes también expresa elección manual.
- En la implementación nativa, priorizar iconos compactos de siguiente/final revelados por hover/foco con etiquetas accesibles y menú equivalente. Los botones de texto del ejemplo sirven para descubrir la regla; no obligan a reducir el ancho de título/créditos en la columna real de fullscreen. El estado vacío de radio será una sola fila compacta que admite drop.
- Arrastrar entre secciones debe resolver IDs, no índices absolutos. No permitir arrastrar una cabecera, mover una fila al historial ni convertir canciones elegidas en propuestas por accidente. Ofrecer equivalente por menú/teclado.
- Controles de transporte, shuffle, repetir, volumen y selección de pestañas permanecen en sus posiciones actuales. El prototipo de panel no intenta rediseñar el resto del fullscreen.

### Compatibilidad con los menús actuales

Inventario contrastado con `UI/ContextMenu/MenuModels.swift`, `MenuActionExecutor.swift` y los adaptadores actuales. Las nuevas secciones usan ese sistema; no crean un menú alternativo que pierda acciones.

| Acción existente | Tratamiento en la nueva cola |
|---|---|
| Reproducir una ocurrencia de la cola | Seleccionar su ID existente; no iniciar otra radio ni recrear la ocurrencia |
| Reproducir una propuesta | Convertir esa elección en manual y reproducirla conservando pendientes; acción acotada a la sección Recomendaciones |
| Iniciar radio / mix | Mantener la acción explícita de iniciar otra sesión y su invalidación; no confundir con seleccionar una propuesta |
| Reproducir siguiente / agregar a la cola | Aplicar el nuevo contrato de prioridad en todos los orígenes: búsqueda, detalle, biblioteca, historial y fullscreen |
| Me gusta / Dislike | Conservar red, rollback y actualización actual de todas las representaciones del video; separar quitar de Dislike |
| Agregar/quitar de biblioteca | Conservar los facts de disponibilidad y ejecutor actual; no convertir en elección de reproducción |
| Agregar a playlist / crear playlist y agregar | Mantener submenu y destino actual; no modificar la cola por esa acción |
| Ir a artista / álbum | Mantener IDs y créditos múltiples; no deducir enlaces del texto del prototipo |
| Compartir | Mantener destino canónico y mecanismo nativo actual |
| Quitar de la cola | Resolver el ID de ocurrencia al ejecutar; una fila desplazada por un avance no puede quitar otra canción por un índice viejo |

El ejecutor genérico de `.play` sobre canción inicia actualmente `playWithRadio`; no reutilizarlo sin un tratamiento específico para seleccionar recomendaciones/ocurrencias. Capturar el ID y la generación al abrir el menú, revalidarlos al ejecutar y derivar el índice vigente sólo en el borde del adaptador heredado. Si la ocurrencia desapareció, la acción se descarta. Las capacidades de biblioteca/playlist/cuenta siguen llegando de `MenuFacts`; el prototipo muestra su ubicación con acciones identificadas como simuladas.

La tabla actual usa `overallIndex` para reproducir, indicar la activa y traducir drops. En la cola seccionada, ese índice visual ya no coincide con el índice autoritativo: cabeceras, anteriores plegadas y propuestas no comprometidas cambian la proyección. Añadir un descriptor de fila con sección, occurrenceID/sessionID y capacidades, y resolverlo en un adaptador específico de cola. No pasar un índice de propuesta a `playQueueIndex`, ni usar el índice visible para resaltar la actual. Conservar el comportamiento genérico de la tabla en álbum, playlist y búsqueda. Probar highlight y drop sobre duplicados con Anteriores abierto/cerrado.

### Estados necesarios

| Estado | Presentación |
|---|---|
| Radio sin pendientes manuales | «No hay canciones agregadas» en A continuación; recomendaciones visibles |
| Reserva cargando con pendientes elegidas | Carga sólo en Recomendaciones; la cola sigue operativa |
| Esperando red al terminar | Mensaje de espera y control disponible para agregar una canción, pausar o reintentar |
| Radio sin resultados | Estado vacío sin spinner infinito |
| Error de radio | Reintentar en Recomendaciones; no borrar pendientes ni historial |
| Playlist paginando | Carga de colección identificada en A continuación, distinta de radio |
| Cola larga | Una superficie de scroll con secciones virtualizadas; foco y arrastre estables |

La UI nativa debe conservar clic derecho sin añadir puntos redundantes a cada fila (antecedente FIX-145 Windows). En el prototipo se usan controles explícitos para hacer visible el comportamiento. Verificar teclado, VoiceOver, ancho estrecho, títulos largos, menú sobre duplicados y localización ES/EN. No certificar rendimiento por una captura o un prototipo HTML.

## Persistencia y vuelta a la versión estable

- La rama protege el código, no los datos ni el identificador de la app instalada.
- Piloto con directorio/namespace de reproducción independiente y sin copiar credenciales. Revisar el aislamiento existente de `HomeLabConfiguration` antes de reutilizarlo: no activar fixtures de Inicio ni asumir que aísla todos los UserDefaults, llavero o datos del core.
- Mantener la sesión estable v2 intacta. En la experimental, persistir historial/actual/pendientes y procedencia con versión nueva; la reserva puede descartarse y recuperarse por semilla al abrir, sin auto reproducir.
- Si se importa v1/v2, tratar sus pendientes como elegidas: no inventar qué parte era radio. Explicar que la separación exacta comienza en una sesión nueva. No sobrescribir el archivo original como efecto de importar.
- No persistir cursores volátiles como si fueran válidos indefinidamente; revalidar o regenerar por sesión/cuenta. Reiniciar no debe disparar audio sin intención del usuario.
- Desactivar el experimento requiere una conversión definida: conservar actual y elegidas, descartar reserva. Preferir conmutación al iniciar una nueva sesión; no cambiar de modelo a mitad de una transición.

## Etapas y contratos de trabajo

- [x] Auditar puntos principales Mac/Windows y antecedentes.
- [x] Definir reglas, riesgos y propuesta de UI.
- [x] Preparar un prototipo interactivo revisable en esta rama.
- [x] Incorporar revisión independiente de contrato/UI y auditoría de rendimiento; contrastar y corregir referencias del revisor antes de aceptarlas.
- [ ] **Etapa 1 — baseline e aislamiento:** ejecutar pruebas actuales de cola/shuffle/persistencia, guardar resultados; definir namespace experimental sin alterar el estable. Documentar modo de lanzamiento y regreso. Responsable: integrador.
- [ ] **Etapa 2 — estado puro:** reserva, procedencia, filtros, promoción atómica y cursores separados en `QueueManager` o un colaborador sin red. Pruebas de orden y ocurrencias antes de conectar reproducción.
- [ ] **Etapa 3 — integración de reproducción:** radio simple/de colección/botones del proveedor, páginas de playlist, EOF y saltos, precarga y errores. Auditar todos los caminos que reemplazan o extienden la cola, incluyendo búsqueda, artista y menús.
- [ ] **Etapa 4 — UI nativa:** secciones derivadas, cabeceras no contadas como canciones, acciones y arrastre con IDs estables, foco/accesibilidad y localización. No sustituir la tabla reciclada por miles de vistas SwiftUI.
- [ ] **Etapa 5 — persistencia experimental:** restore/flush/cambio de cuenta, importar sin perder ocurrencias y regresar a estable sin modificar v2.
- [ ] **Etapa 6 — revisión y entrega Mac:** revisión de diff y carreras; suite Swift, build numerada con `sideb-build-macos`, QA aislada y aceptación del usuario. Registrar FIX y fila PAR al implementar, sin declarar resuelto lo que sólo se diseñó.
- [ ] **Etapa 7 — Windows:** trasladar el contrato al propietario Rust en `src-tauri`, DTO/controller y QueuePanel juntos. No modificar el core compartido por conveniencia. `pnpm check/test/build` y runtime/EOF/restore nativos en Windows; registrar la evidencia propia.
- [ ] **Etapa 8 — integración:** sólo tras validación integrar la rama temporal en main; commit/push/publicación según autorización específica. Conservar builds anteriores.

### Delegación solicitada

- Nombres confirmados: **Gemini 4 Argon (High)** (`antigravity`, `gemini-4-argon-high`) y **GPT 6 Luna** (`codex`, `gpt-6-luna`). Se corrigió el alias inicial «Aragón»; ambos encargos se enviaron con los modelos solicitados.
- Encargo Argon, lectura: revisión de contrato/UI recibida e incorporada en la sección de decisiones; tres huecos principales cerrados como reglas/pruebas del plan. No constituye validación del código nativo todavía inexistente. Revisión nueva implica un encargo nuevo.
- Encargo Luna: prototipo HTML inicial entregado y revisado por el integrador; se corrigieron controles incompletos, menú, selección de recomendaciones y ciclo de repetir. Para código nativo, una etapa por vez con archivos/contrato/pruebas explícitos, sin core, build, Git ni documentación global. Una UI delegada no escribe simultáneamente los archivos del modelo.
- Pedido adicional del usuario: **otro subagente independiente debe auditar rendimiento** y preservar las optimizaciones de la cola actual. Se agrega revisión específica de virtualización, observación, paginación, foco/arrastre y complejidad de operaciones; no se acepta el HTML como prueba de rendimiento nativo.
- Auditoría de rendimiento recibida del segundo encargo Argon High y contrastada: [informe revisado](research/QUEUE-PERFORMANCE-AUDIT-2026-10-30.md). Primer intento fallido por HTTP 502; reintento entregado. La revisión de diseño está completa, la igualdad de rendimiento de la futura implementación sigue sin certificar.
- Revisión del integrador: comprobar diff, invariantes y pruebas del cambio; arreglar hallazgos pequeños directamente y no inferir corrección por la respuesta del agente.

### Puerta de rendimiento solicitada por el usuario

No sustituir el trabajo de optimización existente al separar secciones. Antes de implementar, inventariar las garantías reales de `NativeTrackTableView`/celdas y la ventana de filas de Windows, y los antecedentes de FIXES. La revisión independiente debe producir un informe con referencias y un protocolo comparable.

Antes de integrar la implementación nativa, comparar base `f7fc479` y experimental con misma máquina, configuración Release, fixtures, ancho/altura y patrón de interacción. Incluir listas de 2.000 y 10.000 ocurrencias, duplicados y una sesión de radio prolongada; ampliar el tamaño si el baseline y los límites del catálogo lo permiten. Registrar memoria, CPU del hilo principal, número de filas/celdas vivas, trabajo de layout/configuración, imágenes y latencia de las acciones. Determinar tolerancias con la variabilidad medida del baseline, no inventar un porcentaje de aceptación.

- Exigir renderizado acotado al viewport, preservando reciclaje, foco y fila en drag. No reemplazar la tabla por pilas que materialicen todas las filas.
- Las cabeceras y secciones no deben crear scrolls anidados ni reiniciar la tabla en cada avance.
- Cambios de progreso/tiempo no deben reconstruir cola, snapshot, miniaturas ni hacer guardados completos por tick.
- Reserva e historial deben tener política explícita de crecimiento, filtros y persistencia; no agregar recorridos/copia de toda la sesión por cada recomendación.
- Medir inserción siguiente/final, reordenar, eliminar, shuffle ON/OFF, avanzar en radio, restaurar sesión y abrir/cerrar fullscreen. Separar costos propios de red/audio de los del listado.
- La etapa nativa queda sin aprobación de rendimiento hasta contar con comparativa real. El informe estático de diseño sólo determina condiciones y riesgos.

Contraste estático adicional del integrador: `NativeTrackTableView` ya reutiliza vistas por identificador y actualiza las disponibles, pero `TrackTableRowProjection.make` construye arrays planos de pistas y filas a partir de todas las secciones recibidas en el inicializador. El reciclaje de celdas por sí solo no elimina ese costo. Evitar que la nueva separación alimente el catálogo completo en cada invalidación; medir construcción de proyecciones y publicación además de celdas vivas. Windows ya limita las filas mediante `visibleTrackRange`/`trackSegments` y fija foco/drag fuera del viewport: conservar esa política con el nuevo descriptor de secciones. Esta lectura no reemplaza el informe independiente ni afirma una regresión actual.

La [auditoría independiente contrastada](research/QUEUE-PERFORMANCE-AUDIT-2026-10-30.md) agrega las siguientes condiciones de implementación:

- Cachear proyecciones por revisión estructural, cubriendo metadata/capacidades sin usar ticks como revisión. Distinguir catálogo N, publicación V y vistas físicas vivas.
- Revisar el snapshot Mac calculado antes del debounce y la codificación/escritura en MainActor; coalescer antes del trabajo costoso y evaluar snapshot inmutable/worker con flush y guardas por cuenta. No sacar acceso mutable de QueueManager de su actor.
- En el port Windows, evitar copiar `queue.items` publicados en cada `acceptProgress`; conservar la referencia/revisión cuando la cola no cambia. El costo actual identificado es O(V), no necesariamente O(N).
- Acotar Anteriores de radio y reserva sin recortar la colección ni manuales; mantener índices de duplicados consistentes y poda por lotes con anclas saneadas.
- Probar cargas de 2.000/10.000, radio sintética prolongada y reposo con progreso. Registrar memoria, CPU, latencias, proyecciones, filas publicadas, celdas físicas, imágenes y guardados. No fijar número de celdas, presupuesto en milisegundos o cota de historial por una sugerencia del revisor sin medición.
- El informe distingue propuestas del revisor de evidencia de código y corrige referencias a helpers inexistentes en Windows. Su aprobación de diseño no sustituye los benchmarks nativos ni autoriza una refactorización fuera del ámbito del piloto.

## Criterios de aceptación y pruebas

1. Playlist de 3 canciones y radio producen los órdenes de la tabla; probar lote, inserciones sucesivas y cola vacía.
2. Una precarga o respuesta de red tardía no se adelanta a un agregado manual ni inicia audio tras pausar/cambiar cuenta.
3. Cada avance consume una propuesta como máximo; EOF duplicado, siguiente durante carga y callbacks tardíos no saltan dos pistas.
4. Playlist de varias páginas conserva todas las ocurrencias, incluidos duplicados; «al final» respeta páginas aún pendientes y un error de página no dispara radio.
5. Shuffle ON/OFF y restauración conservan identidad, anclas y audio actual. Repetir y saltos manuales siguen el contrato vigente.
6. Anterior, selección desde historial, eliminación de actual/pendiente y arrastre funcionan por ocurrencia tras la separación.
7. Promover una recomendación por siguiente/final/arrastre no genera reproducción automática duplicada; Like, Dislike y quitar mantienen sus diferencias.
8. Cursores de `/next`, `/browse` y radio no se cruzan. Lotes vacíos, tokens repetidos y propuestas descartadas terminan de forma acotada.
9. Cuenta/contexto nuevos invalidan red y persistencia anteriores; restore no pierde manuales ni inicia audio.
10. Duración, metadatos/enlaces, explícito, accesibilidad, menú contextual y foco funcionan en ambas secciones; contador excluye reserva e historial.
11. Escenario de 2.000 canciones/duplicados conserva renderizado acotado y foco. Medición nativa posterior si cambian contenedores; no afirmar FPS sin medir.
12. Ejecutar `swift test --package-path apple` al implementar Mac; runner de build local habitual antes de entregar app. QA manual de audio y cuenta se reporta separada. No ejecutar suite/build por cambios sólo de plan y prototipo.
13. Revisión independiente de rendimiento entregada, hallazgos incorporados y comparativa nativa de la puerta anterior completada antes de integrar el cambio funcional. No declarar «igual de optimizada» con pruebas de corrección, una build o mediciones del HTML.

## Estado de verificación de esta entrega

- Se revisaron las rutas citadas y antecedentes de forma estática.
- Revisión de contrato/UI: [hallazgos y decisiones](research/QUEUE-CONTRACT-REVIEW-2026-10-30.md). Revisión independiente de rendimiento: [informe contrastado y protocolo](research/QUEUE-PERFORMANCE-AUDIT-2026-10-30.md). Ambas recibidas e incorporadas; sin mediciones nativas nuevas.
- Prototipo: 35 comprobaciones aprobadas con Playwright/Chrome headless sobre archivo local: prioridad de siguiente/final, consumo individual, reproducción manual preservando pendientes, navegación anterior, duplicados de ocurrencia, shuffle reversible del ejemplo, repetir/avance manual, Like/quitar, menú por teclado, reordenamiento, arrastre de recomendación a pendientes, foco tras promoción/eliminación/reordenamiento y anchos 728/480/390/320. Sin errores JavaScript. No son pruebas del reproductor nativo. Script conservado: [queue-recommendations.check.mjs](design/queue-recommendations.check.mjs).
- No se cambió código de reproducción, core, bindings, formato persistido ni datos de usuario. No se creó build ni se ejecutó audio/cuenta real.
- FIX/PAR de implementación pendientes; este documento es un plan y no un fix resuelto.

## Auditoría de cierre del pedido de planificación/diseño

| Requisito de esta entrega | Evidencia |
|---|---|
| Plan de separación de elegidas y radio sin cambiar la respuesta del proveedor | Modelo, reglas, adaptadores por cursor/intención y etapas de este plan |
| Casos límite y funciones actuales conservadas | Decisiones de la revisión, tabla de compatibilidad de menús y matriz de pruebas nativas futuras |
| Trabajo en rama de prueba | `experiment/queue-recommendations`, base `f7fc479`; sólo documentación/prototipo, sin cambios en apple/core/windows |
| Código del prototipo delegado a Luna y revisado por el integrador | HTML inicial entregado; correcciones posteriores de semántica, identidad, foco y menús; 35 comprobaciones reproducibles |
| Diseño discutido con Gemini 4 Argon (High), nombre confirmado por el usuario | Revisión de contrato/UI recibida y sintetizada con decisiones en este plan y su informe |
| Otro subagente independiente para preservar rendimiento | Auditoría de rendimiento recibida, contrastada y convertida en condiciones y protocolo de no regresión |
| UI revisable | Prototipo interactivo mostrado en la conversación, archivo local y guía de uso; sin audio/red ni datos de usuario |
| Límites honestos | Rendimiento nativo, integración, migración y audio reales todavía pendientes de las etapas futuras; no se afirma que la función esté implementada |

Las etapas 1–8 y los criterios de aceptación nativos describen el trabajo posterior para implementar la función. No se marcaron ejecutados por haber entregado este plan. No se creó commit, push, PR, build o release en esta etapa.
