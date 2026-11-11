<script lang="ts" module>
  const retained = new Map<string,{mosaicOffset:number;collectionAnchor:number;shelfOffsets:Record<string,number>}>();
</script>
<script lang="ts">
  import ControlButton from '$lib/components/common/ControlButton.svelte';
  import ControlFilter from '$lib/components/common/ControlFilter.svelte';
  import HorizontalNavigation from '../common/HorizontalNavigation.svelte';
  import { appearance } from '$lib/appearance/preferences';

  import { t, language, resolveMessage } from '$lib/i18n';
  import { providerHeading } from '$lib/i18n/presentation';
  import { onMount, untrack } from 'svelte';
  import type { AuthStatusDto, BrowseCardDto, HomeChipDto, HomeItemDto, HomeSectionDto } from '$lib/types';
  import { projectHome, collectionRowLayout } from '$lib/home/featured';
  import { homeGreetingKey } from '$lib/home/greeting';
  import { alignCollectionAnchor, featuredSelectionKey } from '$lib/home/pages';
  import type { CollectionKind, HomeSettings as Settings } from '$lib/home/settings';
  import type { FeaturedMetadata } from '$lib/home/metadata';
  import HomeCollectionRow from './HomeCollectionRow.svelte';
  import HomeMosaic from './HomeMosaic.svelte';
  import HomeShelf from './HomeShelf.svelte';
  import HomeSettings from './HomeSettings.svelte';
  import FeaturedSheet from './FeaturedSheet.svelte';
  import VirtualStack from '../common/VirtualStack.svelte';
  interface Props {
    chips:HomeChipDto[]; sections:HomeSectionDto[]; selectedChipParams:string|null; isLoading:boolean; error:string|null;
    onSelectChip:(params:string|null)=>void; onRetry:()=>void; onOpenAlbum?:(id:string)=>void; onPlaySong?:(item:HomeItemDto)=>void;
    onOpenPlaylist?:(id:string)=>void; onOpenArtist?:(id:string)=>void; onOpenCatalog?:(id:string,params:string|null,title:string)=>void;
    hasMore:boolean; isLoadingMore:boolean; moreError:string|null; moreNotice:string|null; onLoadMore:()=>void;
    auth:AuthStatusDto; session:string; settings:Settings; kind:CollectionKind; albums:BrowseCardDto[]; playlists:BrowseCardDto[];
    history:{items:{albumId:string|null;album:string|null;artists:string;artistId:string|null}[]}[];
    onSettings:(settings:Settings)=>void; onKind:(kind:CollectionKind)=>void; interactive:boolean; libraryError:string|null;
    onRetryLibrary:()=>void; metadata:Record<string,FeaturedMetadata>; onVisibleCollections:(items:HomeItemDto[])=>void; onCapacity?:(capacity:number)=>void;
    exponentialVolume?:boolean; volumeModePending?:boolean; onExponentialVolume?:(enabled:boolean)=>void;
    /** The playback sidebar owns the right edge: the mosaic and the collection row reach it instead of keeping the 28px inset. */
    sidebarOpen?:boolean;
  }
  let {chips,sections,selectedChipParams,isLoading,error,onSelectChip,onRetry,onOpenAlbum,onPlaySong,onOpenPlaylist,onOpenArtist,onOpenCatalog,
    hasMore,isLoadingMore,moreError,moreNotice,onLoadMore,auth,session,settings,kind,albums,playlists,history,onSettings,onKind,interactive,libraryError,onRetryLibrary,metadata,onVisibleCollections,onCapacity,exponentialVolume=false,volumeModePending=false,onExponentialVolume,sidebarOpen=false}:Props=$props();
  // Keep the last rendered inputs while fullscreen covers Home; publish the latest on reveal.
  const currentInputs=()=>({sections,selectedChipParams,settings,kind,albums,playlists,history,session});
  let rendered=$state(untrack(currentInputs));
  $effect(()=>{const next=currentInputs(),visible=interactive;untrack(()=>{if(visible||next.session!==rendered.session)rendered=next;});});
  let pendingWidth=1000;
  let root:HTMLElement; let width=$state(1000); let greetingKey=$state(homeGreetingKey()); let settingsOpen=$state(false); let gear=$state<HTMLButtonElement>();
  let sheetOpen=$state(false);
  let shelfOffsets=$state<Record<string,number>>({});
  let retentionReady=$state(false);
  let mosaicOffset=$state(0); let collectionAnchor=$state(0); let lastCollectionIds:string[]=[]; let lastSongIds=''; let lastSelectionKey=''; let visibleCollections=$state<HomeItemDto[]>([]); let sheetVisible=$state<HomeItemDto[]>([]);
  const row=$derived(collectionRowLayout(width));
  const projection=$derived(projectHome(rendered.sections,rendered.selectedChipParams,rendered.settings,rendered.kind,row.count,rendered.albums,rendered.playlists,rendered.history));
  const greeting=$derived($t(greetingKey));
  const name=$derived(auth.name?.trim() ?? '');
  const selectionKey=$derived(featuredSelectionKey(rendered.session,rendered.selectedChipParams,rendered.kind,rendered.settings));
  const collectionTitle=$derived(kind==='albums'?$t('sidebar.albums'):$t('windows.ui.playlists'));
  $effect(()=>{if(interactive)onCapacity?.(row.count);});
  $effect(()=>{onVisibleCollections(interactive?(sheetOpen?sheetVisible:visibleCollections):[]);});
  $effect(()=>{
    if (!retentionReady || !interactive) return;
    const currentIds=projection.collections.map(item=>`${item.kind}|${item.id}`),songIds=JSON.stringify(projection.songs.map(item=>item.id)),key=selectionKey;
    untrack(()=>{
      if(key!==lastSelectionKey){
        if(lastSelectionKey) retained.set(lastSelectionKey,{mosaicOffset,collectionAnchor,shelfOffsets:{...shelfOffsets}});
        const saved=retained.get(key);
        mosaicOffset=saved?.mosaicOffset??0;collectionAnchor=saved?.collectionAnchor??0;shelfOffsets=saved?.shelfOffsets??{};
        sheetOpen=false;sheetVisible=[];
      } else {
        collectionAnchor=alignCollectionAnchor(collectionAnchor,lastCollectionIds,currentIds);
        if(songIds!==lastSongIds)mosaicOffset=0;
      }
      lastCollectionIds=currentIds;lastSongIds=songIds;lastSelectionKey=key;
    });
  });
  $effect(()=>{if(!interactive){settingsOpen=false;sheetOpen=false;} else width=pendingWidth;});
  $effect(()=>{if(interactive&&retentionReady){retained.delete(selectionKey);retained.set(selectionKey,{mosaicOffset,collectionAnchor,shelfOffsets:{...shelfOffsets}});while(retained.size>12)retained.delete(retained.keys().next().value!);}});
  function closeSettings(){settingsOpen=false;gear?.focus();}
  function openCollection(item:HomeItemDto){sheetOpen=false;if(item.kind==='album')onOpenAlbum?.(item.id);else onOpenPlaylist?.(item.id);}
  function openSheetArtist(id:string){sheetOpen=false;onOpenArtist?.(id);}
  function openSheetAlbum(id:string){sheetOpen=false;onOpenAlbum?.(id);}
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
    const saved=retained.get(selectionKey);if(saved){mosaicOffset=saved.mosaicOffset;collectionAnchor=saved.collectionAnchor;shelfOffsets={...saved.shelfOffsets};}
    lastSelectionKey=selectionKey;lastCollectionIds=projection.collections.map(item=>`${item.kind}|${item.id}`);lastSongIds=JSON.stringify(projection.songs.map(item=>item.id));retentionReady=true;
  });
  $effect(()=>{
    if(!retentionReady||!interactive)return;
    // A covered Home (display:none) measures 0: keep the last real width so the row and its anchor survive.
    const measure=(next:number)=>{if(next<=0)return;pendingWidth=next;if(interactive)width=next;};
    measure(root.getBoundingClientRect().width);
    const observer=new ResizeObserver(([entry])=>measure(entry.contentRect.width));observer.observe(root);
    return()=>observer.disconnect();
  });
</script>
<section class="home" class:sidebar-open={sidebarOpen} bind:this={root} aria-label={$t('sidebar.home')} aria-busy={isLoading}>
  <div class="contents">
  <header class="heading"><div class="personal">{#if auth.thumbnail}<img class="avatar" src={auth.thumbnail} alt="" />{/if}<h1 title={greeting+(name ? `, ${name}` : '')}>{greeting}{name ? `, ${name}` : ''}</h1></div>
    <div class="actions" role="group" aria-label={$t('windows.ui.refreshAndConfigureHome')}>
      <ControlButton iconOnly type="button" disabled={isLoading} aria-label={$t('windows.ui.refreshHome')} title={$t('windows.ui.refreshHome')} onclick={onRetry}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 7v5h-5M4 17v-5h5"/><path d="M6.1 7a7 7 0 0 1 11.6-1L20 9M4 15l2.3 3A7 7 0 0 0 17.9 17"/></svg></ControlButton>
      <ControlButton iconOnly type="button" bind:element={gear} aria-label={$t('windows.ui.homeSettings')} title={$t('windows.ui.homeSettings')} aria-expanded={settingsOpen} onclick={()=>settingsOpen=!settingsOpen}><svg viewBox="0 0 24 24" aria-hidden="true"><g transform="translate(.5 0)"><path d="m9 3-.6 2.3-2 .9-2.1-.6L2 9.4l1.6 1.7v2L2 14.8l2.3 3.8 2.1-.6 2 .9.6 2.1h5l.6-2.1 2-.9 2.1.6 2.3-3.8-1.6-1.7v-2L21 9.4l-2.3-3.8-2.1.6-2-.9L14 3Z"/><circle cx="11.5" cy="12" r="3"/></g></svg></ControlButton>
    </div>
  </header>
  {#if chips.length}<HorizontalNavigation active={interactive} small center="calc(50% - 7px)" label={$t('windows.ui.homeFilters')}><nav data-horizontal-scroll class="chips" aria-label={$t('windows.ui.homeFilters')}><ControlFilter type="button" selected={selectedChipParams===null} disabled={isLoading} onclick={()=>onSelectChip(null)}>{$t('app.home.allChip')}</ControlFilter>{#each chips as chip (chip.params)}<ControlFilter type="button" selected={selectedChipParams===chip.params} disabled={isLoading} onclick={()=>onSelectChip(chip.params)}>{providerHeading(chip.title, $language)}</ControlFilter>{/each}</nav></HorizontalNavigation>{/if}
  {#if isLoading||error}<div class="status" role={error?'alert':'status'}>{isLoading?$t('home.refresh.updating'):$t('home.error.load') + ': ' + resolveMessage(error, $language)}{#if error}<ControlButton onclick={onRetry}>{$t('sidebar.retry')}</ControlButton>{/if}</div>{/if}
  {#if projection.songs.length||projection.collections.length}
    {#if projection.songs.length}<HomeMosaic songs={projection.songs} active={interactive} {session} offset={mosaicOffset} onScroll={offset=>mosaicOffset=offset} {onPlaySong} {onOpenArtist} {onOpenAlbum} />{/if}
    {#if projection.collections.length}{@const collectionLabel=$t(kind==='albums'?'home.collection.albums':'home.collection.playlists')}<section class="collections" aria-label={collectionLabel}>
      <div class="panel-head"><h2>{collectionTitle}</h2>
        <ControlButton emphasis="quiet" size="utility" type="button" aria-haspopup="dialog" onclick={()=>{sheetVisible=[];sheetOpen=true;}}>{$t('detail.viewAll')}<svg class="chevron" viewBox="0 0 10 10" aria-hidden="true"><path d="m3 1 4 4-4 4"/></svg></ControlButton></div>
      <HomeCollectionRow collections={projection.collections} {metadata} label={collectionLabel} active={interactive} {session} panelStyle={$appearance.albumCardStyle} cardWidth={row.cardWidth} count={row.count}
        anchor={collectionAnchor} onAnchor={index=>collectionAnchor=index} onVisible={items=>visibleCollections=items} onOpen={openCollection} {onOpenArtist} {onOpenAlbum} /></section>{/if}
  {/if}
  {#if !projection.collections.length}<p class="empty-featured">{(kind==='albums'?settings.albumSources:settings.playlistSources).some(row=>row.enabled)?$t('windows.ui.noFeaturedCollectionsOfThisTypeAreAvailableYet'):$t('settings.enableSource')}<ControlButton onclick={()=>settingsOpen=true}>{$t('windows.ui.configureSources')}</ControlButton></p>{/if}
  {#if !isLoading&&!error&&!projection.shelves.length&&!projection.songs.length&&!projection.collections.length}<p class="empty">{$t('windows.ui.noRecommendationsVisibleForThisFilterAndSettings')}</p>{/if}
  <VirtualStack active={interactive} items={projection.shelves} key={section=>section.id} height={(section,w)=>46+24+(section.style==='compactSong'?230:w<760?234:254)}>
    {#snippet children(section)}<HomeShelf active={interactive} {section} initialScroll={shelfOffsets[section.id]??0} onScroll={offset=>shelfOffsets[section.id]=offset} {onOpenAlbum} {onPlaySong} {onOpenArtist} {onOpenPlaylist} {onOpenCatalog} />{/snippet}
  </VirtualStack>
  <footer class="load-more" aria-live="polite">{#if moreError}<p role="alert">{resolveMessage(moreError, $language)}</p>{:else if moreNotice}<p>{resolveMessage(moreNotice, $language)}</p>{:else if !hasMore&&!isLoading&&sections.length}<p>{$t('app.home.noMore')}</p>{/if}{#if hasMore}<ControlButton disabled={isLoading} loading={isLoadingMore} onclick={onLoadMore}>{moreError?$t('sidebar.retry'):$t('home.load_more')}</ControlButton>{/if}</footer>
  </div>
  {#if settingsOpen&&interactive}<HomeSettings {settings} {kind} categories={projection.categories} {libraryError} onChange={onSettings} {onKind} {onRetryLibrary} onClose={closeSettings} {exponentialVolume} {volumeModePending} {onExponentialVolume} />{/if}
  {#if sheetOpen&&interactive}<FeaturedSheet title={collectionTitle} items={projection.collections} {metadata} onClose={()=>sheetOpen=false} onOpen={openCollection} onOpenArtist={openSheetArtist} onOpenAlbum={openSheetAlbum} onVisible={items=>sheetVisible=items} />{/if}
</section>
<style>
  .home { --featured-trailing:28px; min-width:0; min-height:100%; color:#f7f7f8; }
  .home.sidebar-open { --featured-trailing:0px; }
  .contents { position:relative; z-index:1; container-type:inline-size; container-name:home-content; } .heading { display:flex; justify-content:space-between; gap:16px; align-items:center; padding:40px 28px 12px; } .personal { display:flex; align-items:center; gap:12px; min-width:0; min-height:52px; } .avatar { flex:none; width:44px; height:44px; border-radius:50%; object-fit:cover; } h1 { margin:0; min-width:0; font-size:40px; line-height:1.3; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .actions { display:flex; align-items:center; gap:var(--control-action-gap); flex:none; }

  .actions svg { width:18px; height:18px; fill:none; stroke:currentColor; stroke-width:1.6; stroke-linecap:round; stroke-linejoin:round; }



  .chips { display:flex; gap:var(--control-category-gap); padding:4px 28px 18px; overflow-x:auto; scrollbar-width:none; } .chips::-webkit-scrollbar { display:none; width:0; height:0; }
  .status { margin:8px 28px 16px; display:flex; gap:12px; align-items:center; font-size:13px; color:#ccc; }
  .collections { min-width:0; padding:8px 0 0; }
  .panel-head { box-sizing:border-box; height:38px; margin-bottom:2px; padding:0 var(--featured-trailing) 0 28px; display:flex; align-items:center; justify-content:space-between; gap:12px; }
  h2 { margin:0; min-width:0; overflow:hidden; font-size:19px; line-height:24px; text-overflow:ellipsis; white-space:nowrap; }
  .chevron { width:10px; height:10px; margin-left:3px; fill:none; stroke:currentColor; stroke-width:1.6; stroke-linecap:round; stroke-linejoin:round; }
  .empty-featured,.empty { margin:8px 28px 24px; color:#b9b9c2; font-size:13px; }
  .load-more { display:flex; flex-direction:column; align-items:center; gap:12px; padding:24px 28px 140px; color:#b9b9c2; text-align:center; font-size:13px; }  .load-more p { margin:0; }
  @container home-content (width<600px) { h1 { font-size:30px; } }
</style>
