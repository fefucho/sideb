# PLAN-026 — Implementación y mediciones de Letras

Fecha: 2026-10-21, America/Montevideo. [Plan](../PLAN-026-fullscreen-lyrics-performance.md), [auditoría original](LYRICS-PERFORMANCE-2026-10-21.md), [FIX-236](../../../FIXES.md#fix-236).

## Resultado y estado de aceptación

Se implementaron optimizaciones de las filas y del reloj de Letras, con revisión de dos subagentes Luna y uno GPT-6.1 Sol medio. La build Mac 0150 Release está compilada y verificada. **La mejora de FPS de la app todavía no está validada:** hay baseline real de CPU durante scroll continuo, pero la build nueva quedó esperando al Llavero al restaurar la sesión y la herramienta bloquea SecurityAgent por seguridad. No se pudo preparar ni medir su escena. El plan permanece abierto en su aceptación de rendimiento.

La comparación aislada del renderer contextual mejoró de 14,778 a 7,530 ms por snapshot. Es una medida de rasterización sintética, no FPS, GPU ni una comparación completa de la app. No sustituye la medición posterior pendiente.

**Seguimiento posterior del usuario, 2026-10-21:** «bien funciona mejor». Confirma mejora percibida tras la entrega0150; no aporta medidas de frames ni una matriz detallada de canciones/cues. Se conserva esta aceptación cualitativa junto a los límites instrumentales anteriores. A pedido del usuario, el estado acumulado de las letras nuevas y el trabajo necesario para Windows quedan en la [guía de PAR-037/038](../../../PARIDAD.md#lyrics-windows-handoff), antes de compactar la conversación.

## Cambios incorporados

- El contexto usa el mismo Text atribuido preparado que la voz activa, con dibujo nativo cuando no necesita barrido. Mantiene fuente, tracking, saltos, alineación y altura. La vista conserva una caché local de una entrada por línea; cambiar texto o tiempos la invalida. No retiene Text.Layout entre generaciones de SwiftUI.
- Los límites físicos de expansión de palabras se calculan con ordenación y máximo acumulado, O(n log n), conservando solapamientos, anclas anidadas, orden lógico de fragments, RTL y palabras partidas entre renglones. La geometría dependiente del layout sigue reconstruyéndose para el layout entregado; no se introduce una caché con claves incompletas.
- La distancia visual satura en 3, donde ya saturaba el blur. Así una fila lejana no recibe nuevas distancias visualmente equivalentes al avanzar el foco.
- Una frase enfocada que ya terminó utiliza un tiempo final estático durante gaps/outro. Sólo las líneas activas leen positionMS. Se distingue el foco anterior al primer inicio para que no aparezca completado anticipadamente.
- La política del pulso de 30/60 Hz requiere una voz o interludio activo dentro del viewport, mediante onScrollVisibilityChange, disponible desde macOS 15. Se consideran todas las voces del grupo visible. Permanecen el observer periódico de 0,1 s, las fronteras reales de palabras y la coordinación de seek. La política tiene pruebas; la entrega real de callbacks de visibilidad aún necesita QA de la build nueva.
- ClassicLyricsClockHost limita la lectura frecuente del reloj del panel original. PlayerBarProgressView concentra tiempos, progreso y estado de scrubbing. Se conservan los controles, accesibilidad y acciones existentes.

No se modificaron centrado/seguimiento, LazyVStack, backdrop, reverso de información, sidebar, proveedores ni Recomendados en esta ejecución. La extracción de los hosts y las políticas están implementadas; su reducción exacta de invalidaciones en la app aún no se midió.

## Baseline real de scroll continuo

MacBook Pro M1 Pro, 16 GB, macOS 27.0 (26A428), Xcode 27.1 (27A9275). Ahorro de energía desactivado. Bundle original 0147 Release, PID 71018, con FIX-235 ya incluido. Canción EoO de Bad Bunny; caché caliente, documento Better Lyrics / Boidu de 72 líneas y 448 palabras, 34.912 bytes. Documento canónico SHA-256: b62f073b8fc31183d03bb85192cbae7988553284198d4ab6187b0de68d9b9262.

Ventana de 3024 × 1898 píxeles, Letras/Karaoke, tamaño inicial 36, sidebar cerrada. Cue inicial alrededor de 16,9 s. Ochenta gestos de 0,25 páginas en (2300, 1050), cambiando de dirección cada veinte, con una espera solicitada de 250 ms entre gestos. Se guardan los tiempos reales; la latencia de la automatización hace que la duración efectiva varíe. No hubo compilación, exportación pesada ni consultas AX dentro de los intervalos usados de estos ensayos continuos. Las consultas posteriores quedan excluidas.

Time Profiler, muestreo de 1 ms, target Side B, sin waiting threads ni high-frequency sampling. El parser resuelve referencias XML y filtra la ventana real de gestos. La suma de pesos es una estimación de CPU muestreada; no es tiempo de frame. Las categorías inclusivas de stacks se solapan y no se suman entre sí.

| Scroll continuo | Ventana de gestos | CPU muestreada main, 0147 | CPU main por segundo de pared | Build 0150 |
|---|---:|---:|---:|---|
| Pausado | 35,475 s | 8,405 s | 236,9 ms/s | N/D: comparación pendiente |
| Reproduciendo | 49,388 s | 16,497 s | 334,0 ms/s | N/D: comparación pendiente |

La CPU de main es apreciable aun con audio pausado. Esto sostiene investigar montaje, texto y layout durante el desplazamiento; no demuestra por sí solo qué proporción de los tirones corresponde a main o a GPU/compositor.

Como control adicional, ocho gestos de cuatro páginas separados por cuatro segundos dieron 30,5 ms/s de main en pausa y 306,0 ms/s reproduciendo. Ese control contiene intervalos quietos y no se presenta como scroll continuo. Se conserva para comparar el coste adicional del reloj. Tampoco acredita una causa en la sidebar.

La primera traza no fue utilizable. La baseline válida se capturó después de iniciar las ediciones de fuentes, usando siempre el bundle 0147 original, sin recompilarlo ni modificarlo; el código nuevo no forma parte de ese ejecutable. Las capturas descartadas no cuentan como baseline válida anterior a la edición.

## Comparación aislada antes/después

Probes swiftc -O con texto sintético, tres frases de seis segmentos, 36 pt, ancho 420 más padding, escala 2, 45 snapshots por variante descartando los cinco iniciales. Cada snapshot recrea las vistas: no mide la reutilización real de estado/layout de una app montada. Ensayo secuencial con variabilidad del host, sin intervalos de confianza.

| Variante de raster | Mediana anterior | Mediana nueva | P95 anterior → nuevo |
|---|---:|---:|---:|
| Contexto | 14,778 ms | 7,530 ms | 16,677 → 9,037 ms |
| Barrido activo | 15,192 ms | 16,764 ms | 16,632 → 19,660 ms |
| Barrido con movimiento | 15,450 ms | 17,387 ms | 20,158 → 18,850 ms |

El contexto mejoró aproximadamente 49% en este ensayo. **No se demostró mejora del raster activo:** sus medianas subieron en esta ejecución. El ensayo no permite generalizar una regresión de FPS, ni prometer una mejora equivalente de la app.

Microbench puro: componer Text de doce segmentos 18,665 µs frente a 0,0188 µs en un cache hit de la misma línea CoW; cuarenta anclas 17,650 → 3,512 µs. Excluyen Observation, layout de SwiftUI, GPU y audio. La preparación de secuencias no fue modificada por estos resultados.

## Pruebas y build

- Renderer: 36 combinaciones de fixture/fuente/ancho, con 108 medidas de fittingSize entre contexto nativo, activo y referencia anterior. Doce comparaciones de raster contextual idénticas byte por byte; casos de sílabas/ligaduras, CJK, RTL, emoji, saltos y espacios. Vecinos contrastados con referencia exhaustiva, incluidos solapamientos/anclas anidadas.
- Reloj: foco antes del primer inicio, final de frase/gaps/outro, offsets positivos/negativos, visibilidad de grupos e interludios tras restart/stop, voces simultáneas y pausa/seek pendiente. Suites previas de conversión numérica, fetch real y seek conservadas.
- Build 0148 falló al inferir dos fixtures preexistentes de shrinkingDocumentTransitionDoesNotCrash. Se explicitaron tipos y tiempos intermedios, conservando los datos y comprobaciones.
- Build 0149 ejecutó las suites y encontró una carrera en deadlineResolvesPausedSeek: cinco Task.yield no garantizaban el retorno del callback a MainActor. El test ahora espera el resultado observable con límite de 2 s, sin muestrear tiempo ni cambiar el timeout de producción. Focal Release: 19 aprobadas.
- Build oficial 0150: 97 InnerTube + 129 sideb-core + 239 XCTest + 435 Swift Testing aprobadas. Swift Testing declara 442 casos, de los que 7 se omiten; Rust omite otros 8. **900 ejecutadas aprobadas y 15 omitidas** en total, sin fallos. Omisiones live/proveedor opcionales existentes. XCFramework y bindings regenerados por la skill oficial, sin cambios nuevos de fuentes del core ni edición manual de bindings.
- BUILD.json: compiled, Release arm64, versión 1.2.6/build 19, sourceChangedDuringBuild:false. Firma ad hoc verificada y diez hashes del paquete coincidentes. App: builds/macos/build-0150/Side B.app. Cierre documental posterior al paquete.

## Qué impidió cerrar la comparación

Animation Hitches produjo una captura parcial de aproximadamente 21 GB y falló por falta de espacio. Se retiraron sólo las trazas fallidas creadas por este trabajo, preservando logs/metadatos; no se tocaron builds anteriores ni datos de usuario.

Core Animation FPS se deshabilitó explícitamente porque macOS no ofrece esa métrica en ese instrumento. Frame Lifetimes exportó filas con inicios repetidos en cero, duraciones crecientes y luego timestamps imposibles; la tabla RAW display-surface-swap tenía cero filas. No son datos válidos para FPS, hitches, P95 o P99.

Después de las baselines, Computer Use devolvió timeouts y error -10005 también en Finder. Un reset recuperó temporalmente el acceso; al iniciar 0150 volvió a fallar. Se confirmó el nuevo proceso PID 5614 y su ruta exacta, pero no se logró preparar su escena ni ejecutar un perfil posterior comparable. La muestra del proceso anterior estaba en el run loop; **la de 0150 muestra main esperando SecItemCopyMatching al restaurar la sesión** (AccountViewModel.restoreSession → CookieStorage.getFromKeychain), antes de preparar Letras. SecurityAgent se inició con esta build y Computer Use rechazó acceder a él por seguridad. Esto identifica una espera de autenticación durante el inicio, no un ensayo del renderer nuevo. Se solicitó resolver el aviso directamente en el Mac para continuar. No se cambió seguridad, no se eludió ese bloqueo ni se reiniciaron servicios/apps a la fuerza; CookieStorage no se modificó en este trabajo.

## Sidebar y resto de trabajo

La auditoría original sigue vigente: la sidebar cerrada conserva su árbol y no suspende explícitamente todas sus imágenes; eso no equivale a montar toda la biblioteca. Inicio y tablas de fondo ya tienen barreras de actividad. El reverso de información, arte y backdrop permanecen montados. Estas condiciones merecen un A/B propio, pero no se demostró aquí que la sidebar cause los tirones. No se retiraron efectos ni se cambió su estado sin evidencia.

La etapa de red/cancelación sigue aplazada frente al objetivo de FPS, y Recomendados queda fuera de modificaciones. Faltan perfil posterior equivalente, cinco cues/seguimiento/manual/Volver en la build nueva, comparación Clásico/Lectura/Karaoke/sidebar y datos válidos de frames. No se declara completado PLAN-026 ni resuelto el lag sostenido antes de esa aceptación.

Evidencia local ignorada por Git: .cache/plan026-execution-2026-10-21/ contiene snapshots de fuentes, TOC/XML, parser, ventanas y logs oficiales; .cache/plan026-renderer/ contiene probes reproducibles y resultados. Los artefactos versionables sólo resumen medidas y huellas, sin payloads de letras, cookies ni entornos de las trazas. No hubo commit, push ni publicación.
