# PLAN-029 — Indicadores de versión en Mac

- Fecha: 2026-10-27 (America/Montevideo).
- Objetivo: identificar el contenido de la versión seleccionada o activa sin cambiar IDs, audio, ranking ni elecciones manuales.
- Estado: FIX-263 y ajuste posterior [FIX-265](../../FIXES.md#fix-265) implementados en fuentes: E proporcional en metadata; la canción activa fullscreen ahora excluye también el indicador de sus créditos por pedido2026-10-28. Barra inferior, cola y Relacionado conservan indicador. Swift/SDK/AppKit no disponibles en Windows: compilación/suite/QA Mac pendientes; la build Windows0024 no valida Mac.
- Referencias: [PLAN-013 común](../../plans/PLAN-013-explicit-content-indicators.md), [plan Windows espejo](../../windows/plans/PLAN-021-explicit-content-indicators.md), [FIX-262](../../FIXES.md#fix-262), [FIX-263](../../FIXES.md#fix-263), [PAR-040](../../PARIDAD.md).
- Alcance: interfaz Mac, DTOs UniFFI generados desde el core común, proyecciones y snapshots locales. Sin selección automática de versiones (PLAN-014), recursos de audio ni herencia de rating desde el arte.

## Contrato común con Windows

`explicit`, `clean` y `unknown` califican el ID exacto de canción o edición. Badge E sólo para explícito confirmado; L en español/C en inglés sólo para limpieza confirmada. Ausencia de badge, dato viejo o respuesta incompleta quedan desconocidos. El parser actual de YouTube aporta E o desconocido; no se inventa una versión limpia. Al hidratar el mismo ID sólo se enriquece un desconocido; evidencia conocida se conserva incluso ante un conflicto, que no autoriza cambiar audio. No se traslada el estado del encabezado del álbum a sus canciones.

Presentación inicial (la revisión pendiente la reemplaza): chip de 14×14 puntos, radio3, blanco78%, glifo #1c1c1e, path E con tinta x4…10/y3…11 centrada en7,7. El mismo path y colores se usan en Windows. El dibujo evita métricas de baseline. Desconocido no ocupa hueco visible en las filas; tooltip del título y ayuda accesible describen la falta de información en reproducción.

## Implementación

- [x] Componente nativo/SwiftUI único, geometría centrada y etiqueta accesible/localizada; reset al reutilizar celda.
- [x] Home, resultados de búsqueda rápida/completa, tarjetas de catálogo/artista, álbum y otras versiones, biblioteca/Explore, filas, cola, barra y fullscreen.
- [x] Preservar rating en conversiones Home/Browse→canción y Browse→Home; pistas históricas no califican su álbum.
- [x] Mantener metadata conocida al hidratar mismo ID por radio/detalle de álbum y actualizar ocurrencia actual con guardas de token/ID.
- [x] Persistir mediante strings estables en caché Home, sesiones, búsqueda reciente y pins. Campos faltantes/futuros son unknown; Home legacy true sigue explicit y false no implica clean.
- [x] Añadir fuente editorial compartida ES/EN; regeneración portátil y comprobación de recursos coordinadas por integrador.
- [x] Regenerar bindings con UniFFI real desde DLL del core sin feature windows-bridge, con postprocesado oficial. No se editaron contratos generados a mano.
- [x] Revisar diff y constructores contra firmas regeneradas. Los bindings anteriores también omitían contratos actuales del buscador; la regeneración incorpora esas APIs vigentes.
- [ ] En Mac, regenerar XCFramework del core actual y ejecutar `swift test --package-path apple`, incluidas `ContentRatingTests`.
- [ ] Compilar con runner oficial y verificar Home/búsqueda/álbum/cola/NowPlaying, reutilización, ES/EN, VoiceOver, escalado y centrado visual en Mac real.
- [ ] Confirmar manualmente que escoger edición censurada conserva esa edición y que pista activa/etiqueta corresponden al mismo ID. No se certifica audio audible por pruebas de metadata.

## Comprobaciones y límites

`ContentRatingTests.swift` añade regresiones de snapshots antiguos/nuevos, equivalencia por identidad exacta, independencia álbum/pista y badge reutilizado. Se añadieron desde Windows; no ejecutadas aquí por falta de Swift/AppKit/SDK de macOS. La revisión de fuentes y la generación UniFFI no equivalen a compilación Mac ni a QA visual. El XCFramework anterior no valida el contrato nuevo: debe regenerarse antes de compilar. FIX-262/PAR-040 conservan estos pendientes.

## Revisión visual — segunda línea y fullscreen, implementada en fuentes

La revisión de [PLAN-013](../../plans/PLAN-013-explicit-content-indicators.md) se implementa en ambos shells: E al principio de artista/álbum (o de la línea secundaria que contiene tipo y créditos), títulos libres, tamaño `clamp(round(fontSize×0,85),9,12)`, gap4, path14×14 y radio proporcional3/14. El título genérico no inserta badges. En fullscreen la canción activa muestra el indicador sólo junto a sus créditos; cola y Relacionado siguen usando la misma presentación secundaria. La barra inferior usa font11,5→lado10. No se modifica el rating, audio ni edición elegida.

- [x] Trasladar badges desde título/cabecera a metadata secundaria; conservar enlaces, acciones y límites de filas. Cabeceras y cards sin créditos mantienen el indicador confirmado en su espacio secundario.
- [x] Reducir y escalar glifo/fondo según el texto secundario. Home y Biblioteca calculan frames y reservas con lado real+gap4, sin desplazamientos fijos14/20; Home resetea rating al reciclar.
- [x] Quitar badge del título genérico y del título grande fullscreen; conservarlo junto a metadata activa y en cola/Relacionado, sin cambiar metadata.
- [x] Conservar badge en segunda línea de barra inferior; integración respeta cambios concurrentes de marquee y reparto de ancho de PLAN-030.
- [x] Añadir regresiones Swift de geometría9…12/radio/centrado, créditos secundarios, ausencia y reciclado. Adaptar pruebas existentes de cola/colección a coordenadas del contenedor sin perder validaciones de límites/acciones.
- [x] Revisar fuentes:15 vistas con balance de delimitadores, sin wrappers de título con badge, y siete muestras de geometría aprobadas mediante script Python de sólo lectura. No equivale a parseo/compilación Swift.
- [ ] Ejecutar `ContentRatingTests`, `NativeQueueTrackCellTests`, `CollectionTrackTableTests` y suite Swift en Mac; **no ejecutadas**, por pedido de no compilar.
- [ ] Verificar manualmente título grande sin E, metadata con una sola E, cola/Relacionado con E, barra con E, unknown y transición normal→fullscreen→normal con mismo ID/rating.
- [ ] Revisar capturas Mac/Windows, escalado, truncado, alturas y VoiceOver en Mac real. No atribuir a esta revisión pruebas de FIX-262.

Archivos: `ContentRatingBadge.swift`, `FeaturedTrackTitle.swift`, `PlayerBarView.swift`, `FullscreenNowPlayingView.swift`, filas nativas, Home/Biblioteca, búsqueda, catálogo/artista, cabecera y Relacionado; `ContentRatingTests.swift`, `NativeQueueTrackCellTests.swift`, `CollectionTrackTableTests.swift`.

FIX-263 enlaza FIX-262/PAR-040. Se mantienen pendientes el XCFramework y QA nativa de la entrega inicial; no se regeneraron bindings ni se creó build durante esta revisión.
