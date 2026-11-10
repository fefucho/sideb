# Revisión de Implementación — Cola Separada y Recomendaciones (`PLAN-018`)

**Fecha:** 2026-10-30  
**Rama evaluada:** `experiment/queue-recommendations` (árbol de trabajo contra base `f7fc479`)  
**Alcance:** Revisión directa del código nativo implementado en macOS (`apple/`) y Windows (`windows/`), sin usar el prototipo HTML ni sus 35 pruebas como evidencia de rendimiento nativo. `core/` verificado sin cambios (`git diff f7fc479 -- core/` vacío).

## Veredicto Ejecutivo

- **Estado:** **Con bloqueos puntuales antes de cerrar/empaquetar.** La arquitectura base pedida para rendimiento y separación de cola está bien encaminada en ambas plataformas, pero existen **6 bloqueos reales de contrato/estado/escala** (4 en Windows, 2 en macOS) y **5 hallazgos altos** que deben corregirse antes del build final.
- **Límites explícitos de medición:**
  - **No están medidos FPS reales** de scroll/animación en macOS ni en Windows WebView2 (no se ejecutó la app ni servidores/previews).
  - **No está certificado audio/runtime real de Tauri en Windows**: en macOS `cargo check` falla únicamente por los símbolos `#[cfg(target_os = "windows")]` preexistentes del módulo `session` (`login_webview`, `cancel_login`, `sign_out`, `session::restore`, `session::watch_rotations`); `queue.rs`, `commands/playback.rs` y `playback_runtime.rs` no arrojaron errores de tipos propios en `temp/queue-design-qa/windows-cargo-check-no-bundle.log`.

---

## 1. Garantías Verificadas (Sin Regresión)

1. **`core/` intacto:** Cero modificaciones bajo `core/`.
2. **macOS — Reciclaje, ventana acotada y aislamiento de progreso:**
   - `NativeSeparatedQueueView.swift` usa una única `NSTableView` AppKit reciclando `NativeQueueTrackCellView` (`makeView(withIdentifier:)`), sin listas SwiftUI por canción ni tablas anidadas.
   - `QueueManager.visiblePendingIndices` (`QueueManager.swift:168-176`) limita la proyección inicial a `100` pendientes de fuente + hasta `100` manuales recientes (`recentlyInsertedOccurrenceIDs`), expandible bajo demanda (`expandPendingWindow`, `L180-182`), con `Anteriores` plegado por defecto (`showPrevious = false`).
   - `occurrenceIndex(for:)` (`QueueManager.swift:124-137`) cachea `[String: Int]` por `occurrenceStructureRevision`, evitando búsquedas $O(N^2)$ al construir filas sobre colas de 10.000 pistas.
   - `presentationRevision` no cambia con `currentTime` (10 Hz); `NativeSeparatedQueueView.refresh()` (`L89-105`) no reconstruye filas por progreso y sí recibe un incremento único cuando `rememberCurrentTrackDuration` (`PlayerViewModel.swift:344-354`) resuelve una duración ausente en catálogo.
   - `PlaybackStateStore.scheduleSave(snapshot:)` (`PlaybackStateStore.swift:127-191`) ejecuta el closure `playbackSnapshot()` **después** del debounce de 350 ms y delega codificación JSON + escritura atómica a una `DispatchQueue` `.utility`, drenando con `writer.sync` en `flush()` / `activate(_:)`.
3. **Windows — Cero clones de cola por progreso y virtualización de `QueuePanel`:**
   - `PlaybackController.acceptProgress` → `emittedSnapshot` → `cloneState(this.state, undefined, this.publishedQueue)` (`controller.ts:57-70, 121-134, 205-211`) reutiliza `this.publishedQueue` sin recorrer `items` ni `recommendations`. En `+page.svelte:218`, `playerBarState` sólo hace spread superficial $O(1)$, y ningún consumidor de reproducción lee el getter `.snapshot` en ticks de progreso.
   - `queueProjection.ts` + `QueuePanel.svelte` mantienen `Anteriores` plegado por defecto (10.000 pistas previas quedan fuera del rango virtual salvo su cabecera), conservan altura uniforme de slot (`48px` = `46px` + `2px` tanto en `.queue-section-heading` como en `.queue-row`) y mantienen filas con foco o arrastre montadas mediante `pinnedSlots`.
4. **Cursores separados, stale IDs/generación, doble consumo EOF y dislike:**
   - `radioCursorVideoID` / `radio_cursor_video_id` avanza con el lote del proveedor y se persiste separado de `queue.last` (`QueueManager.swift:92, 336`; `PlayerViewModel.swift:250, 1344`; `playback_runtime.rs:88`; `commands/playback.rs:116`).
   - Propuestas protegidas contra IDs obsoletos por `recommendationSessionID` en Mac (`PlayerViewModel.swift:1035-1068`) y `generation` + `observed_auth_generation` + `queue_epoch` en Windows (`commands/playback.rs:1203-1208, 158-165, 3050-3063`).
   - EOF protegido contra doble consumo: `AudioPlayerService.stop()` limpia observadores antes del debounce de 180 ms y `pendingTailSkipToken` ata la espera al token vigente en Mac; Windows consume `loaded_generation = None` una sola vez en `handle_track_ended` (`commands/playback.rs:1447, 1468`) y difiere si hay seek activo (`L1454-1461`).
   - Exclusión/Dislike limpia `recommendations` y pendientes no activos por sesión sin cortar la pista actual si coincide (`QueueManager.swift:525-545`; `queue.rs:1340-1370`; `+page.svelte:1187`).

---

## 2. Hallazgos Concretos (Por Severidad)

### Bloqueantes

#### B1. [BLOQUEANTE · Windows] Bucle de red no acotado en `"search-radio"` y lote inicial insertado en `items` cuando viene `continuation`
- **Archivos / funciones:**
  - `windows/src/routes/+page.svelte` — `playProviderSearchAction` (`L511-526`)
  - `windows/src-tauri/src/commands/playback.rs` — `begin_queue_source` (`L2915-2930`), `fetch_source_background` (`L2997-3115`, recursión en `L3113`), `maybe_prefetch_radio` (`L94-101`), `fetch_radio` (`L160-165`)
- **Evidencia:**
  1. En `+page.svelte:519-524`, `if (radio && !next.continuation && playlistId)` sólo invoca `startSourceRadio` cuando **no** hay `continuation`. Si `search_action` devuelve una radio con `next.continuation` (caso normal en mixes `RD...` o semillas de canción) o sin `playlistId`, cae al `else` y llama `playCollection(next.items, startingAt, source)`, metiendo las ~25 pistas del lote inicial en `items` («A continuación») en vez de `recommendations`.
  2. Inmediatamente después invoca `beginProgressiveSource({ kind: 'search-radio', ..., continuation })`, que lanza `fetch_source_background`. Al recibir cada página (`playback.rs:3087-3089`), fusiona en `recommendations` y en `L3113` vuelve a llamar `fetch_source_background(app)` sin límite de reserva ni compuerta de cercanía al final. En una continuación de radio de YouTube Music (flujo prácticamente infinito), esto dispara páginas de `get_next_continuation` en bucle indefinido, inflando `recommendations` y `loaded_prefix` sin cota.
  3. Además, si una cola queda con `source.kind == "search-radio"`, `maybe_prefetch_radio` (`L98`) y `fetch_radio` (`L163`) rechazan cualquier `source.kind != "radio"`.
- **Acción:** En `playProviderSearchAction`, iniciar siempre salidas `radio` sembrando 1 pista elegida + `recommendations` (nunca `playCollection` con todo el lote en `items`). En `fetch_source_background`, no encadenar otra página para `"search-radio"` cuando `recommendations` ya supera el umbral de reserva; reanudar sólo cerca del borde, igual que `PlayerViewModel.checkAutomixTrigger` en Mac (`L1281-1315`).

#### B2. [BLOQUEANTE · Windows] «Agregar al final», mover al final o promover recomendación rompe permanentemente el batching de 10k pistas (`visible_len = items.len()`)
- **Archivo / funciones:** `windows/src-tauri/src/queue.rs` — `snapshot` (`L530-555`), `enqueue` (`L898-904`), `move_entry` (`L1057-1059`), `choose_recommendation` (`L1255-1259`), `promote_next_recommendation` (`L1214-1220`)
- **Evidencia:** En una playlist de 10.000 pistas (`visible_len = 100`), una sola llamada a `enqueue(..., false)` («Agregar a la cola»), `choose_recommendation(..., false)` (botón `+` en propuesta o promoción automática) o `move_entry(..., None)` asigna `self.visible_len = self.items.len()` (`10.001`). Desde ese momento, cada `pb.to_dto()` clona y envía por IPC las 10.001 entradas completas, y cada nuevo `queue.revision` clona las 10.001 filas en `PlaybackController`. Además, `snapshot()` (`L541`) clona todo `self.recommendations` sin tope (Mac publica `prefix(25)`). Incumple la Decisión 6 de `PLAN-018`.
- **Acción:** Mantener `visible_len` acotado alrededor de `current_index` y proyectar manuales de cola final sin exponer los 9.900 ítems intermedios de fuente (o mantener conjunto de inserciones manuales recientes como Mac `QueueManager.swift:168-176`), además de acotar `recommendations` en `snapshot()`.

#### B3. [BLOQUEANTE · Windows] Desactivar `Shuffle` cuando la pista actual es manual o recomendación convierte pendientes no reproducidas en `Anteriores`
- **Archivo / función:** `windows/src-tauri/src/queue.rs` — `restore_original_order` (`L733-808`)
- **Evidencia:** Si una playlist barajada reproduce en `index = 0` una pista con rango canónico tardío (p.ej. `rank = 1616`), el usuario elige una propuesta con «Reproducir ahora» o avanza a un manual insertado `After(rank 1616)` (`index = 1`) y apaga `Shuffle`, `restore_original_order` ordena todas las fuentes `0..N` por `source_ranks` y proyecta la pista actual después de su padre (`current_index = 1617`). Las 1.616 pistas de fuente que estaban pendientes después de `current_index` pasan a `< current_index` (`Anteriores`) sin haberse reproducido. Incumple la Decisión 1 de `PLAN-018` (resuelta en Mac con `frozenPrefix` en `QueueManager.swift:646`).
- **Acción:** Si la ocurrencia activa no está en `source_ranks`, congelar el prefijo `0..=current_index` en `restore_original_order` y ordenar únicamente las ocurrencias de fuente posteriores.

#### B4. [BLOQUEANTE · Windows] Reordenamiento por drag & drop y teclado permite mover pistas hacia y desde `Anteriores` y `Ahora`
- **Archivos / funciones:**
  - `windows/src/lib/components/fullscreen/QueuePanel.svelte` — `reorderWithKeyboard` (`L165-178`), `dropOnRow` (`L208-227`), `.reorder-handle` (`L278` / render de fila)
  - `windows/src-tauri/src/queue.rs` — `move_entry` (`L1017-1064`)
- **Evidencia:** `{#if !proposal}` muestra `.reorder-handle` habilitado tanto en la fila `Ahora` como en las filas de `Anteriores` al desplegarse, y `dropOnRow` + `queue.rs::move_entry` carecen de guarda `> current_index`. Arrastrar una pista pendiente o una propuesta sobre `Ahora` o `Anteriores` inserta la pista antes de `current_index` (incrementando `current_index` y metiéndola directamente al historial sin sonar). Incumple `PLAN-018` Etapa 4.
- **Acción:** Renderizar `.reorder-handle` sólo en `row.section === 'upcoming'`, ignorar/redirigir drops cuyo destino quede `<= boundary` en `QueuePanel.svelte`, y rechazar movimientos con origen o destino `<= boundary` (`current_index` / `resume_index`) en `queue.rs::move_entry`.

#### B5. [BLOQUEANTE · macOS] Estado detenido sentinel (`currentIndex == queue.count`) borra `Anteriores` al encolar o muestra pista fantasma en «Reproduciendo ahora»
- **Archivos / funciones:**
  - `apple/Sources/SideB/ViewModels/PlayerViewModel.swift` — `playNext(song:)` (`L839-846`), `playNext(tracks:)` (`L848-857`), `addToQueue(song:)` (`L859-866`), `addToQueue(tracks:)` (`L868-878`), `chooseRecommendationNext` (`L1049-1054`), `addRecommendationToQueue` (`L1056-1061`)
  - `apple/Sources/SideB/Services/Player/QueueManager.swift` — `playNext(_:)` (`L356-381`), `addTracksToQueue(_:)` (`L384-393`), `chooseRecommendationNext(id:)` (`L493-501`), `addRecommendationToQueue(id:)` (`L504-513`)
- **Evidencia:** Tras eliminar la última pista activa (`removeQueueTrack`, `PlayerViewModel.swift:1076-1091`), `player.currentTrack` es `nil` y `queueManager.currentIndex == queue.count` con `Anteriores` intacto:
  1. Llamar `playNext(song:)` o `addToQueue(song:)` evalúa `if currentTrack == nil { playWithRadio(song); return }`, destruyendo `Anteriores` e iniciando una radio nueva; `playNext(tracks:)` y `addToQueue(tracks:)` hacen `queueManager.clearQueue()`.
  2. Llamar `chooseRecommendationNext` o `addRecommendationToQueue` inserta en `index == queue.count == currentIndex`. Eso vuelve `queueManager.currentTrack` no-nulo sin iniciar audio (`player.currentTrack == nil`), haciendo que `NativeSeparatedQueueView.buildRows` (`L113`) pinte esa pista bajo «Reproduciendo ahora» (fuera de «A continuación») estando el reproductor detenido.
- **Acción:** En estado sentinel (`currentTrack == nil && !queueManager.queue.isEmpty`), no limpiar `queueManager` ni disparar `playWithRadio`; insertar después del historial y o bien iniciar reproducción de la nueva pista o mantener un cursor de reanudación separado para que permanezca en «A continuación» hasta reproducir.

#### B6. [BLOQUEANTE · macOS] `PlaybackStateStore.identity(for: nil, cookieStorage:)` devuelve siempre `"guest"`, rompiendo la guarda de login y sesiones offline
- **Archivos / funciones:**
  - `apple/Sources/SideB/Services/Player/PlaybackStateStore.swift` — `identity(for:cookieStorage:)` (`L113-119`)
  - `apple/Sources/SideB/App/SideBApp.swift` — arranque (`L85-89`) y login (`L110-119`)
- **Evidencia:** `identity(for: nil, cookieStorage:)` ignora `cookieStorage` y devuelve `"guest"` siempre que `account == nil`. En `SideBApp.swift:110-118`, al cerrar el login webview: (1) `loginIdentity` pasa a `"guest"`, activando la sesión `"guest"` con cookies ya autenticadas mientras corre `fetchAccount`; (2) `guard PlaybackStateStore.identity(for: nil, cookieStorage: cookieStorage) == loginIdentity` (`L117`) compara `"guest" == "guest"` y pierde su protección contra carreras de logout/cambio de cookies; (3) si `fetchAccount` falla por red en el arranque (`L87`), una sesión con cookies válidas carga y sobrescribe la cola `"guest"`.
- **Acción:** Conservar en `identity(for:cookieStorage:)` el fallback de **sólo lectura** por hash `SAPISID` (`session:<sha256>` / lectura de `sideb.playbackAccounts` sin escribir en `UserDefaults` estable desde el experimento).

---

### Altos

#### A1. [ALTO · Windows] `PlaybackRuntime::persist` clona los 10k ítems (`queue.durable()`) sincrónicamente antes del debounce de 350 ms y bajo el `Mutex`
- **Archivos / funciones:** `windows/src-tauri/src/playback_runtime.rs` — `persist` (`L236-288`), `writer` (`L151-191`); `windows/src-tauri/src/queue.rs` — `durable` (`L1299-1317`); `windows/src-tauri/src/lib.rs` — `to_dto` (`L229-243`)
- **Evidencia:** El hilo `sideb-playback-store` difiere `serde_json::to_vec` + `atomic_write` 350 ms, pero `persist()` construye `SavedPlayback` ejecutando `playback.queue.durable()` sincrónicamente dentro de `pb.to_dto()` cada vez que cambia `dirty` (incluidos volumen, repeat, shuffle o saltos rápidos), clonando las 10.000 `QueueEntryDto` completas, normalizando todos sus `thumbnail` y clonando `source_ranks`, `explicit_placements` y `radio_entries` con `state.playback` tomado.
- **Acción:** Diferir la captura de `queue.durable()` tras el debounce o cachear el último `DurableQueue` por `(queue_epoch, queue.revision)` para que cambios de volumen/repeat/track no clonen 10.000 entradas.

#### A2. [ALTO · Windows] Salto manual `next_track` con `Repeat` activo envuelve a `items[0]` en lugar de promover `recommendations`
- **Archivos / funciones:** `windows/src-tauri/src/queue.rs` — `next_or_first` (`L693-710`); `windows/src-tauri/src/commands/playback.rs` — `next_track` (`L1538-1554`)
- **Evidencia:** `next_or_first(wrap_at_end)` evalúa `if wrap_at_end { return self.items.first().cloned(); }` antes de `self.promote_next_recommendation()`, y `next_track` bloquea la espera de radio en el borde cuando `playback.is_repeat == true` (`L1539`). En radio con Repeat activo, pulsar «Siguiente» repite `items[0]` indefinidamente en vez de promover una propuesta (contradice `PLAN-018` Decisión 7 y el comportamiento de Mac en `QueueManager.swift:429`).
- **Acción:** Promover `recommendations` antes de `wrap_at_end` en el salto manual `next_or_first`, y permitir espera/prefetch en `next_track` manual cuando `recommendations` está vacía aunque `is_repeat` sea `true`.

#### A3. [ALTO · Windows / Medio · macOS] Revalidación de duplicados al promover recomendaciones
- **Archivos / funciones:**
  - `windows/src-tauri/src/queue.rs` — `promote_next_recommendation` (`L1214-1220`)
  - `apple/Sources/SideB/Services/Player/QueueManager.swift` — `promoteRecommendation` (`L445-463`)
- **Evidencia:** En Windows, `promote_next_recommendation` toma `self.recommendations.first()` sin verificar si el usuario encoló y reprodujo manualmente ese mismo `video_id` después de `merge_radio`, pudiendo repetir la misma canción inmediatamente al llegar al EOF. En Mac, `promoteRecommendation` sí salta duplicados con `firstIndex(where:)`, pero sólo elimina `index` (`L452`), dejando las propuestas obsoletas saltadas `0..<index` fijas arriba de la sección «Recomendaciones».
- **Acción:** En Windows, descartar al promover entradas cuyo `video_id` esté excluido, con dislike, pendiente o en las últimas 200 reproducidas. En Mac, eliminar `0...index` al promover.

#### A4. [ALTO · macOS] `appendPlaylistTracks` no baraja páginas subsiguientes con `isShuffle == true`
- **Archivo / función:** `apple/Sources/SideB/Services/Player/QueueManager.swift` — `appendPlaylistTracks(_:)` (`L340-353`)
- **Evidencia:** Al cargar páginas 2..N de una playlist progresiva con `isShuffle == true`, `appendPlaylistTracks` agrega las nuevas pistas en orden canónico antes de `endManuals` sin barajarlas. Incumple `PLAN-018` Decisión 5 (Windows sí las baraja en `queue.rs:1386-1395`).
- **Acción:** Barajar las ocurrencias recién insertadas cuando `isShuffle == true` antes de ubicarlas delante de `endManuals`, sin rebarajar las pendientes ya publicadas.

#### A5. [ALTO · macOS] Paridad y accesibilidad en `NativeSeparatedQueueView`: sin acciones rápidas en propuestas, grip engañoso y sin mover por menú/teclado
- **Archivos / funciones:**
  - `apple/Sources/SideB/Views/Common/NativeSeparatedQueueView.swift` — `tableView(_:viewFor:row:)` (`L200-226`), `menu(forRow:)` (`L241-270`), `pasteboardWriterForRow` (`L272-278`)
  - `apple/Sources/SideB/Resources/{es,en}.lproj/Localizable.strings` — `queue.moveNext`, `queue.moveEnd` (`L1630-1633`)
- **Evidencia:**
  1. `configure(..., isReorderable: !active)` (`L208`) muestra el grip de arrastre en `Anteriores` y en `Recomendaciones`, aunque ambos tienen el drag bloqueado en `pasteboardWriterForRow` (`index > parent.manager.currentIndex`, `L274`).
  2. Las filas de `Recomendaciones` no tienen botones compactos («Siguiente» / «Al final» / «Quitar») revelados por hover/foco (`PLAN-018` Etapa 4); el clic simple reproduce inmediatamente (`activate`, `L234-239`) y el menú reutiliza `.queue(occurrenceIndex: -1)` en vez de un origen dedicado con `sessionID` + ID estable (`PLAN-018` Decisión 10).
  3. `queue.moveNext` y `queue.moveEnd` fueron añadidos en `Localizable.strings` pero no se usan en ningún archivo Swift: no hay acción de menú ni atajo de teclado para mover filas elegidas (ni `Backspace`/`Delete` para quitar o integración con `sideBMenuContext`).
- **Acción:** Pasar `isReorderable: committed && index > parent.manager.currentIndex`, añadir controles compactos de propuesta (o menú con origen dedicado de propuesta) y conectar «Mover al comienzo / al final» en filas pendientes elegidas.

---

### Medios y Bajos

#### M1. [MEDIO · Windows] `source_load` suma `recommendations.len()`, falta nota de `Repeat` y se oculta «A continuación» vacío en radio
- **Archivos / funciones:** `windows/src-tauri/src/lib.rs` (`L237-239`); `windows/src/lib/components/fullscreen/queueProjection.ts` (`L17-20`); `windows/src/lib/components/fullscreen/QueuePanel.svelte` (`L236-265`)
- **Evidencia:** (1) `lib.rs:238` pasa `items.len() + recommendations.len()` a `source_load`, sumando la reserva al contador de canciones cargadas; (2) `QueuePanel.svelte` no muestra aviso cuando `playback.isRepeat` está activo junto a recomendaciones (Mac sí en `NativeSeparatedQueueView.swift:127-129`); (3) `queueProjection.ts:17` omite la sección `upcoming` cuando hay 0 pendientes en radio en lugar de mostrar estado vacío.
- **Acción:** Pasar `self.queue.items.len()` a `source_load`, renderizar nota de Repeat cuando haya recomendaciones con `playback.isRepeat`, y mostrar estado vacío ligero en «A continuación» cuando `recommendations.length > 0` y no haya pendientes elegidas.

#### M2. [MEDIO · macOS y Windows] Sin importación inicial única desde sesión estable v2 al almacén experimental
- **Archivos / funciones:** `apple/Sources/SideB/Services/Player/PlaybackStateStore.swift` (`load`, `L193-207`); `windows/src-tauri/src/playback_runtime.rs` (`sync_account`, `L304-322`)
- **Evidencia:** El aislamiento de namespace está bien implementado (no toca los archivos estables), pero cuando el archivo experimental aún no existe para una identidad no se importa en sólo lectura la cola estable existente (`PLAN-018` Decisión 11 / Etapa 5).
- **Acción:** Si se desea continuidad al cambiar desde `main`, caer una única vez en lectura al archivo estable cuando no exista el archivo experimental, sin escribir sobre el archivo original.

#### B0. [BAJO · macOS] `MPRemoteCommandCenter.pauseCommand` no limpia `pendingTailSkipToken`
- **Archivo / función:** `apple/Sources/SideB/ViewModels/PlayerViewModel.swift` — `pauseCommand` (`L1666-1671`)
- **Evidencia:** `togglePlayPause()` (`L1609-1615`) limpia `pendingTailSkipToken = nil` al pausar, pero `pauseCommand` sólo llama `audioService.pause()`. Si llega una página de radio mientras esperaba en el borde tras pausa multimedia externa, `resumeAfterQueueExtension()` (`L1018`) reanudará audio.
- **Acción:** Limpiar `self?.pendingTailSkipToken = nil` dentro de `pauseCommand`.
