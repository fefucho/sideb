# PLAN-024 — Automix: transiciones automáticas con stems

- Fecha: 2026-11-15 (America/Montevideo).
- Estado: motor y contrato del core hechos y probados con audio sintético y 3 pares reales por línea de comandos; **sin UI ni reproductor en ninguna plataforma y sin escucha**. La calidad sonora no está evaluada.
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
| `Kind::Mix` | tempos a menos de 25 % (en la octava de A) y grillas fiables | mezcla con tempo deslizante, stems y cambio de bajo (16, 8 o 4 compases) |
| `Kind::Cut` | tempos demasiado lejanos, u otra negativa de la mezcla, con ambas grillas fiables | A sale en un compás (1–2 compases) con barrido de filtro y eco *ping-pong* sincronizado (3/4 de beat); B entra limpio a su tempo en su primer tiempo, **un compás de A** después de la última línea de compás de A. Sin stems |
| `Kind::Fade` | sin grilla fiable | A se apaga en ~6 s terminando cerca de su final audible; B arranca en su inicio audible, sin entrada gradual, ~1 s de solape |

`Transition`: `kind`, `audio` (todo el archivo, ya con las ganancias), `a_cut`, `overlap_start`, `overlap_end`, `b_offset`, `b_entry`, `handover`, `bpm_a`, `bpm_b`, `bars`, `stems_model`, `detail` (español), `baseline` (sólo el banco). Todas las horas «archivo» son segundos del WAV.

- Antes de `overlap_start` el archivo es A **muestra por muestra** (× ganancia) a partir del segundo `a_cut` de A.
- Desde `overlap_end` es B muestra por muestra (× ganancia): `segundo de B = segundo del archivo − b_offset`, exacto. Antes de `b_entry` B no está en el archivo.
- `handover`: segundo del archivo en que la UI debe pasar a mostrar B (cambio de bajo en `Mix`; entrada de B en `Cut` y `Fade`).
- `Options`: `pre_seconds` (8), `post_seconds` (infinito = B entera), `max_bars` (16), `stem_mode` (`Auto` por defecto), `a_gain`/`b_gain` lineales, `baseline`, `cancel` (`Arc<AtomicBool>`; se revisa entre etapas, una separación en curso termina), y para el banco `a_downbeat_shift`/`b_downbeat_shift`.
- Stems: `StemMode::Auto` usa HT-Demucs si el modelo ya está en disco; si no, usa la separación por frecuencias para esa transición y **baja el modelo en segundo plano**. `Model` lo baja y espera; `Frequency` nunca lo usa. Si el modelo falla (sin red, error del runtime) cae a frecuencias.
- Decodificación (`audio::load`): Symphonia; el cuadro 0 es el primero que muestra el reproductor de la plataforma (lista de edición del MP4 y, en macOS, los 2112 cuadros de cebado de CoreAudio). **Medido: desfase 0 muestras contra AVAssetReader en las 16 canciones de `out/cache`.** `afconvert` descarta 1600 cuadros menos y ffmpeg/libmpv (sólo lista de edición) 2112 menos: no son el reloj de AVPlayer. En Windows el valor (sólo lista de edición, como ffmpeg) **no está verificado** (sin libmpv/ffmpeg aquí).

### Core (`sideb-core`, feature `automix`)

En `SideBCore` (UniFFI):

- `prepare_automix(request_id, from_video_id, from_is_upload, from_gain_db, to_video_id, to_is_upload, to_gain_db, cache_dir) async -> AutomixTransitionRecord`.
- `cancel_automix(request_id)`.
- `automix_model_ready() -> bool`.

Resuelve ambos por el orquestador (se exige AAC: itag 139/140/141/256/258/325/328; si el elegido no lo es se excluye el cliente que lo dio y se reintenta; si ningún cliente da AAC, error `automix:unsupported-format`), baja a `<cache>/audio/<id>.m4a` con peticiones de 1 MB con las cabeceras resueltas (las últimas 12 se conservan), decodifica, corre `prepare` en un hilo bloqueante y escribe `<cache>/transitions/<from>__<to>.wav` (16 bits; float de 32 si las ganancias pasan de escala completa; se conservan 3). Stems en `<cache>/stems` (poda a 400 MB). Una preparación a la vez; una petición nueva sustituye a la anterior (la vieja termina con `automix:cancelled` al llegar a su próximo punto de control y su archivo se borra). No toca `current_playback` ni el historial. Errores tipados como prefijo del mensaje de `SideBError::StreamError` (`automix:cancelled`, `automix:unsupported-format`, `automix:too-long`, `automix:bad-id`): añadir variantes rompería los `match` exhaustivos de Windows.

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
- [ ] Elegir dónde entra B (primer momento fuerte) y dónde sale A por estructura, no sólo por fin del audio.
- [ ] Tonalidad: detectar compatibilidad y, si conviene, transponer B durante la mezcla.
- [ ] Más plantillas (puente de batería) y elección por puntaje entre candidatas.
- [ ] Bajar más el costo de stems: ver Latencia.
- [ ] Modelo sin red: `stem-splitter-core` consulta el manifiesto del modelo en cada llamada; sin red cae a frecuencias aunque el modelo esté en disco.

## Latencia (medida, M1 Pro, `release`, sin otra carga)

- Descarga + decodificación de las dos canciones: ~1 s con caché; la descarga real depende de la red (≈3–4 MB por canción).
- `Cut` y `Fade`: ~0,2–1 s tras la decodificación (no hay stems).
- `Mix` con el modelo, ventanas de 60 s: **146 s** en un proceso nuevo con las dos separaciones a la vez, 184 s una tras otra (el arranque en frío del modelo, ~30–40 s la primera vez del proceso, se solapa). Con el proceso caliente: 124 s a la vez contra 127 s una tras otra; una ventana de 60 s cuesta 55–63 s, una de 30 s, 30 s, una de 8 s, 13 s: ~0,9× tiempo real más ~13 s fijos por llamada (el runtime recrea la sesión en cada `split_file`). Con ventanas de 90 s el par costaba ~184 s en un proceso nuevo: acortar a 60 s casi no se nota porque domina el coste fijo y el arranque en frío.
- Repetir el mismo par: 1,6 s (stems en la caché por contenido).
- Ideas pendientes: reutilizar la sesión del modelo entre llamadas (hoy el crate la recrea; saltearse `split_file` y usar `engine::run_window_demucs` directamente), precalentar el modelo al iniciar, una sola separación con las dos ventanas concatenadas (−13 s, pierde la caché por canción).

## Comprobaciones

Hechas el 2026-11-15 en un M1 Pro (macOS), sin escuchar nada:

- `cargo test --locked --manifest-path core/Cargo.toml -p automix`: 14 pruebas (4 originales y 10 nuevas: contrato de `Mix`, `Cut` y `Fade` con el archivo comparado muestra a muestra contra A y B, ganancias y WAV de 32 bits float, lista de edición MP4, poda de caché, modo de stems).
- `cargo test --locked --manifest-path core/Cargo.toml -p innertube -p sideb-core`: 113 y 191 pruebas (más 11 ignoradas, una de ellas la nueva `automix_live`). Con `--features windows-bridge`: 193. Con `--no-default-features`: 187.
- `cargo check -p sideb-core --features windows-bridge` y `cargo build -p sideb-core --no-default-features`: sin errores. `player` y la app Tauri **no** se compilaron (no hay libmpv en este Mac) ni se probó nada en Windows.
- Prueba en vivo `cargo test -p sideb-core automix_live -- --ignored`: `prepare_automix` real (resolución anónima, descarga, decodificación, `Cut`, WAV) de Levitating a FE!N en 18,7 s con compilación de depuración; la segunda llamada usa la caché de audio.
- `bash apple/build_xcframework.sh` y `swift build --package-path apple --build-system native`: enlazan con `.linkedLibrary("c++")` en el target `SideBCore` de `apple/Package.swift` (sin eso fallan por símbolos de libc++; CoreML se enlaza solo). `libsideb_core.a`: 384 649 520 bytes contra 290 781 264 sin la feature (+93,9 MB, +32 %). Los bindings regenerados sólo añaden (+421 líneas); no se dejaron en `apple/` (hay que regenerarlos con el script al integrar). **No se ejecutó la app de Mac ni se llamó a `prepareAutomix` desde Swift.**
- Banco, 3 pares reales: Levitating → FE!N (antes rechazado por 103 y 74 BPM) sale como `Cut`; FE!N → HIGHEST IN THE ROOM como `Mix` de 4 compases con el modelo (igual que en `batch.log`), con salida idéntica byte a byte al repetirlo desde la caché de stems; One More Time → Around the World como `Mix` de 16 compases con el modelo (igual que en el registro anterior).
- Decodificación: `automix-lab check-decode` contra AVAssetReader (`tools/avfoundation-decode.swift`): desfase 0 muestras en las 16 canciones de `out/cache`.

## Límites conocidos

- El primer tiempo del compás se decide con una heurística (cambio de armonía); puede errar por 1 a 3 beats. En `Cut` eso desplaza el «uno» de B pero no lo saca de un beat; el banco permite corregirlo en `Mix` con `--a-downbeat` / `--b-downbeat`.
- `Mix` sólo funciona con tempo estable y tempos a menos de 25 % entre sí (en la misma octava); fuera de eso cae a `Cut`.
- Los umbrales de confianza están calibrados con muy poco material.
- Una canción de más de 12 minutos se rechaza (`automix:too-long`): se carga entera en memoria.
- Primera transición sin modelo: se usa el sustituto por frecuencias y el modelo (~210 MB) se baja en segundo plano.
- Los remuestreos que no son 44,1 kHz son lineales (suficiente para evaluar; YouTube Music da 44,1 kHz).
- La transición es un archivo local de ~50 MB por canción de 4 minutos (16 bits); se conservan 3.
