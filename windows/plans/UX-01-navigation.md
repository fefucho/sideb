# UX-01 · Historial de navegación

## Decisión
El historial actual sólo guarda detalles y lo borra al tocar la sidebar. Sustituirlo por dos pilas limitadas a 40 entradas: pasado y futuro. Toda transición de pantalla registra la pantalla actual; volver/avanzar intercambia snapshots y una nueva transición vacía el futuro. Repetir el mismo destino no agrega una entrada. La reproducción no forma parte del snapshot.

## Contrato
- Helper TypeScript puro `NavigationHistory<T>`: `visit(current)`, `back(current)`, `forward(current)`, `clear()`, `mapSnapshots(fn)`, `canBack`, `canForward`.
- El integrador conserva vista, navegación primaria, scroll, datos de catálogo, búsqueda, pestaña de biblioteca y playlist abierta. Cancela solicitudes anteriores antes de restaurar y vuelve a pedir sólo detalles pendientes/incompletos. El cambio de cuenta borra ambas pilas.
- Botones Atrás/Adelante en la barra superior, deshabilitados en los extremos. Alt+Izquierda/Derecha y botones laterales del mouse comparten las mismas acciones; no interceptar edición de texto o diálogos.
- Referencia: `apple/Sources/SideB/Services/Navigation/NavigationRouter.swift` y `NavigationInputCoordinator.swift`.

## Propiedad y verificación
Agente: helper `src/lib/navigation/history.ts` y prueba pura de ramificación/límite/actualización de snapshots. Root: composición en `+page.svelte` y métodos de restauración de controllers. Depende de UX-02 para los botones.

Manual: Inicio → álbum → artista → biblioteca → Atrás dos veces → Adelante; volver y abrir otro destino debe descartar el futuro. Recuperar scroll y búsqueda; cambiar de cuenta no recupera datos privados anteriores.
