> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W13 — Cola real mínima y navegación

Fecha: 2026-09-30. Entrega W13 implementada; la validación manual de audio/UI queda pendiente.

## Implementado

- `windows/src-tauri/src/queue.rs`: modelo puro `QueueStateDto`/`QueueEntryDto`, identidad `entryId` independiente de `videoId`, replace/select/next/previous, revisión y tres pruebas unitarias para duplicados, álbum iniciado en pista intermedia, anterior >3 s / <=3 s, fin sin wrap y selección inválida.
- `windows/src-tauri/src/lib.rs`: snapshot de cola dentro de `PlaybackStateDto`; `play_song` reemplaza, selecciona o conserva la cola dentro del mismo lock donde reserva la generación. Un índice seleccionado debe coincidir con el `videoId` solicitado. Una llamada directa inicia cola singleton; reintento explícito conserva cola. Siguiente/Anterior eligen el índice en Rust, reservan transición con `expected_generation` y reproducen por el mismo `play_song`; al final Siguiente conserva el estado terminado. Anterior reinicia la actual si la posición supera 3 s o si está en el primer índice, incluso tras EOF/error; con posición <=3 s retrocede. EOF avanza desde el pump en una tarea Rust. La generación W07 descarta cargas obsoletas. Metadata y carátula de la ocurrencia tienen prioridad; la respuesta del stream completa campos ausentes en la misma fila. Logout y stop limpian cola.
- `windows/src/routes/+page.svelte`: canciones sueltas crean cola individual; álbum crea todas sus ocurrencias en orden y selecciona la ocurrencia clicada; reintento conserva cola. Barra y filas fullscreen llaman navegación y presentan snapshot real. Fila de álbum resalta por contexto e índice; fullscreen identifica filas por `entryId`. Cada pista usa su thumbnail antes del álbum.
- `PlayerBar.svelte` y `FullscreenNowPlaying.svelte`: anterior/siguiente accesibles; lista real clicable y actual resaltada por índice/ocurrencia.

## Verificación

| Comando | Resultado |
| --- | --- |
| `corepack pnpm check` desde `windows/` | Aprobó: 0 errores, 0 avisos. |
| `corepack pnpm build` desde `windows/` | Aprobó; adapter static terminó. |
| `cargo test --manifest-path windows/src-tauri/Cargo.toml queue::tests` | Aprobó 3 pruebas: ocurrencias duplicadas/inicio intermedio/orden, anterior >3 s y <=3 s incluyendo primera pista, EOF sin wrap y selección inválida. |
| `cargo check --manifest-path windows/src-tauri/Cargo.toml` | Aprobó MSVC x64; warnings preexistentes de `sideb-core` y linker Tauri. |
| `cargo build --manifest-path windows/src-tauri/Cargo.toml` | Aprobó MSVC x64. Binario generado en `S:\sideb-target\windows\debug\sideb-windows.exe`. |
| Prueba manual audible y visual en Windows | Pendiente. Antes del corte se abrió la app nueva y se vio el estado inicial; no se alcanzó a probar una cola de álbum. Al retomar, `node_repl` falló con `failed to write kernel assets`, incluso tras reset. |

Codex volvió a abrir el ejecutable final el 2026-09-30; proceso iniciado correctamente. No se hizo logout ni se borró la sesión del usuario.

Entorno usado para el intento con VS: cargar `VsDevCmd.bat -arch=amd64 -host_arch=amd64` según `windows/README.md` y `SIDEB_MPV_DIR=S:\sideb-deps\mpv-gb4b5d69a4-x64-gpl`.

## Límites para revisión

- No se validó reproducción audible en Windows ni el fullscreen abierto con una cola real. La automatización de UI está bloqueada por el fallo de node_repl registrado arriba.
- Se incorporó `queue` al `PlaybackStateDto` como contrato sólo Windows; no se modificó `sideb-core` ni UniFFI/Apple. M7 puede migrar `queue.rs` a un módulo puro compartido, preservando los DTO/eventos específicos de shell y regenerando/verificando UniFFI en macOS si el contrato se comparte.
- No se verificó la escucha de audio, EOF real con varias pistas, transiciones rápidas con clics/EOF simultáneos, ni vista fullscreen contra una cola de álbum en la app abierta.
- W14+ no está implementado; no se agregaron radio, shuffle, repeat, edición, persistencia ni cambios al Plan-015.
