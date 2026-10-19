# Release 1.2.5

- Fecha: 2026-10-19 (America/Montevideo).
- Estado: preparación; compilación nativa/publicación pendientes.
- Objetivo: publicar los botones refinados y las acciones de cuenta inmediatas de FIX-221/222 mediante el actualizador.
- Versión: 1.2.5/build18, tag v1.2.5, Latest numérica con aviso beta como1.2.4.
- Autorización: «subi la uptadte» continúa el pedido de corregir Windows y autoriza commit/push/tag/release; no requiere otra confirmación.
- Base: origin/main0ca3f64, Latest1.2.4/c86454e verificada en GitHub. Conservar su arreglo de rueda y todos los commits remotos. Las versiones anteriores permanecen publicadas.
- Alcance: FIX-221/222 y metadatos/notas/registro de publicación. Apple/core funcionales se mantienen iguales a origin/main. Cambios locales anteriores de sidebar/apariencia, prewarm del core y diagnósticos sin relación permanecen en la carpeta original; no se incluyen por compartir archivos.
- Aislamiento: worktree Git dedicado `sideb-release-1.2.5`, porque el workspace original conserva trabajo pendiente. El creador de worktrees del app no reconoce el repositorio anidado; se usa `git worktree` sin modificar ese árbol.

## Pasos

- [x] Consultar remoto, versiones y workflows; no había release nueva ni compilación activa del destino.
- [x] Trasladar únicamente las fuentes/planes de FIX-221/222 sobre1.2.4 y preservar la corrección remota del volumen.
- [x] Actualizar version.env/manifests/paquete propio en Cargo.lock/default manual del workflow/notas1.2.5.
- [x] Aprobar preflight, pruebas de release/runner y frontend de este checkout aislado; diff y fuentes Apple/core revisados.
- [ ] Commit/pushmain y tag de ese SHA exacto; seguir el workflow de release.
- [ ] Aprobar los builds/pruebas nativos de Mac/Windows y publicar sus cinco assets conjuntamente.
- [ ] Verificar Latest, tag/commit, versiones/hashes de artefactos y descargas públicas.
- [ ] Registrar entrega y límites físicos, cerrar el estado del plan y la paridad que tenga evidencia nueva.

## Límites

Las pruebas locales de FIX-221/222 se hicieron en un árbol con otros cambios; esta release repite frontend en el checkout exacto. La mejora de latencia física de cuenta/proveedor real y la instalación del usuario necesitan prueba en su Windows. No se mide audio audible ni FPS. Mac mantiene firma ad hoc sin notarización. No se instala ni abre una app local al publicar.

## Preflight del checkout de entrega

Preflightv1.2.5/build18,20tests release/runner y396tests frontend aprobados,1fixture nativa omitida; check0errores/0advertencias y build frontend aprobado. Apple/core y fuentes de volumen idénticos a origin/main. Cargo.lock cambia sólo la versión del paquete propio. Diff revisado, fuentes anteriores ajenas conservadas en el árbol original.
