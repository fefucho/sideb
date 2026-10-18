# PLAN-009: volumen con rueda y feedback en fullscreen

## Investigación local del reporte en 1.2.3 — 2026-10-18

- Estado: causa reproducida y corregida en FIX-213; build local0014 compiled/764pruebas/fuentes estables/cuatro hashes válidos; aceptación con dispositivo y audio pendiente.
- [x] Comprobar proceso instalado: `AppData/Local/Side B/sideb-windows.exe`, versión de archivo/producto 1.2.3; WebView2 155.0.4283.62.
- [x] Prueba con entrada inyectada mediante Computer Use en la app instalada, pausada: se observa50→42 tras probar barra y portada, sin traza que atribuya esa primera bajada a una zona concreta. Las pruebas siguientes muestran feedback42 sin cambio. La interpretación inicial de que la portada funcionaba queda reemplazada por las capturas y la reproducción de Chromium; no acredita dispositivo ni audio audible.
- [x] Reabrir el mismo ejecutable normalmente con el observador local schema2 para capturar entrada del dispositivo y órdenes/ACK sin datos de cuenta/canciones. Diagnóstico y capturas en `temp/windows/volume-investigation/`, fuera de Git.
- [x] Analizar captura propia schema2: dos eventos inyectados confiables de833,33px, verticales, cancelables, foco activo y sin bloqueo; consumidos, feedback42, cero órdenes IPC. Sonda acotada del handler confirma delta−8. La primera ventana de captura del dispositivo del usuario terminó sin eventos; no se clasifica hardware.
- [x] Reproducir causa en Edge/Chromium real: los temporizadores nativos lanzan `TypeError: Illegal invocation` al invocarlos como métodos del objeto clock. `input()` activa feedback antes del error; el adaptador no alcanza `adjust`. Un ensayo con política/adaptador/controller originales y RPC simulado produce cero órdenes/50fijo en portada y barra; tras vincular los timers a `globalThis` produce47→48→45→46 sin errores y retira feedback. No requiere cambiar umbrales ni controller/core.
- [x] Agregar regresión que falla antes del cambio por receptor incorrecto y pasa después:18focales aprobadas, incluida renovación/ACK/expiración/cancelación. Comprobar suite global/check/build y registrar FIX-213/PAR-032.
- [x] Completar build local numerada: `builds/windows/build-0014/sideb-windows.exe`, release compiled/sourceChangedDuringBuild=false, cuatro hashes válidos. Verify764pruebas (385frontend/97InnerTube/91core/93bridge/5player/93Tauri;14Rust ignoradas), check0/0. Build-0013 fallida conservada; biblioteca V8 recuperada desde GZIP original con CRC/1796miembros válidos y copia dañada fuera de Git. Sin fuentes core modificadas ni comprobaciones omitidas. Versión pública1.2.3 conservada; instalación/release sin reemplazar.
- [ ] Probar dispositivo del usuario/audio con la build corregida. La herramienta de UI dejó de poder activar la ventana; tras recuperar selección falló de nuevo (`failed to activate captured window`), por lo que se detuvo la automatización nativa. Cerrar/reabrir normalmente la app instalada retira su puerto temporal de diagnóstico.
- Una sonda adicional del controller no terminó: dejó de responder el canal CDP y se interrumpieron sus procesos de inspección. Sin resultado guardado, no se usa como evidencia causal. La causa del receptor de timers se demuestra por separado en Chromium, con código original/corregido y RPC simulado.
- Verificación del entorno: dependencia `happy-dom` inicialmente ausente tras sincronizar Git; resuelta con `pnpm install --frozen-lockfile`, sin modificar manifests/lockfile. No era evidencia del fallo de volumen.

## Arranque y comprobación del EXE entregado — FIX-214

- [x] Reproducir el cierre de0014 con la instancia instalada del diagnóstico aún viva: Application Error1000/0xc0000409; stderr del EXE confirma panic Tauri creando WebView2, HRESULT0x8007139F. No era una prueba del frontend/volumen.
- [x] Cerrar normalmente el PID27572 anterior con Computer Use, sin borrar perfil ni datos; comprobar proceso retirado y puerto62960 cerrado. La herramienta vuelve a poder seleccionar/activar la ventana en este turno.
- [x] Abrir el binario exacto0014 y verificar ruta por PID26816, ventana visible y estabilidad. El lanzador de UI abrió inicialmente la instalación anterior pese a la ruta solicitada; se cerró normalmente y esa apertura no cuenta como validación de0014. La apertura explícita posterior se verificó contra el proceso real.
- [x] Probar wheel inyectado sobre portada42→34→42 y barra abierta42→34→42, con confirmación visible/range y desaparición del porcentaje. Reproducción pausada, volumen42 restaurado y0014 dejada abierta. Cuatro hashes originales conservados; sin recompilar ni editar fuentes.
- [x] El usuario confirma «ahora sí anda» tras probar0014 y solicita subirla. Funcionamiento de scroll aceptado por reporte del usuario; sin inventar tipo de dispositivo ni medición de audio. Publicación seguida en [release1.2.4](../../plans/RELEASE-1.2.4.md)/FIX-215.
- Corrección del entorno registrada en [FIX-214](../../FIXES.md#fix-214). No requiere port Apple ni implementa una política general de múltiples instancias.

## Entrega anterior y alcance conservado

- Fecha: 2026-10-17 (America/Montevideo).
- Estado: **FIX-211 publicado en1.2.3/build16**: captura Windows reproduce cancelación por muestras laterales; corregida y verificada con replay de portada/barra. CI Windows764pruebas/385frontend/check0/0 aprobado; instalador/portable/checksums y frontend del EXE público verificados. Prueba física del nuevo EXE pendiente;1.2.2 conserva el fallo. FIX-207 cubre otra pérdida de remanente y se conserva.
- Objetivo: ajustar el volumen en pasos finos desde la cápsula de volumen abierta, el frente de la portada grande de Ahora suena; mostrar temporalmente el porcentaje sobre la portada oscurecida.
- Relación: complemento Windows de [PLAN-021 Apple](../../apple/plans/PLAN-021-volume-scroll-feedback.md). Comparten intención y presentación, con adaptadores de entrada y audio propios.
- Alcance: Svelte/TypeScript, arbitraje WebView2, controller de reproducción, integración Tauri/libmpv y pruebas/localización ES/EN. Core protegido, volumen del sistema, cambios de curva, nuevas preferencias, instalación/publicación y fuentes Apple quedan fuera. El pedido posterior autoriza la implementación; validación nativa/publicación se registran por separado.

## Corrección de alcance FIX-198

El usuario aclara después de probar0128: **volumen por scroll únicamente sobre el frente visible de la carátula o la cápsula de volumen abierta**. El fondo completo, espacios libres, metadatos, reverso y paneles no ajustan volumen. Esta decisión reemplaza el alcance amplio de FIX-197 y sus referencias históricas a fondo libre. Salir de la carátula cancela ajustes y drena la secuencia propia, sin adoptarla al volver; un gesto iniciado fuera no se convierte en volumen al entrar. El feedback desde la barra con fullscreen abierto se conserva.

Implementado en ambas apps; FIX-198 verificado con 60 focales Mac, build0129 release/745 pruebas ejecutadas, firma y diez hashes válidos. Frontend Windows: check0/0,378 aprobadas/una omitida y build aprobada. QA física y runtime Windows pendientes. La nueva región neutra del Canvas Apple protege superficies retenidas debajo, sin quitar al fondo su arbitraje anterior de navegación. Windows traslada el atributo de la escena al botón de carátula.

## Estado de partida contrastado, anterior a FIX-197

| Fuente | Evidencia y consecuencia |
|---|---|
| [`PlayerBar.svelte`](../src/lib/components/player/PlayerBar.svelte) | Cápsula abierta por clic, popover de 152×36, slot de 32×32, range 0…100, foco, Escape, cierre exterior y protección durante arrastre. No hay handler wheel propio. Conservar geometría y apertura; comprobar el comportamiento implícito del range en WebView2. |
| [`FullscreenNowPlaying.svelte`](../src/lib/components/fullscreen/FullscreenNowPlaying.svelte) | Frente de portada es un botón play/pause; negro al 22 % y controles al hover/foco. Reverso muestra información; cola/letras/recomendaciones ocupan un panel separado. No recibe actualmente un callback de volumen. Mantener identidad y carga de imagen al actualizar porcentaje. |
| [`navigation/gestures.ts`](../src/lib/navigation/gestures.ts) | Un listener wheel de ventana, `passive:false`; sólo Alt + horizontal puede navegar. Cierre fullscreen por arrastre touch/pen sobre superficie marcada, con Pointer Events. **La rueda vertical ordinaria hoy no cierra fullscreen en Windows.** Integrar volumen en este punto de arbitraje sin inventar otro listener competidor. |
| [`+page.svelte`](../src/routes/+page.svelte) | Compone ambas superficies y delega `handleVolumeChange` a `player.setVolume`. Sus guardas ya conocen sesión, navegación, modal, Spotlight, menú y foco. Extender las guardas pertinentes para volumen. Escape respeta primero el popover abierto. |
| [`player/controller.ts`](../src/lib/player/controller.ts) | `setVolume` publica estado optimista y lanza un RPC por llamada. Revisión de operación filtra respuestas antiguas, pero no serializa las aplicaciones reales de audio. Mute y modo exponencial tienen caminos distintos. Una ráfaga wheel necesita orden y coalescencia dentro del controller. |
| [`commands/playback.rs`](../src-tauri/src/commands/playback.rs) | `set_playback_volume` rechaza no finitos y limita 0…100. `apply_volume_preferences` aplica ganancia/volumen bajo lock, actualiza RAM sólo al éxito y hace rollback de audio de mejor esfuerzo al fallar. Libmpv recibe `volume.round()` entero; el DTO conserva el porcentaje `f64`. Mute es cero exacto y restaura el último positivo. |
| [`playback_runtime.rs`](../src-tauri/src/playback_runtime.rs), [`lib.rs`](../src-tauri/src/lib.rs) | Persistencia por cuenta/invitado existente: firma de cambios, worker, último snapshot por ruta, escritura tras 350 ms de silencio y flush al cierre/cambio de identidad. `to_dto` solicita persistencia. No copiar el debounce de UserDefaults propuesto para Apple ni añadir almacenamiento en la vista. Medir serialización de cola y ráfagas antes de optimizar. |
| [`volume.rs`](../src-tauri/src/volume.rs) | La opción exponencial suma atenuación conservando ganancia del track. El gesto cambia el porcentaje del mismo modelo; no redefine esta política. Antecedente [PLAN-007](PLAN-007-exponential-volume.md), FIX-143/PAR-024. |

Antecedentes de presentación: FIX-121-2, FIX-134 y FIX-143, [PLAN-008](PLAN-008-fullscreen-color-logo-type.md). La inspección no acredita audio, FPS ni interacción nativa. No se atribuye una regresión a estos cambios.

## Contrato compartido y diferencias de plataforma

| Aspecto | macOS, PLAN-021 | Windows, este plan |
|---|---|---|
| Zonas | Cápsula abierta y frente visible de portada; fondo excluido (FIX-198) | Mismas zonas y exclusiones |
| Ajuste fino | 1 punto por evento discreto; acumulación para precisión | Pasos de 1 punto desde distancia normalizada por `deltaMode`; no inferir el dispositivo |
| Escala de audio | Float 0…1, AVPlayer | Porcentaje 0…100, Tauri/libmpv; no dividir por 100 al llamar al comando |
| Inercia | `momentumPhase` | Usar `WheelEvent.momentum` cuando el runtime lo exponga y funcione; fallback explícito para versiones anteriores |
| Cierre fullscreen | Volumen reemplaza el descenso wheel en sus zonas | Conservar cierre touch/pen y Escape/botón; la rueda ordinaria no tenía ese cierre |
| Silencio | PLAN-021 propone corregir umbrales de mute | Ya es cero exacto; preservar restauración de 1 % sin portar el arreglo Apple |
| Feedback | Porcentaje y oscurecimiento existente de portada | Mismo contrato; CSS/Svelte y estado compartido del controller |

### Superficies y prioridad

1. **Barra inferior:** wheel vertical sobre la cápsula visible de volumen abierta, incluidos riel y altavoz. Con cápsula cerrada no capturar ni abrir por wheel. Un arrastre activo del slider tiene prioridad hasta soltar. No convertir wheel en mute, pausa ni seek.
2. **Fullscreen (FIX-198):** sólo el frente visible de portada, incluso fallback sin imagen, acepta volumen; requiere pista actual y reproductor disponible. Fondo, espacios libres, márgenes de portada y metadatos no son una zona de volumen. Salir hacia ellos cancela ajustes y drena el grupo propio, sin transferirlo ni adoptarlo al reentrar.
3. **Exclusiones completas:** reverso de información/Genius, paneles de cola/letras/recomendaciones, selector de panel, títulos/artistas/álbumes y sus márgenes reservados, sidebar, barra de progreso, botones y menús. Excluir el contenedor entero del panel, incluso vacío o en su límite de scroll. Un modal, Spotlight, contexto de cuenta obsoleto, ventana inactiva u overlay que ocluya la escena bloquean el volumen.
4. **Excepción explícita:** el botón de portada acepta wheel para volumen y clic para play/pause. No dejarlo excluido accidentalmente por el selector genérico `button` del coordinador, ni habilitar por eso todos los botones.
5. Resolver la superficie frontal real y sus ancestros, con marcadores semánticos como `data-volume-scroll` y `data-volume-excluded`. `event.target` puede permanecer ligado al inicio de una transacción wheel: contrastar la posición actual del puntero y el hit-test visible para detectar salida/oclusiones. No reclamar contenido retenido detrás de otra capa.

### Rueda, trackpad y sensibilidad

**Recomendación:** sumar distancia normalizada y emitir pasos completos de **1 punto porcentual**. FIX-207 conserva el remanente también entre pausas mientras superficie, revisión, dirección y elegibilidad sigan vigentes; los180ms sólo delimitan la propiedad de cada transacción. No usar 1 % por evento general: tanto ratones como trackpads pueden entregar píxeles y muchas muestras por segundo. `deltaMode` expresa unidades, no identifica el hardware. El valor final desde 42 % y un paso ascendente es 43 %.

Defaults iniciales de la app, **pendientes de calibración física en WebView2**:

| `deltaMode` | Distancia inicial por 1 punto porcentual |
|---|---|
| `DOM_DELTA_PIXEL` | 100 píxeles CSS |
| `DOM_DELTA_LINE` | 3 líneas |
| `DOM_DELTA_PAGE` | 1 página |

Estos números no son equivalencias del sistema ni una promesa de «1 muesca física = 1 %». La primera fase recoge trazas de ratón y Precision Touchpad y ajusta estas constantes antes de cerrar el comportamiento. No copiar los 8 pt de AppKit, dividir el delta DOM por `WHEEL_DELTA=120`, multiplicar por DPI/zoom ni consultar el alto cambiante del texto de la portada. El objetivo es precisión consistente por distancia, con el slider disponible para cambios grandes.

- Dirección propuesta: `deltaY < 0` aumenta, `deltaY > 0` reduce; respetar el signo recibido y comprobar las opciones de desplazamiento Windows. No aplicar la inversión de AppKit.
- Exigir intención vertical dominante, inicialmente `abs(y) > 1.25 * abs(x)`. Un inicio horizontal/ambiguo no adquiere volumen. FIX-211: después de adquirirlo, omitir muestras laterales/cero sin borrar remanente ni cancelar el resto del grupo; no sumarlas al volumen ni renovar feedback. Datos no finitos/modo desconocido siguen cancelando. Shift/Ctrl/Alt/Meta conservan su prioridad. Ctrl + wheel puede ser zoom o pinch sintetizado; nunca volumen. Alt + horizontal conserva navegación existente.
- Con igual distancia, unidad, dirección y secuencia, dividir o agrupar muestras debe producir el mismo resultado. No añadir aceleración propia. Una inversión limpia el remanente anterior para evitar retraso en el sentido nuevo.
- En 0/100 consumir sólo input propio, descartar exceso y permitir reversión inmediata. No acumular deuda, enviar comandos nulos ni saltar desde cero al volumen previo. Conservar fracciones existentes: 42,3 + 1 da 43,3 en el modelo, pero el motor actual recibe el entero redondeado. La feature no promete resolución acústica subporcentual.

### Ownership, cancelación e inercia

Reutilizar la entrada central de `installNavigationGestures`: evaluar volumen **antes** del descarte temprano de rueda sin Alt y después entregar los eventos no propios al arbitraje actual. Una política pura separada calcula dueño, pasos y cancelación. Un único listener no pasivo realiza consumo y emisión; no combinarlo con `onwheel` locales que sumen otra vez.

Registrar también el inicio de ráfagas sobre superficies excluidas, sin consumirlas. Agrupar inicialmente por 180 ms de silencio; es un límite de transacción de la app, **no una fase física del trackpad**. Dentro del grupo no adoptar un scroll de letras/cola al cruzar la portada. Al salir de una zona propia hacia controles/paneles, parar ajustes, limpiar remanente y bloquear readopción hasta el grupo siguiente. Drenar los eventos cancelables restantes de esa secuencia propia, sin transferirla a panel, fondo, pull ni navegación: el hit-test detecta la salida, pero no cambia el target ligado a la transacción. El panel puede empezar su scroll con una ráfaga nueva. Cancelar por pista/generación, giro de portada, cierre, resize, foco/visibilidad, sesión, modal, menú, drag o desmontaje. No cancelar por cada tick de progreso ni mantener capturas fuera de la ventana activa.

Para reclamar y cambiar volumen, el evento debe ser cancelable y `preventDefault()` debe ser efectivo. Respetar `defaultPrevented` de un consumidor anterior y no aplicar un cambio adicional. Reclamar desde la primera muestra vertical elegible, incluso por debajo del umbral, para evitar scroll de fondo o wheel nativo del range. Si no se puede cancelar, no aplicar a la vez un cambio custom; cancelar esa secuencia y verificar la ruta nativa. No usar `stopPropagation` indiscriminado ni consumir wheel ajeno. Probar expresamente que un evento sobre el range no modifica el volumen dos veces.

**Soporte moderno:** la documentación actual de [Edge 151](https://learn.microsoft.com/en-us/microsoft-edge/web-platform/release-notes/151#wheel-event-indicates-whether-a-momentum-scroll) incorpora `WheelEvent.momentum`. No mantener como regla universal el comentario antiguo del coordinador que supone ausencia de información de momentum. Detectar capacidad sin suponer que la versión de Edge del equipo sea la de WebView2. Comprobar en eventos reales si la propiedad distingue la inercia en el runtime soportado. Con `momentum === true`, no generar pasos ni renovar los 900 ms de feedback; consumir sólo la continuación cancelable de una secuencia propia, incluido su drenaje tras salir de la zona. Momentum ajeno no inicia volumen. No confundir `false` con fase de inicio/contacto nuevo.

**Compatibilidad anterior:** si falta esa señal, DOM no ofrece aquí fases equivalentes a `NSEvent.phase`; el tiempo entre eventos no prueba que se levantaron los dedos. Mantener acumulación moderada, sin aceleración propia, y procesar eventos elegibles, incluida la inercia indistinguible. Dejar esta diferencia documentada y ensayada; no prometer que se corta al levantar los dedos. No desactivar sólo «trackpads» con una clasificación inventada ni exigir actualización del runtime en silencio. Si QA demuestra cambios de volumen excesivos, recalibrar antes de entregar; si el requisito final exige corte exacto en runtimes antiguos, evaluar aparte una integración nativa que realmente exponga la información necesaria. No presentarla como resuelta por un timeout.

La agrupación temporal tampoco garantiza identificar toda secuencia física: ensayar salida/reentrada e inercia externa con pausas. Marcar cualquier límite restante en la aceptación de Windows.

## Estado de audio y asincronía

Ambas superficies llaman al mismo controller y al comando existente `set_playback_volume`. No añadir volumen independiente a cada vista, no cambiar contratos del core ni escribir directamente al motor desde Svelte.

1. **Una vía ordenada de volumen:** dentro del controller, como máximo un RPC en vuelo y el último objetivo pendiente. La política suma sobre la intención más reciente del controller, evitando perder pasos porque el DTO confirmado llegue después. Coalescer ráfagas como máximo una emisión por frame con tope inicial 60 Hz; primer paso sin demora por un debounce de UI y último objetivo enviado al asentarse. No crear una promesa/RPC por muestra.
2. **Mute, slider y modo:** compartir orden con los otros escritores de volumen y modo exponencial. Un mute posterior descarta el objetivo wheel pendiente y queda después del comando en vuelo para terminar en cero. El slider reemplaza objetivos anteriores; wheel queda bloqueado mientras se arrastra. Cambiar modo conserva porcentaje/ganancia actuales. Una revisión que sólo ignora respuestas viejas en UI no impide que el audio reciba comandos fuera de orden.
3. **Confirmación:** mantener intención pendiente y último valor confirmado dentro del controller. El porcentaje de portada refleja volumen confirmado por el runtime, no una suma en la vista. Puede aparecer inmediatamente con el último confirmado al recibir el gesto y actualizarse tras el ACK. Si el slider conserva su anticipación optimista, documentarla como pendiente; no llamarla audio confirmado. Filtrar DTO/respuestas obsoletos sin perder cola, progreso, revisiones o generación más nuevos; probar eventos de reproducción intercalados entre petición y respuesta.
4. **Error/cancelación:** al fallar detener la ráfaga pendiente, reconciliar con estado nativo y mostrar el error recuperable existente; no reintentar automáticamente ni dejar un porcentaje anticipado como aplicado. Invalidar pendientes al cambiar cuenta/desconectar; la cancelación del frontend no puede deshacer un comando nativo ya en vuelo. Revisar las guardas de identidad/generación del comando al implementar y cubrir el cruce real con cambio de cuenta, sin trasladar volumen a la cuenta nueva ni introducir bloqueos del core.
5. **Persistencia:** reutilizar store por identidad y flush existentes. No escribir preferencias por evento desde Svelte. Medir cantidad de snapshots/clones de cola y trabajo del worker durante un barrido; optimizar sólo con evidencia. No esperar flush síncrono en el handler wheel. El cierre debe conservar el último volumen confirmado; documentar que un cierre abrupto no garantiza el último instante.

## Porcentaje y accesibilidad

- Desde portada o cápsula con fullscreen abierto, mostrar temporalmente `43 %` centrado en el frente, con dígitos de ancho estable y el mismo negro **22 %** del hover. Sustituir el icono play/pause mientras aparece el número. El porcentaje no recibe eventos; clic y menú contextual de portada siguen funcionando.
- Activar feedback al aceptar input, incluido intento en 0/100 o distancia aún menor al primer paso, con el porcentaje confirmado actual. Ocultar aproximadamente **900 ms** tras el último input propio no inercial; al continuar hover/foco retorna play/pause. Cancelar al abandonar hacia un panel, cambiar pista/escena/cuenta o abrir un modal. No oscurecer permanentemente la portada.
- Con reverso visible sólo la cápsula es elegible; mostrar su número en un indicador temporal adyacente al bloque de portada, fuera del texto de información y sin desplazar layout. El reverso nunca cambia de dueño a volumen.
- Mantener dimensiones de cápsula y área de portada. En barra, conservar el range y su `aria-valuetext`; ayuda localizada para indicar rueda, sin añadir un número que tape el riel.
- Conservar teclado, foco/Escape y Narrator. El botón de portada sigue anunciado como play/pause; no sustituir su nombre accesible por volumen. Feedback visual decorativo y anuncio porcentual agrupado al asentarse, sin una región viva que lea cada muestra. El range conserva acciones de 1 punto y nombre «Volumen».
- Respetar `prefers-reduced-motion`, contraste alto/`forced-colors` y escala de texto Windows. Sin escala por evento ni animación de cada dígito. Fondo local del número si el contraste lo necesita, sin alterar el oscurecimiento global por defecto. No remount del componente ni nueva decodificación de imagen por volumen.

## Ejecución y comprobaciones de cierre

- [x] **Investigación y plan:** inspección estática Windows, contraste Apple y fuentes oficiales; documentar diferencias sin implementar ni declarar paridad validada.
- [ ] **1. Calibración de entrada:** en Windows real registrar sólo deltas/unidades/cancelabilidad/capacidad de momentum y versión de WebView2, sin datos de cuenta/canción. Ratón de muescas, giro libre y Precision Touchpad; ajustar umbrales internos. La instrumentación debe poder retirarse/desactivarse y no registrar URLs/credenciales. Elegir fixtures a partir de trazas.
- [x] **2. Política y arbitraje:** añadir módulo puro sugerido `src/lib/player/volume-scroll.ts`, tests de acumulación y ownership e integración del listener existente. Probar routing DOM real y oclusiones; conservar Alt + horizontal y pull touch/pen.
- [x] **3. Audio/controller:** ordenar y coalescer todos los escritores pertinentes, reutilizar comando/rollback/mute y store. Tests de latencia, intercalado de DTO, errores, cambio de cuenta y generación. Cambiar Rust de integración sólo si una guarda o fallo reproducible lo requiere, sin tocar el core protegido.
- [x] **4. Presentación:** conectar callbacks/estado en `+page.svelte`, PlayerBar y FullscreenNowPlaying; feedback acotado, reverso, localización ES/EN y accesibilidad.
- [ ] **5. Verificación (frontend completado; runtime Windows pendiente):** `pnpm check`, `pnpm test`, `pnpm build` en `windows/`; añadir regresiones de política, controller y fixture real de componentes. En Windows ejecutar `windows/scripts/windows.ps1 -Action verify`. Frontend probado en Mac no acredita WebView2/libmpv ni interacción nativa.
- [ ] **6. Cierre físico y entrega:** matriz siguiente, revisión del diff, FIXES para implementación real, evaluación PARIDAD enlazando ambos planes y límites comprobados. Actualizar estado/índices. Si se solicita build, usar el flujo oficial Windows; no crear build, fix ni resultado de audio durante esta planificación.

## Matriz de aceptación

| Área | Casos que deben pasar antes de declarar la función validada |
|---|---|
| Delta | Signos ±; modos pixel/line/page; muestras subdivididas/coalescidas; umbral/remanente; inversión antes de completar paso; cero/NaN/infinito/modo desconocido; fracciones del modelo; saturación y reversión sin deuda. |
| Superficies | Cápsula abierta/cerrada y arrastre; portada/fallback; fondo excluido e inicio/salida/reentrada sin adopción; exclusión de panel vacío, cola/letras/Genius al borde, reverso, controles, títulos/sidebar; popover superpuesto y z-order. |
| Arbitraje | Inicio excluido→portada sin adopción; propia→panel→portada sin reanudar ni desplazar panel/fondo durante grupo, con scroll del panel disponible en ráfaga nueva; no doble cambio en range ni evento ya prevenido; `cancelable=false`; Alt/horizontal y Ctrl/pinch preservados; pointer pull touch/pen, Escape/botón de cierre y clic play/pause intactos. |
| Inercia | Runtime con `momentum` real: contacto mueve, inercia no suma ni renueva feedback; inercia ajena no se adopta. Runtime sin capacidad: comportamiento fallback medido y diferencia publicada. Salida/reentrada, pausas mayores/menores a 180 ms y contacto nuevo tras inercia. |
| Audio/estado | 0/1/5/42/100; último audible 1 %; mute tras ráfaga y desde cero; slider concurrente; modo exponencial ON/OFF y carga de canción; RPC lento/fallido, eventos y respuestas intercalados; cola/progreso intactos; cambio de cuenta, desconexión y cierre con petición en vuelo. |
| Feedback | Primer input y extremo; timeout renovado/cancelado; hover/foco al terminar; reverso; nueva pista con misma imagen/ID y generación nueva; número correcto al rechazar audio; cero timers/trabajo añadido al reposo. |
| Entorno real | Ratón de muescas/giro libre y Precision Touchpad; opciones de scroll del sistema; Windows soportado/runtime mínimo y actual; DPI/escala 100/150/200 %, ventana estrecha/resize, fullscreen cinematográfico y nativo; Narrator/teclado, alto contraste y Reduce Motion. |
| Rendimiento/persistencia | Barrido de 10 s: eventos, pasos, RPC/aplicaciones, snapshots de cola, escrituras y latencia. Sin RPC por muestra ni imágenes recargadas; flush final/restauración por cuenta y sesión invitada con datos de prueba aislados. Medición física separada de check/build/tests. |

## Referencias técnicas oficiales

Consultadas el 2026-10-17. Las características documentadas no demuestran la capacidad del WebView2 instalado; la fase 1 debe comprobarla.

- [W3C Pointer Events 4, WheelEvent](https://www.w3.org/TR/pointerevents4/#interface-wheelevent): unidades y signo del delta, transacción con target ligado, atributo de momentum. La especificación actual aloja allí las secciones de rueda trasladadas desde UI Events. Basar el adaptador en capacidades comprobadas, no en un borrador supuesto universal.
- [Microsoft Edge 151: momentum scroll](https://learn.microsoft.com/en-us/microsoft-edge/web-platform/release-notes/151#wheel-event-indicates-whether-a-momentum-scroll): incorporación de la señal; verificar soporte funcional del runtime destino.
- [W3C, cancelabilidad de wheel](https://www.w3.org/TR/pointerevents4/#cancelability-of-wheel-events) y [DOM, preventDefault](https://dom.spec.whatwg.org/#dom-event-preventdefault): consumo sujeto a cancelabilidad/listener no pasivo.
- [Microsoft, WM_MOUSEWHEEL](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-mousewheel): deltas nativos y `WHEEL_DELTA`; no son unidades DOM. Un puente nativo requeriría investigar enrutamiento WebView2 y duplicación, y no forma parte de la recomendación inicial.

La entrega inicial fue sólo documentación. El pedido posterior añade [FIX-197](../../FIXES.md#fix-197) y PAR-032; no declara aceptación física ni runtime Windows verificado.

## Implementación FIX-197

- `volume-scroll.ts` normaliza deltaMode con los defaults anteriores y mantiene ownership/drain; el listener central resuelve hit-test frontal, consumo efectivo y capacidad de momentum. Los runtimes sin señal conservan el fallback documentado.
- Barra y frente de portada comparten entrada; FIX-198 excluye el fondo. Fullscreen muestra el porcentaje confirmado durante 900 ms, también al ajustar desde la cápsula. El icono play/pause se oculta durante el número, el reverso deja su texto libre y los paneles conservan scroll propio.
- El controller ordena/coalesce nivel, mute y modo en una sola vía, separa intención de `confirmedVolume` y reconcilia fallos sin reintentar la misma ráfaga. `audioRevision` en DTO/integración impide que respuestas/eventos antiguos rebobinen audio sin bloquear progreso/cola.
- Comandos de audio comprueban generación y contexto auth bajo el lock de reproducción. Conservan curva, normalización, mute/restauración y store por cuenta. No cambia el core protegido.
- Verificación frontend: `pnpm check` 0 errores/0 avisos; **378 pruebas aprobadas y una omitida**; build Vite/adapter-static aprobada. Incluye 41 tests de controller y fixture con 11 subpruebas de política, timers, componentes Svelte montados y routing. Tras localizar el porcentaje, check/11 focales/build repetidos y aprobados. `happy-dom@21.0.3` es exclusivamente de desarrollo; no evalúa scripts del documento ni carga recursos externos. La fixture ejecuta los componentes compilados con Svelte y su propio código de prueba, pero inyecta hit-test y no acredita layout real/WebView2.
- La ejecución Rust en este Mac no acredita Windows: sin override falla por DLL de bundle ausente; omitiendo únicamente recursos de bundle avanza hasta referencias/macros de login/session configuradas sólo para Windows. No se altera ese código ajeno para simular verificación. Test de ownership Rust/default DTO agregado, ejecución nativa destino pendiente.

Entrega técnica registrada en [FIX-197](../../FIXES.md#fix-197)/PAR-032; la app Mac hermana se conserva en build0128. No se produjo EXE ni se ejecutó verify en Windows; las casillas de calibración, runtime y aceptación física permanecen abiertas.

## Revisión de release 1.2.1 — 2026-10-17

FIX-201 completa el marcador/selección de FIX-200 sin cambiar la política de volumen de FIX-198. El DTO de cola conserva identidad visual de origen independiente del entryId nativo, incluido shuffle/restauración. 381 frontend/check0/0/build aprobados;45 pruebas del módulo queue.rs real en harness Mac. CI Tauri/libmpv y verificación física permanecen pendientes en [la entrega1.2.1](../../plans/RELEASE-1.2.1.md).

## Reporte posterior a1.2.1 — FIX-207

El usuario confirma Windows: portada y barra muestran siempre el mismo porcentaje con rueda, pero el slider arrastrado sí cambia el sonido. Se reproduce pérdida permanente de distancia con60px cada250ms: cada evento abre una transacción nueva y elimina el remanente antes de alcanzar100px. Esta reproducción usa entrada sintética; no consta el delta real del dispositivo informado.

- [x] Conservar distancia entre pausas sólo en misma superficie/revisión elegible; descartar al invertir o cancelar, sin adoptar secuencias ajenas.
- [x] Cancelar al salir incluso después de expirar los900ms del feedback.
- [x]15 focales aprobadas con política, adaptador, Svelte y PlaybackController reales; RPC simulado registra tres ajustes por seis entradas60px/300ms en cada zona y porcentaje confirmado correcto. Slider20 sigue funcionando; modos/guards/regresiones anteriores conservados.
- [x] `pnpm check`0/0,381frontend aprobadas/1fixture nativa omitida enMac, build frontend aprobado; sin cambios core, audio nativo ni Apple.
- [ ] Probar EXE/WebView2 y dispositivo del usuario enWindows, incluyendo escucha; aún no hay build/publicación de FIX-207.

Evaluación Apple en lectura: eventos de ratón no precisos ya producen un paso por evento; entrada precisa sin fases conserva un reset temporal que requiere investigar separadamente si existe un síntoma equivalente. [PAR-032](../../PARIDAD.md) conserva esa limitación sin declarar un port validado.

## Entrega1.2.2 — FIX-209/210

Fuentes8b8e135 subidas a main y [release1.2.2](https://github.com/fefucho/sideb/releases/tag/v1.2.2) publicada como Latest2026-10-18. Windows job117568496842 aprueba761pruebas (382frontend/97InnerTube/91core/93bridge/5player/93Tauri;14Rust ignoradas), check0/0, compiled/sourceChangedDuringBuild=false, versión1.2.2/build15. Portable/instalador y cuatro hashes de runtime aprobados, descargas públicas idénticas a los artefactos CI. FIX-210 corrige sólo la colección de rutas numeradas y completa publicación; no modifica binarios ni se atribuye éxito al publicador original fallido. Véase plans/RELEASE-1.2.2.md. Cuenta/audio/entrada física e instalador interactivo siguen pendientes; no se cambiaron core ni curva.

## Reporte persistente en1.2.2 — 2026-10-18

El usuario confirma versión1.2.2 y el mismo síntoma. Prueba dirigida: slider en50%, cursor quieto sobre portada y diez muescas hacia abajo; permanece50%. Al iniciar esta investigación no había traza real; no se atribuye el dispositivo a la reproducción de60px/250ms de FIX-207. La captura recibida después permite el cierre técnico de FIX-211 descrito abajo.

- [x] Revisar fuente y ruta común wheel→policy→adjustVolume→set_playback_volume; slider comparte controller/comando. Feedback puede aparecer con delta0 antes de alcanzar un paso. Es una explicación del indicador, no la causa confirmada de este reporte.
- [x] Comprobar bytes publicados: descomprimir desde el EXE público el asset Brotli `/_app/immutable/nodes/2.CSaJCDEQ.js`. Sus538693bytes coinciden íntegramente con el frontend local publicado (SHA256 `8b711b845692af7dfb35f09d2a358f58404df2519e8c15df84ec7ee466fd6f47`); incluye conservación de remanente y adaptador de FIX-207. Evidencia local en `builds/releases/v1.2.2/windows-inspect/`. No prueba qué proceso está abierto en la PC del usuario.
- [x] Preparar [captura local](../scripts/diagnose-volume.md) sobre el EXE instalado, sin recompilar/publicar otra app ni cambiar audio/core/curva. Observa valores y cancelación antes/después del handler, superficie/foco y órdenes/ACK de volumen; no toma datos de cuenta/canción ni comandos ajenos. Preserva retornos/argumentos y se retira al terminar o a120s; máximo400registros.
- [x] Tres pruebas del observador aprobadas: no consumo/comandos propios, preventDefault posterior al handler, condiciones CDP reales sobre funciones IPC inmutables sin pausas/sustituciones y retorno/callback/errores conservados, salida sin campos privados, límite/retirada/timeout. El CDP de V8 local no acredita el launcher PowerShell/WebView2. Las15 focales existentes también aprueban; no reproducen el nuevo fallo físico.
- [x] Verificación local final: `pnpm check`0errores/0avisos; `pnpm test`384aprobadas/1omisión nativa enMac; `pnpm build` frontend aprobado. ZIP de captura con tres archivos y CRC aprobados en `temp/windows/volume-diagnostic/SideB-diagnostico-volumen.zip`; no es un EXE/build numerado ni una nueva release. Sin cambios de lógica de app, core, versión, commit/push o publicación.
- [x] Recibir captura real del launcher PowerShell/CDP en la PC afectada; hash del EXE coincide con1.2.2 publicada. WebView2 155,351eventos/16órdenes;400registros retenidos y resto truncado. Hay177muestras registradas:170en tres grupos completos (121portada/49barra), más7del último grupo incompleto. Las16órdenes/ACK de volumen ocurren durante el arrastre; no hay órdenes durante los grupos de rueda registrados.
- [x] Construir regresión con datos numéricos sin metadatos del usuario y corregir causa, [FIX-211](../../FIXES.md#fix-211)/PAR-032. Antes: primera muestra lateral del grupo cancela y el replay de los tres grupos emite0ajustes. Después:25ajustes y valores59→56,59→67,50→45; portada/barra/controller reales y RPC simulado actualizan porcentaje confirmado. Dos regresiones nuevas fallaron antes y pasan después;17focales/384frontend/1omisión/check0/0/build frontend aprobados. No acredita audio audible ni un EXE nuevo.
- [x] Compilar/entregar Windows1.2.3/build16 con FIX-211; [FIX-212](../../FIXES.md#fix-212)/[plan1.2.3](../../plans/RELEASE-1.2.3.md). CI39149085379 success completo,764pruebas Windows/385frontend, fuentes estables y revisión d8619ca. Instalador/portable públicos/checksums/cuatro hashes internos aprobados; frontend del EXE público idéntico al frontend local verificado. Publicada2026-10-18 14:52:53 America/Montevideo como Latest junto a Mac761pruebas, sin recuperación manual.
- [ ] Repetir entrada física/audio con el EXE corregido en la PC del usuario.1.2.2 conserva el defecto; requiere actualizar a1.2.3.

Detalle de causa: en el primer grupo el evento4 añade x=-23,33/y=13,89 después de sólo30,56px verticales acumulados. La condición por muestra deja de ser vertical y llamaba `cancel()`, vaciando resto y drenando todos los eventos posteriores hasta180ms de silencio. Los otros dos grupos completos reproducen la misma cancelación. Se omiten muestras laterales/cero de una secuencia ya propia; salida de superficie, contexto, modal, modificadores, cancelabilidad y datos inválidos siguen drenando como antes. No se cambia sensibilidad, umbral ni audio nativo.

Limitación corregida del diagnóstico: schema1 utilizaba `queueMicrotask` desde capture para leer `defaultPrevented`; puede ejecutarse antes del listener bubble de la app. Sus valores `wheel-after=false` no prueban que faltara consumo. Schema2 difiere esa lectura a la tarea siguiente y retira timers al terminar; prueba de checkpoint/timers aprobada, repetición física del observador revisado pendiente. La causa se sustenta en replay de deltas y órdenes/ACK observadas, sin depender de ese campo.

Apple consultada en lectura: `Services/Player/VolumeScrollPolicy.swift` ya conserva ownership y remanente al recibir una muestra no vertical después de adquirir volumen (`guard vertical else { consume:true }`); no comparte la cancelación Windows. No requiere port de FIX-211 ni cambia su estado físico pendiente de PAR-032. La captura es exclusiva de Windows/WebView2.

## Entrega1.2.4 — FIX-213/214/215

El usuario confirma «ahora sí anda» con0014 y autoriza subir la build. [Release1.2.4](https://github.com/fefucho/sideb/releases/tag/v1.2.4) publicada como Latest el2026-10-18 a16:38:40 America/Montevideo desde c86454edd63550e642e37676e44ee9e228a045ac. Los cuatro jobs de [CI39157077739](https://github.com/fefucho/sideb/actions/runs/39157077739) aprueban preparación, Mac, Windows y publicación. Las cinco descargas públicas coinciden con digests/manifiestos SHA256; portable Windows con cuatro archivos, PE x64/version1.2.4 y runtime conservado. Mac1.2.4/build17/arm64/mínimo15.0 comprobado; firma aprobada por CI.

Los recuentos764/385 y la aceptación del usuario corresponden a0014/FIX-213; no se atribuye lectura de logs autenticados ni escucha/instalación interactiva nueva a esta entrega. Fuentes funcionales Apple/core conservadas y releases anteriores intactas. Véase [plan1.2.4](../../plans/RELEASE-1.2.4.md) para hashes/evidencia y límites.
