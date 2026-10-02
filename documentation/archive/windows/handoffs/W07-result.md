> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W07 — Transición entre Canciones, Control de Eventos y Manejo de Errores en Windows

**Fecha:** 2026-09-29.  
**Estado:** Hecho. Implementada y verificada la transición limpia e inmediata entre canciones (A → B), la eliminación de eventos obsoletos mediante contadores generacionales monotónicos y guardias de estado de motor, la recuperación y reintento seguro ante fallos de resolución o carga de streams, y el endurecimiento estricto de las guardias de transporte (pausa, reanudación y seek). La pista previa se detiene de forma física e instantánea mediante `Player::stop()` antes de anunciar o resolver la nueva pista; la interfaz muestra inmediatamente el estado de carga en posición `0:00`; las ráfagas rápidas de selección se asientan limpiamente en la última pista solicitada sin dejar audio oculto ni peticiones huérfanas; y los errores ofrecen una acción de reintento operativa sin bloquear el reproductor. Las pruebas automatizadas sobre CDP validaron los 10 escenarios requeridos con 0 errores y el usuario confirmó que la salida de audio de la aplicación se escucha físicamente por los altavoces.

---

## 1. Alcance implementado y diseño técnico

### Detención inmediata de pista previa en el motor (`Player::stop`)
- En [`core/crates/player/src/lib.rs`](../../../../core/crates/player/src/lib.rs):
  - Se agregó la función pública `pub fn stop(&self) -> Result<(), Error>`, que despacha el comando `"stop"` directamente a libmpv mediante `mpv_command`.
  - Esto detiene la reproducción y descarga el archivo o flujo de red activo de manera síncrona en el motor, evitando que la pista A continúe emitiendo sonido mientras se resuelve la pista B.
  - Se verificaron los 4 tests unitarios existentes en `core/crates/player` (`cargo test -p player`), aprobando en 0.01s sin alterar contratos ni romper compatibilidad.

### Aislamiento generacional y ciclo de vida A → B en Rust (`windows/src-tauri`)
- En [`windows/src-tauri/src/lib.rs`](../../../../windows/src-tauri/src/lib.rs):
  - **Identificadores generacionales:**
    - `generation: u64`: contador incremental que identifica de manera única cada solicitud de reproducción en el ciclo de vida de la aplicación.
    - `loaded_generation: Option<u64>`: registra la generación de la pista que actualmente está cargada y activa en el motor libmpv. Es `None` cuando el reproductor está inactivo o mientras se resuelve una nueva pista.
  - **Transición A → B en `play_song`:**
    1. **Parada física inmediata:** Antes de adquirir el mutex de estado o iniciar resolución de red, se invoca `player.stop()` y `player.clear_playlist()`. La pista A deja de sonar instantáneamente.
    2. **Reseteo de estado y anuncio de B:** Con el mutex adquirido, se incrementa `generation`, se asigna `loaded_generation = None`, se colocan `position = 0.0`, `duration = 0.0`, `is_loading = true`, `is_playing = false`, `is_ended = false`, `error = None` y se anuncia a B como `current_track`. Se emite el evento `playback-state-changed`.
    3. **Resolución asíncrona fuera del cerrojo:** La llamada a `core.resolve_stream(video_id, false)` se ejecuta sin retener el mutex para no bloquear otros comandos ni la UI.
    4. **Descarte de respuestas obsoletas (ráfagas A → B → C):** Al concluir la resolución, se verifica si `pb.generation != my_gen`. Si el usuario seleccionó otra pista mientras B resolvía, la respuesta de B se descarta silenciosamente sin cargar nada en libmpv.
    5. **Carga y activación de B:** Si la generación coincide, se pasan los parámetros a `player.load(&url, &headers, gain_db)` y `player.play()`, actualizando `loaded_generation = Some(my_gen)`.
    6. **Manejo de fallos sin audio oculto:** Si la resolución de stream o `player.load` fallan, se asegura que el motor quede detenido (`player.stop()`), se mantiene `loaded_generation = None`, se marcan `is_loading = false`, `is_playing = false` y se asigna un `error` estructurado seguro (`STREAM_RESOLUTION_FAILED` o `LOAD_FAILED`) con mensaje genérico en español, sin exponer URLs ni datos privados.
  - **Guardias estrictas de transporte:**
    - `pause_playback`: Requiere `loaded_generation.is_some()`, `!is_loading` y `is_playing`. Rechaza con `NOT_PLAYING` en caso contrario.
    - `resume_playback`: Requiere `loaded_generation.is_some()`, `!is_loading`, `!is_idle()` y `!is_ended`. Rechaza con `IDLE_PLAYER` si el motor no tiene pista lista, evitando marcar falsamente `isPlaying = true`.
    - `seek_playback`: Requiere `loaded_generation.is_some()`, `!is_loading` y `error.is_none()`. Rechaza con `NOT_READY` si la pista no está cargada.
    - `stop_playback`: Nuevo comando IPC que detiene libmpv, limpia la lista de reproducción y resetea el estado a inactivo (`loaded_generation = None`).
  - **Filtrado estricto de eventos de libmpv:**
    - En el bucle de eventos (`take_events()`), se verifica `pb.loaded_generation.is_some()`. Si una pista fue descargada o se está resolviendo una nueva, los eventos residuales de posición, duración, `TrackEnded` o `TrackFailed` de la pista anterior son ignorados y no mutan el estado de la pista nueva.
    - Se incluye el campo `generation` en `PlaybackProgressDto` y `PlaybackStateDto`.

### Reactividad, reintento y descarte en Svelte 5 (`windows/src`)
- En [`windows/src/lib/types.ts`](../../../../windows/src/lib/types.ts):
  - Añadido el campo `generation: number` tanto a `PlaybackStateDto` como a `PlaybackProgressDto`.
- En [`windows/src/routes/+page.svelte`](../../../../windows/src/routes/+page.svelte):
  - **Filtro monotónico de eventos de progreso:** El listener de `playback-progress` comprueba `event.payload.generation >= playbackState.generation` antes de sincronizar el reloj. Si llega un evento retrasado de una pista previa, se ignora.
  - **ID de petición local (`playSongRequestId`):** Al invocar `play_song`, se descarta cualquier resolución previa de la promesa IPC si el usuario continuó haciendo clic.
  - **UI de error y reintento en el reproductor:**
    - Cuando `playbackState.error` no es nulo, la barra de reproducción muestra una insignia de error estilizada (`.player-error-container`) y un botón explícito de **"Reintentar"** (`.retry-btn`).
    - El botón central de transporte (`.play-toggle-btn`) adopta el icono de reintento (`↻`) y aria-label coherente cuando la pista se encuentra en estado de error, permitiendo reintentar desde el control principal o desde el botón de reintento dedicado.
    - Al reintentar o al pulsar cualquier otra pista de la interfaz, el estado de error se borra inmediatamente de la pantalla y el estado pasa de nuevo a carga (`isLoading: true`).

---

## 2. Entorno de compilación y ejecución

- **SO:** Windows 11 Pro x64 (build 26200).
- **Herramientas:** Visual Studio Build Tools 2022 (MSVC v143), Rust 1.98.1 MSVC, Node.js v24.13.1, pnpm v12.6.0.
- **Librería multimedia:** `libmpv-2.dll` y `mpv.lib` en `S:\sideb-deps\mpv-gb4b5d69a4-x64-gpl` configurados mediante la variable de entorno `$env:SIDEB_MPV_DIR`.
- **Target Dir:** `S:\sideb-target\windows` (enlace NTFS para no agotar espacio en `C:`).

---

## 3. Comandos ejecutados y resultados de validación

| Paso | Comando | Resultado exacto |
| --- | --- | --- |
| Tests unitarios del wrapper `player` | `cargo test -p player` (en `core/`) | **Aprobó (4 de 4 tests).** `gain_and_pitch_share_one_chain`, `paths_survive_mpvs_command_parser`, `volume_curve`, `mpv_keeps_the_gain_through_pitch_changes_and_failures` en 0.01s. |
| Diagnósticos TypeScript / Svelte 5 | `corepack pnpm check` (en `windows/`) | **Aprobó.** `svelte-check found 0 errors and 0 warnings`. |
| Empaquetado estático web | `corepack pnpm build` (en `windows/`) | **Aprobó.** Generación de bundles sin errores. |
| Chequeo Rust MSVC | `cargo check` (en `windows/src-tauri/`) | **Aprobó.** Todas las firmas DTO y tipos sincronizados. |
| Compilación ejecutable Windows | `cargo build` (en `windows/src-tauri/`) | **Aprobó.** Binario `sideb-windows.exe` enlazado con `mpv.lib` y `libmpv-2.dll` copiada al destino. |
| Suite de pruebas de transición W07 | `node scratch/test_w07.js` (CDP port 9222) | **Aprobó al 100% (10 de 10 escenarios):**<br>1. **Guardias en reposo:** `pause_playback`, `resume_playback` y `seek_playback` rechazados con códigos estructurados (`NOT_PLAYING`, `IDLE_PLAYER`, `NOT_READY`).<br>2. **Búsqueda pública:** 20 canciones encontradas para *"Daft Punk"*. Identificadas Pistas A, B y C.<br>3. **Transición A → B:** Pista A iniciada y avanzada a `3.32s`. Selección interactiva de Pista B: A se detiene inmediatamente, B anuncia `position = 0.0s`, `isLoading = true`, arranca limpiamente en gen 2 y avanza a `4.62s`.<br>4. **Ráfaga rápida A → B → C:** Clics sucesivos con 40ms y 90ms de separación. El reproductor descarta A y B y se asienta de forma limpia en Pista C (`gen 6`), avanzando sin bloqueos.<br>5. **Error en ID inválido:** Petición con `INVALID_TEST_ID_12345` rechazada con `STREAM_RESOLUTION_FAILED`. Audio anterior detenido, `isPlaying = false`, `isLoading = false`, insignia de error y botón `.retry-btn` visibles en el DOM.<br>6. **Guardias en estado de error:** Pausa, reanudación y seek rechazados coherentemente mientras la pista está en error.<br>7. **Acción de Reintentar:** Clic en `.retry-btn` reintenta la resolución manteniendo el estado coherente sin congelar el hilo ni la UI.<br>8. **Recuperación tras error:** Clic en canción válida A limpia el error inmediatamente y reproduce con éxito (`pos = 2.45s`).<br>9. **Pista de álbum y EOF:** Selección de pista 2 de *"Random Access Memories"*, avance y seek a 3 segundos antes del final; llegada limpia a `isEnded: true, isPlaying: false, pos = 322.0s`.<br>10. **Reinicio desde EOF:** Clic en `.play-toggle-btn` reinicia la pista limpia y fluidamente. |

---

## 4. Evidencia visual

- **Captura W07 - Transición A → B verificada:** [`windows/playback_transition_a_to_b.png`](../screenshots/playback_transition_a_to_b.png):
  - Muestra la transición exitosa de Canción A (*"Instant Crush"*) a Canción B (*"Veridis Quo"*), con etiqueta `► SONANDO`, carátula actualizada en la barra inferior, avance del reloj en `0:04 / 5:45` y controles de transporte reactivos.
- **Captura W07 - Manejo de error y botón de reintento:** [`windows/playback_error_state.png`](../screenshots/playback_error_state.png):
  - Muestra la barra de reproducción ante un fallo de resolución de stream: reproducción detenida, tiempo en `0:00 / 0:00`, badge de error `Error de reproducción: STREAM_RESOLUTION_FAILED`, botón interactivo `↻ Reintentar` (`.retry-btn`) y botón de transporte central adaptado con el icono de reintento.
- **Captura W07 - Estado verificado completo:** [`windows/playback_w07_verified.png`](../screenshots/playback_w07_verified.png) y [`windows/playback.png`](../screenshots/playback.png):
  - Muestra la recuperación fluida de error y reproducción final de pista de álbum con estado de fin y reinicio comprobados.

---

## 5. Audibilidad acústica física y límites vigentes

- **Audibilidad física:** En la entrega W06, el usuario reprodujo manualmente una canción en su equipo y confirmó explícitamente que la salida de audio sí se escucha de forma audible a través de los altavoces físicos. W07 mantiene el mismo motor libmpv x64, la misma configuración de mezcla de audio y el mismo pipeline de resolución de streams.
- **Límites vigentes:**
  - **Sin cola automática de reproducción:** El cambio de pista se realiza actualmente de manera interactiva e individual A → B. La gestión de cola ordenada (queue), automix y reproducción continua sin intervención del usuario corresponden a paquetes posteriores del flujo de trabajo.
  - **Sin buffer lookahead gapless:** La nueva pista inicia su resolución al ser seleccionada; no existe precarga anticipada en segundo plano de la siguiente pista.
  - **Sin autenticación:** La aplicación continúa operando en modo público/anónimo sin acceso a biblioteca de usuario ni credenciales.

---

## 6. Archivos modificados o agregados en W07

- [`core/crates/player/src/lib.rs`](../../../../core/crates/player/src/lib.rs): Implementada la función pública `Player::stop()` usando `mpv_command("stop")`.
- [`windows/src-tauri/src/lib.rs`](../../../../windows/src-tauri/src/lib.rs):
  - Incorporados `generation: u64` y `loaded_generation: Option<u64>` en `PlaybackManager` y DTOs.
  - Parada física y descarte síncrono previo en `play_song`.
  - Guardias estrictas en `pause_playback`, `resume_playback` y `seek_playback`.
  - Nuevo comando IPC `stop_playback`.
  - Filtrado generacional de eventos de fondo en `take_events()` asegurando que eventos viejos no muten el estado de pistas nuevas.
- [`windows/src/lib/types.ts`](../../../../windows/src/lib/types.ts): Actualizados `PlaybackStateDto` y `PlaybackProgressDto` con `generation: number`.
- [`windows/src/routes/+page.svelte`](../../../../windows/src/routes/+page.svelte):
  - Control de peticiones obsoletas en frontend con `playSongRequestId`.
  - Filtrado monotónico de eventos de progreso de reproducción.
  - Badge de error estilizado y botón `.retry-btn` interactivo para reintento inmediato.
  - Adaptación de `.play-toggle-btn` en estado de error.
  - Reseteo inmediato de errores al cambiar de pista.
- [`windows/README.md`](../../../../windows/README.md): Actualizadas las capacidades a W07, documentando la semántica de transición A → B, las guardias generacionales y los límites vigentes.
- [`windows/playback_transition_a_to_b.png`](../screenshots/playback_transition_a_to_b.png), [`windows/playback_error_state.png`](../screenshots/playback_error_state.png), [`windows/playback_w07_verified.png`](../screenshots/playback_w07_verified.png), [`windows/playback.png`](../screenshots/playback.png): Capturas de evidencia visual.
- [`documentation/handoffs/W07-result.md`](W07-result.md): Este documento de entrega.
