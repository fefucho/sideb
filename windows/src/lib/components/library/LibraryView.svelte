<script lang="ts">
  import ControlButton from '$lib/components/common/ControlButton.svelte';
  import ControlFilter from '$lib/components/common/ControlFilter.svelte';
  import ControlSegments from '$lib/components/common/ControlSegments.svelte';

  import { onMount, tick, untrack } from 'svelte';
  import { t, language, resolveMessage } from '$lib/i18n';
  import type { BrowseCardDto } from '$lib/types';
  import type { AccountSongDto as SongDto } from '$lib/account/types';
  import { libraryDefaults, readLibraryPreferences, writeLibraryPreferences, orderedLibraryCards, libraryMatches, libraryKey, libraryNavigation, type LibraryPreferences, type LibrarySection } from '$lib/library/preferences';
  import VirtualCatalog from '../explore/VirtualCatalog.svelte';
  import VirtualStack from '../common/VirtualStack.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  import AccountTrackTable from './AccountTrackTable.svelte';
  import ContinuationLoader from '../detail/ContinuationLoader.svelte';
  interface Props {
    active?: boolean; accountKey?: string; loggedIn: boolean; tab: LibrarySection; songs: SongDto[];
    playlists: BrowseCardDto[]; albums: BrowseCardDto[]; artists: BrowseCardDto[];
    loading: boolean; loadingMore: boolean; error: string | null; continuation: string | null;
    currentTrackId: string | null; isPlaying: boolean; likedIds: Set<string>; pendingIds: Set<string>;
    onTab: (tab: LibrarySection) => void; onRefresh: () => void; onLoadMore: () => Promise<void> | void;
    onPlay: (index: number, tracks?: SongDto[], usesContinuation?: boolean) => void; onOpenCard: (card: BrowseCardDto) => void;
    onOpenArtist?: (id: string) => void; onOpenAlbum?: (id: string) => void;
    onToggleLike: (track: SongDto) => void; onToggleSaved: (track: SongDto) => void;
    onCreatePlaylist: () => void; onLogin: () => void;
  }
  let { active = true, accountKey = 'guest', loggedIn, tab: liveTab, songs: liveSongs, playlists: livePlaylists, albums: liveAlbums, artists: liveArtists, loading: liveLoading, loadingMore: liveLoadingMore, error: liveError, continuation: liveContinuation,
    currentTrackId: liveTrack, isPlaying: livePlaying, likedIds: liveLikes, pendingIds: livePending, onTab, onRefresh, onLoadMore, onPlay,
    onOpenCard, onOpenArtist, onOpenAlbum, onToggleLike, onToggleSaved, onCreatePlaylist, onLogin }: Props = $props();
  const currentInputs = () => ({tab:liveTab,songs:liveSongs,playlists:livePlaylists,albums:liveAlbums,artists:liveArtists,
    loading:liveLoading,loadingMore:liveLoadingMore,error:liveError,continuation:liveContinuation,
    currentTrackId:liveTrack,isPlaying:livePlaying,likedIds:liveLikes,pendingIds:livePending});
  let rendered = $state(untrack(currentInputs));
  $effect(() => { const next=currentInputs(); if(active)rendered=next; });
  const tab=$derived(rendered.tab),songs=$derived(rendered.songs),playlists=$derived(rendered.playlists),albums=$derived(rendered.albums),artists=$derived(rendered.artists);
  const loading=$derived(rendered.loading),loadingMore=$derived(rendered.loadingMore),error=$derived(rendered.error),continuation=$derived(rendered.continuation);
  const currentTrackId=$derived(rendered.currentTrackId),isPlaying=$derived(rendered.isPlaying),likedIds=$derived(rendered.likedIds),pendingIds=$derived(rendered.pendingIds);
  let root:HTMLElement;
  const pageScroll = () => root?.closest<HTMLElement>('[data-page-scroll], .content-column');
  $effect(() => { if(!active)cancelSearch(); });
  let prefs = $state<LibraryPreferences>(libraryDefaults());
  let query = $state('');
  let searching = $state(false);
  let searchedPages = $state(0);
  let searchGeneration = 0;
  let mounted = $state(false);
  let activeAccount = '';
  const tabs = $derived([
    {id:'all' as const,label:$t('library.tab.all')}, {id:'songs' as const,label:$t('search.filter.songs')},
    {id:'playlists' as const,label:$t('windows.ui.playlists')}, {id:'albums' as const,label:$t('sidebar.albums')}, {id:'artists' as const,label:$t('search.filter.artists')},
  ]);
  const sections = $derived([
    {id:'playlists' as const,label:$t('windows.ui.playlists'),cards:playlists.map(c=>({...c,kind:'playlist'}))},
    {id:'albums' as const,label:$t('sidebar.albums'),cards:albums.map(c=>({...c,kind:'album'}))},
    {id:'artists' as const,label:$t('search.filter.artists'),cards:artists.map(c=>({...c,kind:'artist'}))},
  ]);
  const effectiveOrder = $derived(prefs.order==='artist'&&tab!=='songs'&&tab!=='albums'?'original':prefs.order);
  const cards = $derived(orderedLibraryCards(sections.find(s=>s.id===tab)?.cards ?? [],query,effectiveOrder));
  const allCards = $derived(sections.flatMap(s=>s.cards));
  const pins = $derived(prefs.pins.map(p=>allCards.find(c=>libraryKey(c)===libraryKey(p))??p).filter(c=>libraryMatches(query,c.title,c.subtitle)));
  const visibleSongs = $derived(songs.map((song,index)=>({song,index})).filter(({song})=>libraryMatches(query,song.title,song.artists,song.album))
    .sort((a,b)=>prefs.order==='original'?a.index-b.index:(prefs.order==='artist'?a.song.artists:a.song.title).localeCompare(prefs.order==='artist'?b.song.artists:b.song.title,undefined,{sensitivity:'base',numeric:true})||a.index-b.index));
  function save() { if (activeAccount && activeAccount !== 'guest') writeLibraryPreferences(localStorage,activeAccount,prefs); }
  function selectTab(next:LibrarySection) { cancelSearch(); prefs={...prefs,tab:next}; save(); onTab(next); }
  function togglePin(card:BrowseCardDto) { const key=libraryKey(card); prefs={...prefs,pins:prefs.pins.some(p=>libraryKey(p)===key)?prefs.pins.filter(p=>libraryKey(p)!==key):[...prefs.pins,card].slice(0,50)}; save(); }
  function movePin(card:BrowseCardDto,delta:number) { const list=[...prefs.pins]; const i=list.findIndex(p=>libraryKey(p)===libraryKey(card)); const next=i+delta; if(next<0||next>=list.length)return; [list[i],list[next]]=[list[next],list[i]]; prefs={...prefs,pins:list}; save(); }
  function cancelSearch() { searchGeneration++; searching=false; }
  async function searchRest() {
    if(!active||searching||loading||loadingMore)return;
    const generation=++searchGeneration; searching=true; searchedPages=0;
    for(let page=0;page<8;page++) {
      if(!active||generation!==searchGeneration||!continuation||error)break;
      const token=continuation; await onLoadMore(); await tick();
      if(generation!==searchGeneration||error)break;
      searchedPages++; if(continuation===token)break;
    }
    if(generation===searchGeneration)searching=false;
  }
  $effect(()=>{ query; cancelSearch(); searchedPages=0; });
  $effect(()=>{ if(!mounted)return; const next=loggedIn&&accountKey!=='account:'?accountKey:'guest'; if(next===activeAccount)return;
    cancelSearch(); activeAccount=next; prefs=readLibraryPreferences(localStorage,next); query=libraryNavigation.get(next)?.query??'';
    if(active&&loggedIn&&tab!==prefs.tab)onTab(prefs.tab);
    void tick().then(()=>{ const scroll=pageScroll(); if(scroll)scroll.scrollTop=libraryNavigation.get(next)?.scroll??0; });
  });
  onMount(()=>{
    mounted=true;
    const scroll=pageScroll();
    const remember=()=>{if(active&&activeAccount)libraryNavigation.set(activeAccount,{query,scroll:scroll?.scrollTop??0});};
    scroll?.addEventListener('scroll',remember,{passive:true});
    return()=>{ remember(); cancelSearch(); scroll?.removeEventListener('scroll',remember); };
  });
</script>

<main class="library" bind:this={root} inert={!active} aria-busy={loading}>
  <header class="heading">
    <h1>{$t('sidebar.library')}</h1>

  </header>
  <div class="category-toolbar">
    <nav class="tabs" aria-label={$t('windows.ui.librarySections')}>
    {#each tabs as item (item.id)}<ControlFilter type="button" selected={tab===item.id} onclick={()=>selectTab(item.id)}><svg viewBox="0 0 24 24" aria-hidden="true">{#if item.id==='all'}<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>{:else if item.id==='songs'}<path d="M10 17V5l10-2v12M10 8l10-2"/><ellipse cx="6.5" cy="17.5" rx="3.5" ry="2.5"/><ellipse cx="16.5" cy="15.5" rx="3.5" ry="2.5"/>{:else if item.id==='playlists'}<path d="M4 5h15M4 10h15M4 15h8M17 14v7M13.5 17.5h7"/>{:else if item.id==='albums'}<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2.5"/>{:else if item.id==='artists'}<circle cx="12" cy="7.5" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>{/if}</svg>{item.label}</ControlFilter>{/each}
  </nav>
    {#if loggedIn}<div class="heading-actions">
      <ControlButton type="button" onclick={onCreatePlaylist}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>{$t('detail.playlistEditor.createTitle')}</ControlButton>
      <ControlButton iconOnly type="button" aria-label={$t('library.refresh')} onclick={onRefresh}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 7v5h-5M20 12a8 8 0 1 0-2.3 5.7M20 7l-2.3-2.7"/></svg></ControlButton>
    </div>{/if}
  </div>
  {#if loggedIn}
    <div class="toolbar">
      <div class="search glass"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/></svg>
        <input type="search" bind:value={query} placeholder={$t('library.search.placeholder')} aria-label={$t('library.search.placeholder')} />
        {#if query}<button class="clear" type="button" aria-label={$t('detail.search.clear')} onclick={()=>query=''}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 7 10 10M17 7 7 17"/></svg></button>{/if}
      </div>
      <div class="view-tools"><div class="sort glass"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16M4 12h11M4 18h6"/></svg>
        <select value={effectiveOrder} aria-label={$t('library.sort.label')} onchange={event=>{prefs={...prefs,order:event.currentTarget.value as LibraryPreferences['order']};save();}}>
          <option value="original">{$t('library.sort.original')}</option><option value="name">{$t('library.sort.name')}</option>{#if tab==='songs'||tab==='albums'}<option value="artist">{$t('library.sort.artist')}</option>{/if}
        </select></div>
        {#if tab!=='songs'}<ControlSegments id="library-layout" label={$t('library.view.grid') + ' / ' + $t('library.view.list')}
          options={[{id:'grid',label:$t('library.view.grid')},{id:'list',label:$t('library.view.list')}]}
          value={prefs.layout} onChange={layout=>{prefs={...prefs,layout};save();}} iconOnly>
          {#snippet icon(layout)}<svg viewBox="0 0 24 24" aria-hidden="true">{#if layout==='grid'}<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>{:else}<path d="M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01"/>{/if}</svg>{/snippet}
        </ControlSegments>{/if}
      </div>
    </div>
    {#if tab==='songs'&&query.trim()}
      <div class="coverage" role="status"><span>{$t(continuation?'library.search.loaded':'library.search.complete',[String(songs.length)])} {searchedPages? $t('library.search.progress',[String(searchedPages)]):''}</span>
        {#if searching}<ControlButton emphasis="quiet" size="utility" onclick={cancelSearch}>{$t('library.search.cancel')}</ControlButton>{:else if continuation}<ControlButton emphasis="quiet" size="utility" disabled={loading} loading={loadingMore} onclick={searchRest}>{$t(searchedPages?'library.search.continue':'library.search.rest')}</ControlButton>{/if}
      </div>
    {:else if query.trim()}<p class="coverage">{$t('library.search.collections')}</p>{/if}
  {/if}
  <div class="divider"></div>
  {#if !loggedIn}
    <section class="state"><h2>{$t('library.login_required')}</h2><ControlButton emphasis="prominent" type="button" onclick={onLogin}>{$t('account.sign_in')}</ControlButton></section>
  {:else if tab==='songs'}
    {#if loading&&songs.length===0}<section class="state" role="status"><span class="spinner"></span><p>{$t('windows.ui.loadingSongs')}</p></section>
    {:else if error&&songs.length===0}<section class="state" role="alert"><h2>{$t('library.error.load_songs')}</h2><p>{resolveMessage(error,$language)}</p><ControlButton emphasis="prominent" type="button" onclick={onRefresh}>{$t('sidebar.retry')}</ControlButton></section>
    {:else if visibleSongs.length===0}<section class="state"><h2>{$t(query||continuation?'library.search.empty':'library.empty.songs')}</h2>{#if continuation}<p>{$t('library.search.pending')}</p>{/if}</section>
    {:else}<AccountTrackTable {active} items={visibleSongs.map(item=>item.song)} {currentTrackId} {isPlaying} onPlay={index=>onPlay(index,visibleSongs.map(item=>item.song),!query.trim()&&prefs.order==='original')} {likedIds} {pendingIds} {onToggleLike} {onToggleSaved} {onOpenArtist} {onOpenAlbum} />{/if}
  {:else if loading&&allCards.length===0}<section class="state" role="status"><span class="spinner"></span><p>{$t('common.loading')}</p></section>
  {:else if tab==='all'}
    {#if pins.length}<section class="collection-section"><h2>{$t('library.pinned')}</h2><div class:listing={prefs.layout==='list'} class="overview-grid">{#each pins as card (libraryKey(card))}{@render collection(card,true)}{/each}</div></section>{/if}
    {#each sections as section (section.id)}{@const matching=orderedLibraryCards(section.cards,query,effectiveOrder)}
      {#if matching.length}<section class="collection-section"><div class="section-title"><h2>{section.label}</h2><ControlButton emphasis="quiet" size="utility"  type="button" onclick={()=>selectTab(section.id)}>{$t('library.see_all')} →</ControlButton></div><div class:listing={prefs.layout==='list'} class="overview-grid">{#each matching.slice(0,6) as card (libraryKey(card))}{@render collection(card)}{/each}</div></section>{/if}
    {/each}
    {#if !allCards.length&&!loading&&!error}<section class="state"><h2>{$t('library.empty.all')}</h2></section>{:else if query&&!pins.length&&!allCards.some(c=>libraryMatches(query,c.title,c.subtitle))}<section class="state"><h2>{$t('library.search.empty')}</h2></section>{/if}
  {:else if error&&cards.length===0&&!query}<section class="state" role="alert"><h2>{$t('library.error.load')}</h2><p>{resolveMessage(error,$language)}</p><ControlButton emphasis="prominent" type="button" onclick={onRefresh}>{$t('sidebar.retry')}</ControlButton></section>
  {:else if cards.length===0}<section class="state"><h2>{$t(query?'library.search.empty':tab==='playlists'?'library.empty.playlists':tab==='artists'?'library.empty.artists':'sidebar.no_saved_albums')}</h2></section>
  {:else}<section class="card-content"><div class="grid">{#if prefs.layout==='grid'}<VirtualCatalog {active} items={cards} rowExtra={132} scrollSelector="[data-page-scroll], .content-column">{#snippet children(card)}{@render collection(card)}{/snippet}</VirtualCatalog>{:else}<VirtualStack {active} items={cards} height={()=>92} key={libraryKey} scrollSelector="[data-page-scroll], .content-column">{#snippet children(card)}{@render collection(card)}{/snippet}</VirtualStack>{/if}</div></section>{/if}
  {#if loggedIn&&error}<div class="inline-error" role="alert">{resolveMessage(error,$language)}<ControlButton onclick={onRefresh}>{$t('sidebar.retry')}</ControlButton></div>{/if}
  {#if loggedIn&&loading&&allCards.length}<div class="updating" role="status">{$t('windows.ui.refreshing')}</div>{/if}
  {#if loggedIn&&tab==='songs'&&!query.trim()}<ContinuationLoader context="library:songs" cursor={continuation} loading={loadingMore} disabled={!active||loading} error={error} {onLoadMore} />{/if}
  <div class="bottom-space" aria-hidden="true"></div>
</main>
{#snippet collection(card:BrowseCardDto,pinned=false)}
  {@const isPinned=prefs.pins.some(p=>libraryKey(p)===libraryKey(card))}
  <div class="collection-item" class:has-pin={isPinned}><MediaCard {card} layout={prefs.layout==='list'?'compact':'vertical'} onOpen={()=>onOpenCard(card)} {onOpenArtist} {onOpenAlbum} />
    <div class="pin-actions"><button type="button" class:pinned={isPinned} aria-label={$t(prefs.pins.some(p=>libraryKey(p)===libraryKey(card))?'library.unpin':'library.pin',[card.title])} onclick={()=>togglePin(card)}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m16 3 5 5-3 1-4 4v4l-2 2-3-5-5-3 2-2h4l4-4zM9 15l-6 6"/></svg></button>
      {#if pinned}<button type="button" disabled={libraryKey(prefs.pins[0])===libraryKey(card)} aria-label={$t('library.pin.up',[card.title])} onclick={()=>movePin(card,-1)}>↑</button><button type="button" disabled={libraryKey(prefs.pins[prefs.pins.length-1])===libraryKey(card)} aria-label={$t('library.pin.down',[card.title])} onclick={()=>movePin(card,1)}>↓</button>{/if}
    </div>
  </div>
{/snippet}
<style>
  .library { position: relative; box-sizing: border-box; min-width: 0; min-height: 100%; color: #f7f7f8; background: var(--sideb-background, #1b1b1e); }
  .heading { display:flex; align-items:center; justify-content:space-between; gap:16px; padding:28px 28px 10px; }
  h1 { min-width:0; margin:0; font-size:38px; font-weight:700; line-height:1.12; overflow-wrap:anywhere; }
  .heading-actions { display:flex; align-items:center; gap:8px; }
  .glass { border:1px solid var(--control-border); border-radius:var(--control-radius); color:var(--control-foreground); background:var(--control-surface); box-shadow:var(--control-shadow); }
  button { font:inherit; cursor:pointer; }
  svg { width:19px; height:19px; flex:none; fill:none; stroke:currentColor; stroke-width:1.7; stroke-linecap:round; stroke-linejoin:round; }


  .tabs { display:flex; align-items:center; gap:10px; overflow-x:auto; padding:4px 32px 12px; scrollbar-width:thin; scroll-padding-inline:32px; }



  .toolbar { display:flex; flex-wrap:wrap; align-items:center; justify-content:space-between; gap:12px; padding:0 32px 12px; }
  .search { display:flex; align-items:center; gap:9px; box-sizing:border-box; width:300px; min-width:180px; max-width:100%; height:40px; padding:0 11px 0 14px; color:#bfc0c8; }
  .search input { width:100%; min-width:0; padding:0; border:0; outline:0; color:#f3f3f6; background:transparent; font:inherit; font-size:13px; }
  .search input::placeholder { color:#b3b3be; opacity:1; } .search input::-webkit-search-cancel-button { display:none; }
  .search:focus-within { outline:2px solid var(--sideb-highlight); outline-offset:3px; }
  .clear { display:grid; place-items:center; width:26px; height:26px; padding:0; flex:none; border:0; border-radius:50%; color:inherit; background:transparent; } .clear:hover { background:var(--sideb-surface-hover); }
  .view-tools { display:flex; flex-wrap:wrap; align-items:center; gap:10px; margin-left:auto; }
  .sort { display:flex; align-items:center; gap:8px; min-height:40px; padding:0 12px; }
  .sort select { min-width:0; max-width:220px; padding:0 2px; border:0; color:inherit; background:transparent; font:inherit; font-size:var(--control-action-font); cursor:pointer; } .sort option { color:#f3f3f6; background:var(--sideb-background); }


  .category-toolbar { display:flex; align-items:center; gap:16px; padding:0 28px; min-width:0; }
  .category-toolbar .tabs { flex:1; min-width:0; padding:4px 0; }
  .category-toolbar .heading-actions { flex:none; }
  @media(max-width:760px){.category-toolbar{flex-wrap:wrap;gap:8px;padding-inline:20px}.category-toolbar .tabs{flex-basis:100%}.category-toolbar .heading-actions{margin-left:auto}}
  .divider { height:1px; margin:0 32px 8px; background:rgb(255 255 255 / 9%); }
  @supports ((backdrop-filter:blur(1px)) or (-webkit-backdrop-filter:blur(1px))) {
    .glass { background:var(--sideb-acrylic-surface); backdrop-filter:var(--sideb-acrylic-blur); -webkit-backdrop-filter:var(--sideb-acrylic-blur); }

  }
  .state { display: flex; min-height: 320px; flex-direction: column; align-items: center; justify-content: center; gap: 12px; padding: 24px; color: #b9b9c0; text-align: center; }
  .state h2 { margin: 0; color: #f3f3f5; font-size: 17px; }.state p { max-width: 50ch; margin: 0; font-size: 13px; }
  .spinner { width: 22px; height: 22px; border: 2px solid #ffffff30; border-top-color: var(--sideb-highlight); border-radius: 50%; animation: spin .8s linear infinite; }


  .card-content { position: relative; }.updating { padding: 8px 32px 0; color: #aaaab1; font-size: 11px; }
  .grid { display: block; padding: 20px 32px 0; }
  .inline-error { display: flex; align-items: center; gap: 10px; margin: 8px 32px; padding: 8px 12px; border-radius: 7px; color: #ffd5d5; background: #9d303033; font-size: 12px; }
  .bottom-space { height: 130px; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 3px; }
  @keyframes spin { to { transform: rotate(360deg); } }
  @media (max-width: 640px) { .tabs { overflow-x: auto; padding-inline: 20px; }.divider { margin-inline: 20px; }.grid { padding-inline: 20px; } }
  @media (prefers-reduced-motion: reduce) { .spinner { animation: none; } }

  .coverage { display:flex;gap:12px;align-items:center;margin:0;padding:0 32px 14px;font-size:12px;color:#b6b6bf; }
  .collection-section { padding:16px 32px; }.collection-section h2 { margin:0 0 16px;font-size:19px; }.section-title { display:flex;justify-content:space-between;align-items:baseline;gap:15px; }
  .overview-grid { display:grid;grid-auto-flow:column;grid-auto-columns:180px;gap:18px;overflow-x:auto;padding:4px 2px 8px;scrollbar-width:thin; }.overview-grid.listing,.listing { display:flex;flex-direction:column;gap:8px; }
  .collection-item { position:relative;min-width:0; }.pin-actions { display:flex;gap:3px;justify-content:flex-end;height:24px;margin-top:4px; }.pin-actions button { border:0;border-radius:5px;background:var(--sideb-surface);color:#b6b6bf;cursor:pointer;font-size:14px;padding:0 7px; }.pin-actions button.pinned { color:var(--sideb-highlight); }.pin-actions svg { width:14px;height:14px; }.pin-actions button:disabled { opacity:.3;cursor:default; }
  .collection-item:not(.has-pin) .pin-actions { opacity:0; pointer-events:none; }
  .collection-item:not(.has-pin):hover .pin-actions,.collection-item:not(.has-pin):focus-within .pin-actions { opacity:1; pointer-events:auto; }
  @media(hover:none){.collection-item:not(.has-pin) .pin-actions { opacity:1; pointer-events:auto; }}
  @media(max-width:760px){.heading { align-items:flex-start; flex-wrap:wrap; }.overview-grid{grid-auto-columns:160px}}
  @media(max-width:640px){.heading { padding:28px 20px 10px; }.toolbar { padding-inline:20px; }.collection-section { padding-inline:20px; }.coverage { padding-inline:20px; }.tabs { scroll-padding-inline:20px; }.heading-actions { flex-wrap:wrap; }.view-tools { margin-left:0; }}
  @media(prefers-reduced-transparency:reduce){.glass{background:var(--sideb-acrylic-fallback);backdrop-filter:none;-webkit-backdrop-filter:none;}}
  @media(forced-colors:active){.glass { color:ButtonText; background:ButtonFace; border-color:ButtonText; backdrop-filter:none; -webkit-backdrop-filter:none; }}

</style>
