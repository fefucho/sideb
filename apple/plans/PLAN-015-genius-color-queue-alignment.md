# Colores Genius y alineación de cola desde Windows

- Fecha: 2026-10-10 (America/Montevideo).
- Estado: implementado, pruebas/renders nativos aislados y build-0073 aprobados, incluyendo feedback de canción activa y skip FIX-159/160; aceptación física pendiente.
- Objetivo: llevar a Mac el color de anotaciones de FIX-140 y corregir el centrado duración/asa observado tras FIX-145.
- Alcance: presentación Apple, duración resuelta como metadata de la ocurrencia, traducciones ES/EN y comprobaciones. Windows sólo referencia; core, transporte de audio, identidades y algoritmos de cola conservados.
- Referencias: FIX-073/113/140/145; PAR-023/PAR-009.

## Pasos

- [x] Comparar el código vigente y los antecedentes Windows/Apple.
- [x] Muestrear carátula a 32×32 con caché existente, fallback y cancelación; mantener Carátula/Contraste/Neutro y opacidades .16/.28/.48.
- [x] Centrar el texto de duración en el mismo eje del asa, sin cambiar hitboxes ni reordenado.
- [x] Verificar paletas/contraste, actualización sin reconstruir letras, acciones existentes y build numerada Mac.
- [x] Registrar FIX-157/158 y actualizar paridad con evidencia y límites.

Aceptación física del color, hover, foco y arrastre separada de pruebas/compilación. No subir/publicar antes de cerrar esta revisión.

## Resultado

FIX-157/158: cuatro tests de color Windows y diez focales Swift aprobados. Paletas de referencia iguales en ambos sistemas; contraste ≥4.5:1 en el fondo oscuro de prueba, fallback y modos verificados. NSTextView renderiza el nuevo color manteniendo texto, selección y geometría. Cuatro claves nuevas, 692 traducciones ES/EN verificadas.

Columna derecha de la celda AppKit en 350/576/900: misma Y y diferencia de centro de tinta X de 0.75 puntos, con ambos controles anclados al mismo eje. Capturas aisladas en /tmp/sideb-presentation-qa; no equivalen a la ventana completa ni a entrada física.

Runner build-0071: 182 Rust, 140 XCTest y 256 Swift Testing/5 suites, **578 aprobadas**; 7 live Rust ignoradas. BUILD.json compiled/sourceChangedDuringBuild false, release arm64/SDK 27.0/mínimo macOS 15, firma ad hoc y diez hashes verificados. App en builds/macos/build-0071/Side B.app. Sin cambios core/Windows, commit, push ni publicación; documentación posterior a la build.

## Feedback: canción activa de la cola

FIX-159: Like no marcado debe permanecer visible en la ocurrencia activa, incluso pausada. Si el catálogo omite la duración, mostrar el tiempo resuelto del reproductor sólo para esa ocurrencia; —:— durante resolución. Preservar reemplazo duración/asa al hover/foco y limpiar estado al reciclar. Windows pendiente de este ajuste; sin cambiar audio ni cola autoritativa.

- [x] Corregir visibilidad y fallback sólo de presentación.
- [x] Comprobar pausa, reuso, duplicados, resolución tardía/duración inválida y prioridad de catálogo; compilar build numerada.

Siete focales Swift aprobadas; inspección de renders AppKit a 350/576 confirma corazón y tiempo visibles en reposo. Runner build-0072: 182 Rust + 140 XCTest + 258 Swift Testing/5 suites = **580 aprobadas**, 7 live Rust ignoradas. 692 claves ES/EN verificadas. BUILD.json compiled/sourceChangedDuringBuild false, SDK 27.0/arm64/mínimo macOS 15, firma ad hoc y diez hashes comprobados; XCFramework/bindings sin diff. App: builds/macos/build-0072/Side B.app. Sin apertura automática, cuenta/audio ni aceptación física; core/Windows intactos, sin push/publicación. Documentación de cierre posterior a la build.

## Feedback: primera canción después de saltar

FIX-160 completa el alcance insuficiente de FIX-159: Like disponible en toda la cola y duración resuelta conservada en la ocurrencia original al avanzar, retroceder y restaurar sesión. El catálogo tiene prioridad; duplicados no heredan el dato. Persistir metadata válida una vez, sin reconstruir cola ni cambiar transporte de audio; Dislike/asa mantienen hover/foco.

- [x] Conservar duración resuelta faltante y mostrar Like en todas las filas.
- [x] Comprobar skip/back, duplicados, restauración, datos inválidos, prioridad de catálogo y cuenta distinta; nueva build numerada.

Nueve focales Swift aprobadas. El caso nuevo ejecuta playNext/playPrevious con dos ocurrencias del mismo video y comprueba la duración/Like de la primera celda ya inactiva, duraciones independientes, IDs/token estables, restauración y cuenta distinta. Runner build-0073: 182 Rust + 140 XCTest + 260 Swift Testing/5 suites = **582 aprobadas**, 7 live Rust ignoradas. 692 claves ES/EN verificadas; BUILD.json compiled/fuentes estables, SDK 27.0/arm64/mínimo macOS 15, firma ad hoc y diez hashes verificados. App: builds/macos/build-0073/Side B.app. XCFramework/bindings sin diff, core/Windows/transporte de audio intactos. Sin aceptación física, apertura automática, cuenta/audio real ni push/publicación; cierre documental posterior a build.
