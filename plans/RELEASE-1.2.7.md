# Release 1.2.7 — Lyrics Update

- Fecha: 2026-10-21 (America/Montevideo).
- Estado: preparación autorizada; commit/push y publicación pendientes.
- Autorización: «hace un commit pushealo y release»; la pregunta posterior sobre atribución no cancela la publicación.
- Base: main/origin/main d6e2c4b, actualizado por fetch sin commits remotos pendientes.
- Ámbito: publicar el código compartido acumulado desde1.2.6, Inter Windows y fixes241/242/243; versión1.2.7/build20. PLAN-015 sidebar/topnav sigue sólo planificado.
- Proceso: workflow oficial `.github/workflows/release.yml` desde el commit exacto en main, preflight, borrador, builds numeradas limpias de ambas plataformas, NSIS/portable y ZIP Mac con hashes, publicación conjunta. No sustituir paquetes publicados ni reutilizar la build local1.2.6 como1.2.7.

## Pasos

- [x] Revisar status/diff/origin/main y conservar historial saneado; sin cambios Apple/core de implementación en esta sesión.
- [x] Actualizar version.env, manifests Windows y default del workflow; redactar notas con alcance real de ambas plataformas.
- [x] Verificar preflight y pruebas de release, revisar staged por rutas explícitas y privacidad.
- [ ] Crear commit con FIX-241/242/243/244 y coautoría Codex; push de main sin force.
- [ ] Despachar workflow con v1.2.7 desde el SHA exacto y comprobar tag, builds y publicación conjunta.
- [ ] Descargar assets públicos, comprobar hashes/arquitecturas/versiones e instalación seleccionada por actualizador.
- [ ] Registrar resultado y límites y subir documentación final.

## Evidencia previa y límites

- Preflight v1.2.7/build20/prerelease=false aprobado. `node --test Scripts/release-config.test.mjs Scripts/build-version.test.mjs`:19aprobadas/1omitida exclusiva Mac,0fallos. Diff y lista explícita revisados; autoría conserva el correo GitHub noreply ya verificado en HEAD y añade `Co-authored-by: Codex <noreply@openai.com>` sin cambiar identidad global.
- build-0020 Windows Release local1.2.6/build19 incluye Inter y FIX-242/243:987aprobadas/20live ignoradas, check0/0, fuentes estables y cuatro hashes comprobados. Pruebas raster9casos karaoke y6combinaciones de blur aprobadas. Es evidencia de prueba del código, no el paquete público1.2.7.
- Último commit remoto d6e2c4b con CI Mac y Windows success; la publicación nueva debe compilar de nuevo el commit exacto y sus nuevas versiones.
- No se certifican audio audible, FPS, cuenta/proveedor real, instalación interactiva ni aceptación humana por compilar. Mac conserva firma ad hoc sin notarizar. Los planes de sidebar oculta y preferencias de versiones explícitas siguen pendientes.
- Credenciales de Git usadas sólo en memoria por las operaciones autorizadas de GitHub; no se publican builds, cachés, capturas del usuario, tokens ni respuestas completas de letras.
