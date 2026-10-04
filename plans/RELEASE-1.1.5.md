# Release estable 1.1.5

## Objetivo y alcance

Publicar la versión macOS aprobada por el usuario el 2026-10-04 como estable,
tag `v1.1.5`, versión de bundle `1.1.5` y build pública `9`.
Guardar en `main` los cambios de la última build para continuar el port Windows.
No publicar un binario Windows ni incorporar `temp/`, builds o datos locales al código.

## Estado y pasos

- [x] Comprobar última release: `v1.1.4`, estable.
- [x] Revisar rama/remote: `main`, `fefucho/SIDE-B-CLIENT-NATIVE`; sin commits remotos pendientes al iniciar.
- [x] Actualizar `version.env` a `1.1.5` / `9`.
- [x] Revisar los cambios pendientes de FIX-111/112 y archivos nuevos: revisión estática por integrador y Luna sin bloqueadores encontrados.
- [x] Ejecutar runner numerado, pruebas y firma ad hoc; no abrir la app.
- [x] Revisar versión, arquitectura, SDK y contenido del ZIP de distribución.
- [ ] Guardar cambios con rutas explícitas, enviar `main` y tag.
- [ ] Publicar `SideB-macOS.zip` como estable y Latest; comprobar API/asset/hash.

## Publicación y comprobaciones

Usar el bundle del runner local y empaquetarlo con `ditto --keepParent` para
conservar la misma estructura usada por el actualizador. El commit de release
incluye `[skip ci]` para evitar que el workflow de tags vuelva a compilar y
reemplace el paquete ya verificado con otro distinto. El workflow permanece
activo para futuras releases. La verificación local sustituye esa compilación
automática en esta publicación concreta.

Ejecutar las pruebas locales sin casos live de cuenta/proveedor y omitir el
test que monta una NSWindow, respetando el pedido de no controlar la app.
Compilación/pruebas no certifican audio audible, FPS ni la sesión real del usuario.
Firma ad hoc, sin nueva notarización ni firma Developer ID en este pedido.

### Resultado de compilación

`builds/macos/build-0032/Side B.app`: `compiled`, `sourceChangedDuringBuild: false`,
versión `1.1.5` / build `9`, arm64, SDK 27.0 y mínimo macOS 15.0.
180 pruebas Rust aprobadas (7 live ignoradas), 52 XCTest y 193 Swift Testing
aprobadas. El caso `testHomeFeedCollectionViewMountAndLayout` quedó excluido
para no montar una ventana de la app. El compilador conserva advertencias
deprecadas/de aislamiento y símbolos de depuración; no hubo errores.

El ZIP preserva los bytes del ejecutable, Info.plist y firma del bundle verificado,
pasa la comprobación CRC y contiene sólo el bundle/metadata de archivo.
`SideB-macOS.zip`: 26.806.363 bytes;
SHA-256 `9319ad5beeb132c9e7f2a3dfb652b74248244a22a04bc6c736666f8808fb8403`.
La documentación de esta sección se completó después del runner; las fuentes
compiladas y `version.env` permanecen intactas.

## Referencias

- [FIXES](../FIXES.md): novedades Apple FIX-088–112 y shuffle FIX-097.
- [Paridad](../PARIDAD.md) y [guía de porteo](../PORTEO-INICIO.md): pendientes Windows.
- [Skill Git](../.agents/skills/sideb-git/SKILL.md).
- [Skill build macOS](../.agents/skills/sideb-build-macos/SKILL.md).
