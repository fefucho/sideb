> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# PLAN-014 — Acceso y sesión de Side B Windows

Estado: W12b/W12c con acceso y restauración confirmados en esta PC; falta prueba de logout con cuenta real. W12d Biblioteca pendiente. Fecha: 2026-09-30.

## Objetivo

Permitir iniciar y cerrar sesión en Windows, restaurar una sesión válida después de reiniciar la app y, posteriormente, mostrar Biblioteca y perfil de la cuenta correcta. La sesión nunca debe circular por Svelte, eventos Tauri, logs o capturas, ni quedar en texto claro en la base de datos de Windows.

## Punto de partida comprobado

- Windows usa una instancia de `SideBCore` en `AppState`, pero no expone comandos de autenticación. El sidebar sólo muestra modo invitado.
- `SideBCore::new` restaura `session_cookie` desde SQLite y `SideBCore::set_cookie` la persiste allí (`core/crates/sideb-core/src/lib.rs`). Este contrato no sirve por sí solo para prometer almacenamiento seguro en Windows.
- La app Mac obtiene un encabezado Cookie desde `WKWebView` (`apple/Sources/SideB/Views/Login/LoginWebView.swift`). No se trasladará ese mecanismo a WebView2 por simple copia.
- El plan Windows original propone una ventana WebView2 aislada. La política de Google prohíbe enviar solicitudes de **OAuth** a agentes de usuario embebidos controlados por la app; esto no demuestra por sí solo que el `ServiceLogin` actual de Mac incumpla esa política. Hay que distinguir ambos flujos y su compatibilidad con InnerTube: https://developers.google.com/identity/protocols/oauth2/policies y https://developers.google.com/identity/protocols/oauth2/native-app.

## W12a — decisión de viabilidad (completado por Codex GPT-6 Luna)

Resultado: [W12a-auth-feasibility.md](../handoffs/W12a-auth-feasibility.md). InnerTube requiere cookies de sesión y `SAPISIDHASH`; el flujo OAuth oficial de escritorio entrega tokens para APIs documentadas, sin una conversión conocida a esa credencial. El usuario eligió continuar con el mecanismo de sesión web tipo Mac después de revisar LiMusic como referencia. Es una integración no oficial; su funcionamiento final depende de la prueba con una cuenta.

### Referencia local: LiMusic

El checkout `C:\Users\Stefa\Documentos\CODIGOOOO PADREE\limusic-master` confirma una implementación de la ruta de sesión web en Tauri para Windows. `src-tauri/src/session.rs` abre `ServiceLogin` en una ventana WebView2 visible, espera el retorno a `music.youtube.com`, lee las cookies de dominios YouTube en Rust y exige `SAPISID` antes de llamar a `AppState::sign_in`. En Windows conserva el user agent predeterminado de WebView2 porque cambiarlo no cambia los *client hints* y, según el comentario del proyecto, Google puede rechazar esa combinación. `state.rs` valida la cookie con `account_menu`; `lib.rs` escucha rotaciones y rechazos de sesión y activa persistencia/renovación. `docs/SIGN-IN-SESSIONS.md` describe el perfil persistente de WebView2 y las cuentas múltiples. Esto demuestra que hay un diseño concreto para prototipar, no que Google garantice ese flujo ni que haya sido probado en esta PC con Side B.

**Diferencia obligatoria:** LiMusic persiste la cookie completa en `accounts.session_cookie` y en `settings.session_cookie` dentro de SQLite (`src-tauri/src/db.rs`, `docs/SIGN-IN-SESSIONS.md`). Side B no debe copiar esa persistencia: W12b separa la credencial y la guarda en el almacén seguro de Windows. El perfil persistente de WebView2 también conserva cookies; W12c debe definir y comprobar qué se borra al cerrar sesión. Usar LiMusic como referencia de secuencia y casos de fallo, sin trasplantar sus archivos o su estado de cuenta.

Trabajo de lectura e investigación técnica, sin iniciar sesión ni pedir cookies al usuario:

1. Trazar qué credencial requiere `innertube` para cuenta, biblioteca y reproducción; distinguir entre el encabezado Cookie actual y un posible token OAuth. Identificar la API exacta que Windows tendría que alimentar.
2. Contrastar los flujos de acceso posibles en Windows con documentación oficial vigente de Google y Microsoft. Evaluar el navegador externo con retorno a la app y verificar si entrega una credencial que el core actual puede usar. No asumir que un token OAuth sustituye automáticamente la cookie de InnerTube.
3. Auditar persistencia y ciclo de vida: lectura/escritura de `session_cookie`, logout, cuentas múltiples, respuestas tardías y memoria. Proponer el cambio mínimo de contrato que preserve Mac y evite que Windows escriba el secreto en SQLite.
4. Entregar `documentation/handoffs/W12a-auth-feasibility.md` con una recomendación **viable / bloqueada / requiere decisión de producto**, evidencia por archivo y fuente oficial, prototipo propuesto y riesgos. No guardar secretos ni ejecutar login real.

**Puerta de salida:** no construir una pantalla de acceso ni capturar credenciales hasta elegir un método compatible con el core y aceptar sus límites. No simular sesión.

## W12b — almacenamiento y contrato de sesión (sólo si W12a es viable)

- Elegir un almacén de secretos soportado por Windows y ligado al usuario del sistema. Separar `SessionCredential` de los datos ordinarios de SQLite; nunca exponerlo por `invoke`, DTO, evento ni log.
- Añadir al core o al adaptador Windows una forma explícita de inyectar/quitar la sesión en memoria **sin** persistir la cookie en SQLite. Mantener el comportamiento Mac hasta migrarlo de forma deliberada. Verificar que el constructor Windows no restaure una cookie legada de SQLite accidentalmente.
- Cargar la credencial segura en Rust al arrancar, validar estado contra el proveedor, borrar datos de sesión inválidos y dejar un estado invitado recuperable.
- Definir una generación de sesión para descartar respuestas de Inicio, Biblioteca, búsqueda y playback iniciadas antes de login/logout/cambio de cuenta. Limpiar cachés y estado visible por identidad.

## W12c — UI y flujos de acceso (sólo si W12a y W12b pasan)

- Conectar el perfil del sidebar a acciones reales: Iniciar sesión, estado de carga/error, cuenta activa y Cerrar sesión.
- Ejecutar el flujo de acceso elegido fuera de la WebView principal. El frontend sólo recibe estado seguro (`guest`, `authorizing`, `ready`, `expired`, `error`) y metadatos públicos de perfil, nunca la credencial.
- En logout, borrar credencial del almacén seguro, sesión en memoria, cookies de Google/YouTube del perfil de login de WebView2 y datos de la cuenta visible; dejar la app usable como invitado. Si se decide conservar el perfil para reingreso rápido, documentar esa semántica explícitamente antes de implementarla.
- No habilitar botones de Biblioteca/Me Gusta hasta que sus datos reales y acciones estén conectados.

## W12d — primera pantalla con cuenta

- Implementar Biblioteca de forma separada: playlists/álbumes reales con estados de carga, vacío, sesión vencida y error. Luego Me Gusta e Historial, cada uno en su paquete.

## Verificación mínima

- `cargo test` dirigido para el contrato de sesión; `cargo check/build` Windows; `pnpm check/build` para UI.
- Prueba manual con una cuenta de prueba del usuario: login, reinicio, restauración, logout, reinicio en modo invitado, sesión vencida y cambio de cuenta si se habilita.
- Inspección de SQLite, logs, eventos y DTOs para comprobar ausencia de cookies/tokens; no incluir valores secretos en informes o capturas.
- Confirmar que Inicio, Buscar, reproducción y fullscreen siguen funcionando como invitado y tras logout.

## Fuera de W12

Cola, letras, recomendaciones, edición de playlists, migración del Keychain Mac, datos de cuenta de producción para pruebas automatizadas e instalador.
