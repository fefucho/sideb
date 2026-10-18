# Release 1.2.4

- Fecha: 2026-10-18 (America/Montevideo).
- Estado: preparación; publicación y comprobaciones hospedadas pendientes.
- Objetivo: publicar la corrección de volumen FIX-213 que el usuario confirmó funcionando tras FIX-214.
- Autorización: «buenísimo ahora sí anda te animás a subir esa build». Se prepara1.2.4/build17 para que el actualizador numérico pueda ofrecerla sin reemplazar1.2.3. La opción de subir sólo el ZIP exacto se consultó y se dio oportunidad de responder; se continúa con la actualización recomendada. No se cambian los bytes de0014 ni se presentan como binarios1.2.4.
- Alcance: fuente Windows de FIX-213, su regresión, registros de diagnóstico/confirmación, versiones/manifests/notas. Mac conserva fuentes funcionales y se recompila por el flujo conjunto; core y dependencias conservados. No instalar, reemplazar la app abierta, force push ni modificar releases anteriores.
- Referencias: FIX-213/214/215, PAR-032, [PLAN-009 Windows](../windows/plans/PLAN-009-volume-scroll-feedback.md).

## Pasos

- [x] Revisar estado/main/remoto: b5efe02 local y origin/main, sin commits divergentes. Latest pública1.2.3/build16;0014 compiled/764pruebas/cuatro hashes y usuario confirma funcionamiento.
- [x] Preparar1.2.4/build17, manifests, versión del paquete propio en Cargo.lock, default del workflow y notas. No modificar versiones de dependencias.
- [x] Aprobar preflight v1.2.4/build17 y pruebas runner/release:19aprobadas/1omisión de empaquetado Mac en Windows, cero fallos. Diff y archivos explícitos revisados; fuentes Apple/core y dependencias conservadas.
- [ ] Commit/push a main y tagv1.2.4 en el mismo commit; activar el workflow existente por push del tag sin extraer credenciales.
- [ ] Seguir CI Mac y Windows hasta aprobar pruebas/builds y publicación conjunta.
- [ ] Verificar release Latest/tag/commit, paquetes/checksums y descargas públicas.
- [ ] Registrar resultado real y límites en FIXES/PARIDAD/PLAN-009 y este plan.

## Autenticación y límites

La revisión automática rechazó un intento de reutilizar la credencial guardada de Git para la API. No se extrae ni se persiste esa credencial. El navegador de trabajo no está autenticado; se encontró GitHub disponible para conectar, pero el flujo por tag usa Git Credential Manager y el token de Actions dentro de GitHub, sin requerir una conexión nueva. Un push fallido o CI incompleto no cuenta como publicación.

La confirmación del usuario corresponde a la lógica corregida en0014; la entrega1.2.4 requiere CI y hashes propios. No se inventa escucha física Mac ni prueba de instalación interactiva. Diagnósticos/prototipos/datos locales quedan en temp o builds ignorados.
