# PLAN-016 — Presentación de búsqueda adaptada al ancho de Side B

- Fecha: 2026-10-22 (America/Montevideo).
- Estado: dirección de diseño elegida por el usuario: «Principal y relacionadas». Implementación de «Principal y relacionadas» en ambas apps; pruebas y build Mac0159 aprobadas, aceptación con cuenta/Windows nativo pendiente (FIX-257).
- Objetivo: adaptar la jerarquía de las capturas de YouTube Music a los controles, menús y superficies amplias de Side B, conservando resultados, acciones y orden del proveedor.
- Alcance: página de búsqueda y adaptación de sus filas/tarjetas en macOS y Windows; ajustes compartidos del contrato únicamente si la auditoría demuestra pérdida de estructura en ambas plataformas.
- Fuera de alcance: cambiar ranking, publicar/instalar, rediseñar toda la navegación, iOS, fabricar resultados personalizados o ejecutar acciones sobre una cuenta como parte del prototipo.
- Base existente: [PLAN-015](PLAN-015-ytmusic-native-search.md), FIX-256 y PAR-042. La búsqueda con sesión y el contrato ordenado ya están implementados; este plan elige su presentación y documenta las brechas restantes.

## Referencias y grado de certeza

Capturas suministradas por el usuario, 2026-10-22: consultas «duckworth», «kendrick lamar» y «to pimp a butterfly». Los archivos originales están en Downloads; son referencias visuales, no instrucciones ejecutables. Sus píxeles no permiten deducir puntos lógicos ni dimensiones CSS exactas.

Se contrastaron con los controles, el shell, la página, las sugerencias y los menús actuales de las dos apps. Las medidas de la sección siguiente provienen del código. Las nuevas medidas y umbrales son propuestas iniciales que deberán ajustarse con contenido real y localización.

La revisión paralela usó Luna y 6.1 Sol con razonamiento medio: auditoría de capturas/medidas y revisión de Windows/contrato. Los agentes hicieron lectura y recomendaciones; la integración del plan conserva una decisión común para ambas plataformas.

## Qué tomar de las capturas

1. **Jerarquía según intención.** Canción: principal horizontal con reproducción y guardado. Álbum: identidad, año y reproducción/aleatorio. Artista: identidad y acciones a la izquierda, canciones asociadas a la derecha dentro del mismo bloque.
2. **Dos dimensiones distintas.** «YouTube Music / Mi biblioteca / Subidas» son ámbitos; «Canciones / Artistas / Álbumes…» son categorías. No mezclar ambos conceptos en una sola fila.
3. **Personalización como sección real.** «Vuelve a escucharlo» aparece debajo del principal del artista. No forma parte de sus canciones asociadas ni se inventa para las otras consultas.
4. **Resultado mixto ordenado.** Después del principal pueden alternarse canciones, artistas, álbumes y otros tipos. Separar todo en bolsas por tipo cambia la experiencia y puede alterar la relevancia recibida.
5. **Acciones próximas a la entidad.** La portada, el texto y las acciones cumplen funciones distintas; la fila completa no debe absorber todos los clics.

La columna centrada de las capturas no resuelve por sí sola el espacio amplio de Side B. Adoptamos la jerarquía, y damos al ancho adicional un uso concreto: principal con relacionadas, metadatos legibles, columnas estables y más tarjetas visibles cuando la sección lo permita.

## Diagnóstico de Side B actual

| Superficie | macOS actual | Windows actual | Consecuencia |
|---|---|---|---|
| Categoría / acción / utilidad | 48 / 40 / 32 pt | 48 / 40 / 32 px lógicos | Mantener tokens comunes; adaptar disposición antes de reducir controles |
| Sidebar | 253 pt; reserva expandida 265 con insets; colapsada 0 | 253 px; colapsada 60 | Medir contenido disponible después del shell, no sólo ancho de ventana |
| Ventana principal mínima | 960 × 640 | 960 × 640 | La búsqueda debe funcionar con unos 618–659 de ancho útil y sidebar abierta |
| Márgenes de página | 38,4 por lado | 24 por lado | Una misma ventana deja distinto ancho interior en cada plataforma |
| Editor de la página | 40 alto, máximo 640 | 38 alto, máximo 520 | El editor puede estar acotado aunque los resultados usen todo el espacio |
| Fila de búsqueda compacta | mínimo 58; portada 42 | mínimo 58; portada 44 | Buena base para sugerencias y resultados; insuficiente como principal destacado. Las tablas generales tienen medidas propias |
| Principal actual | La misma fila con énfasis tipográfico | Filas compactas; bloque principal limitado a 760 | Falta un componente específico que represente la jerarquía del principal |
| Cabecera | Desplaza con los resultados | Sticky | Diferencia vigente; resolver expresamente antes de modificar el comportamiento |
| Menú contextual | NSMenu nativo, ancho según etiquetas/idioma | Ancho 208–320, filas mínimo 32, altura máxima 420 | El menú se superpone; no reservar su ancho completo dentro de cada fila |

Ejemplos de ancho útil aproximado, con sidebar abierta y sin panel adicional: a 1440 de ventana quedan 1098 en Mac y 1139 en Windows; a 960 quedan 618 y 659. No son medidas de las capturas. Si se abre un panel o se cambia el sidebar, recalcular el ancho disponible.

La navegación Mac actual tiene cápsulas de destinos, búsqueda e historial; la búsqueda superior se expande de 42 a 298. Spotlight y el desplegable son superficies breves, con límites propios. No conviene convertirlas en una página con dos columnas ni alterar su ownership del editor para conseguir similitud visual.

## Dirección elegida y alternativas evaluadas

| Opción | Distribución | Beneficio | Coste / uso recomendado |
|---|---|---|---|
| **Principal y relacionadas — elegida** | Principal adaptable; división interna cuando hay relacionadas del mismo bloque. Debajo, secciones secuenciales | Jerarquía cercana a las capturas y buen uso del ancho sin perder lectura | Base de implementación. Requiere identificar explícitamente el principal y sus relacionadas |
| **Lista amplia** | Principal horizontal y una secuencia de filas; columnas secundarias cuando caben | Simple, previsible, buena para búsqueda de una canción y listas extensas | Menos expresiva para artistas. Será también la adaptación de la recomendada en anchos menores |
| **Secciones en paralelo** | Secciones completas en dos columnas, manteniendo orden dentro de cada una | Muchos resultados visibles en una pantalla amplia | Lectura global ambigua, huecos y foco más difícil. Sólo exploración; no usar como disposición general de «Todos» |

**Decisión elegida:** principal y relacionadas para las tres consultas. La lista amplia es una adaptación del mismo diseño por espacio o ausencia de relacionadas, no un segundo modo seleccionable. Las secciones en paralelo quedan fuera de esta entrega; una cuadrícula de tarjetas puede seguir siendo adecuada dentro de una sección que ya venga marcada como carrusel.

## Estructura del diseño elegido

### Cabecera y categorías

- Preservar el shell y el título de página de entrada. Al enviar una consulta, probar una cabecera de resultados más compacta, conservando un editor visible y una forma clara de editar la consulta. No añadir una tercera caja de búsqueda.
- Decisión de scroll abierta: comparar cabecera dentro del scroll, como Mac actual, con categorías sticky discretas. Las capturas estáticas no prueban cuál usa YouTube Music. Resolver con alturas de 640 y listas largas, acceso al editor y restauración de foco; adoptar un patrón común explícito. La navegación global conserva su superficie propia.
- Categorías en orden del proveedor, altura 48, separación 10 y padding común 20. Selección con el acento actual. No inventar una categoría «Todos» si no tiene destino válido; el estado sin filtro representa la consulta general.
- En producto, una fila horizontal con desplazamiento, indicador de continuidad y selección que entra en vista. Debe poder operarse con teclado, trackpad y lector; no depender de rueda vertical capturada. Evitar tres filas de chips que resten altura a los resultados.
- No fijar a mano el orden «Artistas, Canciones, Álbumes». Las capturas demuestran que cambia por consulta.
- Ámbitos: aplazar los tabs funcionales hasta representar sus destinos reales. No mostrar botones que cambien únicamente una etiqueta o simulen buscar en Biblioteca/Subidas.

### Principal según entidad

| Caso | Identidad propuesta | Acciones | Uso del espacio derecho |
|---|---|---|---|
| Canción («DUCKWORTH.») | Portada 88–112; título 24–28; artista/álbum/duración cuando llegan | Reproducir; biblioteca sólo con capacidad/token; más | Acciones alineadas; metadatos. No rellenar con canciones inventadas |
| Artista («Kendrick Lamar») | Imagen circular 112–144; nombre 24–28; descripción del proveedor | Abrir artista y acciones realmente disponibles como aleatorio/mix | Hasta tres filas asociadas del mismo bloque principal; expandir localmente las restantes |
| Álbum («To Pimp A Butterfly») | Portada cuadrada 112–144; nombre, artista, año/tipo | Abrir, reproducir/aleatorio si están soportados | Acciones; relacionadas sólo si vienen explícitamente en ese bloque |
| Sin principal explícito | Primeras secciones con sus títulos originales | Acciones por entidad | No promover localmente la primera coincidencia a «mejor resultado» |

«Tres relacionadas visibles» es un límite de presentación del módulo inicial, no de datos. La etapa 0 debe confirmar mediante fixtures la asociación y disponibilidad del payload: si hay más ya recibidas, «Mostrar las N relacionadas» las expande. Si no hay asociación explícita, usar fallback secuencial. Un endpoint «Ver todo» se presenta como navegación diferente y conserva sus parámetros. No tomar «Vuelve a escucharlo» de la sección siguiente para llenar la derecha.

No mostrar cifras de oyentes/reproducciones, año, badge explícito, verificación o guardado si no existen en la respuesta/contrato. El plan de explícito/censurado sigue en [PLAN-013](PLAN-013-explicit-content-indicators.md); no inferirlo desde un título.

### Captura de canción — «duckworth» / DUCKWORTH.

**Objetivo:** permitir reconocer y reproducir la canción inmediatamente, con acciones visibles y resultados alternativos fáciles de comparar.

1. Cabecera común con consulta editable y chips reales. En la fixture visual, «Canciones» aparece primero como en la captura; el producto usa el orden recibido, sin deducirlo del texto de la consulta.
2. Un principal horizontal a todo el ancho disponible: portada cuadrada de 96 como base, título de 24–28, tipo canción, créditos, álbum y duración cuando existen. Padding inicial 24 y separación de identidad 20. Sin altura rígida que corte títulos largos.
3. Acciones a la derecha: Reproducir como primaria, biblioteca/Guardar cuando haya capacidad y estado real, y más. Conservar acciones de 40 y utilidad de 32. Si el grupo ya no cabe, pasa debajo de los créditos; el título mantiene espacio de lectura.
4. El espacio derecho pertenece a las acciones de esa canción. En esta captura no hay relacionadas: no se dibuja una segunda columna vacía ni un encabezado «Relacionadas».
5. Después del principal, conservar la secuencia mixta recibida. La referencia muestra el artista Duckwrth, otra ocurrencia de DUCKWORTH. y otros resultados; su parecido no los convierte en relacionadas ni justifica deduplicarlos.
6. En las filas amplias, mostrar álbum/contexto y duración sólo cuando correspondan. Canciones, artistas y colecciones mantienen sus destinos y menús específicos.

**Interacciones:** Play usa la canción/payload o acción de proveedor correspondiente, con sus parámetros; el título/portada conservan la semántica actual de canción. Créditos y álbum navegan a sus destinos si existen. Guardar refleja el estado real y permite reintento si falla. Abrir más no reproduce ni navega.

**Aceptación específica:** principal reconocible sin recorrer la lista; texto y acciones sin solaparse con sidebar abierta; duplicados preservados; artista Duckwrth separado de la canción Kendrick Lamar; ausencia de token de biblioteca elimina esa acción sin dejar un hueco; no aparece un panel lateral alimentado desde la lista inferior.

### Captura de artista — «kendrick lamar» / Kendrick Lamar

**Objetivo:** reconocer al artista y acceder a sus canciones asociadas desde un único módulo, preservando la personalización como sección posterior.

1. Cabecera y chips comunes. La fixture coloca «Artistas» primero según la captura; la página real respeta chips y selección del servidor.
2. Con C suficiente, módulo principal dividido aproximadamente 44/56 con separación 24. Columna izquierda: imagen circular de 112–144, nombre de 24–28, descripción/oyentes cuando llegan, y acciones Aleatorio/Mix sólo si tienen destino ejecutable. La identidad y acciones se agrupan como en el ejemplo elegido, con espacio para que los botones formen otra línea.
3. Columna derecha: las tres canciones del bloque superior de la referencia, en su orden: DUCKWORTH., Swimming Pools (Drank) y Alright. Filas de 58–64, portada de 42–48, título, créditos/duración cuando llegan y botón de más con espacio estable.
4. Cada canción conserva su payload y posición dentro del mismo bloque. Si la respuesta entrega más de tres relacionadas asociadas, mostrar las primeras tres y expansión local «Mostrar las N relacionadas»; no descartar las demás. «Ver todo» remoto es una acción distinta, visible sólo con endpoint real.
5. Debajo del módulo, «Vuelve a escucharlo» con Die Hard, DNA. y Swimming Pools (Drank) en la fixture de referencia. Mantener su título, orden y ocurrencias cuando la sección exista. No extraer una cuarta relacionada desde allí.
6. Luego siguen «Más resultados» o las secciones/títulos que entregue el proveedor, con el orden mixto recibido. Esta área ocupa el ancho útil sin repartirse en dos columnas de secciones independientes.
7. Con C inferior al mínimo de división, la identidad se vuelve horizontal o apilada y las relacionadas pasan debajo dentro del mismo módulo. «Vuelve a escucharlo» sigue después del grupo completo.

**Interacciones:** nombre/imagen abren el artista; Aleatorio y Mix ejecutan sus endpoints reales. Play en una relacionada reproduce esa ocurrencia; más abre su menú. Reproducir un tema de «Vuelve a escucharlo» usa su propio payload, aunque comparta ID con otra ocurrencia.

**Aceptación específica:** división visible a 1440 con sidebar abierta en ambas apps si el tamaño de texto lo permite; fallback legible a 960; orden del módulo y secciones idéntico al cambiar ancho; ninguna mezcla entre relacionadas y personalización. Sin relación explícita en el contrato se representa el grupo secuencial, sin adivinar roles por título/ID.

### Captura de álbum — «to pimp a butterfly» / To Pimp A Butterfly

**Objetivo:** identificar el álbum oficial, poder abrirlo o reproducirlo y distinguirlo de canciones, vídeos y otras colecciones de nombre parecido.

1. Cabecera común. En la fixture «Álbumes» encabeza los chips como en la captura; el producto respeta el orden real.
2. Principal horizontal a todo el ancho: portada cuadrada de 112–144, título de 24–28 con hasta varias líneas si hacen falta, tipo álbum, artista y año cuando estén disponibles. El título no se confunde con los singles de nombre similar presentes más abajo.
3. Reproducir y Aleatorio se alinean a la derecha cuando caben, con apertura del álbum mediante título/portada y un menú de más según capacidades. El diseño usa el mismo componente base del principal de canción y adapta tamaño de imagen, datos y acciones.
4. Esta captura no tiene tracklist asociada dentro del principal. El módulo se presenta como franja completa, sin panel vacío ni relleno con pistas obtenido de los primeros resultados.
5. Debajo, conservar la lista mixta de referencia: Alright, Kendrick Lamar, You Ain’t Gotta Lie (Momma Said), King Kunta, Hood Politics y las ocurrencias posteriores, según lo recibido. Que una canción pertenezca al álbum no prueba que el proveedor la haya asociado al bloque principal.
6. Si una respuesta futura trae relacionadas explícitas dentro de ese bloque, reutilizar el panel y la adaptación del artista, conservando el orden. La entrega inicial de esta captura se valida sin relacionadas.

**Interacciones:** portada/título abren la página del álbum; Reproducir y Aleatorio usan identidad/acción del álbum y sus parámetros, no la primera canción de la búsqueda. Canciones de la lista inferior conservan su comportamiento independiente y metadatos originales. Los controles de portada no interceptan la apertura del menú ni la navegación del texto.

**Aceptación específica:** nombre completo legible, artista/año sin datos deducidos, acciones sin desbordar al reducir ancho; reproducción de la colección correcta; ninguna tracklist reconstruida ni resultado desplazado al panel derecho. Si faltan acciones reproducibles pero hay destino de álbum, queda disponible Abrir.

### Composición compartida de los tres casos

| Zona | Canción | Artista | Álbum |
|---|---|---|---|
| Principal | Identidad + acciones, franja completa | Identidad/acciones izquierda + relacionadas explícitas derecha si caben | Identidad + acciones, franja completa |
| Relacionadas | Ausentes en la referencia | Tres del mismo bloque; expansión si llegan más | Ausentes en la referencia |
| Personalización | Sólo si llega como sección propia | «Vuelve a escucharlo» debajo, si llega | Sólo si llega como sección propia |
| Resultados posteriores | Secuencia mixta del proveedor | Secuencia mixta del proveedor | Secuencia mixta del proveedor |
| Poco ancho | Acciones debajo de identidad | Identidad → relacionadas → secciones | Acciones debajo de identidad |

Las tres páginas comparten componentes y reglas; los datos del bloque determinan la composición. No hay layouts elegidos comparando la consulta con nombres como «Kendrick» o «TPAB». Los nombres de las capturas sirven para fixtures de aceptación.

### Regla de adaptación al ancho

Sea **C** el ancho útil del contenido, una vez descontados sidebar, paneles, márgenes y safe areas. Usar medición del contenedor; valores iniciales:

| C | Presentación inicial |
|---|---|
| Menos de 680 | Principal apilado o identidad compacta, acciones debajo; relacionadas a continuación. Filas con dos líneas, duración y más; datos secundarios bajo el título |
| 680–959 | Principal horizontal; relacionadas debajo dentro del mismo grupo. Mostrar metadatos adicionales sólo si caben |
| 960–1319 | División interna aproximada 44/56 con gap 24 si hay relacionadas; acciones pueden formar dos líneas |
| 1320 o más | Misma jerarquía; principal 40–44%, resto relacionadas. Filas aprovechan columnas y carruseles muestran más tarjetas |

Además del umbral, exigir mínimos medidos: identidad útil de al menos 360 y panel asociado de al menos 440, más separación. Si las etiquetas, tamaños accesibles o localización no caben, volver a la disposición anterior. 960 es un punto de partida, no una promesa de que todos los idiomas caben igual.

Evitar un máximo global de 760–900 para todos los resultados. Explorar una ampliación gradual del módulo principal, con un techo candidato de 1440 útiles y centrado después; las filas conservan columnas de lectura acotadas y pueden usar el espacio restante para metadatos. El carrusel puede usar el ancho restante. Este techo y las proporciones de la tabla son hipótesis propias de Side B, no medidas inferidas de YouTube Music. Comparar lectura a 1920/2560 antes de fijarlas; no agrandar tipografía o separaciones indefinidamente.

### Filas, tarjetas y menús

- Resultados mixtos: una secuencia vertical, mínimo 58–64 de altura. Imagen 42–48, título y créditos con destinos independientes; la identidad visual de artista es circular y colección cuadrada.
- Lista de canciones homogénea: considerar la tabla nativa virtualizada de Mac; no forzar una tabla de álbum/duración sobre artistas, perfiles y colecciones mezclados.
- Con C amplio y datos suficientes: explorar portada + título/créditos (aprox. 45–55%), álbum/contexto (25–30%), duración y acciones en una cola de ancho estable. Son proporciones de prueba, opcionales por densidad y tipo de sección; validar lectura antes de fijarlas. No dejar todos los datos apilados en los primeros 200 mientras sobra ancho vacío.
- Si no hay dato para una columna, no rellenar con «desconocido» repetido ni títulos deducidos. No desplazar las acciones al aparecer el hover; reservar su espacio compacto.
- Carrusel real: tarjetas con portada y jerarquía de entidad, no filas de 290 disfrazadas de tarjetas. Mantener orden y todos los elementos; flechas/scroll accesibles. No convertir automáticamente cualquier lista en carrusel.
- Menú contextual: reutilizar la política existente por entidad. Reproducir, mezcla, siguiente, cola, me gusta, biblioteca, playlist, navegación y compartir sólo según capacidad. No prometer suscripción/edición/guardar por tener un título de acción.
- El menú de Windows conserva su ancho independiente, ajuste a bordes y submenús que invierten dirección; Mac conserva NSMenu. La fila reserva únicamente el botón de más de 28–32 y su zona de interacción. El menú completo no forma una columna de 320 permanente.
- Portada/texto, reproducción y más son controles hermanos. Abrir el menú no reproduce; reproducir no navega. Acciones esenciales disponibles con foco y teclado, además de hover; probar menú contextual y Shift+F10 donde corresponda.
- Mantener player flotante de Side B y padding inferior suficiente. No copiar la barra de reproducción completa de YouTube Music.

## Contrato y arquitectura necesarios

El contrato de PLAN-015 ya conserva chips, corrección, secciones y sus layouts, acciones opacas y continuaciones. No se vuelve a construir el buscador ni a pedir `/search` por cada tecla.

Brechas que resolver antes del principal definitivo:

1. **Principal y relacionadas.** `layout = top` y arrays paralelos `items`/`songs` no ofrecen por sí solos roles inequívocos para todas las variantes. Revisar fixtures de respuestas: representar identidad principal y relacionadas explícitamente si el parser pierde esa asociación. Fallback: dibujar el grupo secuencial, sin heurísticas por nombre ni primer ID coincidente.
2. **Identidad de ocurrencia.** Conservar un ID estable por ocurrencia y el payload tipado de su canción. Las proyecciones actuales unen arrays por posición/ID; una futura unión discriminada por elemento puede evitar ambigüedad. No deduplicar repeticiones legítimas ni reordenarlas.
3. **Ámbitos.** El parser actual selecciona una pestaña y omite las ocultas; no expone un contrato de navegación de ámbitos. Para incorporarlos, modelar selección/destino/params y probar catálogo, biblioteca y subidas con estados vacío, sin sesión y sin acceso. No sintetizar parámetros a partir del texto.
4. **Metadata y acciones.** Auditar qué subtítulos/atribuciones/contadores y destinos sobreviven el parseo. Tipar semántica de acciones reconocidas; no ejecutar por comparación de rótulos traducidos. Campos ausentes son opcionales.
5. **Tipos no soportados.** Auditar vídeo, episodio, podcast y perfil antes de mostrarlos como filtros o entidades reproducibles. Una tarjeta navegable sin reproducción puede ser válida; un botón Play sin payload válido no.

Contrato objetivo para esta entrega: una colección aditiva de entradas por sección con identidad estable de ocurrencia, rol `primary / related / row`, tarjeta y payload de canción asociado cuando exista. Conservar temporalmente `items`/`songs` para compatibilidad. Los roles provienen de la estructura parseada antes de aplanarla; no de posiciones o IDs comparados en la UI. Un principal inequívoco habilita el módulo destacado. Roles ausentes o varios principales ambiguos mantienen la representación secuencial del grupo. El límite visual de tres relacionadas pertenece a la interfaz y no recorta el contrato.

La presentación pertenece a componentes específicos de la página: principal, relacionadas, sección/carrusel, fila y cabecera. Sugerencias, Spotlight y TopNav comparten proyecciones/acciones, pero conservan sus tamaños, foco, IME y límites de popover. No reutilizar la fila rápida como principal aumentando sólo su peso tipográfico.

### Mapa de implementación por capa

| Capa | Archivos actuales | Trabajo previsto |
|---|---|---|
| Parser compartido | `core/crates/innertube/src/models/search.rs` | Conservar el origen de identidad principal y filas asociadas de `musicCardShelfRenderer`; actualmente `card_shelf_main` y `rows(contents)` terminan aplanados. Validar también respuestas planas/continuaciones |
| Contrato compartido | `core/crates/sideb-core/src/search.rs` | Extensión aditiva con roles por ocurrencia y asociación al bloque, o índices equivalentes inequívocos; card y payload de canción conservan su vínculo. Sin tamaños de UI ni decisiones por consulta |
| Bindings y DTO | `apple/SideBCore/Sources/SideBCore/`, `windows/src-tauri/src/search_page.rs`, `windows/src/lib/types.ts` | Propagar la misma semántica a ambas apps, regenerar bindings mediante el flujo existente; conservar contrato previo durante transición |
| Presentación Apple | `ProviderSearchPageView.swift`, `ProviderSearchProjection.swift`, `ProviderSearchRows.swift`, `SearchView.swift` | Integrar principal específico y relacionadas, medir ancho interior y reutilizar acciones/menús existentes. Propuesta de componente nuevo: `ProviderSearchPrincipalView.swift`; nombre final al implementar |
| Presentación Windows | `components/search/SearchView.svelte`, `search/provider-rows.ts` | Extraer principal y relacionadas; eliminar limitación exclusiva de 760 del principal a favor de reglas por C. Propuestas nuevas: `SearchPrincipal.svelte` y `SearchRelatedResults.svelte` |
| Filas y acciones | `QuickResultComponents.swift`, `SearchSongRow.svelte`, políticas de menú y controllers/player actuales | Compartir lógica de destinos/capacidades, reservar botones de fila y conectar payload de cada ocurrencia; no copiar handlers divergentes |
| Localización y verificación | Catálogos ES/EN y suites actuales de búsqueda | Etiquetas de expansión/locales, accesibilidad y fixtures comunes; pruebas dirigidas al contrato, comportamiento y tres composiciones |

Los nombres propuestos no indican archivos ya creados. Tras el contrato y las fixtures, Apple y Windows pueden avanzar en paralelo; los cambios compartidos tienen un único responsable de integración.

Cambios del core sólo para una pérdida compartida, con lectura previa de sus instrucciones y compatibilidad temporal con consumidores existentes. Los detalles de ancho y composición se resuelven en cada interfaz; no incorporar píxeles ni decisiones de shell al contrato Rust.

## Estados e interacción

- Escribir: sugerencias ordenadas, texto con runs y entradas de historial remoto existentes. No anticipar una búsqueda completa por cada carácter.
- Enviar/seleccionar categoría/corrección: nueva identidad de consulta; preservar params y sesión. Respuestas antiguas no reemplazan la vista actual.
- Carga inicial: esqueleto con la geometría del principal y filas, sin resultados ficticios. Cambio de filtro: indicar actualización sin permitir acciones sobre una consulta incompatible.
- Vacío: mensaje asociado a consulta/categoría y acción para editar o quitar filtro si existe. Sesión requerida: estado específico del ámbito, cuando se incorpore.
- Error: mantener resultados válidos cuando corresponda y reintento localizado. Error al paginar no borra principal ni secciones previas.
- Paginación: anexar donde indica la continuación, conservando ocurrencias y endpoint. No confundir continuidad de búsqueda con `next` de reproducción.
- Navegar y volver: recuperar consulta, categoría, scroll y selección de la misma cuenta; no restaurar contenido privado de otra sesión.
- Historial remoto: borrar sólo por acción explícita con token de la sesión vigente. El prototipo y las pruebas sintéticas no ejecutan borrados remotos.
- Foco: orden identidad → acciones → relacionadas → secciones, consistente con lectura. Escape, composición IME, rangos UTF-16 y ownership del editor conservan las regresiones cubiertas por FIX-196.

## Secuencia de ejecución

### Etapa 0 — Fixtures y contrato mínimo

- [x] Fixtures sintéticas de artista, canción, álbum, sin principal y ocurrencias repetidas; regresiones de corrección/filtro/continuación en PLAN-015. Se mantiene pendiente la comparación autenticada de las tres consultas.
- [x] Documentar la asociación principal/relacionadas y los tipos/acciones realmente disponibles.
- [x] Conservar roles y payload por ocurrencia antes del aplanado; propagar entradas aditivas en bindings/DTO/proyecciones y mantener compatibilidad. Ámbitos pueden quedar en una entrega posterior sin bloquear el nuevo layout.
- [x] Aprobar fixtures base S01, A01 y B01 de la tabla inferior y negativos con ocurrencias repetidas; resolver el contrato antes de dividir tareas de interfaces.
- Salida: fixtures y un contrato suficiente para dibujar sin adivinar roles ni destinos.

### Etapa 1 — Componentes y composición adaptable

- [x] Crear principal de artista/canción/álbum, relacionadas y fallback secuencial.
- [x] Componer primero franja de canción S01 y franja de álbum B01 sobre la misma base; luego identidad de artista y panel A01. Mantener adaptaciones por tipo sin condicionar la UI al texto de la consulta.
- [x] Aplicar adaptación por C y ajuste real de controles; conservar tokens 48/40/32, materiales y player.
- [x] Filas existentes con destinos independientes y acciones estables; carruseles reales con portadas de 180 en Mac y tarjetas comunes en Windows. Columnas adicionales siguen siendo exploración opcional, no requisito del principal.
- [x] Decisión de cabecera: conservar el viewport vigente de cada plataforma (Mac desplaza la cabecera, Windows conserva editor/categorías sobre el scroll). No ampliar este rediseño al ownership del editor; TopNav/Spotlight siguen accesibles. Unificar el scroll entre plataformas queda como exploración de shell separada, con aceptación nativa.
- Salida: las tres consultas de referencia y casos sin principal funcionan en fixtures, con sidebar abierta/cerrada.

### Etapa 2 — Integración funcional en ambas apps

- [x] Conectar principal, menú, play, cola, biblioteca y destinos a las políticas/payloads existentes.
- [x] Mantener chips, corrección, continuaciones, aislamiento de cuenta y estados de error.
- [x] Regresiones automáticas de navegación/editor/acciones conservadas y aprobadas; aceptación física completa pendiente en la matriz.
- [ ] Comprobar que un cambio de ancho/sidebar sólo redistribuya contenido: conserva consulta, filtro, selección, foco compatible, scroll y estado de expansión de relacionadas.
- [x] Incorporar ámbitos sólo si etapa 0 entregó destinos comprobables; de lo contrario excluirlos de esta entrega.
- Salida: misma capacidad y orden en Mac/Windows con adaptación nativa de shell/menú.

### Etapa 3 — Validación y entrega revisable

- [x] Pruebas de contrato significativas: roles, ocurrencias duplicadas, acciones opacas, pestañas/params si se incorporan, continuaciones y respuesta tardía/cambio de cuenta.
- [x] Pruebas de comportamiento: Play no navega, menú no reproduce, filtro actualiza solicitud correcta y retorno restaura estado compatible.
- [ ] Revisión visual nativa en matriz inferior, accesibilidad/teclado y cuenta real; no sustituir por snapshots del prototipo.
- [x] Runner oficial Mac y frontend Windows aprobados; FIX-257/PAR-042 y este plan actualizados. Build/runtime nativos Windows requieren su host compatible y permanecen pendientes.
- Salida: build revisable con validación de las dos apps; no marcar Windows nativo/audio/cuenta verificados por haber pasado sólo frontend.

No asignar fechas artificiales antes de conocer la pérdida de estructura del contrato. Paralelizar Apple y Windows después de acordar fixtures/roles, con un integrador dueño del contrato y sin escrituras simultáneas en archivos compartidos.

## Fixtures de aceptación para las tres capturas

Fixtures sintéticas de contrato y presentación implementadas para S01/A01/B01, expansión A02, duplicados A03 y negativos G01. No son respuestas autenticadas de las consultas ni acreditan toda la matriz nativa; G02/G03 combinan pruebas dirigidas y regresiones previas.

| ID | Contenido | Resultado esperado |
|---|---|---|
| S01 | Principal DUCKWORTH., sin relacionadas; lista con Duckwrth y otra ocurrencia de la canción | Franja completa con acciones y lista ordenada; ningún panel lateral ni deduplicación |
| S02 | Canción sin token de biblioteca o con metadata parcial | Acciones según capacidad; título/créditos disponibles sin datos inventados ni espacios reservados para acciones ausentes |
| A01 | Principal Kendrick; tres relacionadas explícitas; «Vuelve a escucharlo» separado | División interna cuando cabe, luego personalización y resultados; límite entre grupos intacto |
| A02 | Artista con cinco relacionadas del mismo bloque | Tres iniciales y expansión local de las cinco; no se modifica la respuesta ni se confunde con «Ver todo» remoto |
| A03 | Mismo videoID en relacionada y sección posterior, con payloads distintos | Cada ocurrencia ejecuta su propio payload/acción y conserva posición |
| B01 | Principal TPAB sin relacionadas; canciones y artista en resultados posteriores | Franja de álbum y lista mixta; no convertir resultados en tracklist |
| B02 | Álbum con destino válido, sin Play/Aleatorio ejecutables | Apertura disponible; sin acciones reproducibles falsas |
| G01 | Sin principal, roles ambiguos o metadata/imagen ausente | Fallback secuencial y placeholder existente; todos los elementos conservados |
| G02 | S01/A01/B01 en C679/680/959/960, títulos largos, ES/EN y texto ampliado | Cambio de composición al caber realmente; sin pérdida de orden, foco ni acciones |
| G03 | Cambiar consulta/cuenta durante carga, paginación fallida y navegación de vuelta | Guards existentes intactos, reintento y restauración de estado de la cuenta compatible |

La aceptación nativa compara estructura y comportamiento con las referencias, no cifras de reproducciones ni listas idénticas a una sesión web tomada en otro momento.

## Matriz de aceptación

| Eje | Casos y criterio |
|---|---|
| Ancho | Ventanas 960, 1280, 1440, 1920 y 2560; sidebar abierta/cerrada y panel adicional si existe. Medir C. Sin clipping ni columnas ilegibles; división sólo si cabe |
| Alto | 640 y alturas mayores; foco, últimas filas y acciones accesibles por encima del player; sin cabecera desproporcionada |
| Contenido | Las tres consultas, título/autor/álbum largos, metadatos ausentes, muchos chips, varios principales inesperados, duplicados, sin resultados y tipos no soportados |
| Orden | Secuencia y ocurrencias del proveedor idénticas tras adaptar ancho; ninguna pérdida por «mostrar tres» ni reagrupación local |
| Acciones | Canción/colección/artista y capacidades ausentes; menú junto a cada borde, submenús y clic/foco sin reproducción accidental |
| Entrada | Ratón, trackpad, teclado, lector de pantalla, ampliación de texto, español/inglés e IME; foco visible y desplazamiento de chip seleccionado |
| Estado | Carga/error/reintento, cambio rápido de consulta/filtro/cuenta, paginación repetida, navegación y vuelta; datos y tokens ligados a sesión |
| Plataforma | Swift/AppKit nativo y Tauri/Windows nativo; frontend/build no acredita audio ni rendimiento real |


## Ejecución — 2026-10-22, FIX-257

- El parser de `musicCardShelfRenderer` conserva `primary_item_index` y `related_item_indices` antes de aplanar. Son índices de ocurrencia explícitos del mismo bloque; contratos aditivos Swift/Tauri y adaptadores antiguos conservados. El filtro de vídeos remapea todos los índices; si elimina el principal, no promueve otra fila.
- Principal de canción/álbum de ancho completo, con portada, identidad y acciones de 40; artista con panel asociado sólo desde C960. En anchos menores se apila el bloque. El ancho se mide dentro de la página, tras sidebar/márgenes. Más de tres relacionadas se expande localmente sin descargar ni recortar datos; personalización y secciones posteriores siguen fuera del bloque.
- Proyecciones validan tipo/orden/rango/unicidad de roles. Con roles ausentes o inválidos se mantiene la secuencia completa. Las repeticiones legítimas usan su payload de canción; no se unen todas por el primer videoId ni se deduplican.
- Reutiliza las políticas de menú y reproducción de la app; parámetros del proveedor opacos, destinos de créditos independientes y menú sin reproducción accidental. Play de respaldo sólo si no existe una acción reproducible del proveedor y la interfaz dispone de capacidad. Ámbitos remotos permanecen fuera de alcance hasta existir destinos comprobados.
- Cabecera y columnas opcionales: decisión documentada en etapa 1. No se modifican navegación, foco/IME, sesión, player ni su padding inferior.
- Integración y revisión del agente principal sobre código de subagentes Luna. Evidencia final: [Mac0159](../builds/macos/build-0159/BUILD.json),990 ejecutadas aprobadas/17omitidas; Windows453aprobadas/1omitida, check0/0/build aprobado. Tres focales Swift y22 de búsqueda Windows aprobados. Detalle y límites en [FIX-257](../FIXES.md#fix-257)/PAR-042. Ocho capturas nativas sintéticas en C618/C1098 revisadas en `/tmp/sideb-plan016-qa/`; no equivalen a cuenta real ni a Windows/WebView2.

## Antecedente de la fase de planificación

- [x] Comparar las tres capturas y distinguir jerarquía, ámbitos, categorías y secciones.
- [x] Auditar geometría real y menús de ambas apps, contrato y antecedentes.
- [x] Proponer tres opciones, recomendación, medidas iniciales, límites y secuencia.
- [x] Preparar comparación estructural interactiva con las tres consultas. Sus datos son fixtures de diseño; no consulta una cuenta ni reproduce audio.
- [x] Fijar la dirección elegida «Principal y relacionadas» y detallar canción/artista/álbum con composición, interacciones, componentes y aceptación específica.
- [x] Implementación del principal y relacionadas de etapas 0–2; pruebas/build Mac de etapa 3 aprobados; aceptación nativa ampliada pendiente. La matriz con cuenta/Windows nativo permanece pendiente y no se acredita con fixtures.

Verificación de la comparación: sintaxis y DOM, tres variantes × tres consultas, 46 interacciones locales de filtros, menú/Escape, reproducción simulada y sidebar; sin solicitudes externas. No equivale a una revisión de geometría en navegador ni QA nativa. La apertura de la previsualización local en el navegador fue rechazada por su política de URL; no se intentó evadirla. Las medidas finales quedan sujetas a la matriz de aceptación.

La comparación se muestra en el chat; el plan versionable queda autocontenido. Los enlaces de referencia principales son PLAN-015/FIX-256/PAR-042, PLAN-007/FIX-174 (controles), PLAN-008/FIX-178/179 (página), FIX-196 (editores/Spotlight) y los componentes actuales `ProviderSearchPageView.swift`, `QuickResultComponents.swift`, `SearchView.svelte`, `SearchSongRow.svelte`, `ContextMenu.svelte`, `SideBControls.swift`, `tokens.css` y `core/crates/sideb-core/src/search.rs`.

## Seguimiento macOS — FIX-258 (2026-10-23)

El usuario pidió corregir Mac primero y retomar Windows más adelante. [Apple PLAN-027](../apple/plans/PLAN-027-search-density-and-performance.md) y [FIX-258](../FIXES.md#fix-258) registran la revisión de ambas apps abiertas, las tres consultas reales en0159/0160 y las correcciones de densidad/alineación/reciclado. Mac0161 compilada:1011 pruebas aprobadas,17 omitidas, firma/hashes verificados. El último binario espera `SecItemCopyMatching` durante restauración de sesión; su revisión final con cuenta queda pendiente. Las trazas exploratorias no certifican mejora de FPS. Windows no incorpora este seguimiento todavía; no se presenta como paridad visual/rendimiento alcanzada.


### Seguimiento de interacción macOS — FIX-259

[FIX-259](../FIXES.md#fix-259) corrige el salto introducido por el preview inline de FIX-258 mediante un host flotante nativo fuera de la altura medida del header. Spotlight conserva los píxeles de la página seleccionada mientras mantiene suspensión/AX oculto; scrim y vidrio originales sin cambio. Build0162 compilada con fuentes estables, firma estricta y10/10 hashes;1015 pruebas aprobadas,17 omitidas,0 fallos, además de21 focales. Revisión con cuenta real en0162 completada: foco sin desplazar resultados, clic en sugerencia flotante, fondo de Inicio visible bajo Spotlight y restauración con Escape. Esto retoma la comprobación antes pendiente por el arranque de0161. Evidencia `/tmp/sideb-fix244-after/`. Windows se mantiene pospuesto; no se certifican FPS/audio ni QA manual de todas las páginas retenidas.


### Seguimiento de ancho y controles macOS — FIX-246

[FIX-246](../FIXES.md#fix-246) retira el tope1280 de la columna nativa, usa margen28 y centra controles40/32 por renglón. Las categorías conservan scroll/params/selección y sólo desvanecen extremos con overflow. QA0164 detectó recorte de dibujo tras cambiar sidebar;0165 termina layout de celdas antes de actualizar sus hosts y solicita repintado. Focal final24/24, runner0165 con1024 aprobadas/17 omitidas/0 fallos, fuentes estables/firma estricta/10 hashes y405 inputs Mac verificados. Cuenta real: homecoming en960×680 con sidebar abierta/cerrada y1512×949 tras zoom, acciones visibles/centradas y categorías sin corte negro. Windows sigue pospuesto en PAR-042. Evidencia `/tmp/sideb-fix246-review/`.
