> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W08 — estructura y sidebar Windows

Fecha: 2026-09-29. Implementado por Codex con componente `Sidebar` preparado por un subagente de Codex. Antigravity terminó W07 antes de iniciar este paquete.

## Entregado

- `windows/src/lib/components/sidebar/Sidebar.svelte` y `SidebarIcon.svelte`: orden visual de macOS: Inicio, Buscar; Colección (Tus Me Gusta, Biblioteca, Historial); selector Playlists/Álbumes; perfil al pie.
- Los destinos aún no conectados figuran deshabilitados. Inicio y Buscar conservan navegación real; detalle de álbum conserva retorno a su origen.
- `windows/src/routes/+page.svelte`: shell de dos columnas, sidebar compactable, ancho de contenido estable, foco visible y `Ctrl+K` para Buscar. La navegación desplaza el contenido al inicio.
- Snapshot previo de archivos existentes en `S:\sideb-snapshots\pre-ui-2026-09-29`, verificado con SHA-256 antes de editar. Esta copia del proyecto no tiene `.git`.

## Verificación

- `corepack pnpm check`: 0 errores, 0 avisos tras integrar W08.
- `corepack pnpm build`: aprobó.
- En la app Windows: Inicio con feed público, Buscar, búsqueda de álbumes, detalle y retorno; sidebar abierta y compacta; `Ctrl+K` enfoca el campo de Buscar.
- Captura pública: [sidebar e Inicio](images/W08-sidebar-home.jpg).

## Pendiente

- El shell sigue definido en `+page.svelte`; `AppShell` y `ContentHost` separados quedan para cuando la navegación agregue más pantallas. La extracción no es necesaria para usar el sidebar actual.
- No se registró una prueba visual de ventana estrecha. Los destinos de Colección precisan sus pantallas y datos en paquetes posteriores.

ENTREGA LISTA: W08 (estructura básica y sidebar)
