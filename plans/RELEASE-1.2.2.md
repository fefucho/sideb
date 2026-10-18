# Release 1.2.2

- Fecha: 2026-10-17 (America/Montevideo).
- Estado: entregada2026-10-18;1.2.2 Latest con cinco descargas públicas verificadas. Ambas builds nativas aprobadas en8b8e135; FIX-210 corrige colección y completa el borrador tras el fallo del publicador.
- Objetivo: subir fuentes de FIX-207/208 a main y publicar ambos sistemas mediante Release Side B; comprobar paquetes/checksums antes de anunciar éxito.
- Versión:1.2.2/build15, tag v1.2.2, distribución numérica Latest con aviso beta en notas como1.2.1. No reemplazar la release publicada anterior.
- Alcance: volumen wheel Windows FIX-207; ancho/título Explorar y cabeceras desplazables Biblioteca/Búsqueda Apple FIX-208. No modificar core/proveedor/contratos. Conservar prototipos/caché y aplicaciones locales fuera de Git.
- Autorización: pedido «subí la app a GitHub, hacé el release» incluye commit/push/tag/publicación. No requiere otra confirmación. Usar sideb-git para preparar y subir fuentes; release por dispatch del workflow existente.

## Pasos

- [x] Revisar main/remoto y Latest; local/remoto c828d30 sin divergencia, Latest1.2.1. Repo canónico fefucho/sideb; conservar remote histórico redirigido y datos de cuenta.
- [x] Revisar FIX-207/208 y QA previa. Mac build0132/761pruebas y UI aislada parcial aprobados; Windows381frontend/1omisión enMac, check0/0/build frontend aprobados. Son evidencia previa, no binarios1.2.2.
- [x] Actualizar versiones de app/manifests/lock propio, default del workflow y notas1.2.2 sin tocar versiones de dependencias/core.
- [x] Aprobar preflight/checks de publicación y frontend relevante;17 tests runner/release, preflight v1.2.2/build15, frontend381aprobadas/1fixture nativa omitida enMac, check0/0 y build aprobados. Diffcheck limpio; rutas de código/tests/docs explícitas, core y dependencias conservados.
- [x] Commit8b8e1355ffb769e157f396d69264ba2e0d6f5259 con FIX-207/208/209; pushmain y dispatch [release39091299331](https://github.com/fefucho/sideb/actions/runs/39091299331). Prepare aprobado, borrador vacío/tag v1.2.2 apuntan a ese SHA; últimas publicadas conservadas.
- [x] Seguir ambas builds nativas hasta su resultado; Mac y Windows aprobados con761pruebas cada uno. No reutilizar paquetes1.2.1 ni reetiquetar build0132. Fallo posterior del publicador se trata en FIX-210 conservando los binarios de8b8e135.
- [x] Verificar release publicada, Latest/tag/revisión, tres paquetes descargables y dos checksum files. Cinco descargas nuevas sin autenticación idénticas a artefactos CI; SHA256/tamaños/digests,14archivos internos, contenido Mac/portable y firma Mac aprobados.
- [x] Cerrar registros con resultados reales, enlace y límites físicos; FIX-207/208/209/210 y PAR-026/PAR-032 actualizados.

## Límites

Mac sigue con firma ad hoc sin notarización. Windows se compila en runner Windows; frontend enMac no demuestra runtime nativo. Cuenta personal, audio audible, instalador interactivo, VoiceOver/trackpad/FPS físicos no se certifican por la release. La build0132 se conserva como prueba previa con versión1.2.1; la release genera binarios1.2.2/build15 desde su commit exacto.

## Resultados hospedados

- macOS job117568496853 aprobado:761 pruebas ejecutadas (188Rust/236XCTest/337SwiftTesting;7Rust ignoradas/7Swift omitidas), compiled/sourceChangedDuringBuild=false, versión1.2.2/build15 y diez hashes aprobados por el guard de release. Artefactos release-macos12123003237 y release-diagnostics-macos12123306644 descargados y verificados localmente; ZIP SHA256 `604d9fe3a03abc8909a8d9c12bd8b830f0e8eeb343a59abb8cc4cb5ba627a2fb`, firma deep/strict y diez archivos extraídos coinciden con BUILD.json. Fuentes de la revisión exacta8b8e135, sin recuperación manual ni relabel. Windows permanecía en su paso nativo al validar Mac; su resultado final se detalla debajo.
- Windows job117568496842 aprobó build/validación/NSIS/portable/subida de artefactos; post-caché cerrado correctamente.761 pruebas ejecutadas aprobadas (382frontend/97InnerTube/91core/93core+bridge/5player/93Tauri;14Rust ignoradas), check0/0, compiled/sourceChangedDuringBuild=false, versión1.2.2/build15 y revisión8b8e135. Artefactos release-windows12123595699 y release-diagnostics-windows12123830010 descargados; hashes instalador/portable coinciden con checksum y cuatro archivos internos del portable con BUILD.json; ejecutable PE x64 correcto. No se ejecuta el instalador enMac ni se afirma audio audible. Job finalizado con success; publicación posterior recuperada por FIX-210.

### Fallo de colección del publicador — FIX-210

Ambos jobs terminaron success. El job117572820187 descarga correctamente los artefactos y falla antes de sha256sum, al no encontrar el primer archivo en la raíz. Los cinco paquetes/checksums están dentro de build-0001; merge-multiple conserva esa jerarquía. FIX-210 añade colección plana con validación estricta y pruebas. Los binarios se mantienen exactos de8b8e135/tagv1.2.2 y no se recompilan ni relabelan; se completará el borrador vacío existente mediante el mismo colector verificado. El workflow corregido quedará en main para próximas publicaciones; historial fallido conservado con causa explícita.

## Entrega completada

[Side B1.2.2](https://github.com/fefucho/sideb/releases/tag/v1.2.2), publicada2026-10-18 00:15:59 America/Montevideo. Cinco archivos: ZIP Mac, instalador Windows, portable Windows y dos manifiestos SHA256. Tag/target8b8e135, Latest y flags aprobados. Fuentes8b8e135 y arreglo de infraestructura37f5e1e subidos a main. El colector corregido reúne/verifica los artefactos ya aprobados y la CLI completa el borrador vacío, sin mover el tag ni alterar bytes. La ejecución original conserva el fallo del publicador, no se presenta como completamente aprobada.

Descargas públicas nuevas sin autenticación idénticas al staging/artefactos CI; portable PE x64 y cuatro runtimes, Mac arm64/min15/versión1.2.2/build15/firma deep-strict y diez archivos comprobados. Evidencia/paquetes/diagnósticos en builds/releases/v1.2.2, incluido release-verification.json.20 pruebas runner/release aprobadas tras FIX-210;1.522ejecuciones de pruebas nativas aprobadas sumando ambas plataformas. La aceptación física pendiente se mantiene.
