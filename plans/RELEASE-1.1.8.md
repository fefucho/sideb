# Release estable 1.1.8

- Fecha: 2026-10-09 (America/Montevideo).
- Objetivo: publicar código, actualización instalable Mac y documentación de paridad autorizados por el usuario.
- Versión: patch 1.1.8, build pública 12, tag v1.1.8; estable/Latest para el actualizador.
- Ámbito: macOS Apple Silicon, mínimo macOS 15. Incluye FIX-131 (interfaz ES/EN) y conserva los comportamientos de 1.1.7. El repositorio incorpora el checklist Windows de 113 tareas; esta release no implementa esos ports.
- Fuente funcional/documental: commit f92b6b39bf0d386c7092a209091ac5b38155d8db.
- Estado: build-0068 y paquete verificados; publicación pendiente.

## Pasos

- [x] Revisar main/origin, cambios completos y ausencia de tag v1.1.8.
- [x] Commit explícito de FIX-131 y auditoría Windows, sin builds/temp/datos locales.
- [x] Elegir versión/build y preparar notas fieles al alcance.
- [x] Runner numerado, suites, fuentes estables y firma.
- [x] ZIP con bundle/idiomas y extracción: CRC, bytes, versión, arquitectura y firma.
- [ ] Commit release [skip ci], revisión de commits salientes y push main/tag.
- [ ] Draft con asset verificado, publicación estable/Latest.
- [ ] API latest, digest, notas y descarga pública verificados.
- [ ] Cierre documental enviado a main.

## Protocolo

Conservar [RELEASE-1.1.7](RELEASE-1.1.7.md): publicar el bundle del runner local y usar commit [skip ci] para que el workflow de tags no lo sustituya por otra compilación. No cambiar workflows ni mover tags anteriores. El actualizador consulta /releases/latest; conservar SideB-macOS.zip con Side B.app en la raíz.

Los 688 textos ES/EN de FIX-131 incluyen errores/menús/AX/plurales y selector primero en General. Nombres, letras, contenido externo y notas de release conservan su idioma original; cuenta y región de rankings permanecen independientes.

La validación previa build-0067 aprobó 562 pruebas y QA aislada. Para esta versión se genera otra build numerada; esos resultados previos no reemplazan su comprobación. Firma ad hoc, sin notarización Developer ID. No se prueba actualización de la instalación real ni se accede a cuenta real.

## Verificación del paquete

- Runner: `builds/macos/build-0068/BUILD.json`, `compiled`, `sourceChangedDuringBuild: false`.
- Suites: 182 Rust (7 live existentes ignoradas), 140 XCTest y 240 Swift Testing: **562 aprobadas**, cero fallos.
- App: `builds/macos/build-0068/Side B.app`, versión 1.1.8/build 12, com.fefucho.SideB.v2, arm64; mínimo binario/plist macOS 15.0, SDK real 27.0.
- ZIP: `builds/macos/build-0068/SideB-macOS.zip`, 27348395 bytes; SHA-256 `4060bcaf8a2b67351ce6493123ac30dc50dcfae40ecf8b04c3c363976746b54f`.
- Diez hashes del manifest y diez archivos de app tras extracción coinciden; CRC y firma ad hoc estricta original/extraída aprobadas.
- Ambos idiomas presentes dentro de SideB_SideB.bundle: 686 textos + 2 plurales por idioma; Inicio/Home comprobados. No contiene flag HomeLab en producción.
- Evidencia: `builds/macos/build-0068/release-package-verification.json` y `release-binary-build.txt`.
- Runner no modificó fuentes de core/bindings/app/Windows. Cambios posteriores limitados a documentación de release; version.env y fuentes de la app conservan los bytes compilados.

## Publicación verificada

Pendiente de draft, asset y API pública.

## Notas de la release

### Novedades

- Interfaz unificada en español y traducción completa al inglés.
- Selector Español/English al comienzo de General en Configuración.
- Cambio de idioma en vivo en pantallas, menús, ayudas y mensajes, conservando reproducción, navegación, páginas y cola.
- Preferencia de idioma guardada entre ejecuciones, independiente de la cuenta y del país de rankings.
- Los títulos originales de canciones, álbumes y listas, letras y descripciones conservan su contenido.

El repositorio incluye además la auditoría y el plan de paridad Windows, con las funciones y rediseños pendientes. Esa implementación continúa por separado.

### Descarga

SideB-macOS.zip contiene Side B 1.1.8 (build 12), para Mac con Apple Silicon y macOS 15 o posterior. Firma ad hoc verificada; sin notarización Developer ID.

Esta release aprobó 562 pruebas automáticas (182 Rust, 140 XCTest y 240 Swift Testing). Ensayo físico de VoiceOver, ventanas múltiples, cuenta/audio reales, trackpad y FPS pendiente según FIX-131.

