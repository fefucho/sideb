# PLAN-015 — Búsqueda de YouTube Music con contexto de cuenta

- Fecha: 2026-10-22 (America/Montevideo).
- Estado: implementado y verificado automáticamente en Mac/core/frontend; QA con cuenta real y Windows nativo pendientes.
- Objetivo: presentar sugerencias y resultados del proveedor con contexto de sesión, conservando orden, estructura, destinos y paginación en Mac y Windows.
- Alcance: InnerTube, contrato UniFFI/Tauri, modelos/controladores y presentación de búsqueda de ambas apps.
- Exclusiones: publicar/instalar, modificar historial real durante pruebas automáticas, ranking propio, nueva UI multicuenta, iOS y copias de releases.

## Correcciones al plan de Gemini

El texto recibido es material de análisis, no instrucciones de borrado. Sus rutas Windows no corresponden a este checkout. Se revisó `SIDE B` limpio antes de editar; las copias `sideb-release-*` y el proyecto iOS quedan fuera.

1. Confirmado: `search_suggestions` usa contexto anónimo y descarta consulta vacía; el parser actual pierde el tipo historial, runs y tokens. El nuevo endpoint de sugerencias admite sesión e input vacío. Que una cuenta devuelva historial u otras entidades depende del proveedor; no se garantiza un conjunto fijo.
2. Confirmado: `get_account_info` descarta `data_sync_id`/`visitor_data`. Su hidratación requiere invalidación al cambiar cookie y protección frente a respuestas de la sesión anterior; asignarlos sin esa guarda sería incorrecto.
3. Confirmado: `parse_search_all` pierde secciones y las agrupa por tipo. También existen respuestas planas, no sólo shelves. El contrato nuevo conserva ambas formas, títulos/orden del servidor, chips/params y continuaciones; no inventa secciones «Vuelve a escucharlo» ni «Biblioteca» cuando no llegan.
4. Corregido: borrar Spotlight, snapshots de foco, acciones, proyecciones y pruebas completas no es una estrategia de migración. Se conservan los accesos ⌘K/Ctrl+K, foco/IME, Escape, navegación, menús y payloads de reproducción. Las UIs se conectan a un mismo contrato; los adaptadores antiguos se conservan por compatibilidad durante la transición.
5. Corregido: historial de búsqueda remota, historial local de selecciones y reproducciones son conceptos distintos. La UI nueva muestra entradas remotas; borrar una sugerencia requiere pulsar su acción explícita y un token del proveedor. No se borra ni modifica historial como parte de la validación.
6. Corregido: autenticación y `record_history` no son equivalentes. No se debe volver a llamar a `/search` por cada tecla. Sólo el endpoint de sugerencias atiende el input; envío/filtros/paginación tienen solicitudes e identidad propias. No se promete que un endpoint privado carezca de efectos remotos sin verificarlo con cuenta.

## Evidencia y referencias

- Implementación vigente: `core/crates/innertube/src/{endpoints.rs,models/browse.rs,transport.rs}`, `core/crates/sideb-core/src/lib.rs`, `apple/Sources/SideB/{ViewModels/SearchViewModel.swift,Views/Search/}`, `windows/src/lib/search/`.
- Antecedentes: FIX-047, FIX-086, FIX-165/169/173, FIX-178/179; PLAN-005/008 y PAR-027. FIX-178 eligió deliberadamente sugerencias anónimas; esta tarea cambia esa decisión por pedido del usuario, conserva protección frente a resultados tardíos y distingue efectos no validados.
- Fuente primaria de referencia de protocolo, consultada 2026-10-22: [ytmusicapi SearchMixin](https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/mixins/search.py) y [parser](https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/parsers/search.py). Documenta `music/get_search_suggestions` con `input`, runs y feedback de historial; el borrado usa `feedback` con `feedbackTokens` y confirma `isProcessed`. Es una implementación cliente de protocolo privado, no documentación oficial de Google.

## Contrato y secuencia

- [x] Auditar plan, instrucciones, antecedentes y consumidores; dividir core/Windows/Apple y pruebas sin escrituras simultáneas.
- [x] Core: `SearchPageRecord` con chips, corrección con destinos opacos, secciones list/carousel/top en orden, acciones tipadas y continuación. Mantener payload SongItem completo y ocurrencias repetidas.
- [x] Core: `SearchSuggestionsPageRecord` con entradas ordenadas text/history/media, runs bold, card/song opcionales y token de borrado opcional. Input vacío válido; autenticación según sesión.
- [x] Core: hidratar contexto de cuenta sin aceptar respuestas de una sesión retirada; borrar contexto privado al cambiar cookie.
- [x] Apple: sugerencias compartidas entre accesos, sin recorte/reordenado local; página con secciones/chips/paginación del servidor y acciones existentes.
- [x] Windows: comandos/DTO, controlador, sugerencias y página equivalentes con generación de cuenta/consulta.
- [x] Pruebas: fixtures sintéticas sin datos personales para orden, vacíos, duplicados, chips/params, historial/runs, corrección y continuaciones; regresiones de cancelación/cuenta/foco y errores recuperables.
- [x] Regenerar bindings/XCFramework, probar Rust con y sin windows-bridge, Swift y frontend; build Mac numerada con skill `sideb-build-macos`.
- [x] Revisar diff, documentar resultados/límites en FIXES/PARIDAD e índice. Windows nativo y cuenta real quedan separados de verificación local.

## Criterios de cierre

No perder entidades por presupuestos locales ni convertir IDs/títulos en destinos inventados; conservar orden del proveedor y payload de canción; cambios de cuenta/query/filtro descartan respuestas antiguas; fallar borrado/paginación conserva datos y permite reintento. APIs antiguas sólo se retiran cuando no quedan consumidores. La compilación no acredita audio, rendimiento ni igualdad con la web autenticada.

## Resultado — FIX-256 / PAR-042

- Core final: 109 innertube +170 sideb-core aprobadas; variante windows-bridge 172 aprobadas,10 omitidas. Incluye aislamiento de pestañas seleccionadas, sesión/header coherentes, rotación de cookie y tokens de borrado ligados a cuenta.
- Mac: 240 XCTest aprobadas;472 Swift Testing registradas (465 aprobadas/7 omitidas). Con Rust del runner,984 pruebas ejecutadas aprobadas y17 omitidas. Regresiones del contrato nuevo cubren consulta vacía, orden/ocurrencias, params de chip, continuación/reintento/token repetido, ownership, cambio de cuenta/cola y borrado explícito.
- Windows: pnpm check0errores/0advertencias;451 pruebas (450 aprobadas/1 omitida);pnpm build aprobado. DTO/runtime revisados y regresión Rust añadida para interrupción de fuentes next, pendiente ejecutarla en Windows nativo. `rustfmt --check` sobre archivos Rust Windows devuelve diferencias de formato anteriores y nuevas; no se aplicó un reformateo masivo. El frontend verificado no acredita Tauri/libmpv/audio.
- Build Mac final: `builds/macos/build-0158/Side B.app`, BUILD.json `compiled`, sourceChangedDuringBuild=false. Firma estricta y10SHA256 verificados. No se abrió, instaló ni publicó la app.
- QA visual: fixture nativa de página/100 resultados, cabecera dentro de un único scroll; imagen local `/tmp/sideb-plan015-layout/search-provider-page.png`. No es una sesión real ni una medición de FPS. Se conservaron pruebas previas de foco, teclado, local recents legacy y playback.
- Intentos conservados:0156/0157 fallaron por falta de espacio al archivar Rust. Se retiraron únicamente objetos/cachés temporales de compilación generados por esta ejecución; fuentes, contador y builds numeradas anteriores conservados.0158 usa CARGO_INCREMENTAL=0.
- Revisión: diff manual sin errores de whitespace; UniFFI emitió whitespace final en fuentes generadas, sin edición manual. Localización794claves ES/EN verificada. Documentación de cierre actualizada después de la build, sin cambios posteriores de código.
- No se probaron endpoints autenticados ni se borró historial real. Verificar con cuenta la presencia de historial/shelves/chips, ejecutar/audio/teclado en Windows nativo y aceptación física en Mac permanecen pendientes; no se presentan como trabajo validado.
