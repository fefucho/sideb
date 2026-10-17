<script lang="ts">
  import ControlButton from '$lib/components/common/ControlButton.svelte';
  import ControlFilter from '$lib/components/common/ControlFilter.svelte';

  import {t} from '$lib/i18n';
  import {searchProjection} from '$lib/search/projection';
  import {resolveSearchSong,relatedTopSongs} from '$lib/search/songs';
  import VirtualCatalog from '../explore/VirtualCatalog.svelte';
  import VirtualStack from '../common/VirtualStack.svelte';
  import type { AlbumCardDto, BrowseCardDto, SongDto } from '$lib/types';
  import type { SearchData, SearchMode, SearchPartialError } from '$lib/search/controller';
  import type { SearchPreviewData } from '$lib/search/preview';
  import TrackTable from '$lib/components/detail/TrackTable.svelte';
  import QuickResults from './QuickResults.svelte';
  import SearchSongRow from './SearchSongRow.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  import SearchResultCard from './SearchResultCard.svelte';

  interface Props {
    data: SearchData;
    backendReady: boolean;
    currentTrackId: string | null;
    isPlaying: boolean;
    draftQuery: string;
    preview: SearchPreviewData;
    onSearchOriginal?: () => void;
    onSubmit: (query: string, mode: SearchMode) => void;
    onRetry: (query: string, mode: SearchMode) => void;
    onRetrySection?: (block: SearchPartialError)=>void;
    onModeChange: (mode: SearchMode) => void;
    onPlayPreviewSong?: (song: SongDto) => void;
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
    onSearchOriginal, onSubmit, onRetry, onRetrySection, onModeChange, onPlaySong, onPlayPreviewSong, onOpenAlbum, onOpenArtist,
    onOpenPlaylist, onDraftChange, onPreviewFocus, onPreviewDismiss,
  }: Props = $props();

  const all = $derived(searchProjection({...data, albums:data.albums.map(card=>({...card,kind:'album',duration:null}))}));
  const modes: { id: SearchMode; label: string }[] = $derived([
    { id: 'all', label: $t('search.filter.all') }, { id: 'songs', label: $t('search.filter.songs') }, { id: 'artists', label: $t('search.filter.artists') }, { id: 'albums', label: $t('search.filter.albums') }, { id: 'playlists', label: $t('search.filter.playlists') }, { id: 'videos', label: $t('search.filter.videos') },
  ]);
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
    if (!searchFocused || event.defaultPrevented || document.querySelector('[role="menu"]')) return;
    if (showPreview && (event.key==='ArrowDown'||event.key==='ArrowUp')) {
      const rows=[...searchForm.querySelectorAll<HTMLElement>('.preview-content button[data-search-primary]:not(:disabled)')].filter(element=>element.offsetParent!==null);
      const index=rows.indexOf(document.activeElement as HTMLElement);
      const next=event.key==='ArrowDown'?Math.min(index+1,rows.length-1):index<=0?-1:index-1;
      event.preventDefault();if(next<0)searchInput.focus();else rows[next]?.focus();return;
    }
    if (event.key === 'Escape') {
      event.preventDefault();
      dismissSearch();
      searchInput.blur();
    }
  }

  function onWindowMouseDown(event: MouseEvent) {
    if (event.target instanceof Element && event.target.closest('.preview-popover')) event.preventDefault();
  }

  function asSong(card: BrowseCardDto): SongDto | null {
    return resolveSearchSong(card, data.mixedResults ?? {songs:data.songs,topSongs:data.topSongs}, data.videos);
  }

  function openCard(card: BrowseCardDto) {
    if (card.kind === 'artist') onOpenArtist?.(card.id);
    else if (card.kind === 'album') onOpenAlbum({ id: card.id, title: card.title, subtitle: card.subtitle, thumbnail: card.thumbnail });
    else if (card.kind === 'playlist') onOpenPlaylist?.(card.id);
    else { const song=asSong(card); if(song)onPlaySong(song); }
  }

  function openAlbumForSong(song: SongDto, id: string) {
    onOpenAlbum({ id, title: song.album ?? '', subtitle: song.artists, thumbnail: song.thumbnail });
  }

  function playFromPreview(song: SongDto) {
    dismissSearch();
    searchInput.blur();
    (onPlayPreviewSong??onPlaySong)(song);
  }

  function selectFromPreview(card: BrowseCardDto) {
    dismissSearch();
    searchInput.blur();
    openCard(card);
  }

  function retry(mode = data.mode) {
    const query = data.lastSearchedQuery || data.query.trim();
    if(onRetrySection && (mode==='songs'||mode==='videos'||mode==='albums'||mode==='artists'||mode==='playlists'))onRetrySection(mode==='songs'||mode==='videos'?mode:'categories');
    else if (query) onRetry(query, mode);
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
            placeholder={$t('search.placeholder')}
            value={draftQuery}
            disabled={!backendReady}
            oninput={(event) => onDraftChange(event.currentTarget.value)}
            onfocus={focusSearch}
          />
          {#if preview.isLoading}<span class="input-spinner" aria-label="Buscando vista previa"></span>{:else if draftQuery}<button class="clear-button" type="button" aria-label="Limpiar búsqueda" onclick={() => { onDraftChange(''); focusSearch(); searchInput.focus(); }}><svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="7.25"></circle><path d="m7.5 7.5 5 5m0-5-5 5"></path></svg></button>{/if}
          {#if showPreview}
            <div class="preview-popover" role="region" aria-label="Resultados rápidos">
              <div class="preview-content"><QuickResults preview={preview} variant="dropdown" onSelectCard={selectFromPreview} onPlaySong={playFromPreview} onQuery={query=>{dismissSearch();onSubmit(query,data.mode);}} /></div>
              <div class="preview-footer"><span>{$t('search.submit.full_results')}</span><svg viewBox="0 0 18 18" aria-hidden="true"><path d="M4 4v6h9m-3-3 3 3-3 3"/></svg></div>
            </div>
          {/if}
        </div>
      </form>

      <nav class="mode-tabs" aria-label="Filtros de búsqueda">
        {#each modes as mode (mode.id)}
          <ControlFilter selected={data.mode === mode.id} type="button" disabled={!backendReady} onclick={() => onModeChange(mode.id)}><span class="mode-icon" aria-hidden="true">{#if mode.id === 'all'}<svg viewBox="0 0 16 16"><path d="M3 3h4v4H3zM9 3h4v4H9zM3 9h4v4H3zM9 9h4v4H9z"/></svg>{:else if mode.id === 'songs'}<svg viewBox="0 0 16 16"><path d="M9 12V3l5-1v9M9 12a2 2 0 1 1-2-2 2 2 0 0 1 2 2Zm5-1a2 2 0 1 1-2-2 2 2 0 0 1 2 2Z"/></svg>{:else if mode.id === 'videos'}<svg viewBox="0 0 16 16"><rect x="2" y="3" width="12" height="10" rx="2"/><path d="m7 6 4 2-4 2z"/></svg>{:else if mode.id === 'albums'}<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6"/><circle cx="8" cy="8" r="2"/></svg>{:else if mode.id === 'artists'}<svg viewBox="0 0 16 16"><circle cx="8" cy="5" r="2.5"/><path d="M2.5 14a5.5 5.5 0 0 1 11 0"/></svg>{:else}<svg viewBox="0 0 16 16"><path d="M2.5 3.5h11v9h-11zM5 6h6M5 9h4"/></svg>{/if}</span>{mode.label}</ControlFilter>
        {/each}
      </nav>
    </div>
  </header>

  <div class="results-scroll" aria-live="polite" aria-busy={data.isLoading}>
    {#if data.ignoreSpelling}<p class="original-context">{$t('search.correction.original_results')}</p>{/if}
    {#if data.correction}<div class="correction" role="status"><span>{$t(data.correction.applied?'search.correction.showing':'search.correction.suggested',[data.correction.query])}</span>{#if !data.correction.applied}<button type="button" onclick={()=>onSubmit(data.correction!.query,data.mode)}>{$t('search.correction.search')}</button>{/if}{#if data.correction.applied&&onSearchOriginal}<button type="button" onclick={onSearchOriginal}>{$t('search.correction.original')}</button>{/if}</div>{/if}
    {#if data.isLoading && !data.top.length && !data.songs.length && !data.albums.length && !data.artists.length && !data.playlists.length && !data.videos.length}
      <div class="state loading-state"><span class="spinner" aria-hidden="true"></span><strong>{$t('search.loading.catalog')}</strong></div>
    {:else if data.error && !Object.keys(data.partialErrors).length}
      <div class="state error-state" role="alert"><strong>No se pudo completar la búsqueda</strong><span>{data.error}</span><ControlButton type="button"  onclick={() => retry()}>{$t('common.retry')}</ControlButton></div>
    {:else if !data.hasSearched}
      <div class="state empty-state"><svg class="empty-icon" viewBox="0 0 40 40" aria-hidden="true"><circle cx="17" cy="17" r="10"/><path d="m24 24 9 9"/></svg><strong>{$t('search.empty.prompt_title')}</strong><span>{$t('search.empty.prompt_description')}</span></div>
    {:else if data.mode === 'all'}
      {#if data.pendingBlocks?.includes('global')}<section class="hero-placeholder" role="status">{$t('search.loading.catalog')}</section>{/if}
      {#if data.partialErrors.global}<div class="partial-error" role="status">No se pudieron cargar los resultados principales. <ControlButton type="button" onclick={() => onRetrySection ? onRetrySection('global') : retry('all')}>{$t('common.retry')}</ControlButton></div>{/if}

      {#if all.top.length}
        {@const principal = all.top[0]}
        <section class="principal-result" aria-label={$t('search.category.top_result')}>
          {#if ['song','video'].includes(principal.kind)}{@const song=asSong(principal)}{#if song}<SearchSongRow {song} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={id=>openAlbumForSong(song,id)}/>{/if}
          {:else}<MediaCard card={principal} layout="compact" onOpen={()=>openCard(principal)} {onOpenArtist} onOpenAlbum={id=>onOpenAlbum({id,title:principal.album??'',subtitle:principal.artists??null,thumbnail:principal.thumbnail})}/>{/if}
          {#each relatedTopSongs(all) as song (song.videoId)}<SearchSongRow {song} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={id=>openAlbumForSong(song,id)}/>{/each}
        </section>
      {/if}






      {#if all.songs.length}<section class="result-section"><div class="section-heading"><h2>{$t('search.filter.songs')}</h2><ControlButton emphasis="quiet" size="utility"  type="button" onclick={() => onModeChange('songs')}>{$t('search.see_all.feminine')}</ControlButton></div><div class="song-list">{#each all.songs.slice(0, 5) as song (`${song.videoId}-${song.setVideoId ?? ''}`)}<SearchSongRow {song} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={(id) => openAlbumForSong(song, id)} />{/each}</div></section>{/if}
      {#if all.artists.length}<section class="result-section"><div class="section-heading"><h2>{$t('search.filter.artists')}</h2><ControlButton emphasis="quiet" size="utility"  type="button" onclick={() => onModeChange('artists')}>{$t('search.see_all.masculine')}</ControlButton></div><div class="card-shelf">{#each all.artists.slice(0, 12) as card (card.id)}<SearchResultCard {card} size="artist" onActivate={() => openCard(card)} />{/each}</div></section>{/if}
      {#if all.albums.length}<section class="result-section"><div class="section-heading"><h2>{$t('search.filter.albums')}</h2><ControlButton emphasis="quiet" size="utility"  type="button" onclick={() => onModeChange('albums')}>{$t('search.see_all.masculine')}</ControlButton></div><div class="card-shelf">{#each all.albums.slice(0, 12) as album (album.id)}{@const card: BrowseCardDto = { kind: 'album', id: album.id, title: album.title, subtitle: album.subtitle, thumbnail: album.thumbnail, duration: null }}<SearchResultCard {card} size="album" onActivate={() => openCard(card)} />{/each}</div></section>{/if}
      {#if all.playlists.length}<section class="result-section"><div class="section-heading"><h2>{$t('search.filter.playlists')}</h2><ControlButton emphasis="quiet" size="utility"  type="button" onclick={() => onModeChange('playlists')}>{$t('search.see_all.feminine')}</ControlButton></div><div class="card-shelf">{#each all.playlists.slice(0, 12) as card (card.id)}<SearchResultCard {card} size="playlist" onActivate={() => openCard(card)} />{/each}</div></section>{/if}
      {#if all.videos.length}<section class="result-section"><div class="section-heading"><h2>{$t('search.filter.videos')}</h2><ControlButton emphasis="quiet" size="utility"  type="button" onclick={() => onModeChange('videos')}>{$t('search.see_all.masculine')}</ControlButton></div><div class="song-list">{#each all.videos.slice(0, 4) as song (`${song.videoId}-${song.setVideoId ?? ''}`)}<SearchSongRow {song} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={(id) => openAlbumForSong(song, id)} showVideo />{/each}</div></section>{/if}
      {#each (['songs','videos','categories'] as SearchPartialError[]) as block}{#if data.partialErrors[block]}<div class="partial-error" role="status">{data.partialErrors[block]} <ControlButton type="button" onclick={() => onRetrySection ? onRetrySection(block) : retry('all')}>{$t('common.retry')}</ControlButton></div>{/if}{/each}
      {#if !all.top.length && !all.songs.length && !all.albums.length && !all.artists.length && !all.videos.length && !all.playlists.length}
        {#if Object.keys(data.partialErrors).length}<div class="state error-state"><strong>Algunas secciones no están disponibles</strong><ControlButton type="button"  onclick={() => retry('all')}>{$t('common.retry')}</ControlButton></div>
        {:else}<div class="state empty-state"><strong>Sin resultados</strong><span>No se encontraron resultados para «{data.lastSearchedQuery}».</span></div>{/if}
      {/if}
    {:else if data.mode === 'songs' || data.mode === 'videos'}
      {@const songs = filteredSongs()}
      {#if partialError(data.mode)}<div class="partial-error" role="status">No se pudo cargar esta sección. <ControlButton type="button" onclick={() => retry(data.mode)}>{$t('common.retry')}</ControlButton></div>{/if}
      {#if songs.length}
        {#if data.mode === 'songs'}
          <TrackTable items={songs} {currentTrackId} {isPlaying} onPlay={(index) => onPlaySong(songs[index])} {onOpenArtist} onOpenAlbum={(id) => { const song = songs.find((item) => item.albumId === id); if (song) openAlbumForSong(song, id); }} origin={{ view: 'search_results' }} />
        {:else}<VirtualStack items={songs} height={()=>64} key={song=>`${song.videoId}:${song.setVideoId??''}`} scrollSelector=".results-scroll">{#snippet children(song)}<SearchSongRow {song} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={id=>openAlbumForSong(song,id)} showVideo/>{/snippet}</VirtualStack>{/if}
      {:else}<div class="state empty-state"><strong>{partialError(data.mode) ? 'Sección no disponible' : 'Sin resultados'}</strong>{#if !partialError(data.mode)}<span>No se encontraron {data.mode === 'videos' ? 'videos' : 'canciones'} para «{data.lastSearchedQuery}».</span>{/if}</div>{/if}
    {:else}
      {@const cards = filteredCards()}
      {#if partialError(data.mode)}<div class="partial-error" role="status">No se pudo cargar esta sección. <ControlButton type="button" onclick={() => retry(data.mode)}>{$t('common.retry')}</ControlButton></div>{/if}
      {#if cards.length}<VirtualCatalog items={cards} scrollSelector=".results-scroll">{#snippet children(card)}<SearchResultCard {card} size={card.kind==='artist'?'artist':data.mode==='playlists'?'playlist':'album'} filtered onActivate={()=>openCard(card)}/>{/snippet}</VirtualCatalog>
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
  .mode-tabs { display:flex; width:100%; flex:none; flex-wrap:nowrap; justify-content:flex-start; gap:var(--control-category-gap); overflow-x:auto; padding:4px 3px; scrollbar-width:none; }
  .mode-tabs::-webkit-scrollbar { display:none; }

  .mode-icon { display:inline-flex; width:18px; height:18px; align-items:center; justify-content:center; }
  .mode-icon svg { width:18px; height:18px; fill:none; stroke:currentColor; stroke-width:1.4; stroke-linecap:round; stroke-linejoin:round; }



  .results-scroll { min-height:0; flex:1; overflow:auto; padding:20px 24px 120px; scrollbar-color:rgb(255 255 255 / 20%) transparent; }
  .hero-placeholder {display:grid;place-items:center;min-height:58px;margin-bottom:24px;border-radius:14px;background:rgb(255 255 255 / 4%);color:#aaa;font-size:12px}
  .result-section { margin:0 0 24px; }
  .section-heading { display:flex; min-height:26px; align-items:center; justify-content:space-between; margin:0 0 10px; }
  .section-heading h2 { margin:0; color:#f2f2f4; font-size:16px; font-weight:650; }


  .principal-result {max-width:760px;margin-bottom:24px;}
  .principal-result :global(.compact){box-sizing:border-box;min-height:58px;padding:7px 10px;height:58px;}
  .principal-result :global(.compact h3){font-size:14px;}
  .original-context{margin:0 0 12px;color:#b6b6bf;font-size:12px;}
  .correction{display:flex;flex-wrap:wrap;gap:8px 16px;margin-bottom:16px;color:#b6b6bf;font-size:13px;}
  .correction button{padding:0;border:0;background:transparent;color:#eee;font:inherit;cursor:pointer;}
  .correction button:hover{filter:brightness(1.2);}
  .song-list { display:flex; min-width:0; flex-direction:column; gap:2px; }
  .card-shelf { display:flex; gap:16px; overflow-x:auto; padding:2px 2px 8px; scrollbar-width:thin; scrollbar-color:rgb(255 255 255 / 20%) transparent; }
  .state { display:flex; min-height:220px; flex-direction:column; align-items:center; justify-content:center; gap:10px; color:rgb(255 255 255 / 62%); text-align:center; }
  .state strong { color:rgb(255 255 255 / 86%); font-size:15px; font-weight:600; }
  .state span { font-size:12px; }
  .empty-icon { width:40px; height:40px; fill:none; stroke:currentColor; stroke-width:1.6; opacity:.5; }

  .spinner { width:26px; height:26px; border:2px solid rgb(255 255 255 / 12%); border-top-color:#d06c70; border-radius:50%; animation:spin .75s linear infinite; }
  @keyframes spin { to { transform:rotate(360deg); } }
  .partial-error { margin:0 0 16px; padding:9px 12px; border:1px solid rgb(211 103 110 / 38%); border-radius:8px; background:rgb(120 45 50 / 16%); color:#e6babc; font-size:12px; }

  button:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:2px; }
  @media (max-width:560px) { .search-header { padding-inline:14px; }.results-scroll { padding-inline:14px; } }
</style>
