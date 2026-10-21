# PLAN-015 — Sidebar totalmente oculta y navegación superior en Windows

- Fecha: 2026-10-21 (America/Montevideo).
- Estado: **planificado, sin implementación**. El usuario pide preparar el plan mientras se compila Inter; esta build no incorpora la función de navegación.
- Objetivo: ofrecer, en Settings → Apariencia, ocultamiento completo al contraer la sidebar y presentar la topnav vigente de macOS, conservando navegación, búsqueda, cuenta y controles nativos de Windows.
- Alcance: `windows/src/`, pruebas Windows y registros FIXES/PARIDAD. Apple se consulta como origen, sin editar. Sin cambios de core, contratos Rust de audio, credenciales, proveedor de búsqueda, cola o recomendaciones. Sin release/push por este plan.
- Referencias: [PAR-007](../../PARIDAD.md), [PAR-036](../../PARIDAD.md), FIX-193/224/225/240; [plan común de sidebar](../../plans/PLAN-010-sidebar-delivery.md), [apariencia e Inter](PLAN-014-homecoming-inter.md). La exclusión histórica de TopNav Windows se reabre **sólo** para este modo opcional por el pedido actual; las demás exclusiones no se dan por autorizadas.
- Base inspeccionada: `main` `d6e2c4b`, con cambios locales Inter y documentación de build-0017. Conservarlos. Inventario y medidas siguientes describen el código actual; no las variantes históricas retiradas del historial de FIXES.

## 1. Contrato del producto

### Configuración y persistencia

Agregar en Apariencia el selector **«Al contraer la barra lateral»**:

- **Mostrar sólo iconos**: predeterminado, conserva comportamiento actual.
- **Ocultar completamente**: al contraer desaparece toda la columna y se presenta la navegación superior.

Activar esta preferencia no fuerza a cerrar una sidebar abierta. El botón alterna abrir/cerrar; no recorre tres estados. Cambiar la preferencia mientras está contraída aplica el resultado inmediatamente. «Lista/Cuadrícula» sigue siendo una opción independiente para la sidebar desplegada.

Persistir por instalación tanto la preferencia de contracción como el estado abierto/cerrado; sobrevivir reinicio, logout y cambio de cuenta. Campos aditivos propuestos en `AppearancePreferences`: `sidebarCollapseMode: 'icons' | 'hidden'` y `sidebarCollapsed: boolean`. Reutilizar `sideb.appearance.v1`, con defaults `icons`/`false` cuando faltan campos o valores válidos; conservar fondo/lista/cuadrícula/motion existentes. No migración destructiva ni reinicio de otras preferencias. Storage bloqueado conserva funcionamiento en memoria.

### Estados derivados únicos

| Preferencia | Estado | Sidebar efectiva | Topnav de destinos |
|---|---|---|---|
| icons | abierta | Expandida, ancho actual253px | Oculta; TitleBar actual conserva historial |
| icons | contraída | Columna actual60px | Oculta; comportamiento actual |
| hidden | abierta | Expandida, ancho actual253px | Oculta; botón de contraer en sidebar |
| hidden | contraída | **0px**, sin columna ni controles laterales enfocables | Visible; botón de reabrir fuera de sidebar |
| cualquiera | fullscreen del reproductor | Conservar ancho/estado elegido, sin forzar persistencia | Destinos y búsqueda superior ocultos; controles de ventana disponibles |

Derivar `effectiveSidebarMode`/`showTopNav` desde la preferencia, `sidebarCollapsed` y fullscreen; no mantener banderas independientes que puedan contradecirse. Salir de fullscreen restaura la presentación previa. F11 del sistema no equivale al fullscreen del reproductor y no debe cambiar las preferencias.

### Acciones siempre alcanzables

- Reabrir sidebar: botón visible fuera de la columna, con nombre/estado accesible y foco restaurable. Mantenerlo alcanzable también si se oculta la topnav por fullscreen del reproductor, respetando sus controles propios.
- Inicio, Explorar y Biblioteca: mismos handlers/rutas y selección efectiva que el flujo actual; Buscar es una cápsula/acción separada como en Mac, no un cuarto destino permanentemente seleccionado.
- Cuenta: acceso independiente a invitado/login/cancelación/logout/perfil/actualizaciones con los callbacks actuales. Contraer/cambiar de modo no debe cerrar sesión ni crear un segundo flujo de autenticación.
- Me gusta, Historial, crear playlist y colecciones: mantenerlos en Biblioteca o un menú de accesos etiquetado; reutilizar callbacks y permisos. No considerarlos preservados sólo porque existe el botón de Biblioteca: verificar cada acción concreta. En caso de no tener destino equivalente, ofrecer ese acceso en el menú superior.
- Settings y actualizaciones siguen disponibles. No quitar acciones de su ubicación actual hasta comprobar su reemplazo.

## 2. Referencia actual de macOS y adaptación Windows

Leer al implementar:

- `apple/Sources/SideB/SideBApp.swift`: `windowNavigationToolbar` y handlers de navegación/búsqueda.
- `apple/Sources/SideB/Services/Navigation/NavPresentation.swift`: destinos principales Inicio/Explorar/Biblioteca, selección por historial visitado y `!sidebarExpanded && !fullscreenPresented`.
- `apple/Sources/SideB/Views/Components/WindowNavigationToolbarView.swift`: presentación del conjunto, fusión de búsqueda, foco/resultados y transiciones reversibles.
- `TopNavigationView.swift`, `HistoryToolbarView.swift` y `apple/Sources/SideB/UI/ShellLayout.swift`: forma, controles, disponibilidad y medidas vigentes.

La topnav vigente tiene **tres cápsulas**, altura42: búsqueda cerrada42, destinos246 e historial76, separadas10. Búsqueda abierta298 ocupa el ancho de búsqueda+destinos+un gap; los destinos salen y dejan de recibir foco. Historial mantiene posición/tamaño. Estos valores son punto de partida visual, no una garantía de encaje con Inter/ES/EN/DPI y la TitleBar Windows.

Conservar iconos vectoriales, selección, estados enabled/disabled, efectos y proporciones del origen, usando Svelte/CSS y tokens Windows/Inter. No trasladar AppKit/lens nativos ni afirmar identidad píxel a píxel entre motores. Las formas/transiciones funcionales deben coincidir, con superficie de Windows coherente y una sola capa de control.

Reservar franja nativa de ventana32px y sus138px de botones a la derecha; la topnav vive debajo o dentro del espacio libre medido sin superponerse al hit testing de esos controles. Elegir una sola geometría canónica tras medir960×640. Reservar altura real para contenido y menús; Inicio actualmente llega al techo y requiere ajuste específico. No sumar offsets distintos por ruta ni elevar el tamaño mínimo de ventana para ocultar colisiones.

Fullscreen del reproductor oculta destinos/búsqueda como Mac. Barra de título, cerrar/minimizar/maximizar/restaurar y regiones de arrastre conservan su comportamiento Windows. Los campos/botones/resultados nunca son zonas de arrastre.

## 3. Archivos y responsabilidades

| Archivo/componente | Cambio previsto |
|---|---|
| `windows/src/lib/appearance/preferences.ts` | Campos/defaults/setters aditivos y persistencia; estado único de contracción. Sin guardar esta opción por cuenta. |
| `components/home/HomeSettings.svelte` | Selector de comportamiento de contracción y ayuda breve; conservar Lista/Cuadrícula y otros ajustes. |
| `src/routes/+page.svelte` | Componer modo efectivo, topnav, sidebar, menú de cuenta y reserva de contenido; reutilizar handlers, historial y store. No implementar toda la lógica dentro del markup del shell. |
| Nuevo `src/lib/navigation/presentation.ts` | Derivación pura de modos/selección/reservas; sin cola, red ni reloj de audio. Contrato pequeño y comprobable. |
| Nuevo `components/shell/TopNavigation.svelte` | Tres cápsulas, selección, búsqueda expandible y acciones. Recibe estado/handlers; no crea router ni controllers duplicados. |
| `components/shell/TitleBar.svelte` | Mantener botones/drag nativos; ofrecer ancla segura para reabrir y evitar duplicar Atrás/Adelante al mostrar topnav. |
| `components/sidebar/Sidebar.svelte` | Ocultamiento total sin reserva/hit testing/Tab; conservar listas, cuadrícula, permisos, scroll y controles cuando reaparece. |
| Nuevo componente compartido de cuenta, si hace falta | Extraer el perfil/popover hoy embebido en Sidebar, reutilizable por ubicación, con un solo propietario de estado y sin listeners duplicados. |
| `components/home/HomeView.svelte` | Abrir el mismo panel Settings desde el shell mediante petición controlada; conservar controles/contexto de Inicio. No duplicar ajustes ni crear una ruta nueva por comodidad. |
| `components/search/{SpotlightSearch,QuickResults,SearchSongRow}.svelte` y nuevo host anclado si hace falta | Reutilizar contenido/resultados/recientes/acciones; separar presentación modal de la anclada, sin bifurcar negocio. |
| `src/lib/search/{preview,recents}.ts`, navegación/historial existentes | Reutilizar. Cambiar sólo si un contrato real lo requiere; conservar revisión/cuenta/query, cancelación y callbacks. |
| `HomeAmbient.svelte`, `HomeBackground.svelte`, `FullscreenNowPlaying.svelte`, player dock y overlays | Auditar referencias a `--sidebar-width` y reservas superiores; cero real en modo oculto y capas coherentes. No rediseñar fullscreen. |
| `src/lib/i18n/windows.json` | Claves `windows.*` ES/EN nuevas, nombres accesibles y ayuda. `catalog.json` generado no se edita manualmente. |
| Pruebas `sidebar-appearance`, `navigation-history`, `search-*`, `window-controller`, `navigation-gestures`, fixture del shell | Regresiones observables y pruebas de integración descritas abajo. |

## 4. Navegación, búsqueda, settings y foco

1. **Navegación única:** botones nuevos llaman a `handleSwitchNav`, `navigateExplore`, `openAccountNav`, `goBackFromDetail` y `goForward`. Cambiar modo o abrir/cerrar sidebar no inserta visitas ni descarta scroll/filtros/detalles. Selección proviene del contexto/historial real; artista/álbum/playlist y búsquedas no fuerzan Inicio arbitrariamente. No leer entradas futuras para decidir selección.
2. **Búsqueda como Mac:** al pulsar lupa en modo oculto, abrir campo superior expandible y resultados anclados. Reutilizar `SearchPreviewController`, `QuickResults`, recientes y handlers de commit/play. Enter, flechas, Escape, clic fuera y restauración de foco conservan reglas actuales. No cambiar proveedor, consultas, debounce o ranking para este port.
3. **Un solo buscador activo:** Ctrl+K usa el host superior cuando es visible y el Spotlight actual cuando corresponde al modo tradicional/fullscreen. No montar ambos ni mantener dos drafts activos. Abrir sidebar/fullscreen/modal/cambiar cuenta cancela o transfiere estado mediante contrato explícito; no aceptar respuestas tardías de la consulta anterior. Acordar cierre conservador al cambiar presentación y probarlo.
4. **Settings actual:** exponer apertura controlada del panel existente de `HomeView`; desde otra ruta, guardar su snapshot y navegar a Inicio antes de abrirlo. Una petición pendiente se consume una vez tras montaje; cerrar restaura foco en un control visible. Evitar panel duplicado, estado perdido al cambiar la opción dentro de Settings y acceso que sólo funcione con sidebar expandida. Si después se desea Settings global sin navegar a Inicio, tratarlo como mejora separada del host, no duplicar su contenido.
5. **Cuenta común:** un solo popover/estado al mover su ubicación, con listeners limpiados y ancla vigente. Cambiar cuenta invalida previews según política existente, pero mantiene preferencias de instalación.
6. **Estado de sidebar:** preferir conservar su instancia sin espacio ni interacción y darle una señal de visibilidad para suspender handlers globales; si se desmonta, elevar antes `libraryTab`, scroll y ancla de colección al modelo. No perder selección/scroll ni dejar listeners ocultos operativos al reabrir.
7. **Accesibilidad:** hidden implica sin Tab/AX/hit testing, no sólo opacity/transform. Transferir foco antes de ocultar el control propietario. Escape cierra sólo el overlay superior; no dos acciones por un mismo atajo. Respetar reducir movimiento/transparencia, alto contraste y nombres ES/EN. Abrir/cerrar rápidamente revierte desde presentación actual sin dejar capas invisibles bloqueando clics.

## 5. Secuencia de implementación

- [x] Definir alcance y contrato mediante inspección de fuentes; escribir este plan, sin implementar TopNav.
- [ ] Capturar referencia Mac vigente con geometría equivalente y revisión de restricciones nativas; no usar capturas de variantes históricas retiradas.
- [ ] Añadir store/defaults/selector; probar recreación, migración aditiva y tabla de estados sin tocar todavía navegación.
- [ ] Resolver acceso de reabrir/cuenta/Settings/acciones de Biblioteca y ownership del foco antes de permitir cero ancho.
- [ ] Implementar host de tres cápsulas con callbacks reales, sin búsquedas aún; comprobar selección, Atrás/Adelante y reserva de ventana.
- [ ] Integrar búsqueda expandible y contenidos/recientes compartidos; un solo propietario de query/presentación, cancelar respuestas obsoletas.
- [ ] Integrar shell: columna0/60/253, fondos, titlebar, modales, dock y fullscreen. Conservar estado de sidebar y reproducción al cambiar layout.
- [ ] Afinar geometría con Inter/ES/EN y preferencias de accesibilidad; validar UI y recorridos completos.
- [ ] Ejecutar check/tests/build frontend y verify nativo; corregir fallos de contrato, no omitir tests para hacer compilar.
- [ ] Registrar fix y evidencia en FIXES, actualizar **PAR-007** por el alcance nuevo, PAR-036 si afecta a la sidebar y este plan. No marcar aceptación física por lectura de código/build.
- [ ] Generar build numerada con la skill oficial sólo al implementar y probar; comparar `BUILD.json`/fuentes/hashes y entregar ruta exacta. Git/release requieren pedido específico.

## 6. Matriz de aceptación

| Frente | Casos y evidencia requerida |
|---|---|
| Preferencias | Defaults de instalaciones viejas; JSON incompleto/inválido/futuro; storage bloqueado; reiniciar con sidebar cerrada; logout/cambio de cuenta; listas/cuadrícula/fondo/motion conservados. |
| Estados | Cuatro combinaciones de la tabla; cambiar preferencia cerrada y abierta; toggles rápidos; reapertura desde cada ruta/fullscreen; ancho0 sin columna, AX ni botones ocultos. |
| Acciones | Inicio/Explorar/Biblioteca, Me gusta/Historial, playlist/álbum/artista, creación/listas/menús, login/cancel/logout/actualizaciones y Settings realmente alcanzables. Atrás/Adelante restauran página/scroll/filtros sin duplicar visitas. |
| Búsqueda | ES/EN, vacío/recientes/carga/error/resultados, flechas/Enter/Escape/Tab/clic fuera, Ctrl+K, cuentas y respuestas tardías; expansión298 equivalente y navegación sin segundo Spotlight. |
| Composición | Ventanas cliente960×640,1100×720,1440×900; escala100/125/150%; normal/maximizada/F11; sidebar lista/cuadrícula. Medir colisiones con138px de controles de ventana, títulos/filtros, resultados y última fila sobre player. |
| Overlays | Spotlight tradicional, búsqueda anclada, menú contextual, perfil, Settings, editor de playlist y actualización: z-order/hit testing/foco correctos y ningún overlay doble. |
| Reproducción | Cambiar modo no recarga audio, modifica cola/generaciones ni reinicia letras/motion. Entrar/salir de fullscreen devuelve layout previo; progreso/volumen/click-to-seek siguen funcionando. Separar tests de audio audible real. |
| Accesibilidad | Narrator/teclado/orden de foco/nombres/estado seleccionado; alto contraste, reducir movimiento/transparencia; controles de ventana y drag funcionan en ambos modos. |

Comprobaciones de código: `pnpm check`, `pnpm test`, `pnpm build` dentro de `windows/`; `windows/scripts/windows.ps1 -Action verify` en Windows para integración nativa. Fixture de componentes y shell reales con RPC controladas para geometría/teclado; prueba WebView2 física separada. Compilar no certifica FPS/audio/Narrator ni apariencia aceptada.

## 7. Cierre y límites

- No se debe implementar esta función dentro de la build de Inter que está en curso.
- No reabrir ports de fondos fullscreen u otros rediseños ajenos por estar cerca del shell.
- Los cambios de topnav son UI Windows; si aparece un defecto compartido distinto, documentarlo y leer el AGENTS del ámbito antes de editarlo.
- Mantener este plan actualizado con decisiones y pruebas reales. Un intento fallido/investigación queda pendiente, no como fix resuelto.
