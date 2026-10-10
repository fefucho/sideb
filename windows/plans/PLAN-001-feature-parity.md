# PLAN-001 — Paridad de funciones y diseño Mac → Windows

- Fecha: 2026-10-09 (America/Montevideo).
- Estado: auditoría de origen conservada; integración Windows ejecutada en [PLAN-003](PLAN-003-macos-integration.md), aceptación física pendiente.
- Objetivo: llevar Windows al comportamiento y presentación de la app Apple vigente, conservando las capacidades Windows que ya funcionan.
- Seguimiento: [PARIDAD](../../PARIDAD.md) conserva el estado agregado de cada port. Este archivo descompone esos PAR en pasos de ejecución y aceptación; no es un registro paralelo de fixes.
- Referencia: árbol de trabajo actual, incluidos los cambios Apple de traducciones de FIX-131. No comparar sólo contra el último commit o una release Windows antigua.
- Alcance: `windows/` y su integración Tauri. El core común ya ofrece las APIs de catálogo, regiones, historial y Genius necesarias. No modificarlo por necesidades exclusivas Windows.
- Entrega de la auditoría original: análisis y planificación. La ejecución posterior, sus fixes, comprobaciones y límites están en [PLAN-003](PLAN-003-macos-integration.md); no se publicó una release.

## Recepción en Windows — 2026-10-09

Recibido desde `origin/main` en `d37c1ee`. La auditoría de origen usó el baseline Windows de 117 pruebas; esta máquina conservaba trabajo posterior sin commit, con 167 pruebas. El checklist sigue siendo una propuesta y se debe contrastar con ese destino integrado antes de abrir cada tarea. No se declaran ausentes funciones ya implementadas ni se marca aceptación nativa sólo por pruebas frontend.

| Tareas que se solapan | Destino local conservado | Evidencia y límite |
|---|---|---|
| NAV-07 / BIB-01 | Crear desde Sidebar/Biblioteca/menú con editor común, 5000 caracteres y tres privacidades | [FIX-120-2](../../FIXES.md#fix-120-2); formulario/foco y guardas verificados; mutación con cuenta real pendiente |
| FS-04 | Portada activa con clic/Enter/Space, overlay negro 22%, Play/Pausa y foco | [FIX-122-2](../../FIXES.md#fix-122-2); fixture y frontend aprobados, validación WebView2/audio pendiente |
| NAT-02, parte Space | Atajo contextual, sin autorepeat ni captura de edición/controles/diálogos | [FIX-122-2](../../FIXES.md#fix-122-2); los restantes comandos del ítem se mantienen pendientes |
| DET-10 / BIB-06, parte listas | TrackList compartido y viewport acotado en detalle/cuenta/Historial/cola | [FIX-119-2](../../FIXES.md#fix-119-2), [FIX-121-2](../../FIXES.md#fix-121-2); nueva cabecera/densidad/grids y ensayo nativo requieren revisión propia |
| INI / CAR, base anterior | Inicio personalizado, fuentes/configuración, cartas contextuales, feed explícito y ventanas de UI | [FIX-113-2](../../FIXES.md#fix-113-2)–[FIX-116-2](../../FIXES.md#fix-116-2); comparar con las mejoras Apple recién recibidas, especialmente suspensión fullscreen e identidad |
| FS-05 | Windows conserva los controles de cola integrados; Apple acaba de añadir su excepción propia | [FIX-121-2](../../FIXES.md#fix-121-2) frente a [FIX-113 Apple](../../FIXES.md#fix-113); analizar variante, no sustituir acciones durante la sincronización |

**Decisión de producto vigente:** conservar sidebar expandida de 230 px y rail compacto de 60 px. El pedido posterior del 2026-10-10 mueve Atrás/Adelante desde Sidebar a TitleBar y elimina Volver ([FIX-139](../../FIXES.md#fix-139), [PLAN-004](PLAN-004-player-shell-corrections.md)). NAV-01/02/03/05/06 y FS-01/03 contienen propuestas dependientes del shell Apple; no revierten automáticamente esa decisión ni se ejecutan por recibir este documento. El resto del plan se mantiene para trabajo posterior. Las casillas originales permanecen como auditoría de origen hasta evaluar la aceptación completa de cada tarea.

Los FIX Windows concurrentes se distinguen con sufijo `-2`, conservando alias original. PAR-011-2 a PAR-017-2 contienen el seguimiento local; PAR sin sufijo conserva el significado publicado en este plan. [PARIDAD](../../PARIDAD.md) reúne ambos sin perder evidencia.

### Verificación de la integración recibida

Ejecutada en Windows el 2026-10-09 sobre `d37c1ee` más los cambios locales conservados:

| Comprobación | Resultado |
|---|---|
| `pnpm check` | 0 errores, 0 advertencias |
| `pnpm test` | 167/167 aprobadas |
| `pnpm build` | Frontend aprobado |
| `windows/scripts/windows.ps1 -Action verify` | Aprobado: frontend, 92 InnerTube, 90 core y 92 core/windows-bridge (7 live ignoradas por variante), 4 player, 50 Tauri |
| `node --test Scripts/build-version.test.mjs` | 9 aprobadas, 1 caso de empaquetado Mac omitido en Windows; pruebas del runner con ejecutores ficticios, no build Mac |
| Git/documentos | Diff sin errores de whitespace, FIX/PAR únicos, fuentes locales Windows idénticas al respaldo y `main` alineado con `origin/main` (0/0) |

Advertencias Rust de campos no leídos y LNK4098 presentes; no impidieron verify. Log local ignorado: `windows/.cache/sync-2026-10-09-verify.log`. Caché Cargo existente en D: y PSModulePath aislado durante el proceso. No se generó build standalone ni se verificaron UI WebView2/audio/cuenta/gestos nativos. No se creó un commit ni se hizo push; el trabajo Windows sigue local.

## Cómo leer y actualizar el checklist

**F**: comportamiento ausente en el código Windows revisado. **P**: implementación existente que necesita ampliación o rediseño. **A**: equivalente funcional que requiere integración nativa Windows. **V**: verificación pendiente, sin afirmar una ausencia. **D**: decisión de producto, fuera del requisito automático de paridad.

Hay **113 tareas**, incluidas adaptaciones, decisiones y verificaciones; no son 113 funciones inexistentes. Una casilla se marca al cumplir su aceptación, con fix/build/evidencia enlazados y PARIDAD actualizado. La inspección estática confirma diferencias de código, pero no certifica funcionamiento, audio o rendimiento de destino. Las referencias de línea corresponden al árbol auditado y pueden moverse.

## Bases que ya existen y deben conservarse

| Área | Implementación Windows encontrada | Diferencia que sí queda |
|---|---|---|
| Reproducción | libmpv, transporte, seek, volumen/mute, artwork con alternativas y barra flotante centrada | Persistencia, historial, inicio progresivo, activación contextual e integración del sistema |
| Cola | Rust autoritativo, `entryId`, tandas, orden original, shuffle reversible, anclas, insert/move/remove, drag y teclado | Guardado entre ejecuciones, extensión progresiva e intención Next pendiente; ajustes visuales |
| Letras | Sincronizadas y texto simple, seguimiento, pausa al scroll, seek por línea, error/reintento | Segundo modo Genius y anotaciones |
| Recomendaciones | Cuatro grupos, carga diferida, refresh y fallos parciales | Pausa/reanuda por origen y exclusión por Dislike |
| Navegación | Atrás/Adelante, Alt+flechas, botones laterales del mouse, snapshots y scroll vertical | TopNav, Explorar y gestos con respuesta visual |
| Catálogo | Álbum, playlist, artista, catálogo completo de artista, créditos navegables y menús | Cartas comunes, presentación nueva, filtro/orden local y rendimiento |
| Cuenta y biblioteca | Login WebView2, cookies protegidas DPAPI, invalidación de sesión, cuatro pestañas, historial agrupado | Acciones puntuales de sidebar/Biblioteca y registro de escuchas |
| Listas propias | Crear/editar/eliminar, privacidad, añadir/quitar por ocurrencia, ordenar/mover remoto | Unificar editor, completar catálogo antes del drag y separar orden local/remoto |
| Buscar | Seis filtros, preview con debounce, Spotlight, Escape/foco/errores y snapshots | `topSongs`, relacionadas en preview, créditos rápidos y controles comunes |
| Ventana y updates | Minimizar/maximizar/cerrar/drag; F11 separado del reproductor; updater con progreso/skip/reintento | Integrar nuevo shell, acceso manual para invitado, notas legibles y ensayo nativo |

Estas bases se localizaron en [ruta/controladores](../src/routes/+page.svelte), [cola Rust](../src-tauri/src/queue.rs), [comandos playback](../src-tauri/src/commands/playback.rs), [cuenta](../src/lib/account/controller.ts), [letras](../src/lib/player/lyrics.ts), [recomendaciones](../src/lib/player/recommendations.ts), [búsqueda](../src/lib/search/controller.ts) y [actualizador](../src/lib/updater/controller.ts).

## Orden de implementación recomendado

| Etapa | Trabajo | Dependencias y tamaño relativo |
|---|---|---|
| 0 | Asegurar baseline y contratos existentes; preparar fixtures y verificaciones | Antes de cada port; esfuerzo pequeño |
| 1 | Idiomas, identidad contextual, cartas comunes y nuevo shell/configuración | Base transversal; esfuerzo grande |
| 2 | Persistencia/volumen/historial e inicio progresivo | Prioridad funcional alta; puede avanzar junto con el diseño; esfuerzo grande |
| 3 | Inicio completo, fuentes, metadata, caché, ambiente y virtualización | Etapa 1; rendimiento incluido desde el comienzo; esfuerzo muy grande |
| 4 | Detalles, Biblioteca, Historial, búsqueda y artista/catálogos con componentes comunes | Cartas/shell y contratos de reproducción; esfuerzo grande |
| 5 | Explorar, lanzamientos, géneros/momentos y rankings regionales | Cartas/virtualización + bridge regional; esfuerzo grande |
| 6 | Genius completo, información de canción y refinamientos fullscreen | Bridge/controller/panel; reutiliza shell, idioma y foco; esfuerzo grande |
| 7 | Gestos Windows, controles multimedia y comandos de app | Investigación de entrada puede empezar antes; cierre requiere Windows real |
| 8 | QA comparativa, rendimiento/audio, instalador y actualización | Repetir por etapa y cerrar conjunto al final |

El objetivo final es todo el checklist; cada etapa debe dejar la app utilizable y verificable. Los tamaños son relativos, sin estimación de días mientras falten mediciones y host Windows. Evitar juntar todos los cambios antes de probar reproducción y navegación.

## 1. Idiomas — PAR-014

Evidencia: [catálogo/glosario ES/EN](../../apple/Localization/README.md), [resolver Apple](../../apple/Sources/SideB/Utilities/Localization.swift), [Configuración Apple](../../apple/Sources/SideB/Views/Home/HomeSettingsPanel.swift#L61). Windows tiene textos literales y no se encontró catálogo, resolver, preferencia ni selector de idioma; la configuración existente en updater es otra función.

- [ ] **IDI-01** · F · Incorporar las 688 claves y glosario vigentes como recursos consumibles por TypeScript, con resolver reactivo ES/EN; agregar claves exclusivas Windows sin mantener dos traducciones divergentes.
- [ ] **IDI-02** · F · Guardar idioma por instalación, español predeterminado y respaldo; selector primero en General, con Español/English. No vincularlo a cuenta, país de rankings o idioma del proveedor.
- [ ] **IDI-03** · F · Traducir shell, cards, Inicio, detalles, biblioteca, búsqueda, player, cola, letras/Genius, login y updater, incluyendo tooltips, nombres accesibles, menús y estados de carga/vacío.
- [ ] **IDI-04** · F · Presentar errores propios mediante clave/argumentos y resolver plurales, cantidades y resúmenes al mostrar; un aviso ya abierto cambia de idioma. Nombres, letras y notas externas conservan su contenido.
- [ ] **IDI-05** · F · Reetiquetar sin recrear shell/player/controladores, hacer nuevas consultas ni resetear selección, editor, scroll, páginas, imágenes o cola; conservar IDs/raw values/query y metadata original.
- [ ] **IDI-06** · V · Añadir verificación de cobertura ES/EN, argumentos/plurales y recursos empaquetados; probar cambio en vivo sobre menús, búsqueda, lista filtrada y reproducción. Las pruebas Apple no verifican el resolver Windows.

## 2. Shell, navegación y sidebar — PAR-007/008/018/019

Evidencia Apple: [TopNavigationView:80](../../apple/Sources/SideB/Views/Components/TopNavigationView.swift#L80), [HistoryToolbarView:45](../../apple/Sources/SideB/Views/Components/HistoryToolbarView.swift#L45), [ShellLayout:6](../../apple/Sources/SideB/UI/ShellLayout.swift#L6), [SidebarView:159](../../apple/Sources/SideB/Views/Sidebar/SidebarView.swift#L159). Windows: [TitleBar:67](../src/lib/components/shell/TitleBar.svelte#L67), [Sidebar:181](../src/lib/components/sidebar/Sidebar.svelte#L181), [ruta:685](../src/routes/+page.svelte#L685).

- [ ] **NAV-01** · F · Selector superior Inicio/Explorar/Biblioteca/Buscar, visible al cerrar sidebar y fuera del fullscreen del reproductor; mantener controles y región de arrastre Windows.
- [ ] **NAV-02** · P · Selección superior coherente con último destino principal, detalles, subrutas, Spotlight y Atrás/Adelante; callbacks y superficies activas correctos al invertir rápidamente el sidebar.
- [ ] **NAV-03** · P · Completar grupo Actualizar/Atrás/Adelante/Configuración y centrarlo sobre la ubicación del panel abierto o cerrado; disponibilidad por contexto y sin colisión con selector/ventana al resize.
- [ ] **NAV-04** · F · Configuración como overlay derecho, referencia 292 de ancho/inset 6, sin reducir viewport ni mover player; cerrar con Escape/X y cambios de ruta/búsqueda/fullscreen, sin reapertura automática.
- [ ] **NAV-05** · P · Sidebar flotante de 230 con inset 6/radio 10, material, borde y sombra compatibles con Windows; fondo Home/fullscreen/detalle visible detrás, con fallback legible.
- [ ] **NAV-06** · P · Sidebar cerrado sin el rail permanente de 60 si se mantiene la referencia Apple; coordinar reserva, TopNav y centro del player. La barra flotante centrada ya existe.
- [ ] **NAV-07** · P · Botón crear lista desde sidebar, conectado al editor/API actuales; éxito actualiza colecciones y abre destino correcto sin exigir ir a Biblioteca.
- [ ] **NAV-08** · P · Reintento accionable en listas/álbumes de sidebar cuando hay error y colección vacía; reusar carga existente con guardas de sesión.
- [ ] **NAV-09** · P · Menú de Tus Me gusta en sidebar por clic derecho y teclado, equivalente a los menús de colecciones guardadas que Windows ya tiene.

## 3. Carátulas, filas y acciones comunes — PAR-009

Evidencia Apple: [MediaArtworkControls:31](../../apple/Sources/SideB/Views/Common/MediaArtworkControls.swift#L31), [MediaPlaybackIdentity:4](../../apple/Sources/SideB/Models/MediaPlaybackIdentity.swift#L4), [PlayerViewModel:417](../../apple/Sources/SideB/ViewModels/PlayerViewModel.swift#L417). Windows: [HomeCard:23](../src/lib/components/home/HomeCard.svelte#L23), [SearchResultCard:17](../src/lib/components/search/SearchResultCard.svelte#L17), [TrackTable:25](../src/lib/components/detail/TrackTable.svelte#L25), [política menú:69](../src/lib/menu/policy.ts#L69).

- [ ] **CAR-01** · F · Componente de carátula común: canción Play centrado; colección cuerpo abre detalle y Play independiente abajo derecha; puntos arriba derecha. Controles hermanos, una sola acción por interacción.
- [ ] **CAR-02** · P · Hover/foco reales revelan Play/Pause/puntos; rojo sólo al hover del botón Play de colección. Selección persistente no mantiene overlays; foco de teclado conserva controles visibles.
- [ ] **CAR-03** · F · Identidad por contexto/tipo/ID canónico para pausa/reanuda sin reconstruir cola, incluso si una radio avanzó; no activar un álbum sólo porque la canción de radio pertenece a él.
- [ ] **CAR-04** · F · Barras de reproducción en colección y semilla de radio activas, quietas/tenues al pausar; animar sólo visibles con app activa y respetar Reduce Motion/fullscreen.
- [ ] **CAR-05** · P · Reproducir por toda zona no interactiva de fila, dejando artista/álbum/Like/menú independientes; Ctrl/Shift conservan selección y no provocan playback.
- [ ] **CAR-06** · P · Adoptar controles comunes en Inicio, destacados, Biblioteca, Buscar/Spotlight, artista/catálogos, relacionados de álbum y recomendaciones; conectar puntos al motor de menú existente.
- [ ] **CAR-07** · P · Menús de cartas conocen Guardar/Quitar desde biblioteca cacheada, sin exigir siempre detalle; resolver capacidades faltantes bajo demanda y sin inventar propiedad o destino.
- [ ] **CAR-08** · P · Imágenes dimensionadas al uso, placeholder/reintento e identidad/cancelación al reciclar; limitar montajes y memoria, preservando el fallback de artwork fullscreen ya existente.

Aceptación transversal: abrir portada no reproduce; Play no navega; menú/enlace no dispara ambas acciones; la fuente activa conserva ocurrencia, cola y posición. Probar todas las superficies, no sólo Inicio.

## 4. Inicio personalizado y optimización — PAR-002/003/004/005/006/008

Evidencia Apple: [HomeView:151](../../apple/Sources/SideB/Views/Home/HomeView.swift#L151), [selección destacados:43](../../apple/Sources/SideB/Models/HomeFeaturedPresentation.swift#L43), [HomeFeaturedView:91](../../apple/Sources/SideB/Views/Home/HomeFeaturedView.swift#L91), [settings/modelo:186](../../apple/Sources/SideB/Models/HomeRecommendationSettings.swift#L186), [HomeViewModel:299](../../apple/Sources/SideB/ViewModels/HomeViewModel.swift#L299), [metadata álbum](../../apple/Sources/SideB/Models/HomeAlbumMetadata.swift), [metadata playlist](../../apple/Sources/SideB/Models/HomePlaylistMetadata.swift), [cache](../../apple/Sources/SideB/Services/HomeFeedCacheStore.swift). Windows: [HomeView:105](../src/lib/components/home/HomeView.svelte#L105), [presentación](../src/lib/home/presentation.ts), [controller:35](../src/lib/home/controller.ts#L35), [HomeShelf:56](../src/lib/components/home/HomeShelf.svelte#L56). Especificación ampliada: [PORTEO-INICIO](../../PORTEO-INICIO.md).

- [ ] **INI-01** · F · Cabecera con saludo por horario, nombre/avatar y fallback invitado; tres franjas horarias y nombre largo legibles, sin conservar datos de otra cuenta.
- [ ] **INI-02** · F · Acceso rápido 3×3, hasta 27 canciones únicas y tres páginas, prioridades vigentes, flechas/puntos accesibles; navegar página no inicia reproducción.
- [ ] **INI-03** · F · Destacados álbumes/listas: dos filas, 1/2/3 columnas, 2/4/6 por página y seis páginas; fila compartida con Acceso rápido desde 900 de ancho de contenido, apilada debajo.
- [ ] **INI-04** · F · Fuentes independientes por tipo y prioridad estricta: llenar cupo desde primera fuente antes de siguiente, deduplicar ID canónico; todas desactivadas deja vacío, sin sustituir tipo.
- [ ] **INI-05** · F · Suplementos de listas/álbumes guardados y álbumes recientes de Side B sólo si fuente habilitada lo requiere; usar APIs existentes, sin cargar catálogos completos ni inventar álbum sin ID.
- [ ] **INI-06** · F · Tipo destacado global y reglas versionadas por cuenta/guest; defaults y migración segura, A→B→A recupera sus preferencias sin mezclar datos.
- [ ] **INI-07** · F · Configuración de fuentes: activar/desactivar, botones y drag para prioridad, restaurar defaults y estados de biblioteca; preservar foco/Space y feed/cursor.
- [ ] **INI-08** · P · Categorías dinámicas con checkbox sólo de estante, órdenes Side B/YouTube/personalizado, búsqueda si hay más de ocho y reordenamiento/restauración; ocultarlas no retira aportes a destacados.
- [ ] **INI-09** · F · Metadata de álbumes de página visible: artista y destino real, año/count/duración verificables; máximo dos solicitudes simultáneas y LRU seis, generación/cancelación por cuenta/página.
- [ ] **INI-10** · F · Metadata de listas visibles con creador real y totales declarados o catálogo completo; no presentar primera tanda como total. Mismo presupuesto dos/LRU seis y fallback de crédito actualizado.
- [ ] **INI-11** · F · Ambiente global desde hasta cuatro portadas únicas, base grafito, acentos separados y contraluz acotada; caché limitada y neutral inmediato al cambiar cuenta.
- [ ] **INI-12** · F · Humo/nubes de textura compartida con deriva/parallax lentos; pausar por inactividad/minimización/Reduce Motion/fullscreen conservando fase, sin generar textura por frame.
- [ ] **INI-13** · P · Cargar más explícito: hasta tres continuaciones si no cambian contenido visible, incluyendo duplicadas/vacías/ocultas; fin/no novedades/error/reintento. Reusar dedupe/tokens/generaciones existentes.
- [ ] **INI-14** · P · Precarga prioritaria hasta tres páginas/12 s, parando al llegar fuentes habilitadas y omitiéndola si ya están presentes; no seguir cargando todo el feed automáticamente.
- [ ] **INI-15** · F · Feed guardado por cuenta para mostrar al relanzar y refrescar después; hasta cuatro snapshots RAM por chip con cursor y rollback de selección ante fallo. No guardar continuation ni cookies en disco.
- [ ] **INI-16** · F · Virtualización vertical de estantes y horizontal de tarjetas: DOM/callbacks/imágenes limitados al viewport y offsets locales conservados; `loading=lazy` actual no basta.
- [ ] **INI-17** · F · Identidad plana/ancla de destacados al variar columnas o cruzar 900; conservar controles, artwork, metadata y colección visible sin rehacer nodos por columna.
- [ ] **INI-18** · P · Señal visible/tapado para detener medición, observers, reflow y trabajo decorativo bajo fullscreen; aplicar último viewport/datos antes de revelar, conservando scroll/página/fase sin expandir shell.
- [ ] **INI-19** · P · Retirar flechas de estantes genéricos como Apple vigente; conservar desplazamiento horizontal, Ver más y controles de páginas de destacados.
- [ ] **INI-20** · P · Mostrar Sencillo/EP/Álbum según prefijo real del proveedor, conservando tipo/ID de álbum para acciones y nombres originales.

Aceptación: fixtures de muchas categorías, fuentes desactivadas, duplicados VL/LM, páginas incompletas, reintentos y cambios rápidos de cuenta/chip/ancho. Verificar límites de solicitudes/LRU/DOM y conservación al fullscreen; medir consumo en WebView2. Los pools/rebind descartados de FIX-101 no son la solución de referencia.

## 5. Álbumes y playlists — PAR-011

Evidencia Apple: [CollectionDetailHeaderView:33](../../apple/Sources/SideB/Views/Detail/CollectionDetailHeaderView.swift#L33), [DetailTrackProjection:48](../../apple/Sources/SideB/Models/DetailTrackProjection.swift#L48), [PlaylistDetailViewModel:52](../../apple/Sources/SideB/ViewModels/PlaylistDetailViewModel.swift#L52), [ambiente:21](../../apple/Sources/SideB/Views/Detail/CollectionAmbientBackground.swift#L21). Windows: [AlbumDetailView:52](../src/lib/components/detail/AlbumDetailView.svelte#L52), [PlaylistDetailView:69](../src/lib/components/detail/PlaylistDetailView.svelte#L69), [AccountTrackTable:36](../src/lib/components/library/AccountTrackTable.svelte#L36), [mutaciones:274](../src/lib/account/controller.ts#L274).

**Scroll común ya existe en Windows**: cabecera y canciones están en `.content-column`, sin tabla con otro scroll vertical. Conservarlo al virtualizar; no crear una tarea para algo presente.

- [ ] **DET-01** · P · Cabecera común por capacidades, portada referencia 216 y datos/acciones +20%, toolbar inferior y adaptación estrecha; mantener descripción, guardar, editar y permisos actuales.
- [ ] **DET-02** · P · Viewport y separación superior coherentes con TopNav, inset dentro del documento; revisar Volver sticky/padding externo redundantes sin introducir scroll doble.
- [ ] **DET-03** · F · Ambiente de portada detrás de todo el shell, luz .58/.50 y humo .25/.20, extensión 140 bajo header/fade; seguir geometría sin publicar offset por píxel, pausando oculto/inactivo.
- [ ] **DET-04** · F · Filtro local normalizado por título/artista/álbum; clear estable vacía y mantiene edición, Escape/clic exterior desenfoca sin borrar, sin rectángulo interior ni altura animada al escribir.
- [ ] **DET-05** · P · Orden local personalizado/título/artista/álbum/duración también para ajenas/Me gusta; newest/oldest sólo si proveedor/capacidad permiten. Separar proyección local de mutación remota.
- [ ] **DET-06** · P · Catálogo completo y proyección por ocurrencia antes de ordenar localmente o drag; fila filtrada inicia ocurrencia exacta en colección completa/orden elegido, sin truncar reproducción.
- [ ] **DET-07** · P · Drag propio sólo con catálogo completo, custom, sin filtro/carga/mutación e IDs únicos; sucesor real y rollback. Conservar serialización de mutaciones y bloqueo del selector remoto que Windows ya implementa.
- [ ] **DET-08** · P · Filas 58/portada 44/Play 32/acciones 28, columnas por capacidades y Like/menú separados; playlist muestra artista/álbum/duración, álbum omite columna Álbum y selector de orden.
- [ ] **DET-09** · P · Fallback visual/de menú del artista de header sólo si crédito coincide y fila no tiene IDs/runs propios, sin asignar destino a invitados. El override de artista durante playback también existe en Apple y requiere revisión separada de ambas plataformas.
- [ ] **DET-10** · P · Virtualizar filas/cabecera/footer en un documento común, preservando foco, selección, scroll, menú y drag; no montar miles de filas aunque las imágenes sean lazy.

Aceptación especialmente importante: lista 250 con prefijo 100 no mueve la última visible al final real por desconocer sucesor; duplicadas por videoId mantienen setVideoId y ocurrencia. Filtrar sólo oculta, ordenar localmente no modifica YouTube y error no pierde orden/catálogo/audio.

## 6. Biblioteca e Historial — PAR-018/017/009/010

Evidencia Apple: [LibraryViewModel:352](../../apple/Sources/SideB/ViewModels/LibraryViewModel.swift#L352), [HistoryView:124](../../apple/Sources/SideB/Views/History/HistoryView.swift#L124), [PlaylistEditorSheet](../../apple/Sources/SideB/Views/Detail/PlaylistEditorSheet.swift). Windows: [LibraryView:143](../src/lib/components/library/LibraryView.svelte#L143), [editor común:36](../src/lib/components/detail/PlaylistEditorDialog.svelte#L36), [account controller:103](../src/lib/account/controller.ts#L103), [HistoryView:26](../src/lib/components/library/HistoryView.svelte#L26).

- [ ] **BIB-01** · P · Crear desde Biblioteca con editor común de nombre/descripción/privacidad, incluido límite vigente 5000; ya existen API y editor más completo desde menú, no duplicarlos.
- [ ] **BIB-02** · P · Precargar canciones hasta 100 tras primera página y cargar cerca del final, con fallback explícito accesible; reintento sin vaciar contenido, audio o scroll. Refresh conserva cantidad razonable.
- [ ] **BIB-03** · P · Álbumes guardados en orden alfabético estable como Apple, también tras guardar/refresh; listas mantienen su orden definido.
- [ ] **BIB-04** · F · Incorporar reproducción registrada al Historial abierto sin pedir todo de nuevo, manteniendo grupos/ocurrencias y evitando duplicación por eventos de progreso. Depende REP-03.
- [ ] **BIB-05** · F · Segunda activación de ocurrencia actual del Historial pausa/reanuda conservando cola; otra repetida en otro grupo sigue siendo una ocurrencia diferente.
- [ ] **BIB-06** · P · Virtualizar canciones, grupos de Historial y grids grandes, integrando cabecera/estados; adoptar cartas y menú Guardar/Quitar de CAR sin rehacer las cuatro pestañas.

## 7. Buscar y Spotlight — PAR-018/009

Evidencia: [SearchResultsRecord:400](../../core/crates/sideb-core/src/lib.rs#L400) ya contiene `top_songs`; [SearchViewModel:306](../../apple/Sources/SideB/ViewModels/SearchViewModel.swift#L306) los usa. [DTO Windows:20](../src-tauri/src/lib.rs#L20) y [types:81](../src/lib/types.ts#L81) los omiten; [QuickResults:67](../src/lib/components/search/QuickResults.svelte#L67) sólo usa el primer top.

- [ ] **BUS-01** · P · Transportar `topSongs` tipados Tauri→TS, snapshots/caché/preview; resolver SongDto real por ID en vez de reconstruir tarjeta perdiendo tokens de biblioteca/setVideoId/créditos.
- [ ] **BUS-02** · F · Hasta tres canciones relacionadas bajo mejor resultado en dropdown y Spotlight; reutilizar relacionadas que ya existen en búsqueda completa, con menús y acciones correctas.
- [ ] **BUS-03** · P · Artista/álbum navegables independientemente de Play en búsqueda rápida, usando IDs reales y ArtistCredits; navegar cierra Spotlight coordinadamente y conserva audio.
- [ ] **BUS-04** · P · Integrar cartas/filas nuevas y virtualización en resultados; preservar seis filtros, debounce, estados parciales, foco, cierre y snapshots. Preview sigue sin registrar historial de búsqueda.

## 8. Explorar, lanzamientos y rankings — PAR-012

Evidencia Apple: [ExploreCatalog:3](../../apple/Sources/SideB/Models/ExploreCatalog.swift#L3), [ExploreView:46](../../apple/Sources/SideB/Views/Explore/ExploreView.swift#L46), [ExploreViewModel:121](../../apple/Sources/SideB/ViewModels/ExploreViewModel.swift#L121), [grid optimizado](../../apple/Sources/SideB/Views/Explore/ExploreCatalogGridView.swift). Windows no tiene rutas/vistas Explore en [ruta:48](../src/routes/+page.svelte#L48). [Comandos catálogo:217](../src-tauri/src/commands/catalog.rs#L217) ya exponen browse grid/search; [core:800](../../core/crates/sideb-core/src/lib.rs#L800) ya ofrece detección y charts.

- [ ] **EXP-01** · F · Controller/rutas Descubrir/Lanzamientos/Rankings/Géneros/Momentos/categoría/país; entrada TopNav, selección, refresh e historial correctos al ir a detalles y volver.
- [ ] **EXP-02** · F · Portada Descubrir con tabs, shortcuts novedades/rankings, preview hasta 12 álbumes/sencillos y Ver todo, ocho momentos y preview de ocho géneros.
- [ ] **EXP-03** · F · Catálogo vigente de 16 géneros y ocho momentos con ID estable, presentación localizable y consulta exacta de listas; no traducir query del proveedor al cambiar etiqueta.
- [ ] **EXP-04** · F · Catálogo real de lanzamientos mediante browse existente y categorías mediante search playlists; dedupe tipo+ID, datos válidos y estados carga/vacío/error/reintento.
- [ ] **EXP-05** · F · Bridge Tauri/DTO/TS para `detect_music_country` y `get_charts`, con selectedCountry/countries/items y confirmación del país; grid genérico no transporta formData/regiones.
- [ ] **EXP-06** · F · Global + región detectada por conexión anónima YouTube, TTL 10 min y refresh con redetección; Uruguay cuando corresponda, otro país si cambia conexión, Global útil ante fallo.
- [ ] **EXP-07** · F · Selector Global/tu región/todos los países devueltos por proveedor, nombres según idioma y selección confirmada. No fijar Uruguay/US ni hardcodear cantidad de países.
- [ ] **EXP-08** · F · Aislamiento por sesión/ruta/país/refresco, LRU ocho fuentes/ocho regiones, fallos parciales y retry; respuesta tardía de otra selección no reemplaza catálogo.
- [ ] **EXP-09** · F · Virtualizar catálogo y preview horizontal desde el inicio, IDs planos, imágenes/callbacks acotados y playback sólo visible; conservar controles/offset al reciclar y suspender cubierto/inactivo.

Aceptación: Global/UY con fuentes distintas, región no confirmada rechazada, local fallida no elimina Global, selector toma lista real y Atrás/Adelante recupera país. Fixture 5000 álbumes prueba DOM limitado y acciones al ID pintado; perfil WebView2 comprueba rendimiento real. No portar sólo apariencia y dejar el problema de lag para después.

## 9. Reproducción, persistencia y contexto — PAR-016/017/010/021/009

Evidencia Apple: [PlaybackStateStore:6](../../apple/Sources/SideB/Services/Player/PlaybackStateStore.swift#L6), [AudioPlayerService:17](../../apple/Sources/SideB/Services/Player/AudioPlayerService.swift#L17), [PlayerViewModel:287](../../apple/Sources/SideB/ViewModels/PlayerViewModel.swift#L287), [inicio progresivo:545](../../apple/Sources/SideB/ViewModels/PlayerViewModel.swift#L545), [saltos:742](../../apple/Sources/SideB/ViewModels/PlayerViewModel.swift#L742). Windows: [init:105](../src-tauri/src/lib.rs#L105), [store de cookies](../src-tauri/src/session_store.rs), [queue:148](../src-tauri/src/queue.rs#L148), [playback:1045](../src-tauri/src/commands/playback.rs#L1045), [menú:86](../src/lib/menu/executor.ts#L86). Historial existe en [core:1721](../../core/crates/sideb-core/src/lib.rs#L1721), sin caller encontrado en Windows ni `core/crates/player`.

- [ ] **REP-01** · F · Store Rust/Tauri versionado por cuenta/guest con cola, ocurrencias, rangos/anclas/placements/visible count, contexto/radio seed y shuffle/repeat; escritura atómica y recuperación ante corrupción.
- [ ] **REP-02** · F · Restaurar pausado al relanzar o cambiar A→B→A, misma ocurrencia y orden reversible; resolver stream fresco al reanudar. Snapshot UI omite campos privados, no basta guardarlo ni duplicar cola en TS.
- [ ] **REP-03** · F · Registrar reproducción al umbral vigente min(30 s, mitad de duración), una vez por intento/pista; metadata real y playlist source hacia API existente, guardando generación/cuenta y notificando historial.
- [ ] **REP-04** · F · Persistir volumen y último audible antes de mute; aplicar al inicializar motor/UI con límites válidos. Reiniciar silenciado y volver a activar recupera volumen anterior sin iniciar audio.
- [ ] **REP-05** · P · Iniciar playlist/Me gusta desde prefijo cargado inmediatamente en modo normal y completar fuente en background; elegir ocurrencia exacta. Aleatorio inicial sigue esperando catálogo completo.
- [ ] **REP-06** · P · Reproducción de Biblioteca completa su fuente y no queda limitada a canciones ya cargadas; reutilizar flujo progresivo, sin segunda cola ni reset del audio.
- [ ] **REP-07** · P · Completar suffix conservando inserts/moves/removes/ocurrencia activa/shuffle/anclas y tokens; error conserva prefijo/token para retry, sesión/cola nueva rechaza publicación tardía.
- [ ] **REP-08** · P · Intención Next manual al borde mientras fuente extensible carga; consumir una vez al llegar próxima pista, cancelar por epoch/cuenta y distinguir fin agotado, repeat y EOF natural.
- [ ] **REP-09** · P · Coalescer saltos manuales rápidos antes de stream/letras, referencia Apple 180 ms; selección responde inmediatamente y sólo intento final carga. No retrasar EOF ni play directo sin motivo.
- [ ] **REP-10** · P · Radio de álbum/playlist/artista desde menú conserva origen y endpoint/radioId, en lugar de pedir radio de primera canción como hoy; unificar con botón artista ya operativo.
- [ ] **REP-11** · P · Dislike retira la canción también de recomendaciones cargadas, coordinado con rating/rollback y sesión; conservar eliminación por entryId de la ocurrencia de cola, ya existente.
- [ ] **REP-12** · P · Conservar `isUpload` en Song/Playback/Queue DTOs, TS, constructores, cola y persistencia, y pasarlo a `resolve_stream`; Windows hoy fuerza false. Probar la rama autenticada ya existente del core, sin inventar una nueva pestaña de subidas.

Aceptación: duplicados, mutaciones durante carga, pausas/Next rápido, EOF tardío, catálogo fallido y cambio de cuenta. Guardar sólo metadata durable: excluir cookies/headers/URLs firmadas y generaciones de audio. Apple restaura cola pausada; su esquema no guarda el segundo exacto, por lo que no prometerlo como paridad implementada. Para subidas, [Apple:804](../../apple/Sources/SideB/ViewModels/PlayerViewModel.swift#L804) transmite el indicador y [Windows:524](../src-tauri/src/commands/playback.rs#L524) fuerza false: la pérdida de metadata está confirmada; el efecto audible exige ensayo autorizado en Windows.

## 10. Genius completo e información — PAR-015

Evidencia: [core:1852–1926](../../core/crates/sideb-core/src/lib.rs#L1852) ya resuelve/cachea/busca/elige/reporta letras y anotaciones. [GeniusViewModel](../../apple/Sources/SideB/ViewModels/GeniusViewModel.swift), [GeniusPanelView](../../apple/Sources/SideB/Views/Fullscreen/GeniusPanelView.swift) y [información fullscreen:197](../../apple/Sources/SideB/Views/Fullscreen/FullscreenNowPlayingView.swift#L197) son referencia. Windows [PlayerBar:237](../src/lib/components/player/PlayerBar.svelte#L237) lo deshabilita y no expone comandos/DTO/controller/panel Genius.

- [ ] **GEN-01** · F · Comandos/DTO/TS sobre fachada Genius existente: cached/resolve/search/choose/clear/report/annotations/lyrics/metrics; registrar invokes y habilitar entrada Genius como modo de Letras.
- [ ] **GEN-02** · F · Controller por identidad de pista y sesión, caché antes de red, fetch automático opcional tras iniciar playback y carga adelantada al abrir; cancelar y descartar éxitos/errores tardíos.
- [ ] **GEN-03** · F · Estados matched/ambiguous/notFound/error, candidatos, búsqueda manual, elección persistente y cambio reversible; cancelar corrección conserva coincidencia anterior.
- [ ] **GEN-04** · F · Letras por spans/referentId con selección/copiar, hover/foco/clic y resaltado activo; renderer DOM incremental, sin confundir espacios o fragmentos adyacentes.
- [ ] **GEN-05** · F · Anotación anclada al fragmento con cuerpo, autor/verificación, imágenes y enlaces; teclado/Narrator y scroll estable al abrir/cerrar.
- [ ] **GEN-06** · F · Lista/paginación de anotaciones con dedupe por ID, primera lectura limpia y retry que conserva páginas previas; URLs externas compatibles con integración Windows.
- [ ] **GEN-07** · F · Información de canción, descripción, fecha y créditos de producción/composición/performance; vista posterior de artwork o equivalente, fallback sin match y retorno a portada al cambiar pista.
- [ ] **GEN-08** · F · Preferencias persistentes de auto fetch/diagnóstico, menú compacto y guardar pista unresolved para revisar con feedback/dedupe; reporte de A no marca B si cambió pista.

Aceptación: pista A→B y cuenta A→B durante cada fase, ambigüedad sin elegir en silencio, elección durable, retry, caché y contenido accesible. Letras sincronizadas actuales siguen operativas como modo independiente.

## 11. Fullscreen y cola — PAR-008/009

Evidencia Apple: [Backdrop:29](../../apple/Sources/SideB/Views/Fullscreen/FullscreenBackdrop.swift#L29), [SceneLayout:18](../../apple/Sources/SideB/Views/Fullscreen/FullscreenSceneLayout.swift#L18), [artwork:149](../../apple/Sources/SideB/Views/Fullscreen/FullscreenNowPlayingView.swift#L149), [cola específica](../../apple/Sources/SideB/Views/Common/NativeQueueTrackCellView.swift). Windows: [Fullscreen:103/156](../src/lib/components/fullscreen/FullscreenNowPlaying.svelte#L103), [QueuePanel:137](../src/lib/components/fullscreen/QueuePanel.svelte#L137).

- [ ] **FS-01** · P · Backdrop a ventana completa detrás de sidebar/título, separado del foreground con reserva de contenido y fade único; alternar sidebar no recorta/reescala textura ni deja franja.
- [ ] **FS-02** · P · Tipografía/acciones adaptativas y geometría de escena durante sidebar/resize; Windows ya tiene balance de arte/panel y límites, completar sin rehacerlos.
- [ ] **FS-03** · P · Entrada/salida coordinada de fondo y foreground con desplazamiento/fade, Reduce Motion sin traslado; hit testing coherente durante transición y Home sin reflow oculto.
- [ ] **FS-04** · F · Clic/Enter/Space en artwork pausa/reanuda sin reemplazar cola, hover/foco revelan acción; convivir con información Genius y estados loading/error.
- [ ] **FS-05** · P · Cola conserva fila especial 46/Like/Dislike/grip, sin Play flotante ni puntos permanentes; menú por clic derecho/teclado. Exponer conteo total semántico, no confundir tanda publicada con catálogo completo.

## 12. Gestos — PAR-013

Evidencia Apple: [NavigationInputCoordinator](../../apple/Sources/SideB/Services/Navigation/NavigationInputCoordinator.swift), [state machine](../../apple/Sources/SideB/Services/Navigation/WindowGestureStateMachine.swift), [FullscreenGestureMotion](../../apple/Sources/SideB/Views/Fullscreen/FullscreenGestureMotion.swift). Windows sólo tiene navegación por botones/teclado/mouse; no se encontró motor de gestos equivalente.

- [ ] **GES-01** · A · Investigar y documentar eventos reales Precision Touchpad/WebView2 en Windows; decidir detección de contacto/dirección/final/momentum, sin asumir que WheelEvent ofrece fases de NSEvent.
- [ ] **GES-02** · A · Historial horizontal con progreso, destino, armado/cancelación/confirmación y una acción por contacto; guards de modal/menú/ventana/cuenta/ruta/resize, manteniendo mouse/teclado.
- [ ] **GES-03** · A · Propiedad local fija durante contacto: chips/carruseles/paneles paginados de Inicio conservan horizontal incluso al borde; headers/huecos permiten historial. Vertical sigue feed; momentum no cambia otra página.
- [ ] **GES-04** · A · Pull hacia abajo de fullscreen con seguimiento del dedo y snap/cancelación/cierre, fuera de áreas scrolleables como cola/letras/información; reveal conserva Home y Reduce Motion usa alternativa.

Aceptación física obligatoria; no simular que el runtime distingue dedos/fases si todavía no se probó. Háptica/AppKit son específicos de Mac; el requisito portable es respuesta clara y arbitraje estable.

## 13. Integración del sistema, comandos, cuenta y actualizaciones — PAR-020/019/018

Evidencia Apple: [comandos:86–178](../../apple/Sources/SideB/UI/AppMenuCommands.swift#L86), [Space](../../apple/Sources/SideB/Services/Player/PlaybackSpaceShortcut.swift), [Now Playing:1470](../../apple/Sources/SideB/ViewModels/PlayerViewModel.swift#L1470), [cuenta:50](../../apple/Sources/SideB/Views/Sidebar/AccountPopoverView.swift#L50). Windows: [keydown:290](../src/routes/+page.svelte#L290), [auth DTO:5/29](../src-tauri/src/dto.rs#L5), [sidebar:231](../src/lib/components/sidebar/Sidebar.svelte#L231), [notas update:203](../src/lib/components/update/UpdateModal.svelte#L203).

- [ ] **NAT-01** · A · Now Playing/controles multimedia Windows (SMTC o integración elegida): metadata/artwork/estado y play/pause/next/previous/seek a cola autoritativa; limpiar al parar y descartar portada tardía.
- [ ] **NAT-02** · P · Space global sin autorepeat respetando inputs/contenteditable/botones/sliders/login/menús/dialogs; menú/overflow/comandos de app equivalentes para nueva lista, paneles, transporte, volumen, shuffle/repeat y cuenta.
- [ ] **NAT-03** · P · Transportar handle de cuenta como fallback cuando no hay email; mantener login/logout/DPAPI existentes. No trasladar automáticamente el workaround WebAuthn exclusivo WKWebView de Apple.
- [ ] **NAT-04** · P · Buscar actualizaciones accesible también invitado y notas con Markdown/enlaces legibles; reutilizar updater/progreso/skip/retry existentes, sin traducir contenido externo.
- [ ] **NAT-05** · D · Decidir equivalente de selector de salida de audio y acceso a información/créditos de app según UX Windows. AirPlay nativo Mac y Share panel del sistema no son ports literales obligatorios; Copiar enlace Windows ya cumple compartir URL.

## 14. Comprobaciones para cerrar paridad — transversales

- [ ] **QA-01** · V · Por cada etapa, fixtures de generación/cuenta/ruta/ocurrencias y errores; check/tests frontend + compilación de frontend sin avisos relevantes. Actualizar fix/PAR/evidencia, sin declarar runtime por estos checks.
- [ ] **QA-02** · V · En Windows, `windows/scripts/windows.ps1 -Action verify` y runner versionado `node Scripts/build-version.mjs windows` siguiendo [skill Windows](../../.agents/skills/sideb-build-windows/SKILL.md); Tauri/core con y sin windows-bridge/player/empaquetado.
- [ ] **QA-03** · V · Comparación de ventanas/áreas equivalentes, DPI 100/125/150/200, mínimos/resize/sidebar/fullscreen, foco/Tab/Narrator/alto contraste/Reduce Motion; errores y acciones recuperables.
- [ ] **QA-04** · V · Ensayos nativos de audio, EOF/seek/buffering/retry, Next rápido/mute, colas duplicadas y mutaciones durante cargas; controles multimedia y trackpad físicos, con evidencia separada de build.
- [ ] **QA-05** · V · Medir DOM, solicitudes/imágenes, CPU/GPU/memoria y fluidez en Home, lanzamientos largos, tablas y fullscreen; comportamiento oculto sin trabajo recurrente. No inferir FPS por comentarios o cantidades de tests.
- [ ] **QA-06** · V · Cuenta real sólo cuando se autorice ese ensayo: biblioteca/lista propia/Me gusta/historial/región; comparar Home→detalle→Atrás y chip/página/offset en ambas apps antes de afirmar falta de restauración por ruta.
- [ ] **QA-07** · V · Instalación limpia y upgrade/rollback de prueba: definir versión pública Windows frente a 0.1.0 de manifests, elegir asset instalable correcto y verificar descarga/lanzamiento. El selector actual admite zip pero descarga/lanzador usa exe: requiere corrección o rechazo explícito si ese fallback puede ocurrir. Publicación es un pedido posterior.

## Decisiones y elementos excluidos de una promesa de paridad

- [PLAN-008 Apple](../../apple/plans/PLAN-008-home-cleanup-efficiency.md) está propuesto, no implementado: refactor aliases, futuros Canvas/Metal/cambio a 20 fps no son funcionalidades ya portables.
- No revivir pools/rebind de FIX-101 retirados; tomar virtualización vigente y diseñar equivalente Svelte.
- Explore vigente usa categorías Side B y colecciones de ranking por país. Catálogo editorial dinámico y posiciones individuales son etapa futura, no requisito actualmente implementado en Mac.
- No agregar orden por lanzamiento ni fechas inventadas: el catálogo de pistas no ofrece esos timestamps. Newest/oldest remotos sólo según capacidades.
- No exigir filtro local nuevo de Biblioteca/Historial: Apple no lo tiene; sí filtro de detalles.
- No convertir APIs core sin consumidores en funciones faltantes: pinning, offline, EQ, crossfade, gapless, velocidad/pitch o Last.fm no quedan incluidos por existir como idea/API.
- AVPlayer/CoreMedia, AppKit/SwiftUI/Liquid Glass, WKWebView, AirPlay/háptica/menubar son implementaciones Mac. Windows conserva libmpv/WebView2/Tauri y reproduce capacidades/resultado con APIs apropiadas.
- Compartir ya copia enlace correcto en Windows; panel Share nativo adicional queda a decisión.
- Restauración de Home al salir de ruta requiere comparación: Windows ya restaura scroll vertical; no se identificó garantía Apple de páginas/offsets por ruta. Conservación al fullscreen sí está implementada en Apple y debe acompañar al port.

## Evidencia obtenida en esta auditoría

Revisión por tres subagentes de sólo lectura: Inicio/shell, superficies de catálogo/búsqueda y reproducción/integraciones; el integrador contrastó contratos, negativos, solapamientos y cuentas/updater/idiomas. Se inspeccionaron rutas/consumidores/controller/comandos/DTO/core y pruebas actuales; no se dedujo ausencia sólo por nombre de archivo ni por planes históricos.

Comprobaciones nuevas del frontend Windows ejecutadas en **Mac arm64**, 2026-10-09:

| Comando | Resultado |
|---|---|
| `pnpm install --frozen-lockfile` | Completado; lock/manifests sin modificaciones |
| `pnpm check` | 0 errores, 0 avisos |
| `pnpm test` | 117/117 aprobadas, 0 fallos, 0 omitidas |
| `pnpm build` | Bundle de frontend / adapter-static completado |
| Toolchain usada | Node 24.16.0; pnpm 11.19.0 del runtime disponible; manifest declara pnpm 12.6.0 |

Esto comprueba el baseline frontend existente, no las tareas futuras. No es build nativa Tauri Windows ni entrega numerada de aplicación. No se ejecutó UI/audio/instalador/actualización/cuenta real Windows. Los resultados históricos Apple en FIXES/PARIDAD siguen siendo evidencia del origen, no de destino.

Sin nuevos fixes implementados o build Windows que enlazar. Al comenzar el port, actualizar este mismo plan y [PARIDAD](../../PARIDAD.md), registrar cada corrección en [FIXES](../../FIXES.md) y conservar los cambios Apple previos.
