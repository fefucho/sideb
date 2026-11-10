# PLAN-034: Inicio con rieles continuos

Estado: build-0186 rechazada por usuario (portadas superpuestas/texto perdido y lag). Corrección nativa FIX-286; revisión del padre, perfil y nueva build pendientes.

Objetivo: aplicar opción A de /tmp/sideb-approved-home-demo.html usando datos reales.
Alcance: Apple Home; excluye core, Windows, shell y sidebar.
Referencias: FIX-098/099/100/119; FIX-285; PAR-051.

- [x] Inicio siempre apilado; Speed Dial continuo de hasta 27 canciones, min(3, cantidad) filas de 126 pt, gap 12.
- [x] Álbumes/playlists de una fila, pie 120 con paleta al 24% y metadata tipada real.
- [x] Solicitudes acotadas al rango visible; sin estado/vistas de paginación en destacados.
- [x] Flechas/fades por overflow, routing horizontal/vertical, identidad y ancla por ID al resize.
- [x] Ver todo abre sheet de colecciones destacadas reales con acciones actuales.
- [x] Actualizar y ejecutar pruebas focales solicitadas: 10 XCTest y 33 Swift Testing aprobados.
- [x] Revisión del integrador: cierre/navegación de hoja, metadatos del viewport de hoja, accesibilidad de flechas y bordes; 43 focales nuevamente aprobados.
- [x] Build oficial macOS `build-0186`: compiled; 862 Swift y 298 Rust aprobadas (10 Rust ignoradas), empaquetado y firma verificados.
- [ ] Validación visual en la app con el usuario.

Verificación: `swift test --package-path apple --no-parallel --filter 'HomeFeatured|HomeSpeedDial|HomeAlbumMetadata|HomePlaylistMetadata|HomeGesture'`; log `/tmp/home-final-tests.log`. Diff focal sin errores de whitespace. Sin QA manual, build empaquetada, commit ni push; sin subagentes.

Build de prueba: `builds/macos/build-0186/Side B.app`; registro `BUILD.json` del mismo directorio. Rama `design/home-speed-dial-cards`.


Corrección tras feedback real (FIX-286):
- [x] Migrar ambos rieles al renderer AppKit existente con virtualización/reutilización de celdas NSCollectionView.
- [x] Acotar imagen/gradiente/textos explícitamente y probar imágenes no nil cuadradas/horizontales/verticales a2×.
- [x] Publicar sólo cambios de rango; playback sin recarga completa; cancelación y generación al reutilizar/ocultar/cambiar sesión.
- [x] Fixture y PNG nativo `/tmp/sideb-home-native-review.png`, contadores de celdas/solicitudes y acciones/menú tras reuse.
- [x] Integrador inspecciona render de ambos rieles con portadas reales; corrige observación de scroll, suspensión, willDisplay y ancla de registros.
- [ ] Nueva build oficial y QA en app real.
- [ ] Perfil de carga de toda la app para determinar costo restante; no afirmar lag/FPS resueltos.

Log focal de esta corrección: `/tmp/sideb-home-native-final.log`. Los resultados/build anteriores arriba son históricos y no validaron el desborde con imágenes cargadas.

Pasadas finales: `/tmp/sideb-home-native-last.log` y `/tmp/sideb-home-native-images.log` (4 XCTest nativas/cache aprobadas). ImageCache real deduplica dos solicitudes concurrentes al mismo PNG local, downsample404×202 y misma instancia en memoria; cero red.
