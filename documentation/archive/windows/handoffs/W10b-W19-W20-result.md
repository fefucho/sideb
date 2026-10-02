> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W10b/W10c + W19/W20 — Inicio, álbum y artista

**Fecha:** 2026-09-30. **Estado:** implementación integrada y recorrido funcional básico aprobado por el usuario; paridad visual y casos especiales pendientes.

## Causa de las pocas categorías

El core ya devuelve `HomePageRecord.continuation`, pero el DTO Tauri anterior lo descartaba y Windows sólo pedía `get_home_page`. macOS conserva ese token y usa `getHomeContinuation`; además precarga hasta tres páginas para sus secciones prioritarias. No es un límite visual ni una falta de categorías en el componente.

## Trabajo realizado

Tres subagentes GPT-6 Luna implementaron en áreas separadas puente/DTO, álbum/componentes compartidos y artista/catálogo. Root integró navegación, paginación y reproducción, revisó contra fuentes Apple actuales y corrigió contratos/estados.

- Inicio: continuation, precarga limitada a tres peticiones/12 segundos y carga al acercarse al pie, botón manual/reintento, deduplicación por firma Mac, invalidación al cambiar chip/sesión y protección de respuestas antiguas. El presupuesto limita el inicio de peticiones; no aborta una llamada ya iniciada por red lenta.
- DTO Home incluye artistas enlazables, album/albumId, artistRuns, explicit y destinos de Ver más. Las tarjetas de artista, álbum y canciones tienen navegación/reproducción real; playlist se conecta en integración PLAN-017. Flechas horizontales reflejan extremos del carril.
- Álbum: componentes separados, portada180/radio10/gap24/lateral32, título32, artista16, metadata, descripción expandida, separador, tabla numerada de filas52, carruseles y estados útiles. Reproducir y Aleatorio generan snapshot Rust con todas las canciones/portadas e índice inicial correcto. Guardar/En biblioteca usa like_playlist con sesión requerida, pending y error; Más sólo acciones reales.
- Artista: avatar180/gap28/título34, metadata real, biografía modal, mix por `get_next(None, playlistId)` igual a Mac, suscripción autenticada, top5 con filas Mac (index24, portada44, gap14, padding8/10), carruseles144 y vídeos200×112. Playlist/canción/video tienen callbacks opcionales para integración con cuenta; Ver todo topSongs usa topSongsId de playlist cuando el destino está disponible.
- Catálogo: browseId+params, grid, navegación real a tipos disponibles, estados de carga/error/vacío; get_browse_grid no expone continuation, no se inventó paginación.
- Historial de navegación conserva chip, destino y scroll; album→artist→album o Ver más→Volver no altera reproducción. Contadores invalidan requests de destinos abandonados.
- Sesión y cola siguen en Rust. Las mutaciones usan auth_generation/auth_operation/account_core del trabajo de cuenta para serializar frente a logout. No hubo cambios a core ni Apple.

## Archivos principales

`windows/src/routes/+page.svelte`, `windows/src/lib/types.ts`, `windows/src-tauri/src/lib.rs`, `windows/src/lib/home/presentation.ts`, `windows/src/lib/components/home/{HomeView,HomeShelf,HomeCard,CompactSongCard}.svelte`, `windows/src/lib/components/detail/{AlbumDetailView,DetailHeader,TrackTable,DescriptionModal,ArtistDetailView,CatalogView}.svelte`.

## Comprobaciones hasta este punto

- Puente: cargo check aprobado con Visual Studio Build Tools2022 y SIDEB_MPV_DIR; avisos dead_code existentes.
- cargo build aprobado (4m04s), con warnings dead_code/linker LNK4098. Este build precede al cierre de integración de cuenta y debe repetirse si cambian handlers/DTO.
- pnpm build desde windows aprobado antes de los últimos ajustes de componentes; pendiente final coordinado.
- Check del paquete detalle/Home quedó sin diagnósticos propios; check global encontró incompatibilidades durante cambios simultáneos de cuenta. No se declara check global aprobado hasta cierre conjunto.
- Se detectó otro chat editando el mismo checkout. El usuario autorizó coordinar. Root cedió +page/lib.rs/types/Sidebar/PlayerBar/TrackTable, preservó cambios de cuenta y dejó registro W21-coordination.md. No se relanzó la app durante su integración.

## Límites pendientes de verificar

- Comparación Mac por fuentes/medidas de código, sin captura equivalente ni equipo macOS; no declarar paridad pixel a pixel.
- Aleatorio crea una cola mezclada una vez: no sustituye W15 (modo shuffle persistente/repeat).
- Mix carga la tanda inicial de get_next; no extiende radio automáticamente con continuation (W16).
- No se probaron mutaciones reales de biblioteca/suscripción en la cuenta del usuario; se probarán estados/guards sin modificar su cuenta.
- UI de menú se limita a acciones conectadas. Acciones avanzadas del menú Mac (añadir/editar cola, menú contextual completo) dependen de W14 y políticas posteriores.
- Desarrollo debug requiere Vite en 1420. No se generó instalador autónomo.

## Validación manual del usuario — 2026-09-30

Tras recibir el recorrido de seis pruebas, el usuario respondió «perfecto anda todo». Se registra como aprobación del recorrido solicitado, sin extrapolar a funciones que no se pidieron probar:

1. Inicio: llegar al pie y cargar categorías adicionales.
2. Álbum: reproducir, siguiente, anterior y pausa; título, portada y tiempo correspondientes.
3. Fullscreen: canción y cola coincidentes con la barra.
4. Artista desde un álbum: foto, canciones, lanzamientos y descripción.
5. Mix y Aleatorio de artista: iniciar reproducción y avanzar.
6. Inicio → álbum → artista → volver dos veces: restaurar pantallas y posición.

Antes de la prueba del usuario, Codex observó 15 categorías ya cargadas en Inicio y el botón de continuación. La integración de cuenta documentó check 0 errores/0 avisos y builds aprobados en W21-result.md; no se repitieron tests por esta confirmación ni se modificó código.

Quedan fuera de esta aprobación: comparación lado a lado con macOS/DPI/ventana estrecha; errores forzados y cambios rápidos de sesión; mutaciones reales de Guardar/Suscribirse; menús avanzados; shuffle/repeat persistente; continuación automática de radio/cola. El mix y Aleatorio aprobados corresponden a la tanda inicial y a la mezcla inicial de cola implementadas.
