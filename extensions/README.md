# Proveedores visuales opcionales de Side B

El host (Mac y Windows) no conoce Spotify. Ejecuta un paquete usando JSON/stdio v1. `spotify-canvas/` es un ejecutable Rust independiente, fuera de `core/`, del workspace protegido y de las dependencias de las apps. No hay un servidor local, librería dinámica ni acceso al audio/cola.

## Qué es y cómo viaja (desde 1.4.0)

**Spotify Canvas viaja instalado de fábrica en ambas apps, como plugin separable.** La app incluye el paquete firmado/verificado con ella, el host lo coloca la primera vez **sin activarlo** (activar exige iniciar sesión o pegar un token) y el usuario puede **desinstalarlo** desde Configuración → Proveedores visuales opcionales. Si Spotify da problemas, se desinstala y la app sigue exactamente igual: Apple Music es la fuente principal y nada más depende del plugin.

**Política vigente:** Apple Music primero. El proveedor se consulta únicamente como alternativa en el reproductor lateral vertical, después de un resultado vacío/error de Apple. Fullscreen y otros destinos no lo consultan. Está desactivado hasta que el usuario inicia sesión y lo activa; instalar o preinstalar no lo activa.

**Riesgo de términos de Spotify:** Canvas no tiene API pública. El ejecutable usa las interfaces no oficiales del Web Player (Pathfinder y un Bearer de sesión web) y Spotify puede cambiarlas o considerarlas contrarias a sus términos; la cuenta del usuario podría recibir limitaciones. Por eso es opcional, nace desactivado, descarga sólo bajo demanda para la canción en curso, no cachea resultados negativos ni hace prefetch, y es retirable sin efecto en el resto. Side B no tiene relación con Spotify. Los videos no quedan licenciados por este software.

### Qué hace «preinstalar»

| | macOS | Windows |
|---|---|---|
| Carga útil en la app | `Side B.app/Contents/Resources/VisualProviders/spotify-canvas/` | `provider/spotify-canvas/` junto a `sideb-windows.exe` (instalador NSIS: `$INSTDIR\provider\spotify-canvas\`; zip portable: misma ruta relativa) |
| Plataforma del paquete | `macos-arm64` (`sideb-spotify-canvas`) | `windows-x64` (`sideb-spotify-canvas.exe`) |
| Dónde queda la copia instalada | `Application Support/<app>/VisualProviders/Installed/` (host Swift, `VisualProviderHost`) | carpeta de datos de la app, equivalente (host Tauri, W6) |
| Primer arranque | `provisionBundledProvider()` copia manifiesto + ejecutable, 0700, sin cuarentena, **sin activar** y sin tocar credenciales | igual (contrato para el host Windows) |
| Actualización de la app | si el bundle trae una versión **mayor** del mismo `id`, se actualiza en sitio conservando login y activación; nunca baja de versión; un proveedor distinto instalado a mano no se toca | igual |
| Desinstalar | borra de verdad la copia instalada, su token y su caché, y **guarda la decisión** (`sideb.visualProvider.userRemoved.v1`, lista de ids): no se reinstala solo en arranques ni actualizaciones | igual (persistir la decisión en las preferencias del host) |
| Volver a tenerlo | Instalar proveedor (manual), eligiendo la carpeta de la app (`Contents/Resources/VisualProviders/spotify-canvas`) o un paquete descargado; instalar a mano revoca la decisión de borrado | igual con `provider\spotify-canvas` |

La carga útil dentro de la app es parte del bundle firmado y no se borra al desinstalar (una app firmada no se modifica); lo que se borra es la instalación del usuario, y la decisión queda registrada. Quitar la carga útil de los binarios distribuidos es quitar `extensions/spotify-canvas/` del código fuente (ver «Retirar»).

**Contrato de ubicación para el host Windows (`resolve_provider_dir()`, una sola función):** devolver, en este orden, el primer directorio que contenga `manifest.json`: (1) `Resource dir` de Tauri + `provider/spotify-canvas`; (2) `directorio de sideb-windows.exe` + `provider/spotify-canvas` (instalador y zip portable; si Tauri hubiera usado `resources\`, también `resources/provider/spotify-canvas`); (3) sólo en builds de depuración, `<CARGO_MANIFEST_DIR>/provider/spotify-canvas` (lo prepara `windows.ps1`). Cualquier otro lugar no se consulta. El paquete se valida igual que uno manual antes de copiarlo.

## Paquete v1

Una carpeta con `manifest.json` y un ejecutable cuyo nombre es el `executable` del manifiesto. Sólo se copian esos dos archivos al instalar; los demás (`LICENSE`, `THIRD_PARTY_NOTICES.md`, `SHA256SUMS`) son de auditoría: `shasum -a 256 -c SHA256SUMS` (o `Get-FileHash` en Windows) comprueba el paquete. Los nombres no admiten rutas, el protocolo se valida y se rechazan enlaces simbólicos/archivos excesivos (ejecutable ≤128 MiB, manifiesto ≤8 KiB).

**Manifiesto multiplataforma:** el protocolo (`protocolVersion:1`) es el mismo en todas las plataformas y los manifiestos sólo difieren en `platform` y `executable`. Fuentes versionadas (`spotify-canvas/package/`):

- `manifest.macos-arm64.json` → `"platform":"macos-arm64"`, `"executable":"sideb-spotify-canvas"`
- `manifest.windows-x64.json` → `"platform":"windows-x64"`, `"executable":"sideb-spotify-canvas.exe"`

`platform` es opcional y de compatibilidad hacia atrás (paquetes 0.1.x no lo traen): si está presente, el host rechaza un paquete de otra plataforma en lugar de fallar al ejecutarlo; un host debe **ignorar campos desconocidos**. `name`, `version` y `credentialLabel` son metadata. La versión del paquete (0.2.0) debe coincidir con `Cargo.toml` y la comprueba `Scripts/package-visual-provider.mjs`. Esta versión admite un proveedor instalado.

**Es un programa de confianza, no una sandbox:** tiene los permisos del usuario y recibe su canción/token. Un paquete manual debe ser código revisado. La separación no elimina restricciones de Spotify ni concede derechos sobre videos. La app no descarga proveedores de ninguna parte; sólo ejecuta el instalado y activado (el preinstalado procede de la propia app).

## Transporte

Un proceso por solicitud. El host escribe un objeto UTF-8 JSON en stdin y lo cierra; el programa escribe un objeto JSON en stdout y sale. No pasar secretos en argumentos, variables de entorno ni stderr. El host descarta stderr, limita la entrada a32KiB y la salida a16KiB, aplica22s de plazo y termina el proceso al cancelar. No puede devolver un resultado de otra solicitud.

**Windows:** `outputDirectory` llega como ruta nativa de Windows (por ejemplo `C:\Users\...\Sessions\<uuid>`, que en JSON viaja con las barras invertidas escapadas, o con prefijo `\\?\`); el programa no la reinterpreta (hay un test con ambas formas). El host debe lanzar el `.exe` sin ventana (`CREATE_NO_WINDOW`, 0x08000000), con stdin/stdout/stderr redirigidos (el ejecutable es de subsistema consola) y esperar EOF de stdin cerrado. El proveedor no escribe BOM ni fin de línea.

Solicitud (campos y nombres exactos; valores de ejemplo sin credenciales):

```json
{
  "protocolVersion": 1,
  "requestId": "request-uuid",
  "credential": "temporary-secret",
  "outputDirectory": "/private/host/session/request-uuid",
  "track": {
    "videoId": "ytm-id",
    "title": "Title",
    "artist": "Main artist",
    "album": "Album",
    "durationSeconds": 200,
    "explicit": true
  }
}
```

`album`, `durationSeconds` y `explicit` pueden faltar/null. El proveedor decide si la metadata permite una correspondencia fiable. La carpeta de salida es privada y la crea el host. No persistir el token ni incluirlo en la respuesta.

Respuesta positiva:

```json
{"protocolVersion":1,"requestId":"request-uuid","status":"ready","fileName":"visual.mp4"}
```

Otros estados: `absent`, `authRequired`, `rateLimited`, `unresolved`, `unsupported`, `unavailable`; no incluyen archivo. `ready` sólo puede referir `visual.mp4` en la carpeta asignada, nunca una URL o ruta arbitraria. Una respuesta corrupta/versionada o un código de salida no exitoso no equivale a ausencia.

## Archivo y ciclo de vida

El host valida archivo regular sin symlink, ≤24MiB, video único reproducible, H.264, alto720–1920px, relación9:16 aproximada, duración2.5–8.5s y0<fps≤60.1. El rango incluye Canvas 720×1280 que el Web Player sirve en vivo. El reproductor vuelve a validar antes de instalarlo. Siempre silenciado. JPG no se usa como video en esta versión.

Los archivos son temporales por solicitud, no una caché por álbum. Se retienen mientras AVPlayer tenga el asset y se borran después de desmontarlo. Al cancelar la preparación se termina el proceso antes de limpiar su directorio. Se limpian abandonados de más de24h al iniciar el host sólo si su PID propietario ya no existe; no se borran leases de otra instancia activa. Hasta dos solicitudes locales pueden coexistir durante cambios de superficie. El proveedor limita el video a24MiB y la respuesta de catálogo a2MiB. No hay caché persistente de resultados/negativos ni prefetch.

Cambiar configuración/token/paquete invalida la generación y desmonta consumidores antes de cancelar archivos. Una sesión rechazada bloquea nuevas consultas hasta reemplazar token o cambiar configuración. 429 pausa el proveedor60s. Reducir movimiento, visibilidad y política de energía se heredan del reproductor existente. La limpieza de carátulas existente libera también los leases activos; no elimina una instalación ni una credencial.

## Token y límites de Spotify

El token temporal se introduce en un SecureField y se guarda en un namespace separado de Keychain, sin fallback a archivo ni mezcla con la cookie YTM. El host (no el ejecutable) abre una ventana de login una sola vez y reutiliza esa sesión WebKit para obtener un Bearer nuevo en segundo plano cuando el proveedor responde `authRequired`, cuando el token tiene más de 50 min o al volver a la app; el token rechazado nunca se acepta de nuevo y, si todo falla, reintenta con pausas crecientes (FIX-300). El token manual sigue disponible. No darlo por válido sólo por poder guardarlo; el proveedor muestra `authRequired` si Spotify lo rechaza.

El ejecutable usa Pathfinder como referencia de Wolframe. Hace una búsqueda conservadora por título/artista/álbum/duración/explicit cuando se conoce. Si hay dos Spotify IDs candidatos, rechaza la ambigüedad. No normaliza eliminando `live`, remix, dígitos ni versiones. Busca Canvas sólo para una coincidencia única y descarga únicamente de los hosts CDN previstos, sin redirects ni credenciales en la descarga. No almacena URLs en DTOs o logs.

El hash de la búsqueda persistida cambia con el Web Player: el ejecutable usa el vigente y, ante `PersistedQueryNotFound`, descubre el hash actual desde el bundle público con un fallback acotado. La consulta, la descarga Canvas y el MP4 real se validaron con una cuenta (FIX-283); el render dentro de la app sigue pendiente de comprobar. [Investigación](../plans/research/SPOTIFY-CANVAS-EVALUATION-2026-11-01.md) y [plan de integración](../plans/PLAN-022-optional-visual-providers.md).

## Desarrollo, empaquetado y CI

```sh
cargo test --locked --manifest-path extensions/spotify-canvas/Cargo.toml
cargo test --locked --manifest-path extensions/spotify-canvas/Cargo.toml -- --ignored
cargo clippy --locked --manifest-path extensions/spotify-canvas/Cargo.toml --all-targets -- -D warnings
cargo fmt --manifest-path extensions/spotify-canvas/Cargo.toml -- --check
node --test Scripts/package-visual-provider.test.mjs
```

El segundo comando descarga el bundle público del Web Player, sin credenciales, y comprueba que los hashes vigentes siguen siendo descubribles; está ignorado en la suite normal para no depender de la red.

Para formar un paquete (también para instalarlo a mano):

```sh
cargo build --release --locked --target aarch64-apple-darwin --manifest-path extensions/spotify-canvas/Cargo.toml   # macOS
node Scripts/package-visual-provider.mjs --platform macos-arm64 --binary extensions/spotify-canvas/target/aarch64-apple-darwin/release/sideb-spotify-canvas --out <carpeta nueva>
# Windows x64 (en Windows con MSVC): --target x86_64-pc-windows-msvc, --platform windows-x64 y el .exe resultante
```

El script valida el manifiesto contra `Cargo.toml` y el formato del binario (Mach-O arm64 / PE x64), exige una carpeta de salida vacía y escribe `SHA256SUMS`. Los binarios y paquetes generados quedan fuera de Git (`.gitignore`); sólo se versionan los manifiestos de `package/`.

Integración en las builds (no se publica nada automáticamente al terminar un fix):

- **macOS:** `Scripts/build-macos.sh` compila el proveedor (`cargo build --release --locked --target aarch64-apple-darwin`), firma ad hoc una copia, lo empaqueta en `Contents/Resources/VisualProviders/spotify-canvas` y firma/verifica la app. `Scripts/build-version.mjs macos` falla si la fuente existe y el bundle no lo trae.
- **Windows:** `windows/scripts/windows.ps1` (`verify`, `build`, `package`, `dev`) compila el `.exe` (`x86_64-pc-windows-msvc`) y deja el paquete en `windows/src-tauri/provider/spotify-canvas/` (ignorado por Git), que `bundle.resources` de `tauri.conf.json` incluye en el instalador NSIS; `build-version.mjs windows` copia el mismo paquete a `builds/windows/build-NNNN/provider/spotify-canvas/` para el zip portable. `verify` también corre los tests del proveedor.
- **CI / release:** `macos.yml` y `windows.yml` corren fmt, clippy `-D warnings` y tests (Windows sobre MSVC) y el test del empaquetado; `release.yml` verifica el proveedor dentro del `.app` (arm64, firma, `SHA256SUMS`) y que instalador/zip contengan exactamente los archivos hasheados en `BUILD.json`. `Scripts/release-config.mjs` exige esos archivos entre los artefactos verificados de cada plataforma. Los checksums del paquete viajan en su `SHA256SUMS` y dentro de `artifactSHA256` de `BUILD.json`; los zips y el instalador siguen publicando su `*-SHA256.txt`.

## Spotify Jam (`spotify-jam`, v0.2.0)

Proceso de larga vida (no es un proveedor visual): une a Side B a un Jam de Spotify como invitado, refleja el estado y la cola compartidos y reenvía órdenes. No reproduce audio ni conoce YouTube Music. Usa interfaces **no oficiales** del Web Player (dealer WebSocket, `social-connect/v2`, Pathfinder) con el token del usuario; pueden cambiar sin aviso. Es un ejecutable independiente (`extensions/spotify-jam/`, su propio workspace de Cargo).

Transporte: una línea JSON por mensaje, UTF-8, por stdin (host → plugin) y stdout (plugin → host). EOF en stdin equivale a `leave`. El token nunca se imprime ni se registra y los errores de red no se formatean en la salida.

### stdin

- `{"type":"join","credential":"<bearer>","link":"<url|token>"}`: primer mensaje. `link` es un enlace `open.spotify.com/socialsession/<token>` o el token suelto.
- `{"type":"credential","credential":"<bearer>"}`: token renovado (también reanuda una espera de reconexión).
- `{"type":"leave"}`.
- `{"type":"command","action":...,"requestId":"opcional"}`:
  - `pause`, `resume`, `next`, `previous`, `seek` (`positionMs`), `add` (`uri` `spotify:track:...`; añade al final de la cola de usuario).
  - Edición de cola, todas con `"revision":"<queueRevision del último state>"`; si no coincide con la actual se responde `ok:false, detail:"stale"` y no se envía nada. Los índices son del `queue` emitido (0 = siguiente):
    - `{"action":"move","from":2,"to":0,"revision":"…"}`: `to` es el índice final tras mover.
    - `{"action":"insert","uri":"spotify:track:…","index":0,"revision":"…"}`: la pista queda en `index`; `index == queue.length` añade al final.
    - `{"action":"remove","index":1,"revision":"…"}`.
    - Índices fuera de rango, URI inválida o campos ausentes: `ok:false, detail:"invalid"`.
- `{"type":"resolve","requestId":"…","title":"…","artist":"…","album":null,"durationMs":197000}`: busca en el catálogo de Spotify la pista equivalente (no es un `command`).

### stdout

- `joined`: `protocolVersion` (2), `members`, `canControl`, `queueOnly`, `hostDevice`, `hostActive`.
- `state`: `track` (`uri,title,artists,album,durationMs,isrc,provider`), `positionMs`, `atLocalMs` (instante en reloj local en que `positionMs` era cierto; posición en vivo = `positionMs + (ahora − atLocalMs)` si suena), `paused`, `durationMs`, `queue` (todas las pistas siguientes, hasta 200, con la misma forma de pista), `queueRevision` (cadena, o `null` si el clúster no la trae), `previousCount`, `shuffle`, `clockOffsetMs`. Sólo se emite si cambia. Se omiten de `queue` las entradas que no son `spotify:track:`/`spotify:episode:` (delimitadores); el plugin recuerda la correspondencia con la lista cruda. Con más de 60 pistas sin metadatos en caché, se emite primero el estado con lo que hay y de nuevo cuando llega el resto.
- `members`, `session` (`reason`), `notice` (`code`, p. ej. `NO_HOST_ACTIVE_DEVICE`), `ended` (`reason`), `error` (`code`, `retryable`).
- `commandResult`: `action`, `ok`, `detail`, y `requestId` si el comando lo traía.
- `resolved`: `{"type":"resolved","requestId":"…","uri":"spotify:track:…"|null,"title":…,"artists":[…],"durationMs":…}`. `uri: null` (con `title:null, artists:[], durationMs:null`) significa que no hay coincidencia segura o que la búsqueda falló. La coincidencia es conservadora (título y artista normalizados, duración a ≤45 s; sin `durationMs` no hay coincidencia) y se ejecuta en una tarea aparte (máx. 4 a la vez, 18 s de plazo), sin bloquear el estado ni otras órdenes.

### Aplicar la edición de cola

`move`/`insert`/`remove` se envían como `set_queue` (`next_tracks`, `prev_tracks` crudos sin tocar y `queue_revision`) por `POST /social-connect/v2/sessions/<id>/commands/from/hobs_<device>`. Las pistas movidas o insertadas llevan `provider:"queue"` y `metadata.is_queued:"true"`; las entradas no emitidas (delimitadores) conservan su posición relativa a sus vecinas, y al añadir al final la pista queda justo tras la última pista emitida.

**HTTP 200 no significa aplicado.** El servicio responde 200 aunque no aplique la orden; la verdad es el siguiente `state` (si cambió `queueRevision`/`queue`) o un `notice`. El host debe tratar `commandResult.ok` sólo como «aceptado» y esperar el `state`.

### Verificado y no verificado

Medido en vivo (invitado con cuenta gratuita, anfitrión reproduciendo): `pause`, `resume`, `seek`, `next`, `previous` y `add` funcionan y el nuevo estado vuelve por el dealer en ~0,4 s. **No verificado contra el servicio real** (sólo pruebas unitarias con JSON sintético): `set_queue` (mover, insertar, quitar y que el servicio acepte `provider:"queue"` sin `uid` en pistas insertadas), el efecto de la revisión obsoleta, si un invitado sin permiso de control recibe otro error, el límite de 200 pistas y el emparejado de `resolve` (consulta Pathfinder `searchDesktop`, con redescubrimiento del hash si caduca) frente a catálogo real.

Desarrollo: `cargo test`, `cargo clippy --all-targets -- -D warnings` y `cargo build --release --locked` dentro de `extensions/spotify-jam/`. El código de búsqueda (`src/search.rs`) es una copia adaptada del de `spotify-canvas`; no hay dependencia entre crates.

## Retirar

**El usuario:** Configuración → Proveedores visuales opcionales → Desinstalar. Desactiva el proveedor, borra su ejecutable, token y caché, y no se reinstala solo.

**Del producto (desarrollo):** eliminar `extensions/spotify-canvas/` y su entrada de esta documentación, quitar las cinco entradas `provider/spotify-canvas/*` de `bundle.resources` en `windows/src-tauri/tauri.conf.json`, el bloque `RMDir /r "$INSTDIR\provider"` de `nsis_hooks.nsh` (opcional) y los archivos `provider/spotify-canvas/*` de `required` en `Scripts/release-config.mjs`. Sin `extensions/spotify-canvas/Cargo.toml`, `build-macos.sh`, `build-version.mjs` y `windows.ps1` omiten el empaquetado y avisan. Para retirar también la capacidad completa de proveedores: quitar `Services/VisualProviders/`, `VisualProviderSettings` y su inserción en HomeSettingsPanel, y reemplazar la llamada de `AnimatedArtworkView` por su closure `primary` existente; `AnimatedArtworkIdentity` conserva su comportamiento original sin salt. No hay cambios de core/UniFFI/audio que deshacer.
