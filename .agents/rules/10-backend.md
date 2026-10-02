---
trigger: glob
globs: ["core/**/*.rs", "core/Cargo.toml", "core/**/Cargo.toml", "apple/build_xcframework.sh"]
---

# Side B v2 — Rust, InnerTube y UniFFI (2026)

- Mantener la red, el parseo de InnerTube, la persistencia y la resolución de streams en Rust. Exponer a Swift records y errores UniFFI tipados para los flujos de producto; no crear nuevos contratos de JSON crudo cuando un tipo estable resuelva el caso.
- Preservar la compatibilidad del audio con AVPlayer y la política actual de preferir AAC/m4a. Verificar formatos, respuestas y alternativas con el código y pruebas reales antes de convertir una preferencia en una restricción global.
- Tratar cookies, cambios de cuenta, chips y continuaciones como estado con identidad: evitar que respuestas obsoletas sobreescriban datos de otra cuenta o petición. Acotar concurrencia, reintentos y trabajo en segundo plano cuando la carga afecte a la UI.
- Para el feed, medir por separado red, deserialización, parseo, filtros y conversión UniFFI antes de optimizar. Usar fixtures de respuestas para comprobar orden, duplicados, secciones vacías y continuaciones; los tests en vivo no sustituyen esas pruebas.
- Al cambiar un contrato UniFFI, actualizar el XCFramework y el consumidor Swift en la misma tarea; compilar ambos lados y verificar disponibilidad del símbolo. No presumir que un build Swift con binarios previos valida cambios Rust.
- Las referencias de `limusic-master/` sirven para entender comportamientos de InnerTube. Adaptar solo lo necesario y comprobarlo contra la implementación y requisitos actuales de Side B.
