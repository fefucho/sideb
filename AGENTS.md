# Side B: trabajo en el repositorio

Comunicar cambios y resultados en español. El código y sus pruebas describen el comportamiento vigente; `documentation/archive/`, auditorías y planes antiguos son referencias históricas.

## Elegir el ámbito

- Windows (`windows/`): leer [windows/AGENTS.md](windows/AGENTS.md). Guía, arquitectura y pendientes mantenidos allí.
- macOS (`apple/`): leer [apple/AGENTS.md](apple/AGENTS.md). No aplicar reglas Svelte/Tauri a Swift.
- Rust compartido (`core/`): leer [core/AGENTS.md](core/AGENTS.md). Una modificación compartida puede afectar ambas apps.

## Entregar cambios

Trabajar sobre un objetivo concreto, conservar acciones existentes y verificar los contratos que cambien. Un arreglo pequeño no requiere crear un plan ni actualizar varias bitácoras. Mantener documentación sólo si cambian comandos, arquitectura o pendientes del producto.

Antes de editar, comprobar `git status`. No sobrescribir cambios ajenos. Para agentes simultáneos, usar archivos independientes con un integrador; si necesitan editar el mismo ámbito, usar ramas/worktrees separados. Cada encargo debe indicar objetivo, archivos permitidos, contrato y cómo comprobarlo; la respuesta incluye archivos cambiados, pruebas y limitaciones. No hay proveedor ni modelo obligatorio.

Revisar el diff y ejecutar las comprobaciones del ámbito antes de cerrar. Distinguir compilación, pruebas automáticas y validación manual; ninguna prueba de tipos demuestra audio audible o rendimiento. No guardar cookies, credenciales, URLs firmadas, bases de datos de usuario ni dependencias compiladas en Git.
