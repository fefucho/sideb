> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W12a — viabilidad de autenticación para Windows

**Fecha:** 2026-09-30  
**Decisión:** **requiere decisión de producto**. El camino OAuth nativo de Google es viable para APIs oficiales de Google, pero no entrega la credencial que requiere la autenticación actual de InnerTube. Un WebView controlado que extraiga cookies es técnicamente compatible con el core, pero no es el flujo OAuth nativo documentado; si solicita OAuth dentro del WebView, Google lo prohíbe. Antes de UI o captura de credenciales, producto debe elegir entre mantener Windows como invitado, aceptar explícitamente una integración de sesión web no oficial y sus riesgos, o rediseñar el alcance autenticado alrededor de APIs oficiales compatibles.

## Hallazgos

### Credencial que usa el core

- El transporte de `innertube` representa la sesión con `Session.cookie: Option<String>` (`core/crates/innertube/src/transport.rs:41-49`). Al enviar una petición autenticada, adjunta el encabezado `Cookie`; si encuentra `SAPISID` o `__Secure-3PAPISID`, genera `Authorization: SAPISIDHASH ...` (`transport.rs:393-423, 510-516`). Es un mecanismo de sesión web de YouTube, no un bearer OAuth.
- `player` se envía con `set_login = true` (`core/crates/innertube/src/endpoints.rs:49-60`); `account_menu` usa `context_for` y también requiere cookie (`endpoints.rs:215-225`). Las funciones `library_playlists`, `library_albums`, `library_songs` y `library_artists` están explícitamente comentadas como dependientes de login (`endpoints.rs:386-426`); las mutaciones de biblioteca también están marcadas como autenticadas por SAPISIDHASH (`endpoints.rs:577`). Las búsquedas pueden enviarse sin login; al registrar historial sí adjuntan la sesión (`endpoints.rs:65-96`).
- No encontré un parser o autenticador OAuth en `innertube` ni en `sideb-core`; el core entrega la cookie como credencial de transporte. No hay conversión documentada de un OAuth access token a Cookie/SAPISIDHASH.

### Mac actual y contrato compartido

- `LoginWebView.swift` carga `accounts.google.com/ServiceLogin` para YouTube Music, espera cookies de YouTube que incluyan SAPISID/alias y una cookie de sesión, arma un encabezado `Cookie` y se lo entrega a `LoginSheet` (`apple/Sources/SideB/Views/Login/LoginWebView.swift:11, 65-88`).
- `LoginSheet` escribe esa cadena en `CookieStorage` y llama `rustCore.setCookie` (`apple/Sources/SideB/Views/Login/LoginSheet.swift:30-38`). `CookieStorage` usa Keychain en producción, aunque en debug puede usar archivo (`apple/Sources/SideB/Services/Storage/CookieStorage.swift:11-25, 54-64`). `AccountViewModel` la repone en el core al restaurar sesión y la elimina al cerrar sesión (`apple/Sources/SideB/ViewModels/AccountViewModel.swift:17-26, 51-56`).
- La copia de Keychain no evita que hoy haya una segunda copia en texto claro: `SideBCore::new` carga `settings.session_cookie` desde SQLite (`core/crates/sideb-core/src/lib.rs:354-388`) y `SideBCore::set_cookie` la escribe o elimina en SQLite (`lib.rs:408-415`). `db.rs` también define `accounts.session_cookie TEXT NOT NULL` (`core/crates/sideb-core/src/db.rs:158-165`). Por tanto, el requisito de no dejar secreto en la base Windows exige cambiar la ruta del core, y el mismo hallazgo aplica a Mac.
- `innertube` mantiene cookie mutable compartida; al recibir `Set-Cookie`, `absorb_cookies` rota el valor de la sesión actual y dispara `cookie_changed` (`core/crates/innertube/src/transport.rs:179-209`). La señal existe, pero no encontré consumidor en `sideb-core`. Una futura persistencia externa debe cubrir rotación además de login inicial.

### Estado Windows vigente (diferencia con los planes)

- El plan marca W12a como evaluación y M6 como futuro. El checkout confirma que Tauri solo inicializa `SideBCore` (`windows/src-tauri/src/lib.rs:327-345, 924-941`) y el `generate_handler!` registra diagnóstico, búsqueda, Home y reproducción, sin comandos de auth (`lib.rs:1092-1108`). La UI visible sigue en modo invitado según PLAN-014.
- El constructor real de `SideBCore` restaura la cookie legada automáticamente, así que Windows ya puede heredar una sesión guardada previamente en SQLite aunque la shell no exponga login. Antes de ofrecer almacenamiento seguro, Windows necesita una opción de construcción que deshabilite restauración/persistencia legacy y una comprobación de migración/eliminación de filas antiguas.
- El checkout contiene una tabla `accounts`, pero eso no hace seguro el contrato: incluye cookies en `TEXT`, mientras que el constructor observado restaura la clave legacy `settings.session_cookie`. No asumir que la tabla equivale a vault de secretos.

## Flujos oficiales y compatibilidad

1. **OAuth de app instalada con navegador del sistema:** Google documenta el tipo de cliente Desktop, PKCE y redirect loopback para macOS/Linux/Windows desktop; la respuesta es un código OAuth que se canjea por access/refresh tokens para scopes de APIs Google. Fuente: [OAuth 2.0 for iOS & Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app).
2. **WebView controlado por la app:** la política vigente de Google (actualizada el 2026-08-05) dice que no se dirija una solicitud de autorización OAuth a un user-agent embebido controlado por el desarrollador; incluye librerías que permiten ejecutar scripts, modificar rutas o acceder a cookies de sesión. La documentación de apps instaladas dirige al usuario al navegador del sistema y describe `disallowed_useragent` para autorización en user-agents embebidos. Fuentes: [OAuth 2.0 Policies](https://developers.google.com/identity/protocols/oauth2/policies), [OAuth 2.0 for iOS & Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app).
3. **Resultado para Side B:** el navegador externo es el flujo OAuth apropiado, pero entrega tokens OAuth y un código de autorización; no entrega la Cookie de YouTube Music que `SideBCore` espera. Los scopes y tokens autorizan llamadas a APIs específicas, según [Using OAuth 2.0 to Access Google APIs](https://developers.google.com/identity/protocols/oauth2); no hay evidencia oficial de que sirvan como autenticación para los endpoints InnerTube del core. Por eso no se debe conectar el token directamente a `Session.cookie` ni considerar OAuth una sustitución.
4. **Secreto local Windows:** Microsoft documenta Credential Manager como opción preferida para credenciales de apps Win32 y DPAPI (`CryptProtectData`) para secretos persistidos ligados al usuario. Fuentes: [Handling Passwords](https://learn.microsoft.com/en-us/windows/win32/secbp/handling-passwords), [CryptProtectData](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata). Cualquiera resuelve cifrado local; ninguno resuelve la incompatibilidad de credencial OAuth/InnerTube. Preferir Credential Manager para la cookie si encaja con la forma de acceso Rust; DPAPI con alcance de usuario es alternativa para un blob opaco local. No almacenar en una fila SQLite con cifrado casero.

**Alcance de la política:** la regla de user-agent embebido citada es una regla de OAuth. El login Mac observado abre `ServiceLogin` y extrae cookies, no el endpoint OAuth `.../o/oauth2/v2/auth`; estas fuentes no bastan para afirmar que ese código exacto viola por sí mismo la política OAuth. Sí demuestran que migrar a OAuth dentro de WebView2 no es una alternativa permitida, y que el flujo oficial de OAuth externo no proporciona la credencial actual. La extracción de cookie web sigue siendo un contrato no oficial que producto debe aceptar o descartar deliberadamente.

## Propuesta mínima si producto elige continuar con sesión InnerTube

- Mantener la interfaz con `SessionCredential` opaco dentro de Rust. Separar credencial de estado SQLite y añadir una ruta de construcción Windows que no lea ni escriba `session_cookie` legacy. Mantener temporalmente el contrato Apple existente para compatibilidad; planificar luego la migración Mac a almacenamiento externo, porque hoy core duplica allí la cookie.
- Añadir al core operaciones explícitas de instalación/eliminación en memoria y notificación de credencial rotada. El adaptador Windows carga/guarda/borra el secreto en Credential Manager o DPAPI de usuario; el secreto nunca pasa por `invoke`, DTO, evento de UI, log o captura. El adaptador Apple puede migrar en otra etapa a Keychain.
- En la transición, al iniciar Windows detectar la clave legacy sin copiarla a una API de sesión y borrarla de forma transaccional tras definir la migración. No restaurar cuenta por defecto. Login/logout debe incrementar una generación de sesión, invalidar operaciones/cachés antiguas y evitar que un `Set-Cookie` de una petición vieja contamine la cuenta activa.
- Mantener invitado funcional mientras no exista una decisión afirmativa sobre el método no oficial. Si producto requiere únicamente métodos oficiales, cerrar el alcance de inicio de sesión InnerTube como bloqueado y estudiar por separado qué funciones soportan APIs Google documentadas.

## Riesgos y puertas siguientes

- La sesión web puede expirar o rotar; logout y expiración deben borrar la vault y la memoria. `absorb_cookies` actual rota cookie en memoria; no hay persistencia externa conectada.
- El setter actual persiste cookie en SQLite y el constructor la rehidrata. Añadir una vault sin corregir ambas rutas no cumple el objetivo.
- No hay aislamiento por generación en el contrato `SideBCore::set_cookie`; requests en vuelo pueden finalizar tras un cambio de cuenta. El transporte comparte estado mutable para aplicar rotaciones.
- Un flujo OAuth oficial podría seguir siendo útil para APIs públicas/autorizadas que sí documenten el scope requerido, pero no habilita por sí solo `account_menu`, biblioteca, acciones ni reproducción InnerTube.
- No se inició sesión, no se accedió a UI de cuenta y no se manejaron credenciales. Recomendación: resolver W12a como **requiere decisión de producto**; no abrir W12b/W12c hasta fijar si Side B acepta sesión web no oficial o limita Windows a invitado/API oficial.
