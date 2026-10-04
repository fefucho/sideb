---
name: sideb-build-macos
description: Compilar y conservar una build local numerada de Side B para Mac, o compilar y abrir la app. Usar para builds de prueba macOS; no para publicar releases.
---

# Build local Mac

Leer README y `apple/AGENTS.md`. Desde la raíz usar:

```sh
node Scripts/build-version.mjs macos
```

Requiere macOS Apple Silicon (el builder XCFramework genera arm64), Xcode con SDK compatible con las APIs del proyecto, Rust/cargo/rustup, Git y Node.js 22.12+. No afirmar que compila en otro host.

El comando prueba el core, regenera XCFramework/bindings, prueba Swift y empaqueta con SwiftPM `--build-system native`, comprobación de SDK y firma ad hoc verificada. Regenerar artefactos no autoriza modificar fuentes Rust. Revisar el diff generado y preservar cambios existentes.

Predeterminado release; `--configuration debug` si se pide debug. `--open` si se pide ejecutar. La entrada compatible `bash Scripts/compile_and_run.sh` usa el mismo flujo y abre la nueva app. No matar ni reemplazar versiones anteriores.

Entregar ruta `builds/macos/build-NNNN/Side B.app`, resultado de `BUILD.json` y límites. Un fallo conserva log y consume número; corregir y producir otro. No presentar bundles parciales como listos ni inferir audio/FPS.

Limpiar versiones sólo cuando se pida, conservando `.next-number`. No cambiar `version.env`, instalar en `/Applications`, crear tags, hacer push ni publicar para compilar localmente.
