# UX-03 · Playlists y acciones completas

## Decisión
Usar los métodos existentes del core. La UI Windows carece de controles y bridge; no duplicar la lógica de YouTube. Cabecera como macOS: imagen 180×180, gap 24, padding horizontal 32; Reproducir, Aleatorio, Guardar cuando corresponde y Más. El menú Más y clic derecho usan la misma política UX-05.

## Contrato
- RPC autenticados: `edit_playlist_details {playlistId,name,description,privacy}`, `set_playlist_sort {playlistId,sort}`, `delete_playlist {playlistId}`, `add_to_playlist {playlistId,videoId}`, `remove_from_playlist {playlistId,videoId,setVideoId}`, `move_playlist_track {playlistId,setVideoId,successorSetVideoId}`. Devuelven `void` o error tipado.
- Backend verifica propiedad, LM/radio protegidos y `sortEditable` con datos del core, además de autorización/generación de sesión. Canonicalizar sólo prefijo VL; IDs sensibles a mayúsculas.
- Orden: default/newest/oldest/title/artist/album. Reordenar únicamente listas propias en orden manual. Quitar/reordenar por `setVideoId`, nunca sólo por ID de canción (puede repetirse).
- Editor: nombre, descripción y privacidad PRIVATE/UNLISTED/PUBLIC; pending/error; cerrar tras éxito. Eliminar requiere confirmación y luego refresca biblioteca/sidebar y vuelve a Biblioteca.
- Reproducir/Aleatorio/encolar deben resolver todas las páginas, detener continuaciones repetidas y descartar resultados tras cambio de sesión/destino o nueva intención de reproducción. No recortar silenciosamente la playlist a la página cargada. Duplicados explícitos se conservan.
- Referencia: `PlaylistDetailView.swift`, `PlaylistEditorSheet.swift`, `PlaylistDetailViewModel.swift` y `MenuPolicy.swift` en apple.

## Propiedad y verificación
Agente backend: comandos account. Segunda ola frontend: AccountController, PlaylistDetailView, editor y TrackTable (sin root). Root integra callbacks y menú compartido. Pruebas de permisos/paginación/ocurrencias/resultado obsoleto.

Manual: playlist propia y ajena, shuffle, guardar, editar, ordenar, agregar/quitar una canción y eliminación confirmada; lista larga reproduce más allá de la primera página. No ejecutar mutaciones reales durante tests automáticos.
