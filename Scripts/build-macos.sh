#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "🚀 Compilando y Ejecutando SideB..."
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$#" -ne 2 ]; then
    echo "Script interno: usar node Scripts/build-version.mjs macos" >&2
    exit 2
fi
CONF="$1"
APP_DIR="$2"
case "$CONF" in release|debug) ;; *) exit 2 ;; esac
if [ -e "$APP_DIR" ]; then
    echo "El bundle de destino ya existe: $APP_DIR" >&2
    exit 1
fi
cd "$SCRIPT_DIR/../apple"
node "$SCRIPT_DIR/sync-localizations.mjs" --check

# Cargar configuración de versión y repositorio si existe
if [ -f "$SCRIPT_DIR/../version.env" ]; then
    source "$SCRIPT_DIR/../version.env"
fi
APP_VERSION="${MARKETING_VERSION:-1.0.0}"
APP_BUILD="${BUILD_NUMBER:-1}"
REPO_OWNER="${GITHUB_REPO_OWNER:-fefucho}"
REPO_NAME="${GITHUB_REPO_NAME:-side-b}"

if [ ! -d "SideBCore.xcframework" ]; then
    echo "Falta XCFramework: usar el flujo versionado que lo regenera." >&2
    exit 1
fi

echo "📦 Compilando app con el SDK de Xcode..."
# El build system predeterminado de SwiftPM en Xcode 27 enlaza SideB con
# LC_BUILD_VERSION sdk=15.0 aunque compile contra el SDK 27. El build system
# nativo conserva macOS 15 como mínimo y registra el SDK realmente usado.
swift build --build-system native -c "$CONF" --product SideB
BIN_DIR=$(swift build --build-system native -c "$CONF" --show-bin-path)
SWIFT_BIN="$BIN_DIR/SideB"

BUILT_SDK=$(xcrun vtool -show-build "$SWIFT_BIN" | awk '$1 == "sdk" { print $2; exit }')
CURRENT_SDK=$(xcrun --sdk macosx --show-sdk-version)
if [ "$BUILT_SDK" != "$CURRENT_SDK" ]; then
    echo "❌ El ejecutable declara SDK $BUILT_SDK; Xcode usa SDK $CURRENT_SDK." >&2
    exit 1
fi

echo "📦 Creando Side B.app bundle..."
APP_NAME="Side B"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "📦 Copiando ejecutable $CONF (SDK $BUILT_SDK)..."
cp "$SWIFT_BIN" "$MACOS_DIR/$APP_NAME"

# L10n resolves this signed resource inside the app before SwiftPM's build fallback.
LOCALIZATION_BUNDLE="$BIN_DIR/SideB_SideB.bundle"
if [ ! -d "$LOCALIZATION_BUNDLE" ]; then
    echo "Falta el bundle de recursos SwiftPM: $LOCALIZATION_BUNDLE" >&2
    exit 1
fi
cp -R "$LOCALIZATION_BUNDLE" "$RESOURCES_DIR/"
for LANGUAGE in es en; do
    for RESOURCE in Localizable.strings Localizable.stringsdict; do
        if [ ! -f "$RESOURCES_DIR/SideB_SideB.bundle/$LANGUAGE.lproj/$RESOURCE" ]; then
            echo "Falta el recurso $LANGUAGE/$RESOURCE empaquetado." >&2
            exit 1
        fi
    done
done

# Ícono: buscar AppIcon.icns en Resources/ junto al script
ICON_SRC="$SCRIPT_DIR/../apple/Resources/AppIcon.icns"
ICON_KEY=""
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"
    ICON_KEY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
    echo "🎨 Ícono incluido: AppIcon.icns"
else
    echo "⚠️  Sin ícono: pon tu AppIcon.icns en apple/Resources/ para incluirlo."
fi

# Créditos de la app (Acerca de Side B)
CREDITS_SRC="$SCRIPT_DIR/../apple/Resources/Credits.rtf"
if [ -f "$CREDITS_SRC" ]; then
    cp "$CREDITS_SRC" "$RESOURCES_DIR/Credits.rtf"
fi

# Proveedor visual opcional (Spotify Canvas): viaja instalado de fábrica pero retirable. El host Mac lo copia
# a Application Support al primer arranque SIN activarlo; el usuario puede desinstalarlo. Si se retira el
# directorio extensions/spotify-canvas del código fuente, la app se compila igual, sin el proveedor.
PROVIDER_SRC="$SCRIPT_DIR/../extensions/spotify-canvas"
if [ -f "$PROVIDER_SRC/Cargo.toml" ]; then
    echo "📦 Compilando proveedor visual (macOS arm64)..."
    cargo build --release --locked --target aarch64-apple-darwin \
        --manifest-path "$PROVIDER_SRC/Cargo.toml" --target-dir "$PROVIDER_SRC/target"
    PROVIDER_BIN="$PROVIDER_SRC/target/aarch64-apple-darwin/release/sideb-spotify-canvas"
    PROVIDER_DEST="$RESOURCES_DIR/VisualProviders/spotify-canvas"
    # Se firma una copia antes de empaquetar (el host copia el ejecutable fuera del bundle), de modo que
    # SHA256SUMS describe exactamente el binario firmado que viaja en la app.
    PROVIDER_STAGE="$(mktemp -d)"
    trap 'rm -rf "$PROVIDER_STAGE"' EXIT
    cp "$PROVIDER_BIN" "$PROVIDER_STAGE/sideb-spotify-canvas"
    codesign --force -s - "$PROVIDER_STAGE/sideb-spotify-canvas"
    node "$SCRIPT_DIR/package-visual-provider.mjs" --platform macos-arm64 \
        --binary "$PROVIDER_STAGE/sideb-spotify-canvas" --out "$PROVIDER_DEST"
    codesign --verify --strict "$PROVIDER_DEST/sideb-spotify-canvas"
    echo "🎧 Proveedor visual incluido: $PROVIDER_DEST"
else
    echo "ℹ️  Sin extensions/spotify-canvas: la app se empaqueta sin proveedor visual."
fi

# Plugin de sesión opcional (Spotify Jam, PLAN-023): ejecutable separado que la app lanza sólo cuando el
# usuario se une a un Jam. Si se retira extensions/spotify-jam del código fuente, la app se compila igual.
JAM_SRC="$SCRIPT_DIR/../extensions/spotify-jam"
if [ -f "$JAM_SRC/Cargo.toml" ]; then
    echo "📦 Compilando plugin de sesión Spotify Jam (macOS arm64)..."
    cargo build --release --locked --target aarch64-apple-darwin \
        --manifest-path "$JAM_SRC/Cargo.toml" --target-dir "$JAM_SRC/target"
    JAM_DEST="$RESOURCES_DIR/SessionProviders/spotify-jam"
    mkdir -p "$JAM_DEST"
    cp "$JAM_SRC/target/aarch64-apple-darwin/release/sideb-spotify-jam" "$JAM_DEST/sideb-spotify-jam"
    cp "$JAM_SRC/LICENSE" "$JAM_DEST/LICENSE"
    codesign --force -s - "$JAM_DEST/sideb-spotify-jam"
    codesign --verify --strict "$JAM_DEST/sideb-spotify-jam"
    echo "🎧 Plugin de sesión incluido: $JAM_DEST"
else
    echo "ℹ️  Sin extensions/spotify-jam: la app se empaqueta sin Spotify Jam."
fi

# Creamos un Info.plist básico
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.fefucho.SideB.v2</string>
    <key>CFBundleName</key>
    <string>Side B</string>
    <key>CFBundleDisplayName</key>
    <string>Side B</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>es</string>
    <key>CFBundleLocalizations</key>
    <array><string>es</string><string>en</string></array>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>GitHubRepoOwner</key>
    <string>${REPO_OWNER}</string>
    <key>GitHubRepoName</key>
    <string>${REPO_NAME}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
$ICON_KEY
</dict>
</plist>
EOF

# La firma debe funcionar y verificarse antes de entregar el bundle.
codesign --force --deep -s - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Bundle listo: $APP_DIR"
