# UX-04 · Radio de canciones y acciones de cola

## Decisión
Una canción de Inicio debe iniciar radio, como macOS. Reproducir la seleccionada inmediatamente y obtener recomendaciones en segundo plano con `core.get_radio`; conservarla como primera entrada una sola vez. El core ya maneja next/automix. Rust conserva autoridad sobre cola, metadata y EOF.

## Contrato
- RPC `start_song_radio {song:SongDto}` → PlaybackStateDto; `retry_radio {}` → PlaybackStateDto; `enqueue_tracks {items:QueueEntryDto[],position:"next"|"end"}` → PlaybackStateDto; `remove_queue_entry {entryId}` → PlaybackStateDto.
- Metadata opcional `artistId`, `albumId`, `album` en entradas/currentTrack. Estado de radio opcional en cola: `{loading:boolean,error:string|null,canRetry:boolean}`. Error de radio no interrumpe audio ni ocupa el error fatal del reproductor.
- Epoch de propietario de cola independiente de generación de audio: sólo reemplazar cola/cambiar sesión invalida radio. Capturar también generación de autorización; nunca sostener Mutex/RwLock durante await. Un request de radio en vuelo por propietario.
- Fuente `{kind:"radio",id:seedVideoId,title:seedTitle}`. Continuar cuando queden ≤3 pistas con `get_radio_continuation(lastVideoId,seed)`; deduplicar recomendaciones por videoId contra cola de radio. Playlists/encolado manual conservan ocurrencias repetidas.
- Resultado vacío/sin pistas nuevas termina la continuación; error permite reintento explícito sin bucle. EOF esperando una continuación debe avanzar una vez cuando llegue una pista, con guards de epoch/generación; ninguna respuesta vieja cambia otra cola.
- Encolar siguiente/final conserva currentTrack/posición e identidad actual; quitar usa entryId, rechaza pista actual y mantiene el índice si se elimina una anterior. Crear IDs únicos aunque el cliente repita IDs. No iniciar audio por agregar a una cola vacía.
- Referencia: `apple/Sources/SideB/Services/Player/QueueManager.swift` y APIs existentes sideb-core.

## Propiedad y verificación
Agente backend: queue.rs/dto.rs/lib.rs/commands playback y módulos nuevos. Root: PlaybackController y acciones Inicio/menú. Pruebas puras de duplicados/índices/epochs/EOF y errores no fatales; no tests de red con cuenta real.

Manual: canción Inicio → cola con recomendaciones, next/previous y carátula sincronizados; cambiar rápido de canción durante carga; agregar siguiente/final y quitar una ocurrencia distinta de la actual.
