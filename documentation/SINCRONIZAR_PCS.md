# Compartir el código entre Windows y macOS

`apple/`, `windows/` y `core/` viven en el mismo repositorio. GitHub comparte el código y los commits; cada PC conserva sus propias dependencias y archivos de compilación. No hace falta publicar un release para trabajar desde las dos máquinas.

El script [`Scripts/sync.sh`](../Scripts/sync.sh) funciona con Bash y Git en macOS y Git Bash en Windows. [`Scripts/sync.ps1`](../Scripts/sync.ps1) permite usarlo desde PowerShell, usando el Bash incluido en Git for Windows. No requiere Node.js, plugins ni tokens guardados en archivos.

## Rama compartida e integración

El destino común es `main`: ambas PCs deben trabajar sobre la misma base, con `apple/`, `windows/` y un solo `core/`. Las ramas de arreglos son temporales y se integran mediante revisión.

La integración inicial ya está en `main` mediante el [PR #1](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/pull/1), basada en el `main` macOS y con el historial Windows incorporado. Conserva los fuentes de la app macOS, su versión y el FIX-083 del cipher; adapta Windows a esa base. Las CI de [macOS](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/actions/runs/36965397021), [Windows](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/actions/runs/36965397069) y [sincronización](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/actions/runs/36965397035) terminaron correctamente. `windows/main` queda como referencia del estado anterior; los nuevos cambios se hacen desde `main`.

Para verificar en el Mac sin cambiar tu checkout habitual:

```bash
git fetch origin
git worktree add --detach ../SideB-integracion origin/main
cd ../SideB-integracion
cd apple
bash build_xcframework.sh
cd ..
swift test --package-path apple
```

Después, ejecutar los recorridos habituales de reproducción, búsqueda, cuenta y el atajo de espacio. El proyecto macOS actual requiere un SDK que conozca sus APIs macOS 27; la CI usa el runner `xcode-27`. La versión mínima de despliegue se mantiene en macOS 15.

`swift test` comprueba por defecto los contratos y lógica sin consultar servicios externos. Las pruebas antiguas de YouTube se habilitan con `SIDEB_LIVE_TESTS=1`; para el smoke del FIX-083 se conserva `SIDEB_LIVE_CIPHER=1`. La prueba de cuenta es independiente (`SIDEB_LIVE_ACCOUNT=1`), accede al Keychain y puede actualizar su cookie guardada: ejecutarla sólo cuando se quiere comprobar explícitamente esa cuenta. Ninguna de esas pruebas en vivo forma parte de la CI por defecto.

Ese worktree tiene HEAD separado: permite validar, pero no usar `sync push/pull`. Si hay que corregir algo allí, crear primero una rama, por ejemplo `git switch -c codex/macos-integration-check`, y después revisar/commitear los cambios.

## Usar main en ambas PCs

Si todavía no tenés el repositorio:

```bash
git clone https://github.com/fefucho/SIDE-B-CLIENT-NATIVE.git
cd SIDE-B-CLIENT-NATIVE
git fetch origin
git switch main
```

Si ya lo tenés:

```bash
git status
# Revisar y commitear los cambios locales antes de cambiar de rama.
git fetch origin
# Si la rama local aún no existe:
git switch --track origin/main
# Si ya existe:
# git switch main
# git merge --ff-only origin/main
```

No usar `reset --hard` si el Mac tiene commits o cambios locales pendientes. El avance directo incorpora la integración sin reemplazar trabajo; si las ramas divergieron, revisar esos commits antes de resolver el merge.

El fix Windows de playlists/shuffle está guardado en `555338f` y conserva su [guía del port](PLAYLIST_SHUFFLE_PORT.md). La unificación del core no traslada automáticamente las funciones implementadas en los controladores o interfaces de una plataforma a la otra.

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
