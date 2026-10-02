> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# Trabajo compartido Codex ↔ Antigravity para Side B Windows

**Estado:** W01–W06 verificados en Windows el 2026-09-29; M1/M2 cubiertos y M3 parcial. W06 reprodujo pistas públicas mediante libmpv con controles y EOF comprobados por telemetría; falta comprobar audibilidad física. Los hitos completos siguen en [`PLAN-013`](../plans/PLAN-013-side-b-windows-tauri.md).

## Roles y límites

| Participante | Responsabilidad |
| --- | --- |
| Codex (este chat) | Leer código y planes actuales; definir un paquete pequeño con archivos, contratos, pruebas y criterio de salida; revisar el resultado y preparar el siguiente paquete. |
| Antigravity (modelo Flash que el usuario seleccione) | Implementar el paquete asignado en el checkout Windows, ejecutar las comprobaciones disponibles y devolver cambios y evidencia. |
| Usuario | Abrir el encargo en Antigravity, aportar acceso a la PC y a las pruebas manuales, y decidir sobre producto, instalación o publicación cuando haga falta. |

El traspaso se hace por la ventana de Antigravity si Codex tiene permiso de Computer Use para esa app; si no, el usuario pega el **«Prompt listo para Antigravity»**. El archivo del paquete es el contrato compartido. No dar por recibido ni ejecutado un encargo hasta ver su respuesta y el estado del código.

## Bucle de entrega por la app

1. Codex guarda el paquete antes de enviarlo, lo identifica como `W01`, `W02`, etc. y registra qué archivos puede modificar Antigravity.
2. Codex envía a Antigravity **un solo paquete** por vez y espera la respuesta en esa misma conversación. Antigravity termina su respuesta con una línea propia `ENTREGA LISTA: Wxx` o `BLOQUEADO: Wxx`. La frase en el prompt de Codex no cuenta como respuesta ni como finalización.
3. Antes de esa línea, Antigravity escribe estado, archivos tocados, comandos con resultados, contratos cambiados y verificaciones pendientes. También guarda ese informe en `documentation/handoffs/Wxx-result.md` si la tarea llegó a modificar código. El marcador sólo avisa que terminó; no demuestra que el código funcione.
4. Codex lee la respuesta y el informe, revisa archivos y ejecuta las pruebas disponibles. Si falla un criterio, devuelve una corrección del **mismo** paquete. Sólo tras aceptarlo redacta y envía `Wxx+1`.

Este bucle requiere que ambas apps y la PC permanezcan disponibles, permiso efectivo para controlar la ventana de Antigravity y una tarea persistente de Codex para retomar el trabajo después de cada turno. Cualquier bloqueo de acceso, autenticación, herramienta o prueba detiene el ciclo y se informa; no se interpreta el silencio como aprobación.

## Ciclo de un paquete

1. **Preparar:** Codex compara el hito de `PLAN-013` con el código vigente, acota una salida comprobable y nombra archivos permitidos, dependencias y riesgos. El orden inicial es compatibilidad del core → ventana Tauri → primer comando real → audio real → UI amplia.
2. **Implementar:** Antigravity lee `.agents/AGENTS.md`, las reglas aplicables, `PLAN-013` y el paquete. Inspecciona las APIs antes de cambiarlas. Si encuentra una contradicción o un bloqueo, informa la evidencia y el cambio mínimo que propone; no expande silenciosamente el trabajo a otro hito.
3. **Devolver:** Antigravity informa archivos modificados, contratos alterados, comandos y resultado de pruebas, verificación manual pendiente, limitaciones del entorno y próximos riesgos. Adjunta diff/commit si existe Git. Nunca marca una casilla completa por código sin ejecutar o una prueba no realizada.
4. **Revisar:** Codex comprueba diff, tipos/contratos, alcance, regresiones y evidencia. Pide correcciones concretas o cierra el paquete y redacta el siguiente. `PLAN-013` se actualiza sólo cuando se cumple la salida del hito. `PROJECT_STATE.md` cambia al existir funcionalidad Windows; `FIXES_LOG.md` queda para hitos estructurales y cambios de contrato.

**Checkout:** trabajar sobre un único paquete activo por área de código. Si hay Git, usar una rama por paquete y conservar cambios ajenos; este checkout local no incluye `.git`, así que no prometer commits o PR desde él. Una copia Git normal es necesaria para el flujo de ramas y revisión por diff. Si Codex y Antigravity comparten la misma carpeta, avisar antes de editar los mismos archivos.

**Evidencia mínima de entrega:** estado `hecho / parcial / bloqueado`; lista de rutas; resultado exacto de cada comando (`aprobó`, `falló` o `no ejecutado` con motivo); capturas o descripción de la prueba manual sin datos de cuenta; pendientes explícitos. Las métricas de rendimiento requieren build Release, hardware, escenario y método reproducible. No subir cookies, tokens, URLs firmadas ni bases de datos personales.

## Paquete W01 — compatibilidad del core en Windows (M0/M1)

**Propósito:** saber si el core compartido compila y pasa sus pruebas en la PC Windows antes de crear UI. `core/Cargo.toml` incluye `innertube` y `sideb-core`; `core/crates/player` está fuera del workspace y queda fuera de W01. El plan general señala `rustypipe-botguard`/V8 y SQLite como riesgos a comprobar, no como fallas ya confirmadas.

**Entrada:** checkout del repo en Windows x64, toolchain Rust MSVC. Registrar versión de Windows, CPU, RAM, DPI, `rustc -Vv` y `cargo -V`. Si faltan herramientas, informar qué falta y dónde se detuvo la ejecución; no simular un resultado. La línea base de Limusic Release de M0 se puede registrar en paralelo si está disponible, con el mismo hardware y un método escrito; no condiciona los tests de Rust.

**Trabajo autorizado:** desde `core/`, ejecutar `cargo test -p innertube` y `cargo test -p sideb-core`. Si fallan por código o configuración de este repo, aislar la causa y hacer la corrección mínima en `core/` o su documentación de build. Volver a ejecutar el test afectado y luego ambos comandos. No agregar Tauri, libmpv, UI ni cambios a Swift en este paquete. Si una corrección cambia un contrato UniFFI, detenerse y describir el cambio para planificar la validación macOS correspondiente.

**Salida aceptable:** (a) ambos tests pasan y se adjuntan versiones/comandos/resultados; o (b) un bloqueo externo o de toolchain queda reproducido con error, causa probable y siguiente acción concreta. El caso (b) mantiene W01 abierto; no habilita W02. No atribuir a Windows un fallo de red, credenciales o test en vivo sin aislarlo.

**Revisión Codex:** comparar los cambios de `core/` con el contrato Apple, verificar que no se incorporó código de referencia sin procedencia/licencia, leer la salida de los dos tests y decidir si el gate de compatibilidad del core está cumplido. M1 requiere además la ventana Tauri de W02. La validación de Mac se programa si cambió código compartido; requiere host macOS para el build Apple.

### Prompt listo para Antigravity — W01

> Trabajá sólo el paquete **W01** de `.agents/WORKFLOW_WINDOWS.md` para Side B Windows. Usá el modelo Flash configurado para esta sesión. Leé `.agents/AGENTS.md`, `.agents/rules/00-project_rules.md`, `.agents/rules/10-backend.md` y `documentation/plans/PLAN-013-side-b-windows-tauri.md`. Inspeccioná el código actual antes de editar. En la PC Windows x64, registrá Windows/CPU/RAM/DPI y versiones Rust; ejecutá desde `core/` `cargo test -p innertube` y `cargo test -p sideb-core`. Corregí únicamente incompatibilidades comprobadas de este repo necesarias para esos tests. No crees `windows/` todavía ni toques Swift. Al terminar, devolvé estado, archivos cambiados, comandos y resultados exactos, bloqueos y pruebas manuales pendientes. Si modificaste código, guardá el informe en `documentation/handoffs/W01-result.md`. Cerrá tu respuesta con una línea propia `ENTREGA LISTA: W01` o `BLOQUEADO: W01`. No declares M1 completo si faltan tests o una ventana Tauri funcional.

## Paquete W02 — ventana Tauri con el core conectado (resto de M1)

**Entrada:** W01 está comprobado en Windows; ver [`W01-result.md`](../handoffs/W01-result.md). Usar Visual Studio Build Tools 2022 en entorno de desarrollo x64 al compilar Rust, ya que la instalación VS 2026 elegida por un PowerShell normal no encontró `msvcrt.lib`. Node.js, pnpm y Rust están disponibles; comprobar versiones en la sesión antes de usarlos. Si una herramienta falta en el proceso de Antigravity, usar su ruta instalada y documentarlo.

**Alcance de código:** crear `windows/` con el template oficial **Tauri 2 + Svelte + TypeScript + pnpm**. Usar nombre visible Side B, identificador `com.fefucho.sideb.windows` y archivos de datos separados de la app Mac. En `windows/src-tauri/Cargo.toml`, agregar `sideb-core = { path = "../../core/crates/sideb-core" }`; verificar que Cargo construye esa dependencia real. Mantener los comandos y permisos del scaffold al mínimo. No implementar búsqueda, login, audio, cola ni pantalla visual definitiva en W02.

**Entregables:** `windows/` con código fuente, `pnpm-lock.yaml`, configuración Tauri e iconos iniciales propios del proyecto; `windows/README.md` con prerequisitos y comandos reproducibles; una verificación CI Windows x64 acotada al core y al build del shell. No incluir `node_modules/`, `target/`, datos de cuenta ni artefactos binarios en el repo. Consultar el código actual y las [instrucciones oficiales de Tauri](https://v2.tauri.app/start/create-project/) antes de fijar versiones o rutas.

**Verificación:** `pnpm install`, build frontend y build/check de `windows/src-tauri` con la dependencia del core; `pnpm tauri dev` debe abrir una ventana real en esta PC Windows y mostrar contenido de arranque. Registrar resultado y captura sin datos privados. Si aparece una falla en el core o el enlace V8/CRT, aislarla; no eliminar la dependencia para obtener una ventana superficial. Repetir los tests de `innertube` y `sideb-core` si W02 cambia `core/`.

**Salida:** ventana Tauri abierta y core enlazado, README/CI presentes, comandos y evidencia en `documentation/handoffs/W02-result.md`. Si falta una de esas piezas, devolver `BLOQUEADO: W02` con error y siguiente acción. W03 implementará el primer comando funcional con datos reales.

### Prompt listo para Antigravity — W02

> Trabajá sólo **W02** de `.agents/WORKFLOW_WINDOWS.md`, siguiendo `documentation/plans/PLAN-013-side-b-windows-tauri.md` y `.agents/rules/40-windows.md`. Leé `documentation/handoffs/W01-result.md` antes de compilar: en esta PC hay que usar el entorno x64 de Build Tools 2022 para encontrar `msvcrt.lib`. Creá el scaffold oficial Tauri 2 + Svelte + TypeScript + pnpm en `windows/`, agregá la dependencia real por ruta a `sideb-core`, y entregá README y CI Windows. Compilá y abrí la ventana en esta PC; documentá los resultados exactos y cualquier bloqueo. No implementes búsqueda, login ni audio todavía. Guardá `documentation/handoffs/W02-result.md` y terminá tu respuesta con una línea propia `ENTREGA LISTA: W02` o `BLOQUEADO: W02`.

**Cierre W02:** `pnpm build`, `cargo check`, `cargo build` y los tests del core aprobaron en Windows; el WebView2 mostró la pantalla de arranque y respondió a un comando IPC. Ver [informe](../handoffs/W02-result.md) y [captura](../screenshots/rendered_window.png). El CI remoto no se ha ejecutado porque este checkout no tiene `.git`. El `target` de Tauri es una unión local hacia `S:` para evitar llenar `C:`; no es parte del código distribuible.

## Paquete W03 — primera búsqueda real desde el core (M2 parcial)

**Propósito:** sustituir el saludo de prueba por un flujo de búsqueda de canciones que recorra `Svelte → invoke → SideBCore::search_songs → DTO tipado → Svelte`. No cerrar M2 todavía: Home, álbum y resolución de streams quedan para paquetes posteriores.

**Entrada y contratos comprobados:** `SideBCore::new(data_dir: String) -> Result<Arc<SideBCore>, SideBError>` y `search_songs(query: String, record_history: bool) -> Result<Vec<SongItemRecord>, SideBError>` están en `core/crates/sideb-core/src/lib.rs`. El record contiene `video_id`, `title`, `artists`, `album`, `duration` y `thumbnail`; también tiene campos de biblioteca que W03 no necesita exponer. En Tauri 2, usar `Manager::path()` para resolver `app_data_dir()` y `manage`/`State` para el estado compartido. Los comandos asíncronos con `State` deben devolver `Result`, según la [documentación oficial](https://v2.tauri.app/develop/calling-rust/). Inspeccionar el código vigente antes de editar.

**Archivos permitidos:** `windows/src-tauri/src/` y `windows/src-tauri/Cargo.toml`/`Cargo.lock` si son necesarios para DTO y estado; `windows/src/`, `windows/package.json`/`pnpm-lock.yaml` sólo si requiere dependencias justificadas; `windows/README.md`; `documentation/handoffs/W03-result.md`. No cambiar `core/`, `apple/`, permisos Tauri, login ni audio en este paquete. Mantener el identificador `com.fefucho.sideb.windows`.

**Trabajo:**

1. Crear una única instancia `Arc<SideBCore>` al iniciar Tauri en el directorio de datos de **esta app Windows** obtenido de Tauri. No usar rutas Apple, Limusic ni el repositorio como directorio de datos. Si falla la inicialización, mantener la ventana abierta y mostrar un error recuperable; no usar `unwrap`/`expect` para esa falla ni registrar contenido de cuentas.
2. Exponer `search_songs` con consulta recortada y `record_history = false`. Rechazar consultas vacías antes de ir a red. Convertir cada `SongItemRecord` a un DTO Rust `serde::Serialize` de campos estables en `camelCase`: `videoId`, `title`, `artists`, `album`, `duration`, `thumbnail`. Definir el tipo TypeScript correspondiente; no devolver JSON serializado como `String`, tokens de biblioteca, cookies ni URL firmadas. Mapear errores a un código/mensaje de UI sin volcar la consulta ni detalles sensibles a logs.
3. Sustituir la tarjeta de saludo por formulario de búsqueda con Enter y botón. Mostrar estados de espera, sin resultados y error, además de resultados reales con título y artista; las carátulas son opcionales. Evitar que respuestas de búsquedas anteriores reemplacen las nuevas. No agregar controles de reproducción o navegación sin acción real.
4. Actualizar README con el flujo y su límite actual. Añadir una comprobación local útil del contrato Rust/TS (por ejemplo, test del DTO serializado) sin crear tests que sólo copien la implementación.

**Verificación:** `pnpm install --frozen-lockfile`, `pnpm check`, `pnpm build`, `cargo check` y `cargo build` con Build Tools 2022; abrir `pnpm tauri dev` y realizar una búsqueda pública real (por ejemplo `Daft Punk`) en la ventana. Registrar resultado/captura sin datos de cuenta ni URL privadas. Si el proveedor impide obtener resultados, verificar al menos el error visible y dejar la prueba de datos reales pendiente; no afirmar que M2 está completo. Repetir tests de core sólo si se modificó `core/` (fuera del alcance previsto). Tener presente el espacio de `C:` y el `target` local en `S:`.

**Entrega:** guardar `documentation/handoffs/W03-result.md` con archivos, comandos/resultados exactos, evidencia visual y pendientes. Terminar la respuesta con `ENTREGA LISTA: W03` o `BLOQUEADO: W03`. Codex revisará contrato, estado/errores y prueba real antes de planear el paquete siguiente.

### Prompt listo para Antigravity — W03

> Implementá sólo **W03** de `.agents/WORKFLOW_WINDOWS.md` en este checkout, siguiendo `.agents/AGENTS.md`, `.agents/rules/40-windows.md` y `documentation/plans/PLAN-013-side-b-windows-tauri.md`. Leé `documentation/handoffs/W02-result.md` y las APIs reales de `SideBCore` antes de editar. Conectá una única instancia del core al directorio de datos propio de Tauri y una búsqueda pública real `search_songs` con DTO Rust/TypeScript tipado y UI de carga, vacío y error. No toques `core/` ni `apple/`, no agregues login/audio/Home/álbum todavía. Compilá con Build Tools 2022, probá la búsqueda en la ventana Windows y guardá resultados/evidencia en `documentation/handoffs/W03-result.md`. Si la red bloquea los datos reales, informalo como pendiente sin declarar M2 completo. Cerrá con `ENTREGA LISTA: W03` o `BLOQUEADO: W03`.

**Cierre W03:** `pnpm install --frozen-lockfile`, `pnpm check` (0 errores), `pnpm build` y `cargo check` aprobaron; una búsqueda pública de `Daft Punk` produjo 20 canciones en la ventana. Ver [informe](../handoffs/W03-result.md) y [captura](../screenshots/search_results.png). Home, álbum y resolución siguen pendientes de M2.

## Paquete W04 — búsqueda y detalle de álbumes (M2 parcial)

**Propósito:** permitir buscar álbumes y abrir un detalle con pistas reales a través de `SideBCore`. No añadir reproducción, login ni resolución de streams todavía. Conservar la búsqueda de canciones ya verificada.

**Contratos de entrada:** inspeccionar `SideBCore::search_cards(query, "albums") -> Vec<BrowseCardRecord>` y `SideBCore::get_album(browse_id) -> AlbumDetailRecord` en `core/crates/sideb-core/src/lib.rs` antes de editar. `BrowseCardRecord` contiene `kind`, `id`, `title`, `subtitle`, `thumbnail`, `duration`; `AlbumDetailRecord` contiene `browse_id`, `title`, `artist`, `thumbnail`, `items` y otros campos. Los `SongItemRecord` del detalle no deben exponer tokens de biblioteca ni datos de sesión al frontend.

**Archivos permitidos:** `windows/src-tauri/src/`, `windows/src/lib/`, `windows/src/routes/`, `windows/README.md`, `documentation/handoffs/W04-result.md`. Si una dependencia nueva es indispensable, explicar la razón antes de añadirla. No modificar `core/`, `apple/`, identidad de app, permisos o sistema de audio.

**Trabajo:**

1. Añadir comandos Tauri `search_albums(query: String)` y `get_album(browse_id: String)` al `AppState` existente. Usar los métodos reales del core y DTOs Rust `serde::Serialize` en `camelCase` con interfaces TypeScript correspondientes. Para álbumes, exponer sólo IDs/títulos/subtítulos/carátulas y, para detalle, título, artista, carátula y lista de canciones con campos de presentación. Validar parámetros vacíos y reutilizar `CommandError` con mensajes seguros; no loguear consultas, cookies ni respuestas completas del proveedor.
2. En Svelte, añadir elección visible entre Canciones y Álbumes. Las pestañas deben ejecutar el modo seleccionado; preservar o repetir claramente la consulta actual al cambiar de modo. Mostrar tarjetas de álbum con acción real de abrir detalle y un botón Atrás que restaure resultados. El detalle muestra datos reales y pistas como contenido, sin botones de reproducción falsos. Cubrir carga, vacío y error para búsqueda y detalle; impedir respuestas obsoletas si se cambia de modo o álbum durante una petición. Mantener foco/teclado y tamaños razonables en ventana estrecha.
3. Actualizar README con el flujo y límites. Mantener `windows/search_results.png` como evidencia histórica W03; guardar una captura nueva W04 sin datos privados cuando el flujo real funcione.

**Verificación:** desde `windows/`, `corepack pnpm install --frozen-lockfile`, `corepack pnpm check`, `corepack pnpm build`; desde `windows/src-tauri/`, `cargo check` y `cargo build` con Build Tools 2022. Ejecutar `pnpm tauri dev` en la PC, buscar álbumes públicos (por ejemplo `Daft Punk`), abrir uno y comprobar título, artista y pistas reales; capturar la pantalla. Comprobar que la búsqueda de canciones W03 sigue devolviendo resultados. Si la red falla, distinguir el bloqueo de un error de contrato y documentar qué verificación quedó pendiente. No marcar M2 completo.

**Entrega:** `documentation/handoffs/W04-result.md` con rutas, comandos/resultados, evidencia, pendientes y marcador final `ENTREGA LISTA: W04` o `BLOQUEADO: W04`.

### Prompt listo para Antigravity — W04

> Implementá sólo **W04** de `.agents/WORKFLOW_WINDOWS.md` en este checkout, siguiendo `.agents/rules/40-windows.md` y `documentation/plans/PLAN-013-side-b-windows-tauri.md`. Leé `documentation/handoffs/W03-result.md` y los contratos vigentes `SideBCore::search_cards` y `SideBCore::get_album`. Agregá DTOs y comandos tipados para buscar álbumes y abrir un detalle real con pistas; conservá la búsqueda de canciones W03 y su manejo seguro de errores. No toques `core/` ni `apple/`, no añadas login, audio, Home o stream. Compilá, corré `pnpm check`, probá ambos modos en la ventana Windows y guardá evidencia sin datos privados en `documentation/handoffs/W04-result.md`. No declares M2 completo. Cerrá con `ENTREGA LISTA: W04` o `BLOQUEADO: W04`.

**Cierre W04:** búsqueda pública de `Daft Punk` produjo 20 álbumes; se abrió *Random Access Memories* con 13 pistas reales y se volvió a la grilla. `pnpm check` y `cargo check` aprobaron. Ver [informe](../handoffs/W04-result.md), [grilla](../screenshots/album_search_results.png) y [detalle](../screenshots/album_detail.png).

## Paquete W05 — Inicio con secciones y chips reales (M2 parcial)

**Propósito:** mostrar el feed público de Inicio obtenido por `SideBCore::get_home_page`, manteniendo las búsquedas W03/W04. No diseñar aún la app completa ni añadir audio, sesión o resolución de streams.

**Contrato de entrada:** inspeccionar `SideBCore::get_home_page(chip_params: Option<String>) -> HomePageRecord` en `core/crates/sideb-core/src/lib.rs`. `HomePageRecord` contiene `chips`, `sections` y `continuation`. Cada sección tiene título, formato y elementos; cada chip tiene título y parámetros. El `HomeItemRecord` incluye campos de presentación e IDs, sin URLs firmadas. La llamada puede fallar por red o datos del proveedor; no asumir que el feed anónimo será idéntico al de la cuenta Mac.

**Archivos permitidos:** `windows/src-tauri/src/`, `windows/src/lib/`, `windows/src/routes/`, `windows/README.md` y `documentation/handoffs/W05-result.md`. No modificar `core/`, `apple/`, permisos, identidad, instalador ni login.

**Trabajo:**

1. Añadir comando `get_home_page(chip_params?: string)` usando la instancia compartida del core. Convertir a DTOs Rust `serde::Serialize` `camelCase` con tipos TypeScript verificables. Exponer sólo título/params de chips, título/formato/items de secciones y campos necesarios para mostrar cada item (`kind`, `id`, `title`, `subtitle`, `thumbnail`, `artists`, `duration`, `albumId` si corresponde). No devolver registros completos, cookies, tokens de biblioteca ni URL de stream. Reusar `CommandError` con mensaje seguro.
2. Añadir navegación visible Inicio / Buscar a la pantalla Svelte. Inicio muestra secciones reales con carátulas y chips que vuelven a llamar al core con sus parámetros; cubrir carga, vacío y error con reintento. Los ítems que no tengan navegación implementada se muestran como información, sin estilo de botón ni promesas de reproducción. Si un ítem tiene un álbum que puede abrirse con el comando W04, esa navegación debe ser real y el botón Atrás volver al origen correcto; si eso complica el alcance, dejar esos ítems sin interacción. Evitar respuestas obsoletas al cambiar chip o sección.
3. Mantener el estado y funcionamiento de búsquedas de canciones/álbumes y detalle. No implementar continuación/paginación en W05; no mostrar un control «Ver más» que no funcione. Actualizar README con alcance y límites.

**Verificación:** `corepack pnpm install --frozen-lockfile`, `corepack pnpm check`, `corepack pnpm build`, `cargo check` y `cargo build` con Build Tools 2022. En `pnpm tauri dev`, abrir Inicio y comprobar al menos una sección con datos reales del proveedor y un chip funcional; guardar captura sin datos privados. Regresar a Buscar y comprobar una canción y un álbum/detalle público. Si Inicio no devuelve datos por falta de sesión, comprobar el error/estado vacío y registrar el bloqueo; no sustituir por datos falsos ni declarar W05 listo como feed real. No marcar M2 completo: falta resolver streams.

**Entrega:** `documentation/handoffs/W05-result.md` con contratos, rutas, comandos/resultados exactos, capturas y pendientes; marcador final `ENTREGA LISTA: W05` o `BLOQUEADO: W05`.

### Prompt listo para Antigravity — W05

> Implementá sólo **W05** de `.agents/WORKFLOW_WINDOWS.md` siguiendo `.agents/rules/40-windows.md` y `documentation/plans/PLAN-013-side-b-windows-tauri.md`. Inspeccioná la API real `SideBCore::get_home_page` y leé `documentation/handoffs/W04-result.md` antes de editar. Agregá comando/DTOs tipados para Inicio con secciones y chips reales; mantené las búsquedas y detalle W03/W04. Los controles visibles deben funcionar: chips recargan el feed, y los ítems sin navegación implementada quedan informativos. No toques `core/` ni `apple/`, ni añadas audio, login, stream o paginación falsa. Corré `pnpm check`, build web/Rust y probá Inicio, chip y regreso a Buscar en la ventana Windows. Guardá evidencia sin datos privados en `documentation/handoffs/W05-result.md`; no declares M2 completo. Cerrá con `ENTREGA LISTA: W05` o `BLOQUEADO: W05`.

**Cierre W05:** Inicio público cargó 11 chips y secciones reales; cambiar a *Energize* cambió el feed. La navegación rápida Inicio→Buscar→Inicio, búsquedas W03/W04, `pnpm check`, build web y Rust aprobaron. Ver [informe](../handoffs/W05-result.md) y [captura](../screenshots/home_feed.png). Falta resolución/reproducción de streams.

## Paquete W06 — primera canción y reproductor mínimo (M2/M3 parcial)

**Propósito:** al hacer clic en una canción de Buscar o del detalle de álbum, resolverla con `SideBCore::resolve_stream(video_id, false)` y reproducirla con libmpv desde Rust. Entregar play/pausa, seek, volumen, progreso, duración, fin y error visibles. Una sola pista a la vez; sin cola, automix, login ni rediseño general.

**Preparación ya hecha por Codex:** en esta PC hay un build x64 GPL de libmpv de [mpv-player/mpv `git-release`](https://github.com/mpv-player/mpv/releases/tag/git-release), fijado en `S:\sideb-deps\mpv-gb4b5d69a4-x64-gpl\`. El ZIP original `libmpv-v0.41.0-dev-gb4b5d69a4-36603357422-x86_64-w64-mingw32-gpl.zip` tiene SHA-256 `e3a25841283d44590cac772e0e9cf027f14e4294705f08885437f57b0585480c`. Ya se extrajo `libmpv-2.dll` y se creó `mpv.lib` MSVC desde sus 86 exports con `dumpbin`/`lib` de VS Build Tools 2022. Son dependencias **locales**; no copiarlas al código fuente ni incluirlas en Git. Documentar el origen, licencia, hash y cómo configurarlas en otra máquina. Antes de un instalador hay que empaquetar/verificar el DLL y sus licencias (fuera de W06).

**Contratos que deben inspeccionarse:** `StreamPlaybackInfo` y `SideBCore::resolve_stream` en `core/crates/sideb-core/src/lib.rs`; `Player`, `PlayerEvent`, `load`, `play`, `pause`, `seek` y `set_volume` en `core/crates/player/src/lib.rs`; comandos Tauri existentes en `windows/src-tauri/src/lib.rs`. El crate `player` está fuera de los miembros de `core/Cargo.toml` aunque usa dependencias del workspace. Integrarlo como miembro y dependencia por ruta de `windows/src-tauri` si compila en Windows; si no, reportar el fallo concreto y proponer el cambio mínimo, sin copiar el wrapper ni sustituirlo silenciosamente por HTML Audio. El motor de audio pertenece a Rust: **ni la URL firmada ni los headers/cookies salen por `invoke`, eventos, DOM, almacenamiento web o logs**.

**Archivos permitidos:** `core/Cargo.toml`, `core/Cargo.lock` y `core/crates/player/` sólo para compatibilidad Windows del wrapper; `windows/src-tauri/Cargo.toml`, `Cargo.lock`, `build.rs`, `src/` y documentación/configuración local de libmpv; `windows/src/lib/types.ts`, `windows/src/routes/+page.svelte`, `windows/README.md`, `documentation/handoffs/W06-result.md`. No tocar `sideb-core`, `innertube`, UniFFI, Apple, login ni instalador. No guardar URLs firmadas ni tokens en capturas/informes. Avisar si un cambio adicional al core compartido resulta indispensable.

**Implementación:**

1. Conectar `player` y la librería de importación MSVC con una ruta **configurable** de desarrollo (por ejemplo `SIDEB_MPV_DIR` en `build.rs`, validada y documentada). El DLL debe estar junto al `.exe` para la prueba local, fuera de archivos fuente y de Git. Si se toca el crate compartido, preservar su API y el comportamiento Apple. Crear el directorio de caché con la API de rutas Tauri; inicializar un único `Player`, y mostrar error recuperable si libmpv/caché no inicia.
2. Agregar comandos Tauri tipados `play_song(video_id)`, `pause_playback`, `resume_playback`, `seek_playback(seconds)` y `set_playback_volume(volume)`; opcionalmente `get_playback_state` para restaurar la UI tras recarga. Validar ID y números finitos/rangos. Resolver el stream **dentro de Rust**, pasar URL y headers sólo a `Player::load`, y devolver únicamente metadatos seguros (ID, título, artista, carátula, duración si existe, estado). Evitar que una resolución lenta anterior reemplace una selección más nueva mediante generación/identidad de petición. No mantener locks de estado durante la espera de red. Errores de red/URL/mpv se convierten en códigos y mensajes seguros, sin `Debug` de `StreamPlaybackInfo` ni log de mpv que pueda revelar URL.
3. Tomar eventos del `Player` una vez y emitir a Svelte estado de reproducción, posición, duración, fin y fallo. Limitar eventos de posición a aprox. 4–10 Hz y separar estado interno del DTO emitido. Al finalizar la pista, dejar estado detenido; no inventar una cola. Una pista fallida no debe dejar la UI afirmando que suena. Si el wrapper emite mensajes de libmpv con URL, desactivar o sanear esos logs en Windows.
4. En Buscar canciones y pistas de álbum, clic/Enter inicia la canción. Añadir un reproductor simple y persistente durante navegación con título/artista, play/pausa, slider de posición, volumen y estados de carga/error. Todos los botones visibles deben funcionar. Los ítems de Inicio que sólo son informativos siguen sin control falso; no invertir tiempo en pulir estilo. Tipar `invoke`/eventos en TypeScript y limpiar listeners al desmontar.

**Verificación exigida:** `pnpm check`, `pnpm build`, `cargo check`, `cargo build` en VS 2022 x64 con `SIDEB_MPV_DIR` configurada; tests dirigidos del crate `player` si son ejecutables en Windows. Abrir la app en esta PC, buscar una canción pública y comprobar que el estado pasa por carga→reproduciendo, la posición aumenta durante al menos 10 s, pausa detiene el avance, reanudar lo continúa, seek salta, volumen cambia y EOF o error se refleja correctamente. Comprobar al menos una pista desde un álbum. Si se puede observar audio real por salida/loopback, registrar esa evidencia; si no, decir explícitamente que el sonido no fue confirmado aunque el reloj avance. No declarar M3 completo por compilación sola. Mantener operativos Inicio y búsqueda, sin datos sensibles en logs o UI.

**Entrega:** `documentation/handoffs/W06-result.md` con archivos, comandos/resultados exactos, evidencia y límites. Terminar respuesta con `ENTREGA LISTA: W06` o `BLOQUEADO: W06`. Codex revisará el código y repetirá la prueba; si hace falta una corrección, seguirá siendo W06.

### Prompt listo para Antigravity — W06

> Implementá sólo **W06** de `.agents/WORKFLOW_WINDOWS.md` para Side B Windows, siguiendo `.agents/AGENTS.md`, `.agents/rules/00-project_rules.md`, `.agents/rules/10-backend.md`, `.agents/rules/40-windows.md` y `PLAN-013`. Usá el libmpv y `mpv.lib` locales ya preparados en `S:\sideb-deps\mpv-gb4b5d69a4-x64-gpl\` y el entorno x64 de Build Tools 2022. Conectá `SideBCore::resolve_stream` al `core/crates/player` existente y al shell Tauri; reproducí una canción real con play/pausa, seek, volumen y progreso/fin/error visibles. No envíes URLs firmadas ni headers a Svelte, eventos o logs. No toques Apple ni el core de InnerTube/sideb-core, y no agregues cola/login/rediseño. Probá una canción de Buscar y otra del detalle de álbum en la PC, registrá pruebas y límites en `documentation/handoffs/W06-result.md`. Si un bloqueo técnico impide audio, devolvé la evidencia y el cambio mínimo necesario, sin marcar reproducción completa. Cerrá con `ENTREGA LISTA: W06` o `BLOQUEADO: W06`.

**Cierre W06:** `cargo test -p player` (4/4), `pnpm check` (0 errores), build web y `cargo check/build` aprobaron. En la ventana Windows, una pista de Buscar y otra de álbum avanzaron; pausa, reanudación, seek, volumen, EOF, guardia de reanudar en EOF y reinicio se comprobaron por eventos/estado de libmpv. Ver [informe](../handoffs/W06-result.md) y [capturas](../screenshots/playback_search_song.png). El usuario confirmó después que la canción se escucha en su equipo; no se midió el loopback del SO. M3 y el instalador siguen abiertos.

## Paquete W07 — cambio de canción y recuperación de errores (M3 parcial)

**Propósito:** hacer predecible el reproductor de una pista cuando el usuario elige otra canción, selecciona varias rápido o falla la resolución/carga. Conservar W06 y dejar una base confiable para empezar el shell visual M4. No añadir cola, anterior/siguiente, automix ni rediseño.

**Problema comprobado por revisión:** `play_song` cambia el DTO a la nueva pista antes de `resolve_stream`, pero el audio anterior puede seguir sonando mientras llega la respuesta o si falla; además el receptor global de `PlayerEvent` actualiza el DTO sin comprobar a qué intento de reproducción pertenece. La UI puede recibir respuestas `invoke` fuera de orden y `resume_playback` acepta un intento todavía cargando. Inspeccionar el código actual antes de editar y mantener una única semántica para esos casos.

**Archivos permitidos:** `windows/src-tauri/src/`, `windows/src/lib/types.ts`, `windows/src/routes/+page.svelte`, `windows/README.md`, `documentation/handoffs/W07-result.md`; `core/crates/player/` sólo si hace falta una corrección mínima del contrato de eventos, sin alterar Apple. Si se toca el crate compartido, seguir `.agents/rules/10-backend.md` y comprobar sus tests. No tocar `sideb-core`, `innertube`, Apple, identidad de app, login ni instalador.

**Trabajo:**

1. Definir explícitamente el cambio de A→B: al seleccionar B, detener A de forma efectiva antes de anunciar B como pista actual. Mientras B se resuelve, mostrar carga; al fallar, dejar audio detenido y un error de B con acción **Reintentar** funcional. Evitar que un `TrackEnded`, progreso o fallo de A cambie el estado visible de B. No dejar pistas ocultas reproduciéndose. Si el wrapper necesita exponer una operación para detener/vaciar, usar la API existente o una extensión mínima.
2. Mantener la guardia de generación de peticiones para selecciones rápidas A→B→C. Sólo la selección más reciente puede cargar el motor, cambiar estado o mostrar un error. Las respuestas `invoke` antiguas en Svelte tampoco pueden reemplazar el estado más nuevo. No mantener un mutex de estado durante la red. Bloquear pausa/reanudación/seek cuando no hay pista realmente cargada, sin mostrar `isPlaying = true` hasta evento válido del motor.
3. Tratar fallo de resolución, fallo de carga y `TrackFailed` con estado coherente y mensaje seguro, sin URL firmada, headers ni detalles privados en frontend o logs. El botón central después de un fallo debe reintentar la pista actual; al iniciar otra pista, el error previo desaparece. Mantener reproducción normal y EOF de W06.
4. Actualizar README con la semántica de cambio/error y los límites que siguen abiertos (salida acústica física si todavía no se midió; formatos AAC/Opus, expiración de URLs e instalador). No presentar W07 como cierre de M3.

**Verificación:** `corepack pnpm check`, `corepack pnpm build`, `cargo check`, `cargo build`; tests del `player` si se modifica. En la ventana Windows con datos públicos, reproducir A, elegir B durante A y comprobar que el título/progreso corresponden a B y que sólo una pista suena; repetir una selección rápida A→B→C. Provocar un fallo con un ID inválido o un caso reproducible sin datos privados: el audio previo debe detenerse, el error debe aparecer y Reintentar debe funcionar (puede volver a fallar de modo coherente); después elegir una pista válida y recuperar reproducción. Pausa/reanudación/seek durante carga/fallo no deben afirmar éxito falso. Comprobar que Inicio, Buscar, álbum y EOF siguen funcionando. Registrar explícitamente qué se observó en audio físico y qué sólo por eventos/posición.

**Entrega:** `documentation/handoffs/W07-result.md` con decisión de estado, archivos, comandos/resultados, prueba manual, evidencia y pendientes. Terminar respuesta con `ENTREGA LISTA: W07` o `BLOQUEADO: W07`. Codex revisará y repetirá los casos críticos antes de asignar M4.

### Prompt listo para Antigravity — W07

> Implementá sólo **W07** de `.agents/WORKFLOW_WINDOWS.md` en este checkout. Leé `.agents/AGENTS.md`, `.agents/rules/00-project_rules.md`, `.agents/rules/40-windows.md`, `PLAN-013` y `documentation/handoffs/W06-result.md`. Corregí la transición A→B, selecciones rápidas, eventos viejos, errores y reintento del reproductor Windows. La pista anterior debe detenerse al anunciar la nueva; sólo la última selección puede cargar y actualizar UI; ninguna falla puede dejar audio oculto. Conservá W06 y no implementes cola ni rediseño. Usá `SIDEB_MPV_DIR` y Build Tools x64 ya documentados. Verificá compilación y los escenarios reales en la ventana; guardá resultados y límites en `documentation/handoffs/W07-result.md`. Cerrá con `ENTREGA LISTA: W07` o `BLOQUEADO: W07`.

**Cierre W07:** Antigravity entregó y documentó los 10 escenarios CDP en [W07-result.md](../handoffs/W07-result.md). Codex revisó el bloqueo del reproductor al detener/cargar y confirmó `cargo check` posterior. No se asignaron más tareas a Gemini para conservar cuota.

## Secuencia visual acordada — W08 a W11

El usuario priorizó una construcción por partes: primero estructura general y orden correcto de los ítems, luego versiones básicas de barra, Inicio y fullscreen; después ampliar cada parte y trabajar las demás pantallas de a una. Cada paquete debe establecer componentes y contratos estables que admitan contenido posterior, evitando rehacer el shell. W07 se cierra porque ya estaba editando el reproductor. Desde W08, no ampliar funcionalidad de audio salvo regresiones que impidan usar la UI. Tomar como referencia el código Mac vigente y `PLAN-013`, no una captura vieja. Esta copia carece de `.git`: Codex dejará un snapshot recuperable de los archivos Windows antes del refactor visual.

**Contratos de componentes para crecer sin rehacer:** `AppShell` recibe estado de sidebar/destino y regiones sidebar/contenido/player/overlay, sin poseer datos de Home ni reproducción; `Sidebar` recibe destinos tipados y callbacks, manteniendo grupos y orden fijos; `PlayerBar` consume un único `PlaybackStateDto` y callbacks existentes, sin polling propio; `HomeView` recibe chips/secciones y callbacks mientras el contenedor conserva cancelación de peticiones; `FullscreenNowPlaying` recibe pista/estado y acción cerrar, con región derecha reemplazable. Navegar, colapsar sidebar o abrir fullscreen no debe desmontar la barra ni reiniciar audio. Son límites de responsabilidad, no obligación de crear todos los componentes en W08.

### W08 — shell y sidebar en el orden de Side B

Crear tokens CSS según `apple/Sources/SideB/UI/AppTheme.swift` (fondo `#1B1B1E`, sidebar `#24242A`, acento `#A33D45`, realce `#D06C70`) y componentes estables `AppShell`, `Sidebar` y `ContentHost`. Mantener el orden que muestra `apple/Sources/SideB/Views/Sidebar/SidebarView.swift`: **Inicio, Buscar; COLECCIÓN: Tus Me Gusta, Biblioteca, Historial; selector Playlists/Álbumes y su lista; perfil al pie**. Inicio y Buscar deben funcionar con los flujos actuales; álbum conserva su detalle. Mostrar los destinos todavía pendientes en la posición correcta pero claramente deshabilitados, sin navegación o datos fingidos. El perfil puede mostrar estado invitado sin prometer login. Añadir foco visible y `Ctrl+K` para Buscar. Una navegación básica Atrás debe volver desde álbum a su origen; Adelante/Actualizar se incorporarán cuando el historial esté modelado, sin controles falsos. Mantener temporalmente la barra actual hasta W09.

**Salida W08:** shell reconocible, orden visual completo y navegación básica real de Inicio/Buscar/álbum; sidebar abre/cierra con contenido y reproductor estables. `pnpm check/build` y prueba visual en ventana ancha/estrecha. Capturas públicas con sidebar abierta/cerrada e informe `documentation/handoffs/W08-result.md`.

**Corte W08:** Sidebar e integración básica entregadas en [W08-result.md](../handoffs/W08-result.md). `pnpm check/build` y pruebas en ventana ancha pasaron. La extracción opcional de `AppShell`/`ContentHost` y la comprobación de ventana estrecha siguen abiertas.

### W09 — barra de reproducción básica

Usar `apple/Sources/SideB/Views/Components/PlayerBarView.swift` como referencia de jerarquía. Extraer la barra actual a un componente estable `PlayerBar` y llevarla a una isla flotante, centrada respecto del **contenido** con sidebar abierta/cerrada. Conservar scrubber, carátula/metadatos, play/pausa/reintento y volumen reales. No añadir todavía acceso a fullscreen, cola, letras, AirPlay o controles sin destino. No tapar la última fila ni cortar los controles básicos en ventana estrecha. La API del componente debe aceptar el estado/eventos actuales sin duplicar estado de reproducción.

**Salida W09:** barra básica funcional con una canción real, sidebar abierta/cerrada, ventana estrecha/ancha y teclado. `pnpm check/build`, prueba manual y capturas públicas en `documentation/handoffs/W09-result.md`.

**Corte W09:** Barra conectada y probada con pista real, pausa, seek y volumen en [W09-result.md](../handoffs/W09-result.md). `pnpm check/build` pasaron sin avisos. Falta comprobar ventana estrecha visualmente; no se declaran W10/W11 integrados.

### W10 — Inicio visual básico con contenido real

Extraer una vista `HomeView` con chips arriba y secciones/estantes básicos con tarjetas, carátulas y títulos reales del `get_home_page` ya conectado. Seleccionar chip debe cambiar el feed; carga, vacío y error deben seguir correctos. Los ítems sin destino implementado quedan informativos, sin controles falsos. Dejar la estructura de sección/tarjeta preparada para variantes posteriores sin implementar todavía todas las interacciones ni animaciones de Mac. Evitar que progreso del player rerenderice todo el feed en cada tick; medir si se afirma una mejora de rendimiento.

**Salida W10:** Inicio básico usable y coherente visualmente con Side B, con datos públicos y chip funcional; búsqueda/álbum/reproducción sin regresión. `pnpm check/build`, prueba en la ventana, capturas públicas e informe `documentation/handoffs/W10-result.md`.

### W11 — fullscreen básico del tema actual

Crear `FullscreenNowPlaying` como una capa del shell que abre/cierra desde un control real añadido a `PlayerBar` en este paquete. Usar la jerarquía de `apple/Sources/SideB/Views/Fullscreen/FullscreenNowPlayingView.swift`: portada y metadatos de la pista actual a la izquierda, espacio de panel a la derecha. Si aún no hay pista, mostrar un estado vacío útil. La transición no debe reiniciar ni pausar el audio. Mostrar **Cola, Letras, Relacionado** en su orden como pestañas claramente deshabilitadas hasta que cada fuente de datos/acción exista; no construir cola ni letras ficticias. El componente y sus slots deben admitir esas funciones después sin rehacer el fullscreen.

**Salida W11:** abrir/cerrar fullscreen con una pista real y conservar audio/posición; layout básico correcto con ventana ancha/estrecha. `pnpm check/build`, prueba en Windows, captura pública e informe `documentation/handoffs/W11-result.md`. Después, completar paneles y pantallas de Biblioteca, Historial, playlists, artista y demás destinos, uno por paquete.

**Corte W11:** El usuario adelantó fullscreen antes de W10 y autorizó una Cola visual sin gestión real. Se integró la vista básica con pista actual, tres pestañas, botón de la barra y cierre con `Esc`; el progreso siguió al abrir/cerrar. Ver [W11-result.md](../handoffs/W11-result.md). W10 y el breakpoint menor de 780 px siguen pendientes.

## W12 — acceso y sesión Windows

El usuario priorizó evaluar login antes de integrar W10. Seguir [PLAN-014](../plans/PLAN-014-windows-login.md). W12a es una decisión de viabilidad sin credenciales ni UI; W12b almacenamiento/contrato, W12c flujo visible y W12d primera pantalla de Biblioteca sólo comienzan si el paquete anterior pasa. El core actual guarda `session_cookie` en SQLite; no copiar el flujo WKWebView del Mac ni mostrar un login que no pueda cerrar el circuito. Codex coordina y revisa; el primer subpaquete se asigna a un subagente Codex GPT-6 Luna para reservar la cuota de Antigravity.

**Cierre W12a:** Luna entregó la [evaluación de autenticación](../handoffs/W12a-auth-feasibility.md). OAuth oficial de escritorio no entrega directamente la cookie que usa InnerTube. W12b/W12c esperan una decisión de producto entre sesión web no oficial tipo Mac, modo invitado por ahora o un rediseño con APIs oficiales. No se manejaron credenciales ni se usó Antigravity.

**Avance W12b/W12c:** El usuario eligió el flujo de sesión web tipo Mac después de revisar LiMusic. Codex y Luna implementaron el [prototipo de login Windows](../handoffs/W12-login-prototype.md): core sin cookie en SQLite, DPAPI, ventana WebView2, estado de perfil y logout. Tras corregir un deadlock de Tauri pasando `login_webview` a comando asincrónico, el usuario confirmó acceso y restauración luego de reiniciar. Compilación y tests dirigidos pasaron; falta probar logout/reinicio invitado. W12d Biblioteca sigue pendiente.

## Siguiente serie propuesta — W13 a W17

El [PLAN-015](../plans/PLAN-015-windows-reproduccion-cola.md) define paquetes pequeños de reproducción y cola: W13 navegación y sincronización visual, W14 edición manual, W15 shuffle/repeat, W16 radio/automix y W17 restauración/robustez. El avance de cada paquete se registra abajo. W12d Biblioteca continúa como pendiente independiente; coordinar cualquier cambio de cuenta con la cola antes de tocar el mismo estado.

**Avance W13:** el usuario autorizó implementación con GPT-6 Luna. Cola de álbum/tema, ocurrencias, transporte Rust, EOF automático, fullscreen real y carátulas sincronizadas implementados; check/build web y Rust y 3 tests aprobaron. La prueba de audio y UI con una cola real sigue pendiente: el control de ventanas falló al retomar después del corte. Ver [W13-result](../handoffs/W13-result.md). W14–W17 siguen propuestos.

## Prioridad visual — Inicio y catálogo (2026-09-30)

El control de ventanas volvió a funcionar tras reiniciar Codex: se leyó la lista de ventanas y se activó/capturó Antigravity. Esto habilita la prueba manual pendiente, pero no la da por realizada.

El usuario priorizó completar la UI de Inicio según macOS y después playlist, álbum y perfiles, pantalla por pantalla. Seguir [PLAN-016](../plans/PLAN-016-windows-ui-paridad-macos.md): **W10a geometría e integración → W10b metadata/acciones → W10c continuación/estados → W10d cierre visual → W18 playlist → W19 álbum → W20 artista/catálogos → W21 cuenta**. El Inicio actual sigue inline; `HomeView.svelte` todavía no está integrado. W14–W17 mantienen su alcance funcional y no se mezclan con el primer paquete visual. Primer encargo preparado: W10a; implementación pendiente.

**Avance W10a:** el usuario autorizó reparto con Luna. Tres subagentes GPT-6 Luna implementaron HomeView, estantes/tarjetas y presentación/tokens; Codex integró `+page.svelte`, retiró el Inicio anterior y corrigió geometría/metadata. Check web sin errores/avisos, build y prueba de presentación aprobaron. Inicio real, sidebar contraída y apertura de álbum comprobados; ventana estrecha, teclado y comparación por captura Mac pendientes. Ver [W10a-result](../handoffs/W10a-result.md). El párrafo anterior describe el punto de partida; `HomeView` ya está integrado. W10b/W10c continúan pendientes.
