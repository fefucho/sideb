# PLAN-009: cartas comunes y reproducción contextual

- Fecha: 2026-10-04 (America/Montevideo).
- Estado: implementado en Apple por pedido del usuario; verificación automática completada en build-0030 y correcciones FIX-112 en build-0031 y cola propia FIX-113 en build-0033. Validación visual, teclado en ventana real, audio y consumo pendientes.
- Objetivo: una presentación y unas interacciones consistentes para cada tipo de ítem en toda la app; reducir controles visibles y rehacer el indicador de reproducción.
- Ámbito inicial: Apple. Registrar el comportamiento acordado para Windows con implementación propia cuando se ejecute; no modificar core ni contratos de reproducción por una necesidad visual.
- Referencias: [FIXES](../../FIXES.md) (FIX-097–100, 103, 105–106), [PARIDAD](../../PARIDAD.md), [guía actual](../../PORTEO-INICIO.md), [PLAN-008](PLAN-008-home-cleanup-efficiency.md). Este plan no ejecuta ni sustituye la limpieza propuesta en PLAN-008.

## Pedido confirmado

- Diseños generales para álbumes, playlists, canciones y canciones en formato horizontal ancho.
- Limpiar botones y acciones visibles; mantener la acción principal de cada ítem.
- Canciones: al hacer hover, un único botón Play centrado sobre la portada.
- La reproducción depende del lugar: radio o reproducción dentro de una lista (álbum/playlist).
- Inicio/Speed Dial: la carta de la canción que originó la radio mantiene la animación mientras esa radio sea el contexto activo, aunque avance a otras canciones. Reemplazar el diseño actual.
- Álbumes/playlists: la carta abre el detalle. Play en la esquina inferior derecha de la portada; se tiñe de rojo al hacer hover sobre el botón, no sobre toda la carta.
- Acciones secundarias mediante clic derecho y botón de tres puntos en la esquina superior derecha de la portada.
- Indicador elegido: barras suaves en la carta origen de la radio; se sustituyen por Pausa al hover/foco. Al pausar, barras quietas y más tenues; Play al hover/foco.
- Play y tres puntos aparecen con hover o foco de teclado, sin ocupar permanentemente la portada.
- Conservar los enlaces de artista, álbum y creador cuando existan destinos reales.
- Canciones de Biblioteca e Historial: reproducir la lista mostrada desde la ocurrencia elegida.
- Canciones horizontales: un clic en toda la tarjeta reproduce según su contexto, incluidos portada, título y espacio libre. Artista/álbum son enlaces independientes; el botón `…` abre el menú sin reproducir. El Play de la miniatura expresa la misma acción, no limita su área pulsable.
- Álbumes/playlists: el estado de la colección activa se refleja en todas sus cartas de la app; el botón permite Pausar/Reanudar sin reiniciar canción ni cola.
- Definir el plan con preguntas al usuario antes de implementar.

## Decisiones y alcance aplicado

| Decisión | Propuesta inicial | Estado |
|---|---|---|
| Álbum/playlist | Carta abre detalle; Play abajo a la derecha de portada, rojo al hover del botón | Confirmado; reproducción del catálogo canónico en orden |
| Acciones secundarias | Clic derecho y tres puntos arriba a la derecha | Confirmado por el usuario; conservar funcionalidades |
| Indicador de Inicio | Barras suaves centradas en la canción origen de la radio; Pausa al hover/foco aunque la radio haya avanzado | Confirmado por el usuario |
| Visibilidad de controles | Play y puntos aparecen al hover o foco; botón Play de colección rojo sólo con hover del propio botón | Confirmado por el usuario |
| Créditos interactivos | Conservar enlaces de artista/álbum/creador con destinos reales | Confirmado por el usuario |
| Canciones de Biblioteca/historial | Reproducir la lista mostrada desde la ocurrencia elegida | Confirmado por el usuario |
| Alcance del indicador | Inicio/Speed Dial identifica la radio por su canción origen; no trasladar automáticamente esas barras a la canción que suena en todas las vistas | Confirmado; indicador de fila actual conserva la ocurrencia real de la cola |
| Radio pausada sin hover | Barras quietas y más tenues en carta origen; Play al hover/foco | Confirmado por el usuario |
| Colección activa | Estado común en todas sus cartas; Pausa/Reanudar si es el contexto activo, otra colección empieza desde el principio | Confirmado por el usuario |
| Canciones horizontales/filas | Toda la tarjeta reproduce con un clic; artista/álbum navegan por separado y `…` abre el menú | Confirmado; cola exceptuada por FIX-113: subtítulo conjunto, Like/Dislike y grip al hover, clic derecho para menú |
| Búsqueda rápida | Conservar navegación de resultados y teclado; aplicar las mismas reglas por tipo con densidad compacta | Aplicado conservando la navegación y la acción contextual existentes |
| Artistas/videos | Artista abre página; video usa reproducción contextual y miniatura panorámica | Aplicado conservando la navegación y la acción contextual existentes |

## Inventario de partida

Ocho familias visuales, sin contar cabeceras de detalle/reproductor: carta vertical, colección destacada horizontal, tile de canción Speed Dial, canción horizontal compacta, fila ancha de tabla, resultado pequeño de búsqueda rápida, mejor resultado de búsqueda y carta panorámica de video. Artistas añaden portada circular. Varias familias tienen implementaciones separadas por pantalla.

| Superficie | Implementación actual |
|---|---|
| Estantes Inicio | `Views/Home/HomeFeedTableView.swift` usa `HomeItemView` y componentes alojados en `HomeFeedCollectionView.swift` |
| Speed Dial/destacados | `Views/Home/HomeFeaturedView.swift`: `songTile` y `collectionCard` |
| Indicador de Inicio | `Views/Home/HomeEqualizerOverlayView.swift`, estado en `HomeItemView`; Speed Dial necesita revisar/sincronizar estado de reproducción |
| Biblioteca | `Views/Library/LibraryView.swift`: cartas propias y tabla común |
| Buscar | `Views/Search/SearchView.swift`: cartas, mejor resultado y filas propias; `QuickResultComponents.swift` en búsqueda rápida/Spotlight |
| Artista/catálogos | `Views/Detail/ArtistDetailView.swift` y `ArtistCatalogView.swift` |
| Canciones de listas/historial/cola | `Views/Common/NativeTrackTableView.swift`, configurable por contexto |
| Recomendaciones fullscreen | `Views/Fullscreen/Recommended/RecommendedContentView.swift`: filas y cartas propias |

`HomeFeedCollectionView` contiene un contenedor antiguo y piezas aún usadas por producción; no borrar el archivo entero. Consultar PLAN-008 antes de mover piezas. No reintroducir pools/rebind del ensayo descartado FIX-101.

## Contrato de interacción implementado

| Contexto de canción | Acción de reproducción |
|---|---|
| Inicio/Speed Dial/búsqueda independiente | Iniciar radio a partir de la canción |
| Detalle de álbum/playlist | Reproducir la lista desde la ocurrencia elegida, conservando su orden y continuaciones |
| Cola | Activar la ocurrencia existente; no reconstruir la cola ni crear otra radio |
| Canciones de Biblioteca/historial | Reproducir la lista mostrada desde la ocurrencia elegida; conservar orden, filtros, grupos y continuaciones del contexto |
| Recomendaciones fullscreen | Conservar radio para pistas independientes; navegación/reproducción de colección mediante su identidad real |

- Play/Pausa sobre la ocurrencia/contexto ya activos alterna reproducción, conservando posición y cola. Elegir otro contexto debe usar su acción contextual; un `videoId` repetido no basta para identificar una ocurrencia en la cola.
- Álbum/playlist: abrir detalle no cambia el audio. Play usa el catálogo canónico completo y sus continuaciones, sin precargar todas las canciones sólo para dibujar cartas.
- Limpieza: conservar `…` arriba a la derecha y clic derecho como acceso al mismo menú secundario. Retirar botones dedicados de likes/radio/aleatorio de la superficie de la carta y conservar sus funciones en el menú según disponibilidad/contexto. Conservar datos reales, badge explícito y metadata útil; limpiar controles no implica borrar datos.
- Créditos enlazados conservan su acción independiente: pulsar artista/álbum/creador navega al destino real y no dispara además la acción principal de la carta. No inventar enlaces a partir del texto.
- Canciones horizontales: portada, título y espacio libre ejecutan la misma acción contextual mediante un clic. No limitar reproducción a la miniatura ni exigir doble clic. Evitar duplicar solicitudes por propagación del botón Play, eventos de fila o doble clic; enlaces y menú consumen su propia interacción sin activar la canción.
- Destacados: Play abajo a la derecha de la portada sustituye los botones grandes. Aleatorio permanece en el menú; la carta abre detalle y los créditos con destinos reales navegan por separado.
- Indicador de radio en Inicio/Speed Dial: comparar el ID de la carta con `QueueContext.radio(seedVideoId:...)`, no con `currentTrack.videoId`. La carta origen sigue activa al avanzar/retroceder pistas; su control pausa/reanuda la radio actual sin reiniciarla. Al cambiar de contexto o sesión deja de indicar esa radio. `QueueManager` ya conserva `seedVideoId`; revisar su observación y ciclo de vida antes de agregar otro estado.
- Álbumes/playlists: todas las representaciones de la misma colección reflejan el contexto activo con IDs canónicos. Una canción del álbum sonando desde una radio no activa la carta del álbum. No confundir origen de radio, colección activa y pista/ocurrencia actual de la cola.
- Hover y foco de teclado deben permitir la misma acción; nombre accesible Play/Pausa, área pulsable estable y menú accesible si se conserva clic derecho.
- Estado activo se obtiene del reproductor real: no animar por el último clic, carga pendiente o una coincidencia de álbum ajena al contexto de reproducción.
- Indicador ligero: sin análisis de audio nuevo; respetar Reduce Motion, inactividad y visibilidad. No afirmar coste nulo ni fluidez sin medir.

## Etapas

- [x] Cerrar las decisiones de interacción con el usuario; ejecución autorizada el 2026-10-04.
- [x] Aplicar controles comunes y barras suaves a los componentes existentes: Play de 32 pt en portadas grandes, 8 pt de inset para colecciones; variantes compactas según densidad. Conservar medidas/tipografía/esquinas existentes. La revisión visual en la app queda pendiente.
- [x] Separar presentación SwiftUI (`MediaArtworkControls`) de acciones contextuales; variantes AppKit de Inicio/tablas comparten identidad, posiciones y reglas.
- [x] Integrar Inicio/Speed Dial/destacados, Biblioteca/Buscar/Spotlight, artista/catálogos y recomendaciones/tablas.
- [x] Revisar menús, enlaces y zonas de interacción; retirar botones redundantes y preservar funcionalidades secundarias.
- [x] Runner completo: 180 Rust (7 live ignorados), 52 XCTest y 187 Swift Testing/5 suites aprobados. Registro [FIX-111](../../FIXES.md#fix-111), [PAR-009](../../PARIDAD.md) y guía/índice actualizados.
- [ ] Validación manual en sesión real: apariencia, foco/teclado, selección/arrastre, audio y consumo.

## Comprobaciones de cierre

- Radio vs lista, clic sobre carta origen vs otra canción y ocurrencias duplicadas en cola. Avanzar varias pistas de radio conserva barras/control en su carta origen; pausa/reanudación desde esa carta no reinicia la radio. Cambiar contexto retira el indicador anterior.
- Álbum/playlist: abrir sin alterar audio, reproducir colección completa y conservar cola ante error/cancelación/cambio de cuenta.
- Consistencia de carta por tipo entre pantallas, créditos/badges/textos largos, placeholders y densidades.
- Play centrado en canciones y abajo a la derecha en colecciones; `…` arriba a la derecha, sin controles superpuestos ni zonas que ejecuten dos acciones.
- Indicador de origen sincronizado en Inicio/Speed Dial y estado de colección en todas sus cartas; pausa, Reduce Motion, vista fuera de pantalla y ventana inactiva.
- Virtualización, gestos de estantes, paginado de destacados, foco/selección/tablas y acciones secundarias acordadas.
- Enlaces de créditos sin doble acción; Biblioteca/Historial arrancan en la ocurrencia seleccionada dentro de la lista visible, incluyendo resultados filtrados y canciones repetidas.
- En canciones horizontales, clic en portada/título/espacio libre reproduce la misma ocurrencia; artista/álbum navegan y `…` abre el menú sin cambiar audio. Verificar una sola solicitud por interacción, con teclado/selección preservados.
- Pruebas focales de conducta, suite Apple y build versionada; validación visual/consumo por separado. Consultar el resultado concreto de cierre en FIX-111.

## Resultado implementado

Build: `builds/macos/build-0030/Side B.app`, release arm64, SDK 27.0 / mínimo macOS 15, firma ad hoc verificada; BUILD.json `compiled` / `sourceChangedDuringBuild: false`. Focal final: 8 XCTest + 31 Swift Testing aprobados. La suite completa y el bundle corresponden al código final; documentación de cierre actualizada después de compilar. Core/Windows/bindings y versión pública intactos; port Windows pendiente en PAR-009. No hubo commit/push/publicación.

Se integraron tres encargos de subagentes Luna (cartas nativas/indicador, superficies SwiftUI, tablas/historial), con revisión de diff y contratos por el integrador y correcciones de hit testing, foco, gestos de selección y ocurrencias antes del runner final.

## Fuera de alcance actual

Rediseño de shell/reproductor/fullscreen, cambios de fuentes/categorías, ejecución de PLAN-008, core Rust/UniFFI, implementación Windows, commit/push/publicación. Las funciones secundarias permanecen en los menús acordados.

## Correcciones tras probar build-0030 — FIX-112

El usuario aprobó el aspecto general y reportó Play persistente en la fila pulsada y ~5–6 s al cambiar canciones de Biblioteca/Likeados. Play/menú de tabla ahora se revelan por hover/foco de control, sin usar la selección persistente; el estado de pista actual queda independiente. Con tracks ya cargados y continuación, reproducción normal comienza en la ocurrencia elegida mientras se completa la fuente en segundo plano; fuente/ocurrencias/anclas y audio se conservan al completar. Aleatorio inicial conserva catálogo completo antes de elegir. [FIX-112](../../FIXES.md#fix-112), [PAR-010](../../PARIDAD.md); [build-0031](../../builds/macos/build-0031/BUILD.json) compilada con fuentes estables: 180 Rust (7 live ignorados), 52 XCTest y 194 Swift Testing aprobados. Verificación real de los dos reportes pendiente; documentación actualizada después de compilar, sin cambios posteriores de código.

## Cola especial restaurada — FIX-113

Pedido posterior del usuario (2026-10-05): la cola tiene presentación propia como antes de build-0030, con Like/Dislike dedicados y control de reordenamiento al hover, título arriba y artista • álbum juntos debajo. No usar Play flotante ni `…` de las cartas comunes en la cola. Like marcado visible fuera del hover; foco permite operar controles. Clic derecho, selección, ocurrencias duplicadas y arrastre conservan el coordinador/player actuales. Las cartas comunes de otras superficies y el inicio progresivo de FIX-112 siguen vigentes. La celda histórica se recupera de Git en una clase separada con un contrato compartido de refresco. [FIX-113](../../FIXES.md#fix-113), [PAR-009](../../PARIDAD.md); [build-0033](../../builds/macos/build-0033/BUILD.json) compilada con fuentes estables: 180 Rust (7 live ignorados), 52 XCTest y 198 Swift Testing aprobados; cinco focales aprobadas. Documentación actualizada después de compilar, código sin cambios posteriores; validación visual/arrastre físico pendiente.
