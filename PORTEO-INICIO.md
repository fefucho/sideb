# Guía de porteo Mac → Windows: barra superior e Inicio personalizado

Especificación consolidada para trasladar a Windows (`windows/`, Svelte + Tauri) lo construido en macOS (`apple/`, SwiftUI + AppKit). Resume contratos, reglas, constantes y textos que hoy están repartidos en los planes y en `FIXES.md`. Si algo difiere de aquellos, manda el código Apple citado. Estado y seguimiento: [PARIDAD.md](PARIDAD.md) (PAR-001 a PAR-010; auditoría FIX-110, cartas comunes FIX-111 y correcciones FIX-112).

> Convención: «Apple» = referencia ya implementada. «Windows» = qué falta o qué adaptar. Rutas de Apple relativas a `apple/Sources/SideB/`.

Actualización de alcance 2026-10-09: el [checklist integral Windows](windows/plans/PLAN-001-feature-parity.md) cubre también detalles, Explorar, Genius, traducciones, reproducción e integración del sistema; [PARIDAD](PARIDAD.md) conserva su estado. Explorar está habilitado en Apple desde FIX-120; la auditoría de hoy no ejecutó runtime nativo Windows.

## 0. Qué se porta y qué no

| Se porta (comportamiento) | No se porta (específico de macOS) |
|---|---|
| Reglas de selección de destacados, fuentes, categorías, persistencia, textos | `NSSegmentedControl`, `NSGlassEffectView`, toolbar nativa, conversión de coordenadas de ventana (FIX-090, 095, 102, 103, 107 en lo AppKit) |
| Geometría lógica, continuidad del fondo de fullscreen y movimiento coherente con sidebar | Implementación de zIndex/transacciones y transición SwiftUI (FIX-091 a 095); reproducir el resultado con CSS/Tauri |
| Fondo de portadas con humo animado | `TimelineView`, `ImageRenderer` (usar CSS/canvas) |

Los datos iniciales no requieren cambios en core Rust ni contratos UniFFI: todo usa `HomeSectionRecord`, `HomeItemRecord`, `BrowseCardRecord` y `HistoryGroupRecord` existentes. Auditar que el adaptador Tauri/DTO y los tipos TypeScript expongan lo necesario; si un campo del contrato existente falta en el DTO, ampliar adaptador y consumidor juntos, sin inventarlo ni modificar el core por una necesidad de UI.

## 1. Barra superior

Fuentes: `Views/Components/TopNavigationView.swift`, `WindowNavigationToolbarView.swift`, `HistoryToolbarView.swift`, `UI/ShellLayout.swift` · FIX-090, FIX-107 · PLAN-002.

**Selector principal** (cápsula de vidrio): 4 segmentos de icono, ancho preferido 262 pt, relleno interno 3 pt, forma de cápsula (radio = altura/2).

| # | Título | Icono (SF Symbol) | Estado |
|---|---|---|---|
| 0 | Inicio | `house` | activo |
| 1 | Explorar | `sparkles` | activo desde FIX-120; subrutas/categorías/rankings en PAR-012 |
| 2 | Biblioteca | `books.vertical` | activo |
| 3 | Buscar | `magnifyingglass` | activo |

- Los cuatro segmentos emiten sus acciones vigentes. Etiqueta accesible: «Navegación principal».
- Con Reduce Transparency el vidrio pasa a fondo sólido de ventana.
- **Entrada/salida**: al abrir la sidebar el selector sale por arriba hasta superar el borde de la ventana (distancia = centro de la fila 28 pt + media altura + 8 pt) con el mismo progreso y duración (0,42 s suave) que la sidebar. Reduce Motion: un único fade corto (0,12 s). Mientras sale, está sin interacción (solo es interactivo con progreso > 0,95).
- Centrado: el icono queda centrado dentro de la cápsula tras cada layout (el bug de FIX-090 era una altura fija de 28 pt frente a 34 pt reales).

**Grupo de acciones** (cápsula propia, separada del selector; la posición exacta respecto del selector la resuelve `ShellLayout.navigationFrames`): Atrás/Adelante según disponibilidad del historial. Actualizar y el engranaje de Configuración aparecen sólo cuando Inicio es interactivo; se ocultan en otras páginas o mientras fullscreen/buscador deshabilitan la navegación.
- El engranaje usa el mismo tamaño/estilo que Actualizar, va después de Adelante, está habilitado solo si Inicio es interactivo, y refleja si el panel está abierto o cerrado.
- **El grupo se centra siempre sobre la ubicación del panel de configuración**, esté abierto o cerrado (FIX-107): usa el ancho real del panel (`homeSettingsWidth` = 292 pt) y resuelve colisiones con el selector. Abrir o cerrar el panel no lo mueve.
- Ancho mínimo de la barra: 420 pt. Verificar sidebar abierta/cerrada y ventana mínima.

### Fullscreen y sidebar: resultado visible (PAR-008)

Fuentes: `SideBApp.swift`, `Views/Fullscreen/FullscreenBackdrop.swift`, `FullscreenNowPlayingView.swift`, `Views/Fullscreen/FullscreenSceneLayout.swift` · FIX-091–095 · PLAN-003. La referencia final es FIX-095; los intentos 091–094 y sus fallos quedan como antecedentes, no implementaciones a reproducir.

- Backdrop fijo cubre toda la ventana, también detrás de la sidebar. Entrar/salir de fullscreen atenúa el mismo plano en todo el ancho; la página debajo no agrega un segundo oscurecimiento sólo en la columna de contenido.
- Foreground de reproducción separado del backdrop; sidebar/player/buscador quedan por encima. Al alternar sidebar, portada, metadata y paneles usan la misma geometría continua, sin saltos de tipografía ni recortes. Player y buscador mantienen reserva/centrado coherentes.
- Navegación inferior no intercepta input en fullscreen; los controles visibles conservan foco, acciones y accesibilidad. No reconstruir todas las páginas ocultas para lograr el fade.
- Windows actual: `FullscreenNowPlaying.svelte` tiene `inset: 0 0 0 var(--sidebar-width)` y su backdrop está dentro; `+page.svelte` monta fullscreen condicionalmente. El fondo aún no abarca la sidebar. Adaptar composición/transiciones CSS/Tauri y conservar botones de ventana/región de arrastre; no copiar APIs, zIndex numéricos ni hosts AppKit.

## 2. Panel «Configuración de Inicio»

Fuentes: `Views/Home/HomeSettingsPanel.swift`, `Models/HomeRecommendationSettings.swift` · FIX-105, FIX-106 · PLAN-006, PLAN-007.

**Comportamiento del contenedor**
- Panel lateral **derecho, superpuesto** (292 pt): no desplaza ni achica Inicio, no cambia el centrado del reproductor, queda por debajo de fullscreen y no colapsa la sidebar izquierda.
- Se cierra con el botón Cerrar, con Escape (también con el foco en lista o selector), al salir de Inicio, al abrir el buscador, en fullscreen y al cambiar de sesión. **No se reabre solo** al volver.
- Cabecera fija: título «Configuración de Inicio» + botón Cerrar en la misma fila, a 16 pt bajo el borde inferior real del grupo de acciones. Contenido desplazable debajo (no montar miles de filas: limitar al viewport).
- Material, márgenes y radio coherentes con la sidebar izquierda. Respeta Reduce Motion y Reduce Transparency.

**Apartado «Destacados»**
- Selector «Álbumes / Playlists» (predeterminado Álbumes). Persistido entre ejecuciones. Cambiarlo reconstruye la proyección con lo ya cargado: **sin red, sin perder cursor, filtros ni feed**.
- Texto de ayuda: «Las fuentes se usan de arriba abajo, hasta completar un máximo de seis páginas.»
- Lista de fuentes del tipo elegido: cada fila = casilla (Toggle) + título + flechas Subir/Bajar + asa de arrastre. Guardar **una vez al soltar**, no por movimiento del puntero. Accesibilidad: «Arrastrar para ordenar X; también podés usar Subir y Bajar».
- Sin fuentes activas: «Activá una fuente para mostrar destacados de este tipo.» (no activar nada a escondidas ni reemplazar playlists por álbumes).
- Error de biblioteca: «No se pudo actualizar la biblioteca.» + botón «Reintentar biblioteca». Botón «Restaurar fuentes».

**Apartado «Categorías de Inicio»**
- Ayuda: «Ocultar un estante no impide que su fuente aporte destacados.»
- Lista de categorías realmente recibidas (incluidas las que quedaron sin estante porque sus items pasaron a destacados): casilla «Mostrar», título, Subir/Bajar, asa. Buscador de texto cuando hay más de ocho categorías (insensible a mayúsculas/acentos) y vacíos: «Las categorías aparecerán cuando cargue Inicio.» / «No hay categorías con ese nombre.»
- Botones: «Mostrar todas las categorías», «Usar orden de YouTube», «Restaurar orden de Side B».
- Las categorías son dinámicas: salen de los registros del feed/contexto actual. Al refrescar, las que ya no llegan salen de esta lista; las nuevas aparecen activadas salvo que su clave ya tenga una preferencia de ocultamiento. En orden personalizado entran al final, en orden recibido. Cargar más agrega registros; no elimina los anteriores.
- Las claves ausentes permanecen en `categoryOrder`/`hiddenCategoryKeys` para una eventual reaparición. **Límite actual:** al reordenar mientras faltan categorías, se ordenan las presentes y se anexan las ausentes al final; no se garantiza su posición original. Restaurar orden cambia de modo y limpia `categoryOrder`; mostrar todas limpia ocultamiento.
- **Quick picks:** sus canciones se priorizan para Speed Dial y se excluyen del estante. Puede quedar sin estante aunque su casilla esté marcada; esa casilla no apaga Speed Dial. No presentar como implementado un interruptor independiente de Speed Dial.
- Space activa el control que tiene foco (casilla/botón/selector); no disparar reproducción global al operar configuración. Fuera de esos controles se conserva el atajo de reproducción por ventana. Referencia: `PlaybackSpaceShortcutTests`.

## 3. Modelo de configuración y persistencia

```text
HomeRecommendationSettings (versión 1)
  albumSources:    [ {source, enabled} ]   // orden = prioridad
  playlistSources: [ {source, enabled} ]
  categoryOrderMode: "sideB" | "youtube" | "custom"
  categoryOrder:     [categoryKey]          // solo en modo custom
  hiddenCategoryKeys:[categoryKey]
```

- **Clave de almacenamiento por cuenta**: `sideb.home.recommendations.v1.<sha256(identidad de sesión)>` (JSON). Preferencia Álbumes/Playlists: `sideb.home.featuredCollectionKind` (`albums` | `playlists`), global. En Windows usar su almacenamiento local equivalente conservando las claves lógicas.
- Decodificar: `version` ausente → 0; `version` mayor que la actual → defaults. Campos ausentes → defaults. Se descartan fuentes no permitidas para el tipo y duplicadas (se conserva la primera).
- Cambiar de cuenta/sesión **purga** candidatos, metadata y respuestas pendientes; nunca mostrar datos de la cuenta anterior.
- No persistir IDs de fila, primer/último item ni tokens de continuación.

**Fuentes por defecto y disponibles**

| Fuente (`source`) | Título en UI | Álbumes | Playlists | Activa por defecto |
|---|---|:-:|:-:|:-:|
| `recommendedAlbums` | Recomendados para vos | sí | | sí |
| `mixesForYou` | Mixes para vos | | sí | sí |
| `listenAgain` | Volver a escuchar | sí | sí | sí |
| `forgottenFavorites` | Favoritos olvidados | sí | sí | sí |
| `fromLibrary` | De tu biblioteca en Inicio | sí | sí | sí |
| `newReleases` | Nuevos lanzamientos | sí | | sí |
| `fromCommunity` | De la comunidad | | sí | sí |
| `otherHome` | Otros del Inicio | sí | sí | sí |
| `libraryAlbums` | Álbumes guardados | sí | | **no** (suplementaria) |
| `recentAlbums` | De tus escuchas recientes | sí | | **no** (suplementaria) |
| `libraryPlaylists` | Playlists guardadas | | sí | **no** (suplementaria) |

Orden por defecto: el de las filas de la tabla (álbumes: recommended, listenAgain, forgottenFavorites, fromLibrary, newReleases, otherHome, libraryAlbums, recentAlbums; playlists: mixesForYou, listenAgain, forgottenFavorites, fromLibrary, fromCommunity, otherHome, libraryPlaylists).

**Claves de categoría** (`categoryKey(título)`): normalizar (recortar, ignorar mayúsculas y acentos) y buscar alias; si no hay alias → `custom:<título normalizado>`. Alias (inglés/español):
- `quick-picks`: quick picks, selecciones rápidas
- `speed-dial`: speed dial, marcación rápida
- `recommended-albums`: albums for you, álbumes para ti, recommended albums, álbumes recomendados
- `mixes-for-you`: mixed for you, mixes for you, your mixes, personalized mixes, mixes para ti, tus mixes, mixes personalizados, hecho para ti
- `listen-again`: listen again, vuelve a escucharlo, volver a escuchar, escuchar de nuevo
- `new-releases`: new releases, nuevos lanzamientos, lanzamientos nuevos
- `forgotten-favorites`: forgotten favorites/favourites, favoritos olvidados
- `from-library`: from your library, de tu biblioteca, de la biblioteca
- `from-community`: from the community, de la comunidad, de la comunidad de youtube music

Categorías con el mismo título forman un grupo y conservan su orden interno. Si un título desconocido cambia, la preferencia puede no aplicar (límite conocido, el contrato no tiene ID semántico).

## 4. Algoritmo de destacados (álbumes / playlists)

Fuentes: `Models/HomeFeaturedPresentation.swift`, `Models/HomeFeedPresentation.swift`, `ViewModels/HomeViewModel.swift`.

Cadena: **datos crudos → clasificar categorías → candidatos por fuentes activas → selección por capacidad → estantes (orden y visibilidad) → excluir solo destacados expuestos**.

1. **Capacidad**: 2, 4 o 6 colecciones por página según columnas (1/2/3). Máximo **6 páginas** → límite `6 × capacidad` = 12 / 24 / 36. Solo cambia al cruzar 2/4/6, no en cada píxel de redimensionado. Sin páginas vacías ni duplicados de relleno.
2. **Selección** (prioridad estricta): recorrer las fuentes **activas de arriba abajo**; cada una aporta candidatos en el orden interno del feed, filtrando por tipo (`album` o `playlist`); deduplicar por ID canónico; parar al llegar al límite. La primera fuente puede llenar las seis páginas. Una colección repetida en dos fuentes se adjudica a la primera.
   - Las fuentes del feed se resuelven con `source(forTitle:)`: la categoría se clasifica por su clave; todo lo no reconocido es `otherHome`. «Otros del Inicio» **no** reabsorbe familias conocidas aunque estén desactivadas.
   - Las fuentes suplementarias leen listas ya cargadas, sin pedir catálogos: `libraryAlbums` = álbumes de la biblioteca; `libraryPlaylists` = playlists de la biblioteca; `recentAlbums` = álbumes con `albumId` real del historial, deduplicados, tomando la portada de la biblioteca si existe (si no, sin miniatura de video).
3. **ID canónico**: recortar espacios; en playlists, `LM` y `VLLM` → `LM`, y se quita el prefijo `VL`. Clave de dedupe `"<tipo>|<idCanónico>"`.
4. **Speed Dial (canciones)**: hasta 27 canciones (3 páginas de 9), tomadas por prioridad de categoría (Speed Dial / Quick Picks primero), sin repetir ID.
5. **Estantes restantes**: aplicar orden y visibilidad de categorías; quitar de cada estante los items ya destacados (colecciones y canciones); descartar estantes que queden vacíos. **Ocultar una categoría solo oculta su estante**: puede seguir aportando destacados si su fuente está activa.
6. **Orden de categorías**: `sideB` = prioridades fijas actuales (Volver a escuchar 0, Favoritos olvidados 1, Álbumes para ti 2, De tu biblioteca 3, Quick Picks 5, resto 6; desempate por orden recibido); `youtube` = orden crudo del proveedor; `custom` = según `categoryOrder`, y las categorías nuevas van **al final en orden de llegada**; nunca se reactivan ocultas al refrescar o cargar más.
   - Límite actual de aliases: `categoryKey` ignora mayúsculas/tildes, pero `HomePresentationFactory.sectionPriority/style` conserva sus listas propias y sólo recorta/convierte a minúsculas. «recommended albums»/mixes no heredan automáticamente prioridad de «Albums for you» en modo Side B. La unificación propuesta en PLAN-008 todavía no se implementó; conservar el comportamiento actual hasta una decisión registrada.
7. **Si no hay candidatos suficientes** se muestran las páginas disponibles; no recorrer continuaciones de YouTube para completar seis. «Cargar más» puede incorporar nuevos registros (ver PAR-005).
8. **Ambiente**: se usan hasta 4 portadas únicas (primero 2 de colecciones, luego 2 de canciones, luego el resto).

**Metadata de tarjetas** (créditos, resumen, duración): solo para la página visible; máximo **2 solicitudes simultáneas** por modelo, incluso con páginas superpuestas; caché LRU de 6; playlists consultan solo su primera página; el catálogo completo se pide **solo al reproducir/aleatorio**. Cancelación y generación protegen las respuestas. Sin año ni totales inventados.

### Continuaciones, caché y errores (PAR-005 / FIX-104–106)

- Conservar registros crudos, snapshots por filtro y un coordinador/cursor. Ocultar u ordenar sólo cambia la proyección, sin borrar candidatos ni resetear continuaciones.
- «Cargar más» explícito: exclusión de carga simultánea; hasta tres peticiones por clic atravesando páginas repetidas, vacías o sólo con estantes ocultos. Parar en cambio visible, fin o ciclo de tokens. Deduplicar por firma de sección y descartar respuestas de otra generación/filtro/cuenta.
- Actualizar la revisión sólo si cambian canciones/colecciones/estantes visibles, no por nuevos datos ocultos o procedencia de candidatos. Conservar el token válido ante error; liberar loading al terminar/cancelar y permitir reintento inmediato.
- Pie: «No hay más recomendaciones por ahora.»; «Esta tanda no trajo recomendaciones visibles nuevas. Podés cargar la siguiente.»; error «No se pudieron cargar más recomendaciones. Volvé a intentarlo.» Mantener botón si queda token y pie visible sobre el player.
- Precarga inicial de familias nombradas activas: máximo tres continuaciones y presupuesto de 12 s; no buscar una fuente desactivada ni garantizar seis páginas. Si sólo están activas fuentes suplementarias/«Otros», no perseguir familias nombradas.
- Windows ya tiene generaciones/tokens, `moreError` y `finally`, pero `HomeView.svelte` conserva un IntersectionObserver automático. No confundirlo con el botón explícito de Apple ni declarar trasladado el avance por páginas ocultas sin su prueba.

## 5. Interfaz de Inicio: Speed Dial y destacados

Fuentes: `Views/Home/HomeFeaturedView.swift`, `HomeView.swift` · FIX-098, 099, 100, 062 · PLAN-004.

- **Cabecera personal**: saludo según hora («Buen día» antes de 12, «Buenas tardes» antes de 20, «Buenas noches» después), nombre y avatar reales si están disponibles; avatar 44 pt/imagen de 88 px. Subtítulo «Tu próximo lado B empieza acá» o indicación de activar fuentes cuando todas están apagadas. Estado de carga/error/refresco y chips continúan visibles sin reemplazar un feed ya cargado por tarjetas falsas.
- **Layout ancho** (`ancho de contenido ≥ 900 pt`): Speed Dial a la izquierda, destacados a la derecha. **Estrecho**: apilados con 16 pt.
- Márgenes: horizontal 28 pt; separación entre secciones 24 pt; cabecera 38 pt; hueco contenido 8 pt; pie con paginador 48 pt; separación entre tarjetas verticales 24 pt.
- **Speed Dial**: rejilla de **3 columnas** de baldosas cuadradas (máx. 144 pt en ancho, 140 en estrecho; separación 8 pt), hasta 9 por página y 3 páginas; título de sección «Speed Dial».
- **Destacados**: columnas = mín(3, ⌈tarjetas/2⌉, columnas que caben con ancho mínimo de **432 pt** + 24 pt de separación); 2 tarjetas por columna → capacidad 2/4/6 por página. Altura de tarjeta entre 152 y 212 pt (ajustada a la altura del Speed Dial en layout ancho). Tarjeta = portada cuadrada + título y créditos/resumen; la carta abre el detalle correcto salvo controles/enlaces. Play está abajo a la derecha de la portada; Aleatorio permanece en el menú (FIX-111).
- **Paginador**: chevrones y puntos; conserva la colección visible al redimensionar si sigue dentro de la proyección, si no ajusta a una página válida. Cambiar fuentes/tipo/filtro reinicia el paginado.
- Álbumes sin fondo de tarjeta (FIX-099). Mantener estable al abrir/cerrar la sidebar.
- Solo se montan los controles de la página actual; las demás no consultan detalles ni decodifican portadas por adelantado.
- Estados: sin datos → no mostrar tarjetas falsas; error/reintento y «fin del feed» según PAR-005.

### Acciones, créditos y reproducción (PAR-001 / PAR-003 / PAR-006)

- Speed Dial usa la acción de canción con radio existente; portada/título, créditos reales, menús contextuales y enlaces de álbum/artista conservan sus acciones del feed. Likes y demás funciones secundarias se acceden desde clic derecho o `…`. No derivar IDs desde textos o miniaturas.
- Portada/título de destacado abre el detalle según tipo. Álbumes muestran artista/año/cantidad/duración reales; playlists muestran creador con enlace sólo si hay ID de canal real, cantidad/duración del proveedor o de una página completa. No mostrar una primera página parcial como total ni un año como duración.
- Play / Aleatorio del menú pide el catálogo completo al ejecutar la acción y usa el camino canónico de reproducción. La metadata visible sólo pide la primera página; no confundir ambos caminos ni precargar canciones de las 36 colecciones para configurar Inicio.
- Errores/cancelación/cambio de cuenta/contexto no reemplazan cola ni audio con resultados tardíos. Conservar ocurrencias/anclas de pista, shuffle reversible, orden original y tandas/persistencia de PAR-001 (FIX-097); usar player nativo autoritativo de Windows, sin una segunda cola en UI.
- Mantener menús del tipo correcto, acciones accesibles, enlaces y estado loading del destacado correcto. Referencias de regresión: `HomePlaylistPlaybackTests`, `HomeItemHierarchyTests`, `HomeCollectionPreferenceTests` y `PlaybackSpaceShortcutTests`.

### Cartas comunes en toda la app (PAR-009 / FIX-111)

Fuentes: `Models/MediaPlaybackIdentity.swift`, `Views/Common/MediaArtworkControls.swift`, `NativeTrackTableView.swift`, `HomeFeedCollectionView.swift`, `HomeEqualizerOverlayView.swift`; contrato completo en [PLAN-009](apple/plans/PLAN-009-common-media-cards.md).

- Colecciones: toda la carta abre detalle salvo créditos/controles. Play de 32 pt abajo a la derecha, inset 8 pt, blanco sobre círculo negro de opacidad 0,62; acento rojo sólo al hover del propio Play. Menú `…` arriba a la derecha. Canción: Play centrado. Portadas compactas adaptan medidas sin superponer Play y menú; las filas nativas reservan los puntos al extremo derecho por densidad.
- Play y menú aparecen con hover o foco real de control; la selección persistente de una fila no los mantiene visibles (FIX-112); cargar una colección deshabilita su Play y muestra progreso. Clic derecho y puntos usan las mismas acciones/contexto del menú existente. Retirar controles dedicados de likes, dislike, radio y aleatorio de la tarjeta; conservar sus funciones en el menú cuando están disponibles.
- Toda canción horizontal se activa con un clic sobre portada, título o espacio libre. Artista/álbum navegan sólo con IDs reales; `…` abre sin reproducir. No instalar un gesto padre que propague clicks de botones/enlaces. Cmd/Shift en tabla conserva selección, no dispara audio; conservar teclado y accesibilidad.
- Inicio/Speed Dial identifica la radio por `seedVideoId` del contexto real: las barras permanecen en la carta origen al avanzar. Play/Pausa en ese origen alterna la radio actual sin reiniciar pista, tiempo o cola; otra canción crea su radio. Cambiar contexto retira el indicador anterior. No copiar ese indicador de origen a todas las canciones que coincidan con la pista actual.
- Colección activa: comparar tipo e ID canónico con el contexto de cola (playlist acepta prefijo `VL`); todas sus cartas muestran el mismo estado. Una canción sonando por radio no activa su álbum. Play/Pausa de la colección activa conserva pista/ocurrencia/posición; otra colección carga catálogo canónico en orden. Invalidar respuestas pendientes de otra colección cuando se retoma la fuente activa.
- Barras blancas finas, 5 grandes/4 compactas, alto máximo 34/14 pt, ciclos suaves ~1,48–1,84 s. Hover/foco reemplaza barras por Pausa/Play. Pausa deja barras estáticas tenues (opacidad 0,40). Ocultar/salir de pantalla, ventana inactiva/oculta y reducir movimiento retiran animación; no analizar audio ni crear timers por tarjeta.
- Playlist/Biblioteca/Likeados con pistas ya disponibles (FIX-112 / PAR-010): reproducción normal inicia la ocurrencia elegida antes de esperar todas las continuaciones; completar la fuente en segundo plano sin cambiar audio/actual/IDs/anclas, incluso al avanzar o pausar. Conservar token para reintento si falla; rechazar otras cuentas/colas/solicitudes/contextos. Aleatorio inicial espera toda la fuente.
- Álbum/playlist/Biblioteca/Historial reproduce la lista desde la ocurrencia elegida; cola activa la ocurrencia existente, incluidos duplicados. No identificar una ocurrencia únicamente por videoId. Historial pasa por el player para invalidar cargas previas.
- **Cola especial (FIX-113):** presentación propia como build-0029: título y subtítulo conjunto artista • álbum, Like/Dislike dedicados, Like marcado visible; hover/foco revela acciones y reemplaza duración por grip. Sin Play flotante ni `…` de cartas comunes; conservar menú por clic derecho, selección y reordenamiento por ocurrencia. Windows QueuePanel ya presenta Like/Dislike y grip al hover/foco; verificar destino sin copiar AppKit.
- Aplicar estas reglas a Inicio, destacados, Biblioteca, Buscar/Spotlight, artista/catálogos y recomendaciones fullscreen con componentes propios de Windows; conservar continuaciones, shuffle reversible y player autoritativo. La implementación Apple tiene pruebas automáticas; apariencia/audio/consumo en sesión real y port Windows siguen pendientes.

## 6. Fondo de portadas con humo animado

Fuentes: `Views/Home/HomeAmbientBackground.swift`, `HomeAmbientSurface.swift`, `HomeAmbientSmoke.swift` · FIX-098, 100, 108, 109.

- **Paleta**: hasta 3 tintes por portada (conservar acentos pequeños), 4 portadas de 32×32, muestreo fuera del hilo de UI, caché LRU de 64 entradas, aislada por sesión; transición de color de 1 s.
- **Elección de dos colores**: izquierdo = el de mayor croma; derecho = el más distinto en matiz ponderado por croma. Si ambos son de la misma familia (croma > 0,12 y distancia de matiz < 0,10), el derecho es una contraluz tenue (matiz + 0,44, saturación 0,42, brillo 0,68). Pigmentos oscuros se elevan hasta ~0,80 de brillo manteniendo el matiz; fallback neutro frío (sin sepia).
- **Capas** (de abajo arriba): base grafito `#111318`; 3 radiales con composición *screen* (radios 0,62 / 0,58 / 0,42 del lado mayor, opacidades 0,46 / 0,42 / 0,16); 2 capas de humo; degradado oscuro vertical (0 → 0,08 al 42 % → 0,46 abajo).
- **Humo**: textura de opacidad de 384×256 generada **una sola vez** (ruido fractal con vetas, desvanecida en los bordes y hacia abajo), sin datos de cuenta. Se pinta con un degradado de los dos colores (opacidad 0,29 y 0,25) usando la textura como máscara.
- **Animación (FIX-109)**: dos capas de la misma textura, sobredimensionadas para no mostrar bordes: capa A escala 1,5, rotación ±3,5° (ciclo 70 s), desplazamiento 11 % ancho / 6 % alto (ciclos 45 s / 56 s), opacidad ×1,4; capa B espejada en X, escala 1,75, rotación ±4,5° (88 s), desplazamiento 14 % / 8 % (65 s / 78 s), opacidad ×0,9. Los radiales derivan ±11–15 % con ciclos de 36–50 s y fases distintas.
- **Rendimiento**: actualizar a 30 fps como máximo; pausar con la ventana inactiva y con Reduce Motion (queda estático). Sin blur en tiempo real.
- **Windows**: capas con `transform`/`opacity` y `will-change`, textura como imagen/canvas generada una vez, animaciones CSS o `requestAnimationFrame` a 30 fps, `prefers-reduced-motion` y `document.hidden`/blur de ventana para pausar. Medir consumo.

## 7. Equivalentes en Windows

| Apple | Windows (punto de partida) |
|---|---|
| `TopNavigationView`, `WindowNavigationToolbarView`, `HistoryToolbarView` | `windows/src/lib/components/shell/TitleBar.svelte` + `windows/src/routes/+page.svelte`; selector/grupo nuevos conservando controles Tauri |
| `FullscreenBackdrop`, shell/scene layout | `FullscreenNowPlaying.svelte` + `+page.svelte`; separar fondo a toda ventana de foreground/columna |
| `HomeView.swift`, `HomeFeaturedView.swift` | `windows/src/lib/components/home/HomeView.svelte` (cabecera y estantes genéricos) |
| `HomeFeedTableView/CollectionView` | `HomeShelf.svelte` (usa `each` para todos los items) |
| cartas / controles comunes | `HomeCard.svelte`, `SearchResultCard.svelte`, `QuickResults.svelte`, `detail/TrackTable.svelte`, `library/AccountTrackTable.svelte`, `fullscreen/RecommendedPanel.svelte`; adaptar PAR-009 |
| `HomeViewModel` + settings | `HomeController` (ya tiene `moreError`, `finally`, generaciones y tokens) |
| `HomeSettingsPanel` | panel nuevo superpuesto en el shell |
| `HomeAmbient*` | componente de fondo nuevo |

## 8. Pruebas a replicar (Apple → Windows)

Referencia de casos en `apple/Tests/SideBTests/`: `HomeRecommendationSettingsTests`, `HomeFeaturedPresentationTests`, `HomeRecommendationIntegrationTests`, `HomeCollectionPreferenceTests`, `HomeAlbumMetadataTests`, `HomePlaylistMetadataTests`, `HomeAmbientPaletteTests`, `HomeSettingsVisibilityTests`, `TopNavigationViewTests`, `ShellLayoutTests`. Mínimo a cubrir en Windows:

1. Prioridad estricta: la primera fuente agota el cupo antes de pasar a la siguiente; dedupe entre fuentes.
2. Capacidad 2/4/6 → 12/24/36; ninguna colección inaccesible al estrechar la ventana.
3. Todas las fuentes desactivadas → estado vacío, sin sustituir tipo.
4. Ocultar categoría oculta el estante pero conserva sus destacados.
5. Orden `sideB`/`youtube`/`custom`; categorías nuevas al final; ocultas no reaparecen al refrescar.
6. Persistencia por cuenta y por tipo; migración desde preferencia sin versión; versión futura → defaults.
7. Metadata: solo página visible, máx. 2 en paralelo, LRU 6, sin respuestas de cuentas anteriores.
8. Paleta: acento pequeño azul ante dominante tierra; familias distintas ante carátulas repetidas.
9. Panel: Escape/Cerrar, cierre al navegar/buscar/fullscreen, no reabre solo; grupo de acciones centrado abierto y cerrado.
10. Fondo: pausa en inactividad y con reduce-motion; ciclos sin regenerar la textura, contraste legible y consumo medido.
11. TopNav: cuatro segmentos, Explorar operativo (PAR-012), selección coherente con destinos/búsqueda, inversión rápida de sidebar, callbacks vigentes, controles Windows y drag intactos.
12. Fullscreen: fondo continuo tras sidebar/contenido desde el primer frame, sin doble fade ni saltos al alternar sidebar; input y player/buscador con reserva correcta.
13. Categorías dinámicas: desaparición/reaparición y límite de posición tras reordenar con ausentes; Quick picks marcado sin estante no equivale a ocultar Speed Dial.
14. Acciones: abrir detalle correcto, créditos verificables, menús, reproducción completa sólo bajo acción, errores manteniendo cola y shuffle por ocurrencias.
15. Cartas comunes: origen de radio activo tras avanzar y pausa sin reset; colección canónica activa en todas las vistas, foco/hover, enlaces y menú sin doble acción, fila completa y selección modificada, duplicados en cola y cancelación de carga tardía (MediaPlaybackIdentityTests, NativeTrackTableInteractionTests, HomeItemHierarchyTests, HomeAlbumPlaybackTests).

## 9. Pendientes y límites conocidos (no declarar cerrados)

- Arrastre real, navegación de páginas 1–6 y teclado exhaustivo, cuenta real y Instruments: **pendientes en Apple** (PLAN-007). No hay certificación de 120 FPS ni de audio.
- Medición de consumo del fondo animado: pendiente (FIX-109). Apariencia, foco/gestos y audio reales de cartas comunes: pendientes (FIX-111 / PLAN-009).
- Opciones futuras **no acordadas**, no portar como si existieran: playlists reproducidas en Side B, selección propia, «nuevas para vos».
- No existen datos para «más escuchadas históricamente», «recién publicadas» ni «creadas por mí»; no proponerlas.
- PLAN-008 de limpieza/eficiencia sigue **propuesto, sin implementar**. No incluir aliases unificados, refactor ni optimizaciones como funciones ya aplicadas.
- Fix de referencia por tema: barra superior FIX-090/107 · configuración FIX-105/106 · Speed Dial y destacados FIX-098/099/100/111 · cartas comunes FIX-111 · fondo FIX-108/109 · carga de más FIX-104 · reciclaje FIX-101 (descartado).

## 10. Cobertura auditada desde TopNav — FIX-110

Revisión estática del 2026-10-04 contra código Apple/Windows, FIXES y planes; no es ejecución del runtime Windows. Build de aquella auditoría: build-0029, BUILD.json compiled/sourceChangedDuringBuild false, log con 180 Rust (7 live ignorados), 47 XCTest y 177 Swift Testing/5 suites aprobados. La aprobación visual de movimiento figura en FIX-109; consumo Instruments pendiente. No se corrieron nuevas pruebas ni build para esta edición documental.

| Referencias | Resultado a conservar/trasladar | Seguimiento |
|---|---|---|
| [FIX-090](FIXES.md#fix-090), [FIX-107](FIXES.md#fix-107) | Selector, salida con sidebar y grupo de acciones en posición permanente; adaptar implementación nativa | PAR-007 / PAR-006 |
| [FIX-091](FIXES.md#fix-091), [FIX-092](FIXES.md#fix-092), [FIX-093](FIXES.md#fix-093), [FIX-094](FIXES.md#fix-094), [FIX-095](FIXES.md#fix-095) | Continuidad de fondo/fullscreen/sidebar y geometría; referencia final 095, intentos anteriores documentados | PAR-008 |
| [FIX-096](FIXES.md#fix-096) | Alcance de flechas de estantes | PAR-002, por verificar en Windows |
| [FIX-097](FIXES.md#fix-097) | Catálogo/tandas, fuente canónica y shuffle reversible | PAR-001 |
| [FIX-098](FIXES.md#fix-098), [FIX-099](FIXES.md#fix-099), [FIX-100](FIXES.md#fix-100) | Saludo, Speed Dial, destacados adaptativos, gestos, metadata, acciones y ambiente | PAR-003 |
| [FIX-101](FIXES.md#fix-101), [FIX-102](FIXES.md#fix-102), [FIX-103](FIXES.md#fix-103) | Viewport/identidades/acciones; 101 descartado, contrato AppKit 102 y montaje condicional 103 sin port literal | PAR-004 |
| [FIX-104](FIXES.md#fix-104), [FIX-106](FIXES.md#fix-106) | Continuaciones acotadas por cambios visibles, páginas ocultas, error/reintento/fin | PAR-005 |
| [FIX-105](FIXES.md#fix-105), [FIX-106](FIXES.md#fix-106), [FIX-107](FIXES.md#fix-107) | Overlay, fuentes por tipo, categorías dinámicas, persistencia/cuentas, seis páginas, foco y centro fijo | PAR-006 / PAR-007 |
| [FIX-108](FIXES.md#fix-108), [FIX-109](FIXES.md#fix-109) | Paleta, luz/humo y movimiento final de build-0029; adaptación CSS/canvas | PAR-003 |

Ampliación posterior: [FIX-111](FIXES.md#fix-111) lleva controles/identidad/interacción comunes a toda la app (PAR-009), con build-0030 y runner completo: 180 Rust (7 live ignorados), 52 XCTest y 187 Swift Testing aprobados. Validación visual/audio real/consumo y Windows pendientes.

La exclusividad histórica de APIs AppKit/SwiftUI no excluye registrar el resultado visible que Windows debe lograr. Se trasladan contratos/comportamientos y se implementan con la tecnología del destino. No declarar resuelto ninguno de estos pendientes sin evidencia Windows.

FIX-112 / PAR-010 amplía el contrato de inicio de pistas conocidas: catálogo completo en segundo plano para reproducción normal, completo antes de elegir sólo en shuffle inicial. Build-0031: 180 Rust (7 live ignorados), 52 XCTest y 194 Swift Testing aprobados; BUILD.json compiled/sourceChangedDuringBuild false. También corrige controles persistentes por selección de fila (PAR-009). Latencia real/audio pendientes; documentación finalizada después de compilar, sin cambios posteriores de código.

FIX-113 registra la excepción de cola solicitada en 2026-10-05, recuperada desde el código anterior a FIX-111: celda propia con Like/Dislike y subtítulo conjunto, conservando coordinación de cola actual. Build-0033 compilada; 180 Rust (7 live ignorados), 52 XCTest y 198 Swift Testing aprobados, fuentes estables durante build. Validación visual/arrastre con cuenta real y destino Windows pendientes.

## 11. Detalle común de álbumes y playlists — PLAN-010

[FIX-114](FIXES.md#fix-114), [FIX-115](FIXES.md#fix-115), [FIX-116](FIXES.md#fix-116) y [FIX-117](FIXES.md#fix-117) / [PAR-011](PARIDAD.md): UI de detalle común por capacidades. Cabecera y canciones se desplazan juntas; viewport hasta el borde superior de ventana, separación para toolbar dentro de cabecera y desplazable (sin recorte por padding exterior); cabecera +20 %, filas 58 pt, portada 44, Play 32 y Like/menú 28. Ambiente de portada más vivo (luces .58/.50, humo .25/.20), movimiento lento anterior, montado detrás de toda la ventana incluidos título/sidebar, con alto que incluye la separación superior del contenido y llega 140 pt bajo header; sigue el scroll del documento y extiende al rebotar sin franja negra; fade conserva intensidad hasta 60 % y baja suavemente a cero. Pausar por Reduce Motion/inactividad/fuera de viewport, nunca capturar clics ni observar offsets por píxel en el modelo. Buscador derecha sin borde interior ni fondo opaco al editar: clear con identidad/espacio estable, vacía campo/editor/filtro y mantiene edición, clic exterior/Escape desenfocan sin borrar filtro. Filtro/restauración deben actualizar datos y filas de forma consistente antes de recalcular header, conservar editor montado. Playlist añade orden y columnas Canción/Artista/Álbum/Duración; álbum omite Álbum/selector/encabezados. Créditos aclaran al hover/foco, IDs reales y acciones independientes de Play. Filtrar sólo oculta filas: cola completa en el orden elegido desde la ocurrencia elegida. Completar catálogo para orden local y drag personalizado sólo propias guardado por setVideoId/sucesor/rollback; ajenas/Likeados no editables. Lanzamiento retirado por falta de fechas en catálogo, recientes/antiguas por proveedor cuando disponible. Adaptar al contenedor/player Windows; no copiar hosting/AppKit. Auditoría 2026-10-09: Windows ya desplaza cabecera y canciones en un documento vertical común (+page.svelte:931); sus tablas sólo tienen overflow horizontal. Conservar ese scroll. APIs propias y metadata-link al hover ya existen; siguen pendientes cabecera común/viewport, ambiente/filtro/orden local/densidad, drag sobre catálogo completo, virtualización y runtime destino; ver checklist DET del PLAN-001 Windows.
