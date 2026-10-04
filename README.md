# Side B

Dos apps, un core Rust y un `main`: Mac usa SwiftUI/AppKit y AVPlayer; Windows usa Svelte/TypeScript, Tauri y libmpv.

Este README es la entrada para personas y agentes. Abrir como proyecto esta carpeta `SIDE B`, que contiene `.git`, y empezar leyendo este archivo y [AGENTS.md](AGENTS.md).

## Qué leer según la tarea

| Trabajo | Instrucciones | Registro y pendientes |
|---|---|---|
| Mac | [Apple AGENTS](apple/AGENTS.md) | [Fixes: tag Apple](FIXES.md), [planes Apple](apple/plans/README.md) |
| Windows | [Windows AGENTS](windows/AGENTS.md) | [Fixes: tag Windows](FIXES.md), [planes Windows](windows/plans/README.md) |
| Fix compartido / herramientas | [AGENTS general](AGENTS.md); [Core AGENTS](core/AGENTS.md) si cambia Rust | [Fixes: tag Compartido](FIXES.md), [planes generales](plans/README.md) |
| Trasladar un arreglo | AGENTS del destino y fix del origen | [Paridad Mac ↔ Windows](PARIDAD.md) y su referencia |
| Compilar Mac | [Skill Mac](.agents/skills/sideb-build-macos/SKILL.md) | Nueva versión en `builds/macos/` |
| Compilar Windows | [Skill Windows](.agents/skills/sideb-build-windows/SKILL.md) | Nueva versión en `builds/windows/` |
| Guardar / subir cambios | [Skill Git](.agents/skills/sideb-git/SKILL.md) | Diff, fixes, paridad y planes del trabajo |

Antes de corregir algo, buscar su síntoma, componente y archivos en FIXES.md; leer los cambios anteriores relacionados y contrastarlos con el código/Git. Consultar también paridad y planes. Leer sólo las entradas/referencias relevantes, sin cargar todo el historial por rutina.

## Builds locales conservadas

Desde la raíz, con Node.js 22.12 o superior:

```sh
node Scripts/build-version.mjs macos
node Scripts/build-version.mjs windows
```

Configuración predeterminada: `release` en ambos sistemas. Usar `--configuration debug` para debug y `--open` cuando también se quiera abrir la app. Mac requiere Apple Silicon, Xcode y Rust; Windows requiere MSVC 2022, WebView2, Rust, pnpm y PowerShell. Las skills detallan los requisitos.

El comando verifica, compila y crea `builds/<plataforma>/build-0001/`, luego `build-0002/`, etc. Cada carpeta conserva la aplicación, `BUILD.json` con commit/estado local/configuración/comandos/hashes y `build.log`. Sólo `status: compiled` indica comprobaciones y empaquetado terminados; un fallo conserva el diagnóstico y consume su número.

El número local no cambia `version.env`. Las cachés se reutilizan; los resultados numerados se conservan. Borrar versiones antiguas sólo cuando se solicite y conservar `.next-number`. `.lock` protege la compilación activa: si queda tras una interrupción abrupta, comprobar que no haya compilación antes de quitarlo.

`Scripts/compile_and_run.sh` es la entrada compatible para compilar y abrir Mac y usa el mismo flujo versionado. Los scripts internos/de release no son rutas alternativas para las builds locales. No ejecutar `release_update.sh` para guardar código: publica una release.

## Registrar un fix

Un único `FIXES.md` conserva la historia de todas las plataformas, incluidas las entradas importadas. Cada entrada lleva un ID único `FIX-NNN` y un tag de ámbito: `[Apple]`, `[Windows]` o `[Compartido]`. Core y herramientas comunes usan Compartido y detallan el componente. El tag describe dónde se hizo el cambio, no dónde falta trasladarlo ni qué plataformas se verificaron.

Elegir el siguiente número libre global; no renumerar entradas anteriores. Se conservaron IDs `FEAT` históricos y se distinguieron los dos números antiguos repetidos con sufijo `-2`, dejando el alias original. Las mejoras nuevas usan la serie FIX y declaran su tipo.

```markdown
### [FIX-NNN] [Apple] - Título concreto

- Fecha: YYYY-MM-DD (America/Montevideo).
- Componente: cola / shuffle / navegación / búsqueda / Core / build / etc.
- Tipo / estado: fix; implementado / validado / validación pendiente.
- Problema y causa: escenario reproducible y causa encontrada.
- Solución y motivo: qué se cambió y por qué se eligió esa solución.
- Archivos: rutas o enlaces del cambio.
- Fixes relacionados: IDs anteriores; explicar si completa, reemplaza o corrige una regresión.
- Verificación: comandos y resultados reales; prueba manual por separado.
- Límites: lo pendiente y las relaciones causales aún por investigar.
- Paridad: PAR-NNN, o «No aplica: motivo específico».
- Plan / build / commit: referencias disponibles; omitir lo inexistente.
```

El registro sirve para investigar el origen de errores: conservar antecedentes y motivos, no sólo decir «arreglado». No atribuir una causa a un fix anterior sin contrastar el código/evidencia. Si aún no existe commit, incluir el ID del fix en su mensaje cuando se guarde: permite localizarlo con `git log --all --grep='FIX-089'` sin actualizar otra bitácora.

Búsquedas desde la raíz:

```sh
rg -n -i -C 5 'shuffle|QueueManager|PlayerViewModel' FIXES.md
rg -n '^### .*\[Windows\]' FIXES.md
```

Evaluar la otra plataforma en cada fix. [PARIDAD.md](PARIDAD.md) registra lo trasladable o por investigar; un caso exclusivo se explica en su entrada. Resolver paridad requiere evidencia del destino. No borrar fixes cerrados: los nuevos enlazan los antecedentes. Los registros importados indican `Histórico: sí`; sus mediciones y mandatos anteriores no son reglas activas ni mejoras nuevas de una release.

## Planes

Guardar en `apple/plans/`, `windows/plans/` o `plans/`. Los índices enlazan planes activos; PARIDAD conserva el estado de los ports, sin otro backlog duplicado.

Cada plan indica objetivo, estado, alcance/exclusiones, referencias, pasos con casillas, comprobaciones de cierre y enlaces a fixes/builds. Actualizar el mismo archivo. Usar nombres como `PLAN-001-shuffle-reversible.md`. Un plan describe trabajo; un fix registra lo realizado.

## Referencias anteriores

`archive/` conserva las referencias que deben acompañar al repositorio. Sus instrucciones y resultados son históricos:

- El [historial de fixes](FIXES.md#historial-importado) ya está integrado en el registro único; los resultados importados conservan su condición histórica.
- [Blueprint Apple](archive/APPLE_UI_ARCHITECTURE.md): contrastar nombres, medidas y decisiones con el código.
- [Arquitectura Windows](archive/WINDOWS_ARCHITECTURE.md): contrastar contratos con el código actual.
- [Port de playlists/shuffle](archive/PLAYLIST_SHUFFLE_PORT.md): referencia de PAR-001.
- [Índice histórico](archive/README.md): ubicación y condición de las referencias preservadas.

Al incorporar una referencia a una tarea nueva, comprobar su estado y registrar el resultado en los archivos activos. Código y pruebas actuales prevalecen sobre decisiones antiguas.

El resto de lo reunido permanece intacto en `temp/` como material local de importación. Al retomar una tarea, trasladar sólo la referencia necesaria a un plan/documento versionable, revisar sus enlaces y agregarla al índice; no convertir toda la carpeta en instrucciones activas.
