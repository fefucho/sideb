# PLAN-011: Explorar

- Objetivo: activar Explorar en Mac con lanzamientos, rankings globales y de la región actual, géneros y momentos; abrir/reproducir contenido real con los controles comunes.
- Estado: implementado y optimizado en build-0048; suite release y revisión visual con sesión aislada aprobadas. FPS/audio y gesto físico de trackpad no certificados.
- Alcance: integración Apple, rutas/historial, catálogo visual, carga bajo demanda y caché de sesión. Fix del contrato compartido de rankings para ambas plataformas; UI y bridge Windows pendientes en PAR-012.
- Referencias: [YouTube Music Explorar](https://music.youtube.com/explore), [estados de ánimo/géneros](https://music.youtube.com/moods_and_genres), [rankings](https://music.youtube.com/charts), [Spotify Explorar todo](https://open.spotify.com/search), observados en navegador el 2026-10-05 sin iniciar sesión. [Contrato charts de ytmusicapi](https://raw.githubusercontent.com/sigma67/ytmusicapi/main/ytmusicapi/mixins/charts.py) contrastado con respuestas públicas reales. FIX-090 (selector), FIX-111/112 (cartas/acciones), FIX-086 (búsqueda).

## Decisiones

- YouTube: accesos claros a novedades y rankings, categorías por momento. Spotify: tarjetas de color con títulos reconocibles. Adaptación al grafito, símbolos y cartas nativas de Side B.
- Lanzamientos reutilizan `getBrowseGrid`. Géneros/momentos son una selección inicial de Side B; al abrirlos buscan playlists mediante `searchCards`. El catálogo editorial dinámico y las posiciones individuales del ranking quedan para una etapa posterior.
- Problema compartido: Swift y el bridge Tauri sólo tenían browseId/params y devolvían tarjetas planas. El contexto del core usa gl=US; no se transportaban `formData.selectedValues`, país seleccionado ni países disponibles. Usar ese contrato para charts no permitía cumplir selección regional en ninguna app.
- Añadir contrato tipado compartido `getCharts(countryCode)`: enviar país explícito, conservar opciones/selección, exigir confirmación del proveedor y mantener filtros de contenido y rechazo de sesión expirada. Regenerar bindings con el builder; ningún cambio manual de bindings.
- Detectar país anónimo con el bootstrap público de YouTube para la conexión actual. Conservar sólo el código en memoria; no usar GPS, guardar IP/bootstrap ni alterar locale de otros endpoints. Forma desconocida devuelve región no disponible, nunca US supuesto.
- Rankings abre Global + región detectada; selector con todos los países que ofrece el proveedor. Reconsulta detección al entrar después de 10 minutos o pulsar Actualizar. Si no hay detección/soporte, mostrar Global y permitir elección manual; si falla local, conservar Global y reintentar.
- Catálogos largos y preview de novedades reutilizan las tarjetas nativas e imágenes de Inicio; rankings pequeños conservan CatalogCardView/MediaArtworkControls. Menús comunes y selección de Explorar al navegar a detalles, atrás/adelante, teclado, sidebar y búsqueda modal.
- Cachés LRU de ocho fuentes y ocho regiones, aisladas por sesión; generaciones/cancelación descartan respuestas tardías de rutas/cuenta/país. Deduplicar por clase e ID y filtrar clases desconocidas.

## Pasos y cierre

- [x] Inspeccionar referencias, menús y contratos reales.
- [x] Implementar rutas, navegación, portada y categorías.
- [x] Implementar contrato de país/rankings y selector de regiones.
- [x] Implementar carga real, cachés y estados vacío/error/refresh.
- [x] Probar carreras de rutas/sesión/país, cancelación, navegación, cambio de red y fallo parcial.
- [x] Probar proveedor público: país UY, Global y Uruguay con IDs distintos, 69 regiones, lanzamientos y playlists de concentración sin cookies.
- [x] Ejecutar pruebas completas y build numerada con skill Mac; detalles en FIX-120.
- [x] Revisar apariencia, desplazamiento vertical, acciones AX del carrusel, menús, detalle/Atrás, sidebar, categoría y selector de regiones en copias release HomeLab sin cuenta. Detalles y límites en FIX-121; no equivale a un ensayo de audio/FPS/trackpad con sesión real.
- [x] Registrar [FIX-120](../../FIXES.md#fix-120) y [PAR-012](../../PARIDAD.md); actualizar este plan/índice.

Windows comparte el core y pasó sus pruebas con `windows-bridge`, pero falta exponer los dos métodos en comandos/DTO Tauri e implementar Explorar en Svelte. No se afirma ejecución ni compatibilidad visual comprobada en Windows. Sin commit/push/publicación.

## Optimización tras feedback de build-0044

Estado: implementado en FIX-121/build-0048. Usuario reportó lag al cargar/desplazar Lanzamientos y pidió el nivel de Inicio.

- [x] Contrastar LazyVGrid/CatalogCardView con viewport y tarjetas AppKit de Inicio (FIX-102/103/119).
- [x] Capturar build-0044 y comparar con 0045: Time Profiler de 20 s, mismo Mac/tamaño, imágenes precalentadas y 40 gestos. Menos muestras main/graph, desaparece medición de LazyVGrid; catálogo dinámico y distinta duración de entrega impiden convertirlo en FPS o porcentaje universal. Render vertical final conserva ese camino.
- [x] Usar NSCollectionViewFlowLayout con viewport explícito, una cabecera SwiftUI y HomeCollectionItem/HomeItemView recicladas; imágenes/cancelación/menús de Inicio.
- [x] Preservar IDs planos, cache por sesión, carga/error/refresh, historial, menús, Play/foco/accesibilidad y selección de país. El carrusel final usa NSScrollView con scroller overlay automático; descartar ocultamiento total de 0046 que quitaba acciones AX.
- [x] Probar 5.000 álbumes hasta índice 4.900: máximo 15 tarjetas montadas. Ventana oculta y IDs de destino evitan falso positivo de fixture sin ventana. Resize, playback sin rebind, metadata/offset, sesión, reciclaje/acciones/carga, cabecera y preview hasta última tarjeta aprobados.
- [x] Ejecutar suite Swift/build numerada: release completa 182 Rust/65 XCTest/233 Swift Testing aprobada. Debug completo pasó XCTest y falló en deadlines previos de PlaylistPlaybackLatencyTests; focal de esas pruebas y Explore/Home aprobada, sin alterar reproducción. Registrar FIX-121 y ampliar PAR-012; conservar builds 0045/0046, intento 0047 (una espera previa de playlists falló; focal release aprobó en 0,027 s) y logs.

Alcance de esta corrección: render/layout Apple. Core/contrato regional y otras plataformas se conservan. Abrir 0045 normal quedó esperando en SecItemCopyMatching según sample; los mismos binarios se revisaron con namespace de sesión HomeLab aislado, sin modificar credenciales/permisos. Pruebas de conteo de vistas y trazas no certifican FPS. Evidencia, límites y comprobación final en [FIX-121](../../FIXES.md#fix-121). Sin commit/push/publicación.
