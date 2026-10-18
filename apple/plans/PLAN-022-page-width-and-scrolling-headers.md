# PLAN-022: ancho de Explorar y cabeceras que acompañan el scroll

- Fecha: 2026-10-17 (America/Montevideo).
- Estado: implementado e integrado mediante tres subagentes; build-0132 y verificaciones aprobadas, QA visible parcial completada en copia aislada. Biblioteca con cuenta/VoiceOver/trackpad físico pendientes.
- Pedido: usar subagentes para corregir las diferencias visibles en las capturas macOS antes de compilar la próxima build. Explorar debe aprovechar el mismo ancho y margen que Inicio y las otras páginas; retirar el eyebrow pequeño y la descripción, dejando un único título localizado Explorar/Explore del mismo tamaño y a la misma altura que los otros títulos. Biblioteca y Búsqueda deben desplazar su parte superior con el contenido, como Inicio.
- Alcance: UI e integración Apple de Explorar/Biblioteca/Búsqueda y sus regresiones. Conservar navegación, categorías, acciones, preferencias, filtros, foco, paginación, identidad y viewport acotado de listas virtualizadas. Mantener shell/TopNav/barra flotante. No modificar fuentes Rust ni los cambios locales Windows de FIX-207; evaluar paridad sin atribuir al destino un defecto no observado.
- Referencias: capturas aportadas; FIX-120/121 (Explorar), FIX-168/172/179/180 (Biblioteca y búsqueda), FIX-185/186 (páginas retenidas/viewport), FIX-196 (búsqueda integrada), PAR-012/PAR-027/PAR-028/PAR-031. Contrastar con código vigente y antecedentes antes de cambiar.

## Reparto y contratos

1. Subagente Explorar: `Views/Explore/{ExploreView,ExploreCatalogGridView}.swift` y pruebas nuevas de presentación. Comparar márgenes/ancho/título con Inicio/Biblioteca; conservar catálogo virtualizado y acciones. No editar archivos de Biblioteca, Búsqueda, shell o registros compartidos.
2. Subagente Biblioteca: `Views/Library/LibraryView.swift`, `LibraryCollectionViewport.swift` sólo si hace falta, y regresiones propias. Integrar cabecera en el mismo scroll de contenido sin crear dos scrolls verticales anidados ni desvirtualizar catálogos. Conservar offsets por tab/cuenta, filtros, grid/lista y gestos.
3. Subagente Búsqueda: `Views/Search/SearchView.swift` y regresiones propias. Hacer que título/campo/filtros y resultados compartan scroll; conservar sugerencias, foco, recientes, acciones y todas las categorías. Sin cambiar Spotlight ni TopNav salvo necesidad comprobada que debe informar al integrador.
4. Integrador: revisar contratos/diffs, coordinar las comprobaciones Swift para no competir por `.build`, registrar fixes únicos/paridad y verificar la build final con las fuentes ya estabilizadas. Los subagentes preparan pruebas sin lanzar builds simultáneas.

## Pasos y aceptación

- [x] Registrar el plan antes de implementar y compilar; conservar cambios locales preexistentes.
- [x] Contrastar capturas, geometría actual y antecedentes. Explorar limita1400pt y centra; a1512pt deja88pt frente a28pt de Inicio. Se adopta la referencia Inicio28pt lateral/24pt superior/título40pt en caja52pt. Biblioteca/Búsqueda mantienen sus métricas38,4pt existentes y sólo cambian propiedad del scroll. FIX-179/180 documentan ese alineado anterior.
- [x] Corregir Explorar: mismo margen útil a anchuras estrecha/media/amplia, un título localizado, sin eyebrow/descripción redundantes; no recortar ni inutilizar controles.
- [x] Corregir Biblioteca: cabecera y controles se desplazan junto con Todo/catálogos/canciones; viewport de listas sigue acotado, sin doble scroll; acciones/estado/offsets conservados.
- [x] Corregir Búsqueda: cabecera y controles se desplazan junto con resultados/estados; foco/sugerencias, recientes y acciones conservados.
- [x] Integrar y revisar regresiones geométricas/de scroll y límites de rendimiento; evaluar Windows en lectura y actualizar PARIDAD.
- [x] Ejecutar pruebas focales y comprobaciones apropiadas; compilar sólo después de integrar todos los cambios mediante `node Scripts/build-version.mjs macos` y conservar build numerada, fuentes estables, firma y hashes.
- [x] Cerrar FIXES/plan con evidencia real, ruta exacta de build y límites de QA física. No publicar una nueva release como parte de este ajuste sin pedido.

## Límites

Una build y las pruebas no certifican fluidez física, audio ni aceptación visual del usuario. Usar renders nativos aislados y geometría cuando sirvan para comprobar la disposición; no intervenir en la cuenta ni reproducción personal. No limpiar builds/prototipos/cachés ni modificar la release1.2.1 publicada.

## Decisiones de integración

- Biblioteca y Búsqueda tienen varios renderers: SwiftUI para páginas/secciones, NSCollectionView para catálogos y NSTableView para canciones. La cabecera se incorpora al documento de cada renderer, sin envolver una tabla virtualizada en un ScrollView vertical externo.
- `NativeTrackTableView` ya ofrece `scrollingHeader`/altura medida y conserva el hosting/campo cuando cambian filas; ambas páginas reutilizan ese contrato. Biblioteca añade un único hosting de cabecera al documento de su colección, conservando celdas recicladas y offsets.
- Cambios preexistentes FIX-207 Windows preservados; snapshot de342fuentes core/Windows/bindings tomado antes de este pedido para verificar que sigan iguales. Pruebas y compilación Swift coordinadas por el integrador al terminar las ediciones.
- La revisión independiente detectó una regresión de la integración: el estado vacío de Canciones filtradas ocultaba el error parcial y Reintentar. Se corrigió y quedó cubierto por el render vacío→error→recuperado antes de la build final.
- Evaluación Windows sólo en lectura: Explorar ya ocupa el ancho del contenedor pero conserva eyebrow/eslogan/subtítulo; Búsqueda conserva cabecera sticky separada de resultados. Biblioteca tiene composición propia y requiere evaluación nativa por modo. Registrar en PAR-012/PAR-027/PAR-028, sin declarar port ni validación física del destino.

## Verificación e intentos

- Primer focal: producto compilado; fixture Search usaba el nombre importado incorrecto del protocolo de accesibilidad. Corregido a `NSAccessibilityProtocol`, sin cambio de producto.
- Segundo focal: Explorar y virtualización de catálogos aprobados; Biblioteca desplaza cabecera/categorías en sus ocho combinaciones y conserva foco al vaciar canciones/catálogos. Búsqueda conserva borrador/foco al alternar canciones/videos y al cargar, y alinea el campo en los seis filtros. Faltaron dos búsquedas AX en fixtures y un mock de login: `SideBCore(noPointer)` invocaba el método real desde las tarjetas y causaba SIGTRAP. Corregidos recorrido AX (subviews + hijos accesibles), materialización de footer y stub `isLoggedIn`, sin atribuir el trap al producto.
- La compilación detectó captura fuerte implícita en el callback de medición de la nueva cabecera de Biblioteca. Se hizo explícita la captura débil externa e interna, evitando un ciclo del hosting.
- Tercer focal:25XCTest aprobadas y1SwiftTesting; sólo fallaron dos comprobaciones AX de botones virtuales en ventanas ocultas. Todas las mediciones de ancho, scroll, foco, carga y listas de5.000 aprobaron: Explorar máximo15celdas; Biblioteca15grid/10lista.
- Cuarto focal confirmó que el árbol AX de la ventana oculta no publica esos botones SwiftUI, aun recorriendo hosts/protocolos mínimos/atributos informales. Se sustituyen los dos bloques de prueba por render real del footer vacío→error→recuperado y altura/contenido del dropdown con foco/selección conservados, más recarga/commit por modelos reales. No se afirma click físico ni VoiceOver validado; se retiran helpers AX obsoletos de fixtures. Producto conservado.
- Quinto focal: cuatro XCTest Biblioteca y cinco de Búsqueda aprobadas; la última esperaba cierre del preview tras invocar sólo el modelo mientras el campo seguía enfocado. La acción real de página deja el editor antes del commit; el fixture replica ese límite y el sexto focal aprueba la última prueba. En conjunto27XCTest distintas y1SwiftTesting aprobadas, sin fallos pendientes. Renders nativos aislados a730/1100/1512pt y cabeceras antes/después de desplazar en `/tmp/sideb-plan022-layout-review`, revisados por el integrador.
- `node Scripts/build-version.mjs macos` terminó en build-0132 con compiled/sourceChangedDuringBuild=false.761 pruebas ejecutadas aprobadas (188Rust/236XCTest/337SwiftTesting;7Rust ignoradas/7Swift omitidas), diez hashes de artefactos y firma ad hoc deep/strict verificados; arm64/macOS15 mínimo, versión pública1.2.1/build14 conservada.
- Al terminar la build:342archivos core/Windows/bindings iguales al snapshot previo y `git diff --check` aprobado. FIX-208/PAR-012/PAR-027/PAR-028 actualizados; sólo documentación de cierre editada después de compilar. En ese momento todavía no se había abierto la app y sugerencias/Reintentar/VoiceOver/trackpad/FPS quedaban pendientes. La continuación de QA visible se detalla debajo; sin instalación, commit, push ni nueva release.

## Continuación: QA con ventana visible

- Se conserva la entrega original y se crea copia en `builds/macos/build-0132/layout-diagnostics/Side B Layout QA.app`, identificador `com.fefucho.SideB.HomeLab.PageLayout0132`, datos aislados mediante configuración HomeLab ya existente. Sólo metadatos/firma de esa copia cambian; no hay recompilación ni cambios de producto. Las dos versiones previas del usuario permanecen abiertas.
- Inicio/Explorar comparados por UI: mismo origen y escala del título, Explorar ocupa el ancho del contenido con sidebar abierta y cerrada, sin eyebrow/eslogan/subtítulo.
- Búsqueda con consultas públicas drake/frank ocean en invitado: Todo, tabla de Canciones y catálogo de Álbumes desplazan título/campo/filtros con resultados. Vuelta arriba conserva controles y consulta. Sugerencias se muestran dentro del header nativo y el clic sobre frank ocean confirma consulta, cierra panel y presenta canciones nuevas. Sin reproducción.
- Biblioteca invitado presenta título/categorías/estado coherentes; al caber el contenido completo no necesita scroll. Sus ocho modos con datos mantienen evidencia de geometría/foco/scroll de las pruebas; recorrido con cuenta y botón Reintentar siguen pendientes, junto con VoiceOver/trackpad físico/FPS.
- Sin defectos nuevos en este recorrido; no requiere otra build. Copia QA cerrada por su propio menú al terminar y cierre comprobado por proceso; bundles anteriores conservados. Diez hashes del bundle original y342fuentes protegidas siguen iguales. Evidencia adicional en `layout-verification.json`; capturas de UI en el historial de herramientas de este chat.

## Entrega

- Bundle: `builds/macos/build-0132/Side B.app`.
- Evidencia: `builds/macos/build-0132/{BUILD.json,build.log,layout-verification.json}` y renders/diagnósticos de layout en la misma build.

## Publicación posterior1.2.2

Pedido explícito de publicar ambas apps: FIX-209, fuentes8b8e135/tagv1.2.2, versión1.2.2/build15. Mac hospedado aprueba761pruebas (188Rust/236XCTest/337SwiftTesting;7Rust ignoradas/7Swift omitidas), fuentes estables, diez hashes y firma ad hoc; descarga pública verificada. [Release1.2.2](https://github.com/fefucho/sideb/releases/tag/v1.2.2) Latest2026-10-18 incluye ambos sistemas y checksums; FIX-210 resuelve rutas del publicador sin recompilar. Build0132 local previa1.2.1 conservada. No modifica los límites de QA con cuenta/VoiceOver/trackpad físico/FPS de este plan.
