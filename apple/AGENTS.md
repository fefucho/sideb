# macOS

Este ámbito conserva su flujo actual. Consultar `../documentation/UI_ARCHITECTURE.md` y `../.agents/rules/20-frontend.md`; para UI, aplicar `../.agents/skills/swiftui-pro/SKILL.md`.

La app usa SwiftUI/AppKit, AVPlayer y contratos UniFFI del core. Comprobar disponibilidad contra `Package.swift` y el SDK real. No aplicar los scripts ni el backend libmpv de Windows a este ámbito.

Comprobaciones macOS: `swift test --package-path apple` desde la raíz y los scripts existentes en `Scripts/`. Este host Windows no valida una build macOS. Los cambios Rust compartidos deben advertir si requieren regenerar el XCFramework/consumidor Swift.
