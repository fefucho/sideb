> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# PLAN-017 — Cuenta y Biblioteca Windows con referencia macOS

Fecha: 2026-09-30. Estado: base integrada y verificada en Windows; paridad completa parcial. Ver [W21-result](../handoffs/W21-result.md).

## Objetivo

Conectar la cuenta existente a Tus Me Gusta, Biblioteca (Canciones, Playlists, Álbumes, Artistas), playlists y controles de guardar/Me Gusta. macOS determina UI y comportamiento; LiMusic sólo sirve para consultar funcionamiento. No cambiar Apple ni el core compartido. No reemplazar login ni transporte de audio.

## Referencias y geometría

- `apple/Sources/SideB/Views/Library/LibraryView.swift`: cabecera COLECCIÓN/Biblioteca, 32 px horizontales, título 32, superior 24/inferior 18; tabs 13 semibold con padding 15/8 y gap 8; cuadrícula 160–220, separaciones 18/24, portada radio 10; margen inferior 130.
- `Views/Detail/PlaylistDetailView.swift`: cabecera portada 180, gap 24, título 32; LM lleva COLECCIÓN; filas 52 y reserva para reproductor.
- `Views/Sidebar/SidebarView.swift`, `SidebarProfileView.swift`, `AccountPopoverView.swift`: conservar orden Inicio, Buscar, Tus Me Gusta, Biblioteca, Historial, selector Playlists/Álbumes, cuenta.
- `Views/Common/NativeTrackTableView.swift` y PlayerViewModel: acciones reales de Me Gusta y guardar, estados separados. Biblioteca usa feedback tokens; Me Gusta usa rate_song. Album guardado usa like_playlist.

## Entrega por partes y propiedad de archivos

1. Luna backend: `windows/src-tauri/src/lib.rs`, `windows/src/lib/types.ts`. Exponer get_library_playlists/albums/artists/songs, get_playlist_continuation, rate_song, apply_song_library_action, create_playlist. Ampliar SongDto con setVideoId y library (opcionales TS para preservar productores locales), PlaylistDetailDto con metadata completa. Agregar HistoryGroupDto/get_history si la API actual lo permite. Validar sesión, entradas y generación; errores sin credenciales. No cambiar auth.rs ni core.
2. Luna Biblioteca: nuevos `components/library/LibraryView.svelte`, `components/detail/PlaylistDetailView.svelte`, modificar exclusivamente `detail/TrackTable.svelte`. Componentes de presentación con callbacks; root posee requests y navegación. Estados carga/vacío/error/invitado, tabs, tarjetas, continuación, crear playlist con formulario accesible. No cambiar +page ni tipos/backend.
3. Luna sidebar/reproductor: sólo `sidebar/*` y `player/PlayerBar.svelte`. Listas reales, navegación, perfil/popover y corazón de canción actual. Sin requests internos. No cambiar transporte ni fullscreen.
4. Codex integra estado de cuenta, navegación y reproducción de colecciones en `+page.svelte` y módulo de cuenta; revisa y verifica.

## Contratos UI acordados

TrackTable conserva props actuales y agrega opcionales: `likedIds: Set<string>`, `pendingIds: Set<string>`, `onToggleLike(track:SongDto)`, `onToggleSaved(track:SongDto)`. No mostrar botón guardar si no hay token correcto; título guardar/quitar según library.inLibrary. likedIds/pendingIds no se mutan desde componentes.

LibraryView props: `loggedIn`, `tab: 'songs'|'playlists'|'albums'|'artists'`, `songs:SongDto[]`, `playlists/albums/artists:BrowseCardDto[]`, `loading`, `loadingMore`, `error:string|null`, `continuation:string|null`, `currentTrackId`, `isPlaying`, `likedIds`, `pendingIds`, `onTab`, `onRefresh`, `onLoadMore`, `onPlay(index:number)`, `onOpenCard(card:BrowseCardDto)`, `onToggleLike`, `onToggleSaved`, `onCreatePlaylist(title:string,description:string):Promise<void>`, `onLogin`. Formulario crea privada y muestra error real.

PlaylistDetailView props: `playlist:PlaylistDetailDto|null`, `loading`, `loadingMore`, `error`, `loggedIn`, `currentTrackId`, `isPlaying`, `likedIds`, `pendingIds`, `onBack`, `onRetry`, `onLoadMore`, `onPlay(index:number)`, `onToggleLike`, `onToggleSaved`, `onToggleLibrary:()=>Promise<void>`, `onOpenArtist`, `onOpenAlbum`, `onLogin`. Guardar playlist sólo si no es LM/propia.

Sidebar conserva props y agrega opcionales `onLikes/onLibrary/onHistory`, `playlists/albums:BrowseCardDto[]`, `libraryLoading`, `libraryError:string|null`, `selectedCollectionId:string|null`, `onOpenPlaylist(id)`, `onOpenAlbum(id)`. Destination union agrega likes/library/history/playlist/artist. PlayerBar agrega opcionales `loggedIn`, `liked`, `likePending`, `onToggleLike`, `likeError:string|null`.

## Consistencia

- Al cambiar sesión se invalidan requests y se vacían colecciones, tokens y likes. Respuesta vieja nunca reemplaza datos nuevos.
- Las mutaciones se serializan por entidad; estado visual cambia sólo tras éxito y error queda visible. Likes sincronizados entre barra y tablas; hidratación desde LM sin confundir songs guardadas.
- Continuaciones usan el core, bloquean doble carga y conservan ocurrencias usando setVideoId. Nunca guardar/loguear tokens ni cookies.
- Navegar no reproduce ni cambia cola. Reproducir una fila genera cola completa de esa colección cargada con metadata e índice correcto, usando play_song existente.
- Guardar álbum/playlist o crear playlist refresca sidebar y colección afectada. Seguir artista refresca artistas.

## Verificación y límites

Ejecutar check/build frontend desde windows, cargo check/build con MSVC x64 y tests de consistencia de cuenta (respuestas obsoletas, errores de mutación, paginación). Revisar UI y leer colecciones de cuenta real si Computer Use está disponible. No alterar likes/guardados reales sólo para probar. Documentar acciones en vivo no verificadas y comparación Mac por medidas; equivalencia visual por captura exige mismo escenario macOS. Edición/eliminación de playlists y reordenamiento colaborativo se planifican después de esta entrega.
