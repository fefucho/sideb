# Core Rust compartido y protegido

Aplicar [instrucciones comunes](../AGENTS.md). No modificar este ámbito salvo para corregir un problema que afecte a ambas plataformas. Compilar el core existente o regenerar bindings no cambia esa restricción. UI, empaquetado y necesidades de un solo sistema se resuelven fuera del core.

Antes de un fix compartido, identificar el problema en ambas apps, contrato y consumidores. Mantener un solo core que converge en `main`.

- Red, parseo InnerTube, persistencia y resolución de streams permanecen aquí; ventana, sesión del sistema e integración de reproducción pertenecen al shell.
- Usar records/errores UniFFI tipados. Preservar `CipherJsRuntime` y constructor Apple; `windows-bridge` sigue siendo optativo.
- Conservar compatibilidad AVPlayer/libmpv. Comprobar formatos/alternativas antes de convertir una preferencia en restricción global.
- Mantener identidad de cuenta/petición/continuación; descartar respuestas obsoletas y acotar concurrencia/reintentos.
- Usar fixtures para orden, duplicados, vacíos y continuaciones. Medir red, parseo, conversión y renderizado por separado.
- Side B anterior/limusic son referencias de lectura; adaptar sólo comportamiento comprobado contra la implementación vigente.

Desde la raíz, sin cuenta:

```sh
cargo test --locked --manifest-path core/Cargo.toml -p innertube -p sideb-core
cargo test --locked --manifest-path core/Cargo.toml -p sideb-core --features windows-bridge
```

Si cambia UniFFI, regenerar XCFramework/bindings y comprobar Swift en Mac; actualizar/comprobar Tauri en Windows. Una build contra un binario viejo no valida el cambio. `player` requiere libmpv y se verifica con `windows/scripts/windows.ps1 -Action verify`. Informar plataformas no disponibles; no inferir compatibilidad verificada. Tests en vivo ignorados son optativos.

Consultar antecedentes y registrar el fix en [FIXES.md único](../FIXES.md) con tag `[Compartido]` y componente Core; registrar evidencia de ambas plataformas en [PARIDAD.md](../PARIDAD.md).
