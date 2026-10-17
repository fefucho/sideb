# PLAN-020: margen inferior, cierre exterior y búsqueda de TopNav

- Estado: FIX-196 implementado/build0127;728pruebas y firma/hashes aprobados. FIX-195/0126 conservado. QA física diferida por pedido del usuario; ensayos nativos aislados documentados abajo.
- Objetivo: dar aire debajo de las cápsulas, cerrar al hacer clic fuera y recuperar Configuración en menús; definir la conexión completa del buscador existente con TopNav.
- Alcance actual: Apple, margen inferior de 18 pt, cierre exterior por ventana, menús de cuenta/app, investigación y plan de búsqueda.
- Fase autorizada actual (17/10): activar toda la funcionalidad en TopNav conservando dos entradas: ⌘K/Buscar de sidebar → Spotlight rápido; lupa/⌘F → cápsula integrada. Corregir centrado vertical del texto. Volumen con scroll sólo se investiga por separado en PLAN-021.
- Exclusiones: cambios core/Windows, instalación, publicación y rediseño de cápsulas/animaciones validadas en FIX-194.
- Referencias: FIX-193/194, [PLAN-019](PLAN-019-topnav-spacing-lens-motion.md), SpotlightSearchModal, SearchViewModel y SearchRecentStore actuales.

## Entrega actual

- [x] Host con 18 pt bajo las cápsulas/18 pt arriba; añadir sólo 8 pt a la separación del contenido, respetando padding interno de páginas y controles nativos.
- [x] Cerrar con clic exterior en la misma ventana, conservar el evento original, excluir la cápsula visible durante su movimiento y limpiar el monitor al desmontar.
- [x] Reponer Configuración junto a acciones de cuenta/actualizaciones; usar el panel existente y conservar preferencias.
- [x] Inventariar funciones actuales de Spotlight y diseñar integración, estados, teclado, foco, cancelación y pruebas.
- [x] Pruebas focales y build numerada con suite completa/firma/hashes.
- [ ] Revisión en app real: diferida por pedido del usuario; no reabrir ventanas para esta entrega.
- [x] Registrar FIX-195 y evaluar paridad sin modificar Windows.

## Contrato de cierre exterior

Monitor local AppKit únicamente con editor visible/expandido, filtrado por ventana. Devuelve siempre el evento para conservar selección, botones y menús. Compara con el frame presentado de la cápsula, incluida su traslación aditiva. No reenvía mouseDown ni intercepta arrastre.

Referencia oficial: [NSEvent.addLocalMonitorForEvents](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)) y [removeMonitor](https://developer.apple.com/documentation/appkit/nsevent/removemonitor(_:)). Los eventos consumidos por bucles de tracking anidados no pasan por este monitor; comprobar interacción real además de pruebas unitarias.

## Integración Spotlight

### Hallazgos y reutilización

El motor actual alcanza para la integración. No hacen falta endpoints, índice ni ranking nuevos. La cápsula sólo recibe texto y apertura; `NativeSearchBar.onSubmit` todavía no está conectado. La UI de resultados/acciones vive dentro de `SpotlightSearchModal` y debe extraerse manteniendo el modal como consumidor hasta verificar la migración.

| Capacidad que debe conservarse | Fuente vigente |
|---|---|
| Debounce de 250 ms, generaciones, caché de 12 consultas/60 s y payload acotado | `ViewModels/SearchViewModel.swift`, `onQueryChanged`, `cancelPreview` |
| Hasta tres sugerencias textuales y ocho entidades, orden/IDs del proveedor y dedupe por tipo | `SearchViewModel.applyPreview`, `Views/Search/SearchProjection.swift` |
| Recientes de consultas y pistas, 50 por cuenta, borrar/limpiar/deshacer, pista no disponible | `Views/Search/SearchRecentStore.swift`, `SpotlightSearchModal.recentResults` |
| Teclado, selección estable por clave, scroll a selección y accesibilidad | `SpotlightSearchModal.keyboardActions`, `activateSelected`, `resultsScrollView` |
| Play directo con radio, Play siguiente/cola/likes/biblioteca/playlists y menús | `SpotlightSearchModal.quickSongRow`, `quickCardRow`, `MenuActionExecutor` |
| Artista/álbum/playlist y enlaces de créditos, Play de colecciones | `SpotlightSearchModal.handleCardSelected`, componentes `QuickResult*` |
| Carga, vacío, error/reintento y respuesta con sólo textos | `SpotlightSearchModal`, `SearchViewModel` |
| Enter/Ver todos/sugerencia/reciente → página con filtros y corrección reversible | `commitSearch`, `Views/Search/SearchView.swift` |
| Historial por intención: teclear no registra; query enviada sí; pista sólo al confirmar playback | `SearchOrigin`, `PlayerViewModel.activateSearchMediaRadio`, `SearchPlaybackIntegrationTests` |
| Limpieza por sesión y rechazo de respuestas antiguas | `SearchViewModel.clear`, `SideBApp.homeSessionRevision`, `SearchRecentStore.prepareSession` |

Antecedentes contrastados: FIX-165/173/178 definen motor, recientes y reproducción; FIX-181/182 encontraron problemas de propiedad del preview, selección UTF-16 y anclas. FIX-183 retiró aquella isla por decisión del usuario: sus lecciones son evidencia histórica, no una instrucción para restaurar su diseño. FIX-193/194 siguen siendo la composición aprobada.

### Riesgos encontrados

1. **Preview compartido sin dueño.** `SearchView.releasePagePreview` y el `onDisappear` del modal llaman `cancelPreview()` global. Un cierre tardío de la vista anterior puede cancelar el preview recién adquirido por TopNav. Introducir token de editor + generación/sesión: sólo su dueño puede cancelar; la consulta confirmada permanece independiente.
2. **Composición de texto.** El delegado nativo actual consume Enter/Escape/flechas y notifica cualquier cambio. Respetar `hasMarkedText`, dejar confirmar candidatos IME sin submit/cierre y preservar selección UTF-16 al sincronizar valores externos. Ningún eco de resultados debe reescribir el editor o recolocar el caret.
3. **Acciones con intención.** Conservar `activateSearchMediaRadio` y origen `.searchSpotlight` en menús. No registrar consultas al escribir ni pistas al pulsar Play si el player aún no confirmó inicio. No sustituir por Play genérico.
4. **Modelo frente a presentación.** El frame del header ya está en destino mientras Core Animation lo traslada. Anclar sólo al frame modelo separaría resultados y campo. Compartir geometría/timing/traslación del contenedor nativo, sin publicar un `@State` de SwiftUI por frame.
5. **Foco y cleanup tardío.** Publicar resultados no debe volver a enfocar. Navegar, cambiar cuenta, fullscreen y desmontar invalidan acciones diferidas; restaurar foco sólo si ventana/ruta/sesión siguen siendo las mismas y ningún clic externo adquirió otro destino.

### Arquitectura propuesta

- Un controlador de presentación por ventana concentra borrador, expansión, selección, dueño del preview, revisión de foco, sesión y cierre. El VM sigue conservando consulta confirmada, filtros y datos de proveedor.
- Extraer un contenido de resultados compartido y sus acciones desde Spotlight: recientes, sugerencias, entidades y estados. Reutilizar `QuickResultCardRow`/`QuickResultSongRow`, proyección y menús; no duplicar stores ni red.
- TopNav conserva su morph42→298 y la entrada integrada mediante lupa/⌘F. ⌘K y Buscar de sidebar abren el Spotlight rápido como segunda opción permanente. Ambos comparten contenido/acciones/motor, con borradores y dueños de preview independientes. Abrir uno cierra el otro sin cleanup tardío ni pérdida del borrador.
- Panel de resultados hermano de la cabecera en el shell, alineado con el extremo izquierdo de la cápsula. Propuesta inicial: ancho hasta 560 pt, limitado al viewport con 18 pt de margen; 8 pt bajo la cápsula y altura acotada sobre el player. Validar esta medida con contenido real antes de fijarla; el ancho de la cápsula y Back/Forward permanecen iguales.
- Un host nativo para el panel comparte el modelo de geometría y la traslación de la búsqueda; el morph modifica sólo bounds reales como hoy. Recalcular límites en resize/sidebar sin observar geometría por frame en SwiftUI. Ancla identificada/revisada se limpia al desmontar.
- El cierre exterior actual se amplía a la unión de cápsula y panel, incluidos sus descendientes; los menús nativos mantienen su tracking. Siempre devolver el evento original para que el control pulsado responda.
- La página completa mantiene filtros, corrección y rutas. Su editor puede adquirir el preview cuando recibe foco; transferir borrador/selección mediante el controlador y un token nuevo, sin que ambos escriban ni pidan sugerencias simultáneamente.

### Contrato de teclado e interacción

| Entrada | Resultado esperado |
|---|---|
| Lupa/⌘F | Expandir/enfocar TopNav; borrador conservado; vacío muestra recientes |
| ⌘K/Buscar de sidebar | Abrir Spotlight rápido; cerrar cápsula conservando su borrador |
| Escribir texto confirmado | Preview tras debounce; no reciente ni navegación |
| Flechas arriba/abajo | Cambiar selección principal estable; caret horizontal conserva edición; IME tiene prioridad |
| Enter | Ejecutar seleccionado una vez; sin selección enviar query no vacía; vacío no navega |
| Sugerencia textual/Ver todos/reciente query | Una consulta confirmada y una navegación, origen correspondiente |
| Play directo/menú | Acción existente; reciente pista sólo tras confirmación real |
| X con texto | Limpiar y mostrar recientes, mantener foco/apertura |
| X vacío/Escape/clic exterior | Cerrar sin enviar; clic exterior conserva su destino; Escape respeta IME |
| Cuenta/fullscreen/desmontaje | Cancelar preview propio y limpiar presentación; cuenta limpia borrador y selección |

### Fases de integración (FIX-196)

- [x] 1. Añadir ownership de preview por editor/sesión con pruebas rojas/verdes: cleanup viejo no cancela al nuevo; query confirmada independiente.
- [x] 2. Extraer cuerpo/acciones de Spotlight sin cambiar comportamientos; mantener modal y página funcionando.
- [x] 3. Conectar input nativo, callbacks de submit/selección, composición, borrador/rango y comandos globales. Evitar que el actual cierre incondicional de Enter duplique el cierre del controlador.
- [x] 4. Montar panel anclado, geometría de presentación, límites de altura y cierre exterior de cápsula+panel; probar movimiento/reversa/resize sin nuevo reloj de SwiftUI.
- [x] 5. Conservar entradas separadas: ⌘K/sidebar Spotlight, lupa/⌘F TopNav; coordinar editor de página y restauración de foco por ruta/sesión. Verificar equivalencia funcional sin retirar Spotlight.
- [x] 6. Focales + suite completa + build versionada y registro FIX-196. QA física de estados, acciones, teclado, foco y apariencia diferida por pedido, fuera del cierre automático.

### Pruebas de cierre de la integración

Preservar `SearchViewModelTests`, `SearchRecentStoreTests`, `SearchArtistProjectionTests`, `SearchPlaybackIntegrationTests`, `SearchToolbarViewTests` y las regresiones del header. Añadir cobertura de dueño obsoleto, cambios de cuenta, respuesta después de cerrar, acción/navegación única, selección tras reemplazo de resultados, IME/UTF-16 y rango durante morph, alineación del panel, clic passthrough y restauración de foco sin robarlo al destino.

QA nativa: recientes vacíos/mixtos, borrar/deshacer/no disponible, sólo textos, error/reintento, canciones/videos/colecciones y menús, Ver todos/filtros/corrección original, ES/EN, 960×640, sidebar/resize/fullscreen, Reduce Motion/Transparency y VoiceOver. Compilar no sustituye prueba de composición humana, audio o frames presentados.

Paridad: motor común en PAR-027; la nueva presentación AppKit queda en PAR-007, excluida de port Windows. No cambiar APIs del core para resolver estado local del editor.

## Cierre y límites

Separar validación funcional, compilación y percepción de fluidez. No declarar FPS por usar Core Animation/display link. Documentar pruebas reales y lo que quede pendiente.

## Resultado de la entrega actual

Build0126 compiled, fuentes estables;703pruebas ejecutadas aprobadas (188Rust/196XCTest/319SwiftTesting), firma estricta/10hashes válidos y494fuentes protegidas conservadas.38focales aprobadas. Diffcheck de archivos del cambio limpio.0125 se interrumpió antes de terminar al afinar margen; diagnóstico preservado, no se entrega.

0126 espera llavero al restaurar sesión; timeout CUA y sample main en SecItemCopyMatching. Usuario avisado para resolver diálogo. Revisión física de margen/clic exterior/passthrough y menús pendiente; investigación y plan futuro completos, motor de TopNav todavía visual.

Decisión del usuario (2026-10-17): dejar la revisión visual pendiente. No continuar operaciones de UI ni considerar aprobados margen, clic físico/passthrough o menús hasta retomarla. Build0126 y verificaciones automáticas conservadas.

## Ejecución FIX-196 — 2026-10-17

Plan autorizado: (1) contrato permanente de dos accesos; (2) extraer contenido/acciones reutilizables de Spotlight; (3) ownership VM y cancelación por editor; (4) entrada nativa centrada/IME/comandos; (5) panel anclado nativo y cierre exterior compartido; (6) integración shell y pruebas, build numerada.

Reparto: subagente de contenido/Spotlight, subagente AppKit input/alineación, subagente separado de plan de volumen sin implementación; raíz integra header/shell/VM, revisa y valida. No hay escrituras concurrentes sobre los mismos archivos.

### Implementación y comprobaciones previas a la build

- Contenido QuickSearch compartido; Spotlight conserva borrador en Root y sigue siendo una entrada permanente. Panel nativo560×hasta540, anclado a cápsula/traslación, viewport transparente con hit testing local y cierre exterior ampliado.
- Ownership de preview UUID por editor/sesión; refresh técnico de Biblioteca preserva consulta en edición/preview. Foco se adquiere inmediatamente incluso con alpha0/ancho de campo0 antes del primer frame. Captura de foco por control y rango UTF-16, nunca por el NSTextView compartido.
- Texto/placeholder/cursor usan altura natural18pt para14.5pt; comprobación aislada de render conserva centro21pt. Composición IME y externos diferidos, reset de sesión sin publicar marcas, undo/redo retirados por endEditing nativo (probes). Comandos síncronos por canal, sin perder eventos coalescidos.
- Focal final hasta aquí:22XCTest+24SwiftTesting=46 aprobadas; incluye hosting AnyView estable, dos Down en un turno y submit único; propiedad, refresh, foco, geometría, input y cuenta. Se agrega una regresión adicional al reconciliar la misma presentación tras reset de sesión; se ejecutará en la suite de build.
- Build completa pendiente. QA física anterior permanece diferida por pedido del usuario; no se operan otras ventanas/apps ni se reemplaza una revisión de dispositivo con estos ensayos. Volumen permanece sólo en PLAN-021.

### Resultado build0127

`node Scripts/build-version.mjs macos`: compiled/sourceChangedDuringBuild=false;728pruebas ejecutadas aprobadas (188Rust+203XCTest+337SwiftTesting;344Swift registradas con7live omitidas y7liveRust ignoradas). Regresión de misma presentación tras reset de sesión aprobada en suite completa. Firma deep/strict,10hashes y494archivos protegidos core/Windows/bindings válidos.

Bundle: `builds/macos/build-0127/Side B.app`. No abierto para conservar revisión física diferida. Evidencia en diagnostics/FIX196-verification.json, focales y capturas de input aislado. Plan de volumen independiente completo; ninguna implementación de audio/scroll incluida.
