# Traducciones de Side B

El español es el idioma predeterminado y de respaldo. El selector de Configuración guarda `es` o `en` por instalación; no cambia la cuenta, el país de rankings ni el idioma de las consultas de YouTube. Las pruebas y HomeLab usan preferencias aisladas.

## Edición y generación

Los archivos de `fragments/` son la fuente editorial. Cada clave pertenece a un solo fragmento y contiene español e inglés. La división permite revisar cada superficie sin editar simultáneamente el catálogo central.

```json
"home.example": { "es": "Abrir %@", "en": "Open %@" }
```

Para cantidades, usar `one`/`other` y `%lld`, con un helper específico de `L10n`; los demás argumentos son `String` y usan `%@`. Traducir frases completas, conservar el orden de los argumentos y escapar un porcentaje literal del formato como `%%`. Los nombres externos que se interpolan pueden contener porcentajes sin escapar.

Desde la raíz, ejecutar:

```sh
node Scripts/sync-localizations.mjs
node Scripts/sync-localizations.mjs --check
```

El comando valida duplicados, ambos idiomas, compatibilidad de argumentos y referencias literales directas del código. Genera `Localizable.xcstrings` y los recursos nativos `es.lproj`/`en.lproj` con `xcrun xcstringstool`. Estos productos se versionan; no se editan a mano. Revisar también las claves construidas por enums/ternarios: la comprobación literal no sustituye las pruebas de esas rutas.

El runner local y el empaquetador de release comprueban sincronización y presencia de ambos idiomas/plurales antes de firmar la app. Para una build local, usar siempre `node Scripts/build-version.mjs macos`.

## Resolución en la app instalada

`L10n` prioriza `Bundle.main.resourceURL/SideB_SideB.bundle`; `Bundle.module` queda como respaldo para herramientas/pruebas. El accessor generado por SwiftPM puede apuntar a `.build`, por lo que no basta con copiar el recurso: el diagnóstico debe comprobar qué ruta se resolvió.

En una copia aislada cuyo bundle ID activa HomeLab, ejecutar su binario con `--localization-diagnostics` imprime la ruta elegida y textos/plurales ES/EN antes del arranque del core. Ese flag está limitado a HomeLab y no usa preferencias de producción. La evidencia de una copia reubicada se conserva con los diagnósticos de la build.

## Integración

- Usar `L10n.text` para presentación. Conservar `AppMessage` cuando un aviso puede seguir visible al cambiar idioma.
- Mantener códigos, IDs, raw values, nombres de contenido, aliases de clasificación, queries y parámetros en su idioma original. Traducir encabezados/chips conocidos después de clasificarlos; desconocidos quedan como los entrega el proveedor.
- Observar el idioma en la presentación SwiftUI. Los representables capturan la revisión y actualizan sólo controles visibles; los toolbars AppKit observan la revisión sin recrear controles.
- Conservar instancias, selección, offsets, imágenes y acciones. No usar `.id(language)`, resetear caches ni iniciar consultas para traducir.
- Las colas propias guardan una clave opcional de presentación independiente de `QueueContext`. Las sesiones anteriores siguen decodificándose sin ese campo; no se renombra una cola del usuario por coincidir con una palabra reservada.

Español con voseo: «Elegí», «Buscá», «Activá». Usar «lista de reproducción»/«lista», «Ahora suena», «Acceso rápido», «reproducción aleatoria». Los títulos, descripciones, letras y notas de release conservan el texto original; login web y diálogos de macOS siguen su propio idioma.

Pruebas focales: `swift test --package-path apple --no-parallel --filter Localization`. Plan y límites de la entrega: [PLAN-014](../plans/PLAN-014-localization.md).
