# PLAN-007: fuentes, seis páginas y categorías configurables de Inicio

- Fecha: 2026-10-03 (America/Montevideo).
- Estado: activado el 2026-10-03 por pedido del usuario; etapas 1–3 implementadas y pruebas completas aprobadas; FIX-107/build-0025 mantiene controles centrados también con Configuración cerrada. Validación manual de arrastre/cuenta real y comparación de rendimiento pendientes de cierre.
- Objetivo: hasta seis páginas de álbumes/playlists destacados; fuentes activables y ordenadas arrastrando; categorías del feed activables y ordenadas; controles superiores centrados respecto del panel y cabecera con más espacio.
- Decisiones confirmadas por el usuario: fuentes por prioridad estricta, agotando la primera antes de la siguiente; visibilidad de categorías y permiso para aportar destacados independientes.
- Se conserva: panel derecho superpuesto, sin reservar ancho/mover Inicio o reproductor, debajo de fullscreen; controles nativos, navegación, teclado, menús, reproducción/shuffle y aislamiento por cuenta.
- Referencias: [PLAN-006](PLAN-006-home-settings.md), [FIX-105](../../FIXES.md#fix-105), [FIX-102](../../FIXES.md#fix-102), [FIX-103](../../FIXES.md#fix-103), [FIX-104](../../FIXES.md#fix-104), [PAR-006](../../PARIDAD.md).
- Alcance activado: implementación Apple de etapas 1–3, pruebas y build local numerada. Exclusiones: cambios Rust/Windows, opciones posteriores, entrenamiento de un recomendador, consultas masivas de catálogos, commits/push/publicación.

## Evidencia previa a la activación

1. `HomeFeaturedPresentation.make` selecciona seis colecciones únicas. `HomeFeaturedView.collectionPages` limita a tres páginas. La geometría admite una/dos/tres columnas con dos tarjetas por columna: capacidad dos/cuatro/seis por página. Cambiar solamente el límite de páginas no crea más recomendaciones.
2. La metadata se obtiene para la página visible. Playlist consulta primera página, máximo dos solicitudes incluso entre páginas superpuestas y LRU seis. Catálogo completo se pide sólo al reproducir. Debe mantenerse esa separación.
3. `HomeViewModel` conserva secciones crudas, snapshots y un único cursor de continuaciones; precarga hasta tres páginas con presupuesto temporal y Cargar más avanza hasta tres por clic. Su precarga usa prioridades fijas que deberán considerar las fuentes activadas.
4. `HomePresentationFactory` ya reordena determinadas categorías por nombre. Su ID de fila incorpora primer/último item y cambia al refrescar; no sirve para guardar preferencias de una categoría.
5. `LibraryViewModel.loadLibrary` carga listas de álbumes/playlists e historial. `HistoryGroupRecord.items` son canciones: pueden tener `albumId`, pero no un ID de la playlist de origen. Apple `BrowseCardRecord` tampoco expone propiedad de playlist o fecha de publicación. No afirmar que estos datos permiten filtrar playlists propias o recién publicadas.
6. La captura muestra el grupo superior desplazado respecto del centro del panel y el título muy próximo al grupo. Toolbar y panel usan mediciones distintas; el panel sólo reserva `sidebarHeaderInset(titlebarHeight)`.

## Seis páginas con trabajo visible acotado

Propuesta: **hasta seis páginas reales**, sin vacías ni duplicados para rellenar. El proveedor y las fuentes activas determinan si hay suficientes candidatos.

| Columnas actuales | Tarjetas por página | Colecciones para seis páginas |
|---|---:|---:|
| Una | 2 | 12 |
| Dos | 4 | 24 |
| Tres | 6 | 36 |

Mantener un conjunto ordenado de hasta 36 registros ligeros. La proyección para el ancho actual expone como máximo `6 × capacidadPorPágina`; **sólo esas colecciones expuestas se excluyen de los estantes**. Recortar a seis páginas en la vista después de quitar 36 registros del feed haría desaparecer recomendaciones en ventanas estrechas: evitar ese error.

Montar sólo las dos/cuatro/seis tarjetas de la página actual, obtener metadata sólo para ellas y mantener dos solicitudes y LRU seis. Las páginas restantes no crean controles, no consultan detalles ni decodifican portadas por adelantado. El ambiente sigue usando su conjunto pequeño de carátulas. No cargar las canciones de las 36 colecciones.

Actualizar la capacidad sólo cuando cambie entre dos/cuatro/seis, no en cada píxel del resize. Mantener la primera colección visible al redimensionar cuando siga dentro de la proyección; si deja de estarlo, limitar a una página válida. Cambiar fuentes/tipo/filtro reinicia el paginado de destacados de forma explícita.

Usar datos ya disponibles primero. No recorrer todas las continuaciones de YouTube para garantizar seis páginas al iniciar. Si faltan candidatos, mostrar las páginas disponibles; el Cargar más existente puede incorporar nuevos registros con su avance acotado. No prometer 120 FPS sin medir la nueva build.

## Fuentes propuestas y disponibilidad real

Cada tipo mantiene su propia lista de fuentes, con casilla y asa de arrastre. Implementado en FIX-106: fuentes del feed activas inicialmente y biblioteca/historial optativos, conservando la prioridad previa de Side B.

### Álbumes

| Opción | Datos reales | Alcance / límite |
|---|---|---|
| Recomendados para vos | Categorías Albums for you / equivalentes del feed | Selección de YouTube, conservando su orden interno. |
| Volver a escuchar | Álbumes presentes en Listen again | No confundir la categoría del proveedor con un historial cronológico completo. |
| Nuevos lanzamientos | Álbumes presentes en New releases / equivalentes | Usar la categoría del proveedor; no inventar fecha ni ordenar por fecha ausente. |
| Favoritos olvidados | Álbumes presentes en Forgotten favorites | Sólo cuando el proveedor los envíe. |
| De tu biblioteca en Inicio | Categoría From your library | Mantener separada de la biblioteca completa para que las casillas sean claras. |
| Otros álbumes del Inicio | Categorías no clasificadas arriba | No volver a incluir mediante esta fuente familias conocidas que fueron desactivadas. |
| Álbumes guardados | Lista de álbumes ya cargada en LibraryViewModel | Fuente adicional optativa. Es selección desde biblioteca, no ranking de afinidad de YouTube. |
| De tus escuchas recientes | Álbumes asociados a canciones del historial, usando albumId real | Fuente adicional optativa. Deduplicar por álbum, sin resolver cada canción en red; portadas de álbum verificadas o placeholder, sin asumir que una miniatura de video es portada de álbum. |

### Playlists

| Opción | Datos reales | Alcance / límite |
|---|---|---|
| Mixes para vos | Mixed for you / mixes personales del feed | Fuente personalizada que ya prioriza la app. |
| Volver a escuchar | Playlists de Listen again | Reutiliza recomendaciones del proveedor; no infiere playlists desde canciones del historial. |
| Favoritos olvidados | Playlists de Forgotten favorites | Disponible cuando esa categoría contiene playlists. |
| De tu biblioteca en Inicio | Playlists de From your library | Fuente del feed, distinta de toda la biblioteca. |
| De la comunidad | Playlists de From the community / equivalentes | Sólo registros presentes en el feed. |
| Otras playlists del Inicio | Playlists de categorías no clasificadas arriba | Incluye descubrimientos/contextos enviados por YouTube; no realiza una consulta por cada estado de ánimo. |
| Playlists guardadas | Lista ya cargada en LibraryViewModel | Incluye creadas y guardadas; el contrato actual no permite distinguirlas sin pedir detalles. |

Ideas adicionales realistas para una etapa posterior:

- **Playlists reproducidas en Side B:** registrar ID/contexto de playlist y momento de escucha por cuenta. El player conoce `currentPlaylistBrowseId`; su umbral existente de historial es un buen punto para registrar una escucha real, evitando contar un clic o una cola restaurada como reproducción. No recupera retrospectivamente todas las playlists escuchadas en YouTube.
- **Selección propia:** fijar álbumes/playlists elegidos desde la biblioteca y usarlos como una fuente priorizable. No necesita abrir todos sus catálogos.
- **Nuevas para vos:** filtrar candidatos por IDs todavía no mostrados, con registro local acotado por cuenta. Significa no vistos en Side B, no recién publicados.

No proponer como opciones ya disponibles: playlists más escuchadas históricamente, playlists recién publicadas, creadas por mí, o similitud musical calculada desde catálogos completos. Faltan datos verificables para esos criterios.

## Regla de selección confirmada

Recorrer fuentes activadas de arriba abajo, conservar el orden interno disponible, deduplicar por clase e ID canónico y completar el cupo antes de pasar a la siguiente. Con suficientes candidatos, la primera fuente puede ocupar las seis páginas. Una colección compartida por dos fuentes se adjudica a la primera; desactivar una fuente no prohíbe una colección que también llegue por otra fuente activa.

Clasificar cada categoría conocida antes de aplicar casillas. La fuente «Otros del Inicio» excluye esas familias aun cuando estén desactivadas, evitando que una casilla parezca no funcionar. Conservar procedencia del candidato para diagnósticos y, si aporta claridad, una etiqueta breve en la configuración.

Si todas las fuentes están desactivadas, no activar una a escondidas ni reemplazar playlists por álbumes. Mostrar un estado corto que permita volver a configurar fuentes. Una fuente sin datos no genera tarjetas falsas ni dispara consultas ilimitadas.

## Orden y visibilidad del feed de YouTube Music

Lista distinta de las fuentes de destacados: muestra categorías realmente recibidas, incluyendo las que quedaron sin estante porque sus items pasaron a destacados. Cada fila tiene casilla «Mostrar», título y asa para ordenar. Ofrecer búsqueda cuando la lista crezca, y acciones claras para restaurar visibilidad/orden.

**Decisión del usuario:** ocultar una categoría sólo oculta su estante. Puede seguir aportando destacados si su fuente está habilitada. Las fuentes de álbumes/playlists conservan su orden independiente del orden de categorías del feed.

Guardar categorías por claves estables de familia con aliases para nombres conocidos en inglés/español. Para categorías desconocidas, usar título normalizado y tratar filas con el mismo nombre como un grupo, conservando su orden interno. El contrato actual no tiene un ID semántico universal: si cambia un título desconocido, la nueva categoría puede requerir otra preferencia. No persistir IDs de fila, items iniciales/finales ni tokens de continuación.

Conservar como punto inicial el orden actual de Side B. «Usar orden de YouTube» debe restaurar el orden crudo del proveedor, antes de las prioridades que hoy aplica HomePresentationFactory. En orden personalizado, categorías recién recibidas se agregan después de las ordenadas, en orden de llegada; no reactivar categorías ocultas al refrescar o cargar más. Preferencias de familias se aplican coherentemente a los filtros.

Conservar registros crudos/snapshots: ocultar no borra datos ni cambia el cursor de red. El endpoint Home sigue enviando un feed completo; ocultar categorías reduce su presentación, no garantiza que el servidor deje de enviarlas.

## Panel y toolbar

1. Centrar siempre **el mismo grupo nativo** Actualizar / Atrás / Adelante / Configuración respecto de la ubicación del panel, abierto o cerrado (aclaración del usuario, FIX-107). No duplicar botones ni sus equivalentes de teclado en otro host. Calcular geometría en el mismo espacio de ventana y resolver colisiones con el selector superior; abrir/cerrar no cambia su ubicación. Comprobar sidebar abierta/cerrada y ancho mínimo.
2. Colocar el título y Cerrar debajo del borde inferior real del grupo, con separación inicial propuesta de 16 puntos. No depender sólo de titlebarHeight ni de offsets a ojo. Título y Cerrar comparten fila.
3. Cabecera fija y contenido desplazable, con dos apartados: **Destacados** (Álbumes/Playlists, fuentes) y **Categorías de Inicio** (orden/visibilidad). Las fuentes se guardan por tipo aunque sólo uno se muestre en Inicio.
4. Filas compactas con tick y asa; flechas para reordenar con teclado como alternativa al arrastre. Guardar/aplicar una vez al completar el drop, no durante cada movimiento del puntero. Casillas aplican al terminar su acción.
5. Mantener Escape, botón Cerrar, foco/Space nativo en todos los nuevos controles, accesibilidad, Reduce Motion/Transparency y cierre al navegar/buscar/fullscreen. El contenido largo del panel también debe estar limitado a su viewport; no montar 5000 filas de configuración a la vez.

## Integración propuesta

Separar las operaciones: datos crudos → clasificación de categorías/fuentes → candidatos por fuentes activadas → selección según capacidad → estantes con orden/visibilidad → excluir únicamente destacados expuestos. Biblioteca/historial aportan candidatos adicionales sin modificar los registros de Home ni la cola de reproducción.

Introducir configuración Codable versionada y un motor de selección puro, con reglas de fuentes por tipo y reglas de categorías independientes. Migrar la preferencia Álbumes/Playlists existente. Guardar preferencias que contienen títulos/IDs dinámicos por cuenta; purgar candidatos, metadata y respuestas pendientes al cambiar sesión. No escribir el índice de una fila como prioridad persistida.

Reutilizar biblioteca/historial ya cargados; si una fuente habilitada necesita datos aún no disponibles, cargarla de forma acotada fuera del camino de scroll, sin reconstruir tarjetas por cada respuesta. Sin catálogo completo para generar candidatos. La metadata conserva su límite y una caché acotada; reforzar también la concurrencia de álbumes entre páginas superpuestas, que hoy no tiene el limitador compartido de playlists.

Un único coordinador conserva continuaciones de Home. La precarga debe considerar fuentes activadas/datos necesarios, con límite de páginas/tiempo; nunca buscar una fuente desactivada sólo por el requisito fijo de prioridades actuales. Cargar más debe poder avanzar por páginas cuyos estantes estén todos ocultos hasta su límite de tres peticiones, y explicar si no hubo cambios visibles. No repetir FIX-104 con un clic que sólo incorpore categorías ocultas. Publicar una revisión del contenido sólo cuando cambie la proyección visible.

## Etapas activadas

- [x] Revisar código, antecedentes y captura; confirmar independencia de ajustes y prioridad estricta.
- [x] Etapa 1: presupuesto de seis páginas, proyección por capacidad y UI de centrado/separación; verificar que el scroll conserva trabajo acotado antes de sumar nuevas fuentes.
- [x] Etapa 2: fuentes existentes del feed, casillas/arrastre/persistencia; después integrar biblioteca e historial de álbumes con sus datos comprobados. Mantener inicialmente la selección actual al migrar.
- [x] Etapa 3: orden/visibilidad de categorías con claves estables, orden original de YouTube y continuaciones coherentes con categorías ocultas.
- [ ] Opcionales posteriores: playlists reproducidas localmente, selección propia y no vistos; elegir alcance con el usuario, no incluirlos automáticamente como funciones ya acordadas.
- [x] Pruebas y build numerada por etapa significativa; documentar cada implementación en FIXES y actualizar PAR-006 sin cerrar Windows sin validación.

## Criterios de cierre de validación

- Dos/cuatro/seis tarjetas por página, hasta seis páginas, sin items excluidos del feed que resulten inaccesibles al reducir ancho; anclas válidas y ningún duplicado entre fuentes.
- Prioridad estricta y casillas reales, grupos «Otros» sin fugas, fuentes vacías/errores y todas desactivadas; preferencias por tipo/cuenta sobreviven refresh, filtros y reinicio.
- Categorías ocultas siguen aportando destacados según su fuente; ordenar estantes no altera prioridad de destacados; categorías nuevas, nombres repetidos y cambio de idioma se comportan según reglas documentadas.
- Datos/render/carga limitados: sólo página visible, dos requests por modelo, LRU acotada, cero consultas de catálogos completos al configurar; drag no produce escrituras o recargas por frame. Metadata de cuentas anteriores nunca se publica.
- Continuaciones válidas ante ocultar/ordenar durante carga, páginas completamente ocultas, duplicadas/vacías, errores/reintento y fin; mantener acciones y fuente canónica de reproducción/shuffle.
- Geometría/hit testing con sidebar y ancho mínimo, grupo centrado y separación del título; Escape desde tabla/selector/nuevos controles; pantalla real y overlays correctos.
- `swift test --package-path apple`, runner Mac numerado, firma/BUILD.json y revisión del diff. Instruments en mismo Mac/build/ventana/escenario para comparar páginas 1–6 y scroll con panel abierto/cerrado; pruebas de conteo de vistas no equivalen a demostrar 120 FPS.

Paridad: fuentes/configuración/categorías son trasladables y amplían PAR-006; geometría AppKit requiere integración propia. No se necesita cambiar contratos compartidos para las fuentes iniciales revisadas. Cualquier dato adicional deberá evaluarse antes de modificar el core protegido.

## Resultado de la activación — FIX-106 / build-0024

Implementadas etapas 1–3. Motor puro versionado, configuración por cuenta, fuentes estrictas por tipo, seis páginas con presupuesto por capacidad, categorías independientes, orden original de YouTube y continuaciones por cambios visibles. Sólo metadata de página visible con dos requests por modelo/LRU seis; biblioteca e historial optativos con datos reales. Toolbar nativa centrada usando ancho y conversión de coordenadas de ventana; cabecera medida +16 pt. Se preservan shell, reproducción y cambios locales anteriores. Dos subagentes Luna completaron selección/configuración y geometría; integración y revisión final centralizadas.

Runner final: **180 Rust aprobados (7 live ignorados), 45 XCTest y 177 Swift Testing / 5 suites aprobados**. Build-0024 release arm64, SDK 27.0 / mínimo 15, firma ad hoc verificada; BUILD.json compiled/sourceChangedDuringBuild false. Builds 0022/0023 conservadas. Diff sin whitespace inválido; sin cambios core/Windows/bindings. Documentación finalizada después del empaquetado.

Verificación visual con copias HomeLab aisladas del binario: seis páginas y casillas efectivas; esconder estante Albums for you conserva sus destacados. Build-0024 centra el grupo sobre panel en 960 y 1512 pt y separa el título; botón Subir mueve y persiste New releases antes de From your library. En 0022 el host retenía ancho 420 al ampliar; corregido con medición nativa e invalidación del tamaño intrínseco y comprobado en 0024.

Pendientes de cierre, sin confundir con implementación:

- [ ] Arrastre, navegación de páginas 1–6 y teclado exhaustivo en la build final; comprobar resize/ancla y sidebar en la misma sesión. La herramienta devolvió noWindowsAvailable para arrastre/scroll/teclas pese a poder leer AX y accionar botones; no se declara aprobado el gesto.
- [ ] Fuentes adicionales/errores y cambio de cuenta en sesión real. La app normal quedó esperando Keychain al restaurar cookies; se recurrió al fixture aislado y no se eludió la restricción de SecurityAgent. Los casos de datos/cuentas/cancelación están cubiertos por pruebas, no equivalen a ensayo live.
- [ ] Instruments comparable, mismo Mac/build/ventana/scroll con panel abierto/cerrado y páginas 1–6. Time Profiler de 20 s guardado en /tmp/sideb-plan007-build24-panel-open.trace, pero el scroll no se pudo ejecutar: captura no válida para esa comparación. No se certifica 120 FPS ni audio audible.

[FIX-106](../../FIXES.md#fix-106) contiene archivos, intentos y límites; [PAR-006](../../PARIDAD.md) ampliada con Windows pendiente. Las opciones posteriores permanecen fuera del alcance. Sin commit/push/publicación.

## Corrección de centrado permanente — FIX-107 / build-0025

El usuario aclara que la ubicación centrada sobre el panel debe mantenerse incluso con Configuración cerrada. Eliminada la condición settingsPresented de la geometría nativa; el estado del engranaje sigue reflejando abierto/cerrado. Centro calculado siempre con ancho/inset reales del panel y conversión a coordenadas del host. No se alteran otras decisiones de PLAN-007.

Runner completo aprobado: 180 Rust (7 live ignorados), 45 XCTest y 177 Swift Testing/5 suites. Build-0025 compiled/sourceChangedDuringBuild false, firma verificada; versiones anteriores conservadas. Las pruebas existentes de geometría/callbacks pasan; comparación visual abierto/cerrado de esta build pendiente. [FIX-107](../../FIXES.md#fix-107), [PAR-006](../../PARIDAD.md). Sin cambios core/Windows ni commit/push.
