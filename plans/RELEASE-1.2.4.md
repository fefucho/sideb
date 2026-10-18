# Release 1.2.4

- Fecha: 2026-10-18 (America/Montevideo).
- Estado: completado. [Release1.2.4](https://github.com/fefucho/sideb/releases/tag/v1.2.4) publicada como Latest el2026-10-18 a16:38:40 America/Montevideo. Los cuatro jobs de [CI39157077739](https://github.com/fefucho/sideb/actions/runs/39157077739) y las cinco descargas públicas están verificados.
- Objetivo: publicar la corrección de volumen FIX-213 que el usuario confirmó funcionando tras FIX-214.
- Autorización: «buenísimo ahora sí anda te animás a subir esa build». Se prepara1.2.4/build17 para que el actualizador numérico pueda ofrecerla sin reemplazar1.2.3. La opción de subir sólo el ZIP exacto se consultó y se dio oportunidad de responder; se continúa con la actualización recomendada. No se cambian los bytes de0014 ni se presentan como binarios1.2.4.
- Alcance: fuente Windows de FIX-213, su regresión, registros de diagnóstico/confirmación, versiones/manifests/notas. Mac conserva fuentes funcionales y se recompila por el flujo conjunto; core y dependencias conservados. No instalar, reemplazar la app abierta, force push ni modificar releases anteriores.
- Referencias: FIX-213/214/215, PAR-032, [PLAN-009 Windows](../windows/plans/PLAN-009-volume-scroll-feedback.md).

## Pasos

- [x] Revisar estado/main/remoto: b5efe02 local y origin/main, sin commits divergentes. Latest pública1.2.3/build16;0014 compiled/764pruebas/cuatro hashes y usuario confirma funcionamiento.
- [x] Preparar1.2.4/build17, manifests, versión del paquete propio en Cargo.lock, default del workflow y notas. No modificar versiones de dependencias.
- [x] Aprobar preflight v1.2.4/build17 y pruebas runner/release:19aprobadas/1omisión de empaquetado Mac en Windows, cero fallos. Diff y archivos explícitos revisados; fuentes Apple/core y dependencias conservadas.
- [x] Commit/push a main y tagv1.2.4 en c86454edd63550e642e37676e44ee9e228a045ac, ambos refs remotos comprobados. Workflow [39157077739](https://github.com/fefucho/sideb/actions/runs/39157077739) activado por push del tag sin extraer credenciales.
- [x] Seguir CI Mac y Windows hasta aprobar pruebas/builds y publicación conjunta.
- [x] Verificar release Latest/tag/commit, paquetes/checksums y descargas públicas.
- [x] Registrar resultado real y límites en FIXES/PARIDAD/PLAN-009 y este plan.

## Autenticación y límites

La revisión automática rechazó un intento de reutilizar la credencial guardada de Git para la API. No se extrae ni se persiste esa credencial. El navegador de trabajo no está autenticado; se encontró GitHub disponible para conectar, pero el flujo por tag usa Git Credential Manager y el token de Actions dentro de GitHub, sin requerir una conexión nueva. Un push fallido o CI incompleto no cuenta como publicación.

La confirmación del usuario corresponde a la lógica corregida en0014; la entrega1.2.4 tiene CI y hashes propios verificados. Sin nueva escucha física Mac ni prueba de instalación interactiva. Diagnósticos/prototipos/datos locales quedan en temp o builds ignorados.

## Resultados hospedados

- Preparación117762393511 aprobada: configuración, notas, borrador y tag para la revisión exacta.
- macOS117762442770 aprobado:14pasos exitosos, incluidos flujo numerado de pruebas/generación/build, validación de revisión/versión/hashes, firma/arquitectura y empaquetado/upload. Se comprueban el resultado y pasos públicos de Actions; no se atribuye una lectura local de logs ni un recuento nuevo de pruebas que requieren sesión.
- Windows117762442784 aprobado: verificación/build numerado, revisión/versión/hashes, instalador NSIS sin parche, portable y uploads correctos.
- Publicación117770135630 aprobada. Tagv1.2.4 y target apuntan a c86454edd63550e642e37676e44ee9e228a045ac; release pública Latest, sin prerelease. Versiones anteriores conservadas.
- Descargas públicas nuevas: cinco assets coinciden con sus digests de GitHub y los paquetes coinciden con ambos manifiestos SHA256. Portable Windows contiene exactamente EXE, libmpv, Vulkan y licencia; PE x64/version1.2.4 y tres hashes de runtime conservados respecto de0014. EXE SHA256 `d5a81b2dbf3cd14b8f90c42474fe6a1ccd178e47a2a1e63f85943a1034974b6b`.
- ZIP Mac: Info.plist1.2.4/build17/mínimo15.0 y ejecutable Mach-O arm64 comprobados desde Windows. Firma verificada por CI, sin reejecutar codesign localmente.
- Evidencia local ignorada: `builds/releases/v1.2.4/release-verification.json`, metadatos/jobs y cinco assets en `public/`. Sin ejecutar el instalador ni reemplazar la app abierta.

| Paquete público | SHA256 verificado |
|---|---|
| SideB-macOS.zip | `40a655e8de3cdec0dfd4c49593da932bc049ab1f7ed16b6a0a11ccc8824bf4d5` |
| SideB-Windows-x64-setup.exe | `58a0c9369e349a5c9c9c727f0572c1fad57bf86f5fd1fe71ed08a4c2ee3bd9cc` |
| SideB-windows-x64.zip | `c6a6c5d497eb8058544c1c7b72cdc1bcc348dacc67c95db5ad99a28304efe847` |
