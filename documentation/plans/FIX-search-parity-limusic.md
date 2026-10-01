# Búsqueda global y paridad con Limusic

**Estado: Windows implementado · macOS pendiente**  
**Fecha:** 2026-10-01  
**Objetivo:** conservar el diseño de búsqueda de Side B y completar los datos y secciones que necesita para presentar resultados con la estructura de YouTube Music: resultado principal, canciones asociadas, canciones, álbumes, artistas, videos y playlists.

**Actualización 2026-10-01:** Windows reutiliza el parser compartido existente y añade la API de videos para `windows-bridge`; Windows ya presenta los resultados globales y sus filtros. La API `search_videos` y los flags de tarjeta son exclusivos de `windows-bridge`, por lo que no modifican el ABI UniFFI usado por macOS. La etapa macOS y la comprobación manual de búsqueda con una cuenta siguen pendientes.

## Hallazgos verificados

### Qué hace Limusic

- La página consulta en paralelo `searchAll(q, true)`, `search(q, false)` y `searchVideos(q)` ([`+page.svelte`](../../../limusic-master/ui/src/routes/search/+page.svelte#L97-L112)). La búsqueda sin filtro escribe la consulta enviada en el historial; las búsquedas de canciones y videos no la escriben otra vez ([`endpoints.rs`](../../../limusic-master/crates/innertube/src/endpoints.rs#L64-L97), [`+page.svelte`](../../../limusic-master/ui/src/routes/search/+page.svelte#L97-L105)). Si falla la búsqueda filtrada de canciones o videos, el resultado mixto sigue disponible.
- El resultado mixto de YouTube Music es una respuesta plana: el parser clasifica las filas por su destino y guarda por separado la tarjeta `musicCardShelfRenderer` y sus filas relacionadas en `top`; las demás filas entran en `songs`, `albums`, `artists` y `playlists` ([`browse.rs`](../../../limusic-master/crates/innertube/src/models/browse.rs#L547-L602)). No hay un ranking local de títulos: el orden llega de la respuesta de YouTube.
- La vista usa `top[0]` como tarjeta principal y entrega `top[1..]` como filas asociadas; `TopResult.svelte` conserva hasta tres canciones de esas filas ([`+page.svelte`](../../../limusic-master/ui/src/routes/search/+page.svelte#L487-L518), [`TopResult.svelte`](../../../limusic-master/ui/src/lib/components/TopResult.svelte#L20-L46)). Por eso la tarjeta de artista puede incluir temas conocidos sin otra consulta por artista.
- «Todo» muestra hasta cinco canciones y cuatro videos; los filtros de canciones y videos muestran sus listas completas. Álbumes, artistas y playlists se piden con filtros propios al abrir su sección ([`+page.svelte`](../../../limusic-master/ui/src/routes/search/+page.svelte#L174-L197), [`+page.svelte`](../../../limusic-master/ui/src/routes/search/+page.svelte#L288-L306), [`+page.svelte`](../../../limusic-master/ui/src/routes/search/+page.svelte#L487-L540)).
- Limusic envía la consulta principal con `record_history=true`; las consultas de autocompletado usan `false`. En el core, ese parámetro también elige entre contexto de cuenta y anónimo: el comentario del código aclara que la respuesta anónima puede carecer de ranking personalizado ([`endpoints.rs`](../../../limusic-master/crates/innertube/src/endpoints.rs#L64-L97)).
- Las identidades empaquetadas `WEB_REMIX` tienen el mismo `clientName`, `clientVersion` (`1.20260213.01.00`) y `clientId` (`67`) en los dos repositorios ([Limusic `clients.json`](../../../limusic-master/crates/innertube/clients.json#L1-L9), [Side B `clients.json`](../../core/crates/innertube/clients.json#L1-L9)). Los filtros de canciones, álbumes, artistas y playlists también tienen el mismo valor; Limusic además define `FILTER_VIDEO` y Side B no ([Limusic `endpoints.rs`](../../../limusic-master/crates/innertube/src/endpoints.rs#L20-L26), [Side B `endpoints.rs`](../../core/crates/innertube/src/endpoints.rs#L20-L25)). Ambos locales predeterminados son `gl=US`, `hl=en` ([Limusic `context.rs`](../../../limusic-master/crates/innertube/src/models/context.rs#L8-L17), [Side B `context.rs`](../../core/crates/innertube/src/models/context.rs#L8-L17)); una configuración regional reemplazada en runtime aún debe compararse.

### Base de Side B al comenzar el fix

- El core de Side B ya tiene `InnerTube::search_all` y `parse_search_all`, y su parser también añade la ficha principal seguida por sus filas relacionadas a `top` ([`endpoints.rs`](../../core/crates/innertube/src/endpoints.rs#L133-L175), [`browse.rs`](../../core/crates/innertube/src/models/browse.rs#L512-L553)). Una fixture sintética cubre la tarjeta principal y las categorías, pero no prueba filas relacionadas dentro de `top` ([`browse.rs`](../../core/crates/innertube/src/models/browse.rs#L1767-L1830)). La relación no está perdida en el parseo.
- `SearchResultsRecord` ya transporta `top`, `songs`, `albums`, `artists` y `playlists`. El core convierte las filas de `top` en `BrowseCardRecord`; ese tipo admite `kind`, `id`, título, subtítulo, thumbnail y duración, suficientes para conservar canciones relacionadas sin modificar ese record ([`lib.rs`](../../core/crates/sideb-core/src/lib.rs#L236-L276), [`lib.rs`](../../core/crates/sideb-core/src/lib.rs#L361-L368), [`lib.rs`](../../core/crates/sideb-core/src/lib.rs#L1482-L1544)). No hay un campo de videos en el resultado común.
- En macOS, búsqueda rápida, envío y cambio de categoría llaman `searchAll(..., recordHistory: false)`; la pestaña Canciones usa además `searchSongs(..., false)` ([`SearchViewModel.swift`](../../apple/Sources/SideB/ViewModels/SearchViewModel.swift#L100-L124), [`SearchViewModel.swift`](../../apple/Sources/SideB/ViewModels/SearchViewModel.swift#L154-L181), [`SearchViewModel.swift`](../../apple/Sources/SideB/ViewModels/SearchViewModel.swift#L194-L242)). La respuesta `top` sí llega a la vista, pero esta presenta `results.top.first` y no consume `results.top.dropFirst()`; las canciones asociadas quedan ocultas ([`SearchView.swift`](../../apple/Sources/SideB/Views/Search/SearchView.swift#L233-L252), [`SpotlightSearchModal.swift`](../../apple/Sources/SideB/Views/Search/SpotlightSearchModal.swift#L197-L208)). Las secciones dependen del tipo del resultado principal ([`SearchViewModel.swift`](../../apple/Sources/SideB/ViewModels/SearchViewModel.swift#L258-L284)).
- Windows solo declara los modos `songs` y `albums`, con comandos `search_songs` y `search_albums` ([`controller.ts`](../../windows/src/lib/search/controller.ts#L1-L18), [`controller.ts`](../../windows/src/lib/search/controller.ts#L97-L114)). Tauri registra esos dos comandos; `search_songs` llama al core con `record_history=false` y los álbumes usan `search_cards` ([`catalog.rs`](../../windows/src-tauri/src/commands/catalog.rs#L6-L69), [`lib.rs`](../../windows/src-tauri/src/lib.rs#L510-L521)). El core todavía no ofrece `search_videos`; InnerTube no define el filtro `FILTER_VIDEO` ni un método `search_videos`.

### Causa comprobada y límites

La falta de búsqueda global, sus categorías y videos en Windows, y la falta de presentación de las filas asociadas a la tarjeta principal en macOS, son diferencias comprobadas en el código. El core compartido ya parsea la tarjeta y sus canciones asociadas: no corresponde reemplazar el parser ni inventar una clasificación o reordenamiento local para recuperar esa relación.

El cliente y los filtros compartidos que ya existen coinciden en sus configuraciones empaquetadas; no hay evidencia de que una versión/client ID distinto explique estas diferencias. La búsqueda principal de Limusic lleva contexto autenticado; las llamadas de búsqueda de Side B inspeccionadas usan `false`, que el core convierte en contexto anónimo. El comentario del core dice que esto omite el ranking personalizado. Es una causa plausible de que dos clientes reciban distinto artista, canciones o posiciones; sin comparar las respuestas con la misma consulta, región, idioma, versión de cliente y contexto de cuenta no queda demostrado que explique un resultado concreto. Tampoco se afirma que dos consultas reales vayan a devolver idénticas posiciones.

La UI de Búsqueda de Limusic inspeccionada no renderiza «Volver a escucharlo» como sección independiente. No se concluye que la respuesta cruda de YouTube no contenga esa sección: el parser actual recorre una respuesta plana y no conserva rótulos para cada fila. Side B tampoco conserva esos rótulos. Antes de separarla, comprobar la forma con una fixture sintética o una respuesta saneada; no crear historial local artificial para imitarla.

## Diseño propuesto

1. Reutilizar `search_all` y `parse_search_all` existentes. Documentar y probar el contrato de `top`: el primer elemento es la tarjeta principal; los siguientes son filas relacionadas suministradas por el mismo `musicCardShelfRenderer`. Renderizar el principal con el componente existente y hasta tres canciones relacionadas, conservando su orden recibido.
2. Añadir una ruta tipada para búsquedas de videos que use el filtro de YouTube Music que ya usa Limusic y el indicador `musicVideoType`; no clasificar por palabras del título. Respetar el ajuste `hide_videos` ya aplicado a resultados del core y verificar cómo se representa en los resultados filtrados.
3. Para la lista Canciones, usar el resultado filtrado de `search_songs`, que trae duración y créditos utilizables; si falla, presentar `SearchResultsRecord.songs` como Limusic. No mezclar videos dentro de Canciones. Las secciones de álbumes, artistas y playlists consumen las categorías del resultado mixto; sus vistas de «ver más» conservan `search_cards` y sus filtros existentes.
4. Mantener el orden enviado por YouTube para cada colección; la UI puede limitar filas en «Todo» y revelar el resto en el filtro propio. No crear puntuación local por coincidencia de nombres ni inferir que la primera canción es mejor que la tarjeta `top`.
5. Conservar la UI y navegación vigentes de macOS y Windows. En el índice y presentación macOS, consumir las filas `top` posteriores a la principal como canciones relacionadas y añadir Videos. En Windows, ampliar el modelo/controlador existente a búsqueda global y filtros; exponer las acciones de detalle/reproducción usando los comandos y componentes ya disponibles.

### Criterios funcionales para tarjeta principal

- Activar la tarjeta principal de artista abre su perfil usando el `browseId` del proveedor.
- Mostrar hasta tres canciones de `top` posteriores a la tarjeta, según el orden recibido. Deben poder reproducirse como canciones con identidad y metadatos preservados; reutilizar la cola/radio y las acciones de reproducción existentes.
- La acción de mezcla/aleatorio solo aparece si existe un endpoint del proveedor que la respalde; no simularla reordenando localmente las filas.
- Reutilizar los menús compartidos de canción y tarjeta, incluidas las acciones Me gusta disponibles para ese resultado, y mantener activación por teclado.
- Mantener estilos, navegación y componentes visuales propios de Side B; Limusic es referencia de datos y estructura funcional, no de presentación. Si falla la imagen, usar el fallback existente o dejar la imagen vacía; no fabricar assets.

### Contrato y compatibilidad

- Mantener las firmas existentes de `SearchResultsRecord` y `BrowseCardRecord`. El orden de `top` ya comunica la asociación en el parser y la prueba propuesta debe fijar ese comportamiento. Sin embargo, `BrowseCardRecord` pierde `play_count`, `is_video`, `is_upload` y `explicit`; en macOS también omite `artists`, IDs y `artist_runs`, que sólo se agregan bajo `windows-bridge` ([`BrowseItem`](../../core/crates/innertube/src/models/browse.rs#L25-L62), [`BrowseCardRecord`](../../core/crates/sideb-core/src/lib.rs#L236-L276)). Antes de implementar filas de canción asociadas, comprobar qué atributos necesitan los controles Side B. Si requieren créditos enlazables u otras acciones de `SongItemRecord`, acordar un record/DTO aditivo de presentación compartido o ampliar explícitamente el ABI y regenerar Apple; no suponer que el `BrowseCardRecord` actual contiene todos los metadatos.
- Añadir en Rust una operación tipada `search_videos(query, ...) -> Vec<SongItemRecord>` y el filtro de YTM usado por Limusic, sin cambiar la firma de métodos actuales. Usar el mismo método de core desde UniFFI/macOS y Tauri/Windows, con DTO Windows serializado en camelCase. Agregar un método UniFFI requiere regenerar `SideBCore.xcframework` y bindings Swift y probar ambos consumidores.
- Recomendación para las búsquedas enviadas: ejecutar el resultado mixto con contexto de cuenta y registrar una sola consulta; las previews permanecen anónimas y sin historial. Mantener una preferencia de usuario existente si la hay. Hoy `record_history` controla contexto y escritura simultáneamente; si el producto necesita personalización sin escritura de historial, separar esas opciones en el contrato tipado, sin reutilizar el booleano ambiguo. Aplicar la misma política en ambos shells.
- Vincular el caché a consulta normalizada, modo/categoría y época de sesión; invalidar al cambiar de cuenta. Una respuesta de contexto anónimo no debe servirse como si viniera de una consulta autenticada, ni viceversa. Respuestas tardías de una consulta anterior no pueden reemplazar la actual.
- No guardar cookies, cabeceras, IDs de usuario ni cuerpos de respuesta en fixtures o logs. Usar solo JSON sintético sin sesión.

## Etapas y dependencias

### 1. Core Rust / UniFFI

**Estado:** Parser y API de videos implementados en el core; `search_videos` y `BrowseCardRecord.is_video`/`explicit` se exponen solo con `windows-bridge`. El ABI predeterminado UniFFI no cambió; la integración macOS permanece pendiente.

**Archivos de implementación previstos:** `core/crates/innertube/src/endpoints.rs`, `core/crates/innertube/src/models/browse.rs`, `core/crates/sideb-core/src/lib.rs` y pruebas locales correspondientes; regenerar `apple/SideBCore` si se añade la API UniFFI.

- Confirmar el filtro de video que usa Limusic junto a los filtros actuales y parsearlo con el modelo existente de canciones, sin heurísticas de título.
- Extender fixtures sintéticas: tarjeta de artista con Waves, Follow God y Runaway en `top[1..]`; secciones separadas; canción mixta y filtrada con metadata; video marcado por el proveedor; respuestas sin sección; ajuste de ocultar videos; errores aislados. Fijar límites y orden que proceden del parser/filtros.
- Mantener cada tipo de respuesta de proveedor tolerante a secciones ausentes y sin deduplicar canciones por título.

**Depende de:** nada. Entrega: tipos, parser/API y fixtures revisados antes de conectar ambos shells.

### 2. Windows / Tauri + Svelte

**Estado:** Implementado. Tauri registra `search_all`, `search_videos` y `search_cards`; el controlador y la vista soportan Todo, canciones, videos, álbumes, artistas y playlists, conservan errores parciales, controlan respuestas obsoletas por consulta/sesión y usan la tarjeta principal con sus canciones relacionadas.

**Ámbito previsto:** `windows/src-tauri/src/commands/catalog.rs`, registro de comandos en `windows/src-tauri/src/lib.rs`, `windows/src-tauri/src/dto.rs`, `windows/src/lib/types.ts`, `windows/src/lib/search/controller.ts` y componentes de búsqueda existentes.

- Exponer el resultado global y búsqueda de videos mediante el core; mantener listas tipadas y errores parciales para que un fallo del filtro de canciones/videos no oculte las demás secciones.
- Ampliar el estado/caché del controlador con invalidación por query/revisión y sesión; asociar cada respuesta al target vigente.
- Mantener presentación visual y navegación Side B. En «Todo», mostrar tarjeta principal y tres canciones asociadas, cinco canciones, estantes de álbumes/artistas, hasta cuatro videos y playlists; los filtros muestran el resultado completo devuelto.
- Agregar casos sintéticos al controlador para respuestas fuera de orden, fallo parcial, cambio de cuenta y caché con contexto distinto.

**Depende de:** contratos y fixtures del core aprobados. Mantener cambios Tauri/TypeScript en un mismo encargo para no cruzar el límite de DTO.

### 3. macOS / SwiftUI

**Estado:** Pendiente. No se modificaron vistas Swift, bindings ni XCFramework en esta etapa.

**Ámbito previsto:** `apple/Sources/SideB/ViewModels/SearchViewModel.swift`, vistas de `apple/Sources/SideB/Views/Search/`, pruebas de búsqueda y bindings UniFFI generados.

- Usar `top.dropFirst()` para presentar las canciones ya asociadas con la tarjeta principal, sin nueva búsqueda del artista ni reordenamiento.
- Cargar y mostrar sección/filtro de Videos con el método compartido nuevo; conservar la estructura, componentes y navegación macOS.
- Mantener las políticas actuales de previews e historial mientras el contrato de contexto/personalización se decide explícitamente.

**Depende de:** etapa core y XCFramework/bindings actualizados. Windows y macOS pueden avanzar en paralelo después de cerrar el contrato y la fixture compartida; no editar ambos shells dentro de un mismo encargo.

## Comprobación propuesta

### Verificación ejecutada para Windows (2026-10-01)

- `pnpm check`: 0 errores y 0 advertencias; `pnpm test`: 88/88; `pnpm build`: aprobado.
- `cargo test --locked -p innertube`: 90/90; `cargo test --locked -p sideb-core`: 82 aprobadas y 7 ignoradas; `cargo test --locked -p player`: 4/4; `cargo test --locked --lib` en Tauri: 23/23. La suite `sideb-core --features windows-bridge` aprobó 84 pruebas y dejó 7 pruebas en vivo ignoradas.
- `windows/scripts/windows.ps1 -Action build -Configuration debug`: creó el ejecutable standalone y `libmpv-2.dll` en `S:\sideb-target\windows\debug`. Se abrió el ejecutable; Windows informó PID 26128, título `Side B` y `Responding=True`.
- Pendiente: validar manualmente búsqueda global y filtros dentro de la app con cuenta, incluyendo resultados reales y audio reproducible. No se probaron cuentas ni consultas en vivo en esta verificación.
- Pendiente: implementar y verificar la integración macOS, sus bindings UniFFI y XCFramework. No se ejecutaron pruebas Swift.

### Pruebas locales con fixtures sintéticas

- Parser: tarjeta principal artista más tres relacionados en orden; categorías separadas; respuesta vacía/malformada; canciones mixtas frente a canciones filtradas; videos por tipo reportado por YouTube; ajuste de ocultar videos.
- Integración core: `search_all` mantiene sus campos y comportamiento; `search_videos` respeta el contexto explícito, manejo de errores y ajuste de videos. Sin red, cuenta ni datos de sesión.
- Windows: `pnpm check`, pruebas del controlador afectado y build frontend; gate nativo Tauri al cambiar comandos/DTO.
- macOS: `swift test --package-path apple`, regeneración del XCFramework y compilación de ambas partes cuando el contrato UniFFI cambie. En Windows no afirmar validación de compilación Swift.
- Revisión manual separada por shell: búsqueda enviada «Kanye West», búsqueda rápida «Kanye», cambio de consulta durante requests activos, vista Todo y filtros; comprobar tarjeta con sus canciones asociadas, canciones, álbumes, artistas, videos y playlists. Repetir con fallback de filtro fallido, vídeos ocultos, sin resultados y cambio de sesión.

### Comparación de ranking con YouTube Music

Si se necesita explicar la identidad/posición de resultados, hacer después una comparación en vivo independiente: misma consulta literal, mismo dispositivo/región/idioma y versión `WEB_REMIX`, primero sin sesión y luego con la misma cuenta. Registrar solo IDs/títulos públicos y valores no sensibles de contexto; no guardar cookies ni respuestas crudas con datos de sesión. Separar lo que procede de `search_all`, `search_songs` y `search_videos`. El resultado variable del proveedor no es un test determinista ni una garantía de paridad exacta.

## Riesgos y límites

- Un campo nuevo en `SearchResultsRecord` alteraría el record UniFFI y exigiría regenerar bindings y XCFramework; se propone método tipado aditivo para videos.
- `search_all` y los filtros son requests separados: pueden devolver conjuntos/orden distintos. La UI debe aceptar error parcial y evitar sustituir la tarjeta principal por el primer tema filtrado.
- El servidor puede cambiar su ranking por sesión, región, idioma, versión de cliente, experimentos y personalización. Side B no debe afirmar paridad absoluta a partir de screenshots distintos.
- Las consultas adicionales agregan latencia y requests. Ejecutarlas en paralelo como Limusic, sin registrar una consulta enviada más de una vez, y conservar cache/session epochs.
- «Volver a escucharlo» queda pendiente de identificar su origen a partir de una forma de respuesta conservada/saneada; no se debe fabricar historial local ni asumir que es ajena a la respuesta cruda.

## Referencias visuales

La UI que se conserva es la de Side B en macOS y Windows; Limusic sirve como evidencia del contrato de resultados y de la relación entre tarjeta principal y canciones, no como plantilla visual. Las tres capturas que el encargo indicó copiar no estaban disponibles en las rutas `Temp/codex-clipboard-*.png` de este host. No se copiaron ni recrearon; las observaciones usadas aquí son la descripción textual recibida: artista principal con tres canciones, secciones de canciones/álbumes/artistas/videos/playlists y la sección distinta «Volver a escucharlo».
