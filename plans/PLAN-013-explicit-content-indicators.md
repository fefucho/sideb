# PLAN-013 — Indicadores de contenido explícito y versiones limpias

- Fecha: 2026-10-21 (America/Montevideo).
- Estado: **propuesta; no implementada**. Seguimiento común [PAR-040](../PARIDAD.md).
- Alcance: contrato de metadatos compartido, conservación en los bridges y presentación coherente en Mac y Windows. Este plan trata etiquetas que el proveedor aporta; no cambia el ranking ni la elección de resultados, que pertenece a [PLAN-014](PLAN-014-content-version-preference.md).
- Objetivo: que una persona pueda reconocer una versión marcada explícita y una versión identificada como limpia, y que la falta de una marca no se presente como prueba de que la edición es limpia.

## Hallazgos del código actual

La capa InnerTube ya detecta `MUSIC_EXPLICIT_BADGE` en `badges`, `subtitleBadges` y `subtitleBadge` dentro de [metadata.rs](../core/crates/innertube/src/models/metadata.rs). `SongItem` y `BrowseItem` guardan un `bool explicit`; el parser de [browse.rs](../core/crates/innertube/src/models/browse.rs) también lo toma del encabezado de álbum y de tarjetas. Ese booleano registra la presencia del distintivo, no un estado limpio confirmado.

| Superficie | Lo que conserva hoy | Lo que se pierde o falta |
|---|---|---|
| Home | `HomeItemRecord.explicit` cruza core y bridge; Mac lo persiste en `HomeFeedCacheStore` y `HomeFeedCollectionView` muestra E accesible. Windows `HomeItemDto` y `home/controller.ts` conservan el booleano. | El `false` predeterminado no separa desconocido de limpio; cache viejo también sólo tiene booleano. |
| Tarjetas | `BrowseCardRecord` copia `BrowseItem.explicit`. Mac usa las tarjetas del feed. | `windows/src-tauri/src/dto.rs` no copia `explicit` en `BrowseCardDto`, aunque `types.ts` lo declara opcional. `MediaCard.svelte` muestra E sólo cuando llega `true`; no cubre toda tarjeta ni las filas de canciones. |
| Búsqueda | El parser de canciones asigna `SongItem.explicit`; las tarjetas de búsqueda usan `BrowseItem.explicit`. | `SongItemRecord` en `core/.../lib.rs` omite el campo al convertir ambos tipos. `SongDto` de Tauri y el `SongItemRecord` UniFFI generado tampoco lo tienen. Por ello, listas/filas de búsqueda no reciben la marca; `SearchView.swift`/`QuickSearchContentView.swift` tampoco dibujan un badge. El DTO Tauri de tarjetas descarta la marca también en resultados de álbum. |
| Detalle y versiones de álbum | InnerTube `AlbumPage` tiene `explicit` de encabezado; sus `items` tienen estado de pista. | `AlbumDetailRecord`, `AlbumDetailDto` y los tipos de interfaz omiten explícito del encabezado y canciones en Mac y Windows. Las secciones “otras versiones” pueden transportar un `BrowseItem.explicit` en el origen, pero se pierde en los DTO del bridge/Windows. |
| Cola y Now Playing | Una selección inicial puede proceder de una fila que sí conocía la marca. | `PlaybackTrackDto`/estado de reproducción y los modelos de Now Playing no mantienen el dato. `/next` y `/player` no siempre entregan marca; tratarlos como limpio borraría contexto válido o inventaría certeza. No hay badge E en barra/Now Playing. |
| Biblioteca y Explore | Sus listas usan filas/tarjetas y modelos locales con valores por defecto. | Los elementos construidos a mano y los registros anteriores usan `false`; no hay evidencia de que sean limpios. Las conversiones de `BrowseCardRecord` usadas para vistas sintéticas asignan `explicit: false`. |

Windows tiene `ExplicitBadge.svelte` y `MediaCard.svelte`; Mac define el badge nativo en la colección Home. Esos componentes prueban que existe tratamiento visual en ciertos contextos, no que resultados, pista activa o versiones estén cubiertos. El código de Side B no tiene una preferencia local de contenido explícito; la necesidad observada es ver claramente las etiquetas que entrega el proveedor.

## Evidencia y límite sobre Graduation

[FIX-238](../FIXES.md#fix-238) y [PLAN-012](PLAN-012-animated-artwork.md) documentan una respuesta oficial de búsqueda para Graduation que selecciona la edición limpia `1442845779` (`videoArtwork: null`) y enlaza en `other-versions` la edición explícita `1451901307`, cuyo encabezado ofrece motion. El arreglo de motion sigue sólo versiones oficiales compatibles. Esto demuestra que dos ediciones del mismo álbum pueden tener estados y recursos distintos; **que compartan portada o motion no demuestra que el audio activo sea la edición explícita ni la limpia**. La búsqueda ambigua reportada requiere además etiquetar cada candidato real y mejorar la elección por separado en PLAN-014.

La fuente concreta conocida aquí es el distintivo de YouTube Music. Su ausencia, el fallo de parseo, el endpoint `/player`, un resultado local sin etiqueta o un dato antiguo no confirman contenido limpio. Sólo un campo explícito y documentado del proveedor que declare `clean` podrá producir el estado limpio. No inferir limpieza del título sin `Explicit`, de una portada, de que haya versión alternativa ni de que no aparezca el icono E.

## Contrato de datos propuesto

1. Añadir de forma compatible un estado de contenido a las superficies compartidas y migrar sus consumidores desde el booleano ambiguo. Conservar temporalmente el booleano de origen para compatibilidad, sin usarlo como prueba de limpieza. El nuevo estado tiene tres valores serializados estables: `explicit`, `clean` y `unknown`. Mantenerlo separado para **álbum/edición** y **cada pista**: un álbum puede contener una pista explícita sin que el proveedor marque el encabezado, y la marca del encabezado no sustituye el dato de cada fila.
2. El parser asigna `explicit` sólo al detectar el distintivo en el nodo exacto de la entidad. Asigna `clean` sólo ante evidencia positiva y reconocida del contrato de origen. Ausencia de badge/campo, parser incompleto o esquema desconocido asignan `unknown`.
3. Mantener `unknown` ante fallo, dato ausente, endpoint sin soporte, objeto creado localmente, histórico sin metadata, radio/autoplay que no incluya rating y pistas no relacionadas. No convertir error en estado limpio ni propagar la etiqueta de una fila vecina, tarjeta contenedora o portada.
4. Añadir el estado a `SongItemRecord`, `BrowseCardRecord`, `AlbumDetailRecord`, modelos de playback y los DTO Tauri correspondientes. Copiarlo en todas las conversiones de búsqueda, Home, álbum, lista/biblioteca, cola y reproducción. La respuesta `/next` puede enriquecer un campo desconocido por identidad exacta de la pista/ocurrencia ya etiquetada; nunca sobrescribir un valor conocido con `unknown` ni cruzar marcas entre ediciones.
5. Preservar las versiones vinculadas como candidatos separados, con su identificador, título/calificador, artista, estado de álbum y distintivo de cada fila cuando exista. No propagar el estado de una versión a otra por nombre, artista, número de pistas, álbum compartido, carátula o motion compartido.
6. Migrar caché y almacenamiento: registros legacy `true` pasan a `explicit`; `false` pasa a `unknown`, nunca a `clean`. Decodificadores toleran campo faltante y estados futuros como `unknown`; conservar lo demás y no invalidar preferencias/caché no relacionadas. Evitar serializar enumeraciones Rust dependientes de su índice ordinal: usar nombres documentados/compatibles en el borde.
7. No deducir el estado del audio desde metadatos de una colección externa de arte animado. Motion es un recurso visual; la identidad de versión de audio requiere la pista/álbum fuente del playback.

## Presentación propuesta

- Usar un único componente/estilo accesible en ambas apps. Mostrar `E` para `explicit` y una etiqueta distinta y legible, por ejemplo `L`/“Limpio” (`C`/“Clean” en inglés), sólo para `clean` confirmado. Para `unknown`, omitir distintivo y texto de limpieza; donde el contexto explique estados, exponer “Sin información de contenido” en metadatos accesibles. No reservar un hueco visible que parezca una tercera calificación.
- En tarjetas y listas densas, adjuntar el chip a título/metadata sin cambiar el área clicable, altura de fila, navegación, acciones, selección ni orden de artistas. Reutilizar el label de accesibilidad localizado, contraste del componente y estado correcto al reciclar celdas.
- Mostrar el estado en tarjetas de Home, resultados de canciones/álbumes y cabecera del detalle; mostrar el estado de pista en filas de álbum/biblioteca/búsqueda y en Now Playing/barra compacta sólo si la vista ya dispone de metadatos confirmados para la pista activa. Un badge del encabezado no debe repetirse como calificación de todas sus canciones.
- Candidatos de versiones explícita/limpia deben mostrar título, artista y su propio distintivo juntos en búsqueda y en la sección de versiones del álbum. La fila no debe insinuar que elegirla cambia otra pista ya en reproducción.
- No hacer trabajo de red para adornar la UI. En estado de carga, conservar título/placeholder existente y no parpadear entre clean y unknown. En error, vacío, cuenta invitada o metadato no disponible, no mostrar `clean`; renderizar las filas sin badge y conservar las acciones. Un dato tardío sólo actualiza el elemento cuya identidad/sesión sigue vigente.
- Accesibilidad: el símbolo aislado `E` o `L` lleva etiqueta hablada localizada; evitar anunciarlo dos veces en el mismo nombre accesible. Foco, lectura con VoiceOver/Narrator, escalado y hover/tooltip deben identificar explícito, limpio confirmado y dato no disponible.

## Etapas de implementación y aceptación

1. **Fijar fuente y enum.** Documentar el valor de proveedor que prueba limpieza; si la fuente actual sólo expone insignia explícita, aceptar que `clean` no se produce todavía y mantener `unknown` en las demás respuestas. Definir la semántica por entidad/edición y serialización antes de migrar campos.
2. **Extender parseo y core.** Añadir fixtures sanitizadas para distintivo en cada ubicación admitida, clean positivo documentado, badge ausente, campo nulo, esquema desconocido y entidades vecinas con distinta marca. Probar que el parser sólo lee el nodo propio, mantiene separado encabezado y pistas y que conversiones InnerTube→core→UniFFI/serde conservan cada estado.
3. **Actualizar Mac y Windows juntos.** DTOs de búsqueda, tarjetas, detalle, cola/playback, modelos TS y Swift; caché de Home y storage durable con migración legacy; mapping explícito de cada constructor/sintético a `unknown`. Regenerar UniFFI por el flujo oficial y validar compatibilidad del app bridge/Tauri.
4. **Cubrir vistas.** Home, búsqueda rápida y completa, canciones y álbumes del catálogo, detalle con versiones, pistas del álbum/listas, estado vacío/carga/error, Now Playing y mini player. Usar componente compartido visual por plataforma; conservar acciones y navegación. Excluir cambios de scoring, mezcla de resultados, búsqueda adicional y selección automática de versión (PLAN-014).
5. **Pruebas de contrato.** Fixtures con la misma Graduation en versión limpia y explícita, badges distintos por pista, el mismo artwork/motion compartido, evento `/next` sin marca y respuesta tardía tras cambiar sesión/álbum. Verificar estados en records y DTOs de ambos bridges, round-trip y migración `true→explicit`, `false/missing→unknown`; comprobar que ninguna prueba convierte ausencia de icono en `clean`.
6. **Pruebas de UI Mac/Windows.** Capturas/automatización de cards, búsqueda con ambos candidatos, álbum y lista, Now Playing para explícito/limpio/desconocido. Revisar celdas recicladas, teclado/foco, VoiceOver/Narrator, localización ES/EN y texto largo; casos loading, error, vacío e invitado no reciben una etiqueta falsa.
7. **Cierre.** Ejecutar suites focales core/bridge, Swift y `pnpm check/test/build`; inspeccionar la misma escena y paridad visual/semántica. Registrar fix común, actualizar PARIDAD y este plan al implementarlo. No cerrar si sólo existe el chip Home o si falta un consumidor/estado de migración.

## Lista de aceptación

- [ ] Un origen puede afirmar explícito, limpio o desconocido sin colapsar estados.
- [ ] La ausencia de `MUSIC_EXPLICIT_BADGE` queda desconocida salvo fuente positiva de limpio documentada.
- [ ] Marca de álbum y marca de canción conservan entidad y edición independientes.
- [ ] Mac y Windows reciben el estado en Home, tarjetas, búsqueda, álbum, filas y playback soportado.
- [ ] Graduation limpia/explicita se distingue por metadatos de cada versión; compartir artwork/motion no altera audio ni etiqueta.
- [ ] Cargas, fallos, filas vacías, radio y datos legacy no producen una etiqueta clean falsa.
- [ ] Etiquetas y estados accesibles/localizados funcionan en listas densas y celdas recicladas.
- [ ] Regresión core/bridge/frontend y evaluación de paridad documentadas; ranking y elección permanecen en PLAN-014.
