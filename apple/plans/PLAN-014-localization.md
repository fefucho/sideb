# PLAN-014: español coherente e inglés seleccionable

- Objetivo: unificar primero la interfaz de Side B en español y añadir después inglés, con un selector de idioma al principio del panel de configuración existente y conservando reproducción, navegación, gestos, preferencias y rendimiento.
- Estado: implementado en FIX-131/build-0067, 2026-10-08 (America/Montevideo). Tres entregas Luna revisadas e integradas; 688 claves ES/EN, 562 pruebas aprobadas y QA aislada en ambos idiomas. Comprobaciones físicas y Windows pendientes, con límites registrados al cierre.
- Alcance: app Mac SwiftUI/AppKit, textos propios, menús, ayudas, accesibilidad, mensajes, plurales, formatos y empaquetado de recursos. Español predeterminado y respaldo; inglés se habilita al completar su traducción y comprobaciones.
- Exclusiones: cambios en los contratos/core Rust, motor de reproducción, idioma de las peticiones del proveedor, país de rankings, búsqueda del proveedor, nombres originales de contenido, traducción automática en ejecución, port Windows y publicación.
- Referencias: [PLAN-006](PLAN-006-home-settings.md), [PLAN-007](PLAN-007-home-recommendation-sources.md), [PLAN-011](PLAN-011-explore.md), [PLAN-012](PLAN-012-navigation-gestures.md), [PLAN-013](PLAN-013-fullscreen-home-performance.md); FIX-105/106/119/120/121/122/129.

## Hallazgos iniciales contrastados con el código

| Superficie | Estado observado | Consecuencia para la migración |
|---|---|---|
| `Views/Home/HomeSettingsPanel.swift`, `HistoryToolbarView.swift`, `SideBApp.swift` | Panel de «Configuración de Inicio» superpuesto, engranaje disponible en Inicio, oculto en otras rutas/fullscreen/búsqueda; preferencias de Inicio por sesión | Añadir idioma como preferencia global de la app, separada de las fuentes por cuenta, manteniendo la geometría y las condiciones de apertura actuales |
| `apple/Package.swift` | Sin recursos declarados ni `defaultLocalization`; no hay `.xcstrings`, `.strings` o `.stringsdict` de producto | Introducir recursos nativos y comprobar su resolución tanto con Swift Testing como en la app instalada |
| `Scripts/build-version.mjs` → `Scripts/build-macos.sh` | El flujo vigente copia ejecutable, icono y créditos; declara sólo `es` en Info.plist y no copia un bundle de recursos de SideB | Incluir el recurso de SwiftPM y ambos idiomas antes de firmar; una compilación que pasa no demuestra que la traducción llegue al usuario |
| `Scripts/build-app.sh` | Contiene otro camino de catálogos, con referencias como Kaset; no es la entrada del runner actual | Su existencia no prueba soporte de localización en nuestras builds. Trabajar sobre el flujo vigente y auditar el empaquetador de release cuando corresponda |
| `UI/ContextMenu/*`, `UI/AppMenuCommands.swift`, `Views/Common/*`, `Views/Home/HomeFeedCollectionView.swift` | Menús y celdas nativas reciben `String`, labels/tooltips se fijan también durante construcción/configuración | El entorno de SwiftUI no actualiza por sí solo estos textos. Necesitan una actualización explícita y acotada |
| `SearchViewModel.swift` | `SearchFilter`/`SearchCategory` usan textos españoles como `rawValue` e ID | Conservar los valores existentes; añadir una etiqueta traducible separada, sin cambiar selección o identidad al elegir idioma |
| `HomeRecommendationSettings.swift`, `HomeFeedPresentation.swift`, `HomeFeaturedPresentation.swift` | Clasificación, estilo, orden y preferencias de categorías dependen de títulos originales/aliases; algunos IDs tienen fallback al título | Traducir en la presentación después de clasificar. Conservar título crudo, aliases, ID, preferencias y orden; nunca alimentar la lógica con el título traducido |
| `HomeAlbumMetadata.swift`, `HomePlaylistMetadata.swift` | Resúmenes en español/«Playlist» ya formateados y guardados en memoria junto con datos | Mantener datos/caché de red; actualizar sólo el resumen visible según idioma para evitar textos viejos o nuevas consultas |
| `ExploreCatalog.swift` | Países nombrados con `Locale(identifier: "es")`; títulos/subtítulos propios y consultas editoriales están juntos | Traducir nombres y textos visibles, conservar código de país, selección, queries y claves de caché |
| `core/crates/innertube/src/models/context.rs` | El locale predeterminado del proveedor es `hl=en`, `gl=US`; charts tiene su contrato regional explícito | El idioma de interfaz es independiente del idioma del proveedor y de la región detectada. Cambiarlo no modifica peticiones ni cambia Uruguay a otro país |
| ViewModels/servicios | Mensajes propios ya resueltos como `String`, con `error.localizedDescription` incorporado en varios casos | Conservar la condición del error y presentar mensajes propios traducibles; los detalles externos requieren un tratamiento explícito, no una sustitución de palabras |

La inspección es un mapa inicial, no un inventario completo de cada literal. Las fixtures, logs, identificadores, símbolos, URLs y protocolos deben distinguirse de los textos visibles.

## Experiencia implementada

Se conserva el panel derecho, material, tamaño y comportamiento. Su encabezado es «Configuración»; dentro del área desplazable, la primera sección es «General», con «Idioma de la aplicación» y un selector nativo compacto. Opciones: **Español** y **English**, escritas en su propio idioma para que siempre se reconozcan. Debajo aparecen las opciones de **Inicio**, con separación visual.

English se habilita con el catálogo completo. Las etiquetas cambian en vivo y la elección se guarda entre ejecuciones, por instalación e independiente de cuenta. Valor ausente o inválido vuelve a español. Esta primera versión tiene dos opciones; «Seguir al sistema» queda fuera del alcance inicial. La prueba manual de varias ventanas/cambio de cuenta permanece pendiente.

Mantener inicialmente el engranaje en las mismas rutas donde existe hoy; hacerlo accesible desde todos los menús sería otra decisión de producto. Conservar los identificadores AX existentes y añadir uno estable para el selector, foco de teclado propio, Escape y la política de Espacio del panel.

## Arquitectura implementada

### Catálogo y recursos

La implementación usa `apple/Localization/fragments/*.json` como fuente editorial, con una sola entrada por clave y ES/EN obligatorios. El generador reúne un catálogo único `apple/Localization/Localizable.xcstrings`, con `sourceLanguage: es` y claves semánticas estables —por ejemplo `navigation.home`, `player.play`, `settings.language`— organizadas por superficie. La [guía de autoría](../Localization/README.md) describe el contrato. Una misma palabra puede necesitar claves diferentes si expresa acciones distintas. Cantidades, nombres interpolados y frases completas se traducen con argumentos tipados; singular/plural en el catálogo, sin concatenar fragmentos.

El flujo de SwiftPM nativo genera `.strings`/`.stringsdict` en `apple/Sources/SideB/Resources/{es,en}.lproj` mediante `xcrun xcstringstool`. Los recursos derivados se versionan y se comprueba que coincidan con el catálogo; `swift test --package-path apple` también funciona directamente. Sólo los fragmentos se editan a mano; catálogo y recursos son derivados. `node Scripts/sync-localizations.mjs` genera los productos; `--check` comprueba sin mutar fuentes y se ejecuta al empaquetar. `Package.swift` declara `defaultLocalization: "es"` y procesa esos recursos.

Se comprobaron nombres/rutas del recurso generado por SwiftPM, pluralización y reproducibilidad. El empaquetador copia el recurso del target de la app, valida idiomas/plurales y lo incluye en la firma. `L10n` prioriza el bundle dentro de `Contents/Resources`, cuya ruta se confirmó desde el ejecutable de una copia reubicada. Los bindings UniFFI permanecen intactos.

### Estado y resolución

- `AppLanguage` identifica idiomas con códigos estables `es`/`en`; `AppLanguageStore` observable pertenece a la app y existe también si falla el arranque del core. Persistencia mediante un `UserDefaults` inyectable, con dominio separado para HomeLab/pruebas. Ningún vínculo con cookies o preferencias por cuenta.
- Una fachada pequeña `L10n` resuelve claves/argumentos desde el recurso del idioma elegido y usa español como respaldo. No mostrar claves técnicas al usuario; faltantes deben fallar la comprobación de catálogo antes de entregar una versión. API tipada e inyectable para probar ambos idiomas sin tocar preferencias reales.
- Seleccionar explícitamente el recurso `.lproj` del idioma para Foundation/AppKit. Pasar `locale` a `String(localized:...)` sólo configura la interpolación de valores; no cambia por sí solo el idioma del lookup. Evitar depender del idioma actual de macOS para resolver los textos propios.
- SwiftUI observa el idioma donde hay texto y recibe el contexto en roots, sheets, popovers y comandos; los `NSHostingView` independientes requieren propagación explícita. AppKit actualiza títulos, placeholders, tooltips y AX durante su ciclo de actualización. Menús nuevos resuelven el idioma vigente al abrirlos; cambiar idioma no ejecuta acciones ni altera `MenuActionId`/targets/facts.
- No usar el idioma como `.id` del shell/tabla/reproductor ni cambiar claves de vistas para forzar una reconstrucción. Reetiquetar controles y vistas visibles preservando instancia, foco, scroll, selección, portada y cachés. No introducir observación de idioma en los deltas de gestos ni actualizaciones de progreso de audio.
- Errores propios y títulos de destinos guardan una clave/descriptor con argumentos cuando sea necesario, para actualizarse aunque existieran antes del cambio. Conservar la información técnica externa como detalle y mantener las mismas condiciones y acciones de reintento; la UI de resumen tiene un mensaje traducible completo.

### Textos propios y contenido del proveedor

Traducir controles, navegación, pestañas, categorías propias de Explorar, encabezados, estados, ayudas y accesibilidad. Normalizar encabezados conocidos de YouTube —por ejemplo «Listen again»— mediante su familia semántica reconocida, sólo al mostrarlos. El título original sigue siendo la entrada de clasificación/preferencias.

Canciones, álbumes, artistas, nombres de listas del usuario, letras, descripciones editoriales y notas de release mantienen su contenido original. No inferir que una lista personal es «Tus Me gusta» por su nombre; usar el ID de la colección del sistema. Categorías desconocidas conservan el texto del proveedor hasta tener una correspondencia fiable, sin traducir nombres propios ni adivinar su significado. La página web de login y diálogos suministrados por macOS tienen su propio idioma.

Idioma visible y país son conceptos separados. Los códigos `UY`/`ZZ`, detección regional y selección de rankings permanecen; se traduce sólo su presentación. Conservar zona horaria y contratos de duración/protocolo; aplicar formatos de números/fechas visibles con una política explícita, sin reparsear metadatos usando el idioma de UI ni alterar el orden de las canciones.

## Guía editorial inicial

Español con voseo coherente con la app actual («Elegí», «Buscá», «Soltá»); frases breves y términos consistentes. Usar «lista» en espacios compactos y «lista de reproducción» cuando aporta claridad. El inglés se redacta para sus controles, conservando el significado y las acciones; revisar espacio y truncado en ambos idiomas.

| Concepto | Español propuesto | Inglés propuesto |
|---|---|---|
| Home / Library / Search | Inicio / Biblioteca / Buscar | Home / Library / Search |
| Now playing | Ahora suena | Now playing |
| Playlist | Lista de reproducción / Lista | Playlist |
| Play / Play next | Reproducir / Reproducir a continuación | Play / Play next |
| Shuffle | Reproducción aleatoria | Shuffle |
| Add to queue | Añadir a la cola | Add to queue |
| Speed Dial propio | Acceso rápido | Speed Dial |
| Quick picks del proveedor | Selecciones rápidas | Quick picks |
| Listen again | Volver a escuchar | Listen again |
| Liked collection del sistema | Tus Me gusta | Liked songs |

Esta tabla es una propuesta de redacción; las claves y acciones técnicas permanecen independientes de sus palabras.

## Etapas implementadas y comprobaciones pendientes

1. **Infraestructura.**
   - [x] Inventario y separación de UI, datos, lógica, diagnósticos y contenido externo; fragmentos con ES/EN completos y catálogo/recursos derivados sincronizados.
   - [x] Resolver explícito, argumentos, plurales 0/1/2, respaldo español y faltantes sin claves visibles; preferencias/contexto global aislados y selector primero en General.
   - [x] Recurso empaquetado/resuelto dentro de una copia reubicada, firma/manifest e idiomas es/en comprobados. Lookup explícito independiente del idioma del sistema.
2. **Interfaz propia.**
   - [x] Shell/sidebar/toolbar/configuración y menús; reproductor/fullscreen/cola/letras/indicadores de gesto y labels AX.
   - [x] Inicio/Explorar/Biblioteca/Buscar/Spotlight/detalles/historial/cuenta/editor/actualizaciones y estados de carga/vacío/error.
   - [x] Encabezados/chips conocidos después de clasificación y resúmenes calculados sin cambiar datos/IDs/cachés; revisión editorial de las tres entregas antes de integrar la opción inglesa.
3. **Inglés y selector funcional.**
   - [x] Cobertura ES/EN de todas las claves, argumentos/plurales validados, English habilitado con catálogo completo.
   - [x] Cambio en vivo en copia HomeLab, menú nativo incluido, selección/pista conservadas y preferencia al relanzar. Errores/resúmenes existentes e identidad verificados en pruebas.
   - [ ] Ensayo manual con varias ventanas y cambio de cuenta real; la preferencia es global e independiente de cuenta en el código/pruebas.
4. **Regresiones y entrega.**
   - [x] Suite Apple/core completa, generación/empaquetado y build numerada por runner con la skill del repositorio; FIX-131/PAR-014 y documentación actualizados, sin publicación.
   - [x] Inspección visual del selector/panel en ambos idiomas, encabezados, menús y labels AX en ventana de 1512 pt; no atribuir audio/FPS a la build.
   - [ ] Anchos estrechos y textos excepcionalmente largos, VoiceOver real, foco/teclado completos, reproducción continua audible y trackpad físico. Cobertura automática de estado/gestos preservada.

## Pruebas de cierre concretas

- Catálogo: todas las claves del código existen en español; en la entrega bilingüe también en inglés. Argumentos y tipos compatibles, plurales y caracteres/porcentajes correctos. Recursos derivados sincronizados y faltante deliberado resuelto en español sin exponer la clave.
- Persistencia: sin valor/valor inválido → español; relanzamiento conserva elección; cambiar cuenta no altera idioma; pruebas y HomeLab no escriben el dominio real.
- Identidad: con los mismos records, elegir idioma conserva IDs, filtros, parámetros de búsqueda, rutas/índice de historial, orden y categorías ocultas. Mantener los `rawValue` existentes y comparar acciones de menús por ID/target/facts, con etiquetas distintas.
- Estado: cambio durante reproducción conserva pista, tiempo, estado play/pause, ocurrencias y orden de cola. No rebootstrap de core/cuenta, reinicio de AVPlayer, consultas adicionales, invalidación de cachés o resolución nueva de streams.
- Render nativo: actualizar textos/AX sin reconstruir tablas/carruseles ni recargar imágenes; conservar offsets/selección/páginas y actualizar resúmenes en caché. Inicio oculto por fullscreen mantiene su pausa y recibe sólo la última presentación al revelarse.
- Gestos: textos traducidos conservan la política FIX-129 —carruseles/chips/páginas de Inicio locales; headers/huecos con historial— y el descenso fullscreen fuera de zonas desplazables. No variar propietario, umbral, callbacks o número de anuncios/hápticos por traducir.
- Región: Global y Uruguay conservan mismos códigos/IDs/selección al pasar a inglés; nombre del país se presenta en el idioma elegido sin disparar detección ni consulta de rankings.
- Empaquetado: lookup en pruebas y bundle final, ambas localizaciones/plurales presentes, firma válida y recurso resuelto dentro de la copia instalada. Auditar `package_release.sh`/workflow antes de una futura publicación, sin usar el script alternativo como sustituto del runner.

## Paridad y límites

Windows no presenta actualmente un sistema de idiomas identificado en la búsqueda de fuentes. Mantener claves/glosario como referencia transferible; el catálogo y la integración AppKit pertenecen a Apple. Un port necesita su propia persistencia/presentación Svelte y comprobación de funcionamiento. No modificar el core compartido para el selector Mac ni afirmar validación Windows. Crear la fila de paridad al registrar la primera implementación, con evidencia de origen y destino pendiente.

## Resultado de la implementación

FIX-131 reúne la infraestructura y las tres entregas Luna revisadas por superficie. 688 claves completas, sin traducción automática ni cambios de locale del proveedor. Las seis suites de localización suman 30 pruebas dentro de la suite final. El runner de build-0067 aprobó 182 Rust, 140 XCTest y 240 Swift Testing (562); siete casos Rust existentes ignorados. Catálogo `--check`, sintaxis de empaquetadores, diff, diez hashes, firma ad hoc y `sourceChangedDuringBuild: false` comprobados.

En copia HomeLabFixture reubicada, el diagnóstico del ejecutable eligió `Contents/Resources/SideB_SideB.bundle`, resolvió Inicio/Home y plurales 0/1/2 de ambos idiomas. Evidencia: `builds/macos/build-0067/diagnostics/localization-resources.json` y `localization-ui.json`. Panel y selector primero en General revisados visualmente; inglés/español en vivo, menús nativos y labels AX actualizados; segunda página de canciones y pista original conservadas durante el cambio, y preferencia inglesa al relanzar. Se actualizan tanto el título del ítem como el del submenú que AppKit muestra en la barra; acciones/targets e idempotencia probados.

La primera build 0063 falló por expectativas textuales anteriores, corregidas sin alterar acciones. Las builds intermedias 0064–0066 permitieron detectar dependencia de `.build` en el resolver, encabezados genéricos y etiquetas/títulos nativos; la entrega es 0067. Copias de QA cerradas, datos/preferencias reales preservados, fuentes Windows/core/bindings y versión pública sin cambios. `package_release.sh` auditado estáticamente, sin ejecutarlo ni publicar; su CI y las comprobaciones físicas arriba siguen pendientes. No se afirma audio audible, VoiceOver ni FPS por tests/AX.

## Documentación primaria consultada

- [Apple: catálogos, contexto y plurales](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog).
- [Apple: recursos localizados de Swift Package](https://developer.apple.com/documentation/xcode/localizing-package-resources) y [Swift PackageDescription](https://docs.swift.org/latest/documentation/packagedescription/).
- [Apple: entorno locale de SwiftUI](https://developer.apple.com/documentation/swiftui/environmentvalues/locale).
- [Apple: String con clave, valor predeterminado, bundle y locale](https://developer.apple.com/documentation/swift/string/init(localized:defaultvalue:table:bundle:locale:comment:)); distingue formato de valores de idioma de lookup.
- [Apple: Bundle.localizedString y respaldo](https://developer.apple.com/documentation/foundation/bundle/localizedstring(forkey:value:table:)).
- [Apple: Text(verbatim:)](https://developer.apple.com/documentation/swiftui/text/init(verbatim:)); los textos externos y los ya resueltos por la fachada no necesitan una segunda búsqueda de traducción.
