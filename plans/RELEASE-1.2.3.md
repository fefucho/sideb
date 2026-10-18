# Release 1.2.3

- Fecha: 2026-10-18 (America/Montevideo).
- Estado: entregada; [1.2.3](https://github.com/fefucho/sideb/releases/tag/v1.2.3) Latest publicada2026-10-18 14:52:53 America/Montevideo. [CI39149085379](https://github.com/fefucho/sideb/actions/runs/39149085379) termina success en sus cuatro jobs, desde d8619caf93a753dc55a0343e7b3242383610a840. Cinco descargas públicas/checksums y contenido interno aprobados.
- Objetivo: publicar FIX-211 para que el usuario pueda actualizar su PC; entregar Mac y Windows en la misma release, con paquetes y checksums comprobados.
- Versión:1.2.3/build16, tag v1.2.3, Latest numérica con aviso beta, igual que las entregas anteriores.
- Alcance: política de entrada Windows y regresiones basadas en deltas numéricos; diagnóstico local acotado. Mac conserva fuentes/UI/audio de1.2.2; core y dependencias conservados. Versiones/manifests y notas actualizadas, sin relabel de binarios anteriores.
- Autorización: «actualiza entonces pone1.2.3» continúa el pedido de publicar el arreglo e incluye commit/push/tag/release; no requiere otra confirmación.
- Referencias: [FIX-211](../FIXES.md#fix-211), FIX-212, [PLAN-009 Windows](../windows/plans/PLAN-009-volume-scroll-feedback.md), PAR-026/PAR-032.

## Pasos

- [x] Revisar main/remoto/releases: local y origin/main en7c8ebbc, sin divergencia ni intento activo; Latest1.2.2 y sin release1.2.3. Caché/prototipos y captura original del usuario quedan fuera de Git.
- [x] Actualizar version.env/manifests Windows/versión del paquete propio en Cargo.lock/default del workflow y notas1.2.3. No cambiar versiones de dependencias.
- [x] Aprobar preflight v1.2.3/build16 y20tests runner/release; frontend384aprobadas/1fixture nativa omitida enMac, check0/0/build aprobado. Diff, FIXES, paridad y paths explícitos revisados; no son comprobaciones nativas1.2.3 todavía.
- [x] Commit/pushmain d8619caf93a753dc55a0343e7b3242383610a840 y dispatch [Release Side B39149085379](https://github.com/fefucho/sideb/actions/runs/39149085379) para v1.2.3. Preparación aprobada; borrador vacío y tag apuntan a ese SHA exacto. Main remoto sincronizado, caché/prototipos locales conservados.
- [x] Seguir compilación/pruebas nativas Mac y Windows hasta success;761Mac/764Windows ejecutadas aprobadas, fuentes estables y ambos paquetes verificados. Publicador corregido por FIX-210 aprueba sin recuperación manual.
- [x] Verificar publicación Latest/tag/revisión, tres paquetes y dos archivos SHA256, metadatos de build/fuentes/hashes y descargas públicas. Cinco descargas nuevas sin autenticación idénticas a artefactos CI; frontend del EXE público idéntico al frontend local probado.
- [x] Registrar entrega y límites físicos con enlace y resultados reales en FIX-211/212, PAR-026/PAR-032 y PLAN-009.

## Límites

Las pruebas del fix reproducen tres grupos de entrada real y usan RPC simulado; la build nueva requiere prueba física del usuario en Windows. No se prueba cuenta personal, audio audible ni instalación interactiva por publicar paquetes. Mac mantiene firma ad hoc sin notarización. No se reemplaza1.2.2 ni se abre/instala una app local.

## Resultados hospedados

- macOS job117738935493 aprobado:761pruebas ejecutadas (188Rust/236XCTest/337SwiftTesting;7Rust ignoradas/7Swift omitidas), compiled/sourceChangedDuringBuild=false, versión1.2.3/build16 y SHA d8619ca. Artefactos release-macos12144638048 y release-diagnostics-macos12144862338 descargados. ZIP SHA256 `4ccb816dbcfb1dda866916ac4a5fedae6764e445981a085ac72263cf113e5b2a`, diez hashes internos, firma deep/strict/arm64/mínimo15 y plist1.2.3/16 aprobados tras extracción local. Build/pruebas nativas8,5min; Windows seguía activo al verificar Mac. Evidencia en builds/releases/v1.2.3/actions y mac-ci-extracted.
- Windows job117738935620 termina success, incluido cierre de caché:764pruebas ejecutadas (385frontend/97InnerTube/91core/93core+bridge/5player/93Tauri;14Rust ignoradas), check0/0, compiled/sourceChangedDuringBuild=false, versión1.2.3/build16 y SHA d8619ca. Artefactos release-windows12145450800 y release-diagnostics-windows12145156673 descargados; dos paquetes coinciden con su manifiesto SHA256 y cuatro archivos del portable con BUILD.json; PE x64 válido. Frontend del EXE CI descomprimido byte a byte idéntico al frontend local verificado: asset2.6UQMOzZS.js,538755bytes, SHA256 `d406088062b533d8626e98f59441c5f2101dcf9ac415a919f6703719d55aaa32`. Verificación/compilación nativa23,5min; sin ejecución del instalador ni audio audible enMac.

## Entrega completada

[Side B1.2.3](https://github.com/fefucho/sideb/releases/tag/v1.2.3), publicada2026-10-18 14:52:53 America/Montevideo como Latest, con aviso beta y sin flag prerelease. Tag/target d8619caf93a753dc55a0343e7b3242383610a840, versión1.2.3/build16, cinco assets/tamaños/digests y ambos manifiestos aprobados. Jobs de preparación117738866025, Mac117738935493, Windows117738935620 y publicador117746141630 terminan success; sin relabel ni recuperación manual.1.525ejecuciones de pruebas nativas aprobadas entre ambas plataformas.

Descargas públicas nuevas sin autenticación coinciden con los artefactos CI. Mac ZIP SHA256 `4ccb816dbcfb1dda866916ac4a5fedae6764e445981a085ac72263cf113e5b2a`; instalador Windows `220ee04b9b33af7983a40bcd9e38dcc47ebc098b6a8e027feeb1ce66723f7bf2`; portable `c99d4d137184435532513f5afafc256f16930f8994d0d062d530a5cd400f8f22`. Diez hashes internos Mac y cuatro Windows, firma Mac y arquitectura/versiones aprobados también en descargas públicas. El EXE público contiene el mismo asset frontend verificado byte a byte arriba; no se entregó un frontend anterior.

Evidencia en builds/releases/v1.2.3/release-verification.json, actions/, mac-extracted/ y descargas públicas de los cinco archivos. Fuentes subidas en d8619ca;1.2.2 conservada sin modificar. Entrada física del nuevo EXE, audio audible e instalación interactiva pendientes de prueba del usuario; no se declaran resueltos por CI.
