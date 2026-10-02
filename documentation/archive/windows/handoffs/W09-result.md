> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W09 — barra de reproducción básica Windows

Fecha: 2026-09-29. Componente preparado por un subagente de Codex e integrado por Codex.

## Entregado

- `windows/src/lib/components/player/PlayerBar.svelte`: isla flotante con progreso, carátula, título, artista, play/pausa/reintento y volumen. Recibe `PlaybackStateDto` y callbacks; no invoca Tauri ni mantiene un segundo estado de reproducción.
- `windows/src/routes/+page.svelte`: reemplaza la barra anterior, conecta los comandos W06/W07 y centra la isla respecto del área de contenido con sidebar abierta o compacta. Corrige la evaluación del error antes de limpiar el estado al reintentar.
- El feed deja espacio inferior para la barra. El CSS incluye adaptación de ancho; la ventana estrecha aún requiere comprobación visual.

## Verificación

- `corepack pnpm check`: 0 errores, 0 avisos.
- `corepack pnpm build`: aprobó después de la última corrección de CSS.
- En la app Windows: Buscar «Daft Punk», reproducir `Veridis Quo (Edit)`, confirmar progreso 0:01→0:13; pausar y comprobar que se mantiene en 0:13; seek a 0:46; volumen de 100% a 38%. La pista y los controles persistieron al cambiar Inicio/Buscar y compactar el sidebar. La salida acústica de esta prueba concreta no se midió; el usuario ya confirmó audio audible en W06.
- Capturas públicas: [sidebar abierta](images/W09-playerbar-open.jpg), [sidebar compacta](images/W09-playerbar-collapsed.jpg).

## Pendiente

- Verificar visualmente la barra en ventana estrecha. No se añadieron controles de cola, letras ni fullscreen; pertenecen a paquetes posteriores.

ENTREGA LISTA: W09 (barra básica; prueba estrecha pendiente)
