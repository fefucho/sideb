# UX-05 · Menús contextuales compartidos

## Decisión
Reproducir política de macOS, no inventar opciones por pantalla. Una política TypeScript pura recibe target/origen/hechos y produce secciones; el mismo menú sirve para clic derecho y Más. Un executor central traduce acciones a controllers/RPC. Ningún botón habilitado sin acción real.

## Contrato
- Canción: reproducir, iniciar radio, siguiente/final de cola; like, biblioteca sólo con token válido; agregar a playlist/submenú y nueva playlist; ir al álbum/artista si hay IDs; copiar enlace; quitar de playlist propia por setVideoId; quitar ocurrencia de cola salvo actual.
- Álbum/playlist: reproducir, shuffle, radio cuando existe endpoint, siguiente/final (todas las páginas), biblioteca cuando conocida; navegación, copiar enlace. Playlist propia: editar, ordenar si editable, eliminar. LM no admite editar/eliminar/guardar. Radio dinámica sólo reproducir mix, navegar y acciones conocidas; no tratarla como playlist editable.
- Artista: radio si tiene endpoint, suscripción cuando disponible, navegar y copiar enlace. Ocultar navegación al destino ya abierto. Guest no habilita mutaciones de cuenta; propiedad desconocida nunca implica propia.
- `MenuTarget` transporta DTO real y para queue `entryId`; `MenuOrigin` indica vista/playlist actual/propiedad y contexto. Abrir por servicio en Svelte context compartido; evitar propagación desde links internos.
- Menu UI: clamp al viewport, secciones, submenús, Escape/clic fuera, flechas/roving focus/Shift+F10, restauración de foco. Impedir menú WebView sólo sobre entidades musicales. Share inicial copia URL y comunica error real.
- Referencia: `apple/Sources/SideB/UI/ContextMenu/{MenuPolicy,MenuModels,MenuActionExecutor}.swift`, `UI/AppContextMenuFactory.swift`.

## Propiedad y verificación
Segunda ola: política/component/context y hooks de Home/Search/Sidebar/Album/Artist/Catalog/Library. Root: executor e integración con playlist/player/fullscreen. No editar archivos de otro agente activo.

Pruebas de política para guest, LM, radio, ownership desconocida, current queue occurrence y tokens. Manual clic derecho y Más deben coincidir; probar submenú/teclado y al menos una acción de cada grupo.
