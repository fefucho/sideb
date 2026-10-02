# Compartir el código entre Windows y macOS

`apple/`, `windows/` y `core/` viven en el mismo repositorio. GitHub comparte el código y los commits; cada PC conserva sus propias dependencias y archivos de compilación. No hace falta publicar un release para trabajar desde las dos máquinas.

El script [`Scripts/sync.sh`](../Scripts/sync.sh) funciona con Bash y Git en macOS y Git Bash en Windows. [`Scripts/sync.ps1`](../Scripts/sync.ps1) permite usarlo desde PowerShell, usando el Bash incluido en Git for Windows. No requiere Node.js, plugins ni tokens guardados en archivos.

## Primera vez en el Mac

Si todavía no tenés el repositorio:

```bash
git clone https://github.com/fefucho/SIDE-B-CLIENT-NATIVE.git
cd SIDE-B-CLIENT-NATIVE
git fetch origin
git switch --track origin/windows/ux-controls-and-menus
```

Si ya lo tenés:

```bash
git status
# Revisar y commitear los cambios locales antes de cambiar de rama.
git fetch origin
# Si la rama local aún no existe:
git switch --track origin/windows/ux-controls-and-menus
# Si ya existe:
# git switch windows/ux-controls-and-menus
```

La rama `windows/ux-controls-and-menus` contiene el fix de playlists/shuffle guardado en `555338f`. Abrir esa rama en el Mac permite comparar ambos clientes y consultar la [guía del port](PLAYLIST_SHUFFLE_PORT.md).

En la revisión del 2026-10-02, `origin/main` y la rama Windows tienen historiales sin ancestro común y diferencias en `apple/`. Por eso hacer pull de `main` no incorpora el fix Windows. El script no intenta unir esos historiales ni trasladar archivos entre ellos. Para conservar tu checkout macOS en `main` y consultar Windows al lado, podés abrir otro checkout:

```bash
git fetch origin
git worktree add --detach ../SideB-Windows-reference origin/windows/ux-controls-and-menus
```

Ese checkout es una referencia para comparar: no ejecutar `sync push/pull` allí porque tiene HEAD separado. Para editar desde las dos PCs con los scripts, usar una rama de trabajo compartida. La integración de los historiales de `main` y Windows requiere una tarea específica con revisión de diferencias de ambos clientes.

## Rutina para pasar de una PC a otra

1. En la PC donde trabajaste, revisar el diff, agregar los archivos del cambio y crear un commit.
2. Ejecutar `push` desde esa PC.
3. En la otra PC, elegir la misma rama y ejecutar `pull` antes de editar.

Windows, desde la raíz del repo:

```powershell
git status
git diff
git add -- ruta/al/archivo
git commit -m "fix(windows): describir el arreglo"
powershell -NoProfile -File Scripts/sync.ps1 push
```

Mac, desde la raíz del repo:

```bash
bash Scripts/sync.sh pull
# Trabajar, revisar y commitear los archivos del cambio.
bash Scripts/sync.sh push
```

Al regresar a Windows:

```powershell
powershell -NoProfile -File Scripts/sync.ps1 pull
```

Para ver la rama, diferencias con GitHub y cambios pendientes, usar `status` en cualquiera de los dos scripts. Los scripts resuelven la raíz desde su propia ubicación, por lo que también funcionan al invocarlos desde otra carpeta.

## Reglas que conserva el script

- Siempre sincroniza la rama actual; no sustituye esa rama por `main` o `windows/main`.
- `push` configura el tracking de la rama y sólo sube commits de código. No crea ni sube tags, no cambia versiones y no dispara el workflow de release por tags.
- `pull` sólo acepta avance directo (`--ff-only`); no crea merges automáticos ni sobrescribe commits.
- `push` y `pull` rechazan cambios locales sin commitear, incluidos archivos nuevos. `status` permite inspeccionarlos.
- Si ambas PCs tienen commits distintos, pide resolver el merge/rebase antes de sincronizar. No hace force-push, reset ni stash automático.
- Los pushes pueden ejecutar las comprobaciones habituales de CI del repo; eso es independiente de publicar una versión para los usuarios.

## Trabajar en paralelo

Para pasar el trabajo de una PC a otra, usar la misma rama y terminar con `push` antes de cambiar de equipo. Para editar simultáneamente, crear ramas distintas desde la misma base, por ejemplo `codex/windows-playlists` y `codex/macos-playlists`, y después integrarlas mediante un PR o un merge revisado.

Cambiar de rama cambia el checkout completo: no intentar mantener `apple/` en una rama y `windows/` en otra dentro del mismo checkout. Si necesitás ver dos revisiones a la vez, usar dos checkouts o worktrees.

No agregar ejecutables, carpetas `target/`, `.build/`, `node_modules/`, cookies ni bases de datos de usuario. El script no ejecuta `git add .`; los archivos de cada commit se eligen al revisar el cambio.
