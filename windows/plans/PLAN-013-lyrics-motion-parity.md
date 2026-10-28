# PLAN-013 — Paridad Windows de letras y carátulas animadas

- Fecha: 2026-10-21 (America/Montevideo).
- Estado: **implementado; build nativa Windows aprobada, aceptación física pendiente**. [FIX-240](../../FIXES.md#fix-240), build-0017 x64 Release desde `d6e2c4b`,1.2.6/build público19,987pruebas aprobadas,fuentes estables y cuatro hashes revalidados. Sin arranque/cuenta/audio ni QA visual nueva; los resultados de origen Mac y sus límites se conservan abajo.
- Objetivo: llevar a Windows la experiencia vigente de Mac: letras nuevas por defecto, Original con el mismo diseño y respaldo automático, ajustes y seguimiento coherentes, seek fiable y carátulas animadas con carga imperceptible sobre la imagen estática.
- Referencia: fuentes actuales de Mac y build0155 Release, FIX-228 a FIX-239; [PAR-037/038/039](../../PARIDAD.md). El core rico y el proveedor de vídeos ya son compartidos. La build de Mac y sus pruebas no validan Windows.
- Ámbito: integración Tauri/libmpv, controllers TypeScript, fullscreen Svelte, Apariencia e idiomas ES/EN. Preservar los cambios locales existentes, cola nativa, cuenta, sidebar, Genius y resto de preferencias.
- Exclusiones: cambios a Recomendados, rediseño de sidebar, publicación/push, implementación de los planes generales de [indicadores explícitos](../../plans/PLAN-013-explicit-content-indicators.md) y [preferencia de versión](../../plans/PLAN-014-content-version-preference.md). Este PLAN-013 pertenece a `windows/plans/`, no sustituye al PLAN-013 general.
- Validación diferida: el usuario canceló el A/B de rendimiento Mac y confirmó funcionamiento de las carátulas. No reactivarlo ni convertirlo en requisito de este port. No hay FPS certificados. La futura aceptación visual/funcional nativa Windows se detalla abajo; cualquier perfil instrumental adicional se acuerda por separado.

## 1. Punto de partida comprobado

| Área | Mac vigente | Windows actual | Trabajo necesario |
|---|---|---|---|
| Datos de letras | Documento rico, palabras, voces, traducciones e instrumental; clásico conservado | `get_lyrics` y DTO sólo por líneas | Exponer y consumir la API rica aditiva existente |
| Panel nuevo | Predeterminado; menú superpuesto; Karaoke/Lectura | `LyricsPanel.svelte` clásico; sin renderer rico | Documento preparado, reloj local, renderer y menú |
| Original y fallback | Misma presentación y estado compartido con nuevo, FIX-239 | Diseño anterior, base25,2px/peso500 | Unificar estilo, controles y selección efectiva |
| Manual/blur | Scroll manual quita todo blur contextual hasta Volver/clic/nueva ocurrencia | Seguimiento básico y Volver; sin contrato nuevo | Estado común explícito y cancelación de centrados obsoletos |
| Seek | Target absoluto, revisión, ocurrencia, adopción y resultado medido | Sólo `seconds`; rechaza carga/ausencia de duración y publica target sin confirmar audio | Adaptar FIX-233/234 al estado real de libmpv |
| Motion | Vídeo local sobre imagen, políticas nativas y liberación tras30s | H.264 local, toggle/caché/cancelación/primer frame ya implementados | Completar ciclo nativo, carrera de clear y validación real WebView2 |

Hallazgos de destino: `commands/lyrics.rs` y `player/lyrics.ts` no consumen `get_karaoke_lyrics`; `lyricsMode = synced/genius` selecciona un panel/proveedor y **no** equivale a Karaoke/Lectura. `lyricSeekSeconds` exige duración positiva. `seek_playback` no recibe identidad esperada, rechaza un item aún no adoptado y asigna `pb.position = seconds` al aceptar el comando. En motion, `document.hasFocus()` no representa oclusión; el controller no libera el asset por inactividad. El coordinador de clear captura consumidores existentes, pero el componente no bloquea un montaje nuevo durante el borrado.

## 2. Contrato y arquitectura

### Datos compartidos y frontera Tauri

- Reutilizar `SideBCore.get_karaoke_lyrics(video_id, title, artist, album, duration_secs?, force_refresh)` y los records `KaraokeLyricsInfo`, `KaraokeLineInfo` y `KaraokeWordInfo`. Mantener `get_lyrics` y su consumidor como fuente Original/respaldo. No duplicar providers, parser TTML o caché en TS.
- Añadir comando/DTO camelCase, registro Tauri y tipos/cliente TS juntos. Conservar provider, isSynced, instrumental, líneas con timeMs/endTimeMs/text/words/translation/role/agent/groupId/section y palabras con text/startMs/endMs. Mantener opcionales, cero y texto exacto.
- Tiempos de letras en **milisegundos**; duración de solicitud y seek de audio en **segundos**. Probar el recorrido record real → JSON → TS → target, además de helpers aislados; ningún cast puede convertir ausencia en cero o un cue válido en subnormal.
- Core conserva caché `karaoke:v4`, firma de metadata/duración y ajuste, TTL diferenciados y provisional60s sin duración; un fallo no equivale a ausencia. Límites actuales:2MiB,5.000líneas,2.048segmentos/línea y50.000totales. No modificar core por una necesidad exclusiva Windows.

### Controllers y propiedad del estado

- Un controller rico separado coordina solicitudes y prepara el documento fuera del trabajo por frame. Identidad: sesión/cuenta + ocurrencia nativa/entryId + revisión + video + firma de metadata/duración. Repetir el mismo vídeo en la cola debe crear otra ocurrencia; no usar sólo videoId.
- Activar el consumidor rico cuando fullscreen muestra Letras y no Genius; invalidarlo al salir/cambiar cuenta. Conservar el flujo clásico existente: Mac también lo solicita fuera del panel. Cancelación integral de red clásico/rico no está implementada en Mac y no es una condición ficticia de paridad.
- Refresh de la misma ocurrencia conserva documento válido y lectura manual durante carga/error recuperable. Metadata o duración tardía permite nueva resolución sin aceptar respuestas de otra ocurrencia. Distinguir loading, refresh, error, ausencia e instrumental.
- Modelo de presentación compartido por Original/nuevo, local al host fullscreen: tamaño, Karaoke/Lectura y seguimiento. El tiempo y las actualizaciones por frame pertenecen a hijos locales, nunca a ese modelo ni a `+page.svelte`.
- Preparar documento/secuencia/índices/segmentos una vez por revisión; invalidar geometría por texto/fuente/ancho/traducción. No guardar layouts obsoletos ni medir cada palabra durante cada frame.

## 3. Selección, fallback y ajustes idénticos

Separar **preferencia de fuente** (nuevas/Original/Genius) de **renderer efectivo** (rico/clásico/estado). Nuevas es la preferencia inicial. Genius conserva prioridad, funciones y suspensión del rico.

| Situación | Resultado |
|---|---|
| Rico válido | Mostrar nuevo; un instrumental válido tiene su propio estado |
| Rico esperando/ausente/error, clásico actual disponible | Mostrar Original con el mismo estilo y controles comunes; mantener preferencia nuevas |
| Rico llega después del clásico | Reemplazar suavemente sin perder tamaño, modo ni manual de la misma ocurrencia; sin texto de la pista anterior |
| Refresh con rico válido | Mantener el documento visible; indicar refresh sin vaciarlo |
| Usuario elige Original | Mantener Original hasta volver a nuevas; no forzar cambio por respuesta tardía |
| Sin documentos válidos | Estado claro loading/ausencia/error con menú accesible y retry apropiado |

El menú debe describir el renderer visible. En respaldo automático, ofrecer intentar nuevas/reintentar según estado; no invertir una preferencia invisible ni mostrar una acción que lleva al mismo panel por error. Deshabilitar la acción mientras ya está en curso.

| Ajuste | Paridad requerida | Vida del estado |
|---|---|---|
| Karaoke/Lectura | Mismos modos en nuevo y Original; Karaoke inicial | Compartido mientras vive el host fullscreen, también al cambiar pista |
| Tamaño |36 inicial;20…48, paso2 | Igual que modo; sin saltos al usar fallback |
| Seguimiento/manual | Compartido por los dos renderers | Se conserva al cambiar renderer/refrescar la misma ocurrencia; nueva ocurrencia reinicia automático |
| Movimiento de palabras | ON inicial; sólo efectos sobre timing real | Local al montaje rico, como Mac; no inventar persistencia global |
| Traducciones | ON inicial; control cuando existen | Local al montaje rico |
| Desfase |−5…+5s, paso100ms y reset0 cuando hay timing; positivo adelanta letras | Local al rico; nueva ocurrencia/montaje parte de0 |
| Proveedor/timing | Informativo y exacto; refresh forzado; volver a Original/nuevas | Según fuente efectiva y datos disponibles |
| Carátulas animadas | Toggle Apariencia ON inicial, indicación «cuando estén disponibles», tamaño/borrado de caché y errores | Preferencia persistente existente, ES/EN |

Los controles de letras van en menú de tres puntos superpuesto arriba a la derecha, también desde Original/loading/error/empty. No añadir cabecera ni footer de proveedor que reduzcan el viewport. Original conserva timing por línea: no simular palabras, traducciones o voces que no existen. Configuración conserva color/fondo sólido, sidebar lista/cuadrícula e idioma; abrir Settings no prepara ni descarga vídeos.

## 4. Diseño común y reglas de blur

Implementar tokens/helpers comunes para ambos renderers. Referencias de producción: `ExperimentalLyricsStyle.swift`, `ExperimentalLyricsPanel.swift` y bloque clásico de `FullscreenNowPlayingView.swift`; cotejar su estado al ejecutar el plan.

| Propiedad | Referencia Mac que debe reproducirse en Windows |
|---|---|
| Texto principal |36 por defecto; Karaoke bold/700 y tracking−0,18; Lectura medium/500 y tracking0 |
| Leading | Altura objetivo1,25×fuente; compensar métricas reales sin aplicar dos veces el leading de SwiftUI |
| Fondos/traducciones | Fondos max(18;0,68×fuente); traducción max(13;0,57×tamaño de fila) |
| Contexto | Blanco opacidad0,40;0,78 con contraste aumentado; escala0,98 o1 con Reducir movimiento |
| Palabra activa sin iluminar | Opacidad base0,70;0,86 con contraste aumentado |
| Blur contextual | Distancia1→1,2;2→2,1;≥3→3. Distancia visual saturada a3 |
| Condición de blur | Sólo Karaoke + seguimiento automático + distancia>0 + sin Reducir movimiento/contraste aumentado |
| Foco/efectos | Transición0,788s sin cambiar geometría; quitar blur manual inmediatamente. Barrido continuo, feather≤30; sostenidas escala≤1,13/lift≤2/glow radio≤5 sólo mientras activas |
| Ancho/padding | Laterales32 si viewport≥330,20 si menor; Karaoke reserva48 extra para efectos, Lectura no; sin ampliar artificialmente el ancho de shaping |
| Filas/grupos | Padding vertical10 Karaoke/8 Lectura; separación interna de grupo8; stack externo0 |
| Extremos/máscara | Karaoke sincronizado: medio viewport arriba/abajo; otros12. Fade superior48/inferior88; máscara rectangular con contraste aumentado |
| Controles | Menú overlay trailing8; Volver bottom12; mismo viewport útil y alineación que Mac |

Comparar unidades lógicas y escalado Windows100/125/150/200%, no equiparar píxeles físicos con puntos. La fuente de Mac es de sistema: resolver la familia y métricas disponibles en Windows con comparación visual. No declarar identidad tipográfica sólo porque ambos usan `system-ui`; registrar cualquier diferencia residual. Mantener el texto seleccionable/accesible y shaping nativo; no separar cada sílaba en cajas flex que rompan ligaduras/RTL/wrapping. El barrido debe continuar entre fragmentos de una palabra partida en varias líneas.

| Evento | Seguimiento y blur |
|---|---|
| Rueda, trackpad, arrastre de scrollbar, touch o navegación de scroll con teclado | Entrar en manual antes del siguiente centrado; retirar blur de todas las filas inmediatamente, incluidas las pasadas |
| Avanza audio durante manual | Actualizar foco/tiempos sin centrar ni reponer blur; opacidad/escala contextual siguen su diseño |
| Resize, fuente, traducción, modo, refresh o llegada tardía del rico | Conservar manual; invalidar callbacks/mediciones de centrado anteriores |
| Volver | Reanudar automático y centrar frase actual; blur vuelve sólo si lo permiten modo/accesibilidad |
| Clic en letra con cue válido | Reanudar seguimiento y solicitar seek identificado; reconciliar contra audio real |
| Nueva ocurrencia, incluso mismo videoId | Reiniciar seguimiento y desfase; conservar tamaño/modo del host |
| Lectura, Reducir movimiento o contraste aumentado | Blur0 aunque siga automáticamente |

Distinguir scroll programático de interacción manual para que un centrado propio no se cancele a sí mismo. Un timer nunca puede reactivar seguimiento. Conservar posiciones/anclas válidas al intercambiar rico/clásico; no forzar scroll al fondo ni completar líneas antes de su primer tiempo.

## 5. Documento rico, reloj y seek reales

- Conservar roles/agentes/grupos/secciones y orden de presentación. Lead gobierna el ancla; fondos tardíos no retroceden scroll. Todas las voces simultáneas mantienen sus tiempos y pueden animarse.
- Reconciliar segmentos con el texto Unicode exacto. Ante detalle inválido, usar presentación legible por línea, conservando el texto; no inventar tiempos. Probar emoji/ZWJ, marcas combinadas, CJK, RTL, ligaduras, espacios y puntuación.
- Intro/interludio/outro con tres puntos sólo en huecos demostrables≥5.000ms de la unión de **todas** las voces. Líneas sin tiempo son barreras; outro requiere duración final conocida. Instrumental no se confunde con vacío/error.
- Reloj anclado a posición observada de libmpv, ocurrencia y revisión de seek. Los eventos actuales pueden espaciarse200ms: resolver fronteras cortas y, si se usa interpolación, acotarla entre muestras reales, reconciliar cada observación y congelarla en pausa/buffering/muestra obsoleta/seek pendiente. No sustituir audio por un contador `Date.now()` independiente.
- Animación local de filas activas visibles, hasta60Hz cuando corresponde y30Hz en ahorro/interludios según la política Mac; estática en pausa/oculto/seek pendiente y contexto terminado. Conservar detección de fronteras aun con pulso detenido. Evitar RPC por frame, `timeupdate` global, stores de toda la app a60Hz, recomposición completa por tick y lectores de geometría intercalados con escrituras.
- Target común: `max(0, (lineMS - offsetMS) / 1000)`. Limitar arriba sólo con duración finita positiva conocida; duración desconocida permite seek absoluto válido. Duración VOD adoptada prevalece sobre rangos provisionales casi vacíos.
- Ampliar el contrato de seek de manera compatible con scrubbing y demás consumidores: identidad de cuenta/ocurrencia/generación esperada, revisión y target pendiente. Rechazar invocaciones tardías para otra pista antes de mutar libmpv. La cola nativa sigue siendo autoritativa.
- Último clic gana; callbacks viejos no modifican pista/documento actual. Si la canción restaurada todavía resuelve/adopta su item, conservar sólo el último cue de esa ocurrencia y aplicarlo al item correcto. Preservar pausa cuando el item está cargado.
- Separar intención de posición observada: un RPC aceptado no demuestra que mpv llegó al target. Resolver completion/fallo/deadline/cancelación con evidencia real del motor, incluso pausado; reconciliar foco/seguimiento sin pisos de tiempo ni compensaciones arbitrarias. Portar comportamiento, no APIs AVPlayer.

## 6. Carátulas animadas: completar lo existente

Reutilizar `commands/animated_artwork.rs`, `artwork/{animated,controller,policy,clearCoordinator}.ts` y `AnimatedArtwork.svelte`. Ya existen toggle/caché, cancelación, leases, debounce300ms, H.264 local, metadatos, callback de primer frame y fade225ms. No reescribir el proveedor compartido ni presentar ese código como pendiente de creación.

- Mantener imagen estática debajo en todo momento; vídeo sobre ella, sin alterar geometría/radio, sin capturar input ni tapar acciones. Mostrar vídeo sólo tras primer frame presentable de la solicitud vigente. El fallback `requestAnimationFrame` con HAVE_CURRENT_DATA necesita comprobación WebView2: no garantiza por sí mismo composición visible. Error/ausencia/timeout vuelve a imagen sin flash negro, spinner ni error intrusivo.
- Elegir la mejor representación nativa hasta1080×1080 y60fps si existe fuente; no imponer768/30, reescalar para aparentar más calidad, interpolar frames ni duplicar descargas preventivas. Windows usa H.264 compatible; Mac prefiere HEVC con un fallback H.264. Fuente real comprobada After Hours1080HEVC30: no afirmar prueba de fuente60 ni H.264 Windows sin comprobarlo.
- Un vídeo local completo, máx128MiB/60s; scope asset existente y CSP restringidos. No enviar URL firmada al frontend ni añadir streaming remoto en paralelo. Caché común150MiB, positivos30d/ausencia válida7d, single-flight, cancelación/leases, `.part` atómico y LRU protegidos se conservan. Borrar caché de vídeo elimina archivos propios y parciales, conservando veredictos y sin relanzar la descarga del consumidor actual.
- Mismo álbum reutiliza asset/player; otro álbum retira la animación anterior enseguida. Identidad de álbum/sesión separada de ocurrencia de canción. Pausa/reverso/ocultamiento detienen vídeo; OFF/cierre/cuenta/Reducir movimiento/presión de memoria y condiciones nativas de energía que lo requieran liberan recursos.
- Añadir un único deadline cancelable de30s de inactividad tras pausa/ocultamiento/reverso para liberar decoder, fuente local y lease. Al volver, reutilizar caché si existe y revelar con la misma transición; no multiplicar timers ni dejar descargas frías esperando.
- Reemplazar la equivalencia foco=visibilidad por estado nativo coherente de ventana visible/minimizada/ocluida. Una ventana visible sin foco no es automáticamente invisible. Integrar energía/memoria mediante señales nativas disponibles, sin polling agresivo; documentar limitaciones si Windows no ofrece una señal equivalente a thermal de Mac, sin fingir paridad.
- Cerrar carrera de clear: impedir nuevas preparaciones desde que comienza el borrado, incluidos consumidores que se montan después de capturar los actuales. Detach `pause/remove src/load`, cancelar callback/deadline y esperar liberaciones antes de borrar archivos; mantener bloqueo del mismo consumidor hasta nuevo álbum/reapertura, como Mac. Probar handles Windows y account/session swap durante cancelación.
- FIX-238 ya llega del core: versiones oficiales compatibles, hasta3 alternativas a un salto, título/artista/trackcount y exclusión de remaster/deluxe/live incompatibles; `negative_schema:2` invalida negativos anteriores conservando positivos. Comprobar Graduation censurado/explícito sin usar la portada para decidir qué audio reproducir. Ausencia válida se ignora; fallo transitorio no se cachea como ausencia de7d ni se reintenta en cada tick.
- Sidebar, miniaturas y backdrop mantienen imágenes estáticas. Sólo la carátula fullscreen elegible posee decoder; Settings y secciones ocultas no deben crear otros consumidores.

## 7. Ejecución por etapas

- [x] Auditar Mac/Windows y antecedentes con integrador y subagentes Luna/6.1Sol medio de sólo lectura; distinguir código existente de brechas. Sin pruebas/build/GUI en esta etapa.
- [x] **A — Contratos y fixtures:** fijar referencia Mac actual y casos clásicos/ricos/voces/instrumental/Unicode; identificar entryId/generation/cuenta y observaciones mpv. Capturar geometría equivalente como referencia visual, sin reactivar el perfil Mac cancelado.
- [x] **B — Bridge y carga:** DTO/comando/TS rico, controller con revisiones y documento preparado; conservar clásico/Genius y estados de refresh/fallback. Probar contratos y respuestas tardías antes de renderer.
- [ ] **C — Audio (código y tests aislados implementados; falta comprobar libmpv real):** seek identificado y diferido por ocurrencia, confirmación real y reloj local; verificar pausado, duración desconocida y adopción. Revisar scrubbing y controles existentes.
- [x] **D — Presentación:** tokens/componentes comunes, menú completo, nuevo por defecto, Original idéntico, fallback sin salto, reglas manual/blur, voces/interludios y shaping. Acotar montaje/actualizaciones al viewport sin romper medidas, selección, foco o accesibilidad.
- [ ] **E — Motion y Settings (ciclo/políticas implementados; cierre nativo y límites de oclusión pendientes):** cerrar clear/30s/políticas nativas, verificar calidad/primer frame/loop y mismos ajustes ES/EN. Conservar proveedor y caché compartidos.
- [ ] **F — Integración y entrega (diff/frontend/contratos revisados; verify/build Windows pendientes):** revisión completa del código de subagentes, matriz siguiente, verify/build oficial Windows y documentación con evidencia real y límites. No cerrar paridad antes de validar destino.

Delegación futura: Luna para DTOs/tipos/fixtures/menús localizados bien acotados;6.1Sol medio para renderer/shaping, reloj/seek libmpv y ciclo de vídeo/clear. Un solo propietario por archivos compartidos; el integrador revisa todos los diffs y cruces de contrato antes de integrarlos. No editar Apple ni core salvo problema común comprobado y registrado.

Mapa de archivos previsto: `src-tauri/src/commands/{lyrics,playback,animated_artwork}.rs`, registro/estado Tauri y adaptador de player; `src/lib/types.ts`, `player/{lyrics,controller}.ts`, composición `routes/+page.svelte`; `components/fullscreen/{FullscreenNowPlaying,LyricsPanel,AnimatedArtwork}.svelte`; `artwork/*`, `HomeSettings.svelte`, preferencias y catálogo. Nuevos módulos de documento/reloj/presentación/renderer rico bajo `src/lib/player/` y `components/fullscreen/` se nombrarán al ejecutar; no agregar lógica por frame a la composición raíz.

## 8. Matriz de aceptación y cierre

| Grupo | Casos y resultado exigido |
|---|---|
| Contrato | Records reales con3418ms y otros cues distintos, null/0, segmentos/voces/Unicode; JSON sin pérdidas; ms→s correcto; clásico sigue compatible |
| Carga | A→B→A, cuenta nueva, dos ocurrencias del mismo video, duración/metadata tardía, refresh/error recuperable, ausencia e instrumental; ninguna respuesta vieja ni texto de otra pista |
| Selección/opciones | Nuevas inicial; rico ausente usa clásico idéntico; rico tardío conserva tamaño/modo/manual; Original explícito no cambia solo; Genius prioritario; menús coherentes en todos los estados |
| Blur/manual | Rueda/trackpad/scrollbar/teclado quitan inmediatamente todo blur contextual en ambos renderers; reloj/refresh/resize/cambio de fuente no lo restauran; Volver/clic/nueva ocurrencia sí; Lectura/accesibilidad siempre blur0 |
| Diseño | Comparación Mac/Windows a área lógica equivalente, tamaños20/36/48, ancho estrecho/amplio y DPI100/125/150/200%; mismas métricas, máscara, alineación y controles; sin salto al fallback |
| Texto rico | Palabra repartida en líneas, ligaduras/RTL/CJK/emoji, voces solapadas y fondos tardíos, gaps≥5s, barrera sin tiempos/outro conocido; sin aplanar voces ni romper wrapping |
| Audio/seguimiento | Al menos5cues distintos adelante/atrás, clics rápidos, play/pausa, duración desconocida, restaurado sin item, seek fallido, pista/cuenta cambiada y scrubbing; comprobar cue enviado **y posición observada**, foco correcto y último clic ganador |
| Recursos | Pausa/hidden/salida desmontan animación local cuando corresponde; sin RPC/red por frame, suscripción global60Hz ni layout de todas las filas por tick; scroll ya cargado funcionalmente fluido en WebView2 y sin scroll al fondo |
| Motion | Sin vídeo/404/transitorio, archivo malformado, cache hit/frío, primer frame tardío, cambio álbum y misma carátula entre pistas, pausa/reverso/30s, minimizar/ocluir/sin foco, OFF/ON/Reduce Motion, energía/memoria, sesión cambiada, clear concurrente y mount durante clear; sin flash/sonido propio/corte de música/archivo bloqueado |
| Settings | Toggle y preferencias existentes sobreviven reinicio; ES/EN y teclado/accesibilidad; tamaño de caché/error/borrado correctos; Settings abierto no descarga vídeo |

Pruebas a ampliar: `windows/scripts/lyrics-controller.test.mjs`, pruebas de componente/renderer y fixtures nuevas, `animated-artwork-{policy,component}.test.mjs`, tests Rust Tauri/estado del reproductor y tests de seek del adaptador mpv. Pruebas con RPC simulado no sustituyen audio/primer frame reales. No reutilizar los conteos históricos412/1 ni las suites Mac como resultados de esta implementación.

Al implementar, ejecutar `pnpm check`, `pnpm test` y `pnpm build` dentro de `windows/`; luego `windows/scripts/windows.ps1 -Action doctor` y `-Action verify` en Windows. Para entrega local, aplicar la [skill oficial Windows](../../.agents/skills/sideb-build-windows/SKILL.md) y desde raíz usar `node Scripts/build-version.mjs windows` en Windows x64/MSVC/WebView2. Conservar EXE, libmpv, Vulkan y licencia juntos en la build numerada; comprobar `BUILD.json`, hashes y estabilidad de fuentes. No compilar Windows desde Mac como sustituto ni entregar EXE aislado.

Cerrar con FIX Windows real y actualizar **las mismas PAR-037/038/039**, este plan e índice: qué funciona, pruebas ejecutadas, build exacta y diferencias/aceptación nativa pendientes. No crear otro backlog de paridad ni marcar completo por compilar. No publicar, hacer push, incrementar versión pública o probar mutaciones de cuenta real por este plan. Distinguir validación visual/funcional, CPU y FPS/hitches; no certificar «sin lag» mediante tests unitarios, tasa del vídeo o compilación.

## Referencias de implementación

- [Guía acumulada de letras y seek](../../PARIDAD.md#lyrics-windows-handoff), [guía de motion](../../PARIDAD.md#animated-artwork-handoff) y [FIXES](../../FIXES.md).
- [PLAN-025 Mac](../../apple/plans/PLAN-025-word-synced-lyrics.md), [PLAN-026 Mac](../../apple/plans/PLAN-026-fullscreen-lyrics-performance.md), [reporte de ejecución de letras](../../apple/plans/research/LYRICS-PLAN026-RESULTS-2026-10-21.md).
- [PLAN-012 compartido motion](../../plans/PLAN-012-animated-artwork.md), [evidencia del proveedor](../../plans/research/ANIMATED-ARTWORK-2026-10-21-results.md), [cancelación de mediciones Mac](../../plans/research/ANIMATED-ARTWORK-PERFORMANCE-2026-10-21.md).


## Ejecución — FIX-240, 2026-10-21

Código implementado sin cambios de Apple/core ni Recomendados. Tres encargos6.1Sol medio prepararon UI, seek y motion; se detuvieron por cuota y el integrador continuó, revisó/corrigió contratos, composición, renderer, visibilidad y pruebas. No se solicitó otra autorización ni se publicó código.

| Comprobación realizada en Mac | Resultado / alcance real |
|---|---|
| Frontend | `pnpm check`:0errores/0advertencias; `pnpm test`:430aprobadas/1omitida exclusiva Windows; `pnpm build`:aprobado en `windows/build/`, advertencia de chunk grande conservada |
| Contratos Rust y seek |8tests de DTOs/tiempos/Unicode/instrumental y máquina de seek, extraídos de fuentes de producción a probe local con core compartido; aprobados. No ejecutan Tauri/libmpv |
| Win32 | Bindings Power/Memory/DWM comprobados por compilación aislada; corrección de tipo DWMWA i32→u32. No prueba señales del SO real |
| Fixture Chromium | Original/nuevo36px/700/tracking−0,18/line-height45 y geometría212×270 idénticos en caso de palabra partida en6renglones;6rectángulos de máscara con progreso continuo. Blur1,2px→none al scroll, manual/Volver y fallback comprobados; ni FPS ni WebView2 |
| Check Tauri desde Mac | `--locked` inicialmente detectó lock desactualizado; se añadieron sólo roxmltree/http-range requeridos. Tras habilitar protocol-asset, check normal exige DLL Windows. Override temporal de recursos permite revisar fuentes pero falla por10 referencias login/session cfgWindows preexistentes; no se alteran guardas productivas para aparentar build destino |

Evidencia local: `windows/.cache/plan013-{check,tests,build,contract-probe,cargo-check}.log`, fixture/captura/DOM en `windows/.cache/plan013-visual/`. No contienen credenciales ni se incluyen artefactos en Git. El cambio final de origen del efecto sostenido usa el centro de todos los fragmentos, manteniendo el barrido continuo.

Implementación relevante: Original comparte exactamente el componente base y estado con el rico; se distingue preferencia/renderer efectivo. No muestra clásico de otra generación/entryId. Cambios de documento no reactivan seguimiento; hidden desmonta filas y mantiene ajustes/posición manual. Se validan límites de grafemas antes de aplicar máscaras. Sólo texto visible mide geometría y las palabras terminadas dejan de mutar atributos por frame. EOF durante pending se difiere y contrasta con idle real; cambio de item/cuenta lo cancela. Seek pendiente es una vista previa fija identificada; `position` sigue siendo observado. Montajes tardíos durante clear se bloquean y sus detaches se esperan.

Pendiente en Windows: ejecutar doctor/verify/build oficial y matriz real de audio/cues/restauración, WebView2 H.264/primer frame/loop/handles, accesibilidad/DPI/ventana/energía/memoria. No hay EXE/build numerada nueva. El motor compartido no etiqueta sus Position con ticket/ocurrencia; la exclusión absoluta de muestras ya encoladas no se acredita con los tests del adaptador. DWM-cloaking/minimizado están integrados, pero no detección completa de solapamiento de ventanas ni thermal equivalente; no cerrar PAR-039 como paridad completa. Mac conserva su build0155 y el A/B cancelado, sin nuevo perfil. El port no certifica FPS ni que una fuente real60 esté disponible.

## Build nativa Windows — 2026-10-21

- Pedido posterior: traer lo último subido desde Mac y compilar Windows. Árbol local limpio al comenzar. Fetch detecta historial reescrito por FIX-227; `23f1df5^{tree}` y `653149f^{tree}` son idénticos. Se conserva `codex/pre-sync-20261021` local y se sigue el nuevo `main` en `d6e2c4b52b102a55b4b1ae4b7c08f6bdd563cca7`; no se publica la historia anterior.
- Comando oficial: `node Scripts/build-version.mjs windows`. Verify y build Release aprobados, sin cambios funcionales para compilar ni modificación de Apple/core. Fuentes inicialmente limpias, `sourceChangedDuringBuild:false`, `status:compiled` en `builds/windows/build-0017/BUILD.json`; log completo al lado.
- Verificación:987pruebas aprobadas (431frontend,97InnerTube,169core,171bridge,5player,114Tauri),20live Rust ignoradas; check0errores/0advertencias,build frontend y EXE nativo aprobados. Avisos de unused import/dead_code,LNK4098 y chunk grande conservados, sin errores. No se repiten las cifras de Mac como evidencia nativa.
- Artefacto: `builds/windows/build-0017/sideb-windows.exe`, PE x64 y recurso de versión1.2.6 comprobados, build público19. Conservar con `libmpv-2.dll`, `vulkan-1.dll` y `VulkanRT-License.txt`; cuatro hashes revalidados. EXE SHA256 `51e5749f00dd47b6a545cc3ba58a38fa937cd3d516407898bcbbb7448d4c4a38`. Builds anteriores intactas; número local0017 independiente de la versión pública.
- No se abrió el ejecutable ni se probó cuenta/audio/cues/WebView2/H.264/primer frame/loop/energía/memoria/DPI/fluidez. Esa matriz física sigue pendiente en PAR-037/038/039; no se cierra paridad ni se certifican FPS por compilar. Mac conserva sus resultados y el A/B cancelado.
- La documentación de FIXES/PARIDAD/este plan es posterior al empaquetado. Sin instalación, publicación de release,tags,commit ni push en este pedido.

## Corrección del renderer — FIX-242, 2026-10-21

Las capturas posteriores del usuario y una contraprueba raster descubren que la capa animada dejaba base/relleno fijos debajo, produciendo glifos duplicados. El origen descrito arriba como unión de todos los fragmentos se sustituye por anclas inferiores por palabra y renglón, como en Mac, con límites físicos de expansión. Se transforma base/relleno juntos y brillo sólo sobre relleno, sin alterar layout, reloj ni proveedor. [PLAN-016](PLAN-016-karaoke-fragment-rendering.md) y [FIX-242](../../FIXES.md#fix-242) conservan detalles: check0/0,431tests/build frontend y9casos raster/shaping Chromium aprobados, con fallo demostrado en el renderer anterior. No hay EXE nuevo; build-0018 incluye Inter pero precede a FIX-242. La QA WebView2/audio/FPS y PAR-037 siguen pendientes.

Entrega posterior: build-0020 Windows x64 Release incluye FIX-242 y el margen de pintura de FIX-243 para el borde izquierdo del blur, además de Inter. Verify987aprobadas/20live ignoradas/check0/0, `status:compiled`, fuentes estables, cuatro hashes y PE/versión comprobados. build-0019 previa al borde conservada con deriva de fuentes registrada, no es la entrega final. [PLAN-016](PLAN-016-karaoke-fragment-rendering.md#entrega-standalone--build-0020) conserva ruta, SHA y límites; aceptación humana pendiente, sin abrir/publicar la app.

## Seguimiento integrado —2026-10-26

[FIX-249](../../FIXES.md#fix-249)/[FIX-250](../../FIXES.md#fix-250) completan correcciones detectadas al ejecutar el [PLAN-018 Windows](PLAN-018-windows-current-parity-roadmap.md#18-ejecución-con-subagentes-2026-10-26): Original seleccionable en carga/fallback, namespace de cuenta/entryId clásico coherente con el host, energía/visibilidad conectada al reloj,30Hz bajo rAF120Hz y fronteras de documento sin polling16ms. Mapas de gaps/Segmenter preparado, forced-colors y focoEscape; primer frame de motion no se revela inactivo y play tardío interrumpido no cancela fuente reanudada. Clear espera también teardown que llega durante eliminación; identidad Unicode/créditos como Mac.

21focales de letras y5Rust de seek,28focales motion aprobadas; primera suite global integrada473aprobadas/1omitida y check0/0. Preparación5000líneas/50000segmentos no acredita DOM5000/FPS. La evidencia final de frontend/build/QA de composición se registra en PLAN-016. Sin core/Apple propios ni EXE Windows. Procedencia de Position,5cues/restauración/EOF audibles, WebView2/handles/loop/DPI/Narrator y señales físicas siguen pendientes en destino; oclusión total/thermal y A/B Mac mantienen sus límites previos.
