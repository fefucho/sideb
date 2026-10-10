<script lang="ts">
  import { t, language } from '$lib/i18n';
  import { providerHeading } from '$lib/i18n/presentation';
  import { onMount } from 'svelte';
  import type { HomeItemDto } from '$lib/types';
  import type { HomeSectionPresentation } from '$lib/home/presentation';
  import HomeCard from './HomeCard.svelte';
  import CompactSongCard from './CompactSongCard.svelte';
  interface Props {active?:boolean;section:HomeSectionPresentation;onOpenAlbum?: (id:string)=>void;onOpenPlaylist?:(id:string)=>void;onOpenArtist?:(id:string)=>void;onPlaySong?:(item:HomeItemDto)=>void;onOpenCatalog?:(id:string,params:string|null,title:string)=>void;initialScroll?:number;onScroll?:(offset:number)=>void}
  let {active=true,section,onOpenAlbum,onOpenPlaylist,onOpenArtist,onPlaySong,onOpenCatalog,initialScroll=0,onScroll}:Props=$props();
  let track:HTMLDivElement;let width=$state(1000);let left=$state(0);let narrow=$state(false);
  const compact=$derived(section.style==='compactSong');const rows=$derived(compact?4:1);
  const itemWidth=$derived(compact?(narrow?286:330):(narrow?140:160));const stride=$derived(itemWidth+16);
  const columns=$derived(Math.ceil(section.items.length/rows));
  const start=$derived(Math.max(0,Math.floor(left/stride)-1));const end=$derived(Math.min(columns,Math.ceil((left+width)/stride)+1));
  const visible=$derived(section.items.slice(start*rows,end*rows));
  function sync(){if(!track||!active)return;width=track.clientWidth;left=track.scrollLeft;narrow=(track.closest('.home')?.getBoundingClientRect().width??width)<760;onScroll?.(left);}
  $effect(()=>{if(active)requestAnimationFrame(sync);});
  onMount(()=>{track.scrollLeft=initialScroll;sync();const observer=new ResizeObserver(sync);observer.observe(track);return()=>observer.disconnect();});
</script>
<section class="shelf" aria-label={providerHeading(section.title, $language)}>
  <header><h2>{providerHeading(section.title, $language)}</h2>{#if section.moreBrowseId&&!section.moreBrowseId.startsWith('FE')&&onOpenCatalog}<button type="button" onclick={()=>onOpenCatalog?.(section.moreBrowseId!,section.moreParams,section.title)}>{$t('detail.viewAll')}</button>{/if}</header>
  <!-- Keyboard scrolling is available independently of individual cards. -->
  <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
  <div class="track" class:compact bind:this={track} onscroll={sync} role="region" aria-label={providerHeading(section.title, $language)} tabindex="0">
    <div class="track-space" style={`width:${Math.max(0,columns*stride-16)}px`}>
      <div class="window" class:compact style={`left:${start*stride}px;--item-width:${itemWidth}px`}>
      {#each visible as item (item.id)}{#if compact}<CompactSongCard item={item.record} {onPlaySong} {onOpenArtist} {onOpenAlbum}/>{:else}<HomeCard item={item.record} {onOpenAlbum} {onOpenArtist} {onOpenPlaylist} {onPlaySong}/>{/if}{/each}
      </div>
    </div>
  </div>
</section>
<style>
  .shelf{width:100%;padding:0 0 24px;}header{box-sizing:border-box;height:46px;padding:0 28px;display:flex;align-items:center;justify-content:space-between;gap:12px;}h2{min-width:0;overflow:hidden;margin:0;font-size:19px;line-height:24px;font-weight:700;text-overflow:ellipsis;white-space:nowrap;}header button{flex:none;padding:5px 0;border:0;background:transparent;color:inherit;font:inherit;font-size:13px;font-weight:600;cursor:pointer;}
  .track{box-sizing:border-box;width:100%;height:254px;padding:0 28px;overflow-x:auto;overflow-y:hidden;scrollbar-width:none;} .track::-webkit-scrollbar{display:none;width:0;height:0;} .track.compact{height:230px;}.track-space{position:relative;height:100%;}.window{position:absolute;top:0;display:flex;gap:16px;}.window.compact{display:grid;grid-auto-flow:column;grid-template-rows:repeat(4,56px);grid-auto-columns:var(--item-width);column-gap:16px;row-gap:1px;}
  button:focus-visible,.track:focus-visible{outline:2px solid var(--sideb-highlight);outline-offset:-2px;}
  @container home-content (width<760px){.track:not(.compact){height:234px;}}
</style>
