# Revisión del core entre macOS y Windows

Fecha: 2026-10-02. Revisión del código y del historial, sin modificar implementaciones ni integrar ramas.

Revisiones comparadas:

- `origin/main`: `a98439d815f350275164e95dd909aa88cea98a37`.
- `origin/windows/main`: `e0c0665654d8428cc13fa547829d31563f24af27`.

## Conclusión

Un único core Rust para ambas apps es viable. Las interfaces nativas y los reproductores pueden conservar implementaciones diferentes: macOS usa Swift/AVPlayer y Windows usa Tauri/libmpv. Las mejoras de red, parseo, metadatos, persistencia y resolución de streams pueden convivir en la misma base de código.

Editar `core/` para implementar esas mejoras fue una decisión compatible con esa arquitectura. La separación de historiales y la falta de integración permitieron que las copias divergieran. Tener una carpeta llamada `core/` en cada rama no sincroniza su contenido.

La diferencia funcional de macOS ausente en el core Windows es el FIX-083, que conecta el cipher a un runtime JavaScript nativo. El fix reciente de playlists/shuffle (`555338f`) no modificó ningún archivo de `core/`.

## Qué permite reconstruir el historial

`main` comienza en `1f2b6a2`, mientras que el historial Windows comienza en `03c2e39`, un snapshot del proyecto. No hay ancestro común entre las ramas. Los cambios Windows anteriores a ese snapshot no tienen commits individuales en este historial, por lo que se pueden identificar comparando código, pero no atribuir su fecha original a partir de esos commits.

| Commit | Cambios relevantes al core | Consecuencia |
| --- | --- | --- |
| `03c2e39` | Incluye sesión externa para Windows, limpieza de cookies antiguas y adaptación de libmpv. | Son cambios ya presentes en el snapshot; conserva el constructor macOS. |
| `19b5f2b` | Agrega `core/AGENTS.md`. | Documentación; no modifica el comportamiento. |
| `e82896a` | Conserva álbum y enlaces de artistas, centraliza conversión de tarjetas y agrega `windows-bridge`. | Parte mejora el parseo compartido; parte agrega campos sólo para Windows. Incluye bastante reformateo de `lib.rs`. |
| `e8c89cd` | Agrega búsqueda filtrada de videos, campos de clasificación para Windows y pruebas de resultados de artista. | API adicional condicionada para Windows; el filtro respeta `hide_videos` y no duplica el registro de la búsqueda. |
| `555338f` | No toca `core/`. | La cola por tandas y el shuffle global están en los controladores Windows y su cola Tauri. |
| `d75d3ea` en `main` | FIX-083: callback `CipherJsRuntime`, registro del runtime y evaluación de firmas/transformación de `n`. | No está integrado en la rama Windows. FIX-084, en el mismo commit, corresponde al atajo de espacio de la app macOS. |

## Hallazgo principal: FIX-083 ausente

El archivo `core/crates/sideb-core/src/cipher/mod.rs` de Windows es exactamente igual, byte por byte, al de `main` antes de `d75d3ea`:

```text
main antes de FIX-083: 78d97b3cf2be841f8780b1ca3b3a3d7a247345ed
windows/main:         78d97b3cf2be841f8780b1ca3b3a3d7a247345ed
main actual:          7f0d78d2d3644fe1a42e1d0b2cccf531e70252cd
```

Esto demuestra que Windows conserva la implementación anterior; no es una eliminación producida por el fix de shuffle. El historial del snapshot no permite determinar cómo se eligió originalmente esa copia.

En Windows, `deobfuscate_stream_url` no evalúa la firma y devuelve `None`; `transform_n_param_in_url` devuelve la URL original. La resolución depende de las alternativas de streams directos previstas por el coordinador.

En `main`, Rust recibe un callback `CipherJsRuntime` y Swift lo implementa mediante JavaScriptCore en `NativeCipherJsRuntime.swift`. `SideBApp.swift` instala ese runtime llamando a `setCipherJsRuntime`.

Combinar el Swift actual de `main` con el core Windows y regenerar sus bindings deja esa llamada sin contrato: faltan el protocolo y el método. Es una incompatibilidad comprobada por inspección. Compilar el conjunto completo de `windows/main` en macOS es otro caso: su copia de Swift también carece de esa integración; aunque llegara a compilar, eso no demostraría que conserva el comportamiento actual de macOS.

## Cambios Windows que pueden convivir con macOS

### Sesión y persistencia

`SideBCore::new` sigue usando `build(data_dir, true)`: conserva la restauración y persistencia de cookies que utiliza Apple.

`SideBCore::new_windows` usa `build(data_dir, false)`: limpia cookies SQLite heredadas y recibe las credenciales desde el almacenamiento del host Windows. Los métodos de esta integración no están exportados por el bloque UniFFI de macOS. Tauri efectivamente usa `new_windows`.

`db.rs` agrega la limpieza de credenciales, el checkpoint del WAL y la compactación. Esa limpieza se invoca por el camino Windows; no se ejecuta automáticamente al construir el core mediante `new` de Apple. Hay pruebas separadas para ambos caminos.

### Metadatos y búsqueda

Los records adicionales de Windows están protegidos con `#[cfg(feature = "windows-bridge")]`. El manifiesto Tauri activa esa feature; el script `apple/build_xcframework.sh` no la activa.

Se compararon los 17 structs públicos cuyo nombre termina en `Record`, eliminando los campos condicionados a Windows y normalizando comentarios/espacios: todos conservan los mismos campos que `main`. Esto verifica las definiciones de esos records; no prueba por sí solo toda la ABI ni la compatibilidad de un XCFramework antiguo. El callback del FIX-083 sigue siendo una diferencia real.

Las mejoras que sí se aplican al parseo compartido son:

- Recuperar el nombre del álbum desde su enlace en tarjetas de canciones.
- Conservar álbum, ID de álbum y artista al convertir canciones de búsqueda y recomendaciones.
- Reutilizar una conversión común de tarjetas, con los campos Windows adicionales condicionados.

La API `SideBCore::search_videos` está en un bloque completo condicionado a `windows-bridge`; la función de InnerTube es adicional y no sustituye las APIs de búsqueda existentes. La prueba del resultado superior de artista agregada en `e8c89cd` verifica comportamiento del parser ya existente, no una reescritura de ese parser.

### Reproductor y workspace

Windows agrega `player` al workspace, un método `stop` de libmpv y un `build.rs` cuyo ajuste de enlaces se ejecuta sólo para Windows. El crate `sideb-core` no depende de `player`.

El script macOS compila explícitamente `--package sideb-core`; esa compilación no incorpora automáticamente libmpv. Un comando amplio como `cargo test --workspace` también seleccionaría `player` y debe contemplar sus dependencias nativas. Esto no implica convertir AVPlayer en libmpv.

## Fixes macOS que ya están conservados

La comparación actual no encuentra diferencias en `genius.rs`, `lyrics.rs`, `orchestrator.rs`, `local.rs`, `blocked.rs`, `cipher/config.rs`, `cipher/fetcher.rs`, `cipher/extractor.rs` ni el directorio `potoken/`.

Por tanto, no corresponde asumir que faltan todas las mejoras de Genius, letras o reproducción introducidas en `f01a758`, `6ca3d37`, `364d776` y `b76487b`. Las diferencias finales dentro de `core/` se limitan a 11 archivos, incluido `AGENTS.md`, el workspace y el lockfile.

## Verificación y límites

Pruebas ejecutadas en Windows con Visual Studio 2022/MSVC inicializado:

```powershell
cargo test --locked --manifest-path core/Cargo.toml -p innertube -p sideb-core
cargo test --locked --manifest-path core/Cargo.toml -p sideb-core --features windows-bridge
```

- Configuración por defecto: 90 pruebas InnerTube y 82 del core aprobadas; 7 pruebas en vivo ignoradas.
- Con `windows-bridge`: 84 pruebas del core aprobadas; 7 pruebas en vivo ignoradas.
- Sin fallos. El compilador emitió advertencias de código sin usar y el linker MSVC emitió LNK4098; no fue una compilación libre de advertencias.
- La primera ejecución sin inicializar el entorno MSVC falló al compilar dependencias C por falta de headers. Se repitió con el entorno de Visual Studio 2022 que utiliza el script del proyecto y terminó correctamente; ese fallo inicial no demuestra una incompatibilidad del core.

La prueba de persistencia Apple y la de sesión externa Windows pasaron en ambas configuraciones. Las pruebas de los campos Windows pasaron con la feature activa. Estos resultados no detectan por sí solos el FIX-083 ausente, cuya prueba de parseo de cipher también falta en esta copia.

La inspección y las pruebas Rust en este host no validan la compilación Swift, el enlace del XCFramework, reproducción audible ni resolución de streams con una cuenta real en macOS. Los tests en vivo ignorados no se ejecutan en esta revisión.

## Criterios para integrar las ramas

1. Conservar el FIX-083 y su implementación Swift, junto con las extensiones Windows. Mantener las alternativas de resolución cuando un host no instala runtime JavaScript.
2. Conservar el constructor Apple y el constructor de sesión externa Windows.
3. Mantener los campos Windows condicionados mientras no se decida cambiar también los contratos Swift.
4. Regenerar bindings y XCFramework desde el core integrado, sin reutilizar un binario de otra revisión.
5. Verificar Rust con y sin `windows-bridge`, Tauri en Windows y Swift/AVPlayer en macOS antes de considerar la integración validada.

Un cambio en lógica realmente compartida puede beneficiar a ambas apps al recompilar. Una mejora dentro de sus interfaces o colas propias requiere implementación en cada cliente; el fix de shuffle reciente pertenece a ese segundo caso.
