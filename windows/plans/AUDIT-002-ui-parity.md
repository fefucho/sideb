# Auditoría de estructura y funciones de UI — Windows / macOS

- Fecha: 2026-10-05 (America/Montevideo).
- Estado: auditoría estática terminada; diferencias de implementación pendientes. Registro: [FIX-117-2](../../FIXES.md#fix-117-2).
- Objetivo: comparar componentes, composición, información visible, gestos, acciones y estados para acercar Windows a la referencia macOS y facilitar futuros ports.
- Alcance: código vigente de ambas apps y captura de playlist del usuario; sin cambios de UI, controllers, Apple ni core. El árbol ya contenía trabajo sin commit de FIX-113-2 a FIX-116-2 y se conservó.
- Referencias: [AUDIT-001](AUDIT-001-home-parity.md), [PARIDAD](../../PARIDAD.md), FIX-087, FIX-098 a FIX-112 y FIX-113-2 a FIX-116-2. Esos antecedentes orientan la comparación; sus pruebas no son comprobaciones nuevas de esta auditoría.

## Conclusión

La diferencia de la captura es real: Windows dibuja siempre el encabezado `# / Título / Álbum / Duración`; macOS configura `headerView = nil`. El álbum de cada canción sí se muestra en ambas plataformas cuando corresponde. Para acercar el resultado hay que retirar la fila visible de encabezados, conservando información y semántica accesible.

La causa estructural más importante es que Windows mantiene dos implementaciones de tabla y otra de cola, con contratos de presentación distintos. macOS reutiliza `NativeTrackTableView` en álbum, playlist, Biblioteca, Historial, búsqueda filtrada y cola; sus canciones populares de artista usan filas propias. Las cartas Windows ya comparten controles tras FIX-113-2 a FIX-116-2, pero el resultado principal de búsqueda todavía tiene controles independientes y algunas variantes pierden información de su contexto.

Hay paridad considerable en colores, Inicio/configuración, reproducción contextual, menús, letras sincronizadas y navegación básica. Persisten diferencias visuales, de interacción y funciones incompletas; no se puede afirmar igualdad global de UI por las pruebas previas de Inicio. Conviene igualar contratos de componentes y composición de pantallas; las implementaciones nativas pueden seguir siendo diferentes.

## Método, prioridades y límites

Se inventariaron 42 componentes Svelte Windows y 47 archivos Swift en `Views` Apple. Se contrastaron vistas principales, componentes comunes, consumidores, controllers/view models y rutas de acciones relevantes. El inventario no significa una revisión exhaustiva de cada línea de esos archivos.

- **P1:** diferencia de función o de componente común que afecta varias pantallas; primera tanda sugerida.
- **P2:** diferencia comprobada de presentación/interacción, o riesgo estructural que necesita escenario reproducible antes de un fix.
- **P3:** terminología, detalle secundario o adaptación que debe documentarse para evitar divergencias futuras.
- **Confirmado por código:** ramas, props o medidas distintas. No equivale a validación visual nativa.
- **Por verificar en runtime:** consecuencias sobre ancho real, DPI, foco, latencia o rendimiento. No se presentan como bugs reproducidos.

No se ejecutaron nuevas suites, builds, pruebas con cuenta, audio ni mediciones de FPS/consumo. No se compararon ventanas nativas Mac/Windows simultáneamente. Las medidas siguientes son puntos/px declarados en código, sin afirmar equivalencia física a distinto DPI o entre fuentes SF y Segoe UI. Las referencias de línea corresponden al árbol local auditado y pueden cambiar después.

## Mapa de componentes y responsabilidades

| Responsabilidad | macOS | Windows actual | Diagnóstico |
|---|---|---|---|
| Shell, composición y conexión de acciones | [SideBApp.swift](../../apple/Sources/SideB/SideBApp.swift), Router y view models | [+page.svelte](../src/routes/+page.svelte), controllers y NavigationHistory | Ambas tienen separación de servicios/estado; Windows concentra más coordinación en la raíz: 1148 líneas frente a 577 de SideBApp. Tamaño es señal de acoplamiento, no prueba de un fallo. |
| Pistas con selección, enlaces, actividad y reordenamiento | [NativeTrackTableView.swift](../../apple/Sources/SideB/Views/Common/NativeTrackTableView.swift) | [TrackTable.svelte](../src/lib/components/detail/TrackTable.svelte), [AccountTrackTable.svelte](../src/lib/components/library/AccountTrackTable.svelte), [QueuePanel.svelte](../src/lib/components/fullscreen/QueuePanel.svelte) | Principal área de divergencia. Unificar contrato de fila/lista, conservando adaptadores de datos y acciones por contexto. |
| Arte y controles de reproducción/menú | [MediaArtworkControls.swift](../../apple/Sources/SideB/Views/Common/MediaArtworkControls.swift), composiciones propias por pantalla | [MediaArtwork.svelte](../src/lib/components/common/MediaArtwork.svelte), [MediaCard.svelte](../src/lib/components/common/MediaCard.svelte), [RowPlay.svelte](../src/lib/components/common/RowPlay.svelte) | Mac también compone cartas distintas. Compartir controles no obliga a que todos los contextos usen la misma carta genérica. |
| Detalle y sus estados | [DetailSharedComponents.swift](../../apple/Sources/SideB/Views/Common/DetailSharedComponents.swift), vistas de álbum/playlist/artista | [DetailHeader.svelte](../src/lib/components/detail/DetailHeader.svelte), vistas y estados propios | Windows reutiliza parte de la cabecera, pero no todos los estados ni la composición. |
| Acciones contextuales | [MenuPolicy.swift](../../apple/Sources/SideB/UI/ContextMenu/MenuPolicy.swift) y ejecutor | [policy.ts](../src/lib/menu/policy.ts), [executor.ts](../src/lib/menu/executor.ts), ContextMenu | Base centralizada en ambas. No hay motivo para llevar acciones de vuelta a cada pantalla. |
| Geometría y colores | [AppTheme.swift](../../apple/Sources/SideB/UI/AppTheme.swift) | [tokens.css](../src/lib/styles/tokens.css) y estilos de componentes | Colores principales alineados; radios, tamaños y tipografía siguen dispersos en Windows. |
| Cola y reproducción | PlayerViewModel/QueueManager y AVPlayer | PlaybackController y cola nativa Tauri/libmpv | Conservar autoridad nativa, ocurrencias y generaciones. Igualar UI no justifica crear otra cola o modificar core. |

## Listas, detalles, Biblioteca e Historial

### UI-001 — Encabezados visibles ajenos a la referencia [P1, confirmado]

Mac elimina el encabezado en [NativeTrackTableView](../../apple/Sources/SideB/Views/Common/NativeTrackTableView.swift), línea 244. Windows lo emite sin condición en [TrackTable](../src/lib/components/detail/TrackTable.svelte), línea 36, y [AccountTrackTable](../src/lib/components/library/AccountTrackTable.svelte), línea 72; CSS reserva 32 px y un separador. Afecta más superficies que la playlist de la captura: álbum, Biblioteca, grupos de Historial, populares de artista y canciones filtradas de búsqueda.

Objetivo: lista sin esa franja visible, con estructura accesible. No retirar la columna/información de álbum por confundirla con el encabezado. Seguimiento: PAR-012-2.

### UI-002 — Dos tablas y una cola con contratos de fila distintos [P1, confirmado]

Las dos tablas Windows duplican selección, activación, columnas, créditos, duración, menú, estilos y navegación de teclado. AccountTrackTable añade mutaciones; QueuePanel vuelve a implementar la fila. El componente nativo Apple reúne más de esas responsabilidades mediante opciones, adaptadores y callbacks.

Objetivo: `TrackList`/`TrackRow` Windows comunes con variante por contexto y adaptadores de SongDto/AccountSong/QueueEntry. Las mutaciones siguen en sus controllers y la cola en su runtime autoritativo. No sustituir datos de ocurrencias por `videoId` ni fusionar acciones que dependen de propiedad de la playlist. PAR-012-2.

### UI-003 — Reserva de columnas y orden diferente entre tablas [P1, confirmado]

[AccountTrackTable](../src/lib/components/library/AccountTrackTable.svelte), líneas 39–40 y estilos, declara `hasActions = true` y reserva **200 px para acciones**, aun sin edición/reordenamiento. Duración ocupa 70 px y álbum 22%; el mínimo con ambas es 660 px y admite desplazamiento horizontal. TrackTable reserva una columna de menú de 36 px y coloca menú/duración en otro orden. Mac usa una única columna de contenido, ajusta subcampos dentro de la fila, limita álbum a 160 y usa duración 44/menú 24; deshabilita scroll horizontal en NativeTrackTableView, líneas 235–266 y 1152–1164.

La reserva excesiva de AccountTrackTable explica una diferencia de espacio verificable por código; cuánto afecta cada ventana necesita prueba. Objetivo: mismo reparto adaptable de fila y acciones que ocupen espacio según contexto. PAR-012-2.

### UI-004 — Play aparece en el índice y no sobre la portada [P2, confirmado]

Windows monta [RowPlay](../src/lib/components/common/RowPlay.svelte) en la celda del índice: TrackTable:43 / AccountTrackTable:79; sus miniaturas son imágenes sin ese overlay. Mac sitúa Play en la miniatura y barras de actividad en el índice mediante NativeTrackTableView:1031–1060 y 1138–1143. Es una diferencia de interacción recurrente, aunque el clic en la fila y la pausa contextual ya estén implementados.

Objetivo: definir una sola política de índice/barras y arte/Play/menú, conservando selección modificada, foco, clic derecho y activación única. PAR-012-2 / PAR-009.

### UI-005 — Edición de playlist con controles persistentes adicionales [P2, confirmado]

AccountTrackTable:91–93 muestra flechas subir/bajar y botón quitar en playlists propias. Mac usa asa de arrastre al hover en lugar de duración, y acciones de eliminación contextual; NativeTrackTableView:1198 y 1325–1331. Windows también admite arrastre: la diferencia no es que falte totalmente reordenar, sino la presentación y ocupación de controles adicionales.

Objetivo: acercar controles visibles a Mac preservando alternativas de teclado, eliminación, bloqueo durante mutación y posición de ocurrencias repetidas. PAR-012-2 / PAR-013-2.

### UI-006 — Apariencia de fila activa y densidad [P2, confirmado]

Ambas listas ordinarias parten de fila 52 y portada 40. Windows usa título 13, radio de arte 6, bordes inferiores y hover rectangular; la actividad principalmente colorea el título. Mac usa título 14, radio de miniatura 2 y fondo/borde redondeados de actividad (NativeTrackTableView:863–881; dibujo de hover con inset/radio propios).

Objetivo: tokens para fila normal/cola/compacta y contrato de estado normal/hover/foco/selección/cargando/activa/pausada. No asumir que color de título representa toda la actividad. PAR-012-2 / PAR-017-2.

### UI-007 — Listas largas sin reciclaje equivalente [P1, estructura confirmada; impacto por medir]

Las tablas y cola Windows renderizan todos los ítems con `each`; Mac recicla celdas de NSTableView (`viewFor`, `prepareForReuse`, líneas 473 y 943). RowPlay crea observador de visibilidad y listeners de ventana por instancia. Las optimizaciones de HomeShelf/VirtualStack no virtualizan estas tablas.

Objetivo: listas acotadas al viewport, identidad estable y observación compartida cuando corresponda. Medir DOM, listeners, memoria y respuesta con listas largas antes de elegir implementación; no se midió lag ni FPS. Preservar selección fuera de viewport, foco, arrastre y carga de continuaciones. PAR-012-2; no confundir con PAR-004, que cubre Inicio.

### UI-008 — Metadata y carga de playlists/Biblioteca [P2, confirmado]

Mac muestra descripción y cantidad de canciones; Windows condiciona esa cantidad a la ausencia de `subtitle` en [PlaylistDetailView](../src/lib/components/detail/PlaylistDetailView.svelte):78. Windows añade selector de orden en el cuerpo, mientras Mac coloca los seis órdenes en menú; ambos tienen las mismas seis opciones, no falta una opción de orden. En detalle de playlist/Biblioteca, Apple dispara continuación cerca del final; Windows ofrece botón explícito (PlaylistDetail:94 / Library:115 frente a PlaylistDetailView.swift:88 y LibraryView.swift:132–151).

Objetivo: cantidad independiente del subtítulo, ubicación de orden y política de continuación por pantalla. La carga **explícita de Inicio** ya está alineada y debe conservarse: no aplicar un único mecanismo global. El inicio de playback sin esperar todo el catálogo es otro asunto, ya registrado en PAR-010. PAR-013-2.

### UI-009 — Cabeceras y estados de detalle compuestos de forma distinta [P2, confirmado]


Álbum/playlist comparten arte 180 y título 32 como base, pero Mac limita el título a dos líneas y usa radio de hero 8; Windows permite crecimiento del título y usa radio 10 en [DetailHeader](../src/lib/components/detail/DetailHeader.svelte) / PlaylistDetail. Windows añade `Volver`/línea superior propios en detalles además de las acciones de navegación del shell. Mac coloca navegación global y reutiliza DetailLoadingHeader/DetailErrorState; los estados Windows están más repetidos entre vistas.

Objetivo: cabecera de detalle común con variantes, límites de texto y estados conservando descripción completa, reintento y arte. Evaluar redundancia del botón Volver sin reactivar TopNav/ocultamiento de sidebar excluidos. PAR-013-2 / PAR-017-2.

### UI-010 — Biblioteca y catálogos escalan las cartas de otra manera [P2, confirmado]

[LibraryView.swift](../../apple/Sources/SideB/Views/Library/LibraryView.swift):12 usa carta adaptable 160–220; [LibraryView.svelte](../src/lib/components/library/LibraryView.svelte):166 usa mínimo 160 y `1fr` sin máximo. Catálogo Apple usa 150–190; [CatalogView.svelte](../src/lib/components/detail/CatalogView.svelte) parte de 156 sin el mismo tope. Biblioteca Mac usa texto 13/11 y una línea; la carta general Windows 14/12 y dos líneas.

Objetivo: variantes explícitas Biblioteca/catálogo/feed en lugar de heredar todo del estilo de una carta general. Los cuatro tabs y funciones básicas de Biblioteca ya existen en ambas. PAR-017-2.

### UI-011 — Historial repite tablas y no normaliza títulos de fecha [P2, confirmado]

[HistoryView.svelte](../src/lib/components/library/HistoryView.svelte):26–30 monta una tabla por grupo, con encabezados repetidos y `numbered=false`; conserva offset para identificar ocurrencias. [HistoryView.swift](../../apple/Sources/SideB/Views/History/HistoryView.swift):10–55 y 108 usa secciones de una lista y normaliza Today/Yesterday/días/meses a español. Windows muestra el título del proveedor tal cual; sólo habrá texto inglés si el proveedor lo devuelve así. Mac numera dentro de cada sección; Windows muestra nota en lugar de número.

Objetivo: presentación de secciones/fechas/índice compartida, sin romper el offset global usado para activar la ocurrencia correcta. PAR-012-2.

### UI-012 — Populares y Ver todo de artista [P2, confirmado; disponibilidad por verificar]

Mac compone cinco filas populares propias sin encabezado; [ArtistDetailView.svelte](../src/lib/components/detail/ArtistDetailView.svelte):169 usa TrackTable con su formato de columnas. Para `Ver todo`, Windows rechaza IDs que comienzan por `FE` (línea 178), mientras [ArtistDetailView.swift](../../apple/Sources/SideB/Views/Detail/ArtistDetailView.swift):403 admite `moreBrowseId` no vacío. En **Inicio**, ambos rechazan FE: esa regla no debe generalizarse al artista sin revisar el tipo de destino.

Objetivo: variante de fila popular y prueba con catálogo real/fixture de cada tipo de ID antes de cambiar disponibilidad. No se demostró que un catálogo real actualmente accesible se pierda. PAR-013-2.

## Búsqueda y creación de playlists

### UI-013 — Resultado principal de búsqueda fuera de los controles comunes [P1, confirmado]

[SearchView.swift](../../apple/Sources/SideB/Views/Search/SearchView.swift):546–747 distingue hero de colección/canción/video/artista. Colecciones y canciones reutilizan MediaArtworkControls con actividad, pausa, carga y acciones; los créditos pueden navegar a artista/álbum. [SearchView.svelte](../src/lib/components/search/SearchView.svelte):197–216 compone imagen y botones independientes. El botón de canción dice y dibuja siempre Reproducir; colecciones no tienen ese overlay común y video no tiene ese botón explícito. Video **sí puede reproducirse** por `openCard`; no se afirma que sea inaccesible. Los créditos del hero son texto plano y el menú se accede por contexto, sin el mismo disparador de puntos.

Objetivo: HeroCard con variantes y el mismo controlador de actividad que las demás cartas, conservando abrir detalle vs reproducir como acciones distintas. PAR-014-2 / PAR-009.

### UI-014 — Canciones y videos filtrados usan listas diferentes [P2, confirmado]

Windows usa TrackTable para canciones filtradas y SearchSongRow para videos (SearchView:246–247). Mac usa NativeTrackTableView en ambos filtros; las canciones muestran álbum en subtítulo. Windows muestra columna de álbum aparte. [SearchSongRow.svelte](../src/lib/components/search/SearchSongRow.svelte):5–8 declara `showVideo` pero no lo consume; por eso pasar esa prop no introduce un indicador de video.

Objetivo: misma variante de fila de búsqueda, con contrato de metadata/kind/duración explícito. La actividad de SearchSongRow proviene de los componentes comunes; no se declara rota porque sus props antiguas no se desestructuren. PAR-014-2 / PAR-012-2.

### UI-015 — Spotlight/resultados rápidos pierden información por usar carta genérica [P2, confirmado]

Los límites sí coinciden: Spotlight 5 artistas/8 canciones/5 álbumes/5 playlists; desplegable 2/3/2/2, debounce 250 ms. Apple [QuickResultComponents.swift](../../apple/Sources/SideB/Views/Search/QuickResultComponents.swift) muestra tipo de resultado, duración de canción y variantes de arte 38/48. [QuickResults.svelte](../src/lib/components/search/QuickResults.svelte):19–21 usa MediaCard compacta con arte 40 y no añade tipo/duración equivalentes.

Objetivo: variante QuickResult con esos datos y contrato común de abrir/reproducir. Conservar foco inicial, Escape y devolución de foco: Windows ya implementa esos mecanismos en Spotlight. PAR-014-2.

### UI-016 — Tres rutas de creación no comparten el mismo editor [P1, confirmado]

Mac conecta el `+` de [SidebarView.swift](../../apple/Sources/SideB/Views/Sidebar/SidebarView.swift):159–170 y crear desde Biblioteca al mismo [PlaylistEditorSheet.swift](../../apple/Sources/SideB/Views/Detail/PlaylistEditorSheet.swift), presentado en SideBApp:505, con título/descripción/privacidad. Windows no tiene ese `+` en [Sidebar.svelte](../src/lib/components/sidebar/Sidebar.svelte):181–195. Biblioteca usa formulario propio: descripción de 500 caracteres y creación privada. [PlaylistEditorDialog.svelte](../src/lib/components/detail/PlaylistEditorDialog.svelte) ya admite 5000 y PRIVATE/UNLISTED/PUBLIC, pero la creación nueva de la raíz sólo lo monta al crear desde una canción; `createPlaylistFromSong` necesita esa canción (+page:720–724 y 976–977).

Objetivo: editor único para crear desde Sidebar/Biblioteca/menú de canción y editar, con entrada de canción opcional, privacidad y errores consistentes. No limitar el editor existente al formulario reducido. PAR-015-2.

## Reproductor, fullscreen y letras

### UI-017 — Créditos de la cola no navegan como en Mac [P1, confirmado]

[QueuePanel.svelte](../src/lib/components/fullscreen/QueuePanel.svelte):140–143 coloca ArtistCredits dentro del botón de selección y no le pasa IDs/callbacks de navegación; pulsar esa región activa la fila. Mac pasa Router a NativeTrackTableView en FullscreenNowPlayingView.swift:538–543 y enlaza artista/álbum cuando hay IDs (NativeTrackTableView:529–534).

Objetivo: enlaces independientes y espacio restante con activación de fila; conservar `entryId`, selección actual y reordenamiento. Los botones inline de Like/Dislike de la cola Windows también son una composición distinta: Mac recibe callbacks en su lista, pero no se encontró render de botones inline equivalentes allí. No inventar que Mac muestra todos esos botones. PAR-012-2 / PAR-016-2.

### UI-018 — Genius y reverso informativo de la portada ausentes [P1, confirmado]

[PlayerBar.svelte](../src/lib/components/player/PlayerBar.svelte):238 deshabilita explícitamente Genius; Windows no monta equivalente de [GeniusPanelView.swift](../../apple/Sources/SideB/Views/Fullscreen/GeniusPanelView.swift) ni su view model. Mac tiene letras/anotaciones, acciones de coincidencia y reverso informativo de portada (FullscreenNowPlayingView.swift:185–280). Es un faltante funcional considerable, separado de radios/CSS y de letras sincronizadas normales.

Objetivo: tarea de integración Windows por fases, aprovechando contratos existentes sólo después de revisar su exposición nativa. Esta auditoría no modifica core ni presupone que toda la integración pueda hacerse únicamente en Svelte. PAR-016-2.

### UI-019 — Atajo global de reproducción con Space [P1, ausencia por código; runtime pendiente]

Mac instala [PlaybackSpaceShortcut.swift](../../apple/Sources/SideB/Services/Player/PlaybackSpaceShortcut.swift):28–46 desde SideBApp:61 y respeta edición de texto y controles nativos. Windows maneja Escape/F11/Alt-flechas/Ctrl-K en +page:361–384; no se encontró un equivalente global en fuentes de frontend/runtime. Space sobre un botón enfocado puede activarlo por comportamiento nativo del navegador: eso no es un atajo global de reproducción.

Objetivo: toggle global con exclusiones de inputs, botones, menús, diálogos y regiones que usan Space para lectura/scroll. Confirmar WebView2 antes del cierre. PAR-016-2.

### UI-020 — Adaptación de la barra a ventanas pequeñas [P2, riesgo por verificar]

Ambas parten de barra flotante de 74 y máximo 820, seek, shuffle/repeat, volumen y paneles. Mac [PlayerBarView.swift](../../apple/Sources/SideB/Views/Components/PlayerBarView.swift):27 cambia composición bajo 760. Windows PlayerBar:372 fija columnas `208px minmax(0, 1fr) 16px 232px`, sin rama equivalente por ancho. Eso crea riesgo de compresión de controles; no se reprodujo desborde en una ventana nativa durante esta auditoría.

Objetivo: fixture de barra/ventana estrecha y variante compacta según espacio disponible de contenido. PAR-016-2.

### UI-021 — Fullscreen tiene base común, pero tipografía no adaptable equivalente [P2, confirmado]

Ambas usan reservas base de 52 arriba/112 abajo y región de metadata de 68. Mac [FullscreenSceneLayout.swift](../../apple/Sources/SideB/Views/Fullscreen/FullscreenSceneLayout.swift):31 interpola título 21–28, subtítulo 14.5–17.5 y acciones según arte/ancho; [FullscreenNowPlaying.svelte](../src/lib/components/fullscreen/FullscreenNowPlaying.svelte):193–195 fija título 28/subtítulo 17.5. El cálculo de límite de arte y algunos blancos de controles también difieren.

Objetivo: adaptar métricas a espacio real sin copiar transacciones SwiftUI ni reactivar la transición de sidebar excluida (PAR-008). No se concluye que todas las diferencias de límites de arte sean errores: requieren ventanas equivalentes. PAR-016-2.

### UI-022 — Recomendaciones usan otra densidad de fila [P2, confirmado]

[RecommendedPanel.svelte](../src/lib/components/fullscreen/RecommendedPanel.svelte) usa MediaCard compacta de altura 56; Apple [RecommendedContentView.swift](../../apple/Sources/SideB/Views/Fullscreen/Recommended/RecommendedContentView.swift) compone filas con arte 44 y otra densidad tipográfica/enlaces. Ambas tienen fuentes de artista/álbum/similares/relacionadas y actualización. No se encontró un selector de categorías Mac que falte portar aquí.

Objetivo: variante compacta de recomendaciones con medidas y metadata de su contexto. PAR-017-2.

### UI-023 — Letras sincronizadas: lógica cercana y mejoras Windows que conservar [P3, confirmado]

[lyrics.ts](../src/lib/player/lyrics.ts):15–36 replica selección de línea activa incluso con timestamps desordenados y limita seek a duración, como LyricTiming en FullscreenNowPlayingView.swift:652–668. [LyricsPanel.svelte](../src/lib/components/fullscreen/LyricsPanel.svelte) y SyncedLyricsPanel comparten fuente 25.2, espacios 20, escala 1.025, opacidades 1/.60/.36, seguimiento centrado, pausa por scroll y Volver a la letra actual; contemplan Reduce Motion. Windows añade fuente del proveedor, error y reintento visibles; la vista Mac de letras normales sólo muestra carga/letra/vacío.

Conservar recuperación Windows al definir el contrato. Igualar presentación no implica retirar estados útiles. Este contraste no valida timing/audio/scroll nativos con una pista real. PAR-016-2.

## Cartas, sistema visual y arquitectura transversal

### UI-024 — Tipo visible en cartas de Inicio y variantes de metadata [P2, confirmado]

Las selecciones/páginas/configuración principales ya están auditadas en AUDIT-001 y FIX-114-2 a FIX-116-2. En cartas ordinarias grandes, [HomeFeedCollectionView.swift](../../apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift):1187 muestra tipo de contenido junto a metadata/badge. [MediaCard.svelte](../src/lib/components/common/MediaCard.svelte):23 tiene etiqueta para featured, pero la variante vertical general no compone esa línea de tipo equivalente.

Objetivo: contrato por variante de carta: etiqueta, título, artista/enlaces, subtítulo y resumen opcionales según contexto. No asumir que la corrección de destacados de FIX-115-2 cubrió todas las cartas ordinarias. PAR-009 / PAR-017-2.

### UI-025 — Geometría dispersa pese a colores compartidos [P1 para la base; valores confirmados]

Mac centraliza radios de arte 2/5/8 en AppTheme. Windows tiene tokens de cartas 12/compactas 8, MediaArtwork 10, miniaturas 6, tiles destacados 5, hero de detalle 10 y otros valores por pantalla. Algunos tokens de Inicio no gobiernan la carta común que finalmente se renderiza. Los colores base/acento sí coinciden (`#1b1b1e`, `#24242a`, `#a33d45`, `#d06c70`); no hay que rehacer la paleta.

Objetivo: tabla semántica de geometría por variante y tokens efectivamente consumidos; tamaños de control/título/arte deben cambiar juntos. La E negra 14×14 de FIX-116-2 es una elección explícita del usuario para Windows: conservarla aunque Apple use otros colores. PAR-017-2.

### UI-026 — Imágenes sin estrategia común equivalente por contexto [P2, estructura confirmada; coste por medir]

Apple usa [CachedAsyncImage.swift](../../apple/Sources/SideB/Views/Common/CachedAsyncImage.swift), ImageURLHelper/targetSize y carga cancelable. Windows usa `img`/lazy/fallback en varias superficies; el helper [artwork.ts](../src/lib/images/artwork.ts) optimiza candidatos para fullscreen, pero no gobierna todas las cartas/tablas/detalles. El navegador tiene caché; no se afirma que Windows descargue todo repetidamente ni carezca de caché.

Objetivo: componente/servicio de arte que resuelva tamaño por contexto, placeholders y errores; revisar cancelar trabajo según visibilidad y medir descarga/decodificación antes de cambios extensos. PAR-017-2.

### UI-027 — Iconos tipográficos restantes [P2, confirmado]

FIX-116-2 unificó puntos y E con SVG. Aún hay Play, refresh, notas, flechas y cerrar escritos como glifos en varias superficies, junto con PlayerIcon/SidebarIcon/MenuIcon. Apple usa nombres SF Symbols y geometrías controladas. La línea base y forma dependen de fuente, lo que favorece nuevos descentrados incluso con el mismo rectángulo de botón.

Objetivo: una familia SVG Windows por nombre/rol semántico y cajas comunes, no copiar SF Symbols como assets. Mantener nombres accesibles y blancos de clic. PAR-017-2.

### UI-028 — Estados y diálogos con infraestructura repetida [P2, confirmado; accesibilidad por verificar]

Windows combina dialog nativo HTML, modales con foco manual y helpers repetidos; algunos buscan botones de `[role=dialog]` globalmente. Mac usa sheets/popovers nativos y algunos estados compartidos de detalle. Windows ya tiene gestión de Escape/foco en menús y Spotlight: no se declara que falte todo el teclado ni que esos modales sean inaccesibles.

Objetivo: helpers de modal y estados carga/vacío/error/reintento reutilizables, consulta de foco acotada al modal, conservación del foco originario y comportamiento consistente durante acciones pendientes. Confirmar teclado/lector de pantalla en WebView2; la etiqueta ARIA por sí sola no es evidencia de comportamiento. PAR-017-2.

### UI-029 — Menús: base compartida, terminología y disponibilidad por aclarar [P3, confirmado]

Policy/ejecutor centralizados cubren play/radio/cola/like/biblioteca/playlist/artista/álbum/compartir/editar/eliminar/orden. No se halló motivo para duplicarlos al refactorizar filas. Hay etiquetas distintas entre plataformas y una disponibilidad de radio de artista distinta: Apple inicia mix desde el artista; Windows requiere datos de playlist en la política de ese target. No se probó esa diferencia con un perfil real, por lo que requiere fixture y decisión antes de llamarla regresión.

Objetivo: catálogo semántico de acciones/etiquetas/condiciones, con ejecutores nativos conservados. ContextMenu Windows ya tiene navegación por flechas, Home/End/Escape y submenús. PAR-013-2 / PAR-017-2.

### UI-030 — Navegación, cuenta y actualización: diferencias que no deben borrarse automáticamente [P3]

Windows NavigationHistory guarda hasta 40 snapshots con scroll/estado; Apple Router conserva historial de destinos con otro modelo. No retirar restauración Windows para igualar un detalle de implementación. Definir comportamiento al volver y disponibilidad Atrás/Adelante por destino.

Ambas exponen perfil/sesión/cierre; Windows coloca Buscar actualizaciones en popover de cuenta como adaptación a su shell. Apple muestra email o handle; Windows usa email o fallback. UpdateModal comparte estados principales de actualización, pero Windows presenta notas con `pre` y Apple Markdown/LocalizedStringKey; no se validaron contenido, instalación ni actualización real. Login y almacenamiento nativos requieren conservar sus adaptadores de plataforma.

Objetivo: mismas funciones y estados visibles donde corresponda, con controles de ventana/cuenta propios de cada SO. PAR-017-2; la ubicación de actualización es una adaptación documentada, no un faltante.

## Diferencias conocidas y decisiones conservadas

| Punto | Decisión / estado |
|---|---|
| Sidebar Windows permanente expandida/compacta; ausencia del selector TopNav Mac | Decisión del usuario. No portar ocultamiento total ni selector superior. PAR-007 continúa excluido. |
| Continuidad de fondo/transición fullscreen ligada a sidebar Mac | PAR-008 excluido del pedido anterior; no se reabre por esta auditoría. Las funciones de Genius/cola/teclado siguen siendo comparables. |
| AirPlay y efectos nativos | Picker AirPlay de Mac depende de su plataforma. No exigir la misma implementación en Windows; documentar capacidades reales. Glass/blur/transparencia pueden usar otro renderer con legibilidad equivalente. |
| E negra | Elección explícita Windows en FIX-116-2; conservar tamaño/centrado y colores solicitados. |
| Playback de playlist sin esperar catálogo completo | PAR-010 ya pendiente: +page:563–574 espera resolvePlaylistTracks; Apple puede iniciar desde cargados y continuar en segundo plano. No atribuirlo al encabezado o al layout. |
| Snapshots de chip/hidratación de feed | PAR-011-2 ya pendiente. Es estado/caché de Inicio, separado de cartas, canvas y cabecera. |
| Reintento/error/fuente en letras normales y snapshots de navegación Windows | Capacidades útiles Windows. Mantenerlas al acercar la UI y evaluar si también convienen en Mac. |

## Contratos sugeridos para implementar después

Una UI cercana no necesita dos árboles idénticos ni transportar código SwiftUI a Svelte. Necesita que una función nueva tenga un lugar equivalente donde implementarse y criterios verificables:

| Contrato lógico | Datos y variantes | Comportamiento que debe quedar fijo |
|---|---|---|
| TrackList / TrackRow | Contexto, ocurrencia/source, índice, arte, álbum `none/inline/column`, duración, tipo, acciones permitidas y edición | Play sobre arte, estado de origen, clic de fila, enlaces independientes, selección/foco, menú, reordenamiento, viewport/continuación. |
| MediaCard / Hero / QuickResult | Kind, variante, etiqueta, título, créditos enlazables, resumen, loading y actividad | Carta abre o reproduce según kind; Play de colección no se confunde con abrir; pausa/reanuda origen activo; menú no reproduce. |
| DetailHeader / DetailState | Tipo, arte, título/subtítulo/resumen/contador/descripción, acciones y estado | Geometría/líneas constantes por ancho, metadata completa, errores recuperables, navegación sin controles duplicados accidentales. |
| PlaylistEditor | Crear/editar, canción inicial opcional, privacidad y errores | Todos los puntos de entrada usan campos/límites/validación iguales; cancelar y retry no crean playlists duplicadas. |
| Player / FullscreenPanel | Ancho de contenido, track/generation, panel, capacidades nativas | Barra compacta, atajos respetando controles, créditos enlazables, estados de letras/Genius, autoridad nativa de cola. |
| UI tokens / Artwork / Icon / Modal | Roles y variantes explícitas | Geometría efectiva, imágenes del tamaño necesario, iconos centrados, foco y accesibilidad coherentes. |

Estos son contratos de UI y pruebas de presentación. No requieren meter estado visual en `core/`, sincronizar preferencias de cuentas entre SO ni crear una segunda cola. Documentar primero valores/variantes realmente usados y mantener adapters de plataforma. Comparar las pantallas con el mismo fixture: una lista de títulos largos, múltiples artistas, video, falta de arte/IDs, playlist propia/ajena, ocurrencias repetidas y estados de actividad/carga/error.

## Orden de trabajo recomendado

1. **Listas comunes — PAR-012-2:** unificar contrato/adaptadores; retirar encabezados visibles, revisar 200 px de acciones, miniatura/Play, columnas, actividad y secciones. Añadir virtualización según mediciones sin perder gestos/ocurrencias.
2. **Búsqueda — PAR-014-2:** hero conectado a controles comunes, filas canción/video y QuickResult con tipo/duración. Reutilizar la base de la tanda anterior.
3. **Crear playlists y detalles — PAR-015-2 / PAR-013-2:** editor único, `+` de Sidebar, metadata, orden y continuación por contexto; comprobar Artist/Ver todo. PAR-010 mantiene su tarea de integración de playback propia.
4. **Sistema visual — PAR-017-2 / PAR-009:** variantes/tokens de cartas y cabeceras, imágenes/iconos/estados/modales. Las medidas se validan en WebView2 a anchos/DPI equivalentes.
5. **Reproductor — PAR-016-2:** atajo Space, créditos de cola y adaptación compacta; después Genius/reverso informativo como port funcional de mayor tamaño. PAR-011-2 conserva su seguimiento de estado persistente de Inicio.

Este orden es una propuesta de implementación posterior, no autorización inferida para cambiar la UI durante el pedido de análisis. Los hallazgos pendientes se siguen en PARIDAD; este informe conserva evidencia de la auditoría y no duplica su estado.

## Revisión y cierre

- [x] Leer instrucciones, antecedentes relevantes y estado Git; conservar cambios existentes.
- [x] Comparar listas, playlists, álbumes, Biblioteca e Historial.
- [x] Comparar búsqueda/Spotlight, artista/catálogos, Inicio, shell, reproductor/fullscreen y letras.
- [x] Contrastar arquitectura, estados, navegación, menús, accesibilidad y riesgos de recursos por código.
- [x] Escribir evidencia, prioridades, adaptaciones y límites; enlazar PAR-012-2 a PAR-017-2 y registrar FIX-117-2.

Validación de esta entrega: referencias locales y anchors nuevos comprobados, documentos revisados y diff sin errores de whitespace. No se ejecutan pruebas de aplicación por un cambio exclusivamente documental. Implementación, comparación visual nativa y rendimiento quedan pendientes; ninguna fila de paridad se cierra por este informe.

## Implementación posterior — 2026-10-05

El pedido posterior del usuario autoriza [PLAN-002](PLAN-002-ui-lists-shell.md), implementado en FIX-118-2 a FIX-122-2: shell/Home/sidebar, base de listas/Historial, playlist/Biblioteca/editor, cola, Space y overlay de portada. Este informe conserva la evidencia del estado auditado antes de esos cambios. [PARIDAD](../../PARIDAD.md) lleva el estado vigente; no todos los30puntos quedan implementados. Validación de esta tanda:167frontend, check/build y browser con fixtures; nativo/cuenta/audio/rendimiento pendientes.
