# PLAN-014 — Caso Homecoming y tipografía Inter

- Fecha: 2026-10-21 (America/Montevideo).
- Estado: investigación de Homecoming concluida para la consulta pública; Inter implementada y build-0018 aprobada. Aceptación humana pendiente. [FIX-241](../../FIXES.md#fix-241).
- Objetivo: contrastar Homecoming con el karaoke de macOS y empaquetar Inter para toda la interfaz Windows.
- Pedido y corrección: el usuario inicialmente reporta iluminación sólo por frase y luego precisa que sucede con Homecoming de Kanye; United in Grief sí anima palabras. No tratarlo como fallo global del renderer ni inventar tiempos ausentes. Confirmación de comportamiento de esa pista en Mac pendiente.
- Ámbito: integración y UI Windows, recursos de fuente y licencias. Apple/core se consultan; sólo un defecto compartido comprobado habilita cambios de core según sus instrucciones.
- Fuentes: FIX-228…240; PAR-037, PLAN-013 Windows, modelo/renderer y cadena de proveedores vigentes en ambas apps. Conservar las modificaciones documentales de build-0017 anteriores a este pedido.

## Pasos

- [x] Comparar datos, reconciliación y renderer de Windows/Mac; investigar respuestas públicas de Homecoming y United in Grief sin cuenta ni audio.
- [x] Documentar limitación de fuente/versión sin presentar fallback por frases como karaoke por palabra; no se reprodujo un defecto global del renderer y no se modificó.
- [x] Incluir Inter variable normal e italic y su licencia oficial en recursos locales; aplicar familia en shell, controles, menús, sidebar y paneles sin descargas en ejecución.
- [x] Verificar fuente real con fixture de componentes,frontend check/tests/build y diff. Comparación adicional de píxeles de karaoke inconclusa; no se presenta como QA de audio/sincronía.
- [x] Registrar cambios, resultados y límites en FIXES/PARIDAD y este plan; sin commit/push/release.

## Cierre

Separar pruebas de datos, renderizado, compilación y aceptación física. No certificar precisión auditiva ni FPS mediante fixtures. Build numerada sólo mediante el protocolo oficial si corresponde.

## Resultado — 2026-10-21

- Usuario precisa que sólo Homecoming parecía ir por frases, mientras United in Grief sí funciona por palabra; luego considera que la primera puede no tener ese recurso. Respuestas públicas200 de Boidu: Homecoming/Kanye West/Graduation203s,TTML Line,63p/0spans; United In Grief/Kendrick Lamar/Mr. Morale & The Big Steppers255s,TTML Word,92p/901spans temporizados. Resumen sin letras ni cuenta en `.cache/homecoming-inter/evidence.json`. Ambos shells consumen core/proveedor comunes. No equivale a identificar la edición exacta del usuario ni a escuchar sincronización Mac nueva.
- Inter4.1 oficial normal/italic100–900 y licencia local; caras y token propios, preload de normal y overrides del shell/sidebar/menús unificados. Inter custom normal/italic y componentes reales comprobados en Edge headless sin fuentes externas; seis combinaciones de ancho/idioma sin recorte de toolbar ni desborde global. La fixture antes imponía Segoe UI y ahora hereda. El API de fuentes de Chromium acredita glyphs custom donde hay texto directo; inputs/selects además se verifican por familia computada. Evidencia en `.cache/homecoming-inter/font-results.json`.
- Build oficial autorizada en pedido posterior: `node Scripts/build-version.mjs windows`,build-0018 Windows x64 Release,1.2.6/build público19,`status:compiled`,fuentes estables desde base `d6e2c4b` con cambios locales.987pruebas/check0/0,20live Rust ignoradas; frontend/nativo aprobados. Tres assets frontend coinciden con las fuentes/licencia originales; cuatro hashes de artefactos revalidados y PE x64/versión comprobados. EXE SHA256 `f97711e066945fc3e4c2c4c251f8169a90facb27a3a572bf56ea6844e409be3f`.
- Ejecutable `builds/windows/build-0018/sideb-windows.exe`,junto a libmpv/Vulkan/licencia; anteriores intactas. No se abrió la app ni probó audio/cuenta/QA humana. Sin cambios Apple/core, renderer de letras, versión pública o release. El usuario pausó compilación para discutir ideas y luego la autorizó expresamente; no se inició EXE nuevo durante esa pausa.
- Mientras compilaba se preparó [PLAN-015](PLAN-015-sidebar-hidden-topnav.md): configuración de ocultamiento total y topnav Mac. Es sólo planificación; no está en0018. El plan se incorporó y esta documentación se actualizó después de empaquetar para conservar la fuente estable de la build.
