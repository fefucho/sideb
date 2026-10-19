# Release 1.2.6

- Fecha: 2026-10-19 (America/Montevideo).
- Estado: preparación.
- Autorización: «actualiza el codigo desde github y despues arma la nueva sidebar pone las opciones etc y subilo otra vez».
- Base: origin/main 23f1df5; Latest 1.2.5, build 18. Conservar la integración Windows de colecciones/cipher de 8f38bfe y su build 0016.
- Entrega: 1.2.6/build 19, tag v1.2.6, Latest numérica con aviso beta; paquetes Mac/Windows nuevos del mismo commit.
- Contenido: FIX-224 sidebar y Apariencia en ambas apps; FIX-225 metadatos/publicación. [Plan funcional](PLAN-010-sidebar-delivery.md).

## Pasos

- [x] Crear checkout desde GitHub y conservar el trabajo local previo.
- [x] Integrar sidebar/opciones con fuentes remotas; actualizar metadatos y notas.
- [x] Aprobar verificaciones locales y revisión del diff.
- [ ] Commit/push y tag del SHA exacto sin force.
- [ ] Aprobar ambos builds y la publicación conjunta del workflow.
- [ ] Descargar los cinco assets públicos sin autenticación; comprobar Latest, tag, versiones, arquitectura, firmas/hashes y selección del actualizador.
- [ ] Registrar cierre en FIXES/paridad/planes y subir documentación.

## Límites

No se instalan ni abren apps de producción ni se modifica cuenta/reproducción. Mac conserva firma ad hoc sin notarización. Windows físico y latencia del proveedor requieren aceptación del usuario; los tests y fixtures no certifican audio/FPS ni instalación interactiva.

Preflight v1.2.6/build 19 y 20 tests de release/runner aprobados. Frontend check 0/0, 399 aprobadas/1 omitida y build; Mac local build-0001 estable, 764 ejecutadas aprobadas, firma/arquitectura/hashes válidos. Ajuste posterior exclusivo CSS Windows y CI Mac general serializado; CI de release verifica el commit final limpio. Detalles en el plan funcional.
