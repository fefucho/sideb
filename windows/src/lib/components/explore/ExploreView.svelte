<script lang="ts">
  import ControlButton from '$lib/components/common/ControlButton.svelte';
  import ControlFilter from '$lib/components/common/ControlFilter.svelte';

  import {tick} from 'svelte';
  import type {BrowseCardDto} from '$lib/types';
  import type {ExploreData} from '$lib/explore/controller';
  import {tabs,genres,moods,selectedTab,countryName,type ExploreRoute,type ExploreCategory} from '$lib/explore/catalog';
  import {t,language} from '$lib/i18n';
  import VirtualCatalog from './VirtualCatalog.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  interface Props {data:ExploreData;onNavigate:(route:ExploreRoute)=>void;onRefresh:()=>void;onOpenCard:(card:BrowseCardDto)=>void;onScrollTop?:(offset:number)=>void;currentTrackId?:string|null;isPlaying?:boolean;active?:boolean}
  let {data,onNavigate,onRefresh,onOpenCard,onScrollTop,active=true}:Props=$props();
  let scroll:HTMLDivElement;
  $effect(()=>{const route=data.route;const offset=data.scrollTop;void tick().then(()=>{if(scroll&&data.route===route)scroll.scrollTop=offset;});});
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
  <nav aria-label={$t('explore.eyebrow')}>{#each tabs as item (item)}<ControlFilter selected={tab===item} onclick={()=>onNavigate(item)}>{$t(`explore.route.${item}`)}</ControlFilter>{/each}<ControlButton iconOnly type="button" disabled={data.isLoading} onclick={onRefresh} aria-label={$t('explore.refresh')}>↻</ControlButton></nav>
  <div class="explore-scroll" bind:this={scroll} onscroll={()=>{if(active)onScrollTop?.(scroll.scrollTop);}}>
    <header><p>{$t('explore.eyebrow')}</p><h1>{data.route==='discover'?$t('explore.title.discover'):title}</h1>{#if data.route==='discover'}<p>{$t('explore.subtitle.discover')}</p>{/if}</header>
    {#if tab==='charts'}
      <label>{$t('explore.region.selector')} <select class="sideb-control-field" value={data.route} onchange={event=>onNavigate(event.currentTarget.value as ExploreRoute)}><option value="charts">{$t('explore.region.global_and_yours')}</option><option value="country:ZZ">{$t('explore.region.global')}</option>{#each data.countries.filter(c=>c.code!=='ZZ') as country (country.code)}<option value={`country:${country.code}`}>{countryName(country.code,$language)}</option>{/each}</select></label>
      {#if data.detectedCountry}<p class="hint">{$t('explore.region.detected',[countryName(data.detectedCountry,$language)])}</p>{/if}
      {#if data.regionMessage}<p class="hint" role="status">{$t(data.regionMessage,[countryName(data.detectedCountry??'ZZ',$language)])}</p>{/if}
    {/if}
    {#if data.error}<div class="state" role="alert"><p>{$t(data.error)}</p><ControlButton onclick={onRefresh}>{$t('explore.retry')}</ControlButton></div>{/if}
    {#if data.isLoading}<p class="hint" role="status" aria-busy="true">{$t('explore.refresh_music')}…</p>{/if}
    {#if data.route==='discover'}
      <div class="shortcuts"><button type="button" onclick={()=>onNavigate('releases')}>{$t('explore.shortcut.new_arrivals')} →</button><button type="button" onclick={()=>onNavigate('charts')}>{$t('explore.shortcut.global_region')} →</button></div>
      <section><div class="section-heading"><h2>{$t('explore.section.new_albums_singles')}</h2><ControlButton emphasis="quiet" size="utility"  type="button" onclick={()=>onNavigate('releases')}>{$t('explore.see_all')}</ControlButton></div>{@render cards(data.items.slice(0,12),true)}</section>
      <section><h2>{$t('explore.section.for_every_moment')}</h2>{@render categories(moods)}</section>
      <section><div class="section-heading"><h2>{$t('explore.section.explore_genres')}</h2><ControlButton emphasis="quiet" size="utility"  type="button" onclick={()=>onNavigate('genres')}>{$t('explore.see_all')}</ControlButton></div>{@render categories(genres.slice(0,8))}</section>
    {:else if data.route==='genres'}{@render categories(genres)}
    {:else if data.route==='moods'}{@render categories(moods)}
    {:else if tab==='charts'}
      {#each data.sections as section (section.code)}<section><h2>{countryName(section.code,$language)}</h2>{#if section.error}<p role="status">{$t(section.error)} <ControlButton onclick={onRefresh}>{$t('explore.retry')}</ControlButton></p>{:else}{@render cards(section.items)}{/if}</section>{/each}
      {#if !data.isLoading&&!data.error&&!data.sections.some(s=>s.items.length)}<div class="state">{$t('explore.charts.empty_title')}</div>{/if}
    {:else}{@render cards(data.items)}{#if !data.isLoading&&!data.error&&!data.items.length}<div class="state">{$t('explore.empty.description')}</div>{/if}{/if}
  </div>
</div>
<style>.explore-page{display:flex;flex-direction:column;height:100%;min-height:0;color:var(--text-primary,#eee);}nav{display:flex;align-items:center;gap:var(--control-category-gap);padding:16px 24px;flex:none;overflow-x:auto;border-bottom:1px solid #ffffff12;}.categories button,.shortcuts button{font:inherit;color:inherit;border:0;border-radius:12px;background:var(--sideb-surface);padding:12px;cursor:pointer;}.categories button:hover,.shortcuts button:hover{filter:brightness(1.1);}button:focus-visible,select:focus-visible{outline:2px solid var(--sideb-highlight);outline-offset:2px;}.explore-scroll{flex:1;min-height:0;overflow:auto;padding:24px 30px 120px;}header p,.hint{color:#aaa;font-size:13px;}header h1{margin:8px 0;font-size:30px;}section{margin-top:28px;}h2{font-size:18px;}.section-heading{display:flex;align-items:center;justify-content:space-between;gap:12px;}.categories{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:14px;}.categories button{text-align:left;min-height:110px;padding:18px;background:linear-gradient(125deg,hsl(var(--hue) 40% 27%),hsl(var(--hue) 25% 13%));}.categories strong,.categories span{display:block;}.categories span{margin-top:8px;color:#ffffffa8;font-size:12px;}.shortcuts{display:flex;gap:16px;margin-top:22px;}.shortcuts button{flex:1;padding:24px;text-align:left;}.state{text-align:center;padding:30px;color:#bbb;}label{display:flex;gap:10px;align-items:center;margin:20px 0;}select{max-width:100%;}@media(max-width:600px){.explore-scroll{padding-inline:16px;}nav{padding-inline:16px;}.shortcuts{flex-direction:column;}}</style>
