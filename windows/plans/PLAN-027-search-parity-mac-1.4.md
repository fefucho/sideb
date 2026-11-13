# PLAN-027 — Búsqueda: paridad con los cambios Mac de FIX-332, 333, 336 y 337

- Fecha: 2026-11-13 (America/Montevideo).
- Estado: **W1–W4 implementadas y probadas en Node/DOM (2026-11-13)**; falta captura/medición en navegador y toda validación nativa. Fixes [FIX-340](../../FIXES.md#fix-340), [FIX-341](../../FIXES.md#fix-341), [FIX-342](../../FIXES.md#fix-342).
- Objetivo: llevar a Windows el comportamiento que Mac ya tiene en la búsqueda: sin «Various artists» (PAR-060), buscador rápido denso con recientes que guardan lo abierto y resultados en vivo (PAR-058), y resultados por categorías (PAR-057).
- Ámbito: `windows/src` (Svelte/TypeScript). **Sin cambios en `core/`, Tauri ni DTO:** `SearchPageDto`, `SearchChipDto.params`, `search_page`, `search_suggestions_page` y `startRadio(song, onAcceptedGeneration)` ya existen. Frontend verificado con pruebas de Node, `pnpm check/test/build` y Chrome local; **nada de esto demuestra funcionamiento nativo Windows**.
- Referencias Mac (lectura): [FIX-332](../../FIXES.md#fix-332), [FIX-333](../../FIXES.md#fix-333), [FIX-336](../../FIXES.md#fix-336), [FIX-337](../../FIXES.md#fix-337), [Apple PLAN-036](../../apple/plans/PLAN-036-search-category-sections.md).

## Diagnóstico del estado de Windows (2026-11-13)

| Tema | Mac | Windows hoy | Consecuencia |
|---|---|---|---|
| Artista omitido bajo la tarjeta del artista | Hereda el artista del principal (FIX-337) | `projection.ts` (ruta vieja, `associatedSong`) ya lo hace; la ruta del proveedor `provider-rows.ts` no | Las filas relacionadas del principal salen sin artista. Los textos «Various artists» existen en el catálogo pero ningún componente los usa |
| Buscador rápido | Secciones, filas compactas, mejor resultado, grupos, completaciones al final, sin historial al escribir | `QuickResults.svelte` pinta la lista plana del endpoint de sugerencias, filas de 58 px y el historial propio mezclado al escribir | Mismo problema de legibilidad y de pocos resultados (el endpoint da ~3 elementos multimedia) |
| Resultados en vivo | `loadQuickPage` (búsqueda completa con espera y caché) | `ProviderPreviewController` solo llama `search_suggestions_page` | Hay que pedir además `search_page` sin historial |
| Recientes locales | Entidades + canciones, mostrados primero | `SearchRecentStore` (consultas y canciones) existe y tiene pruebas, pero **no se instancia en ninguna parte de la app**; solo se importa el tipo `SearchOrigin` | Es funcionalidad nueva en Windows: hay que cablear el almacén (cuenta, `startRadio`, confirmación de reproducción) además de ampliar entidades |
| Página de resultados | Secciones por categoría rellenadas por chip | `SearchView` pinta el documento del proveedor (principal, lista mixta, carruseles) | Hay que añadir proyección por categorías, relleno por chip y entradas de documento con altura constante |

## Reglas que se respetan

- Las consultas enviadas **no** se registran en recientes locales (decisión de PLAN-015, también en Mac): el historial remoto de YouTube Music es su fuente. El fixture compartido `scripts/fixtures/search-recents-behavior.json` no cambia de semántica.
- Los payloads por ocurrencia (`setVideoId`, IDs repetidos) se conservan: se usa el emparejamiento ordinal de `provider-rows.ts`.
- La petición en vivo del buscador rápido y el relleno por categorías se disparan desde la capa de UI/controllers de búsqueda, con generaciones que descartan respuestas obsoletas, y no registran historial.
- «Listen again» y cualquier estante con título que no sea una categoría conocida no se muestran en la vista por categorías.
- Cambio de cuenta invalida recientes, caché de búsqueda en vivo y relleno por categorías.

## Etapas

- [x] **W1 — Artista heredado (PAR-060).** `provider-rows.ts`: en una sección `top` con principal artista, las canciones sin artista ni `artistRuns` heredan nombre, id y enlace. Pruebas.
- [x] **W2 — Presentación del buscador rápido (PAR-058, parte 1 y FIX-336).** Módulo puro `quickPresentation.ts` (recientes/mejor resultado/búsquedas/grupos, límites, orden del teclado, historial descartado al escribir); `ProviderPreviewController` pide además `search_page` (250 ms, caché 60 s, sin historial, generaciones); `QuickResults.svelte` con secciones, filas de 40/32 px y ✕ al pasar el cursor. Pruebas de Node y navegador.
- [x] **W3 — Recientes que guardan lo abierto (PAR-058, parte 2).** `SearchRecentStore` acepta artistas, álbumes y playlists con su tarjeta (compatible con archivos anteriores); se instancia con `localStorage`, se asigna la cuenta, se registran los artistas/álbumes/playlists abiertos desde el buscador y los resultados, y las canciones por `startRadio(song, onAcceptedGeneration)` + confirmación de reproducción. «Borrar»/«Deshacer». Pruebas del almacén y del cableado.
- [x] **W4 — Resultados por categorías (PAR-057).** `categories.ts` (clasificación por `kind`, subtítulo y `isVideo`, orden de chips, relleno por chip con 3 peticiones como máximo y generaciones), entradas de documento `category-heading/carousel/grid/loading` con alturas constantes en `estimateSearchEntryHeight`, integración en `SearchView`/`SearchViewport`, preferencia `categoryView` (por defecto activada, sin UI como en Mac). Pruebas y fixture de navegador a 960/1100/1384 px.
- [ ] **W5 — Cierre.** Hecho: `svelte-check` 0 errores, 660/663 pruebas (3 omitidas), `vite build`, FIXES y PARIDAD. Pendiente: captura con Chrome (la fixture `plan016-browser.mjs` se cerró sola) y validación nativa. Original: `pnpm check`, `pnpm test`, `pnpm build`; captura con Chrome; FIXES `[Windows]`, PARIDAD (PAR-057/058/060 pasan a «Implementado / validación nativa pendiente»), este plan.

## Fuera de alcance

- FIX-331 (filas desplazadas al cambiar el ancho): es exclusivo de `NSTableView`. `SearchViewport.svelte` mide y reposiciona por geometría propia; se comprobará con la fixture de W4, sin asumir el mismo fallo.
- Ajuste visible en Configuración para volver a la lista del proveedor (tampoco existe en Mac).
- Windows nativo (WebView2, audio): sigue sin validar.
