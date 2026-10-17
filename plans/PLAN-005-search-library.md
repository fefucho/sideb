# Spotlight con recientes y Biblioteca personal

- Fecha: 2026-10-10 (America/Montevideo).
- Estado: implementado en Apple/Windows; comprobaciones automatizadas aprobadas; aceptación física pendiente (2026-10-11).
- Objetivo: que Buscar recuerde lo que el usuario decidió hacer y presente resultados previsibles; llevar Biblioteca al nivel visual de álbumes y playlists.
- Alcance: comportamiento equivalente en Apple y Windows, con integración propia de cada plataforma y APIs existentes.
- Exclusiones: cambiar el motor de reproducción, reemplazar Spotlight por otra entrada, sincronizar recientes locales con YouTube, modificar el core protegido o inventar fechas de incorporación a Biblioteca.
- Relacionado: [enlaces de invitados en títulos](PLAN-006-featured-artist-links.md). Registro: FIX-165/166 y PAR-027/028; evidencia al final.

## 1. Decisión de producto: conservar el Spotlight

Buscar en la sidebar y el atajo actual siguen abriendo el modal. El modal tiene tres estados: **Recientes**, **Sugerencias mientras escribís** y **Cargando/sin resultados/error**. Enter desde el campo o «Ver todos los resultados» abre la página completa que ya existe.

La página completa sirve para explorar; el modal sirve para volver a algo o poner música rápidamente. El concepto visual anterior de búsqueda es una referencia de jerarquía, no una propuesta de eliminar este flujo.

### Qué se guarda exactamente

| Acción | Entrada en Recientes de Side B | Resultado |
|---|---|---|
| Escribir `Kanye` sin elegir nada | Ninguna | Se muestran sugerencias |
| Escribir `Kanye` y reproducir directamente una sugerencia | La canción elegida | Conserva la activación de radio actual; no agrega `Kanye` |
| Enter en el campo o «Ver todos los resultados» | La consulta `Kanye` | Abre la búsqueda completa |
| Enter sobre una fila seleccionada explícitamente con teclado | Lo mismo que el clic en esa fila | Una canción se reproduce; no se confunde con enviar la consulta |
| Reproducir desde la página completa después de Enter | Conserva la consulta ya guardada | No agrega además la canción por ese flujo |
| Abrir artista, álbum o playlist desde una sugerencia | Ninguna, en esta primera entrega | Navega al detalle |
| Agregar una sugerencia a la cola, sin reproducirla ahora | Ninguna | Conserva la acción de cola |
| Recargar, reintentar, paginar, volver atrás o cambiar filtro | Ninguna nueva | No cambia la fecha de un reciente |
| Volver a abrir una consulta reciente | Esa consulta pasa al primer lugar | Abre resultados completos |
| Reproducir una canción reciente | Esa canción pasa al primer lugar | Usa la misma reproducción/radio que una sugerencia |
| Reproducción automática del siguiente tema | Ninguna | Esto no es el historial de escuchas |

Decisión para el MVP: dos tipos de entrada, consulta y pista. Las sugerencias de video reproducibles usan el mismo tipo de pista, conservando su indicador de video. Colecciones visitadas o reproducidas quedan fuera del historial del buscador por ahora.

### Cuándo se confirma una entrada

- **Consulta:** al envío explícito de texto no vacío, una vez por interacción, aunque termine sin resultados o con error. Así se puede retomar o reintentar. Una búsqueda abierta programáticamente desde otro componente no se considera automáticamente un envío del usuario.
- **Pista:** cuando la activación solicitada desde Spotlight alcanza el estado de reproducción correspondiente a esa pista; no basta un hover ni comenzar a resolver una URL. No esperar un umbral de escucha. Una orden rechazada, cancelada o reemplazada antes de iniciar no crea entrada.
- Enlazar el origen de la acción, la sesión y la generación de reproducción. Confirmar el `videoId` esperado y descartar eventos tardíos. Verificar los callbacks reales de AVPlayer/libmpv antes de elegir el punto de confirmación; una promesa resuelta de transporte no demuestra inicio.
- Centralizar este seguimiento para fila, botón play, tarjeta principal y menú contextual «Reproducir ahora». No observar indiscriminadamente todos los cambios de canción.
- Si el usuario elige una pista que ya está reproduciéndose y la acción se acepta sin reiniciarla, actualizar el reciente una vez. Una selección repetida se mueve arriba; no genera duplicados.

## 2. Presentación y teclado del modal

1. Una apertura nueva del Spotlight muestra campo vacío y Recientes. Separar su borrador de la consulta de la página completa: abrir/cerrar el modal no borra los resultados que están detrás. Después de Escape, la próxima invocación comienza otra búsqueda; esta es una decisión explícita de UX que sustituye la recuperación automática del texto anterior de Windows.
2. Con texto, mostrar sugerencias de red. Al limpiar el campo, volver a Recientes sin una petición vacía.
3. Lista mixta en orden de uso: consulta con icono de lupa y texto; pista con portada, título y artista. Etiqueta discreta de tipo cuando ayude. Eliminar una entrada mediante acción accesible de fila; «Borrar recientes de Side B» con posibilidad de deshacer.
4. Guardar hasta 50 entradas por cuenta, mostrar unas 6–8 filas según altura disponible y permitir scroll para las restantes. Sin una segunda página de historial en esta entrega. El modal puede crecer frente al placeholder vacío actual, respetando barra de reproducción y ventana mínima.
5. Sin recientes: explicación breve de que aparecerán las búsquedas enviadas y las canciones reproducidas desde aquí. Sin recomendaciones inventadas ni una pantalla vacía enorme.
6. Con resultados: un principal, hasta tres canciones asociadas si hay datos y un bloque compacto de coincidencias adicionales. Presupuesto inicial: hasta ocho resultados accionables más «Ver todos»; omitir duplicados y secciones vacías.
7. Conservar Escape, restauración del foco al cerrar, navegación por flechas, Tab, lector de pantalla y foco visible. No seleccionar automáticamente una canción de modo que Enter en el campo deje de buscar.
8. Al completar una respuesta no mover el foco, el scroll ni la selección que el usuario ya esté usando. Una nueva consulta invalida el conjunto anterior inmediatamente.

## 3. Arquitectura del historial local

Crear un servicio `SearchRecentStore` en Apple y un controller/store equivalente en Windows. Servicios implementados con los nombres de este contrato. Compartir esquema y fixtures de comportamiento; no introducir una nueva API en core.

Contrato persistido versionado:

```text
RecentEntry
  key, kind: query | track, lastUsedAt
  query: texto visible y clave normalizada                         [query]
  track: videoId, title, artists, artistRuns, thumbnail,
         album/artist IDs disponibles, isVideo/isUpload            [track]
```

- Clave de consulta: espacios exteriores/interiores normalizados y case-fold; conservar texto visible. No fusionar palabras distintas por eliminación indiscriminada de acentos.
- Clave de pista: identidad del proveedor y `videoId`, con el ámbito necesario para uploads. No deduplicar por título ni alterar las identidades/ocurrencias de la cola.
- Partición por identidad estable de cuenta/canal activo; invitado separado. No usar solo el nombre visible del usuario. Cambiar sesión invalida tareas y vacía inmediatamente la proyección visible antes de cargar la nueva partición.
- Guardar solo metadatos suficientes para mostrar y reactivar mediante APIs actuales. No persistir cookies, URLs de stream ni tokens de acciones temporales. Las portadas usan el sistema de caché actual y placeholder si caducan.
- Escritura atómica/serializada, validación de esquema al leer y recuperación ante contenido corrupto. Si hay varias ventanas Apple, un store de cuenta compartido coordina escrituras; el estado del modal sigue siendo por ventana.
- No migrar automáticamente todo el historial de escuchas a estos recientes: tiene otro significado. Eliminar recientes no borra escuchas ni historial remoto.
- Track unavailable: informar el fallo y ofrecer quitar la entrada o buscar por título/artista. No sustituirla automáticamente por una grabación distinta.

### Diferencia con `recordHistory`

El core actual usa `record_history` para decidir si una búsqueda lleva contexto de cuenta. Las previews son anónimas; las búsquedas enviadas pueden registrarse en YouTube. El nuevo store local es independiente.

Introducir un origen explícito en la integración (`submit`, `recentQuery`, `preview`, `filter`, `refresh`, `navigationRestore`, `artistResolution`) para no deducir intención a partir de una carga. Solo `submit`/`recentQuery` registran consulta local y solicitan el registro remoto ya existente. Previews y búsquedas técnicas de artistas siguen sin registro.

Apple actualmente llama `searchAll(recordHistory: true)` dentro de `commitSearch`, que también puede activarse al aparecer o refrescar la vista. Separar el envío del usuario de la obtención de datos. Windows ya pasa un booleano; sustituir convenciones dispersas por el origen explícito en el controller.

Límite del contrato actual: `false` también retira personalización. Preferir restaurar resultados cacheados y evitar reconsultas automáticas innecesarias; un reintento sin registro puede tener otro orden del proveedor. No prometer identidad exacta entre preview anónima y búsqueda confirmada, ni cambiar core para añadir una combinación que todavía no existe.

## 4. Resultados que se entiendan

Problemas observados: las categorías del preview se reordenan según el primer resultado; la página completa puede interponer videos antes de álbumes/artistas; las respuestas mixtas, canciones y videos se esperan en conjunto. Hay varias proyecciones y falta una regla transversal de deduplicación.

Propuesta:

- Definir una proyección de presentación por plataforma con el mismo contrato: principal, canciones asociadas y secciones. Respetar orden del proveedor dentro de cada tipo. El contrato ya agrupa categorías; no afirmar que se recupera un ranking global que no está disponible.
- Página «Todo»: principal + canciones, después artistas, álbumes, playlists y videos. Filtros siempre en posiciones estables: Todo, Canciones, Artistas, Álbumes, Playlists, Videos. Sin secciones vacías de relleno.
- Deduplicar el mismo recurso por tipo e ID entre principal y bloques siguientes de «Todo». No colapsar canción y videoclip distintos por el nombre; tampoco aplicar deduplicación a ocurrencias legítimas en playlists o cola.
- Publicar cada bloque cuando llega, con error/reintento local al bloque. No retrasar canciones útiles por una consulta lenta de videos.
- Reutilizar respuesta mixta para la primera presentación; cargar datos adicionales por demanda o progresivamente según el filtro. Ninguna petición por tecla fuera del debounce actual de 250 ms.
- Mantener altura reservada razonable durante carga; no cambiar el principal mientras el usuario lo apunta solo porque llegó una respuesta secundaria. Reemplazar el conjunto al cambiar consulta o confirmar una nueva búsqueda.
- No añadir reranking con IA. La mejora inicial es jerarquía, estabilidad, menos duplicados y rapidez de presentación.

## 5. Biblioteca: aplicar la dirección visual acordada

La biblioteca actual tiene título, pestañas y contenido básico, mientras álbumes y playlists tienen una cabecera con portada y jerarquía más fuerte. Mantener esas funciones y construir una vista personal coherente con los detalles.

### Estructura

- Dirección corregida por el usuario el 2026-10-11: retirar collage, ambientación y subtítulo decorativo. Cabecera compacta con título, crear playlist y refrescar; categorías de 48 pt/px con iconos inmediatamente arriba de las herramientas. Reutilizar Liquid Glass Apple y acrylic Windows sólo en controles, con fallback accesible.
- Buscar en la biblioteca en una cápsula separada; ordenar y cambiar de vista a la derecha, con adaptación estrecha. Todo muestra una fila horizontal por sección para evitar una tarjeta huérfana en una segunda fila; el catálogo completo conserva lista/cuadrícula.
- Añadir **Todo** como portada de Biblioteca: Fijados arriba y secciones cortas de playlists, álbumes y artistas con «Ver todos». Acceso claro a Canciones guardadas; no incrustar una lista ilimitada entre tarjetas.
- Conservar filtros Canciones, Playlists, Álbumes y Artistas. Primera visita: Todo; después recordar el último filtro por cuenta. Vista de cuadrícula/lista para colecciones; canciones conservan su tabla y acciones.
- Barra de herramientas con «Buscar en tu biblioteca», ordenar y vista. Distinguirla visualmente del buscador global: nunca abrir Spotlight al escribir aquí.
- Fijar/desfijar mediante menú y acción accesible. Fijados son atajos locales por cuenta, con orden manual y clave tipo+ID; no modifican la biblioteca remota. Un fallo de red no borra un fijado.
- Reutilizar tarjetas y estados de hover/play/menú existentes. No crear otra familia de tarjetas solo para esta pantalla. Recordar filtros, vista, orden y posición al volver de un detalle.

### Datos y estados honestos

- Ordenar por nombre y, donde exista, artista. «Orden original» conserva la secuencia recibida antes de ordenar en la integración. Actualmente álbumes se ordenan al cargarlos: preservar esa secuencia por separado si se ofrece esta opción.
- No ofrecer «Agregados recientemente» con datos que no tienen esa fecha. Tampoco mostrar un total de canciones cargadas como si fuera el total completo de la cuenta.
- Canciones tiene paginación; el filtro local debe indicar «Buscando en canciones cargadas» y ofrecer «Buscar en el resto» para recorrer continuaciones de forma incremental, cancelable y limitada. Mostrar progreso, resultados parciales y «Continuar» al alcanzar el presupuesto; nunca «No existe en tu biblioteca» con páginas pendientes.
- Para álbumes/artistas/playlists, filtrar el conjunto expuesto por las APIs actuales y verificar su cobertura durante implementación. Si una API no ofrece continuaciones, no prometer indexación completa ni inventar un endpoint.
- Consultas/filtros/carga cambian de generación; las respuestas de otra cuenta no pueden poblar portada, índice, collage o fijados.
- Diferenciar cuenta desconectada, colección vacía, filtro sin coincidencias, carga inicial, actualización conservando contenido y error recuperable. Cada estado tiene una acción apropiada.

## 6. Mapa de integración y antecedentes

| Área | Puntos actuales |
|---|---|
| Spotlight Apple | [SpotlightSearchModal.swift](../apple/Sources/SideB/Views/Search/SpotlightSearchModal.swift), [SearchViewModel.swift](../apple/Sources/SideB/ViewModels/SearchViewModel.swift) |
| Resultados Apple | [SearchView.swift](../apple/Sources/SideB/Views/Search/SearchView.swift), [QuickResultComponents.swift](../apple/Sources/SideB/Views/Search/QuickResultComponents.swift) |
| Búsqueda Windows | [preview.ts](../windows/src/lib/search/preview.ts), [controller.ts](../windows/src/lib/search/controller.ts), [SpotlightSearch.svelte](../windows/src/lib/components/search/SpotlightSearch.svelte), [+page.svelte](../windows/src/routes/+page.svelte) |
| Biblioteca Apple | [LibraryView.swift](../apple/Sources/SideB/Views/Library/LibraryView.swift), [LibraryViewModel.swift](../apple/Sources/SideB/ViewModels/LibraryViewModel.swift), [CollectionDetailHeaderView.swift](../apple/Sources/SideB/Views/Detail/CollectionDetailHeaderView.swift) |
| Biblioteca Windows | [LibraryView.svelte](../windows/src/lib/components/library/LibraryView.svelte), [account/controller.ts](../windows/src/lib/account/controller.ts) |
| Contrato consultado, sin cambios previstos | [endpoints.rs](../core/crates/innertube/src/endpoints.rs) |

Antecedentes en [FIXES](../FIXES.md): FIX-047 (generaciones/ventanas), FIX-053 (foco y fullscreen), FIX-086 (búsqueda y radio). Son referencias históricas; contrastar sus garantías con el código y las pruebas actuales.

## 7. Ejecución por entregas

- [x] Revisar implementación actual y definir semántica consulta/pista con la corrección del usuario.
- [x] **A — Recientes funcionales:** implementar store versionado, orígenes de acción, confirmación de playback, aislamiento de cuentas y deduplicación; integrar estado vacío/recientes en ambos Spotlights.
- [x] **B — Resultados:** proyección estable, presupuesto del modal, deduplicación por recurso, publicación progresiva y errores parciales. Conservar radio, menús y teclado.
- [x] **C — Biblioteca visual:** cabecera compacta sin collage, categorías glass superiores, Todo, componentes comunes, toolbar y estados de carga/vacío/error. Mantener rutas y acciones existentes.
- [x] **D — Biblioteca funcional:** fijados, preferencias, filtro local consciente de paginación, orden y restauración del scroll.
- [ ] **E — Validación y entrega:** ejecutar pruebas por plataforma, validación visual/nativa, registrar fixes y paridad; actualizar este plan con evidencia y builds solo si se solicitan.

Cada entrega debe quedar utilizable por separado. Prioridad A → B → C → D. El resolver de invitados puede seguir un plan independiente; no bloquear recientes esperando esa función.

## 8. Criterios de cierre

- [ ] Caso central: escribir Kanye y reproducir una sugerencia guarda exactamente esa pista; cerrar y reabrir Spotlight permite reproducirla otra vez sin escribir Kanye.
- [ ] Caso Enter: guarda Kanye una sola vez; reproducir en resultados, volver, cambiar filtro, refrescar y reintentar no crean entradas adicionales ni las mueven arriba.
- [ ] Enter de campo y Enter de fila tienen semánticas distintas, verificadas con teclado y lector de pantalla.
- [ ] Fallo/cancelación de reproducción, dos clics rápidos, eventos tardíos, autoplay y cambio de cuenta no crean recientes incorrectos.
- [ ] Reiniciar conserva entradas; eliminar/deshacer, límite de 50, datos corruptos y varias ventanas no pierden datos válidos ni cruzan cuentas.
- [ ] Respuesta lenta de videos no bloquea canciones; resultados de una consulta anterior nunca reaparecen; foco y principal no saltan al interactuar.
- [ ] Biblioteca conserva reproducción/radio, cola, like, menús, creación de playlists y navegación al cambiar de vista. Filtros no afirman ausencia sobre páginas sin cargar.
- [ ] Revisión visual en ventana mínima/amplia, portada ausente, títulos largos, ES/EN, reducción de movimiento y fullscreen.
- [x] Apple: pruebas relevantes de store/orígenes/generaciones/proyección y `swift test --package-path apple`. Windows: fixtures equivalentes y `pnpm check`, `pnpm test`, `pnpm build`; comprobación nativa Windows separada.
- [ ] Medir peticiones por flujo y ausencia de trabajo por fila durante scroll. Registrar mediciones reales; este plan no afirma mejoras de rendimiento comprobadas.

## Evidencia de implementación (2026-10-11)

Tres subagentes GPT-6.1 Sol/medium implementaron búsqueda, Biblioteca e invitados con revisión cruzada del integrador. Fuentes del core intactas. Los casilleros A–D acreditan código, no aceptación física de todas las superficies.

- Store local por cuenta, 50 recientes mixtos, escritura segura, eliminar/deshacer y recuperación de pistas fallidas. Intención ligada al item/token AVPlayer o generación/evento nativo Windows; no se confirma al resolver URL. Elegir la pista actual sonando conserva reproducción.
- Resultados con proyección equivalente, ocho acciones primarias en Spotlight, deduplicación por tipo/ID y errores/reintentos independientes. Flechas recorren filas primarias; acciones secundarias siguen accesibles con Tab.
- Biblioteca con collage, Todo, fijados canónicos reordenables, lista/cuadrícula, orden original, filtro y recorrido cancelable de ocho páginas de canciones. Colecciones declaran cobertura del proveedor: APIs internas recorren hasta veinte páginas sin exponer un índice completo.
- Preferencias por cuenta; consulta/scroll durante navegación. Cambio de cuenta limpia contenido e invalida cargas y rollback de mutaciones tardías.
- Fixture de componentes Windows revisado en navegador: recientes mixtos, sugerencias por bloques, alturas, portadas limitadas, filtro/fijado y Escape restaurando foco. Fixture temporal retirado. No equivale a WebView2 nativo ni a cuenta real.
- Primera suite Windows: 320 aprobadas, cero fallos, una prueba nativa omitida en Mac; check 0 errores/0 advertencias y build frontend aprobados. Revalidación final tras revisión cruzada en curso.
- Build-0076: 182 Rust aprobadas/7 live ignoradas; compilación Swift aprobada, tests detectaron jerarquía/hover de Inicio tras incorporar enlaces. Intento conservado como fallido; no entregable. Regresiones nuevas de recientes, proyección y Player pasaron. Corrección y nueva build pendientes del cierre de verificación.

Pendiente de aceptación física: cuenta/proveedor/audio, teclado y lector de pantalla nativos, ventana mínima, ES/EN, reducción de movimiento, consumo y FPS. No se afirma que haya mediciones de rendimiento ni que las APIs indexen toda una cuenta.

### Revalidación posterior a revisión cruzada

Build-0077 compilada y firmada, fuentes estables durante la build: 618 pruebas aprobadas (182 Rust, 140 XCTest, 296 Swift Testing), siete live Rust ignoradas. Corrige jerarquía/hover de Inicio sin debilitar assertions. Windows: 334 aprobadas/0 fallos/1 fixture sólo Windows omitido, check0/0 y build frontend aprobado. Fixture navegador adicional: ArrowDown enfoca play, Enter reproduce, enlace de invitado de reciente navega y Escape restaura Buscar. Fixtures temporales retirados.

Última corrección antes de entrega: caché negativa parcial del prefetch ya no bloquea búsqueda contextual al clic, incluso si comparte una petición en curso; reutiliza ausencia exacta fresca para consultar sólo el contexto, y repite exacta si expiró. Regresiones de ambos lenguajes y de activación AppKit por teclado/accesibilidad agregadas. Revalidación en build-0078 aprobada; ver cierre final.

### Cierre automatizado final

Build final [build-0078](../builds/macos/build-0078/BUILD.json): compilada release arm64, SDK27.0/mínimo15, firma verificada, sourceChangedDuringBuild=false y diez hashes comprobados. **622 pruebas aprobadas** (182 Rust/140 XCTest/300 Swift Testing;7 live Rust ignoradas). Incluye regresiones de caché parcial/completa, vuelo simultáneo, expiración, cancelación de consumidores, cuenta/rollback y activación AppKit sin puntero. Windows: **337 aprobadas/0 fallos/1 fixture nativo omitido en Mac**, check0 errores/0 advertencias y build frontend aprobados; aviso de chunk grande conservado. Catálogos730 ES/EN actuales. Fuentes core/bindings sin cambios. Cierre documental posterior, sin cambios de código tras la build. No se abrió/instaló/publicó ni se cambió versión pública. Cuenta real, audio audible, FPS y runtime Windows siguen pendientes.

### Refinamiento solicitado tras la primera entrega — 2026-10-11

- [x] Retirar collage/hero y repetir el lenguaje de controles de álbum/playlist; categorías superiores grandes, herramientas agrupadas y secciones horizontales en Todo. Mantener funciones y preferencias.
- [x] Restaurar créditos ausentes de canciones asociadas al artista superior, priorizando metadata explícita y sin reemplazar colaboradores. Fixture de metadata incompleta en ambas plataformas; no atribuir una causa al proveedor sin payload real.
- [x] Revisar vistas a 730/1100 pt/px con datos sintéticos; filtro/fijados/lista, crédito recuperado y enlace de invitado independiente en navegador.
- [x] Verificación automatizada completa y build de refinamiento; aceptación física separada. FIX-168/169; hover FIX-170, PLAN-006. La captura nativa de NSHostingView permite comprobar layout, pero no certifica refracción final de Liquid Glass ni interacción con cuenta real.

Revisión de gestos del integrador: el historial global sólo respeta propietarios horizontales explícitos. Las nuevas categorías/filas Apple usan el marcador existente de Inicio/Explorar y lo desactivan bajo fullscreen; regresión sobre LibraryView real comprueba zonas y desactivación. Build-0079 intermedia aprobó 627 pruebas/firma/fuentes estables; Windows 340/0/1, check0/0 y build frontend aprobados. Nueva build final con ajuste de scroll en curso.

La regresión de gesto aprobó con LibraryView montada y dibujada en NSWindow (el host separado dejaba ancestros de scroll con bounds cero). Verifica propietarios por sección, espacio exterior que conserva historial y desactivación bajo fullscreen; mantiene las comprobaciones de routing reales.

Cierre del refinamiento: [build-0080](../builds/macos/build-0080/BUILD.json) compilada/firma válida/fuentes estables/diez hashes comprobados, 628 pruebas (182 Rust/140 XCTest/306 Swift Testing),7 live ignoradas. Windows340 aprobadas/0fallos/1omitida, check0/0 y build frontend aprobado. Catálogos730 ES/EN verificados, rutas de fixture retiradas y core/bindings intactos. FIX-168/169/170; cierre documental posterior sin cambios de código. Cuenta real, audio y Windows nativo pendientes.

### Rendimiento de categorías — 2026-10-11

- [x] Reemplazar grid/lista SwiftUI de Álbumes/Playlists/Artistas Apple por viewport nativo reciclado, siguiendo Novedades; mantener cabecera, rutas, menús, fijados, scroll y cuentas.
- [x] Evitar refiltrar/reordenar colecciones en cada actualización de scroll/reproducción.
- [x] Windows: conservar VirtualCatalog de Novedades para grid y reutilizar VirtualStack para listas; reservar altura real de títulos y pin.
- [x] Probar miles de tarjetas, reciclado, desplazamiento profundo, filtros y cambios de layout.
- [x] Verificación global y build versionada; medir FPS físicos por separado.

Seguimiento FIX-172/PAR-028. La falta de virtualización completa es un hallazgo de código; no constituye una medición de todos los factores del lag percibido.

Focales finales: siete XCTest de viewport y cinco de hover/gestos aprobadas;5.000/tipo máximo15grid/10lista con viewport1000×760. Primer intento detectó dirección horizontal implícita, corregida en producción sin relajar tests. Windows348/0/1, check0/0/build frontend y ocho tests de render2000 aprobados. Fixture navegador confirmó final1985–1999; no valida filtroprofundo/computedCSS. FIX-171/172, build global en curso.

Cierre FIX-171/172: [build-0081](../builds/macos/build-0081/BUILD.json) compilada release arm64, SDK27.0/mínimo15, firma verificada, fuentes estables y10hashes comprobados.635 pruebas Mac (182Rust/147XCTest/306Swift Testing,7live ignoradas); Windows348 aprobadas/0fallos/1omitida, check0/0/buildfrontend aprobados. Sin fuentes core/bindings modificadas; cierre documental posterior sin cambios de código. App final sin abrir/instalar/publicar. Cuenta real, FPS/Instruments y Windows nativo siguen pendientes.


Seguimiento 2026-10-11 — [FIX-173](../FIXES.md#fix-173): la prueba de éxito con AVPlayer reprodujo una canción sin crear recientes; se añadió confirmación correlacionada desde el observador de progreso existente y deduplicación por item. Integración final verifica persistencia, reanudación, una sola escritura y exclusión de reproducción fuera del buscador; las sugerencias del campo comparten el origen de Spotlight. Build-0082 compilada con fuente estable, firma/diez hashes verificados y636 pruebas aprobadas (182 Rust/147 XCTest/307 Swift Testing); Windows37 focales aprobadas. Cuenta/proveedor y aceptación física siguen pendientes; no sustituye los criterios manuales abiertos arriba.

### Alineación de acciones de Biblioteca — 2026-10-12 (FIX-180)

Mover crear playlist y refrescar desde la fila del título a la derecha de las categorías, centrados verticalmente. Eliminar la reserva derecha142 de la cabecera; margen38.4 compartido con búsqueda, ordenar y resultados. Categorías conservan desplazamiento horizontal independiente cuando el ancho no alcanza y acciones mantienen su espacio. Sin modificar comportamiento ni topnav. Build-0091 compiled/fuentes estables/firma/10hashes y646 pruebas ejecutadas aprobadas. CUA confirmó alineación y abrir/cancelar hoja sin crear playlist; captura `/tmp/sideb-library-build-0091.png`. Windows inspeccionado: acciones aún junto al título, port pendiente en su ámbito.
