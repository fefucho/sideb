---
trigger: glob
globs: ["apple/**/*.swift", "apple/**/*.xcodeproj", "apple/**/Package.swift"]
---

# Side B v2 — SwiftUI, AppKit y macOS (2026)

Leer `.agents/skills/swiftui-pro/SKILL.md` para trabajo de interfaz, interacción o rendimiento. El SDK de desarrollo es Xcode 27; `Package.swift` admite macOS 15+.

## Arquitectura y comportamiento

- Respetar las cuatro capas y el centrado de la barra sobre el área de contenido de `documentation/UI_ARCHITECTURE.md`. La vista fullscreen vigente es `FullscreenNowPlayingView`; comprobar nombres y rutas actuales antes de editar.
- Reproducir con AVPlayer y mantener integraciones del sistema. Consumir los modelos tipados de UniFFI; evitar parseo JSON de datos del Core dentro de vistas.
- Preferir controles de sistema, navegación de teclado, VoiceOver, estado de foco y menús reales. Mantener acciones completas durante cambios de arquitectura.

## Diseño macOS 27 con compatibilidad macOS 15+

- Liquid Glass corresponde a controles y navegación destacados; evitar aplicarlo de forma masiva a tarjetas y fondos de contenido. Usar APIs nativas con `#available` y revisar contraste, transparencia reducida y apariencia de ventana inactiva.
- Preservar el título, toolbar y controles de ventana nativos. No fijar offsets para imitar el sistema sin comprobar resize, sidebar y versiones admitidas.

## Rendimiento medido

- Elegir `List`, `Table`, stacks lazy, `NSTableView` o `NSCollectionView` según contenido y trazas. `NativeTrackTableView` es la referencia existente para listas largas de pistas; un feed heterogéneo puede necesitar otra composición. No existe un umbral universal de 20 elementos ni una garantía universal de 15 celdas.
- Mantener identidad estable de filas y tarjetas; limitar tareas de imágenes, decodificar fuera del hilo principal y actualizar `NSView`/`NSImageView` en el hilo principal. Revisar el coste de invalidaciones por estado observable, hover, efectos y cambios de tamaño.
- Perfilar con SwiftUI Instrument, Time Profiler, Hitches y memoria. Separar tiempo de red, Core/UniFFI y renderizado; comparar la misma build, Mac y escenario. Un objetivo de 120 Hz se verifica en pantalla compatible y con trazas, nunca por inferencia.
