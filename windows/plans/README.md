# Planes Windows

- [PLAN-022: Barra de reproducción, ancho útil y título desplazable](PLAN-022-player-bar-space-marquee.md) — FIX-265/build0024 Release compiled/fuentes estables/cuatro hashes; verify1089pruebas/0fallos. Corazón destacado/dislike, acciones junto al texto corto, separadores invisibles, portada radio2, fullscreen activo sinE y flechas sin bandas negras; Edge16/12/26casos aprobados. Mac030/PAR-044; QA WebView2/Narrator/audio y Mac pendientes.

- [PLAN-021: Indicadores de contenido explícito](PLAN-021-explicit-content-indicators.md) — FIX-262/263/265/PAR-040: metadata por entidad/ID; E proporcional en artista/álbum. Revisión265 excluye también créditos de canción activa fullscreen; barra/cola/Relacionado conservan indicador. Edge12casos/cuatro alternancias aprobados; build0024 Release compilada con verify1089aprobadas. QA nativa/cuenta pendiente.

- [PLAN-020: Flechas para navegación horizontal con mouse](PLAN-020-horizontal-scroll-controls.md) — Flotantes elegida e implementada/FIX-261 en todo el inventario;490pruebas/check0/0/build frontend,26casos/44avances con mouse en Edge y app completa28evidencias. QA WebView2 pendiente; sin EXE nuevo.

- [PLAN-019: Traspaso GitHub → PC Windows](PLAN-019-windows-github-handoff.md) — ejecutado en PC26/27: main13011e7, borrador preservado, doctor/verify y build0021 Release x64 compiled/fuentes estables/cuatro hashes;1054pruebas aprobadas y QA Edge sintética28evidencias. Usuario detuvo Computer Use con Escape; EXE nuevo sin abrir, aceptación WebView2/audio/motion pendiente. FIX-260; sin nueva release.

- [PLAN-018: Plan integral para llevar la experiencia actual a Windows](PLAN-018-windows-current-parity-roadmap.md) — ejecución2026-10-26 con subagentes: FIX-248…255 implementan búsqueda actual, reloj/Original, ciclo motion, retención/Biblioteca, Relacionado y correcciones de teclado/fullscreen. Suite final479aprobadas/1omitida, check0/0/build frontend; Rust+bridge284aprobadas/10omitidas en Mac. QA sintética28evidencias/errors[] con geometría real; verify/EXE/WebView2/audio Windows pendientes. Indicadores/versiones siguen como entrega común posterior; PARIDAD conserva aceptación y límites.

- [PLAN-017: Búsqueda del proveedor](PLAN-017-provider-search.md) — página y sugerencias autenticadas, filtros/acciones/paginación remotos; validación nativa Windows pendiente.

- [PLAN-016: Duplicación de karaoke](PLAN-016-karaoke-fragment-rendering.md) — FIX-242: base/relleno se mueven juntos; ancla por palabra/renglón y límites de vecinos como Mac. FIX-243 recupera halo izquierdo del blur por contención CSS;9casos karaoke/6blur aprobados. Entrega build-0020 x64 Release compiled/fuentes estables/check0/0/987pruebas aprobadas/20live ignoradas/cuatro hashes revalidados, con Inter y ambos fixes. Aceptación WebView2 pendiente;0019 previa al ajuste conservada.

- [PLAN-015: Sidebar oculta y topnav](PLAN-015-sidebar-hidden-topnav.md) — planificado por pedido del usuario, sin implementación. Opción al contraer: iconos o cero ancho; topnav Mac, búsqueda expandible, cuenta/Settings accesibles y estado persistido. Contratos, archivos, etapas y matriz funcional/visual/nativa definidos. PAR-007 se reabre sólo para este modo opcional; no está en build-0018.

- [PLAN-014: Homecoming e Inter](PLAN-014-homecoming-inter.md) — FIX-241: Homecoming público trae frases sin palabras; United in Grief sí tiene901segmentos temporizados. Renderer intacto. Inter4.1 normal/italic y licencia locales; frontend/fixture y build-0018 x64 Release aprobados,987pruebas/check0/0/fuentes estables/cuatro hashes verificados. Aceptación humana pendiente; sin publicación.

- [PLAN-013: Letras y carátulas animadas](PLAN-013-lyrics-motion-parity.md) — FIX-240 implementa renderer rico/Original compartido, opciones/blur/manual/fallback, seek identificado y cierre de ciclo motion30s/clear/políticas. Check0/0,430tests frontend/1omitido, build frontend y8contratos Rust aislados aprobados; fixture Chromium con wrapping y blur. Verify/EXE/audio/WebView2/DPI Windows y límites de oclusión pendientes. PAR-037/038/039 siguen abiertos.

- [Sidebar y Apariencia: entrega compartida](../../plans/PLAN-010-sidebar-delivery.md) — FIX-224/225 publicada Latest 1.2.6/build 19 sobre GitHub 23f1df5; nueva sidebar y opciones sincronizadas, 764 pruebas Mac/793 Windows y cinco descargas públicas verificadas. PAR-036; aceptación física pendiente.

- [PLAN-012: Respuesta de Like y biblioteca](PLAN-012-action-feedback.md) — FIX-222 publicada en 1.2.5/build 18 mediante FIX-223: optimismo/rollback, red concurrente y acciones acotadas a 15 s. Verify/build Windows, 397 frontend y 97 Tauri aprobados, incluidos los cuatro tests del guard; paquetes/hashes comprobados. Cuenta real/WebView2 interactivo pendientes. PAR-035.

- [PLAN-011: Acabado de botones](PLAN-011-button-polish.md) — FIX-221 publicada en 1.2.5/build 18 mediante FIX-223: materiales/jerarquía/iconos refinados y QA navegador. Verify/build EXE Windows y 397 tests frontend aprobados; paquetes/versiones/hashes comprobados. Comparación Apple estática; aceptación física Windows pendiente. PAR-030.

- [PLAN-010: Buscador, Explorar, colecciones y streams](PLAN-010-windows-ui-stream-bugs.md) — FIX-216/217/218/219 implementan Spotlight, jerarquía/scroll de Explorar, toolbar responsive/ambiente detrás y runtime cipher aislado registrado inicio/retry. Fixture Edge144combinaciones y verify completo776pruebas/check0/0 aprobados. Por pedido posterior «compila así pruebo»,build-0015 Release compiled/fuentes estables/cuatro hashes revalidados,entregada sin abrir. WebView2 y pista exacta/control pendientes de prueba del usuario; sin publicación.

- [PLAN-009: Volumen con rueda y feedback fullscreen](PLAN-009-volume-scroll-feedback.md) — FIX-213 corrige `Illegal invocation` del indicador que interrumpía rueda en1.2.3. Build local0014 release compiled,764pruebas/check0/0/fuentes estables/cuatro hashes válidos y regresión Chromium antes/después aprobada. FIX-214 retira la instancia de diagnóstico que bloqueaba WebView2: mismo EXE abierto/estable y wheel42→34→42 comprobado en portada/barra; usuario confirma funcionamiento, sin medición de audio. FIX-207/211 conservan sus correcciones de acumulación y FIX-198 sus zonas; complementa PLAN-021 Apple. FIX-215 publicada1.2.4/build17 como Latest, CI completo y cinco descargas/checksums aprobados; instalador interactivo pendiente.

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

[Formato](../../.agents/WORKFLOW.md#planes), [fixes](../../FIXES.md#fix-087), [paridad](../../PARIDAD.md).

| Plan | Estado | Alcance |
|---|---|---|
| [PLAN-001 — Paridad de funciones y diseño](PLAN-001-feature-parity.md) | Auditoría conservada; ejecución en PLAN-003 | 113 tareas, incluidas decisiones y ensayos físicos. Casillas de aceptación conservadas; PAR-001 a PAR-021 conservan el significado publicado |

No se reactiva ningún plan automáticamente. Los planes UX-01 a UX-06 y los pendientes previos están reunidos en `temp/windows/` como material local de importación. Al retomar uno, comprobar evidencia/código y trasladar sólo ese plan a esta carpeta, con sus enlaces actualizados.
