# Arquitectura Windows

## Responsabilidades

| Capa | Código | Responsabilidad |
|---|---|---|
| Composición | `src/routes/+page.svelte` | Shell, navegación, historial de vistas y conexión entre dominios |
| Presentación | `src/lib/components/`, `styles/tokens.css` | Vistas y controles; referencia visual en `apple/Sources/SideB/Views/` |
| Home | `src/lib/home/controller.ts`, `presentation.ts` | Carga/chips/continuaciones; identidad y orden de estantes |
| Búsqueda | `src/lib/search/controller.ts` | Consultas por modo, caché de sesión e invalidación |
| Catálogo | `src/lib/catalog/controller.ts` | Álbum, artista, grillas, snapshots y solicitudes pendientes |
| Cuenta | `src/lib/account/controller.ts` | Biblioteca, likes, playlists e historial; cambios y paginación por cuenta |
| Navegación/ventana | `src/lib/navigation/history.ts`, `window/controller.ts`, `components/shell/TitleBar.svelte` | Atrás/Adelante, snapshots y controles Tauri; F11 alterna fullscreen nativo |
| Menús | `src/lib/menu/{types,policy,hooks,executor}.ts`, `components/menu/ContextMenu.svelte` | Política común de macOS, clic derecho/Más, disponibilidad y ejecución por controller |
| Reproductor UI | `src/lib/player/controller.ts` | Comandos y eventos; snapshot de transporte publicado para barra/fullscreen |
| Actualizador UI | `src/lib/updater/controller.ts`, `components/update/UpdateModal.svelte` | Comprobación manual y automática, Fix Report, barra de progreso y coordinación de actualización |
| Contratos frontend | `src/lib/types.ts`, `account/types.ts`, `updater/types.ts` | DTOs del bridge; estado de cuenta y actualización tipado |
| Integración nativa | `src-tauri/src/lib.rs` | Inicialización, estado compartido, autenticación, eventos y registro Tauri |
| Bridge | `src-tauri/src/dto.rs`, `commands/` | Conversión de records y comandos de catálogo/cuenta/reproducción/actualización |
| Actualizador nativo | `src-tauri/src/commands/updater.rs`, `nsis_hooks.nsh` | Consulta SemVer a GitHub Releases, streaming de instalador NSIS y script trampoline de reinicio |
| Cola | `src-tauri/src/queue.rs` | Pistas por ocurrencia, índice y revisión; límites de next/previous |
| Sesión | `src-tauri/src/session.rs`, `session_store.rs` | Login WebView2, cancelación, restauración y protección de credenciales |
| Core | `../core/crates/sideb-core`, `innertube`, `player` | Proveedor/red/persistencia/streams y wrapper libmpv |

## Flujo de datos

Los controladores TypeScript reciben RPC/listeners y publican snapshots a Svelte. La inyección permite probar respuestas y eventos sin Tauri, red ni una cuenta real. Los componentes reciben datos y callbacks; no vuelven a consultar el proveedor por su cuenta.

La cola autoritativa está en Rust. Los eventos `playback-state-changed` y `playback-progress` actualizan tanto barra como fullscreen. `entryId` identifica una ocurrencia, `generation` una carga de audio y `queue.revision` una modificación de cola. Selecciones retrasadas usan entryId, no un índice que pudo cambiar. Una canción repetida conserva dos entradas. El frontend descarta estados anteriores; Rust valida las operaciones retrasadas y el avance por EOF.

Para playlists, Rust conserva el orden completo pero publica inicialmente la pista seleccionada y hasta 99 siguientes, además del historial anterior. Los snapshots agregan otras 100 cuando quedan diez pistas visibles por delante; el shuffle abarca también las pistas todavía no publicadas. Encolar al final o mover al final hace visible la cola completa para conservar esas acciones. `play_song` recibe el flag optativo `shuffle` junto con la colección ya mezclada, y lo conserva al avanzar entre ocurrencias. Cuenta reutiliza las páginas visibles y guarda hasta 20 catálogos completos en memoria de sesión; la hidratación de likes alimenta ese catálogo y comparte su petición con Play. Actualizar, modificar la colección o cambiar de cuenta invalida la caché. Sin un catálogo completo, la primera reproducción todavía debe resolver las continuaciones; una continuación repetida falla para evitar presentar un shuffle parcial como global.

Una canción de Inicio inicia radio: carga audio y agrega recomendaciones del core sin reiniciar la pista. El epoch de propietario de cola y la generación de sesión descartan recomendaciones obsoletas; un solo request continúa cuando quedan pocas pistas. Se deduplican recomendaciones por videoId, conservando duplicados de playlists y del encolado manual. El error de radio es recuperable e independiente del audio.

Home y catálogo invalidan solicitudes al cambiar contexto; búsqueda y cuenta vacían datos/cachés privados al cambiar de cuenta. El historial conserva snapshots y scroll en pasado/futuro, limitado a 40 entradas por pila. Una visita nueva descarta el futuro; Atrás/Adelante invalidan cargas abandonadas y restauran el destino. Los cambios de cuenta vacían ambas pilas.

Las acciones masivas de playlist resuelven continuaciones antes de reproducir/encolar y conservan setVideoId por ocurrencia. Edición/eliminación/orden validan permisos en el backend y los diálogos sólo cierran tras éxito. Los menús usan los mismos comandos que los botones. La barra superior reemplaza decoraciones Windows. Como en macOS, el reproductor expandido ocupa el área de contenido sin cambiar el tamaño de ventana; conserva sidebar, controles superiores y scroll sólo en la lista derecha. F11 controla por separado el fullscreen del sistema. La cápsula mantiene medidas fijas de controles y portada; sólo la metadata se trunca, y el volumen se despliega sin alterar el layout. La ventana conserva el mínimo macOS de 960×640. `set_shuffle` mezcla las entradas posteriores a la pista actual sin recargarla; `set_repeat` activa `loop-file` en la pista actual y el siguiente manual avanza a otra entrada. Ambos estados se devuelven en snapshots de reproducción como `isShuffle` e `isRepeat`. Genius permanece deshabilitado. La barra Windows no muestra AirPlay.

Autenticación y almacenamiento sensible permanecen en el runtime. Los DTOs no incluyen cookies ni URLs firmadas. Las vistas muestran sólo el estado público de la sesión.

Los paneles del reproductor expandido se separan en `QueuePanel`, `LyricsPanel` y `RecommendedPanel`. El reordenamiento mueve una ocurrencia por `entryId` antes de otra, o al final; conserva la entrada activa y no carga de nuevo el audio. `dragDropEnabled: false` permite que WebView2 entregue los eventos HTML de arrastre a la UI.

`player/lyrics.ts` solicita el proveedor compartido `get_lyrics`, invalida respuestas por pista/generación/sesión y calcula la línea actual a partir de la posición. La vista desplaza sólo su contenedor, suspende el seguimiento al intervenir el usuario y permite retomarlo o buscar la posición de una línea sincronizada. `player/recommendations.ts` carga al abrir Relacionado: pistas del artista, del mismo álbum, canciones parecidas y artistas afines; conserva resultados parciales, reutiliza datos de la pista y permite actualizar. Ambos controladores se limpian al cambiar de cuenta.

El actualizador automático consulta la API de GitHub Releases con SemVer, muestra una modal estilo macOS con el Fix Report, descarga con reporte de progreso a través de eventos Tauri y desacopla la instalación silenciosa mediante un trampoline batch que espera el cierre del proceso actual, ejecuta el setup NSIS en modo `/S` y reabre la app.

## Cambiar un contrato

Actualizar el comando/DTO Rust y su tipo/consumidor TypeScript juntos. Si cambia un record del core, revisar también el consumidor UniFFI macOS. Agregar pruebas cuando haya una regla o regresión observable: identidad de cola, respuesta tardía, reset de cuenta, paginación, error recuperable. Una extracción mecánica no requiere duplicar pruebas por cada función.

El bridge Tauri activa el feature optativo `sideb-core/windows-bridge` para conservar créditos de artistas y metadata de tarjetas en sus records. El contrato UniFFI de Apple se genera sin ese feature; sus campos permanecen iguales. Los DTOs Windows transportan `artistRuns` con nombre e identificador por artista desde el proveedor hasta la cola y el reproductor. La metadata que llega con una radio completa datos de pistas ya presentes conservando sus identificadores de ocurrencia y la carga de audio.

## Build

`scripts/windows.ps1` resuelve el repositorio desde su propia ubicación, prepara MSVC 2022, fija la dependencia libmpv y ejecuta comandos iguales en local y CI. La build standalone incluye frontend compilado y DLL junto al ejecutable. `package` genera el instalador NSIS per-user mediante Tauri v2, asegurando mediante un hook que `libmpv-2.dll` se instale junto al ejecutable en la máquina de destino.

La CI Windows verifica tipos, pruebas frontend y Rust, y compila el standalone. El workflow de release compila tanto `SideB-macOS.zip` como `SideB-Windows-Setup.exe` y los publica juntos en GitHub Releases.
