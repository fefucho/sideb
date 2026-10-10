# PLAN-005 — Texto Genius y prueba de color de anotaciones

- Fecha: 2026-10-10 (America/Montevideo).
- Estado: implementación, revisión y verificación automatizada terminadas; build-0007 conservada. Aceptación visual nativa pendiente.
- Objetivo: corregir envoltura/alineación de letras según NSTextView Apple y permitir comparar resaltado derivado de carátula o de contraste. Retirar menú superior Side B por pedido.
- Ámbito: presentación Windows; Apple sólo lectura, core/cola/audio intactos. Antecedentes: FIX-073 Apple y FIX-137/139 Windows, build-0006.

## Pasos

- [x] Sustituir fragmentos botón atómico por texto inline accesible que envuelve junto con texto plano, alineado a izquierda; conservar selección, teclado y popup sobre el renglón clicado.
- [x] Comparar colores Carátula/Contraste/Neutro desde opciones Genius; neutral Apple blanco .16/.28, activo .48; evitar rojo fijo y respuestas de imagen obsoletas.
- [x] Subagente: retirar menú superior Side B y código sin callers; conservar flechas, drag, atajos y acciones de otras superficies.
- [x] Revisión cruzada y visual con líneas largas, parciales, saltos, distintos IDs, caracteres acentuados y ventana angosta; errores y ausencia de cover.
- [x] Check/tests/build, registro FIX/PAR y build numerada para probar. No commit/push.

## Cierre

Separar fixture/navegador de WebView2 y audio/cuenta real. Cambios de color experimentales no se declaran paridad Apple. Registros: [FIX-140](../../FIXES.md#fix-140), [FIX-141](../../FIXES.md#fix-141), PAR-015/016-2/019/023. Cola: [PLAN-006](PLAN-006-queue-presentation.md) revisado, sin implementación en esta etapa.

## Revisión y evidencia

- Origen Apple GeniusPanelView.swift: draw líneas 570–586, highlightRects 605–635, setLyrics 737/742. Texto continuo, blancos .16/.28 y activo .48; fuente 20 semibold y encabezado16 bold. Recorta fondo de espacios, no el texto.
- Causa destino: button conserva caja atómica y alineación centrada aunque se configure display:inline. Se reemplaza por span inline con rol/foco/teclas y fondo por fragmento; conserva IDs repetidos y texto exacto, separando whitespace marginal sin resaltarlo.
- Supervisor aceptó observaciones del agente: capturar renglón antes del await; cancelar apertura pendiente si cambia scroll/tamaño; teclado elige primer fragmento visible; Enter/Space sin repeat, scroll ni toggle de reproducción.
- Fixture real GeniusPanel + TitleBar: ventana1280×720/panel560 y ventana420×720. Línea larga: tres rectángulos con x20 y anchos430/454/261; angosta: cuatro con x20. Texto parcial mantiene concatenación original, sin cajas independientes. No botón Side B.
- Colores comprobados: portada azul→97/147/203; contraste→169/131/88; portada verde en contraste→180/108/208; neutro255/255/255. Cambio de estilo conserva texto. Fallo/CORS/carátula ausente usan fallback gris.
- Revisión final del subagente detectó contraste insuficiente en neutro activo blanco .48. Corregido: normal/hover blancos, selección con acento de carátula acotado; fallback gris también acotado. Prueba ampliada con texto real #f4f4f5, fallback y neutro activo: contraste ≥4,5:1 sobre el fondo oscuro de prueba. Las 14 pruebas focales volvieron a pasar.
- Clic en segundo renglón: flecha centrada en ese fragmento; Escape cierra y retorna foco. Space abre span; clic exterior cierra. Rutas temporales/Vite/navegador cerrados; fixture sólo en `.cache/`.
- Pruebas focales: 14 highlight/popover aprobadas; subagente menú 18 navegación/Space/F11 aprobadas. Check integrado final: 0 errores/0 advertencias. Suite completa y build aprobadas según cierre siguiente.
- Sin tocar queue funcional. Nueva petición independiente: análisis/plan de presentación de cola, PLAN-006; no implementación autorizada en esta etapa.

## Resultado de cierre — 2026-10-10 12:44 (America/Montevideo)

- `node Scripts/build-version.mjs windows`: exit 0; protocolo verify/build aprobado, release conservada. `pnpm check`: 0 errores/0 advertencias; `pnpm test`: 264/264; `pnpm build`: aprobado.
- Rust: InnerTube 92, core 90 sin bridge +92 con bridge, player 4 y Tauri 78. Total nativo 356; integrado **620 aprobadas**, cero fallos, 14 live ignoradas. Advertencias históricas de campos sin uso y enlazador conservadas.
- [build-0007/sideb-windows.exe](../../builds/windows/build-0007/sideb-windows.exe), junto con libmpv-2.dll, vulkan-1.dll y VulkanRT-License.txt. [BUILD.json](../../builds/windows/build-0007/BUILD.json): compiled/release, sourceChangedDuringBuild false. Cuatro SHA256 comprobados. [Log](../../builds/windows/build-0007/build.log). Builds anteriores conservadas.
- Diff whitespace limpio; sin cambios Apple/core. No se abrió el EXE ni se probó Genius/cuenta/audio real, Narrator, DPI o WebView2 físico. La revisión visual usó fixture en navegador. Sin commit/push/publicación.
- PLAN-006 comparado por subagente y revisado por integrador contra constraints Apple/markup Windows: orden común Dislike → Like → duración/grip, conservando acceso al menú antes del grupo. Es un plan de presentación, sin cambios de funcionamiento ni implementación de cola en esta build.
