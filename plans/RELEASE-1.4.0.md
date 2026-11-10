# Release 1.4.0 — Mac y Windows

- Fecha: 2026-11-09 (America/Montevideo).
- Estado: **preparada, NO publicada.** Versión 1.4.0 / build 22 aplicada en `version.env`, `windows/package.json`, `windows/src-tauri/{tauri.conf.json,Cargo.toml,Cargo.lock}` y el default de `release.yml`; notas en `release-notes/1.4.0.md`. Sin commit, push, tag ni release.
- Alcance: paridad completa Mac → Windows en [PLAN-023](../windows/plans/PLAN-023-paridad-1.4.0.md) (FIX-302…309), Spotify Canvas instalado de fábrica en ambas apps y retirable (FIX-308; decisión del usuario), más el trabajo Mac FIX-270…301.
- Autorización de publicación: pendiente; publicar requiere pedido explícito.

## Verificado desde la Mac (2026-11-09)

- Frontend Windows: `svelte-check` 0 errores/1 warning previo; `node --test --test-concurrency=1 scripts/*.test.mjs` 608 pruebas, 605 aprobadas, 3 omitidas, 0 fallos; 871 claves compartidas ES/EN verificadas.
- Proveedor Spotify Canvas: `cargo test --locked` 7 aprobadas/1 omitida, clippy y fmt limpios; `swift test --filter VisualProvider` 21/21; `Scripts/*.test.mjs` 42 aprobadas/1 omitida.
- Host Windows del proveedor en harness: 60 tests Rust, clippy limpio, `cargo check` target `x86_64-pc-windows-msvc` sin errores.

## Pendiente antes de publicar

- [ ] `swift test --package-path apple` completo y build Mac numerada estable (la 0222 marcó `sourceChangedDuringBuild`).
- [ ] En la PC: `windows/scripts/windows.ps1 -Action verify` (primera compilación de `queue.rs`, `playback.rs`, host de proveedores), build x64, instalador y zip portable con la carpeta `provider/`.
- [ ] Confirmar la hipótesis de WebView2 oculto para el login/renovación del token (`on_page_load` + `eval_with_callback`); si falla, cambiar el canal.
- [ ] QA humana: lateral, Inicio, Configuración, búsqueda/artista, Spotify con cuenta real, audio, actualización.
- [ ] Decidir el texto de privacidad de Configuración (menciona que no se envían credenciales a terceros; el proveedor opcional consulta a Spotify).
- [ ] Revisar términos de Spotify antes de mencionar Canvas en comunicaciones públicas.
- [ ] Commit, push, tag `v1.4.0` y workflow `release.yml` sólo con pedido explícito.
