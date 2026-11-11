# PLAN-024 — Reproducción de Too Good

- Fecha: 2026-10-29 (America/Montevideo).
- Estado: FIX-313/FIX-314 implementados y entregados en build0026 Release compiled, fuentes estables y cuatro hashes revalidados. Verify1090aprobadas/0fallos; dos probes en vivo aprobadas aparte. Too Good y One Dance resuelven WEB_REMIX/itag141 y devuelven audio por GET. Escucha/recorrido en app pendientes.
- Objetivo: reproducir el fallo de `ZBz12OQJT_Q` (Too Good feat. Rihanna, ID encontrado en la cola local) y corregir su causa conservando la grabación elegida.
- Alcance: diagnóstico de resolución/cipher y reproducción Windows; consultar core y Apple. Cambiar core sólo si se demuestra defecto compartido.
- Antecedentes: FIX-083, FIX-219, PAR-033 y PLAN-010. Instalar el callback no acreditó reproducción de la pista real.
- Exclusiones: publicación, Git, cambio de cuenta o sustitución por otra versión.

## Pasos

- [x] Leer reglas, historial y estado Git (limpio al comenzar).
- [x] Identificar ID en la cola local sin imprimir sesión ni URLs privadas.
- [x] Reproducir y separar configuración de player, ejecución JS y validación HTTP; libmpv/escucha quedan explícitamente pendientes.
- [x] Corregir la causa demostrada y agregar regresiones pertinentes.
- [x] Ejecutar comprobaciones, revisar diff y registrar fix/paridad según evidencia.
- [x] Entregar resultado y límites de audio/proveedor/plataforma.
- [ ] Confirmar escucha y recorrido de reproducción/reintento en la app nativa; no se acredita con GET ni compilación.

## Evidencia

- La caché local contiene player `4efb8b2c`; falta en tabla bundled, pero ambos registros remotos actuales incluyen configuración para él. Esto por sí solo no demuestra el fallo.
- Se solicitó enlace/error al usuario para confirmar la versión; la investigación independiente continúa con el ID de la cola.
- El test en vivo con la integración anterior falla: el player no carga. Probe aislado identifica `Context has not been set and window is undefined`; rquickjs fuerza strict por defecto, anulando el this del IIFE que el player usa como window.
- El mismo player/inyección carga y transforma firma/n con strict no forzado. Apple usa JavaScriptCore sin esta opción; core no requiere modificación.
- FIX-313 conserva presupuestos/aislamiento y agrega regresión de IIFE clásico/strict explícito, prueba pública optativa y prueba optativa de resolución/GET con sesión nativa sin audio.
- `cargo test --offline --locked --manifest-path windows/src-tauri/Cargo.toml --lib cipher_runtime::tests -- --nocapture`:11aprobadas/2live ignoradas. `live_public_player_cipher -- --ignored --nocapture`:1aprobada tras el fix; la misma prueba falló antes.
- `SIDEB_LIVE_SESSION_DIR` apunta al almacén nativo autorizado; `live_session_stream_probe -- --ignored --nocapture`:1aprobada, ambos IDs resueltos por WEB_REMIX/itag141, GET parcial de4096bytes de audio para cada uno. Usa sesión sólo en memoria y DB auxiliar temporal; no cambia cola, cuenta, historial ni muestra URLs. No prueba mpv ni sonido audible.

## Entrega y bloqueo de build

- Primer protocolo oficial: build0025 fallida, conservada con su diagnóstico. Frontend502aprobadas/1fallida por timeout CDP de la fixture PlayerBar; no es un EXE nuevo.
- Repetición aislada reproduce Runtime.evaluate timeout. FIX-314 limita el entry de optimización y desactiva watcher en la fixture inmutable cuyo root contiene perfiles de Edge. Limitar sólo el entry no bastó; con watcher desactivado la copia diagnóstica completa16casos/errors[]. No se modifican assertions ni producto.
- Test oficial aislado:1aprobada/0fallos en17,9s con16geometrías; suite completa lo repite en34,4s sin fallo. No se redujeron assertions ni ampliaron timeouts.
- Build0026: `node Scripts/build-version.mjs windows`, Release x64, `status:compiled`, `sourceChangedDuringBuild:false`; EXE/libmpv/Vulkan/licencia juntos y cuatro hashes revalidados. Ejecutable: `builds/windows/build-0026/sideb-windows.exe`; manifest y log al lado. EXE SHA256 `a01f10276436cf32545bb95fec162b072ba1567b8273e07bae1bb5424e98ee7f`.
- Verify:1090aprobadas(503frontend/112InnerTube/175core/177bridge/5player/118Tauri),0fallos/22live ignoradas. Las dos probes nuevas fueron ejecutadas aparte. Check0errores/1warning previo MediaCard; builds frontend/nativa aprobadas con avisos existentes dead_code/LNK4098/chunk. Diff y rustfmt revisados.
- Documentación de cierre posterior al empaquetado; sin cambios funcionales posteriores. Sin abrir app ni escuchar audio durante esta ronda; prueba del proveedor por HTTP separada de reproducción física. Apple/core intactos; sin nueva validación Mac ni cierre de aceptación nativa PAR-033.
