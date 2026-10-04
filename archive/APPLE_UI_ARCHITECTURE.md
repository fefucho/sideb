# 📐 Side B (v2) - Blueprint de Arquitectura de UI

> **Documento de Referencia Obligatorio para el Agente Frontend (@frontend)**  
> Todo desarrollo de interfaz, navegación, vistas y componentes debe apegarse estrictamente a las especificaciones y jerarquía de capas definidas en este documento.

---

## 🏛️ 1. Sistema de Capas (Z-Layer Stack)

La aplicación no es un conjunto desordenado de vistas, sino una pila estricta de 4 capas visuales superpuestas:

```
┌────────────────────────────────────────────────────────────────────────┐
│  CAPA 3: ISLA DE REPRODUCCIÓN FLOTANTE (Player Bar Flotante)           │
│  • Centrada exclusivamente sobre el Área de Contenido (no con sidebar) │
│  • Liquid Glass (ultraThinMaterial + resplandor + borde sutil)         │
├────────────────────────────────────────────────────────────────────────┤
│  CAPA 2: VISTA FULLSCREEN / AHORA SUENA (Big Picture Overlay)          │
│  • Se despliega por encima del navegador de páginas                    │
│  • Artwork grande a la izquierda, paneles a la derecha                 │
│  • 3 botones superiores derechos: [Cola 📋] [Letras 🎤] [Sugerencias ✨]│
├────────────────────────────────────────────────────────────────────────┤
│  CAPA 1: NAVEGADOR DE PÁGINAS (Content Browser Stack)                  │
│  • Rutas web: Inicio, Búsqueda, Álbum, Artista, Playlist, Biblioteca   │
│  • Historial con Back (◀) y Forward (▶)                               │
│  • Ciclo de vida ligero: no retiene 50 páginas en memoria              │
├────────────────────────────────────────────────────────────────────────┤
│  CAPA 0: SHELL DE VENTANA Y SIDEBAR (Estructura Base macOS)            │
│  • Sidebar flotante colapsable (230px, margen uniforme de 6px, esquinas de radio 10px)       │
│  • Área de contenido dinámico a la derecha                             │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 🧭 2. Capa 1: Navegador de Páginas (Browser Stack con Historial)

### Filosofía de Navegación
Funciona idéntico a un navegador web o a Apple Music:
- Las páginas no se apilan infinitamente consumiendo memoria.
- Existe un objeto reactivo central: `NavigationRouter`.
- Si el usuario navega a un álbum y luego al artista y luego al inicio, puede usar **Atrás (◀)** y **Adelante (▶)** o atajos de teclado (`⌘[` y `⌘]`).

### Modelo del Router
```swift
enum PageDestination: Equatable, Hashable {
    case home
    case search(query: String?)
    case album(browseId: String)
    case artist(browseId: String)
    case playlist(browseId: String)
    case library
    case history
}

@Observable
final class NavigationRouter {
    var history: [PageDestination] = [.home]
    var currentIndex: Int = 0
    
    var currentPage: PageDestination { history[currentIndex] }
    var canGoBack: Bool { currentIndex > 0 }
    var canGoForward: Bool { currentIndex < history.count - 1 }
    
    func navigate(to destination: PageDestination) {
        // Truncar historial adelante si estábamos en medio
        if currentIndex < history.count - 1 {
            history.removeSubrange((currentIndex + 1)...)
        }
        history.append(destination)
        currentIndex = history.count - 1
    }
    
    func goBack() {
        guard canGoBack else { return }
        currentIndex -= 1
    }
    
    func goForward() {
        guard canGoForward else { return }
        currentIndex += 1
    }
}
```

---

## 🏝️ 3. Capa 3: Isla de Reproducción Flotante (Player Bar)

### Regla Crítica de Posicionamiento y Centrado Geométrico
- **NO se centra respecto a la ventana completa** si la barra lateral está visible.
- **Se centra exclusivamente respecto al Área de Contenido**:
  - Si la Sidebar está expandida (242px con márgenes, definidos en `ShellLayout`), la isla se centra en el espacio restante `(WindowWidth - 242px)`.
  - Si la Sidebar está colapsada (0px), la isla se centra automáticamente en toda la ventana.
- **Implementación**: La isla flota en el `overlay` o pie del contenedor del `ContentArea`, con `padding(.bottom, 20)`.

### Estilo Visual (Liquid Glass & Apple Music Simplicity)
- **Material**: `.background(.ultraThinMaterial)`.
- **Forma**: Cápsula o rectángulo con esquinas redondeadas (`cornerRadius: 16` a `20`).
- **Borde**: `RoundedRectangle.stroke(Color.white.opacity(0.12), lineWidth: 1)`.
- **Sombra**: Sombra difusa suave para despegarla del contenido en scroll (`color: .black.opacity(0.25), radius: 15, y: 8`).
- **Ancho**: Responsivo pero acotado (máximo 820px, mínimo 600px).

### Componentes Internos de la Isla (100% cableados, cero botones ciegos)
1. **Izquierda (Track Info)**:
   - Thumbnail cuadrado (44x44) con esquinas redondeadas.
   - Resplandor sutil detrás del thumbnail con los colores predominantes del arte (`ArtworkGlow`).
   - Título de la pista (con scroll marquesina si desborda).
   - Artista (clicable para navegar a su página).
   - Botón de Like / Favorito (corazón) conectado a `rate_song`.
2. **Centro (Controles & Scrubber)**:
   - Botones: Shuffle, Anterior, Play/Pause principal grande, Siguiente, Repeat.
   - Barra de progreso suave (`AppleMusicScrubber`):
     - Tiempo transcurrido a la izquierda (`1:23`).
     - Barra deslizante que permite arrastrar y soltar para hacer seek.
     - Tiempo restante a la derecha (`-2:45`).
3. **Derecha (Herramientas & Expansión)**:
   - Slider de volumen con icono de altavoz.
   - Botón para abrir la **Vista Fullscreen / Big Picture** (Capa 2).
   - Botón para abrir el **Mini Player flotante** de escritorio.

---

## 🌌 4. Capa 2: Vista Fullscreen / Big Picture Overlay

### Comportamiento
- Se despliega suavemente por encima del navegador de páginas mediante una transición de resorte (`.spring(response: 0.45, dampingFraction: 0.85)`).
- La música **sigue sonando ininterrumpidamente**; solo cambia el modo de visualización.
- La isla de reproducción flotante se oculta o se integra limpiamente en la parte inferior del modo fullscreen.

### Distribución de la Vista Fullscreen
- **Fondo**: Resplandor dinámico generado a partir de la carátula actual con desenfoque extremo (`blur(radius: 60)` y opacidad oscura para alto contraste).
- **Zona Superior Derecha (Los 3 Botones Clave)**:
  1. 📋 **Cola (Queue)**: Abre el panel lateral derecho con las canciones siguientes y permite reordenar/eliminar.
  2. 🎤 **Letras (Lyrics)**: Muestra las letras sincronizadas en tipografía grande con scroll automático y salto al hacer clic en una estrofa.
  3. ✨ **Recomendados / Relacionados**: Muestra canciones similares generadas por el radio/automix de YouTube Music.
- **Zona Izquierda / Central**:
  - Artwork en alta resolución (grande, con bordes redondeados y sombra tridimensional).
  - Título, artista y metadatos detallados.

---

## 🚫 5. Mandamientos Inquebrantables para el @frontend

1. **PROHIBIDO crear botones sin acción**: Si un botón no tiene su ViewModel o endpoint de Rust listo, **no se dibuja**.
2. **PROHIBIDO hardcodear mocks que tapen bugs**: Toda vista debe aceptar un ViewModel con datos reales o un estado vacío explícito (`EmptyStateView`).
3. **Respeto a la Geometría**: Nunca uses offsets fijos que rompan el centrado de la isla flotante al cambiar el tamaño de la ventana o colapsar la barra lateral.
4. **Fluidez 120Hz**: Todas las animaciones de scroll y transiciones deben usar tipos nativos de SwiftUI (`Animation.interactiveSpring`, materiales nativos) sin bloquear el hilo principal.

## Navegación de la ventana macOS

La toolbar nativa usa `unifiedCompact(showsTitle: false)` y conserva los semáforos del sistema: el centro de Cerrar se ancla en (28, 28), preservando el tamaño y separación originales y restaurando su posición al entrar al fullscreen del sistema. El toggle de sidebar ocupa `.navigation`, sin fondo, en (116, 28).

El resto de la navegación se aloja en un único item `.primaryAction`: `NativeNavigationHeader` dispone el selector principal y el historial en el mismo espacio de coordenadas. Su anchura sigue la ventana reservando 280 puntos para los controles nativos y el toggle; la altura del host se mantiene en 72 puntos. En el header se convierte una única referencia de ventana (centro horizontal de la ventana, altura 28) y se limita al viewport real. Ambas cápsulas comparten el mismo centro vertical incluso cuando esa referencia debe limitarse. No existen correcciones independientes que puedan abandonar la recolocación de uno de los grupos. La cápsula principal se centra sobre la ventana y el historial queda al borde derecho del item. Las superficies conservan su vidrio nativo y el resto de la toolbar es transparente.

El selector es un `NSSegmentedControl` de selección única de tamaño `.large`, con símbolos de 14 puntos y cápsula de 262×34 puntos. La celda se mide con `sizeToFit()`; no hay estiramiento, cambio de proporciones de símbolos ni escalado de coordenadas. AppKit administra la lente, tracking, foco y VoiceOver; macOS 27+ declara el rol `.tabs` y macOS 26+ usa borde `.capsule` y wrapper `NSGlassEffectView`, con margen de 3 puntos. El historial usa botones AppKit de 28×28 con símbolos de 13 puntos y acciones/atajos nativos: Atrás, Adelante y Actualizar (sólo en Inicio). Su cápsula mide 96×34 en Inicio y 62×34 en otros destinos. `NavigationGlassSurface` aloja ambos tipos de contenido y mantiene un tamaño exacto, independiente de propuestas de un `NSHostingView`.

Se conservan Inicio, Explorar (deshabilitado, Próximamente), Biblioteca y Buscar. Buscar abre el Spotlight existente, también mediante ⌘K y ⌘F. La selección en destinos profundos sigue el último destino principal del prefijo visitado del historial; Historial pertenece a Biblioteca. Durante Ahora suena se ocultan las dos cápsulas y se desactivan sus acciones. `ShellLayout` centraliza las medidas del panel y su reserva interna de titlebar; Inicio pasa esa reserva al documento desplazable.

La visibilidad del selector la controla un progreso animable de SwiftUI, interpolado en la misma transacción de 0.42 segundos que la transición de la sidebar. AppKit aplica ese progreso a una sola opacidad, en la superficie que aloja vidrio y contenido, más un desplazamiento vertical de hasta 8 puntos. No hay fades multiplicados entre padres e hijos ni un segundo reloj de animación o completions. El control se oculta al terminar y desactiva la interacción durante la salida. El binding de sidebar centraliza las entradas de toolbar, menú y fullscreen con la misma animación reversible. Movimiento reducido usa un fade breve; transparencia reducida y ventana inactiva reciben fondos sólidos en los controles de vidrio. SwiftUI administra la toolbar; WindowConfigurator no instala una toolbar AppKit vacía.


## Scroll de Inicio

El título, subtítulo y chips de Inicio se alojan como primera fila del `NSTableView` del feed mediante `NSHostingView`; se desplazan en el mismo documento vertical que los estantes, sin un segundo scroll vertical ni un encabezado fijado. `HomeFeedRows` mantiene el mapeo entre encabezado, categorías y fila de paginación. Los estantes conservan su scroll horizontal y el reciclado de tarjetas. El viewport de Inicio ocupa también el área superior de la ventana: la reserva inicial de controles pasa a `contentInsets.top` dentro del documento, permitiendo que el contenido scrollee detrás de los controles sin una franja fija. Los indicadores horizontales se ocultan en el entorno SwiftUI de la ventana. `HomeFeedScrollView` fuerza scroller horizontal nil/false incluso ante reasignación y tiling. Los scrollers ortogonales internos del collection compositional se revisan tras cada layout, con observadores deduplicados.
