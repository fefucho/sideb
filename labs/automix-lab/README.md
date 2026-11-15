# automix-lab

Banco de pruebas de transiciones automáticas. Experimento de [PLAN-024](../../plans/PLAN-024-automix.md): no forma parte de las apps ni del workspace de `core/`.

Entran dos canciones y sale un WAV con el final de la primera, la transición y el principio de la segunda. Al lado escribe el mismo tramo con un crossfade común, para comparar.

## Uso

Desde esta carpeta:

```sh
cargo build

# Dos canciones de YouTube Music (búsqueda, id o URL), con stems
target/debug/automix-lab mix "yt:Daft Punk One More Time" "yt:Daft Punk Around the World" -o out/prueba.wav

# Rápido, sin modelo de stems (sólo separa graves del resto)
target/debug/automix-lab mix a.mp3 b.m4a -o out/prueba.wav --no-stems

# Ver tempo y grilla de una canción
target/debug/automix-lab analyze "yt:Daft Punk Around the World"
```

Opciones de `mix`: `--bars` (compases de mezcla, 16 por defecto), `--pre` y `--post` (segundos de cada canción alrededor), `--a-downbeat N` y `--b-downbeat N` (corre el primer tiempo detectado N beats, si la entrada suena cruzada).

Todo lo generado queda en `out/` (ignorado por Git): descargas en `out/cache/`, stems en `out/stems/`.

## Qué hace

1. Estima el tempo y ajusta una grilla de beats sólo en el tramo que usa la transición (final de A, principio de B).
2. Separa en stems esos dos tramos con HT-Demucs. La primera vez baja el modelo.
3. Durante la mezcla el tempo se desliza del de A al de B y cada canción lo sigue beat a beat con Signalsmith Stretch.
4. Aplica la plantilla «cambio de bajo»: B entra sin bajo, a mitad de la mezcla se intercambian los bajos, A se va en la segunda mitad y nunca cantan las dos a la vez.
5. Fuera de la mezcla el audio es el original sin tocar, para poder empalmarlo.

## Notas

- La descarga de YouTube Music es anónima (AAC 128 kbps); no usa la cuenta ni las cookies de Side B.
- Formatos locales: mp3, m4a/AAC, flac, wav, ogg.
- Requiere las herramientas de línea de comandos de Xcode (compila Signalsmith Stretch en C++).
- Licencias de terceros: Signalsmith Stretch (MIT), `stem-splitter-core` y HT-Demucs (MIT), ONNX Runtime (MIT).

```sh
cargo test
```
