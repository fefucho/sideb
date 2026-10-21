# Release 1.2.7 — Lyrics Update

- Fecha: 2026-10-21 (America/Montevideo).
- Estado: **publicada como Latest1.2.7/build20**, no prerelease; mantiene aviso beta. Cinco descargas públicas verificadas.
- Autorización: «hace un commit pushealo y release»; la pregunta posterior sobre atribución no cancela la publicación.
- Base: main/origin/main d6e2c4b, actualizado por fetch sin commits remotos pendientes.
- Ámbito: publicar el código compartido acumulado desde1.2.6, Inter Windows y fixes241/242/243; versión1.2.7/build20. PLAN-015 sidebar/topnav sigue sólo planificado.
- Proceso: workflow oficial `.github/workflows/release.yml` desde el commit exacto en main, preflight, borrador, builds numeradas limpias de ambas plataformas, NSIS/portable y ZIP Mac con hashes, publicación conjunta. No sustituir paquetes publicados ni reutilizar la build local1.2.6 como1.2.7.
- Fuentes: commit/tag exacto `a28fb6c1e76975bda196ce9620a736191035f062`, main subido sin force; coautoría Codex incluida. El commit documental de cierre es posterior y no mueve el tag.
- Publicación: [workflow39691913511](https://github.com/fefucho/sideb/actions/runs/39691913511), cuatro jobs success; [release pública](https://github.com/fefucho/sideb/releases/tag/v1.2.7), publicada2026-10-21 23:35:09UTC. Título: Side B1.2.7 — Lyrics Update.

## Pasos

- [x] Revisar status/diff/origin/main y conservar historial saneado; sin cambios Apple/core de implementación en esta sesión.
- [x] Actualizar version.env, manifests Windows y default del workflow; redactar notas con alcance real de ambas plataformas.
- [x] Verificar preflight y pruebas de release, revisar staged por rutas explícitas y privacidad.
- [x] Crear commit con FIX-241/242/243/244 y coautoría Codex; push de main sin force.
- [x] Despachar workflow con v1.2.7 desde el SHA exacto y comprobar tag, builds y publicación conjunta.
- [x] Descargar assets públicos, comprobar hashes/arquitecturas/versiones e instalación seleccionada por actualizador.
- [x] Registrar resultado y límites y subir documentación final.

## Evidencia previa y límites

- Preflight v1.2.7/build20/prerelease=false aprobado. `node --test Scripts/release-config.test.mjs Scripts/build-version.test.mjs`:19aprobadas/1omitida exclusiva Mac,0fallos. Diff y lista explícita revisados; autoría conserva el correo GitHub noreply ya verificado en HEAD y añade `Co-authored-by: Codex <noreply@openai.com>` sin cambiar identidad global.
- build-0020 Windows Release local1.2.6/build19 incluye Inter y FIX-242/243:987aprobadas/20live ignoradas, check0/0, fuentes estables y cuatro hashes comprobados. Pruebas raster9casos karaoke y6combinaciones de blur aprobadas. Es evidencia de prueba del código, no el paquete público1.2.7.
- Último commit remoto d6e2c4b con CI Mac y Windows success; la publicación nueva debe compilar de nuevo el commit exacto y sus nuevas versiones.
- No se certifican audio audible, FPS, cuenta/proveedor real, instalación interactiva ni aceptación humana por compilar. Mac conserva firma ad hoc sin notarizar. Los planes de sidebar oculta y preferencias de versiones explícitas siguen pendientes.
- Credenciales de Git usadas sólo en memoria por las operaciones autorizadas de GitHub; no se publican builds, cachés, capturas del usuario, tokens ni respuestas completas de letras.

## Verificación de publicación

- Workflow39691913511 completo: prepare, Mac arm64, Windows x64 y publicación conjunta success al primer intento. Tag v1.2.7 exacto a28fb6c; no se modifican releases anteriores.
- CI Mac: build-0001 Release1.2.7/build20, initially clean, sourceChangedDuringBuild=false, pasos passed.97InnerTube+169core+239XCTest+454Swift Testing ejecutadas=959aprobadas;10Rust+7Swift live omitidas. El reporte Swift Testing enumera461casos e incluye las7omisiones. Plist1.2.7/build20, arm64 y firma deep/strict aprobados por el workflow.
- CI Windows: build-0001 Release1.2.7/build20, initially clean, sourceChangedDuringBuild=false, pasos passed.431frontend+97InnerTube+169core+171bridge+5player+114Tauri=987aprobadas;20live Rust ignoradas, check0/0. NSIS empaqueta sin recompilar/parchear el EXE verificado; portable con exactamente EXE/libmpv/Vulkan/licencia.
- Descargas públicas sin autenticación: cinco tamaños/digests API/SHA256 correctos. Todos los hashes internos de los manifests CI coinciden con los paquetes públicos:10Mac y4Windows. PE x64 público FileVersion/ProductVersion1.2.7; Mac Info.plist1.2.7/build20 y Mach-O arm64 comprobados desde el ZIP.
- API Latest del repo canónico y del alias SIDE-B-CLIENT-NATIVE usado por versiones instaladas devuelven v1.2.7. La selección de Windows prioriza el único EXE setup, SideB-Windows-x64-setup.exe. No se instala ni ejecuta el paquete para comprobarlo.
- Evidencia local ignorada en `.cache/release-1.2.7/{workflow.json,release.json,diagnostics-summary.json,public-verification.json,diagnostics/,public/}`. Tokens sólo en memoria; diagnósticos y binarios no se agregan a Git.
- Cierre documental posterior a publicar. Aceptación física, audio audible, cuenta/proveedores, FPS y actualización interactiva pendientes. El trabajo concurrente ajeno se conserva fuera de estos commits.

## Assets públicos verificados

| Archivo | Bytes | SHA256 |
|---|---:|---|
| SideB-macOS-SHA256.txt | 82 | e57c8f8bd26ab78f60c0be4f448bcbfab00d69d58c750880d92ae0d5e19d6b93 |
| SideB-macOS.zip | 28712335 | 3f7e9c0345a0e0dd726e79862967ffaa1f34bd3bd6f44405450c2b51d9c2fa70 |
| SideB-Windows-x64-setup.exe | 52163117 | c1ca4a33964022648e9310571d56f9c566d5a939c7d8b19cc5003fd0ddf81b30 |
| SideB-Windows-x64-SHA256.txt | 182 | 5b1ccf0d79011ff4542d99bc9a6cf6b423ba9eb1c065a242a55ca09c7641f607 |
| SideB-windows-x64.zip | 72876134 | 48532dbbba7461fc738981a4075d9c9e680b7f3cc58ebcb70274ca5029ba47b1 |
