# PLAN-024 — Automix: transiciones automáticas con stems

- Fecha: 2026-11-15 (America/Montevideo).
- Estado: motor y contrato del core hechos y probados con audio sintético y pares reales; integraciones de Windows y Mac hechas por otros encargos; **ronda 2 (latencia): versión rápida sin modelo, modelo caliente en CPU de CoreML, tramos mínimos y precarga**. Sin escucha: la calidad sonora no está evaluada.
- Rama / carpeta: `feature/automix` (`sideb-wt-automix-lab/`). Motor en [`core/crates/automix`](../core/crates/automix); contrato en `core/crates/sideb-core` (`automix_job.rs`); banco de pruebas en [`labs/automix-lab/`](../labs/automix-lab/README.md).
- Objetivo: que Side B una dos canciones como lo haría un DJ (tempos sincronizados, entrada en compás, cambio de bajo, una sola voz a la vez) en vez de un crossfade.

## Idea central

La transición no se mezcla en vivo: se renderiza por adelantado mientras suena la canción actual y el reproductor cambia **una sola vez**, de la canción A al archivo; desde ahí B suena entera del archivo. El archivo contiene, en orden: `pre` segundos de A sin tocar (8 por defecto), la transición y TODO el resto de B sin tocar hasta su final.

## Alcance y exclusiones

Incluye: el motor (`automix`), `sideb-core` (feature `automix`, activa por defecto en ambas apps) y el banco de pruebas. El core autoriza el trabajo del usuario (2026-11-15) pese a que `core/` es protegido: es una función nueva compartida, no un fix.

Excluye por ahora: cambios en `apple/` (salvo, si hiciera falta, ajustes de enlazado) y `windows/`, el reproductor (AVPlayer en Mac, libmpv en Windows) y cualquier UI. El motor no usa la cuenta más allá de lo que ya hace `resolve_stream`.

## Contrato

### Motor (`automix`)

`automix::prepare(a: &Track, b: &Track, cache: &Path, opts: &Options) -> Result<Transition>` no falla con audio analizable. Baja por una escalera:

| Tipo | Cuándo | Qué hace |
|---|---|---|
| `Kind::Mix` | tempos a menos de 25 % (en la octava de A) y grillas fiables | mezcla con tempo deslizante y cambio de bajo (8 o 4 compases; el plan se hace sin el modelo, ver «Calidad») |
| `Kind::Cut` | tempos demasiado lejanos, u otra negativa de la mezcla, con ambas grillas fiables | A sale en un compás (1–2 compases) con barrido de filtro y eco *ping-pong* sincronizado (3/4 de beat); B entra limpio a su tempo en su primer tiempo, **un compás de A** después de la última línea de compás de A. Sin stems |
| `Kind::Fade` | sin grilla fiable | A se apaga en ~6 s terminando cerca de su final audible; B arranca en su inicio audible, sin entrada gradual, ~1 s de solape |

`Transition`: `kind`, `audio` (todo el archivo, ya con las ganancias), `a_cut`, `overlap_start`, `overlap_end`, `b_offset`, `b_entry`, `handover`, `bpm_a`, `bpm_b`, `bars`, `stems_model`, `separated_seconds`, `same_cut_as_fast`, `detail` (español), `baseline` (sólo el banco). Todas las horas «archivo» son segundos del WAV.

- Antes de `overlap_start` el archivo es A **muestra por muestra** (× ganancia) a partir del segundo `a_cut` de A.
- Desde `overlap_end` es B muestra por muestra (× ganancia): `segundo de B = segundo del archivo − b_offset`, exacto. Antes de `b_entry` B no está en el archivo.
- `handover`: segundo del archivo en que la UI debe pasar a mostrar B (cambio de bajo en `Mix`; entrada de B en `Cut` y `Fade`).
- `Options`: `pre_seconds` (8), `post_seconds` (infinito = B entera), `max_bars` (16), `stem_mode` (`Auto` por defecto), `a_gain`/`b_gain` lineales, `baseline`, `cancel` (`Arc<AtomicBool>`; se revisa entre etapas, una separación en curso termina), y para el banco `a_downbeat_shift`/`b_downbeat_shift`.
- **Calidad.** El plan (grilla, largo del solape, punto de corte, entrada de B) se hace **siempre sobre la separación por frecuencias** (`StemMode::Frequency`: graves por debajo de 180 Hz y el resto), sin el modelo ni el stem de voz. Como no sabe dónde canta cada una, el solape se limita a 8 compases y no se saltea el final instrumental de A (antes, con el stem de voz, podía ser de 16 y B podía cantar sobre ese final). Con `StemMode::Frequency` la mezcla (versión «rápida») cruza los graves en la línea de compás central y el resto del espectro, voces incluidas, en el compás que la rodea (`eq_swap_gains`). Con `StemMode::Model` (versión «stems»), `Plan::upgrade` **separa con HT-Demucs sólo los tramos que el render lee** (el solape más 4 s de contexto a cada lado, de cada canción), y con el stem de voz decide cuándo entra a cantar B dentro del solape y si las armonías chocan; el plan no se toca, así que **`a_cut` y todo el resto del archivo coinciden con la versión rápida** (`same_cut_as_fast`, siempre `true` hoy; está en el contrato por si algún día el plan usa el modelo). `StemMode::Auto` elige `Model` si el modelo está en disco y si no `Frequency` y arranca su descarga. Si el modelo falla (sin archivo, error del runtime) la versión rápida queda (`stems_model = false`).
- **Modelo (`automix::model`).** Una sesión de ONNX Runtime propia, larga: se carga una vez (el modelo compilado de CoreML se guarda en `<carpeta del modelo>/coreml-cache`, así que las cargas siguientes tardan 0,2 s), se reutiliza entre llamadas, **no toca la red mientras el archivo esté en disco** (se descarga, con comprobación SHA-256, sólo si falta) y se suelta tras `set_idle_release` (60 s por defecto; `None` la conserva). El pre y posprocesado (STFT de 4096 puntos in, STFT inversa de la rama espectral sumada a la temporal out) está adaptado de `stem-splitter-core` 1.2.0 (MIT OR Apache-2.0; aviso en `model.rs` y `THIRD_PARTY_NOTICES.md`). Las ventanas avanzan 3/4 de ventana (antes, la mitad) y se mezclan con pesos triangulares, de modo que el modelo siempre tiene contexto a ambos lados. Proveedor de ejecución: macOS, CoreML con las unidades `CPUOnly` y formato MLProgram; Windows, DirectML con CPU de respaldo (**no probado**); `Compute::Cpu`, el proveedor de CPU de ONNX Runtime. Una separación con `Priority::Low` (la precarga) cede, entre ventanas, ante cualquier trabajo normal.
- **Separación anticipada (`automix::prefetch`).** `tail_span`/`head_span` son los tramos de 50 s que una transición puede leer de cualquier canción; la caché de stems (`stems::separate_span`) sirve cualquier tramo contenido en uno ya separado (comprobado por huella del audio) y sólo escribe un tramo si el `.meta` va al final.
- Decodificación (`audio::load`): Symphonia; el cuadro 0 es el primero que muestra el reproductor de la plataforma (lista de edición del MP4 y, en macOS, los 2112 cuadros de cebado de CoreAudio). **Medido: desfase 0 muestras contra AVAssetReader en las 16 canciones de `out/cache`.** `afconvert` descarta 1600 cuadros menos y ffmpeg/libmpv (sólo lista de edición) 2112 menos: no son el reloj de AVPlayer. En Windows el valor (sólo lista de edición, como ffmpeg) **no está verificado** (sin libmpv/ffmpeg aquí).

### Core (`sideb-core`, feature `automix`)

En `SideBCore` (UniFFI):

- `prepare_automix(request_id, from_video_id, from_is_upload, from_gain_db, to_video_id, to_is_upload, to_gain_db, quality, cache_dir) async -> AutomixTransitionRecord`. `quality`: `"fast"` (sin modelo) o `"stems"` (con el modelo; si no está en disco falla con `automix:model-unavailable` y empieza a bajarlo). El registro agrega `quality`, `same_cut_as_fast`, `separated_seconds`, `elapsed_seconds`.
- `cancel_automix(request_id)`, `automix_model_ready() -> bool`.
- `prefetch_automix(items: [AutomixQueueItem{video_id, is_upload}]) async`, `cancel_automix_prefetch()`, `set_automix_cache_dir(cache_dir)`.
- `get_automix_settings() -> AutomixSettings`, `set_automix_settings(AutomixSettings) -> AutomixSettings` (`quality` auto|fast|stems, `fast_on_battery`, `skip_same_album`, `compute` auto|gpu|cpu, `lookahead` 1–3, `keep_model_loaded`), guardados en la base del core.
- `automix_capability() -> AutomixCapability{model_ready, model_downloading, realtime_factor, stems_recommended, provider}`; `automix_cache_usage() -> AutomixCacheUsage{audio_bytes, stems_bytes, transitions_bytes, model_bytes}`; `clear_automix_cache()`; `delete_automix_model()`.

Resuelve ambos por el orquestador (se exige AAC: itag 139/140/141/256/258/325/328; si el elegido no lo es se excluye el cliente que lo dio y se reintenta; si ningún cliente da AAC, error `automix:unsupported-format`), baja a `<cache>/audio/<id>.m4a` con peticiones de 1 MB con las cabeceras resueltas (las últimas 12 se conservan), decodifica, corre `prepare` en un hilo bloqueante y escribe `<cache>/transitions/<from>__<to>.<fast|stems>.wav` (el rápido sigue en disco mientras llega el de stems) (16 bits; float de 32 si las ganancias pasan de escala completa; se conservan 3). Stems en `<cache>/stems` (poda a 400 MB). Una preparación a la vez; una petición nueva sustituye a la anterior (la vieja termina con `automix:cancelled` al llegar a su próximo punto de control y su archivo se borra). No toca `current_playback` ni el historial. Errores tipados como prefijo del mensaje de `SideBError::StreamError` (`automix:cancelled`, `automix:unsupported-format`, `automix:too-long`, `automix:bad-id`): añadir variantes rompería los `match` exhaustivos de Windows.

## Referencias

- [BitChord](https://github.com/kushagrasinghx/BitChord) (GPL-3; su analizador viene de [Orchard](https://github.com/SFG5453/Orchard), AGPL-3): cliente con automix. Mezcla en vivo y cae a crossfade simple casi siempre; sirve como referencia de diseño de la escalera de confianza.
- [Mosaikbox](https://repositum.tuwien.at/bitstream/20.500.12708/212628/1/Sowula-2024-Mosaikbox%20Improving%20Fully%20Automatic%20DJ%20Mixing%20Through%20Rule-ba...-vor.pdf): mezcla automática con reglas sobre stems.
- [Post de Len Vande Veire](https://lenvdv.github.io/2018-03-20-autodj): pipeline completo de un auto-DJ.

## Pasos

- [x] Banco de pruebas: carga, grilla de beats local, time-stretch con mapa de tiempo, stems (HT-Demucs), plantilla «cambio de bajo», crossfade de comparación.
- [x] Pruebas automáticas con pistas sintéticas: tempo y primer tiempo recuperados; beats de ambas canciones alineados durante toda la mezcla; bordes idénticos al original; contrato del archivo para los tres tipos.
- [x] Descarga desde YouTube Music por búsqueda, id o URL (banco) y desde el orquestador (core).
- [x] Motor movido a `core/crates/automix`; el banco es un cliente fino.
- [x] Escalera `Mix` → `Cut` → `Fade` con un solo punto de entrada (`prepare`); el par Levitating → FE!N, antes rechazado, produce `Cut`.
- [x] Archivo con A sin tocar, la transición y el resto de B sin tocar; ganancias horneadas; WAV de 16 bits o float.
- [x] Reloj de decodificación igual al de AVPlayer (medido contra AVAssetReader).
- [x] Latencia de stems: ventanas de 60 s (antes 90) y separación en paralelo; medido abajo.
- [x] Modelo ausente: no bloquea (separación por frecuencias + descarga en segundo plano).
- [x] Contrato del core (`prepare_automix`, `cancel_automix`, `automix_model_ready`) con la feature `automix` (activa por defecto; compila con `--no-default-features`).
- [x] XCFramework de Mac con el motor enlaza (ver Comprobaciones).
- [ ] **Escucha del usuario** con pares reales variados de los tres tipos; anotar qué falla (primer tiempo mal detectado, entrada en mal lugar, choque de tonalidad, eco del corte).
- [ ] Prueba de empalme sin clic en AVPlayer y libmpv: de A al archivo en `a_cut + posición`, y la compensación del reloj en Windows.
- [ ] Verificar Windows: compilación de `automix` (Signalsmith en C++ con MSVC, ONNX Runtime) y el reloj de decodificación contra libmpv.
- [ ] Integración en las apps: cuándo pedir la preparación (en cuanto se conoce la siguiente), qué hacer mientras se prepara, ajustes del usuario, ReplayGain/ganancias, qué hacer con `bars`/`kind` en la UI, comportamiento con álbumes y playlists ordenadas.
- [x] Windows, integración (código y pruebas de lógica; **sin ejecutar en Windows**): ajuste «Automix (beta)» apagado por defecto (Ajustes → Reproducción, persistido por cuenta junto al volumen exponencial), botón «Beta · Automix» en la barra de paneles de la pantalla completa con estado apagado/activo/preparando/lista (tipo y BPM)/no disponible (motivo)/mezclando, y coordinador nativo en `windows/src-tauri/src/automix_runtime.rs` (elegibilidad, preparación con ganancias, empalme por posición, traspaso de cola sin cargar el flujo, seeks, encadenado A→B→C, cancelaciones por generación/cola/cuenta/Jam/repetir). Un Jam apaga Automix también en la interfaz (ajuste y píldora deshabilitados con «No disponible en Jam», preparación cancelada, archivo soltado con arranque normal; la preferencia guardada no cambia). Marca decorativa en la barra de progreso (barra inferior y pantalla completa) en `aCut + overlapStart` de la canción actual, con el tramo teñido hasta el final, mientras la transición está lista o el archivo suena antes del traspaso. Textos: claves compartidas de `automix.json` de Mac (sólo `windows.automix.error` es propia de Windows). Pruebas: 21 de Rust (con stubs en Mac) y `scripts/automix-ui.test.mjs`.
- [ ] Windows, verificación nativa pendiente: compilación MSVC de `automix` (Signalsmith C++, ONNX Runtime) dentro de la app Tauri; que libmpv abra el WAV y el empalme (pausa → `loadfile replace` → seek → reanudar) no tenga clic ni hueco audible; que `time-pos`/`duration` del WAV coincidan con los segundos que supone el contrato (reloj de decodificación de Symphonia contra libmpv: lista de edición del MP4); que el historial de B (`record_playback`) cuente tras el traspaso; escucha real de los tres tipos; propuesta de `Player::load_at` en el informe de la tarea (empalme sin hueco).
- [x] **Mac, integración (2026-11-15, sin escucha):** ajuste «Automix (beta)» (apagado por defecto, se guarda con el prefijo del reproductor), píldora «Beta · Automix» sobre la portada en pantalla completa con estado (apagado / preparando / lista tipo+bpm / no disponible+motivo / mezclando), `AutomixCoordinator` (elegibilidad: sin Jam, sin repetir un tema, siguiente conocido distinto y no del mismo `albumId`; cancela por salto, cola, cambio de tema, cuenta, Jam y apagado), `AVQueuePlayer` con `forwardPlaybackEndTime = aCut` y el WAV en cola (empalme sin cortes), traspaso de la cola/UI/letras/Me gusta/Ahora suena en `handoverSeconds` sin resolver el stream por la vía normal (se resuelve de fondo para historial y `streamInfo`), mapa de tiempos del archivo (saltos, letras, encadenado A→B→C), sin ganancias (el Mac no normaliza volumen). Código: `apple/Sources/SideB/Services/Automix/`, `AudioPlayerService` (sesgo de tiempo y empalme), `PlayerViewModel` (anfitrión y traspaso). Pruebas: `AutomixTests.swift`.
- [x] **Mac, Jam y marcador (2026-11-15):** con un Jam activo el ajuste y la píldora quedan deshabilitados («No disponible en Jam»), no se prepara nada, se cancela lo pendiente y, si el Jam empieza con el archivo sonando, el Jam toma el control por la vía normal (`audioService.stop()`); la preferencia guardada no cambia y rige de nuevo al terminar. Marcador en la barra de progreso (la misma del reproductor inferior y de pantalla completa): marca en `aCutSeconds + overlapStartSeconds` y tramo teñido hasta el final mientras la transición está lista o sonando; desaparece al cancelar, abandonar o traspasar. Sin cambios en el área de toque ni en el salto.
- [x] **Mac, diagnóstico (2026-11-15):** menú «Automix › Diagnóstico…» (⌥⌘A) que abre una ventana de utilidad con el estado en vivo (0,25 s, sólo mientras está abierta), la petición, el `AutomixTransitionRecord`, el reproductor (etapa, elementos de la cola, tiempo crudo/sesgo/mostrado, `forwardPlaybackEndTime`, cuentas atrás hasta corte, solape y traspaso) y un registro circular de 1000 eventos que también va a `os.Logger` (categoría `automix`, `log stream --predicate 'category == "automix"'`), sin URLs, cookies ni cabeceras (saneado). Botones: copiar/limpiar registro, mostrar/abrir el archivo, cancelar, «Preparar ahora» y «Saltar a 10 s antes del corte». Código: `Services/Automix/AutomixDiagnostics.swift`, `Views/Automix/AutomixDiagnosticsView.swift`.
- [ ] Mac: escucha del empalme (¿clic o hueco al pasar de la canción al archivo en `aCut`? ¿entrada tardía con salto de ~0,15 s?), del traspaso de la UI y de los saltos dentro del archivo; no se pudo comprobar sin oído.
- [ ] Mac: letras experimentales con el archivo sonando (el reloj usa el sesgo de tiempo; las marcas de frontera se instalan una vez, el muestreo de 0,1 s corrige el resto).
- [ ] Elegir dónde entra B (primer momento fuerte) y dónde sale A por estructura, no sólo por fin del audio.
- [ ] Tonalidad: detectar compatibilidad y, si conviene, transponer B durante la mezcla.
- [ ] Más plantillas (puente de batería) y elección por puntaje entre candidatas.
- [x] Ronda 2 (2026-11-15), pedida por la prueba en Mac (canciones de ~1,5 min sin transición): `quality` «fast»/«stems»; sesión del modelo propia y larga, sin red con el modelo en disco; medición de proveedores (la GPU de CoreML era 4× más lenta que la CPU: 0,9× → 5,6× tiempo real); separar sólo los tramos que se leen (122 s → 37–44 s de audio por par); precarga con `prefetch_automix` (par precargado: 2,4 s); ajustes, capacidad, uso de caché y borrado del modelo en el core.
- [ ] Mac y Windows: usar `quality` (pedir «fast» primero y mejorar a «stems» si `automix_capability().stems_recommended` y llega a tiempo), `prefetch_automix`, los ajustes y la capacidad; avisar al usuario del uso de disco y de memoria (el modelo ocupa ~2 GB de RAM en uso).
- [ ] Memoria: con CoreML, tras soltar la sesión quedan ~1,1–1,3 GB residentes (la caché de CoreML en el proceso); con el proveedor de CPU de ONNX Runtime se liberan por completo (~60–240 MB). Decidir si vale una CPU más lenta (2,2×) por liberar la memoria, o un proceso aparte para el modelo.
- [ ] Windows: DirectML (`cfg(windows)`, CPU de respaldo) sin compilar ni medir; empaquetar `onnxruntime.dll`/`DirectML.dll`.
- [ ] Plan con el modelo para mezclas largas (16 compases, B cantando sobre el final instrumental de A): hoy el plan se hace sin el stem de voz y se limita a 8 compases.

## Latencia (medida, M1 Pro, `release`)

Ronda 1 (antes): `Mix` con el modelo, 146 s en un proceso nuevo (184 s en serie); 2 ventanas de 60 s por par (~122 s de audio) a ~0,9× tiempo real.

Ronda 2, por orden de lo medido:

- **Proveedor de ejecución** (`model_bench`, 23,4 s de audio, ventanas de 7,8 s con paso de 3/4, tiempo real = audio / tiempo de pared con la sesión caliente):

| Configuración | Carga fría | Carga con caché compilada | Tiempo real | RAM pico |
|---|---|---|---|---|
| CoreML `CPUOnly` MLProgram (**elegida**) | 20,9 s | 0,2 s | **5,4–5,7×** | ~2,0–2,5 GB |
| CoreML `CPUAndNeuralEngine` | 38,2 s | 10,9 s | 5,3–5,5× | ~2,4–3,0 GB |
| CoreML `All` | 59,2 s | 11,5 s | 1,6× (y 0,3× en una repetición) | ~1,3–2,2 GB |
| CoreML `CPUAndGPU` (el valor por defecto de `stem-splitter-core`) | — | — | ~1× (3,7 s por ventana de 7,8 s) | — |
| CoreML `CPUAndGPU` con acumulación fp16 | 42,8 s | — | 0,2–0,4× | ~0,8 GB |
| ONNX Runtime CPU (8 hilos) | 0,4 s | — | 2,2× | ~2,6 GB |
| CoreML formato NeuralNetwork | — | — | falla (panic al cargar) | — |

El «0,9× tiempo real» de la ronda 1 era la GPU de CoreML: la CPU lo hace 5–6 veces más rápido, y el Neural Engine no gana a la CPU (el modelo, un transformer, queda repartido en muchos subgrafos). Con ≥5× no hace falta un modelo más liviano: no se evaluó ninguno.
- **Qué se separa.** Antes, 2 ventanas de 60 s por par (~122 s de audio). Ahora, sólo el solape más 4 s a cada lado de cada canción: **36,7 s** (FE!N → HIGHEST IN THE ROOM, 8 compases a 148–153 BPM), 44 s (One More Time → Around the World, 8 compases). Además las ventanas del modelo avanzan 3/4 en lugar de 1/2 (10 ventanas para 60 s en lugar de 16).
- **Tiempos de `prepare_automix`** (prueba en vivo `automix_live_timing`, `--release`, pares reales):

| Caso | Tiempo |
|---|---|
| «fast», descargando las dos canciones | 7,6 s |
| «fast», audio en caché | 2,1 s |
| «stems», proceso nuevo, modelo sin compilar en la caché (36,7 s separados) | 25,9 s (de ellos ~20 s la compilación única de CoreML) |
| «stems», modelo ya cargado, par sin precargar (36,7 s separados) | 8,7 s |
| «stems», par precargado | **2,4 s** (0 s separados) |
| precarga de un par (descarga + 2 tramos de stems, en segundo plano) | 20,1 s |
| `Cut` | ~0,2–1 s tras decodificar |

- **Memoria del modelo**: ~2,0–2,5 GB resident mientras se usa (ONNX Runtime CPU: 2,6 GB). Al soltar la sesión, CoreML deja ~1,1–1,3 GB en el proceso; ONNX Runtime CPU baja a 60–240 MB. El modelo ocupa 210 MB en disco y la caché de stems de una canción ~70 MB.
- Factor medido en la prueba en vivo: `realtime_factor` 5,57 (`stems_recommended`).

## Comprobaciones

Hechas el 2026-11-15 en un M1 Pro (macOS), sin escuchar nada:

- `cargo test --locked --manifest-path core/Cargo.toml -p automix`: 14 pruebas (4 originales y 10 nuevas: contrato de `Mix`, `Cut` y `Fade` con el archivo comparado muestra a muestra contra A y B, ganancias y WAV de 32 bits float, lista de edición MP4, poda de caché, modo de stems).
- `cargo test --locked --manifest-path core/Cargo.toml -p innertube -p sideb-core`: 113 y 191 pruebas (más 11 ignoradas, una de ellas la nueva `automix_live`). Con `--features windows-bridge`: 193. Con `--no-default-features`: 187.
- `cargo check -p sideb-core --features windows-bridge` y `cargo build -p sideb-core --no-default-features`: sin errores. `player` y la app Tauri **no** se compilaron (no hay libmpv en este Mac) ni se probó nada en Windows.
- Prueba en vivo `cargo test -p sideb-core automix_live -- --ignored`: `prepare_automix` real (resolución anónima, descarga, decodificación, `Cut`, WAV) de Levitating a FE!N en 18,7 s con compilación de depuración; la segunda llamada usa la caché de audio.
- `bash apple/build_xcframework.sh` y `swift build --package-path apple --build-system native`: enlazan con `.linkedLibrary("c++")` en el target `SideBCore` de `apple/Package.swift` (sin eso fallan por símbolos de libc++; CoreML se enlaza solo). `libsideb_core.a`: 384 649 520 bytes contra 290 781 264 sin la feature (+93,9 MB, +32 %). Los bindings regenerados sólo añaden (+421 líneas); no se dejaron en `apple/` (hay que regenerarlos con el script al integrar). **No se ejecutó la app de Mac ni se llamó a `prepareAutomix` desde Swift.**
- Banco, 3 pares reales: Levitating → FE!N (antes rechazado por 103 y 74 BPM) sale como `Cut`; FE!N → HIGHEST IN THE ROOM como `Mix` de 4 compases con el modelo (igual que en `batch.log`), con salida idéntica byte a byte al repetirlo desde la caché de stems; One More Time → Around the World como `Mix` de 16 compases con el modelo (igual que en el registro anterior).
- Decodificación: `automix-lab check-decode` contra AVAssetReader (`tools/avfoundation-decode.swift`): desfase 0 muestras en las 16 canciones de `out/cache`.

Ronda 2 (2026-11-15):

- `cargo test --locked ... -p automix`: 22 pruebas (+3 con el modelo, marcadas `#[ignore]`, que pasaron: separación que suma a la entrada, sesión que se construye una sola vez y se suelta tras estar ociosa, y `upgrade` que conserva el corte y sólo separa el solape; segunda llamada servida de la caché). `-p innertube -p sideb-core`: 113 y 197 (+11 ignoradas); con `windows-bridge`: 199; con `--no-default-features`: 187.
- Pruebas nuevas del core: ajustes (por defecto, corrección de valores fuera de rango, persistencia entre núcleos, lectura de ajustes parciales o viejos), uso y borrado de caché, regla de capacidad, peticiones inválidas que fallan antes de tocar la red, precarga que cancela la anterior.
- XCFramework (`apple/build_xcframework.sh`, release): `libsideb_core.a` de 380 628 544 bytes (4 MB **menos** que los 384 649 520 de la ronda 1, porque ya no se enlaza `stem-splitter-core`; +89,8 MB sobre los 290 781 264 sin la feature). Los bindings regenerados compilan (`swift build --target SideBCore`); el destino `SideB` falla **sólo** en `PlayerViewModel.swift:2201` por el argumento nuevo `quality` (trabajo del agente de Mac) y, con los bindings anteriores contra el XCFramework nuevo, no compila (la firma cambió). Enlace y ejecución comprobados con un paquete mínimo fuera del repositorio (`getAutomixSettings`, `setAutomixSettings` corrigiendo `lookahead` 9 → 3, `automixCapability`, `automixCacheUsage`, `prepareAutomix` con un id inválido y `prefetchAutomix([])`): sin cambios en `apple/Package.swift` (`.linkedLibrary("c++")` de la ronda 1 basta). Los bindings regenerados **no** se dejaron en `apple/`.

## Límites conocidos

- El primer tiempo del compás se decide con una heurística (cambio de armonía); puede errar por 1 a 3 beats. En `Cut` eso desplaza el «uno» de B pero no lo saca de un beat; el banco permite corregirlo en `Mix` con `--a-downbeat` / `--b-downbeat`.
- `Mix` sólo funciona con tempo estable y tempos a menos de 25 % entre sí (en la misma octava); fuera de eso cae a `Cut`.
- Los umbrales de confianza están calibrados con muy poco material.
- Una canción de más de 12 minutos se rechaza (`automix:too-long`): se carga entera en memoria.
- Sin el modelo en disco sólo hay «fast»; el modelo (~210 MB) se baja al pedir «stems» o con la precarga si el ajuste de calidad no es «fast».
- La versión rápida no sabe dónde canta cada canción: mezcla de a lo sumo 8 compases (antes, con el modelo, hasta 16) y cruza voces y armonía en un compás, sin evaluar choque de tonalidades. Con B cantando desde el primer compás, la versión de stems silencia las voces de A durante todo el solape.
- Los remuestreos que no son 44,1 kHz son lineales (suficiente para evaluar; YouTube Music da 44,1 kHz).
- La transición es un archivo local de ~50 MB por canción de 4 minutos (16 bits); se conservan 3.
