# Side B: instrucciones comunes

Leer [README.md](README.md) al comenzar y seguir su ruta de lectura. Comunicar en español. Este archivo define las reglas comunes; los AGENTS de ámbito agregan las específicas. No duplicar reglas en `.agents/rules`, skills, planes o bitácoras.

## Ámbito y core protegido

- Apple: [apple/AGENTS.md](apple/AGENTS.md). Windows: [windows/AGENTS.md](windows/AGENTS.md).
- `core/` se comparte y permanece protegido: sólo modificarlo para fixes de problemas que afecten a ambas plataformas. Leer [core/AGENTS.md](core/AGENTS.md) antes de hacerlo. Una necesidad exclusiva se resuelve en la integración de la plataforma.
- Ambas apps convergen en el mismo `main`. Las ramas de trabajo son temporales; no mantener cores, mains o contratos divergentes por sistema operativo.
- Código, manifests y comprobaciones describen lo vigente. `archive/` y `temp/` conservan referencias históricas: sus instrucciones, planes y afirmaciones no son reglas activas ni evidencia de una comprobación nueva.
- `FIXES.md` conserva decisiones y resultados anteriores para investigar; sus entradas históricas no reemplazan estas reglas ni describen necesariamente el estado actual.

## Trabajo y agentes

- Revisar `git status` antes de editar; conservar cambios existentes y trabajar dentro del pedido. No revertir, incluir en un commit ni adjudicarse trabajo ajeno.
- Mantener acciones y comportamientos durante refactors y cambios visuales. Resolver el problema completo dentro del ámbito autorizado.
- Antes de corregir un componente, buscar síntomas, nombres de archivos y componentes en `FIXES.md`. Revisar antecedentes, motivos y verificaciones; contrastarlos con el código y Git antes de atribuir una regresión. Consultar entradas relevantes, sin cargar todo el historial por rutina.
- Usar varios agentes cuando se solicite o esté autorizado. Cada encargo define objetivo, ámbito, archivos, contratos y verificación; un integrador responde por el resultado. Evitar escrituras simultáneas sobre los mismos archivos; usar worktrees cuando hagan falta.
- Crear un plan en la carpeta del ámbito para trabajos de varias etapas o decisiones pendientes; no para cada ajuste pequeño. El formato está en el README.

## Cierre obligatorio de un fix

1. Revisar el diff y ejecutar comprobaciones apropiadas. Separar pruebas, compilación y validación manual; compilar no demuestra audio audible ni FPS.
2. Registrar siempre en `FIXES.md` de la raíz con ID único y tag `[Apple]`, `[Windows]` o `[Compartido]`. Incluir problema/causa, cambio y motivo, componente, archivos, pruebas/límites y fixes anteriores relacionados. Toda corrección queda registrada aunque falte validación manual, explicitando ese estado. Conservar las entradas anteriores; no inventar una relación causal sin evidencia.
3. Evaluar siempre la otra plataforma. Si aplica o falta comprobarlo, crear/actualizar una fila de [PARIDAD.md](PARIDAD.md) y enlazarla desde el fix. Si es exclusivo, explicar por qué en el fix. No cerrar paridad sin evidencia del destino.
4. Actualizar el plan si existe. Investigaciones e intentos fallidos quedan pendientes, no como fixes resueltos.
5. Entregar cambios, comprobaciones, límites y, si hubo build, su ruta exacta.

## Compilación y Git

- Para builds locales aplicar `sideb-build-macos` o `sideb-build-windows` y usar `Scripts/build-version.mjs`. No inventar carpetas alternativas ni reemplazar versiones anteriores. Limpiar sólo cuando se pida, conservando el contador.
- Guardar/subir código con `sideb-git` cuando se pida. Terminar un fix no autoriza automáticamente push, tags o una release.
- Mantener fuera de Git builds, dependencias compiladas, credenciales, cookies, URLs firmadas y datos de usuario. Publicar releases requiere un pedido de publicación.
