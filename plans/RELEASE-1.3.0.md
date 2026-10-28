# Release 1.3.0 — Mac y Windows

- Fecha: 2026-10-28 (America/Montevideo).
- Autorización: «hace un release y mandalo macos y windows1.3»; publicar1.3.0/build21 con ambos paquetes.
- Carpeta activa: SIDE B. No trabajar desde la copia de referencia.
- Estado: publicada como Latest y verificada; unión de FIX-267/268 y todo el trabajo autorizado de ambas plataformas conservados en SIDE B.
- Base local: d6e2c4b; origin/main d0b5549, ya integrado por contenido en SIDE B. Registrar ambas historias sin reset/stash/force push; verificar el árbol contra origin/main antes de conservar su ascendencia.
- Respaldo externo: `sideb-local-backups/2026-10-28-release-1.3.0/`.

## Pasos

- [x] Revisar versiones, workflow, autorización, remoto y CI anteriores.
- [x] Cambiar versión a1.3.0/build21 y redactar notas públicas con alcance real.
- [x] Corregir fixture Windows cuyo watcher entra en el perfil bloqueado de Edge; conservar las pruebas completas.
- [x] Probar preflight/release y revisar rutas/diff/privacidad antes de commit.
- [x] Guardar el código autorizado, preservar ancestry de origin/main, revisar tramo saliente y subir sin force.
- [x] Despachar workflow oficial del commit exacto; borrador y tagv1.3.0.
- [x] Esperar Mac arm64/Windows x64 y publicación conjunta; resolver fallos reales.
- [x] Descargar assets públicos y verificar hashes/arquitectura/versiones/Latest.
- [x] Registrar resultado y límites; ninguna release parcial.

## Hallazgos previos

CI Mac anterior falló en aislamiento de NativePlayerTitleViewport, corregido ya por FIX-266 y suites/build0167. CI Windows anterior falló en player-bar-layout al vigilar Cookies-journal del perfil de Edge bajo el root de Vite. Las fixtures son estáticas: desactivar watcher conserva la carga y las assertions sin tocar el producto ni ignorar el error. Se aplica a las tres fixtures con el mismo patrón.

## Límites

Publicación mediante workflow oficial con borrador hasta que pasen ambas plataformas. No renombrar una build1.2.7 ni mezclar artefactos de commits distintos. Firma Mac ad hoc; no afirmar notarización, audio audible, FPS físicos, cuenta real o instalación interactiva.

## Evidencia local inicial

Preflightv1.3.0/build21/prerelease=false y20regresiones de release aprobadas. PlayerBar real en Chrome/Mac conserva16geometrías e interacciones, sin omitir el test. Revisados CI anteriores:40632099958/Windows (watchEBUSY) y40632099952/Mac (actor corregido por FIX-266).

## Intento1 y determinismo de la fixture

Workflow40712727499/0c01a5d: prepare aprobado; Windows deja atrás el watcher y falla en el supuesto de animación del título. Repro local con Chrome y --force-prefers-reduced-motion falla igual antes del arreglo y pasa después. La fixture ahora fija media no-preference y foco de foreground, comprueba esa condición y conserva las assertions de Reduce Motion. La app/producto no cambia. Se cancela el intento; borrador y tag provisional sólo se retiran comprobando que siguen sin publicar/assets y apuntan al SHA esperado. Se conserva el historial y los logs. Nuevo commit y nueva ejecución de ambas plataformas, sin mezclar artefactos.

## Resize Mac sin asumir preferencias del host

CI general40712726728 detecta una aserción de644pt. Con NSScroller legacy se reproduce localmente clip683/render627, correcto para margen28 por lado. La prueba ejecuta overlay+legacy y deriva el ancho del clip nativo, conserva identidad y expansión. Las nueve focales de viewport pasan después del arreglo. El producto no cambia; el estado del segundo intento de release se sigue por su SHA exacto, sin publicar nada que no pase las puertas nativas.

## Intento 2, build local y revisión final

El intento 40714872363/f6b33a6 aprueba Windows nativo, NSIS y portable; Mac falla en la aserción de scrollbar anterior y publicación queda omitida. Al terminar el run se comprueba borrador sin assets y target exacto antes de retirar únicamente ese borrador/tag provisional. El intento 40719131271 genera ambas plataformas desde 5a4cb0d65405055462f9c5dc89d597ceccf2b74c, que incluye las regresiones de ambos estilos de scrollbar. No se reutilizan los paquetes del intento anterior.

Código guardado por lista explícita en ab9a2be; 0c01a5d conserva ascendencia remota después de auditar que el árbol ya contenía sus cambios. f6b33a6 y 5a4cb0d ajustan exclusivamente fixtures/pruebas/documentación. Main subido sin force; no se incluyen builds, cachés ni datos de usuario.

Build local oficial 0168 en SIDE B: 1.3.0/build 21, Release/compiled sobre 5a4cb0d, fuentes estables, firma estricta y diez hashes verificados. 287 Rust + 272 XCTest + 490 Swift Testing ejecutadas = 1.049 aprobadas, 17 omitidas, cero fallos. App en `builds/macos/build-0168/Side B.app`; no se instala ni se reemplaza la app abierta.

## Publicación y comprobación pública

- [Release v1.3.0](https://github.com/fefucho/sideb/releases/tag/v1.3.0), publicada el 2026-10-28 a las 16:03:50 UTC, Latest, sin draft ni prerelease. La aplicación sigue en beta como indican README y notas.
- [Workflow 40719131271](https://github.com/fefucho/sideb/actions/runs/40719131271): prepare, Mac, Windows y publish aprobados. Tag, borrador y ambos manifiestos apuntan a `5a4cb0d65405055462f9c5dc89d597ceccf2b74c`; el tag publicado no se mueve. La documentación de cierre se guarda después.
- Mac arm64: 1.049 pruebas ejecutadas aprobadas (287 Rust, 272 XCTest, 490 Swift Testing), 17 omitidas y cero fallos. Windows x64: 1.089 aprobadas (503 frontend, 112 InnerTube, 175 core, 177 core/windows-bridge, 5 player, 117 Tauri), 20 live omitidas y cero fallos. El warning CSS previo sigue sin errores de check.
- Cinco assets públicos descargados sin autenticación: ZIP Mac, instalador NSIS Windows, ZIP portable Windows y dos archivos SHA-256. Tamaños y digests de API, checksums publicados y contenido extraído coinciden. No se mezclaron artefactos de otros intentos.
- App Mac extraída: versión 1.3.0/build 21, arm64 y firma estricta válida; sus diez archivos coinciden con BUILD.json de CI. EXE portable: PE AMD64, versiones de archivo/producto 1.3.0.0; ejecutable, libmpv, Vulkan y licencia coinciden con los cuatro hashes del manifiesto Windows. El workflow comprueba también que el EXE usado por NSIS es el verificado.
- API pública Latest comprobada tanto en `fefucho/sideb` como en el alias `fefucho/SIDE-B-CLIENT-NATIVE`: v1.3.0. Tag remoto y tag local verificados contra el SHA de ambos builds.
- Evidencia local ignorada: `.cache/release-1.3.0/{public-verification.json,release.json,diagnostics,public,extracted}` y logs de los tres intentos. Se conserva fuera del contenido publicable del repositorio.

No se certifica instalación interactiva Windows, audio audible, cuenta real ni FPS físicos. Firma Mac ad hoc, sin notarización. PAR-040/042/043/044 mantienen sus pendientes de aceptación física.
