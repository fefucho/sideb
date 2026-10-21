# Rendimiento de Letras en macOS — auditoría del 2026-10-21

- Estado: auditoría completada; propuestas pendientes de revisión, sin optimizaciones aplicadas.
- Base: código compilado en build0146 Release, versión1.2.6/build19; checkout907ac01 con los cambios locales anteriores preservados.
- Pedido: estudiar carga y lag de Letras, relación con la sidebar nueva y actividad de fondo. Recomendados se inspeccionó sólo para determinar si participa; no se modificó ni se propone optimizarlo en esta entrega.
- Método: revisión del integrador y tres subagentes GPT-6.1 Sol medio; recorrido de código, caché SQLite de sólo lectura y microbenchmarks aislados con texto sintético. No se inició otra build ni se modificaron fuentes, preferencias o datos del usuario por esta auditoría.
- Límite: el Mac bloqueado impide una nueva sesión controlada de Instruments y la comprobación visible de0146. No se midieron FPS, latencia de proveedores ni carga CPU/GPU de la app real. La aceptación visible de FIX-234 sigue pendiente. Las trazas antiguas son antecedentes, no mediciones de0146.

## Qué encontré

Hay dos problemas distintos que conviene medir y resolver por separado:

1. **Tardar en mostrar la letra:** existen búsquedas clásicas y experimentales independientes, cascadas de proveedores, resultados cacheados que no se muestran de inmediato y peticiones que pueden continuar después de abandonar el panel. Es trabajo real comprobado en el código.
2. **Tirones cuando la letra ya está cargada:** el karaoke recompone texto enriquecido y realiza dibujo personalizado con geometría por palabra, varias pasadas, máscaras y efectos. Es el primer candidato para perfilar. El microbenchmark encuentra mucho más coste en esa ruta que en recorrer los tiempos, pero no demuestra cuánto pesa en una ventana real.

La sidebar puede contribuir, especialmente durante su animación y cargas iniciales: permanece montada incluso cerrada y no recibe suspensión de imágenes. Sin embargo, usa colecciones lazy y no hay evidencia de que cargue toda la biblioteca ni de que reciba cada tick del audio. **No hay base para declararla la causa principal del lag sostenido de Letras.**

Recomendados no se monta como panel mientras Letras está seleccionado. Puede terminar una petición que se inició antes, y el Inicio retenido mantiene algunas tareas globales; eso es distinto de estar renderizando continuamente la pestaña Recomendados.

El fallo de tiempos casi cero corregido en FIX-234 explicaba los saltos al inicio y el foco al final; no es una medición de rendimiento. Las comparaciones futuras deben hacerse sobre0146 para evitar confundir ese error funcional con tirones de dibujo.

## 1. Qué sucede al cargar una canción y abrir karaoke

### Dos rutas de letras pueden consultar la misma canción

`PlayerViewModel.playSongNow` llama a `loadLyrics` antes de resolver el stream, aunque el usuario use karaoke. Al activar «Probar nuevas letras», `FullscreenNowPlayingView` crea otra petición y el controller llama a `getKaraokeLyrics`. Conservan APIs, cachés y presentaciones separadas; no encontré coordinación de peticiones en vuelo entre ambas rutas.

Esto permite dos consultas a Boidu/LRCLIB para la misma canción. No significa que siempre haya dos descargas: un acierto de caché puede resolver una ruta inmediatamente. Tampoco hay peticiones de letras por frame.

Evidencia: `apple/Sources/SideB/ViewModels/PlayerViewModel.swift:885–897,1249–1284`; `Views/Fullscreen/FullscreenNowPlayingView.swift:107–109,638–656`; `ViewModels/ExperimentalLyricsController.swift:133–164`.

### La primera letra visible puede esperar varios servicios

| Ruta sin acierto de caché | Comportamiento comprobado | Consecuencia posible |
|---|---|---|
| Clásica | Consulta `next()` de YouTube antes de Boidu; después puede recorrer Boidu, LRCLIB exact, YTM timed, NetEase, QQ, KuGou, LRCLIB fuzzy y respaldos plain | Una respuesta rápida de letras puede quedar detrás de otra petición lenta; no se publican resultados intermedios |
| Experimental | Boidu y luego LRCLIB; límites de petición8s y5s | La degradación puede consumir aproximadamente13s de presupuestos de red, más el resto del procesamiento; no es una latencia medida |
| Respaldo clásico del experimento | Se lee antes de consultar proveedores, pero se devuelve al terminar los intentos frescos | Puede existir texto local usable y aun así mantenerse el estado de carga |
| Refresh experimental | Omite su caché experimental y el respaldo de caché clásica | Actualizar puede ser sustancialmente más lento que reabrir un acierto válido |

Clásico tiene límites mayores: LRCLIB15s por consulta; NetEase/QQ pueden hacer dos solicitudes de8s, y KuGou tres. InnerTube tiene un timeout de60s por petición y hasta tres intentos para ciertos errores de transporte. **No deben sumarse como si cada canción consumiera el peor caso**: hay retornos anticipados, errores distintos y aciertos de caché.

Evidencia: `core/crates/sideb-core/src/lyrics.rs:126–160,184–308,332–337,634–841`; `lyrics/karaoke.rs:145–205,310–333,437–456`; `core/crates/innertube/src/transport.rs:145–146,298–349`.

### Cancelar la presentación no equivale a cancelar la red

El controller cancela su `Task` y rechaza respuestas viejas por revisión, cuenta y ocurrencia. El puente generado `uniffiRustCallAsync` usa continuación/polling y no enlaza esa cancelación de Swift con una cancelación del futuro Rust. Una consulta ya iniciada puede seguir hasta terminar y guardar caché aunque su resultado ya no se aplique a la pantalla.

Además, duración, álbum y artista participan en la identidad de petición. El enriquecimiento de metadata puede reiniciar una carga provisional. Esto es especialmente relevante al cambiar de canción rápidamente o entrar/salir del experimento, no como explicación automática de lag estable varios minutos después.

Evidencia: `ExperimentalLyricsController.swift:73–101,104–130`; `FullscreenNowPlayingView.swift:638–645`; `PlayerViewModel.swift:330–339,1213–1244`; `apple/SideBCore/Sources/SideBCore/sideb_core.swift:7095–7123`.

### Los payloads de letras no parecen enormes

Lectura local de sólo lectura, con tamaño UTF-8 del payload persistido:

| Caché | Filas | Payloads presentes | Total | Mediana por payload | Máximo |
|---|---:|---:|---:|---:|---:|
| Clásica | 378 | 366 | 6.126.059 bytes | 7.409,5 bytes | 160.361 bytes |
| Experimental, todos los prefijos `karaoke:` | 10 | 10 | 235.212 bytes | 25.482,5 bytes | 45.046 bytes |

La distribución no es una tasa de aciertos y no demuestra qué resultados siguen vigentes. Sí indica que no hace falta una letra de megabytes para que este caso tenga lag. No se exportaron letras comerciales ni datos de cuenta al reporte. Resumen reproducible ignorado por Git: `.cache/lyrics-performance-2026-10-21/cache-size-summary.json`.

## 2. El karaoke no se dibuja como un Text estático

### Trabajo que continúa después de cargar

| Cadencia / evento | Trabajo |
|---|---|
| Audio general, intervalo solicitado0,1s | Actualiza tiempo/progreso de la barra y procesamiento de reproducción |
| Reloj experimental, intervalo solicitado0,1s | Consulta el tiempo real de AVPlayer y reconcilia foco/actividad |
| Mientras cambia una palabra y la ventana está visible | Un Timer local solicita60Hz;30Hz con ahorro de energía. Son intervalos solicitados, no FPS garantizados |
| Interludio animado | Pulso de30Hz para los puntos |
| Fronteras de palabras/líneas/esperas | AVPlayer añade callbacks de frontera que también muestrean el reloj |
| Cambio de frase | Cambian foco y distancia de filas, se animan blur/escala y se centra el scroll |
| Actualización y dibujo de fila rica activa | El body recompone `Text` al actualizarse; `draw` construye geometría y dibuja runs, relleno y efectos. No son necesariamente llamadas uno a uno |

El diseño ya limita parte del daño: sólo las filas activas/enfocadas leen la posición por frame; el padre observa conjuntos y foco que cambian en fronteras. Filas futuras/pasadas usan estados asentados. Por tanto **no es correcto afirmar que toda la app o todas las letras se reconstruyen60veces por segundo**.

Evidencia: `Services/Player/AudioPlayerService.swift:273–314`; `Views/Fullscreen/Lyrics/ExperimentalLyricsClock.swift:42–53,146–208`; `ExperimentalLyricsPanel.swift:136–148,364–391`.

### Candidatos concretos en el renderer

- `ExperimentalKaraokeText.composed` recorre segmentos y crea el `Text` con atributos en cada evaluación del cuerpo. Los segmentos del modelo están preparados, pero el objeto de texto enriquecido se vuelve a construir.
- `draw` de la fila activa llama a `wordGeometry`: arma diccionarios y arrays de fragmentos, ordena y calcula anclas. Para cada fragmento revisa las demás anclas de su renglón. Hay una componente cuadrática respecto de palabras por renglón, además del resto de la construcción.
- Cada run temporizado puede dibujarse como base y como parte iluminada. Durante el barrido crea una capa con máscara de gradiente; puede añadir sombra/brillo, transformación y elevación. Las filas contextuales añaden blur y escala; el scroll completo tiene otra máscara vertical.
- Reducir movimiento elimina efectos decorativos y blur contextual, pero conserva el relleno karaoke. No equivale a convertir el renderer en texto plano. Leer o volver al panel clásico permite una comparación más limpia de rutas, aunque sus layouts también difieren.

Evidencia: `ExperimentalKaraokeText.swift:20–49,69–126,149–194`; `ExperimentalLyricsPanel.swift:170–180,364–391`; `ExperimentalLyricsStyle.swift`.

Primera propuesta para después de medir: separar composición/layout estáticos del progreso, reutilizar geometría por texto/fuente/ancho/dirección, y evitar reconstrucciones cuando sólo avanza el tiempo. La caché debe invalidarse correctamente con resize, tamaño, traducción y Unicode; no basta cachear por índice de frase.

### Reloj y montaje: hay trabajo repetido, pero no todo merece la misma prioridad

El reloj recorre grupos/líneas para foco y actividad. No dispone de un índice incremental para esas consultas. Sin embargo, el ensayo aislado de letras normales muestra un coste pequeño: no empezaría por reescribirlo antes de perfilar composición y dibujo.

`ExperimentalLyricsPanel.init` evalúa `Self.items` para el valor inicial del State; `startClock` lo vuelve a calcular y `clock.start` vuelve a calcular esperas. Es trabajo redundante por montaje/reconstrucción, **no se ha probado que ocurra por frame**. Un `Equatable` del lifecycle también puede comparar el documento completo, aunque arrays que compartan almacenamiento pueden resolver igualdad mediante caminos rápidos. No se encontró hashing de todo el documento por frame.

Hay dos oportunidades más acotadas: durante interludio/outro el foco anterior persiste y `active = isFocused || isAnimated` mantiene suscrita su fila con palabras. Los ticks de puntos a30Hz pueden reconstruir esa frase ya cantada; en un gap sin pulso puede suceder a10Hz. Y ocultar la ventana detiene el Timer rápido, pero no retira el observer periódico0,1s ni las fronteras mientras el panel siga montado. `onDisappear → stop` sí retira todo. Son flujos evitables comprobados, sin un coste medido en la app.

En un clic hay un centrado inmediato y puede programarse otro cuando cambia el foco; las revisiones descartan peticiones diferidas antiguas, pero no son un cancelador de una animación de scroll ya iniciada. El scroll experimental y los cambios de contexto usan una respuesta/duración cercana a0,788s: también hay que separar una transición visual deliberada de un hitch del render. Es candidato para contar comandos/animaciones en saltos rápidos, no causa demostrada del antiguo salto al fondo: ese síntoma se explicó por los tiempos casi cero.

El clásico usa `VStack` para todas las líneas y calcula el foco desde `currentTime`; el experimento usa `LazyVStack`. Una conversión general a `VStack` podría empeorar letras largas. Primero medir cuántas filas viven y cuánto layout hacen.

Evidencia: `ExperimentalLyricsPanel.swift:27–33,196–215,248–303`; `ExperimentalLyricsClock.swift:31–38,146–159`; `ExperimentalLyricsSequence.swift:11–41`; `FullscreenNowPlayingView.swift:808–822,865–881`.

### Microbenchmarks nuevos: útiles para priorizar, no para anunciar FPS

Fuentes copiadas con hashes, fixtures propias y compilación optimizada de probes independientes en el mismo Mac M1Pro. No abren la app ni descargan datos. El tick del modelo reproduce las búsquedas/conjuntos y excluye Observation, AVPlayer y SwiftUI; la secuencia usa las funciones extraídas. El ensayo de dibujo recrea un `ImageRenderer`, layout y bitmap por muestra. No representa la reutilización del layout en la ventana real, el compositor ni su GPU.

| Modelo sintético | Consulta foco/activos/esperas/palabras, mediana | Construcción de secuencia, mediana |
|---|---:|---:|
| 80 líneas /480palabras | 0,720µs | 47,35µs |
| 400 líneas | 2,131µs | 233,83µs |
| 4.000 líneas | 21,633µs | 2.648,73µs |

Ensayo de raster: tres frases sintéticas de seis palabras,36pt, ancho420, padding32, escala2,25 renders nuevos por variante, excluyendo cinco muestras iniciales. M1Pro/macOS27.0/Swift6.4; ejecutables con `swiftc -O -target arm64-apple-macosx15.0`. No se ejecutó en macOS15. Hay18rangos temporizados; no se instrumentó el número real de glifos/runs:

| Variante aislada | Mediana | P95 |
|---|---:|---:|
| Texto simple | 1,995ms | 2,249ms |
| TextRenderer contextual, `active=false` | 10,924ms | 11,054ms |
| Barrido sin movimiento | 11,297ms | 11,506ms |
| Barrido con efectos | 11,640ms | 12,590ms |

En este ensayo la ruta rica es más costosa incluso en contexto sin barrido. Eso invita a separar composición/layout del efecto antes de atribuir todo al brillo. Las tres filas simultáneas son un caso sintético, no un recuento de la app. El barrido sin movimiento usa Reducir movimiento; contexto desactiva active. El P95 es una aproximación con20muestras útiles, no un estudio estadístico amplio ni una ejecución aleatorizada. **No convertir estos milisegundos a FPS, multiplicarlos por60 ni usarlos como porcentaje del hilo principal.** No son un perfil de0146 ni prueban que ese coste se pague completo en cada frame.

## 3. Sidebar nueva: qué puede influir y qué no está demostrado

La sidebar se construye siempre desde el shell. Cerrarla aplica desplazamiento y, según Reducir movimiento, opacidad; también desactiva hit testing y accesibilidad. No la desmonta ni le propaga un estado de actividad para suspender imágenes. `CachedAsyncImage` hereda actividad predeterminada true fuera de las páginas retenidas: las tarjetas ya montadas pueden conservar/completar cargas aunque queden fuera de pantalla.

Eso es un punto a mejorar o medir, pero tiene límites importantes:

- Colección usa `LazyVStack`/`LazyVGrid`, pestaña seleccionada y tarjetas `Equatable`. No encontré una construcción eager de toda la biblioteca al abrir Letras.
- Los menús calculan sus hechos al abrirse; no hay que contabilizarlos como trabajo continuo sólo por existir el botón.
- Shell y sidebar no leen directamente `currentTime` en su cuerpo. Pasar un PlayerViewModel observable no los suscribe automáticamente a todas sus propiedades.
- Abrir/cerrar la sidebar cambia el ancho disponible del foreground y puede modificar el ancho de Letras y el tamaño de artwork durante la transición; sus límites pueden conservar alguno de esos tamaños. Puede provocar nuevo wrapping/layout/geometría de texto junto al trabajo de glass y composición. Esta combinación es un candidato especialmente claro para tirones durante la animación, no evidencia de que la sidebar explique todo el lag con ella quieta.

Propuesta posterior: añadir actividad/visibilidad a las cargas de la sidebar conservando estado y scroll; medir el beneficio antes de desmontarla. Comparar panel quieto y transición por separado.

Evidencia: `SideBApp.swift:537–572`; `Views/Sidebar/SidebarStyledContent.swift:176–181,200–239,299–309`; `Views/Common/CachedAsyncImage.swift:22,47–92`; `Views/Components/RetainedMainPages.swift:3–10`; `Views/Fullscreen/FullscreenSceneLayout.swift:47–55`.

La dependencia de Observation se determina por las propiedades leídas, no sólo por compartir una referencia. La recomendación de reducir trabajo por evaluación y acotar dependencias coincide con [Demystify SwiftUI performance, Apple](https://developer.apple.com/videos/play/wwdc2023/10160/); no sustituye una medición de los bodies concretos de Side B.

## 4. Qué más vive mientras se ven Letras

| Componente | Estado comprobado | Tipo de coste / interpretación |
|---|---|---|
| Carátula grande | Visible; target1200×1200 y fallback de URL | Red/decodificación al cambiar, textura retenida y composición. ImageCache usa límite de downsample2×: hasta2400px por lado si la fuente lo permite; no es una medición de tamaño real |
| Fondo fullscreen | Siempre montado; visible mediante opacidad, imagen objetivo300 y blur75 sobre la ventana | Candidato GPU/composición. No encontré un reloj propio ni una animación ambiental continua en este backdrop |
| Reverso de carátula / información | Montado en el mismo ZStack, oculto con opacidad y rotación; contiene descripción/créditos/ScrollView | Mantiene árbol/layout/AX cuando hay datos. No demuestra rasterización completa de una capa transparente; sí justifica comparar carga diferida del reverso |
| Barra flotante y motor de audio | Activos | Progreso10Hz, controles y reproducción; actividad esperada que debe mantenerse |
| Genius | Caché local al preparar canción; si autofetch está habilitado, se programa aproximadamente1s después de solicitar `audioService.play`; puede coincidir con buffering | Resolución, letra y hasta dos páginas de anotaciones; puede continuar sin abrir Genius. La configuración local consultada lo tenía habilitado |
| Álbum / metadata | Petición de álbum si falta nombre y hay ID | Carga puntual; puede enriquecer identidad y reiniciar una consulta provisional de letras |
| Radio / automix / cola | Según contexto y proximidad al final | Puede extenderse cuando quedan dos pistas o menos; no es el render de Cola |
| Historial | Al alcanzar30s o la mitad de pista, lo menor | Red/DB y sincronizaciones puntuales |
| Inicio retenido | Sigue en memoria; recibe actividad false al cubrirse | Feed/saludo/cargas visibles y animación ambiental tienen suspensión; no vuelve a renderizar todo el feed por el simple hecho de retenerlo |
| Fondo de Inicio | Montado salvo preferencia Liso; fullscreen entra en `isObscured` | Detiene drift y resolución de paleta. Pueden terminar fades/frames pendientes; no hay evidencia de bucle ambiental continuo debajo de Letras |
| Biblioteca / sincronización suplementaria | Fuera del contrato de visibilidad de la página | Playlists/álbumes/historial y prefetch de Inicio ya iniciado pueden completar. Este último admite hasta tres continuaciones y comprueba un presupuesto12s antes de iniciar cada una; una petición en vuelo puede excederlo |
| Recomendados fullscreen | Rama no seleccionada, no montada junto a Letras | Una consulta anterior puede finalizar después de salir. Se deja expresamente fuera de optimizaciones |

La caché de imágenes ya reutiliza memoria/disco y peticiones en vuelo, hace downsample y usa trabajo de fondo. Tiene un presupuesto configurado de150MiB de RAM y200MiB de disco; **no son consumos medidos de esta pantalla**. Cancelar la vista no necesariamente cancela sus tareas compartidas internas. Una imagen máxima de2400²×4 representa aproximadamente22MiB sin compresión, pero una fuente menor consume menos y no se midió ese tamaño en la app.

Evidencia principal: `FullscreenNowPlayingView.swift:147–185,214–275,440–480`; `FullscreenBackdrop.swift:33–65`; `Utilities/ImageCache.swift:37–94,105–151,158–185`; `ViewModels/GeniusViewModel.swift:62–104,298–370`; `ViewModels/PlayerViewModel.swift:343–377,869–897,1213–1246,1288–1458,1474–1578`; `SideBApp.swift:416–428,518–638,776–797`; `HomeViewModel.swift:408–438`; `Views/Home/HomeFeedTableView.swift:235–247,513–558`.

Por tanto, **ver texto no implica tener una pantalla compuesta solamente por texto**. Hay audio, imágenes, vidrio, blur, máscaras y servicios paralelos, con cadencias y duraciones diferentes.

## 5. Qué está bien delimitado y conviene conservar

- El audio sigue usando el tiempo real de AVPlayer; no hay que arreglar rendimiento con un contador alternativo que pueda desincronizar.
- El pulso rápido depende de reproducción, visibilidad de ventana y palabras/esperas cambiantes. Pausa, buffering y ventana oculta reducen trabajo; abandonar el panel desmonta su reloj.
- Foco y actividad se publican sólo cuando cambian; las filas contextuales no necesitan progreso60Hz.
- Inicio ya tiene un contrato de suspensión bajo fullscreen, conservando scroll y contenido. Reemplazarlo por un desmontaje masivo puede perder estado o empeorar la vuelta.
- Cola, Letras y Recomendados son ramas de un switch, no tres paneles completos renderizados simultáneamente.
- Sigue pendiente cruzar la visibilidad de la fila activa con el scroll manual: el reloj puede mantener el pulso aunque el usuario esté leyendo lejos de la frase que suena.

Estas protecciones existen en el código, pero no certifican ausencia de regresiones ni un objetivo de FPS. [TextRenderer](https://developer.apple.com/documentation/swiftui/textrenderer) permite controlar el dibujo; el trabajo concreto de iteraciones, capas y máscaras descrito aquí procede del renderer de Side B.

## 6. Orden propuesto para mejorar después de revisar este reporte

| Prioridad | Trabajo propuesto, aún no autorizado para implementación | Qué debería mejorar / cómo comprobarlo |
|---|---|---|
| 1 | Medir una baseline0146 con caché caliente/fría y marcas por etapa | Separar espera de red, primer texto, adaptación/modelo, bodies/layout y composición; evitar optimizar por intuición |
| 2A, carga | Coordinar peticiones clásicas/experimentales y presentar respaldo usable antes del refresh rico | Menos duplicación y menor tiempo hasta primer texto, manteniendo comparación y sin rotular respaldo como dato fresco |
| 2B, reproducción | Reutilizar composición/layout/geometría del texto; dejar el progreso como cambio pequeño; no recalcular palabras asentadas innecesariamente | Menos tiempo/asignaciones por dibujo. Conservar shaping, RTL, emoji, sílabas, wrapping y tamaño |
| 3 | Separar foco/fronteras de dibujo continuo y limitar pulso a filas activas realmente visibles | Ahorrar al leer lejos de la frase, en pausa, gaps y ventana cubierta, conservando sincronización de audio |
| 4 | Suspender imágenes/tareas de sidebar oculta y evaluar reverso de información diferido | Menos trabajo ajeno al panel sin perder colección, scroll o transición |
| 5 | Afinar reinicios por metadata, cancelación efectiva y presupuesto de proveedores; revisar precarga de Genius | Menos búsquedas obsoletas y ráfagas al cambiar rápido de canción. Cambios de contrato/core requerirían su alcance compartido y pruebas |
| 6 | Comparar efectos/contexto, backdrop y geometría de la sidebar; optimizar sólo el coste demostrado | Menos tirones durante transición sin degradar el diseño por sospecha |

No recomiendo reescribir todo el motor, cambiar proveedor, pasar todo aVStack ni quitar glass/blur globalmente antes de medir. El ensayo puro sugiere que optimizar el escaneo de80líneas aportaría poco frente a estudiar el dibujo rico. Ningún paso de esta tabla optimiza Recomendados.

## 7. Prueba que permitiría decidir con datos

Misma build0146, mismo Mac/ventana/canción/tramo, configuración de movimiento/energía y estado de caché. Sin compilación concurrente. Medir repeticiones con el mismo procedimiento; hacer las consultas AX y capturas fuera del intervalo de perfilado porque añaden trabajo al proceso.

| Comparación | Qué aísla |
|---|---|
| Abrir Letras con acierto de caché vs petición nueva controlada | Latencia de red/caché frente a primer montaje; no borrar toda la caché del usuario |
| Clásico vs Lectura experimental vs Karaoke | Rutas de presentación, reconociendo que fuente/tamaño/layout también varían |
| Mismo karaoke con efectos/contexto cambiados en una variante futura de diagnóstico | Coste de composición y efectos por separado; no aplicar cambios permanentes de preferencias sin acuerdo |
| Sidebar abierta/cerrada quieta y, por separado, durante transición | Retención/cargas frente a relayout por ancho/glass |
| Inicio vs Biblioteca debajo, con el mismo contenido fullscreen | Comprobar que la suspensión elimina diferencias de la página de fondo |
| Pausa, palabra activa, interludio, scroll manual lejos de foco, minimizar/restaurar | Validar cadencias y ausencia de trabajo rápido innecesario |
| Clics cortos/lejanos/consecutivos y resize | Contar peticiones de scroll, layout y reconstrucciones de geometría |

Herramientas: SwiftUI Instruments y Time Profiler para bodies/layout/asignaciones; Animation Hitches/Core Animation y herramientas GPU para composición; marcas por ocurrencia para caché/proveedor/parseo/FFI/modelo/primer contenido. Medir distribución y P95, no sólo media. Un frame de60Hz dispone de16,7ms y uno de120Hz de8,3ms para el sistema completo; son presupuestos matemáticos, no resultados actuales.

Cierre deseable de una futura optimización: mejora reproducible frente a baseline, clics y foco correctos, comportamiento de pausa/oculto, sin pérdida de estado de sidebar/páginas y sin regresión visual de Unicode/resize. La escucha fina y el rendimiento no se certifican compilando o contando tests.

## 8. Evidencia y alcance del cierre

- Antecedentes leídos: FIX-122/123, FIX-185 a192, FIX-224/225 y FIX-228 a234. Sus resultados pertenecen a builds y escenarios anteriores.
- Ejemplo histórico: las trazas de `builds/macos/build-0050/fullscreen-home-performance/` compararon un fixture invitado con cola vacía, sin audio/carátula actuales. No se reutilizan sus porcentajes como rendimiento de karaoke0146.
- Evidencia nueva local ignorada: `.cache/lyrics-performance-2026-10-21/` contiene `source-code-before.json`, `cache-size-summary.json`, `metadata.json`, `commands.txt`, `model-probe.swift`, `raster-probe.swift`, las fuentes copiadas y resultados compilados `model-compiled-results.txt` / `raster-compiled-25-results.txt`. Las tablas usan los ejecutables compilados; `interpreter-command.txt` conserva sólo la verificación del comando de intérprete, no una serie de resultados interpretados. No se exportan cookies, URLs firmadas ni letras comerciales.
- Verificación final: huellas SHA-256 comparadas de554archivos de código/configuración; cero modificados o añadidos. Resultado local: `.cache/lyrics-performance-2026-10-21/audit-verification.json`.
- El código de la auditoría es sólo lectura; el reporte y enlaces de documentación son la entrega. No hay fix, release, build nueva ni cambios de Recomendados en esta investigación.
- [PLAN-025](../PLAN-025-word-synced-lyrics.md) conserva el experimento y la reparación funcional; este reporte propone el trabajo de rendimiento que el usuario revisará después.
