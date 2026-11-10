# Revisión independiente de contrato y UI — PLAN-018

- Fecha: 2026-10-30.
- Modelo solicitado y usado: Gemini 4 Argon (High), `gemini-4-argon-high`, proveedor Antigravity.
- Base del código nativo inspeccionado: `f7fc479`; rama de diseño `experiment/queue-recommendations`.
- Alcance: lectura del plan, prototipo y caminos de cola/reproducción/menús actuales. No ejecutó el reproductor, no modificó fuentes nativas ni midió rendimiento.
- Resultado recibido: no hay impedimento arquitectónico para separar elegidas/reserva con un propietario y la tabla reciclada actual; sí había tres huecos de contrato que debían cerrarse antes de implementar.

## Hallazgos y tratamiento del integrador

| Hallazgo de la revisión | Decisión incorporada |
|---|---|
| Reproducir una propuesta sin ancla puede mandarla al final durante `restoreSourceOrder` y hacer que las elegidas queden antes del índice actual | Anclar la elección y mantener la partición anteriores/actual/pendientes. Añadir el caso más general de padre con rango tardío tras shuffle, para el que un ancla sola tampoco prueba corrección |
| Radios de colección/mixes podían comprometer todo el lote inicial y `/next` sin source podía confundir una playlist con radio | Clasificar por intención/destino normalizado, conservar el catálogo real y comprometer sólo la inicial de radio. Probar todos los inicios, PL/OLAK/RD y respuestas ambiguas |
| Semilla, continuación opaca `/next` y extensión por `lastVideoId + radioSeed` tienen contratos distintos | Cursores por propósito; último video de radio independiente de manuales; enriquecimiento antes de filtrar la semilla repetida |
| Páginas posteriores con shuffle ON podían quedar detrás de un manual `.end` | Mantener nuevas fuentes antes de `.end`, respetar colocaciones y evitar rebarajar el lote ya visible por cada página |
| `visibleCount` y mostrar un manual al final no se resuelven cargando/publicando todo | Mantener separadas publicación, catálogo y celdas. Decisión de proyección sujeta a la auditoría de rendimiento, sin eliminar batching por conveniencia |
| Repetir impedía alcanzar la reserva con salto manual, mientras la nota de UI prometía que continuaría | Preservar el modo vigente y explicarlo en la sección de recomendaciones al activarlo; no introducir otro modo en esta función |
| Dislike/quitar actual sin pendientes podía volver al índice cero | Transición de exclusión: pendientes, reserva, espera/parada; distinta de repetir, por ID de ocurrencia |
| Búsqueda por videoId y un EOF viejo durante debounce podían avanzar otra ocurrencia o saltar dos veces | Identidad de ocurrencia/playback antes del stream, una intención por avance y pruebas con callbacks retrasados y duplicados |
| `.recommendations` también se usa en Explorar/Relacionado | Origen específico de propuesta de cola; conservar las otras superficies y sus acciones |
| «Reproducir siguiente» y «Mover al comienzo» se confundían en el prototipo | Separar duplicar elección de mover ocurrencia; preservar ambos comportamientos en plan y simulación |
| Origen de colección no equivale a participación en shuffle después de mover | Procedencia descriptiva separada de sourceRank/placement; mover fija posición sin perder origen |
| Filtro automático podía descartar una elección manual duplicada | Filtrar sólo promoción automática; respetar duplicados elegidos explícitamente |
| Persistencia experimental podía contaminar claves estables y crecer indefinidamente en radio | Namespace propio, importación v2 de una sola vez y cota de anteriores de radio a definir con el baseline; nunca recortar catálogo/manuales por esa cota |

Estas decisiones están detalladas en [PLAN-018](../PLAN-018-queue-recommendations.md), sección «Decisiones incorporadas de la revisión independiente». Cierran ambigüedades del diseño; su corrección nativa seguirá requiriendo implementación y pruebas. Los escenarios de carrera son riesgos identificados por lectura, no regresiones reproducidas aquí.

## Ajustes de UI aceptados

- Una sola tabla con secciones nativas y un único scroll; conservar tabla/celdas existentes, foco y footer para estados de carga/error.
- Conservar transporte/shuffle/repetir en la barra actual; no duplicarlos en la cabecera de la cola. El prototipo los representa una vez al pie para poder simular el avance.
- Acciones compactas de siguiente/final en hover/foco con etiquetas accesibles, conservando el menú completo. Los botones de texto de la simulación permiten descubrir el contrato, sin fijar el diseño final de las celdas estrechas.
- Estado vacío de pendientes compacto durante radio y estados de carga independientes para colección y recomendaciones.

## Límites y siguiente comprobación

El código nativo sigue intacto. La simulación demuestra interacciones del ejemplo, no paginación/restore/red/audio reales. La [auditoría independiente de rendimiento](QUEUE-PERFORMANCE-AUDIT-2026-10-30.md) fue recibida en el reintento con el mismo modelo tras un primer HTTP 502 e incorporada al plan. Ninguno de los dos informes permite afirmar igualdad de FPS, memoria o latencia de una implementación que aún no existe.
