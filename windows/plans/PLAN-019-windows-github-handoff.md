# PLAN-019 — Continuar el port en la PC Windows

- Fecha: 2026-10-26, America/Montevideo.
- Objetivo: bajar desde GitHub el port actual, compilarlo en Windows y cerrar lo que necesita WebView2/libmpv y entrada física.
- Base integrada: `origin/main` `f91f2de`, incluida la release 1.2.7/build20, Inter y los fixes Windows publicados241/242/243. Esta entrega agrega código a main; no publica otra release ni un instalador nuevo.
- Estado: fuentes integradas; check/tests/build y QA de navegador aprobados en Mac. La aceptación nativa del nuevo conjunto permanece pendiente.
- Orden de lectura: [AGENTS](../../AGENTS.md), [Windows AGENTS](../AGENTS.md), este traspaso, [PLAN-018 integral](PLAN-018-windows-current-parity-roadmap.md), [PARIDAD](../../PARIDAD.md), [FIXES](../../FIXES.md).

## 1. Qué contiene esta subida

Buscador con contrato autenticado del proveedor y sus dependencias Rust/Tauri; página compacta y virtualizada; tres sugerencias de texto y música; retención de Inicio/Explorar/Biblioteca/Search; suspensión de trabajo oculto; letras con Original, identidad de cuenta/ocurrencia y reloj por fronteras/ahorro; ciclo motion corregido; Relacionado reciclado y aislado por contexto; teclado del actualizador y menús/fullscreen corregidos.

La integración conserva Inter, el traslado conjunto de tinta base/relleno por fragmento y el margen de pintura del blur de GitHub. No reemplazar KaraokePhrase por la versión antigua para resolver un conflicto. El inicio exacto de palabra debe seguir despertando el barrido aunque el relleno sea0.

Se incluyen archivos nuevos de core y Windows, no sólo el diff de archivos ya seguidos. Las traducciones ES/EN de búsqueda se obtienen de `apple/Localization/fragments/search-provider.json`; ese origen compartido y sus recursos generados viajan también. El código de producto Apple que estaba pendiente en el checkout Mac no se incluye; sus planes y resultados se conservan como contexto documental, no como nueva implementación Apple publicada.

Los IDs locales provisionales de búsqueda241/242 y Mac243/244 chocaban con IDs publicados en GitHub: en esta entrega son256/257/258/259. Los IDs publicados241…244 conservan su significado. Los planes Windows nuevos de proveedor e integral pasan a017/018, conservando los planes015/016 ya publicados. [FIX-260](../../FIXES.md#fix-260) registra la integración;248…255 conservan los fixes del port.

## 2. Bajar en Windows sin mezclar un checkout viejo

Para un clon nuevo, desde una carpeta de trabajo en PowerShell:

```powershell
git clone --branch main https://github.com/fefucho/sideb.git SIDE-B-CLIENT-NATIVE
Set-Location SIDE-B-CLIENT-NATIVE
git log -1 --oneline
git status --short
```

Para un clon existente, primero revisar `git status --short`. Sólo si está limpio y no hay commits locales divergentes:

```powershell
git switch main
git pull --ff-only origin main
```

Si hay trabajo local o divergencia, conservarlo e integrarlo; no usar reset, limpieza ni stash automático. La alternativa más simple para probar es otro clon. No copiar sólo `windows/`: necesita el mismo core y scripts de esta revisión.

## 3. Entorno y build oficial

Requisitos: Windows10/11 x64, WebView2, VS2022 con C++/Windows SDK, Rust estable MSVC/x64, Git, Node24 recomendado (mínimo22.12) y pnpm12.6.0 declarado en package/CI. Bootstrap necesita conexión y7-Zip o tar compatible. No usar MinGW ni cambiar manifests para ocultar falta de toolchain.

```powershell
node --version
pnpm --version
rustc -Vv
git --version
powershell -NoProfile -File .\windows\scripts\windows.ps1 -Action doctor
node Scripts/build-version.mjs windows
```

Si falta pnpm, instalar la versión declarada antes de compilar; por ejemplo `npm install --global pnpm@12.6.0`, según el entorno de la PC. El runner oficial prepara las DLL/import library cuando faltan, ejecuta verify y conserva una build Release numerada. No hace falta repetir verify manualmente antes de cada build oficial. Para investigar un fallo aislado, `windows/scripts/windows.ps1 -Action verify` cubre frontend, core con/sin bridge, player y Tauri.

Sólo `builds/windows/build-NNNN/BUILD.json` con `status: compiled` confirma el resultado. Conservar `sideb-windows.exe`, `libmpv-2.dll`, `vulkan-1.dll` y `VulkanRT-License.txt` juntos. No renombrar una build anterior ni entregar EXE aislado. Guardar BUILD.json/log/commit/hashes al informar; los artefactos permanecen fuera de Git.

El push también activa Windows CI: [ejecuciones](https://github.com/fefucho/sideb/actions/workflows/windows.yml). Si termina bien, el artefacto `sideb-windows-debug-x64` contiene EXE y sus tres acompañantes. Es una build debug de Actions, no una release ni prueba física. Para una entrega local Release usar el runner anterior.

## 4. Matriz para cerrar en la PC

| Prioridad | Recorrido | Resultado que se debe comprobar |
| --- | --- | --- |
| P0 | Doctor → verify → build | Misma revisión; check y suites nativas aprobadas, BUILD.json compiled y hashes correctos. Registrar omisiones live; no presentarlas como ejecutadas. |
| P0 | Iniciar y reproducir una pista conocida | Login del usuario dentro de la app, reproducción audible y progreso observado de libmpv. No compartir cookies, tokens, URLs firmadas ni datos de cuenta. |
| P0 | Cinco cues de letras adelante/atrás | Comparar destino con posición realmente observada; pausa, reproducción, restauración, duración tardía y clics rápidos. El pending visual no acredita audio confirmado. |
| P0 | Cerca del final / cambio de pista / duplicado de video | EOF procesado una sola vez; ningún callback anterior cambia la nueva entryId/cuenta; pausa y último cue se conservan. |
| P0 | Motion frío/caliente y varias vueltas | H.264 real, imagen hasta primer frame válido, sin negro/parpadeo/sonido de vídeo ni interrupción del audio. Conservar metadata de la fuente real, sin inventar60fps. |
| P0 | Motion pausa/OFF/ocultar30s/limpiar caché | Se detiene/libera/reanuda según política; clear espera handles, conserva imagen y no produce sharing violation ni re-descarga inmediata indebida. |
| P1 | Buscar homecoming, kendrick lamar, to pimp a butterfly | Principal canción/artista/álbum; chips/correcciones/paginación y acciones conservan proveedor/ocurrencias. Play/radio/aleatorio y next usan semilla e índice correctos. |
| P1 | Preview / Spotlight / IME | Tres textos y medios disponibles; clic exterior cierra y llega al destino; sin salto de resultados; Escape y Tab respetan modal/menú; composición no envía Enter. |
| P1 | Búsqueda profunda / resize / sidebar | DOM acotado; no pierde fila, menú, foco o ancla al agregar página/cambiar ancho. Cabecera/resultados alineados aun con scrollbar clásico. |
| P1 | Letras nuevo/Original/lectura/ajustes | Inter legible, sin glifos duplicados; halo sin corte; voz simultánea/CJK/RTL/palabra partida; Original accesible en loading/error; scroll manual persiste y Volver retoma. |
| P1 | Fullscreen compacto y amplio | Cierre y tabs sin superposición; último botón del menú alcanzable y clic real cambia a Original. Probar también teclado. |
| P1 | Relacionado y refresh | Cuatro estantes, columnas270/3filas52/clip168; controles activos; wheelY llega al scroll exterior, wheelX al carrusel; offsets/foco/menú de teclado sobreviven reciclado y refresh. |
| P1 | Diez ciclos Inicio/Explorar/Biblioteca/Search + Spotlight | Mismo estado/scroll/borrador; fondo visible sin controles interactivos detrás; observadores suspendidos; cuenta distinta purga datos anteriores. |
| P1 | DPI100/125/150/200%, texto ampliado, ancho960 y amplio | Sin recortes, targets accesibles, textos y menús visibles, portadas con DPR actual. Sidebar abierta/cerrada. |
| P1 | Narrator, teclado, alto contraste/forced-colors, Reduce Motion | Lectura accesible única, foco/retorno correctos; no depende de capas decorativas; contraste y movimiento respetados. |
| P1 | Minimizando/restaurando, escritorio virtual, ahorro/memoria | Señales nativas llegan a vídeo y reloj; retorno estable. DWM-cloaked no prueba que la ventana esté tapada por otras. |

Para cada fallo guardar: SHA, Windows/WebView2/GPU/DPI, build exacta, pasos mínimos, esperado/observado y captura o log sanitizado. No atribuir causa a core o renderer sin reproducirla. No certificar FPS/latencia con contador rAF; si se mide rendimiento, usar una herramienta y corpus comparables.

## 5. Qué sigue pendiente de verdad

- QA nativa de la matriz anterior. Las pruebas en Mac/DOM no sustituyen WebView2/libmpv/Win32 ni input físico.
- `PlayerEvent::Position(f64)` no trae procedencia/ticket ni readback de seek. Mantener guards actuales; no pegar una etiqueta al recibir el evento para fingir identidad. Si se reproduce un fallo, documentar antes una solución común cuando implique tocar el contrato protegido.
- Oclusión por solapamiento completo y thermal no tienen equivalencia total implementada. No apagar por perder foco. Mantener ahorro/memoria/minimización reales.
- Explícito/clean/unknown y preferencias de ediciones son funciones futuras de ambas apps: PAR-040/041 y planes compartidos013/014. No están implementadas en Mac como para portarlas aquí; no añadir ranking/reemplazo de IDs silencioso.
- Sidebar oculta/topnav Windows conserva su [PLAN-015](PLAN-015-sidebar-hidden-topnav.md) publicado; esta subida no ejecuta ese plan nuevo.
- Instalación/actualizador físico y release nueva no forman parte de esta subida de código. La corrección de teclado del actualizador sí está incluida.

## 6. Mensaje para pegarle al agente de Windows

> Continuá el port desde main actualizado de GitHub. Leé AGENTS.md, windows/AGENTS.md y windows/plans/PLAN-019-windows-github-handoff.md; después PLAN-018 y PARIDAD.md. Conservá Inter y los fixes publicados241/242/243 junto con248…260 y las dependencias del buscador compartido. Revisá git status y conservá cualquier trabajo local. Ejecutá doctor y la build oficial con node Scripts/build-version.mjs windows; corregí los fallos de integración que puedas reproducir, sin cambiar core protegido para necesidades exclusivas Windows. Verificá la matriz priorizada de búsqueda, letras/seek audible, motion, retención y Relacionado en WebView2, incluidos DPI, teclado y accesibilidad. Registrá cada arreglo con ID global nuevo en FIXES, actualizá PARIDAD/planes y entregá BUILD.json, ruta exacta del EXE con DLL/licencia y pruebas/límites. No cierres paridad por compilar ni inventes FPS/audio. No publiques otra release ni cambies versión/tag por este pedido; si falta una prueba física, dejala explícita.

## 7. Evidencia del conjunto integrado

Validación repetida sobre este checkout integrado, no tomada de la ejecución anterior:

- `pnpm check`:0 errores/0 advertencias.
- `pnpm test`:480 declaradas,479 aprobadas/1 omitida exclusiva Windows,0 fallos.
- `pnpm build`: sitio estático generado; aviso de chunk grande conservado. No es un EXE.
- Rust sin bridge:112InnerTube+170core=282 aprobadas,10live omitidas,0fallos. Variante core/windows-bridge:172 aprobadas/10live omitidas/0fallos. Ejecutadas en Mac, sin player/Tauri Windows.
- App completa con Inter local:28evidencias/errors[] en Chrome/Mac software, incluidos layouts/búsqueda/retención/letras/cuenta sintética.
- Renderer integrado:9casos raster/shaping/animación más fallback, seek atrás/final, Reduce Motion, pausa, fuera de pantalla y forced-colors aprobados;6casos de halo del blur a dos anchos/tresDPR aprobados. Chromium software, sin certificación GPU/WebView2/audio.
- i18n verifica la fuente editorial compartida y el catálogo generado; fixture de blur actualizada al scope de sesión/entryId vigente. Los intentos fallidos iniciales están descritos en FIX-260.

Entorno local: Darwinarm64, Node24.16.0 y pnpm11.25.0 del host, con las dependencias existentes; Windows/CI usa12.6.0 declarado. Logs/capturas/cachés no se suben. El commit de esta entrega se identifica en main con FIX-260; no hay release nueva ni EXE nativo generado en este Mac. CI o build local Windows deben comprobar el conjunto nativo completo antes de darlo por validado.
