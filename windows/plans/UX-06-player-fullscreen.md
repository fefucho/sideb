# UX-06 · Barra de reproducción y fullscreen

## Decisión
Portar geometría real de macOS. El bug de scroll viene de `overflow:auto` exterior y un grid con min-height: el contenido largo expande la pantalla. Fijar altura del contenedor y de todos los ancestros; sólo panel derecho desplaza su contenido, carátula y metadata permanecen estables.

## Geometría y contrato
- PlayerBar macOS: cápsula max-width 820, alto 74; progreso arriba (padding x32, alto14, tiempo10.5); controles gap14/paddingx20. Orden transport → separador → portada/metadata/like/más → lyrics/queue/volumen/fullscreen. Mantener tamaño de iconos, portada y tipografía al reducir ancho; truncar metadata y desplegar volumen con una huella fija de 32px. Mantener seek, retry, audio real y accesibilidad. SVG coherentes, no emojis como iconos.
- Fullscreen top52, reserva inferior112; paddingX clamp(24,3.5vw,48), gap clamp(24,2.8vw,40). Área disponible H=max(200,H−52−112). Derecho ideal 52% del ancho disponible, máximo 56%, mínimo340 limitado al espacio. El techo base de 600px crece en ventanas altas (máximo entre 600 y 0.875×altura máxima de carátula). Limitar la columna izquierda a altura máxima de carátula/0.9; centrar ambas columnas juntas cuando sobra ancho para conservar la separación. Cover=min(90%columnaIzquierda,H−16−68−16), centrado junto a metadata (gap16,height68).
- Tabs Cola/Letras/Relacionado centrados sobre panel; alto40/gap14. Panel derecho altura disponible−54, min-height0; cola con encabezado fijo, sólo lista overflow:auto y overscroll containment. Exterior height/max-height100dvh overflow:hidden; grid hijos min-width/min-height0. Mantener dos columnas desde mínimo app960×640, compactar contenido sin volver toda la pantalla scrollable.
- Callbacks existentes compatibles. Nuevos opcionales: `onOpenArtist(id)`, `onOpenAlbum(id)`, `onOpenMenu(event)`, `onSelectPanel("queue"|"lyrics"|"related")`, prop `selectedPanel`; root es dueño del tab y presentación expandida; F11 nativo permanece independiente (UX-02). Queue row abre menú por entryId. Mostrar cola aunque no haya pista actual. Letras/Relacionado siguen placeholders explícitos hasta su tarea de proveedor.
- Referencia exacta: `apple/Sources/SideB/Views/Components/PlayerBarView.swift` y `Views/Fullscreen/FullscreenNowPlayingView.swift` (usar fórmulas, no comentario viejo 60/40).

## Propiedad y verificación
Agente UI primera ola: sólo PlayerBar y FullscreenNowPlaying/local icon helper. Root: posición dock/metadata/callbacks/header. No editar types/root/account. Frontend check sin warnings; manual 960×640,1100×720/maximizado, scroll largo de cola, cambio pista, seek/volumen y tabs. El usuario hace QA visual mientras esté presente.
