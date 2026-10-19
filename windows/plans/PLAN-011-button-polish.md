# PLAN-011 — Acabado de botones Windows

- Fecha: 2026-10-19 (America/Montevideo).
- Estado: implementado; frontend, QA navegador y verify/build EXE Windows en CI aprobados. Aceptación visual física pendiente. FIX-221 / PAR-030.
- Objetivo: comparar los botones actuales con macOS y mejorar el acabado Windows sin cambiar acciones ni proporciones de la app.
- Alcance: tokens/CSS compartidos, iconos de acciones en álbum/playlist/artista/Explorar/Historial y acabado de los controles del reproductor. Apple y core se consultan sin editar. Preservar el trabajo local previo de sidebar y apariencia.
- Antecedentes: FIX-174 (familia común), FIX-175/176/177 (selector fullscreen compacto), PAR-030; `apple/Sources/SideB/UI/{SideBControls,LiquidGlassCompat}.swift` y componentes Windows vigentes.

## Comparación sobre código vigente

| Aspecto | macOS | Windows antes del cambio | Decisión |
|---|---|---|---|
| Tamaños | Categorías48, acciones40, utilidades32 | Mismas alturas | Conservar geometría y pesos estables |
| Material | Cristal nativo o material según disponibilidad; borde neutro10%/0,5pt | Acrílico con borde blanco20%/1px en todos los controles | Borde propio más discreto y luz superior tenue, sin alterar el material de paneles |
| Jerarquía | Material y tinte nativos | Prominente y seleccionado comparten exactamente el mismo fondo | Acción principal en rojo de marca; selección con tinte más suave |
| Iconos | SF Symbols vectoriales con geometría estable | Mezcla de SVG y caracteres ▶/⤨/▣/♧/↻ | Reutilizar SVG del sistema de iconos existente |
| Pulsación | Oscurece el material | Todos los controles adoptan tinte rojo al pulsar | Respuesta neutra, seleccionada y prominente por separado |
| Cobertura | Estilo común en acciones | Historial mantiene botones rectangulares independientes | Integrarlo con ControlButton preservando callbacks |

La comparación del material Apple es estática; no equivale a una medición visual simultánea de ambos sistemas. El navegador local muestra componentes Windows reales con datos aislados, sin cuenta ni reproducción.

## Pasos y cierre

- [x] Revisar instrucciones, antecedentes, diferencias locales y código de ambas plataformas.
- [x] Inspeccionar el aspecto Windows inicial en navegador.
- [x] Refinar tokens/superficies, estados e iconos sin alterar comportamiento.
- [x] Comprobar componentes reales, teclado, carga, tamaños y variantes sobre fondo plano/ambiental.
- [x] Ejecutar `pnpm check`, `pnpm test` y `pnpm build` frontend.
- [x] Revisar diff, registrar FIX y actualizar PAR-030/índice.

## Resultado y evidencia

- Neutros con borde11%, luz superior sutil y sombra discreta; acciones principales en rojo de marca y selección tintada. Alturas conservadas, selector fullscreen40/32.
- Iconos SVG reutilizados de MenuIcon; Historial incorpora ControlButton y el Play del reproductor comparte tokens. Callbacks y semántica vigentes conservados.
- Check0/0;386pruebas aprobadas/1omitida nativa; build frontend aprobado en `windows/build/`, con aviso de chunk grande preexistente.
- Browser1280×720 y panel574px; control compacto104px en columna360. Foco/End/flechas, carga sin salto148,0703px, Play/menú y estados Guardado/Suscrito comprobados con callbacks locales. ES/EN y replay de reglas CSS de contraste/transparencia/movimiento revisados.
- Capturas locales en `windows/.cache/button-polish/evidence/`; `windows-buttons-preview.png` muestra cabecera real de álbum y PlayerBar con datos de ejemplo. Captura inicial `before.png`; Apple comparado por código, sin medición visual nativa simultánea.
- [FIX-221](../../FIXES.md#fix-221), [PAR-030](../../PARIDAD.md). No se genera EXE desde el host Mac.

## Límites

Narrator, ejecución interactiva WebView2 y aceptación visual requieren el sistema destino. La compilación frontend en Mac no demuestra ejecución nativa. La publicación posterior se gestiona por separado en FIX-223.

## Entrega nativa posterior — FIX-223

El checkout aislado de 1.2.5/build 18 conserva únicamente los cambios autorizados y el arreglo de volumen de 1.2.4: check 0/0, 397 tests frontend sin omisiones y verify/build Windows nativos aprobados. EXE x64 con versión binaria 1.2.5.0; instalador, portable y cuatro hashes de runtime comprobados. [Release 1.2.5](../../plans/RELEASE-1.2.5.md), [CI](https://github.com/fefucho/sideb/actions/runs/39287591174). Esta evidencia amplía la fase frontend inicial; no certifica aceptación física.
