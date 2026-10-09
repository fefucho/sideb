# Planes Apple

[Formato](../../README.md#planes), [fixes](../../FIXES.md), [paridad](../../PARIDAD.md).

| Plan | Estado | Referencia |
|---|---|---|
| [PLAN-014: español e inglés](PLAN-014-localization.md) | FIX-131/build-0067: 688 claves ES/EN, 562 pruebas y QA aislada aprobadas; comprobaciones físicas pendientes | Selector primero en Configuración, cambio en vivo/persistencia, recursos instalados, IDs/cola/país y render conservados; PAR-014 |
| [PLAN-013: fullscreen con Inicio de fondo](PLAN-013-fullscreen-home-performance.md) | FIX-123/124/build-0052: 485 pruebas + 10 del runner aprobadas; caso sidebar cerrado→fullscreen→abrir y cuatro alternancias comprobados visualmente | FIX-095/109/119/122/123; viewport externo ajustado al shell, tamaño nativo interno retenido, pausa y snapshots diferidos; FPS reales sin certificar |
| [PLAN-012: navegación con gestos](PLAN-012-navigation-gestures.md) | FIX-129/build-0061: Inicio conserva scroll/páginas locales, 49 pruebas focales y 532 release aprobadas; geometría y botones comprobados, ensayo físico pendiente | FIX-125/126/127/128/129; propietarios limitados al viewport, headers/huecos con historial, secuencia fija hasta terminar |
| [PLAN-011: Explorar](PLAN-011-explore.md) | Implementado y optimizado en build-0048; suite release completa aprobada, UI en sesión aislada y trazas comprobadas; FPS/audio/trackpad físico no certificados | FIX-120/121/PAR-012; Global + región y selector, lanzamientos/categorías con tarjetas nativas recicladas y viewport acotado |
| [PLAN-010: detalle compartido de álbum/playlist](PLAN-010-collection-detail-ui.md) | Implementado; validación manual pendiente | FIX-114/build-0034 y FIX-115/build-0035; FIX-116/build-0036 ambiente continuo; FIX-117/build-0038 scroll/buscador; FIX-118/build-0039 editor desde foco y altura estable, visual pendiente |
| [PLAN-009: cartas comunes y reproducción contextual](PLAN-009-common-media-cards.md) | Implementado Apple en build-0033 (cola propia FIX-113); 52 XCTest/198 Swift Testing aprobados, validación visual/manual pendiente | FIX-111/112/113 (cola propia) · PAR-009/010; FIX-097–100/103/105–106 como antecedentes |
| [PLAN-008: limpieza y eficiencia de Inicio](PLAN-008-home-cleanup-efficiency.md) | Propuesto, sin implementar; cinco etapas independientes para ejecutar con poca cuota | [FIX-109](../../FIXES.md#fix-109), PAR-003 |
| [PLAN-007: fuentes y categorías de Inicio](PLAN-007-home-recommendation-sources.md) | Etapas 1–3 implementadas en Apple, build-0025 y pruebas completas; centrado permanente FIX-107; validación manual/rendimiento pendiente de cierre | [FIX-106](../../FIXES.md#fix-106), [FIX-107](../../FIXES.md#fix-107), PAR-006 |
| [PLAN-006: configuración de Inicio](PLAN-006-home-settings.md) | Completado en Apple: build-0021, pruebas completas y controles/overlay comprobados en ventana real | [FIX-105](../../FIXES.md#fix-105), PAR-006 |
| [PLAN-005: fluidez de Inicio](PLAN-005-home-cell-reuse.md) | Usuario confirma fluidez en 0017; FIX-104/build-0018: paginación comprobada; FIX-119/build-0039 columnas/sidebar sin recrear controles, comprobación física pendiente | [FIX-104](../../FIXES.md#fix-104), PAR-004/005 |
| [PLAN-004: Inicio personalizado](PLAN-004-personalized-home.md) | FIX-109/build-0029: movimiento del fondo con aprobación visual registrada; consumo pendiente | [FIX-100](../../FIXES.md#fix-100), [FIX-108](../../FIXES.md#fix-108), [FIX-109](../../FIXES.md#fix-109), PAR-003 |
| [PLAN-001: playlists/shuffle](PLAN-001-playlists-shuffle.md) | Implementado; base build-0011 y comienzo progresivo FIX-112/build-0031, validación manual pendiente | [FIX-097](../../FIXES.md#fix-097), [FIX-112](../../FIXES.md#fix-112), PAR-001/010 |
| [PLAN-002: selector superior](PLAN-002-top-navigation-layout.md) | Implementado; validación visual pendiente | [FIX-090](../../FIXES.md#fix-090), PAR-007 |
| [PLAN-003: fullscreen/sidebar](PLAN-003-fullscreen-sidebar.md) | FIX-095 implementado; build-0008, validación visual pendiente | [FIX-095](../../FIXES.md#fix-095), PAR-008 |

Planes previos en `temp/documentation/plans/` (material local de importación): comprobar estado/código antes de trasladar uno.
