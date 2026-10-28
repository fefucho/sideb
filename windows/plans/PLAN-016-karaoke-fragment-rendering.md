# PLAN-016 — Duplicación de palabras durante el karaoke Windows

- Fecha: 2026-10-21 (America/Montevideo).
- Estado: FIX-242 implementado; pruebas automatizadas y visuales Chromium aprobadas. Aceptación nativa de canciones reales pendiente.
- Objetivo: eliminar letras superpuestas/desplazadas durante el relleno y los efectos de palabras, también al envolver a otro renglón; preservar los tiempos y la presentación funcional de Mac.
- Evidencia: capturas del usuario con `Kiss of life` y `Something heavenly led me to you`; el último `you` aparece repetido a la izquierda. No se atribuye al proveedor ni a Inter sin reproducción. Capturas originales fuera del repositorio.
- Ámbito: renderer/medición y pruebas frontend Windows. Consultar `ExperimentalKaraokeText.swift`, `ExperimentalLyricsWordAnchors.swift` y estilo Mac sin editar Apple/core. No implementar la topnav de PLAN-015 ni publicar por este pedido. Conservar cambios locales Inter y registros de builds anteriores.
- Referencias: FIX-240/241, PAR-037 y PLAN-013 Windows. La comparación de píxeles anterior en la fixture Inter fue inconclusa; no equivale a esta regresión validada.

## Pasos

- [x] Reproducir en Chromium real con el componente de producción, reloj controlado, Inter y frases cortas/multilínea, registrando bounds y capturas.
- [x] Contrastar con Mac: una transformación conjunta de base/relleno por fragmento visual, anclas por renglón, límite por vecinos, barrido continuo de palabra y tiempos reales.
- [x] Corregir el renderer Windows sin duplicar glifos ni redistribuir texto/tiempos; mantener fallback, Unicode/RTL, pausa/seek, cambio de fuente/tamaño/ancho, offscreen y accesibilidad.
- [x] Añadir regresión del componente montado en navegador con afirmaciones visuales/geométricas útiles; comprobar antes/después, no sólo cantidad de nodos SVG.
- [x] Ejecutar check/tests/build frontend y registrar FIX/PARIDAD/plan con límites.
- [ ] Aceptación física en WebView2 con las canciones del usuario, pausa/seek/seguimiento y DPI/GPU reales. No se certifican FPS/audio por compilar.

## Resultado y comprobaciones

- Causa reproducida en el componente previo de FIX-240/d6e2c4b: base y relleno fijos más otra copia transformada. El ancla anterior mezclaba renglones. No se atribuye a fuente ni proveedor.
- Windows ahora suprime ambos dibujos fijos del fragmento activo y transforma su base y relleno juntos. Brillo sólo en relleno; ancla inferior por palabra/renglón y crecimiento limitado por vecinos/margen como en Mac. El texto original conserva layout/shaping/AX/selección; las copias decorativas no se seleccionan. No se cambian tiempos ni core.
- `pnpm check`:0/0; `pnpm test`:431 aprobadas/0 omitidas; `pnpm build`:aprobado, aviso de chunk grande conservado.
- Prueba reproducible: desde `windows/`, `node scripts/karaoke-render-browser.mjs`. Usa Edge headless local; `SIDEB_BROWSER` permite seleccionar Chromium. Fixtures de datos sin cuenta ni proveedor. Evidencia ignorada en `.cache/karaoke-render-browser/`.
- 9 casos de shaping/raster: ambas frases, palabra partida en varios renglones, árabe/RTL, hebreo/latín, acentos/emoji, tamaños20–72, escala0,88 y DPR1/1,25/2. Al ocultar sólo el fragmento móvil, sus píxeles de origen quedan vacíos: no queda texto fijo superpuesto. Anclas verificadas contra Range; pausa, seek atrás/final, motion reducido/off, fallback/vacío, cambios de documento/tamaño/ancho, offscreen/reentrada y forced-colors aprobados. Sin errores JS ni tráfico externo; capturas revisadas visualmente.
- Contraprueba con `SIDEB_KARAOKE_COMPONENT` apuntando a la copia anterior local: falla en el primer caso con827píxeles de texto estacionario. Copia y capturas anteriores en `.cache/karaoke-render/`; la última ejecución aprobada queda en `.cache/karaoke-render-browser/results.json`.
- [FIX-242](../../FIXES.md#fix-242), PAR-037; Apple/core intactos. Mac consultado como referencia, sin nueva validación en ese SO. La comparación de píxeles de FIX-241 no acreditaba esta regresión; se conserva ese límite histórico.
- No hay EXE nuevo: build-0018 precede al fix. Build standalone por protocolo oficial cuando se solicite, sin reemplazar builds anteriores. Sin commit/push/release ni implementación de PLAN-015.

## Seguimiento — borde izquierdo del blur, FIX-243

El usuario pidió build y, durante la compilación0019, adjuntó otra captura y precisó que el defecto está en el borde izquierdo de las letras desenfocadas. No se refiere al degradado inferior. La reproducción con `LyricsPanel` real confirma que `content-visibility:auto` corta la pintura al borde del grupo, coincidente con el comienzo del texto.

- [x] Reproducir y comparar contra el mismo grupo con `content-visibility:visible`.
- [x] Mantener optimización y añadir `overflow-clip-margin:24px`, sin alterar el layout del texto ni quitar blur. Apple/core intactos; problema específico de contención CSS Windows.
- [x] Fixture raster de650/310px y DPR1/1,25/2: halo exterior recuperado, sin scroll horizontal ni cambio de bounds/scrollTop al alternar margen de pintura. Capturas anteriores y posteriores revisadas. Scripts/evidencia: `node scripts/lyrics-blur-browser.mjs`, `.cache/lyrics-blur/`.
- [x] Completar build oficial que incluya FIX-242/243 e Inter, verificar metadatos/hashes y entregar carpeta standalone.
- [ ] Probar ambos defectos con las canciones del usuario en WebView2 real. No se certifican audio/fluidez por compilar.

La build0019, iniciada antes del reporte, se conserva como resultado previo al ajuste de borde: `status:compiled`, verify987aprobadas/20live ignoradas. Mientras enlazaba se aplicó FIX-243 después del empaquetado frontend; `sourceChangedDuringBuild:true`. No usarla como prueba de inclusión de FIX-243 ni como entrega final. Se inicia una nueva build con las fuentes de ambos fixes estabilizadas. [FIX-243](../../FIXES.md#fix-243), PAR-037; sin release/commit/push ni implementación de PLAN-015.

## Entrega standalone — build-0020

- `node Scripts/build-version.mjs windows`: verify y compilación frontend/nativa aprobadas. Build final con Inter y FIX-242/243: `builds/windows/build-0020/sideb-windows.exe`, junto a `libmpv-2.dll`, `vulkan-1.dll`, `VulkanRT-License.txt`, `BUILD.json` y `build.log`. Builds anteriores intactas.
- `BUILD.json`: `status:compiled`, `sourceChangedDuringBuild:false`, Release/x64, versión1.2.6/build público19, base d6e2c4b con cambios locales. El contador0020 es local, no cambia la versión pública.
- Verify987aprobadas (431frontend,97InnerTube,169core,171bridge,5player,114Tauri),20live Rust ignoradas; check0errores/0advertencias. Avisos de unused/dead_code,LNK4098 y chunk grande conservados, sin errores.
- Cuatro hashes revalidados y PE x64/versión1.2.6 comprobados. EXE SHA256 `85d7b53e45cef8e10dad0c52708837dbad485e1ceea727c1bf4781f4251e4385`. Pruebas raster anteriores:9casos karaoke y6combinaciones de blur aprobadas.
- Sin abrir la app ni probar cuenta/audio/canciones reales/GPU/DPI/fluidez en WebView2; aceptación del usuario pendiente. Documentación final posterior al empaquetado; sin cambio funcional tras compilar. Sin commit/push/release ni implementación de PLAN-015.
