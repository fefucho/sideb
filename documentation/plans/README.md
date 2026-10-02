# 📋 Side B (v2) - Registro Oficial de Planes y Epics

> **Gobernanza Pragmática**: Todo el desarrollo de Side B v2 se organiza en torno a planes estructurales modulares y verificables. Cada plan contiene su propio checklist vivo (`[ ]` / `[x]`) con división estricta de dominios (Core en Rust y Shell en Swift).

---

Windows usa ahora [su backlog vigente](../../windows/BACKLOG.md); los planes del port se conservan en [el archivo histórico](../archive/windows/README.md). Este índice mantiene los planes macOS y roadmaps existentes.

## 📑 Epics de Desarrollo

| Plan ID | Documento | Alcance y Módulos Clave | Estado |
|---|---|---|:---:|
| **PLAN-001** | [`PLAN-001: Motor de Audio y MVP Flotante`](PLAN-001-motor_audio_avplayer.md) | Resolución de streams AAC (itag 140/141), records UniFFI tipados, `AudioPlayerService` nativo (`AVPlayer`), Scrubber y primera barra flotante. | ✅ **Completado** |
| **PLAN-002** | [`PLAN-002: Shell de 4 Capas, Sidebar y Feed de Inicio`](PLAN-002-navegador_paginas_y_ui.md) | Shell de 4 capas, Sidebar colapsable, `NavigationRouter` con historial `⌘[`/`⌘]`, Home dinámico con chips y continuaciones, y Player Bar macOS 26. | ✅ **Completado** |
| **PLAN-003** | [`PLAN-003: Cola de Reproducción, Automix y Radio`](PLAN-003-cola_automix_radio.md) | `QueueManager`, avance automático de pistas, tabla de cola en Fullscreen, automix continuo infinito y radio por canción. | ✅ **Completado** |
| **PLAN-004** | [`PLAN-004: Catálogo y Búsqueda Reactiva`](PLAN-004-catalogo_y_busqueda.md) | Detalle de Playlist y Álbum con `NativeTrackTableView`, paginación de listas largas, biblioteca, página de Artista y Búsqueda global con modal Spotlight. | ✅ **Completado** |
| **PLAN-005** | [`PLAN-005: Modo Fullscreen y Letras Sincronizadas`](PLAN-005-fullscreen_y_letras.md) | Overlay cinematográfico `FullscreenNowPlayingView`, selector de pestañas (Cola/Letras/Recomendados), letras interactivas a 120Hz y fallback LRCLIB. | ✅ **Completado** |
| **PLAN-006** | [`PLAN-006: Estabilización y Rendimiento Home Feed`](PLAN-006-optimizacion_rendimiento_home_feed.md) | Erradicación de regresiones de FPS, diffing estable de listas en SwiftUI, aislamiento de estado y prefetching de imágenes. | ✅ **Completado** |
| **PLAN-007** | [`PLAN-007: Menús Contextuales por Entidad`](PLAN-007-menus-contextuales.md) | Definición y contrato unificado de acciones contextuales para canciones, álbumes, artistas, playlists y radios. | ✅ **Completado** |
| **PLAN-008** | [`PLAN-008: Ejecución y Despacho de Acciones en Menús`](PLAN-008-fix-acciones-menus-contextuales.md) | Corrección de selectores target/action, validación de items en AppKit (`NSMenuItemValidation`) y bridging reactivo a SwiftUI. | ✅ **Completado** |
| **PLAN-009** | [`PLAN-009: Inicio con tarjetas grandes y canciones compactas`](PLAN-009-inicio-dos-formatos.md) | Dos formatos para estantes dinámicos, metadata y enlaces tipados, orden prioritario y precarga acotada. | 🧪 **Validación manual** |
| **PLAN-010** | [`PLAN-010: Proporciones y alineación de tarjetas en Inicio`](PLAN-010-pulido-tarjetas-inicio.md) | Reducir escala de las tarjetas grandes y alinear título, tipo, distintivo y artista según la altura real del texto. | 🧪 **Validación manual** |
| **PLAN-011** | [`PLAN-011: Navegación con trackpad y botones laterales del mouse`](PLAN-011-gestos-navegacion.md) | Gestos Atrás/Adelante sin animación, respetando el scroll horizontal y el router por ventana. | 🧪 **Validación manual** |
| **PLAN-012** | [`PLAN-012: Información de Genius en Side B v2`](PLAN-012-genius-v2.md) | Resolución conservadora, contenido tipado, caché SQLite, carga tras iniciar audio y corrección manual. | 🧪 **Validación de proveedor y rendimiento** |

---

## 🧭 Planes Maestros, Diagnósticos y Futuro

- [**`PLAN-MASTER-correcciones-auditoria.md`**](PLAN-MASTER-correcciones-auditoria.md): Plan de resolución integral derivado de la auditoría del 24 de septiembre (26 hallazgos A01 a A26 agrupados en 8 secciones de arquitectura y estabilidad).
- [**`ROADMAP-2026-yt-music-completo.md`**](ROADMAP-2026-yt-music-completo.md): Hoja de ruta para completar la experiencia de YouTube Music (biblioteca de usuario, playlists privadas, subidas de archivos, videos musicales y sesión offline).
- [**`PLAN-home-performance.md`**](PLAN-home-performance.md): Plan complementario de análisis de rendimiento y scroll en el feed de inicio.

---

## 🛠️ Plantilla para Nuevas Epics

Para crear un nuevo plan, duplicar y completar la estructura de [**`PLAN_TEMPLATE.md`**](PLAN_TEMPLATE.md).
