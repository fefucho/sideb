# PLAN-028 — Relacionado en fullscreen

- Objetivo: conservar los cuatro estantes, medidas y acciones de Relacionado, con el ciclo de vida y controles actuales.
- Estado: implementado;build0166 Release compilada,1029 pruebas aprobadas (2026-10-26, America/Montevideo).
- Ámbito: Apple; core y Windows sólo consultados. Conservar cambios previos del árbol.
- Referencias: FIX-042/044 (datos y cuatro estantes), FIX-052/078 (estados/controles), FIX-104/119/121/185/236 (reciclado y observación). Windows RecommendedPanel/recommendations requieren evaluación propia.

## Pasos

- [x] Contrastar antecedentes con el código; detectar cargas duplicadas, estado anterior durante skip y controles sin identidad de playback.
- [x] Preparar estantes con identidad por ocurrencia y viewport nativo que recicle estantes/columnas; conservar270pt,3filas,44pt y avatares76pt.
- [x] Acotar carga por canción/cuenta/generación, compartir petición pendiente y cancelar al desmontar.
- [x] Conservar reproducción/radio, pausa, créditos, álbum, menús y navegación; actualizar indicador/controles comunes.
- [x] Pruebas focales y suite Swift; build numerada si herramientas disponibles.
- [x] Registrar FIX y paridad; revisión de diff y límites de QA/rendimiento.

## Cierre

Validar identidad duplicada, reciclado, tamaño de viewport, scroll/foco/acciones y carreras de carga sin red. Compilación no certifica FPS, audio ni aceptación física. No publicar ni hacer push.

## Evidencia inicial

FIX-247/PAR-043. Doce focales sin red aprobadas;3000canciones/1000columnas, máximo3visibles y33configuraciones en11posiciones; reentrada vertical y offset conservados en NSWindow sin mostrar. Renders340/600pt inspeccionados en `/tmp/sideb-related-qa/`. Cuenta real/teclado/trackpad físico y FPS pendientes.

## Entrega build0166

[Registro](../../builds/macos/build-0166/BUILD.json): compiled/Release;282 Rust +269 XCTest +478 Swift Testing =1029 ejecutadas aprobadas,17 omitidas, cero fallos. Swift Testing anuncia485 incluidas7 omitidas:478 ejecutadas. Firma estricta y10hashes verificados. Doce focales incluidas. Snapshot propio361fuentes/recursos Apple/core idénticos entre inicio de regeneración y cierre. El fingerprint global cambia durante el runner (`sourceChangedDuringBuild=true`); generación de bindings y trabajo Windows simultáneo, sin afirmar una causa única del cambio ni estabilidad global. Documentación de cierre posterior al paquete. Sin cambios de fuentes propios después del build; `diff --check` focal limpio, whitespace global en bindings de búsqueda generados no editado manualmente.

Bundle: `builds/macos/build-0166/Side B.app`. Cuenta real/teclado/menús/trackpad físico y FPS quedan como validación pendiente; no se declara rendimiento perceptual medido ni se cierra PAR-043 en Windows.
