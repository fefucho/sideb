# PLAN-020 — Navegación horizontal con mouse en Windows

- Fecha:2026-10-27, America/Montevideo.
- Estado: **Flotantes implementada en Windows por FIX-261; check/tests/build frontend y matriz de navegador aprobados. QA física WebView2 pendiente; sin EXE nuevo**.
- Pedido: revisar todas las pantallas y proponer flechas al principio/final de cada zona horizontal, superpuestas al contenido para avanzar una pantalla con mouse. Mostrar opciones antes de incorporar el cambio.
- Alcance propuesto: presentación/entrada Windows; carruseles reales, filas paginadas y tiras de categorías. Sin cambios de core, orden del proveedor, audio ni implementación Apple.
- Estado inicial: main13011e7; modificaciones documentales anteriores en FIXES/PARIDAD/PLAN-018/019/índice conservadas. No se incluyen ni reinterpretan como cambios de esta propuesta.

## Inventario de fuentes actuales

| Pantalla / superficie | Implementación | Estado / propuesta |
|---|---|---|
| Inicio: estantes de álbumes/playlists/artistas y canciones compactas de cuatro filas | `home/HomeShelf.svelte`, `.track` con ventana horizontal | Sin flechas/barra oculta. Overlay a izquierda/derecha; avance por tarjetas o columnas completas, conservando virtualización/offsets. |
| Inicio: filtros por categoría | `home/HomeView.svelte`, `.chips` | Scroll horizontal/barra oculta. Controles pequeños a ambos extremos sólo si hay desbordamiento. |
| Inicio: Speed Dial | `home/HomeView.svelte`, `.dial`/`.pager` | Ya paginado en grupos de9 con flechas/puntos inferiores. Proponer llevar las flechas a los bordes del bloque; conservar puntos y paginación existentes, evitando dos pares. |
| Inicio: álbumes/playlists destacados | `home/HomeView.svelte`, `.collections`/`.pager` | Ya paginado según ancho. Mismo criterio que Speed Dial; no convertirlo en otro motor de scroll. |
| Explorar: novedades en Descubrir | `explore/VirtualCatalog.svelte`, `horizontal=true` desde `ExploreView.svelte` | Carrusel de álbumes/singles sin flechas. Mantener celdas y ventana virtual. Lanzamientos completos, géneros, momentos y rankings son grillas verticales. |
| Explorar: pestañas Descubrir/Lanzamientos/Rankings/Géneros/Momentos | `explore/ExploreView.svelte`, `nav` | Puede desbordar; flechas pequeñas. Dejar Actualizar accesible sin cubrirlo. |
| Búsqueda: secciones carrusel enviadas por el proveedor | `search/SearchView.svelte`, `.card-shelf` | Álbumes/artistas/playlists y filas musicales según respuesta. Flechas de contenido; medir geometría real variable, sin inventar una anchura universal ni recortar resultados. |
| Búsqueda: chips del proveedor | `search/SearchFilterChips.svelte`, `.mode-tabs` | Ya tiene detección de extremos/fade, sin flechas. Reutilizar estado; controles fuera de la máscara para que no se desvanezcan. |
| Biblioteca → Todo: fijados y estantes por tipo | `library/LibraryView.svelte`, `.overview-grid` | Carrusel de fijados y hasta6 elementos por sección cuando está en vista grilla. Flechas en cada fila que desborde; en modo lista no corresponde. Ver todo conserva su destino. |
| Biblioteca: pestañas de categorías | `library/LibraryView.svelte`, `.tabs` | Flechas pequeñas sólo con overflow; no cubrir Crear playlist/Actualizar de la misma toolbar. |
| Artista: discografía y demás secciones del proveedor | `detail/ArtistDetailView.svelte`, `.carousel` | Flechas por sección; artistas con portada circular conservan forma/menús. Canciones populares usa tabla vertical. |
| Álbum: otras ediciones y demás secciones del proveedor | `detail/AlbumDetailView.svelte`, `.cards` | Flechas por sección; Ver todo y lista de pistas mantienen comportamiento. |
| Fullscreen → Relacionado | `fullscreen/RecommendedPanel.svelte` + `RecommendedViewport.svelte`, `axis=x` | Cuatro familias: más del artista, mismo álbum, similares y artistas relacionados. Flechas por estante; las canciones avanzan por columnas270px×3filas, artistas por celdas86px+gap. No afectar el viewport vertical padre ni foco/menú retenidos. |

También se revisaron Sidebar, player, cola, letras/Genius/información, playlists/catálogos completos, menús, ajustes y diálogos. No tienen carruseles horizontales de contenido adicionales en las fuentes actuales. `overflow:auto` de texto/diálogos no justifica flechas de medios: si produce overflowX accidental, debe corregirse el wrapping/min-width; `ReleaseNotes.svelte` admite `pre` horizontal y se revisará como texto excepcional, sin superponer controles de álbum. Sliders de volumen/progreso y elementos truncados tampoco son carruseles.

## Opciones evaluadas — Flotantes elegida

1. **Flotantes — recomendada:** círculos40px sobre ambos bordes, centrados sobre portadas o bloque de canciones. Fondo sólido/translúcido de alto contraste y fade lateral sutil. Disponibles sin hover cuando hay contenido en esa dirección; izquierda ausente al comienzo y derecha ausente al final. No agregan altura ni reducen la cantidad visible de tarjetas. Hay que reservar una pequeña zona segura en extremos para no tapar acciones de tarjetas.
2. **Esquinas:** círculos36px en la esquina superior izquierda/derecha del carrusel. Despejan el centro de portadas/filas, pero se acercan a los botones de reproducción/menús; requieren espacio local y no deben quedar encima de esos targets.
3. **Laterales:** flechas en dos canaletas fuera del área de tarjetas, sin cubrir portadas ni canciones. Más claras y cómodas, a cambio de reducir el ancho disponible. En panel Relacionado estrecho esto puede dejar menos columnas visibles.

Las tres variantes del prototipo comparan el mismo contenido de ejemplo, con álbumes, columnas de canciones y categorías. No son capturas de producto modificado. La visibilidad al pasar el mouse podría añadirse como refinamiento secundario, pero no se propone ocultar toda la pista de navegación por defecto.

## Comportamiento acordado

- Flechas sólo si hay más contenido; cada dirección refleja el límite real, incluido resize/sidebar/DPI, carga de imágenes/continuación y cambio de categoría/cuenta.
- Un clic avanza aproximadamente un viewport, alineado a tarjetas/columnas completas y sin saltarse elementos parcialmente visibles. Con panel menor que una columna, permitir alcanzar toda la columna sin quedar bloqueado por el snap. En paginadores existentes avanzar su página real.
- Animación corta; instantáneo con Reduce Motion. Clics repetidos y cambio de ancho durante animación no deben perder el destino ni acumular saltos obsoletos.
- Flechas fuera del nodo que scrollea y de sus máscaras/clip, ancladas al viewport visible. Sin aumentar scrollWidth ni quedar sujetas al reciclado de tarjetas.
- Mouse, rueda/trackpad, Shift+rueda cuando el sistema la suministre y teclado conservan sus rutas. Rueda vertical sigue moviendo la página; no secuestrarla para horizontal por defecto.
- Clic/Enter/Espacio de flecha sólo navegan la fila; nunca reproducen/abren la tarjeta detrás. Nombre accesible ES/EN por sección y foco visible; no desmontar sin retorno de foco el botón activado al llegar a un extremo.
- Reusar un control visual/medición común para scrollers y un adaptador para paginadores. Respetar suspensión de páginas retenidas, offsets/contexto, menús/foco de viewports virtuales y ausencia de observers activos detrás de overlays.
- Alto contraste/forced-colors mantiene botones reconocibles; área de pulsación al menos40px en mouse y44px con entrada táctil. Filtros pueden mostrar icono más pequeño manteniendo target.

## Etapas si se aprueba

- [x] Revisar fuentes de todas las superficies; distinguir carruseles, paginadores, filtros y overflow accidental.
- [x] Consultar antecedentes: FIX-096/PAR-002 retiró flechas de cabecera por decisión visual Mac; FIX-113-2 trasladó esa decisión a Windows. El pedido actual propone una adaptación explícita a mouse Windows, sin atribuir una regresión al port ni cambiar Mac. FIX-248/251/253/260 preservan virtualización/retención/Relacionado e integración publicados.
- [x] Preparar opciones interactivas y un inventario para revisar.
- [x] Elección del usuario: «floatantes, perfecto»; se aplica también a los paginadores existentes conservando sus puntos.
- [x] Implementar el control y adaptadores en Windows, incluyendo todas las superficies de la tabla; conservar el diseño elegido en anchos estrechos.
- [x] Verificar destinos por límites reales, columna mayor que viewport, clics rápidos, resize, RTL, foco, variantes paginadas y suspensión en regresiones de estado/montaje; conservar las pruebas5000 de menú/foco/retención. Reduce Motion/forced-colors y clics reales se comprueban además en el navegador descrito abajo. Esto no sustituye accesibilidad física ni un perfil de frames.
- [x] Revisar navegador con fixtures, check/tests y build frontend. El build estático no es un EXE; mantener el runner oficial para una futura entrega nativa solicitada.
- [ ] QA WebView2 con mouse/teclado y cuenta del usuario, Narrator/contraste del sistema; EXE numerado cuando se pida. No se opera la app instalada en esta tarea.
- [x] Registrar FIX-261 y actualizar PARIDAD/PAR-002: adaptación autorizada para mouse Windows; no se modifica la decisión Mac ni el core protegido.

## Ronda inicial de propuesta

La ronda inicial sólo auditó código y preparó una demostración aislada, sin modificar componentes ni compilar. El usuario eligió Flotantes después y autorizó la incorporación que se describe a continuación.

Prototipo aislado con Inter local: tres variantes comprobadas en navegador a768/352px,18recorridos de avanzar/volver entre álbumes/canciones/filtros aprobados y sin excepciones del fragmento ni overflow exterior. Se inspeccionaron capturas amplias y estrechas. Evidencia ignorada en `.cache/scroll-proposals/results.json`; no acredita una integración Svelte/WebView2 ni funcionamiento de los carruseles de producto. La previsualización local requirió completar el estado inicial del wrapper al extraer su iframe para el harness; no se cambia producto para ello.

## Ejecución — FIX-261

- Se incorporan `HorizontalNavigation.svelte` y `horizontal/scroll.ts`; los consumidores del inventario marcan su scroller y usan el mismo control. Speed Dial/destacados conservan sus páginas/puntos y sólo trasladan el par de flechas. Filtros usan círculos visualmente menores con target40px; entrada táctil44px. Las filas compactas de Inicio/Relacionado reservan44px interiores por extremo para no tapar el control de reproducción de la primera columna completa. Las portadas no cambian de tamaño.
- Los scrollers virtuales usan su stride existente. Los de tamaños mezclados consultan límites mediante búsqueda binaria al pulsar, sin un barrido de todas las tarjetas por frame. Se conserva scroll/teclado/rueda vertical; no hay RPC ni selección de canciones al pulsar flechas. Extremos/foco, idioma y cambios de dirección/resize/contexto se reconcilian con el DOM.
- La revisión por pantalla encontró dos callbacks tardíos de integración: VirtualCatalog leía `host` cuando Svelte ya había limpiado el binding y SearchViewport ejecutaba `blur` después de desmontarse. Se captura el nodo suscrito para retirar listeners y se comprueba conexión antes del microtask de foco. Se añaden regresiones de desmontaje activo/salida con foco. El primer harness también omitía `preview` requerido por SearchView: se completa la fixture; no se cambia SearchView para aceptar un contrato inválido.
- Check final:0errores/0advertencias. Suite frontend integrada del checkout: **490aprobadas/0fallos/0omitidas**. Incluye las5pruebas superiores nuevas de navegación y las regresiones de desmontaje dentro del test de montaje. Tras detectar cambios concurrentes en player/controller y su test de contenido, se repiten las60focales de navegación/reproducción/contenido y check0/0; no se atribuyen los cambios de contenido a esta tarea. `pnpm build` estático aprobado; conserva aviso de chunk grande.
- Navegador de app completa con RPC sintético: **28evidencias/errors[]**, incluidas retención/purga de cuenta, Spotlight/preview,5000resultados, layouts960/1280/1440/1920/DPR1/1.25/1.5/2, letras/manual/Original y toolbar. Evidencia `windows/.cache/plan016-browser/results.json`; log de esta ronda `windows/.cache/horizontal-shell-browser.log`.
- Matriz específica `node scripts/horizontal-navigation-browser.mjs`: **26casos/errors[]** sobre componentes reales,1000px/DPR1 y600px/DPR1.5. Inicio/paginadores/filtros, estante grande/compacto5000, Explorar, Search, Biblioteca incluidos8fijados, Álbum, Artista, los cuatro estantes de Relacionado con5000canciones y artistas, y tamaños mixtos/LTR→RTL. **44avances** con mouse CDP, hit real del botón y target≥40px, dirección anterior disponible después de avanzar, sin abrir/reproducir contenido detrás ni overflow de la página. Se comprueba forced-colors emulado, no Narrator. Capturas compactas/Relacionado/Inicio inspeccionadas. Logs/capturas/resultados en `windows/.cache/horizontal-navigation-browser/`.
- No se afirma aceptación física WebView2/audio/FPS. El componente se integra al frontend; no se construye EXE, instala, hace commit/push/tag ni publica release. La build0021 del traspaso anterior no contiene estas flechas.
- Se preservan las modificaciones concurrentes de contenido/FIX-262 en Apple/core/Tauri/UI y los registros anteriores. Las490pruebas describen esa ejecución del checkout compartido; el manifiesto de252fuentes detectó dos cambios ajenos durante la verificación y no se presenta como una congelación de todo el repositorio. El ajuste final de centrado de filtros de Inicio sólo cambia la ubicación del control y se repite en la matriz de navegador/build frontend.
