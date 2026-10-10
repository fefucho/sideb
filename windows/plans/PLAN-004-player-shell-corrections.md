# PLAN-004 — Corregir Genius, metadata y controles del shell

- Fecha: 2026-10-10 (America/Montevideo).
- Estado: implementación, revisión y verificación automatizada terminadas; build-0006 conservada. Aceptación física pendiente.
- Objetivo: resolver los bugs comunicados tras build-0005, contrastando presentación y animación con Apple vigente.
- Ámbito: Windows; Apple de referencia, core protegido. Conservar árbol local y acciones existentes; sin commit/push/publicación ni cuenta real.
- Antecedentes: FIX-132/133/135 y [PLAN-003](PLAN-003-macos-integration.md).

## Ejecución supervisada

- [x] Agente Genius: sólo Cola/Letras/Relacionado arriba; botón Genius inferior selecciona Letras con modo Genius. Ajustar tipografía al origen Apple.
- [x] Agente Genius: icono info.circle junto al corazón; reverso cuadrado de carátula, estilo Apple y giro horizontal 0.48 s, sin mover metadata; Reduce Motion y foco.
- [x] Agente Genius: anotación anclada a línea con piquito, cierre exterior/Escape y reposicionamiento/cancelación al scroll/resize.
- [x] Agente metadata: rastrear views del acceso rápido, conservar artista y resolver álbum real sin convertir contador en nombre.
- [x] Integrador: Atrás/Adelante fuera de sidebar, por encima del contenido; quitar Volver y puntos superiores sin respuesta, conservando acceso a comandos.
- [x] Agente ambiente + integrador: corregir capas de álbum/playlist y medición de cabecera para ambiente continuo, scroll y fullscreen.
- [x] Integrador: revisar diff de agentes, comunicar fallos concretos y ejecutar check/tests/build apropiados.
- [x] Registrar FIX/PAR y resultados; conservar nueva build por protocolo sin sobreescribir build-0005.

## Comprobaciones y límites

Validar fixtures con nombres largos, loading/error, álbum conocido/desconocido, anotación al borde, scroll/resize, ventana amplia/angosta y sidebar 230/60. Separar frontend, runtime/build y validación física. No afirmar audio/SMTC/cuenta/DPI/Narrator sin ensayos reales.

## Revisión supervisada

- Se señaló y corrigió al agente la pérdida de medidas del ambiente: Svelte reemplaza cssText al animar; top/height/visibility ahora son estado y directivas reactivas.
- Revisión cruzada señaló artistRuns antiguos con contadores y parejas nombre/ID incompatibles; corrección nativa y regresiones antes de build.
- Revisión cruzada reprodujo solicitudes Genius repetidas tras respuestas vacías/error; controller ahora conserva intento aceptado y reintenta sólo por acción explícita. 14 pruebas controller + 8 popover aprobadas; check 0/0.
- Fixture con componentes reales en navegador: 1440×900, sidebar 230 y 60; ambiente top0/height434 persistente durante animación, scroll900→top−900/height434. Resize850×700→height472.547 por cabecera medida; flechas permanecen arriba a la derecha. Buscar comparte fila con acciones cuando cabe. Sidebar fixture simplificada; no certifica runtime Tauri.
- Revisión Genius: tres pestañas, fuente20, reverso cuadrado y transición .48; anotación con flecha y cierre exterior. Pruebas focales cubren viewport angosto, clip parcial, cancelación pendiente y Escape.
- Rutas temporales retiradas y navegador restaurado/cerrado al finalizar revisión. Fixtures fuente sólo en `.cache/` ignorada.

Registros: [FIX-137](../../FIXES.md#fix-137), [FIX-138](../../FIXES.md#fix-138), [FIX-139](../../FIXES.md#fix-139); paridad PAR-011/015/019/013-2/016-2 y nueva PAR-022 para investigar metadata Apple/core.

## Resultado de cierre — 2026-10-10 11:49 (America/Montevideo)

- `node Scripts/build-version.mjs windows`: exit 0; verify y build aprobados por protocolo, con MSVC 2022 y dependencias/caché existentes.
- Frontend: `pnpm check` 0 errores/0 advertencias, `pnpm test` 258/258 y `pnpm build` aprobado.
- Rust: InnerTube 92, sideb-core 90 sin bridge +92 con bridge, player 4, Tauri 78. Total nativo 356; total integrado **614 aprobadas**, cero fallos, 14 live ignoradas. Incluye el último guard nombre/ID compatible antes de rellenar artistRuns.
- Release: [build-0006/sideb-windows.exe](../../builds/windows/build-0006/sideb-windows.exe), acompañado por libmpv-2.dll, vulkan-1.dll y VulkanRT-License.txt. [BUILD.json](../../builds/windows/build-0006/BUILD.json): `status: compiled`, `sourceChangedDuringBuild: false`; cuatro hashes SHA256 comprobados. [Log](../../builds/windows/build-0006/build.log). Builds anteriores conservadas.
- `git diff --check` limpio; sin cambios Apple/core. Rutas de review retiradas; Vite y navegador de prueba cerrados. Sin commit/push/publicación.
- Advertencias Rust históricas de campos sin uso y LNK4098 conservadas; no bloquean build ni se atribuyen a estos fixes.
- Límites: no se abrió el EXE ni se verificó audio audible, servicios Genius/cuenta real, SMTC físico, DPI/Narrator/gestos o actualización instalada. La revisión visual usa navegador con fixtures; aceptación final WebView2 pendiente. Si el proveedor no entrega álbum real, queda ausente en vez de mostrar views.
