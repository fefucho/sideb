<script lang="ts">
  import ControlButton from '$lib/components/common/ControlButton.svelte';
  import MenuIcon from '$lib/components/menu/MenuIcon.svelte';
  import ControlFilter from '$lib/components/common/ControlFilter.svelte';

  import {tick,untrack} from 'svelte';
  import type {BrowseCardDto} from '$lib/types';
  import type {ExploreData} from '$lib/explore/controller';
  import {tabs,genres,moods,selectedTab,countryName,type ExploreRoute,type ExploreCategory} from '$lib/explore/catalog';
  import {t,language} from '$lib/i18n';
  import VirtualCatalog from './VirtualCatalog.svelte';
  import HorizontalNavigation from '../common/HorizontalNavigation.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  interface Props {data:ExploreData;onNavigate:(route:ExploreRoute)=>void;onRefresh:()=>void;onOpenCard:(card:BrowseCardDto)=>void;onScrollTop?:(offset:number)=>void;currentTrackId?:string|null;isPlaying?:boolean;active?:boolean}
  let {data:liveData,onNavigate,onRefresh,onOpenCard,onScrollTop,active=true}:Props=$props();
  let rendered=$state(untrack(()=>liveData));
  $effect(()=>{const next=liveData;if(active)rendered=next;});
  const data=$derived(rendered);
  let scroll:HTMLDivElement;
  let lastSnapshot:ExploreData|null=null, savedOffset=0, wasActive=false;
  $effect.pre(()=>{if(wasActive&&!active&&scroll)savedOffset=scroll.scrollTop;wasActive=active;});
  $effect(()=>{
    if(!active)return;
    const snapshot=data,offset=lastSnapshot===snapshot?savedOffset:snapshot.scrollTop;
    lastSnapshot=snapshot;
    void tick().then(()=>{if(active&&scroll&&data===snapshot)scroll.scrollTop=offset;});
  });
  const tab=$derived(selectedTab(data.route));
  const title=$derived(data.route.startsWith('category:')?$t(`explore.category.${data.route.slice(9)}.title`):data.route.startsWith('country:')?$t('explore.route.chart_country',[countryName(data.route.slice(8),$language)]):$t(`explore.route.${data.route}`));
  function open(card:BrowseCardDto){if(active)onOpenCard(card);}
</script>
{#snippet categories(items:ExploreCategory[])}
  <div class="categories">{#each items as item (item.id)}<button type="button" style={`--hue:${item.hue*360}`} onclick={()=>onNavigate(`category:${item.id}`)}><strong>{$t(`explore.category.${item.id}.title`)}</strong><span>{$t(`explore.category.${item.id}.subtitle`)}</span></button>{/each}</div>
{/snippet}
{#snippet cards(items:BrowseCardDto[],horizontal=false)}
  <VirtualCatalog {items} {horizontal} {active}>
    {#snippet children(card)}<MediaCard {card} onOpen={()=>open(card)} onPlay={()=>open(card)} onOpenArtist={id=>open({kind:'artist',id,title:'',subtitle:null,thumbnail:null,duration:null})} onOpenAlbum={id=>open({kind:'album',id,title:'',subtitle:null,thumbnail:null,duration:null})}/>{/snippet}
  </VirtualCatalog>
{/snippet}
<div class="explore-page" inert={!active}>
  <div class="explore-scroll" bind:this={scroll} onscroll={()=>{if(active)onScrollTop?.(scroll.scrollTop);}}>
    <header><h1>{data.route==='discover'?$t('navigation.explore'):title}</h1></header>
    <div class="explore-tabs"><HorizontalNavigation {active} small label={$t('explore.eyebrow')}><nav data-horizontal-scroll aria-label={$t('explore.eyebrow')}>{#each tabs as item (item)}<ControlFilter selected={tab===item} onclick={()=>onNavigate(item)}>{$t(`explore.route.${item}`)}</ControlFilter>{/each}</nav></HorizontalNavigation><ControlButton iconOnly type="button" disabled={data.isLoading} onclick={onRefresh} aria-label={$t('explore.refresh')}><MenuIcon name="refresh" /></ControlButton></div>
    {#if tab==='charts'}
      <label>{$t('explore.region.selector')} <select class="sideb-control-field" value={data.route} onchange={event=>onNavigate(event.currentTarget.value as ExploreRoute)}><option value="charts">{$t('explore.region.global_and_yours')}</option><option value="country:ZZ">{$t('explore.region.global')}</option>{#each data.countries.filter(c=>c.code!=='ZZ') as country (country.code)}<option value={`country:${country.code}`}>{countryName(country.code,$language)}</option>{/each}</select></label>
      {#if data.detectedCountry}<p class="hint">{$t('explore.region.detected',[countryName(data.detectedCountry,$language)])}</p>{/if}
      {#if data.regionMessage}<p class="hint" role="status">{$t(data.regionMessage,[countryName(data.detectedCountry??'ZZ',$language)])}</p>{/if}
    {/if}
    {#if data.error}<div class="state" role="alert"><p>{$t(data.error)}</p><ControlButton onclick={onRefresh}>{$t('explore.retry')}</ControlButton></div>{/if}
    {#if data.isLoading}<p class="hint" role="status" aria-busy="true">{$t('explore.refresh_music')}…</p>{/if}
    {#if data.route==='discover'}
      <div class="shortcuts">
        <button type="button" style="--hue:7" onclick={()=>onNavigate('releases')}>
          <svg class="shortcut-icon" viewBox="0 0 32 32" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><circle cx="16" cy="16" r="12"/><circle cx="16" cy="16" r="3"/><path d="M16 7a9 9 0 0 1 9 9M16 25a9 9 0 0 1-9-9"/></svg>
          <span class="shortcut-copy"><strong>{$t('explore.route.releases')}</strong><span>{$t('explore.shortcut.new_arrivals')}</span></span><span class="shortcut-arrow" aria-hidden="true">↗</span>
        </button>
        <button type="button" style="--hue:230" onclick={()=>onNavigate('charts')}>
          <svg class="shortcut-icon" viewBox="0 0 32 32" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M5 26h23M8 22v-7h4v7M16 22V6h4v16M24 22V11h4v11"/></svg>
          <span class="shortcut-copy"><strong>{$t('explore.route.charts')}</strong><span>{$t('explore.shortcut.global_region')}</span></span><span class="shortcut-arrow" aria-hidden="true">↗</span>
        </button>
      </div>
      <section><div class="section-heading"><h2>{$t('explore.section.new_albums_singles')}</h2><ControlButton emphasis="quiet" size="utility"  type="button" onclick={()=>onNavigate('releases')}>{$t('explore.see_all')}</ControlButton></div>{@render cards(data.items.slice(0,12),true)}</section>
      <section><h2>{$t('explore.section.for_every_moment')}</h2>{@render categories(moods)}</section>
      <section><div class="section-heading"><h2>{$t('explore.section.explore_genres')}</h2><ControlButton emphasis="quiet" size="utility"  type="button" onclick={()=>onNavigate('genres')}>{$t('explore.see_all')}</ControlButton></div>{@render categories(genres.slice(0,8))}</section>
    {:else if data.route==='genres'}{@render categories(genres)}
    {:else if data.route==='moods'}{@render categories(moods)}
    {:else if tab==='charts'}
      {#each data.sections as section (section.code)}<section><h2>{countryName(section.code,$language)}</h2>{#if section.error}<p role="status">{$t(section.error)} <ControlButton onclick={onRefresh}>{$t('explore.retry')}</ControlButton></p>{:else}{@render cards(section.items)}{/if}</section>{/each}
      {#if !data.isLoading&&!data.error&&!data.sections.some(s=>s.items.length)}<div class="state">{$t('explore.charts.empty_title')}</div>{/if}
    {:else}<section><h2>{$t(data.route==='releases'?'explore.section.new_albums_singles':'explore.section.playlists_to_explore')}</h2>{@render cards(data.items)}{#if !data.isLoading&&!data.error&&!data.items.length}<div class="state">{$t('explore.empty.description')}</div>{/if}</section>{/if}
  </div>
</div>
<style>
  .explore-page{height:100%;min-height:0;min-width:0;color:var(--text-primary,#eee);container-type:inline-size;}
  .explore-scroll{height:100%;min-height:0;min-width:0;overflow:auto;box-sizing:border-box;padding:24px 28px 140px;}
  header h1{margin:0;min-height:52px;font-size:40px;line-height:52px;font-weight:700;overflow-wrap:anywhere;}
  .explore-tabs{display:flex;align-items:center;gap:8px;min-width:0;margin-top:30px;}
  nav{display:flex;align-items:center;gap:var(--control-category-gap);padding:4px 2px;overflow-x:auto;scrollbar-width:none;}
  nav :global(button){flex:none;}
  .categories button,.shortcuts button{font:inherit;color:inherit;border:1px solid #ffffff12;border-radius:14px;background:var(--sideb-surface);cursor:pointer;}
  .categories button:hover,.shortcuts button:hover{filter:brightness(1.1);}
  button:focus-visible,select:focus-visible{outline:2px solid var(--sideb-highlight);outline-offset:2px;}
  .hint{color:var(--text-secondary,#aaa);font-size:13px;}
  section{margin-top:30px;min-width:0;}
  h2{margin:0 0 16px;font-size:21px;}
  .section-heading{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:16px;}
  .section-heading h2{margin:0;}
  .categories{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(190px,100%),1fr));gap:14px;margin-top:30px;}
  section .categories{margin-top:0;}
  .categories button{text-align:left;min-width:0;min-height:135px;padding:18px;background:linear-gradient(125deg,hsl(var(--hue) 40% 27%),hsl(var(--hue) 25% 13%));}
  .categories strong,.categories span{display:block;overflow-wrap:anywhere;}
  .categories span{margin-top:8px;color:#ffffffa8;font-size:12px;}
  .shortcuts{display:flex;gap:16px;margin-top:30px;}
  .shortcuts button{display:flex;align-items:center;gap:16px;flex:1;min-width:0;padding:22px;text-align:left;border-radius:18px;background:linear-gradient(125deg,hsl(var(--hue) 40% 27%),hsl(var(--hue) 25% 13%));}
  .shortcut-icon{width:46px;height:32px;flex:none;color:hsl(var(--hue) 45% 75%);}
  .shortcut-copy{min-width:0;flex:1;overflow-wrap:anywhere;}
  .shortcut-copy strong{display:block;font-size:18px;}
  .shortcut-copy span{display:block;margin-top:5px;font-size:12px;color:#ffffffa8;}
  .shortcut-arrow{flex:none;font-size:16px;color:#ffffff99;}
  .state{text-align:center;padding:30px;color:var(--text-secondary,#bbb);}
  label{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin:30px 0 20px;}
  select{max-width:100%;min-width:0;}
  @container (width < 600px){.shortcuts{flex-direction:column;}}
</style>
