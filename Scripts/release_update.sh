#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

VERSION_FILE="version.env"

if [ ! -f "$VERSION_FILE" ]; then
    echo "❌ Error: no se encontró $VERSION_FILE"
    exit 1
fi

source "$VERSION_FILE"

CURRENT_VERSION="${MARKETING_VERSION:-1.0.0}"
CURRENT_BUILD="${BUILD_NUMBER:-1}"

# Determinar nueva versión
INCREMENT_TYPE="${1:-patch}"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR=${MAJOR:-1}
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}

case "$INCREMENT_TYPE" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
    *)
        # Si se pasó un número de versión directo (ej: 1.1 o 1.2.3)
        if [[ "$INCREMENT_TYPE" =~ ^[0-9]+\.[0-9]+$ ]]; then
            NEW_VERSION="${INCREMENT_TYPE}.0"
        elif [[ "$INCREMENT_TYPE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            NEW_VERSION="$INCREMENT_TYPE"
        else
            echo "❌ Tipo de incremento no válido: $INCREMENT_TYPE (usa patch, minor, major, x.y o x.y.z)"
            exit 1
        fi
        ;;
esac

if [ -z "${NEW_VERSION:-}" ]; then
    NEW_VERSION="$MAJOR.$MINOR.$PATCH"
fi

NEW_BUILD=$((CURRENT_BUILD + 1))

echo "======================================================"
echo "🚀 Lanzando actualización de Side B"
echo "Versión actual: $CURRENT_VERSION (Build $CURRENT_BUILD)"
echo "Nueva versión : $NEW_VERSION (Build $NEW_BUILD)"
echo "======================================================"

# Actualizar version.env
cat > "$VERSION_FILE" <<EOF
# Información centralizada de versiones y repositorio de Side B
MARKETING_VERSION="$NEW_VERSION"
BUILD_NUMBER="$NEW_BUILD"
GITHUB_REPO_OWNER="$GITHUB_REPO_OWNER"
GITHUB_REPO_NAME="$GITHUB_REPO_NAME"
EOF

# Extraer correcciones generales y Mac desde los registros activos
NOTES_FILE="RELEASE_NOTES.tmp"

python3 "$SCRIPT_DIR/generate_recap.py" "$NEW_VERSION" --platform macos > "$NOTES_FILE"

echo ""
echo "📝 Fix Report generado para el Release:"
cat "$NOTES_FILE"
echo ""

# Guardar en git
git add "$VERSION_FILE"
git commit -m "chore(release): actualizar versión a $NEW_VERSION (Build $NEW_BUILD)"

TAG_NAME="v$NEW_VERSION"

# Crear tag con el reporte de fixes como mensaje
git tag -a "$TAG_NAME" -F "$NOTES_FILE"

# Subir a GitHub
echo "📤 Subiendo rama main y tag $TAG_NAME a GitHub..."
git push origin main
git push origin "$TAG_NAME"

rm -f "$NOTES_FILE"

echo ""
echo "======================================================"
echo "🎉 ¡Versión $TAG_NAME lanzada con éxito!"
echo "GitHub Actions está compilando el paquete en Apple Silicon."
echo "Los usuarios de Side B recibirán este Fix Report y el update."
echo "======================================================"
