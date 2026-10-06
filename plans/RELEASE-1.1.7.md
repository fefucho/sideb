# Release estable 1.1.7

- Fecha: 2026-10-06 (America/Montevideo).
- Objetivo: publicar la actualización autorizada por el usuario conservando la implementación actual de FIX-120–129.
- Versión: patch 1.1.7, build pública 11, tag v1.1.7; estable/Latest para el actualizador.
- Ámbito: macOS Apple Silicon, mínimo macOS 15. Incluye Explorar/rankings, optimizaciones de catálogos e Inicio, historial con feedback y descenso interactivo de Ahora suena. No se modifica funcionalidad en esta publicación.
- Estado: publicada estable/Latest; API, digest y descarga pública verificados.

## Pasos

- [x] Revisar main/origin, release v1.1.6 y cambios locales de FIX-120–129; conservar temp fuera de Git.
- [x] Elegir versión y actualizar version.env.
- [x] Preparar notas de producto según comportamiento vigente, sin atribuir validación física/FPS a pruebas.
- [x] Runner numerado, suites, fuente estable y firma ad hoc.
- [x] ZIP con ditto --keepParent; CRC, arquitectura/versión/SDK, bytes y firma tras extracción.
- [x] Commit con rutas explícitas y push atómico main/tag.
- [x] Draft con asset verificado; publicar estable/Latest.
- [x] Verificar API latest, digest y descarga pública.

## Protocolo y límites

Seguir RELEASE-1.1.6: publicar el bundle del runner local y usar commit [skip ci] para evitar que el workflow de tags sustituya el paquete verificado. Conservar workflows y versiones anteriores. El actualizador consulta /releases/latest y su asset .zip; conservar nombre SideB-macOS.zip y estructura Side B.app.

Las pruebas y QA de cada fix se conservan en FIXES.md y sus planes. El usuario pidió publicar la implementación actual. El ensayo físico completo de trackpad, dirección natural, FPS y audio con cuenta real sigue pendiente. Firma ad hoc, sin notarización Developer ID. Windows mantiene sus pendientes de PARIDAD.md.

## Verificación del paquete

- Runner: `builds/macos/build-0062/BUILD.json`, estado `compiled`, `sourceChangedDuringBuild: false`.
- Suites: 182 Rust (7 live ignoradas), 115 XCTest y 235 Swift Testing aprobadas: 532, cero fallos.
- App: `builds/macos/build-0062/Side B.app`, versión 1.1.7/build 11, bundle com.fefucho.SideB.v2, arm64, mínimo macOS 15.0, SDK real 27.0.
- ZIP: `builds/macos/build-0062/SideB-macOS.zip`, 27235944 bytes.
- SHA-256: `b6998dbf898b6c2f157d5e7cb07a9a7da3c508d538c2b6d3649cd0d8bbf1e3b3`.
- Cinco hashes del manifest coinciden; CRC y bytes de todos los archivos coinciden tras extracción. Firma ad hoc estricta verificada en original y extraído; sin flag de diagnóstico en el Info.plist de producción.
- Evidencia local: `builds/macos/build-0062/release-package-verification.json`. No se cambian fuentes core/bindings/Windows durante esta publicación; el checkpoint previo c59acce aporta Explorar y el contrato común de FIX-120.
- Después del runner sólo se actualiza documentación y se retira una línea vacía final de WindowGestureRegionTests para cumplir git diff --check; casos/aserciones conservados. Fuentes de app y version.env conservan los bytes compilados.

## Publicación verificada

- Commit release/tag: `9070861abf0bccc8c41d229159d661f321941b26`; tag anotado `v1.1.7`, enviado con main en push atómico. Incluye FIX-120–129, paridad y planes; temp permanece fuera de Git.
- Release: [Side B v1.1.7](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/releases/tag/v1.1.7), ID 404982549, publicada 2026-10-06T17:32:29Z (14:32:29 America/Montevideo).
- Draft y asset verificados antes de activar estable/Latest. `draft: false`, `prerelease: false`; API pública `/releases/latest` devuelve `v1.1.7`.
- Asset `SideB-macOS.zip`: ID 616187184, estado uploaded, 27235944 bytes. Digest remoto `sha256:b6998dbf898b6c2f157d5e7cb07a9a7da3c508d538c2b6d3649cd0d8bbf1e3b3`, igual al local.
- Descarga pública sin autenticación: tamaño/SHA-256/CRC coinciden, notas publicadas iguales al archivo preparado. Evidencia en `builds/macos/build-0062/release-publication-verification.json` y copia descargada en `public-download-verification/`.
- `gh run list --branch v1.1.7` no mostró runs; commit [skip ci] conserva el paquete local y workflow existente. Cierre documental en commit posterior, sin mover el tag ni reemplazar el asset.

## Notas de la release

- Explorar incorpora lanzamientos, categorías y rankings globales y de la región detectada, con selector para consultar otros países.
- Catálogos largos de lanzamientos usan tarjetas recicladas para reducir el trabajo al cargar y desplazar álbumes.
- Inicio suspende fondo y actualizaciones del feed mientras Ahora suena lo cubre; se corrigen los límites del shell al abrir la sidebar.
- Atrás/Adelante con trackpad muestra progreso, destino y confirmación al soltar, con respuesta háptica cuando el dispositivo la admite.
- En Inicio, carruseles, filtros y destacados paginados conservan su gesto horizontal; títulos y espacios libres mantienen navegación de historial.
- Ahora suena permite arrastrar hacia abajo con dos dedos para cerrar, acompañando el movimiento y conservando el scroll de cola/listas/letras.

SideB-macOS.zip contiene Side B 1.1.7 (build 11), para Mac con Apple Silicon y macOS 15 o posterior. Paquete con firma ad hoc verificada, sin notarización Developer ID. Esta release aprobó 532 pruebas automáticas (182 Rust, 115 XCTest y 235 Swift Testing); validación física completa de trackpad y FPS/audio con cuenta real pendientes.
