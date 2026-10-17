# Controles homogéneos en macOS y Windows

- Fecha: 2026-10-12 (America/Montevideo).
- Estado: implementación Apple/Windows completada y revisada; pruebas/build Mac y frontend Windows aprobados; aceptación visual/accesibilidad nativa pendiente.
- Objetivo: centralizar aspecto, medidas e interacción de los botones usando Biblioteca y las acciones de álbum/playlist como referencia visual.
- Alcance: Inicio, Búsqueda completa, Explorar, Biblioteca, detalles de álbum/playlist/artista y selector Cola/Letras/Relacionado. Revisar acciones auxiliares de esas pantallas para evitar excepciones accidentales.
- Exclusiones: rediseñar contenido, portadas, sidebar o transporte del player; cambiar navegación, búsqueda, historial, peticiones o core; convertir enlaces de artista en cápsulas o agregarles subrayado.
- Evidencia: revisión de código por integrador y auditor, componentes reales Windows en navegador, pruebas de layout SwiftUI y suites completas. Las medidas siguientes ya están implementadas y verificadas geométricamente; la apariencia nativa completa queda por aceptar.
- Antecedentes: [Biblioteca y buscador](PLAN-005-search-library.md), [enlaces de invitados](PLAN-006-featured-artist-links.md), FIX-166/169/171/172. Conservar rendimiento y hover sólo por brillo de artistas.
- Resultado: [FIX-174](../FIXES.md#fix-174), [FIX-175](../FIXES.md#fix-175), [FIX-176](../FIXES.md#fix-176), [FIX-177](../FIXES.md#fix-177), [PAR-030](../PARIDAD.md). Bundle actual `builds/macos/build-0087/Side B.app`, sin abrir/instalar/publicar.
- Antecedente rechazado visualmente por el usuario: FIX-175. Sólo fullscreen recupera el grupo compacto de40 y el estilo de la topbar. Mac usa NSSegmentedControl y NavigationGlassSurface reales; Windows una variante toolbar40/32 opt-in. Biblioteca y los demás controles conservan el diseño aprobado. Cuatro focales Apple y640pruebas/build-0084,354pruebas/frontend Windows aprobados; selector comprobado visualmente en una ventana nativa aislada.

- Corrección previa aceptada FIX-176: comparación AppKit confirma doble bezel dentro de vidrio. Selector único NSSegmentedControl sin NavigationGlassSurface, distribución automática, selección nativa y host40pt. Clic/arrastre/AX comprobados en fixture nativo; cuatro focales aprobadas y build-0085 compilada con640pruebas, fuentes estables, firma y diez hashes verificados. Topbar sin cambios. No equivale a aceptación en app completa.

- Ajuste pedido tras aprobar FIX-176: FIX-177 usa extraLarge nativo desde26 (36pt en SDK27), padding20/ancho real de símbolos y host40 sin cambiar la reserva del panel ni la selección deslizante. Compacto con slots48 desde26 para contener la lente y ancho152 que cabe en160pt. Cuatro focales/clic/arrastre/AX comprobados; intento0086 interrumpido al detectar ancho insuficiente; build-0087 aprobada con640pruebas, compiled/fuentes estables, firma y diez hashes verificados. Windows36 pendiente de evaluación.

## Diagnóstico inicial

| Superficie | macOS actual | Windows actual |
|---|---|---|
| Biblioteca | Categorías de 48 pt, texto 15,6, padding horizontal 20 y cristal interactivo; herramientas de 40 pt | Categorías de 48 px, texto 16, padding 20; material acrílico, borde y tinte seleccionado |
| Álbum/playlist | `CollectionDetailHeaderView` ya comparte acciones con `compatGlass`; texto 15,6 y padding vertical 9,6, sin altura común explícita | `CollectionHeader` comparte estructura y radio de cápsula; acciones con altura mínima 38 y estilos locales planos |
| Inicio | Chips con texto 13, padding 14×7 y fondo plano; tamaño derivado del texto | Chips con texto 13 y padding 14×7; selección blanca en CSS local |
| Búsqueda completa | Filtros con texto 11,5, padding 12×5 y fondo plano | Filtros con texto 12,5, padding 12×5 y fondo plano |
| Explorar | Tabs con texto 12, padding 15×10, fondos/bordes propios | Navegación con radio 9 y reglas generales para botones/selects; distinto de las cápsulas |
| Cola/Letras/Relacionado | Cápsula agrupada con padding exterior 4; segmentos con texto 13 y selección roja plana | Grupo de 40 px con segmentos de 32; base opaca `#343437` y selección roja plana |

La duplicación no está sólo en colores: cada vista decide geometría, tipografía, borde y estados. `LiquidGlassCompat.swift` centraliza el material Apple, pero no el control. `AppTheme.swift` y `tokens.css` tienen colores/superficies, pero no un contrato compartido de botones. En Windows varias reglas locales generales de `button` pueden sobrescribir el futuro componente.

## Diseño implementado

Una familia de cápsulas de cristal con medidas por función, no medidas elegidas por pantalla. Mantener la referencia grande de Biblioteca; no reducirla para igualarla a los filtros pequeños actuales.

| Función | Medida inicial en unidades lógicas | Regla |
|---|---|---|
| Categorías/filtros principales | Alto 48; texto 15–16 semibold; padding horizontal 20; separación 10 | Misma medida en Biblioteca, Inicio, Búsqueda y tabs de Explorar |
| Acciones de cabecera/herramientas | Alto 40; texto 14–15 semibold; padding horizontal 16; separación 8 | Reproducir, Aleatorio, Guardar, Nueva playlist, orden y actualizar |
| Acciones sólo de icono | Caja 40×40; icono 16–18 | Misma alineación con acciones de texto, tooltip y nombre accesible |
| Selector agrupado fullscreen | Alto exterior40; texto13; Windows segmentos32; Apple bezel nativo sin estirar | FIX-176 conserva el tamaño anterior y elimina el doble bezel de FIX-175: lente nativa Apple, selección neutra Windows; una sola superficie |
| Utilidades en contenido denso | Caja 32×32 | Sólo donde ya lo exija una fila/overlay; no usar para filtros o tabs principales |

Los valores se expresan en pt Apple y px CSS Windows: comparar a escala lógica equivalente, no por píxeles físicos de capturas Retina. Ajustar ópticamente tipografía e iconos nativos sin variantes nuevas por pantalla. Fijar el peso del texto para que seleccionar un filtro no cambie su ancho.

### Material y estados

- Reposo: cristal neutro, borde tenue y texto legible; los colores ambientales pueden verse sin bajar el contraste del contenido.
- Selección: tinte rojo existente translúcido, texto claro y una señal persistente de contorno/superficie. Un filtro seleccionado no debe parecer un botón presionado permanentemente ni depender sólo del color.
- Hover: aumento suave de luminosidad; sin subrayado, escalado ni halo. El foco de teclado tiene una señal propia, visible aunque no haya hover.
- Presionado: respuesta breve de superficie/brillo; no modificar medidas ni provocar saltos.
- Deshabilitado: contraste atenuado, sin interacción o hover activo. Carga: conservar ancho y etiqueta accesible, integrar spinner sin desplazar los controles vecinos.
- Acciones: base neutra para Aleatorio/Guardar/herramientas; una variante prominente sólo cuando la jerarquía de la pantalla lo justifique. Guardado/activado es un estado persistente distinto de pulsación.
- macOS: reutilizar `compatGlass`, con disponibilidad actual y fallback macOS 15. Verificar selección visible también al reducir transparencia y con ventana inactiva: el helper actual cambia el fondo y no basta depender del tinte del material.
- Windows: reutilizar tokens acrílicos de Biblioteca y controlar las reglas de hover seleccionadas para que no borren el estado activo. Adaptación visual propia de WebView2, sin presentar CSS blur como Liquid Glass nativo.
- Excepción por función, FIX-175: fullscreen conserva proporciones compactas y lente neutra; Apple deja selección/hover/foco al control AppKit de la topbar. El tinte rojo anterior sigue siendo válido para categorías y acciones guardadas, no se impone al selector nativo.
- Mantener Reduce Motion, Reduce Transparency y alto contraste/forced colors. Las transiciones deben responder a esas preferencias.

## Arquitectura

### Apple

- [x] Definir métricas y colores de controles junto a `UI/AppTheme.swift`, en `UI/SideBControls.swift`.
- [x] Crear estilo SwiftUI común para botones, con tamaños/énfasis/selección explícitos, respetando `Button`, `Menu`, foco, accesibilidad y `isEnabled`.
- [x] Crear etiqueta común texto+icono reutilizable y selector agrupado que comparta métricas/estados; no copiar otra implementación independiente del material.
- [x] Reutilizar compatibilidad/material existentes: `LiquidGlassCompat.swift` para botones individuales y `NavigationGlassSurface` de la topbar para el selector nativo FIX-175. Selección y hover detrás del texto; no crear otra implementación del cristal.
- [x] Mantener hover/pulsación locales al control, sin observación global de reproducción ni actualizaciones de la pantalla completa.

### Windows

- [x] Agregar tokens `--control-*` a `src/lib/styles/tokens.css` con los mismos roles y medidas.
- [x] Crear `ControlButton`, `ControlFilter` y `ControlSegments` en `src/lib/components/common/`; compartir reglas en `styles/controls.css`.
- [x] Admitir iconos/contenido, loading, disabled, etiquetas, tipos HTML y callbacks tipados; conservar semántica de botón frente a enlaces.
- [x] Para pestañas de panel usar `tablist`/`tab`/`tabpanel` y navegación apropiada; para filtros usar su estado presionado/seleccionado según la función. Foco, selección visual y estado accesible comparten el mismo fallback habilitado.
- [x] Eliminar reglas locales sustituidas y acotar los selectores generales de `button`/`select`; no resolver conflictos acumulando `!important`.

La centralización es de especificación y componentes de cada plataforma. No introducir Rust, una dependencia visual externa ni un motor compartido para dibujar botones.

## Orden de implementación

1. [x] Preparar comparación local de componentes Windows sobre fondo neutro/coloreado y fixture SwiftUI de layout. Contrastar con Biblioteca/álbum/playlist y revisar estados en código/navegador. La refracción y los estados nativos Apple no se certifican con el renderer fuera de ventana.
2. [x] Extraer Biblioteca y cabecera álbum/playlist a los componentes; conservar la referencia visual y ordenar alturas de herramientas. En Windows llevar las acciones planas al material compartido.
3. [x] Migrar Inicio, filtros de Búsqueda y navegación de Explorar a categorías48. Home reserva112/168pt desde las métricas comunes; banda de filtros56pt.
4. [x] Adaptar Cola/Letras/Relacionado conservando agrupación y área útil del panel. Refinamiento FIX-175: grupo40, selector AppKit sin NavigationGlassSurface en Mac (FIX-176), variante toolbar32 en Windows. Adaptar texto→iconos según ancho del panel; sin cambiar callbacks.
5. [x] Revisar acciones de artista, refresh, orden, menús y «Ver todo»/reintentos. Mantener «Ver todo» discreto y tarjetas de género/ánimo como contenido.
6. [x] Retirar estilos duplicados, revisar adaptación, ejecutar comprobaciones automáticas y registrar FIX/PARIDAD. Aceptación manual nativa separada abajo.

## Adaptación y rendimiento

- [x] Categorías con scroll horizontal conservando fuente/alto. Search Windows a980px: viewport de filtros708px, contenido804px; Space en Videos activa/focaliza y desplaza hasta hacerlo visible. Trackpad nativo pendiente.
- [x] Grupo compacto con iconos, etiquetas accesibles y tooltip. En FIX-174 se comprobó Windows128×48px a360px; FIX-175 reduce su variante fullscreen a40/32 y verifica geometría/flechas en navegador. SwiftUI nativo cabe a160/260/420pt con alto40pt, conserva los nombres accesibles al ocultar etiquetas y mantiene el primer responder al navegar.
- [x] Preservar virtualización de Biblioteca/Novedades, identidad y scroll: sin cambios nuevos en sus implementaciones; regresiones existentes aprobadas. Hover local al control.
- [x] Cristal sólo en controles/cabeceras. Una superficie por grupo; sin animaciones de blur.
- [x] Verificar ausencia de reflow en selección/carga y resize del grupo. Apple: títulos ES/EN conservan medidas; Windows: carga conserva148,07×40px.
- [ ] Medir scroll/consumo y entrar/salir de fullscreen en apps nativas; la compilación y las capturas no demuestran FPS.

## Cierre y validación

- [x] Navegador Windows: comparación de material neutro/coloreado, ES/EN, geometría/selección, navegación por flechas/Home, carga/deshabilitado y adaptación; pantallas reales Inicio, Biblioteca, Search, Explorar, playlist y artista con bridge simulado sin cuenta/audio.
- [x] Semántica y navegación automática: cinco pruebas Windows nuevas, foco/selección sincronizados, loading sin interacción y tipo HTML nativo. Revisión de foco/selección Apple en código. Créditos de artistas conservan hover por brillo sin subrayado.
- [x] Regresiones automáticas de filtros/categorías, callbacks de play/shuffle/guardar, virtualización, recientes y playback aprobadas; no se alteraron controladores/core por este trabajo.
- [x] Apple actual, FIX-177: build-0087,640pruebas aprobadas, compiled/sourceChangedDuringBuild=false, firma estricta y diez hashes verificados. Clic/arrastre nativo en texto e iconos comprobados, lente contenida y fixture cerrado.
- [x] Apple previo, FIX-176: build-0085 con640pruebas aprobadas; cuatro focales de controles, clic/arrastre Cola→Relacionado y AX comprobados en ventana nativa desde clases de producción; fixture cerrado, app completa pendiente.
- [x] Apple previo, FIX-175 (preview rechazado; reemplazado por FIX-176): build-0084 con640pruebas aprobadas (182Rust/151XCTest/307Swift Testing;7live Rust ignoradas); cuatro pruebas de controles, incluidos layout NSHostingView y teclado/callbacks AppKit. BUILD.json compiled/sourceChangedDuringBuild=false; firma estricta y diez hashes verificados.
- [x] Windows actual, FIX-175: `pnpm check`0errores/0advertencias; `pnpm test`354aprobadas/1omitida exclusiva Windows; `pnpm build`frontend aprobado con aviso habitual de chunk grande. No se produjo instalador Windows desde Mac.
- [x] Componente Mac en ventana nativa aislada con fondo coloreado, nombres completos, selección por clic y árbol AX de tabs comprobados. FIX-176 elimina la banda observada y verifica clic/arrastre por AX. El fixture reutiliza las clases de producción, sin cuenta/audio.
- [x] Diff revisado y `git diff --check` aprobado; FIX-174/175/176, PAR-030 e índice actualizados. Sólo documentación modificada después de compilar.
- [ ] Aceptación visual de apps nativas con fondos/animación e idiomas; macOS15, ventana inactiva, Reduce Transparency/Reduce Motion/alto contraste del sistema y WebView2 real.
- [ ] VoiceOver/Narrator y teclado/trackpad nativos completos; smoke con cuenta/audio real y mediciones de rendimiento.

La corrección FIX-177 conserva una sola superficie nativa y el host40, aumentando bezel a36; build-0087 aprobada,640pruebas, compiled/sourceChangedDuringBuild=false, firma estricta y diez hashes comprobados. Los renderizados Apple fuera de ventana de FIX-174 no acreditan el aspecto de Liquid Glass; FIX-175 retiró ese exportador de pruebas al pasar a AppKit y comprobó el componente en una ventana real aislada. No se abrió ni instaló el bundle de Side B; tampoco se publicó o guardó un commit. Las ventanas, pestañas y procesos temporales de comparación quedaron cerrados.
