# Planes Windows

- [PLAN-008: Fondo, logo y tipografía fullscreen](PLAN-008-fullscreen-color-logo-type.md) — implementado/revisado; FIX-146/151/PAR-025, build-0012 release con646 pruebas aprobadas e icono PE redondeado verificado; aceptación física pendiente.

- [PLAN-007: Volumen exponencial opcional](PLAN-007-exponential-volume.md) — implementado/revisado; FIX-143/PAR-024, opción inicial OFF, build-0008 release/631 pruebas aprobadas; escucha física pendiente.

- [PLAN-006: Presentación y orden de botones de cola](PLAN-006-queue-presentation.md) — corrección adicional FIX-145 sin puntos, centros uniformes y duración/asa coincidentes; check/fixture y build-0009 release aprobados (631 pruebas); aceptación física pendiente. Build-0008 conserva estado anterior.

- [PLAN-005: Texto Genius y colores](PLAN-005-genius-text.md) — terminado: flujo de letras, Carátula/Contraste/Neutro y retiro del menú superior; 620 pruebas aprobadas, build-0007 release conservada. Aceptación visual nativa pendiente.

- [PLAN-004: Correcciones de reproductor y shell](PLAN-004-player-shell-corrections.md) — terminado: Genius/Letras, reverso/anotaciones, álbum de Inicio, navegación y ambiente; 614 pruebas aprobadas, build-0006 release conservada. Aceptación física pendiente.

- [PLAN-003: Integración macOS → Windows](PLAN-003-macos-integration.md) — integración y revisión terminadas, 583 pruebas aprobadas y build-0005 release conservada; aceptación física pendiente.

- [PLAN-002: Listas, playlists/cola y shell](PLAN-002-ui-lists-shell.md) — implementado / validación nativa pendiente; FIX-118-2 a FIX-122-2, sidebar Windows y navegación propias conservadas.
- [PLAN-001: Inicio configurable y cartas comunes](PLAN-001-personalized-home.md) — implementado / validación nativa pendiente; FIX-113-2 / FIX-114-2, sidebar Windows conservada.
- [Auditoría funcional contra macOS](AUDIT-001-home-parity.md) — evidencia por función y diferencias registradas en PARIDAD.
- [Auditoría general de UI Windows/macOS](AUDIT-002-ui-parity.md) — comparación estática terminada; 30 puntos de estructura, presentación y funciones, con diferencias pendientes en PAR-012-2 a PAR-017-2. FIX-117-2; sin cambios de UI.

[Formato](../../README.md#planes), [fixes](../../FIXES.md#fix-087), [paridad](../../PARIDAD.md).

| Plan | Estado | Alcance |
|---|---|---|
| [PLAN-001 — Paridad de funciones y diseño](PLAN-001-feature-parity.md) | Auditoría conservada; ejecución en PLAN-003 | 113 tareas, incluidas decisiones y ensayos físicos. Casillas de aceptación conservadas; PAR-001 a PAR-021 conservan el significado publicado |

No se reactiva ningún plan automáticamente. Los planes UX-01 a UX-06 y los pendientes previos están reunidos en `temp/windows/` como material local de importación. Al retomar uno, comprobar evidencia/código y trasladar sólo ese plan a esta carpeta, con sus enlaces actualizados.
