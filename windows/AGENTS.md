# Windows

Aplicar [instrucciones comunes](../AGENTS.md). Modificar la app Windows y su integración, sin adaptar el core protegido para necesidades exclusivas Windows.

- Svelte/TypeScript presenta datos; los controllers de `src/lib/` coordinan solicitudes/estado; `src/routes/+page.svelte` compone la app. Reutilizar tokens y componentes existentes.
- Tauri en `src-tauri/` mantiene comandos/DTOs, sesión WebView2, ventana y libmpv. Actualizar DTO y consumidor TypeScript juntos.
- La cola nativa es autoritativa; no duplicarla en la UI. Preservar `entryId`, revisiones, `generation`, `loaded_generation`, comandos tardíos y EOF. Duplicados de playlists/manuales conservan ocurrencias distintas.
- Invalidar Home/búsqueda/catálogo/biblioteca/historial/recomendaciones al cambiar cuenta/contexto. Descartar respuestas obsoletas; comprobar errores recuperables y estados vacío/carga/error.
- Comparar Apple con ventana/áreas equivalentes y medidas reales. Separar fullscreen del reproductor y del sistema. Una tarea Windows permite consultar Apple, no modificarlo.
- Mantener credenciales/almacenamiento protegido en el runtime; no publicar cookies o URLs firmadas en DTOs/logs. Pruebas con cuenta real requieren un pedido que las incluya.
- Ejecutar pnpm en `windows/`: `pnpm check`, `pnpm test`, `pnpm build` para frontend. Probar regresiones observables, no duplicar la implementación con tests triviales.
- Para runtime usar `windows/scripts/windows.ps1 -Action verify` en Windows: frontend, core con/sin `windows-bridge`, player y Tauri. Tests en vivo ignorados son optativos.
- Para builds locales usar [sideb-build-windows](../.agents/skills/sideb-build-windows/SKILL.md). Conservar EXE, libmpv, Vulkan y licencia juntos.
- Frontend verificado en Mac no demuestra funcionamiento nativo Windows. Separar build, audio, instalación y actualización real.

Consultar antecedentes y registrar arreglos en [FIXES.md único](../FIXES.md) con tag `[Windows]`, consultar [planes](plans/README.md) y evaluar [paridad](../PARIDAD.md). La [arquitectura anterior](../archive/WINDOWS_ARCHITECTURE.md) ayuda a localizar contratos, contrastándola con el código actual.
