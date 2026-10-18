# Release 1.2.3

- Fecha: 2026-10-18 (America/Montevideo).
- Estado: verificación local aprobada; commit/push y compilación/publicación hospedadas pendientes.
- Objetivo: publicar FIX-211 para que el usuario pueda actualizar su PC; entregar Mac y Windows en la misma release, con paquetes y checksums comprobados.
- Versión:1.2.3/build16, tag v1.2.3, Latest numérica con aviso beta, igual que las entregas anteriores.
- Alcance: política de entrada Windows y regresiones basadas en deltas numéricos; diagnóstico local acotado. Mac conserva fuentes/UI/audio de1.2.2; core y dependencias conservados. Versiones/manifests y notas actualizadas, sin relabel de binarios anteriores.
- Autorización: «actualiza entonces pone1.2.3» continúa el pedido de publicar el arreglo e incluye commit/push/tag/release; no requiere otra confirmación.
- Referencias: [FIX-211](../FIXES.md#fix-211), FIX-212, [PLAN-009 Windows](../windows/plans/PLAN-009-volume-scroll-feedback.md), PAR-026/PAR-032.

## Pasos

- [x] Revisar main/remoto/releases: local y origin/main en7c8ebbc, sin divergencia ni intento activo; Latest1.2.2 y sin release1.2.3. Caché/prototipos y captura original del usuario quedan fuera de Git.
- [x] Actualizar version.env/manifests Windows/versión del paquete propio en Cargo.lock/default del workflow y notas1.2.3. No cambiar versiones de dependencias.
- [x] Aprobar preflight v1.2.3/build16 y20tests runner/release; frontend384aprobadas/1fixture nativa omitida enMac, check0/0/build aprobado. Diff, FIXES, paridad y paths explícitos revisados; no son comprobaciones nativas1.2.3 todavía.
- [ ] Commit/pushmain y dispatch Release Side B para v1.2.3; comprobar revisión exacta del borrador/tag.
- [ ] Seguir compilación/pruebas nativas Mac y Windows; resolver cualquier fallo sin omitir guardas.
- [ ] Verificar publicación Latest/tag/revisión, tres paquetes y dos archivos SHA256, metadatos de build/fuentes/hashes y descargas públicas.
- [ ] Registrar entrega y límites físicos con enlace y resultados reales.

## Límites

Las pruebas del fix reproducen tres grupos de entrada real y usan RPC simulado; la build nueva requiere prueba física del usuario en Windows. No se prueba cuenta personal, audio audible ni instalación interactiva por publicar paquetes. Mac mantiene firma ad hoc sin notarización. No se reemplaza1.2.2 ni se abre/instala una app local.
