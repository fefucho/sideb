# PLAN-003 — Ejecución de la integración macOS → Windows

- Fecha: 2026-10-09; actualizado 2026-10-10 (America/Montevideo).
- Estado: integración, revisión y verificación automatizada terminadas; build-0005 conservada. Aceptación física pendiente.
- Objetivo: ejecutar las funciones del plan recibido [PLAN-001](PLAN-001-feature-parity.md), preservando el trabajo Windows local.
- Alcance: Windows frontend, integración Tauri y pruebas. Apple es referencia de lectura y `core/` permanece protegido. No incluye publicación, push ni ensayos con cuenta real.
- Decisiones: conservar sidebar expandida 230/rail 60 y navegación Windows. NAV-01/02/03/05/06, FS-01/03 y NAT-05 se adaptan a esa decisión; no habilitan un cambio de producto automático. Seguimiento posterior a build-0005: [PLAN-004](PLAN-004-player-shell-corrections.md), FIX-137…139, mueve historial a TitleBar por pedido y corrige Genius/metadata/ambiente; no modifica la evidencia histórica de esta build.
- Referencias: [paridad](../../PARIDAD.md), [fixes](../../FIXES.md), planes Apple 009–014 y PORTEO-INICIO. Baseline: árbol local recibido (167 pruebas registradas en la recepción); comprobar de nuevo al integrar.

## Contratos contrastados con el código

1. Apple `Localization.swift` separa idioma de cuenta/proveedor; mensajes por clave/argumentos se resuelven al presentar. Windows debe reetiquetar sin reconstruir controladores ni cola.
2. Apple `ExploreCatalog.swift` define rutas, 16 géneros y ocho momentos con query estable independiente del idioma. Charts necesitan contrato regional, no un browse grid genérico.
3. Apple `DetailTrackProjection.swift` conserva índice original y ordinal/setVideoId al filtrar/ordenar. La proyección Windows debe reproducir la ocurrencia dentro de la fuente completa, no el subconjunto filtrado.
4. Windows ya tiene Inicio personalizado, configuración, cartas comunes, virtualización de estantes/listas, editor común y Space/artwork. Auditar diferencias nuevas en lugar de reemplazarlo.
5. La cola Rust Windows es autoritativa. Persistencia, carga progresiva, comandos multimedia y registro de historial deben respetar generaciones/entryId; la UI no mantiene una segunda cola.
6. `SearchResultsRecord` ofrece `top_songs`; se incorporó al DTO Windows. Genius se reutilizó del core mediante bridge, estado y presentación Windows propios.

## Puntos de ejecución y responsables

- [x] **A — Reproducción/nativo:** REP-01…12, NAT-01/03. Inspeccionar persistencia y audio Apple, ampliar Rust/DTO y controlador Windows; probar duplicados, suffix, cambios de cuenta, errores y comandos tardíos.
- [x] **B — Explorar/búsqueda:** EXP-01…09 y BUS-01…04. Catálogo, regiones, cachés/generaciones, vistas virtualizadas y mejores resultados; entregar contratos de conexión al integrador.
- [x] **C — Genius/idioma:** GEN-01…08 e IDI-01…06. Recursos ES/EN de origen, resolver reactivo y bridge/controller/panel Genius; ampliar traducción de superficies una vez coordinadas las escrituras.
- [x] **Integrador — Inicio/detalles/biblioteca/shell:** conciliar CAR/INI/NAV/DET/BIB/FS/NAT-02/04 con el destino local, implementar faltantes y conectar A/B/C sin escrituras concurrentes en archivos compartidos.
- [x] **Gestos:** GES-01…04: documentar límites reales de WebView2, implementar arbitraje conservador con cancelación y alternativa teclado. No afirmar fases de contacto inexistentes ni validación física.
- [x] **Revisión:** revisar diffs por agente, comunicar errores concretos y exigir corrección; probar riesgos observables por contrato, luego suite frontend/runtime.
- [x] **Cierre documental:** registrar FIX únicos, actualizar PAR y checklist de origen sólo con evidencia; mantener casillas físicas pendientes.

## Coordinación de archivos

El integrador posee `+page.svelte`, `src-tauri/src/lib.rs`, `types.ts`, registros FIX/PAR y planes. Los agentes entregan módulos propios y solicitudes precisas de registro/DTO; cambios compartidos se coordinan antes de escribir. No revertir trabajo inicial, ni crear commits.

## Comprobaciones de cierre

- [x] `pnpm check`, `pnpm test`, `pnpm build`.
- [x] `windows/scripts/windows.ps1 -Action verify`; pruebas Rust focales durante la integración.
- [x] Build standalone por skill/runner; ruta y estado reales registrados.
- [x] Revisión parcial de UI con fixtures: acciones, filtros, menús, foco, resize, datos vacíos/error, cambios de idioma y respuesta obsoleta.
- [x] Ensayos físicos pendientes explicitados: audio, trackpad, SMTC, DPI/Narrator, consumo y cuenta real. No cerrar QA-03…07 sin evidencia.

## Resultados

### Integración supervisada

Los tres subagentes retomaron sus módulos existentes; se revisaron contratos y se corrigieron errores de ocurrencia/índice, cachés obsoletas, identidad de Historial, rollback de chip, guardas de cuenta/playback y de resolución de uploads, sanitización durable de URLs, disponibilidad Next nativa, paginación Genius, foco invitado del menú y fallback de créditos. La revisión final de cobertura se encuentra en [matriz de aceptación](PLAN-003-coverage.md). Las casillas del plan original describen aceptación completa, no ausencia de código.

- [FIX-132](../../FIXES.md#fix-132): detalles/cabecera y alineación solicitada, listas/ocurrencias, Biblioteca/Historial, feed durable y suspensión bajo fullscreen.
- [FIX-133](../../FIXES.md#fix-133): Explorar/regiones/cachés, mejores resultados y gestos adaptados.
- [FIX-134](../../FIXES.md#fix-134): persistencia, inicio progresivo, Next/EOF, escuchas, uploads, radio/Dislike y SMTC.
- [FIX-135](../../FIXES.md#fix-135): Genius completo, ES/EN, comandos, información y updater.
- [FIX-136](../../FIXES.md#fix-136): runner Windows; aislamiento de artefactos core/Tauri tras comprobar una colisión de rlib sin hash entre workspaces con distintas features de serde. Runner completo aprobado y biblioteca Tauri conservada durante las suites core.

### Evidencia de UI

Fixture local temporal, sin cuenta/RPC: playlist de 1000 ocurrencias monta 22–23 filas; cabecera con acciones/orden/búsqueda alineados en ventana amplia y segunda fila sin solapar al reducirla. Tabla con índice angosto y canción flexible. Cambio de idioma conserva títulos/metadata externa. Catálogo Explorar de 5000 álbumes monta 16 cartas en ventana angosta. Son comprobaciones de geometría/DOM en navegador; no certifican FPS, consumo ni WebView2. La ruta temporal fue retirada antes de empaquetar.

### Verificación

- Frontend final: `pnpm check` 0 errores/0 advertencias; `pnpm test` 234/234 después de todas las correcciones, incluidos créditos, imágenes, menú de Likeados, foco invitado y capacidades de cola. `pnpm build` aprobado sin ruta de fixture.
- Primer runner: InnerTube 92, core 90 y core/windows-bridge 92 aprobadas; siete live ignoradas por variante, player 4 aprobadas. Tauri detectó colisión de caché antes de correr sus tests: se reparó el runner, no se atribuyó falsamente a Genius.
- Runner final `verify`: exit 0; InnerTube 92, core 90 y core/windows-bridge 92, player 4 y Tauri 71 aprobadas. Son **583 pruebas aprobadas** incluyendo frontend; 14 live ignoradas (siete por variante core). Se repitió correctamente dentro del protocolo de build.
- Aislamiento comprobado: SHA256 de `debug/deps/libsideb_core.rlib` antes/después del runner idéntico: `BC69C833132041032D87AB7ACBCB2319B2A6A8F63CE5D500D56ADE8D4CB935E7`.
- Recursos: `node windows/scripts/sync-localizations.mjs --check` verifica 688 claves compartidas. Protocolo `Scripts/build-version.test.mjs`: nueve aprobadas y una de empaquetado Mac omitida; no acredita build nativa Apple.
- Revisión final de diff sin errores de whitespace; Apple y core sin modificaciones de fuentes. Advertencias Rust de campos sin uso y del enlazador permanecen registradas; no se presenta el compilador nativo como libre de advertencias.

### Build conservada

`node Scripts/build-version.mjs windows` terminó con exit 0 el 2026-10-10, 06:56 America/Montevideo. Release standalone: `C:\Users\Stefa\Escritorio\SIDE B CODIGO PADREEEE\Side-B-main\builds\windows\build-0005\sideb-windows.exe`.

[BUILD.json](../../builds/windows/build-0005/BUILD.json): `status: compiled`, pasos verify/build aprobados y `sourceChangedDuringBuild: false`. SHA de fuentes durante compilación: `a994580c37c1b407b3d77bfdc1c98b9e42ecfedd575ae584ce05e6a99a1a8b80`. Los cuatro archivos conservados —EXE, libmpv, Vulkan y licencia— coinciden con sus hashes registrados. [Log completo](../../builds/windows/build-0005/build.log). Documentación de cierre actualizada después de compilar, sin nuevos cambios de código. Builds anteriores preservadas; no se abrió la app, publicó ni modificó la versión pública.

### Aceptación pendiente

Audio audible y latencia real, continuidad tras reiniciar con cuenta, uploads/radio/remoto, SMTC y teclas físicas, conexión regional y Genius reales, Precision touchpad/touch/pen, Narrator/DPI/foco/drag, consumo/FPS y actualización instalada. No se ejecutaron pruebas de cuenta real ni se cerraron QA-03…07. WebView2 no ofrece fases AppKit: Alt+wheel horizontal es entrada explícita y descenso touch/pen usa contacto real. El shell Windows 230/60 y sus Atrás/Adelante permanecen como decisión vigente.
