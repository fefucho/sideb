# Instrucciones y habilidades

[AGENTS.md de la raíz](../AGENTS.md) define el flujo común. Cada plataforma tiene su propio AGENTS; las habilidades se cargan sólo cuando corresponden:

| Ámbito | Habilidad | Documentación |
|---|---|---|
| UI Windows | [windows-ui](skills/windows-ui/SKILL.md) | [Windows](../windows/README.md) |
| Tauri/audio/build Windows | [windows-runtime](skills/windows-runtime/SKILL.md) | [Arquitectura Windows](../windows/ARCHITECTURE.md) |
| UI macOS | [swiftui-pro](skills/swiftui-pro/SKILL.md) | [Arquitectura macOS](../documentation/UI_ARCHITECTURE.md) |

Las reglas de Rust/macOS existentes se conservan. El antiguo protocolo por paquetes Windows está en [el archivo histórico](../documentation/archive/windows/agents/WORKFLOW_WINDOWS.md).
