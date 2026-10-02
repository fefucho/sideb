> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W01 — compatibilidad del core en Windows

**Fecha:** 2026-09-29. **Estado:** compatibilidad del core comprobada; M1 sigue abierto hasta validar la ventana Tauri de W02. No se modificó código de `core/` ni de `apple/`.

## Equipo y herramientas

- Windows 11 Pro x64, build 26200; AMD Ryzen 5 5500 (6 núcleos, 12 hilos); 16 GB RAM; 96 DPI (100 %), según el inventario de Antigravity.
- Visual Studio Build Tools 2022 17.14 con herramientas C++ x64 y Windows SDK 10.0.26100.0. Hay también Visual Studio Community 2026, cuya instalación no tiene `msvcrt.lib` en la ruta x64 normal.
- Rustup 1.29.1 instalado con `winget install --id Rustlang.Rustup -e`; toolchain `stable-x86_64-pc-windows-msvc`, `rustc 1.98.1`, `cargo 1.98.1`.
- Node.js v24.13.1, pnpm v11.19.0 y Git v2.53.0.windows.1 disponibles en la terminal actual. Este checkout local no tiene `.git`.

## Ejecución y resultados

El primer intento sin Rust falló porque `cargo` no existía. Tras instalar Rust, un intento desde PowerShell normal falló en el linkeo: Rust eligió `link.exe` de Visual Studio 2026 y no encontró `msvcrt.lib` (`LNK1104`). Se inició el entorno x64 de **Build Tools 2022** mediante `VsDevCmd.bat` para que `PATH`, `LIB` e `INCLUDE` apunten a la instalación completa. Desde `core/`:

| Comando | Resultado |
| --- | --- |
| `cargo test -p innertube` | 87 aprobadas; 0 fallidas. Smoke en vivo y doc tests: 0 ejecutadas. |
| `cargo test -p sideb-core` | 79 aprobadas; 0 fallidas; 7 ignoradas porque requieren proveedores en vivo. Doc tests: 0 ejecutadas. |

Ambos comandos terminaron con código de salida 0. `sideb-core` mostró avisos de código no usado y `LNK4098` (conflicto de bibliotecas CRT), sin fallar los tests. Ese aviso merece revisión si aparece durante el enlace de Tauri; no se hizo un cambio especulativo en el core.

### Repetir en una terminal de desarrollo x64

Abrir una terminal **Developer Command Prompt for VS 2022** de la instalación Build Tools, o invocar `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat` con `-arch=amd64 -host_arch=amd64` en `cmd.exe`. En esa sesión, ir a `core/` y ejecutar los dos comandos de la tabla. Si el shell no tomó el PATH nuevo de rustup, usar `%USERPROFILE%\.cargo\bin\cargo.exe`.

## Siguiente gate

W02 debe crear `windows/`, conectar la dependencia por ruta a `sideb-core`, compilar y abrir una ventana Tauri en esta PC. Hasta entonces, **M1 no está completo**. Los tests anteriores no prueban reproducción, WebView2, rendimiento ni instalador.
