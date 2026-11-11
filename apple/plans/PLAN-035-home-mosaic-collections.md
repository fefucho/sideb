# PLAN-035: Inicio con mosaico de Acceso rápido y tarjetas grandes de colecciones

- Objetivo: trasladar a Mac el Inicio destacado de Windows (PAR-054): el mosaico de canciones reemplaza al riel de Acceso rápido y las tarjetas grandes con panel de texto reemplazan al riel de álbumes/playlists.
- Estado: implementado y revisado el 2026-11-11 ([FIX-328](../../FIXES.md#fix-328), PAR-054); 352 XCTest + 647 Swift Testing aprobadas y renders fuera de pantalla revisados. Falta la validación del usuario en la app. Línea base `builds/macos/build-0223` sobre `main` ab25883; build de prueba `builds/macos/build-0226`.
- Decisión del usuario (2026-11-11): en Mac el mosaico reemplaza al riel de canciones y las tarjetas grandes al riel de colecciones, igual que en Windows. Se conserva «Ver todo».
- Alcance: presentación de los destacados de Inicio en `apple/`. Sin cambios en `core/` ni en `windows/` (sólo lectura), ni en qué canciones o colecciones se eligen, ni en la reproducción.
- Exclusiones: estantes del feed, ambiente de Inicio, hoja «Ver todo» (conserva su tarjeta actual), FIX-324/325/326 y las correcciones propias de Windows.

## Referencias

- Windows, código (la referencia es el código, no una descripción): `windows/src/lib/home/{mosaic,coverColor,featured,metadata}.ts`, `windows/src/lib/components/home/{HomeMosaic,HomeCollectionRow,HomeView}.svelte`, `windows/src/lib/components/common/{MediaCard,MediaArtwork,HorizontalNavigation}.svelte`.
- Windows, registro: [FIX-320](../../FIXES.md#fix-320), [FIX-321](../../FIXES.md#fix-321) (reemplaza la píldora y las sombras de color de FIX-320), [FIX-322](../../FIXES.md#fix-322) (dos defectos de integración), [PLAN-026 Windows](../../windows/plans/PLAN-026-home-mosaic-albums.md).
- Mac, punto de partida (rieles de la 1.4.0, PAR-051, FIX-285/286/296/299): `HomeFeaturedView.swift`, `HomeFeaturedNativeRail.swift`, `HomeFeaturedPresentation.swift`, `HomeViewModel.swift`, `HomeItemView` en `HomeFeedCollectionView.swift`, `HomeAlbumMetadata.swift`, `HomePlaylistMetadata.swift`, `HomeFeedTableView.swift` (viewport hospedado), [PLAN-034](PLAN-034-home-continuous-cards.md).

## Qué tiene que quedar igual que en Windows

Canciones:

- Tres filas, celda 144, separación 8 (paso 152), alto 448, scroll horizontal. Tamaños: chica 1×1, apaisada 2×1, grande 2×2.
- Disposición por bloques T/B/W/S con FNV-1a sobre los IDs (unidades UTF-16 unidas por U+001F) y mulberry32: misma lista, mismo dibujo, idéntico al de Windows. Se comprueba con vectores generados ejecutando `mosaic.ts`.
- Título y artista directo sobre la portada, sobre un degradado inferior (72 % del alto; 52 % en las grandes) teñido con el color de la carátula al 30 % sobre `#0b0b0f`, con paradas 94/80/48/14/0 % en 0/20/42/66/100 %. Sin píldora, sin sombras ni brillos de color.
- Tipografía: 13/16 semibold, 16/20 bold y 22/27 bold; artista 11.5/12.5/14 al 72 % de blanco. Márgenes 10/12/16 y base 9/11/14.
- Hover o foco de teclado: zoom de la portada al 104 % dentro de su marco, 250 ms. Sin elevación.
- Play: círculo blanco con icono oscuro abajo a la derecha (30/32/40; separación 8/10/14); siempre visible en las grandes. El texto reserva `play + 14` a la derecha cuando Play se ve.
- Canción que suena: ecualizador de tres barras a la izquierda del título, en su renglón, sin ocultarse con hover; en pausa, quietas al 50 %. Sin contorno ni aura.
- Título largo: se desvanece en los últimos 18 pt en lugar de cortarse.

Colecciones:

- Fila horizontal; `útil = ancho − 56`, `n = límite(⌊(útil + 24) / 224⌋, 2, 5)`, se suman tarjetas mientras el ancho supere 320; ancho = `(útil − 24·(n−1)) / n`. Separación 24, encaje al inicio de tarjeta.
- Tarjeta vertical, radio 14, sombra de reposo `0 12 30 −16` negra, portada cuadrada y panel claro con padding 12/14/14: etiqueta 10/14 bold con tracking 1.2, título 17/22 bold, artista 14/19 medium, resumen 12/16 a 6 pt, hasta dos líneas.
- Acabado «Blanco»: panel `#f5f5f7`, título `#1d1d1f`, artista `#3a3a3c`, etiqueta y resumen `#6e6e73`. «Blanco teñido» (por defecto): portada espejada y desenfocada (26, saturación 1.5) bajo un velo blanco al 78 %; artista negro 79 %, etiqueta y resumen negro 58 %. Sin imagen se ve como «Blanco».
- Preferencia de instalación en Configuración → Apariencia, «Tarjetas de álbumes»: «Blanco teñido» / «Blanco».
- Hover: sube 4 pt con sombra negra neutra `0 20 34 −18` al 80 %, portada atenuada 30 %, y Play (abajo izquierda) y menú (abajo derecha) en círculos de vidrio de 38 a 12 pt del borde. Con Reduce Transparency, círculos opacos `negro 60 %`. Con Reduce Motion, sin transiciones.
- Los detalles de toda la fila se piden de una vez, con las visibles primero; dos solicitudes simultáneas; límite de caché 48.

Defectos de Windows que no se repiten:

- Recalcular la fila con ancho ≤ 0 mientras Inicio está tapado: se ignora la medida y se conserva la última real, con su ancla.
- Medir o publicar desde un contenedor ya desmontado: toda devolución diferida comprueba que el carril siga vivo.

## Contratos de Mac que no cambian

- Abrir álbum, playlist y artista; reproducir canción y colección; menú contextual por clic derecho, botón y teclado; estado activo, pausado y cargando.
- Retención de posición horizontal al volver a Inicio y ancla por ID al cambiar la lista o el ancho.
- Reproductor lateral abierto: los carriles llegan al borde (`trailingInset` 0).
- Suspensión de celdas con Inicio tapado o fullscreen, VoiceOver (etiquetas y orden), Reduce Motion y Reduce Transparency.
- Proyección: mismas fuentes, prioridad, deduplicado, 27 canciones y capacidad fija de 6 (36 colecciones), que en Mac no depende del ancho.

## Decisiones tomadas por defecto (a confirmar por el usuario)

- Títulos de sección con la tipografía actual de Mac (22 bold) en lugar de los 19 px de Windows.
- Flechas de Mac conservadas; los fundidos laterales de los rieles se retiran porque Windows no los tiene y oscurecerían el panel claro.
- La hoja «Ver todo» conserva la tarjeta anterior.
- El alto del bloque destacado pasa a depender del ancho (la tarjeta de colección crece con la ventana); la 1.4.0 lo había fijado para evitar tirones al redimensionar, así que el resize sólo cambia el tamaño de ítem del layout, sin reconfigurar celdas.

## Etapas

| # | Encargo | Archivos | Depende de |
|---|---|---|---|
| 1A | Disposición pura del mosaico y regla de la fila de colecciones | `Models/HomeMosaicLayout.swift`, `Models/HomeCollectionRowLayout.swift`, pruebas nuevas | — |
| 1B | Color por carátula con caché por sesión | `Services/HomeCoverColorStore.swift`, pruebas nuevas | — |
| 1C | Preferencia `albumCardStyle`, selector en Apariencia, textos ES/EN y límite de detalles 6 → 48 | `UI/HomeAppearance.swift`, `Views/Settings/SettingsModalView.swift`, `Localization/fragments/home-appearance.json` (y derivados), `Models/Home{Album,Playlist}Metadata.swift`, pruebas | — |
| 2 | Mosaico: celda, layout del carril y reemplazo del riel de canciones | `HomeFeedCollectionView.swift` (`HomeItemView`), `HomeFeaturedNativeRail.swift`, `HomeFeaturedView.swift`, pruebas | 1A, 1B |
| 3 | Colecciones: tarjeta con panel, fila por ancho, hover y detalles de toda la fila | los mismos de 2, más `HomeView.swift` si hace falta | 1A, 1C, 2 |
| 4 | Integración: revisión de diffs, suite completa, FIXES, PARIDAD y build numerada | registros y correcciones menores | 1–3 |

1A, 1B y 1C corren en paralelo sobre archivos distintos; 2 y 3 son secuenciales porque comparten `HomeItemView`, el carril y `HomeFeaturedView`. Subagentes Sonnet 5.5 con esfuerzo medio; revisión del agente principal.

## Pasos

- [x] Sincronizar `main` (ab25883), leer PARIDAD, FIX-317/320/321/322/323 y PLAN-026 Windows.
- [x] Línea base: `node Scripts/build-version.mjs macos` → build-0223.
- [x] Vectores de referencia del mosaico generados con el `mosaic.ts` de Windows.
- [x] 1A, 1B, 1C: disposición y fila (12 pruebas, vectores de Windows), color por carátula (15), preferencia y límite de detalles.
- [x] 2: mosaico. Revisión con render: el degradado quedaba arriba y el círculo de Play tapaba su icono; corregidos.
- [x] 3: colecciones. Revisión con render: la unión portada/panel salía redondeada; `maskedCorners` se reemplazó por recortes simples verificables.
- [x] 4: revisión de diffs, suite Swift (352 + 647) y core (112 + 186; 188 con `windows-bridge`), FIX-328, PAR-054/055/051 y build numerada.
- [ ] Validación visual del usuario en la app (cuenta real, VoiceOver, Reduce Motion/Transparency, resize, reproductor lateral).

## Comprobaciones de cierre

- Ninguna acción de Acceso rápido ni de las colecciones destacadas se pierde respecto de la 1.4.0.
- La misma lista de IDs dibuja el mismo mosaico que en Windows (vectores).
- La posición horizontal sobrevive a tapar y destapar Inicio, también con ancho 0 intermedio.
- No queda código, estilo ni prueba sin uso de los rieles reemplazados.
- Pruebas, compilación y validación manual se informan por separado.

## Resultado y pendientes

- La disposición del mosaico coincide con Windows en los ocho vectores, incluido uno con caracteres no ASCII.
- El render fuera de pantalla no refleja `maskedCorners`, transformaciones de capa ni materiales de vidrio: la elevación, la sombra animada y el Liquid Glass sólo se pueden juzgar en la app.
- Sin medir: fluidez al redimensionar con la tarjeta de ancho variable y costo de pedir hasta 36 detalles al abrir Inicio.
- A confirmar por el usuario: las decisiones por defecto de arriba, el umbral de encaje (0,3 del paso) y si la etiqueta y el resumen deben repetir las mayúsculas y el tipo tal como hoy los muestra Windows.
