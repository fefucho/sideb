# Octave — referencia visual de letras y plan para macOS

Fecha: 2026-10-20. Estado: investigación visual completada y propuesta pendiente de implementación. Continúa [PLAN-025](../../apple/plans/PLAN-025-word-synced-lyrics.md) y la [investigación de datos Apple/TTML](APPLE-LYRICS-2026-10-20.md).

## Resultado

Podemos acercar mucho el panel experimental de Side B al aspecto observado en [Octave Music](https://music.octavestreaming.com/): letra grande y pesada, frase activa centrada, contexto desenfocado, relleno suave y ampliación de palabras sostenidas, tres puntos en las esperas y controles discretos. No hace falta cambiar de renderer ni depender de Octave como proveedor para hacer esta parte visual.

Las letras clásicas siguen disponibles y predeterminadas. La nueva presentación se propone dentro del acceso temporal «Probar nuevas letras», con regreso a «Letras actuales». Las voces de fondo independientes requieren enriquecer el contrato de datos; en las muestras visuales de Octave se mostraron entre paréntesis o como líneas normales del mismo tamaño.

## Qué se comprobó en la web

Se utilizó la pestaña que dejó abierta el usuario. Tras completar él mismo el desbloqueo de acceso, se probaron búsqueda, reproducción local, pausa, saltos, pantalla completa, desplazamiento manual y distintos anchos. No se modificaron cuentas ni se usó el reproductor remoto. El volumen estaba en cero: la prueba valida presentación y avance del reloj visible, no sincronización auditiva.

| Canción / versión visible | Qué permitió comprobar |
|---|---|
| Patience (feat. Don Toliver), Lil Uzi Vert, Pink Tape, 4:22 | Tipografía, espaciado, desenfoque, entrada y ad-libs en líneas normales. |
| De Música Ligera, Soda Stereo, Me Verás Volver (Hits & Más), 3:33 | Intro e interludio con puntos; salto al entorno de 1:15; contexto anterior y siguiente; scroll manual; adaptación de columnas. No se seleccionó una versión en vivo. |
| DtMF, Bad Bunny, DeBÍ TiRAR MáS FOToS, 3:57 | Intro, frases extensas y rápidas, ad-libs integrados entre paréntesis alrededor de 0:40. |
| Blinding Lights, The Weeknd, After Hours, 3:20 | Relleno durante palabras sostenidas alrededor de 0:59 y 1:02; máscara, brillo, elevación y escala; estado pausado. |

Las cuatro son una muestra visual, no una medición de cobertura de catálogo. La versión de estudio de Soda se eligió desde una recopilación; no se asume identidad de master con las respuestas API anteriores sólo por coincidir título/duración.

Evidencia local ignorada: `builds/octave-lyrics-visual-2026-10-20/`. Incluye capturas y medidas de DOM/CSS; no se incorporan letras completas ni datos de cuenta al repositorio. [Resumen de medidas versionable](OCTAVE-LYRICS-VISUAL-2026-10-20-evidence.json). El tamaño temporal del navegador se restauró y la última reproducción quedó pausada.

## Medidas observadas

Referencia principal: viewport de **1134 × 853 CSS px**, DPR 2. Los CSS px son unidades lógicas: no convertir 36 px en 72 pt por la pantalla Retina. SwiftUI debe partir de 36 pt y contrastar ancho real de los glifos y altura de línea.

| Elemento | Octave medido | Aplicación propuesta en Side B |
|---|---|---|
| Fuente | Familia del sistema primero: `-apple-system`, `system-ui`, SF Pro; luego Inter y otros respaldos | SF del sistema, peso bold. La cadena CSS no demuestra por sí sola qué archivo tipográfico terminó renderizando. |
| Tamaño / peso | **36 px / 700** en 900, 1134 y 1440 px de ancho | Base de **36 pt bold** en Karaoke; actual experimental: 29 pt semibold. Incremento aproximado de 24 % en tamaño. Mantener ajuste manual. |
| Altura de línea | **45 px**, proporción 1,25 | Objetivo visual 45 pt a 36 pt de fuente; calibrar métricas nativas, no sumar 45 pt de `lineSpacing`. |
| Tracking | −0,176 px en la referencia de Patience | Punto inicial aproximado −0,18 pt; confirmar con SF nativa. |
| Separación | 10 px arriba y abajo del bloque de palabras; una fila de un renglón ocupa 65 px | 20 pt extra por frase, altura variable según wrapping. No duplicar ese espacio con los 22 pt actuales del VStack. |
| Columna | Contenedor 447 px, 32 px laterales; fila 383 px; reserva derecha 48 px para compartir → texto efectivo 335 px | Padding lateral 32 pt en referencia de escritorio. Reservar la columna de acción sólo si se incluye esa acción; si no, ajustar el máximo de texto para conservar el wrapping de referencia. |
| Posición activa | Centro del viewport de letras; padding superior e inferior de 360 px para un viewport de 720 px | Espaciadores calculados con la altura disponible, para centrar también primera y última frase. Sólo en el experimento. |
| Bordes de lista | Máscara: entrada superior en 48 px y salida inferior en 88 px | Degradado vertical equivalente, con alternativa accesible sin pérdida de legibilidad. |
| Activa | Color de referencia `#F5F5F7`, blur 0, escala 1 | Foco claro y estable; evitar que tamaño/peso cambien en cada transición. |
| Otras frases | Blanco con alfa 0,40; escala 0,98; blur por distancia observado de 1,2 / 2,1 / 3 px | Atenuación y desenfoque por distancia al foco, tope 3 pt. Reducir desenfoque al aumentar contraste. No acumular otra opacidad de fila sobre el alfa. |
| Cambio de foco | Transición CSS de 788 ms con curva amortiguada para transform/filter/color/opacity | Ajustar una transición nativa cercana a 0,8 s. Ese valor no mide por sí solo la duración interna del autoscroll ni es duración fija de las palabras. |
| Palabra en progreso | Base alfa 0,70 + capa iluminada alfa 1; máscara horizontal suave | Separar opacidad de la frase pendiente de la base de la frase activa. El experimento hoy usa base 0,40. |
| Borde del relleno | Dos muestras dieron una franja de gradiente de **30 px** | Aplicar el gradiente en coordenadas de palabra, con un ancho limitado por su geometría; calibrar visualmente. El renderer actual usa 3 pt por glifo. No cambiar sólo ese número sin revisar coordenadas. |
| Sostenidas | En una muestra: escala **1,1288**, elevación **1,84 px**, origen inferior central; brillo blanco de radio 5 px con alfa variable | Objetivo inicial de hasta ~1,13 y ~2 pt, condicionado por duración/progreso real. Transformación de dibujo, sin remaquetar texto. Los valores observados no revelan la función completa de animación de Octave. |
| Protección del efecto | Activa con padding 24 px y margen −24 px; otras con 8/−8 | Ampliar límites de dibujo para no cortar blur, brillo o escala; no tratar esos 24 px como espaciado entre frases. |

Fondo: colores ambientales suaves procedentes visualmente de la portada, con oscurecimiento hacia abajo y contraste suficiente. Se vio la transición rosa de Patience a oliva de Soda y verde de DtMF. Esto no establece el algoritmo de extracción de color. Conservar primero el fondo y la portada de Side B; ajustar después si impiden igualar el contraste.

## Adaptación al ancho

| Viewport probado | Resultado |
|---|---|
| 1440 × 900 | 36/45 px, contenedor de letras 600 px y fila 536 px; ancho efectivo de texto aproximado 488 px al descontar la acción. |
| 1134 × 853 | 36/45 px, contenedor 447 px y fila 383 px; texto aproximado 335 px. |
| 900 × 900 | 36/45 px, contenedor 370 px y fila 306 px; texto aproximado 258 px. Más renglones, no una reducción automática de fuente. |
| 600 × 900 | La pantalla completa pasó a una composición compacta de portada/controles sin la columna de letras visible. No se verificó allí el tamaño de letras. |

La clase CSS contiene un tamaño compacto de 1,7 rem, pero no se declara como una medida visual comprobada. El breakpoint exacto tampoco se deduce de estas cuatro pruebas. Para macOS, conservar letras accesibles al reducir ventana y permitir tamaño manual; no copiar automáticamente la ocultación compacta de Octave.

## Instrumentales y comportamiento

En Soda se observaron **tres puntos** entre la frase anterior y la siguiente, tanto en la intro como en un interludio. La frase anterior puede continuar enfocada. El bloque ocupa 38 px: puntos de base 14 × 14 px, gap 10 px y padding vertical de 12 px. Los puntos cambian escala y opacidad; en una captura estaban en 1 / 0,723 / 0,52 y alfa 1 / 0,55 / 0,22. El brillo medido incluye radio 16 px. Durante la intro de DtMF se vieron los tres puntos iluminados cerca de la primera entrada.

Esas muestras muestran progreso visual, pero no bastan para afirmar si Octave usa exactamente tres etapas, una función continua concreta o qué umbral elige para insertar un interludio. Tampoco prueban ausencia real de voz en audio: son intervalos de letras.

Al desplazar la lista apareció una pastilla flotante **Current line** al pie. Después desapareció antes de poder accionar el retorno; no se midió su timeout ni se verificó el resultado de ese click. Side B ya dispone de Volver: conservarlo con prioridad del scroll manual, sin adoptar un retorno automático no comprobado.

Los controles superiores son pequeños y flotantes: desfase −/Sync/+, probar otra fuente y acciones de letras. Se pulsó «Try another lyrics source»; no apareció un selector ni una identidad de proveedor verificable. No atribuir el resultado a una API determinada. La procedencia detallada es una mejora que Side B debe conservar en su menú accesible.

## Ad-libs y voces de fondo

En DtMF, los ad-libs de la muestra se dibujan dentro de la misma frase entre paréntesis, a **36 px / bold / alineación inicial**, y alargan el bloque. En Patience también se observaron ad-libs como filas normales del mismo tamaño. No se comprobó composición independiente por agente, alineación opuesta de duetos ni reducción de tamaño para coros en estas vistas.

Eso encaja con la limitación de las respuestas Octave ya investigadas: palabras con inicio/fin, sin rol de fondo o agente. En cambio, las muestras TTML conservaron `x-bg` y agentes. Para una presentación más completa, preservar esos campos y grupos en el parser/contrato antes de intentar distinguir voces visualmente. Paréntesis por sí solos no justifican inventar una segunda voz.

## Plan de implementación macOS

### A. Igualar primero el estilo en la opción experimental

1. Concentrar las medidas en un estilo de presentación local: fuente 36 bold, altura objetivo 45, padding de frase 10+10, foco y efectos. Aplicarlo en `ExperimentalLyricsPanel.swift` y `ExperimentalKaraokeText.swift`, sin cambiar el panel clásico.
2. Limpiar el encabezado experimental: conservar selector de prueba/vuelta y reunir tamaño, movimiento, traducción, desfase y procedencia en opciones discretas. No incorporar compartir/descargar líneas sólo para llenar la columna de Octave; ajustar el ancho del texto con criterio explícito.
3. Agregar padding de centrado dependiente del viewport y máscara superior/inferior. Comparar primera, media y última frase. **Decisión de alcance:** esto cambia los límites naturales de FIX-064 para esta variante; el modo clásico y su criterio actual permanecen intactos.
4. Añadir blur por distancia, escala de contexto 0,98, foco estable y transiciones amortiguadas cercanas a 0,8 s. Hacer scroll al cambiar de foco, sin ejecutarlo por frame ni mientras manda el scroll manual.
5. Cambiar el relleno a una base más luminosa y un frente de gradiente suave. Aplicar escala/elevación/brillo a las sostenidas sin modificar su layout. Ajustar límites para no cortar el efecto en los bordes de fila/viewport. Los timestamps existentes siguen gobernando el progreso.

Entregable A: comparación visual con las mismas cuatro canciones y fixtures propios, a 900/1134/1440 de ancho de ventana equivalente. La ausencia de un proveedor nuevo no bloquea este tramo.

### B. Intro, interludios y outro

1. Añadir al documento un modelo explícito de intervalos de espera, separado del booleano «pista instrumental». Precalcularlo al cargar/revisar el documento o cambiar la duración válida.
2. Usar secciones explícitas cuando sean utilizables y contrastarlas con la unión de **todas** las voces. Para inferencia, unir intervalos temporizados válidos por palabras/voces; usar fin de línea fiable si faltan palabras. Un fin fabricado como «inicio de la siguiente línea» no sirve para detectar un hueco.
3. Propuesta inicial: mostrar espera en huecos de al menos **5 s**, configurable internamente para QA. Es una decisión de Side B pendiente de prueba; no un umbral descubierto de Octave o Apple. Intro desde cero hasta primera voz; outro sólo con duración de pista válida y sin voces posteriores. Si faltan límites, omitir la inferencia.
4. Dibujar tres puntos de 14 pt, gap 10, bloque de 38 pt. Progreso calculado con tiempo de AVPlayer y el mismo desfase; sin contadores independientes. Al pausar o bufferizar se congela; seek recalcula inmediatamente.
5. Extender `ExperimentalLyricsClock.shouldPulse`: hoy sólo anima si hay palabra en cambio. Permitir actualización local mientras el indicador visible cambia; suspender oculto/pausado/fin de espera y con Reducir movimiento usar un estado estático o actualizaciones discretas. No subir toda la app a 60 Hz.

Entregable B: intro/interludio/outro, huecos cortos sin indicador, límites exactos del umbral, voces solapadas que suprimen falsas esperas y sincronía del desfase comprobados con fixtures deterministas.

### C. Detalle TTML y voces completas

1. Enriquecer de forma aditiva `core/crates/sideb-core/src/lyrics/karaoke.rs` y los records experimentales de `lib.rs` para conservar segmentos silábicos, rol de voz de fondo, agente, agrupación y secciones cuando existan. Actualizar bindings por el flujo oficial; revisar compatibilidad de los consumidores compartidos. Las letras clásicas y sus claves no se migran destructivamente.
2. Adaptar `ExperimentalLyricsDocument.swift` y `ExperimentalLyricsController.swift` conservando revisión, ocurrencia/cuenta y descarte de respuestas tardías. Llevar más datos no debe convertir paréntesis en roles automáticamente.
3. Componer voz principal y fondo como grupos vinculados con tiempos independientes. Propuesta de Side B: fondo más pequeño y subordinado, con margen para simultaneidad; agentes distintos pueden permitir alineación opuesta si los datos y QA lo justifican. Esto es una mejora adicional, **no un comportamiento demostrado de Octave**.
4. Seguir la investigación previa de LRC.red/Boidu para detalle y evaluar Octave como alternativa de cobertura. Mostrar proveedor real y calidad. No llamar «Apple oficial» a todo TTML compatible con su formato.

A y B pueden entregarse antes que C, pero la detección de esperas deberá recalcular la unión de voces cuando C incorpore esa información. Acceso Apple autenticado continúa como posibilidad posterior, no requisito de este diseño.

### D. Revisión y entrega para probar

- Fixtures propios para una, dos y cinco líneas visuales; palabras largas, acentos/emoji, CJK/RTL, ligaduras y segmentos que cruzan renglones. No incluir letras comerciales completas en tests o Git.
- Tests focales de intervalos, superposición de voces, umbral, duración desconocida, pausa/buffering, seek y desfase. Verificar respuestas tardías al cambiar fuente y repetir canción.
- QA de scroll manual/Volver, click para seek, cambio de tamaño en mitad de frase, primera/última frase centradas, cambio de Karaoke/Lectura y vuelta al panel clásico/Genius.
- Reducir movimiento: relleno temporal legible sin escala, elevación o desplazamiento animado. Contraste aumentado: atenuar/retirar blur y elevar contraste de contexto. VoiceOver recibe texto una vez; los puntos se anuncian como espera, no tres caracteres repetidos.
- Comparación de consumo con build0141: fila activa y espera visible, pausa, oculto y scroll manual. Instruments y escucha real antes de afirmar fluidez o precisión auditiva. El DOM medido no equivale a un benchmark del renderer nativo.
- Al implementar, pruebas apropiadas y build macOS numerada mediante el flujo oficial, sin publicación. Registrar FIX/paridad sólo por trabajo efectivamente realizado. Esta investigación no modificó fuentes de la app ni recompiló la build0141.

## Decisión recomendada

Mantener el renderer nativo y los proveedores actuales para el primer ajuste visual. Tomar de Octave **36 bold, foco central, contexto difuminado, relleno suave y puntos de espera**. Después completar TTML/voces desde datos ricos, porque las muestras de Octave simplifican esa información. Así el estilo solicitado queda comprobable pronto dentro del experimento y el detalle vocal tiene una etapa técnica concreta.
