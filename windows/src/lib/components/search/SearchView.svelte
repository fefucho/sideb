<script lang="ts">
  import ControlButton from '$lib/components/common/ControlButton.svelte';
  import {untrack} from 'svelte';
  import {songFromSearchCard} from '$lib/search/songs';
  import SearchFilterChips from './SearchFilterChips.svelte';
  import HorizontalNavigation from '../common/HorizontalNavigation.svelte';
  import SearchViewport from './SearchViewport.svelte';
  import {projectSearchDocument, estimateSearchEntryHeight, searchEntryCanFocus} from '$lib/search/document';

  import {t} from '$lib/i18n';

  import type { AlbumCardDto, BrowseCardDto, SongDto } from '$lib/types';
  import type { SearchMode, SearchPartialError } from '$lib/search/controller';
  import type {ProviderSearchData as SearchData} from '$lib/search/provider';
  import type {SearchActionDto,SearchSectionDto} from '$lib/types';
  import type { SearchPreviewData } from '$lib/search/preview';
  import QuickResults from './QuickResults.svelte';
  import SearchSongRow from './SearchSongRow.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  import SearchResultCard from './SearchResultCard.svelte';
  import SearchPrincipal from './SearchPrincipal.svelte';

  interface Props {
    data: SearchData;
    active?: boolean;
    contentScrollElement?: HTMLElement | null;
    onSelectParams:(params:string|null)=>void;
    onLoadMore:()=>void;
    onMore:(section:SearchSectionDto)=>void;
    onAction:(action:SearchActionDto,section:SearchSectionDto)=>void;
    onRemoveSuggestion?:(token:string)=>void;
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
    active=true,contentScrollElement=$bindable(),onAction,onSelectParams,onLoadMore,onMore,onRemoveSuggestion,data, backendReady, currentTrackId, isPlaying, draftQuery, preview,
    onSearchOriginal, onSubmit, onRetry, onRetrySection, onModeChange, onPlaySong, onPlayPreviewSong, onOpenAlbum, onOpenArtist,
    onOpenPlaylist, onDraftChange, onPreviewFocus, onPreviewDismiss,
  }: Props = $props();

  // Retained pages keep their rendered snapshot and geometry while hidden.
  let displayData=$state(untrack(()=>data));
  $effect(()=>{if(active)displayData=data;else dismissSearch();});
  let visiblePlayback=$state(untrack(()=>({currentTrackId,isPlaying})));
  $effect(()=>{if(active)visiblePlayback={currentTrackId,isPlaying};});
  const entries=$derived(projectSearchDocument(displayData.page));
  const documentKey=$derived(`${displayData.lastSearchedQuery}:${displayData.params??''}`);
  let expandedSections=$state<Record<string,boolean>>({});
  $effect(()=>{documentKey;expandedSections={};});
  let composing=false;
  let scrollbarGutter=$state(0);
  $effect(()=>{
    if(!active||!contentScrollElement)return;
    const element=contentScrollElement;
    const measure=()=>scrollbarGutter=Math.max(0,element.offsetWidth-element.clientWidth);
    const observer=new ResizeObserver(measure);observer.observe(element);measure();
    return ()=>observer.disconnect();
  });
  let searchInput: HTMLInputElement;
  let searchForm: HTMLFormElement;
  let searchFocused = $state(false);
  const showPreview = $derived(searchFocused);

  function submit(event: SubmitEvent) {
    event.preventDefault();
    if(composing)return;
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
    if (!active || event.isComposing || !searchFocused || event.defaultPrevented || document.querySelector('[role="menu"]')) return;
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
    if (!active||!searchFocused||!(event.target instanceof Node))return;
    // Capture outside clicks without cancelling their navigation or activation.
    if(!searchForm?.contains(event.target))dismissSearch();
  }

  function asSong(card: BrowseCardDto): SongDto | null {
    // Paired occurrences already use their exact song DTO. An unpaired card must
    // never steal another occurrence's setVideoId/library tokens through an ID scan.
    return songFromSearchCard(card);
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

</script>

<svelte:window onkeydown={onWindowKeydown} onpointerdowncapture={onWindowMouseDown} />

<div class="search-page" style:--search-scrollbar-gutter={`${scrollbarGutter}px`}>
  <header class="search-header">
    <div class="search-header-inner">
      <h1>{$t('search.title')}</h1>
      <form bind:this={searchForm} class="search-form" role="search" onsubmit={submit}>
        <div class="search-field" role="group" aria-label={$t('search.title')} onfocusout={onSearchFocusout}>
          <svg class="search-icon" viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="11" cy="11" r="7.5"></circle><path d="m16.5 16.5 4 4"></path></svg>
          <input
            bind:this={searchInput}
            type="search"
            aria-label={$t('search.placeholder')}
            placeholder={$t('search.placeholder')}
            value={draftQuery}
            disabled={!backendReady}
            oncompositionstart={()=>composing=true}
            oncompositionend={()=>composing=false}
            oninput={(event) => onDraftChange(event.currentTarget.value)}
            onfocus={focusSearch}
          />
          {#if preview.isLoading}<span class="input-spinner" aria-label={$t('search.loading.quick')}></span>{:else if draftQuery}<button class="clear-button" type="button" aria-label={$t('detail.search.clear')} onclick={() => { onDraftChange(''); focusSearch(); searchInput.focus(); }}><svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="7.25"></circle><path d="m7.5 7.5 5 5m0-5-5 5"></path></svg></button>{/if}
          {#if showPreview}
            <div class="preview-popover" role="region" aria-label={$t('search.suggestions.title')}>
              <div class="preview-content"><QuickResults {onRemoveSuggestion} preview={preview} variant="dropdown" onSelectCard={selectFromPreview} onPlaySong={playFromPreview} onQuery={query=>{dismissSearch();onSubmit(query,data.mode);}} /></div>
              <div class="preview-footer"><span>{$t('search.submit.full_results')}</span><svg viewBox="0 0 18 18" aria-hidden="true"><path d="M4 4v6h9m-3-3 3 3-3 3"/></svg></div>
            </div>
          {/if}
        </div>
      </form>

      <SearchFilterChips chips={displayData.page?.chips??[]} disabled={!backendReady||displayData.isLoading} {active} onSelect={onSelectParams}/>

    </div>
  </header>

  <div class="results-scroll" bind:this={contentScrollElement} aria-live="polite" aria-busy={displayData.isLoading}>
    {#if displayData.page?.correction}{@const correction=displayData.page.correction}<div class="correction" role="status"><span>{$t(correction.applied?'search.correction.showing':'search.correction.suggested',[correction.query])}</span>{#if correction.applied}<button type="button" onclick={()=>correction.originalParams?onSelectParams(correction.originalParams):onSearchOriginal?.()}>{$t('search.correction.original')}</button>{:else}<button type="button" onclick={()=>correction.params?onSelectParams(correction.params):onSubmit(correction.query,'all')}>{$t('search.correction.search')}</button>{/if}</div>{/if}
    {#if displayData.isLoading}<div class="state" role="status"><span class="spinner"></span>{$t('search.loading.catalog')}</div>{/if}
    {#if displayData.error}<div class="partial-error" role="alert">{displayData.error}<ControlButton type="button" onclick={()=>displayData.page?.continuation?onLoadMore():retry()}>{$t('common.retry')}</ControlButton></div>{/if}
    <SearchViewport items={entries} estimate={estimateSearchEntryHeight} canFocus={searchEntryCanFocus} scrollElement={contentScrollElement} {active} {documentKey} styleKey={$t('search.provider.related')}>
      {#snippet children(entry)}
        {#if entry.kind==='heading'}
          <div class="section-heading">{#if entry.showTitle}<h2>{entry.section.title}</h2>{/if}{#if entry.section.moreParams||entry.section.moreBrowseId||entry.section.moreQuery}<ControlButton type="button" onclick={()=>onMore(entry.section)}>{$t('search.provider.show_all')}</ControlButton>{/if}</div>
        {:else if entry.kind==='principal'&&entry.projection.primary}
          <section class="principal-container"><SearchPrincipal primary={entry.projection.primary} related={entry.projection.related} remaining={[]} section={entry.section} expanded={expandedSections[entry.key]??false} onExpandedChange={value=>expandedSections={...expandedSections,[entry.key]:value}} currentTrackId={visiblePlayback.currentTrackId} isPlaying={visiblePlayback.isPlaying} {onAction} {onPlaySong} {onOpenArtist} {onOpenAlbum} {onOpenPlaylist} {openCard} {openAlbumForSong}/></section>
        {:else if entry.kind==='actions'}
          <div class="search-actions">{#each entry.section.actions as action,index (`${action.title}:${index}`)}<ControlButton type="button" onclick={()=>onAction(action,entry.section)}>{action.title}</ControlButton>{/each}</div>
        {:else if entry.kind==='carousel'}
          <HorizontalNavigation {active} label={entry.section.title || $t('search.title')} revision={documentKey} center="80px">
          <div class="card-shelf" data-horizontal-scroll>{#each entry.rows as row,itemIndex (`${row.itemIndex??'song'}:${row.songIndex??itemIndex}`)}
            {#if row.song}{@const song=row.song}<SearchSongRow {song} currentTrackId={visiblePlayback.currentTrackId} isPlaying={visiblePlayback.isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={id=>openAlbumForSong(song,id)}/>
            {:else if row.card}{@const card=row.card}<SearchResultCard {card} size={card.kind==='artist'?'artist':card.kind==='playlist'?'playlist':'album'} onActivate={()=>openCard(card)}/>{/if}
          {/each}</div>
          </HorizontalNavigation>
        {:else if entry.kind==='row'}{@const row=entry.row}
          {#if row.song}{@const song=row.song}<SearchSongRow {song} currentTrackId={visiblePlayback.currentTrackId} isPlaying={visiblePlayback.isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={id=>openAlbumForSong(song,id)}/>
          {:else if row.card}{@const card=row.card}<MediaCard {card} layout="compact" onOpen={()=>openCard(card)} {onOpenArtist} onOpenAlbum={id=>onOpenAlbum({id,title:card.album??'',subtitle:card.artists??null,thumbnail:card.thumbnail})}/>{/if}
        {/if}
      {/snippet}
    </SearchViewport>
    {#if displayData.page?.continuation}<ControlButton type="button" disabled={displayData.loadingMore} onclick={onLoadMore}>{$t(displayData.loadingMore?'common.loading':'search.provider.load_more')}</ControlButton>{/if}
    {#if !displayData.isLoading&&!displayData.error&&!displayData.page?.sections.length}<div class="state empty-state"><strong>{$t(displayData.hasSearched?'search.empty.query':'search.empty.prompt_title',[displayData.lastSearchedQuery])}</strong></div>{/if}
  </div>
</div>

<style>
  .search-page { --search-bg: var(--sideb-background, #1b1b1e); --search-surface: var(--sideb-sidebar, #24242a); display:flex; width:100%; min-height:0; height:100%; flex:1; flex-direction:column; margin:0; color:#f2f2f4; }
  .search-header { position:sticky; z-index:30; top:0; flex:none; padding:18px calc(28px + var(--search-scrollbar-gutter, 0px)) 12px 28px; border-bottom:1px solid rgb(255 255 255 / 7%); background:rgb(27 27 30 / 88%); backdrop-filter:blur(18px) saturate(1.2); }
  .search-header-inner { min-width:0; display:flex; flex-direction:column; align-items:stretch; gap:12px; }
  .search-header h1{margin:0;font-size:40px;font-weight:700;line-height:1.2;letter-spacing:-1px;}
  .search-form { position:relative; z-index:31; width:100%; margin:0; }
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
  .preview-popover { position:absolute; z-index:40; top:42px; left:50%; box-sizing:border-box; display:flex; width:100%; max-height:min(340px, calc(100vh - 150px)); flex-direction:column; transform:translateX(-50%); padding:8px; border:1px solid rgb(255 255 255 / 10%); border-radius:14px; background:rgb(39 39 44 / 97%); box-shadow:0 16px 48px rgb(0 0 0 / 48%); }
  .preview-content { box-sizing:border-box; width:100%; min-height:0; flex:1; overflow-y:auto; }
  .preview-footer { box-sizing:border-box; display:flex; width:100%; flex:none; align-items:center; gap:8px; padding:8px 10px 2px; border-top:1px solid rgb(255 255 255 / 8%); color:rgb(255 255 255 / 48%); font-size:11.5px; }
  .preview-footer svg { width:14px; height:14px; margin-left:auto; fill:none; stroke:currentColor; stroke-width:1.5; stroke-linecap:round; stroke-linejoin:round; }
  .results-scroll { min-height:0; flex:1; overflow:auto; overflow-anchor:none; padding:20px 28px 120px; scrollbar-color:rgb(255 255 255 / 20%) transparent; }
  .search-actions{display:flex;align-items:center;flex-wrap:wrap;gap:8px;padding:8px 0;}
  .principal-container { container-type:inline-size; margin:0 0 16px; }
  .section-heading { display:flex; min-height:44px; align-items:center; justify-content:space-between; margin:0; }
  .section-heading h2 { margin:0; color:#f2f2f4; font-size:16px; font-weight:650; }


  .correction{display:flex;flex-wrap:wrap;gap:8px 16px;margin-bottom:16px;color:#b6b6bf;font-size:13px;}
  .correction button{padding:0;border:0;background:transparent;color:#eee;font:inherit;cursor:pointer;}
  .correction button:hover{filter:brightness(1.2);}
  .card-shelf { display:flex; gap:16px; overflow-x:auto; padding:2px 2px 8px; scrollbar-width:thin; scrollbar-color:rgb(255 255 255 / 20%) transparent; }
  .state { display:flex; min-height:220px; flex-direction:column; align-items:center; justify-content:center; gap:10px; color:rgb(255 255 255 / 62%); text-align:center; }
  .state strong { color:rgb(255 255 255 / 86%); font-size:15px; font-weight:600; }
  .state span { font-size:12px; }

  .spinner { width:26px; height:26px; border:2px solid rgb(255 255 255 / 12%); border-top-color:#d06c70; border-radius:50%; animation:spin .75s linear infinite; }
  @keyframes spin { to { transform:rotate(360deg); } }
  .partial-error { margin:0 0 16px; padding:9px 12px; border:1px solid rgb(211 103 110 / 38%); border-radius:8px; background:rgb(120 45 50 / 16%); color:#e6babc; font-size:12px; }

  button:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:2px; }

</style>
