# PLAN-012: navegación con gestos y respuesta visual

- Objetivo: volver y avanzar con el trackpad de forma predecible y bajar Ahora suena mediante un gesto vertical que acompañe los dedos; mantener propiedad de scroll, cancelación, fluidez y lenguaje visual de Side B.
- Estado: FIX-129 afina Inicio tras confirmación del usuario: historial activo, pero FIX-128 tomaba también el scroll horizontal. Carruseles/filtros y contenido paginado ahora conservan la secuencia; títulos/huecos/paginadores responden al historial. Build-0061 firmada, 49 pruebas focales y 532 de la suite release aprobadas; comprobación física pendiente.
- Alcance: entrada, historial y presentación Apple. No cambia reproducción, red, proveedor ni core. Mouse y teclado conservan sus acciones. La propuesta visual en la conversación es una simulación local, no una modificación de la app.
- Referencias: [Apple: Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures?changes=_6), [NSEvent / swipe tracking](https://developer.apple.com/documentation/appkit/nsevent), [haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics); [FEAT-068](../../FIXES.md#feat-068) y [FIX-100](../../FIXES.md#fix-100).
- Fix de la política vigente: [FIX-129](../../FIXES.md#fix-129), sobre [FIX-128](../../FIXES.md#fix-128) (build-0060). Antecedentes: [FIX-125](../../FIXES.md#fix-125), [FIX-126](../../FIXES.md#fix-126), [FIX-127](../../FIXES.md#fix-127). [PAR-013](../../PARIDAD.md); fases/háptica AppKit propias de Apple.

## Base investigada antes de implementar

`NavigationInputCoordinator.swift` usa un monitor local de eventos por ventana. Exige deltas precisos y que el gesto esté habilitado en macOS. Decide el eje después de 8 puntos acumulados; si X no supera Y × 1,25 lo fija como vertical. Acumula desplazamiento horizontal al borde y navega al soltar si supera 55 puntos. No expone progreso ni estado visual y no produce feedback háptico.

El destacado paginado de Inicio declara `HorizontalNavigationGestureOwner` y conserva toda la secuencia. Otros `NSScrollView` horizontales pueden entregar primero desplazamiento al contenido y luego cambiar a historial al alcanzar el borde. Esta diferencia está comprobada en el código; su relación con cada fallo que percibe el usuario requiere capturar eventos reales. El momentum se deja pasar sin navegar, pero una secuencia ya consumida por historial necesita conservar su dueño hasta terminar para no desplazar accidentalmente el destino.

`NavigationRouter` conserva destinos e índice. No conserva nombres de álbum/playlist ni un estado general de presentación por visita. FEAT-068 describe un indicador y haptics históricos; ese indicador no está en las fuentes activas. No se infiere cuándo o por qué dejó de estar. Los tests activos de `HomeGestureRoutingTests` comprueban la región propietaria, no el ciclo completo de navegación física.

## Interacción recomendada

- Una cápsula de material nativo al borde izquierdo del área central para Atrás, derecho para Adelante; altura aproximada de 44 puntos, flecha de 14–16 y dos líneas breves. Aparece sólo durante el gesto, a media altura del contenido. Usa superficies y trazo de las cápsulas actuales y `AppTheme.accentHighlight` (#D06C70) al activarse.
- Durante el tirón: flecha neutra, una progresión discreta alrededor de su círculo, destino (“Lanzamientos”) y acción (“Volver”). Sin porcentaje en la app ni notificación permanente.
- Al armar: flecha/progreso en rojo suave y texto “Soltá para volver”. Un único pulso háptico de alineación por gesto cuando el dispositivo lo admita. El color se acompaña de texto; no es la única señal.
- Al soltar armado: una sola navegación y retirada breve de la cápsula. Antes del umbral: retorno suave sin tocar el historial. Invertir la dirección permite desarmar antes de soltar; usar histéresis para evitar alternar estados cerca del umbral.
- Sin destino: cápsula neutra breve con “No hay una página anterior/siguiente”, resistencia más corta, sin estado armado ni háptica de confirmación.
- Sidebar, controles de ventana, cápsula superior y reproductor quedan anclados. El contenido puede ceder como máximo unos 8 puntos mediante transformación de composición, sin relayout de colecciones. Si las trazas muestran un coste, mantener sólo movimiento del indicador. Transiciones iniciales orientativas de 140–180 ms al confirmar y 180–220 ms al cancelar, a calibrar en hardware.
- Reduce Motion elimina el desplazamiento del contenido y el resorte; Reduce Transparency usa superficie opaca legible. VoiceOver anuncia disponibilidad/destino al cambiar de estado, no cada delta. Botones, atajos y acciones de menú siguen siendo alternativas completas.

## Reglas de activación

1. Historial disponible en la ventana con excepción local de Inicio: viewport de carruseles, chips y contenido paginado de Speed Dial/colecciones. Fijar dueño y candidato al empezar, incluso sin deltas; mantener toda la secuencia y momentum al llegar al borde o salir de la región. Consultar sólo propietarios explícitos, sin veto genérico de scroll views o controles.
2. Títulos, headers, huecos, padding exterior y paginadores de Inicio conservan historial; player/sidebar/cabecera en foreground prevalecen sobre un carrusel inferior. Scroll vertical/diagonal, selección por mouse, scrubbing, clicks y teclado mantienen su flujo. Sheets/modales, menús, Spotlight y Ahora suena conservan guards; descenso vertical sigue protegiendo cola/listas/letras.
3. Esperar evidencia horizontal suficiente, con banda indecisa para diagonales; no clasificar un gesto ambiguo prematuramente. Normalizar dirección una vez y comprobar ambas configuraciones de desplazamiento natural.
4. Modelo explícito: reposo → detectando → tirando → armado → confirmando/cancelando; variante sin destino. Sólo un gesto físico nuevo inicia otra navegación. Cancelar por pérdida de foco, ventana desmontada, modal, cambio externo de ruta o sesión; limpiar indicador y candidato.
5. El motor propio utiliza fases/deltas precisos de trackpad sin depender de la preferencia externa de pasar páginas de macOS. No modificar ajustes del usuario. No convertir rueda sin fases ni momentum en contactos nuevos de navegación.
6. El candidato se fija por visita del historial: verificar que sigue siendo válido al soltar. Resolver nombres con metadata ya disponible, o fallback “Álbum”/“Playlist”; no consultar red durante el gesto. Cancelar conserva scroll, selección y foco. Auditar restauración al volver; si faltan snapshots, guardarlos por visita, con tamaño acotado, sin capturas de pantalla ni un segundo árbol de contenido.

## Implementación por etapas

- [x] Contrastar coordinador, router, propietarios horizontales, tests, tema y antecedentes con el código activo.
- [x] Observar cápsulas, sidebar, área central y reproductor en build-0048 aislada; crear propuesta interactiva con estados de tirón, activación, cancelación, sin destino y carrusel.
- [x] Capturar una traza acotada por gesto en una build diagnóstica: fases, momentum, eje, dueño, motivo de rechazo y candidato. Sin eventos continuos en producción, metadata privada ni cuenta registrada. Reproducir el fallo en Inicio, Lanzamientos y detalles.
- [x] Implementar modelo de estados y arbitraje por secuencia; comparar adapter AppKit nativo y acumulador existente. Crear pruebas significativas de fases, ambigüedad, reversión, cancelación, dirección natural y una sola navegación.
- [x] Integrar overlay único ligero al área de contenido y háptica opcional. Actualizaciones locales de progreso: no invalidar el shell/feed por delta, cargar portadas ni montar la página de destino antes de confirmar. Preservar controles/foco y disponibilidad superior.
- [x] Verificar identidad del candidato, títulos y restauración del historial; evitar navegación tardía a un candidato cambiado mientras el gesto está activo.
- [x] Ejecutar pruebas Apple completas y build numerada con la skill Mac. Registrar fix, límites, plan y evaluación de paridad cuando haya implementación.
- [ ] Ensayo físico y revisión visual en la misma build: aceptar el diseño sólo después de verificar uso real y trazas.

## Comprobaciones de cierre

- Atrás y adelante; inicio/final del historial; diagonal, tirón corto, reversión, cancelación y swipes rápidos repetidos. Exactamente una navegación por secuencia confirmada y ninguna por momentum.
- Inicio: carrusel en inicio/medio/final, chips y destacados reciben su scroll/paginación local; títulos/huecos y chrome conservan historial. Contacto cruzando límites mantiene su dueño y sólo otro contacto puede cambiarlo. Fuera de ventana no inicia navegación.
- Scroll natural activado/desactivado, preferencia de pasar páginas activada/desactivada, trackpad real y mouse disponible. No cambiar preferencias del usuario para probar sin autorización.
- Sidebar visible/oculta, resize, múltiples ventanas, sheet/Spotlight/menú/fullscreen, pérdida de foco, cambio de ruta/cuenta y desmontaje durante el gesto.
- Cancelar conserva la visita; volver restaura la posición acordada, selección y foco donde corresponda. Sin crecimiento no acotado de snapshots ni imágenes retenidas por el indicador.
- VoiceOver, teclado, Reduce Motion, Reduce Transparency y legibilidad de materiales. No depender exclusivamente de haptics o color.
- Instruments durante gestos repetidos en Inicio y Lanzamientos con miles de álbumes e imágenes ya cargadas. Overlay sin trabajo de red/layout por delta ni incremento del número de tarjetas montadas. Compilar o simular scroll en UI no certifica suavidad ni detección de fases de trackpad.

El orden prioriza detección y propiedad, luego apariencia y calibración: el indicador debe representar el estado que realmente decide la navegación.

## Extensión: bajar Ahora suena con dos dedos

Pedido del usuario tras aprobar la propuesta horizontal: tirar hacia abajo fuera de zonas desplazables, ver el fullscreen acompañar el movimiento en tiempo real y cerrar al soltar. Estado: implementado con FIX-125; FIX-127 amplía pruebas de cierre/cancelación y geometría, ensayo físico pendiente. Se refiere al overlay Ahora suena de Side B, no a salir del modo de pantalla completa de la ventana de macOS.

### Base comprobada

`FullscreenCanvas` presenta el foreground por condición de `isFullscreenPresented`, con transición desde abajo. `WindowRootView` mantiene el backdrop aparte y las páginas montadas con opacidad cero/hit testing deshabilitado durante Ahora suena. Sidebar y player son capas superiores independientes. La cola usa `NativeTrackTableView`; letras, Genius, información de carátula y recomendaciones contienen zonas de scroll. No existe progreso vertical interactivo en esas capas.

No basta con poner un `DragGesture` sobre toda la pantalla: no representa por sí solo el scroll de dos dedos del trackpad y competiría con listas y controles. El input vertical debe integrar las fases de `NSEvent.scrollWheel`, deltas precisos y momentum, con un dueño fijado al inicio. Referencias: [Apple: phase](https://developer.apple.com/documentation/appkit/nsevent/phase-swift.property) y [momentumPhase](https://developer.apple.com/documentation/appkit/nsevent/momentumphase); [FIX-094](../../FIXES.md#fix-094) y [FIX-095](../../FIXES.md#fix-095) explican por qué fondo, shell y foreground fueron separados.

### Comportamiento

- Sobre carátula frontal, fondo o espacios libres elegibles: un desplazamiento deliberadamente vertical hacia abajo empieza a bajar la superficie de Ahora suena. Usar la dirección física normalizada, sin invertir el resultado cuando cambia el ajuste de scroll natural.
- Durante el contacto, actualizar desplazamiento con los deltas nativos, sin interpolación ni resorte que persiga cada evento. Es seguimiento directo del gesto percibido; el sistema puede aplicar aceleración, por lo que no se afirma una correspondencia milimétrica con el recorrido físico de los dedos ni FPS sin medir.
- Al tirar, revelar la misma página que estaba debajo; no navegar, reiniciar tareas, cargar una copia ni alterar su scroll. Mantener bloqueada su interacción hasta terminar el cierre.
- Un tirón corto vuelve exactamente a reposo con resorte breve al soltar. Uno suficiente completa la salida desde su posición actual. Retirar los dedos no debe provocar un salto ni sumar dos transiciones (offset interactivo + transición de desmontaje).
- Umbral inicial orientativo de 22–25 % del alto útil, acotado a unos 100–160 puntos y con histéresis. Calibrar con trackpad físico; evitar cerrar con un pequeño impulso inicial. Una terminación rápida puede considerarse después de validar distancia mínima y velocidad reciente de contacto, nunca usar el momentum como nueva orden de cierre.
- Mostrar sólo una señal pequeña durante el tirón: chevron hacia abajo y “Soltá para cerrar” al armar, con el mismo acento/háptica opcional del horizontal. La pantalla moviéndose aporta la respuesta principal. Sidebar, player y controles de ventana permanecen anclados; la reproducción continúa.
- Un gesto iniciado sobre cola, lista/playlist desplazable, letras, Genius, información de carátula o recomendaciones pertenece a esa región hasta terminar, esté al principio, al final o temporalmente sin overflow. No transferir al cierre al llegar al borde ni cuando el puntero sale de ella. Sliders, selección, botones y reorder mantienen sus interacciones.
- Mantener Escape y el botón actual de minimizar Ahora suena. Cancelar si se abre un modal/Spotlight, cambia la ventana/foco, hay resize incompatible, cambia la sesión o se cierra externamente el overlay. Cambiar de canción durante el tirón conserva la misma superficie y no remonta el gesto.
- Reduce Motion elimina la gran traslación y ofrece confirmación visual discreta; las alternativas de teclado/botón permanecen disponibles. No depender de color o haptics para saber cuándo se activa.

### Integración y coste

Complejidad media: seguir el movimiento es una transformación; la parte delicada es el arbitraje de scroll y el cierre desde una posición intermedia. No requiere red ni cambios del core. Reutilizar el motor de fases/propiedad/cancelación del plan horizontal, con acciones distintas: historial sólo fuera de Ahora suena, descenso sólo dentro. La preferencia de macOS de pasar páginas pertenece al gesto de historial; no reutilizar automáticamente ese guard para bloquear el cierre vertical propio del overlay.

Añadir estado de presentación por ventana (`reposo`, `tirando`, `armado`, `cerrando`, `retornando`) acotado al host visual, sin escribir un offset continuo en `PlayerViewModel`. Mantener `isFullscreenPresented` hasta que se confirma y termina la salida; conservar panel y scroll al cancelar. Transformar foreground y fondo de forma coordinada, preservando una sola imagen/blur persistente y el orden páginas → fullscreen → sidebar → player → Spotlight. Verificar mezcla detrás de sidebar y primer/último frame contra FIX-095; no agrupar de nuevo las capas a ciegas ni recalcular el blur por delta.

- [x] Revisar capas, visibilidad de la página inferior, cola y paneles desplazables; preparar propuesta interactiva del descenso.
- [x] Extender captura de fases y ownership a input vertical, incluido inicio sin `.began`, cambio de puntero, reversión y momentum; comprobar dirección física con scroll natural en ambas configuraciones.
- [x] Implementar progreso/settlement en un host aislado, con seguimiento directo durante el contacto y animación sólo al resolver; revelar la página existente sin desbloquearla durante el tirón.
- [x] Integrar exclusiones semánticas de regiones desplazables y controles. Probar cola/letras/recomendaciones/carátula volteada en ambos extremos sin una sola transferencia accidental al cierre.
- [x] Verificar cancelación, cierre único, posición/panel al volver a abrir, reproducción continua, Escape/botón y sesión/ventana/resize. Cero navigaciones de historial durante Ahora suena o durante su animación de salida.
- [ ] Medir compositor/main/blur en la misma build durante tirones repetidos; revisar primer frame, salida desde offset intermedio y backdrop detrás de sidebar. No certificar seguimiento perfecto ni Hz a partir del prototipo de conversación.
- [x] Cerrar con pruebas/build/fix y evaluación de PARIDAD; implementación y comprobación física pendientes.

## Seguimiento del bloqueo reportado — 2026-10-06

[FIX-127](../../FIXES.md#fix-127) conserva FIX-125/126 y verifica el adaptador con candidatos reales y la composición de regiones. En copia release HomeLab de 0058, Biblioteca admite historial en los puntos centrales muestreados; Inicio protege paneles paginados/carruseles. Sidebar/player tienen límites correctos. Ahora suena admite descenso sobre portada y protege el panel derecho. Los botones de historial y apertura/cierre se comprobaron por UI.

- [x] Probar adaptador real: captura, candidatos, commit/momentum, ruta/sesión/modal y completion fullscreen.
- [x] Probar tabla/player/canvas SwiftUI-AppKit y muestrear la ventana completa aislada.
- [x] Conservar build-0059 con runner completo, 526 pruebas y fuente estable.
- [ ] Reproducir el bloqueo con trackpad físico y localizar página/zona, distinguiendo scroll horizontal propio de un rechazo incorrecto.
- [ ] Ajustar arbitraje si la captura demuestra un rechazo incorrecto; calibrar respuesta y medir fluidez en la misma build.

El diagnóstico requiere una copia HomeLab y la clave SideBGestureDiagnostics de su bundle. Guarda geometría/flags al estabilizar el shell, sin datos privados ni eventos continuos de producción. No sustituye una captura de fases de contacto ni demuestra seguimiento físico.

La prueba del bridge real con una ruta observada por una vista hija reprodujo una cápsula horizontal retenida tras navegar. FIX-127 hace incondicional la lectura de historial/índice en setup; la cancelación ahora pasa para historial y fullscreen. El muestreo de 0059 confirma actualización también en reposo al navegar Inicio→Biblioteca→Explorar. Esta corrección no cierra la reproducción física del bloqueo general comunicado.

## Política global solicitada — 2026-10-06

El usuario confirmó que 0059 mantiene el fallo en la mayoría de la UI y pidió activación agresiva en todos los ítems, dejando las excepciones para después. [FIX-128](../../FIXES.md#fix-128) elimina ambos vetos de ownership/exclusión del historial y su dependencia de la preferencia externa del sistema. El adaptador captura únicamente elegibilidad de ventana y candidato; sólo fullscreen necesita inspeccionar paneles.

- [x] Sustituir veto por ítem por elegibilidad del viewport completo; mantener guards de modo/foco/modal y fases precisas.
- [x] Ampliar pruebas del contexto real y ambos destinos sobre grilla de shell, controles y carruseles; proteger scroll vertical y descenso fullscreen.
- [x] Ejecutar pruebas focales (44, incluidas 43 de gestos) y runner completo (528); conservar build-0060 firmada con fuente estable.
- [ ] Confirmar con trackpad físico que el gesto responde en las superficies reportadas; calibrar distancia/diagonales y medir fluidez.

En FIX-128 el desplazamiento horizontal de carruseles cedió prioridad al historial por este pedido. El usuario confirmó la activación en Inicio; FIX-129 recupera allí la propiedad local descrita a continuación. Fuera de Inicio se conserva la política global.

Build-0060: grilla de 408 puntos del shell a tres anchos, ida/vuelta por punto; controles y carrusel nativo con el contexto del adaptador real. En la ventana HomeLab aislada, Inicio/Biblioteca admiten 16/16 puntos muestreados aunque sean excluidos/owners horizontales; botones de historial y scroll vertical de Inicio comprobados por UI. Estos resultados verifican la política global y su integración, sin sustituir el ensayo físico pendiente. Evidencia/build en FIX-128.

## Prioridad local de Inicio aprobada — 2026-10-06

El usuario confirmó activación de historial en Inicio con 0060 y pidió recuperar su scroll horizontal antes de continuar con otros menús. [FIX-129](../../FIXES.md#fix-129) acota la excepción a chips, viewport de cada estante y contenido de los dos paneles paginados. La reserva no se extiende a toda la sección; footer/títulos/huecos permiten historial. Todo el contacto conserva su dueño, también al borde.

- [x] Capturar sólo propietarios explícitos en Inicio y preservar arbitraje de ventana/modo.
- [x] Acotar overlays paginados al contenido y declarar owner en scroll nativo de cada carrusel.
- [x] Probar área de tarjetas vs header/footer, tres anchos, extremos y ausencia de overflow, captura inicial/puntero/momentum y coexistencia con historial.
- [x] Completar runner (532 pruebas) y conservar build-0061 firmada con fuente estable; comprobar botones de paginación, scroll vertical, navegación de regreso y geometría de regiones en copia aislada.
- [ ] Confirmar sensación y fases de trackpad real, dirección natural y fluidez en la misma build.

La copia HomeLab reserva seis puntos de Inicio para contenido horizontal y conserva diez para historial; Biblioteca conserva dieciséis de dieciséis. Las pruebas del adaptador verifican que el contacto completo pase a los controles locales y que no se transfiera al historial. La automatización horizontal no cambió páginas/ítems visibles, por lo que el deslizamiento físico permanece pendiente. Evidencia y límites completos en FIX-129.
