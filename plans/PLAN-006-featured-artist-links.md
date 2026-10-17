# Enlaces a invitados mencionados en títulos

- Fecha: 2026-10-10 (America/Montevideo).
- Estado: implementado en Apple/Windows; comprobaciones automatizadas aprobadas; aceptación física pendiente (2026-10-11). Investigación previa con GPT-6 Sol; implementación/revisión con GPT-6.1 Sol/medium.
- Objetivo: pulsar nombres de invitados dentro del título y abrir el perfil más probable aunque el proveedor solo haya enviado texto.
- Alcance: Apple y Windows; parsing de títulos/créditos sin ID, resolución mediante búsquedas existentes, caché local e interacción accesible.
- Exclusiones: inventar IDs, modificar los créditos originales, convertir IDs de Genius en IDs de YouTube, consultar modelos de IA en cada reproducción o modificar el core protegido.
- Relacionado: [Spotlight y Biblioteca](PLAN-005-search-library.md). Registro: FIX-167 y PAR-029; evidencia al final.

## 1. Decisión de producto

Para `Tema (feat. Joe Fox & Kanye West)`, mostrar el mismo título con **Joe Fox** y **Kanye West** como destinos independientes. `feat.`, espacios, `&`, `y`, paréntesis y demás puntuación conservan su aspecto y no son enlaces.

Cuando falte el ID, la app busca y **elige automáticamente el candidato más lógico**. No exige que haya un único resultado ni abre un selector por cada ambigüedad. Esta decisión incorpora la preferencia del usuario: aceptar una inferencia razonable para que el enlace sea útil.

Un ID original sigue teniendo prioridad. Un destino inferido se guarda como tal, separado del crédito del proveedor. Si no aparece ningún artista razonablemente compatible, el clic abre búsqueda por ese nombre; no navega al primer resultado irrelevante solo para producir un enlace.

La búsqueda de artistas no prueba participación en la grabación y los homónimos pueden producir errores. El producto debe ofrecer corrección discreta y recordar esa elección, sin presentar la inferencia como un crédito verificado.

## 2. Lo que permite el código actual

- `SongItem.title` es texto plano. `artist_runs` conserva nombres e IDs del subtítulo; no describe rangos dentro del título.
- Apple ya presenta créditos con `TrackArtistLinks`; Windows tiene `ArtistCredits.svelte`. Los IDs disponibles pueden abrir perfiles directamente.
- Existe `search_cards(query, "artists")`; se puede resolver un nombre sin registrar una búsqueda del usuario. Sus tarjetas aportan tipo, ID y título; no asumir que incluyen popularidad, seguidores o una relación demostrada con la canción.
- El título de una fila es actualmente una acción de reproducción en las dos plataformas. Agregar spans con apariencia de enlace no basta: hay que cambiar las zonas de interacción y foco.
- La información de radio/álbum ya cargada puede completar IDs. No descargar álbumes o radios enteros solo para resolver un nombre.

Por ello el MVP puede vivir en las integraciones Swift y TypeScript, usando APIs del core existente. Compartir fixtures de entrada/salida para mantener paridad. La duplicación acotada del algoritmo no autoriza un nuevo feature dentro del core protegido.

## 3. Detección y segmentación del texto

### 3.1 Encontrar una cláusula de invitados

1. Detectar `feat`, `feat.`, `ft`, `ft.` y `featuring` sin distinguir mayúsculas, con límites de palabra. No detectar `ft` dentro de otra palabra.
2. Admitir grupos entre paréntesis/corchetes y sufijos inequívocos: `Tema feat. A & B`, `Tema (feat. A, B y C)`.
3. `with`/`con` solo se interpretan como créditos cuando la forma está claramente delimitada, por ejemplo `Tema (with A)`. No dividir títulos como `With or Without You`.
4. Separar descriptores de versión delimitados (`- Remaster`, `(Live)`, etc.) del candidato, sin borrar palabras que podrían pertenecer al nombre. Conservar el título original intacto.
5. Producir segmentos con rango original: texto normal, marcador, candidato a artista y conector. Normalizar una copia para buscar; nunca reconstruir el título desde la versión normalizada.

### 3.2 Elegir entre nombre compuesto y varios invitados

`&`, `y`, `and`, comas y `/` son posibles separadores **dentro de la cláusula de invitados**, no reglas globales. `x` solo entra en una etapa posterior con evidencia suficiente; no confundirlo con una inicial o parte del nombre.

Para `Joe Fox y Kanye West`:

- Generar la alternativa de un nombre completo y la alternativa `Joe Fox` + `Kanye West`.
- Reutilizar primero nombres/IDs conocidos de la misma pista. Si coinciden ambos artistas, aceptar la división sin pedir red.
- Si falta información, resolver candidatos de las alternativas de forma acotada. Dos nombres completos con artistas compatibles y ninguna entidad compatible para la cadena completa favorecen la división.
- No decidir por el simple número de resultados: comparar cobertura del texto, coincidencia de nombres y contexto. Aplicar penalización a cortes sin evidencia para evitar sobresegmentar.
- Una entidad conocida que cubre todo el texto debe ganar frente a fragmentos débiles: `Earth, Wind & Fire`, `Simon & Garfunkel`, `Of Monsters and Men`, `AC/DC` y `Tyler, The Creator` son fixtures obligatorias.
- Si la cadena completa corresponde a un dúo y sus miembros también tienen perfiles, el crédito explícito del mismo tema decide. Sin ese dato, preferir la entidad completa exacta; no inventar una lista de colaboradores distinta al texto recibido.
- Evaluar grupos completos contiguos permite `Earth, Wind & Fire & Kanye West`: conservar el grupo y separar a Kanye si los candidatos lo respaldan.

Usar búsqueda de particiones acotada (beam/dynamic programming), no todas las combinaciones de separadores. Presupuesto inicial: hasta seis candidatos finales y ocho consultas de artistas por título, con deduplicación de consultas. Al alcanzar el límite, resolver los fragmentos más claros y dejar los restantes disponibles para resolución al clic.

## 4. Resolver y elegir automáticamente

### Prioridad de fuentes

1. ID proporcionado en `artistRuns`/metadatos fiables de **esa misma pista**, coincidiendo el nombre. No sustituir un crédito original con una inferencia previa.
2. Corrección local que el usuario haya elegido para ese fragmento/contexto, cuando no hay ID original. Si después aparece un ID original distinto, invalidar la inferencia y usar el dato original; no aplicar una corrección global de un homónimo a todas las canciones.
3. Caché de resolución válida para el mismo contexto.
4. Búsqueda de artistas por nombre completo normalizado, usando la API existente sin historial.

### Orden de candidatos de búsqueda

Filtrar resultados a entidades de artista con destino real no vacío; deduplicar por ID. No construir un ID desde el nombre ni asumir que todo resultado es un perfil.

Ordenar con reglas explicables:

- Coincidencia del nombre completo: exacta normalizada primero, alias conocido después, aproximaciones por errores pequeños al final. Case, espacios y variantes Unicode equivalentes no deben perjudicar al candidato; quitar palabras distintivas sí.
- Evidencia de la misma grabación o créditos ya disponibles: máxima prioridad contextual. Coincidencias de álbum/título/artista principal son señales auxiliares, no prueba independiente de colaboración.
- Cobertura de tokens y similitud del nombre; evitar candidatos que omiten la mayor parte del nombre solicitado.
- Posición devuelta por el proveedor como desempate de candidatos igualmente plausibles; después ID estable para que el enlace no cambie entre renders.

Si hay dos homónimos plausibles y no hay evidencia adicional, elegir el mejor ordenado en lugar de pedir confirmación. No exigir un gran margen entre primero y segundo para enlazar: esa sería una política más conservadora que la solicitada. Registrar internamente el motivo y que el resultado es inferido, sin exponer puntuaciones como porcentajes de certeza.

Si la búsqueda exacta falla, permitir un intento contextual acotado con nombre del invitado y artista principal; evaluar los nombres obtenidos contra el invitado original. No aceptar al artista principal solo porque la consulta contextual lo hizo aparecer primero. Calibrar aproximaciones con fixtures antes de habilitarlas: sin un candidato compatible, búsqueda visible como último recurso.

No usar una supuesta popularidad que la API no ofrece ni un alias global inventado (`Ye` → Kanye, por ejemplo) sin una fuente ya conocida. Una búsqueda puede devolver ese alias; el algoritmo debe distinguir esa evidencia de una equivalencia asumida.

### Salida del resolver

```text
ResolvedCredit
  originalRange, displayName, normalizedName
  destinationId?
  provenance: provider | userChoice | inferred | unresolved
  evidenceKind, resolvedAt, resolverVersion
```

Los rangos se aplican solo a la versión exacta del título analizada. Swift y JavaScript no intercambian offsets suponiendo que cuentan Unicode igual: cada implementación materializa rangos con su sistema y comparte fixtures con substrings esperados.

## 5. Experiencia de uso

- Un nombre resuelto abre directamente el perfil. Hover/subrayado sutil y cursor indican enlace, sin convertir todo el título en tags de colores.
- Un nombre todavía pendiente sigue siendo accionable: al pulsarlo aparece un estado breve «Buscando artista…», cancelable. Si se encuentra candidato, abrirlo; ante timeout/error o ausencia de candidato, ofrecer búsqueda y reintento. No bloquear el reproductor.
- Presupuesto de espera de clic inicial: aproximadamente dos segundos antes de ofrecer el fallback; ajustar con mediciones. Si el usuario elige otra acción o cierra, una respuesta tardía puede llenar caché pero no navegar después.
- Tooltip accesible para inferidos: «Abrir [nombre] · coincidencia sugerida». El texto visible principal sigue limpio.
- Menú del nombre: «Abrir artista», «Cambiar coincidencia…» y «Buscar este nombre». Cambiar abre un selector local de candidatos y guarda el destino elegido para esta pista/fragmento. Es una herramienta de corrección voluntaria, no un paso obligatorio.
- El resto del título conserva su acción actual; el enlace nunca dispara play, doble clic de fila, selección de otro destino o arrastre accidental. No anidar botones dentro de un botón de reproducción.
- Accesibilidad: nombre y rol de enlace, foco por cada destino, activación por teclado y puntuación leída naturalmente. Elipsis/truncado no puede dejar zonas de clic invisibles.

## 6. Carga, caché y separación de datos

- Resolver de inmediato IDs disponibles; prefetch de invitados de la pista actual y después de filas visibles bajo demanda/hover/foco. No escanear la biblioteca ni lanzar peticiones por cada render.
- Una cola de resolución con máximo dos peticiones concurrentes, deduplicación en vuelo y el presupuesto por título anterior. Cancelar trabajo de baja prioridad al salir de la superficie.
- Clave de caché: proveedor, nombre normalizado, `videoId`, contexto de artista/álbum y versión del parser/resolver. No usar solo el nombre: el mismo homónimo podría corresponder a artistas distintos.
- Separar cuenta/invitado y generación para no guardar contexto privado en otra sesión. Las resoluciones técnicas no se agregan ni a Recientes de Side B ni a historial remoto.
- Valores iniciales a medir: inferencias positivas siete días, negativas diez minutos, máximo 500 entradas con LRU. Correcciones explícitas persisten hasta eliminarlas; no vencen como un fallo temporal. Guardar IDs y metadatos mínimos, sin URLs firmadas ni credenciales.
- Si llegan créditos reales después, tienen prioridad y reemplazan el overlay inferido. No escribir inferencias en `artistRuns`, tags del archivo, cola nativa o metadatos del proveedor.
- No mover enlaces bajo el cursor al completar una resolución. Mantener el texto y la geometría; cambiar el destino en la siguiente interacción segura. Si cambia el título o pista, invalidar los rangos antiguos.

## 7. Integración por superficies

| Área | Trabajo previsto |
|---|---|
| Dominio Apple | Parser/resolver/store separados de las vistas; llamadas al core existente y cancelación por sesión/pista |
| Dominio Windows | Controller/servicio TypeScript equivalente, transporte por `search_cards` actual; sin lógica extensa dentro de `+page.svelte` |
| Reproductor y fullscreen | Componente de título segmentado; primer lugar para validar lectura, navegación y enriquecimiento tardío |
| Créditos bajo el título | Reutilizar IDs reales; permitir resolver nombres no enlazados claramente identificados, sin volver a partir runs que ya tienen ID |
| Filas Apple | Hit testing/foco por rango o controles separados en `NativeTrackActionField`; conservar el comportamiento de la tabla y geometría del texto |
| Filas Windows | Texto y enlaces como controles hermanos en `TrackList`, no un botón grande que contenga botones |
| Búsqueda, álbum, playlist, biblioteca, cola | Integrar por componentes comunes y comprobar las superficies que tengan una implementación propia; resolución visible acotada |

Referencias verificadas:

- [TrackArtistLinks.swift](../apple/Sources/SideB/Views/Components/TrackArtistLinks.swift), [PlayerBarView.swift](../apple/Sources/SideB/Views/Components/PlayerBarView.swift), [NativeCollectionTrackCellView.swift](../apple/Sources/SideB/Views/Common/NativeCollectionTrackCellView.swift).
- [ArtistCredits.svelte](../windows/src/lib/components/ArtistCredits.svelte), [TrackList.svelte](../windows/src/lib/components/common/TrackList.svelte), [catalog.rs](../windows/src-tauri/src/commands/catalog.rs).
- [metadata.rs](../core/crates/innertube/src/models/metadata.rs), [endpoints.rs](../core/crates/innertube/src/endpoints.rs), [lib.rs](../core/crates/sideb-core/src/lib.rs): lectura del contrato; sin modificaciones previstas.
- Antecedente [FIX-085](../FIXES.md#fix-085): destinos independientes originales. Esta propuesta agrega inferencias sin perder esa garantía.

## 8. Fases y dificultad

- [x] Comprobar fuentes, IDs disponibles y API de búsqueda; revisión adicional con GPT-6 Sol.
- [x] **A — Parser y fixtures:** cláusulas, alternativas de segmentación, rangos Unicode y descarte de falsos positivos. Dificultad media.
- [x] **B — Resolver:** reuse de IDs, ranking automático, caché, presupuestos, correcciones y fallback. Dificultad media/alta; la precisión se valida con un corpus, no solo con Joe Fox/Kanye.
- [x] **C — Pista actual:** títulos y créditos en barra/fullscreen de ambas plataformas, clic sin playback y enriquecimiento tardío. Dificultad media.
- [x] **D — Listas:** adaptar interacción AppKit/Svelte, truncado, foco y componentes reutilizados en todas las superficies. Dificultad alta; es la parte más delicada para no romper acciones existentes.
- [ ] **E — Aceptación/paridad:** pruebas, revisión visual y casos reales con evidencia; registrar fixes, paridad y actualizar este plan.

Orden recomendado: una primera entrega completa para la pista actual, seguida por listas. No declarar toda la función terminada mientras las filas sigan comportándose distinto. No hace falta una IA en tiempo real; el costo principal es resolver ambigüedad e interacción correctamente.

## 9. Matriz de aceptación

| Caso | Resultado exigido |
|---|---|
| `Tema (feat. Joe Fox & Kanye West)` y variante con `y`/`and` | Dos destinos independientes; conectores sin enlace |
| Invitado presente en título y `artistRuns` con ID | Reutilizar ID sin búsqueda |
| Invitado solo como texto, candidato compatible | Abrir perfil automáticamente; marcar procedencia inferida |
| Dos homónimos igualmente compatibles | Elegir determinísticamente el mejor candidato; permitir corregir sin modal previo |
| Solo resultados incompatibles, timeout u offline | No inventar destino; búsqueda/reintento disponible |
| `Earth, Wind & Fire`, `Simon & Garfunkel`, `AC/DC`, `Of Monsters and Men`, `Tyler, The Creator` | Conservar entidad completa cuando la evidencia la respalde |
| Grupo con separadores + otro invitado | Mantener el grupo y separar al invitado, sin fragmentar cada palabra |
| `With or Without You`, palabras que contienen `ft`, títulos sin invitados | No crear créditos nuevos |
| Emoji, diacríticos, caracteres combinados, no latinos, varios grupos y remaster | Rangos correctos y título intacto |
| Clic/Enter en enlace dentro de fila | Navegar una vez, sin play ni propagación a la fila |
| Clic en título fuera del enlace | Conservar acción previa de esa superficie |
| Respuesta después de cambiar canción/cuenta o cancelar clic | No aplicar rango/destino ni navegación al contexto nuevo |
| Créditos originales aparecen después | Sustituir inferencia por ID original sin cambiar el texto arbitrariamente |
| Cien filas visibles o scroll rápido | Respetar concurrencia/presupuesto; ninguna tormenta de consultas por render |
| Elegir otro artista en «Cambiar coincidencia» | Recordar corrección en esta pista/contexto; no contaminar homónimos globales |

- [x] Ejecutar corpus común en Swift/TypeScript y revisar por separado segmentación, destino y falsas detecciones; reportar números reales y ejemplos fallidos, sin prometer precisión del 100%.
- [x] Ejecutar pruebas Apple y `swift test --package-path apple`; Windows `pnpm check`, `pnpm test`, `pnpm build`, con validación nativa Windows aparte.
- [ ] Verificar puntero, teclado, accesibilidad, menús, doble clic, truncado, playlists con canciones repetidas y cola/reproducción sin regresiones.
- [ ] Comprobar que resolver nombres no agrega búsquedas técnicas a recientes ni a historial remoto.
- [x] Registrar límites, fixes y paridad; evidencia automatizada abajo. Aceptación física pendiente.

## Evidencia de implementación (2026-10-11)

- Parser/resolver equivalentes Swift/TypeScript, corpus compartido de dieciséis títulos; prioridad provider → corrección local → caché → búsqueda compatible. Dos peticiones concurrentes, ocho consultas por título, seis créditos finales. No se ejecuta IA ni se escriben inferencias en créditos del proveedor/core.
- Barra/fullscreen, créditos, filas nativas/Svelte, Inicio, búsqueda y cola integrados. Texto intacto; controles separados por rango visible, truncado sin hitboxes invisibles y primer clic sobre el nombre original. Resolución al clic con presupuesto total de dos segundos; fallback de búsqueda y corrección voluntaria.
- Caché positiva siete días/negativa diez minutos, límite 500, contexto y cuenta aislados. Cancelación por consumidor y guardas de identidad/cuenta en selector de correcciones incluidas en la revisión final.
- Ocho focales Swift y treinta resolver/cola Windows aprobaron antes del cierre. Corpus ejecutado en ambos lenguajes. Fixture visual verificó Joe Fox y Kanye como destinos separados, clic en Kanye navega sin play.
- Primera build-0076 compiló fuentes, pero fallaron pruebas de jerarquía/hover de Inicio; se conserva el intento fallido. Nueva build y suite global final se registrarán al terminar.

Pendientes: perfiles reales del proveedor, aceptación AppKit/WebView2, teclado/lector de pantalla y prueba física de cola/audio/FPS. El corpus determinista no es una medida de precisión de resultados reales. No hay commit, push ni publicación asociados a esta implementación.

### Revalidación posterior a revisión cruzada

Build-0077 compilada y firmada, fuentes estables durante la build: 618 pruebas aprobadas (182 Rust, 140 XCTest, 296 Swift Testing), siete live Rust ignoradas. Corrige jerarquía/hover de Inicio sin debilitar assertions. Windows: 334 aprobadas/0 fallos/1 fixture sólo Windows omitido, check0/0 y build frontend aprobado. Fixture navegador adicional: ArrowDown enfoca play, Enter reproduce, enlace de invitado de reciente navega y Escape restaura Buscar. Fixtures temporales retirados.

Última corrección antes de entrega: caché negativa parcial del prefetch ya no bloquea búsqueda contextual al clic, incluso si comparte una petición en curso; reutiliza ausencia exacta fresca para consultar sólo el contexto, y repite exacta si expiró. Regresiones de ambos lenguajes y de activación AppKit por teclado/accesibilidad agregadas. Revalidación en build-0078 aprobada; ver cierre final.

### Cierre automatizado final

Build final [build-0078](../builds/macos/build-0078/BUILD.json): compilada release arm64, SDK27.0/mínimo15, firma verificada, sourceChangedDuringBuild=false y diez hashes comprobados. **622 pruebas aprobadas** (182 Rust/140 XCTest/300 Swift Testing;7 live Rust ignoradas). Incluye regresiones de caché parcial/completa, vuelo simultáneo, expiración, cancelación de consumidores, cuenta/rollback y activación AppKit sin puntero. Windows: **337 aprobadas/0 fallos/1 fixture nativo omitido en Mac**, check0 errores/0 advertencias y build frontend aprobados; aviso de chunk grande conservado. Catálogos730 ES/EN actuales. Fuentes core/bindings sin cambios. Cierre documental posterior, sin cambios de código tras la build. No se abrió/instaló/publicó ni se cambió versión pública. Cuenta real, audio audible, FPS y runtime Windows siguen pendientes.

### Feedback de hover/foco — 2026-10-11

FIX-170 completa el affordance: AppKit añade tracking/dibujo de halo y subrayado al nombre visible; SwiftUI y Windows iluminan con el acento Side B y subrayan hover/foco. No cambia rangos, hitboxes ni resolver. Dos regresiones nativas de render reversible/foco/ausencia de activación aprobadas; navegador confirmó acento rgb(208,108,112), subrayado y apertura del artista sin play. Build-0080 compilada/fuentes estables/firma y diez hashes verificados:628 pruebas Mac;340 Windows, check0/0 y build frontend aprobados. No hubo cambios de código después; aceptación física pendiente.

### Corrección del estilo de hover por pedido del usuario — 2026-10-11

FIX-171 sustituye el estilo de FIX-170: sin subrayado, halo ni acento en el nombre. Los créditos conservan sus colores previos y cambian sólo de brillo al hover/foco; los artistas dentro del título reciben el mismo feedback discreto. AppKit modifica únicamente el color de los rangos visibles, sin mover texto ni hitboxes. Resolver, menús y destinos permanecen. Verificación focal/global en curso; PAR-029.

Cierre FIX-171/172: [build-0081](../builds/macos/build-0081/BUILD.json) compilada release arm64, SDK27.0/mínimo15, firma verificada, fuentes estables y10hashes comprobados.635 pruebas Mac (182Rust/147XCTest/306Swift Testing,7live ignoradas); Windows348 aprobadas/0fallos/1omitida, check0/0/buildfrontend aprobados. Sin fuentes core/bindings modificadas; cierre documental posterior sin cambios de código. App final sin abrir/instalar/publicar. Cuenta real, FPS/Instruments y Windows nativo siguen pendientes.
