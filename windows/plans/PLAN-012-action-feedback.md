# PLAN-012 — Respuesta inmediata de Me Gusta y biblioteca

- Fecha: 2026-10-19 (America/Montevideo).
- Estado: implementado; frontend, QA navegador y verify/build EXE Windows en CI aprobados, incluidos los cuatro tests Rust en Tauri nativo. Cuenta real/WebView2 interactivo pendientes. FIX-222 / PAR-035.
- Objetivo: eliminar esperas de acciones detrás de cargas de biblioteca y mostrar inmediatamente la intención del usuario, con reversión y error ante un rechazo.
- Ámbito: integración Tauri Windows, controller de cuenta, composición y botones de Like/Guardar/Suscripción; conservar edición de playlists, generaciones, cuenta y acciones existentes. Apple/core sólo como referencia.
- Causas comprobadas: `auth_operation` es un mutex sostenido durante solicitudes completas (incluidos catálogos de biblioteca paginados). El corazón del reproductor/cola confunde hidratación global de likes con mutación individual. `toggleLike` espera todas las páginas antes de actuar; guardados esperan también recargas posteriores. Los botones reemplazan su contenido por un spinner hasta confirmar la red.
- Referencias: FIX-087/166/174/221; Apple `AlbumDetailViewModel.toggleLibrary` y `PlayerViewModel.toggleTrackLike` ya actualizan primero y revierten al fallar.

## Ejecución

- [x] Revisar antecedentes y localizar las esperas en frontend y runtime.
- [x] Permitir solicitudes simultáneas de una misma sesión, manteniendo cambios de credenciales exclusivos y mutaciones serializadas.
- [x] Acotar a15s las acciones simples de Like/Guardar/Suscripción, incluyendo su espera en cola, sin reintentos automáticos.
- [x] Aplicar feedback optimista con rollback aislado por cuenta y eliminar recargas secundarias de la espera del botón.
- [x] Separar hidratación global del pending individual y conservar icono/etiqueta durante sincronización.
- [x] Probar red lenta/error, duplicados, páginas tardías y cambio de cuenta; ejecutar check/test/build frontend y tests Rust del guard de sesión.
- [x] Registrar FIX, paridad, evidencias y límites Windows nativos.

## Resultado

- Check0/0;398pruebas frontend aprobadas/1omitida exclusiva Windows; compilación frontend en `windows/build/` con advertencia de chunk grande preexistente.
- Cuatro tests Rust de concurrencia/timeout aprobados con Tokio1.53.1 (lock de Windows) en `.cache/action-feedback-rust/`. Check global Tauri en Mac no aprobado: handlers/login/session exclusivos Windows; detalles en FIX-222. Configuración y lock de producción conservados.
- Browser con callbacks controlados: Guardar seleccionado y etiqueta visibles en el primer click; corazón visible mientras confirma. Captura `windows/.cache/action-feedback/evidence/immediate-feedback.png` y logs locales. Simulación de la vista previa termina a900ms, sin cuenta ni cambios remotos.
- Apple revisado por código: optimismo existente en álbum/Like, sin editarlo ni cambiar core. [FIX-222](../../FIXES.md#fix-222), [PAR-035](../../PARIDAD.md).

## Cierre

No probar mutaciones contra la cuenta real. Las pruebas usan RPC controladas y componentes reales. La verificación aislada Rust en Mac no sustituye WebView2/EXE/verify en Windows. Core y Apple funcionales se conservan. La publicación posterior autorizada se gestiona por separado en FIX-223.

## Entrega nativa posterior — FIX-223

1.2.5/build 18: 397 tests frontend sin omisiones/check 0/0; Tauri nativo aprueba 97 tests, incluidos los cuatro de SessionOperations, y verify/build release completos. EXE x64 1.2.5.0 y hashes de los cuatro archivos de runtime comprobados contra el SHA de fuentes exacto. La fase frontend inicial incluía dos tests de trabajo local ajeno que se excluyen de esta entrega. [Release 1.2.5](../../plans/RELEASE-1.2.5.md), [CI](https://github.com/fefucho/sideb/actions/runs/39287591174). Quedan pendientes la latencia del proveedor/cuenta real y aceptación interactiva en Windows.
