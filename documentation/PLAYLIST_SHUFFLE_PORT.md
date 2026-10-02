# Playlists por tandas y shuffle global: referencia para macOS

Fix implementado en Windows el 2026-10-01. El port a macOS está pendiente; esta guía describe el comportamiento que debe conservarse, no una implementación Swift ya realizada.

## Problema y resultado

Windows recorría todas las continuaciones al pulsar Play, aunque la hidratación de likes ya había leído esas mismas páginas. Además, publicaba todas las entradas de la cola en cada snapshot. El botón de shuffle de la colección mezclaba las pistas, pero no comunicaba siempre ese modo al reproductor nativo.

El fix reutiliza el catálogo completo en memoria de sesión y publica la cola de playlists en tandas de 100. La lista completa de metadatos sigue existiendo en memoria: **100 es el tamaño de la tanda visible, no el límite del catálogo ni una descarga de 100 archivos de audio**. El audio se resuelve para la pista seleccionada.

Si el catálogo todavía está incompleto, la primera reproducción debe terminar de leer las continuaciones. Este fix no elimina esa espera inicial ni incorpora una caché persistente entre aperturas de la app.

## Contrato del comportamiento

1. La cola autoritativa conserva todas las ocurrencias y su orden. Una canción repetida en una playlist conserva entradas distintas.
2. Al iniciar desde el índice `i`, se publica el prefijo hasta `min(total, i + 100)`: incluye el historial anterior, la pista seleccionada y hasta 99 siguientes. Desde el inicio se ven 100; al elegir una pista avanzada se conserva también el historial para Atrás.
3. Cuando quedan diez entradas visibles por delante de la actual, el prefijo publicado crece otras 100, hasta agotar la colección. Las tandas siguientes siguen el mismo orden; no se vuelven a mezclar al publicarlas.
4. Shuffle desde el botón de la colección mezcla **todas** las ocurrencias antes de elegir la primera pista. Una canción de la última página puede ser la primera.
5. Activar shuffle durante la reproducción conserva la ocurrencia actual y las ya recorridas, y mezcla todas las pendientes, incluidas las todavía ocultas. Pulsarlo estando activo lo desactiva; la implementación actual no restaura el orden original.
6. Siguiente, EOF, Atrás, repetir y selección usan la cola completa, no sólo la tanda visible. El cambio de tamaño de la tanda no reinicia el audio.
7. Las acciones manuales siguen disponibles. En Windows, encolar al final o mover al final expone toda la cola para que el resultado sea visible. Insertar a continuación mantiene visible la entrada manual.
8. Las tandas se aplican a todas las playlists, incluida `LM`. Los álbumes, radios y otras fuentes conservan su publicación completa.
9. La hidratación de likes y Play comparten la petición pendiente. Los catálogos completos se reutilizan durante la sesión, con un máximo de 20 en Windows.
10. Actualizar, modificar la colección o cambiar de cuenta invalida la caché. Las respuestas de una cuenta, navegación, petición o revisión anterior no pueden poblar ni reproducir el contexto nuevo.
11. Un error de página es recuperable y no guarda un catálogo parcial como completo. Si el proveedor repite una continuación, se informa un error en lugar de presentar un shuffle parcial como global.

## Implementación Windows que sirve de referencia

| Archivo | Responsabilidad |
|---|---|
| [`account/controller.ts`](../windows/src/lib/account/controller.ts) | `completePlaylists`, `likesHydration`, `catalogRevision`; hidratar y reutilizar todas las páginas, invalidar la caché y rechazar continuaciones repetidas. |
| [`queue.rs`](../windows/src-tauri/src/queue.rs) | Catálogo autoritativo en `items`, límite interno `visible_len`, `snapshot()` y ampliación de tandas desde `select()`. El shuffle opera sobre `items` completo. |
| [`lib.rs`](../windows/src-tauri/src/lib.rs) | `PlaybackManager::to_dto()` copia sólo la tanda publicada mediante `queue.snapshot()`. |
| [`commands/playback.rs`](../windows/src-tauri/src/commands/playback.rs) | `play_song` recibe el argumento optativo `shuffle` al reemplazar una colección; avanzar por ocurrencias conserva el modo. |
| [`player/controller.ts`](../windows/src/lib/player/controller.ts) | Envía `shuffle` junto con la colección; una selección que conserva la cola envía `null` para no cambiar el modo. |
| [`+page.svelte`](../windows/src/routes/+page.svelte) | `playCollection()` mezcla toda la colección con Fisher–Yates y comunica el modo en el mismo comando de reproducción. |

No trasladar Tauri, libmpv ni sus DTOs a Swift. Portar el comportamiento usando el reproductor AVPlayer y los contratos existentes de macOS.

## Puntos de entrada para el port macOS

| Archivo actual | Trabajo a realizar en macOS |
|---|---|
| [`QueueManager.swift`](../apple/Sources/SideB/Services/Player/QueueManager.swift) | Separar el orden completo de las entradas expuestas a las vistas. `toggleShuffle()` debe mezclar las pendientes del catálogo completo; las propiedades de navegación deben conservar el acceso al total. Preservar la identidad de cada ocurrencia. |
| [`PlaylistDetailViewModel.swift`](../apple/Sources/SideB/ViewModels/PlaylistDetailViewModel.swift) | Unificar Play, shuffle y selección con un catálogo completo compartido. Actualmente `shuffle()` mezcla sólo `playlist.items`, que puede contener únicamente la primera página. |
| [`PlayerViewModel.swift`](../apple/Sources/SideB/ViewModels/PlayerViewModel.swift) | Aprovechar `hydrateLikedSongs()` para conservar también los metadatos y compartir su tarea con Play. Adaptar `playPlaylist()` y el avance para publicar tandas sin limitar la cola autoritativa. |
| [`MenuActionExecutor.swift`](../apple/Sources/SideB/UI/ContextMenu/MenuActionExecutor.swift) | Reutilizar la misma resolución/caché desde `loadCompletePlaylist()`; el menú contextual actual ya tiene un recorrido distinto que carga todo antes de reproducir. |
| [`PlaybackStateStore.swift`](../apple/Sources/SideB/Services/Player/PlaybackStateStore.swift) | Revisar la restauración de la cola: guardar sólo la tanda visible no debe hacer perder las canciones pendientes al restaurar. Mantener la persistencia compatible con las reglas actuales de sesión. |

Actualmente `extendPlaylistIfNeeded()` solicita la siguiente página y `appendPlaylistTracks()` la agrega sin mezclar, deduplicando por `videoId`. Copiar ese recorrido produciría shuffle parcial y podría eliminar ocurrencias repetidas. En el port, publicar la siguiente tanda de un catálogo ya completo debe ser una operación local, independiente de la paginación de red.

`hydrateLikedSongs()` también tiene un límite actual de diez páginas adicionales y corta silenciosamente ante errores. No considerar ese resultado completo si todavía hay continuación: resolver todas las páginas con detección de tokens repetidos y errores recuperables antes de usarlo como catálogo para shuffle global. Compartir la tarea e incorporar validación de cuenta para que una hidratación tardía no restaure datos de la cuenta anterior.

Revisar `checkAutomixTrigger()`: el umbral para ampliar la tanda visible es distinto del final real de la playlist. No iniciar radio/Automix cuando sólo se agotó la tanda y todavía quedan pistas del catálogo. Conservar cancelación, generación de cuenta y `queueToken` para rechazar trabajo obsoleto.

Las vistas deben consumir la tanda publicada, evitando copiar/renderizar toda la colección mediante `upNextTracks`. El transporte y la cola completa siguen siendo la fuente de verdad. La carga visual de más filas de la playlist puede continuar por páginas, separada del catálogo de reproducción.

## Pruebas que debe conservar el port

- Biblioteca de 2000 entradas: primera tanda de 100, ampliaciones de 100, última pista alcanzable y sin saltos ni duplicación de ocurrencias.
- Shuffle global: una pista fuera de las primeras 100 puede aparecer en la primera tanda; concatenar las tandas produce exactamente el orden completo ya mezclado.
- Activar shuffle durante la reproducción: conservar pista actual e historial; mezclar también las entradas ocultas sin reiniciar el audio.
- Selección avanzada, Atrás, EOF, repetir, duplicados, cambio de playlist, eliminación, encolado manual y reordenamiento.
- Play mientras se hidratan likes: compartir las páginas pendientes y evitar una segunda descarga completa.
- Caché invalidada por refresh, mutaciones y cambio de cuenta; respuestas tardías descartadas.
- Error de red recuperable y continuación repetida: no presentar ni cachear un catálogo incompleto como completo.
- Álbumes y radios: conservar su comportamiento y sus controles actuales.

Pruebas Windows de referencia: [`account-controller.test.mjs`](../windows/scripts/account-controller.test.mjs), [`account-playlist-actions.test.mjs`](../windows/scripts/account-playlist-actions.test.mjs), [`playback-controller.test.mjs`](../windows/scripts/playback-controller.test.mjs), pruebas de `queue.rs` y de `PlaybackManager` en `lib.rs`.

## Verificación realizada

En Windows pasaron `windows/scripts/windows.ps1 -Action verify`: tipos sin errores ni advertencias, 114 pruebas frontend, build frontend, 90 pruebas de `innertube`, 82 de `sideb-core` (7 pruebas en vivo ignoradas), 4 de `player` y 35 del bridge Tauri. También pasó `-Action build -Configuration debug`, con ejecutable standalone y `libmpv-2.dll` adyacente.

No se midieron tiempos con una cuenta real ni audio audible. Hubo advertencias de compilación del core/enlazador; los gates terminaron con éxito. macOS no fue modificado ni compilado en este host Windows. Al realizar el port, ejecutar `swift test --package-path apple` en un Mac y comprobar reproducción, tiempos de arranque y consumo de memoria con la misma biblioteca antes y después.
