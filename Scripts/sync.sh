#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
ACTION="${1:-status}"
REMOTE="${2:-origin}"

fail() { echo "Error: $*" >&2; exit 1; }
usage() {
  echo "Side B: sincronizar el código entre Windows y macOS"
  echo "  bash Scripts/sync.sh status [origin]"
  echo "  bash Scripts/sync.sh push [origin]"
  echo "  bash Scripts/sync.sh pull [origin]"
  echo "push/pull requieren cambios commiteados y usan la rama actual. No crean tags ni cambian versiones."
}
if [[ "$ACTION" == "--help" || "$ACTION" == "-h" ]]; then usage; exit 0; fi
[[ "$#" -le 2 ]] || fail "Sobran argumentos. Usá --help."
case "$ACTION" in status|push|pull) ;; *) fail "Acción inválida: $ACTION. Usá status, push o pull." ;; esac
[[ "$REMOTE" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || fail "Remote inválido; usá su nombre, por ejemplo origin."
command -v git >/dev/null 2>&1 || fail "Git no está instalado."
BRANCH="$(git symbolic-ref --quiet --short HEAD)" || fail "HEAD está separado. Elegí una rama con git switch antes de sincronizar."
git remote get-url "$REMOTE" >/dev/null || fail "El remote $REMOTE no existe."
CHANGES="$(git status --porcelain --untracked-files=all)"
if [[ "$ACTION" != "status" && -n "$CHANGES" ]]; then
  fail "Hay cambios sin guardar. Revisalos y commitealos antes de $ACTION. El script no agrega archivos ni guarda cambios automáticamente."
fi

# Fetch updates tracking refs, without changing working files or importing release tags.
git fetch --no-tags "$REMOTE"
REMOTE_REF="refs/remotes/$REMOTE/$BRANCH"
REMOTE_EXISTS=false
AHEAD=0
BEHIND=0
if git rev-parse --verify --quiet "$REMOTE_REF^{commit}" >/dev/null; then
  REMOTE_EXISTS=true
  read -r BEHIND AHEAD <<< "$(git rev-list --left-right --count "$REMOTE_REF...HEAD")"
fi
echo "Rama: $BRANCH | Remote: $REMOTE"
if [[ "$REMOTE_EXISTS" == true ]]; then
  echo "Commits locales por subir: $AHEAD | Commits remotos por traer: $BEHIND"
else
  echo "Esta rama todavía no existe en $REMOTE; push la creará."
fi

case "$ACTION" in
  status)
    if [[ -n "$CHANGES" ]]; then git status --short; else echo "Directorio de trabajo limpio."; fi
    ;;
  push)
    [[ "$BEHIND" -eq 0 ]] || fail "El remoto tiene commits que faltan aquí. Traelos con pull; si las ramas divergieron, resolvé el merge/rebase antes de volver a subir."
    git -c push.followTags=false push --set-upstream "$REMOTE" "HEAD:refs/heads/$BRANCH"
    echo "Código de $BRANCH sincronizado con $REMOTE."
    ;;
  pull)
    [[ "$REMOTE_EXISTS" == true ]] || fail "La rama $BRANCH todavía no existe en $REMOTE. Subila desde la otra PC primero."
    if [[ "$AHEAD" -gt 0 && "$BEHIND" -gt 0 ]]; then
      fail "Las dos PCs tienen commits distintos. Resolvé el merge/rebase; el script no reemplaza el trabajo de ninguna."
    fi
    git -c merge.autoStash=false merge --ff-only "$REMOTE_REF"
    echo "Código de $BRANCH actualizado desde $REMOTE."
    ;;
esac
