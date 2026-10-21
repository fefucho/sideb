# PLAN-014 — Preferencia de versión explícita o censurada

- Fecha: 2026-10-21 (America/Montevideo).
- Estado: propuesta documental; sin implementación, migración, pruebas nuevas ni build de esta política. Seguimiento común [PAR-041](../PARIDAD.md).
- Alcance: contrato y política comunes para Mac y Windows; configuración y presentación propias de cada shell.
- Producto acordado: priorizar versiones explícitas por defecto y permitir preferir versiones censuradas.
- Excepción obligatoria: abrir o reproducir deliberadamente un álbum censurado respeta su ID, orden y pistas.
- Referencias: [PLAN-013 sobre etiquetas/metadata explícita](PLAN-013-explicit-content-indicators.md); [PLAN-012](PLAN-012-animated-artwork.md) y FIX-238 sobre arte independiente del audio.
- No se autoriza aquí implementar ranking, optimizar Recomendados ni cambiar los streams de reproducción.

## Hechos comprobados en el código vigente

1. [SongItem](../core/crates/innertube/src/models/metadata.rs) contiene `explicit: bool`, con default falso.
   Su comentario documenta que browse/search llevan badge, mientras `/next` y `/player` no lo aportan en esos renderers.
   Por tanto una canción llegada por radio puede tener `false` aunque browse del mismo ID muestre explícita.
2. `is_explicit` sólo busca `MUSIC_EXPLICIT_BADGE` bajo `badges`, `subtitleBadges` y `subtitleBadge` del nodo.
   No devuelve una prueba positiva de edición censurada cuando falta el badge.
3. [BrowseItem y AlbumPage](../core/crates/innertube/src/models/browse.rs) también usan booleanos.
   Un badge de álbum y uno de pista son evidencias de entidades diferentes: no se deben copiar indiscriminadamente.
4. [Contratos core](../core/crates/sideb-core/src/lib.rs): `HomeItemRecord` y `BrowseCardRecord` conservan el booleano; `SongItemRecord` y `AlbumDetailRecord` lo omiten. La información se pierde antes de llegar a filas de canciones y cabeceras de álbum.
   En [DTO Tauri](../windows/src-tauri/src/dto.rs), `HomeItemDto` lo conserva, mientras `SongDto`, `AlbumDetailDto` y `BrowseCardDto` lo omiten; los [tipos TS](../windows/src/lib/types.ts) de algunas tarjetas lo declaran opcional, pero eso no repone un dato descartado.
5. [Archivos locales](../core/crates/sideb-core/src/local.rs) construyen registros con `explicit: false` sin una prueba de versión clean.
   Ese valor describe ausencia de etiqueta disponible en ese camino, no ausencia comprobada de lenguaje explícito.
6. [Endpoints InnerTube](../core/crates/innertube/src/endpoints.rs) construyen búsquedas por categorías y `next` con video/playlist seed.
   No se encontró un parámetro implementado para exigir explicit/clean en esas llamadas.
7. No se encontró ISRC ni un contrato de enlaces oficiales entre versiones en los modelos YTM inspeccionados.
   Eso no demuestra que nunca existan en el proveedor; impide asumirlos disponibles para esta implementación.
8. [SearchViewModel](../apple/Sources/SideB/ViewModels/SearchViewModel.swift) usa generaciones para consultas y previews.
   Una política nueva debe incorporarse a esa identidad; no puede aceptar resultados tardíos de la preferencia anterior.
9. [PlayerViewModel](../apple/Sources/SideB/ViewModels/PlayerViewModel.swift) reproduce álbum con las pistas recibidas y contexto de browse ID.
   [QueueManager](../apple/Sources/SideB/Services/Player/QueueManager.swift) conserva IDs de ocurrencia, rangos y colocaciones manuales.
10. [Controller Windows](../windows/src/lib/player/controller.ts) envía ID elegido, fuente y `queueEntryId` al runtime.
    [Comandos de reproducción](../windows/src-tauri/src/commands/playback.rs) mantienen la cola nativa y su generación como autoridad.
11. [Recomendaciones Windows](../windows/src/lib/player/recommendations.ts) cargan relacionados, artista y álbum por separado.
    Esas estanterías no equivalen a una cola automática; conservan revisiones y resultados parciales.
12. FIX-238 permite resolver motion decorativo desde otra versión oficial compatible del álbum.
    No sustituye video ID de audio, playlist, álbum abierto, historial ni likes; esa separación sigue siendo obligatoria.

## Interpretación y límites de la evidencia

- La conclusión segura es que `false` mezcla información desconocida con contenido potencialmente clean.
- No puede construirse una preferencia fiable mediante `explicit == false` como filtro de versiones censuradas.
- Dos resultados con título/artista iguales no prueban que sean versiones intercambiables.
- No se comprobó que el catálogo entregue siempre ambas versiones ni que las exponga en la misma página.
- Los hechos anteriores proceden de lectura de código; este plan no registra una validación nueva de endpoints en vivo.
- No se aplican contratos de búsqueda Apple/iTunes al catálogo YTM: son proveedores e identidades diferentes.

## Contrato de metadata propuesto, coordinado con PLAN-013

- Introducir un estado aditivo `explicit`, `clean` o `unknown`, sin reinterpretar retrospectivamente todos los booleanos falsos.
- Mantener compatibilidad temporal con el booleano actual y planificar su retiro sólo cuando ambos consumidores estén adaptados.
- `explicit`: evidencia positiva del proveedor para esa entidad y ese ID; badge reconocido es una fuente posible.
- `clean`: evidencia positiva de edición censurada/clean desde una fuente comprobada, no mera falta de badge.
- `unknown`: campo ausente, renderer sin capacidad, archivo local sin dato o respuesta que no permite concluir.
- Guardar procedencia, entidad, ID, versión del parser y fecha; distinguir metadata de álbum de metadata de pista.
- Enriquecer el mismo ID con evidencia más fuerte; un `/next` sin dato no degrada un explicit previamente confirmado.
- Conflictos entre evidencias deben quedar como conflicto/unknown investigable, sin cambiar automáticamente el audio.
- La etiqueta visible y accesible sigue PLAN-013; no rotular «censurada» una pista cuyo único dato es falso.
- Un estado de parental controls/restricted mode, si existe, es otra capacidad y no se infiere de esta preferencia.

## Preferencia y persistencia propuestas

- Enum de producto: `preferExplicit` —«Preferir explícitas»— como default de instalación.
- Segunda opción: `preferClean` —«Preferir censuradas»—; es una preferencia flexible, no una garantía de bloqueo.
- Tercera opción propuesta: `catalogOrder` —«Respetar el orden del catálogo»— para desactivar esta prioridad propia.
- Configuración en una sección de reproducción/contenido de Ajustes, separada del toggle de carátulas animadas y de Apariencia.
- Texto de apoyo: se priorizan versiones disponibles; los álbumes y pistas elegidos manualmente se respetan.
- Persistir por instalación en ambos shells, con clave y esquema propios, sin reutilizar el almacenamiento de Apariencia.
- Cambiar cuenta conserva esta elección local, pero invalida respuestas privadas y equivalencias dependientes del catálogo/cuenta.
- Una nueva sesión hereda el valor persistido; no crear overrides ocultos de sesión ni sincronización de cuenta no implementada.
- Si más adelante se pide preferencia por cuenta, requerirá un diseño separado de precedencia, migración y estado sin sesión.
- Valor ausente o desconocido al decodificar: usar `preferExplicit`; migrar preservando cualquier elección válida existente.
- Si falla persistencia, conservar el cambio durante la sesión y aplicar el tratamiento de errores de Ajustes vigente.
- Decisión pendiente de aceptación: confirmar la tercera opción y los textos ES/EN antes de implementar controles.

## Política por intención de la acción

| Superficie o intención | Comportamiento propuesto |
|---|---|
| Búsqueda escrita y sugerencias | Priorizar una versión preferida dentro de grupos equivalentes verificados; no borrar alternativas |
| Fila concreta seleccionada en búsqueda | Reproducir exactamente el ID visible que el usuario eligió |
| Inicio y Recomendados presentados | Prioridad sugerida entre versiones equivalentes; mostrar la identidad real resultante |
| Radio/autoplay generado | Elegir la alternativa preferida verificada antes de insertar una nueva ocurrencia automática |
| Semilla manual de radio | Respetar el ID de la semilla elegida; aplicar preferencia sólo a nuevas selecciones automáticas posteriores |
| Álbum abierto/reproducido expresamente | Conservar browse ID, edición, orden, pistas y starting index, también si es clean |
| Playlist manual, likes, historial o cola existente | Conservar IDs y ocurrencias; no sustituir ni reordenar retroactivamente |
| Carátula animada | Resolver enriquecimiento visual sin cambiar ninguna decisión de audio |

- Separar el ranking de sugerencias de la selección automática: presentar primero no autoriza sustituir una fila pulsada.
- Un álbum clean escogido desde resultados es una elección manual fuerte incluso con `preferExplicit` activa.
- Un grupo «Del álbum» en Recomendados conserva las pistas de ese álbum; no forma una edición híbrida.
- «Reproducir álbum» desde una tarjeta concreta conserva el álbum representado, aunque la tarjeta se haya ordenado por preferencia.
- Radio de artista/mood sin pista elegida puede aplicar selección automática desde el primer elemento, con procedencia explícita.
- Shuffle cambia el orden según la acción existente, no los IDs de la edición seleccionada.
- Agregar dos veces el mismo video conserva dos ocurrencias: equivalencia de versiones no significa deduplicación de cola.
- Descargar, marcar like o agregar a playlist se aplica al ID mostrado; nunca a una sustitución invisible.

## Equivalencias seguras y selección acotada

1. Usar sólo candidatos disponibles y autorizados por la cuenta/storefront; no fabricar filtros ni endpoints no comprobados.
2. Preferir un enlace oficial de versiones verificado cuando el proveedor realmente lo exponga y se haya documentado su parser.
3. Contrastar identidad de artista y álbum, título, duración y calificadores de edición; conservar deluxe/live/remaster/remix.
4. ISRC, si llega a estar disponible y validado, aporta evidencia adicional; su ausencia no se convierte en igualdad.
5. ISRC por sí solo tampoco prueba clean/explicit: comprobar estado de versión y coherencia de la grabación.
6. No usar distancia de duración como prueba única; el umbral y tolerancias deben fijarse con fixtures reales, no inventarse aquí.
7. Ante múltiples alternativas compatibles sin una correspondencia inequívoca, mantener el ID original y no sustituir.
8. Acotar búsquedas adicionales, concurrencia, tiempo y caché; sin un descargador o resolvedor completo por fila visible.
9. Si el catálogo ya ofrece pares confirmados, la prioridad debe ser estable dentro del grupo y respetar el orden entre grupos.
10. No promover canciones irrelevantes sobre resultados relevantes únicamente por tener etiqueta explícita.

## Fallbacks y cambios de preferencia

- `preferExplicit` sin alternativa explicit confirmada: conservar el resultado del catálogo; no ocultar clean ni desconocidos.
- `preferClean` sin alternativa clean confirmada: conservar el resultado disponible y su etiqueta real, sin prometer censura.
- Un desconocido no se presenta como clean, aunque pase a ser el único resultado disponible.
- Un modo estricto de exclusión sería otro producto: queda pendiente y no se activa implícitamente al elegir `preferClean`.
- No modificar contenido de la cuenta ni un supuesto restricted mode del proveedor para simular esta preferencia local.
- Cambiar el ajuste no interrumpe audio ni reescribe la cola actual, incluida su parte automática ya insertada.
- Aplicar la nueva prioridad a consultas nuevas/refrescadas y a futuras selecciones automáticas; comunicar ese alcance en Ajustes.
- Una acción manual ya iniciada conserva su snapshot de ID/edición aunque el ajuste cambie durante la resolución.

## Caché, generaciones y paginación

- Separar metadata factual por ID de resultados derivados por preferencia; cambiar la preferencia no borra evidencia válida.
- Claves derivadas: cuenta/sesión, storefront, consulta/contexto, revisión de política y preferencia efectiva.
- Asociaciones entre versiones conservan procedencia y TTL; error, esquema desconocido o ambigüedad no son ausencia permanente.
- Invalidar resultados derivados al cambiar cuenta/preferencia; descartar respuestas antiguas antes de publicar o insertar cola.
- Cada radio/session generation captura su política; inserciones nuevas requieren la revisión efectiva y seed/contexto vigentes.
- Una continuación pertenece a su consulta y política: no mezclar páginas de generaciones distintas ni reutilizar un cursor en otra cuenta.
- Ranking por página no garantiza orden global; mantener prioridad sólo en grupos ya conocidos y no prometer reordenamiento global.
- Preservar cursores, posición visible y ocurrencias manuales; decidir con fixtures si un cambio de política requiere reiniciar la consulta.
- No refrescar o reordenar Recomendados por cada tick del reproductor; este plan define política, no una optimización de su controlador.

## Etapas y comprobaciones de aceptación pendientes

- [ ] Alinear PLAN-013: metadata triestado, procedencia y contrato aditivo Mac/Windows; fixture de `/next` sin badge.
- [ ] Documentar capacidades YTM reales con muestras sanitizadas antes de elegir filtros o vínculos entre versiones.
- [ ] Aceptar persistencia de instalación, enum de tres opciones y textos accesibles ES/EN.
- [ ] Implementar motor de política común sólo tras autorización compartida; preservar paths de audio y preferencias ajenas.
- [ ] Integrar ranking de búsqueda/sugerencias y selección automática como operaciones distintas, con identidad de intención.
- [ ] Probar explicit/clean/unknown y conflicto; un false heredado o archivo local nunca confirma clean.
- [ ] Probar equivalencias: artista incorrecto, remix/live/deluxe, duración cercana, ISRC ausente y enlaces ambiguos.
- [ ] Probar álbum clean manual con default explicit: IDs, orden, duplicados, starting index y shuffle intactos en ambas apps.
- [ ] Probar radio con seed clean manual y selección futura; likes/playlists/historial/cola no cambian retroactivamente.
- [ ] Probar cambio de ajuste/cuenta durante búsqueda, continuación, resolución y radio; ninguna respuesta vieja muta el contexto nuevo.
- [ ] Probar UI: alternativas permanecen elegibles, etiquetas correctas, texto sin garantía estricta y ajuste persistente tras reinicio.
- [ ] Verificar caché fría/caliente, fallo/transitorio, alternativa no disponible y error de almacenamiento sin loops de consulta.
- [ ] Separar tests de política/contrato, builds de ambos consumidores y prueba manual de audio/IDs; no inferir uno de otro.
- [ ] Registrar implementación futura en FIXES/PARIDAD y actualizar este plan; esta propuesta no cierra ninguna paridad.
