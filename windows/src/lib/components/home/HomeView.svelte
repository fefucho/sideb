<script lang="ts" module>
  const retained = new Map<string,{songPage:number;collectionAnchor:number;shelfOffsets:Record<string,number>}>();
</script>
<script lang="ts">
  import { t, language, resolveMessage } from '$lib/i18n';
  import { providerHeading, collectionSummary } from '$lib/i18n/presentation';
  import { onMount, untrack } from 'svelte';
  import type { AuthStatusDto, BrowseCardDto, HomeChipDto, HomeItemDto, HomeSectionDto } from '$lib/types';
  import { projectHome, featuredLayout } from '$lib/home/featured';
  import { homeGreetingKey } from '$lib/home/greeting';
  import { alignCollectionAnchor, featuredSelectionKey, FeaturedWheelInput } from '$lib/home/pages';
  import { metadataFor } from '$lib/home/collectionMetadata';
  import type { CollectionKind, HomeSettings as Settings } from '$lib/home/settings';
  import type { FeaturedMetadata } from '$lib/home/metadata';
  import HomeShelf from './HomeShelf.svelte';
  import HomeSettings from './HomeSettings.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  import VirtualStack from '../common/VirtualStack.svelte';
  interface Props {
    chips:HomeChipDto[]; sections:HomeSectionDto[]; selectedChipParams:string|null; isLoading:boolean; error:string|null;
    onSelectChip:(params:string|null)=>void; onRetry:()=>void; onOpenAlbum?:(id:string)=>void; onPlaySong?:(item:HomeItemDto)=>void;
    onOpenPlaylist?:(id:string)=>void; onOpenArtist?:(id:string)=>void; onOpenCatalog?:(id:string,params:string|null,title:string)=>void;
    hasMore:boolean; isLoadingMore:boolean; moreError:string|null; moreNotice:string|null; onLoadMore:()=>void;
    auth:AuthStatusDto; session:string; settings:Settings; kind:CollectionKind; albums:BrowseCardDto[]; playlists:BrowseCardDto[];
    history:{items:{albumId:string|null;album:string|null;artists:string;artistId:string|null}[]}[];
    onSettings:(settings:Settings)=>void; onKind:(kind:CollectionKind)=>void; interactive:boolean; libraryError:string|null;
    onRetryLibrary:()=>void; metadata:Record<string,FeaturedMetadata>; onVisibleCollections:(items:HomeItemDto[])=>void; onCapacity:(capacity:number)=>void;
    exponentialVolume?:boolean; volumeModePending?:boolean; onExponentialVolume?:(enabled:boolean)=>void;
  }
  let {chips,sections,selectedChipParams,isLoading,error,onSelectChip,onRetry,onOpenAlbum,onPlaySong,onOpenPlaylist,onOpenArtist,onOpenCatalog,
    hasMore,isLoadingMore,moreError,moreNotice,onLoadMore,auth,session,settings,kind,albums,playlists,history,onSettings,onKind,interactive,libraryError,onRetryLibrary,metadata,onVisibleCollections,onCapacity,exponentialVolume=false,volumeModePending=false,onExponentialVolume}:Props=$props();
  // Keep the last rendered inputs while fullscreen covers Home; publish the latest on reveal.
  const currentInputs=()=>({sections,selectedChipParams,settings,kind,albums,playlists,history,session});
  let rendered=$state(untrack(currentInputs));
  $effect(()=>{const next=currentInputs(),visible=interactive;untrack(()=>{if(visible||next.session!==rendered.session)rendered=next;});});
  let pendingWidth=1000;
  let root:HTMLElement; let width=$state(1000); let greetingKey=$state(homeGreetingKey()); let settingsOpen=$state(false); let gear:HTMLButtonElement;
  let shelfOffsets=$state<Record<string,number>>({});
  let retentionReady=$state(false);
  let songPage=$state(0); let collectionAnchor=$state(0); let lastCollectionIds:string[]=[]; let lastSongIds=''; let lastSelectionKey='';
  const candidates=$derived(projectHome(rendered.sections,rendered.selectedChipParams,rendered.settings,rendered.kind,6,rendered.albums,rendered.playlists,rendered.history));
  const layout=$derived(featuredLayout(width,candidates.songs.length,candidates.collections.length));
  const capacity=$derived(layout.capacity);
  const projection=$derived(projectHome(rendered.sections,rendered.selectedChipParams,rendered.settings,rendered.kind,capacity,rendered.albums,rendered.playlists,rendered.history));
  const songPages=$derived(Math.ceil(projection.songs.length/9));
  const collectionPages=$derived(Math.ceil(projection.collections.length/capacity));
  const collectionPage=$derived(Math.min(Math.floor(collectionAnchor/capacity),Math.max(0,collectionPages-1)));
  const visibleCollections=$derived(projection.collections.slice(collectionPage*capacity,(collectionPage+1)*capacity));
  const greeting=$derived($t(greetingKey));
  const name=$derived(auth.name?.trim() ?? '');
  const selectionKey=$derived(featuredSelectionKey(rendered.session,rendered.selectedChipParams,rendered.kind,rendered.settings));
  const songWheel=new FeaturedWheelInput(),collectionWheel=new FeaturedWheelInput();
  function changeCollectionPage(page:number){collectionAnchor=Math.max(0,Math.min(page,collectionPages-1))*capacity;}
  function wheel(event:WheelEvent, songs:boolean){const count=songs?songPages:collectionPages;if(count<2||Math.abs(event.deltaX)<=Math.abs(event.deltaY)*1.4||Math.abs(event.deltaX)<=.5)return;event.preventDefault();const delta=(songs?songWheel:collectionWheel).consume(event.deltaX*(event.deltaMode===1?16:event.deltaMode===2?width:1),event.deltaY,event.timeStamp);if(delta!==null){if(songs)songPage=Math.max(0,Math.min(songPage+delta,songPages-1));else changeCollectionPage(collectionPage+delta);}}
  $effect(()=>{if(interactive)onCapacity(capacity);});
  $effect(()=>{onVisibleCollections(interactive?visibleCollections:[]);});
  $effect(()=>{
    if (!retentionReady || !interactive) return;
    const currentIds=projection.collections.map(item=>`${item.kind}|${item.id}`),songIds=JSON.stringify(projection.songs.map(item=>item.id)),key=selectionKey;
    untrack(()=>{
      if(key!==lastSelectionKey){
        if(lastSelectionKey) retained.set(lastSelectionKey,{songPage,collectionAnchor,shelfOffsets:{...shelfOffsets}});
        const saved=retained.get(key);
        songPage=saved?.songPage??0;collectionAnchor=saved?.collectionAnchor??0;shelfOffsets=saved?.shelfOffsets??{};
      } else {
        collectionAnchor=alignCollectionAnchor(collectionAnchor,lastCollectionIds,currentIds);
        if(songIds!==lastSongIds)songPage=0;
      }
      lastCollectionIds=currentIds;lastSongIds=songIds;lastSelectionKey=key;
    });
  });
  $effect(()=>{if(!interactive)settingsOpen=false; else width=pendingWidth;});
  $effect(()=>{if(interactive&&retentionReady){retained.delete(selectionKey);retained.set(selectionKey,{songPage,collectionAnchor,shelfOffsets:{...shelfOffsets}});while(retained.size>12)retained.delete(retained.keys().next().value!);}});
  function closeSettings(){settingsOpen=false;gear?.focus();}
  function openCollection(item:HomeItemDto){if(item.kind==='album')onOpenAlbum?.(item.id);else onOpenPlaylist?.(item.id);}
  // Suspend the clock under fullscreen; reconcile immediately on reveal/activation.
  $effect(()=>{
    if(!interactive)return;
    let timer:ReturnType<typeof setInterval>|undefined;
    const resume=()=>{
      clearInterval(timer);
      if(document.visibilityState!=='visible')return;
      greetingKey=homeGreetingKey();
      timer=setInterval(()=>greetingKey=homeGreetingKey(),60000);
    };
    resume();document.addEventListener('visibilitychange',resume);window.addEventListener('focus',resume);
    return()=>{clearInterval(timer);document.removeEventListener('visibilitychange',resume);window.removeEventListener('focus',resume);};
  });
  onMount(()=>{
    const saved=retained.get(selectionKey);if(saved){songPage=saved.songPage;collectionAnchor=saved.collectionAnchor;shelfOffsets={...saved.shelfOffsets};}
    lastSelectionKey=selectionKey;lastCollectionIds=projection.collections.map(item=>`${item.kind}|${item.id}`);lastSongIds=JSON.stringify(projection.songs.map(item=>item.id));retentionReady=true;
    const observer=new ResizeObserver(([entry])=>{pendingWidth=entry.contentRect.width;if(interactive)width=pendingWidth;});observer.observe(root);
    return()=>observer.disconnect();
  });
</script>
<section class="home" bind:this={root} aria-label={$t('sidebar.home')} aria-busy={isLoading}>
  <div class="contents">
  <header class="heading"><div class="personal">{#if auth.thumbnail}<img class="avatar" src={auth.thumbnail} alt="" />{/if}<h1 title={greeting+(name ? `, ${name}` : '')}>{greeting}{name ? `, ${name}` : ''}</h1></div>
    <div class="actions" role="group" aria-label={$t('windows.ui.refreshAndConfigureHome')}>
      <button type="button" disabled={isLoading} aria-label={$t('windows.ui.refreshHome')} title={$t('windows.ui.refreshHome')} onclick={onRetry}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 7v5h-5M4 17v-5h5"/><path d="M6.1 7a7 7 0 0 1 11.6-1L20 9M4 15l2.3 3A7 7 0 0 0 17.9 17"/></svg></button>
      <button type="button" bind:this={gear} aria-label={$t('windows.ui.homeSettings')} title={$t('windows.ui.homeSettings')} aria-expanded={settingsOpen} onclick={()=>settingsOpen=!settingsOpen}><svg viewBox="0 0 24 24" aria-hidden="true"><g transform="translate(.5 0)"><path d="m9 3-.6 2.3-2 .9-2.1-.6L2 9.4l1.6 1.7v2L2 14.8l2.3 3.8 2.1-.6 2 .9.6 2.1h5l.6-2.1 2-.9 2.1.6 2.3-3.8-1.6-1.7v-2L21 9.4l-2.3-3.8-2.1.6-2-.9L14 3Z"/><circle cx="11.5" cy="12" r="3"/></g></svg></button>
    </div>
  </header>
  {#if chips.length}<nav class="chips" aria-label={$t('windows.ui.homeFilters')}><button type="button" aria-pressed={selectedChipParams===null} disabled={isLoading} onclick={()=>onSelectChip(null)}>{$t('app.home.allChip')}</button>{#each chips as chip (chip.params)}<button type="button" aria-pressed={selectedChipParams===chip.params} disabled={isLoading} onclick={()=>onSelectChip(chip.params)}>{providerHeading(chip.title, $language)}</button>{/each}</nav>{/if}
  {#if isLoading||error}<div class="status" role={error?'alert':'status'}>{isLoading?$t('home.refresh.updating'):$t('home.error.load') + ': ' + resolveMessage(error, $language)}{#if error}<button type="button" onclick={onRetry}>{$t('sidebar.retry')}</button>{/if}</div>{/if}
  {#if projection.songs.length||projection.collections.length}
    <div class="featured" class:wide={layout.wide} style={`--song-width:${layout.songWidth}px;--tile:${layout.tile}px;--card-height:${layout.cardHeight}px`}>
    {#if projection.songs.length}<section class="dial" aria-label={$t('provider.heading.speed-dial')} onwheel={event=>wheel(event,true)}><h2>{$t('provider.heading.speed-dial')}</h2><div class="tiles">{#each projection.songs.slice(songPage*9,(songPage+1)*9) as item (item.id)}<MediaCard card={item} layout="tile" onPlay={()=>onPlaySong?.(item)} {onOpenArtist} {onOpenAlbum} />{/each}</div>
      {#if songPages>0}<div class="pager" aria-label={$t('windows.ui.speedDialPages')}><button type="button" aria-label={$t('windows.ui.previousSpeedDialPage')} disabled={!songPage} onclick={()=>songPage--}><svg viewBox="0 0 16 16" aria-hidden="true"><path d="m10 3-5 5 5 5" /></svg></button>{#each Array(songPages) as _,i}<button type="button" class="dot" aria-label={$t('home.page.position', [$t('provider.heading.speed-dial'), i+1, songPages])} aria-current={songPage===i?'page':undefined} onclick={()=>songPage=i}></button>{/each}<button type="button" aria-label={$t('windows.ui.nextSpeedDialPage')} disabled={songPage>=songPages-1} onclick={()=>songPage++}><svg viewBox="0 0 16 16" aria-hidden="true"><path d="m6 3 5 5-5 5" /></svg></button></div>{/if}
    </section>{/if}
    {#if projection.collections.length}<section class="collections" onwheel={event=>wheel(event,false)} aria-label={kind==='albums'?$t('home.collection.albums'):$t('home.collection.playlists')}><h2>{kind==='albums'?$t('sidebar.albums'):$t('windows.ui.playlists')}</h2><div class="collection-grid" style={`--columns:${layout.columns}`}>
      {#each visibleCollections as item (`${item.kind}|${item.id}`)}{@const detail=metadata[`${item.kind}|${item.id}`]??metadataFor(item)}<div class="featured-card"><MediaCard card={{...item,title:detail.title,subtitle:null,artists:detail.artists,artistId:detail.artistId,artistRuns:[]}} layout="horizontal" featured onOpen={()=>openCollection(item)} {onOpenArtist} {onOpenAlbum} summary={collectionSummary(detail.summary, $language)} /></div>{/each}
    </div>{#if collectionPages>0}<div class="pager" aria-label={$t('windows.ui.featuredPages')}><button type="button" aria-label={$t('windows.ui.previousFeaturedPage')} disabled={!collectionPage} onclick={()=>changeCollectionPage(collectionPage-1)}><svg viewBox="0 0 16 16" aria-hidden="true"><path d="m10 3-5 5 5 5" /></svg></button>{#each Array(collectionPages) as _,i}<button type="button" class="dot" aria-label={$t('home.page.position', [$t('settings.featured'), i+1, collectionPages])} aria-current={collectionPage===i?'page':undefined} onclick={()=>changeCollectionPage(i)}></button>{/each}<button type="button" aria-label={$t('windows.ui.nextFeaturedPage')} disabled={collectionPage>=collectionPages-1} onclick={()=>changeCollectionPage(collectionPage+1)}><svg viewBox="0 0 16 16" aria-hidden="true"><path d="m6 3 5 5-5 5" /></svg></button></div>{/if}</section>{/if}
    </div>
  {/if}
  {#if !projection.collections.length}<p class="empty-featured">{(kind==='albums'?settings.albumSources:settings.playlistSources).some(row=>row.enabled)?$t('windows.ui.noFeaturedCollectionsOfThisTypeAreAvailableYet'):$t('settings.enableSource')}<button type="button" onclick={()=>settingsOpen=true}>{$t('windows.ui.configureSources')}</button></p>{/if}
  {#if !isLoading&&!error&&!projection.shelves.length&&!projection.songs.length&&!projection.collections.length}<p class="empty">{$t('windows.ui.noRecommendationsVisibleForThisFilterAndSettings')}</p>{/if}
  <VirtualStack active={interactive} items={projection.shelves} key={section=>section.id} height={(section,w)=>46+24+(section.style==='compactSong'?230:w<760?234:254)}>
    {#snippet children(section)}<HomeShelf active={interactive} {section} initialScroll={shelfOffsets[section.id]??0} onScroll={offset=>shelfOffsets[section.id]=offset} {onOpenAlbum} {onPlaySong} {onOpenArtist} {onOpenPlaylist} {onOpenCatalog} />{/snippet}
  </VirtualStack>
  <footer class="load-more" aria-live="polite">{#if moreError}<p role="alert">{resolveMessage(moreError, $language)}</p>{:else if moreNotice}<p>{resolveMessage(moreNotice, $language)}</p>{:else if !hasMore&&!isLoading&&sections.length}<p>{$t('app.home.noMore')}</p>{/if}{#if hasMore}<button type="button" disabled={isLoading||isLoadingMore} onclick={onLoadMore}>{isLoadingMore?$t('home.loading_recommendations'):moreError?$t('sidebar.retry'):$t('home.load_more')}</button>{/if}</footer>
  </div>
  {#if settingsOpen&&interactive}<HomeSettings {settings} {kind} categories={projection.categories} {libraryError} onChange={onSettings} {onKind} {onRetryLibrary} onClose={closeSettings} {exponentialVolume} {volumeModePending} {onExponentialVolume} />{/if}
</section>
<style>
  .home { min-width:0; min-height:100%; color:#f7f7f8; }
  .contents { position:relative; z-index:1; container-type:inline-size; container-name:home-content; } .heading { display:flex; justify-content:space-between; gap:16px; align-items:center; padding:40px 28px 12px; } .personal { display:flex; align-items:center; gap:12px; min-width:0; min-height:52px; } .avatar { flex:none; width:44px; height:44px; border-radius:50%; object-fit:cover; } h1 { margin:0; min-width:0; font-size:40px; line-height:1.3; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  button { border:0; color:inherit; background:var(--sideb-surface); font:inherit; border-radius:8px; cursor:pointer; } button:hover:not(:disabled) { background:var(--sideb-surface-hover); } button:disabled { opacity:.4; cursor:default; } button:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:3px; }
  .actions { display:flex; align-items:center; gap:2px; flex:none; padding:3px; height:40px; box-sizing:border-box; border:1px solid var(--sideb-acrylic-border); border-radius:999px; background:var(--sideb-acrylic-fallback); box-shadow:0 2px 6px rgb(0 0 0 / 10%); }
  .actions button { display:grid; place-items:center; width:32px; height:32px; padding:0; border-radius:50%; background:transparent; }
  .actions svg { width:18px; height:18px; fill:none; stroke:currentColor; stroke-width:1.6; stroke-linecap:round; stroke-linejoin:round; }
  .actions [aria-expanded=true] { background:#ffffff24; }
  @supports (backdrop-filter:blur(1px)) { .actions { background:var(--sideb-acrylic-surface); backdrop-filter:var(--sideb-acrylic-blur); } }
  @media (forced-colors:active) { .actions { background:Canvas; border-color:ButtonText; backdrop-filter:none; } }
  .chips { display:flex; gap:8px; padding:4px 28px 18px; overflow-x:auto; scrollbar-width:none; } .chips::-webkit-scrollbar { display:none; width:0; height:0; } .chips button { flex:none; padding:7px 14px; font-size:13px; border-radius:999px; } .chips [aria-pressed=true] { background:#ffffff24; }
  .status { margin:8px 28px 16px; display:flex; gap:12px; align-items:center; font-size:13px; color:#ccc; } .status button { padding:5px 12px; }
  .featured { display:flex; flex-direction:column; gap:24px; padding:8px 28px 24px; } .wide { flex-direction:row; } h2 { margin:0 0 16px; font-size:19px; line-height:24px; } .dial { flex:none; width:min(100%,436px); } .wide .dial { width:var(--song-width); } .tiles { display:grid; grid-template-columns:repeat(3,var(--tile)); gap:8px; } .tiles :global(.media-card) { width:var(--tile); aspect-ratio:1; }
  .collections { min-width:0; flex:1; } .collection-grid { display:grid; grid-template-columns:repeat(var(--columns),minmax(0,1fr)); grid-template-rows:repeat(2,1fr); grid-auto-flow:column; gap:24px; } .featured-card { height:var(--card-height); min-width:0; }
  .pager { display:flex; align-items:center; justify-content:center; gap:9px; height:48px; } .pager button { display:inline-flex; align-items:center; justify-content:center; flex:none; width:28px; height:28px; padding:0; line-height:1; background:transparent; } .pager svg { width:12px; height:12px; fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; } .pager .dot { width:14px; height:28px; border-radius:0; background:transparent; } .pager .dot::after { content:""; width:7px; height:7px; border-radius:50%; background:#ffffff45; } .pager [aria-current=page]::after { background:#ffffffcc; }
  .empty-featured,.empty { margin:8px 28px 24px; color:#b9b9c2; font-size:13px; } .empty-featured button { margin-left:12px; padding:6px 10px; }
  .load-more { display:flex; flex-direction:column; align-items:center; gap:12px; padding:24px 28px 140px; color:#b9b9c2; text-align:center; font-size:13px; } .load-more button { padding:9px 20px; border:1px solid var(--sideb-surface-border); } .load-more p { margin:0; }
  @container home-content (width<600px) { h1 { font-size:30px; }  .featured-card :global(.horizontal) { gap:12px; } .featured-card :global(.horizontal h3) { font-size:22px; line-height:27px; } .featured-card :global(.credits) { font-size:13px; } .featured-card :global(.art) { max-width:42%; } }
</style>
