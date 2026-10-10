# Listas comunes, playlists/cola y ajustes del shell Windows

- Fecha: 2026-10-05 (America/Montevideo).
- Estado: implementado / validación nativa pendiente; FIX-118-2 a FIX-122-2.
- Objetivo: acercar listas, playlists y cola a la UI Apple preservando acciones/ocurrencias; corregir Inicio/sidebar, arrastre de ventana, Space global y overlay de portada fullscreen.
- Alcance: Windows UI/integración. Apple de referencia sólo lectura; core protegido sin cambios. Conservar sidebar permanente y navegación Atrás/Adelante en sidebar, sin trasladar TopNav/transición Mac. Genius no incluido en este pedido.
- Referencias: [AUDIT-002](AUDIT-002-ui-parity.md), [PARIDAD](../../PARIDAD.md), FIX-113-2 a FIX-117-2.
- Delegación: listas comunes/Historial (Sol), playlist/Biblioteca/editor (Sol), cola (Sol), integración/Home/sidebar/Space/fullscreen (agente principal). Ownership separado; raíz integra y registra fixes.

## Pasos

- [x] Leer instrucciones, antecedentes y Git; preservar cambios existentes.
- [x] Inicio: scroll horizontal disponible sin barras; controles Actualizar/Configuración agrupados en acrílico.
- [x] Shell/sidebar: caption/drag misma altura, toggle/paddings simétricos, navegación restaurada a sidebar.
- [x] Listas: contrato común, sin cabecera visible, actividad/Play/columnas/secciones y viewport.
- [x] Playlist/Biblioteca: metadata/orden/continuación, editor único y entrada desde sidebar.
- [x] Cola: metadata enlazable, arte/Play/actividad y acciones/arrastre por ocurrencia.
- [x] Space global con excepciones de texto/controles; portada fullscreen con filtro/Play/Pausa Apple.
- [x] Revisar integración/diff, pruebas pertinentes y frontend check/build.
- [x] Verificar visual/gestos con fixtures de navegador; separar limitaciones WebView2/cuenta/audio.
- [x] Registrar fixes y evaluar paridad; no cerrar runtime por compilación.

Comprobaciones de cierre: selección modificada sin reproducción accidental, botones/enlaces independientes, duplicados/entryId intactos, foco/menús/drag/carga recuperable, navegación y editor comunes, scroll horizontal oculto pero operativo. Sin cuenta real, build standalone ni commit solicitados en este turno.

## Resultado y límites

167 pruebas frontend aprobadas (14 nuevas frente a FIX-116-2), `pnpm check` con 0 errores y 0 advertencias, build frontend aprobado y diff revisado. Navegador con datos ficticios a 1443×884 y 840×760: capturas en `windows/.cache/ui-fix-2026-10-05/`; ruta temporal retirada y servidor/pestaña cerrados. Las listas de 1000 entradas montan 20–21 filas con altura total de 52000 px; la cola monta 22–23 con altura de 48000 px. Ocurrencias, foco, enlaces, teclado, Space y campos del editor verificados. No se mide FPS/audio audible ni se usa cuenta real; Tauri/WebView2/arrastre nativo pendientes. Hashes de 140 archivos Apple/core intactos.

Cierre retomado el 2026-10-09: las 167 pruebas, `pnpm check` (0 errores y 0 advertencias) y `pnpm build` aprobaron nuevamente sobre la integración final, incluida la banda lateral de arrastre. Revisión independiente Luna sin bloqueantes de composición/eventos. Cambios de código terminados; sólo queda la validación manual nativa indicada arriba. No se generó un EXE nuevo ni se hizo commit/push.

PAR-012-2 / PAR-015-2 implementados con validación nativa pendiente; PAR-013-2 / PAR-016-2 / PAR-017-2 mantienen trabajo restante. PAR-010 / PAR-011-2 y Genius/cabeceras generales/hero de búsqueda/compactación player no se declaran resueltos por esta tanda. Ver [FIX-118-2](../../FIXES.md#fix-118-2), [FIX-119-2](../../FIXES.md#fix-119-2), [FIX-120-2](../../FIXES.md#fix-120-2), [FIX-121-2](../../FIXES.md#fix-121-2), [FIX-122-2](../../FIXES.md#fix-122-2).

## Sincronización posterior — 2026-10-09

Recibidos los cambios Apple/core/herramientas y el plan integral desde `origin/main` (`d37c1ee`); fuentes locales Windows conservadas byte por byte. Los hashes de Apple/core citados arriba corresponden al cierre anterior, no al árbol nuevo recibido. Los FIX-118 a FIX-122 locales pasan a distinguirse como FIX-118-2 a FIX-122-2 por colisión con IDs Apple publicados, manteniendo alias original y evidencia. No se generó un nuevo EXE.

El plan [PLAN-001 integral](PLAN-001-feature-parity.md#recepción-en-windows--2026-10-09) registra el baseline auditado en origen, solapamientos y decisiones de sidebar; no reabre automáticamente esta tanda ni autoriza implementar todo su checklist. Historial anterior preservado en la rama local `codex/recovery-before-sync-2026-10-09`; respaldo completo fuera del repositorio en `C:/Users/Stefa/.codex/backups/sideb-sync-20261009-194720/`.

Verificación posterior a recibir GitHub: `windows/scripts/windows.ps1 -Action verify` aprobado: 167 frontend, check sin errores/advertencias, frontend build, 92 InnerTube, 90 core/92 core-Windows (7 live ignoradas por variante), 4 player y 50 Tauri. Advertencias de campos no leídos/LNK4098 presentes. Runner versionado: 9 pruebas aprobadas y 1 de empaquetado Mac omitida; no se generó EXE ni se probó UI/audio real. [Evidencia completa](PLAN-001-feature-parity.md#verificación-de-la-integración-recibida).
