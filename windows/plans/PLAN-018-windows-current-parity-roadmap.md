# PLAN-018 — Llevar a Windows la experiencia actual de Side B

- Fecha de auditoría: **2026-10-24**, America/Montevideo.
- Estado actual,2026-10-27: **fuentes implementadas; doctor/verify nativo y build Windows0021 Release aprobados; aceptación manual Windows pendiente**. Búsqueda, letras, motion y retención trabajados en Mac el26 con tres subagentes y revisión cruzada. El26/27 se descarga13011e7 en PC y se verifican1054pruebas/fuentes estables/cuatro hashes; [PLAN-019 §8](PLAN-019-windows-github-handoff.md#8-ejecución-en-la-pc-2026-10-2627) registra evidencia y detención de Computer Use por el usuario antes de abrir0021. La auditoría original del24 y ejecución Mac de sección18 se conservan con sus fechas y límites.
- Pedido: analizar todo lo pendiente para Windows, con foco en buscador nuevo, carátulas animadas y letras, y explicar cómo trasladarlo desde Mac.
- Referencia de búsqueda: Mac **0163**, FIX-256/257/258/259/245 y [Apple PLAN-027](../../apple/plans/PLAN-027-search-density-and-performance.md). **Actualización al ejecutar: FIX-246/Mac0165**, ancho disponible/acciones/categorías aprobado con cuenta real en el origen; esa referencia reemplaza al estado todavía en comprobación que se leyó el24. Letras y motion: Mac **0155**, FIX-228…240; se comparan además las fuentes actuales.
- Fuentes locales: commit `d6e2c4b` más un árbol con modificaciones y archivos nuevos de búsqueda todavía sin seguimiento. **El commit solo no contiene todo el trabajo auditado.**
- Autoridad del estado de paridad: [PARIDAD.md](../../PARIDAD.md). Este documento organiza la ejecución; no crea otros IDs PAR ni sustituye sus evidencias.
- Planes de implementación que continúan vigentes: [Windows PLAN-013, letras/motion](PLAN-013-lyrics-motion-parity.md), [Windows PLAN-017, búsqueda](PLAN-017-provider-search.md), [PLAN-015 compartido](../../plans/PLAN-015-ytmusic-native-search.md) y [PLAN-016 compartido](../../plans/PLAN-016-search-presentation.md). Los números repetidos pertenecen a carpetas distintas.

## 1. Conclusión de la auditoría

No hay que empezar de cero. El core compartido y los consumidores Windows ya incluyen páginas autenticadas de búsqueda, principal/relacionadas, letras por palabra y vídeos locales de carátula. El trabajo se divide en cuatro estados:

| Estado | Qué significa | Qué corresponde hacer |
|---|---|---|
| Falta de implementación comprobada | El comportamiento de Mac no tiene equivalente en el destino | Implementar dentro de Windows y probar la regresión observable |
| Implementado, falta destino | Existe código y cobertura aislada, pero falta Windows/Tauri/WebView2/libmpv | Ejecutar verify, build y casos nativos; corregir sólo lo que la evidencia encuentre |
| Por investigar | Hay una limitación o un camino costoso; aún no hay reproducción/medición concluyente | Preparar caso, observar y decidir; no presentarlo como defecto demostrado |
| Pendiente en ambas apps | Es una función futura compartida | Ejecutar su propio plan Mac/Windows; no contabilizarla como port atrasado |

La mayor brecha nueva de producto está en **FIX-258/245/246 de búsqueda** y **PAR-031 de retención/suspensión**. En letras/motion, FIX-240 ya hizo el port principal: falta especialmente cerrar audio real, ciclo de vídeo y compatibilidad del runtime. Indicadores y preferencias explicit/clean siguen sin implementar en las dos apps. Al comenzar cada lote se vuelve a leer la referencia vigente: hay trabajo Apple concurrente y no se congelan sus decisiones con esta planificación.

## 2. Qué se comprobó ahora y qué sigue sin evidencia

Se leyeron las instrucciones comunes y de ámbitos, guía de trabajo, índices/planes, PARIDAD y fixes relacionados; se contrastaron componentes Svelte, controllers TS, DTO/comandos Tauri, runtime de seek/ventana, consumidor Rust player, referencias Swift y CI/empaquetado.

Comprobaciones ejecutadas **en este Mac el 24 de octubre**:

| Comprobación | Resultado | Alcance |
|---|---|---|
| `pnpm check`, desde `windows/` | 0 errores, 0 advertencias | Tipos/diagnósticos frontend |
| `pnpm test`, desde `windows/` | 454 declaradas: **453 aprobadas, 1 omitida, 0 fallos** | Regresiones frontend/contratos simulados; la omitida necesita Windows |
| Manifests y workflows | Revisados en fuentes | No se ejecutó CI remoto ni se consultó su último resultado |
| Builds locales presentes | Mac0163 `compiled`; no hay `builds/windows/build-*/BUILD.json` en este checkout | No demuestra que no existan builds Windows en otro host |
| Producto/versiones | `version.env`, package/Tauri: **1.2.6, build público19** | No equiparar árbol local, release y app instalada |

Logs de esta ronda: `/tmp/sideb-windows-plan-20261024-check.log` y `/tmp/sideb-windows-plan-20261024-test.log`. Node local24.16.0; `pnpm --version` local11.25.0, frente a12.6.0 declarado en package/CI. Los checks pasaron con ese entorno; la reproducción oficial debe alinear el gestor declarado, sin cambiar dependencias por rutina.

No se ejecutaron build frontend nueva, compilación Tauri, audio, cuenta real, GUI Windows, instalación, actualización, perfiles ni publicación. Los conteos/builds de los planes anteriores conservan su fecha y no se reutilizan como una comprobación nueva.

## 3. Inventario de pendientes y prioridad

| Área / referencia | Estado Windows observado | Pendiente concreto | Prioridad |
|---|---|---|---|
| Motor de búsqueda / PAR-042 | `ProviderSearchController`, DTO y endpoints existentes | Verify Tauri; acciones/continuaciones con sesión y audio reales | P0 de integración |
| Principal y relacionadas / PAR-042 | Implementados en Svelte | Densidad de FIX-258; ancho disponible/centrado de acciones y categorías de FIX-246, con validación Mac todavía en curso | P1 |
| Proyección de búsqueda / PAR-042 | Empareja con `findIndex` y calcula desde el render | Proyección por ocurrencia lineal, cacheada y preparada por revisión | P1 |
| Viewport de búsqueda / PAR-042 | `#each` monta todas las secciones/filas | Virtualización de resultados mixtos, alturas y anclas estables | P1 |
| Sugerencias / PAR-042 | Preview absoluto y cierre por foco ya existen | Máximo3 entradas de texto con consulta; teclado y render con la misma lista | P1 |
| Retención de páginas / PAR-031 | La composición usa ramas que desmontan destinos | Conservación acotada, suspensión de trabajo y purga por cuenta | P1, después del viewport |
| Letras ricas / PAR-037 | FIX-240 implementado | WebView2, estados/fallback, voces, wrapping, accesibilidad y carga larga | P0 de aceptación |
| Seek / PAR-038 | Identidad, revisión, pending y timeout implementados | Confirmación libmpv/pausa/restauración/EOF; origen de eventos encolados | P0 |
| Reloj de letras / PAR-037 | Reloj local e interpolación acotada existentes | Conectar política de ahorro; auditar despertares/coste de huecos | P1; comprobar antes de optimizar |
| Motion / PAR-039 | H.264 local, primer frame,30s/clear/señales Win32 implementados | Decodificación/composición/loop/handles reales y casos de carrera | P0 de aceptación |
| Oclusión/thermal / PAR-039 | Visible/minimizado/cloaked/ahorro/memoria | Ventana completamente tapada sin señal; diferencia térmica de plataforma | Investigación explícita |
| Biblioteca/cabeceras / PAR-028/027 | Función implementada, presentación previa | Acciones junto a categorías; revisar fondo/editor/ancho de búsqueda | P2 |
| Inicio/Explorar/colecciones/cola/Genius | Ya implementados, mucha evidencia histórica | Barrido nativo dirigido de los flujos existentes | P2, sin reescritura |
| Indicadores / PAR-040 | Parciales en Home; contrato general pendiente | explicit/clean/unknown, metadata y migraciones compartidas | Segunda entrega |
| Preferencia de versiones / PAR-041 | Sin implementar en ambas apps | Depende de PAR-040 y equivalencias comprobables | Después de indicadores |
| TopNav Apple / PAR-007/008 | Exclusión previa de port visual | Mantener navegación propia; revisión de comportamiento compatible | Fuera del port visual |
| Volumen exponencial / PAR-024 | Windows ya lo tiene | Falta eventual destino Mac; no es deuda Windows | Fuera de este port |

P0 significa que impide afirmar que el conjunto funciona en Windows. P1 completa la experiencia pedida. P2 cierra coherencia/regresiones del resto; no obliga a rehacer funciones ya presentes.

## 4. Traducción de arquitectura Mac → Windows

| Responsabilidad Mac | Equivalente Windows | Regla de traducción |
|---|---|---|
| SwiftUI/AppKit presenta records UniFFI | Svelte5 presenta DTO camelCase vía Tauri | Trasladar comportamiento y contratos, no sintaxis de vistas |
| `ProviderSearchProjection`/índice por ocurrencia | `search/provider-rows.ts` y proyección de página preparada | IDs repetidos conservan payload, posición y menú de cada ocurrencia |
| `NSTableView` reutiliza celdas | Viewport DOM con ventana de filas y overscan | Número de nodos ligado al área visible, no a resultados totales |
| Alturas AppKit por fila + caché | Medidas CSS/ResizeObserver por clave y revisión | Invalidación por ancho/texto/fuente/expansión; mantener ancla visible |
| Host flotante de sugerencias | Preview absoluto actual; portal sólo si clipping lo exige | No agregar altura al documento ni alterar el scroll al enfocar |
| Páginas AppKit retenidas con suspensión | Hosts Svelte retenidos de forma acotada + contratos de actividad | Separar retención visual, acciones, AX, observers/red y animación |
| `ExperimentalLyricsDocument/Sequence` | `prepareKaraoke` y documento preparado TS | El parser/provider/caché permanecen en Rust |
| TextRenderer y shaping nativo | Texto DOM completo + Range/SVG sobre fragmentos | Preservar Unicode, ligaduras, RTL y salto de línea |
| Observaciones AVPlayer + reloj local | `Position` libmpv + `KaraokeClock` local | Posición observada distinta del target; nunca RPC por frame |
| Seek/adopción AVPlayer | Runtime Tauri + `SeekState` + cola nativa | Preservar cuenta, entryId y generaciones; adaptar confirmación a mpv |
| AVPlayerLayer/Looper decorativo | `<video muted loop>` local WebView2 | Un decoder de carátula; música sigue por libmpv |
| Señales NSWindow/energía/thermal | Win32/DWM/Power/Memory y visibilidad WebView | Usar capacidades reales; registrar equivalencias incompletas |
| Materiales y tipografía Apple | Tokens actuales/CSS/fuente disponible Windows | Comparar área lógica y DPI; no distribuir SF Pro ni copiar AppKit |

`core/` sigue protegido. En esta ejecución Windows sólo se cambia integración/UI. Un problema común demostrado se separa como fix compartido con ambos consumidores y pruebas; los futuros PAR-040/041 requieren su alcance común propio.

## 5. Etapa A — Fijar una base reproducible y verificable

**Objetivo:** que el host Windows reciba exactamente el código auditado y que una falla nativa se pueda atribuir a una fuente concreta.

- [x] A01 — Leer código, fixes y planes; distinguir hecho actual de descripciones anteriores a FIX-240.
- [x] A02 — Ejecutar check y tests frontend actuales; resultados en sección2.
- [x] A03 — Al comenzar implementación, inventariar `git status --short`, diff y archivos sin seguimiento. Preparar snapshot/manifiesto de fuentes autorizadas, incluidos `search.rs`, `search_page.rs`, componentes y tests nuevos. Un `git diff` solo omite esos archivos.
- [x] A04 — Host PC y checkout13011e7 identificados; fuentes completas y hashes estables antes/después de build0021. Borrador local conservado. Evidencia nueva en [PLAN-019 §8](PLAN-019-windows-github-handoff.md#8-ejecución-en-la-pc-2026-10-2627).
- [x] A05 — Doctor/verify Windows aprobados el26/27; Node24.13.1/pnpm12.6.0/Rust1.98.1 MSVC/VS2022/WebView2155.1054pruebas aprobadas/0fallos; diez live omitidas por variante core. Entorno y límites en PLAN-019 §8; DPI físico/Narrator aún no verificados.
- [x] A06 — Resolver fallas de integración reproducibles en este host; distinguir frontend, core+bridge y nativos. Corregidos binding inicial, composición del actualizador, foco/menú y rueda; player/Tauri/WebView2 siguen en A05/G02.
- [x] A07 — Fixtures sanitizadas de búsqueda/letras/motion y referencias geométricas Mac0165/0155/0166 preparadas. Datos de cuenta/RPC/covers sintéticos; sin cookies, credenciales ni URLs firmadas.

**Salida A:** mismo conjunto de fuentes en destino y verify nativo conocido. Si un entorno no está disponible, se puede continuar con código/fixtures en Mac, pero A05 y todos los cierres nativos permanecen abiertos.

## 6. Etapa B — Completar el buscador actual

### B1. Conservar el motor que ya existe

Archivos: `src/lib/search/provider.ts`, `provider-preview.ts`, `src-tauri/src/search_page.rs`, `commands/catalog.rs`, `commands/playback.rs`, `src/routes/+page.svelte` y tipos/DTO de búsqueda.

- [ ] B01 — Verificar round-trip de chips, corrección, params opacos, roles primary/related, acciones, feedback de historial y continuaciones. No convertir el rediseño en un ranking propio.
- [ ] B02 — Comprobar que Play/radio/aleatorio conservan video/playlist seed, starting index, token de `next` y automix; extender la fuente progresiva al llegar al borde. Repetidos conservan ocurrencias.
- [ ] B03 — Cambiar consulta/filtro/cuenta mientras hay page/preview/next/continuación pendientes; descartar respuestas antiguas sin perder retry del estado vigente.
- [ ] B04 — Comprobar navegación Atrás/Adelante: query, chip, expansión, scroll y borrador según su intención; filtros/restauración no añaden historial de submit accidental.

Estas acciones están programadas. B01…04 son aceptación de integración, no una lista de endpoints por crear.

### B2. Proyección lineal y cacheada

Hallazgo: `providerRows` usa un `findIndex` por tarjeta y `projectSearchSection` se invoca desde el template. Con muchas canciones, el emparejamiento puede ser cuadrático. No es una medición de lag, pero sí trabajo repetido comprobable.

- [x] B05 — Preparar un mapa `videoId → secuencia de índices/payloads` con cursores y consumir cada ocurrencia una sola vez. Conservar `setVideoId`, library token, créditos y metadata propios. No colapsar duplicados con un `Map<id, song>` único.
- [x] B06 — Preparar proyección de página fuera del template: principal, relacionadas y secuencia restante. Roles inválidos/ausentes conservan fallback ordenado completo.
- [x] B07 — Separar revisiones: nueva consulta/cuenta invalida documento; append añade secciones; expansión invalida bloque; playback actualiza actividad visible sin reconstruir payloads.
- [x] B08 — Probar 5.000 entradas con duplicados, canciones sin card y cards sin song; correspondencia exacta y contadores de trabajo lineal. Evitar umbrales de milisegundos dependientes de la máquina como única prueba.

### B3. Densidad y geometría de FIX-258

Hallazgos: `SearchView.svelte` monta cabecera de sección aunque el título esté vacío, y la monta también encima del principal; `SearchPrincipal.svelte` apila identidad de artista en C≥960. El diseño vigente Mac ya compactó esos casos.

- [x] B09 — Usar una columna compartida para cabecera, principal y resultados: **ancho útil menos28 por lado, sin tope1280/1336**, según FIX-246. El máximo1280 de FIX-258 ya fue retirado de las fuentes Mac durante esta auditoría; no trasladarlo como objetivo nuevo. Adaptar después de sidebar/márgenes y validar texto ampliado antes de fijar mínimos.
- [x] B10 — No montar cabecera vacía; evitar repetir el título del principal. Si hay «Ver todo» remoto, conservar acceso sin reservar un bloque de título vacío.
- [x] B11 — Principal de canción/álbum compacto y acciones agrupadas a la derecha cuando caben; artista horizontal con relacionadas. Conservar fallback apilado y expansión local de más de tres relacionadas.
- [x] B12 — Referencia inicial Mac: filas58, cabeceras44 y carruseles232 unidades lógicas. Ajustar a métricas reales de Windows; altura del principal variable por contenido, no recortada por una cifra fija.
- [x] B13 — Preservar portada circular de artista, créditos con destinos separados, hit targets de40/32, menús y acciones condicionadas por capacidad. Ningún clic de créditos/menú reproduce por propagación.
- [x] B14 — Revisar cabecera/material de Windows frente a FIX-179 y columna nueva. Mantener por esta entrega la decisión previa de editor/chips fuera del scroll de resultados; llevarlos al documento completo es un cambio de shell separado.
- [x] B27 — Comparar acciones40/32 centradas verticalmente en cada renglón, con menú y wrapping, siguiendo FIX-246. Windows usa flex propio: comprobar diferencia antes de cambiarlo; no copiar el bug del layout Swift como si estuviera presente.
- [x] B28 — Categorías: fade transparente de referencia24 en extremos sólo donde queda overflow, sin fondo negro; conservar scroll horizontal, orden, params, selección y acceso por teclado. Medir overflow al cambiar ancho/idioma/chips; no publicar scroll global por píxel. Verificar primero aceptación final del ajuste Mac en curso.

### B4. Viewport mixto y conservación de posición

Mac usa tabla reutilizada; Windows necesita un equivalente DOM. `VirtualStack.svelte` ya existe, pero no resuelve por sí solo las alturas medidas del principal ni todos los problemas de foco/anclaje. Su búsqueda de rango es lineal y debe evaluarse antes de reutilizarlo para una página larga.

- [x] B15 — Aplanar entradas visuales: principal, heading no vacía, fila, carrusel, estado/error y continuación. Claves por ocurrencia/sección/revisión compatibles con append, no sólo videoId.
- [x] B16 — Implementar/adaptar un viewport con offsets acumulados, búsqueda binaria de rango y overscan acotado. Medir sólo entradas montadas; evitar lectores de geometría de todas las filas durante scroll.
- [x] B17 — Mantener caché de alturas por clave/ancho/estilo; reservar estimaciones coherentes para imágenes tardías. Al corregir una altura anterior al viewport, compensar scroll conservando la misma entrada visible y su desplazamiento relativo.
- [x] B18 — Append/expandir/colapsar conservan ancla; nueva query/filtro inicia donde corresponda a su intención. Cambiar sidebar/DPI/fuente invalida medidas sin perder consulta o foco compatible.
- [x] B19 — Foco y menú de una fila virtual: mantener ancla mientras el control lo necesita, o cerrar de forma explícita antes de desmontar; navegación por teclado materializa la siguiente entrada y la hace visible.
- [x] B20 — Integrar con `contentScrollElement`, historial y restauración del shell. Conservar fondo/player/padding inferior y un solo propietario de scroll de resultados.
- [x] B21 — Cerrar con 5.000 resultados, scroll hasta4500, append con principal fuera de vista, menú junto a los bordes y resize. Criterio: DOM montado acotado por viewport+overscan, no proporcional a5.000; cero pérdidas de ocurrencias. Registrar el máximo observado, sin copiar el máximo40 de la prueba Mac como garantía Windows.

### B5. Sugerencias de FIX-245 y prevención de regresiones FIX-259

Windows ya tiene preview `position:absolute` y cierre por foco. **No necesita portar el host AppKit ni se afirma que tenga el bug de salto Mac.**

- [x] B22 — Derivar una lista visible común: si `query.trim()` no está vacío, conservar como máximo3 entradas no musicales y todas las entidades en su orden relativo; con campo vacío, conservar todo el historial recibido. No recortar el DTO ni modificar tokens/cache del proveedor.
- [x] B23 — Hacer que QuickResults, navegación ArrowUp/Down, Enter, selección, altura y Spotlight usen esa misma lista. Botón de borrar historial se mantiene separado de la acción primaria.
- [x] B24 — Probar6 completados seguidos de2 canciones: tres textos y música visibles en el panel habitual; seleccionar la primera entidad con ratón/teclado ejecuta su payload correcto.
- [ ] B25 — Probar clic exterior en fondo, título, Inicio y control interactivo: cierra panel, conserva draft y el mismo clic llega al destino; no submit ni desplazamiento artificial. Verificar en WebView2, no asumirlo por `focusout`.
- [ ] B26 — Abrir/cerrar preview sin salto de resultados; Spotlight sobre Inicio/Search/Biblioteca/Explorar conserva la imagen de fondo seleccionada y restaura foco al cerrar. IME no envía Enter de composición; Escape respeta prioridad modal/menú.

**Salida B:** misma jerarquía y políticas recientes de búsqueda que Mac0163 más los ajustes de FIX-246 que hayan quedado validados, con viewport propio Windows y funciones del proveedor intactas. Seguimiento en PAR-042 y Windows PLAN-015.

## 7. Etapa C — Cerrar letras y seek con el motor real

### C1. Lo que ya está implementado

`commands/lyrics.rs` expone `get_karaoke_lyrics` y DTO ricos; `karaoke.ts` prepara palabras/voces/grupos/traducción/instrumental; `LyricsPanel.svelte` comparte Original/nuevo, tamaño/modo/manual/menú/fallback; `KaraokePhrase.svelte` usa texto completo y máscaras; `KaraokeClock` parte de muestras reales. `SeekState` distingue target pendiente de posición observada y usa cuenta/generación/entryId. Todo proviene de FIX-240, no se programa de nuevo.

### C2. Contratos, presentación y estados

- [ ] C01 — Verificar DTO real Rust→JSON→TS: ms/segundos, cero/ausencia, palabras y finales, provider, roles, agentes, grupos, sección, traducción e instrumental. Duración tardía inicia resolución válida para la misma ocurrencia.
- [ ] C02 — Matriz de fuente: rico inmediato; clásico mientras rico carga; rico ausente/error; llegada tardía; refresh con documento válido; Original elegido; Genius activo. Conservar manual/tamaño/modo y nunca texto de otra ocurrencia.
- [ ] C03 — Ajustes: nuevas/Karaoke inicial, tamaño36 con20…48/paso2; Lectura, movimiento, traducción, desfase±5s/paso100ms, proveedor/timing y retry. Menú presente en loading/error/empty/Original sin consumir altura del panel.
- [ ] C04 — Scroll manual por rueda/trackpad/barra/teclado/touch quita blur inmediatamente; refresh/resize/renderer no lo repone. Volver/clic/nueva ocurrencia sí; Lectura/Reduce Motion/contraste mantienen blur0.
- [ ] C05 — Corpus Unicode y voces: palabra partida en varias líneas, CJK/RTL, ligaduras, emoji/ZWJ y combinaciones; voces simultáneas y fondos tardíos sin retroceder ancla. Error de detalle conserva texto legible por línea.
- [ ] C06 — Intro/interludio/outro de≥5s sólo donde la unión de todas las voces lo permite; líneas sin tiempo como barrera y outro con duración válida. Instrumental es un estado positivo separado de vacío.
- [ ] C07 — Comparar Original/nuevo a20/36/48, ancho estrecho/amplio y DPI100/125/150/200. Tipografía, padding, fade, máscara y wrapping sin salto de layout al fallback.
- [ ] C08 — Narrator, teclado y selección/texto accesible: evitar doble lectura de capas decorativas, foco visible y retorno desde menú; probar `forced-colors` real además de `prefers-contrast`. La existencia de la media query no demuestra esa cobertura.

### C3. Seek: prioridad de aceptación

- [ ] C09 — Con archivo local controlado y duración conocida, ejecutar al menos5 cues adelante/atrás. Registrar target, revisión, entrada y posición realmente observada. La tolerancia actual de confirmación es250ms, timeout15s; son reglas del adaptador, no garantía de latencia audible.
- [ ] C10 — Repetir en pausa, durante resolución/adopción y con duración inicialmente desconocida. Pista restaurada sin item conserva sólo el último cue de esa ocurrencia; item ya cargado conserva pausa.
- [ ] C11 — Clics rápidos A→B→C, scrubbing intercalado, cambio de pista y mismo video duplicado en otra entryId; cambio de cuenta y retorno tardío. Ningún callback anterior confirma o altera una intención nueva.
- [ ] C12 — Seek próximo al final, EOF mientras pending, error/deadline y siguiente pista. EOF diferido se procesa una sola vez sólo si el motor está realmente idle y conserva propietario vigente.
- [x] C13 — Investigar la procedencia de `PlayerEvent::Position(f64)`: actualmente no contiene ticket/entryId. Reproducir una muestra ya encolada cercana al nuevo target y comprobar si podría confirmar el seek incorrecto. Los guards actuales reducen carreras; no prueban el origen del evento.
- [ ] C14 — Si C13 demuestra fallo, resolver en integración Windows con barrera/adopción/observación del motor comprobable. Si la solución requiere cambiar el contrato protegido de player, documentar problema común/consumidores antes de abrir un fix compartido. No añadir una etiqueta artificial al recibir el evento como si acreditara su origen.
- [ ] C15 — Después del archivo local, verificar stream remoto y discontinuidades de buffering en host/cuenta autorizados. Separar resolución/cipher/red del seek/renderer; un audio no reproducible impide valorar sincronía.

### C4. Reloj, actividad y trabajo pendiente de investigar

Hallazgos adicionales de esta auditoría: `KaraokeClock.setSlow` existe **sin consumidores** en `src/lib`; la rama sin barrido programa timeout16ms; `LyricsPanel` busca hueco con `findIndex` por pulso y recorre gaps dentro de cada grupo al renderizar. Son hechos de código; todavía no son una medición de consumo ni justifican cambiar todo el renderer.

- [x] C16 — Conectar una política local de ahorro/visibilidad: señales existentes de energía/ventana cuando correspondan; pulsos de letras limitados y congelación al ocultar/pausar/buffering/seek. Evitar que sólo motion reciba la señal de ahorro mientras karaoke queda a régimen completo.
- [x] C17 — Medir callbacks activos visibles y sin barrido; comprobar si se puede programar la próxima frontera en vez de despertar cada16ms. Conservar palabras cortas/gaps y reconciliación con muestras libmpv; no introducir un reloj independiente.
- [x] C18 — Preparar `gapsByBefore`/índice temporal una vez por documento si el perfil/corpus demuestra coste; no recalcular un escaneo grupos×gaps por cambio de foco. Mantener orden y barreras de todas las voces.
- [ ] C19 — Comprobar que sólo frases visibles miden Range/rectángulos y actualizan máscara, y que las terminadas dejan de pintar. El contexto sigue estático; no levantar posición por frame a `+page.svelte` ni a un store global.
- [ ] C20 — Probar fixtures de5.000 líneas y límite total de segmentos sin congelar entrada; `content-visibility:auto` evita parte del rendering, pero mantiene DOM y árbol accesible. Si el coste real exige virtualizar letras, diseñar anclaje/foco/medidas/AX antes de sustituirlo.

**Salida C:** renderer/fallback y seguimiento verificados en WebView2 y seeks confirmados por libmpv; limitación C13 resuelta o descrita con caso/evidencia pendiente. Seguimiento en las mismas PAR-037/038 y Windows PLAN-013.

## 8. Etapa D — Cerrar carátulas animadas en Windows

### D1. Base existente y diferencias de plataforma

Archivos: `components/fullscreen/AnimatedArtwork.svelte`, `artwork/{animated,controller,clearCoordinator,policy,runtime}.ts`, `commands/animated_artwork.rs`, `artwork_runtime.rs`, preferencias/Apariencia y configuración asset/CSP Tauri.

Existe H.264 local, imagen permanente, callback de primer frame, fade225ms, debounce300ms, caché150MiB y leases; timeout de inicio8s y liberación tras30s inactiva. FIX-238 de otras ediciones oficiales vive en core y ya llega a ambos consumidores. Windows pide `preferHevc:false`; no se copia el camino HEVC/AVPlayer de Mac.

- [ ] D01 — Resolver un asset H.264 real en Windows y verificar dimensiones/fps/duración/codec declarados y reproducidos. Hasta1080/60 si la fuente existe; no convertir30 en60 ni escalar una fuente menor para fingir calidad.
- [ ] D02 — Archivo frío frente a caché caliente: distinguir resolución, descarga, apertura, primer frame y fade. La espera inicial mencionada en FIX-237 sigue siendo un punto a revisar; no hay optimización de latencia demostrada por esta auditoría.
- [ ] D03 — Mantener imagen hasta frame válido de la solicitud vigente. Probar `requestVideoFrameCallback` y el fallback `HAVE_CURRENT_DATA`/rAF en WebView2; `loadeddata` por sí solo no acredita composición sin negro.
- [ ] D04 — Repetir loop real varias vueltas; sin parpadeo, sonido de vídeo ni salto de geometría. Controles/gestos/volumen/flip siguen recibiendo input y el audio libmpv no se interrumpe.
- [ ] D05 — Mismo álbum entre pistas reutiliza vídeo/lease; cambio álbum o sesión retira el anterior enseguida, incluso con prepare/descarga/frame en vuelo.
- [ ] D06 — Pausa/reverso/oculto detienen vídeo;30s liberan src/decoder/lease; volver antes cancela deadline, volver después reutiliza caché. OFF/Reduce Motion/cierre/cuenta/ahorro/memoria liberan según política sin multiplicar timers.
- [ ] D07 — Borrar caché mientras reproduce/descarga/cancela, con un consumidor que aparece durante clear: bloquear preparaciones, detach de todos, esperar handles, borrar propios/parciales y conservar veredictos. Sin error de sharing violation ni re-descarga del mismo consumidor inmediatamente.
- [ ] D08 — Ausencia legítima,404/transitorio, timeout, archivo truncado y metadata inválida vuelven a imagen sin spinner intrusivo. Un fallo temporal no se convierte en ausencia7d ni se reintenta en cada tick.
- [ ] D09 — Graduation clean/explicit y un álbum sin motion: resolver otras versiones oficiales cuando corresponda sin modificar audio/videoId, edición elegida, orden, historial ni likes. Negativos antiguos revalidados; positivos existentes conservados.
- [ ] D10 — Settings/miniaturas/sidebar/backdrop no montan ni descargan otro vídeo. Toggle/caché sobreviven reinicio e idiomas; limpieza/tamaño/error accesibles desde teclado.

### D2. Ventana, energía y límites reales

- [ ] D11 — Probar ventana visible sin foco, minimizada/restaurada, escritorio virtual/cloaked, bloqueo de sesión y fullscreen del sistema frente al del reproductor. No usar `document.hasFocus()` como equivalente de invisibilidad.
- [ ] D12 — Comprobar que las señales actuales llegan al componente en cada transición: `refresh_window` se ejecuta ante eventos Tauri, pero leer `DWMWA_CLOAKED` no garantiza recibir un evento para todo cambio de escritorio. Investigar notificación adicional sólo si falta el caso real.
- [ ] D13 — Probar ahorro y presión de memoria reales o inyectados de forma controlada, con retorno a normal. Una compilación aislada de bindings no demuestra dispatch nativo.
- [x] D14 — Definir alcance de ventana completamente cubierta por otras ventanas. DWM-cloaking no mide solapamiento general: evaluar señal disponible en el host y coste antes de implementar. Si no hay una solución fiable, documentar la diferencia residual y mantener minimización/ocultamiento reales cubiertos; no apagar por perder foco.
- [x] D15 — Registrar la diferencia térmica: no hay equivalente directo implementado de thermal-state Mac. Usar ahorro/memoria existentes y fallback estático cuando proceda; cualquier política térmica adicional requiere su propia evidencia, no una API supuesta.

**Salida D:** vídeo local nativo y limpieza/ciclo comprobados; Windows tiene evidencia propia. PAR-039 se mantiene parcial si D14/D15 siguen abiertos. El A/B Mac previamente cancelado sigue cancelado.

## 9. Etapa E — Retención de páginas y coherencia del resto

### E1. PAR-031: trasladar el comportamiento, no los hosts AppKit

Hallazgo: `+page.svelte` alterna destinos con `#if/:else if`. Inicio/Biblioteca/Explorar conservan algunos datos/offsets en controllers o stores, pero sus componentes se desmontan. Eso no equivale a la retención de instancias de Mac.

- [x] E01 — Restauración de páginas y diferencia entre datos/DOM/scroll auditadas; FIX-251 conserva hosts y suspende trabajo. Navegador completo y diez ciclos de componentes reales verifican regresiones sintéticas; cuenta/entrada física Windows pendientes.
- [x] E02 — Definir hosts retenidos acotados para destinos principales. Estado mínimo por host: selected, visuallyRetained, interactive y workActive; no un booleano ambiguo que deje observers/timers vivos bajo fullscreen.
- [x] E03 — Al cambiar destino: congelar snapshot, pausar medición/animación/suscripciones no necesarias y ocultar controles del árbol accesible. Purga al cambiar cuenta/contexto; limitar memoria de páginas montadas sin acumular cada detalle visitado.
- [x] E04 — Spotlight translúcido mantiene píxeles de la página seleccionada, con `inert`/AX y trabajo suspendidos; fullscreen oculta contenido. Cerrar restaura foco válido; no enfocar un nodo viejo tras cambio de cuenta.
- [x] E05 — Revisar contratos de `active` en VirtualStack/VirtualCatalog y vistas. No basta envolver un componente con `display:none` si siguen suscripciones/efectos; ni mantenerlo visible permite dejarlo interactivo tras el modal.
- [ ] E06 — Probar diez ciclos, vuelta a una fila profunda, resize/sidebar bajo cobertura, cuenta diferente y descarte de respuestas. Registrar observers/timers y memoria retenida antes/después; no prometer misma mejora CPU que Mac.

### E2. Ajustes de paridad pequeños y comprobables

- [x] E07 — Biblioteca: trasladar posición de crear/refrescar a la derecha de categorías, FIX-180/PAR-028, conservando editor único/permisos/orden/tab/query y layout estrecho.
- [ ] E08 — Cabeceras de Biblioteca/Búsqueda/Explorar: comparar columna, fondo, scroll y reserva inferior con áreas lógicas equivalentes. Priorizar diferencias registradas FIX-179/208; no fusionar TopNav/sidebar Apple.
- [ ] E09 — Invitados/créditos: probar título segmentado, homónimos, metadata tardía y celdas recicladas; hover sólo brillo y primer clic navega sin reproducir, PAR-029.
- [x] E10 — Evaluar si la retención exige modificar búsqueda o Biblioteca para congelar estado visible; conservar su cobertura de búsqueda paginada honesta, sin afirmar que un filtro local indexa toda la cuenta.

### E3. Barrido funcional existente, sin reconstruir lo entregado

| Grupo de paridad | Comprobación pendiente en Windows |
|---|---|
| PAR-001/009/010/021 | Playlist grande con inicio progresivo, next al borde, shuffle reversible, repetidos por entryId, radio con semilla correcta, dislike y subidas |
| PAR-003/004/005/006/011-2 | Inicio por cuenta/chip, configuración/fuentes, caché al reiniciar, páginas vacías/repetidas, fin del feed y ventanas de tarjetas |
| PAR-011/012/013-2 | Álbum/playlist/artista/catálogo, filtro/orden/continuación, créditos/cabeceras y acciones de colección correctas |
| PAR-014/030/036 y variantes -2 | ES/EN en vivo, sidebar lista/grid/fondo, controles40/32/48, foco/errores/diálogos y DPI |
| PAR-015/016-2/023 | Genius inline/anotaciones/reverso/información, color, ancla del popover y cierre exterior, sin degradación al activar rico |
| PAR-016/017 | Cerrar/abrir en pausa, volumen y pista por cuenta; historial una vez por ocurrencia sólo cuando reproduce |
| PAR-019/020 | Space fuera de editables, Ctrl+K, Alt+flechas, F11, SMTC/teclas multimedia y metadata/seek vigentes |
| PAR-025/032/033 | Fondo/portada/icono, rueda de volumen en sus zonas y regresión de cipher en una pista antes problemática y una de control |
| PAR-026/035 | Like/Guardar con optimismo/rollback/cambio cuenta, instalador/portable/actualizador y ausencia de avisos repetidos |

- [ ] E11 — Ejecutar este barrido con casos representativos y recoger sólo fallos nuevos; registrar el PAR afectado. Lo ya aprobado por el usuario, como rueda de volumen, se protege como regresión, no se vuelve a declarar ausente.
- [ ] E12 — Mutaciones reales de biblioteca/cuenta y pruebas con cuenta requieren un pedido que las incluya; preparar antes fixtures y recorridos revisables. Este plan no ejecuta esas mutaciones ni cambia sesión.

**Salida E:** comportamiento retenido bajo modales/navegación y coherencia del resto, con las diferencias por plataforma identificadas. PAR-007/008 conservan la exclusión del port visual de TopNav/sidebar; no se levantan por inferencia del pedido general.

## 10. Etapa F — Funciones futuras compartidas

Estos dos trabajos no bloquean entregar a Windows el buscador/letras/motion ya existentes. Necesitan implementación en Mac y Windows, no traducir una implementación Mac terminada.

### F1. Indicadores explicit/clean/unknown — PAR-040

Seguir [PLAN-013 compartido](../../plans/PLAN-013-explicit-content-indicators.md).

- [ ] F01 — Determinar evidencia positiva del proveedor por entidad; ausencia de badge o booleano false significa unknown, no clean. Álbum y canción tienen calificaciones independientes.
- [ ] F02 — Contrato aditivo y migraciones del core común: records, storage/cache, metadata y constructores legacy; no perder marcas al pasar por next/radio o metadatos tardíos.
- [ ] F03 — Actualizar UniFFI/Swift por flujo oficial y Tauri/TS juntos; Song/AlbumDetail y algunas cards hoy pierden información. `ExplicitBadge.svelte` existente no resuelve esa falta de datos.
- [ ] F04 — Cubrir Home, búsqueda rápida/completa, álbumes/catálogo, listas/cola/playback donde haya metadata confirmada. Texto accesible ES/EN y ninguna etiqueta clean falsa durante loading/error.
- [ ] F05 — Pruebas por ID/edición, migración y celdas recicladas; misma portada/motion no obliga a misma calificación. Cierre con evidencia de las dos apps.

### F2. Preferencia de versiones — PAR-041

Seguir [PLAN-014 compartido](../../plans/PLAN-014-content-version-preference.md), después de F1.

- [ ] F06 — Fijar precedencia de intención y opciones de producto pendientes del plan: default preferExplicit y opción preferClean; catalogOrder y textos definitivos aún propuestos.
- [ ] F07 — Resolver equivalencia de versiones con evidencia suficiente; título/artista iguales no prueban intercambiabilidad. Sin vínculo fiable, conservar elección/orden vigente y no inventar sustituciones.
- [ ] F08 — Integrar preferencia persistente y revisión de consultas/respuestas: metadatos, caché, controllers y UI de ambos shells. No suponer un filtro remoto explicit/clean que no está implementado.
- [ ] F09 — Aplicar sólo a presentación/selecciones automáticas acordadas; pista/álbum/playlist elegidos manualmente y cola ya creada conservan IDs/ocurrencias. Radio conserva semilla manual.
- [ ] F10 — Resolver la convivencia con PLAN-015: el buscador nuevo conserva orden del proveedor; si se aprueba priorizar versiones, será una política explícita sobre grupos equivalentes, identificable y comprobable, no una reordenación silenciosa añadida al port.
- [ ] F11 — Probar Graduation clean/explicit, desconocidos, cuenta/contexto cambiado, rollback/persistencia y edición elegida deliberadamente; arte decorativo independiente del audio.

**Salida F:** mejora común aparte, con contrato único y sin dos cores o políticas divergentes por SO. No incluirla a medias para marcar Windows «al día».

## 11. Dependencias y orden de entrega

```text
A: snapshot y verify nativo
  ├─ B1/B2: preservar contrato y preparar proyección
  │    ├─ B3: densidad y columna
  │    ├─ B4: viewport, alturas y scroll
  │    └─ B5: sugerencias y teclado
  ├─ C: letras y seek real → correcciones demostradas
  └─ D: motion WebView2/ciclo → correcciones demostradas

B/C/D → integración conjunta → E: retención y barrido → G: build/QA/entrega

F1: indicadores en ambas apps → F2: equivalencias/preferencia → entrega común posterior
```

Orden de trabajo recomendado por lotes revisables:

| Lote | Contenido | Complejidad / dependencia | Evidencia exigida |
|---|---|---|---|
| 0 | A, base y estado real del runtime | Media; acceso a Windows | Snapshot, doctor/verify y límites |
| 1 | B22…26, sugerencias; B09…14, densidad | Media; conservar contratos actuales | Componente/teclado/resize y capturas |
| 2 | B05…08 y B15…21, proyección/viewport | Alta; claves/alturas/scroll |5.000 entradas, ocurrencias, anclas y foco |
| 3 | C01…15, letras/seek nativos | Alta; audio disponible | Cues observados, pausa/restauración/EOF |
| 4 | D01…15, vídeo y ciclo nativo | Media/alta; WebView2 real | Primer frame/loop/clear/30s y señales |
| 5 | C16…20 y E01…10, actividad/retención | Alta; viewport estable | Trabajo visible acotado, navegación/fondo/AX |
| 6 | E11/G, regresiones y entrega Windows | Media; lotes anteriores | Build exacta, matriz nativa y pendientes residuales |
| 7 | F1/F2, funciones compartidas nuevas | Alta; decisión/contrato/equivalencias | Ambos consumidores y migraciones |

No se fija fecha sin el primer verify y la reproducción del seek/vídeo en destino. Esos resultados pueden convertir lotes3/4 en aceptación breve o revelar correcciones nativas sustanciales. La secuencia es válida aunque una sola persona la ejecute; no presupone agentes ni tareas remotas en marcha.

## 12. Matriz mínima de aceptación

| ID | Escenario | Resultado requerido |
|---|---|---|
| S01 | DUCKWORTH., Kendrick Lamar, To Pimp a Butterfly | Principal canción/artista/álbum con jerarquía correcta; no exigir resultados idénticos a otra fecha/cuenta |
| S02 | Sin principal, roles inválidos, metadata ausente y duplicados | Secuencia completa y payload por ocurrencia; acciones según capacidad |
| S03 |6 textos +2 canciones; campo vacío; borrar historial | Máximo3 textos con query y todas las entidades; vacío sin recorte; feedback con token propio |
| S04 | Foco/clic exterior/Spotlight/IME/Escape/Enter | Sin salto/submit accidental; clic único llega al destino; foco restaurado |
| S05 |5.000 resultados, append, expansión y resize | Nodos acotados, ancla estable, sin pérdida de filas/tokens/menú |
| S06 | Query/filtro/cuenta/cursor cambiados durante solicitudes | Respuestas antiguas descartadas y retry del estado correcto |
| L01 | Rico, Original, fallback, refresh, error, instrumental y Genius | Estado/menú correctos; mismo tamaño/manual y nada de otra pista |
| L02 | Voces/Unicode/wrapping/interludios y duración tardía | Texto/timing íntegros, sin blur manual ni interludios falsos |
| L03 |5 cues, clics rápidos, pausa, restauración, EOF y duplicados | Último cue válido; confirmar posición real y propietario; error/deadline explícitos |
| L04 | Scroll manual/Volver/resize/cambio renderer | Manual conserva lectura y blur0; Volver/clic siguen al ancla válida |
| M01 | Vídeo frío/caliente, loop, ausente/error y frame tardío | Imagen siempre disponible; vídeo sólo vigente; música continua |
| M02 | Mismo/otro álbum, OFF/ON, pausa/reverso/30s y clear concurrente | Reuso/liberación/cancelación correctos; sin handles bloqueados |
| M03 | Sin foco/minimizada/restaurada/cloaked/ahorro/memoria | Aplicar política real; documentar oclusión/thermal no cubiertos |
| N01 | Diez ciclos principales/Spotlight/fullscreen/cuenta | Restauración de estado, fondo conservado donde corresponde, AX inactivo oculto |
| R01 | Cola/radio/playlist/SMTC/volumen/Genius/idiomas | Ninguna regresión en flujos existentes representativos |
| P01 | Instalador y portable en host limpio; actualización desde instalada | Arranque y runtimes correctos, persistencia y versión sin aviso repetido |

Matriz geométrica: ventanas960×640,1280×720,1440×900,1920×1080 y2560×1440 **cuando el área de trabajo lo permita**; sidebar abierta/cerrada, DPI100/125/150/200 y texto ampliado. Registrar ancho/alto CSS del contenido; a DPI alto una ventana lógica mínima puede no caber en una pantalla física pequeña: comprobar el caso compatible, no forzar dimensiones imposibles. Probar borde de composición C679/680/959/960 con fixture/host de área adecuada.

Matriz de plataforma: Windows10 y11 x64 dentro del soporte declarado, versión WebView2 anotada, GPU/hardware y reproducción por software si está disponible. Accesibilidad: Narrator, teclado, contraste del sistema y Reducir movimiento. Cuenta invitada y cuenta autorizada tienen recorridos distintos; no falsear cobertura de sesión con mocks.

Cada caso queda como aprobado/fallido/no ejecutado, con fuente/build/host y evidencia. Captura, test, audio y perfil son evidencias diferentes; compilar o ver una máscara no acredita sonido ni FPS.

## 13. Etapa G — Comprobaciones, build y entrega

### Comandos de verificación

Frontend desde `windows/`:

```sh
pnpm check
pnpm test
pnpm build
```

Runtime desde la raíz **en Windows**:

```powershell
./windows/scripts/windows.ps1 -Action doctor
./windows/scripts/windows.ps1 -Action verify
```

Build local desde la raíz, aplicando antes [sideb-build-windows](../../.agents/skills/sideb-build-windows/SKILL.md):

```powershell
node Scripts/build-version.mjs windows
```

`verify` cubre frontend, core con/sin windows-bridge, player y Tauri según runner vigente. Si cambia contrato común en una tarea posterior, ejecutar sus suites/consumidores y regenerar bindings por el flujo oficial. No alterar cfg/recursos para presentar una compilación Mac como prueba Windows.

- [x] G01 — Check/test/build frontend finales y diff/whitespace propios aprobados;479pruebas/1omitida Windows,0fallos y check0/0. Core+bridge284aprobadas/10omitidas. Nativos necesarios separados en G02; sin formato masivo/cambios ajenos.
- [x] G02 — Doctor/verify Windows sobre13011e7 aprobados:480frontend+112InnerTube+170core+172bridge+5player+115Tauri;1054aprobadas/0fallos,10live omitidas por variante core. [PLAN-019 §8](PLAN-019-windows-github-handoff.md#8-ejecución-en-la-pc-2026-10-2627).
- [x] G03 — `builds/windows/build-0021/BUILD.json`: compiled, Release x64, fuentes estables; cuatro hashes y PE/version comprobados. EXE/DLL/licencia conservados juntos. No implica QA audible/visual.
- [ ] G04 — Ejecutar matriz mínima sobre esa build y host real; registrar los pendientes sin sustituirlos por conteos históricos o CI.
- [ ] G05 — Revisar funcionamiento combinado búsqueda→play→lyrics→motion→cambio de pista→volver a búsqueda, incluidos overlay, sidebar y cambio de cuenta. Las pruebas aisladas de cada función no cubren esa composición.
- [ ] G06 — Instalación/portable/actualización cuando corresponda a la entrega autorizada; no bump de versión pública, push, tag o publicación por el mero cierre del port.
- [x] G07 — Correcciones registradas en FIX-248…255 [Windows]; PAR-042/037/038/039/031/028/043 y planes actualizados con evidencia y límites propios.
- [x] G08 — Build0021 y registro entregables con rutas exactas, pruebas y límites en PLAN-019 §8. G04/G05 y paridad física permanecen abiertos: usuario detuvo Computer Use con Escape antes de abrir0021.

No hace falta repetir toda la suite después de cada cambio documental; las pruebas de producto se ejecutan por lote y al integrar fuentes finales. Pruebas nuevas deben cubrir regresiones observables: orden/identidad, foco, altura, ventana de DOM, confirmación de seek o liberación de vídeo.

## 14. Rendimiento: criterio y límites de esta planificación

La revisión funcional de fluidez en Windows forma parte de la aceptación. Un benchmark/perfil instrumental adicional se organiza como tarea específica; **no reabre el A/B de Mac cancelado** ni promete120Hz o60fps del renderer por tener una fuente60.

Si se solicita medición, usar el mismo host/build/configuración/viewport/corpus, separar reposo, scroll cargado, barrido, buffering y motion frío/caliente; medir proceso app/WebView/GPU cuando sea posible. Conservar trazas comparables, tiempos de entrada/layout y CPU/memoria. FPS/P95/P99 sólo se informan si se recolectaron frames válidos con una herramienta adecuada; contar rAF o fps declarados del vídeo no prueba presentación.

Invariantes verificables desde ahora: sin RPC ni descarga por frame; proyección de búsqueda por revisión; DOM de búsqueda acotado; geometría de palabras visible; reloj vinculado a audio observado; páginas ocultas sin actividad innecesaria; un solo consumidor decorativo de vídeo y liberación tras30s. El perfil decidirá optimizaciones adicionales, no una atribución anticipada al core/sidebar/red.

## 15. Diferencias que no deben convertirse en trabajo ficticio

- FIX-259 tiene partes exclusivas de AppKit. Windows ya usa preview absoluto; sólo se trasladan las garantías de interacción y se comprueban sus casos.
- FIX-236 optimiza TextRenderer/AVPlayer. Windows conserva los principios de preparación/visibilidad/reloj local; no copia clases Swift ni se atribuye su misma mejora.
- No se porta Liquid Glass/TopNav de tres cápsulas ni un cambio de sidebar excluido previamente. Los contratos de búsqueda/foco/accesibilidad sí deben funcionar en el shell Windows propio.
- No se crea otro provider de letras/motion, ni otra caché/cola/autoplay en TS para evitar actualizar una integración.
- No se modifica el audio de un álbum clean para obtener su motion ni se infiere clean desde false o desde una portada.
- No se reescribe Recomendados como parte del cierre lyrics/motion. Si el barrido encuentra un fallo, se registra y acota con su PAR.
- No se reactiva automáticamente Apple PLAN-008 (limpieza futura de Inicio) ni material en archive/temp; tampoco se trata el port inverso de volumen exponencial como ausencia Windows.
- Textos anteriores a FIX-240 en PARIDAD/planes son diagnóstico histórico. El estado actual del consumidor rico/seek/señales nativas se lee en las secciones de ejecución y las fuentes.

## 16. Referencias técnicas externas verificadas para este plan

La arquitectura se deriva del repositorio. Estas fuentes oficiales sustentan decisiones de plataforma; no acreditan que Side B ya las haya validado en un equipo Windows:

- [Tauri2, prerrequisitos](https://v2.tauri.app/start/prerequisites/): toolchain C++ y WebView2 para desarrollo Windows; el runner del repo además fija VS2022.
- [Tauri2, instaladores Windows](https://v2.tauri.app/distribute/windows-installer/): empaquetado y distribución del runtime. Mantener el flujo oficial del proyecto.
- [Microsoft, WebView2 Controller/IsVisible](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2controller): visibilidad del WebView independiente del HWND y beneficios al ocultar. Comprobar primero qué gestiona Tauri; no suspender el audio nativo al minimizar.
- [Microsoft, DWMWINDOWATTRIBUTE](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute): DWMWA_CLOAKED describe ocultamiento por app/shell/herencia. La limitación respecto del solapamiento se mantiene explícita; no se infiere una señal general de oclusión.
- [MDN, requestVideoFrameCallback](https://developer.mozilla.org/en-US/docs/Web/API/HTMLVideoElement/requestVideoFrameCallback): callback asociado a frames enviados al compositor, con sus limitaciones; requiere comprobación en WebView2.
- [MDN, content-visibility](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/content-visibility): `auto` puede omitir render fuera de vista, conservando DOM y accesibilidad; no equivale a una lista virtual que desmonta elementos.

## 17. Cierre de esta tarea de planificación

- [x] Auditar implementación actual, antecedentes y estado de paridad, sin asumir que Windows está vacío.
- [x] Identificar port real de búsqueda reciente, puntos nativos de letras/motion y retención pendiente.
- [x] Identificar brechas adicionales de energía del reloj, costes a investigar y diferencia de procedencia de Position, sin presentarlas como fallas audibles demostradas.
- [x] Separar funciones nuevas compartidas y exclusiones de plataforma/decisiones previas.
- [x] Definir archivos de entrada, traducción técnica, dependencias, lotes y aceptación.
- [x] Ejecutar check/tests frontend actuales y registrar su entorno/alcance.
- [x] Enlazar en índice Windows y registro de paridad; conservar planes/historial previos.
- [ ] Cerrar aceptación nativa, empaquetado Windows y funciones futuras compartidas. El usuario autorizó ejecutar el26; las fuentes completadas se detallan abajo y las validaciones físicas no se marcan por tests en Mac.

La tarea original del24 sólo produjo el plan. La ejecución autorizada el26 sí modifica producto y registra FIX-248…255 en el historial único, preservando cambios previos Apple/core y búsqueda compartida.


## 18. Ejecución con subagentes —2026-10-26

Usuario: «ejecuta este plan con subagentes, chequea que ui esté igual que macOS, que funcionalidad también y arréglalo». Integración en el mismo árbol con ámbitos de escritura separados: búsqueda; letras/seek; motion. El integrador conserva shell/retención/Biblioteca y documentación. Las revisiones cruzadas posteriores incluyen búsqueda por el agente de letras y retención por el de motion; no se crean chats ni se publica código.

### Resultado implementado

- **Búsqueda/FIX-248:** proyección y documento mixto cacheados por revisión, emparejamiento ordinal seguro y fallback único; duplicados ambiguos no roban tokens. Viewport binario, alturas revisadas por contenido/ancho/idioma, ancla compensada, menú/foco conservados y expansión retenida. Nueva consulta/filtro vuelve al comienzo; append conserva offset. Diseño contra Mac0165: título40, campo completo, margen28, principal80/96, acciones centradas y artista con acciones bajo título junto a portada, fade24 y compensación de barra clásica. Máximo3 textos con query y todas las entidades; vacío sin recorte. Fallback song/video conserva Play y metadata segura aunque no tenga payload asociado.
- **Letras/FIX-249:** conserva rico/Original común, diseño36 y ajustes existentes. Original seleccionable durante carga/error/fallback; validación estricta de sesión y ocurrencia para clásico. El shell y panel usan el mismo namespace sessionRevision. Reloj visible recibe energía/memoria y minimizado/cloaked;30Hz reales incluso con rAF120Hz. Fronteras preparadas evitan polling16ms sin barrido, mapas/búsquedas temporales de gaps y Segmenter reutilizado. Escape del menú devuelve foco y forced-colors retira efectos. Estado manual/tamaño/modo siguen compartidos.
- **Motion/FIX-250:** frame presentado estando inactivo no se revela hasta reanudar; rechazo tardío de play interrumpido no retira vídeo reanudado. Clear espera consumidores aparecidos durante la eliminación y comunica errores de teardown. Identidad normaliza NFC/espacios y créditos como Mac. Mantiene runtime/DWM/30s/H.264 existentes.
- **Retención/FIX-251:** cuatro páginas principales lazy y acotadas, hosts independientes y purga DOM por sesión; páginas detrás de Spotlight conservan píxeles con inert/AX oculto. Datos/mediciones y observadores de listas/portadas se suspenden; vuelven con geometría/DPR actual. Explore conserva offset real al cubrir/revelar el mismo snapshot, navegación restaura el solicitado. Biblioteca mueve crear/refrescar a la tira de categorías sin reserva142. Imágenes ignoran errores de nodos anteriores; fondos separan visibilidad de actividad.

### Evidencia automatizada acumulada de esta ejecución

- Primera suite global integrada: **474 declaradas,473 aprobadas/1 omitida exclusiva Windows**,0 fallos. Log `/tmp/sideb-plan016-all-tests.log`; es anterior a posibles correcciones encontradas por la revisión de app completa, por lo que el cierre final registra su propio resultado.
- Check de los ámbitos integrados:0 errores/0 advertencias. Comprobación final pendiente de congelar las últimas correcciones de QA.
- Búsqueda focal:73 pruebas aprobadas; seis casos DOM internos y máximo22 entradas montadas para5.000 resultados con scroll hasta4500, append, ancla, foco, menú, consulta nueva, metadata ausente, IME y gutter17. Un carrusel o bloque expandido sigue siendo una entrada compuesta;5.000 hijos dentro de un único carrusel/related no están acreditados por esa cifra.
- Letras focal:21 pruebas y5 pruebas Rust de la máquina seek aprobadas. Corpus de preparación5.000 líneas/50.000 segmentos: prueba documento/fronteras, no DOM5.000 ni FPS/GPU.
- Motion/retención de portadas: frame/clear/runtime y montaje real con28 focales de motion, además de las regresiones de retención/Explore/portadas incluidas en la suite global. Diez ciclos conservan DOM/borrador/scroll; observers/listeners de portadas van1→0→1 y reconcilian DPR/medidas al volver.
- `cargo test --locked --manifest-path core/Cargo.toml -p innertube -p sideb-core --features sideb-core/windows-bridge` ejecutado en Mac:112InnerTube+172core=284aprobadas,10omitidas,0fallos; log `/tmp/sideb-plan016-core-bridge.log`. No cambia core ni compila Tauri/Player Windows.
- QA de app completa: `windows/scripts/plan016-browser.mjs` con RPC sintético, producción `+page.svelte` y componentes reales. Capturas/medidas quedan en `windows/.cache/plan016-browser/`; revisión en curso. Ni la cuenta fixture ni Chromium equivalen a cuenta real/WebView2.

### Pendientes que siguen abiertos

1. Host Windows x64/MSVC/WebView2 para doctor/verify, build numerada, primer frame/loop/handles/GPU, audio libmpv y cinco cues/restauración/EOF reales. El entorno comprobado es Darwin arm64; no se detectó SSH/VM/PowerShell Windows accesible. La app Codex sólo ofrece host local en esta sesión. No se modifica el runner para eludir esa condición.
2. C13 investigado: `PlayerEvent::Position(f64)` no acredita origen y Player no expone readback/ack del seek. Guards de cuenta/generación/entryId/revisión existentes se conservan. Sin reproducción nativa del caso encolado, no se atribuye defecto audible ni se introduce un ticket artificial. C14/C15 y aceptación PAR-038 quedan abiertos.
3. D14/D15 investigados: DWM-cloaked no equivale a ventana cubierta por otras ventanas y no hay thermal-state equivalente implementado. Se mantienen minimización/ocultamiento/ahorro/memoria; no se afirma cobertura total.
4. Cuenta real, Narrator, Windows10/11, DPI/texto del sistema, instalación/actualizador y barrido físico del resto de funciones. Pruebas mock/DOM y un build frontend no sustituyen esos recorridos.
5. F1/F2 siguen como entrega futura común: no hay indicadores explícito/clean/unknown completos ni equivalencias de audio implementados en Mac. Este port no introduce una política de ranking/selección divergente ni cambia core protegido sólo para Windows. Se conservan sus planes/PAR-040/041 y decisiones pendientes.
6. TopNav/materiales y shell propios Windows mantienen las exclusiones PAR-007/008 del plan. Se compara contenido/interacciones con Mac, sin afirmar reproducción literal de Liquid Glass ni de métricas de una fuente no disponible.

El A/B Mac cancelado no se reabre. No se certifica FPS ni audio por compilación. Sin commit/push/tag/release ni bump de versión pública.


### Cambio del origen durante la integración

La auditoría de hashes encontró cambios Apple ajenos en PlayerViewModel/RecommendedContentView y plan/registro, sin cambios nuevos del core. Corresponden a **FIX-247/Mac0166/PAR-043** de Relacionado. No se revierten ni se atribuyen a esta tarea. Se incorpora una extensión acotada de E11 para revisar su equivalente Windows: reciclado de columnas y controles/contexto existentes; no rediseñar fuentes ni crear otro motor. Las exclusiones de optimización de red de PLAN-013 permanecen. La referencia de búsqueda sigue Mac0165 y la de letras/motion0155.


### Regresión encontrada al montar la app completa —FIX-252

La verificación aislada de Spotlight no detectaba que el actualizador siempre montado interceptaba Escape/Tab aun cerrado. El navegador completo con +page y RPC sintético reprodujo el fallo; [FIX-252](../../FIXES.md#fix-252) hace que listener/foco/trap pertenezcan sólo al modal abierto y al diálogo propio, con guard de instalación. Regresión montada junto a Spotlight aprobada; el recorrido completo puede volver a navegar con el primer clic tras Escape. No es un ajuste de la fixture para saltarse el teclado. La configuración de cuenta y los comandos de actualización siguen simulados.


### Extensión acotada de Relacionado —FIX-253

El lote E11 incorpora la referencia Mac0166 sin alterar proveedores ni el motor compartido. [FIX-253](../../FIXES.md#fix-253) implementa viewports binarios vertical/horizontal con columnas270px, tres filas52px/huecos6px y clip168px; artistas76px/columna86px/clip118px. Controles comunes y Play/Pause reflejan la pista actual. requestIdentity/contextKey y suspend aíslan contexto/cuenta/respuestas tardías; offsets sobreviven refresh y reciclado y se purgan por contexto. La suspensión invalida aceptación, no cancela una RPC nativa ya iniciada.

Revisión cruzada encontró dos P2 reales: popup por teclado no pinneaba origen y overscroll contain de ambos ejes bloqueaba rueda vertical sobre canciones. Ambos corregidos;15focales controller/geometría/montaje real aprobadas. Fixture5000canciones+5000artistas con máximos4columnas/7artistas, fila4500, duplicados, foco/menú Shift+F10, reciclado/offset, contexto/cuenta y teardown. Cableado onSuspend verificado en +page/FullscreenNowPlaying. No acredita Narrator/WebView2/rueda física/FPS ni cuenta/audio real.


### Estado de cierre por lote

| Lote | Fuentes y pruebas realizadas aquí | Aceptación que sigue abierta |
| --- | --- | --- |
| A/B, buscador | FIX-248;80pruebas búsqueda/actualizador, app completa,8tamaños/DPR/sidebar y12casos principal/gutter17; documentos5000 y teclado/menú | WebView2, proveedor/cuenta real, reproducción/radio y navegación física |
| C, letras/seek | FIX-249; fuente Original, scope, reloj/ahorro/fronteras y corpus; renderer/menú/manual reales en navegador | Cues audibles/libmpv/EOF/restauración, Narrator y matriz Unicode/DPI nativa |
| D, motion | FIX-250; carreras de frame/play/clear, fallback, energía/visibilidad controladas y contrato runtime | H.264/WebView2, frame/loop/GPU/handles, señales Win32 en host real |
| E, shell/Biblioteca | FIX-251;retención/scroll/AX y observadores, suspensión/reentrada/DPR y cuenta sintética | Memoria/latencia medidas, interacción física y mutaciones autorizadas con cuenta real |
| E11, Relacionado | FIX-253;15focales,5000+5000, columnas/filas/menús/contexto, renders340/600 y rueda en Chrome | WebView2/Narrator/trackpad físico/cuenta y audio/FPS |
| Composición | FIX-252; modal cerrado ya no captura teclado; app completa usa componentes de producción con bridge sintético | Instalador/actualizador Windows real |
| F, funciones comunes futuras | Diseño/precondiciones conservados; no existe paridad Mac que trasladar todavía | Indicadores y política de ediciones requieren entrega compartida y decisiones documentadas |
| G, entrega | Frontend compilable y evidencia reproducible; sin versión/release pública | Doctor/verify/EXE y recorrido Windows x64/MSVC/WebView2 |

Las casillas de aceptación física no se marcan por pruebas sintéticas. El límite de este host impide cerrar el plan completo: la siguiente etapa requiere Windows; no se presenta el sitio estático como ejecutable Windows.


### Revisión visual final —FIX-254

La inspección del integrador de lyrics-new detectó cierre fullscreen absoluto sobre el último tab en960px/sidebar colapsada. [FIX-254](../../FIXES.md#fix-254) reserva celda32px+gap12 y usa ancho local para etiquetas. Matriz de cuatro geometrías960/1440×sidebar comprueba intersección vacía y hits de cierre/tres tabs. Mantiene grid/proporciones del contenido. Revisión independiente Relacionado340/600 compara medidas con Mac0166 y corrige radio2px sólo en su portada. Rueda vertical del Panel real llega91px (máximo disponible) y horizontal200px; clip168 contiene la tercera fila exactamente, arte44/avatar76/columna270. Evidencia `.cache/related-review-browser/evidence.json`; no mide FPS ni entrada física Windows.


### Cierre frontend de la ejecución —2026-10-26

- Check final: **0 errores y0 advertencias**. Suite final: **480 declaradas,479 aprobadas/1 omitida exclusiva Windows,0 fallos**. Build estático aprobado en `windows/build/`; conserva aviso de chunk principal>500kB, sin atribuir mejora de FPS/CPU por compilación. No es un EXE.
- Core+bridge en este Mac: **284 aprobadas/10 omitidas/0 fallos**; no ejecuta player/Tauri Windows. Máquina seek aislada:5aprobadas. Los focales están incluidos cuando corresponde en las suites, no se suman otra vez como pruebas distintas.
- Navegador final: **28 evidencias y errors[]**, con componentes de producción/+page y RPC sintético: retención/Spotlight/AX/scroll,8combinaciones960…1920×DPR1…2×sidebar,12principales canción/artista/álbum con scrollbar CSS real17px, preview3+2/clic exterior sin salto,5000resultados profundos, cuatro layouts fullscreen con hit targets separados, letras rico→Original/manual y purga de DOM al cambiar cuenta fixture.
- [FIX-255](../../FIXES.md#fix-255) corrige el menú de letras recortado por altura de ventana: ahora cabe dentro del panel. La aserción comprueba hit real del último botón y cambio de etiqueta a Usar nuevas letras; manual=true solo no era evidencia suficiente. Capturas `lyrics-options-source.png` y `lyrics-original.png` inspeccionadas.
- Corridas intermedias se interrumpieron al cerrar Chrome con código0/CDP1006, sin excepción JS de producto observada; stderr también registró errores CVDisplayLink del host. No se afirma una causa única. La corrida completa final usa **Chrome con GPU desactivada** y espera del harness en Node; conserva mediciones/acciones de DOM reales. Comando reproducible desde windows: `SIDEB_BROWSER_SOFTWARE=1 SIDEB_BROWSER='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' node scripts/plan016-browser.mjs`. No certifica compositor/GPU ni WebView2.
- Evidencia local: `windows/.cache/plan016-browser/results.json` y PNG, `windows/.cache/related-review-browser/evidence.json`/renders340/600, logs y manifiesto final en `windows/.cache/plan016-execution-20261026/`. La validación compara hashes de267fuentes/tests/configs Windows antes/después para detectar cambios durante check/test/build; no representa un fingerprint completo del repositorio. Incluye archivos nuevos sin seguimiento.
- Entorno: Darwin arm64, Node24.16.0 y pnpm local11.25.0. El paquete/CI declara12.6.0; no se cambió el gestor ni lock por rutina. El runner oficial Windows debe usar su entorno fijado.
- FIX-248…255, PARIDAD e índices actualizados; diff/whitespace Windows/documentos propios limpio. Cambios previos Apple/core preservados; sin commit/push/version bump/build pública.

**La ejecución local termina con producto modificado y comprobado en frontend.** A04/A05 y G02…G04/G06, audio/seek real, H.264/WebView2/Win32/DPI/Narrator y aceptación física siguen abiertos por falta de host Windows. E12 no ejecuta mutaciones reales de cuenta. F permanece entrega futura compartida. No se cierra la paridad nativa ni se entrega una build ficticia.


## 19. Traspaso a GitHub y Windows —2026-10-26

Este plan era PLAN-016 local y pasa a018 al integrar origin/main f91f2de: GitHub ya publicó otro PLAN-016 Windows de karaoke y PLAN-015 sidebar. Proveedor pasa a017; el [PLAN-019](PLAN-019-windows-github-handoff.md) es la entrada para bajar en PC, compilar y continuar. Publicados FIX-241…244 conservados; IDs locales provisionales de búsqueda241/242 y Mac243/244 pasan a256/257/258/259 en el registro integrado. No reinterpretar referencias numéricas de capturas/builds locales antiguas como si correspondieran a la release1.2.7.

Se integra el port con Inter, tinta base/relleno movida por fragmento y halo del blur ya publicados; el comienzo exacto de palabra sigue despertando el sweep. La primera suite integrada detectó fuente editorial ES/EN faltante y expectativa antigua de capas en la fixture: se incluyen dependencias y se verifica propiedad de tinta activa en lugar de preservar un conteo obsoleto. QA integrada carga las mismas fuentes Inter locales que +layout;28evidencias/errors[] aprobadas. Resultado final de check/tests/build y subida en PLAN-019/FIX-260. La evidencia previa479/284/28 se conserva como antecedente de la ejecución anterior; no se afirma identidad de todas las fuentes tras integrar GitHub.
