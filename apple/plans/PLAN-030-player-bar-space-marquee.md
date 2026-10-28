# PLAN-030 — Barra de reproducción: ancho útil y título desplazable en macOS

- Fecha: 2026-10-27 (America/Montevideo).
- Estado: implementación completada; pruebas Swift preparadas, ejecución y validación nativa pendientes.
- Objetivo: dedicar a título y artista/álbum el ancho útil entre portada y acciones, acercar Corazón destacado/dislike/⋯ al texto natural y recuperar la lectura automática del título largo con pausa al pasar el mouse.
- Plan espejo: [Windows PLAN-022](../../windows/plans/PLAN-022-player-bar-space-marquee.md). Seguimiento común: [PAR-044](../../PARIDAD.md).
- Alcance: barra inferior Mac, su distribución y presentación del título. Incluye el radio de portada y retirar el badge de los créditos de la pista activa fullscreen; no modificar core, reproducción, cola, servicios de créditos ni navegación.

## Hallazgos y antecedentes

1. `PlayerBarView.swift:43` añade `Spacer(minLength: 12)` entre metadata y controles derechos; los espacios del HStack se suman a esa separación. La metadata tiene además `.frame(maxWidth: 340)` en `trackInfoSection`. Hay dos propietarios del espacio libre; el texto no tiene prioridad exclusiva sobre él. La cantidad visible debe medirse en Mac: la captura del usuario corresponde a Windows.
2. Like ocupa espacio dentro del título; en compacto se traslada a la segunda línea. ⋯ es otro elemento horizontal de 28 pt. Unificarlos en una columna libera ancho en las dos líneas y elimina esa diferencia entre tamaños.
3. Con canción activa se utiliza `FeaturedTrackTitle`; `ScrollingTrackTitle` sólo queda en «Sin reproducción». El cambio está confirmado en el diff de `63b896b`: se sustituyó el componente desplazable por el título con enlaces. [FIX-167](../../FIXES.md#fix-167) documenta esos enlaces y su hit testing por glifo. Es una sustitución concreta comprobada; no se atribuyen otras regresiones a ese commit agregado.
4. `FeaturedTrackTitle.swift` crea un `NativeTrackActionField` de una línea con `.byTruncatingTail`; no hay desplazamiento integrado. El componente viejo sí medía overflow, pero al entrar el mouse cancelaba la tarea y ponía offset en cero: tampoco satisface congelar exactamente la posición visible.
5. [FIX-038](../../FIXES.md#fix-038) describe la distribución anterior de Like; [FIX-039](../../FIXES.md#fix-039) conserva accesos y enlaces. [FIX-059](../../FIXES.md#fix-059) explica por qué volumen usa overlay y una huella estable. Se revisaron como antecedentes históricos, contrastados con las fuentes actuales; sus pruebas no validan este plan.

## Contrato común con Windows

Contrato actualizado por FIX-265: transporte → hueco invisible29 → portada → columna de título y artista • álbum → gap10 → Like destacado y columna dislike/⋯ → espacio sobrante → hueco invisible17 → Letras/Genius/cola y controles propios del sistema.

- Mantener cápsula de 74 pt de alto y máximo 820 pt, centrada en el contenido. No ensancharla para ocultar el problema.
- El texto recibe todo el ancho sobrante. Retirar el límite arbitrario de 340 pt y el Spacer flexible posterior; los controles derechos conservan su ancho real, incluido AirPlay en Mac.
- Ambos separadores de la barra son invisibles:29pt entre transporte y portada,17pt antes de Letras. Los controles derechos siguen anclados; el espacio que no necesita metadata corta queda después de sus acciones.
- Corazón destacado: Like32×44/icon25 a izquierda de dislike arriba y ⋯ abajo24×22/gap2; separación horizontal4, conjunto60×46. Reservar la huella sin canción/sesión y deshabilitar rating sin sesión real. Dislike usa la acción existente que envía DISLIKE y retira la ocurrencia activa, sin estado visual ficticio.
- Título y segunda línea comparten el mismo borde derecho antes de esa columna. La segunda línea sigue mostrando enlaces independientes de artistas y álbum; no se introduce animación adicional en ella.
- Conservar el badge secundario de barra, cola y Relacionado de [PLAN-029](PLAN-029-explicit-content-indicators.md). Por revisión posterior del usuario, fullscreen de pista activa omite badge en título y créditos; se conserva el rating.
- Desplazar horizontalmente el título completo sólo si su contenido medido excede el viewport por más de 1 pt. Una línea que cabe permanece inmóvil y alineada a la izquierda.
- Ciclo propuesto, igual en ambos sistemas: espera inicial de 1 s, recorrido hacia la izquierda a 24 pt/s (duración mínima 3,5 s), pausa final de 1,3 s y retorno al inicio sin animación antes del siguiente ciclo.
- Hover o foco de teclado dentro del título congela la posición visible, sin saltar al principio; al salir de ambos continúa el tiempo restante. Abrir un menú de crédito mantiene la pausa hasta cerrarlo.
- Cambio de canción/texto o ancho reinicia medición y ciclo, sin heredar offset. Actualizaciones de posición de audio o Like no deben reiniciarlo. Si aparece hover durante un resize, se mantiene pausado en el nuevo inicio.
- Reduce Motion: título estático truncado, texto completo disponible mediante ayuda accesible/tooltip. Suspender animación cuando la barra no es visible o la app está en segundo plano; no añadir ticks a PlayerViewModel.
- Conservar enlaces a invitados, clic derecho, menú, foco y nombres accesibles. Una sola representación interactiva del título: sin copias enfocables o anunciadas dos veces.

## Implementación prevista

- [ ] Medir ancho real de transporte, AirPlay y controles derechos en barra de 620/700/760/820 pt; registrar baseline antes/después y comprobar umbral compacto de 760.
- [x] Reorganizar `Views/Components/PlayerBarView.swift`: metadata expansible, columna de acciones24×22 con2pt entre ellas, separador17pt y grupo derecho intrínseco. Compacto conserva las cinco acciones de transporte, reduce sus blancos a24/32pt y gaps a4pt; derecha reduce gaps a4pt conservando volumen/AirPlay32pt. Badge secundario existente conservado.
- [x] Incorporar presentación desplazable optativa a `Views/Components/FeaturedTrackTitle.swift`, activada sólo por la barra. El resto mantiene su representable de campo nativo original, sin viewport ni observadores añadidos.
- [x] Implementar `NativePlayerTitleViewport`: `NSClipView` desplaza bounds nativos; texto, botones, AX y coordenadas de puntero comparten geometría. Sólo nombres enteramente visibles conservan controles visibles; un callback del overlay reaplica clipping después de reconstruir créditos, incluso durante pausa.
- [x] Usar `NSAnimation` no bloqueante con progreso temporal conservado al pausar; sin Timer/ticks SwiftUI. Cancelación al desmontar, reinicio por canción/texto/ancho, pausa por hover/foco/menús/app en segundo plano y ventana oculta/minimizada/oculta por otras ventanas. Reduce Motion mantiene truncado y ayuda con título completo.
- [x] Retirar `ScrollingTrackTitle`; su alternativa sin reproducción es texto estático. La pista activa conserva invitados mediante el campo original dentro del viewport.
- [x] Añadir `PlayerBarTitleMotionTests.swift`: temporización, pausa determinística/resize/cambio de identidad, geometría nativa, hit testing desde host, clipping/reconstrucción de créditos y Reduce Motion. Se revisaron las regresiones existentes de hover/reutilización; no se ejecutaron desde Windows. La medición de layout SwiftUI real sigue pendiente, sin prueba geométrica ficticia de la barra completa.

## Verificación y cierre

- [ ] Probar títulos cortos/largos, feat/ft con enlaces, acentos/emoji, artista/álbum largos o ausentes, carga/error/reintentar, Like pendiente/error/invitado, cambio rápido de pista y metadata tardía del mismo ID.
- [ ] Medir que no haya hueco elástico después de ⋯, que ambos textos tengan el mismo límite derecho y que Like/dislike/⋯ ocupen su conjunto60×46 sin colisiones.
- [ ] Verificar hover a mitad del recorrido: posición estable al menos 2 s y continuación al salir; repetir con foco y menú. Resize, sidebar expandida/compacta, fullscreen abierto/cerrado y ES/EN.
- [ ] Comprobar que volumen overlay no cambie los bordes del texto; AirPlay, scrubber, todos los accesos y teclado conservan sus acciones.
- [ ] Ejecutar regresiones focales y `swift test --package-path apple` en un Mac; para build usar `sideb-build-macos` y `Scripts/build-version.mjs macos`. Ejecutar allí la regeneración de XCFramework/bindings que requiere el estado actual de PLAN-029.
- [ ] QA nativa macOS 15 y sistema con Liquid Glass disponible, VoiceOver y Reduce Motion. Revisar actividad en segundo plano; no inferir FPS de compilación.
- [x] Revisar diff y registrar [FIX-264](../../FIXES.md#fix-264)/PAR-044 con implementación y límites por destino. Windows cuenta con pruebas/fixture Edge y posterior build0023 Release compiled (verify1084pruebas aprobadas); aceptación nativa de ambos sistemas permanece pendiente. No se generó build Mac.

## Evidencia de FIX-264 y límites nativos

Implementación y revisión estática realizadas desde Windows sobre fuentes vigentes e historial. `git diff --check` acotado a los tres archivos existentes modificados pasó. Se intentó `swift test --package-path apple`: PowerShell respondió que `swift` no está instalado/reconocido; ninguna prueba Swift/AppKit se ejecutó. Sin build, bindings nuevos, app Mac abierta ni medición visual/FPS/audio.

El cálculo de las huellas declaradas deja aproximadamente106pt para texto a620pt en compacto (transport144 + primer separador29 + portada40 + gaps16 + acciones24 + separador17 + derecha212 + padding32), y200pt a820pt en modo amplio (208 + 29 + 46 + 24 + 24 + 17 + 232 + 40 de ancho ocupado). Es cálculo de fuentes, no baseline/medición nativa; comprobar tamaños intrínsecos y umbral760 en Mac. El volumen conserva su huella32×32 y overlay152pt.

Las pruebas preparadas de pausa verifican tiempo/posición conservados con avance determinístico sin ventana. No certifican todavía una congelación real de2s ni reanudación durante `NSAnimation`; esa aceptación temporal, foco/menús y VoiceOver requiere Mac. El integrador mantiene el registro efectivo en FIXES.md/PAR-044 y la validación pendiente.

## Revisión Corazón destacado — FIX-265 (2026-10-28)

- [x] Completar la implementación parcial recibida: `PlayerBarMetadataActionLayout` mide el tamaño ideal real de las dos líneas mediante `sizeThatFits(.unspecified)`, incluidos campo nativo del título, créditos SwiftUI, badge y separadores de artista/álbum. Limita metadata a `available−70`; las acciones quedan a10pt del final de la línea más larga. No se usa cantidad de caracteres ni offset de marquee/audio para el ancla.
- [x] Reservar60×46 para Like32×44/icon25, gap4 y dislike/⋯24×22/gap2. Like y dislike deshabilitados sin canción/sesión; guardas también en acción. Dislike reutiliza `PlayerViewModel.dislikeTrack`, incluida reversión local del Like ante error remoto y eliminación inmediata de ocurrencia según su política preexistente.
- [x] Reemplazar también el separador entre transporte y portada por hueco invisible de igual ancho; conservar hueco17 antes de Letras. La portada normal y fallback usan `AppTheme.artworkThumbnailRadius=2`, mismo token que `NativeQueueTrackCellView`.
- [x] Retirar `ContentRatedMetadata` exclusivamente de los créditos de la pista activa en `FullscreenNowPlayingView`; no se altera rating, barra, cola ni Relacionado. Esta decisión actualiza la revisión de PLAN-029 que antes mostraba E debajo del título grande.
- [x] Investigar gradientes/blur de navegación: FIX-261 y el componente flotante nuevo son exclusivos Windows. Apple mantiene flechas AppKit de cabecera (`HomeFeedCollectionView`) y paginación de `HomeFeaturedView`, sin halo/velo añadido a esas flechas; no hubo cambio de navegación Apple. Los gradientes de artwork/ambientación existentes cumplen otra función y se conservaron.
- [x] Preparar `PlayerBarLayoutTests.swift` con `NSHostingView` y componentes reales (`FeaturedTrackTitle` desplazable, `TrackArtistLinks`, badge y álbum); escenarios título/artista largos, acentos/emoji y slots de138/218/176/236 derivados de barras620/700/760/820. Comprueba ancho natural/clamp, distancia10 y huella60×46 sin overflow; la fila conserva altura ideal46 incluso dentro de una propuesta vertical100 (no absorbe el alto adicional de la cápsula). Las pruebas no han sido ejecutadas.
- [x] Revisar diff y `git diff --check` acotado (aprobado, sólo advertencias LF/CRLF). Se intentó `swift test --package-path apple`: PowerShell no reconoce `swift`; no hay ejecución Swift/AppKit ni build Mac.
- [ ] En Mac ejecutar layout/motion/suite Swift y QA visual real de620/700/760/820, títulos/metadata tardíos, cuenta invitada, dislike remoto, enlaces, teclado/VoiceOver y transiciones fullscreen. Los cálculos anteriores de espacio corresponden a FIX-264; ahora metadata recibe36pt menos por acciones60 en lugar24. No constituyen una medición nativa.

Integración cerrada en [FIX-265](../../FIXES.md#fix-265)/PAR-044. Windows build0024 Release compiled, verify1089pruebas aprobadas y hashes verificados; esas pruebas no validan Mac. Sin cambios propios del core/bindings ni build Apple en esta revisión.
