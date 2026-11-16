# automix-lab

Banco de pruebas de transiciones automáticas. Experimento de [PLAN-024](../../plans/PLAN-024-automix.md). El motor vive en [`core/crates/automix`](../../core/crates/automix) (lo usan también las apps a través de `sideb-core`); este programa es sólo un cliente: baja o abre canciones, llama a `automix::prepare` y guarda el resultado. No forma parte del workspace de `core/`.

Entran dos canciones y sale un WAV con el final de la primera, la transición y el principio de la segunda (`--post`; el core entrega la segunda entera). Si la transición es una mezcla, al lado escribe el mismo tramo con un crossfade común, para comparar.

## Uso

Desde esta carpeta:

```sh
cargo build --release

# Dos canciones de YouTube Music (búsqueda, id o URL), con stems
target/release/automix-lab mix "yt:Daft Punk One More Time" "yt:Daft Punk Around the World" -o out/prueba.wav

# Rápido, sin modelo de stems (sólo separa graves del resto)
target/release/automix-lab mix a.mp3 b.m4a -o out/prueba.wav --no-stems

# Ver tempo y grilla de una canción
target/release/automix-lab analyze "yt:Daft Punk Around the World"

# Nivel cada 0,5 s de un WAV (para ver cómo se mueve una transición)
target/release/automix-lab levels out/prueba.wav --from 15 --to 40
```

Opciones de `mix`:

- `--max-bars`: compases máximos de la mezcla (4, 8 o 16; 16 por defecto).
- `--pre` y `--post`: segundos de A antes de la transición y de B después (20 por defecto; `inf` deja B entera, como hace el core).
- `--a-downbeat N` y `--b-downbeat N`: corren el primer tiempo detectado N beats, si la entrada suena cruzada.
- `--stems-cache`: carpeta de los stems ya separados (`out/stems-cache/` por defecto).
- `--no-stems`: sin el modelo.

Todo lo generado queda en `out/` (ignorado por Git): descargas en `out/cache/`, stems en `out/stems-cache/`.

## Qué hace

`automix::prepare` baja por una escalera hasta donde haga falta y el banco imprime qué tipo salió:

1. **mix** (`Kind::Mix`): estima el tempo y ajusta una grilla de beats sólo en el tramo que usa la transición, separa en stems esos dos tramos (60 s de cada canción) con HT-Demucs, desliza el tempo del de A al de B siguiendo cada canción beat a beat con Signalsmith Stretch y aplica la plantilla «cambio de bajo»: B entra sin bajo, a mitad de la mezcla se intercambian los bajos, A se va en la segunda mitad y nunca cantan las dos a la vez.
2. **cut** (`Kind::Cut`): tempos demasiado lejanos (o la mezcla se negó por otra causa) pero con grillas fiables. A sale en un compás con un barrido de filtro y un eco sincronizado; B entra limpio, a su tempo, en su primer tiempo, un compás después. No usa stems.
3. **fade** (`Kind::Fade`): sin grilla fiable. A se apaga en unos 6 s cerca de su final audible; B arranca desde su inicio audible con ~1 s de solape.

Fuera de la transición el audio es el original sin tocar, para poder empalmarlo.

## Verificar la decodificación

El motor decodifica con Symphonia y descarta el cebado que el reproductor de la plataforma descarta (en macOS, lo que AVFoundation: lista de edición más 2112 cuadros). Medido (2026-11-15) en las 16 canciones de `out/cache/`: desfase 0 muestras contra AVAssetReader, que descarta 3712 cuadros del decodificador (1600 de la lista de edición más 2112 del cebado de CoreAudio). `afconvert` (ExtAudioFile) descarta sólo 2112, y ffmpeg/libmpv, que respeta sólo la lista de edición, 1600: el reloj del motor es el del reproductor de cada plataforma, no el de `afconvert`. Para repetir la comprobación contra AVAssetReader:

```sh
swiftc -O tools/avfoundation-decode.swift -o /tmp/avfoundation-decode
/tmp/avfoundation-decode out/cache/<id>.m4a /tmp/referencia.wav
target/release/automix-lab check-decode out/cache/<id>.m4a /tmp/referencia.wav   # desfase 0 = coinciden
```

## Notas

- La descarga de YouTube Music es anónima (AAC 128 kbps); no usa la cuenta ni las cookies de Side B.
- Formatos locales: mp3, m4a/AAC, flac, wav, ogg.
- Requiere las herramientas de línea de comandos de Xcode (compila Signalsmith Stretch en C++).
- Licencias de terceros: Signalsmith Stretch (MIT), `stem-splitter-core` y HT-Demucs (MIT), ONNX Runtime (MIT).

```sh
cargo test                                          # este banco
cargo test --manifest-path ../../core/Cargo.toml -p automix   # el motor
```
