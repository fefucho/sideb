<script lang="ts">
  import type { AlbumCardDto, BrowseCardDto, SongDto } from '$lib/types';
  import type { SearchData, SearchMode } from '$lib/search/controller';
  import type { SearchPreviewData } from '$lib/search/preview';
  import { createMenuHandlers } from '$lib/menu/hooks';
  import TrackTable from '$lib/components/detail/TrackTable.svelte';
  import ArtistCredits from '$lib/components/ArtistCredits.svelte';
  import QuickResults from './QuickResults.svelte';
  import SearchSongRow from './SearchSongRow.svelte';
  import SearchResultCard from './SearchResultCard.svelte';

  interface Props {
    data: SearchData;
    backendReady: boolean;
    currentTrackId: string | null;
    isPlaying: boolean;
    draftQuery: string;
    preview: SearchPreviewData;
    onSubmit: (query: string, mode: SearchMode) => void;
    onRetry: (query: string, mode: SearchMode) => void;
    onModeChange: (mode: SearchMode) => void;
    onPlaySong: (song: SongDto) => void;
    onOpenAlbum: (album: AlbumCardDto) => void;
    onOpenArtist?: (id: string) => void;
    onOpenPlaylist?: (id: string) => void;
    onDraftChange: (query: string) => void;
    onPreviewFocus: () => void;
    onPreviewDismiss: () => void;
  }

  let {
    data, backendReady, currentTrackId, isPlaying, draftQuery, preview,
    onSubmit, onRetry, onModeChange, onPlaySong, onOpenAlbum, onOpenArtist,
    onOpenPlaylist, onDraftChange, onPreviewFocus, onPreviewDismiss,
  }: Props = $props();

  const createMenu = createMenuHandlers();
  const modes: { id: SearchMode; label: string }[] = [
    { id: 'all', label: 'Todo' }, { id: 'songs', label: 'Canciones' }, { id: 'videos', label: 'Videos' },
    { id: 'albums', label: 'Álbumes' }, { id: 'artists', label: 'Artistas' }, { id: 'playlists', label: 'Playlists' },
  ];
  let searchInput: HTMLInputElement;
  let searchForm: HTMLFormElement;
  let searchFocused = $state(false);
  const hasDraft = $derived(draftQuery.trim().length > 0);
  const showPreview = $derived(searchFocused && hasDraft);

  function submit(event: SubmitEvent) {
    event.preventDefault();
    const query = draftQuery.trim();
    if (!backendReady || !query) return;
    onPreviewDismiss();
    searchFocused = false;
    searchInput.blur();
    onSubmit(query, data.mode);
  }

  function focusSearch() {
    searchFocused = true;
    onPreviewFocus();
  }

  function dismissSearch() {
    searchFocused = false;
    onPreviewDismiss();
  }

  function onSearchFocusout(event: FocusEvent) {
    const next = event.relatedTarget;
    if (next instanceof Node && searchForm?.contains(next)) return;
    dismissSearch();
  }

  function onWindowKeydown(event: KeyboardEvent) {
    if (searchFocused && !event.defaultPrevented && event.key === 'Escape') {
      event.preventDefault();
      dismissSearch();
      searchInput.blur();
    }
  }

  function onWindowMouseDown(event: MouseEvent) {
    if (event.target instanceof Element && event.target.closest('.preview-popover')) event.preventDefault();
  }

  function asSong(card: BrowseCardDto): SongDto {
    return {
      videoId: card.id, title: card.title, artists: card.artists ?? '', artistRuns: card.artistRuns ?? [],
      album: card.album ?? null, albumId: card.albumId ?? null, artistId: card.artistId ?? null,
      duration: card.duration, thumbnail: card.thumbnail, isVideo: card.isVideo ?? card.kind === 'video',
    };
  }

  function target(card: BrowseCardDto) {
    if (card.kind === 'artist') return { kind: 'artist' as const, card };
    if (card.kind === 'playlist') return { kind: 'playlist' as const, card };
    if (card.kind === 'album') return { kind: 'album' as const, card };
    return { kind: 'song' as const, song: asSong(card) };
  }

  function openCard(card: BrowseCardDto) {
    if (card.kind === 'artist') onOpenArtist?.(card.id);
    else if (card.kind === 'album') onOpenAlbum({ id: card.id, title: card.title, subtitle: card.subtitle, thumbnail: card.thumbnail });
    else if (card.kind === 'playlist') onOpenPlaylist?.(card.id);
    else onPlaySong(asSong(card));
  }

  function openAlbumForSong(song: SongDto, id: string) {
    onOpenAlbum({ id, title: song.album ?? '', subtitle: song.artists, thumbnail: song.thumbnail });
  }

  function playFromPreview(song: SongDto) {
    dismissSearch();
    searchInput.blur();
    onPlaySong(song);
  }

  function selectFromPreview(card: BrowseCardDto) {
    dismissSearch();
    searchInput.blur();
    openCard(card);
  }

  function retry(mode = data.mode) {
    const query = data.lastSearchedQuery || data.query.trim();
    if (query) onRetry(query, mode);
  }

  function filteredCards(): BrowseCardDto[] {
    if (data.mode === 'albums') return data.albums.map((album) => ({
      kind: 'album', id: album.id, title: album.title, subtitle: album.subtitle,
      thumbnail: album.thumbnail, duration: null,
    }));
    if (data.mode === 'artists') return data.artists;
    return data.playlists;
  }

  function filteredSongs(): SongDto[] {
    return data.mode === 'videos' ? data.videos : data.songs;
  }

  function partialError(mode: SearchMode): string | undefined {
    if (mode === 'all') return data.partialErrors.global || data.partialErrors.songs || data.partialErrors.videos || data.partialErrors.categories;
    if (mode === 'songs') return data.partialErrors.songs;
    if (mode === 'videos') return data.partialErrors.videos;
    return data.partialErrors.categories;
  }
</script>

<svelte:window onkeydown={onWindowKeydown} onmousedown={onWindowMouseDown} />

<div class="search-page">
  <header class="search-header">
    <div class="search-header-inner">
      <form bind:this={searchForm} class="search-form" role="search" onsubmit={submit}>
        <div class="search-field" role="group" aria-label="Campo de búsqueda" onfocusout={onSearchFocusout}>
          <svg class="search-icon" viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="11" cy="11" r="7.5"></circle><path d="m16.5 16.5 4 4"></path></svg>
          <input
            bind:this={searchInput}
            type="search"
            aria-label="Buscar en YouTube Music"
            placeholder="Buscar en YouTube Music…"
            value={draftQuery}
            disabled={!backendReady}
            oninput={(event) => onDraftChange(event.currentTarget.value)}
            onfocus={focusSearch}
          />
          {#if preview.isLoading}<span class="input-spinner" aria-label="Buscando vista previa"></span>{:else if draftQuery}<button class="clear-button" type="button" aria-label="Limpiar búsqueda" onclick={() => { onDraftChange(''); focusSearch(); searchInput.focus(); }}><svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="7.25"></circle><path d="m7.5 7.5 5 5m0-5-5 5"></path></svg></button>{/if}
          {#if showPreview}
            <div class="preview-popover" role="region" aria-label="Resultados rápidos">
              <div class="preview-content"><QuickResults preview={preview} variant="dropdown" onSelectCard={selectFromPreview} onPlaySong={playFromPreview} /></div>
              <div class="preview-footer"><span>Presiona Enter para ver todos los resultados</span><svg viewBox="0 0 18 18" aria-hidden="true"><path d="M4 4v6h9m-3-3 3 3-3 3"/></svg></div>
            </div>
          {/if}
        </div>
      </form>

      <nav class="mode-tabs" aria-label="Filtros de búsqueda">
        {#each modes as mode (mode.id)}
          <button type="button" class="mode-tab" class:active={data.mode === mode.id} disabled={!backendReady} aria-current={data.mode === mode.id ? 'page' : undefined} onclick={() => onModeChange(mode.id)}><span class="mode-icon" aria-hidden="true">{#if mode.id === 'all'}<svg viewBox="0 0 16 16"><path d="M3 3h4v4H3zM9 3h4v4H9zM3 9h4v4H3zM9 9h4v4H9z"/></svg>{:else if mode.id === 'songs'}<svg viewBox="0 0 16 16"><path d="M9 12V3l5-1v9M9 12a2 2 0 1 1-2-2 2 2 0 0 1 2 2Zm5-1a2 2 0 1 1-2-2 2 2 0 0 1 2 2Z"/></svg>{:else if mode.id === 'videos'}<svg viewBox="0 0 16 16"><rect x="2" y="3" width="12" height="10" rx="2"/><path d="m7 6 4 2-4 2z"/></svg>{:else if mode.id === 'albums'}<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6"/><circle cx="8" cy="8" r="2"/></svg>{:else if mode.id === 'artists'}<svg viewBox="0 0 16 16"><circle cx="8" cy="5" r="2.5"/><path d="M2.5 14a5.5 5.5 0 0 1 11 0"/></svg>{:else}<svg viewBox="0 0 16 16"><path d="M2.5 3.5h11v9h-11zM5 6h6M5 9h4"/></svg>{/if}</span>{mode.label}</button>
        {/each}
      </nav>
    </div>
  </header>

  <div class="results-scroll" aria-live="polite" aria-busy={data.isLoading}>
    {#if data.isLoading}
      <div class="state loading-state"><span class="spinner" aria-hidden="true"></span><strong>Buscando…</strong></div>
    {:else if data.error && !Object.keys(data.partialErrors).length}
      <div class="state error-state" role="alert"><strong>No se pudo completar la búsqueda</strong><span>{data.error}</span><button type="button" class="retry-button" onclick={() => retry()}>Reintentar</button></div>
    {:else if !data.hasSearched}
      <div class="state empty-state"><svg class="empty-icon" viewBox="0 0 40 40" aria-hidden="true"><circle cx="17" cy="17" r="10"/><path d="m24 24 9 9"/></svg><strong>Busca música</strong><span>Encuentra canciones, artistas, álbumes, videos y playlists.</span></div>
    {:else if data.mode === 'all'}
      {#if data.partialErrors.global}<div class="partial-error" role="status">No se pudieron cargar los resultados principales. <button type="button" onclick={() => retry('all')}>Reintentar</button></div>{/if}

      {#if data.top.length}
        {@const hero = data.top[0]}
        {@const heroMenu = createMenu(() => target(hero), { view: 'search_results' })}
        <section class="result-section" aria-label="Resultado principal">
          <h2 class="hero-heading">Mejor resultado</h2>
          <div class="hero-section" class:has-related={hero.kind === 'artist' && data.top.slice(1).some((card) => card.kind === 'song')}>
            <article class="hero-card" oncontextmenu={heroMenu.onContextMenu}>
              <button class="hero-art" class:artist={hero.kind === 'artist'} type="button" aria-label={`${hero.kind === 'artist' ? 'Abrir' : 'Ver'} ${hero.title}`} onclick={() => openCard(hero)} onkeydown={heroMenu.onKeyDown}>
                {#if hero.thumbnail}<img src={hero.thumbnail} alt="" loading="lazy" />{:else if hero.kind === 'artist'}<svg class="hero-person-icon" viewBox="0 0 36 36" aria-hidden="true"><circle cx="18" cy="12" r="6"/><path d="M6 33c.7-7.5 5-11.5 12-11.5S29.3 25.5 30 33"/></svg>{:else}<span aria-hidden="true">♫</span>{/if}
              </button>
              <div class="hero-copy">
                <span class="eyebrow">{hero.kind === 'artist' ? 'ARTISTA' : hero.kind === 'album' ? 'ÁLBUM' : hero.kind === 'playlist' ? 'PLAYLIST' : 'CANCIÓN'}</span>
                <button class="hero-title" type="button" onclick={() => openCard(hero)} onkeydown={heroMenu.onKeyDown}>{hero.title}</button>
                {#if hero.subtitle}<span class="hero-subtitle">{hero.subtitle}</span>{/if}
                {#if hero.kind === 'artist'}<span class="hero-helper">Ver discografía completa</span>{/if}
                <div class="badges">{#if hero.explicit}<span class="tag explicit" aria-label="Contenido explícito">E</span>{/if}{#if hero.isVideo}<span class="tag">VIDEO</span>{/if}</div>
              </div>
              {#if hero.kind === 'artist'}<button class="hero-action" type="button" aria-label={`Abrir perfil de ${hero.title}`} disabled={!onOpenArtist} onclick={() => onOpenArtist?.(hero.id)}><svg viewBox="0 0 36 36" aria-hidden="true"><circle cx="18" cy="18" r="17"/><path d="M10 18h16m-7-7 7 7-7 7"/></svg></button>
              {:else if hero.kind === 'song'}<button class="hero-action" type="button" aria-label={`Reproducir ${hero.title}`} onclick={() => onPlaySong(asSong(hero))}><svg class="play-icon" viewBox="0 0 20 20" aria-hidden="true"><path d="m7 4 9 6-9 6z"/></svg></button>{/if}
            </article>

            {#if hero.kind === 'artist'}
              {@const relatedSongs = data.top.slice(1).filter((card) => card.kind === 'song').slice(0, 3)}
              {#if relatedSongs.length}<div class="hero-related"><h3>Canciones destacadas</h3><div class="song-list">{#each relatedSongs as card (card.id)}<SearchSongRow song={asSong(card)} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={(id) => openAlbumForSong(asSong(card), id)} />{/each}</div></div>{/if}
            {/if}
          </div>
        </section>
      {/if}

      {#if data.songs.length}<section class="result-section"><div class="section-heading"><h2>Canciones</h2><button type="button" onclick={() => onModeChange('songs')}>Ver todas</button></div><div class="song-list">{#each data.songs.slice(0, 5) as song (`${song.videoId}-${song.setVideoId ?? ''}`)}<SearchSongRow {song} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={(id) => openAlbumForSong(song, id)} />{/each}</div></section>{/if}

      {#if data.albums.length}<section class="result-section"><div class="section-heading"><h2>Álbumes</h2><button type="button" onclick={() => onModeChange('albums')}>Ver todos</button></div><div class="card-shelf">{#each data.albums.slice(0, 12) as album (album.id)}{@const card: BrowseCardDto = { kind: 'album', id: album.id, title: album.title, subtitle: album.subtitle, thumbnail: album.thumbnail, duration: null }}<SearchResultCard {card} size="album" onActivate={() => openCard(card)} />{/each}</div></section>{/if}

      {#if data.artists.length}<section class="result-section"><div class="section-heading"><h2>Artistas</h2><button type="button" onclick={() => onModeChange('artists')}>Ver todos</button></div><div class="card-shelf">{#each data.artists.slice(0, 12) as card (card.id)}<SearchResultCard {card} size="artist" onActivate={() => openCard(card)} />{/each}</div></section>{/if}

      {#if data.videos.length}<section class="result-section"><div class="section-heading"><h2>Videos</h2><button type="button" onclick={() => onModeChange('videos')}>Ver todos</button></div><div class="song-list">{#each data.videos.slice(0, 4) as song (`${song.videoId}-${song.setVideoId ?? ''}`)}<SearchSongRow {song} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={(id) => openAlbumForSong(song, id)} showVideo />{/each}</div></section>{/if}

      {#if data.playlists.length}<section class="result-section"><div class="section-heading"><h2>Playlists</h2><button type="button" onclick={() => onModeChange('playlists')}>Ver todas</button></div><div class="card-shelf">{#each data.playlists.slice(0, 12) as card (card.id)}<SearchResultCard {card} size="playlist" onActivate={() => openCard(card)} />{/each}</div></section>{/if}

      {#if data.partialErrors.songs || data.partialErrors.videos || data.partialErrors.categories}<div class="partial-error" role="status">Algunas secciones no se pudieron cargar. <button type="button" onclick={() => retry('all')}>Reintentar</button></div>{/if}
      {#if !data.top.length && !data.songs.length && !data.albums.length && !data.artists.length && !data.videos.length && !data.playlists.length}
        {#if Object.keys(data.partialErrors).length}<div class="state error-state"><strong>Algunas secciones no están disponibles</strong><button type="button" class="retry-button" onclick={() => retry('all')}>Reintentar</button></div>
        {:else}<div class="state empty-state"><strong>Sin resultados</strong><span>No se encontraron resultados para «{data.lastSearchedQuery}».</span></div>{/if}
      {/if}
    {:else if data.mode === 'songs' || data.mode === 'videos'}
      {@const songs = filteredSongs()}
      {#if partialError(data.mode)}<div class="partial-error" role="status">No se pudo cargar esta sección. <button type="button" onclick={() => retry(data.mode)}>Reintentar</button></div>{/if}
      {#if songs.length}
        {#if data.mode === 'songs'}
          <TrackTable items={songs} {currentTrackId} {isPlaying} onPlay={(index) => onPlaySong(songs[index])} {onOpenArtist} onOpenAlbum={(id) => { const song = songs.find((item) => item.albumId === id); if (song) openAlbumForSong(song, id); }} origin={{ view: 'search_results' }} />
        {:else}<div class="song-list filtered-videos">{#each songs as song (`${song.videoId}-${song.setVideoId ?? ''}`)}<SearchSongRow {song} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={(id) => openAlbumForSong(song, id)} showVideo />{/each}</div>{/if}
      {:else}<div class="state empty-state"><strong>{partialError(data.mode) ? 'Sección no disponible' : 'Sin resultados'}</strong>{#if !partialError(data.mode)}<span>No se encontraron {data.mode === 'videos' ? 'videos' : 'canciones'} para «{data.lastSearchedQuery}».</span>{/if}</div>{/if}
    {:else}
      {@const cards = filteredCards()}
      {#if partialError(data.mode)}<div class="partial-error" role="status">No se pudo cargar esta sección. <button type="button" onclick={() => retry(data.mode)}>Reintentar</button></div>{/if}
      {#if cards.length}<div class="filtered-grid" class:artist-grid={data.mode === 'artists'}>{#each cards as card (card.id)}<SearchResultCard {card} size={card.kind === 'artist' ? 'artist' : data.mode === 'playlists' ? 'playlist' : 'album'} filtered onActivate={() => openCard(card)} />{/each}</div>
      {:else}<div class="state empty-state"><strong>{partialError(data.mode) ? 'Sección no disponible' : 'Sin resultados'}</strong>{#if !partialError(data.mode)}<span>No se encontraron resultados para «{data.lastSearchedQuery}».</span>{/if}</div>{/if}
    {/if}
  </div>
</div>

<style>
  .search-page { --search-bg: var(--sideb-background, #1b1b1e); --search-surface: var(--sideb-sidebar, #24242a); display:flex; width:100%; min-height:0; height:100%; flex:1; flex-direction:column; margin:0; color:#f2f2f4; }
  .search-header { position:sticky; z-index:30; top:0; flex:none; padding:18px 24px 12px; border-bottom:1px solid rgb(255 255 255 / 7%); background:rgb(27 27 30 / 88%); backdrop-filter:blur(18px) saturate(1.2); }
  .search-header-inner { display:flex; flex-direction:column; align-items:center; gap:12px; }
  .search-form { position:relative; z-index:31; width:min(100%, 520px); margin:0; }
  .search-field { position:relative; display:flex; width:100%; align-items:center; }
  .search-field input { box-sizing:border-box; width:100%; height:38px; padding:8px 40px; border:1px solid rgb(255 255 255 / 9%); border-radius:999px; outline:none; background:rgb(255 255 255 / 7%); color:#fff; font:inherit; font-size:14px; line-height:20px; }
  .search-field input::-webkit-search-cancel-button { display:none; }
  .search-field input:focus { border-color:rgb(255 255 255 / 24%); background:rgb(255 255 255 / 9%); }
  .search-field input::placeholder { color:rgb(255 255 255 / 48%); }
  .search-icon { position:absolute; left:14px; color:rgb(255 255 255 / 70%); pointer-events:none; }
  .clear-button { position:absolute; right:10px; display:grid; width:24px; height:24px; place-items:center; padding:0; border:0; border-radius:50%; background:transparent; color:rgb(255 255 255 / 60%); cursor:pointer; }
  .clear-button svg { width:16px; height:16px; fill:none; stroke:currentColor; stroke-width:1.5; }
  .input-spinner { position:absolute; right:14px; width:14px; height:14px; border:1.5px solid rgb(255 255 255 / 20%); border-top-color:rgb(255 255 255 / 76%); border-radius:50%; animation:spin .75s linear infinite; }
  .clear-button:hover { color:#fff; background:rgb(255 255 255 / 9%); }
  .preview-popover { position:absolute; z-index:40; top:42px; left:50%; box-sizing:border-box; display:flex; width:min(520px, calc(100vw - 48px)); max-height:min(340px, calc(100vh - 150px)); flex-direction:column; transform:translateX(-50%); padding:8px; border:1px solid rgb(255 255 255 / 10%); border-radius:14px; background:rgb(39 39 44 / 97%); box-shadow:0 16px 48px rgb(0 0 0 / 48%); }
  .preview-content { box-sizing:border-box; width:100%; min-height:0; flex:1; overflow-y:auto; }
  .preview-footer { box-sizing:border-box; display:flex; width:100%; flex:none; align-items:center; gap:8px; padding:8px 10px 2px; border-top:1px solid rgb(255 255 255 / 8%); color:rgb(255 255 255 / 48%); font-size:11.5px; }
  .preview-footer svg { width:14px; height:14px; margin-left:auto; fill:none; stroke:currentColor; stroke-width:1.5; stroke-linecap:round; stroke-linejoin:round; }
  .mode-tabs { display:flex; width:100%; flex:none; flex-wrap:nowrap; justify-content:flex-start; gap:8px; overflow-x:auto; scrollbar-width:none; }
  .mode-tabs::-webkit-scrollbar { display:none; }
  .mode-tab { display:inline-flex; flex:none; align-items:center; gap:6px; padding:5px 12px; border:1px solid transparent; border-radius:999px; background:rgb(255 255 255 / 7%); color:rgb(255 255 255 / 67%); font-size:12.5px; font-weight:550; white-space:nowrap; cursor:pointer; }
  .mode-icon { display:inline-flex; width:13px; height:13px; align-items:center; justify-content:center; }
  .mode-icon svg { width:13px; height:13px; fill:none; stroke:currentColor; stroke-width:1.4; stroke-linecap:round; stroke-linejoin:round; }
  .mode-tab:hover:not(:disabled) { background:rgb(255 255 255 / 7%); color:#fff; }
  .mode-tab.active { background:var(--sideb-accent, #a33d45); color:#fff; }
  .mode-tab:disabled { opacity:.45; cursor:not-allowed; }
  .results-scroll { min-height:0; flex:1; overflow:auto; padding:20px 24px 120px; scrollbar-color:rgb(255 255 255 / 20%) transparent; }
  .result-section { margin:0 0 24px; }
  .section-heading { display:flex; min-height:26px; align-items:center; justify-content:space-between; margin:0 0 10px; }
  .section-heading h2 { margin:0; color:#f2f2f4; font-size:16px; font-weight:650; }
  .section-heading button { padding:4px 8px; border:0; border-radius:6px; background:transparent; color:rgb(255 255 255 / 66%); font:inherit; font-size:12px; font-weight:500; cursor:pointer; }
  .section-heading button:hover { background:rgb(255 255 255 / 8%); color:#fff; }
  .hero-section { display:grid; grid-template-columns:minmax(0, 1fr); align-items:center; gap:12px 16px; padding:16px; border:1px solid rgb(255 255 255 / 8%); border-radius:14px; background:rgb(255 255 255 / 4%); }
  .hero-section.has-related { grid-template-columns:minmax(0, 1fr) minmax(0, 1.05fr); }
  .hero-heading { margin:0 0 10px; color:#f2f2f4; font-size:16px; font-weight:650; }
  .hero-card { display:flex; min-width:0; align-items:center; gap:16px; }
  .hero-art { display:grid; width:80px; height:80px; flex:none; place-items:center; overflow:hidden; padding:0; border:0; border-radius:12px; background:rgb(255 255 255 / 7%); color:rgb(255 255 255 / 55%); font-size:28px; cursor:pointer; }
  .hero-art.artist { border-radius:50%; }
  .hero-art img { width:100%; height:100%; object-fit:cover; }
  .hero-person-icon { width:36px; height:36px; fill:none; stroke:currentColor; stroke-width:1.5; stroke-linecap:round; }
  .hero-copy { display:flex; min-width:0; flex:1; flex-direction:column; align-items:flex-start; gap:4px; }
  .eyebrow { color:rgb(255 255 255 / 52%); font-size:10px; font-weight:700; letter-spacing:.7px; }
  .hero-title { max-width:100%; overflow:hidden; padding:0; border:0; background:transparent; color:#f7f7f8; font-size:18px; font-weight:650; text-align:left; text-overflow:ellipsis; white-space:nowrap; cursor:pointer; }
  .hero-subtitle { max-width:100%; overflow:hidden; color:rgb(255 255 255 / 64%); font-size:13px; text-overflow:ellipsis; white-space:nowrap; }
  .hero-helper { color:rgb(255 255 255 / 51%); font-size:11.5px; }
  .badges { display:flex; gap:5px; }
  .tag { display:inline-flex; align-items:center; padding:2px 6px; border-radius:4px; background:rgb(255 255 255 / 10%); color:rgb(255 255 255 / 70%); font-size:9px; font-weight:700; }
  .tag.explicit { padding-inline:5px; }
  .hero-action { display:grid; width:36px; height:36px; flex:none; place-items:center; border:0; border-radius:50%; background:rgb(255 255 255 / 12%); color:#fff; cursor:pointer; }
  .hero-action svg { width:36px; height:36px; fill:none; stroke:currentColor; stroke-width:1.5; stroke-linecap:round; stroke-linejoin:round; }
  .hero-action .play-icon { width:17px; height:17px; fill:currentColor; stroke:none; }
  .hero-action:disabled { opacity:.45; cursor:not-allowed; }
  .hero-action:hover { background:rgb(255 255 255 / 22%); }
  .hero-related { min-width:0; }
  .hero-related h3 { margin:0 0 5px 10px; color:rgb(255 255 255 / 67%); font-size:11px; font-weight:600; }
  .song-list { display:flex; min-width:0; flex-direction:column; gap:2px; }
  .card-shelf { display:flex; gap:16px; overflow-x:auto; padding:2px 2px 8px; scrollbar-width:thin; scrollbar-color:rgb(255 255 255 / 20%) transparent; }
  .filtered-grid { display:grid; grid-template-columns:repeat(auto-fill, minmax(150px, 180px)); justify-content:start; gap:24px 20px; }
  .filtered-grid.artist-grid { grid-template-columns:repeat(auto-fill, minmax(130px, 160px)); }
  .state { display:flex; min-height:220px; flex-direction:column; align-items:center; justify-content:center; gap:10px; color:rgb(255 255 255 / 62%); text-align:center; }
  .state strong { color:rgb(255 255 255 / 86%); font-size:15px; font-weight:600; }
  .state span { font-size:12px; }
  .empty-icon { width:40px; height:40px; fill:none; stroke:currentColor; stroke-width:1.6; opacity:.5; }
  .retry-button { padding:7px 12px; border:0; border-radius:7px; background:var(--sideb-accent, #a33d45); color:#fff; cursor:pointer; }
  .spinner { width:26px; height:26px; border:2px solid rgb(255 255 255 / 12%); border-top-color:#d06c70; border-radius:50%; animation:spin .75s linear infinite; }
  @keyframes spin { to { transform:rotate(360deg); } }
  .partial-error { margin:0 0 16px; padding:9px 12px; border:1px solid rgb(211 103 110 / 38%); border-radius:8px; background:rgb(120 45 50 / 16%); color:#e6babc; font-size:12px; }
  .partial-error button { margin-left:5px; padding:0; border:0; background:transparent; color:#fff; cursor:pointer; }
  button:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:2px; }
  @media (max-width:720px) { .hero-section,.hero-section.has-related { grid-template-columns:1fr; }.hero-related { padding-top:8px; border-top:1px solid rgb(255 255 255 / 8%); } }
  @media (max-width:560px) { .search-header { padding-inline:14px; }.results-scroll { padding-inline:14px; }.hero-art { width:64px; height:64px; }.filtered-grid { grid-template-columns:repeat(auto-fill, minmax(130px, 1fr)); gap:20px 14px; } }
</style>
