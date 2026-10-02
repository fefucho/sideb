# Fuentes Apple para Side B — revisadas en septiembre de 2026

## Compatibilidad del proyecto

- `apple/Package.swift` declara macOS 15 como mínimo. Confirmar la versión de Xcode y Swift del host antes de usar APIs nuevas.
- Liquid Glass se introdujo en macOS 26 y recibe refinamientos en macOS 27. Muchos cambios visuales del sistema se adoptan al ejecutar la app en 27; no requieren replicar el aspecto con controles personalizados.
- `AsyncImage` tiene caché HTTP por defecto en macOS 27. Esa mejora no cubre automáticamente macOS 15/26 ni todas las necesidades de tamaño, persistencia o cancelación de `ImageCache`.
- SwiftUI de 2026 mejora la inicialización de `@State` y el flujo de datos; algunas mejoras se retroportan. No atribuir una caída de FPS a un wrapper o contenedor sin registrar sus actualizaciones en Instruments.

## Cambios concretos de macOS 27 a evaluar

- Liquid Glass, sidebar, toolbar y bordes de ventana reciben ajustes del sistema. Conservar controles nativos donde sea posible y comparar su aspecto en macOS 15, 26 y 27. El efecto interactivo de vidrio está destinado a controles, no a cada tarjeta del contenido.
- AppKit incorpora mejoras de navegación por teclado, restauración de ventanas y configuración concéntrica de esquinas. Adoptarlas cuando la interfaz afectada lo necesite; comprobar disponibilidad en el SDK y no crear sustitutos manuales por defecto.
- SwiftUI y AppKit comparten más infraestructura. En vistas AppKit nuevas, valorar la observación de modelos en vez de invalidaciones manuales; validar el comportamiento de back deployment antes de aplicarlo a macOS 15.
- `AsyncImage` puede aprovechar caché HTTP del sistema en macOS 27. Comparar su política y consumo con `CachedAsyncImage` bajo el mismo escenario antes de reemplazar la caché existente.
- Instruments 27 aporta herramientas para distinguir trabajo en Main Actor, contención y bloqueo. Separar estos casos de los hitches causados por layout, imágenes o GPU.

## Diseño e interacción

- [Materiales y Liquid Glass — HIG](https://developer.apple.com/design/human-interface-guidelines/materials): separar la capa de controles del contenido y usar vidrio con moderación.
- [Modernize your AppKit app — WWDC26](https://developer.apple.com/videos/play/wwdc2026/289/): cambios de Liquid Glass en macOS 27, foco, gestos y restauración de ventanas.
- [What’s new in SwiftUI — WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/): cambios en SwiftUI, carga de imágenes y flujo de datos.
- [Use SwiftUI with AppKit and UIKit — WWDC26](https://developer.apple.com/videos/play/wwdc2026/272/): interoperabilidad y observación en AppKit.
- [Platforms State of the Union — WWDC26](https://developer.apple.com/videos/play/wwdc2026/102/): cambios de diseño y bases compartidas de los frameworks.
- [Scroll views — HIG](https://developer.apple.com/design/human-interface-guidelines/scroll-views): gestos y comportamiento esperados de desplazamiento.

## Rendimiento

- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance): actualizaciones largas, frecuencia de invalidación y causas en Instruments.
- [Optimize SwiftUI performance with Instruments — WWDC25](https://developer.apple.com/videos/play/wwdc2025/306/): traza de SwiftUI, Time Profiler y Hitches.
- [Profile, fix, and verify — WWDC26](https://developer.apple.com/videos/play/wwdc2026/268/): distinguir CPU, contención, bloqueo y Main Actor con Instruments 27.
- [Creating performant scrollable stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks): elegir stacks normales o lazy a partir del perfil.
- [NSCollectionView](https://developer.apple.com/documentation/appkit/nscollectionview): secciones, elementos reutilizables y layout de colecciones visuales.
- [Recording Performance Data](https://developer.apple.com/documentation/os/recording-performance-data): intervalos `OSSignposter`.
- [AsyncImage](https://developer.apple.com/documentation/swiftui/asyncimage): comportamiento de caché HTTP en macOS 27.
