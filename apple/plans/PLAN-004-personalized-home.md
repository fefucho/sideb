# PLAN-004 — Inicio personalizado

- Estado: FIX-100 implementado; ambiente FIX-108 y movimiento FIX-109/build-0029. Paleta/renders revisados y aprobación visual del movimiento registrada en FIX-109; consumo Instruments y demás validaciones pendientes.
- Objetivo: un Inicio con luz suave de carátulas, cabecera personal y recomendaciones destacadas antes de los estantes.
- Alcance: Apple; Speed Dial 3×3 con hasta tres páginas de canciones que inician radio; una a tres columnas de dos álbumes según espacio, hasta seis visibles y páginas locales, reproducción y shuffle canónico; adaptación a ventana estrecha; cabecera completa dentro del scroll existente.
- Exclusiones: core/proveedor nuevos, inventar recomendaciones o metadatos, modificar Windows, cambiar shell/toolbar/fullscreen o controlar la laptop. Se usan recomendaciones reales del feed disponible; pueden existir menos páginas.
- Referencias: mockups del usuario de 2026-10-03; HomeView/HomeFeedTableView/HomeViewModel; FIX-095 (capas), FIX-096 (flechas), FIX-097 (shuffle), antecedentes históricos FIX-027/029/030 de rendimiento de Inicio.
- Responsables: integrador selecciona datos, conecta acciones/cuenta y revisa; Luna implementa HomeFeaturedView y HomeAmbientBackground en archivos independientes.

## Pasos

- [x] Revisar reglas, historial y contratos existentes.
- [x] Selección determinista de hasta 27 canciones / 6 álbumes, prioridades personalizadas, deduplicación y estantes restantes.
- [x] Vistas destacadas con páginas independientes, accesibilidad y tamaños adaptativos.
- [x] Paleta acotada con imágenes pequeñas y fondo común de ventana detrás de sidebar.
- [x] Integrar cabecera personal, altura real del header y reproducción protegida ante respuestas obsoletas/cambio de cuenta.
- [x] Revisar diff y pruebas de selección, concurrencia, geometría y paleta; compilar mediante runner numerado.
- [x] Registrar FIX-098, paridad y ruta de build.
- [x] Corregir medidas de destacados desde viewport nativo, separar cabecera y mantener identidad durante sidebar.
- [x] Álbumes sin fondo, portada/nombre alineados y resumen real con acciones Liquid Glass.
- [x] Compilar FIX-099 en runner numerado y registrar resultado.
- [x] FIX-100: intro/destacados en una superficie, reconciliar altura real tras remount, columnas adaptativas y etiqueta dentro de portada.
- [x] FIX-100: fundido local, gestos separados de historial, metadata con concurrencia acotada y color cromático real.
- [x] Compilar FIX-100 y registrar build.
- [ ] Validación visual/audio por el usuario: tamaños con sidebar abierta/cerrada, paginación, radio, álbum/shuffle y fullscreen.

## Cierre

Conservar reciclaje AppKit y scroll completo; no indicadores horizontales nuevos. No crear NSWindow ni abrir la app. Una build aprobada no certifica apariencia, FPS ni audio real.

## Resultado automático

[FIX-098](../../FIXES.md#fix-098), [PAR-003](../../PARIDAD.md). Build `builds/macos/build-0012/Side B.app`: release arm64/SDK 27.0, macOS 15 mínimo, firma verificada; metadata `compiled` y fuentes estables. 14 comprobaciones focales; runner completo con 180 pruebas Rust, 29 XCTest y suite Swift Testing de 114 casos (7 live omitidos). Se excluyó la prueba de montaje que crea NSWindow. No se abrió la app. Apariencia/fluidez/audio quedan para el usuario.

## Corrección tras feedback del usuario

[FIX-099](../../FIXES.md#fix-099): fila propia de destacados medida por el viewport AppKit en cada ancho de sidebar; cabecera/chips permanecen en scroll. Espaciado de categoría, álbumes sin fondo, fila de altura de carátula con nombre alineado arriba y acciones Liquid Glass. Catálogos de los dos álbumes visibles aportan año/canciones/duración con caché de seis y protección de sesión. Build `builds/macos/build-0013/Side B.app`: 180 pruebas Rust, 30 XCTest y suite Swift Testing de 124 casos aprobados (7 live omitidos); firma verificada, SDK 27.0/mínimo 15.0, BUILD.json compiled/sourceChangedDuringBuild false. Fuentes estables; no app ni ventanas abiertas. Validación real de diseño/animación/audio permanece a cargo del usuario.

## Paginación, layout y ambiente revisados

[FIX-100](../../FIXES.md#fix-100) sustituye las dos superficies de FIX-099 por una sola fila SwiftUI de intro/destacados, medida por AppKit con reconciliación de la altura real al volver de páginas. Grilla alineada, 1–3 columnas de álbumes (2/4/6 visibles), texto íntegro dentro de portada, fundido de 140 ms acotado a cada panel y gestos locales separados del historial. Metadatos de visibles con dos fetches simultáneos máximo; sampler de color cromático y hasta cuatro portadas pequeñas. Build-0014: 180 Rust, 34 XCTest y suite Swift Testing de 127 casos aprobados (7 live omitidos); firma/SDK/mínimo y fuentes estables verificados, BUILD.json compiled. Sin abrir/controlar app ni crear ventanas. Animación visual, gestos reales, fondo y audio pendientes del usuario.

## Difuminado revisado tras feedback — FIX-108

El usuario rechaza el ambiente marrón de Inicio. FIX-108 conserva hasta tres acentos por portada y elige familias de tono distintas; superficie independiente con base grafito, zonas de luz más acotadas y caída suave hacia abajo. Contraluz derivada y tenue cuando sólo hay una familia cromática, evitando un lavado sepia. Se conservan cuatro imágenes pequeñas, LRU 64, cálculo fuera del main actor, transición/Reduce Motion/cancelación/cuenta y capas existentes; no modifica fullscreen, navegación ni fuentes de recomendaciones.

Siete pruebas focales aprobadas; runner final build-0027: 180 Rust (7 live ignorados), 47 XCTest y 177 Swift Testing/5 suites aprobados. Firma verificada, compiled/sourceChangedDuringBuild false. Renders de la superficie SwiftUI de producción con paletas de ejemplo cálida/contrastada/neutra revisados sin NSWindow ni abrir/controlar app. Comparación del mismo fixture RGBA mediante caminos viejo/nuevo en `builds/macos/build-0027/previews/comparison-smoke.png`; PNGs y fuente del diagnóstico conservados. No equivale a captura del feed real ni benchmark de FPS. Apariencia con carátulas/vidrio reales y medición Instruments permanecen pendientes.

[FIX-108](../../FIXES.md#fix-108), [PAR-003](../../PARIDAD.md). Build `builds/macos/build-0027/Side B.app`; versiones anteriores conservadas, sin cambios core/Windows ni commit/push.

El usuario aprueba los colores y solicita luz con humo: integrada neblina con vetas suaves mediante máscara procedural de opacidad 384×256, calculada una vez en utility y compartida sin datos de cuenta. La misma paleta tiñe el humo; textura estática, aparición breve con Reduce Motion y caída vertical. Renders nativos cálido/contrastado/neutro con la fábrica de producción revisados. Build-0027 vuelve a aprobar el runner completo; 0026 sin humo conservada. Sin nuevas consultas, imágenes grandes ni recalcular textura por scroll/resize. Rendimiento por Instruments y apariencia con sesión real siguen pendientes.

## Referencia vigente de ambiente y auditoría de paridad

FIX-109/build-0029 añade dos capas de humo con deriva/parallax y radiales móviles, cadencia programada de 30 actualizaciones/s y pausa por scenePhase/Reduce Motion. Sustituye el humo estático de 0027 como referencia actual; conserva paleta/máscara de FIX-108. [PAR-003](../../PARIDAD.md), [guía §6](../../PORTEO-INICIO.md#6-fondo-de-portadas-con-humo-animado), [FIX-110](../../FIXES.md#fix-110) actualizan seguimiento. La aprobación visual registrada no demuestra consumo ni FPS; PLAN-008 sigue propuesto.
