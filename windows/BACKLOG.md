# Pendientes Windows

Única lista activa de producto Windows. Mantener objetivos verificables; usar el diff/commit para explicar la implementación. Un pendiente se cierra con evidencia de su comportamiento, no por el estado de un plan antiguo.

## Base disponible

Inicio con chips/continuaciones; búsqueda de canciones y álbumes; álbum/artista/catálogos; login persistente; biblioteca, likes, playlists e historial; reproducción, pausa, seek, volumen, next/previous y fullscreen con cola compartida. El usuario confirmó audio y el recorrido básico de Inicio → álbum → artista → Atrás antes de esta reorganización.

## Próximo trabajo

### Reparaciones en curso (pedido del usuario)

| Plan | Responsable / dependencia | Resultado |
|---|---|---|
| [UX-01](plans/UX-01-navigation.md) | Navegación + integración root | Atrás/Adelante entre todas las vistas |
| [UX-02](plans/UX-02-titlebar.md) | Navegación, junto a UX-01 | Barra superior y fullscreen nativo |
| [UX-03](plans/UX-03-playlists.md) | Backend primero, UI segunda ola | Botones, edición, orden y acciones de playlist |
| [UX-04](plans/UX-04-radio-queue.md) | Backend + controller root | Radios de Inicio y edición segura de cola |
| [UX-05](plans/UX-05-context-menus.md) | Segunda ola, usa UX-03/04 | Clic derecho y Más con política macOS |
| [UX-06](plans/UX-06-player-fullscreen.md) | UI primera ola + integración root | Barra y fullscreen con scroll independiente |

Root revisa contratos antes de delegar e integra `+page.svelte`; agentes no comparten archivos activos. Pruebas manuales a cargo del usuario mientras esté presente. Los planes se cierran con evidencia y luego se archivan, sin convertirse en otra lista de estado.

Implementación de los seis planes integrada en `windows/ux-controls-and-menus`. Gates locales: frontend 85/85 pruebas y tipos sin errores/advertencias; bridge Tauri 26/26 pruebas. Falta confirmar en la app nueva el comportamiento visual y las operaciones con la cuenta; la aprobación anterior del usuario corresponde al baseline. Los paneles Letras/Relacionado y el reordenamiento de cola ya tienen implementación; queda confirmar con una canción real el arrastre, el seguimiento de letras y la navegación desde recomendados.

| Prioridad | Resultado | Criterio de cierre |
|---|---|---|
| 1 | Validar reordenamiento de cola | Arrastrar desde el handle y con teclado; comprobar pista activa y duplicados durante reproducción real |
| 1 | Validar shuffle/repeat | La implementación runtime está; falta confirmación manual de shuffle y repetición durante reproducción. Persistencia entre reinicios sigue en Restauración de reproducción |
| 1 | Validar radio continua | UX-04 implementa continuación/deduplicación por videoId/reintento; confirmar con reproducción real el final de bloque y cambio de canción durante carga |
| 2 | Restauración de reproducción | Persistir cola, pista, posición y modos; volver a abrir sin reproducir por sorpresa |
| 2 | Acciones de playlists/menús | Agregar/quitar pistas, editar listas propias y completar menús según permisos; estados pendientes/error recuperables |
| 2 | Paridad visual por pantalla | Comparar capturas Mac/Windows con ventana y sidebar equivalentes; resize/DPI, foco, teclado y navegación sin regresiones |
| 2 | Validar letras y recomendados | Probar sincronía/seek/follow con canción real, estados sin letras, cambio rápido de pista y los cuatro estantes con navegación/encolado |
| 3 | Distribución Windows | Empaquetado NSIS currentUser, hook de libmpv-2.dll, comandos Tauri de actualización, modal Svelte y workflow de release integrados; probar instalación y actualización en máquina limpia |

## Cómo elegir una tarea

Elegir un resultado de la tabla y acotar archivos/contratos. Si requiere varios agentes, repartir dominios sin compartir archivos o usar worktrees; un integrador revisa el diff y los gates. Sólo escribir un diseño adicional si hay una decisión nueva que no pueda explicarse brevemente en el encargo. El backlog no es un registro de cada ajuste visual.
