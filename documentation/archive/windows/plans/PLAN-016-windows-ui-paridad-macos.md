> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# PLAN-016 — UI Windows: Inicio y vistas de catálogo como en macOS

- **Fecha:** 2026-09-30.
- **Estado:** En desarrollo; W10b/W10c y W19/W20 integrados; recorrido funcional básico aprobado por el usuario. Paridad visual y casos especiales pendientes. Ver [W10b-W19-W20-result](../handoffs/W10b-W19-W20-result.md).
- **Prioridad actual:** continuar categorías de Inicio → álbum → artista/catálogo. Cuenta y playlist se integran coordinadamente en PLAN-017 por petición posterior del usuario.
- **Método:** entregas pequeñas, revisadas en la app; cerrar una pantalla antes de avanzar a la siguiente.

## 1. Objetivo y límites

Trasladar a Windows la jerarquía, densidad, proporciones, márgenes, estados e interacciones de la app macOS actual. El código vigente de Apple es la referencia; los planes antiguos describen historia. Mantener sidebar y barra de reproducción disponibles al navegar, sin reiniciar audio ni modificar la cola por abrir una pantalla.

Este documento es el plan de implementación. No declara UI implementada ni equivalencia visual verificada. En este host se pueden capturar y operar ventanas Windows; para comparar ambas plataformas se necesita una captura Mac del mismo escenario. Hasta disponer de ella, usar las medidas del código y registrar esa limitación.

«Perfiles» se interpreta como página de artista y presentación de la cuenta propia. Mac tiene `ArtistDetailView` y un perfil de cuenta con popover en la sidebar; no inventar una página pública de usuario que no exista en la referencia.

PLAN-015 conserva W14–W17 para edición de cola, shuffle/repeat, radio y persistencia. Este plan integra esas acciones cuando estén disponibles; no implementa otra máquina de reproducción. Fullscreen conserva su trabajo previo y recibe únicamente las correcciones necesarias por integración.

## 2. Estado inicial comprobado y fuentes

### Windows

- `windows/src/routes/+page.svelte` contiene el Inicio efectivo: cabecera del prototipo, chips, render del feed y detalle de álbum inline. Las filas compactas de ese render son informativas.
- `windows/src/lib/components/home/HomeView.svelte` existe, pero no se importa ni usa en `+page.svelte`. Es un punto de partida, no la pantalla vigente.
- Existen `get_home_page`, `get_album`, login y reproducción con snapshot de cola. No existen aún wrappers Tauri de playlist, artista ni continuación de Inicio.
- `HomeItemDto` omite `artistId`, `album`, `artistRuns` y `explicit`; `HomeSectionDto` omite `moreBrowseId` y `moreParams`; `HomePageDto` omite `continuation`. Esos datos ya existen en el core.
- El detalle de álbum Windows pierde `artistId`, `playlistId`, `inLibrary` y `sections` del record compartido.
- W13 está implementado y compilado; queda su prueba manual de cola/audio. Ver `documentation/handoffs/W13-result.md`.

### Referencias Mac de solo lectura

| Área | Fuente vigente |
| --- | --- |
| Cabecera, chips, estados | `apple/Sources/SideB/Views/Home/HomeView.swift` |
| Estantes, scroll, dimensiones | `apple/Sources/SideB/Views/Home/HomeFeedTableView.swift` |
| Tarjetas, metadata, hover y botones | `apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift` (`HomeItemView`, `HomeSectionHeaderView`) |
| Orden, formatos e identidad | `apple/Sources/SideB/Models/HomeFeedPresentation.swift` |
| Colores y superficies | `apple/Sources/SideB/UI/AppTheme.swift` |
| Playlist | `apple/Sources/SideB/Views/Detail/PlaylistDetailView.swift` y su ViewModel |
| Álbum | `apple/Sources/SideB/Views/Detail/AlbumDetailView.swift` y su ViewModel |
| Artista y catálogos | `apple/Sources/SideB/Views/Detail/ArtistDetailView.swift`, `ArtistCatalogView.swift` y su ViewModel |
| Cabeceras, carga, errores, descripción | `apple/Sources/SideB/Views/Common/DetailSharedComponents.swift`, `DescriptionCardModal.swift` |
| Filas y columnas | `apple/Sources/SideB/Views/Common/NativeTrackTableView.swift` |
| Cuenta propia | `apple/Sources/SideB/Views/Sidebar/SidebarProfileView.swift` |
| Datos reales | `core/crates/sideb-core/src/lib.rs` |

No portar AppKit a Svelte literalmente: conservar geometría y comportamiento con componentes web. No modificar `apple/` para facilitar el port.

## 3. Medidas de referencia

Usar puntos Mac como base de píxeles CSS lógicos, no como píxeles físicos. El breakpoint depende del **ancho del contenido**, excluyendo sidebar; usar container queries o una medición equivalente. Segoe UI puede cambiar el ancho del texto respecto de SF; verificar los saltos de línea.

| Elemento | Valor comprobado en Mac |
| --- | --- |
| Fondo / sidebar | `#1B1B1E` / `#24242A` |
| Acento / realce | `#A33D45` / `#D06C70` |
| Superficie / hover de tarjeta | blanco 5% / 8% según tema; contrastar su aplicación en la celda |
| Cabecera Inicio | horizontal 28, superior 24, inferior 12 |
| Título / subtítulo Inicio | 27 bold / 13; separación 3 |
| Chips | separación 8; padding horizontal 14 y vertical 7; fuente 13; banda 42 de alto y margen inferior 4 |
| Feed | inset superior 10; reserva inferior 120 para la barra flotante |
| Cabecera de estante | margen horizontal 28; banda de 46 |
| Portada grande | 160 × 160; 140 × 140 si contenido < 760 |
| Tarjeta grande | ancho igual a portada; alto portada + 94 de región de texto |
| Estante | insets laterales 28; separación horizontal entre columnas 16 |
| Portada grande → título | 11 |
| Título de tarjeta | 14 semibold; hasta 2 líneas de 18 |
| Título → metadata | 3 después de la última línea visible, sin coordenada fija |
| Metadata grande | 12; tipo, `E`, separador y artista/creador alineados; detalle hasta 2 líneas |
| Portada grande | radio 12; artista circular |
| Compacta | celda 330 × 56; ancho 286 si contenido < 760; estante 230 de alto |
| Portada compacta | 44 × 44, inset 6, radio 8; texto empieza a 58 |
| Compacta: título / menú | título 13 semibold; área de menú 28 × 28 |
| Detalle playlist/álbum | portada 180 × 180, radio 10; separación portada/texto 24; título 32 bold |
| Detalle artista | avatar 180 × 180; título 34 bold; contenido lateral 32, cabecera superior 28 |
| Tabla compartida Mac | alto base de fila 52; comprobar overrides en cada vista antes de fijarlo |

Medir también el espacio entre estantes y las columnas de tabla directamente en el componente activo al implementar; no sustituir esas medidas por valores elegidos a ojo. Preservar el marco de texto de tarjetas grandes aun con títulos cortos; la metadata se ajusta a cada título, las portadas y el comienzo de títulos permanecen alineados.

## 4. Estructura para crecer por pantalla

- `+page.svelte`: coordinación de sesión, navegación y reproductor. Extraer el render de Inicio efectivo a `HomeView`; retirar exclusivamente su markup y estilos obsoletos tras conectar el reemplazo.
- `lib/styles/tokens.css`: medidas y colores comunes. `+layout` carga los tokens una vez.
- `lib/components/home/`: `HomeView`, `HomeShelf`, `HomeCard`, `CompactSongCard`, estados del feed.
- `lib/home/presentation.ts`: normalización de formato, orden e identidades; no mezcla estado de audio.
- `lib/navigation/`: destinos tipados y historial con ID/params/scroll. Empezar con Inicio, búsqueda y álbum; incorporar playlist/artista cuando sus vistas estén listas.
- `lib/components/detail/`: cabecera compartida, descripción, tabla y estados; vistas específicas conservan sus diferencias.
- `lib/api/`: wrappers `invoke` tipados conforme se extraen; `types.ts` conserva DTOs consistentes con Rust.

Los nombres nuevos son propuestos. Confirmar los límites antes de crear archivos; evitar una extracción general que retrase el primer Inicio visible. Una única implementación de tarjeta, tabla y navegación debe servir a las pantallas posteriores.

### Reglas de datos y acciones

1. Agregar campos DTO desde records existentes; no parsear el DOM ni copiar datos de screenshots.
2. Identidades por entidad y ocurrencia, con identidad estable de sección como Mac. No usar sólo título de sección ni `videoId` como key cuando hay duplicados.
3. Filtrar sólo secciones vacías. En Todos ordenar: volver a escuchar → favoritos olvidados → álbumes para ti → biblioteca → selecciones rápidas → restantes en su orden original. Con chip conservar orden del proveedor.
4. Volver a escuchar y favoritos olvidados usan tarjetas grandes. Compacta sólo cuando todos los ítems son canciones y el formato o la sección lo indica. Secciones mixtas usan grandes.
5. `kind` y contratos reales deciden destinos; no inferir tipo sólo por un prefijo de ID. Los `moreBrowseId` que empiezan por `FE` no son «Ver más» navegable en la referencia actual.
6. Respuestas atrasadas de chip, cuenta o destino no reemplazan la selección vigente. Continuaciones se asocian a chip y revisión de sesión; una petición por token activo, sin bucles automáticos tras error.
7. La imagen visible sigue la metadata de la entrada seleccionada del snapshot Rust. Abrir una tarjeta o volver a Inicio no modifica playback.
8. No añadir botones decorativos. Una acción pendiente se omite o queda identificada como no disponible; nunca parece funcional. Al cerrar cada pantalla registrar las diferencias funcionales que siguen dependiendo de otros paquetes.

## 5. Inicio — W10a a W10d

### W10a — Integrar y cerrar la geometría

**Objetivo:** que el Inicio real deje de mostrar la UI del prototipo y use la composición Mac.

- [x] Integrar `HomeView` en `+page.svelte` con datos y callbacks existentes; eliminar duplicación del render anterior.
- [x] Quitar de Inicio la cabecera central del prototipo y su texto técnico. Mantener errores de backend en una presentación discreta con acción real.
- [x] Aplicar cabecera, chips, márgenes, estantes, tamaños, dos formatos y tipografía de la tabla anterior. Breakpoint implementado; prueba estrecha pendiente.
- [x] Alinear portadas/títulos; metadata debajo de la última línea real; fallback de imagen mantiene su tamaño. Fallback verificado por código, no con fallo de imagen forzado.
- [x] Aplicar variantes circular/cuadrada, foco y hover sin desplazar tarjetas. Foco por teclado pendiente de prueba manual.
- [x] Usar columnas de cuatro filas compactas, con orden de arriba abajo y luego a la columna siguiente; no una lista vertical de ancho completo.
- [ ] Mantener sidebar, barra flotante y reserva inferior; revisar ancho de contenido con sidebar abierta/cerrada.

**Archivos:** componentes Home, tokens, presentación, `+page.svelte` y carga de estilos. No modificar Rust en W10a.

**Salida:** Inicio conectado, navegación a álbum y reproducción existentes conservadas; capturas de grandes/compactas y ventana estrecha/ancha. Registrar en `documentation/handoffs/W10a-result.md`. Esta entrega cierra composición, no todos los destinos.

### W10b — Metadata, navegación y estados de reproducción

- [x] Ampliar `HomeItemDto` y mapping Rust con `artistId`, `album`, `artistRuns`, `explicit`; espejo TypeScript sin romper campos existentes.
- [x] Mostrar `E`, tipo y enlaces individuales de artista cuando hay ID. Sin ID, texto normal.
- [ ] Tarjeta/título abren destino; botón de portada reproduce cuando hay acción implementada. En canción la activación principal reproduce; enlace de metadata navega sin disparar play.
- [ ] Conectar indicador de tema activo y pausa a snapshot vigente, sin actualizar todas las tarjetas por cada tick de posición.
- [ ] Definir destinos tipados, Atrás/Adelante reales y restauración de scroll para Inicio↔álbum. Retornar conserva chip y offsets de estantes.
- [ ] Flechas de estante desplazan su propio carrusel y tienen estado correcto en extremos; no dependen de un scroll vertical global.
- [ ] Preparar destinos de playlist/artista y documentar que se habilitan al entregar W18/W20.
- [ ] Menús de tarjeta muestran sólo acciones implementadas; edición de cola y radio se conectan según PLAN-015.

**Salida:** metadata y acciones existentes reales, teclado usable, duplicados sin errores y reproducción sin doble disparo. Informe W10b con destinos pendientes explícitos.

### W10c — Feed completo, continuaciones y recuperación

- [x] Pasar `moreBrowseId`, `moreParams`, `continuation` por Tauri/TypeScript.
- [x] Wrapper `get_home_continuation` sobre `SideBCore.get_home_continuation(token)` y registro del comando.
- [ ] Cargar siguiente página al acercarse al final con footer de estado y reintento acotado. Conservar offsets; no reemplazar páginas cargadas ni eliminar ocurrencias válidas.
- [ ] Carga inicial, vacío, error inicial y fallo al actualizar son estados separados. Durante refresh conservar contenido con banner como Mac.
- [ ] Cambios rápidos de chip y sesión descartan respuestas anteriores; cancelar/inutilizar continuación al cambiar filtro.
- [ ] Habilitar «Ver más» sólo para destinos soportados; agregar navegación de catálogo tipada cuando W20b esté listo.
- [ ] Evaluar caché de feed por cuenta/chip reutilizando mecanismos existentes. No anunciar «contenido guardado» hasta que exista restauración real. Estado guardado persistente se entrega por separado si requiere almacenamiento nuevo.

**Archivos adicionales:** DTOs y wrappers en `windows/src-tauri/src/lib.rs`, tipos/API y estado de Home. Métodos del core ya existen; no cambiar UniFFI.

**Salida:** Inicio carga contenido más allá de la primera página y se recupera de errores sin borrar el feed útil. Informe W10c con evidencias de continuación.

### W10d — Cierre visual de Inicio

- [ ] Comparar referencia Mac y Windows con el mismo ancho lógico de contenido; mismas entidades cuando sea posible.
- [ ] Capturar a ambos lados del breakpoint 760 y a DPI Windows 100%/125%/150% disponibles. No declarar probado un DPI no ejecutado.
- [ ] Revisar títulos de una/dos líneas, metadata larga, `E`, artista circular, imagen fallida y secciones mixtas.
- [ ] Tab/Enter, foco visible, scroll horizontal, volver con offsets, refresh/error y última fila libre de la barra.
- [x] Pista real: play/pausa, siguiente/anterior, artwork y cola sincronizados mientras se navega; completar evidencia manual pendiente de W13.
- [ ] Separar en el informe paridad visual de destinos pendientes W18/W20 y funciones pendientes W14–W17. No marcar «paridad funcional total» hasta cerrar esas dependencias.

## 6. Playlist — W18a a W18c

### W18a — Datos, cabecera y tabla compartida

- [ ] Crear wrapper `get_playlist` de `SideBCore.get_playlist(id)` y DTO completo, incluyendo propiedad, biblioteca, privacidad, colaboración, sort y continuación.
- [ ] Vista `PlaylistDetailView`: portada 180, cabecera lateral 32, título y subtítulo como Mac, descripción a dos líneas y modal de lectura completa.
- [ ] Identificar colección Me Gusta cuando ID sea `LM`, igual que Mac.
- [ ] Extraer `TrackTable` con columnas de referencia, duración alineada, portada, metadata, distintivo, hover/foco y pista activa. Preservar ocurrencias repetidas.
- [ ] Carga con skeleton 180; vacío útil; error con reintento. Sin bloquear reproductor.
- [ ] Abrir desde Inicio y volver al mismo chip/scroll.

### W18b — Reproducción y lista larga

- [ ] Reproducir desde fila o cabecera crea cola ordenada con índice correcto y contexto playlist; usa el transporte W13.
- [ ] Continuación mediante `get_playlist_continuation`, estado de carga, reintento y protección de respuestas viejas.
- [ ] Definir cómo ampliar la cola de una playlist paginada sin reemplazar la selección ni editar implícitamente una cola distinta; documentar si sólo están encoladas las filas cargadas hasta disponer de extensión real.
- [ ] Scroll largo y retorno con selección/posición conservados; virtualizar la tabla si el escenario real lo requiere, sin prometer métricas por el framework.

### W18c — Acciones según propiedad

- [ ] Inventariar acciones reales de Mac y métodos existentes: biblioteca, me gusta, ordenar, editar playlist propia, quitar/mover canciones.
- [ ] Separar lectura de mutaciones. Implementar cada grupo en subpaquete con permisos/propiedad, estado pendiente, éxito y error visibles.
- [ ] Shuffle y radio dependen de W15/W16; no simularlos. Menús reutilizan política por entidad.
- [ ] Validar invitado, playlist ajena y propia sin cambios destructivos de prueba no autorizados.

## 7. Álbum — W19a y W19b

### W19a — Llevar el detalle existente a la referencia

- [x] Extraer detalle inline a `AlbumDetailView` sobre cabecera y tabla compartidas.
- [x] Geometría: portada 180, gap 24, lateral 32, título 32, artista 16 semibold; año/tipo/conteo y descripción como Mac.
- [x] Completar DTO con `artistId`, `playlistId`, `inLibrary`, `sections`; navegación al artista cuando W20 esté listo.
- [x] Conservar reproducción del álbum completo desde índice y carátula por pista/fallback álbum ya implementados.
- [ ] Aplicar diferencias de tabla Mac para álbum: numeración, columna álbum oculta/subtítulos según configuración vigente, duración y tema activo.

### W19b — Pie y acciones

- [ ] Carruseles de otros lanzamientos/secciones con tarjetas compartidas, orden del record y navegación real.
- [ ] Biblioteca y menú de álbum sólo con contratos disponibles; shuffle/radio según dependencias.
- [ ] Descripción expandida, errores, datos incompletos, retorno y estado de player sin regresión.

## 8. Perfiles — W20a/W20b y W21

### W20a — Artista

- [x] Wrapper `get_artist` sobre `SideBCore.get_artist(browseId)`; DTO de todos los campos de `ArtistDetailRecord` y carruseles.
- [x] Avatar circular 180, título 34, suscriptores/oyentes sólo si existen, descripción expandible.
- [x] Orden Mac: cabecera → separador → canciones principales → carruseles de álbumes/sencillos/vídeos y demás secciones presentes.
- [ ] Reutilizar tabla/tarjetas; reproducir top songs con índice/contexto real. Radio y seguir requieren sus contratos y estado real.
- [ ] Habilitar enlaces de artista desde Inicio, canciones y álbum; respuesta antigua no reemplaza otro perfil.

### W20b — Catálogo y «Ver más»

- [x] Revisar `ArtistCatalogView` y el método de browse vigente antes de definir wrapper.
- [ ] Destino con browseId y params; listado/carrusel, título, paginación cuando el proveedor la ofrece, carga/error/vacío y retorno con scroll.
- [ ] Completar «Ver más» de Inicio y de artista para los tipos soportados; registrar cualquier endpoint no navegable.

### W21 — Cuenta propia en sidebar

- [ ] Comparar perfil existente Windows con `SidebarProfileView`: avatar, nombre/handle y popover; invitado, cargando y fallo de cuenta.
- [ ] Usar el login y persistencia confirmados por el usuario. No rehacer autenticación.
- [ ] Popover abre/cierra con teclado y devuelve foco; información personal sólo la necesaria, sin credenciales en UI/logs/capturas compartidas.
- [ ] Logout mantiene el contrato actual de limpiar sesión y cola; su prueba manual requiere el escenario acordado para no interrumpir música inadvertidamente.

## 9. Verificación y entrega por paquete

1. `corepack pnpm check` y `corepack pnpm build` desde `windows/` para cambios web. Compilar Rust sólo cuando cambie el puente; usar entorno MSVC x64 documentado.
2. Tests dirigidos cuando hay riesgo concreto: orden/formato/identidad, respuestas fuera de orden y mapping DTO. Ajustes de padding se validan visualmente.
3. Abrir Windows real con Vite activo si se usa el ejecutable debug con `devUrl`. Un `cargo build` de desarrollo no produce por sí solo una app autónoma con frontend incluido.
4. Capturas antes/después y revisión de ancho/DPI; indicar si Mac se comparó por captura o sólo por código.
5. Informe `documentation/handoffs/<paquete>-result.md`: archivos, estado, comandos/resultados, prueba manual, dependencias y límites. No incluir cookies, tokens ni URLs firmadas.
6. Actualizar casillas sólo por trabajo comprobado. Cerrar hito de documentación general al entregar pantalla, no por cada ajuste CSS.

## 10. Primer encargo listo para implementar

> Implementá únicamente **W10a de PLAN-016**. Leé `.agents/AGENTS.md`, reglas generales/Windows y este plan. El Inicio activo está inline en `windows/src/routes/+page.svelte`; `HomeView.svelte` existe pero no está integrado. Conectá esa vista, reemplazá el render anterior y trasladá las medidas de `HomeView.swift`, `HomeFeedTableView.swift` y `HomeItemView` en `HomeFeedCollectionView.swift`. Usá ancho del contenido para el breakpoint 760: portadas 160/140 y compactas 330/286 × 56, artwork 44 con inset 6. Metadata a 3 de la última línea del título; margen lateral 28 y reserva inferior 120. Conservá sesión, álbum, cola Rust, barra y fullscreen. No implementes otras pantallas ni cambies Rust/Apple en este paquete. Ejecutá check/build web y probá Inicio real con ventana ancha/estrecha, sidebar abierta/cerrada, canciones y álbum. Devolvé capturas y `documentation/handoffs/W10a-result.md`, con estados y verificaciones pendientes explícitos. Cerrá con `ENTREGA LISTA: W10a` o `BLOQUEADO: W10a`.

**Siguiente acción:** el recorrido básico de Inicio paginado, álbum, artista, mix y retorno quedó aprobado por el usuario. Continuar con los pendientes específicos, sin repetir ese recorrido salvo regresión. Mantener pendientes de W10d la comparación visual Mac equivalente y distintos DPI. El shuffle de cabecera mezcla la cola una vez; radio carga la tanda inicial; W15/W16 conservan modo persistente/repeat y continuación automática.

## 11. Avance W10b/W10c, W19 y W20 (2026-09-30)

Implementados el contrato de continuation de Inicio, precarga limitada, deduplicación por firma Mac, carga al pie/reintento y protecciones de sesión/request; enlaces de artista/álbum, flechas de estantes y Ver más. Se extrajo el álbum inline a componentes de detalle, con cabecera/tabla/descripción/carruseles y acciones reales. ArtistDetailView y CatalogView están conectados a navegación, top songs y snapshot de cola; mix usa get_next como Mac. Biblioteca/suscripción usan sesión y serialización frente a logout.

La comparación usó código vigente Mac: artista gap28, carruseles144/vídeo200×112 y top5 filas44 con gap14/padding8-10; estos overrides prevalecen sobre la tabla genérica de medidas para esa pantalla. Álbum conserva portada180/gap24/título32.

No cerrar checklists de QA por esta integración: queda prueba en ventana y equivalencia con screenshot Mac. Ver el informe para resultados y límites. Dos chats compartían el checkout; se coordinó propiedad de archivos y runtime con autorización explícita del usuario, registrada en W21-coordination.

### Cierre del recorrido básico — 2026-09-30

El usuario confirmó «perfecto anda todo» luego de las seis pruebas de Inicio/continuación, álbum/transporte, fullscreen/cola, artista/detalles, mix/Aleatorio y retorno/posición. Ver la evidencia y su alcance en W10b-W19-W20-result.md. No se cierran por esa respuesta las casillas que incluyen paridad visual por captura, errores forzados, mutaciones de cuenta o funciones avanzadas todavía pendientes.
