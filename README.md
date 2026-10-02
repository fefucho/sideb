# Side B

> Cliente de YouTube Music: macOS nativo con SwiftUI/AppKit y Windows con Tauri/Svelte, sobre un core Rust compartido.

## Desarrollo por plataforma

- [Windows: requisitos, comandos y verificación](windows/README.md).
- [Instrucciones comunes para agentes](AGENTS.md), con ámbitos independientes para Windows, macOS y el core.
- [Índice de documentación](documentation/README.md).
- [Compartir el código entre ambas PCs](documentation/SINCRONIZAR_PCS.md): integración basada en `main` y sincronización por Git.

Las instrucciones de instalación y desarrollo macOS se mantienen debajo.

## 🚀 Instalación en macOS

### Opción 1: Instalación automática por Terminal (Recomendado)
Para instalar o actualizar Side B en un solo paso sin lidiar con bloqueos de seguridad de macOS, ejecutá en tu Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/fefucho/SIDE-B-CLIENT-NATIVE/main/install.sh | bash
```

Este comando descarga la última versión desde GitHub Releases, la instala en `/Applications/Side B.app` y remueve automáticamente los atributos de cuarentena.

---

### Opción 2: Descarga manual (.zip) desde GitHub Releases
Podés descargar el archivo `SideB-macOS.zip` directamente desde [**Releases**](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/releases/latest).

#### ⚠️ Importante sobre la primera apertura (Gatekeeper):
Al descargar la app desde un navegador (Safari o Chrome), macOS le asigna automáticamente un atributo de **cuarentena** (`com.apple.quarantine`). Al abrirla por primera vez, macOS mostrará un aviso diciendo que *"Apple no puede comprobar si contiene software malicioso"* o que *"la aplicación está dañada"*.

> **¿Por qué pasa esto?**  
> Apple exige pagar una suscripción de desarrollador de \$99 USD anuales para notarizar y validar apps con sus servidores. Side B es un proyecto comunitario, libre y gratuito, por lo que no cuenta con esa firma comercial.

#### 💡 ¿Cómo abrirla sin dar vueltas?
1. Descomprimí el ZIP y arrastrá **`Side B.app`** a tu carpeta de **Aplicaciones** (`/Applications`).
2. Abrí la **Terminal** y ejecutá este comando de una sola línea:
   ```bash
   xattr -cr /Applications/"Side B.app"
   ```
   ¡Listo! Con eso se elimina la bandera de cuarentena y Side B abrirá normalmente con doble clic para siempre.

*(Alternativa por interfaz gráfica: si preferís no usar la Terminal, podés ir a **Ajustes del Sistema** > **Privacidad y Seguridad**, bajar hasta la sección de **Seguridad** y hacer clic en **"Abrir de todos modos"**, ingresando tu contraseña o Touch ID).*

---

## ✨ Características
- **Audio de alto rendimiento**: Integración nativa con `AVPlayer` y motor de stream optimizado en Rust.
- **Diseño macOS 26/27**: Estilo Liquid Glass, tipografía SF Pro adaptativa y paleta refinada (ver [`UI_ARCHITECTURE.md`](documentation/UI_ARCHITECTURE.md)).
- **Colección y reproducción**: Cola dinámica, radios continuas, historial y sincronización de biblioteca.
- **Auto-actualizaciones**: Integración directa con GitHub Releases para recibir nuevas versiones dentro de la app con un solo clic. Consulta la [**Guía de Actualizaciones y Lanzamiento**](documentation/GUIA_DE_ACTUALIZACION.md).

## 💻 Requisitos
- macOS 15.0 o superior (compatible con Apple Silicon e Intel).

## 🛠️ Compilación local
Para compilar y ejecutar en modo Release:
```bash
sh Scripts/compile_and_run.sh
```

## 🧪 Pruebas
```bash
swift test --package-path apple
```

## 📚 Documentación del Proyecto
- [**Estado del Proyecto**](documentation/PROJECT_STATE.md): Resumen de arquitectura, hitos y componentes vigentes.
- [**Planes y Epics**](documentation/plans/README.md): Registro histórico de epics y roadmaps de producto.
- [**Registro de Fixes**](documentation/FIXES_LOG.md): Bitácora técnica continua de correcciones y mejoras.
- [**Auditorías y Reportes**](documentation/audits/README.md): Archivo histórico de optimizaciones de scroll y diagnósticos forenses.

## 🙏 Agradecimientos y Créditos

Side B es posible gracias al software de código abierto y a proyectos excepcionales que allanaron el camino:

- **[Limusic](https://github.com/SimoHypers/limusic)** (creado por [SimoHypers](https://github.com/SimoHypers)): La base del backend en Rust (`core`), la integración con la API de InnerTube (YouTube Music), la lógica de resolución de streams y cipher, el soporte de PoToken y los esquemas de persistencia local en SQLite están fundamentados y adaptados de la arquitectura desarrollada originalmente en el proyecto Limusic. ¡Muchas gracias por su valioso trabajo en la comunidad de código abierto!
