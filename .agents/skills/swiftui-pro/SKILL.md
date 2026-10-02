---
name: swiftui-pro
description: Diseñar, implementar o revisar la interfaz nativa de Side B en macOS 15–27 con SwiftUI y AppKit, incluyendo Liquid Glass, accesibilidad y rendimiento medido. Usar para trabajo de UI macOS del proyecto; no para cambios aislados de Rust.
---

# SwiftUI y AppKit para Side B (2026)

Trabajar sobre `apple/` y aplicar `.agents/rules/20-frontend.md`. Consultar [fuentes Apple y compatibilidad](references/apple-2026.md) al decidir sobre APIs, diseño o rendimiento de macOS 26/27.

## Decisiones que importan

- Comprobar la versión mínima en `Package.swift` y la disponibilidad de cada API en el SDK local. El host macOS 27 no convierte una API 27 en válida para macOS 15. Preferir comportamientos de sistema y usar `#available` cuando corresponda.
- Conservar la arquitectura de cuatro capas, navegación, reproducción real y acciones de `UI_ARCHITECTURE.md`. Verificar detalles concretos en el código actual; los logs de fixes son historia.
- Usar Liquid Glass en controles y navegación donde mejore la jerarquía. Dejar el contenido legible, probar contraste, transparencia reducida, ventana inactiva, tamaños de ventana y teclado. Evitar capas decorativas repetidas sin beneficio medido.
- Reducir dependencias observadas por cada vista, mantener identidad estable y preparar trabajo caro fuera de `body`. Elegir contenedores SwiftUI y AppKit según el patrón de contenido. Reutilizar `NativeTrackTableView` en tablas de pistas cuando encaje; considerar `NSCollectionView` para colecciones visuales heterogéneas si una traza lo justifica.
- Cargar y decodificar imágenes a tamaño apropiado, con concurrencia acotada y cancelación al dejar de ser visibles. Toda mutación de vistas AppKit ocurre en el hilo principal. No asumir que `AsyncImage` de macOS 27 sustituye automáticamente una caché personalizada que también soporta macOS 15.

## Verificación

Para una regresión, registrar un escenario repetible y una línea base. Usar SwiftUI Instrument, Time Profiler, Hitches y memoria; marcar con `OSSignposter` límites de red, Core, UniFFI e interfaz si el cuello de botella no es claro. Cambiar una causa respaldada por la traza y repetir exactamente el escenario. Compilación y tests funcionales validan corrección, no FPS.
