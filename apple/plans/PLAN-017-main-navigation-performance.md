# PLAN-017: rendimiento al cambiar Inicio, Biblioteca y Explorar

- Fecha: 2026-10-13 (America/Montevideo).
- Estado: FIX-188/0111 compiled,677pruebas/firma/hashes y QA aprobados; CPU387ms/s idle no acredita mejora global. Hosting independiente de fondo en investigación FIX-189. FIX-185/0108 y FIX-186/0109 entregados; usuario confirma que0109 es mucho más responsiva. Seguimiento FIX-187/0110 compiled/fuentes estables,673pruebas/firma/10hashes y QA de navegación/scroll/sidebar/AX aprobados. Fixture demuestra eliminación de DFS innecesario en Flow. Fluidez global/composición de0110 y virtualización de sidebar pendientes de medición.
- Objetivo: estudiar la lentitud y los tirones al cambiar de destino principal en macOS, distinguiendo montaje de vistas, carga de datos y composición/animaciones.
- Alcance: código vigente y medición del ejecutable release0091; conservar los cambios locales existentes. No modificar core, Windows, preferencias ni reproducción.
- Referencias: FIX-119/121/122 (reciclaje y suspensión dentro de una página), FIX-167/170/171 (enlaces de artistas e invitados), FIX-172 (viewport Biblioteca), FIX-184 (restauración topnav), PLAN-013 y PLAN-016.

## Pasos

- [x] Leer instrucciones, antecedentes y shell/rutas/vistas/modelos.
- [x] Identificar exactamente el ejecutable medido y su relación con el árbol local.
- [x] Capturar cambios repetidos con Instruments y separar el tramo previo de reposo/lectura AX; excluir una captura inicial de otro ejecutable.
- [x] Contrastar stacks de creación/layout, cachés y efectos visuales con sus caminos de código.
- [x] Registrar resultados reproducibles y prioridades de corrección, separando evidencia e hipótesis.

## Resultado

La evidencia apunta principalmente a trabajo de montaje y layout en el hilo principal, especialmente al regresar a Inicio. La caché de datos no conserva los controles de la página. El recálculo de enlaces de artistas añade trabajo repetido a ese montaje. El perfil CPU no coloca la barra de navegación ni el cuerpo del fondo entre los caminos dominantes; esto no descarta costo GPU/compositor.

### Ejecutable y escenario

- La primera apertura por nombre inició `/Applications/Side B.app`, cuyo SHA256 coincide con build0074. Su Time Profiler de10s se conserva como evidencia inicial, **excluido de comparaciones con0091**. Se cerró y abrió el bundle0091 por su ruta explícita.
- Medición principal: `builds/macos/build-0091/Side B.app/Contents/MacOS/Side B`, PID68267, release arm64. SHA256 `7434d4310191ff80d422cbf24bb620491c22a5b7e59e653082fc5775563e7e25`, idéntico al manifiesto. Commit base `0f0b34364c947a6d88cbf93703b40e933885b07b`, con cambios locales al compilar; `sourceChangedDuringBuild=false`. La build no equivale al árbol local actual completo.
- Mismo Mac/ventana, sidebar expandido, Inicio con contenido, pista restaurada y pausada. No se pulsó Play ni se alteraron preferencias, cuenta o colecciones. Los botones y el destino visible se comprobaron con AX después de cada acción.
- Animation Hitches:45.903s, seis cambios Explore→Library→Home, repetidos dos veces. Time Profiler:36.025s, nueve cambios con esos destinos ya visitados/cargados. La última observación de ambos recorridos confirmó Inicio visible y sidebar conservado. Al reanudar tras la interrupción, el proceso ya no estaba en ejecución; no se volvió a abrir.
- Evidencia local: `.cache/navigation-performance-2026-10-13/`, con trazas, exports XML, identidad del ejecutable, `analyze.py`, `summary.json` y `hitch-correlated-stacks.json`. No se guardan árboles AX ni datos de la cuenta en este plan.

### Evidencia nueva

| Medida | Resultado e interpretación |
|---|---|
| Primer regreso a Inicio, Animation Hitches | Una actualización de207.245ms iniciada80ms después del clic. En ese intervalo hay206ms muestreados del hilo principal:181ms sin stacks AX y25ms AX. Aparecen `HomeShelfRowView.layout`, `HomeNativeCollectionView.layout`, creación/configuración de items y `HomeItemView.init` |
| Segundo regreso a Inicio | Actualización de249.921ms iniciada101ms después del clic;198ms muestreados del hilo principal,182ms sin AX y16ms AX. Mismos caminos de creación/layout |
| Trabajo posterior al primer regreso | Otra actualización de320.946ms;318ms CPU principal muestreados,302ms sin AX. El layout de estantes y las nuevas tarjetas siguen apareciendo. No se atribuye todo el costo a un único método |
| Time Profiler completo |20,982ms CPU principal muestreados;7,491ms con stacks AX y13,491ms sin AX. Los13,491ms incluyen todo el recorrido y el tramo previo, no sólo los clics |
| Símbolos propios sin AX, inclusivos | `HomeShelfRowView.layout`:2,326ms; `HomeNativeCollectionView.layout`:2,063ms; `NativeFeaturedArtistOverlay.rebuild`:1,027ms; `NativeTrackActionField.layout`:790ms; `HomeItemView.init`:393ms |
| Familias CPU sin AX | Feed nativo de Inicio:3,299ms; controles de navegación:63ms; cuerpo/reloj del ambiente:19ms; imágenes:6ms. Categorías inclusivas: se solapan y **no se suman** |

La actualización de368ms posterior al segundo regreso sólo contiene129ms CPU principal muestreados: no se interpreta como bloqueo CPU continuo ni se atribuye por completo a layout. Los totales brutos de hitches/updates contienen múltiples registros de etapas y no se presentan como cantidad de frames perdidos.

La automatización y las consultas AX añaden trabajo real al proceso. Filtrar stacks AX y correlacionar CPU con actualizaciones ayuda a identificar el camino de la app, pero no elimina todos los efectos indirectos del ensayo. Los tiempos entre clic y observación AX **no** son latencia de navegación. No se infieren FPS, porcentajes de mejora ni costo GPU a partir de muestras CPU.

### Caminos de código comprobados

1. **Se conserva el modelo, se desmonta la vista.** `SideBApp.swift` selecciona un único destino mediante `switch router.currentPage`. Salir de Inicio destruye su representable y coordinador; volver llama a `HomeFeedTableView.makeNativeScrollView`, `reloadData`, monta estantes/items y hosting de destacados. `horizontalOffsets` vive en el coordinador, no en una caché por destino. El reciclaje de FIX-119 dentro de Inicio no conserva esa instancia al navegar a otra página.
2. **TextKit se repite en cada layout.** `NativeTrackActionField.layout` llama incondicionalmente a `featured.rebuild`. `NativeFeaturedArtistOverlay.rebuild` crea `NSTextStorage`, `NSLayoutManager` y `NSTextContainer`, mide glifos y actualiza controles/etiquetas AX sin una clave de geometría/texto ya resuelta. También hace ese trabajo con `credits` vacío si el campo tiene área disponible. Hay reutilización de botones por ID, pero no de la medición.
3. **El fast path de tarjetas no evita reconstruir enlaces.** `HomeItemView.configure` calcula `samePresentation`, pero llama a `configureFeatured` de título/artista **antes** del retorno rápido. `NativeFeaturedArtistOverlay.configure` vuelve a preparar texto/créditos y llama a `rebuild`. Datos idénticos todavía disparan ese trabajo.
4. **Hay más trabajo de layout por comprobar.** `HomeNativeCollectionView.layout` recorre descendientes y vuelve a asignar opciones de scroll en cada pasada. `HomeShelfRowView.layout` fuerza layout de colección al restaurar el offset. Ambos aparecen en las trazas; falta un A/B para separar sus contribuciones y determinar si hay invalidaciones evitables.
5. **Caché y animación son asuntos distintos.** Inicio sólo recarga desde su task si `sections.isEmpty`; Biblioteca usa `loadedSections` y Explorar `snapshots`. Volver a páginas cargadas puede ser caro aunque no espere una petición nueva. `navigateMain` cambia el router directamente: no hay una transición explícita común de0.42s entre estos destinos. Esa duración de `NavPresentation` corresponde a presentaciones como sidebar/buscador. No se identifica una duración deliberadamente larga como explicación principal.

No hay evidencia suficiente para culpar al backend Rust o a la red por el trabajo principal de estos intervalos. El perfil observa CPU de interfaz; no verifica tráfico ni demuestra que nunca haya cargas asíncronas al navegar.

## Correcciones propuestas, pendientes

1. **Acotar el recálculo de enlaces**, con fast path cuando no hay créditos y caché de medición invalidada sólo por texto/créditos, tamaño, fuente, truncamiento/alineación, idioma o sesión. Evitar setters y tracking innecesarios; actualizar callbacks sin rehacer la geometría cuando la presentación es idéntica. Conservar hover/foco, destinos, rangos visibles y reutilización.
2. **Retener los destinos principales ya visitados**, empezando por Inicio, con un ciclo de visibilidad explícito. Pausar fondo, tareas, hover/indicadores e imágenes de destinos ocultos y retirarlos del árbol accesible. Invalidez por cuenta y memoria acotada; conservar scroll/páginas/historial. Mantener tres vistas activas sin suspensión podría empeorar consumo y no constituye una solución comprobada.
3. **Medir de nuevo antes de ajustar efectos visuales.** Comparar variantes independientes en release, mismo Mac/ventana/contenido y acciones. Revisar layout de estantes/descendientes según la traza; estudiar GPU/compositor sólo si sigue el síntoma. Duración menor o un fade no quitan el trabajo síncrono encontrado.

- [x] Implementar y probar la corrección autorizada: FIX-185, build0108,659aprobadas; identidad, suspensión, servicios de ventana y mediciones repetidas cubiertas.
- [x] Comprobar navegación/AX/scroll/sidebar/Spotlight/fullscreen en la app final0108.
- [ ] Acreditar mejora global de fluidez con A/B controlado y aceptación física; CPU parcial no basta.

## Otra plataforma

Lectura de `windows/src/routes/+page.svelte`: también monta Home/Explore/Library mediante ramas condicionales, por lo que la retención por destino merece estudiar su conveniencia allí. La reconstrucción de TextKit y los controles AppKit son exclusivas Apple. Sin medición nativa Windows, sin port ni cierre de paridad; esta investigación no registra un fix implementado.

## Comprobaciones de cierre

- Atribuir sólo lo sustentado por código y trazas nuevas; no convertir muestras CPU en FPS.
- Conservar evidencia local bajo `.cache/`; no guardar árboles AX con datos de la cuenta en documentación pública.
- Restaurar Inicio y el estado de sidebar observado; conservar reproducción y preferencias.
- Investigación documentada; cualquier implementación o validación pendiente permanece explícitamente pendiente.

## Implementación autorizada

- 2026-10-13: FIX-185 aplica caché TextKit/configuración tipada, retención acotada por cuenta y suspensión de viewport/tareas/modelos nativos ocultos. Conserva TopNav restaurada; no se retoma su rediseño.
- Focal final inicial:24XCTest +36Swift Testing aprobadas; repetición de retención final3XCTest aprobada con catálogos/tabla reales.
-0101: fallo de LocalizationPlayerTests (álbum duplicado) tras154XCTest;318Swift Testing registradas (311aprobadas/7live omitidas). Regresión del fast path corregida con sufijo explícito y generación por idioma; añade cancelación de navegación de artistas al ocultarse. Intento conservado; no se entrega. Suite/build y perfil finales pendientes. PAR-031 registra traslado por estudiar, sin fuentes core/Windows editadas.

-0102 compilada y estable:655pruebas aprobadas/14live omitidas. Refinamiento final de vista previa de tablas suspendidas durante el gesto fullscreen y botones invisibles de invitados; focal de preview/cancelación/hover aprobada. Se genera una build posterior para esa fuente exacta antes de medir.

-0103 aprobada/estable. Suspensión también propagada explícitamente al NSHostingView de destacados con HomeFeaturedViewport.isActive, incluyendo montaje inicialmente oculto. Focal de4regresiones nativas de retención aprobada; build final siguiente incluirá ese puente.

## Estado de entrega al2026-10-13 (histórico)

- Build final: `builds/macos/build-0104/Side B.app`, compiled/fuentes estables.656aprobadas:188Rust,155XCTest y313Swift Testing;14live omitidas. Firma estricta y10hashes aprobados. Regeneración de bindings sin cambios nuevos de fuente, core/Windows conservados.
- Dos intentos CUA (0103 y0104) fallaron por Mac bloqueado. Desbloqueo solicitado; no se abrió app ni se atribuye mejora cuantitativa/FPS. A/B y QA de navegación/sidebar/scroll/Spotlight/fullscreen siguen pendientes.
- Después de desbloquear: abrir0104 por ruta exacta, verificar proceso/hash, recorrer páginas ya cargadas, conservar scroll y comprobar AX de página activa. Time Profiler y Animation Hitches con mismo Mac/ventana/acciones; separar AX y muestras inclusivas. Las trazas0091 son antecedentes, no una validación de0104.

### Reanudación2026-10-14

- Mac desbloqueado.0104/PID41425/hash verificado; arranque inicialmente esperando `SecItemCopyMatching` al restaurar sesión. El usuario resolvió el diálogo del llavero; se continuó sin leer ni ingresar credenciales mediante herramientas.
- Navegación real precargada y retorno de scroll de Inicio comprobado (0.245607406007935 antes/después). Buscador y fullscreen abren/cierran con Surf pausada. Sidebar expandido restaurado antes de cerrar0104.
- Se detectan nodos AX de páginas ocultas y cabecera desplazada al cerrar sidebar. Refinamientos adicionales de agrupación/ocultación AX y ancho/alineación del hosting nativo; nueva build y QA/perfil pendientes. La fixture de geometría nativa no reproduce el recorte físico, por lo que se requiere comprobarlo en la app final.
-0105 compiled/658aprobadas, firma y10hashes verificados. El wrapper AX SwiftUI todavía expone páginas ocultas en QA. Frontera nativa de página retenida con hosting estable, Environment completo y teardown explícito:17focales aprobadas; nueva build pendiente. Se repite referencia0091 en ventana amplia actual (3024×1964 píxeles), sidebar expandido y Surf pausada: nueve cambios CPU completados; intento Animation Hitches interrumpido por actividad del usuario/cierre de sidebar, excluido de comparación y conservado.
-0106 compiled/estable/658aprobadas, firma y10hashes verificados. AX tras completar carga inicial confirma sólo el destino activo en Explore→Library→Home. Screenshot detecta segundo inset superior del hosting. Ajuste final: safeAreaRegions=[] y transferencia explícita de valores públicos del Environment; hosting conserva su contexto AX y expone el hijo activo.17focales aprobadas, incluida geometría, purga y preview a través del hosting. Se genera otra build para esa fuente exacta.

-0107 compiled/estable/658aprobadas, firma y10hashes verificados. AX sólo de destino activo; scroll de Inicio idéntico0.2750087138375741 al regresar, sidebar sin recorte ni segundo inset. Spotlight y fullscreen ocultan/restauran AX, Surf pausada. CPU repetida con0091 en ventana3024×1964: regreso a Inicio, primeros300ms sin stacks AX138/170/150→67/118/106ms; sin muestras de montaje nativo/rebuild en0107. Total16,472→20,000ms sin AX, duraciones46.285/46.081s: persiste layout y no acredita mejora general/FPS. Las dos capturas de animación0107 quedaron excluidas: una sin rutas y otra con seis rutas pero salida no guardada después de agotarse espacio. Se retiraron temporales propios sin uso, sin borrar builds.
- Revisión de frontera NSHostingView: transferir también los servicios públicos propios sideBMenuContext/collectionBackgroundController del shell; agregada regresión de identidad y actualización de servicios para las tres páginas, incluyendo páginas ocultas. Nueva build posterior pendiente.

## Cierre de FIX-185,2026-10-14

-0108 compiled/fuentes estables,659aprobadas (188Rust/158XCTest/313Swift Testing),14live omitidas. Firma estricta y10hashes aprobados. SHA256 del ejecutable `bf73470e7ca5a7f0074685c1b56b7a8599c4c7428ba4d5128862ec904e8663bf`; proceso63648 verificado al realizar QA.
- Cinco pruebas de retención aprobadas; servicios de ventana conservan identidad y reciben reemplazos en destinos activos y ocultos. UI0108 confirma AX de una única página, scroll de Inicio0.2750087138375741 idéntico antes/después de visitar Explorar, overlays y sidebar correctos con Surf pausada. Captura JPEG verifica3024×1898.
- La anotación3024×1964 de las capturas previas no estaba respaldada por metadatos. Se conserva CPU0107 como indicio parcial, con contenido/carga AX variables y sin comparación de altura verificada. No se acredita mejora global ni FPS. Repetición0091 tras la interrupción no iniciada: proceso64415 ya cerrado, xctrace exit21. Las capturas de animación fallidas no cuentan como evidencia.
- Bundle final: `builds/macos/build-0108/Side B.app`. Sin nuevos cambios core/Windows ni instalación/publicación. La app de `/Applications` abierta al retomar tiene otro hash; no es0108.

## Análisis complementario de la hipótesis de sidebar,2026-10-14

El usuario pidió terminar FIX-185 y después contrastar un análisis de Claude. Se cerró la implementación0108 y se estudió esta hipótesis sin aplicar un congelado de layout no validado.

### Contraste con el código vigente

- `SideBApp.sidebarBinding` usa `.smooth(duration:0.42, extraBounce:0)` o0.12s con Reduce Motion. El HStack reserva242pt (230+dos insets de6), no230pt. Al animar esa reserva cambia el ancho disponible de la página activa. FIX-185 retiene/congela páginas ocultas; no congela el layout de la página visible.
- Inicio tiene tabla/estantes/colecciones y destacados SwiftUI. `HomeFeedScrollView.layout` llama a `updateFeatured()`; ésta calcula geometría y sólo modifica `featuredViewport.width` si cambió. La invalidación de altura de fila está condicionada a altura distinta o caché nativa discrepante. No sucede obligatoriamente en cada frame.
- La altura es por tramos: con9canciones y al menos2álbumes, sobre960pt `tile` queda limitado a144 y el panel mide542pt más la cabecera fija. En la ventana medida (1512pt, contenido aproximado1270–1512pt al alternar sidebar) puede cambiar de1a2columnas de álbumes sin cambiar esa altura. Bajo960pt y al cruzar900pt sí cambia la geometría/altura; esta captura no cubre esos tamaños.
- El callback `updateFeatured()` no reemplaza por sí mismo el root de destacados. El reemplazo existe en la rama `force:true`, llamada desde `updateNativeScrollView`; no se midió cuántas veces se ejecuta por frame. Las invalidaciones pueden producir trabajo SwiftUI diferido que no conserve el setter productor en su stack.
- `onGeometryChange` observa un Int (`albumsPerPage`), no cada ancho. `setFeaturedCapacity` además retorna si la capacidad coincide. La proyección cambia en umbrales2/4/6. Explorar también recalcula tamaños e invalida su flow layout cuando el ancho varía más de0.5pt.
- No se comprobó la afirmación de acumulación al pulsar muy rápido: esta prueba deja observar cada acción; no es un ensayo de interrupciones rápidas.

### Traza nueva de la app final

- Release0108 por ruta/hash exactos, PID17756; Mac/ventana3024×1898 verificados en la misma sesión. Inicio/Explorar precargados, reproducción pausada. Time Profiler46.023s. Se ejecutaron seis toggles por página y se dejó Inicio/sidebar abierto. La última apertura de Explorar empezó después del fin de la traza: se excluye, no se contabiliza como cero. Comparación equilibrada: tres cierres por página, ventana fija de750ms desde la solicitud del clic.
- Promedio CPU principal sin stacks AX: Inicio444.33ms y Explorar492.67ms. No demuestra que Inicio consuma más CPU total ni que sea más fluido; no son duraciones de animación ni FPS. AX directo e indirecto añaden carga al ensayo.
- Stacks inclusivos de layout: Inicio368ms, Explorar334.33ms. Feed nativo de Inicio23.33ms frente a3.33ms al estar oculto; `updateFeatured`0.33ms y proyección0.67ms en Inicio. Son familias solapadas, no se suman. El costo bajo del setter no excluye trabajo SwiftUI diferido, pero no permite señalarlo como cuello principal. `WindowNavigationToolbarView.updateNSView` también aparece:45ms en Inicio,82.67ms en Explorar; contiene layout síncrono del header común.
- Evidencia local privada: `validation-2026-10-14/sidebar-cpu-0108.trace`, exports toc/profile, `sidebar-events-0108.json`, `analyze-sidebar.py`, `sidebar-summary-0108.json`. Esta captura se guardó/exportó correctamente. Es una medición de sidebar0108, no un nuevo A/B de navegación0091→0108.

### Evaluación de la solución sugerida

Separar la animación del contenedor de la redistribución costosa es una dirección válida para un prototipo A/B. No es una garantía de visual idéntico: fijar el ancho inicial o final y recortar puede alterar cuándo cambian las columnas, introducir un salto de contenido o desajustar regiones de interacción. Un commit diferido debe seguir el final real de la transición y admitir reversas, Reduce Motion y resize; un temporizador fijo de0.42s no basta.

La evidencia confirma trabajo de layout y la mayor estructura interna de Inicio. No confirma que la invalidación de altura/root/proyección ocurra en cada frame ni que explique por sí sola el lag. Antes de sustituir la animación se necesita aislar invalidaciones de contenido/header y comprobar la variante en ventanas que crucen960/900pt y con interrupciones rápidas, midiendo frames/compositor además de CPU. No se declara aplicado un segundo fix ni se cambia el aspecto durante este análisis.

## Investigación de SwiftUI/AppKit con documentación Apple,2026-10-14

Pedido: estudiar por qué siguen sintiéndose mal los cambios de página mediante topnav y la apertura/cierre de sidebar. Esta etapa es investigación: conserva la implementación0108, sin nuevos cambios de producción ni nueva compilación.

### Fuentes primarias y aplicación al caso

- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance): hay que distinguir evaluación de cuerpos, actualizaciones de vistas de plataforma y otras tareas como geometría/texto. Un cuerpo rápido no demuestra que el trabajo posterior que desencadena sea barato.
- [WWDC25: Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/): el grafo de causas y efectos permite seguir invalidaciones que no quedan juntas en un stack imperativo. Los cambios del Environment también generan comprobaciones aunque un cuerpo termine sin ejecutarse. Se usó este instrumento para ampliar la traza CPU anterior.
- [WWDC23: Demystify SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/): dependencias e identidad determinan qué se actualiza. Recalcular valores de vistas no equivale automáticamente a destruir/recrear toda la interfaz. Hay que identificar la cadena que dispara trabajo y la frecuencia.
- [NSViewRepresentable.updateNSView](https://developer.apple.com/documentation/swiftui/nsviewrepresentable/updatensview(_:context:)): el puente actualiza la configuración nativa afectada por nueva información. En este código se mezcla esa actualización semántica con el progreso de presentación.
- [NSView.layoutSubtreeIfNeeded](https://developer.apple.com/documentation/appkit/nsview/layoutsubtreeifneeded()) y [needsLayout](https://developer.apple.com/documentation/appkit/nsview/needslayout): el sistema ejecuta layout antes de mostrar la vista; la llamada explícita obtiene geometría actualizada inmediatamente. Aquí se marca y fuerza repetidamente desde la actualización de la toolbar. Revisar esas llamadas permite evitar pasadas síncronas que no necesitan consumir geometría nueva.
- [Unifying your app’s animations](https://developer.apple.com/documentation/swiftui/unifying-your-app-s-animations) y [NSViewRepresentableContext.animate](https://developer.apple.com/documentation/swiftui/nsviewrepresentablecontext/animate(changes:completion:)): Apple ofrece un timing compartido para integración AppKit/SwiftUI y retargeting. El método del contexto figura disponible desde macOS15, con back-deployment antes de15.4, compatible con el mínimo del proyecto. Es una alternativa a reenviar una configuración completa por cada valor interpolado.
- [Core Animation: Improving Animation Performance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/ImprovingAnimationPerformance/ImprovingAnimationPerformance.html), guía histórica, y [política de redraw durante resize](https://developer.apple.com/documentation/appkit/nsview/layercontentsredrawpolicy-swift.enum/duringviewresize): tener capas no garantiza una animación barata. Dibujar/redimensionar y componer contenido son trabajos distintos. No se propone cambiar a ciegas políticas o transforms de vistas que administra el sistema.

Las páginas de referencia que el navegador devolvió sólo como shell JavaScript se leyeron también mediante su Markdown oficial con curl del sistema y verificación TLS normal. No se usaron blogs, foros externos ni recomendaciones no verificadas como evidencia.

### Medición nueva

- Bundle0108/hash previamente verificado `bf73470e7ca5a7f0074685c1b56b7a8599c4c7428ba4d5128862ec904e8663bf`, PID19314, mismo Mac. Ventana3024×1898, Inicio/Explorar/Biblioteca precargados y reproducción pausada. Tres acciones de sidebar (cerrar/abrir/cerrar) y Explore→Library→Home desde el selector nativo, no desde el sidebar.
- Plantilla SwiftUI de Instruments27;45.963932s guardados y exports de updates/causes/Time Profiler/hitches. La plantilla informa Layout Updates=Not Included: no se interpreta como una medición completa de todas las pasadas de layout.
- Se adjuntó a un proceso existente. Parte de las vistas previas al inicio carecen de nombre público, aunque descripciones de adaptadores, causas observables y tipos de actualizaciones sí están disponibles. El instrumento volcó árboles de diagnóstico; son datos privados locales, no instrucciones ni contenido publicable.
- Las lecturas AX posteriores al clic añaden trabajo directo/indirecto. Los tiempos entre solicitud de clic y observación no son latencia de UI. Las ventanas analizadas se cortan al siguiente clic para no mezclar acciones. Duraciones de eventos anidados y aristas del grafo no se suman ni se convierten en FPS o cantidad de redibujados completos.
- Evidencia privada bajo `.cache/navigation-fix-2026-10-13/validation-2026-10-14/`: `swiftui-transitions-0108.trace`, toc, `research-swiftui-updates-0108.xml`, `research-swiftui-causes-0108.xml`, `research-time-profile-0108.xml`, `research-hitches-updates-0108.xml`, eventos y `analyze-swiftui-research.py`/`swiftui-research-summary-0108.json`. Excluidos localmente de Git.

### Hallazgos

1. **La geometría vuelve a entrar en el camino de contenido de Inicio.** La traza tiene una causa directa `@Observable HomeFeaturedViewport.(CGFloat)` hacia el adaptador `HomeFeedTableView`, además de actualizar `HomeFeaturedHostedContent`. El código lee/escribe `featuredViewport.width` en `Coordinator.updateFeatured`. Al recibir una actualización, `updateNativeScrollView` llama incondicionalmente `updateFeatured(force:true)`, que puede reasignar el root de destacados. Así, la separación pretendida entre ancho y snapshot no es completa: un cambio de ancho puede volver a actualizar el adaptador y recorrer su camino de configuración. El grafo también enlaza esos cambios con HomeFeaturedView, ForEach de tarjetas, MediaArtworkControls y sus GeometryReader/botones.

   La aclaración anterior sobre rootView era incompleta: el callback de layout con force=false no lo reemplaza directamente, pero existe esta ruta indirecta con force=true. Hay que revisar ambas, no deducir ausencia de trabajo por el tiempo bajo del setter aislado.

2. **El cambio de capacidad produce picos en mitad de la animación.** Los eventos `PlatformViewChild<...HomeFeedTableView>` duran16.607/21.624/18.199ms en los tres toggles. Comienzan aproximadamente286/349/236ms después de solicitar el clic, dentro del tramo esperado de0.42s. Sus causas incluyen `GeometryActionBinder<_GeometryActionModifier<Int>>`; el único modificador Int de este tipo en las fuentes es el de HomeView que observa albumsPerPage y llama setFeaturedCapacity/rebuildProjection. Esto vincula los picos con la ruta de capacidad/proyección/aplicación nativa, sin atribuir todo el costo al cálculo de altura. A este ancho la altura del panel puede permanecer constante. La duración incluye instrumentación; no demuestra por sí sola la cantidad de frames perdidos.

3. **La toolbar repite configuración semántica mientras se desplaza.** `AnimatedWindowNavigationToolbarView.animatableData` transporta revealProgress; su body genera `WindowNavigationToolbarView`. Cada updateNativeContainer vuelve a pedir/configurar imágenes, tooltips y etiquetas localizadas de cuatro segmentos, y el historial vuelve a hacer lo mismo con sus cuatro botones. Existen observadores de idioma, pero el camino de progreso no tiene una guarda por revisión. Después se marca/ejecuta layout síncrono del header y se vuelven a invalidar hijos. El grafo vincula explícitamente revealProgress con preferencias, transacciones y AppKitSegmentedControl. El adaptador de toolbar registra44actualizaciones,87.509ms inclusivos y un máximo individual3.696ms en toda la captura. Son eventos instrumentados del adaptador, no44frames ni87.5ms de bloqueo continuo.

4. **El puente retenido añade reconciliación que merece acotarse.** El adaptador RetainedPageContent registra43updates/12.082ms inclusivos, máximo1.355ms. Reasigna rootView en cada update y el grafo muestra invalidaciones por Environment y layout. No es la ruta más costosa de esta traza, y no prueba recreación total de las páginas, pero conservar identidad no elimina automáticamente todo trabajo de actualización.

5. **Abrir sidebar y cambiar página son operaciones estructurales diferentes.** El sidebar sigue bajo un if que lo inserta/retira, y usa ScrollView+VStack con ForEach de todas las playlists/álbumes. Por tanto se vuelve a montar su contenido al abrir; el costo total de ese montaje no está aislado aquí. Las páginas principales están retenidas, pero navigateMain/router y la selección de opacidades no definen una transición animada común de contenido. La selección del control nativo y el cambio de presentación de las páginas pueden tener comportamientos visuales diferentes. Esto no equivale a una reconstrucción completa de toda la app.

### Orden de corrección propuesto, aún no implementado

- Separar configuración semántica de toolbar de su presentación. Actualizar iconos/textos/AX por cambio real de idioma/datos/selección, conservando callbacks frescos; mover/fundirse sin repetir esa configuración. Revisar el uso incondicional de layoutSubtreeIfNeeded y usar el timing/retargeting compartido del contexto cuando corresponda.
- Cortar la realimentación de geometría y el force de contenido. El coordinador puede comparar geometría con un valor nativo no observable, publicar sólo al hosting que la consume y decidir el reemplazo de root/snapshot por cambios semánticos. Hay que comprobar que una actualización puramente geométrica no active otra ronda de configuración del feed.
- Separar redistribución visual de la publicación/aplicación del snapshot al cruzar capacidad. Evitar una recarga costosa dentro del frame de transición; comparar alternativas que mantengan identidad, scroll y momento de aparición de columnas. Congelar todo o aplicar un temporizador fijo no garantiza conservar el aspecto y manejar reversas.
- Evaluar identidad estable/virtualización del sidebar y una política explícita de transición entre páginas. Mantener AX, foco, Reduce Motion, gestos y purga por cuenta del fix previo.

La validación siguiente debe aislar una modificación por vez, usar mismo tamaño/datos/build/Mac y cubrir ventana amplia, cruces960/900pt e interrupciones rápidas. Añadir una captura sin lecturas AX durante el tramo crítico y medir frames/compositor junto con CPU. El costo GPU del vidrio y el fondo no quedó aislado; no se declara que una única modificación resuelva toda la sensación de lag.

## Ejecución autorizada,2026-10-15

El usuario pidió implementar desde este plan con subagentes supervisados. Dos frentes con archivos separados: configuración/presentación de toolbar e invalidación/proyección de Inicio. Un tercer agente revisa sidebar, fronteras retenidas y regresiones sin editar. El integrador revisa los cambios y ejecuta pruebas/build/QA; no se autorizan instalación, publicación ni modificaciones de core/Windows.

- [x] Toolbar: diffs semánticos, localización por revisión y callbacks siempre actuales; conservar reloj/reversas nativas y eliminar layout síncrono redundante.
- [x] Inicio: geometría comparada fuera de observación y hosting invalidado por contenido real, sin perder callbacks, idioma, actividad o sesión.
- [x] Capacidad: reutilizar insumos de proyección y evitar publicar estantes/snapshots idénticos al cambiar columnas, sin temporizadores ni diferir la aparición visual.
- [x] Revisar contratos y regresiones de ambos frentes antes de integrar.
- [x] Pruebas focales, suite oficial/build numerada, firma/hashes y QA de app exacta.
- [x] Repetir captura0108→0109 en mismo Mac/tamaño/recorrido, explicitando AX/instrumentación y cambios del proveedor; no acredita igualdad total de datos ni fluidez global.

La revisión independiente recomienda conservar por ahora el montaje actual de sidebar y la política visual de cambio de página. Retener sidebar sin actividad/AX/purga explícitos conservaría tareas y popovers; agregar crossfade podría componer dos páginas. Su costo no quedó aislado, por lo que no se mezclan con las dos rutas de trabajo redundante comprobadas. La virtualización de sus listas queda como candidato sujeto a medición, no como fix aplicado. Tampoco se omite la reasignación del root de páginas retenidas por mera igualdad de ruta: debe seguir transmitiendo Environment, servicios y callbacks actualizados.

Implementación FIX-186:41XCTest+21Swift Testing focales aprobadas, incluidos10tests nuevos. El primer focal expuso que un wrapper con capturas iguales no se reevaluaba al reasignar root; generación explícita sin cambiar identidad corrigió las10aserciones, conservadas. Se verifican ancho sin dependencia inversa, cambios reales sin resize, callbacks actuales, montaje inicialmente oculto/reanudación, purga, capacidad y toolbar. La captura SwiftUI0108 nueva contiene las seis acciones dentro de35.958s, ventana JPEG3024×1898 y reproducción pausada. Incluye consultas AX posteriores a cada clic; se declara su carga, sin inferir latencia de input ni FPS. Build/QA/A-B del código nuevo pendientes.

### Entrega de FIX-186 y comprobación,2026-10-15

- Build0109 release **compiled**, sourceChangedDuringBuild=false,669aprobadas (188Rust/168XCTest/313Swift Testing),14live omitidas. Firma estricta y10hashes aprobados. SHA256 ejecutable `8104e2771b7be163204bf1bd87700074ab24c3a895e1269fd35728c8fc6da029`. Bundle `builds/macos/build-0109/Side B.app`; fuentes core/Windows mantienen los hashes previos de esta etapa.
- UI por ruta exacta/PID98772: páginas precargadas Explore→Library→Home sólo exponen destino activo. Scroll de Inicio0.3935162094763092 idéntico al regresar; fullscreen y Spotlight/Escape restauran AX. Settings abre/cierra, sidebar en ambos estados sin recorte y cinco toggles consecutivos terminan coherentemente. Playback pausado; no se accionaron Play/Like ni preferencias de sistema/cuenta. JPEG verifica3024×1898. Fixtures cubren umbrales y reversas; no todos los anchos ni preferencias se reprodujeron físicamente.
- Nueva referencia0108/PID92498 de35.958297s y0109/PID98772 de35.965599s; SwiftUI/Layout Updates=Not Included, mismo Mac/ventana/recorrido (cerrar/abrir/cerrar sidebar, Explore→Library→Home mediante topnav). Todas las acciones dentro de la cobertura. Los tiempos se recortan al primer1s desde solicitud de clic y al próximo clic. AX después de las acciones añade trabajo; no son latencias de input. El proveedor cambió algunas canciones/recomendaciones entre los arranques aunque se conservó estructura y tamaño: comparación parcial.

| Adaptador, primer1s de tres toggles |0108(ms inclusivos)|0109(ms inclusivos)|
|---|---|---|
| WindowNavigationToolbarView |32.703 /31.991 /32.099|1.827 /0.788 /2.022|
| HomeFeedTableView |4.477 /4.193 /4.059|4.260 /3.107 /4.710|

El adaptador toolbar completo acumula112.420→6.448ms en las trazas, pero pasar layout síncrono al ciclo de AppKit también mueve trabajo fuera de ese método. No se interpreta esa caída como ahorro total de la aplicación. El retorno a Inicio registra6.051→6.457ms; no demuestra mejora de ese evento. La prueba de Observation confirma el corte de dependencia inversa del ancho. Los tests verifican ausencia de reconstrucción/configuración igual y actualización semántica correcta.

La tabla hitches presenta tiempos altos incluso en reposo (referencia: ventanas de1s entre496y533ms) y no muestra mejora global clara en los tres toggles (unión de intervalos recortados:537.499/570.835/545.633→545.836/523.540/558.331ms). Se conservan como diagnóstico bajo instrumentación, no como FPS, frames perdidos o métrica ponderada de Organizer. Algunos registros finales avisan trabajo GPU; hace falta aislar composición e instrumentación antes de atribuirlo al fondo o vidrio. [Apple: Understanding hitches](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app) distingue actualización/commit/render y plazo de presentación; [Explore UI animation hitches](https://developer.apple.com/videos/play/tech-talks/10855/) explica normalizar tiempo de hitch, sin convertir conteos de etapas en frames.

Evidencia privada de la etapa: `implementation-2026-10-15/` contiene snapshots/hashes previos, focal inicial/final, build-verification.json, trazas SwiftUI de ambas builds, eventos/toc, exports y resúmenes de updates/hitches con sus scripts. FIX-186 cierra las correcciones justificadas de configuración/geometría; la casilla de fluidez global permanece pendiente. No se implementó retención de sidebar ni crossfade ni se cambió el fondo para ocultar un costo no aislado. Sin instalación en Applications, commit/push ni publicación.

La revisión independiente posterior confirma trabajo continuo del ambiente (`HomeAmbientSurface`, intervalo mínimo1/30s), pero no causalidad con el piso de registros: el reposo exporta47–56registros/s, predominantemente8.33ms sin Potential Issue, sin correspondencia demostrada con ese schedule. [Apple TimelineSchedule](https://developer.apple.com/documentation/swiftui/timelineschedule/animation(minimuminterval:paused:)) limita la cadencia máxima; [WWDC20/10077](https://developer.apple.com/videos/play/wwdc2020/10077/) explica que objetivos deliberados30/24Hz y reposo se contemplan al medir hitches. No se descuentan esos registros como costo fijo ni se cambia el ambiente por esa hipótesis. Correlacionar deadlines/Commit/Render/GPU/Frame Lifetime y aislar AX sigue pendiente; dos intentos de abrir Instruments por control UI terminaron en timeout, sin inspección gráfica de la traza.

## Seguimiento de optimización tras aceptación de0109,2026-10-15

El usuario confirma que0109 se siente mucho más responsiva y pide revisar otras oportunidades. Esa aceptación física complementa FIX-186 sin modificar los límites del perfil de hitches anterior.

FIX-187 elimina una búsqueda DFS de scrolls ortogonales que HomeNativeCollectionView hacía también en Flow (Inicio actual, Explorar y Biblioteca). Layout nil y Flow omiten scanner; otros layouts/transiciones conservan el contrato anterior. Retiro/cambio de layout limpia sólo clips observados; nuevo layout noFlow programa una pasada normal para rearmarlos. El cambio afecta un único archivo de producción; no modifica datos/layout/estética ni core/Windows. [Apple: Flow layout](https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout) organiza filas/columnas según un eje; [scroll ortogonal de secciones](https://developer.apple.com/documentation/appkit/nscollectionlayoutsectionorthogonalscrollingbehavior) corresponde al comportamiento de secciones composicionales.

- [x] Caracterizar antes de editar producción:103probes públicos,50hooks y50layout generan5.150lecturas cada uno; baseline4tests/23aserciones fallidas, compositional aprobado. Un primer intento falló compilando helper sin @MainActor y no cuenta como medición.
- [x] Implementar guardas/limpieza y revisión independiente por dos agentes; integrador añade rearmado explícito al cambiar layout.
- [x] Focal integrado57XCTest+1Swift Testing; repetición final4XCTest aprobada.0lecturas de probes en hooks/layoutFlow; retiro real conserva103lecturas AppKit frente206previas, separado del hook propio0. ScrollFlow no alterado ni observado; compositional/custom/transición conservados por tests.
- [x] Suite/build numerada, firma/hashes, QA de la app exacta.

La fixture sin datasource/ventana aísla el scanner, no reproduce layout/render ortogonal completo ni demuestra tiempos/FPS. La guarda reduce trabajo proporcional al árbol de controles sin cambiar el layout de AppKit.

Otros candidatos estudiados y no implementados:

1. Sidebar usa VStack para todas las playlists/álbumes y CachedAsyncImage inicia tareas fuera de viewport; el límite4de ImageCache sólo aplica a prefetch, no a image(for:). Priorizar experimento de filas lazy individualmente expandidas, midiendo montajes/solicitudes en biblioteca grande y preservando scroll/selección/menús/AX/cuenta. No se mantiene sidebar oculta ni se limita globalmente la caché sin estudiar cancelación y cargas visibles.
2. ExploreCatalogGridView compara dos arrays de identidades en cada update aun con cards iguales. Biblioteca primero guarda igualdad de cards. Posible fast path de datos conservando parent/callbacks/playback/localización; todavía no se midió su costo.
3. Header de Explorar puede capturar textos traducidos y su identidad no incluye idioma; añadir regresión antes de cachearlo. Biblioteca fuerza layout para tamaño del documento y clamp de offset: no retirarlo sin preservar geometría/scroll. RetainedMainPages conserva Environment/servicios/callbacks y no se cachea por mera ruta.

### Cierre de FIX-187

-0110 release **compiled**, sourceChangedDuringBuild=false;673aprobadas (188Rust/172XCTest/313Swift Testing),14live omitidas. Firma estricta y10hashes aprobados. SHA256 ejecutable `8890fccdbb2b590a51c6bc8effe5095c14d075a72e0c310e960dd7d499553e9f`; bundle `builds/macos/build-0110/Side B.app`. Core/Windows sin nuevos cambios respecto al inicio de etapa.
- QA por ruta exacta/PID11383, JPEG3024×1898: Explore→Library→Home con AX sólo del contenido activo; álbumes de Biblioteca nativos renderizados y scroll comprobado, vuelta a All. Inicio conserva0.3541147132169576 al visitar Explorar y regresar. Ensayo previo mezcló scroll horizontal con el cambio de página y no sirve como comparación de scroll; la repetición aislada sí conserva valor exacto. Sidebar en ambos estados sin recorte; Spotlight/Escape oculta/restaura AX. Playback pausado, estado final Inicio/sidebar cerrada igual al observado al retomar. Primer getApp terminó en timeout; el segundo confirmó apertura normal sin operar el llavero.
- Beneficio acotado al recorrido omitido/propiedad del scroll comprobados por regresión, sin nuevo A/B Instruments ni FPS acreditados. No se adjudica a0110 la aceptación física de0109. Evidencia privada `flow-layout-2026-10-15/`: baseline fallido de compilación, baseline funcional, focal integrado/final, snapshot/diff, build y verification.json. Sin instalación/commit/push/publicación. Sidebar lazy y otros candidatos permanecen pendientes.


## Investigación y corrección de layout durante animaciones,2026-10-15

El usuario informa que sidebar sigue sintiéndose mal y solicita resolver trabajo de Inicio que afectaría futuras animaciones. No se interpreta la aceptación de0109 como aceptación de toda la fluidez. FIX-188 corta la publicación de tamaño desde el viewport retenido hacia State/root y separa Speed Dial del ancho global de destacados, conservando el layout visible a cada ancho, las acciones y la propuesta exterior de FIX-123.

- [x] Revisar RetainedMainPages, HomeFeaturedView, HomeFeedTableView y fondo; documentación primaria NSHostingView/sizingOptions y WWDC22 Use SwiftUI with AppKit.
- [x] CPU0110/PID12694 con4toggles por página. Home460/499/473/498ms sin stacks AX en primeros750ms; Explore552/513/543/525ms. ViewGraph/display/layout de framework domina en ambas; no queda aislado a Inicio. Los~50ms con nombre rootView son DisplayList.ViewUpdater.render, no setter. Captura con screenshot antes de AX sigue teniendo stacks AX y no prueba ausencia de carga de accesibilidad.
- [x] Implementar retención de frame nativa; outer viewport llena propuesta, inner oculto congelado; Environment/root se actualizan semánticamente.
- [x] Extraer Speed Dial/artwork con entradas propias, sin equatable que ignore closures; paginación y AnyLayout conservados.
- [x]34XCTest focales aprobadas;84resizes del probe dan0updates también antes: prueba de contrato, no ahorro. Speed Dial tras asentamiento inicial mantiene0builders/0updates en40resizes del fixture de callbacks estables. 3SpeedDial tests y focal9 aprobadas; callback/menu/locale/actividad/paginación comprobados donde el fixture expone interfaces públicas. AX/clic SwiftUI en app pendientes.
- [ ] Suite completa/build oficial/firma/hashes/QA de app nueva.
- [ ] Comparar adaptadores SwiftUI con misma secuencia3toggles, Mac y ventana; resultado global/FPS y compositor siguen sin acreditar hasta evidencia apropiada.

Fuentes: [NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview), [sizingOptions](https://developer.apple.com/documentation/swiftui/nshostingview/sizingoptions), [Use SwiftUI with AppKit](https://developer.apple.com/videos/play/wwdc2022/10075/). sizingOptions=[] ya estaba aplicado: no se presenta como optimización nueva. El cambio evita realimentación geométrica entre sistemas, sin concluir que toda la reconfiguración sea reconstrucción de controles.

Reposo0110 desglosado por segundos:19–22s estable337msRunning/s, con142ms/s de búsqueda recursiva de autolayout y97ms/s de NSHostingView.layout. Los items/estantes se crean sólo durante asentamiento16–17/17–18, coincidente con AX, no permanentemente. Explorar36–50s estable~1ms/s. El fondoTimeline30Hz es candidato de disparo indirecto y debe aislarse si las correcciones de viewport/SpeedDial no reducen ese costo.


### Resultado0111 y continuación

FIX-188 build0111 compiled/sourceChangedDuringBuild=false/677aprobadas, firma/10hashes. QA conserva Songs página2 y scroll0.3935162094763092 al navegar; Spotlight/fullscreen ocultan/restauran AX, mismo viewport3024×1898, reproducción pausada. CPU de tres toggles484/483/479ms sinAX en primeros750ms y reposo25–35s387.2msRunning/s: no prueba mejora global. ReferenciaCPU0110 había precalentado2destinos y0111 los3; no se interpreta diferencia idle como regresión atribuida al fix.

Se prueba como cambio único posterior alojar HomeAmbientBackground en NSHostingView propio, sin cambiar Timeline/paleta/máscaras/fase. Puede acotar ViewGraph del fondo, pero permanece bajo mismaNSWindow y no garantiza evitar el recorrido global. Sólo A/B0111→siguiente build con mismas3páginas/Mac/ventana decide si ayuda. Candidato preparado fuera de Sources durante build y aplicado después; registro FIX-189 y validación final pendientes. Si no reduce costo, retirarlo o mantenerlo como investigación, sin atribuirle solución.


### Experimento FIX-189: hosting ambiental independiente

- [x] Aplicar como cambio aislado después de0111: renderer ambiental con mismo Timeline/máscaras/fórmulas/paleta en NSHostingView propio; inputs semánticos/Environment explícitos, frame nativo guardado y safe area exterior.
- [x]27pruebas focales aprobadas (5hosting nuevas con Environment real, paleta, scroll, suspensión y reloj).
- [ ] Build oficial/suite completa/firma/hashes.
- [ ] CompararCPUidle y3toggles contra0111; retirar/revisar experimento si no acredita reducción.
- [ ] QA composición/safe-area/AX/páginas/scroll/pausa; registrar límites de contenido/AX y no convertir CPU enFPS.


Resultado del experimento189:0112compiled/682aprobadas/firma10hashes; propiohosting conserva costo idle340.75ms/s. Referencia inmediata400.12ms/s, pero tamaño referencia no certificado nuevo y0112captura2642×1662, distinto a referencia histórica3024×1898. No afirmar15%/FPS ni causalidad. Se retira el hosting y sus tests específicos: reduceMotion/env siguen siendo requisito para renderer nuevo. Siguiente experimento: CALayers con animaciones precomputadas, sinTimeline/Timer/framecallbacks sobreSwiftUI; fórmulas generadoras y fase conservadas con error de interpolación acotado, comparación estática/pausa y A/B requeridos.


## Renderer ambiental nativo, FIX-190

- [x] PrototipoCALayer12keyframes, sinTimeline productivo; máscara/paleta en propietario anterior.
- [x]4regresiones geométricas/continuidad/identidad/input y error de interpolación; fórmulas originales8fases/3tamaños.
- [x] RutaGPUoffscreenvalidada por sentinels; se detecta diferencia de espacio de color y orientación de máscara antes de empaquetar.
- [x] Paridad visual tras filtro público sRGB, flip de máscara y signo de rotación nativa:48pares/96PNG, mediasmáximas0.967/0.349 y máximos7/4 sobre255. In-processCoreImage: ahorro debe medirse.
- [x] Suite completa/build oficial0113/firma/10hashes:682aprobadas,sourceChangedDuringBuild=false; core/Windows intactos.
- [ ] A/B contra0112 o0111 del mismo tamaño certificado, tres destinos precalentados,3toggles y reposo sin consultasUI. Si funciona, verificar retorno/scroll/sidebar/Spotlight/fullscreen y apariencia detrás de titlebar; no extrapolar CPU aFPS.

Focal35XCTest aprobadas y repetición5nativas/compositor final; nuevo A/Bcertifica ventana2642×1662 en0112 antescaptura y exigeigualenbuildfinal. Se preserva actividadscenePhase; se retiró gating NSApp.isActive adicional para no medir un fondo pausado por focodeotraapp. Build oficial siguiente sinedicionesdurantecompilación.

0113compiled/682aprobadas/firma/10hashes. AperturaPID70939 esperando llavero; QA/perfil final pendientes. Referencia actual0112:384.62msRunning/s idle,3toggles467/492/506ms sinAXen750ms;2642×1662verificado. No se extrapolan fixtures/build a fluidez.


### Regresión visual0113 y FIX-191

Usuario confirma apertura pero ventana invisible. Reproducido por CUA: AX y acciones siguen vivas, pantalla blanca en Home y Explore;0112 restaura dibujo completo en mismo tamaño2642×1662. Se rechaza0113 como candidata utilizable; la comparación offscreen no cubría compositorNSWindow/SwiftUI/Glass.

- [x] Reproducir0113 y control negativo0112, sin operar contraseña ni atribuir fallo al llavero.
- [x] Separar filtros CI del árbol visible: CAMetalLayer recibe CARenderer offscreen, CADisplayLink nativo sin invalidar ViewGraph/layout. Mantener30Hz/paleta/máscara/fase/pausa y límite2frames en vuelo.
- [x] Pruebas de aislamiento/render y backing2x, build oficial0115/firma/hashes/coreWindows;684aprobadas.
- [x] QA0115 con ventana real: visibilidad, sidebar/rutas/estado/Spotlight/fullscreen.
- [x] CPU0115 del mismo escenario/tamaño contra0112, reposo y clics separados; no usar ventana blanca como prueba de rendimiento.

Focal6 verde y8pares visuales1x/2x aprobados.0114compiled/683pruebas/firma10hashes/coreWindows/sourceChanged=false; no se abre como final. Revisión191 detecta último frame perdido al cancelar fade en Reduce Motion con movimiento detenido; prueba roja reproduce demanda ausente, se corrige antes de0115. TimeProfiler estándar excluye Waiting: CPU no certifica ausencia de esperas nextDrawable, complementar con sample independiente durante acciones. Referencia nueva0112 conserva2642×1662/Paradise pausada/tres páginas:373.5msRunning/s idle y486/497/504ms en750ms sinAX.


### Resultado0115 y trabajo pendiente

FIX-191 corrige ventana invisible0113:0115compiled/sourceChanged=false/684pruebas/firma10hashes/coreWindows intactos, SHA20dd03af0175b0fc1f859d9d084046de75bf3e668000a81440c224670d72c8a2. QA2642×1662 verifica ambas sidebar, paginaciónSongs/Albums, rutas conAXactivo, scroll0.3160621761658031 ySongs2 alvolver/Spotlight/fullscreen. FinalHome/sidebarabierta/páginas1/feed0/pausado.

- Reposo25–33s:373.5→120msRunning/s, layout310.88→16.75ms/s. Mejora observada~68%CPUmain/~95%layout; contenido/paleta proveedor cambian, sin garantíaFPS/GPU. Presenter concentra948de958ms finales sinAX.
- Toggles750ms sinAX486/497/504→505/463/492: no hay mejora concluyente de la sidebar. Hosting/ViewGraph domina, sin reload/setterroot/adapter concreto identificado. No atribuir costo a rootViewsetter: esDisplayList.render.
- Muestra separada12s/5665samplesmain/27nextDrawable sin hojaswaitcomprobadas enpresenter; intrusiva y sólo primera apertura dentrocaptura, no garantía ceroesperas.
- SwiftUI18s/dos toggles conserva tabla layout vacía porqueLayout Updates no está incluido: no es prueba de ausencia de layout.

Pendiente del objetivo global: habilitar captura de Layout Updates/causas con propietario verificable y separar ventana de animación del overhead AX; medir ancho de featured vs shell antes de migrar o cachear controles. MediaArtworkControls usaGeometryReader para boolcompact<64 aun en tiles conocidos≥144pt: candidato pequeño que requiereaislamiento, no explicación del costo completo. Mantener identidad/acciones/Environment y layoutvisible, no añadir temporizador que ignore cambios durante sidebar. Otro costo ya aislado: presenterCARenderer/CI ocupa prácticamente todoCPUidle restante; evaluar shaderMetal directo sólo con paridadvisual/ciclo y medida, sin declarar ese cambio implementado.

### Layout desde lanzamiento y candidato FIX-192

- [x] Guardar captura0115 desde lanzamiento después de parada del usuario,9:43.950; tablas layout presentes. Export CLI se interrumpe por crecimiento de scratch y se retira sólo ese scratch identificado. No usar sus filas parciales como owner fiable.
- [x] Leer UI Instruments del cierre marcado03:57.985, rango gráfico aproximado2.01s:59.03ms layout,52.66ms raízLazy,1.44ms raízAnyView. Rama más costosaHStack42.83→MoveTransition31.49→padding/sombra31.48→VStack29.71ms. Código y subagente identifican exterior SidebarView, no una fila concreta. El panel de Inicio no queda demostrado como causa dominante de este tramo.
- [x] Candidato mínimo geometryGroup alrededor de SidebarView, por dentro de transición y padding; ancho230pt ya fijo. No congelar visible, no retener sidebar oculta, no cambiar callbacks/Environment/Glass ni reserva.
- [x] Suite/build oficial0116/firma/hashes/coreWindows.
- [x] Validación perceptual del usuario de0116: «bueno quedo muy bien la verdad». Se conserva el cambio.
- [ ] QA exhaustiva del integrador: glass/menús/foco/gestos/reversas/Reduce Motion.
- [ ] Cuantificar con A/B contra0115 del mismo tamaño/Mac/tres destinos,3toggles y reposo. No confundir ahorro de reposo191 con mejora de sidebar ni aceptación perceptual con FPS medidos.

0116compiled/sourceChangedDuringBuild=false/684pruebas/firma10hashes/coreWindows sin cambios; SHA d3b741e3bcb029385e2955a9c097c1c123b2a8dc7664377bb54fa103a9dda55c. AperturaPID16949 esperaSecItemCopyMatching; no es QA ni medida de mejora. Referencia nueva0115,2642×1662/tresdestinos/pausa/3toggles:499/508/495ms sinAX en750ms. Su tramo25–33s carece deRunningmain: certificar visibilidad/actividad antes de comparar reposo, no interpretarlo como ahorro nulo.

Actualización posterior,2026-10-16: el usuario confirma que el resultado quedó muy bien. Se registra aceptación manual de0116; la comparación instrumental posterior no se completó y no se afirma un porcentaje de mejora de sidebar.
