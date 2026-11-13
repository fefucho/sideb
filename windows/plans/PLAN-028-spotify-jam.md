# PLAN-028: Spotify Jam como invitado en Windows

Paridad de [PLAN-023](../../plans/PLAN-023-spotify-jam.md) / [FIX-343](../../FIXES.md#fix-343) (Mac) → [PAR-062](../../PARIDAD.md). Estado: en implementación, sin validar en Windows real.

## Objetivo

Unirse a un Jam de Spotify como invitado desde Side B Windows y reproducir en YouTube Music el equivalente de cada pista, en sincronía, con la cola del Jam reflejada y los controles compartidos. Nunca se reproduce audio de Spotify ni se saltea Premium.

## Reparto

| Parte | Dónde | Qué hace |
|---|---|---|
| Plugin | `extensions/spotify-jam/` (el mismo de Mac, compilado `x86_64-pc-windows-msvc`) | Protocolo JSON por stdin/stdout v2 (`extensions/README.md`) |
| Runtime | `windows/src-tauri/src/jam/`, `commands/jam.rs` | Proceso del plugin, token de Spotify (sesión WebView2 compartida con Canvas, sin depender de que Canvas esté instalado), velocidad y reloj de libmpv, reemplazo de «lo que sigue» en la cola nativa |
| Lógica | `windows/src/lib/jam/` | Emparejado con YouTube Music, espejo de cola, motor de sincronía, RPC consciente del Jam, estado para la UI |
| UI | `windows/src/lib/components/jam/`, barra, fullscreen, lateral | Botón Conexiones, panel del Jam, marcadores, filas de cola, avisos, confirmación de salida, menú de depuración |

Contrato entre las tres partes: [`src/lib/jam/types.ts`](../src/lib/jam/types.ts) (eventos del plugin, comandos del runtime, `JamViewState`, `JamActions`) y [`src/lib/jam/index.ts`](../src/lib/jam/index.ts) (`createJam`).

## Decisiones

- **La cola nativa sigue siendo la autoridad.** El Jam la reemplaza con `play_song` (`queueItems` = actual + siguientes emparejadas, `queueSource.kind = "jam"`) al cambiar de pista y con `jam_replace_upcoming` cuando sólo cambia lo que sigue. `kind = "jam"` no dispara radio ni carga de fuente; las recomendaciones del frontend se apagan mientras dura.
- **Controles compartidos.** Con el Jam activo, `pause/resume/next/previous/seek`, quitar, mover y agregar a la cola salen hacia Spotify (envoltorio `jam.rpc`); el audio local sólo cambia cuando vuelve el `state`. Reproducir otra cosa pide confirmar la salida.
- **Sincronía igual que Mac** (`JamSyncEngine`): se ajusta sólo tras un cambio real (pista, pausa/play, salto > 0,6 s), con seeks y ráfagas de velocidad fija 0,95×/1,05× de libmpv, presupuesto de 6 s y luego se deja sonar.
- **Sin AirPlay en Windows:** el botón Conexiones sólo ofrece el Jam.
- **El token nunca cruza IPC:** lo obtiene y lo entrega el runtime.

## Verificación

- Desde Mac: `pnpm check`, `pnpm test`, `pnpm build`; chequeo de tipos del crate para `x86_64-pc-windows-msvc` con `cargo xwin check` (sin enlazar ni ejecutar tests).
- Pendiente en PC: `windows.ps1 -Action verify`, build, y prueba con un Jam real (entrar, sincronía audible, cola, controles, salida).
