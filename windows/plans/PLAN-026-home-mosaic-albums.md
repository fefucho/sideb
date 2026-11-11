# PLAN-026 — Inicio destacado: mosaico de Acceso rápido y tarjetas grandes de álbumes

- Objetivo: reemplazar el Speed Dial 3×3 paginado de Inicio por un mosaico de canciones a todo el ancho, con scroll horizontal y destacadas más grandes en orden semialeatorio, y cambiar las tarjetas destacadas de álbumes por tarjetas verticales grandes con la portada arriba y un panel de texto debajo, con dos acabados elegibles en Configuración.
- Estado: implementado el 2026-11-10 con subagentes Sonnet 5.5 (esfuerzo medio) e integración y revisión del agente principal. [FIX-320](../../FIXES.md#fix-320) y segunda vuelta de diseño [FIX-321](../../FIXES.md#fix-321), PAR-054, `builds/windows/build-0029` Release compilada (build-0027 muestra el diseño anterior). Falta la aceptación del usuario en la app y confirmar las decisiones tomadas por defecto.

**Integración 1.4.0 —2026-11-10:** FIX-322 lleva este plan (antes PLAN-025 en la copia Side-B-main, con FIX-268/269 y PAR-045) a la 1.4.0 como FIX-320/321/PAR-054; el mosaico y la fila de colecciones reemplazan los rieles de FIX-302. Release sin verify compilada; aceptación del usuario pendiente.
- Ámbito: presentación de Acceso rápido y de las colecciones destacadas de Inicio en Windows (`windows/src`). Sin cambios en `core/`, en qué canciones o colecciones se eligen ni en la reproducción. Apple queda como fila de paridad.
- Exclusiones: estantes compactos (`CompactSongCard`), tarjetas de los estantes (`HomeCard`), ambiente de Inicio, publicación.
- Numeración: este plan nació como PLAN-025 (`PLAN-025-speed-dial-redesign.md`); se renumeró porque otra sesión creó el mismo día [PLAN-025 de rediseño visual](PLAN-025-windows-visual-redesign.md). Ese plan propone radios de arte 2/5/8 (decisión D3 pendiente): si se aprueba, los radios 10/14 de este plan se revisan ahí.

## Decisiones del usuario (2026-11-10)

- El cuadrado 3×3 no continúa: en una ventana horizontal desaprovecha el ancho.
- Acceso rápido pasa a tener scroll horizontal y ocupa todo el ancho; canciones más grandes cada tanto, en un orden que se sienta medio aleatorio.
- Variante elegida para canciones: Mosaico de tres filas (frente a Cinta de dos filas y Cinta mixta, descartadas).
- Álbumes: el diseño anterior era temporal. Tarjetas grandes con panel de texto debajo de la portada, al estilo de Apple Music, viéndose 4 o 5.
- Los acabados «Blanco» y «Blanco teñido» quedan ambos disponibles en Configuración para probarlos.
- Se retiran el Speed Dial y las tarjetas de álbum anteriores; sólo queda lo nuevo.

## Decisiones tomadas por defecto (falta confirmación del usuario)

- Mosaico arriba y álbumes debajo. Con 900 px de alto de ventana los álbumes arrancan cerca de los 740 px.
- Cantidad de álbumes adaptable al ancho (regla abajo), no fija.
- Orden del mosaico estable mientras la lista de canciones no cambie.
- Tope de 27 canciones sin cambios.
- Acabado inicial: «Blanco teñido». La preferencia es de la instalación (Apariencia), no de la cuenta.
- Sólo Windows en esta entrega.

## Estado anterior verificado

- `HomeView.svelte` pintaba `.dial` (grilla `.tiles` 3×3 con `MediaCard layout="tile"`, 9 por página, puntos, rueda por página con `FeaturedWheelInput`) y `.collection-grid` (`MediaCard layout="horizontal" featured`, dos filas, hasta tres columnas, puntos). Ambos layouts sólo los usaba `HomeView`.
- `featured.ts` (`featuredLayout`) repartía la fila entre dial y colecciones desde 900 px y derivaba de ahí columnas, capacidad y alto de tarjeta; `projectHome` limita canciones a 27 y colecciones a `capacidad × 6`.
- `+page.svelte` recibe `onCapacity` y `onVisibleCollections`; esta última dispara la carga de metadata sólo de las colecciones visibles (`home/metadata.ts`).
- `HomeShelf.svelte` ya resuelve un carril horizontal con ventana de elementos, `HorizontalNavigation` (flechas de FIX-261) y posición retenida.
- Antecedentes: FIX-098 (diseño original aprobado sobre mockup), FIX-188 (geometría del Speed Dial en Apple), FIX-113-2 (port Windows), FIX-261 (flechas horizontales). Un fix histórico retiró el «aura roja» y el contorno rojo al sonar de las tarjetas de canciones de Inicio: no se reintroducen.

## Especificación: mosaico de canciones

Geometría: celda de 144 px, separación 8 px (paso 152), tres filas, alto 448 px. Tamaños: chica 1×1 (144×144), apaisada 2×1 (296×144), grande 2×2 (296×296).

Disposición (`home/mosaic.ts`): bloques sin huecos, de izquierda a derecha, con generador determinista sembrado por los IDs.

- T: grande en filas 0-1 y dos chicas en la fila 2. B: grande en filas 1-2 y dos chicas en la fila 0. W: apaisada en una fila y cuatro chicas. S: columna de tres chicas.
- La canción 0 siempre es grande; entre grandes hay de 1 a 3 columnas; dos grandes seguidas alternan arriba/abajo; sólo la última columna puede quedar incompleta.
- La pieza destacada de cada bloque toma la primera canción del bloque: el orden del proveedor se respeta de izquierda a derecha.
- Misma lista, mismo dibujo. Lista nueva, disposición nueva.

Tarjeta (todas con radio 10, portada a sangre y texto en una píldora de vidrio abajo):

| | Chica | Apaisada | Grande |
|---|---|---|---|
| Píldora: separación del borde | 6 px | 8 px | 10 px |
| Píldora: padding | 6/9/7 | 8/12/9 | 10/14/11, derecha 66 |
| Píldora: radio | 8 | 10 | 12 |
| Título | 12/15, 600 | 15/19, 700 | 20/25, 700 |
| Artista | 10.5/13 | 11.5/15 | 13/18 |
| Play | 28 px, al pasar el mouse | 32 px, al pasar el mouse | 40 px, siempre visible |

- Píldora: `rgb(16 16 20 / 64%)`, `backdrop-filter: blur(14px) saturate(1.3)`, borde `rgb(255 255 255 / 14%)`, brillo interior `inset 0 1px 0 rgb(255 255 255 / 6%)`. Título y artista en una línea con elipsis; artista `#ffffffc4`.
- Play: círculo `--sideb-accent` dentro de la píldora, a la derecha; al aparecer, la píldora reserva 42 px a la derecha. Menú `⋯`: 28 px, arriba a la derecha, radio 7, `#0009`, al pasar el mouse o con foco.
- Hover: `translateY(-3px) scale(1.035)` (apaisada 1.02; grande `translateY(-2px) scale(1.012)`) y sombra `0 16px 30px -10px` del color de la carátula mezclado 85 % con negro. La grande tiene en reposo `0 20px 44px -20px` del color de la carátula.
- Sonando: ecualizador de cuatro barras blancas (3 px de ancho, 14 px de alto) dentro de la píldora, halo `0 12px 28px -12px` del color de la carátula y borde de la píldora teñido. En pausa, barras quietas y atenuadas. Cargando, spinner en el lugar de Play. Sin contorno ni aura roja.
- Sin color disponible, las sombras usan negro.
- Transiciones de 180 ms `cubic-bezier(.2,.8,.2,1)`; con movimiento reducido, ninguna.

Carril: scroll horizontal nativo con barra oculta, márgenes laterales de 28 px, `HorizontalNavigation` sin páginas (paso 152), sólo se montan las celdas cercanas al área visible, y espacio vertical para que la elevación y las sombras no se recorten. La rueda vertical sigue desplazando Inicio.

## Especificación: tarjetas de álbum

Fila: tarjetas con separación de 24 px y márgenes laterales de 28 px, scroll horizontal con encaje al inicio de cada tarjeta y flechas flotantes. Sin puntos de página.

Cantidad visible (`n`) y ancho, con `útil` = ancho de contenido − 56: `n = límite(⌊(útil + 24) / 224⌋, 2, 5)`; si el ancho resultante supera 320 px, se suman tarjetas hasta bajar de 320. Ancho de tarjeta = `(útil − 24·(n−1)) / n`. Ejemplos: útil 1304 → 5 de 241 px; 1000 → 4 de 232; 844 → 3 de 265; 1624 → 5 de 305.

Tarjeta: radio 14, sombra en reposo `0 12px 30px -16px #000`, portada cuadrada arriba y panel debajo con padding 12/14/14.

- Etiqueta (Álbum, EP, Single o Lista, con la lógica existente): 10/14, 700, espaciado 1.2 px.
- Título: 17/22, 700, una línea. Artista: 14/19, 500, con sus enlaces. Resumen: 12/16, 6 px arriba.
- Blanco: panel `#f5f5f7`; título `#1d1d1f`; artista `#3a3a3c`; etiqueta y resumen `#6e6e73`.
- Blanco teñido: detrás del texto, la misma portada espejada y desenfocada (`blur(26px) saturate(1.5)`), con un velo `rgb(255 255 255 / 78%)`; título `#1d1d1f`; artista `rgb(0 0 0 / 79%)`; etiqueta y resumen `rgb(0 0 0 / 58%)`. Sin imagen, se ve como Blanco.
- Hover: `translateY(-4px)` y sombra `0 24px 42px -18px` del color de la carátula mezclado 75 % con negro. Play de 44 px `--sideb-accent` abajo a la derecha de la portada; menú de 30 px arriba a la derecha.
- Foco visible y contraste suficiente sobre el panel claro, incluidos los enlaces de artista.

## Contratos que no cambian

- Canciones: activar desde cualquier punto de la tarjeta (`media.activate` / `onPlay`), menú contextual por clic derecho, botón `⋯` y teclado, enlaces de artista y de invitados del título, indicador de contenido explícito, estados activo/pausado/cargando de `sourceActive` y `media.pending`.
- Colecciones: abrir, Play, menú, enlace de artista, etiqueta de tipo, resumen, selector Álbumes/Listas y fuentes de Configuración; la metadata se pide para toda la fila de una vez, con las tarjetas visibles primero (revisión del 2026-11-10 por pedido del usuario; antes sólo las visibles).
- Posición horizontal retenida al volver a Inicio y por selección; al cambiar la lista de colecciones se conserva el elemento ancla.
- Proyección (`projectHome`): mismas fuentes, prioridad y deduplicado.
- Movimiento reducido y pausa de animaciones fuera de foco o visibilidad.

## Encargos

| # | Encargo | Archivos | Depende de |
|---|---|---|---|
| 1 | Disposición pura del mosaico y color por carátula | `home/mosaic.ts`, `home/coverColor.ts`, `scripts/home-mosaic.test.mjs` | — |
| 2 | Preferencia `albumCardStyle` y selector en Configuración | `appearance/preferences.ts`, `HomeSettings.svelte`, `i18n/windows.json`, `scripts/sidebar-appearance.test.mjs` | — |
| 3 | Mosaico: tarjeta, carril y reemplazo del Speed Dial | `MediaCard.svelte`, `MediaArtwork.svelte`, `HomeMosaic.svelte` (nuevo), `HomeView.svelte`, pruebas | 1 |
| 4 | Álbumes: tarjeta con panel, fila y retiro del diseño anterior | `MediaCard.svelte`, `HomeCollectionRow.svelte` (nuevo), `HomeView.svelte`, `home/featured.ts`, `+page.svelte` si hace falta, pruebas | 1, 2, 3 |
| 5 | Integración: revisión de diffs, verificación completa, FIXES, PARIDAD y cierre | registros y correcciones menores | 1–4 |

Los encargos 1 y 2 corren en paralelo sobre archivos distintos; 3 y 4 son secuenciales porque comparten `MediaCard.svelte` y `HomeView.svelte`.

## Pasos

- [x] Leer instrucciones, Git y antecedentes; seguir ambas secciones en código.
- [x] Tres rondas de maquetas y decisiones del usuario.
- [x] Encargo 1: `mosaic.ts`, `coverColor.ts` y 8 pruebas. Revisión: los fallos de carga también se recuerdan.
- [x] Encargo 2: preferencia `albumCardStyle`, selector y pruebas. Revisión: `windows.json` devuelto a LF.
- [x] Encargo 3: layout `mosaic`, `HomeMosaic` y retiro del Speed Dial. Revisión: especificidad de las reglas sobre `MediaArtwork`.
- [x] Encargo 4: layout `panel`, `HomeCollectionRow`, `collectionRowLayout` y retiro del diseño anterior. Revisión: límite de metadata de 6 a 9 y recorte del borde de la tarjeta siguiente.
- [x] Encargo 5: check 0/0, 513 pruebas, build de frontend, 12 capturas del fixture de supervisión, FIX-320, PAR-054 y build-0027.
- [x] Revisión 2026-11-10: detalles de toda la fila de colecciones de una vez (límite de metadata 48). Check 0/0 y 513 pruebas; entregada en build-0029 (FIX-321).
- [x] Segunda vuelta de diseño pedida por el usuario el 2026-11-10 tras ver build-0027. Canciones: la píldora de vidrio con el nombre se ve genérica; se presentaron tres maquetas (1 Degradado, 2 Texto debajo, 3 Portada limpia). Colecciones: no gusta la sombra del color de la carátula al pasar el mouse; se presentaron tres maquetas (A Portada atenuada, B Zoom de portada, C Elevación neutra). Elegidas 1 y A, esta última conservando la elevación. Implementado con un subagente Sonnet 5.5 medio y revisado: FIX-321, build-0029 Release compiled. La especificación visual de píldora y sombras de color de más arriba queda reemplazada por la de FIX-321.
- [ ] Aceptación del usuario en la app (WebView2, cuenta y audio reales) y confirmación de las decisiones por defecto.

## Pendientes conocidos

- Rendimiento del `backdrop-filter` de las píldoras al desplazar el mosaico: sin medir.
- `prefers-reduced-motion` y `prefers-reduced-transparency`: implementados, sin ejercitar.
- A 960 px de ancho el reproductor flotante tapa el panel de texto de las tarjetas hasta bajar.
- Un título chico con invitados se corta sin puntos suspensivos (comportamiento anterior al cambio).
- `navigation/gestures.ts` conserva el selector sin uso `.featured-pages` (anterior al cambio).
- El fixture de supervisión vive en `windows/.cache/plan025-browser/run.mjs`, fuera de Git; no es una prueba de la suite.

## Comprobaciones de cierre

- Ninguna acción de Acceso rápido ni de las colecciones destacadas se pierde respecto del estado anterior.
- El mosaico y la fila de álbumes ocupan el ancho disponible desde ventanas angostas hasta maximizada, sin recortes ni scroll horizontal de la página.
- La disposición no salta entre renders con la misma lista.
- El color por carátula no retrasa el primer pintado ni conserva datos de otra cuenta.
- No queda código, estilo ni texto sin uso del Speed Dial ni de las tarjetas anteriores.
- Validación visual en WebView2 real separada de las pruebas de frontend.

## Paridad

Apple conserva el Speed Dial 3×3 junto a los álbumes. Al cerrar la implementación Windows se crea la fila en `PARIDAD.md`.
