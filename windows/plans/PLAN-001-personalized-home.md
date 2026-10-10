# Inicio configurable y cartas comunes Windows

- Objetivo: implementar saludo, Speed Dial, destacados, ambiente, configuración por cuenta, cartas comunes y feed explícito conservando la sidebar expandida/compacta Windows.
- Estado: implementado / validación nativa pendiente (2026-10-04).
- Alcance: frontend Windows, controllers/contratos existentes; sin modificar Apple ni core. Selector superior Mac y transición de ocultamiento de sidebar excluidos por decisión del usuario.
- Referencias: [guía](../../PORTEO-INICIO.md), [paridad](../../PARIDAD.md), FIX-098 a FIX-112 y FIX-087 (ocurrencias/cola).

## Pasos

- [x] Modelo de preferencias y proyección por fuentes/categorías, persistencia aislada por cuenta.
- [x] Inicio adaptable, paginadores, metadata visible y fondo de portadas pausado en inactividad.
- [x] Panel superpuesto: fuentes/categorías, teclado, orden/arrastre y cierre al cambiar contexto.
- [x] Controles comunes y reproducción contextual; filas y menús sin doble acción, identidades de ocurrencias conservadas.
- [x] Feed explícito con avance acotado y fin; virtualización de estantes y tarjetas.
- [x] Comprobaciones frontend, pruebas de regresión, revisión visual disponible; registrar FIX/paridad y límites.
- [ ] Validación en WebView2: cuenta real, audio audible, arrastre, foco exhaustivo y consumo. Requiere sesión de prueba autorizada; no se declara resuelta.

## Auditoría funcional contra macOS — completada, validación nativa pendiente

- [x] Contrastar selección/dedupe/orden, capacidades y páginas con modelos/vistas Apple actuales.
- [x] Contrastar persistencia, fuentes suplementarias, metadata y cancelación por contexto/cuenta.
- [x] Contrastar feed, avance acotado, prefetch y virtualización conservando acciones.
- [x] Contrastar radio/colecciones/filas/menús y fondo; distinguir adaptaciones de plataforma de diferencias de lógica.
- [x] Corregir diferencias dentro de los cuatro bloques, cubrir regresiones y registrar matriz de evidencia/FIX/paridad.

[Matriz funcional y límites](AUDIT-001-home-parity.md), [FIX-114-2](../../FIXES.md#fix-114-2). 152 pruebas aprobadas, check sin errores/advertencias y build frontend aprobado. Revisión de navegador del ancla/categorías y fila activa/foco/selección de duplicados. PAR-010 / PAR-011-2 siguen pendientes; no se declara paridad total de la app ni validación nativa.

## Cierre de implementación inicial (FIX-113-2)

Build standalone posterior solicitada para probar FIX-113-2 / FIX-114-2: `builds/windows/build-0003/sideb-windows.exe` (Release x64), BUILD.json compiled/sourceChangedDuringBuild false; SHA-256 de EXE/libmpv/Vulkan/licencia comprobados. Runner nativo completo aprobado: 152 frontend, 90 InnerTube, 90 core y 92 windows-bridge (7 live ignoradas por variante), 4 player, 50 Tauri. Cuenta/audio audible/ventana reales siguen pendientes; app no abierta. Build-0001/0002 fallidas conservadas; la compilación final aisló módulos de Windows PowerShell y usó caché Cargo en D: por espacio insuficiente en C:. Junction de target y caches/builds fuera de Git. Documentación agregada después del build, sin cambios de código.

Registrado en [FIX-113-2](../../FIXES.md#fix-113-2); PAR-002 / PAR-003 / PAR-004 / PAR-005 / PAR-006 / PAR-009 implementados con validación nativa pendiente. `pnpm check`: 0 errores/0 advertencias; `pnpm test`: 134 aprobadas (17 nuevas); `pnpm build`: frontend generado en `windows/build`, sin ejecutable standalone. Diff revisado.

Prueba de navegador con datos ficticios: anchos 800/1440/2400, panel superpuesto, Space/Escape, filtro sin tildes, orden por botones, página anclada al resize, origen de radio tras avanzar, acciones/menú independientes y selección modificada de duplicados. Fixture de 5000 categorías: 2–4 estantes y 18–41 cartas montadas en las posiciones comprobadas; evidencia de DOM acotado, no de FPS/consumo. Captura y fixture conservados localmente en `windows/.cache/ui-review-2026-10-04/`; ruta de prueba retirada del producto.

La raíz arranca en navegador, pero las llamadas/eventos Tauri fallan allí por ausencia del runtime nativo; esa comprobación no valida IPC ni audio. PAR-010 (inicio antes de completar catálogo) sigue pendiente y fuera del pedido. No se modificaron Apple, core, TitleBar/sidebar ni composición de fullscreen; sin commit/push/publicación ni pruebas con cuenta real.

## Ajustes visuales reportados tras build-0003 — 2026-10-05

- Estado: implementación, revisión de navegador y build-0004 completadas; validación visual WebView2 pendiente; referencia: cinco capturas del usuario y vistas Apple vigentes.
- [x] Integrar controles de ventana con el fondo de Inicio, sin franja ni reserva superior independiente; conservar arrastre/navegación/acciones Windows.
- [x] Mostrar artista en Speed Dial y etiqueta/título/crédito/resumen de álbum alineados arriba.
- [x] Centrar flechas y puntos del paginador por geometría, con blancos de teclado/clic útiles.
- [x] Igualar radios/degradados/humo de macOS con máscara suave preparada una sola vez; mantener pausa por inactividad y Reduce Motion.
- [x] Verificar en fixture de navegador con metadata asíncrona, checks/tests/build y registrar FIX-115-2/paridad.
- [ ] Revisión visual final en WebView2 por el usuario.

No cambia la decisión sobre sidebar permanente ni traslada selector TopNav/transiciones de fullscreen.

Cierre [FIX-115-2](../../FIXES.md#fix-115-2): `builds/windows/build-0004/sideb-windows.exe`, Release x64, compiled/sourceChangedDuringBuild false. Verify/build completos aprobados: 153 frontend, check sin errores/advertencias, 90 InnerTube, 90 core/92 bridge (7 live ignoradas por variante), 4 player, 50 Tauri; hashes de EXE/DLLs/licencia correctos. Captura de fixture `windows/.cache/ui-review-2026-10-05/inicio-corregido.png`; no se abrió app ni cuenta. Fuentes congeladas durante compilación; documentación finalizada después.

## Controles y marca de explícito — FIX-116-2, 2026-10-05

- Objetivo: un único indicador E negro de tamaño fijo y puntos centrados independientes de tipografía en Windows.
- Estado: implementado y verificado en navegador/frontend; validación visual WebView2 pendiente. Alcance: componentes de presentación Windows; sin cambiar acciones/DTO/core/Apple.
- [x] Crear ExplicitBadge/MoreIcon comunes y sustituir los indicadores y puntos duplicados.
- [x] Revisar variantes de carta/título largo, marca de búsqueda y filas/menús; comprobar geometría y acciones de cartas/detalle/tablas en fixture.
- [x] Check/tests/build frontend, diff, FIX-116-2 y paridad.
- [ ] Confirmación visual en WebView2.

Cierre [FIX-116-2](../../FIXES.md#fix-116-2): 153 pruebas frontend, check sin errores/advertencias y build frontend aprobados. Badge 14×14 negro y centros coincidentes; menús conservan gestos sin reproducción accidental. Captura ignorada `windows/.cache/ui-review-2026-10-05/controles-centrados.png`. No se genera standalone; build-0004 no incorpora este fix.
