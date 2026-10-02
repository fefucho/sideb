---
name: windows-ui
description: Implementar y revisar la interfaz Windows de Side B con Svelte y TypeScript, usando la app macOS como referencia visual y preservando los contratos Tauri. Usar para pantallas, navegación y estado de presentación en windows/src.
---

# Interfaz Windows de Side B

Consultar `windows/ARCHITECTURE.md` para ubicar el controlador y `windows/README.md` para ejecutar comprobaciones. La raíz de la app compone vistas; cargar datos y descartar respuestas obsoletas en el controlador del dominio correspondiente.

Para paridad visual, localizar primero la vista Swift en `apple/Sources/SideB/Views/`. Comparar ancho de ventana, sidebar y área de contenido equivalentes; medir paddings y proporciones antes de modificarlos. Reutilizar `windows/src/lib/styles/tokens.css` y componentes existentes.

La cola, pista y transporte provienen del snapshot nativo. Mantener identidades de ocurrencias, generaciones y rutas de artista/álbum; no deduplicar canciones sólo por videoId. El cambio de cuenta debe invalidar peticiones pendientes y vaciar datos privados de la presentación.

Verificar estados vacío, carga y error además del caso con datos. Usar `check`, tests del controlador afectado y build frontend; para cambios visuales comprobar la app en un escenario concreto y comunicar qué se observó. Crear fixtures o capturas cuando resuelvan una regresión o una comparación; no para cada ajuste de CSS.
