---
trigger: model_decision
description: "Consultar al investigar InnerTube, algoritmos o componentes visuales de sideb OLD y limusic-master"
---

# Side B v2 — uso de referencias antiguas

`sideb OLD/` y `limusic-master/`, cuando estén disponibles fuera de este checkout, son fuentes pasivas de solo lectura. Confirmar en `core/` y `apple/` qué contratos, nombres, decisiones de UI y comportamientos siguen vigentes antes de adaptar código.

- Para diseño e interacción, consultar `sideb OLD/Sources/SideB/` como ejemplo. No portar reproductores WebView, inyecciones JavaScript ni parsers Swift de YouTube; el audio actual usa AVPlayer y el Core de Rust.
- Para InnerTube, consultar `limusic-master/` como referencia de endpoints, continuaciones y manejo de errores. No copiar heurísticas, identificadores ni afirmaciones de rendimiento sin comprobar que aplican a la respuesta actual.
- Las reglas macOS 15–27 y la guía activa están en `.agents/rules/20-frontend.md` y `.agents/skills/swiftui-pro/SKILL.md`. El material histórico no reemplaza documentación del SDK ni mediciones de la app.
