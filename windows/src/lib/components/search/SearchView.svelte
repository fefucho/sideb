<script lang="ts">
  import type { AlbumCardDto, BrowseCardDto, SongDto } from "$lib/types";
  import ArtistCredits from "$lib/components/ArtistCredits.svelte";
  import type { SearchData, SearchMode } from "$lib/search/controller";
  import { createMenuHandlers } from "$lib/menu/hooks";

  interface Props {
    data: SearchData; backendReady: boolean; currentTrackId: string | null; isPlaying: boolean;
    onSubmit: (query: string, mode: SearchMode) => void; onQueryChange: (query: string) => void;
    onRetry: (query: string, mode: SearchMode) => void;
    onModeChange: (mode: SearchMode) => void; onQuickSearch: (query: string) => void;
    onPlaySong: (song: SongDto) => void; onOpenAlbum: (album: AlbumCardDto) => void;
    onOpenArtist?: (id: string) => void; onOpenPlaylist?: (id: string) => void;
  }
  let { data, backendReady, currentTrackId, isPlaying, onSubmit, onRetry, onQueryChange, onModeChange, onQuickSearch, onPlaySong, onOpenAlbum, onOpenArtist, onOpenPlaylist }: Props = $props();
  const createMenu = createMenuHandlers();
  const modes: { id: SearchMode; label: string }[] = [
    { id: 'all', label: 'Todo' }, { id: 'songs', label: 'Canciones' }, { id: 'videos', label: 'Videos' },
    { id: 'albums', label: 'Álbumes' }, { id: 'artists', label: 'Artistas' }, { id: 'playlists', label: 'Playlists' }
  ];
  function submit(event: SubmitEvent) { event.preventDefault(); onSubmit(data.query, data.mode); }
  function asSong(card: BrowseCardDto): SongDto {
    return { videoId: card.id, title: card.title, artists: card.artists ?? '', artistRuns: card.artistRuns,
      album: card.album ?? null, duration: card.duration, thumbnail: card.thumbnail, isVideo: card.isVideo ?? false,
      artistId: card.artistId ?? null, albumId: card.albumId ?? null };
  }
  function play(song: SongDto) { onPlaySong(song); }
  function playCard(card: BrowseCardDto) { if (card.kind === 'song' && card.id) play(asSong(card)); }
  function openCard(card: BrowseCardDto) {
    if (card.kind === 'artist') onOpenArtist?.(card.id);
    else if (card.kind === 'album') onOpenAlbum({ id: card.id, title: card.title, subtitle: card.subtitle, thumbnail: card.thumbnail });
    else if (card.kind === 'playlist') onOpenPlaylist?.(card.id);
    else playCard(card);
  }
  function target(card: BrowseCardDto) {
    if (card.kind === 'artist') return { kind: 'artist' as const, card };
    if (card.kind === 'playlist') return { kind: 'playlist' as const, card };
    if (card.kind === 'album') return { kind: 'album' as const, card };
    return { kind: 'song' as const, song: asSong(card) };
  }
  function openSongAlbum(song: SongDto, id: string) { onOpenAlbum({ id, title: song.album ?? '', subtitle: song.artists, thumbnail: song.thumbnail }); }
  function showMore(mode: SearchMode) { onModeChange(mode); }
  const visible = (mode: SearchMode) => data.mode === mode;
  const searched = () => data.hasSearched;
  const errorFor = (key: keyof NonNullable<SearchData['partialErrors']>) => data.partialErrors?.[key];
</script>

<div class="search-view-container" data-primary-search>
  <nav class="mode-tabs" aria-label="Modo de búsqueda">
    {#each modes as item}
      <button type="button" class="tab-btn" class:active={data.mode === item.id} disabled={!backendReady} onclick={() => onModeChange(item.id)}>{item.label}</button>
    {/each}
  </nav>
  <section class="search-section">
    <form class="search-form" onsubmit={submit}>
      <div class="input-wrapper">
        <svg class="search-icon" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>
        <input id="search-input" type="text" data-primary-search aria-label="Buscar en YouTube Music" placeholder="Buscar canciones, artistas, álbumes…" value={data.query} oninput={(event) => onQueryChange(event.currentTarget.value)} disabled={!backendReady} />
        {#if data.query && !data.isLoading}<button type="button" class="clear-btn" onclick={() => onQueryChange("")} aria-label="Limpiar búsqueda">&times;</button>{/if}
      </div>
      <button type="submit" class="submit-btn" disabled={!backendReady || data.isLoading || !data.query.trim()}>{data.isLoading ? "Buscando…" : "Buscar"}</button>
    </form>
    <div class="quick-chips"><span class="chip-label">Sugerencias:</span><button type="button" class="chip" disabled={!backendReady || data.isLoading} onclick={() => onQuickSearch("Daft Punk")}>Daft Punk</button><button type="button" class="chip" disabled={!backendReady || data.isLoading} onclick={() => onQuickSearch("Radiohead")}>Radiohead</button><button type="button" class="chip" disabled={!backendReady || data.isLoading} onclick={() => onQuickSearch("Gustavo Cerati")}>Gustavo Cerati</button></div>
  </section>
  <section class="content-section" aria-live="polite">
    {#if data.isLoading}<div class="state-container"><div class="spinner"></div><p>Buscando en YouTube Music…</p></div>
    {:else if data.error && !Object.keys(data.partialErrors).length}<div class="state-container error-state"><h3>Error al consultar el catálogo</h3><p>{data.error}</p><button class="submit-btn" type="button" onclick={() => onRetry(data.lastSearchedQuery || data.query, data.mode)}>Reintentar</button></div>
    {:else if !searched()}<div class="state-container"><h3>Buscá música</h3><p>Encontrá canciones, artistas, álbumes, videos y playlists.</p></div>
    {:else if visible('all')}
      {#if errorFor('global')}<div class="partial-error" role="alert">No se pudieron cargar todos los resultados. <button type="button" onclick={() => onRetry(data.lastSearchedQuery, 'all')}>Reintentar</button></div>{/if}
      {#if data.top.length}
        {@const card = data.top[0]}
        {@const menu = createMenu(() => target(card), { view: 'search_results' })}
        <section class="shelf"><h2>Resultado principal</h2><div class="top-layout">
        <article class="hero-card" oncontextmenu={menu.onContextMenu}>
          <button type="button" class:round={card.kind === 'artist'} class="hero-art" onclick={() => openCard(card)} onkeydown={menu.onKeyDown} aria-label={`Abrir ${card.title}`}>
            {#if card.thumbnail}<img src={card.thumbnail} alt="" loading="lazy" />{:else}<span>{card.kind === 'artist' ? '♫' : '♪'}</span>{/if}
          </button>
          <div class="hero-info"><span class="eyebrow">{card.kind === 'artist' ? 'ARTISTA' : card.kind === 'album' ? 'ÁLBUM' : card.kind === 'playlist' ? 'PLAYLIST' : card.kind === 'song' ? 'CANCIÓN' : 'RESULTADO'}</span><button class="hero-title" type="button" onclick={() => openCard(card)} onkeydown={menu.onKeyDown}>{card.title}</button>{#if card.subtitle && card.kind !== 'artist'}<p>{card.subtitle}</p>{/if}{#if card.explicit}<span class="tag-explicit" aria-label="Contenido explícito">E</span>{/if}{#if card.isVideo}<span class="tag-video">VIDEO</span>{/if}</div>
        </article>
        {#if card.kind === 'song'}<button type="button" class="hero-play" onclick={() => playCard(card)}>Reproducir</button>{/if}
        {#if card.kind === 'artist' && data.top.length > 1}<div class="known-songs"><h3>Canciones destacadas</h3>{#each data.top.slice(1).filter(item => item.kind === 'song').slice(0, 3) as related (related.id)}{@const relatedSong = asSong(related)}{@const relatedMenu = createMenu(() => ({ kind: 'song', song: relatedSong }), { view: 'search_results' })}<div class="song-row" role="group" aria-label="Opciones de canción" oncontextmenu={relatedMenu.onContextMenu}><button class="thumb-container song-play" type="button" onclick={() => play(relatedSong)} onkeydown={relatedMenu.onKeyDown} aria-label={`Reproducir ${related.title}`}>{#if related.thumbnail}<img src={related.thumbnail} alt="" loading="lazy" />{:else}<span>♫</span>{/if}</button><div class="meta-col"><button class="song-title song-play" type="button" onclick={() => play(relatedSong)} onkeydown={relatedMenu.onKeyDown}>{related.title}</button><div class="song-credits"><ArtistCredits artistRuns={related.artistRuns} artists={related.artists ?? ''} artistId={related.artistId ?? null} onOpenArtist={onOpenArtist} album={related.album ?? null} albumId={related.albumId ?? null} onOpenAlbum={(id) => openSongAlbum(relatedSong, id)} /></div></div>{#if related.explicit}<span class="tag-explicit" aria-label="Contenido explícito">E</span>{/if}{#if related.isVideo}<span class="tag-video">VIDEO</span>{/if}{#if related.duration}<span class="song-duration">{related.duration}</span>{/if}</div>{/each}</div>{/if}
      </div></section>
      {/if}
      {#if data.songs.length}<section class="shelf"><div class="shelf-heading"><h2>Canciones</h2><button type="button" onclick={() => showMore('songs')}>Ver todas</button></div><div class="song-list">{#each data.songs.slice(0, 5) as song (`${song.videoId}-${song.setVideoId ?? ''}`)}{@const menu = createMenu(() => ({ kind: 'song', song }), { view: 'search_results' })}<div class="song-row" role="group" aria-label="Opciones de canción" class:is-active-track={currentTrackId === song.videoId} oncontextmenu={menu.onContextMenu}><button type="button" class="thumb-container song-play" onclick={() => play(song)} onkeydown={menu.onKeyDown} aria-label={`Reproducir ${song.title}`}>{#if song.thumbnail}<img src={song.thumbnail} alt="" loading="lazy" />{:else}<span>♫</span>{/if}</button><div class="meta-col"><button type="button" class="song-title song-play" onclick={() => play(song)} onkeydown={menu.onKeyDown}>{song.title}</button><div class="song-credits"><ArtistCredits artistRuns={song.artistRuns} artists={song.artists} artistId={song.artistId} onOpenArtist={onOpenArtist} album={song.album} albumId={song.albumId} onOpenAlbum={(id) => openSongAlbum(song, id)} /></div></div><div class="extra-col">{#if currentTrackId === song.videoId && isPlaying}<span class="tag-playing">SONANDO</span>{/if}{#if song.isVideo}<span class="tag-video">VIDEO</span>{/if}{#if song.duration}<span class="song-duration">{song.duration}</span>{/if}</div></div>{/each}</div></section>{/if}
      {#if data.albums.length}<section class="shelf"><div class="shelf-heading"><h2>Álbumes</h2><button type="button" onclick={() => showMore('albums')}>Ver todos</button></div><div class="card-grid">{#each data.albums.slice(0, 8) as album (album.id)}{@const card: BrowseCardDto = { kind: 'album', id: album.id, title: album.title, subtitle: album.subtitle, thumbnail: album.thumbnail, duration: null }}{@const menu = createMenu(() => ({ kind: 'album', card }), { view: 'search_results' })}<button type="button" class="browse-card" onclick={() => onOpenAlbum(album)} oncontextmenu={menu.onContextMenu} onkeydown={menu.onKeyDown}><div class="cover">{#if album.thumbnail}<img src={album.thumbnail} alt="" loading="lazy" />{:else}<span>▧</span>{/if}</div><strong>{album.title}</strong>{#if card.explicit}<span class="tag-explicit">E</span>{/if}{#if album.subtitle}<small>{album.subtitle}</small>{/if}</button>{/each}</div></section>{/if}
      {#if data.artists.length}<section class="shelf"><div class="shelf-heading"><h2>Artistas</h2><button type="button" onclick={() => showMore('artists')}>Ver todos</button></div><div class="card-grid">{#each data.artists.slice(0, 8) as card (card.id)}{@const menu = createMenu(() => target(card), { view: 'search_results' })}<button type="button" class="browse-card" onclick={() => openCard(card)} oncontextmenu={menu.onContextMenu} onkeydown={menu.onKeyDown}><div class="cover round">{#if card.thumbnail}<img src={card.thumbnail} alt="" loading="lazy" />{:else}<span>♫</span>{/if}</div><strong>{card.title}</strong>{#if card.explicit}<span class="tag-explicit">E</span>{/if}{#if card.subtitle}<small>{card.subtitle}</small>{/if}</button>{/each}</div></section>{/if}
      {#if data.videos.length}<section class="shelf"><div class="shelf-heading"><h2>Videos</h2><button type="button" onclick={() => showMore('videos')}>Ver todos</button></div><div class="song-list">{#each data.videos.slice(0, 4) as song (`${song.videoId}-${song.setVideoId ?? ''}`)}{@const menu = createMenu(() => ({ kind: 'song', song }), { view: 'search_results' })}<div class="song-row" role="group" aria-label="Opciones de canción" oncontextmenu={menu.onContextMenu}><button type="button" class="thumb-container song-play" onclick={() => play(song)} onkeydown={menu.onKeyDown} aria-label={`Reproducir ${song.title}`}>{#if song.thumbnail}<img src={song.thumbnail} alt="" loading="lazy" />{:else}<span>♫</span>{/if}</button><div class="meta-col"><button type="button" class="song-title song-play" onclick={() => play(song)} onkeydown={menu.onKeyDown}>{song.title}</button><div class="song-credits"><ArtistCredits artistRuns={song.artistRuns} artists={song.artists} artistId={song.artistId} onOpenArtist={onOpenArtist} album={song.album} albumId={song.albumId} onOpenAlbum={(id) => openSongAlbum(song, id)} /></div></div><span class="tag-video">VIDEO</span></div>{/each}</div></section>{/if}
      {#if data.playlists.length}<section class="shelf"><div class="shelf-heading"><h2>Playlists</h2><button type="button" onclick={() => showMore('playlists')}>Ver todas</button></div><div class="card-grid">{#each data.playlists.slice(0, 8) as card (card.id)}{@const menu = createMenu(() => target(card), { view: 'search_results' })}<button type="button" class="browse-card" onclick={() => openCard(card)} oncontextmenu={menu.onContextMenu} onkeydown={menu.onKeyDown}><div class="cover">{#if card.thumbnail}<img src={card.thumbnail} alt="" loading="lazy" />{:else}<span>♫</span>{/if}</div><strong>{card.title}</strong>{#if card.explicit}<span class="tag-explicit">E</span>{/if}{#if card.isVideo}<span class="tag-video">VIDEO</span>{/if}{#if card.subtitle}<small>{card.subtitle}</small>{/if}</button>{/each}</div></section>{/if}
      {#if data.partialErrors?.songs || data.partialErrors?.videos || data.partialErrors?.categories}<div class="partial-error" role="status">Algunas secciones no se pudieron cargar. <button type="button" onclick={() => onRetry(data.lastSearchedQuery, 'all')}>Reintentar</button></div>{/if}
      {#if !data.top.length && !data.songs.length && !data.albums.length && !data.artists.length && !data.videos.length && !data.playlists.length}<div class="state-container"><h3>Sin resultados</h3><p>No se encontraron resultados para «{data.lastSearchedQuery}».</p></div>{/if}
    {:else}
      {@const title = modes.find(item => item.id === data.mode)?.label ?? 'Resultados'}
      {@const cards = data.mode === 'artists' ? data.artists : data.mode === 'playlists' ? data.playlists : []}
      {@const songs = data.mode === 'videos' ? data.videos : data.mode === 'songs' ? data.songs : []}
      {@const empty = data.mode === 'albums' ? data.albums.length === 0 : cards.length === 0 && songs.length === 0}
      {#if Object.keys(data.partialErrors).length}<div class="partial-error" role="status">Algunos resultados no se pudieron cargar. <button type="button" onclick={() => onRetry(data.lastSearchedQuery, data.mode)}>Reintentar</button></div>{/if}
      {#if empty}<div class="state-container"><h3>Sin resultados</h3><p>No se encontraron {title.toLowerCase()} para «{data.lastSearchedQuery}».</p></div>
      {:else}<section class="shelf"><div class="results-header"><h2>{title} para «{data.lastSearchedQuery}»</h2></div>
        {#if data.mode === 'albums'}<div class="card-grid">{#each data.albums as album (album.id)}{@const card: BrowseCardDto = { kind: 'album', id: album.id, title: album.title, subtitle: album.subtitle, thumbnail: album.thumbnail, duration: null }}{@const menu = createMenu(() => ({ kind: 'album', card }), { view: 'search_results' })}<button type="button" class="browse-card" onclick={() => onOpenAlbum(album)} oncontextmenu={menu.onContextMenu} onkeydown={menu.onKeyDown}><div class="cover">{#if album.thumbnail}<img src={album.thumbnail} alt="" loading="lazy" />{:else}<span>▧</span>{/if}</div><strong>{album.title}</strong>{#if album.subtitle}<small>{album.subtitle}</small>{/if}</button>{/each}</div>
        {:else if cards.length}<div class="card-grid">{#each cards as card (card.id)}{@const menu = createMenu(() => target(card), { view: 'search_results' })}<button type="button" class="browse-card" onclick={() => openCard(card)} oncontextmenu={menu.onContextMenu} onkeydown={menu.onKeyDown}><div class="cover" class:round={card.kind === 'artist'}>{#if card.thumbnail}<img src={card.thumbnail} alt="" loading="lazy" />{:else}<span>♫</span>{/if}</div><strong>{card.title}</strong>{#if card.explicit}<span class="tag-explicit">E</span>{/if}{#if card.isVideo}<span class="tag-video">VIDEO</span>{/if}{#if card.subtitle}<small>{card.subtitle}</small>{/if}</button>{/each}</div>
        {:else}<div class="song-list">{#each songs as song (`${song.videoId}-${song.setVideoId ?? ''}`)}{@const menu = createMenu(() => ({ kind: 'song', song }), { view: 'search_results' })}<div class="song-row" role="group" aria-label="Opciones de canción" oncontextmenu={menu.onContextMenu}><button type="button" class="thumb-container song-play" onclick={() => play(song)} onkeydown={menu.onKeyDown} aria-label={`Reproducir ${song.title}`}>{#if song.thumbnail}<img src={song.thumbnail} alt="" loading="lazy" />{:else}<span>♫</span>{/if}</button><div class="meta-col"><button type="button" class="song-title song-play" onclick={() => play(song)} onkeydown={menu.onKeyDown}>{song.title}</button><div class="song-credits"><ArtistCredits artistRuns={song.artistRuns} artists={song.artists} artistId={song.artistId} onOpenArtist={onOpenArtist} album={song.album} albumId={song.albumId} onOpenAlbum={(id) => openSongAlbum(song, id)} /></div></div>{#if song.duration}<span class="song-duration">{song.duration}</span>{/if}</div>{/each}</div>{/if}
      </section>{/if}
    {/if}
  </section>
</div>

<style>
  .search-view-container { display:flex; flex-direction:column; gap:1.4rem; }
  .mode-tabs { display:flex; flex-wrap:wrap; justify-content:center; gap:.35rem; background:#1e1e24; padding:.3rem; border-radius:12px; border:1px solid #2e2e38; width:fit-content; max-width:100%; margin:0 auto; }
  .tab-btn { background:transparent; border:0; color:#9ca3af; font-size:.88rem; font-weight:600; padding:.45rem .85rem; border-radius:8px; cursor:pointer; }
  .tab-btn:hover:not(:disabled) { color:#fff; background:#ffffff0d; }
  .tab-btn.active { background:#a33d45; color:#fff; }
  .tab-btn:disabled { opacity:.5; cursor:not-allowed; }
  .search-section { display:flex; flex-direction:column; gap:.75rem; }
  .search-form { display:flex; gap:.75rem; }
  .input-wrapper { flex:1; position:relative; display:flex; align-items:center; min-width:0; }
  .search-icon { position:absolute; left:1rem; color:#9ca3af; pointer-events:none; }
  input[type="text"] { width:100%; box-sizing:border-box; background:#24242a; border:1px solid #3a3a44; border-radius:10px; padding:.75rem 2.5rem .75rem 2.85rem; font-size:1rem; color:#fff; outline:none; }
  input[type="text"]:focus { border-color:#a33d45; box-shadow:0 0 0 2px #a33d4540; }
  .clear-btn { position:absolute; right:.75rem; background:transparent; border:0; color:#9ca3af; font-size:1.4rem; cursor:pointer; }
  .submit-btn { background:#a33d45; color:#fff; border:0; border-radius:10px; padding:.65rem 1.25rem; font-weight:600; cursor:pointer; }
  .submit-btn:disabled { opacity:.5; cursor:not-allowed; }
  .quick-chips { display:flex; align-items:center; gap:.5rem; flex-wrap:wrap; font-size:.85rem; }
  .chip-label { color:#9ca3af; }
  .chip { background:#24242a; border:1px solid #3a3a44; color:#d1d5db; border-radius:999px; padding:.25rem .75rem; cursor:pointer; }
  .content-section { min-height:320px; }
  .state-container { background:#24242a; border:1px solid #32323a; border-radius:12px; padding:2.5rem 1.5rem; text-align:center; display:flex; flex-direction:column; align-items:center; gap:.75rem; color:#9ca3af; }
  .state-container h3,.state-container p { margin:0; }.state-container h3 { color:#fff; }
  .spinner { width:32px; height:32px; border:3px solid #ffffff1a; border-top-color:#a33d45; border-radius:50%; animation:spin .8s linear infinite; }
  @keyframes spin { to { transform:rotate(360deg); } }
  .shelf { margin:0 0 1.6rem; }.shelf h2 { color:#fff; font-size:1.2rem; margin:0; }
  .shelf-heading,.results-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:.85rem; }
  .shelf-heading button,.partial-error button { color:#e4a0a3; background:transparent; border:0; font:inherit; font-weight:600; cursor:pointer; }
  .top-layout { display:grid; grid-template-columns:minmax(260px, 1fr) minmax(300px, 1.2fr); gap:1rem; background:#24242a; border:1px solid #32323a; border-radius:12px; padding:1rem; }
  .hero-card { display:flex; align-items:center; gap:1rem; min-width:0; }
  .hero-art { width:112px; height:112px; flex:none; border:0; border-radius:10px; overflow:hidden; background:#1b1b1e; color:#85858d; font-size:2.2rem; cursor:pointer; padding:0; }
  .hero-art.round { border-radius:50%; }.hero-art img { width:100%; height:100%; object-fit:cover; }
  .hero-info { min-width:0; }.eyebrow { display:block; color:#9ca3af; font-size:.68rem; font-weight:700; letter-spacing:.08em; margin-bottom:.25rem; }
  .hero-title { display:block; max-width:100%; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; border:0; padding:0; background:none; color:#fff; font-size:1.35rem; font-weight:700; text-align:left; cursor:pointer; }
  .hero-info p { margin:.25rem 0 0; color:#a1a1aa; font-size:.9rem; }.hero-play { align-self:center; grid-column:1; background:#34343c; border:0; border-radius:8px; color:#fff; padding:.55rem .85rem; cursor:pointer; }
  .known-songs { border-left:1px solid #3a3a44; padding-left:1rem; min-width:0; }.known-songs h3 { margin:0 0 .5rem; color:#d4d4d8; font-size:.85rem; }
  .song-list { display:flex; flex-direction:column; gap:.45rem; }.song-row { display:flex; align-items:center; gap:.85rem; min-width:0; padding:.55rem .7rem; background:#24242a; border:1px solid #32323a; border-radius:9px; }
  .song-row:hover { background:#2b2b32; border-color:#42424c; }.thumb-container { width:44px; height:44px; flex:none; overflow:hidden; border-radius:6px; background:#1b1b1e; display:grid; place-items:center; color:#777; }
  .thumb-container img { width:100%; height:100%; object-fit:cover; }.song-play { border:0; padding:0; color:inherit; font:inherit; text-align:left; cursor:pointer; }.song-play:focus-visible,.browse-card:focus-visible,.hero-art:focus-visible { outline:2px solid #d06c70; outline-offset:2px; }
  .meta-col { flex:1; min-width:0; }.song-title { width:100%; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; background:transparent; color:#fff; font-size:.92rem; font-weight:600; }
  .song-credits { color:#9ca3af; font-size:.8rem; white-space:nowrap; overflow:hidden; }.song-credits :global(.artist-credits) { display:flex; }.song-credits :global(.credit-link:hover) { color:#fff; text-decoration:none; }
  .extra-col { display:flex; align-items:center; gap:.5rem; flex:none; }.song-duration { color:#9ca3af; font: .82rem "Cascadia Code",Consolas,monospace; }.tag-video,.tag-playing,.tag-explicit { display:inline-flex; align-items:center; justify-content:center; font-size:.62rem; font-weight:700; padding:.15rem .4rem; border-radius:4px; background:#3f3f46; color:#e4e4e7; }.tag-playing { background:#6366f133; color:#a5b4fc; }.tag-explicit { min-width:.75rem; padding:.08rem .25rem; color:#d4d4d8; background:#52525b; }
  .card-grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(150px,1fr)); gap:.85rem; }.browse-card { min-width:0; border:1px solid #32323a; border-radius:11px; padding:.7rem; background:#24242a; color:inherit; text-align:left; display:flex; flex-direction:column; gap:.35rem; cursor:pointer; }.browse-card:hover { background:#2b2b33; border-color:#a33d45; }
  .cover { aspect-ratio:1; width:100%; overflow:hidden; display:grid; place-items:center; border-radius:8px; background:#1b1b1e; color:#777; font-size:2rem; }.cover.round { border-radius:50%; }.cover img { width:100%; height:100%; object-fit:cover; }.browse-card strong,.browse-card small { overflow:hidden; white-space:nowrap; text-overflow:ellipsis; }.browse-card strong { color:#fff; font-size:.9rem; }.browse-card small { color:#9ca3af; font-size:.78rem; }
  .partial-error { margin:.5rem 0; padding:.7rem .9rem; border:1px solid #85464a; border-radius:8px; color:#f0b8bb; background:#552a302e; }
  @media (min-width:1100px) { .top-layout { grid-template-columns:minmax(280px, .85fr) minmax(320px, 1.15fr); } }
  @media (max-width:760px) { .top-layout { grid-template-columns:1fr; }.known-songs { border-left:0; border-top:1px solid #3a3a44; padding:1rem 0 0; }.hero-play { grid-column:auto; } }
  @media (max-width:560px) { .search-form { flex-direction:column; }.card-grid { grid-template-columns:repeat(2,minmax(0,1fr)); }.hero-art { width:84px; height:84px; } }
</style>
