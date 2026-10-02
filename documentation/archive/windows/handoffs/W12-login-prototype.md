> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W12 — prototipo de acceso Windows

Fecha: 2026-09-30. Estado: acceso y restauración tras reinicio confirmados por el usuario; logout aún no probado con cuenta real.

## Alcance entregado

- `SideBCore::new_windows` no restaura ni persiste cookies en SQLite. Limpia la cookie heredada, activa `secure_delete`, trunca el WAL y compacta la base. `SideBCore::new` y `set_cookie` mantienen el contrato Mac. API Rust de sesión en memoria y notificación de rotaciones.
- `windows/src-tauri/src/session.rs`: ventana WebView2 visible hacia `ServiceLogin`, retorno a YouTube Music, lectura de cookies YouTube dentro de Rust, validación con `account_menu`, estado de cuenta seguro para UI, restauración al inicio y persistencia de cookies rotadas.
- `windows/src-tauri/src/session_store.rs`: cifrado de usuario Windows con DPAPI en `youtube-session.dpapi`; la cookie no cruza comandos/eventos Tauri ni se guarda en SQLite. Logout borra archivo protegido, memoria, cookies Google/YouTube del perfil WebView2 y estado de reproducción.
- Sidebar con `Entrar`/`Salir`, estado de carga, cuenta y errores. Biblioteca permanece deshabilitada hasta su paquete.
- `build.rs` omite la copia de `libmpv-2.dll` si el destino existente tiene los mismos bytes, para permitir compilar con la app de desarrollo abierta.

## Verificación

- `corepack pnpm check`: 0 errores, 0 advertencias.
- `corepack pnpm build`: aprobado.
- `cargo check --manifest-path windows/src-tauri/Cargo.toml` con Build Tools 2022 x64 y `SIDEB_MPV_DIR`: aprobado.
- `cargo build --manifest-path windows/src-tauri/Cargo.toml` con el mismo entorno: aprobado; binario lanzado en Windows.
- Test dirigido del core: constructor Windows limpia/no restaura/no persiste cookie ficticia; constructor Mac conserva el contrato; limpieza de DB/WAL no deja el marcador ficticio y conserva metadatos. Aprobados por el subagente Luna.
- `cargo test --manifest-path windows/src-tauri/Cargo.toml --lib session_store::tests::dpapi_roundtrip_and_delete`: aprobado, incluso segunda escritura para cookie rotada.
- `cargo test --manifest-path windows/src-tauri/Cargo.toml --lib session::tests::exports_youtube_cookies_only`: aprobado; sólo se exportan cookies de dominios YouTube y se exige `SAPISID`.
- Inspección visual de la ventana Windows: Inicio y sidebar invitado cargan; `Entrar` abre la ventana titulada `Iniciar sesión en YouTube Music`. No se interactuó con el formulario de Google.

## Prueba pendiente

El usuario confirmó que el acceso funcionó tras la corrección de la ventana en blanco. Se comprobó que el archivo DPAPI protegido existe (2582 bytes) y que SQLite sigue con 0 filas de cookie en `settings` y 0 cuentas con cookie en `accounts`. Se reinició la app y el usuario confirmó que la cuenta siguió iniciada sin volver a entrar. Falta probar `Salir`/reinicio invitado; se dejó la sesión activa. La Biblioteca sigue pendiente de W12d.

## Corrección de ventana en blanco

La primera compilación abría una ventana WebView2 en `about:blank` y bloqueaba el cierre. La causa fue crearla desde `login_webview` como comando Tauri sincrónico; [Tauri documenta el deadlock en Windows](https://docs.rs/tauri/2.12.0/tauri/webview/struct.WebviewWindowBuilder.html). Se convirtió el comando en asincrónico, como el flujo de referencia de LiMusic, y se añadió **Cancelar** en el perfil. Después del cambio, `pnpm check/build` y `cargo check/build` aprobaron; la ventana navegó a Google en esta PC, el proceso continuó respondiendo y la ventana pudo cerrarse. Falta la prueba de completar sesión.

## Límites

La sesión web de YouTube Music no es una API oficial de Google y puede cambiar o ser rechazada. La limpieza de SQLite reduce remanentes en la base y WAL; no borra copias externas, snapshots o bloques físicos retenidos por SSD. El perfil WebView2 conserva cookies mientras la sesión está activa; logout intenta borrarlas. El prototipo soporta una cuenta activa, sin cambio de cuentas. No se incluyen secretos ni capturas de autenticación en este informe.
