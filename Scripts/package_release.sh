#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../apple"
node "$SCRIPT_DIR/sync-localizations.mjs" --check

APP_NAME="Side B"
APP_DIR=".build/app/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

BIN_DIR=$(swift build -c release --show-bin-path)
cp "$BIN_DIR/SideB" "$MACOS_DIR/$APP_NAME"
LOCALIZATION_BUNDLE="$BIN_DIR/SideB_SideB.bundle"
for LANGUAGE in es en; do
  for RESOURCE in Localizable.strings Localizable.stringsdict; do
    if [ ! -f "$LOCALIZATION_BUNDLE/$LANGUAGE.lproj/$RESOURCE" ]; then
      echo "Falta recurso de idioma: $LANGUAGE/$RESOURCE" >&2
      exit 1
    fi
  done
done
cp -R "$LOCALIZATION_BUNDLE" "$RESOURCES_DIR/"

ICON_KEY=""
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
  ICON_KEY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>"
fi

if [ -f "Resources/Credits.rtf" ]; then
  cp "Resources/Credits.rtf" "$RESOURCES_DIR/Credits.rtf"
fi

RAW_TAG="${1:-${GITHUB_REF_NAME:-v1.0.0}}"
CLEAN_VERSION="${RAW_TAG#v}"
BUILD_NUM="${GITHUB_RUN_NUMBER:-1}"

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
    <key>CFBundleShortVersionString</key>
    <string>${CLEAN_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUM}</string>
    <key>GitHubRepoOwner</key>
    <string>fefucho</string>
    <key>GitHubRepoName</key>
    <string>SIDE-B-CLIENT-NATIVE</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
$ICON_KEY
</dict>
</plist>
EOF

codesign --force --deep -s - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
ditto -c -k --keepParent "$APP_DIR" "SideB-macOS.zip"

echo "✅ SideB-macOS.zip creado exitosamente."
