# PLAN-019: margen, lente y movimiento de TopNav

- Estado: implementado/build0124, suite y QA funcional/capturas aprobadas; FPS físicos sin certificar. FIX-194.
- Objetivo: corregir los tres defectos reportados en0122: poco espacio superior, lente contra los extremos y movimiento entre centro/bordes entrecortado.
- Alcance: cabecera Apple, cápsulas42pt, destinos246pt, historial76pt/divisor, fusión exacta298pt y búsqueda visual con acciones/atajos conservados.
- Exclusiones: motor de búsqueda, core, Windows, instalación/publicación.
- Referencias: [PLAN-018](PLAN-018-three-navigation-capsules.md), FIX-193/192, capturas del usuario16/10 y prototipo original TopNavComparisonApp.swift.

## Pasos

- [x] Medir margen real y reservar18pt arriba (centro39), conservando host72pt y espacio inferior.
- [x] Aislar padding nativo: setWidth80 genera pista258, lentes−2/−2pt contra el exterior. Distribución nativa/frame240 del prototipo deja pista240 e insets7/7pt. Mantener KVO y no usar sizeToFit.
- [x] Separar traslación lateral del morph de anchura. CAKeyframe position aditiva/opacity de hosts exteriores; displaylink sólo para bounds reales de búsqueda.
- [x] Revisar subagentes y contratos: reversa desde presentación, resize condicionado, completions con revisión, foco/editor, Reduce Motion y fullscreen/desmontaje.
- [x] Conservar despacho nativo de input: hitTest ajusta el modelo al punto visible ante mouseDown real; devuelve el target a AppKit y retoma la traslación tras liberar el botón.
- [x] Compilar por fases y aprobar focales nativas:22XCTest+6SwiftTesting,17/10.
- [x] Generar build numerada por sideb-build-macos, suite completa/firma/hashes/fuentes protegidas.
- [x] Revisar márgenes, extremos, navegación, búsqueda/atajos y sidebar en la app real. Registrar evidencia y límites.

## Evidencia y decisiones

- Vidrio/sólido,3selecciones: pista240 e insets extremos7/7; configuración anterior reproduce258 y−2/−2. Se elimina setWidth, conservando slots nominales80.
- Fase1 swift build release aprobada;13XCTest+6SwiftTesting verdes. Focal integrada inicial detectó reloj vacío Reduce Motion/retorno fullscreen; ambos corregidos.
- 0123 falló con SIG11 del nuevo test de mouseDown reenviado: responder chain volvía al header y desbordaba stack. Estrategia retirada por completo. Un script interpretado daba1acción pero el mismo arnés compilado da0 incluso en reposo; no era evidencia válida del tracking moderno. Se conserva despacho original AppKit, sin overrides/reenvío de mouseDown.
- Focal final17/10:22XCTest+6SwiftTesting aprobadas, con target nativo bajo el puntero, modelo estable durante tracking, acción AppKit/reversa, width/foco independiente y fin de animación. No se afirma mouseUp sintético ni drag físico aprobados por esos tests.
- TimeProfiler de referencia coincide con compilación y no sirve como A/B. AnimationHitches no completó guardado; CoreAnimationFPS informa que macOS no dispone de esa métrica. No se certifican120FPS físicos.

## Cierre

Build compiled, firma/hashes válidos, suite completa y revisión en ventana real. Actualizar FIXES/PAR-007 manteniendo exclusión Windows. Evidencia de ejecución en builds/macos/build-NNNN/diagnostics.

## Resultado0124 (2026-10-17)

- 700pruebas ejecutadas aprobadas (188Rust/193XCTest/319SwiftTesting),14live omitidas; fuentes estables, firma estricta/10hashes y472archivos protegidos válidos.
- UI real1321×831pt: márgenes, ambos extremos, búsqueda exacta, foco/texto al trasladar, atajos, Back/Forward por clic de coordenadas en reposo y retorno con botón fullscreen comprobados.6toggles sidebar sin fallo funcional; no se certifica FPS ni clic/drag físico en plena traslación.
- TimeProfiler25s sin build concurrente guardado en diagnostics/FIX194-final-sidebar.trace.3282msmain,943AX/2328hosting inclusivos; no A/B válido ni medición de frames presentados.
- Bundle builds/macos/build-0124/Side B.app abierto, borrador vacío y Paradise pausada. No se modifican core/Windows ni se conecta motor de búsqueda.
