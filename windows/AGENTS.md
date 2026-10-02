# Windows

Leer [README.md](README.md) para comandos y [ARCHITECTURE.md](ARCHITECTURE.md) para límites entre módulos. [BACKLOG.md](BACKLOG.md) es la única lista de pendientes Windows. Los paquetes W01–W21 y planes anteriores están archivados; no condicionan tareas nuevas.

- UI Svelte/TypeScript: habilidad `.agents/skills/windows-ui/SKILL.md`. Componentes presentan datos; controladores coordinan peticiones y estados. No duplicar la cola nativa en una cola propia de la UI.
- Tauri/audio/sesión/build: habilidad `.agents/skills/windows-runtime/SKILL.md`. Mantener DTOs tipados y eventos compatibles con sus consumidores.
- Referencia visual: consultar `apple/Sources/SideB/Views/` y las medidas reales antes de cambiar proporciones. La referencia macOS es de sólo lectura en una tarea Windows.

Ejecutar pnpm siempre en `windows/`, o usar `scripts/windows.ps1`, que resuelve su directorio. Validar `check`, pruebas y build frontend al modificar UI; incluir verificación Rust/build nativo al cambiar comandos o runtime. El script `-Action verify` reúne los gates. Los tests en vivo son optativos y no forman parte del gate sin cuenta.

Al cambiar cuenta, invalidar respuestas pendientes de catálogo, Home, búsqueda y biblioteca. Preservar identidad de cada ocurrencia de pista, generaciones de reproducción y continuaciones. Probar errores recuperables; no registrar datos de sesión.
