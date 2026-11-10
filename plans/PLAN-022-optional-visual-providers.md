# PLAN-022: Proveedores visuales opcionales

Fecha: 2026-11-01. Estado: implementado en fuentes Mac, pruebas sin cuenta aprobadas; QA real/Windows pendientes. Pedido: integración Spotify separable, instalable por elección del usuario. Corrección de alcance: **Apple Music primero; Spotify sólo como alternativa en el reproductor lateral vertical**. Fullscreen no consulta proveedores externos.

## Arquitectura y ámbito

Host genérico Mac + ejecutable Rust separado por JSON/stdio v1. Proveedor fuera del core y fuera de la dependencia de la app. No modifica audio, cola, contratos UniFFI ni el proveedor Apple. Instalación y token explícitos, apagado por defecto, token en Keychain separado. Futuro host Windows consume el mismo protocolo; port pendiente.

Referencias: [reporte](research/SPOTIFY-CANVAS-EVALUATION-2026-11-01.md), [contrato](../extensions/README.md), PLAN-012, PLAN-021. FIX-283 / PAR-050.

## Pasos

- [x] Definir protocolo, paquete y límites; separar el código específico de Spotify.
- [x] Implementar consulta Pathfinder, matching conservador y descarga acotada Rust.
- [x] Host Mac, instalación/desinstalación, credencial protegida y settings ES/EN.
- [x] Apple primero; alternativa sólo lateral; identidad por canción al habilitar extensión.
- [x] Cancelación, salida acotada, validación local y liberación tras desmontar player.
- [x] Finalizar pruebas y registrar FIX-283/PAR-050:4Rust,863Swift globales y26focales finales aprobadas; formato/Clippy y844claves ES/EN verificados.
- [x] Corregir negociación del client-token (`Accept: application/json`), probar autenticación/Pathfinder con Bearer por mecanismo privado y empaquetar extensión arm64 v0.1.1.
- [x] Obtener Canvas `ready` para dos pistas y validar MP4 real con AVFoundation; ampliar el tope del host al formato 720×1280 observado.
- [x] Corregir validación final del controlador de artwork/AVPlayer para Canvas de extensión 720×1280 hasta1920px; agregar regresión focal.
- [x] Build local macOS 0189 Release; 583 tests en 34 suites aprobados, BUILD.json compiled y fuentes estables durante el build.
- [x] Corregir falso negativo de coincidencia para video YouTube extendido con track Spotify único por metadata; compilar e instalar extensión v0.1.2 sin borrar la credencial. Confirmación live de «Follow God» pendiente.
- [x] Preservar token y estado enabled al actualizar el mismo provider ID; indicar explícitamente cuando falta guardar el Bearer. Compilado en build-0192 Release.
- [x] FIX-288: actualizar hash/variables de búsqueda y descubrir el hash desde el bundle público ante `PersistedQueryNotFound`; 6 tests, descubrimiento live, clippy/fmt/build y paquete v0.1.3 aprobados.
- [ ] Instalar el paquete v0.1.3 y confirmar render en el lateral con Apple Music como proveedor prioritario.
- [ ] Host y settings Windows, validación Windows real.

## Límites y decisiones

Login único por WebView y renovación autónoma del Bearer en el host (FIX-300; sin validar con Spotify real). No se importan cookies ni se incluye catálogo TOTP remoto. Matching requiere título, artista, duración y álbum si existe; rechaza ambigüedad. Sólo MP4 H.264 vertical 720–1920px de alto y hasta8.5s; JPG/no coincidencia/error conservan el proveedor habitual. Archivos temporales privados por solicitud, sin caché persistente de coincidencias ni negativos.

Un plugin es código de confianza con acceso del usuario, no una sandbox ni una autorización del proveedor. Las restricciones de uso de Spotify continúan aplicando. No se creó una release pública; la build local 0189 se conserva en el repositorio de trabajo. La consulta y descarga se validaron con cuenta real, pero el render dentro de la app sigue pendiente de comprobar en esta build.
