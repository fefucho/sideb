# Release 1.2.2

- Fecha: 2026-10-17 (America/Montevideo).
- Estado: preparación; publicación solicitada explícitamente por el usuario.
- Objetivo: subir fuentes de FIX-207/208 a main y publicar ambos sistemas mediante Release Side B; comprobar paquetes/checksums antes de anunciar éxito.
- Versión:1.2.2/build15, tag v1.2.2, distribución numérica Latest con aviso beta en notas como1.2.1. No reemplazar la release publicada anterior.
- Alcance: volumen wheel Windows FIX-207; ancho/título Explorar y cabeceras desplazables Biblioteca/Búsqueda Apple FIX-208. No modificar core/proveedor/contratos. Conservar prototipos/caché y aplicaciones locales fuera de Git.
- Autorización: pedido «subí la app a GitHub, hacé el release» incluye commit/push/tag/publicación. No requiere otra confirmación. Usar sideb-git para preparar y subir fuentes; release por dispatch del workflow existente.

## Pasos

- [x] Revisar main/remoto y Latest; local/remoto c828d30 sin divergencia, Latest1.2.1. Repo canónico fefucho/sideb; conservar remote histórico redirigido y datos de cuenta.
- [x] Revisar FIX-207/208 y QA previa. Mac build0132/761pruebas y UI aislada parcial aprobados; Windows381frontend/1omisión enMac, check0/0/build frontend aprobados. Son evidencia previa, no binarios1.2.2.
- [x] Actualizar versiones de app/manifests/lock propio, default del workflow y notas1.2.2 sin tocar versiones de dependencias/core.
- [x] Aprobar preflight/checks de publicación y frontend relevante;17 tests runner/release, preflight v1.2.2/build15, frontend381aprobadas/1fixture nativa omitida enMac, check0/0 y build aprobados. Diffcheck limpio; rutas de código/tests/docs explícitas, core y dependencias conservados.
- [ ] Commit con FIX-207/208/209; pushmain y dispatch releasev1.2.2 en la misma revisión. Confirmar draft/tag/Actions.
- [ ] Seguir ambas builds nativas hasta su resultado y corregir fallos concretos si aparecen. No reutilizar paquetes1.2.1 ni reetiquetar build0132.
- [ ] Verificar release publicada, Latest/tag/revisión, tres paquetes descargables y dos checksum files. Descargar y cotejar SHA256; inspeccionar contenido Mac/portable y firma Mac.
- [ ] Cerrar registros con resultados reales, enlace y límites físicos.

## Límites

Mac sigue con firma ad hoc sin notarización. Windows se compila en runner Windows; frontend enMac no demuestra runtime nativo. Cuenta personal, audio audible, instalador interactivo, VoiceOver/trackpad/FPS físicos no se certifican por la release. La build0132 se conserva como prueba previa con versión1.2.1; la release genera binarios1.2.2/build15 desde su commit exacto.
