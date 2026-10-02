> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# PLAN-015 — Reproducción cotidiana y cola en Side B Windows

- **Fecha:** 2026-09-30
- **Estado:** W13 implementado y compilado; validación manual pendiente. W14–W17 propuestos.
- **Alcance:** controles de transporte, cola, carátulas, modos de reproducción y continuidad en Windows.
- **Relación:** desarrolla M7 de [PLAN-013](PLAN-013-side-b-windows-tauri.md) por entregas pequeñas. No sustituye [PLAN-003](../../../plans/PLAN-003-cola_automix_radio.md), que registra el trabajo macOS.

## 1. Resultado esperado

Al elegir una canción o pista de álbum, Side B debe saber qué se está reproduciendo, qué sonó y qué sigue. La barra y fullscreen deben mostrar **la misma pista y carátula** que la cola. Siguiente, Anterior, fin natural, selección de una fila, shuffle, repeat e inserciones deben cambiar ese único estado sin dejar audio o imágenes de otra pista. Una canción sola podrá iniciar radio y continuar cuando se acabe el lote, con errores recuperables.

El usuario pidió avanzar por partes. Cada paquete de abajo termina con una experiencia utilizable y se verifica antes de empezar el siguiente. Letras, Relacionado, rediseño visual, playlists, controles multimedia de Windows y audio sin cortes no son requisitos de este plan.

## 2. Lo que existe hoy y lo que conviene reutilizar

| Área | Estado comprobado en el código Windows | Referencia útil |
| --- | --- | --- |
| Audio | `play_song` resuelve y carga una pista en libmpv; hay pausa, reanudar, seek, volumen, progreso, EOF, error y `generation`. EOF actualmente deja `isEnded = true`. | `windows/src-tauri/src/lib.rs`, `core/crates/player/src/lib.rs` |
| UI | `+page.svelte` guarda `PlaybackStateDto`; `PlayerBar` recibe estado/callbacks; fullscreen recibe el mismo estado, pero dibuja una cola fija de una canción. No hay Siguiente/Anterior. | `windows/src/routes/+page.svelte`, `windows/src/lib/components/player/PlayerBar.svelte`, `windows/src/lib/components/fullscreen/FullscreenNowPlaying.svelte` |
| Catálogo | Buscar devuelve `SongDto`; álbum devuelve `items: SongDto[]`; Inicio permite iniciar temas individuales. El clic en una pista de álbum pasa `selectedAlbum.thumbnail` aunque `track.thumbnail` exista. | `windows/src/lib/types.ts`, `windows/src/routes/+page.svelte` |
| Red | El core ya ofrece `get_next`, `get_radio`, `get_radio_continuation` y, para otra etapa, continuaciones de playlist. No hace falta recrear InnerTube en Tauri. | `core/crates/sideb-core/src/lib.rs` |
| Mac | `QueueManager` ya define contexto, índice, inserción, selección, eliminación, shuffle, repeat y cercanía al final. Su plan figura completo para Mac; eso no demuestra que Windows lo tenga. | `apple/Sources/SideB/Services/Player/QueueManager.swift` |
| LiMusic | Rust posee la cola y emite cambios; Svelte la presenta. Su lógica distingue selección manual, EOF, historial, elementos manuales y autoplay. | `limusic-master/src-tauri/src/state.rs`, `ui/src/lib/queue.ts`, `ui/src/lib/player.svelte.ts` |

Tomar de LiMusic **el comportamiento y los casos límite**, no copiar su `state.rs` completo: incluye Listen Together, lookahead, crossfade y persistencia que no corresponden a los primeros paquetes. Revisar licencia/procedencia antes de reutilizar código literal.

## 3. Contrato estable desde el primer paquete

**Autoridad:** Rust mantiene la cola y decide qué pista cargar. Svelte sólo envía acciones y presenta snapshots. `PlaybackStateDto.currentTrack` es la pista que el motor intenta reproducir; el elemento `queue.items[queue.currentIndex]` debe referirse a la misma **ocurrencia**. El índice, no el `videoId`, identifica una fila: pueden existir duplicados.

**Ubicación:** implementar un modelo de transiciones puro en Rust compartible con Mac (módulo de `sideb-core` o crate pequeño del workspace, según el acoplamiento real al compilar). Tauri conserva la coordinación con libmpv, eventos y resolución de streams. Al introducir APIs públicas en `sideb-core`, no alterar los contratos UniFFI existentes sin regenerar el XCFramework y comprobar Swift en macOS. Si este host no puede hacerlo, mantener la nueva API Rust aislada de los exports Apple y dejar explícito el gate de migración M7. Evitar una segunda máquina de estados en TypeScript.

**Snapshot tipado propuesto** (`QueueStateDto`, nombres definitivos al implementar):

```text
items: [{ entryId, videoId, title, artists, thumbnail, duration,
          origin: context | manualNext | manualEnd | autoplay }]
currentIndex: number | null
source: { kind: song | album | radio | manual, id?, title? }
repeat: off | all | one
shuffle: boolean
autoplay: boolean
revision: number
```

`entryId` debe ser estable por ocurrencia, incluso con `videoId` duplicado. `revision` aumenta al cambiar cola/índice/modos y permite descartar respuestas viejas. El DTO no lleva cookies, headers ni URL firmadas. `PlaybackStateDto.generation` sigue identificando el intento de carga, no reemplaza la identidad de la cola. Exponer `get_queue` para restaurar/reconciliar la UI tras perder un evento; emitir un evento de cola después de cada mutación. Para lotes grandes, evaluar el patrón de LiMusic `queue-changed` / `queue-index` / append, sin optimizar antes de medir.

**Regla de carátula:** el objeto de pista seleccionado contiene su propia `thumbnail`; si falta, usar la portada del contexto (por ejemplo álbum); si también falta, mostrar placeholder. El mismo objeto y la misma prioridad alimentan barra, fullscreen, fila actual y cola. Una respuesta tardía de `resolve_stream` sólo puede mejorar metadatos de la generación activa. Al cambiar de pista, título, artista, portada, duración y posición se actualizan juntos; no mostrar la foto anterior con el audio nuevo. No usar un `videoId` igual como única prueba de identidad.

**Transición de audio:** todas las rutas de cambio (clic, fila de cola, Siguiente, Anterior, EOF y radio) pasan por una operación única `start_entry` o equivalente que reserva generación, detiene/limpia el audio anterior, anuncia la nueva pista, resuelve, carga y emite estado. Conservar las guardias de W07 contra selecciones rápidas. El pump de libmpv no debe hacer red ni esperar un mutex durante la carga: despacha EOF a una tarea serializada. Un evento viejo no puede mover el índice nuevo. En error, mostrar cuál pista falló, permitir Reintentar/Omitir y nunca afirmar que suena si el motor quedó idle.

## 4. Orden de entrega

### W13 — cola real mínima y navegación

**Avance 2026-09-30:** Luna y Codex implementaron la entrega Windows; check/build web y Rust y 3 tests de cola pasaron. EOF y transporte se resuelven en Rust. Falta comprobar audio, EOF real y fullscreen con un álbum por fallo de la herramienta de control de ventanas. Ver [W13-result](../handoffs/W13-result.md). No se marca el paquete completo hasta esa prueba.

**Propósito:** reproducir un álbum de principio a fin y navegar la cola visible. Incluye Siguiente, Anterior y sincronización de portada.

- Crear `QueueModel` y `QueueStateDto` con reemplazo atómico, `select(index)`, siguiente y anterior. Iniciar una pista de Buscar/Inicio crea cola de una pista; pulsar una pista de álbum crea la cola con **todas** las pistas en el orden del álbum y empieza en el índice elegido. No usar una radio de red todavía.
- Mantener historial dentro de esa cola al avanzar. “Anterior” con posición **mayor a 3 s** reinicia la pista; con posición **hasta 3 s** va a la anterior; en el inicio de una cola sin anterior reinicia la actual. “Siguiente” al final sin autoplay deja la pista terminada/detenida; no inventa otra.
- EOF avanza una vez, desde la generación activa; si no hay siguiente deja estado terminado. Clic repetido rápido, EOF simultáneo con Siguiente y selección durante una carga no deben reproducir una pista equivocada.
- Barra: botones Siguiente/Anterior accesibles por teclado, con estado deshabilitado cuando corresponde. Fullscreen: filas reales de cola, actual destacada, clic para reproducir; mostrar previas y próximas en orden. Reemplazar contador fijo “1 canción”. Mantener el layout básico W11, sin rearmarlo.
- Corregir prioridad de carátula de pista de álbum (`track.thumbnail ?? selectedAlbum.thumbnail`) y usar `entryId` para destacar ocurrencias, no coincidencia por `videoId`.

**Salida:** desde la pista 2 de un álbum se ve el álbum completo, Siguiente/Anterior y EOF mueven audio, índice, texto y carátula juntos; Buscar/Inicio siguen reproduciendo una canción. No hay radio ni repeat todavía.

### W14 — edición manual de la cola

**Propósito:** que el usuario controle qué suena después sin perder el contexto actual.

- Acciones contextuales para canciones de Buscar, Inicio y álbum: “Reproducir a continuación” y “Añadir a la cola”. Añadir desde cola vacía inicia una cola manual; documentar si se inicia inmediatamente o queda pausada y mantener esa regla en todas las superficies.
- Dos segmentos manuales: `manualNext` va inmediatamente detrás de la pista actual, en orden FIFO entre varias pulsaciones; `manualEnd` va detrás de ese bloque y antes de la continuación automática. El contexto de álbum conserva su orden después de los manuales. La UI marca origen sin depender del texto de la canción.
- Eliminar fila futura, limpiar sólo canciones añadidas manualmente, seleccionar una fila y reordenar futuras por `entryId`/índice. No permitir borrar/reordenar la pista que está sonando en esta primera versión. Recalcular índice sin cambiar la canción activa cuando se toca una fila anterior.
- Definir explícitamente duplicados: el usuario puede añadir dos veces la misma canción; cada copia conserva su `entryId`. Repetir una acción sobre una misma fila de cola puede mover esa ocurrencia, sin borrar otras copias. Documentar la semántica elegida en el handoff.

**Salida:** insertar dos canciones, ver su orden, oírlas antes de volver al álbum y editarlas sin saltos inesperados.

### W15 — shuffle y repeat

- `repeat = off → all → one → off`; el modo se ve igual en barra y fullscreen. EOF con `one` repite la pista; Siguiente manual **sale de esa repetición para avanzar** y mantiene el modo `one` para la siguiente. `all` vuelve al inicio al terminar; `off` se detiene sin siguiente.
- Shuffle sólo altera el tramo futuro elegible; no mueve la pista activa ni el historial, y respeta el bloque `manualNext`. Conservar orden base para apagar shuffle sin repetir lo ya escuchado. Las nuevas inserciones mientras shuffle está activo deben tener una regla probada de posición.
- Testear álbum con pistas duplicadas y salto al último índice. Revalidar la fila actual y el próximo ítem si hay lookahead de libmpv; si todavía no se usa lookahead, no introducirlo sólo por este paquete.

**Salida:** modos visibles y coherentes tras clic, EOF, skip y cambio de cola.

### W16 — radio y continuidad automática

- Un tema individual puede iniciar radio con `SideBCore::get_radio`; el tema elegido sigue siendo la primera pista. Mostrar carga de radio aparte de la carga del audio: el usuario puede escuchar la semilla aunque falle la consulta. Evitar doble inserción si EOF y la precarga solicitan el mismo lote.
- Con `autoplay` activo, pedir continuación cerca del final (por ejemplo, ≤2 pistas futuras) mediante `get_radio_continuation`. Usar `queue revision`/token de sesión para descartar respuestas de otra cola, cuenta o semilla. Deduplicar **sólo lo generado automáticamente** por `videoId`; conservar duplicados manuales o del álbum. Limitar reintentos y mostrar un fin honesto si no hay más resultados o falla la red.
- Los temas de álbum respetan primero el álbum; la radio posterior se añade detrás del contexto y de las inserciones manuales. Reusar `get_next` cuando corresponda para metadatos/continuación, sin copiar el cliente InnerTube de LiMusic.
- Interruptor de autoplay real. Siguiente en el último tema puede solicitar el siguiente lote; el botón indica carga y un fallo deja el estado recuperable. Cambiar de cuenta cancela/descarta consultas de radio pendientes.

**Salida:** una canción sola y un álbum continúan con radio, sin duplicaciones por carrera ni bloqueo del control al fallar la red.

### W17 — restauración y cierre de robustez

- Persistir snapshot de cola, índice, modos, contexto y posición **por cuenta** con formato versionado. Tras reinicio, restaurar pausado; resolver URL nueva sólo al reanudar. Logout limpia o separa el snapshot de esa cuenta; nunca muestra su cola en invitado/otra cuenta. Si no hay sesión, la cola pública usa identidad de invitado separada.
- Reintento u omisión visible ante resolución fallida, URL vencida o pista no disponible. No avanzar infinitamente por pistas fallidas: tope por lote/cola con mensaje. Verificar pausa/seek/volumen después de cada transición.
- Comprobar comportamiento al cerrar durante una carga, reconectar red y volver desde suspensión. Añadir medición de transición entre canciones antes de decidir si vale la pena implementar lookahead/gapless como otro plan.

**Salida:** cola y posición reaparecen pausadas tras reinicio y no se mezclan entre cuentas; fallos de stream tienen una salida clara.

## 5. Matriz de pruebas por paquete

| Escenario | Primer paquete | Resultado obligatorio |
| --- | --- | --- |
| Álbum desde pista intermedia; EOF; último tema | W13 | Audio, índice, carátula, barra y fullscreen apuntan a la misma ocurrencia; fin correcto. |
| Anterior después de 4 s y antes de 3 s | W13 | Primero reinicia; luego retrocede. |
| Clic A→B→C y EOF de A mientras C carga | W13 | Sólo C puede sonar y actualizar la UI. |
| Dos copias con igual `videoId` | W13/W14 | Clic, resaltado y eliminación afectan la ocurrencia elegida. |
| Añadir a continuación y al final durante álbum | W14 | Orden manual FIFO y retorno al contexto. |
| Shuffle y cada modo repeat con salto manual/EOF | W15 | Orden e índice estables; fin o repetición según modo. |
| Radio lenta, duplicados, red caída y cambio de cuenta | W16 | Sin duplicación, bloqueo ni actualización tardía. |
| Reinicio, reanudar, logout y segunda cuenta | W17 | Datos aislados y URL de audio resuelta de nuevo. |

En cada paquete: pruebas unitarias de **transiciones de cola** en Rust (índices, duplicados, EOF y carreras donde se puedan simular), `corepack pnpm check`, `corepack pnpm build`, `cargo check` y `cargo build` de Windows con el entorno x64/`SIDEB_MPV_DIR` documentado. Probar audio **escuchable** en la app real, más barra/fullscreen y teclado. `cargo test` para los crates tocados. Registrar comando, resultado y límite de cada prueba en `documentation/handoffs/Wxx-result.md`; no declarar probado algo sólo por compilar. Si se altera una API Apple, exigir build Apple en host macOS antes de cerrar ese paquete.

## 6. Decisiones de alcance y riesgos

1. **No meter todo en un paquete.** W13 establece el contrato y la UI real; W14–W17 lo amplían sin cambiar quién posee el estado.
2. **No asumir que LiMusic es el contrato de producto.** Sus reglas de `previous`, `repeat`, segmentos manuales y eventos sirven de referencia, pero Side B debe mantener su propia semántica documentada y sus tipos.
3. **No confundir EOF con error.** EOF avanza según cola/modo; fallo puede reintentar u omitir con tope. Una respuesta vieja de red o motor no mueve la cola nueva.
4. **No prometer gapless.** Primero lograr transiciones correctas; medir la pausa audible y plantear precarga sólo si hace falta.
5. **No guardar streams.** Persistir IDs/metadatos/posición, nunca URLs firmadas, headers ni cookies en snapshots o eventos UI.

**Primer trabajo recomendado:** W13. Es la base para todos los demás y elimina la cola visual ficticia del fullscreen sin exigir radio o persistencia en el mismo cambio.
