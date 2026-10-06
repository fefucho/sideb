# PLAN-013: investigar fullscreen y sidebar con Inicio de fondo

- Fecha: 2026-10-05 (America/Montevideo).
- Estado: regresión de geometría corregida con FIX-123 en build-0052; 485 pruebas del runner y 10 pruebas Node aprobadas. Caso de entrada con sidebar cerrado y cuatro alternancias comprobados visualmente en release aislada. FIX-124 explicita ejecución serial de Swift Testing; FPS con sesión/audio reales sin certificar.
- Objetivo: explicar el lag reportado al abrir/cerrar sidebar en Ahora suena con Inicio debajo, comparado con Biblioteca, y distinguir evidencia de hipótesis.
- Ámbito: análisis y corrección Apple autorizada después del diagnóstico; fondo/feed, pruebas y build numerada. Comprobaciones reales en copia HomeLab aislada. Core/Windows, datos de la app instalada, preferencias del sistema, commit/push/publicación excluidos.
- Referencias: FIX-095, FIX-098/099/100, FIX-108/109, FIX-119; PLAN-003/005/008; PAR-003/006/008.

## Regresión reportada después de build-0050 — FIX-123

- [x] Revisar captura del usuario y contrastar tamaño retenido del feed con el contrato de layout del shell.
- [x] Reproducir en prueba SwiftUI del shell con Inicio real, fullscreen y reserva de sidebar; 18 fallos de geometría antes del cambio. App 0050 reproduce sidebar truncado al partir cerrado.
- [x] Corregir el contrato externo sin reactivar fondo/layout ocultos: GeometryReader en HomeView acepta el tamaño disponible y contiene el ancho retenido del feed.
- [x] Verificar anchuras/origen del shell y sidebar, inversión, resize y retorno; 15 XCTest/2 Swift Testing focales aprobadas. Suite release completa serial: 68 XCTest/235 Swift Testing aprobadas.
- [x] Build numerada 0052 con runner que explicita `--no-parallel` (FIX-124); 485 pruebas aprobadas y 10 Node del runner. Intentos concurrentes/build-0051 fallidos por esperas del mock de playlists, conservados.
- [x] Comprobar visualmente apertura/cierre partiendo de sidebar cerrado en copia aislada release: panel completo, contenido/cola/player dentro de ventana; cuatro alternancias adicionales conservaron la geometría.

La lectura AX de presencia/ausencia de Inicio en FIX-122 no prueba los bordes del shell. Su prueba de viewport aislado tampoco incluía la reserva lateral del HStack; se agrega esa cobertura en este cierre.

El fixture de geometría final carga dos paneles destacados y un estante sin imágenes/continuación, con caché/preferencias aisladas. La prueba reproduce el contrato de HomeView real sin dejar trabajo de imágenes ajeno a su objetivo. Los timeouts de playlists persistieron tras ese ajuste y desaparecieron al ejecutar toda la suite release en serie; FIX-124 registra esa política de verificación, sin cambiar reproducción/aserciones.

Resultado de app: copia de 0050 reprodujo el mismo recorte del usuario; copia de 0052 con la misma ventana/fixture y Song 2 seleccionada sin audio corrigió la secuencia Inicio/sidebar cerrado → fullscreen → abrir sidebar. Capturas revisadas después de la apertura y cuatro alternancias: panel completo y cola/duración dentro del borde derecho. Artefacto normal `builds/macos/build-0052/Side B.app`; `compiled`, fuente estable durante runner, firma ad hoc verificada. Protocolo/logs en `builds/macos/build-0052/fullscreen-sidebar-regression/`. Registros de FIX-122 conservados como históricos, sin reutilizar su cifra de ahorro CPU para afirmar FPS o validar geometría.

Retorno de 0052: Inicio mostró recomendaciones, álbumes 700/701, página 1/6 y scroll AX 0 con sidebar expandido. Las pruebas nativas cubren además offset no nulo e identidad. Captura Time Profiler de 12 s con Song 2 seleccionada/pausada y cola visible, sin entrada/AX durante la grabación: 2146 muestras Running del hilo principal (2146 ms), cero muestras inclusivas de HomeAmbientSurface/HomeAmbientMotionClock/HomeFeatured y cero backtraces ausentes. Apoya conservación de la pausa oculta, sin afirmar costo total cero; la cola/pista seleccionada difieren del reposo de FIX-122, por lo que no se comparan sus CPU. No mide frames/GPU. Copias diagnósticas cerradas y apps normales 0048/0050 preservadas.

## Investigación

- [x] Revisar el shell, el fondo de Inicio, el feed nativo, Biblioteca y la animación compartida.
- [x] Comparar los commits recientes y los antecedentes de rendimiento.
- [x] Leer la UI de la app existente antes/después de una muestra de cinco segundos, sin acciones de entrada.
- [x] Caracterizar si el feed oculto sigue midiendo destacados al cambiar el viewport; no crear NSWindow.
- [x] Guardar conclusiones, límites y propuesta de corrección con orden de verificación.

## Verificación de la corrección

- [x] Medir antes/después en release con igual fixture/ventana/panel/sidebar; HomeLab sin pista/audio, con Inicio debajo.
- [x] Conservar superficie/fase, estado de Inicio, scroll, tarjetas y geometría al volver; pruebas de identidad/reloj y comprobación de app.
- [x] Ejecutar pruebas apropiadas y build numerada; registrar FIX y evaluación de paridad.

Ampliaciones de medición si persiste el síntoma: Biblioteca y sesión/pista reales, Core Animation/Animation Hitches y GPU; variantes separadas de fondo/layout para atribuir su contribución. El A/B conjunto cierra la verificación del trabajo oculto corregido, sin certificar FPS.

La investigación inicial no constituye un fix ni demuestra FPS. La implementación autorizada posteriormente se registra en FIX-122 y en la sección final; no se cierra paridad sin evidencia del destino.

## Resultado y evidencia

La explicación más probable es trabajo de Inicio que permanece activo bajo Ahora suena, sumado al costo de fullscreen/sidebar. Hay dos caminos concretos comprobados; falta un A/B de rendimiento que determine cuánto aporta cada uno al síntoma.

| Hallazgo | Evidencia | Alcance de la conclusión |
|---|---|---|
| El fondo de Inicio se evalúa aunque fullscreen lo tape | `SideBApp.swift:443–447` monta `HomeAmbientBackground` cuando la página es `.home`, sin condición de fullscreen. `HomeAmbientSurface.swift:18–20` agenda movimiento con intervalo mínimo de 1/30 s y sólo pausa por Reduce Motion o escena inactiva. Muestra del proceso de build-0048, con fullscreen visible antes/después y sin acciones de entrada, contiene `HomeAmbientSurface.surface(time:)` y `smokeLayer` | La evaluación real del fondo en este escenario está comprobada. No demuestra que la GPU dibuje todas las capas tapadas ni atribuye porcentajes de CPU/GPU al fondo |
| La página oculta recibe los cambios de ancho del sidebar | `SideBApp.swift:237–241` mantiene la reserva de sidebar en el HStack de páginas; `:347` oculta el contenido por opacidad. `HomeView.swift:25–28` conserva observación geométrica. `HomeFeedTableView.swift:182–193`, `:273–295`, `:404–418` siguen actualizando destacados/alturas sin guardia de `isObscured` | La bandera oculta el NSScrollView y controla hover/indicadores de estantes; no suspende los callbacks de geometría |
| La caracterización nativa confirma medidas con el scroll oculto | Test temporal con `isObscured: true`, cambios reales de frame/bounds y `layoutSubtreeIfNeeded`, sin llamada manual a `boundsChanged`, sin ventana: 10 anchos de 1100 a 640, 17 llamadas a la función de altura; un `updateNativeScrollView` posterior añade una medida | Comprueba ejecución en el camino oculto, incluida actualización del ancho observable. Es una caracterización del control; no mide el gesto real del sidebar, el contenido completo de la sesión ni FPS |
| Biblioteca evita esos costos específicos | `LibraryView.swift` no incorpora `HomeAmbientSurface`, destacados de Inicio ni `setFeaturedCapacity`. El shell usa `Color.sidebDarkBackground` fuera de Inicio. La tabla/grilla de Biblioteca puede seguir haciendo layout bajo fullscreen | Explica una diferencia concreta entre destinos; no afirma que Biblioteca tenga costo cero ni que toda biblioteca sea siempre más rápida |
| La duración configurada es común | `NavPresentation.swift:28–29`: `.smooth(duration: 0.42, extraBounce: 0)` para ambos destinos; Reduce Motion usa 0.12 s | No aparece una duración más larga específica de Inicio. La diferencia percibida es compatible con trabajo extra/pérdida de fluidez; falta medir los frames |

### Relación con las versiones recientes

- El shell que conserva páginas ocultas y el canvas/backdrop de fullscreen ya está en `e3e7b28` (2026-10-03, FIX-091–095). `FullscreenBackdrop.swift` y `FullscreenSceneLayout.swift` no cambian entre ese commit y HEAD.
- Inicio personalizado/destacados incorpora trabajo adaptativo de layout en `5cf08ef` (2026-10-03, FIX-098–100).
- `ca039d6` (2026-10-04) añade `HomeAmbientSurface` con humo/movimiento de FIX-108/109. FIX-109 ya declara consumo sin medir y posible costo de composición por `.screen`. Son tres radiales y dos capas de humo con máscaras, escaladas 1.5 y 1.75 y actualizadas continuamente; la máscara se prepara una sola vez fuera del hilo UI. No hay evidencia de que se regenere el ruido procedural a cada frame.
- `62a3eb8` (2026-10-05, FIX-119) conserva identidad de destacados y evita recargar estantes idénticos al cambiar columnas. Mejora un problema real de Inicio visible; no incorpora suspensión del layout oculto ni pausa del fondo al entrar en fullscreen. No se atribuye una regresión a FIX-119.
- `c59acce` (HEAD al investigar) agrega Explorar. El diff desde `62a3eb8` no cambia `HomeAmbientSurface` ni `HomeFeedTableView`, y los cambios del shell corresponden a la nueva navegación de Explorar. No hay evidencia que responsabilice al agregado de Explorar del síntoma con Inicio.

Los cambios de capacidad 2/4/6 pueden llamar a `HomeViewModel.rebuildProjection` cuando se cruza un umbral de columnas: vuelve a ordenar/proyectar el feed y publicar datos. Es un costo adicional posible durante resize; el guard de capacidad evita ejecutarlo para cada ancho intermedio. No se midió este costo por separado.

### Comprobaciones de esta investigación

- App existente: `builds/macos/build-0048/Side B.app`, release, versión 1.1.6 (10), PID 70437; proceso consultado por ruta. macOS 27.0 según encabezado de la muestra.
- Lectura AX antes y después confirmó Ahora suena visible, con control «Cerrar pantalla completa», y árbol sin cambios. No se hizo clic, navegación, reproducción ni modificación de preferencias. No se almacena el árbol AX con datos de la cuenta.
- `sample 70437 5 1 -file /tmp/sideb-fullscreen-home-20261005.sample.txt`: muestra nueva del 2026-10-05 19:00:49 −0300. Hay cuatro entradas de stack que contienen `HomeAmbientSurface.surface(time:)` y una de `smokeLayer`; son entradas del árbol agregado, **no cantidad de frames, invocaciones ni porcentaje de CPU**. No aparecen símbolos de HomeFeatured/HomeFeed en esta muestra sin interacción; no se usa para atribuir layout de sidebar.
- `swift test --package-path apple --filter FullscreenHiddenHomeDiagnosticsTests`: una prueba XCTest aprobada, cero fallos, 0.115 s; compilación del runner 37.42 s, con advertencias anteriores del proyecto. No se corrió la suite completa ni se empaquetó una app nueva, porque no se implementa un fix.
- Diagnóstico emitido: `hidden=true widths=[1100, 1040, 980, 920, 899, 850, 820, 760, 700, 640] featuredHeightMeasurements=17 representableUpdateMeasurements=1 window=nil`.
- El test temporal se retiró de `apple/Tests` tras caracterizar. Copia de su fuente, resultado y muestra guardados en `builds/macos/build-0048/fullscreen-home-analysis/`. Las fuentes de producción y las pruebas permanentes quedan intactas.

### Corrección propuesta en el diagnóstico inicial

1. Pasar visibilidad explícita al fondo de Inicio y pausar su Timeline cuando fullscreen lo cubre. Mantener superficie/paleta e identidad para conservar el fundido y el retorno a Inicio. Reanudar con continuidad; comprobar que la fecha absoluta del Timeline no produzca salto visible al volver.
2. Suspender medidas/publicaciones/rebind del feed oculto; conservar el último viewport y el estado de scroll/páginas. Retener el snapshot más reciente y aplicar ancho/alturas pendientes antes de que Inicio reaparezca. Evitar desmontar todo Inicio o descartar cambios de sesión/cuenta.
3. Comprobar por separado los callbacks de `onGeometryChange`, `onViewportLayout`, bounds y actualizaciones de NSViewRepresentable. Un guard solamente en `updateNativeScrollView` no cubre los otros caminos; suspender `updateFeatured` solamente tampoco elimina la proyección desde `HomeView`.
4. Medir A/B en release con igual pista/panel/tamaño/estado de reproducción: Inicio actual, fondo pausado, layout suspendido y ambas cosas; Biblioteca como comparación. Capturar reposo y aperturas/cierres repetidos, incluyendo invertir el gesto y cruzar 760/900 puntos/columnas. Time Profiler + Core Animation/Animation Hitches para atribuir CPU y frames; GPU/compositor si persiste el costo.

No se propone cambiar el aspecto o los 30 fps del fondo visible sin medirlo. El trabajo oculto es la primera intervención para este escenario; optimizar el fondo cuando Inicio sí está visible pertenece también a PLAN-008 etapa 4.

### Paridad y límites

Revisión estática de `windows/src/lib/components/home/HomeView.svelte` y `windows/src/routes/+page.svelte`: Inicio Windows usa fondo CSS estático y fullscreen deja montado el contenido (`.fullscreen-open .content-column` cambia overflow). No contiene este Timeline/humo SwiftUI ni los callbacks de destacados AppKit, por lo que los dos caminos encontrados son específicos de Apple. La regla de suspender trabajo tapado es transferible cuando se porte el fondo/destacados (PAR-003/006) y se conserve el shell (PAR-008); no se cambia Windows ni se declara su runtime verificado.

Pendiente: A/B cuantitativo y validación del sidebar en movimiento. La muestra breve demuestra actividad oculta pero no puede asignar todo el lag al humo, certificar FPS ni demostrar qué parte del trabajo evita el compositor. La caracterización nativa no sustituye una traza del gesto real con datos de la sesión.

## Implementación autorizada — FIX-122

- [x] Pausar Timeline por fullscreen y conservar su fase con HomeAmbientMotionClock.
- [x] Congelar el tamaño del NSScrollView oculto y suspender callbacks de medidas/hover/playback/acciones nativas.
- [x] Mantener snapshot aplicado consistente con la tabla; diferir las actualizaciones y aplicar el último snapshot al revelar.
- [x] Registrar capacidad pendiente de HomeView sin reproyectar el feed oculto; aplicarla al volver.
- [x] Regresiones de viewport SwiftUI real y callbacks nativos, snapshot/hosting/offset conservados y reloj continuo: 2 XCTest + 2 Swift Testing aprobadas. Focal combinada 11 XCTest/2 Swift Testing; suite debug completa 67 XCTest/235 Swift Testing aprobadas.
- [x] Build release numerada y comparación en copia aislada de la app.

La implementación conserva el humo/30 fps de Inicio visible y la duración de sidebar. No desmonta Inicio, no cambia el backdrop de fullscreen ni modifica fuentes del core/Windows. Referencia: [FIX-122](../../FIXES.md#fix-122).

Primer runner release: build-0049 falló en dos esperas `pending[key]` de 2 s de PlaylistPlaybackLatencyTests; 182 Rust/67 XCTest y las regresiones nuevas aprobadas. Focal release posterior aprobó ambos tests previos en 0.098 s y las cuatro regresiones nuevas sin cambios de fixtures/reproducción. El runner completo repetido aprobó en build-0050: 182 Rust (7 live ignoradas), 67 XCTest y 235 Swift Testing, 484 pruebas. Se conservan ambos logs; no se atribuye la causa del fallo a la UI.

### Comprobación release y trazas antes/después

`builds/macos/build-0050/Side B.app` es el artefacto entregable, release arm64 firmado ad hoc, SDK 27.0/mínimo macOS 15.0. BUILD.json indica `compiled`, `sourceChangedDuringBuild: false`; bindings regenerados sin diff. Se mantuvo versión 1.1.6 (10).

Se copiaron 0048/0050 a bundles de diagnóstico firmados con ID `com.fefucho.SideB.HomeLabFixture`, datos/preferencias aislados de la app normal. Mismo fixture invitado y carátulas PNG locales deterministas, ventana conservada, panel Cola sin pista/audio. Sólo las copias recibieron clics; la app original de 0048 (PID 70437) permanece ejecutándose.

Time Profiler en el mismo Mac: 12 s de reposo por versión y 30 s con 16 alternancias reales de sidebar por versión. La lectura AX después de cada clic confirmó fullscreen visible e Inicio ausente del árbol. Los bucles de acciones/AX duraron aproximadamente 19 s antes y 14 s después; se compara la misma cantidad de acciones y ventana de captura, no la duración de animación inferida de esas lecturas. Una pareja; orden 0048 → 0050. Hay actividad externa del exportador/copia durante reposo y overhead de AX en los gestos; no se usa esta medición para afirmar FPS.

| Tiempo CPU muestreado del hilo principal Running | 0048 | 0050 |
|---|---:|---:|
| Reposo 12 s, todos los stacks | 2918 ms | 4 ms |
| Reposo, excluyendo stacks AX/accesibilidad | 2896 ms | 4 ms |
| Sidebar 30 s/16 clics, todos los stacks | 16079 ms | 11364 ms |
| Sidebar, excluyendo stacks AX/accesibilidad | 11723 ms | 8822 ms |
| Sidebar, stacks inclusivos HomeAmbientSurface/reloj sin AX | 33 ms | 0 ms |
| Sidebar, stacks inclusivos HomeFeatured sin AX | 210 ms | 0 ms |
| Sidebar, stacks inclusivos HomeFeedTableView/ScrollView sin AX | 198 ms | 65 ms |

El hilo principal sin stacks AX muestra aproximadamente 25% menos CPU muestreada durante sidebar en esta pareja. La desaparición de HomeAmbientSurface y HomeFeatured apoya la suspensión del trabajo oculto. El feed aún recibe actualizaciones ligeras del representable; no se afirma costo cero del shell ni del framework. Las categorías inclusivas se solapan: **no sumarlas ni atribuir todo el ahorro al cuerpo del fondo**. No hay medición de frames/GPU ni desglose de variantes independientes.

Retorno de Inicio: después de cerrar sidebar bajo fullscreen aparecen cuatro álbumes (700–703), con feed visible y presentación correcta. En una segunda comprobación, página Álbumes 2/6 (702–703) y scroll AX `0.1583166332665331` se conservaron exactamente después de abrir fullscreen y expandir/contraer sidebar. Captura de retorno revisada: mismas tarjetas y estantes, sin viewport vacío. Las pruebas nativas también confirman hosting/offset y snapshot más reciente. La primera comprobación agrupada adicional se descartó: la copia terminó por la ruta normal aprobada de AppKit, sin reporte de crash; se relanzó y se verificó cada acción explícitamente con éxito. No se adjudica esa ejecución descartada al fix ni se usa como evidencia de conservación.

Trazas, XML, parser `summarize_profiles.py`, resumen `profile-summary.json` y protocolo en `builds/macos/build-0050/fullscreen-home-performance/`. Las copias de diagnóstico se cerraron al terminar; no se instaló ni reemplazó la app normal. Documentación finalizada después del runner, sin cambios posteriores de código de producción.
