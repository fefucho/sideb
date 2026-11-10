# Punto de reanudación — reproductor lateral Side B

> Actualización01/11: este handoff describe0181. La entrega técnica vigente es build0183 (FIX-278/279, PLAN-031 iteración5):841Swift+298Rust, firma/10hashes y fuentes estables verificados. El usuario ahora pide aprovechar mejor el espacio vertical de la portada cuadrada; esa ampliación está en discusión y aún no implementada.

## Pedido vigente

El usuario pidió compactar contexto y luego corregir bugs y terminar la UI. Todavía no especificó nuevos bugs de build0181. No inventar síntomas ni empezar otra reescritura sin revisar el caso real.

Repo canónico: `/Users/stefano/Documents/PROGRAMACION PADRE/SIDE B RUST BASED PROJECTO/SIDE B`. Comunicar en español rioplatense, con avances breves; evitar confirmaciones innecesarias y esperas sin explicación.

## Estado comprobado

- Última entrega: `builds/macos/build-0181/Side B.app`.
- `BUILD.json`: `compiled`, Release, `sourceChangedDuringBuild:false`.
- Runner oficial:272XCTest+568SwiftTesting=840Swift aprobadas;112innertube+186sideb-core=298Rust aprobadas,10live omitidas.
- Firma ad hoc y10hashes del bundle revalidados.823claves ES/EN sincronizadas y verificadas.
- Sin commit, push ni publicación. Muchos cambios previos y archivos untracked: revisar git status y conservarlos; no adjudicarse todo el diff.
- FIX-277 registra este rediseño; FIX-276 pertenece al otro chat que agregó fuentes de letras. Siguiente ID libre al cerrar este resumen:278; comprobar nuevamente antes de usarlo.
- Plan principal: `apple/plans/PLAN-031-now-playing-sidebar.md`, sección Iteración4. Paridad del panel:PAR-046 abierta. Fuentes de letras:PLAN-020/PAR-047, sin declarar validación Windows por tests Mac.

## Decisiones de producto aprobadas

1. El trabajo de controles afecta el pie del panel derecho; la barra flotante horizontal conserva distribución y acciones.
2. Pie adaptativo256–320pt con metadata y Like/Dislike/menú, progreso ancho con tiempos debajo, transporte espaciado y volumen/AirPlay visibles. Conservar semánticas Side B.
3. Imagen estática o animación1:1: tarjeta cuadrada centrada, márgenes y esquinas redondeadas, como fullscreen. Evitar estirar una carátula cuadrada para fingir vertical.
4. Video vertical: inmersivo a todo el ancho, desde arriba; máscara inferior nativa y superficie cromática continua con controles. Sin franjas horizontales entre copias de imágenes y video.
5. Mostrar carátula inmediatamente y reemplazar al llegar el primer frame del video. El usuario aceptó dejar para después la animación elaborada del cambio de formato.
6. Recomendaciones deben quedar al nivel de cola/playlists: viewport nativo, celdas reutilizables, imágenes cancelables y llegada progresiva; no basta con diferir un árbol SwiftUI.

## Implementación actual

### Composición y controles

- `Views/PlaybackSidebar/PlaybackSidebarScene.swift`: cabecera/cuerpo/pie; usa altura adaptativa y renderer nativo.
- `Models/PlaybackPresentation.swift`: modo exclusivo barra/lateral/fullscreen y retorno al origen; `footerHeight(for:)`.
- `Views/Components/PlayerBarView.swift`: acciones compartidas; parámetros `isSidebar` y `sidebarHeight`.
- `PlayerBarProgressView.swift`: modo apilado opcional `isStacked`, defaultfalse conserva barra horizontal.
- `FullscreenNowPlayingView.swift`: host común de letras/cola/artwork; conserva las fuentes nuevas del otro chat.

### Portada/video

- `Views/PlaybackSidebar/NowPlayingSidebarArtwork.swift`: `SidebarArtworkLayout`, tarjeta cuadrada inmediata; cambia a inmersivo sólo al primer frame listo. Preview del mismo video para blur ambiental, sin capturas por frame.
- `Views/Fullscreen/Artwork/AnimatedArtworkView.swift`: `AnimatedArtworkSurfaceStyle` controla radio y máscara inferior dentro de AVPlayerLayer; callbacks de frame/preview/invalidez.
- `AnimatedArtworkController.swift`: identidad por álbum/sesión, fingerprint por metadata/orientación, cancelación/generaciones, preparación opcional con audio pausado (`prepareWhilePaused`), suspensión por scroll y restricciones/pressure.
- Video visible pausado retiene su frame; idle libera cuando deja de poder resolverse/verse. Evita volver solo a cuadrado tras30s de pausa visible.
- `FullscreenBackdrop.swift`: color continuo del panel y luminancia acotada. Fullscreen conserva presentación propia.

### Recomendaciones

- `Views/PlaybackSidebar/NativeSidebarRecommendationsView.swift`: un NSScrollView/NSTableView con spacer inicial del hero, filas de secciones/estados/canciones; reutiliza NativeQueueTrackCellView sin crear cola propia. Actualiza por revisión/diffs y conserva ancla al insertar datos por encima.
- Controles refresh, selección, menús, teclado, hover y votos conservados. Refresh se reconfigura cuando termina loading; hover se restaura al actualizar filas.
- `NativeSidebarArtistShelf.swift`: NSCollectionView horizontal reciclable, fotos cancelables y paso de scroll vertical al padre; menús creados bajo demanda.
- `NowPlayingSidebarRecommendations.swift` ahora contiene sólo modelos preparados/IDs; el feed SwiftUI antiguo se retiró.
- `SidebarArtworkScrollCoordinator.swift`: estado por ocurrencia, progreso cuantizado y host de artwork; bridge medidor antiguo retirado.
- `PlayerViewModel.swift`: recommendedRevision evita comparar payloads por reloj; fetch publica secciones conforme llegan y descarta respuestas por request/cuenta; mantiene error parcial/reintento. No añade canciones a QueueManager al renderizar.
- Marcador Instruments `SidebarRecommendations.Update` delimita aplicación/layout, sin títulos ni URLs.

## Verificación y límites reales

- Pruebas de payload10000: render limitado al contrato de10por estante y al viewport; identidad de duplicados, actualización sin reconstrucción, scroll/remount y ancla al insertar artistas.
- Regresiones de preparación pausada, suspensión/reanudación con el mismo AVPlayer, liberación y presentación cuadrada/vertical.
- Revisión visual parcial en app0181: pie, tiempos debajo, fondo continuo y tarjeta cuadrada centrada observados. Se vieron letras funcionando visualmente; no se escuchó/verificó audio ni se hizo VoiceOver completo.
- Pendientes: video vertical real con distintas portadas, mínimo960×640, cambios rápidos/resize, fluidez al llegar recomendaciones y comparación controlada de rendimiento. No afirmar FPS ni que el lag desapareció por pasar tests.
- Trazas locales de0178: `/tmp/sideb-sidebar-before-0178.trace`, `/tmp/sideb-sidebar-loading-0178.trace`. No son una comparación controlada con0181; no sacar porcentajes de mejora de ellas.
- Automatización nativa: lecturas/capturas funcionaron, algunas acciones sobre pestañas agotaron timeout. Esto no demuestra que la app se bloquee; lecturas posteriores seguían funcionando. Había varias builds previas abiertas: identificar proceso correcto al medir.

## Incidencias de integración ya cerradas

-0179: SwiftTesting SIGTRAP en ExperimentalLyricsFetchIntegrationTests. El fixture SideBCore(noPointer:) no interceptaba el nuevo setSetting de selección de fuente. Se agregó override y comprobación de fuenteauto; no se editó binding a mano ni se cambió producción de letras.
- Se retiraron dos argumentos inválidos pasados a ClassicLyricsClockHost; el selector de fuentes permanece en el menú común.
-0180: todos los tests pasaron, pero sync-localizations --check detectó catálogo generado desactualizado. Se regeneraron823claves desde fragmentos y0181 cerró todo.
-0179/0180 conservan diagnósticos, no son entregables completos.

## Reglas para continuar

Leer AGENTS.md, apple/AGENTS.md y antecedentes relevantes en FIXES.md antes de editar. Core compartido protegido; esta iteración no lo modificó. Tall opcional de core pertenece a la iteración3 aprobada: prefer_tall=false por defecto, fallback cuadrado; Windows sigue sin UI tall.

Respetar los cambios concurrentes terminados de letras y los previos de cola/Windows. No editar bindings manualmente. Si se necesita build, usar `.agents/skills/sideb-build-macos/SKILL.md` y `node Scripts/build-version.mjs macos`; conservar todas las builds numeradas.

No hay procesos de tests/build pendientes de este trabajo ni subagentes trabajando. El usuario autorizó opcionalmente Luna6 para código y Sol6.1 para razonamiento; no es obligatorio delegar. Para el próximo bug: reproducir en0181, leer componente/fix, parche acotado, comprobaciones relevantes y registro real de límites/resultados.
