#!/bin/bash
set -e
export PATH="$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=15.0

# Configuración
WORKSPACE_DIR="../core"
CRATE_NAME="sideb_core"
MAC_TARGET="aarch64-apple-darwin"
OUTPUT_DIR="SideBCore/Sources/SideBCore"

echo "======================================"
echo "Compilando $CRATE_NAME para macOS..."
echo "======================================"

# Movernos al workspace de Rust
cd "$WORKSPACE_DIR"

# 1. Asegurarnos de tener el target instalado
rustup target add $MAC_TARGET

# 2. Compilar la librería estática
cargo build --locked --release --target $MAC_TARGET --package sideb-core

# 3. Generar los bindings de UniFFI
# uniffi-bindgen extrae las interfaces de lib.rs y genera .swift y .h
echo "Generando bindings para Swift..."
cargo run --locked --bin uniffi-bindgen -- generate \
  --library target/$MAC_TARGET/release/libsideb_core.dylib \
  --language swift \
  --out-dir ../apple/$OUTPUT_DIR

# Fix Swift 6 Strict Concurrency warnings/errors in generated file
sed -i '' 's/private var initializationResult/private let initializationResult/g' ../apple/$OUTPUT_DIR/sideb_core.swift 2>/dev/null || true
sed -i '' 's/^fileprivate let uniffiContinuationHandleMap/nonisolated(unsafe) fileprivate let uniffiContinuationHandleMap/' ../apple/$OUTPUT_DIR/sideb_core.swift 2>/dev/null || true
sed -i '' 's/^private let uniffiContinuationHandleMap/nonisolated(unsafe) private let uniffiContinuationHandleMap/' ../apple/$OUTPUT_DIR/sideb_core.swift 2>/dev/null || true
sed -i '' 's/^fileprivate class UniffiHandleMap<T>\(: @unchecked Sendable\)\{0,1\}/fileprivate class UniffiHandleMap<T>: @unchecked Sendable/' ../apple/$OUTPUT_DIR/sideb_core.swift 2>/dev/null || true
sed -i '' 's/^private class UniffiHandleMap<T>\(: @unchecked Sendable\)\{0,1\}/private class UniffiHandleMap<T>: @unchecked Sendable/' ../apple/$OUTPUT_DIR/sideb_core.swift 2>/dev/null || true

# 4. Crear la estructura del xcframework (usando la librería estática para integrarlo fácil en Xcode)
cd ../apple

echo "Empaquetando en XCFramework..."

# Limpiar build anterior
rm -rf SideBCore.xcframework

# Crear un directorio temporal para las cabeceras
mkdir -p build/Headers
cp $OUTPUT_DIR/*.h build/Headers/
cp $OUTPUT_DIR/*.modulemap build/Headers/module.modulemap 2>/dev/null || true

# Empaquetar usando la librería estática (.a)
xcodebuild -create-xcframework \
  -library ../core/target/$MAC_TARGET/release/libsideb_core.a \
  -headers build/Headers \
  -output SideBCore.xcframework

# Limpiar temporal
rm -rf build

echo "✅ Listo! SideBCore.xcframework generado correctamente."
