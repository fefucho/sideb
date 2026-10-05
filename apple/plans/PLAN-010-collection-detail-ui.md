# PLAN-010: detalle compartido de álbumes y playlists

- Fecha: 2026-10-05 (America/Montevideo).
- Estado: base FIX-114/build-0034 y pulido FIX-115/build-0035 verificados automáticamente; validación manual pendiente. FIX-116/build-0036: continuidad del ambiente en shell verificada automáticamente; apariencia real pendiente. FIX-117/build-0038: viewport/campo/clear/transacciones verificados automáticamente; comprobación física pendiente.
- Alcance: Apple, vistas detalle y tabla; conservar cola especial FIX-113 y reproducción progresiva FIX-112. No core/Windows/version pública/commit/publicación.

## Contrato acordado

Álbum y playlist comparten cabecera, controles y tabla; las capacidades por tipo activan columnas/orden/edición sin duplicar UI. Cabecera y canciones recorren un único scroll reciclado. Portada/metadatos/acciones de cabecera +20 % (180→216 pt). Revisión del usuario FIX-115: filas 58 pt, apenas mayores que las originales 52 (reemplaza 78 de FIX-114), portada 44/Play 32/acciones 28. Ambiente de portada más vivo (.58/.50, humo .25/.20) detrás de toda la ventana —incluidos título y sidebar— hasta 140 pt bajo la cabecera (FIX-116), siguiendo el scroll nativo del documento, sin hit testing. FIX-117: viewport al borde superior; separación de toolbar dentro de la cabecera medida que se desplaza, sin padding exterior de página; fade intenso hasta 60 % y caída suave al fondo real. Conservar movimiento lento y pausas por Reduce Motion/inactividad/fuera de viewport.

Buscador al borde derecho de la misma línea de Play/Guardar/Aleatorio, adaptable a ventanas estrechas. En playlist, selector de orden al lado. Filtrar sólo oculta filas: pulsar una coincidencia sigue por la lista completa desde su ocurrencia elegida. El orden seleccionado determina también la reproducción de toda la playlist, confirmado por el usuario; completar catálogo antes de reproducir órdenes locales para no ordenar sólo un prefijo. Preservar duplicados, continuaciones y acciones.

Playlist: tabla con encabezados Canción, Artista, Álbum y Duración; Like y menú separados a la derecha. Álbum comparte tabla sin columna Álbum ni selector de orden; canción/título, artista, duración, Like y menú. Enlaces reales independientes de reproducción.

Orden: personalizado, título, artista, álbum, agregado recientemente, agregado hace más tiempo y duración. No inventar fechas: SongItemRecord no incluye fecha de lanzamiento ni de agregado; retirar lanzamiento en FIX-115 por pedido del usuario, órdenes de agregado usan proveedor cuando disponible. Orden local alfabético/duración sobre catálogo completo, sin modificar el orden guardado del proveedor. Sólo playlists propias permiten arrastre de orden personalizado, guardado en YouTube Music; ajenas y Likeados no son editables. Completar propias en personalizado antes de habilitar arrastre para conocer el sucesor real incluso al final visible. Deshabilitar arrastre mientras hay filtro/otro orden/carga/mutación, conservar IDs de ocurrencia/setVideoId. Bloquear cambios paralelos de orden remoto y reproducción durante su guardado; restaurar orden tras error.

Buscador nativo sin borde de foco interior, editor temporalmente transparente y clear NSButton montado de forma estable (FIX-117): clic fuera y Escape terminan edición sin borrar filtro, monitor por ventana y retiro al desmontar. X forma parte del buscador y conserva edición; campo/editor/binding se vacían juntos. Cambiar proyección de pistas dentro de transacción AppKit antes de recalcular altura/configurar header; conservar campo montado. Enlaces de artista/álbum aclaran al hover/foco; reutilizar ID de artista del header sólo cuando el crédito coincide y la fila no trae destino propio.

## Etapas

- [x] Cabecera como fila inicial de tabla: mismo scroll y reciclaje, cálculo de altura sin observar cada píxel.
- [x] Componente único de cabecera/toolbar con medidas +20 %, filtro y selector condicionado.
- [x] Ambiente común de carátula con movimiento acotado, caché y fade.
- [x] FIX-117: viewport completo, separación superior dentro del scroll, transparencia del editor y clear nativo; filtro/restauración de filas transaccional, pruebas con 94 pistas y editor activo.
- [x] FIX-116: fondo a todo el shell, sin franja superior ni corte tras sidebar; geometría nativa de scroll/resize/rebote, identidad por página/cuenta y pausa en Ahora suena.
- [x] Presenter único de filas detalle con columnas y tamaños ajustados a 58 pt, links/Like/menú sin disparar reproducción.
- [x] Proyección estable de filtro/orden, catálogo completo al necesitarlo y rechazo de respuestas obsoletas.
- [x] Orden manual de propias por API actual; casos ajenos/Likeados deshabilitados.
- [x] Pruebas apropiadas, revisión de subagentes/diff, runner numerado y documentación FIX/paridad.

## Referencias y límites

FIX-097 (cola/ocurrencias/catálogo), FIX-108/109 (paleta/humo Inicio), FIX-111/112 (cartas/clic/latencia), FIX-113 (cola especial). Pruebas sin NSWindow no certifican scroll físico, audio, apariencia de cuenta real ni consumo Instruments. Windows necesita equivalente Svelte/CSS y verificación de destino.

Focal de 34 Swift Testing aprobada y runner final `node Scripts/build-version.mjs macos`: 180 Rust aprobados (7 live ignorados), 54 XCTest y 216 Swift Testing/5 suites aprobados. Incluye reproducción filtrada de álbum en el estado final. Revisión de modelos/catálogo por subagente Luna y revisión integradora de vistas/tabla/ambiente; corregido drag del prefijo paginado y permisos LM/VLLM. Previews de cabecera real a 600/1100 pt inspeccionadas en `/tmp/sideb-fix114-previews`; render fuera de ventana comprueba composición/altura, no certifica materiales Liquid Glass ni cuenta real.

Build: `builds/macos/build-0034/Side B.app`, BUILD.json/build.log. Release arm64, SDK 27.0 / mínimo macOS 15.0, firma ad hoc verificada; `status: compiled`, `sourceChangedDuringBuild: false`. Fuentes core/Windows/bindings/version.env intactas, sin commit/push/publicación ni apertura automática. Documentación de cierre actualizada después del runner, sin cambios posteriores de código. Validación manual de scroll/foco/arrastre/guardar orden, audio y medición Instruments siguen pendientes.

## Pulido FIX-115

- [x] Buscador sin ring interior, clic exterior/Escape y monitor por ventana, prueba con ventana oculta.
- [x] Densidad 58/44/32/28 compartida; enlaces con hover/foco y destino real.
- [x] Ambiente vibrante extendido al inicio de canciones, pausa por viewport y sin capturar clics.
- [x] Retirar opción lanzamiento sin fechas disponibles y actualizar contrato de paridad.
- [x] Runner numerado final y registro de comprobaciones/límites.

Cierre FIX-115: focal final 3 XCTest y 32 Swift Testing; runner 180 Rust (7 live ignorados), 54 XCTest y 219 Swift Testing/5 suites aprobados. `builds/macos/build-0035/Side B.app`, compiled/sourceChangedDuringBuild false, SDK 27.0/macOS mínimo 15.0/firma ad hoc verificada. Código intacto tras runner; documentación de cierre posterior. Prueba de foco con NSWindow oculta, viewport/hit testing nativo y enlaces, sin certificar aspecto de vidrio/portadas ni clic físico con cuenta real. Sin apertura automática, commit, push o publicación.

FIX-116: focal de 3 XCTest/22 Swift Testing aprobada, dos nuevas regresiones de cobertura/scroll/identidad en ventana oculta y revisión Luna sin hallazgos. Runner final build-0036 aprobado: 180 Rust (7 live ignorados), 54 XCTest y 221 Swift Testing/5 suites; status compiled, fuentes estables y firma verificada. Apariencia en sesión real pendiente.

FIX-117: Swift release completa aprobada (55 XCTest/224 Swift Testing); la nueva UI nativa se ejecuta en XCTest antes de los modelos paralelos tras una espera agotada en build-0037. Runner final build-0038 aprobado: 180 Rust (7 live ignorados), 55 XCTest y 224 Swift Testing/5 suites; compiled, fuentes estables, firma/SDK verificados. Sin stack concluyente del cierre reportado; escenarios de búsqueda/borrado nativos cubiertos, validación física con cuenta real pendiente.

## Seguimiento FIX-118 (2026-10-05)

- [x] Reproducir en build-0038 el rectángulo al enfocar el campo vacío y la franja superior con CUA.
- [x] Editor NSTextView propio desde NSCell, transparente antes de escribir y ante atributos reaplicados por hosting; no alterar otros editores.
- [x] Mensaje vacío como footer de canciones, sin cambiar altura de cabecera; transacciones nativas de filtro sin animación.
- [x] Host decorativo sin segunda safe area de ventana; comprobar pintura del borde superior con titlebar real.
- [x] Completar focal/suite y build numerada.
- [ ] Comprobación visual en aplicación (Mac bloqueado).
- [x] Registrar FIX-118/PAR-011 y límites de validación.

Build final build-0039: runner `node Scripts/build-version.mjs macos` aprobado, 180 Rust (7 live ignorados), 58 XCTest y 224 Swift Testing/5 suites (462 total). `builds/macos/build-0039/Side B.app`, BUILD.json/build.log; compiled/sourceChangedDuringBuild false, release arm64, SDK 27.0/macOS mínimo 15/firma ad hoc verificada. Focal final 11 XCTest/29 Swift Testing aprobada; revisión Sol e integradora. Código conservado tras runner; documentación posterior. Comprobación de app detenida por Mac bloqueado al seleccionar la nueva build con CUA; se pidió desbloqueo. Mantener pendiente la apariencia/fluidez física y medición Instruments; las pruebas no certifican FPS ni audio.
