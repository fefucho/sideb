# PLAN-021 — Indicadores de versión de contenido en Windows

- Fecha: 2026-10-27 (America/Montevideo).
- Estado: FIX-263 y ajuste posterior [FIX-265](../../FIXES.md#fix-265) implementados: E proporcional en metadata secundaria, títulos libres y canción activa fullscreen sinE también en créditos. Barra inferior, cola y Relacionado conservan indicador. Fixture Edge12casos/cuatro alternancias aprobados; build0024 Release compiled/verify1089pruebas aprobadas. QA WebView2/cuenta/Narrator pendiente; reemplaza el pedido anterior de no compilar.
- Objetivo: reconocer el contenido explícito del elemento elegido y de la pista activa con el mismo indicador y significado que macOS, sin cambiar la edición reproducida.
- Alcance: metadata común, DTO/cola de Tauri integrados por el responsable compartido; tipos/controller/proyecciones/caché y presentación Windows.
- Exclusiones: ranking, sustitución de IDs, preferencia de versiones, restricciones parentales, streams y publicación/build standalone.
- Referencias: [PLAN-013 común](../../plans/PLAN-013-explicit-content-indicators.md), [plan Apple espejo](../../apple/plans/PLAN-029-explicit-content-indicators.md), [PAR-040](../../PARIDAD.md), [FIX-262](../../FIXES.md#fix-262). PLAN-014 común continúa separado de este pedido.

## Contrato igual a Mac

`contentRating` distingue `explicit`, `clean` y `unknown`. El booleano heredado `explicit:true` conserva evidencia positiva; `false`, campo ausente o valor futuro permanecen desconocidos. La ausencia de E nunca identifica una versión censurada. El proveedor actual no aporta una fuente positiva comprobada de clean; el UI puede representar ese estado cuando lo reciba, pero no lo fabrica por título, álbum, arte ni proximidad a otra pista.

Presentación inicial (la revisión pendiente la reemplaza): badge de 14×14, radio3, fondo blanco con opacidad0,78 y glifo oscuro `#1c1c1e`. La E usa exactamente el mismo trazado geométrico de macOS: tinta en x4…10/y3…11, centro7,7. No depende de ascenso/descenso de una fuente. Clean confirmado usa L en español y C en inglés; unknown no reserva chip visible y conserva descripción accesible/tooltip.

En la primera entrega, en filas, búsqueda, cabecera de álbum, cola y reproductor el badge antecede al título con separación6. En tarjetas de Inicio y cuadrículas de Biblioteca antecede a la metadata secundaria, como sus celdas Mac; las tarjetas de catálogo/búsqueda/artista y listas de Biblioteca lo muestran antes del título. El título largo se recorta en su espacio y conserva el badge.

## Trabajo

- [x] Revisar metadata/contratos, historial de Home y controles existentes; conservar cambios locales ajenos de navegación horizontal.
- [x] Usar un componente de badge y un título de canción reutilizado por búsqueda, listas, recomendados, cola, barra y fullscreen.
- [x] Etiquetar tarjetas/cabecera de álbum y respetar estados por entidad: un álbum explícito no marca automáticamente cada pista.
- [x] Conservar rating al convertir Home/catálogo/búsqueda a canciones, menús, recientes y payloads de reproducción.
- [x] Conservar rating en caché Home y recientes con migración compatible. Las copias de snapshots/colecciones retienen metadata y cada ocurrencia original.
- [x] Hidratar evidencia conocida sólo para el mismo videoID/namespace y contexto de cuenta. Los snapshots sin badge no borran evidencia conocida; cambio de edición/cuenta no la hereda. Sin búsqueda nueva por fila ni caché global.
- [x] Compartir recursos editoriales ES/EN con Mac y generar catálogo Windows por su script oficial.
- [x] Probar ausencia/legacy/valor futuro, equivalencias por ID, pares clean/explicit, elección manual, duplicados, snapshots/cambio de cuenta y persistencia de recientes.
- [x] Verificar Edge con componentes reales, fuentes locales, títulos largos, reciclado explicit→unknown→clean, ES/EN, DPR1/1,5/2 y forced-colors. Datos/RPC sintéticos, sin cuenta/audio.
- [ ] Revisar cuenta real y WebView2, Narrator, escalado nativo y confirmación humana de ambas interfaces. No cerrar PAR-040 por un frontend o una compilación.

## Evidencia y límites

- `windows/scripts/content-rating.test.mjs`: seis regresiones de contratos/elección/persistencia/contexto.
- `windows/scripts/content-rating-browser.mjs`: fixture real de `FeaturedTrackTitle`, `MediaCard` y `HomeCard`;12combinaciones de estado/idioma/DPR, glifos centrados7,7 y chips14×14, sin desborde o errores de navegador. Forced colors con colores de sistema contrastantes. Evidencia local ignorada en `windows/.cache/content-rating-browser/{results.json,explicit-dpr-1.png,explicit-dpr-1.5.png,explicit-dpr-2.png}`.
- Comprobaciones finales: `pnpm check`0errores/0advertencias; `pnpm test`491aprobadas/0fallos; `pnpm build`aprobado, advertencia de chunk grande existente. `node windows/scripts/sync-localizations.mjs --check`:801claves compartidas verificadas. Diff propio sin errores de whitespace.
- Integración nativa comprobada por responsable compartido:117tests Tauri y5player aprobados; core/InnerTube112/175 y bridge177. No se generó una build standalone. La fixture valida DOM/layout/interacción de componentes reales; no equivale a una prueba de datos de la cuenta ni a una build nativa Mac/Windows.
- Registrar resultado compartido en FIX-262/PAR-040 y conservar PLAN-014 separado: sigue siendo posible elegir deliberadamente cualquier edición.

## Cierre de integración

Verificador oficial `windows/scripts/windows.ps1 -Action verify` aprobado sobre las fuentes finales:1077pruebas (491frontend,112InnerTube,175core,177core/windows-bridge,5player,117Tauri),0fallos y20ejecuciones live ignoradas. Check0/0 y build frontend aprobados; sin standalone nuevo. Log local ignorado: `.cache/explicit-content-verify.log`. La compilación de tests y las fixtures de navegador no sustituyen QA con cuenta/WebView2/Narrator ni validación Mac.

## Revisión visual — segunda línea y fullscreen, FIX-263

La revisión se aplicó con [FIX-263](../../FIXES.md#fix-263), siguiendo la ubicación y medidas de PLAN-013. `FeaturedTrackTitle` ya no compone insignias; `ArtistCredits` las antepone a artista/álbum, incluso si sólo se conoce el rating y faltan los créditos. `MediaCard`, cabeceras y búsqueda trasladan el rating de su propia entidad a la metadata secundaria. `CollectionHeader` desconocido sin créditos no reserva una fila vacía.

- [x] Trasladar badges desde título/cabecera a metadata secundaria; conservar enlaces/acciones/truncado y alturas existentes.
- [x] Lado `clamp(round(fontSizeSecundario×0,85),9,12)`, gap4; SVG viewBox14 y radio3/14 escalados, colores y centro7,7 conservados. CSS hereda el tamaño real de los créditos, sin calcular desde el título.
- [x] Título grande fullscreen sin E; metadata secundaria, cola y filas de Relacionado mantienen un indicador por entidad. Sin supresión global desde el contenedor fullscreen.
- [x] Barra inferior conserva el badge en su segunda línea; no se alteró su visibilidad ni selección de audio.
- [x] Verificar DOM real con enlaces artista/álbum y acción del título; reciclado explicit→unknown→clean→explicit, metadata ausente y cabecera unknown sin espacio reservado.
- [x] Verificar Edge con componentes reales: metadata10/11,5/13/17,5, tarjetas/cabecera/Home, títulos largos, ES/EN, DPR1/1,5/2 y forced colors. Cuatro cambios true/false de fullscreen conservan ID/rating: barra, fullscreen, QueuePanel y RecommendedSongRow reales muestran badges secundarios; todos los títulos permanecen libres.
- [ ] QA humano en WebView2/Narrator y comparación visual de las mismas escenas en Mac/Windows. Las capturas sintéticas no confirman apariencia nativa, audio ni accesibilidad con lector real.

### Evidencia de esta revisión

- `node --test windows/scripts/content-rating.test.mjs windows/scripts/content-rating-layout.test.mjs`:7pruebas aprobadas;6contratos previos y1regresión DOM nueva con los escenarios descritos.
- `node windows/scripts/content-rating-browser.mjs`:12combinaciones aprobadas, forced colors y cuatro cambios de fullscreen; errores de navegador vacíos. Fixture real Svelte/Edge con datos/RPC sintéticos, sin cuenta ni reproducción. Vite sólo transforma módulos de prueba en memoria; no se ejecutó build del producto, runner Windows, Cargo ni EXE.
- Capturas locales ignoradas y JSON geométrico: `windows/.cache/content-rating-browser/explicit-dpr-{1,1.5,2}.png` y `results.json`. Captura DPR1 inspeccionada visualmente: chips antes del artista, títulos libres y centrado proporcional.
- Diff propio sin errores de whitespace. Los cambios concurrentes de barra/marquee y navegación horizontal se conservaron. El integrador revisa `FeaturedTrackTitle` al compartir archivo con ese trabajo.
- La evidencia anterior de pnpm/check/suite completa/build corresponde a FIX-262. No se ejecutaron de nuevo por el límite explícito de no compilar y por el trabajo concurrente de otras funciones.
