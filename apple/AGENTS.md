# Apple

Aplicar [instrucciones comunes](../AGENTS.md). Modificar la app Mac y su integración, sin adaptar el core protegido para necesidades exclusivas Apple.

- SwiftUI/AppKit para UI, AVPlayer para audio, UniFFI para contratos tipados. La red y resolución del proveedor permanecen en el core existente.
- `Package.swift` declara macOS 15 mínimo. Verificar SDK real y disponibilidad; usar `#available` para APIs posteriores. No fijar el sistema operativo del agente en estas instrucciones.
- Preservar shell/sidebar, navegación, Ahora suena y barra flotante centrada sobre el área de contenido. Comprobar medidas actuales antes de reutilizar el blueprint histórico.
- Conservar título/controles de ventana, teclado, foco, accesibilidad y acciones de menús. Aplicar Liquid Glass según disponibilidad y legibilidad, no de forma masiva al contenido.
- Preservar identidad de ocurrencias, generaciones y estado de reproducción. Cambiar cuenta invalida datos privados y respuestas pendientes.
- Elegir contenedores SwiftUI/AppKit según contenido y trazas; `NativeTrackTableView` es una referencia para pistas, no una regla universal para todo feed.
- Identidad estable, observación acotada y carga/decodificación de imágenes limitada/cancelable. Mutar AppKit en el hilo principal; evitar trabajo costoso en `body`.
- Ejecutar pruebas apropiadas y `swift test --package-path apple`. Medir rendimiento con Instruments en el mismo escenario/build/Mac; compilar no demuestra 120 Hz.
- Para builds locales usar [sideb-build-macos](../.agents/skills/sideb-build-macos/SKILL.md). Regenera XCFramework/bindings antes de compilar, sin cambiar fuentes del core. No editar manualmente bindings para simular un cambio Rust.
- Un fix compartido requiere [core/AGENTS.md](../core/AGENTS.md) y revisar Windows. Una tarea Apple permite consultar Windows como referencia de lectura, no modificarlo.

Consultar antecedentes y registrar arreglos en [FIXES.md único](../FIXES.md) con tag `[Apple]`, consultar [planes](plans/README.md) y evaluar [paridad](../PARIDAD.md) según las reglas comunes.
