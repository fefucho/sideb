# PLAN-017 — Búsqueda de Windows con páginas del proveedor

- Estado: implementación completada; verificación frontend y límites nativos informados al integrador.
- Objetivo: consumir la página/sugerencias autenticadas del core sin reconstruir ranking, filtros o historial local.
- Alcance: Svelte/TypeScript, DTO y comandos Tauri Windows. El core compartido y Apple se integran en el plan raíz.
- Referencias: `plans/PLAN-015-ytmusic-native-search.md`, FIX-086 y la corrección del plan original proporcionado por el usuario.

**Seguimiento2026-10-24:** la implementación del proveedor se conserva. El [PLAN-018 integral, etapaB](PLAN-018-windows-current-parity-roadmap.md#6-etapa-b--completar-el-buscador-actual) detalla el port pendiente de FIX-258/245 y el ajuste Mac FIX-246 en curso: proyección lineal por ocurrencia, viewport mixto, densidad/ancho disponible, acciones/categorías y máximo3 sugerencias de texto con consulta. Preview absoluto/cierre exterior ya existen y se prueban como regresión. Check actual0/0 y453pruebas frontend aprobadas/1omitida; sin runtime/EXE nuevos. PAR-042 conserva el estado y la evidencia por plataforma.

## Pasos

- [x] Conservar APIs/controladores legacy y sus garantías mientras el shell usa controladores de página del proveedor.
- [x] Presentar chips, corrección, secciones ordenadas, acciones y continuación con parámetros opacos.
- [x] Usar entradas ordenadas de sugerencias (incluido input vacío), runs en negrita y borrado remoto explícito.
- [x] Retirar historial local del shell y de Spotlight; conservar navegación, foco y menús.
- [x] Añadir regresiones de parámetros, metadata, cuenta, paginación y sugerencias vacías.
- [ ] Verificar runtime, audio y teclado real en Windows; sin acceso a cuenta real en esta tarea.

## Cierre

Verificado: `pnpm check` 0 errores/0 advertencias; `pnpm test` 446 pruebas, 445 aprobadas y 1 omitida (verify nativo en Windows); `pnpm build` aprobado, salida `windows/build/`; `git diff --check -- windows` limpio. Nueve regresiones nuevas cubren páginas/parámetros, restauración, continuación repetida, ocurrencias, reset de cuenta, sugerencias vacías y borrado en vuelo.

El integrador registra FIXES/PARIDAD y resultados finales. `pnpm check`, `pnpm test`, `pnpm build` verifican frontend; no constituyen una build nativa Windows. Se mantienen los puntos de entrada del shell reutilizando QuickResults, evitando cambios de navegación/foco ajenos al contrato.


## Revisión de acciones — 2026-10-22

La auditoría detectó que los botones del proveedor perdían la continuación de `next` al convertirla a un vector de canciones. `SearchNextDto` conserva ahora items, token y automix; el controlador del shell distingue colección/radio y adjunta el token a la fuente progresiva nativa con generación esperada. Esa fuente consume `get_next_continuation`, conserva guards de cuenta/cola y sus ocurrencias, y descarta los cursores privados al cambiar de cuenta o reiniciar. Sin token, una radio conserva su playlist real en el runtime de radio existente. Las seis regresiones nuevas verifican parámetros, metadatos, automix y respuestas tardías; el test Rust de interrupción de cuenta está añadido y pendiente del verify nativo Windows.

Última verificación frontend: check 0/0, suite 446 (445 aprobadas/1 omitida), build estático aprobado. ARIA de SearchView usa traducciones compartidas.

Última revisión de acciones: destinos browse conservan sus params incluso con card presente; las acciones video y radio sin token comienzan por el video indicado, conservando el orden completo de la página. Se amplió `start_source_radio` con índice opcional compatible. Verificación final posterior: check 0/0; 33 pruebas focales aprobadas; build frontend aprobado y diff sin errores de whitespace.

## Cierre final integrado

Freeze final:451 pruebas,450 aprobadas/0fallos/1omitida; pnpm check0/0 y pnpm build aprobados. Logs locales `/tmp/sideb-windows-test-frozen-final.log` y `/tmp/sideb-windows-rustfmt-final.log`. `rustfmt --check` devolvió diferencias de formato anteriores y nuevas en archivos amplios; no se aplicó formato masivo. Fuentes nativas Windows, pruebas Rust de runtime y audio siguen pendientes de verify en Windows. FIX-256/PAR-042 registran el alcance conjunto y la build Mac0158, sin afirmar paridad nativa validada.


## Port de presentación vigente —2026-10-26

[FIX-248](../../FIXES.md#fix-248) traslada FIX-258/245/246 del Mac0165: documento/proyección lineal por ocurrencia, viewport mixto/altura por revisión y anclas, columna completa margen28, principal compacto/acciones/categorías y máximo3textos con consulta. Tipos/payloads/orden/params y continuaciones del motor existente se conservan. Duplicados ambiguos usan ordinal+fallback único sin prestar tokens; nueva consulta/filtro vuelve a0, append preserva posición. Preview absoluto/cierre exterior/IME y teclado comparten lista visible.

73focales/check0/0 aprobados; seis casos DOM internos y máximo22entradas montadas entre5000 hasta4500, append/foco/menú/ancla/metadata ausente/gutter17. QA de app completa con bridge sintético en curso en [PLAN-018 Windows](PLAN-018-windows-current-parity-roadmap.md#18-ejecución-con-subagentes-2026-10-26). Verify/EXE/proveedor/audio/cuenta/WebView2/Narrator Windows reales pendientes; cabecera fija propia de plataforma conservada. No se acredita5000hijos en un único carrusel/bloque relacionado con la cota vertical.
