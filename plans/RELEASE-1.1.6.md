# Release estable 1.1.6

- Fecha: 2026-10-05 (America/Montevideo).
- Objetivo: publicar la actualización descargable autorizada por el usuario, quien delegó número y decisiones de publicación.
- Versión elegida: patch 1.1.6, build pública 10, tag v1.1.6; estable/Latest para el actualizador.
- Ámbito: macOS Apple Silicon/macOS mínimo 15, FIX-113–119 ya enviados a main en 62a3eb8. Conservar fuentes/core/Windows y temp local.
- Estado: build y paquete verificados; pendiente publicación.

## Pasos

- [x] Revisar main/origin, release v1.1.5 y ausencia de tag v1.1.6.
- [x] Elegir versión y actualizar version.env.
- [x] Preparar notas de producto sin atribuir validación visual/FPS a pruebas.
- [x] Runner local numerado, suites y firma ad hoc.
- [x] ZIP con ditto --keepParent, CRC, arquitectura/versión/SDK y bytes/firma tras extracción.
- [ ] Commit release con rutas explícitas y push atómico main/tag.
- [ ] Publicar draft con asset verificado y activar estable/Latest.
- [ ] Comprobar API latest, tamaño/digest y descarga pública.

## Protocolo y límites

Seguir RELEASE-1.1.5: publicar el bundle del runner local con SDK real, usar commit [skip ci] para que el workflow de tags no reemplace ese paquete con otra compilación. No modificar workflows ni versiones anteriores. El actualizador consulta /releases/latest y el asset .zip; conservar nombre SideB-macOS.zip y estructura Side B.app.

La validación visual/física de FIX-118/119 quedó pendiente por Mac bloqueado. La autorización de publicar procede del pedido actual; no afirmar audio/FPS. Firma ad hoc, sin nueva firma Developer ID/notarización.

## Verificación de paquete

- Runner: `builds/macos/build-0040/BUILD.json`, status `compiled`, `sourceChangedDuringBuild: false`.
- App: `builds/macos/build-0040/Side B.app`, versión 1.1.6/build 10, bundle com.fefucho.SideB.v2, arm64, mínimo macOS 15.0, SDK real 27.0.
- Suites: 180 Rust aprobadas (7 live ignoradas), 58 XCTest y 224 Swift Testing en 5 suites: 462 aprobadas.
- ZIP: `builds/macos/build-0040/SideB-macOS.zip`, 26957548 bytes.
- SHA-256: `42c179d2d58aca9db5a567e7228088463da95bcaddfbbe3b393a6816d3a9ea18`.
- CRC correcto, sólo bundle y metadatos macOS; bytes de todos los archivos idénticos tras extracción, firma ad hoc estricta verificada en original y extraído.
- Fuentes de app: commit 62a3eb85cfa27d2b132ad38315553e5f531bdd02 más version.env 1.1.6/10; sólo documentos de release actualizados después del runner.

## Notas de la release

## Novedades

- Álbumes y playlists comparten cabecera y lista de canciones en un único desplazamiento, con fondo basado en la carátula y enlaces de artista/álbum.
- Buscador de canciones transparente desde el foco, borrado estable y mensaje sin resultados separado de la cabecera para evitar saltos.
- Ajuste del fondo de los detalles para cubrir también la zona de la barra superior y la sidebar.
- Inicio conserva las tarjetas al cambiar columnas y evita recargar estantes que no cambiaron al abrir o cerrar la sidebar.
- La cola recupera su presentación propia con Me Gusta/No me gusta y control de arrastre.
- Playlists: filtro y opciones de orden conservan la colección completa al reproducir; reordenamiento disponible en playlists propias compatibles.

## Descarga

`SideB-macOS.zip` contiene **Side B 1.1.6 (build 10)** para **Mac con Apple Silicon**, mínimo **macOS 15**.

Paquete con firma ad hoc verificada, sin notarización Developer ID. Release de macOS; el port Windows continúa por separado.

Esta release aprobó 462 pruebas automáticas (180 Rust, 58 XCTest y 224 Swift Testing). La comprobación visual y de fluidez con cuenta real continúa pendiente.
