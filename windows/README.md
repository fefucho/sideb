# Side B para Windows

App Tauri 2 + Svelte 5/TypeScript que reutiliza el core Rust y reproduce con libmpv. Esta guía contiene el flujo vigente; [arquitectura](ARCHITECTURE.md), [pendientes](BACKLOG.md) e [instrucciones de agentes](AGENTS.md) completan la documentación activa. Los planes Wxx están en [el archivo histórico](../documentation/archive/windows/README.md).

## Requisitos

- Windows x64 con WebView2 Runtime.
- PowerShell, Node.js 24, pnpm 12.6.0 y Rust estable `x86_64-pc-windows-msvc`.
- Visual Studio 2022 Build Tools: C++ de escritorio y Windows SDK. El script selecciona 17.x explícitamente.
- Para bootstrap inicial: conexión a GitHub y 7-Zip (en PATH o instalado en `Program Files/7-Zip`). Se puede usar `tar.exe` si su versión admite el LZMA del archivo `.7z`; el tar de Windows Server 2022 no lo admite.

`package.json` fija pnpm; los lockfiles forman parte de Git. No ejecutar pnpm desde la raíz del repositorio: el proyecto frontend está en `windows/`.

## Comandos desde la raíz

```powershell
# Diagnóstico sin instalar ni abrir la app
powershell -NoProfile -File windows/scripts/windows.ps1 -Action doctor

# Descargar libmpv verificado y generar la import library MSVC
powershell -NoProfile -File windows/scripts/windows.ps1 -Action bootstrap

# Tipos, tests, frontend y pruebas Rust sin cuenta ni red de proveedor
powershell -NoProfile -File windows/scripts/windows.ps1 -Action verify

# Ejecutable que abre sin servidor Vite
powershell -NoProfile -File windows/scripts/windows.ps1 -Action build -Configuration debug

# Desarrollo con recarga
powershell -NoProfile -File windows/scripts/windows.ps1 -Action dev
```

También admiten `pwsh`. El script resuelve rutas desde su ubicación; puede invocarse desde otro directorio usando su ruta absoluta. Los errores detienen la acción y devuelven salida no exitosa.

Bootstrap usa `windows/.cache/mpv/`, ignorado por Git. La versión fijada es `mpv-dev-x86_64-20260928-git-e470f8986e` del tag `20260928` de `shinchiro/mpv-winbuild-cmake`. También prepara el loader x64 de Vulkan 1.4.363.0 desde el [archivo oficial de LunarG](https://vulkan.lunarg.com/sdk/home), necesario para cargar esta DLL de libmpv aun al reproducir sólo audio. URLs y SHA256 están fijados en el script y se comprueban antes de extraer; no se instala software en el sistema. `verify`, `build` y `package` descargan ese loader sólo cuando falta en la caché. Para usar una instalación existente con `libmpv-2.dll` y `mpv.lib`:

```powershell
$env:SIDEB_MPV_DIR = 'C:\dependencias\mpv'
powershell -NoProfile -File windows/scripts/windows.ps1 -Action verify
```

No incluir esa carpeta, cookies ni datos de usuario en Git. Si falta la dependencia, ejecutar bootstrap o suministrar una instalación válida. No usar la DLL de otra arquitectura.

## Qué produce build

- Debug: `src-tauri/target/debug/sideb-windows.exe`, `libmpv-2.dll`, `vulkan-1.dll` y `VulkanRT-License.txt` juntos.
- Release: los mismos archivos en `src-tauri/target/release/`, con `-Configuration release`.
- `CARGO_TARGET_DIR` puede cambiar la carpeta; no forma parte del contrato una unidad como `S:`.

El frontend queda incluido en el ejecutable Tauri. Mantener ambas DLL y la licencia junto al exe al copiarlo. `package` genera un instalador NSIS; su instalación requiere validación manual en una máquina limpia antes de publicarlo. WebView2 sigue siendo requisito de ejecución.

Una ventana que muestra `localhost rechazó la conexión` corresponde a una build de desarrollo cuyo Vite está apagado. Usar `dev` para esa ventana o abrir el ejecutable standalone producido por `build`.

## Iteración rápida de frontend

Desde `windows/`:

```powershell
pnpm check
pnpm test
pnpm build
```

Los tests de controladores inyectan RPC/eventos falsos y prueban consistencia sin modificar una cuenta. `verify` agrega pruebas de `innertube`, `sideb-core`, `player` y el bridge Tauri. Las pruebas en vivo ignoradas del core no se ejecutan por defecto.

`sideb-core` se comprueba con y sin `windows-bridge`: Windows usa esa feature para sus extensiones y macOS consume el contrato por defecto, incluido `CipherJsRuntime`. Las dos apps comparten la base `main`; seguir [la guía entre PCs](../documentation/SINCRONIZAR_PCS.md) para traer el código y validarlo en el Mac.

## Revisión de una entrega

Revisar `git diff`, ejecutar los gates del ámbito y comprobar en la app el recorrido afectado. Para un refactor amplio: abrir standalone, Inicio → álbum → artista → Atrás, búsqueda, barra/fullscreen, next/previous/seek; verificar sesión restaurada sin cerrar sesión. Audio audible y comparación visual se registran sólo cuando se prueban.

La CI de [Windows](../.github/workflows/windows.yml) ejecuta los mismos scripts y conserva exe + DLL como artifact. Su resultado remoto se verifica en GitHub después de enviar una rama; una ejecución local no lo demuestra.

## Trabajo con agentes

Un coordinador integra. Repartir archivos independientes; si dos agentes necesitan los mismos, usar ramas/worktrees. El encargo contiene objetivo, archivos, contrato y verificación; el resultado contiene diff, comprobaciones y límites. No se requieren planes numerados, handoffs ni un modelo/proveedor particular. Cambios pequeños quedan explicados por su commit; actualizar esta guía sólo cuando cambie el flujo.
