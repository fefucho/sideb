---
name: sideb-build-windows
description: Compilar y conservar una build standalone numerada de Side B para Windows, o compilar y abrir el ejecutable. Usar para builds locales Windows; no para publicar instaladores.
---

# Build local Windows

Leer README y `windows/AGENTS.md`. Desde la raíz usar:

```powershell
node Scripts/build-version.mjs windows
```

Requiere Windows x64, WebView2, PowerShell, MSVC 2022 C++/Windows SDK, Rust MSVC, Git, Node.js 22.12+ (CI usa 24) y pnpm fijado en `windows/package.json`. Bootstrap inicial necesita conexión y 7-Zip o tar compatible. Diagnóstico: `windows/scripts/windows.ps1 -Action doctor`.

El comando usa el script existente para bootstrap si faltan DLL/import library, verifica frontend/core/player/Tauri y compila standalone. Conserva EXE, libmpv, Vulkan y licencia juntos en `builds/windows/build-NNNN/`. Assets/SHA256 están fijados; `SIDEB_MPV_DIR` permite dependencias existentes.

Predeterminado release; `--configuration debug` si se pide. `--open` si se pide ejecutar. No entregar EXE aislado ni la carpeta mutable `src-tauri/target`; conservar versiones anteriores.

Entregar ruta, resultado de `BUILD.json` y límites. Fallos conservan log y número. Diferenciar build, audio, cuenta real, instalación/actualización. Verificar frontend en Mac no valida una build nativa Windows.

Limpiar sólo cuando se pida, conservando contador. No modificar core por necesidades Windows, cambiar versiones públicas, publicar instaladores, crear tags ni hacer push para entregar una build local.
