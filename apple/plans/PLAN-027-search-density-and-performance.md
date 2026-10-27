# PLAN-027 — Búsqueda macOS: densidad, alineación y reciclado

- Fecha: 2026-10-23 (America/Montevideo).
- Estado: implementados FIX-258/244/245/246, build0165 compilada y1024 pruebas aprobadas. Revisión final con cuenta real completada en0165. Sólo macOS; Windows se retoma después por pedido del usuario.
- Objetivo: corregir el resultado visual de FIX-257 y trasladar las mecánicas de viewport/reciclado de Inicio y Biblioteca a los resultados mixtos de búsqueda.
- Antecedentes: PLAN-016 compartido, FIX-102/121/172/208/241/242 y PAR-042. Core, proveedores, ranking, shell, player y código Windows se conservan.

## Diagnóstico

La revisión de escritorio encontró dos instancias: `/Applications/Side B.app` (1.2.7/build20, presentación agrupada anterior) y la build local0159 (presentación de principal/relacionadas). No se equiparan ambos binarios. En0159 se observó principal de artista demasiado alto, título repetido encima del bloque, acciones lejos del borde derecho y mucho aire entre resultados sin título de sección. Las capturas originales de YouTube Music se usan para jerarquía/densidad, sin copiar sus coordenadas físicas.

El código de0159 reconstruía índices de canciones por cada fila, filtraba ocurrencias restantes al evaluar secciones y usaba pilas SwiftUI anidadas para resultados/paginaciones. Las secciones sin título también montaban su cabecera vacía y separación exterior. Esto explica huecos concretos; no permite atribuir todo el lag sin medir.

## Implementación

- [x] Auditar app abierta, ambas presentaciones y antecedentes de optimización.
- [x] Preparar mapa lineal de canciones por ocurrencia una vez por página recibida; conservar setVideoId, créditos, acciones y duplicados.
- [x] Aplanar entradas visuales sin insertar cabeceras vacías ni repetir el título del principal. Filas58, cabeceras44, carruseles232; altura del principal medida.
- [x] Un solo NSScrollView con NSTableView y hosting SwiftUI reutilizado sólo para filas montadas. `sizeThatFits` explícito del viewport; cabecera persistente dentro del documento.
- [x] Revisiones separadas de consulta/cuenta, snapshot y reproducción: nueva consulta reinicia; append/expansión conservan offset; playback actualiza visibles. Ningún estado de scroll publicado por píxel a SwiftUI.
- [x] Columna compartida para cabecera/filas, margen28; FIX-246 retira el tope1280 y aprovecha todo el ancho disponible; principal más compacto, acciones agrupadas a la derecha, artista horizontal con relacionadas.
- [x] Mantener editor/foco/IME, filtros, corrección, continuaciones y menús por ocurrencia. FIX-259 corrige el preview inline de FIX-258: sugerencias flotantes clicables ancladas al campo, fuera de la altura medida del header.
- [x] Aprobar pruebas de integración, geometría, expansión/resize y 5.000 resultados.
- [x] Revisar en0160 la app completa con las tres consultas, sidebar abierto/cerrado y scroll. Corregir también el inset automático16pt de AppKit y la invalidación de alturas durante append detectados al revisar.
- [x] Medir perfil de ejecución y distinguir trabajo eliminado, fluidez percibida y FPS no certificados.
- [x] Build oficial0161, firma/hashes y registro FIX-258/PAR-042.
- [x] Retomar la revisión con cuenta real: completada en0162 al abrir desde Finder.0161 había quedado esperando `SecItemCopyMatching`, corroborado con dos muestras; ese intento anterior no se contabiliza como búsqueda ejecutándose. En0162 se verificaron sugerencias flotantes clicables sin desplazamiento y Spotlight sobre Inicio, incluida restauración al cerrar.

## Verificación prevista y límites

Fixtures nativas: principales de canción/artista/álbum, metadatos ausentes, títulos largos, ES/EN, anchos618/1098, mismo ID repetido con payload distinto, resize y expansión local. Viewport:5.000 entradas, desplazamiento hasta4500, montaje acotado, cabecera única, append sin salto y consulta nueva al inicio. La prueba real debe comprobar posición del editor, alineación de principal/filas, menús y destino de créditos.

Time Profiler inicial de0159 conservado en `/tmp/sideb-search-perf-20261023/before-0159.trace`,20s, consulta Kendrick Lamar. Una llamada larga de automatización de gestos agotó el timeout; no se considera un recorrido A/B idéntico ni un benchmark de FPS. La evidencia instrumental final y los límites se anotarán al cerrar.

La build se conservará sin instalar ni reemplazar las instancias anteriores. No se ejecutan mutaciones de biblioteca ni reproducción de audio para validar el layout.

## Resultado y límites

Runner0161:282 Rust,248 XCTest y481 Swift Testing aprobadas (1011 ejecutadas,17 omitidas,0 fallos). Incluye foco/selección/sugerencias durante cambios de página, no sólo identidad del host. El append conserva la altura112pt de un principal fuera de pantalla y la posición de la misma fila; cambiar su revisión permite medir210pt. La celda real comparte origen/ancho con la cabecera usando tabla `.plain`, como Inicio/Biblioteca.

Perfil posterior0160/Kendrick,20s:2555 muestras main,1393ms AX y1162ms sin AX;702ms graph,71ms lazy/stack,101ms medición y97ms tabla nativa inclusivos. Un gesto down0.25 confirmado. El recorrido inicial agotó timeout y difiere del posterior: estos números no demuestran una reducción porcentual ni certifican FPS. La proyección lineal cacheada y el montaje de menos de40 celdas para5000 entradas sí están comprobados por pruebas; no equivalen a un benchmark de animación.

[BUILD0161](../../builds/macos/build-0161/BUILD.json): `compiled`, release, fuentes sin cambios durante build; firma estricta y10 hashes verificados.0160 y0159 conservadas. Cierre documental posterior al empaquetado. Detalle de intentos y evidencia local en [FIX-258](../../FIXES.md#fix-258).

## Regresiones de interacción — FIX-259

El usuario señaló que enfocar el buscador desplazaba la página y Spotlight ocultaba el fondo. El primer caso proviene del preview inline añadido en FIX-258. El segundo se reprodujo sobre Inicio en0160: la suspensión de la página ocultaba su viewport nativo; sobre Search el fondo permanecía montado. Scrim/vidrio originales se conservan.

Implementación: host flotante en el documento, fuera de la medición del header, con hit testing sobre resultados y seguimiento de geometría nativa; retención visual separada de actividad/AX para páginas detrás del modal translúcido. Fullscreen sigue ocultando contenido. Focal final21/21 aprobadas, capturas nativas sintéticas revisadas en `/tmp/sideb-fix244-layout/`: preview superpuesto sin desplazar filas y Home retenido bajo el scrim. Build oficial0162:1015 aprobadas,17 omitidas,0 fallos; `compiled`, fuentes estables durante build, firma estricta y10/10 hashes verificados. Revisión en app completa con cuenta real: panel flotante abre sin mover principal/filas y recibe clic en consulta; Spotlight conserva carátulas/contenido de Inicio bajo el scrim original y Escape restaura la página. Evidencia de escritorio en `/tmp/sideb-fix244-after/`. Biblioteca/Explorar cubiertos por compilación y retención compartida, sin atribuirles QA manual en esta ronda. Sin certificación nueva de FPS/audio. Cierre documental posterior al paquete. [FIX-259](../../FIXES.md#fix-259) registra el cierre.


## Cierre exterior y prioridad visual de música — FIX-245

- [x] Reproducir en0162 el panel de `homecoming` con seis completados antes de las canciones y el foco persistente tras clic en título exterior.
- [x] Añadir cierre nativo fuera del campo/panel sin consumir el clic, borrar draft ni enviar consulta.
- [x] Limitar a tres texto/historial con consulta, preservando todas las entidades, payloads y orden; vacío conserva historial completo. Página/Spotlight/TopNav comparten lista de render y teclado.
- [x] Focal integrado15/15 y runner0163 con1018 aprobadas/17 omitidas/0 fallos. Build compiled/fuentes estables/firma estricta/10 hashes verificados. Cuenta real: tres completados con canciones visibles, clic exterior sin salto ni pérdida del borrador/no submit, clic único navega a Inicio y Atrás restaura Search; Spotlight comparte el recorte. Evidencia `/tmp/sideb-fix245-review/`. [FIX-245](../../FIXES.md#fix-245).

Windows mantiene implementación previa y queda pospuesto; PAR-042 registra el límite visual pendiente.


## Ancho disponible y controles — FIX-246

- [x] Comparar0163 con Inicio/Explorar y las dos capturas del usuario: tope1280 y alineación superior de acciones40/32 identificados.
- [x] Usar ancho del viewport menos28pt por lado para cabecera/filas; retirar tope alternativo1336 de SearchView.
- [x] Centrar controles por renglón sin cambiar tamaños ni wrapping; tira de categorías con borde transparente gradual sólo donde queda contenido y sin efecto oscuro del sistema26+.
- [x] Focal final24/24: resize/scrollers/acciones/scroll horizontal y controles reales durante seis cambios de ancho sin scroll; renders compactos y amplios revisados. QA0164 detectó repintado antiguo tras cerrar sidebar, resuelto con layout previo de celdas e invalidación del host en0165.
- [x] Build0165 compiled/fuentes estables/405 hashes de inputs Mac/10 hashes de artefacto/firma estricta;1024 aprobadas/17 omitidas/0 fallos. Cuenta real homecoming en960×680/sidebar abierta-cerrada y1512×949/zoom nativo: margen28, Play/menú centrados/visibles y categorías sin corte negro. Arranque esperando llavero se resolvió al abrir normalmente desde Finder. [FIX-246](../../FIXES.md#fix-246); Windows diferido en PAR-042.
