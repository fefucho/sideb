> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W11 — fullscreen básico de reproducción en Windows

Fecha: 2026-09-29. El usuario adelantó este paquete antes de integrar W10 y pidió una Cola visual aun sin gestión de cola.

## Entregado

- `windows/src/lib/components/player/PlayerBar.svelte`: botón de flecha a la derecha, con nombre accesible y estado abierto/cerrado. Permanece visible en la barra flotante.
- `windows/src/lib/components/fullscreen/FullscreenNowPlaying.svelte`: vista de dos columnas inspirada en el fullscreen de Mac. Usa margen superior de 52 px, horizontal de 24–48 px, separación de 24–40 px y reserva inferior de 112 px para la barra. Tras comparar la captura con el usuario, las columnas quedaron visualmente equilibradas: 50/50 y portada al 95% de la izquierda, limitada por la altura disponible. Fondo basado en la portada.
- Pestañas seleccionables **Cola, Letras, Relacionado** en ese orden. Cola presenta la pista actual real y un estado vacío para lo siguiente; no se inventan pistas. Letras y Relacionado explican que sus datos aún no están disponibles.
- `windows/src/routes/+page.svelte`: apertura/cierre de la capa sin recrear la barra ni alterar comandos de audio. Se cierra con el botón, la flecha o `Esc`. La barra se centra respecto de toda la ventana mientras está abierto.

## Verificación

- `corepack pnpm check`: 0 errores, 0 avisos.
- `corepack pnpm build`: aprobó.
- Prueba manual en la app Windows con `Veridis Quo (Edit)` de Daft Punk: abrir fullscreen, cambiar las tres pestañas, reanudar la canción dentro de fullscreen (el progreso avanzó de 0:46 a 0:48), cerrar con `Esc` y confirmar que siguió avanzando (1:05). Se dejó pausada al terminar la prueba. No se midió la salida acústica de esta prueba; el usuario había confirmado audio audible en W06.
- Inspección visual a ancho habitual y una disposición de unos 800 px: portada, pestañas, panel derecho y barra conservaron separación y alineación. El breakpoint de columna única por debajo de 780 px queda pendiente de inspección visual.
- [Captura pública con Cola y pista actual](images/W11-fullscreen-queue.jpg).

**Ajuste visual posterior:** a 1102 px de ancho la portada pasó de aproximadamente 415 a 456 px; el panel derecho ocupa aproximadamente 497 px. La captura enlazada muestra esta versión corregida.

## Límites

- Cola sólo muestra la pista actual porque Windows aún no tiene QueueManager. No permite añadir, reordenar o saltar pistas.
- Letras y recomendaciones todavía no tienen fuente conectada. El selector sí cambia de panel.
- Esta es una vista que ocupa el área de la app; no cambia el modo de pantalla completa del sistema operativo.
- W10 Inicio visual sigue sin integrar y se hará como paquete separado.

ENTREGA LISTA: W11 básico
