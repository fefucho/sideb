# Release 1.2.6

- Fecha: 2026-10-19 (America/Montevideo).
- Estado: **publicada como Latest 1.2.6/build 19**, tag v1.2.6, no prerelease; mantiene el aviso beta.
- Autorización: «actualiza el codigo desde github y despues arma la nueva sidebar pone las opciones etc y subilo otra vez».
- Base: origin/main 23f1df5; conserva la integración Windows de colecciones/cipher de 8f38bfe y toda 1.2.5.
- Fuentes: ea7f80a347f9c5656c67be8909294adc172b4175, tag exacto creado por el flujo autorizado sin force.
- Publicación: [workflow 39329895213](https://github.com/fefucho/sideb/actions/runs/39329895213), cuatro jobs aprobados al primer intento; [release pública](https://github.com/fefucho/sideb/releases/tag/v1.2.6) publicada 2026-10-19 22:11:00 UTC.
- Contenido: FIX-224 sidebar y Apariencia en ambas apps; FIX-225 metadatos/publicación. [Plan funcional](PLAN-010-sidebar-delivery.md), PAR-036.

## Pasos

- [x] Crear checkout desde GitHub y conservar el trabajo local previo.
- [x] Integrar sidebar/opciones con fuentes remotas; actualizar metadatos y notas.
- [x] Aprobar verificaciones locales y revisión del diff.
- [x] Commit/push y solicitud de tag del SHA exacto sin force.
- [x] Aprobar ambos builds y la publicación conjunta del workflow.
- [x] Descargar los cinco assets públicos sin autenticación; comprobar Latest, tag, versiones, arquitectura, firma/hashes y selección del actualizador.
- [x] Registrar cierre en FIXES/paridad/planes y subir documentación.

## Verificación

- Preflight v1.2.6/build 19 y 20 tests locales de release/runner aprobados. 752 claves ES/EN generadas y validadas. Frontend local: check 0/0, 399 aprobadas/1 fixture exclusiva Windows omitida y build aprobado. QA browser con controles reales y renders Mac de lista/cuadrícula revisados; preferencias persisten y los selectores se sincronizan sin modificar recomendaciones.
- Mac local: builds/macos/build-0001/Side B.app, compiled/sourceChangedDuringBuild=false, 764 ejecutadas aprobadas, 14 live omitidas, diez hashes/firma/arm64 correctos. Diagnóstico inicial de enlace de caché preservado; no consumió build ni cambió fuentes. Tras compilar sólo cambian CSS Windows y CI Mac general serializado; los paquetes oficiales recompilan el commit final limpio.
- Ambos builders oficiales: Release build-0001, versión 1.2.6/build 19, SHA exacto, árboles limpios, sourceChangedDuringBuild=false y pasos passed. Logs/manifests descargados en builds/releases/v1.2.6/actions/release-diagnostics-{macos,windows}.
- Mac CI: 97 InnerTube +91 core, 239 XCTest y 337 Swift Testing ejecutadas (suite 344 con siete live omitidas): **764 aprobadas**, 14 live omitidas en total. Firma deep/strict, arm64 y plist correctos; diez hashes internos coinciden con BUILD.json. El binario público contiene settings.appearance, settings.sidebarLayout y sideb.sidebar.style.v1.
- Windows CI: **793 aprobadas** (400 frontend sin omisiones, 97 InnerTube, 91 core, 93 bridge, 5 player y 107 Tauri), 14 live Rust omitidas y check 0/0. Verify/build/NSIS aprobados, portable con exactamente EXE/libmpv/Vulkan/licencia y cuatro hashes internos válidos. PE x64, versión binaria 1.2.6.0.
- Root UI extraído del EXE público Windows: 2.nkqRcxX_.js, Brotli descomprimido 547225 bytes, SHA256 372faf5e25bcc3631b4bffdae88ca18767e2cb3b6fb02c848b06cc86e0b1147c. Contiene settings.appearance, settings.sidebarLayout, sidebar-layout-picker, home-background-picker y layout-toggle; coincide con el EXE aprobado de CI.
- Cinco descargas públicas sin autenticación: bytes, tamaños, digests GitHub y archivos SHA256 coinciden con CI. API Latest canónica y endpoint con el nombre anterior usado por el actualizador devuelven v1.2.6; Windows selecciona SideB-Windows-x64-setup.exe. Evidencia local ignorada: builds/releases/v1.2.6/verification/{delivery,public-downloads,workflow}.json y windows-root-ui.js.
- El workflow se despacha desde main con headSha exacto y crea el tag con GITHUB_TOKEN; se evita duplicar compilaciones por push/tag. La autorización ya incluye publicación. Core/bindings/runtime Windows y correcciones remotas protegidas sin cambios funcionales frente a 23f1df5.

## Descargas públicas verificadas

| Archivo | Bytes | SHA256 |
|---|---:|---|
| SideB-Windows-x64-SHA256.txt | 182 | f23560466e42a78929bdcbe287d6346f0847a1f7d1e8d0fbc01bd23fe15cbf89 |
| SideB-Windows-x64-setup.exe | 51183608 | 551c76d00ca668139493ec1edcc653e024076edccc6ffd5cf1e222bb2139f6fc |
| SideB-macOS-SHA256.txt | 82 | 227e08105a4a60fb4ee2f85b676a9c2ef164e5a13c2b2af3abe29ada5d9698f3 |
| SideB-macOS.zip | 28096885 | a5d945c8bf049442bd71f4ad122ada537fce4bc888828c2bf0d85f4361916a7a |
| SideB-windows-x64.zip | 71802994 | 8bb4ec1d5ab86dba15015dba8726159a49e3bb1fe55c74b3432945986bdd2096 |

## Límites

No se instalan ni abren apps de producción ni se modifica cuenta/reproducción. Mac conserva firma ad hoc sin notarización. Cuenta/proveedor real, audio audible, instalación interactiva, FPS, Narrator/VoiceOver y aceptación física no se certifican por las pruebas o compilación. La carpeta original con trabajo pendiente se conserva; el checkout actualizado/revisado es sideb-release-1.2.6. Los paquetes y el tag siguen apuntando al commit de producto ea7f80a; la documentación de cierre se guarda después de publicar.
