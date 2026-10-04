# PLAN-005: reutilización de categorías y tarjetas de Inicio

- Objetivo: mantener el trabajo y las vistas del scroll ligados al viewport, incluso con 5000 categorías cargadas.
- Estado: usuario confirma «ahora está fino» en build-0017/FIX-103. FIX-104/build-0018 corrige Cargar más conservando los cambios de rendimiento; pruebas y pie final verificados en app real. No hay medición que certifique 120 FPS. FIX-101 descartado.
- Alcance: tabla vertical de Inicio, colecciones horizontales y pruebas de reciclaje. Preservar destacados, formatos, reproducción, menús, teclado, accesibilidad y offsets independientes.
- Exclusiones: core Rust, Windows, cambios visuales y promesas de 120 FPS sin medición.
- Referencias: FIX-027/029/030 históricos contrastados con código actual; FIX-098/099/100 y checkpoint `5cf08ef`. El feed ya virtualiza en ambos ejes: se investiga el costo del reciclaje, no una carga de todas las canciones de cada playlist.

## Pasos

- [x] Revisar código actual, antecedentes y checkpoint.
- [x] Comparar variantes en diagnóstico anterior: aplanado de capas y política de texto descartados; rebind reduce recargas pero no demuestra FPS.
- [x] Separar reutilización por formato visual y conservar celdas preparadas al cambiar categoría compatible.
- [x] Probar cambio de identidad, acciones, selección, offsets, cambios de cantidad y scroll con 5000 categorías (120000 registros, máximo 3 filas/26 tarjetas).
- [x] Ejecutar suite Swift, build numerada, revisar diff y registrar fix/paridad.
- [ ] Medir fluidez en la app completa con imágenes cargadas y gesto real de trackpad.
- [x] Retirar pools/rebind/scanner del ensayo FIX-101; preservar virtualización original y clamp de offset.
- [x] Capturar app real: traza muestra coste repetido de medición Auto Layout vía SwiftUI, ausente contrato sizeThatFits que sí usa la playlist.
- [x] Verificar FIX-102 (contrato de tamaño del viewport), compilar y repetir captura con mismo Mac/viewport; documentar diferencias de contenido y gestos que limitan la comparación.
- [x] Capturar Animation Hitches de build-0016 y distinguir render costoso de una medición de FPS; no dar por resuelto todo el lag.
- [x] Comparar Inicio y playlist en build-0016 reduciendo lecturas AX: desmontaje de estantes y actualización de estilos de controles destacan en Inicio.
- [x] Montar sólo metadata necesaria por formato, conservar instancias/acciones y verificar reciclaje entre formatos; eliminar botón redundante del título con hit-test de etiqueta pasante.
- [x] Compilar nueva build y repetir captura; se conserva reducción de costo específico de desmontaje/contexto, sin deducir mejora global/FPS.
- [x] Reproducir Cargar más en build-0017: la acción llega y el pie desaparece sin categorías visibles nuevas.
- [x] Avanzar continuaciones sin estantes nuevos con límite, retirar debounce del botón explícito, mostrar error/fin y verificar reintento/cancelación/generaciones.
- [x] Compilar y verificar Cargar más en la ventana real conservando los cambios del scroll; nueva percepción de fluidez por el usuario pendiente.

## Cierre

Las pruebas deben verificar vistas acotadas y datos correctos después de reutilizar, sin deducir FPS del tiempo de un callback ni de un temporizador. Registrar comparaciones con el mismo escenario/build/Mac y separar diagnóstico aislado de app completa.

## Resultado registrado

[FIX-101](../../FIXES.md#fix-101), [PAR-004](../../PARIDAD.md). Swift: 37 XCTest y 128 Swift Testing aprobados. Focales: identidad de celdas, callbacks nuevos, preparación fuera de pantalla, selección limpia, offset 450→0→450 y clamp al reducir contenido. Build: [build-0015](../../builds/macos/build-0015/BUILD.json), app `builds/macos/build-0015/Side B.app`, compiled/sourceChangedDuringBuild false y firma verificada. No se abrió esta build; falta revisión visual/trackpad y FPS.

Modo de carga sintética: lanzar la build con `SIDEB_HOME_LAB=1 SIDEB_HOME_FIXTURE=1 SIDEB_HOME_FIXTURE_CATEGORIES=5000`; usar las 16 imágenes locales de la fixture para comparar con caché caliente. Este modo aísla almacenamiento/cuenta; la prueba real debe repetirse en Inicio de la cuenta del usuario. La cantidad de datos sigue consumiendo memoria y preparación inicial: lo acotado es el conjunto de vistas del scroll.

## Revisión tras feedback negativo

El resultado anterior pertenece a build-0015 y no acredita mejora del lag. Ensayo retirado en [FIX-102](../../FIXES.md#fix-102). Captura real `/tmp/sideb-home-real-build15.trace`: 1353/3855 muestras main sin AX en medición de restricciones/tamaños; 311 en display_if_needed (inclusive).

## Resultado de FIX-102

Build [build-0016](../../builds/macos/build-0016/BUILD.json), app `builds/macos/build-0016/Side B.app`, compiled/sourceChangedDuringBuild false y firma verificada. Runner: 180 pruebas Rust aprobadas (7 live ignoradas), 37 XCTest y 128 Swift Testing/5 suites aprobados. Las pruebas actuales conservan offsets/reciclaje original, añaden seguimiento del viewport en tres tamaños y carga sintética de 5000 categorías; no conservan el rebind rechazado.

Ambas apps abiertas en el mismo Mac, ventana 1512×949 puntos con sidebar oculto, contenido de cuenta ya cargado. Time Profiler 25 s por proceso; desplazamientos nativos automatizados en ambas direcciones. Se excluyen muestras cuyo backtrace contiene AX o mshMIGPerform. Exportaciones `/tmp/sideb-home-real-profile.xml` y `/tmp/sideb-home-real16-profile.xml`.

| Cadena inclusive del main | Build-0015 | Build-0016 |
|---|---:|---:|
| Muestras tras excluir AX | 3855 | 3928 |
| measureMin / systemLayoutSizeFitting | 1353 | 1 |
| Enumeración de restricciones | 1230 | 0 |
| NSHostingView | 1701 | 413 |

Resultado: la nueva implementación elimina la medición predeterminada del árbol AppKit que Inicio realizaba y que la playlist evita con sizeThatFits. No sumar las filas ni traducirlas a FPS/porcentaje global de CPU. Las recomendaciones se renovaron al abrir build-0016; las muestras de scroll/inercia y duración activa no son idénticas. La conclusión comprobada corresponde a esa cadena de medición, no a la fluidez total.

Captura posterior Animation Hitches `/tmp/sideb-home-frames-build16.trace` (proceso 73642), pantalla integrada 3024×1964/120 Hz según device-display-info. Exportaciones `/tmp/sideb-home-frames16-details.xml`, `/tmp/sideb-home-frames16-display.xml`. La plantilla marca render y actualizaciones potencialmente costosos. Para render se une Swap ID con registros del proceso y se filtra containment-level=0 para evitar duplicar subintervalos: 828 registros, mediana 14.51 ms, p95 16.77 ms y máximo 64.69 ms. Son duraciones de etapa bajo instrumentación; no intervalos de presentación ni una media de FPS. Las tablas displayed-surfaces-per-second, displayed-surfaces-interval y display-surface-swap no tienen filas exportadas. No se usa el número de registros/lifetimes dividido por tiempo para inventar FPS.

Siguiente investigación si persiste: comparación controlada de composición de Inicio y playlist, aislando dibujo de tarjetas y shell/fondo con contenido fijo e imágenes calientes. No volver a cambiar pools o arquitectura basándose sólo en cantidad de vistas; la virtualización original ya está acotada. Trackpad humano y validación perceptual pendientes; FIX-102 no se registra como solución completa del lag.

## Resultado de FIX-103

Usuario confirma mejora parcial en 0016. [FIX-103](../../FIXES.md#fix-103) reduce metadata del árbol de vistas según formato/contenido, conservando las instancias para reutilizarlas, y elimina el botón transparente redundante del título. Compacto sin álbum: 14→7 controles directos. Pruebas verifican clic de título al botón de tarjeta, label accesible, mismos controles de metadata tras compacto→grande→compacto, callbacks nuevos y z-order del artista. Apariencia de textos, badges y tarjetas revisada en ventana real; acciones/hover/menús/ecualizador cubiertos por pruebas existentes.

Build [build-0017](../../builds/macos/build-0017/BUILD.json), app `builds/macos/build-0017/Side B.app`, compiled/sourceChangedDuringBuild false y firma verificada. Runner: 180 Rust aprobados (7 live ignorados), 39 XCTest, 128 Swift Testing/5 suites aprobados. Carga de 5000 categorías: 3 estantes/36 tarjetas máximos en árbol y 3 instancias de estante retenidas; no valida FPS.

Primera comparación de Inicio/playlist en 0016 localiza desmontaje y estilos como costo grande de Inicio (trazas `/tmp/sideb-home-build16-noax-oct3.trace`, `/tmp/sideb-playlist-build16-noax-oct3.trace`). Para comparar el cambio se repite 0016 y se prepara ambas con 60 scrolls de calentamiento, alternando bloques de 20 abajo/arriba/abajo hasta el fondo. Time Profiler 20 s, misma ventana 1512×949/sidebar visible, 40 scrolls de 0.45 páginas en bloques de ocho arriba/abajo; una lectura AX final. Exportaciones `/tmp/sideb-home-build16-controls-repeat-oct3.xml` y `/tmp/sideb-home-build17-controls-oct3.xml`. Se excluyen backtraces AX, mshMIGPerform y Accessibility.

| Cadena inclusive del main | Build-0016 repetición | Build-0017 |
|---|---:|---:|
| Muestras restantes | 3135 | 3011 |
| Desmontaje de filas | 561 | 465 |
| Cambio de ventana del árbol | 551 | 475 |
| Contexto semántico de controles | 296 | 226 |
| Actualización de estilo | 155 | 128 |
| display_if_needed | 499 | 499 |

Conclusión acotada: menos controles y menos trabajo en el desmontaje/contexto, mientras dibujo permanece costoso. No sumar filas ni convertirlas a FPS o porcentaje global: datos/kinds cambiaron al refrescar recomendaciones y estado de reproducción difiere entre procesos. La primera captura 0016 (3448 main/681 desmontaje) no tenía calentamiento idéntico y no se toma como base del porcentaje. Se mantiene el cambio como mejora estructural con evidencia específica, pendiente de percepción/trackpad; no solución completa del lag. El fix AppKit no requiere port Windows: HomeCard.svelte ya usa if para metadata/explicit y una acción principal común a título/portada. PAR-004 continúa pendiente para virtualización Windows.

## Resultado de FIX-104

Usuario confirma fluidez en 0017 y reporta que Cargar más no funciona. La prueba real confirma dispatch y desaparición del pie sin categorías visibles nuevas. [FIX-104](../../FIXES.md#fix-104) conserva el render y avanza hasta tres continuaciones por clic cuando vienen estantes repetidos/vacíos; muestra error, tanda sin novedades o fin, permite reintentar sin el debounce histórico y libera la carga al cancelar. No reconstruye tarjetas en páginas sin estantes nuevos. Core/Windows sin cambios; diferencias trasladables en [PAR-005](../../PARIDAD.md).

Build [build-0018](../../builds/macos/build-0018/BUILD.json), app `builds/macos/build-0018/Side B.app`; compiled/sourceChangedDuringBuild false, firma verificada. Runner: 180 Rust aprobados (7 live ignorados), 40 XCTest y 135 Swift Testing/5 suites aprobados. Ocho regresiones nuevas cubren botón nativo, duplicados, límite/ciclo, página vacía terminal, reintento inmediato, cancelación y respuesta de filtro anterior.

En app real (PID 92039), bajar y pulsar Cargar más termina con «No hay más recomendaciones por ahora». AX y captura confirman el mensaje visible sobre la barra flotante, sin spinner atascado. Esa continuación no añadió categorías; no se registra como prueba de nuevas categorías del proveedor. Error/reintento y salto de páginas repetidas se validan con dobles de Core. Cantidad de contenido y FPS no se deducen de esta comprobación; no hay feed infinito garantizado por el endpoint.
