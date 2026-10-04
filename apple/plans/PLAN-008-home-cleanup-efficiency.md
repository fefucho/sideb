# PLAN-008: limpieza y eficiencia de Inicio (revisión de código)

- Fecha: 2026-10-04 (America/Montevideo). Revisado y ampliado con verificación por `grep` el mismo día.
- Estado: **propuesto, sin implementar**. Cinco etapas independientes; cada una cabe en una sesión corta y se puede entregar sola.
- Destinatario: otro agente (GPT/Gemini) que integre el plan sin haber visto la conversación. Este documento contiene el contexto necesario.
- Reglas: no cambiar Rust/UniFFI ni Windows; no cambiar comportamiento visible salvo donde se indique; tests existentes en verde; un FIX por etapa (consultar el siguiente libre en FIXES.md al ejecutar; no reservar IDs en el plan) con campo Paridad; no hacer commit sin que el usuario lo pida.

## Contexto mínimo

- App macOS en `apple/Sources/SideB/` (SwiftUI + AppKit). Inicio personalizado: Speed Dial, destacados (álbumes/playlists), panel de configuración, fondo de portadas con humo animado. Referencias: [FIX-098](../../FIXES.md#fix-098) a [FIX-109](../../FIXES.md#fix-109), [PLAN-007](PLAN-007-home-recommendation-sources.md), [PORTEO-INICIO.md](../../PORTEO-INICIO.md).
- Comandos: pruebas focales `swift test --package-path apple --filter Home`; build numerada completa `node Scripts/build-version.mjs macos` (corre Rust + XCTest + Swift Testing; solo al final de una etapa que cambie comportamiento). Estado de partida: 180 Rust (7 live ignorados), 47 XCTest, 177 Swift Testing / 5 suites.
- Hay cambios locales sin commit de otros trabajos en el árbol; **no revertirlos ni mezclar** con este plan.

## Hallazgos verificados

| # | Hallazgo | Evidencia | Etapa |
|---|---|---|---|
| H1 | Títulos de categoría copiados en 3 sitios con normalización distinta | `HomeRecommendationSettings.aliases` + `normalize` (ignora mayúsculas y tildes); `HomeFeaturedPresentation.priority(_:kind:)` (idem); `HomeFeedPresentation.sectionPriority/style/normalized` (solo `lowercased()`) | 1 |
| H2 | `sectionPriority` no reconoce «recommended albums», «álbumes recomendados» ni los alias de mixes, que `priority` y `aliases` sí; en modo `sideB` esas categorías caen en prioridad 6 | comparar listas en `HomeFeedPresentation.swift` líneas ~98–107 contra `HomeFeaturedPresentation.swift` líneas ~140–152. **Puede ser intencional**: confirmar con el usuario antes de cambiar el orden visible | 1 |
| H3 | `categoryKey(forTitle:)` (folding + diccionario) se llama dentro de comparadores de `sorted` y en filtros, además de `HomeViewModel.hasReceivedEnabledSources` con literales en inglés | `HomeRecommendationSettings.swift` ~107–123; `HomeFeaturedPresentation.swift` ~59, ~114; `HomeViewModel.swift` ~110–112, ~453–462 | 2 |
| H4 | `HomeFeedCollectionView` (struct de 570 líneas, líneas 6–577) **no se usa en producción**: solo la instancia `HomeFeedCollectionView(` en `Tests/SideBTests/HomeViewModelTests.swift:413`. La vista activa es `HomeFeedTableView` (`HomeView.swift:50`). El resto del archivo (`HomeNativeCollectionView`, `HomeCollectionItem`, `HomeSectionHeaderView`, `HomeInteractiveLinkButton`, `HomePlayHitButton`, `HomeItemView`, líneas 578–1477) **sí se comparte**: lo usan `HomeFeedTableView`/`HomeShelfRowView` y 4 archivos de pruebas | `grep` | 3 |
| H5 | `HomeBenchmarkFixture` y `HomeLabConfiguration` **no son código de prueba suelto**: se activan por *bundle identifier* (`com.fefucho.SideB.HomeLab…`) y aíslan Keychain, caché de imágenes, Application Support y preferencias. No son un riesgo en la build normal. Solo `HomeViewModel.swift:378` bifurca por `usesFixture` | `HomeLabConfiguration.swift`, usos en `CookieStorage`, `ImageCache`, `PlaybackStateStore`, `AudioPlayerService` | 3 (solo documentar) |
| H6 | `HomeFeaturedPresentation.==` ignora `collectionSources` (a propósito, para no republicar la vista) sin comentario que lo explique | `HomeFeaturedPresentation.swift:12–15` | 3 |
| H7 | Fondo animado: `TimelineView` a 30 fps reconstruye `GeometryReader` + degradados cada cuadro; varias capas grandes con `blendMode(.screen)` en movimiento; `.transition(.opacity)` sin efecto en `smokeLayer`; constantes de animación sueltas por la vista | `HomeAmbientSurface.swift` | 4 |
| H8 | «Cargar más» y la precarga están acotados (3 peticiones, set de tokens usados, firma de sección): **sin hallazgos**, no tocar | `HomeViewModel.swift` ~296–335 | — |

## Etapa 1 — Una sola fuente de verdad para las categorías (H1, H2) · riesgo bajo

Objetivo: que clasificar un título de categoría se haga en un único lugar (`HomeRecommendationSettings.categoryKey`) y que el resto compare claves.

- [ ] **Paso 0 (prueba de caracterización, antes de tocar nada)**: crear en `Tests/SideBTests/` una prueba que, para cada alias de `aliases` (con tildes, sin tildes, MAYÚSCULAS y con espacios), registre qué devuelven hoy `categoryKey`, `HomeFeaturedPresentation.priority` (vía `make` con una sección de ese título, o hacer `priority` `internal`), `HomeFeedPresentation.sectionPriority` y `style`. Guardar el resultado actual como esperado **tal cual está hoy** (incluida H2). Debe pasar con el código actual.
- [ ] **Paso 1 (decisión)**: si la prueba confirma H2, preguntar al usuario si «Álbumes recomendados» y los mixes deben ordenarse como «Álbumes para ti» en modo `sideB`. Si no responde, **conservar el comportamiento actual** y dejarlo anotado como límite.
- [ ] **Paso 2**: reemplazar las listas por comparaciones con claves: `"listen-again"`→0, `"forgotten-favorites"`→1, `"recommended-albums"`→2, `"from-library"`→3, `"quick-picks"`→5, resto→6 (feed), y `priority` de destacados 0/1/2/3/4 según tipo. Añadir un helper interno único (`HomeCategoryFamily` o extensión de `HomeRecommendationSettings`) para no repetir `categoryKey(forTitle:)` con literales; usarlo también en `HomeViewModel.hasReceivedEnabledSources` en lugar de los literales «Albums for you», «Mixed for you», etc.
- [ ] **Paso 3**: la prueba del paso 0 debe seguir pasando (o cambiar solo donde el usuario aprobó). Correr `--filter Home`.
- [ ] Hecho cuando: ninguna lista de títulos de categoría fuera de `aliases`; `grep -n "listen again" apple/Sources` solo aparece en `HomeRecommendationSettings.swift`.
- Registrar FIX-110. Paridad: Windows debe tener una sola función de clave (anotar en PAR-003/PAR-006 y en [PORTEO-INICIO.md](../../PORTEO-INICIO.md) §3 y §4).

## Etapa 2 — Claves una sola vez y proyección sin trabajo repetido (H3) · riesgo bajo

- [ ] En `orderedFeedRecords`, `visibleFeedRecords`, `orderedShelfSections` y el filtro de `HomeFeaturedPresentation.make`: calcular la clave **una vez por elemento** (`map { (key, element) }`) antes de ordenar o filtrar. Mantener el desempate por posición original (orden estable).
- [ ] Opcional: caché pequeña título→clave (diccionario estático con límite) si el perfil lo justifica; no añadirla “por si acaso”.
- [ ] `HomeViewModel.rebuildProjection` se llama desde 7 sitios (líneas ~70, 90, 97, 141, 356 y los que usan `apply`). Verificar que ninguno la dispara dos veces seguidas para el mismo cambio (p. ej. `setRecommendationSettings` + `apply`). No tocar `selectionRevision/contentRevision` ni la comparación `projected != featured`.
- [ ] Prueba nueva: ≥ 200 categorías en modos `sideB`, `youtube` y `custom` con orden idéntico antes/después del cambio (comparar con el resultado de la implementación anterior en la misma prueba o con un orden esperado fijo).
- Hecho cuando: pruebas `Home*` en verde y ninguna llamada a `categoryKey` dentro de un cierre de `sorted`/`filter`.

## Etapa 3 — Limpieza de vistas y documentación de lo intencional (H4, H5, H6) · riesgo medio

- [ ] **Mover** a archivos nuevos las clases compartidas de `HomeFeedCollectionView.swift` (líneas 578–1477): p. ej. `HomeFeedItemViews.swift` para `HomeItemView`, `HomePlayHitButton`, `HomeInteractiveLinkButton`, `HomeSectionHeaderView`, `HomeCollectionItem`, `HomeNativeCollectionView`. Mover sin editar el contenido; compilar; pruebas `HomeItemHierarchyTests`, `HomeFeedReuseTests`, `HomeFeedScrollTests` en verde.
- [ ] **Migrar** la única prueba que instancia `HomeFeedCollectionView` (`HomeViewModelTests.swift:413`) a `HomeFeedTableView` o eliminarla si prueba solo ese struct, justificándolo en el FIX.
- [ ] **Eliminar** el struct `HomeFeedCollectionView` (líneas 6–577) solo si lo anterior está en verde. Si algo en esa vista era el único que cubría un caso (reciclaje FIX-101/102/103), **no borrar**: anotar el hallazgo en esta sección.
- [ ] Comentar `==` de `HomeFeaturedPresentation` (por qué `collectionSources` no participa).
- [ ] Añadir en `HomeLabConfiguration.swift` un comentario breve de que se activa por bundle ID y aísla almacenamiento (H5); no mover ni borrar nada.
- Guardarraíl: no tocar la medición/reciclaje de FIX-101/102/103 ni la geometría de FIX-100. Esta etapa es de organización; si un cambio altera layout o gestos, revertir y anotar.
- Hecho cuando: build numerada con todas las pruebas, y `grep -rn "HomeFeedCollectionView\b" apple` sin resultados en `Sources`.

## Etapa 4 — Medir y decidir sobre el fondo animado (H7) · riesgo bajo

- [ ] **Medir primero** con Instruments (Time Profiler y Core Animation) en la misma Mac, build release, Inicio abierto 60 s, sin interacción: build-0027 (humo estático) vs build-0029 o posterior (animado), y con la ventana en segundo plano. Anotar CPU/GPU medios y picos.
- [ ] Criterio de decisión: si el aumento es bajo y estable, **solo** retirar `.transition(.opacity)` de `smokeLayer` y agrupar las constantes (abajo). Si es alto, probar en este orden, midiendo tras cada paso: (1) 20 fps; (2) `drawingGroup()` sobre el `ZStack` de capas; (3) `Canvas` para radiales y humo; (4) quitar `blendMode(.screen)` de las nubes; (5) `MeshGradient`/Metal (mínimo del proyecto: macOS 15).
- [ ] Extraer las constantes de animación (periodos, amplitudes, escalas, opacidades; ver [PORTEO-INICIO.md](../../PORTEO-INICIO.md) §6) a un `struct HomeAmbientMotion` interno; sin cambiar valores. Mantener pausa por `scenePhase` y Reduce Motion.
- [ ] Registrar los números en FIX-109 (hoy dice «medición pendiente») y, si cambian valores, actualizar PORTEO-INICIO §6.
- Hecho cuando: hay una medición registrada y el fondo no empeora el consumo respecto del criterio acordado con el usuario.

## Etapa 5 — Documentación

- [ ] Actualizar [PORTEO-INICIO.md](../../PORTEO-INICIO.md) si cambia la función de clave (etapa 1) o los valores del fondo (etapa 4).
- [ ] Actualizar [PARIDAD.md](../../PARIDAD.md) (PAR-003/006) y el índice [README](README.md) con el estado final de este plan.

## Orden y costo

| Etapa | Riesgo | Costo estimado | Depende de |
|---|---|---|---|
| 1 | bajo | medio (pruebas de caracterización) | — |
| 2 | bajo | bajo | 1 (comparten helper) |
| 3 | medio | medio (mover código y compilar) | — |
| 4 | bajo | medio (requiere medir a mano) | — |
| 5 | nulo | bajo | 1, 4 |

Si hay que elegir solo una: **etapa 1**. Si la cuota es muy corta: etapa 2 sin la etapa 1 es posible, pero conviene hacerlas juntas.

## Hallazgos nuevos

Añadir aquí, con fecha, lo que aparezca durante la ejecución (síntoma, archivo/línea, evidencia, etapa):

- 2026-10-04: sin hallazgos adicionales tras verificar H1–H8.

## Fuera de alcance

Core Rust/UniFFI, Windows, rediseño de la capa de shell (FIX-091 a FIX-095), nuevas funciones de Inicio, optimizaciones sin medición, commits/push/publicación.
