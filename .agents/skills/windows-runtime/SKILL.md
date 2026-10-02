---
name: windows-runtime
description: Mantener los comandos Tauri, reproducción libmpv, sesión WebView2 y compilación Windows de Side B. Usar para windows/src-tauri y los scripts de build; el core Rust compartido conserva sus propias instrucciones.
---

# Runtime y build Windows de Side B

Consultar `windows/ARCHITECTURE.md` para el módulo y contrato afectados. Usar `windows/scripts/windows.ps1` y los requisitos de `windows/README.md`; no copiar rutas locales de otra máquina.

El runtime mantiene una cola autoritativa y snapshots completos. Preservar `entryId`, `generation`, `loaded_generation`, avance por EOF y validación de comandos retrasados. Comprobar cambios con las pruebas de cola/controlador, sin depender de una cuenta real.

El login usa WebView2 y almacenamiento protegido Windows; verificar cancelación/cierre y restauración sin exponer cookies ni cambiar cuenta durante pruebas sin autorización del usuario. Las tareas de autenticación invalidan resultados anteriores mediante su generación.

libmpv necesita la DLL y su biblioteca de importación MSVC. Bootstrap fija asset y SHA256; `SIDEB_MPV_DIR` permite una instalación existente. Usar el entorno MSVC que resuelve el script y ejecutar `verify`/`build` para cambios nativos. Un ejecutable standalone debe incluir la DLL y abrir sin Vite. La verificación del instalador, audio físico y macOS se informa aparte si no se ejecutó.
