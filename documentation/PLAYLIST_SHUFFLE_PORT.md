# Playlists por tandas y shuffle global: referencia para macOS

Fix de tandas implementado en Windows el 2026-10-01; ampliado el 2026-10-02 con restauración del orden completo al apagar shuffle. El port a macOS está pendiente; esta guía describe el comportamiento que debe conservarse, no una implementación Swift ya realizada.

## Problema y resultado

Windows recorría todas las continuaciones al pulsar Play, aunque la hidratación de likes ya había leído esas mismas páginas. Además, publicaba todas las entradas de la cola en cada snapshot. El botón de shuffle de la colección mezclaba las pistas, pero no comunicaba siempre ese modo al reproductor nativo.

El fix reutiliza el catálogo completo en memoria de sesión y publica la cola de playlists en tandas de 100. La lista completa de metadatos sigue existiendo en memoria: **100 es el tamaño de la tanda visible, no el límite del catálogo ni una descarga de 100 archivos de audio**. El audio se resuelve para la pista seleccionada.

Si el catálogo todavía está incompleto, la primera reproducción debe terminar de leer las continuaciones. Este fix no elimina esa espera inicial ni incorpora una caché persistente entre aperturas de la app.

## Contrato del comportamiento

1. La cola autoritativa conserva todas las ocurrencias y su orden. Una canción repetida en una playlist conserva entradas distintas.
2. Al iniciar desde el índice `i`, se publica el prefijo hasta `min(total, i + 100)`: incluye las posiciones anteriores, la pista seleccionada y hasta 99 siguientes. Desde el inicio se ven 100; al elegir una pista avanzada se conservan también las posiciones anteriores para Atrás. El orden anterior de la cola no equivale necesariamente al historial de temas efectivamente escuchados.
3. Cuando quedan diez entradas visibles por delante de la actual, el prefijo publicado crece otras 100, hasta agotar la colección. Las tandas siguientes siguen el mismo orden; no se vuelven a mezclar al publicarlas. Tras restaurar el orden, el prefijo se amplía para incluir el índice real de la actual, sus siguientes y las entradas explícitas que ya estaban publicadas, aunque sus anclas las reubiquen más adelante.
4. Shuffle desde el botón de la colección elige la primera pista entre **todas** las ocurrencias y mezcla el resto. Una canción de la última página puede ser la primera. La colección llega al gestor en su orden original; elegir una pista aleatoria no convierte las posiciones anteriores en historial.
5. Activar shuffle durante la reproducción conserva el prefijo hasta la ocurrencia actual y mezcla las entradas de fuente que están después de ella, incluidas las todavía ocultas. **Desactivarlo restaura la colección completa a su orden original**, reubica la misma ocurrencia actual en su posición canónica real y mantiene su audio. Las pistas anteriores en la colección aparecen arriba de la actual y las posteriores abajo, aunque se hayan escuchado en otro orden. Reactivar shuffle mezcla únicamente las entradas de fuente que ahora quedan después de la actual. No se recrean ocurrencias eliminadas ni se reinicia el audio.
6. Siguiente, EOF, Atrás, repetir y selección usan la cola completa, no sólo la tanda visible. El cambio de tamaño de la tanda no reinicia el audio.
7. Las acciones manuales siguen disponibles. Reproducir a continuación conserva un bloque prioritario anclado a la ocurrencia que estaba activa: al apagar shuffle sigue inmediatamente después de su ancla reubicada. Añadir a la cola conserva las manuales al final. Un índice fijo en el array mezclado no alcanza para preservar estas acciones cuando toda la fuente cambia de posición. Un arrastre explícito se conserva como excepción al orden automático mediante un ancla antes de otra ocurrencia o al final, incluso si mueve una pista que vino de la fuente. En Windows, encolar al final o mover al final expone toda la cola para conservar esas acciones; insertar a continuación mantiene visible la entrada manual.
8. Las tandas se aplican a todas las playlists, incluida `LM`. Los álbumes, radios y otras fuentes conservan su publicación completa.
9. La hidratación de likes y Play comparten la petición pendiente. Los catálogos completos se reutilizan durante la sesión, con un máximo de 20 en Windows.
10. Actualizar, modificar la colección o cambiar de cuenta invalida la caché. Las respuestas de una cuenta, navegación, petición o revisión anterior no pueden poblar ni reproducir el contexto nuevo.
11. Un error de página es recuperable y no guarda un catálogo parcial como completo. Si el proveedor repite una continuación, se informa un error en lugar de presentar un shuffle parcial como global.

El contrato reversible pertenece a la **lógica de reproducción** y se aplica a cualquier colección que reemplace la cola: playlists, likes, álbumes y canciones de artista. Las tandas de publicación siguen siendo específicas de playlists. En radios sólo se dispone de las recomendaciones ya recibidas; no se pueden mezclar recomendaciones que el proveedor todavía no entregó. Las nuevas recomendaciones conservan el orden de llegada como referencia y mantienen la deduplicación propia de radio.

### Orden de colección y canción actual

Al apagar shuffle se ordena **todo el álbum o playlist**, y se conserva la canción que suena por su identidad de ocurrencia, no por su índice anterior. La posición puede cambiar sin hacer seek, pausar, resolver otro stream ni cargar nuevamente la pista. El prefijo anterior en la vista ordenada muestra las posiciones originales de la colección; no pretende reconstruir el historial de escucha en shuffle.

Ejemplo con catálogo `A, B, C, D, E, F`: se escuchó `E` y está sonando `C`; las pendientes en shuffle son `F, A, D, B`. Se agrega `X` con Reproducir a continuación y `Y` al final:

```text
Antes:       E | C | X, F, A, D, B, Y
Shuffle OFF: A, B | C | X, D, E, F, Y
Shuffle ON:  A, B | C | X, F, D, E, Y   (un resultado posible)
             posiciones anteriores / actual / siguientes
```

`A` y `B` recuperan sus lugares antes de `C`; `E` recupera su lugar después aunque se hubiera escuchado. `X` permanece a continuación de `C` y `Y` al final. Si luego está sonando `X`, se conserva esa ocurrencia manual y se recalcula su índice al ordenar la fuente y recomponer sus anclas. Dos ocurrencias de `A` conservan identidades distintas aunque compartan `videoId`.

Caso de las capturas: en un álbum de 12 entradas, `Say You Will` es la primera en el orden original pero aparece sexta en shuffle. Al desactivar, las 12 entradas vuelven al orden del álbum y la misma ocurrencia de `Say You Will` pasa a la primera posición sin interrumpir la reproducción. Si la actual fuera la pista original número siete, debe quedar séptima, con las seis anteriores arriba y las cinco posteriores abajo; las manuales pueden desplazar ese índice según sus anclas.

## Implementación Windows que sirve de referencia

| Archivo | Responsabilidad |
|---|---|
| [`account/controller.ts`](../windows/src/lib/account/controller.ts) | `completePlaylists`, `likesHydration`, `catalogRevision`; hidratar y reutilizar todas las páginas, invalidar la caché y rechazar continuaciones repetidas. |
| [`queue.rs`](../windows/src-tauri/src/queue.rs) | Cola autoritativa completa, `source_ranks`/`next_source_rank` y `explicit_placements` internos, con colocaciones `After(entryId)`/`Before(entryId)`/`End`. `shuffle_on_start()` evita falso historial; `shuffle_after_current()` reorganiza fuente posterior, `restore_original_order()` proyecta bloques manuales sobre toda la fuente ordenada y recalcula la actual por identidad. `visible_len` limita publicación; `snapshot()` no expone ni copia los mapas completos. |
| [`lib.rs`](../windows/src-tauri/src/lib.rs) | `PlaybackManager::set_shuffle_mode()` aplica transiciones sólo si cambia el modo; `to_dto()` copia sólo la tanda publicada mediante `queue.snapshot()`. |
| [`commands/playback.rs`](../windows/src-tauri/src/commands/playback.rs) | `play_song` recibe el argumento optativo `shuffle` al reemplazar una colección; aplica el modo junto al reemplazo y `set_shuffle` cambia la política ON/OFF sin cargar de nuevo el audio. Avanzar por ocurrencias conserva el modo. |
| [`player/controller.ts`](../windows/src/lib/player/controller.ts) | Envía `shuffle` junto con la colección; una selección que conserva la cola envía `null` para no cambiar el modo. |
| [`+page.svelte`](../windows/src/routes/+page.svelte) | `playCollection()` entrega toda la colección en su orden original y comunica el modo en el mismo comando de reproducción. Al iniciar en shuffle elige un índice aleatorio; el gestor nativo organiza la cola. |

No trasladar Tauri, libmpv ni sus DTOs a Swift. Portar el comportamiento usando el reproductor AVPlayer y los contratos existentes de macOS.

## Puntos de entrada para el port macOS

| Archivo actual | Trabajo a realizar en macOS |
|---|---|
| [`QueueManager.swift`](../apple/Sources/SideB/Services/Player/QueueManager.swift) | Centralizar reemplazo, shuffle inicial, restauración completa y edición de cola. Separar cola completa, orden original por ocurrencia, anclas de manuales y tanda publicada. Recalcular la posición de la misma ocurrencia actual cuando cambia todo el orden. Las propiedades de navegación deben conservar el acceso al total. |
| [`PlaylistDetailViewModel.swift`](../apple/Sources/SideB/ViewModels/PlaylistDetailViewModel.swift) | Unificar Play, shuffle y selección con un catálogo completo compartido. Actualmente `shuffle()` mezcla sólo `playlist.items`, que puede contener únicamente la primera página. |
| [`AlbumDetailViewModel.swift`](../apple/Sources/SideB/ViewModels/AlbumDetailViewModel.swift), [`ArtistDetailViewModel.swift`](../apple/Sources/SideB/ViewModels/ArtistDetailViewModel.swift) | Dejar de enviar arrays `.shuffled()`; enviar orden canónico y modo al gestor. El shuffle de canciones de artista también debe usar esa política. |
| [`PlayerViewModel.swift`](../apple/Sources/SideB/ViewModels/PlayerViewModel.swift) | Aprovechar `hydrateLikedSongs()` para conservar también los metadatos y compartir su tarea con Play. Adaptar `playPlaylist()` y el avance para publicar tandas sin limitar la cola autoritativa. |
| [`MenuActionExecutor.swift`](../apple/Sources/SideB/UI/ContextMenu/MenuActionExecutor.swift) | Reutilizar la misma resolución/caché desde `loadCompletePlaylist()` y pasar arrays originales con modo. El menú contextual actual carga todo antes de shuffle, pero mezcla previamente las pistas y luego asigna `isShuffle`. |
| [`PlayerBarView.swift`](../apple/Sources/SideB/Views/Components/PlayerBarView.swift) | Mantener el botón como consumidor de la política central `toggleShuffle()`; no reconstruir la cola desde la vista. |
| [`PlaybackStateStore.swift`](../apple/Sources/SideB/Services/Player/PlaybackStateStore.swift) | Versionar persistencia para guardar orden canónico, identidad por ocurrencia, anclas de manuales y cola completa. Una tanda visible o una cola mezclada sin referencia original no permite restaurar correctamente el modo. |

Actualmente `extendPlaylistIfNeeded()` solicita la siguiente página y `appendPlaylistTracks()` la agrega sin mezclar, deduplicando por `videoId`. Copiar ese recorrido produciría shuffle parcial y podría eliminar ocurrencias repetidas. En el port, publicar la siguiente tanda de un catálogo ya completo debe ser una operación local, independiente de la paginación de red.

`hydrateLikedSongs()` también tiene un límite actual de diez páginas adicionales y corta silenciosamente ante errores. No considerar ese resultado completo si todavía hay continuación: resolver todas las páginas con detección de tokens repetidos y errores recuperables antes de usarlo como catálogo para shuffle global. Compartir la tarea e incorporar validación de cuenta para que una hidratación tardía no restaure datos de la cuenta anterior.

Revisar `checkAutomixTrigger()`: el umbral para ampliar la tanda visible es distinto del final real de la playlist. No iniciar radio/Automix cuando sólo se agotó la tanda y todavía quedan pistas del catálogo. Conservar cancelación, generación de cuenta y `queueToken` para rechazar trabajo obsoleto.

Las vistas deben consumir la tanda publicada, evitando copiar/renderizar toda la colección mediante `upNextTracks`. El transporte y la cola completa siguen siendo la fuente de verdad. La carga visual de más filas de la playlist puede continuar por páginas, separada del catálogo de reproducción.

### Plan de implementación macOS

1. **Modelo de cola por ocurrencia.** Introducir un identificador interno estable y un rango canónico por ocurrencia, asociado al propietario de cola. Se puede envolver `SongItemRecord` dentro de Swift sin cambiar records UniFFI ni el core. No usar `videoId` como clave única. `replaceQueue()` asigna identidad nueva y captura el orden de entrada antes de cualquier mezcla; una nueva colección limpia la metadata anterior. Ajustar selección, eliminación y movimientos para operar por esa identidad.
2. **Una sola política.** Recibir `shuffle` junto con el reemplazo. En inicio aleatorio, elegir una ocurrencia entre todo el catálogo, colocarla como actual en la posición cero y mezclar todas las otras; no inventar historial con los índices anteriores del array original. Al encender durante reproducción, conservar el prefijo hasta la actual y mezclar sólo las entradas de fuente posteriores. Al apagar, ordenar todas las ocurrencias presentes de la fuente por rango original, recomponer los bloques manuales y buscar la actual por su identidad para recalcular `currentIndex`. No limitar la restauración al sufijo ni conservar un índice de la cola mezclada como si fuera el índice real. No modificar `currentTrack`, resolver streams, hacer seek, llamar a Play ni cambiar la generación de audio por un toggle.
3. **Ediciones y radio.** `playNext`/`addTracksToQueue` generan ocurrencias manuales, incluso si sus `videoId` ya existen en la fuente. Modelar colocaciones explícitas `After(entryId)`, `Before(entryId)` o `End`: PlayNext encadena anclas desde la activa, hermanos conservan su orden actual y llamadas nuevas mantienen su prioridad; Append queda al final. Conservar el árbol cuando la actual es manual. Un arrastre usa Before/End y prevalece sobre su rango original como edición explícita. Evitar ciclos al mover anclas/dependientes; reanclar el vínculo que cause el ciclo al lugar previo. Al eliminar un ancla explícita, sus dependientes heredan su colocación; al eliminar una fuente, usar un vecino canónico para conservar el lugar de sus manuales. Eliminar también retira esa ocurrencia de la referencia; el toggle no la recrea. Radio/Automix incorporan recomendaciones con rangos nuevos por llegada y conservan su deduplicación; no reutilizar una referencia de la colección previa.
4. **Catálogo y publicación.** Resolver todas las páginas mediante una tarea compartida antes de afirmar shuffle global. Mantener todo el catálogo en el gestor y una tanda visible local de 100; crecer otras 100 al umbral de diez. Separar esa ampliación de las continuaciones de red y de `isNearTail`/Automix. Al ordenar, una actual de rango alto puede pasar de índice cero a índice 1750: ampliar el prefijo publicado hasta incluir esa posición real y sus siguientes, en lugar de truncar la cola a las primeras 100. Conservar también la visibilidad de todas las entradas explícitas que estaban publicadas antes de reanclarlas, sin exigir publicar el catálogo entero por defecto. No recortar la cola autoritativa a lo publicado.
5. **Entradas y estado atómicos.** Adaptar Play, selección y shuffle de playlist/álbum/artista y sus menús para entregar el array original. Evitar `.shuffled()` en consumidores y asignaciones de `isShuffle` después de Play. Serializar o descartar toggles obsoletos; comprobar la misma cola/`queueToken` después de cualquier espera. Invalidar catálogo y tareas por cuenta. Mantener botón, snapshots y orden final consistentes al pulsar ON/OFF/ON rápidamente.
6. **Persistencia por cuenta.** Ampliar `SavedPlaybackState` y adaptar tanto `PlayerViewModel.playbackSnapshot()` como `switchPlaybackSession(to:)`. Guardar cola completa y metadata original, identidad de la actual, modo y anclas/orden de bloques manuales; no guardar URLs de audio ni cookies. El historial real de escucha, si se conserva, debe ser separado del orden de la colección y de `currentIndex`. La versión 1 sólo guarda el array reproducido y `isShuffle`: **no se puede deducir de ahí el orden original**. Definir una migración explícita, por ejemplo conservar su orden guardado como nueva referencia y restaurar con shuffle apagado; probarla con duplicados y cuentas distintas. Restaurar toda la metadata conjuntamente, sin capturar la cola ya mezclada como si fuera el catálogo original.
7. **Comprobar en Mac.** Agregar pruebas puras de la política en `apple/Tests/SideBTests/QueueManagerShuffleTests.swift` y ampliar `PlaybackStateStoreTests.swift`. Ejecutar `swift test --package-path apple` desde la raíz en un Mac y los scripts existentes de build. Comprobar manualmente audio, sesión y paginación con la misma biblioteca de 2000 entradas.

Este port pertenece al gestor y a los consumidores macOS. La corrección Windows no cambia `core/`, los records UniFFI, el cipher ni AVPlayer; no hace falta crear dos cores ni trasladar Tauri a Swift.

### Prompt para ejecutar el port en el Mac

Después de sincronizar el código que contiene esta guía, se puede usar este encargo en el checkout macOS:

```text
Implementá en macOS el fix documentado en documentation/PLAYLIST_SHUFFLE_PORT.md.
Leé AGENTS.md y apple/AGENTS.md y comprobá git status antes de editar. Tomá las
pruebas y la política Windows de windows/src-tauri/src/queue.rs y lib.rs como
referencia de comportamiento. Conservá las funciones existentes de macOS,
AVPlayer, el cipher y los records/bindings UniFFI; no traslades Tauri/libmpv ni
modifiques el core compartido para introducir esta política de cola.

Planificá por modelo de cola, catálogo completo/cache, entrypoints, persistencia
y pruebas. Centralizá la política en QueueManager.swift: identidad por ocurrencia,
rango original, anclas/bloques manuales y publicación de playlists en tandas de 100.
Shuffle inicial recibe orden canónico, elige sobre todo el catálogo y coloca la
actual en índice cero sin falso historial. ON conserva el prefijo hasta la actual
y mezcla sólo entradas de fuente posteriores, incluidas las ocultas. OFF ordena
la colección ENTERA por rango original y reubica la misma ocurrencia actual en
su posición real; originales anteriores arriba y posteriores abajo. No ordenes
sólo pendientes ni mantengas el índice anterior mezclado. Puede haber temas ya
escuchados debajo de la actual al recuperar su posición original. No recrees
eliminadas ni reinicies audio, generación o posición temporal. PlayNext mantiene
bloques prioritarios anclados por entryId; Append queda al final. Un slot numérico
fijo no alcanza. La actual puede ser manual; recomponé anclas y buscá su identidad.
Si la actual pasa al índice 1750, el snapshot incluye ese índice real y siguientes.
Las colocaciones explícitas usan After(entryId), Before(entryId) o End; un drag
prevalece como edición explícita sobre su rango original. Conservá dependientes
y prioridad de bloques, evitá ciclos y reanclá al eliminar referencias sin perder
manuales ni reconstruir la ocurrencia eliminada.

Adaptá PlayerViewModel, PlaylistDetailViewModel, AlbumDetailViewModel,
ArtistDetailViewModel y MenuActionExecutor para enviar arrays originales y modo
juntos, sin .shuffled() previo ni isShuffle asignado después de Play. Reutilizá
tareas de likes/playlist, detectá errores y tokens repetidos, invalidá por cuenta
y separá ampliar la tanda del final real/Automix. Conservá queueToken y las
generaciones para descartar respuestas obsoletas y toggles rápidos.

Versioná PlaybackStateStore y adaptá exportación/restauración en PlayerViewModel:
cola completa, ocurrencias, orden original, anclas manuales, identidad actual
y modo. Separá historia de escucha del orden actual de la colección. Definí y
probá migración de versión 1 sin inventar orden original desde
un array mezclado. No persistás cookies ni URLs de audio.

Agregá pruebas puras QueueManagerShuffleTests y de PlaybackStateStore: 2000
ocurrencias, tanda 100/crecimiento, ON/OFF/ON, actual manual, varias PlayNext,
duplicados, eliminación, drag, radio, cambio de colección/cuenta y restauración.
Ejecutá swift test --package-path apple y los scripts de build existentes en
Mac. Las pruebas públicas de red sólo se habilitan expresamente con
SIDEB_LIVE_TESTS=1, cipher con SIDEB_LIVE_CIPHER=1 y cuenta real con
SIDEB_LIVE_ACCOUNT=1; esta última accede al Keychain. Distinguí pruebas/compilación
de la validación manual de audio, sesión, tiempos y memoria. Revisá el diff y
entregá archivos cambiados, resultados y límites reales del port.
```

## Pruebas que debe conservar el port

- Biblioteca de 2000 entradas: primera tanda de 100, ampliaciones de 100, última pista alcanzable y sin saltos ni duplicación de ocurrencias.
- Shuffle global: una pista fuera de las primeras 100 puede aparecer en la primera tanda; concatenar las tandas produce exactamente el orden completo ya mezclado.
- Activar/desactivar/reactivar shuffle durante la reproducción: ON mezcla las entradas de fuente posteriores; OFF restaura la fuente entera y recalcula el índice por identidad activa; el audio, generación y posición temporal no cambian. Verificar también las entradas ocultas y que eliminar una ocurrencia no permita recrearla.
- Shuffle inicial desde una ocurrencia avanzada: primera posición actual y sin falso historial; las restantes, anteriores y posteriores en el catálogo, quedan pendientes y elegibles.
- Álbum de 12 entradas, primera original en sexta posición del shuffle: OFF devuelve las 12 al orden original y mueve la actual a la primera posición. Repetir con actual original número siete: seis anteriores arriba y cinco posteriores abajo.
- Playlist de 2000, actual original 1750 en índice cero de shuffle: OFF recupera su índice canónico y el snapshot incluye la actual y próximas; navegar/Atrás/EOF usa los índices nuevos y no una selección obsoleta.
- Reproducir a continuación y añadir al final durante shuffle: OFF reconstruye anclas para mantener PlayNext inmediatamente después de su ocurrencia de referencia y Append al final. Incluir varias manuales consecutivas, PlayNext desde una manual activa y eliminación/movimiento del ancla.
- Duplicados de fuente y manual con el mismo `videoId`: conservar cantidades e identidad exacta de cada ocurrencia. Eliminar una de las repetidas no elimina ni resucita las otras al alternar el modo.
- Arrastrar una ocurrencia y luego apagar shuffle: conserva su colocación explícita Before/End y sus dependientes; el resto de fuente recupera el orden canónico. Probar ciclos entre anclas, eliminación de fuentes/manuales que anclan bloques y fallback estable sin pérdida. Reemplazar la colección limpia metadata anterior.
- ON/OFF/ON rápido durante resolución del stream, navegación, continuación de radio o cambio de cuenta: aceptar sólo estado vigente y no reiniciar audio.
- Persistencia: round trip de cola mezclada con manuales, anclas y duplicados; restauración y shuffle OFF recuperan colección completa e índice de la misma actual. Migrar versión 1 sin asumir que conoce el catálogo original y sin mezclar cuentas.
- Selección avanzada, Atrás, EOF, repetir, duplicados, cambio de playlist, eliminación, encolado manual y reordenamiento.
- Play mientras se hidratan likes: compartir las páginas pendientes y evitar una segunda descarga completa.
- Caché invalidada por refresh, mutaciones y cambio de cuenta; respuestas tardías descartadas.
- Error de red recuperable y continuación repetida: no presentar ni cachear un catálogo incompleto como completo.
- Álbumes y canciones de artista: mismo contrato reversible; no limitar shuffle a las primeras filas visibles. Radio: ordenar recomendaciones ya recibidas y comprobar llegada tardía sin contaminación de una cola reemplazada.

Pruebas Windows de referencia: [`account-controller.test.mjs`](../windows/scripts/account-controller.test.mjs), [`account-playlist-actions.test.mjs`](../windows/scripts/account-playlist-actions.test.mjs), [`playback-controller.test.mjs`](../windows/scripts/playback-controller.test.mjs), pruebas de `queue.rs` y de `PlaybackManager` en `lib.rs`.

## Verificación del fix inicial (2026-10-01)

En Windows pasaron `windows/scripts/windows.ps1 -Action verify`: tipos sin errores ni advertencias, 114 pruebas frontend, build frontend, 90 pruebas de `innertube`, 82 de `sideb-core` (7 pruebas en vivo ignoradas), 4 de `player` y 35 del bridge Tauri. También pasó `-Action build -Configuration debug`, con ejecutable standalone y `libmpv-2.dll` adyacente.

No se midieron tiempos con una cuenta real ni audio audible. Hubo advertencias de compilación del core/enlazador; los gates terminaron con éxito. macOS no fue modificado ni compilado en este host Windows. Al realizar el port, ejecutar `swift test --package-path apple` en un Mac y comprobar reproducción, tiempos de arranque y consumo de memoria con la misma biblioteca antes y después.

## Verificación anterior: restauración sólo de pendientes (2026-10-02)

Antes de la aclaración visual que exige ordenar la colección entera, pasaron las 117 pruebas frontend, la comprobación de tipos sin errores ni advertencias y la build frontend. Pasaron las 41 pruebas nativas del bridge Tauri, incluidas cinco regresiones de la política anterior de cola y una del gestor de reproducción: catálogo completo oculto, restauración de pendientes, manuales, duplicados, eliminación, movimientos, fuentes/radio y conservación de generación, posición e identidad activa. También se revisaron de forma independiente los consumidores y el flujo de reproducción. Esos resultados verificaban el contrato anterior; no demuestran por sí solos la restauración completa descrita ahora.

También pasó `windows/scripts/windows.ps1 -Action build -Configuration debug` con la configuración habitual: el ejecutable standalone abrió, creó la ventana y respondió, cargando `libmpv-2.dll` y `vulkan-1.dll` desde la carpeta de la build. Se reabrió la app de prueba con el fix.

Estas pruebas anteriores no prueban audio audible, tiempos ni hidratación con una cuenta real. El port Swift está pendiente: esta ampliación no modifica `apple/` ni `core/` y no se compiló macOS desde este host Windows.

## Verificación de restauración completa

Pasaron las **50 pruebas nativas Tauri, sin fallos**, con la política corregida: colección entera en orden original, índice canónico de la misma actual, transporte sin recarga ni cambio de generación/posición, PlayNext/Append anclados, eliminación y movimiento de referencias, ciclos y cadena de 2000 manuales. La prueba del álbum de 12 entradas reproduce el orden de las capturas; las de playlists verifican catálogo oculto completo y el prefijo publicado tras reubicar la actual. La cola, el transporte y sus consumidores también tuvieron revisión independiente.

Pasó `windows/scripts/windows.ps1 -Action build -Configuration debug`, incluida la build frontend. El ejecutable standalone abrió y respondió con una ventana Side B; cargó `libmpv-2.dll` y `vulkan-1.dll` desde la carpeta de la build. La app quedó abierta con esta versión para comprobar manualmente el comportamiento.

No hay cambios nuevos de frontend, `core/` ni `apple/` en esta corrección. Las advertencias existentes del core/enlazador no impidieron las pruebas ni la compilación. Audio audible, hidratación con cuenta real y port macOS siguen fuera de esta verificación automatizada.
