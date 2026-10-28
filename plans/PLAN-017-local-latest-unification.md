# PLAN-017 — Unificar latest y el trabajo local de Mac

- Fecha: 2026-10-28 (America/Montevideo).
- Objetivo: una build en la carpeta habitual `SIDE B` que conserve latest1.2.7 y sus cambios actuales, junto a todo el producto Mac local (búsqueda nativa/preview/retención y Relacionado).
- Estado: unión de fuentes verificada en0004; carpeta de destino corregida a `SIDE B` por pedido del usuario, FIX-268/build0167 Release compilada y verificada. Origen local `SIDE B` sobre d6e2c4b; destino `sideb-github-latest` sobre d0b5549, coincide con origin/main al iniciar. Ambos árboles y builds previas conservados.
- Respaldo externo: `sideb-local-backups/2026-10-28-unification/`, inventario por SHA, parche de cambios previos del destino y propuestas de merge por archivo.

## Pasos

- [x] Inventariar135rutas locales contra base común/destino;56idénticas,30sin cambio en destino,49divergentes. Comprobar que19divergencias ya están incluidas como subconjunto en latest.
- [x] Conservar core, traducciones, Windows, Inter/letras y rating/marquee de latest; documentos Windows015/016 locales ya renombrados017/018 por FIX-260, sin duplicarlos.
- [x] Incorporar28rutas Apple sin conflicto y combinar PlayerViewModel, Explore, Library, Search y Recommended con las revisiones actuales.
- [x] Integrar rating confirmado y UI secundaria en las nuevas superficies de búsqueda y Relacionado.
- [x] Ejecutar focales, suite Swift y build numerada oficial; corregir integración y verificar firma/hashes/fuentes.
- [x] Registrar FIX-267, actualizar índices/paridad y entregar la ruta única para probar.

## Contratos

No reemplazar latest por el árbol antiguo. Conservar fixes261…266, cambios previos sin commit del destino y versiones públicas1.2.7/build20. Regenerar bindings con el core vigente; no editarlos manualmente. No publicar, hacer push o reemplazar builds existentes. No trasladar binarios/cachés/cuentas desde el árbol local.

## Validación

Regresiones de proveedor/ocurrencias/cuenta/paginación, preview sin movimiento, retención y tamaño de viewport; Relacionado con cancelación/reciclado/offset; rating explicit/clean/unknown y misma identidad; marquee/títulos/Inter/cola actuales. Suite completa en Mac y build oficial. FPS, audio y aceptación con cuenta se informan por separado.

## Focal integrado

71aprobadas:43XCTest y28Swift Testing; tres nuevas regresiones de integración validan grabación/ocurrencia/rating y composición secundaria en principal/Relacionado. Cinco diffs previos del destino conservados byte a byte. La suite y el paquete completos están en curso.

## Entrega unificada

- Destino de la primera integración (reemplazado por la corrección de carpeta de FIX-268): `sideb-github-latest`, fuentes de latestd0b5549 + producto Mac local incorporado. Los cinco diffs previos del destino y las135rutas inventariadas del origen permanecen intactos en su procedencia.
- Bundle de la primera unión en la referencia: `sideb-github-latest/builds/macos/build-0004/Side B.app`; [registro histórico](../../sideb-github-latest/builds/macos/build-0004/BUILD.json). Compiled/Release,1.2.7/build20;287Rust+272XCTest+490Swift Testing =1049ejecutadas aprobadas,17omitidas,0fallos.
- Firma estricta y10hashes revalidados; fingerprint global sin cambios durante el runner y snapshot independiente369fuentes/recursos idénticos. Binario con ambos viewports locales, título nuevo y badges de latest. Inter se conserva en fuentes Windows; Mac conserva su tipografía nativa.
- La app que estaba abierta al cerrar la verificación seguía siendo0003; no se cierra ni reemplaza ese proceso desde esta integración. Para probar la unión usar explícitamente0004.
- Sólo documentación de cierre posterior al paquete. Sin cambios/versiones nuevas de core o Windows, sin push/release. Cuenta real, audio/FPS y aceptación de interacción física no certificados por estas pruebas.

## Carpeta canónica corregida —2026-10-28 / FIX-268

El usuario aclara que todo debe quedar en su carpeta habitual `SIDE B`, sin trabajar desde `sideb-github-latest`. La integración completa ya validada se traslada a `SIDE B`, conservando su `.git`, builds0001…0166, cachés/dependencias y datos locales. La copia de referencia queda intacta; no se borra ni se utiliza como destino de desarrollo. El inventario de135cambios originales sigue idéntico al respaldo inicial, sin trabajo nuevo que resolver. Se importan170rutas diferentes y dos antiguos planes Windows quedan como enlaces al contenido renombrado017/018. No se trasladan binarios, dependencias, credenciales ni cachés.

Respaldo externo: `sideb-local-backups/2026-10-28-canonical-side-b/`. `AGENTS.md` registra el destino pedido para evitar repetir la confusión. Build Mac oficial desde `SIDE B`, contador0167 conservado. Verificación completa y firma/hashes aprobados desde SIDE B; sin push/publicación.

## Entrega canónica final —0167

- Bundle activo para probar: `SIDE B/builds/macos/build-0167/Side B.app`; [BUILD0167](../builds/macos/build-0167/BUILD.json). Release/compiled,1.2.7/build20, fuentes estables durante el runner.
- Mac/core:1049ejecutadas aprobadas,17omitidas,0fallos. Firma estricta/10hashes revalidados y737archivos de producto idénticos antes/después. Binario con RecommendedShelfViewport, ProviderSearchViewport, NativePlayerTitleViewport y ContentRatingBadge. Hash de la build0166 anterior intacto.
- Windows frontend:501aprobadas/2omitidas/0fallos, check0errores/1advertencia CSS previa y build aprobado; no constituye ejecución nativa Windows.
- Evidencia y recuperación: `sideb-local-backups/2026-10-28-canonical-side-b/`. No se escribe en la referencia, no se copian datos/cachés/Git y no se borra ninguna build previa. AGENTS.md fija SIDE B como destino habitual.
- Cuenta real/audio/FPS/interacción física pendientes. Sólo documentación posterior al paquete; sin commit/push/release.
