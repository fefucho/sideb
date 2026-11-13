# PLAN-023 — Escuchar juntos: Spotify Jam como invitado

- Fecha: 2026-11-13 (America/Montevideo).
- Estado: implementado en Mac en la rama (FIX-343); protocolo medido con un Jam real; versión final (sincronía nueva, edición de cola, UI) sin validación manual. Windows pendiente (PAR-062).
- Rama / carpeta: `feature/listen-together`, worktree `sideb-listen-together/` (base `46e7fcf`). No se integra a `main` hasta que el usuario lo dé por listo.
- Objetivo: que Side B entre como invitado a un Jam de Spotify, copie su canción actual, posición y cola, y reproduzca el equivalente de cada canción desde YouTube Music. Side B nunca reproduce audio de Spotify.
- Orden de plataformas: Mac primero; Windows después con el mismo plugin y contrato.

## Qué se sabe y qué no

| Dato | Origen | Estado |
|---|---|---|
| Una cuenta free invitada por un Premium entra al Jam, ve la canción actual y puede mover la cola; el audio suena sólo en el anfitrión | Prueba del usuario en la app oficial, 2026-11-13 | Observado; no medido desde Side B |
| El servicio es `social-connect` en `spclient.wg.spotify.com`: unirse `POST /social-connect/v2/sessions/join/<token>` con cuerpo `{}`, salir `POST …/<session_id>/leave` | [Starless `docs/jam.md`](https://github.com/baironvillar/Starless/blob/main/docs/jam.md) (MIT), medido con cuenta Premium | Documentado por terceros |
| La cola es `spotify:list:jam-list:<session_id>`, se lee por `ListReadService/GetLists` en protobuf y es la cola del player del anfitrión | Ídem | Documentado por terceros |
| Comandos de invitado: `POST …/sessions/<id>/commands/from/<device_id>` con `endpoint: add_to_queue / play / skip_next` | Ídem | Aceptados por el servicio; no se comprobó que lleguen al anfitrión |
| Estado de reproducción (pista, posición, pausa, cola) en `GET /connect-state/v1/cluster` | Ídem | No se sabe si el anfitrión aparece en el cluster del invitado |
| Cambios en vivo por un pubsub (`SessionUpdate`) | Ídem, leído de strings del cliente | Sin implementar en ningún proyecto encontrado; Starless consulta cada 3 s |
| El Bearer del Web Player que ya usa Spotify Canvas sirve para `social-connect` | Sonda propia, 2026-11-13 | **Confirmado**: `join` 200 con Bearer web + `client-token` |
| Quitar o reordenar canciones de la cola del Jam por comando | — | **Sin medir** |

## Alcance y exclusiones

Incluye: plugin separado, host de sesión en cada shell, «modo sesión» de la cola, traducción Spotify → YouTube Music, sincronización de posición, botón y marcadores de UI, ES/EN.

Excluye en este plan:

- Ser anfitrión de un Jam o reproducir audio de Spotify.
- Cualquier forma de saltear una restricción de cuenta: si el servidor rechaza una operación, se muestra como no disponible.
- Salas propias Side B ↔ Side B con `core/crates/listen-protocol` (hoy sin consumidores). Quedan para un plan posterior; el botón y el modo sesión se diseñan para alojarlas.
- Cambios en `core/`. Si aparece una necesidad real de ambas plataformas, se evalúa aparte según `core/AGENTS.md`.

## Arquitectura

```
Spotify (social-connect, listas, estado)
        │  red, protobuf, tiempo real
┌───────▼────────────┐
│ extensions/        │  ejecutable Rust separado, fuera del core
│ spotify-jam        │  conoce Spotify; no conoce YouTube Music
└───────┬────────────┘
        │  JSON por stdio, proceso vivo: comandos ↓ eventos ↑
┌───────▼────────────┐
│ Host de sesión     │  Mac: Swift · Windows: Tauri
│ (genérico)         │  no conoce Spotify
└───────┬────────────┘
        │  metadata de canciones, posición, cola, participantes
┌───────▼────────────┐
│ Modo sesión        │  Mac: QueueManager / PlayerViewModel
│ + traductor a YTM  │  Windows: queue.rs / controller.ts
└────────────────────┘
```

- **Plugin `spotify-jam`.** Mismo modelo que `extensions/spotify-canvas`: paquete con manifiesto por plataforma, apagado por defecto, desinstalable, credencial en Keychain / almacén del host. Diferencia: Canvas responde una consulta y termina; el Jam necesita un **proceso de larga vida** que emite eventos. Eso es un tipo de protocolo nuevo (propuesta: `protocolVersion: 2`, `kind: "session"`), sin tocar el v1 de los proveedores visuales.
- **Eventos del plugin (borrador):** `joined {session, host, members, permissions}`, `state {track, position_ms, at_server_ms, paused}`, `queue {tracks[]}`, `members {…}`, `permissions {…}`, `ended {reason}`, `error {code, retryable}`.
- **Comandos del host (borrador):** `join {link}`, `leave`, `add {spotify_uri}`, y si se miden: `skip`, `remove`, `reorder`.
- **Cada canción viaja con metadata suficiente para traducirla:** URI, título, artistas, álbum, duración, explícito, y quién la agregó si el servicio lo informa.
- **El traductor a YouTube Music vive en el shell**, usando la búsqueda existente del core. El plugin no depende de InnerTube.

## Etapa 0 — Sonda (bloquea todo lo demás)

Binario de prueba dentro de `extensions/spotify-jam`, con un Jam real del amigo. Vuelca respuestas a archivos locales fuera de Git, con tokens y nombres recortados.

- [x] El Bearer del Web Player + `client-token` es aceptado por `join` (200). El Web Player no ofrece Jam en su interfaz, pero el servicio acepta su sesión. **No hace falta un segundo login.**
- [x] Link de invitación `open.spotify.com/socialsession/<token>`: el token del path alcanza. Falta la variante corta `spotify.link`.
- [x] Respuesta de `join` como invitado: `is_controlling: true`, `playbackControl: CONTROL`, `is_listening: false`, `queue_only_mode: false`, capacidades `{invite}`. Trae `host_device_info` y `hostActiveDeviceId`.
- [x] Estado del anfitrión: tras unirse, `connect-state` (registro `PUT /connect-state/v1/devices/hobs_<id>` con el connection id del canal) devuelve `player_state` con `track.uri`, `position_as_of_timestamp`, `timestamp`, `is_paused`, `duration`, `prev_tracks`, `next_tracks`, `options` (shuffle/repeat, `modes.jam: on`) y `server_timestamp_ms`. Contexto `spotify:list:jam-list:…`.
- [x] Tiempo real: `wss://dealer.spotify.com` entrega `social-connect/v2/session_update` (con `reason`, p. ej. `SESSION_MEMBER_PAUSE_CHANGED`) y `hm://connect-state/v1/cluster` con el estado completo en JSON. Pausar/reanudar llegó en ~0,1 s desde la marca del servidor. **No hace falta consultar cada 3 s.**
- [x] `jam-list` por `GetLists`: 200, 30 URIs. `next_tracks` del cluster: 25 (5 `context` + 20 `enhanced_recommendation`, las recomendaciones propias de Spotify con el anfitrión en shuffle inteligente).
- [x] Salir: `POST …/leave` 200; el cluster emite `DEVICES_DISAPPEARED`.
- [x] Las pistas del estado y la cola vienen sólo con URI. `GET /metadata/4/track/<gid hex>?market=from_token` devuelve nombre, artistas, álbum, duración, número de pista e **ISRC** con el mismo Bearer (5 pistas en paralelo: 0,35 s). El ISRC sirve como clave fuerte para la coincidencia con YouTube Music. Explícito no vino como campo propio en la muestra.
- [x] Comandos como invitado free, con el anfitrión reproduciendo: `pause`, `resume`, `seek_to`, `skip_next`, `skip_prev` y `add_to_queue` responden `SUCCESS` y el estado nuevo vuelve por el canal en ~0,4 s. La canción agregada aparece primera en la cola con `provider: queue`.
- [x] Con el anfitrión inactivo (teléfono en pausa hace rato) el servicio igual responde 200 `RECOVERED`, no aplica nada y avisa por el canal con `userMessage: NO_HOST_ACTIVE_DEVICE`. El resultado real de un comando es el estado que vuelve, no la respuesta HTTP.
- [x] El estado del Jam llega en el cluster del invitado como un dispositivo virtual activo `social-connect-<session_id>`; el teléfono del anfitrión no figura. Sólo ese dispositivo se trata como Jam.
- [x] Cambio de canción y seek: llegan como estado nuevo (pista y posición) por el mismo canal.
- [ ] Quitar y reordenar (`set_queue`): se envió con el anfitrión inactivo, sin efecto observable. Repetir con el anfitrión activo.
- [ ] Plan de la cuenta: `/v1/me` devolvió 429; que la cuenta invitada es free lo confirma el usuario.
- [ ] Fin del Jam por el anfitrión y expulsión.
- [ ] Duración del token y renovación sin cortar la sesión; link corto `spotify.link`.

Respuestas crudas de la sonda: carpeta temporal de la sesión, fuera de Git (contienen datos de cuenta). Los fixtures saneados se generan al empezar la Etapa 1.

Salida: tabla de resultados en este plan y fixtures saneados para tests. Con eso se confirma o se recorta el alcance de las etapas siguientes.

## Cuestiones a resolver antes de construir

### Cuenta y login

- El Jam aparece con el nombre y la foto de la cuenta de Spotify del usuario ante el resto de los participantes.
- **Decidido:** si están los dos plugins, comparten el mismo login de Spotify. La sonda confirmó que el mismo Bearer web sirve para ambos. Implica que el host deje de guardar una credencial única «visual-provider» y pase a una credencial por cuenta de Spotify, usable por varios plugins.
- Riesgo de términos: interfaces no oficiales; Spotify puede cambiarlas o limitar la cuenta. Mismo aviso que Canvas, visible antes de activar.

### Entrar y salir

- Entrada inicial: pegar el link de invitación. Abrir links `spotify.link` directamente en Side B exigiría registrar un esquema de URL y competiría con la app de Spotify; queda fuera de la primera versión.
- Las invitaciones «Request to Jam» llegan por los mensajes de Spotify; no se intenta leerlas.
- Al entrar con música sonando: guardar una **instantánea** de la cola y la posición actuales; al salir, restaurarla en pausa.
- Al cerrar la app dentro de un Jam: salir del Jam. Al abrir, no reingresar solo.
- Reconexión: red caída, Mac suspendida, token vencido. Reintentos acotados y luego estado «desconectado» con botón para reintentar.

### Traducir Spotify → YouTube Music

- Criterio: título y artista normalizados, álbum si existe, duración con tolerancia, preferir resultados de tipo canción sobre videos. `spotify-canvas` ya tiene normalización y matching en el sentido inverso; se reutiliza el criterio, no el binario.
- Versiones: explícita/censurada, remaster, en vivo, single vs. álbum. Respetar la preferencia existente de versiones de audio.
- Caché persistente por ID de Spotify, con la opción de **corregir a mano** una coincidencia mala («elegir otra versión»), que queda guardada.
- Sin coincidencia: la fila se muestra como no disponible; cuando le toca, Side B queda en silencio con aviso y retoma en la siguiente.
- Podcasts, archivos locales del anfitrión y contenido no musical: no disponibles.
- Pre-resolver coincidencia y stream de las próximas 2–3 canciones para no llegar tarde al cambio. Limitar búsquedas simultáneas.

### Sincronizar la reproducción

Objetivo del usuario: sincronía lo más exacta posible, no «aproximada».

- Fuente de verdad: `position_as_of_timestamp` + `timestamp` del estado, con `server_timestamp_ms` para estimar el desfase del reloj local (varias muestras, quedarse con la de menor latencia).
- Al cargar una canción, saltar a la posición viva sumando lo que tardó en resolverse el stream.
- Corrección en dos niveles: desfase chico → ajuste fino de velocidad (±2–3 %, inaudible) hasta converger; desfase grande → seek. Umbrales a fijar midiendo, no de antemano.
- **La misma grabación es condición de la sincronía exacta.** Si YouTube Music entrega otra versión (video con intro, remaster, edición), la posición coincide pero el audio no. Por eso: preferir resultados de tipo canción, comparar duración con la de Spotify y marcar «sincronía dudosa» cuando difieren.
- **Corregir a mano re-sincroniza al instante:** al elegir otra versión, se carga y salta a la posición viva sin esperar al cambio de canción. Se guarda además un ajuste fino por coincidencia (± ms) para versiones con intro distinta.
- Latencia de salida: AirPlay y Bluetooth agregan retardo propio. Ajuste global de desfase en Configuración; medir si el sistema informa la latencia de la ruta.
- Límite real: la sincronía se mide contra lo que el anfitrión *informa*, no contra lo que suena en su parlante. El resultado se valida a oído con el amigo.
- La duración en YouTube Music puede diferir: si termina antes, esperar; si el anfitrión cambia antes, cortar y seguir.
- Controles — **decidido: compartidos siempre que se pueda, locales como alternativa.**
  - Volumen y silencio: siempre locales.
  - Play/pausa, siguiente, anterior, seek y teclas multimedia: envían el comando al Jam y afectan a todos, como en la app oficial (la sonda mostró `playbackControl: CONTROL`; falta medir cada comando).
  - Side B no mueve su audio por su cuenta: espera el estado que vuelve por el canal en tiempo real, así nunca queda adelantado respecto del Jam.
  - Si un comando no está permitido o falla: pausa pasa a ser sólo local (al reanudar vuelve a la posición viva); seek/siguiente/anterior se deshabilitan con explicación.

### Modo sesión: qué se apaga

Mientras dura el Jam, la cola es un espejo de sólo lectura. Se desactivan:

- Radio, automix y extensión automática de la cola.
- Reserva de recomendaciones y su bloque en la cola (PLAN-018/019).
- Shuffle y repetir.
- «Reproducir siguiente», «Agregar a la cola» y arrastre locales (ver «Agregar canciones»).
- Persistencia de la cola del Jam como sesión restaurable.
- Reproducir otra cosa desde la biblioteca o la búsqueda: pide confirmación «Salir del Jam y reproducir».

Efectos externos — **decidido:**

- Historial de YouTube Music y scrobbling a Last.fm: sí cuentan.
- Discord: muestra que estás en un Jam.
- Controles y metadata del sistema (Now Playing): activos; sus botones siguen la regla de controles compartidos.

Nota: la cola del Jam puede incluir recomendaciones propias de Spotify (`enhanced_recommendation`). Son parte del Jam y se reproducen; lo que se apaga son las recomendaciones de Side B. Se pueden distinguir visualmente.

### Agregar canciones al Jam

- Requiere el camino inverso: canción de YouTube Music → URI de Spotify (búsqueda por Pathfinder, como hace Canvas) → comando `add_to_queue`.
- Depende de la Etapa 0. Si el comando no llega al anfitrión o el invitado no tiene permiso, la función se omite en la primera versión.
- Si se incluye: «Agregar al Jam» en menús contextuales, con estado pendiente hasta que la canción aparezca en la cola espejo, y error visible si no hay equivalente en Spotify.
- Respetar permisos del anfitrión (`queue_only_mode`, control de invitados); pueden cambiar durante la sesión.

## Interfaz

### Botón «Conexiones»

Reemplaza al botón de AirPlay en la barra inferior, el lateral y fullscreen. Abre un panel con:

1. **AirPlay** (sólo Mac). El selector nativo es una vista del sistema: hay que comprobar que se pueda alojar o disparar desde dentro del panel sin perder el menú de rutas (antecedente FIX-039).
2. **Spotify Jam**: instalar/activar el plugin, iniciar sesión, pegar link, estado, participantes, salir.
3. **Escuchar juntos de Side B**: reservado; no se muestra hasta que exista.

En Windows no hay AirPlay ni selector de salida: el botón aparece sólo si hay al menos una opción disponible.

### Marcador de Jam activo

| Lugar | Propuesta |
|---|---|
| Fullscreen | Píldora sobre la carátula: «En el Jam de *Nombre*» con avatares de participantes; clic abre el panel |
| Lateral | Misma píldora en la cabecera del panel, sobre la carátula |
| Barra inferior | El botón «Conexiones» pasa a estado activo (tinte + avatar del anfitrión como insignia) y la línea de contexto bajo el artista muestra «Jam de *Nombre*». Sin píldora adicional: no hay ancho |
| Cola | Cabecera «Jam de *Nombre*» en lugar de playlist/álbum/radio; sin bloque de recomendaciones; «agregada por» en cada fila si el servicio lo informa |

### Estados que la UI tiene que cubrir

Conectando · sincronizando · en vivo · anfitrión en pausa · canción no disponible · reconectando · Jam terminado por el anfitrión · expulsado · sin permiso para agregar · sesión de Spotify vencida · plugin no instalado.

Los controles deshabilitados explican por qué al pasar el mouse. Todo texto en ES/EN. Al terminar el Jam: aviso y restauración de la cola anterior.

## Etapas

- [x] **0. Sonda**: resultados arriba. Quedan sin medir `set_queue`, `resolve`, fin del Jam por el anfitrión, expulsión, link corto y duración del token.
- [x] **1. Plugin `spotify-jam`** v0.2.0: sesión, estado, cola completa, comandos, edición de cola, `resolve`, reconexión; 19 tests. Falta manifiesto/paquete instalable y fixtures saneados de respuestas reales.
- [ ] **2. Host de sesión Mac**: `JamProcess`, binario en `Resources/SessionProviders/`, login compartido. Falta instalación/desinstalación propia y sección en Configuración.
- [x] **3. Traductor a YouTube Music**: `JamMatcher`, corrección manual persistente y pre-resolución de la cola. Sin caché persistente de coincidencias automáticas ni uso del ISRC.
- [x] **4. Modo sesión Mac**: instantánea/restauración, cola espejo, recomendaciones y shuffle/repetir inertes, confirmación al reproducir otra cosa, `JamSyncEngine`.
- [x] **5. UI Mac**: «Conexiones», panel de Jam, marcadores, cola, avisos, ES/EN. Revisada sólo en capturas fuera de pantalla.
- [x] **6. Agregar / insertar / reordenar / quitar** desde Side B: implementado; reordenar, insertar y quitar sin medir contra Spotify.
- [ ] **7. Windows**: pendiente (PAR-062).
- [ ] **8. Cierre**: FIX-343 y PAR-062 registrados. Faltan validación manual con Jam real, aviso en README e integración a `main`.

### Validación manual pendiente (versión final)

1. Sincronía: que quede «fija» en pocos segundos y no vuelva a ajustar durante la canción; revisar `jam-sync.jsonl` si alguna canción no converge.
2. Reordenar, insertar («Reproducir siguiente») y quitar desde la cola de Side B, mirando el teléfono anfitrión.
3. Agregar una canción de YouTube Music al Jam.
4. Salida de audio / AirPlay desde el popover de Conexiones.
5. Salir del Jam: la cola anterior vuelve en pausa.
6. Marcador sobre la carátula con carátula animada y video inmersivo.

## Comprobaciones de cierre

- Tests del plugin con fixtures saneados: parseo de sesión, cola, eventos, errores, renovación.
- Tests del traductor: coincidencias exactas, versiones, ambigüedad, sin resultado.
- Tests del modo sesión: entrar/salir restaura la cola; ninguna vía de recomendación agrega canciones; reloj y umbral de corrección.
- QA manual con Jam real: entrar a mitad de canción, cambio de canción, pausa, seek, cola reordenada por el anfitrión, canción sin equivalente, fin del Jam, corte de red, suspensión del equipo.
- Medir a oído y con registro el desfase real frente al anfitrión; compilar no demuestra sincronía.

## Decisiones tomadas (2026-11-13)

1. Login compartido entre Canvas y Jam.
2. Lo escuchado en un Jam cuenta para el historial de YouTube Music y Last.fm.
3. Discord muestra que estás en un Jam.
4. Controles compartidos con el Jam cuando sea posible; locales como alternativa.
5. El botón se llama «Conexiones».
6. Si agregar canciones resulta frágil, la primera versión sale sin esa función.
7. Corregir una coincidencia a mano la reproduce y sincroniza en el momento.
