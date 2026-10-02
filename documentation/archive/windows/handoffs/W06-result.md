> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W06 — Primera Canción y Reproductor Mínimo en Windows (M2/M3 parcial)

**Fecha:** 2026-09-29.  
**Estado:** Hecho. Implementada la reproducción real de canciones y pistas de álbum desde el shell nativo Tauri 2 en Windows mediante la integración de `SideBCore::resolve_stream` con el crate `core/crates/player` sobre **libmpv** x64. Contratos IPC y DTOs tipados en Rust y TypeScript; barra de reproducción persistente en Svelte 5 con controles completos y funcionales (play/pausa, barra de progreso con seek interactivo, volumen, estados de carga, error y fin de pista con reinicio). Verificada la reproducción real de canciones desde Búsqueda y Detalle de Álbum, el avance continuo del reloj, los controles de transporte, el evento EOF limpio, el bloqueo coherente de reanudación en estado inactivo y el reinicio de pista en la PC Windows mediante pruebas automatizadas sobre CDP. Se respeta estrictamente la privacidad: ninguna URL firmada ni cabecera de red sale hacia el frontend, DOM, eventos o logs. `apple/`, `innertube` y `sideb-core` se mantuvieron intactos.

---

## 1. Alcance implementado y arquitectura de audio

- **Integración de `core/crates/player` y `libmpv` sin rutas hardcodeadas:**
  - Se incorporó `core/crates/player` como miembro del workspace en [`core/Cargo.toml`](../../../../core/Cargo.toml) y como dependencia por ruta en [`windows/src-tauri/Cargo.toml`](../../../../windows/src-tauri/Cargo.toml).
  - Se eliminaron todas las rutas absolutas hardcodeadas (`S:\sideb-deps...`) de los scripts de build y del código de la app.
  - La ruta a libmpv se parametriza mediante la variable de entorno explícita `SIDEB_MPV_DIR` en [`core/crates/player/build.rs`](../../../../core/crates/player/build.rs) y [`windows/src-tauri/build.rs`](../../../../windows/src-tauri/build.rs).
  - `build.rs` copia `libmpv-2.dll` al directorio de salida (`target/debug/` o `target/release/`) comprobando errores explícitamente (`expect(...)`). En tiempo de ejecución, la aplicación en [`windows/src-tauri/src/lib.rs`](../../../../windows/src-tauri/src/lib.rs) utiliza la DLL ubicada junto al ejecutable (`sideb-windows.exe`), haciendo que el binario sea portable y desacoplado del entorno de compilación.
  - La creación del directorio de caché de audio maneja errores de forma segura sin ignorar fallos del sistema de archivos.
  - Los 4 tests unitarios de `player` pasaron satisfactoriamente en Windows x64.
- **Resolución de streams y ciclo de vida de reproducción en Rust:**
  - En [`windows/src-tauri/src/lib.rs`](../../../../windows/src-tauri/src/lib.rs):
    - `play_song(video_id, title, artists, thumbnail) -> Result<PlaybackStateDto, CommandError>`: resuelve el stream de forma asíncrona mediante `core.resolve_stream(video_id, false)`. Valida identificadores vacíos, libera cerrojos durante la espera de red y utiliza un contador generacional (`generation`) para descartar resoluciones lentas obsoletas si el usuario selecciona otra pista. Pasa la URL resuelta, las cabeceras requeridas y la ganancia de sonoridad (`loudness_db`) directamente a `player.load(&url, &headers, gain_db)` y llama a `player.play()`.
    - **Timing correcto:** `play_song` **no** marca `isPlaying = true` de forma prematura; devuelve inmediatamente `{ isPlaying: false, isLoading: true, isEnded: false, ... }`, delegando el estado de reproducción activo a la llegada del evento `PlayerEvent::Playing(true)` desde libmpv.
    - `pause_playback() -> Result<PlaybackStateDto, CommandError>`: pausa la reproducción en libmpv y actualiza el estado.
    - `resume_playback() -> Result<PlaybackStateDto, CommandError>`: incluye una **guardia estricta** contra reproductor inactivo o pista finalizada (`if player.is_idle() || pb.is_ended`), rechazando con el error estructurado `IDLE_PLAYER` en vez de marcar falsamente `isPlaying = true`.
    - `seek_playback(seconds: f64) -> Result<PlaybackStateDto, CommandError>`: ejecuta seek absoluto en segundos comprobando números finitos y positivos.
    - `set_playback_volume(volume: f64) -> Result<PlaybackStateDto, CommandError>`: ajusta el volumen aplicando la curva perceptual a nivel escala 0–100%.
    - `get_playback_state() -> Result<PlaybackStateDto, CommandError>`: sincroniza el estado actual para la interfaz o tras recargas.
- **Canal de eventos, fin de pista (EOF) y telemetría segura:**
  - Bucle en segundo plano consumiendo eventos de `player.take_events()`:
    - Emite `playback-state-changed` cuando cambia el estado de reproducción (`Playing`), duración (`Duration`), fin de pista (`TrackEnded`) o fallo (`TrackFailed`).
    - Emite `playback-progress` para actualizaciones de posición temporal, limitando la tasa de emisión a ~5 Hz (cada 200 ms) para evitar sobrecargar el hilo del WebView2.
    - **Manejo de EOF:** Al llegar a fin de pista (`TrackEnded`), se actualiza `is_ended = true`, `is_playing = false` y `position = duration`, notificando de inmediato a la UI.
    - **Privacidad estricta:** Ni la URL de googlevideo ni las cabeceras HTTP o cookies se envían en eventos, DTOs, DOM o logs. Los errores se empaquetan en `CommandError` seguros y los registros de mpv se silenciaron (`LIMUSIC_MPV_LOG=no`).
- **Interfaz Svelte 5 y controles reactivos:**
  - En [`windows/src/routes/+page.svelte`](../../../../windows/src/routes/+page.svelte):
    - **Barra de reproducción persistente:** Ubicada en la parte inferior (`footer.player-bar`) con carátula de pista, título, artista, botón de transporte reactivo (`.play-toggle-btn`), deslizador interactivo de seek con tiempo actual y duración formateados (`m:ss`), deslizador de volumen (0–100%) y badge de error seguro.
    - **Reinicio ante EOF:** Cuando `playbackState.isEnded` es verdadero, el botón central adopta el icono de repetición/reinicio (⟲) y al hacer clic reinicia la reproducción de la pista actual desde el inicio.
    - **Filas interactivas:** Las filas de canciones en resultados de búsqueda y las pistas del detalle de álbum son botones interactivos accesibles por teclado (Enter / Espacio) y clic. Al activarse, muestran la indicación `► SONANDO` y borde resaltado.
    - **Suscripción y limpieza:** Listeners de eventos de Tauri tipados, sincronización de estado en `onMount` y desuscripción garantizada en el retorno de ciclo de vida.
- **Tipos TypeScript:**
  - En [`windows/src/lib/types.ts`](../../../../windows/src/lib/types.ts): interfaces `PlaybackTrackDto`, `PlaybackStateDto` (con campo `isEnded: boolean`) y `PlaybackProgressDto`.

---

## 2. Entorno de compilación y ejecución

- **SO:** Windows 11 Pro x64 (build 26200).
- **CPU:** AMD Ryzen 5 5500 (6 núcleos, 12 hilos).
- **RAM:** 16 GB.
- **DPI:** 96 (100 %).
- **Herramientas:** Visual Studio Build Tools 2022 (MSVC v143), Rust 1.98.1 MSVC, Node.js v24.13.1, pnpm v12.6.0.
- **Librería multimedia:** `libmpv-2.dll` y `mpv.lib` en `S:\sideb-deps\mpv-gb4b5d69a4-x64-gpl`.
- **Target Dir:** `S:\sideb-target\windows` (unión NTFS para preservar espacio en disco `C:`).
- **Variable de entorno:** `$env:SIDEB_MPV_DIR = "S:\sideb-deps\mpv-gb4b5d69a4-x64-gpl"`.

---

## 3. Comandos ejecutados y resultados exactos

| Paso | Comando | Resultado exacto |
| --- | --- | --- |
| Tests unitarios del wrapper `player` | `cargo test -p player` (en `core/`) | **Aprobó (4 de 4 tests).** `gain_and_pitch_share_one_chain`, `paths_survive_mpvs_command_parser`, `volume_curve`, `mpv_keeps_the_gain_through_pitch_changes_and_failures` en 0.01s. |
| Diagnósticos TypeScript / Svelte 5 | `corepack pnpm check` (en `windows/`) | **Aprobó.** `svelte-check found 0 errors and 0 warnings`. |
| Empaquetado estático web | `corepack pnpm build` (en `windows/`) | **Aprobó en 4.00s.** Bundles generados sin advertencias. |
| Chequeo Rust MSVC | `cargo check` (en `windows/src-tauri/`) | **Aprobó en 9.64s.** Dependencias de `player` y `sideb-core` validadas. |
| Compilación ejecutable Windows | `cargo build` (en `windows/src-tauri/`) | **Aprobó.** Binario `sideb-windows.exe` enlazado con `mpv.lib` y `libmpv-2.dll` copiada al destino junto al ejecutable. |
| Ejecutable con interfaz incorporada (revisión Codex) | `corepack pnpm tauri build --debug --no-bundle` (en `windows/`, VS 2022 x64 y `SIDEB_MPV_DIR` definidos) | **Aprobó en 2m 57s.** Con Vite apagado, el `.exe` abrió Inicio, buscó 20 canciones de *Daft Punk* y reprodujo *Veridis Quo (Edit)* con posición observada en `0:05`; se cerró y reabrió dejando el reproductor detenido. Esto comprueba funcionamiento autónomo del binario de prueba, no un instalador. |
| Verificación interactiva CDP | `node scratch/test_playback.js` | **Aprobó suite completa con 0 errores:**<br>1. **Búsqueda pública:** 20 canciones encontradas para *"Daft Punk"*. Primera canción: *"Veridis Quo (Edit)"* / *"Instant Crush"*.<br>2. **Timing de `play_song`:** Devuelve de inmediato `isPlaying: false, isLoading: true, isEnded: false`.<br>3. **Arranque de reloj:** Al llegar el evento de libmpv, `isPlaying: true`, posición avanza de 0.30s a 6.34s en 6 segundos continuos.<br>4. **Pausa:** `isPlaying: false`, posición congelada en 6.39s tras 2s.<br>5. **Reanudar:** `isPlaying: true`, posición avanza a 8.42s.<br>6. **Seek:** Salto a 45.0s comprobado, avance continuado a 46.95s.<br>7. **Volumen:** Ajustado exitosamente al 70%.<br>8. **Prueba de EOF:** Seek a 334.56s (duración 337.56s). Tras 3 segundos se recibe evento `TrackEnded`, pasando limpiamente a `isEnded: true, isPlaying: false, pos: 337.56s`.<br>9. **Guardia de inactividad:** Intento de `resume_playback` en estado EOF es rechazado con error `IDLE_PLAYER` (*"La pista ha finalizado o no hay reproducción activa para reanudar."*).<br>10. **Reinicio por UI:** Clic en `.play-toggle-btn` en estado finalizado reinicia la canción exitosamente (`isPlaying: true, isEnded: false, pos: 0.11s`).<br>11. **Pista de álbum:** Apertura del álbum *"Random Access Memories"*, selección de pista 2 *"The Game of Love"*, reproducción iniciada y avance a 4.90s comprobado. |

---

## 4. Evidencia visual

- **Captura W06 - Reproducción de Canción desde Buscar:** [`windows/playback_search_song.png`](../screenshots/playback_search_song.png):
  - Canción *"Instant Crush (feat. Julian Casablancas)"* seleccionada con etiqueta `► SONANDO`.
  - Barra de reproducción inferior visible: carátula del álbum, título, artista, botón de pausa activo, barra de seek con progreso `0:06 / 5:37` y volumen al 70%.
- **Captura W06 - Reproducción de Pista desde Detalle de Álbum:** [`windows/playback_album_track.png`](../screenshots/playback_album_track.png):
  - Detalle del álbum *"Random Access Memories"* con 13 pistas reales.
  - Barra de reproducción inferior visible: carátula, pista *"The Game of Love"*, artista *"Daft Punk"*, botón de pausa activo, progreso `0:04 / 5:22` y volumen al 70%.
- **Captura general de entrega:** [`windows/playback.png`](../screenshots/playback.png).

---

## 5. Declaración de límites y audibilidad física

- **Comprobación acústica vs. telemetría:** Las pruebas automatizadas verifican rigurosamente de extremo a extremo la resolución del stream en InnerTube, la carga de URLs firmadas en libmpv, el reloj de transporte, el avance temporal continuo, la respuesta a pausa/seek/volumen, el evento EOF limpio y el reinicio. **No obstante, no se realizó captura directa ni medición del flujo acústico hacia altavoces/auriculares físicos mediante sondas de audio del SO**, por lo que la audibilidad acústica física en los altavoces no fue grabada ni medida directamente.
- **Confirmación del usuario (2026-09-29):** el usuario reprodujo la canción en su equipo y confirmó que sí se escucha por la salida de audio. Es una comprobación manual de audibilidad, distinta de una medición de loopback del SO.
- **Límites vigentes:** El reproductor actual maneja una pista activa a la vez; la cola de reproducción, automix y reproducción continua entre pistas corresponden a paquetes posteriores. No hay sesión de usuario ni biblioteca autenticada.

---

## 6. Archivos modificados o agregados en W06

- [`core/Cargo.toml`](../../../../core/Cargo.toml): Agregado `crates/player` a `workspace.members`.
- [`core/crates/player/build.rs`](../../../../core/crates/player/build.rs): Script de build para resolver el enlace nativo con `mpv.lib` en Windows mediante la variable explícita `SIDEB_MPV_DIR` (sin rutas fijas).
- [`windows/src-tauri/Cargo.toml`](../../../../windows/src-tauri/Cargo.toml): Añadida la dependencia `player = { path = "../../core/crates/player" }`.
- [`windows/src-tauri/build.rs`](../../../../windows/src-tauri/build.rs): Configurado enlace de `mpv.lib` mediante `SIDEB_MPV_DIR` y copia obligatoria de `libmpv-2.dll` al directorio de destino del perfil sin tragar errores.
- [`windows/src-tauri/src/lib.rs`](../../../../windows/src-tauri/src/lib.rs): Inicialización de `Player`, directorio de caché de audio con manejo de error, bucle de eventos con manejo de `TrackEnded` (`is_ended = true`), comandos `play_song` (sin falso `isPlaying` prematuro), `pause_playback`, `resume_playback` (con guardia `is_idle` / `is_ended`), `seek_playback`, `set_playback_volume`, `get_playback_state`, DTOs de reproducción (`PlaybackStateDto.isEnded`) y privacidad estricta de logs y URLs.
- [`windows/src/lib/types.ts`](../../../../windows/src/lib/types.ts): Tipos TypeScript `PlaybackTrackDto`, `PlaybackStateDto` (con `isEnded: boolean`) y `PlaybackProgressDto`.
- [`windows/src/routes/+page.svelte`](../../../../windows/src/routes/+page.svelte): Barra de reproducción persistente inferior, controles de transporte, seek y volumen, botón de reinicio al terminar la pista, interactividad en canciones y pistas de álbum, suscripciones a eventos con limpieza de listeners y adaptación accesible sin warnings.
- [`windows/README.md`](../../../../windows/README.md): Documentación de configuración con variable explícita `SIDEB_MPV_DIR`, resolución de la DLL junto al ejecutable, hash y comandos reproducibles.
- [`windows/playback_search_song.png`](../screenshots/playback_search_song.png), [`windows/playback_album_track.png`](../screenshots/playback_album_track.png), [`windows/playback.png`](../screenshots/playback.png): Capturas de verificación visual actualizadas.
- [`documentation/handoffs/W06-result.md`](W06-result.md): Este informe de entrega.
