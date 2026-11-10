# Diagnóstico de desplazamiento horizontal de queue

- Fecha: 2026-10-31, America/Montevideo.
- Pedido: planificar «Continua» e investigar scroll horizontal reportado por el usuario en la queue nueva.
- Estado: causa de geometría reproducida con AppKit aislado; corrección de producto y QA de gestos pendientes en [PLAN-019](../PLAN-019-continuous-queue.md).

## Contraste de fuentes

`NativeSeparatedQueueView.makeNSView` oculta el scroller horizontal pero omite `table.style = .plain` y `horizontalScrollElasticity = .none`, presentes en `NativeTrackTableView.makeNSView`. Su actualización asigna a la columna `scroll.contentSize.width`. El `QueueTable` nuevo no añade una política propia de ajuste de ancho en layout.

FIX-036 ya documentaba el bloqueo de elasticidad horizontal y ajuste de columna; no se afirma una regresión de aquel commit sin comparación histórica. El nuevo contenedor omite configuraciones presentes en la implementación actual de referencia.

`ProposalCell` reserva dos botones de 26 pt además de la celda común. Eso reduce espacio para texto; no es necesario para reproducir los 32 pt de exceso. Windows utiliza otro motor: `.queue-list` especifica sólo `overflow-y:auto`; su riesgo de desbordamiento requiere medición DOM, no se le atribuye el resultado AppKit.

## Reproducción ejecutada

Comando: `swift plans/research/queue-horizontal-scroll-probe.swift`.

El script recrea la configuración de geometría de producción: NSScrollView con una columna, NSTableView sin cabecera, separación cero, altura de fila 46, ajuste uniforme y ancho de columna igual al viewport. Compara estilo automático/plain y elasticidad automática/deshabilitada, redimensionando 600→350→600 pt.

| Estilo | Elasticidad horizontal | Viewport | Documento | Exceso | X permitido por constrainBoundsRect para propuesta X=20 |
|---|---|---:|---:|---:|---:|
| Automático | Automática | 600 | 632 | 32 | 20 |
| Automático | Deshabilitada | 600 | 632 | 32 | 20 |
| Automático | Automática | 350 | 382 | 32 | 20 |
| Automático | Deshabilitada | 350 | 382 | 32 | 20 |
| Plain | Automática | 600 | 600 | 0 | 0 |
| Plain | Deshabilitada | 600 | 600 | 0 | 0 |
| Plain | Automática | 350 | 350 | 0 | 0 |
| Plain | Deshabilitada | 350 | 350 | 0 | 0 |

Volver a 600 reproduce los mismos resultados. Estos números corresponden al AppKit instalado en este Mac; no prometen idénticos insets en todos los macOS soportados.

## Conclusión y límites

Hay un exceso real de ancho atribuible al estilo automático en la reproducción local, incluso sin canciones ni botones. Ocultar la barra y deshabilitar elasticidad por sí solos no eliminan ese exceso. El estilo plain elimina el exceso geométrico de esta prueba; restaurar además elasticidad `.none` completa la política sólo vertical de la tabla de referencia.

La prueba usa `constrainBoundsRect`, no reproduce eventos físicos de trackpad. Falta comprobar ventana real, SwiftUI, resize/sidebar, selección/arrastre y posibles gestos globales de navegación. Tampoco prueba overflow Windows. No se cambiaron fuentes de app ni se generó una build.
