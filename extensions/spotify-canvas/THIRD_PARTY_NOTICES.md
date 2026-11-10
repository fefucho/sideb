# Referencias y atribución

La consulta Pathfinder y el intercambio de client-token se basan en la investigación pública de **Wolframe Team**, proyecto MIT [Wolframe-spotify-canvas](https://github.com/squeeeezy/Wolframe-spotify-canvas/tree/e3b78a48e99137ed7313dfd6a09bb553fa15b23d). Su aviso MIT se conserva en LICENSE. No se añade su crate ni su versión de reqwest como dependencia del core.

Los nombres y estructura de la consulta de búsqueda se contrastaron con la documentación/código MIT de [SpotifyScraper](https://github.com/AliAkhtari78/SpotifyScraper/tree/9cbf05aa4963bac3684bb941270dcb62fc851ab7), Copyright (c) 2025 Ali Akhtari. No se copia su runtime, autenticación por cookie, fixtures ni código Python. La lógica de matching y el host/protocolo son propios de Side B.

Spotify Canvas, marcas y videos no quedan licenciados por esta licencia de software. Las dependencias transitivas figuran en Cargo.lock y conservan sus propias licencias; esta nota no equivale a una auditoría completa ni a autorización del servicio.

## Dependencias compiladas en el ejecutable

El ejecutable (`sideb-spotify-canvas` en macOS arm64, `sideb-spotify-canvas.exe` en Windows x64) enlaza estáticamente las dependencias de [Cargo.lock](Cargo.lock): 116 crates en macOS y 119 en Windows (los tres adicionales son `cpufeatures`, `windows-link` y `windows-sys`, todos MIT OR Apache-2.0). Todas tienen licencia de software libre; el resumen por licencia SPDX declarada en cada crate (comprobado con `cargo metadata --locked` para `aarch64-apple-darwin` y `x86_64-pc-windows-msvc`) es:

| Licencia declarada | Crates (macOS) |
|---|---|
| MIT OR Apache-2.0 / Apache-2.0 OR MIT / MIT/Apache-2.0 | 62 |
| MIT | 21 |
| Unicode-3.0 (tablas de `icu_*`) | 18 |
| (MIT OR Apache-2.0) AND Unicode-3.0 | 2 (`unicode-ident`, `unicode-normalization`) |
| ISC | 2 (`rustls-webpki`, `untrusted`) |
| Apache-2.0 OR ISC OR MIT | 2 (`rustls`, `hyper-rustls`) |
| Apache-2.0 AND ISC (más texto OpenSSL/BoringSSL en sus fuentes) | 1 (`ring`) |
| CDLA-Permissive-2.0 (certificados raíz de Mozilla) | 1 (`webpki-roots`) |
| BSD-3-Clause | 1 (`subtle`) |
| Apache-2.0 | 1 (`sync_wrapper`) |
| Otras combinaciones permisivas (`Unlicense OR MIT`, `Zlib OR Apache-2.0 OR MIT`, `Apache-2.0 OR BSL-1.0`, `BSD-2-Clause OR Apache-2.0 OR MIT`, `MIT OR Apache-2.0 OR Zlib`) | 5 (`memchr`, `tinyvec`, `ryu`, `zerocopy`, `lru-slab`) |

Los crates dobles pueden usarse bajo cualquiera de sus opciones; los textos completos acompañan a cada crate en su versión fijada de crates.io. Esta tabla es un resumen técnico, no una auditoría legal. El TLS es `rustls` con `ring` y las raíces de `webpki-roots`: no se enlaza OpenSSL ni se usa el almacén de certificados del sistema.
