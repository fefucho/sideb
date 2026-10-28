# Release 1.3.0 — Mac y Windows

- Fecha: 2026-10-28 (America/Montevideo).
- Autorización: «hace un release y mandalo macos y windows1.3»; publicar1.3.0/build21 con ambos paquetes.
- Carpeta activa: SIDE B. No trabajar desde la copia de referencia.
- Estado: preparación; conservar la unión de FIX-267/268 y todo el trabajo autorizado de ambas plataformas.
- Base local: d6e2c4b; origin/main d0b5549, ya integrado por contenido en SIDE B. Registrar ambas historias sin reset/stash/force push; verificar el árbol contra origin/main antes de conservar su ascendencia.
- Respaldo externo: `sideb-local-backups/2026-10-28-release-1.3.0/`.

## Pasos

- [x] Revisar versiones, workflow, autorización, remoto y CI anteriores.
- [x] Cambiar versión a1.3.0/build21 y redactar notas públicas con alcance real.
- [x] Corregir fixture Windows cuyo watcher entra en el perfil bloqueado de Edge; conservar las pruebas completas.
- [ ] Probar preflight/release y revisar rutas/diff/privacidad antes de commit.
- [ ] Guardar el código autorizado, preservar ancestry de origin/main, revisar tramo saliente y subir sin force.
- [ ] Despachar workflow oficial del commit exacto; borrador y tagv1.3.0.
- [ ] Esperar Mac arm64/Windows x64 y publicación conjunta; resolver fallos reales.
- [ ] Descargar assets públicos y verificar hashes/arquitectura/versiones/Latest.
- [ ] Registrar resultado y límites; ninguna release parcial.

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
