<script lang="ts">
  import { afterUpdate, onMount } from 'svelte';
  import type { HomeItemDto } from '$lib/types';
  import HomeCard from './HomeCard.svelte';
  import CompactSongCard from './CompactSongCard.svelte';
  import type { HomeSectionPresentation } from '$lib/home/presentation';

  export let section: HomeSectionPresentation;
  export let onOpenAlbum: ((id: string) => void) | undefined = undefined;
  export let onOpenPlaylist: ((id: string) => void) | undefined = undefined;
  export let onOpenArtist: ((id: string) => void) | undefined = undefined;
  export let onPlaySong: ((item: HomeItemDto) => void) | undefined = undefined;
  export let onOpenCatalog: ((id: string, params: string | null, title: string) => void) | undefined = undefined;

  let trackElement: HTMLDivElement | undefined;
  let canScrollBack = false;
  let canScrollForward = false;

  function refreshScrollState() {
    if (!trackElement) return;
    const maxScroll = Math.max(0, trackElement.scrollWidth - trackElement.clientWidth);
    const nextBack = trackElement.scrollLeft > 1;
    const nextForward = trackElement.scrollLeft < maxScroll - 1;
    if (nextBack !== canScrollBack) canScrollBack = nextBack;
    if (nextForward !== canScrollForward) canScrollForward = nextForward;
  }


  function scrollShelf(direction: -1 | 1) {
    if (!trackElement) return;
    trackElement.scrollBy({ left: direction * Math.max(240, trackElement.clientWidth * 0.8), behavior: 'smooth' });
  }

  onMount(() => {
    const frame = requestAnimationFrame(refreshScrollState);
    const observer = typeof ResizeObserver !== 'undefined' && trackElement
      ? new ResizeObserver(refreshScrollState)
      : undefined;
    if (observer && trackElement) observer.observe(trackElement);
    return () => {
      cancelAnimationFrame(frame);
      observer?.disconnect();
    };
  });

  afterUpdate(refreshScrollState);
</script>

<section class="shelf" aria-label={section.title}>
  <header class="header">
    <h2>{section.title}</h2>
    <div class="header-actions">
      {#if section.moreBrowseId && !section.moreBrowseId.startsWith('FE') && onOpenCatalog}
        <button class="see-all" type="button" onclick={() => onOpenCatalog?.(section.moreBrowseId!, section.moreParams, section.title)}>Ver más</button>
      {/if}
      <div class="scroll-controls" aria-label={`Desplazar ${section.title}`}>
        <button class="scroll-button" type="button" aria-label={`Desplazar ${section.title} a la izquierda`} disabled={!canScrollBack} onclick={() => scrollShelf(-1)}><svg viewBox="0 0 16 16" aria-hidden="true"><path d="m10 3-5 5 5 5" /></svg></button>
        <button class="scroll-button" type="button" aria-label={`Desplazar ${section.title} a la derecha`} disabled={!canScrollForward} onclick={() => scrollShelf(1)}><svg viewBox="0 0 16 16" aria-hidden="true"><path d="m6 3 5 5-5 5" /></svg></button>
      </div>
    </div>
  </header>
  {#if section.style === 'compactSong'}
    <div class="compact-track" bind:this={trackElement} onscroll={refreshScrollState} role="region" aria-label={`${section.title}, canciones`}>
      {#each section.items as item (item.id)}
        <CompactSongCard item={item.record} {onPlaySong} {onOpenArtist} {onOpenAlbum} />
      {/each}
    </div>
  {:else}
    <div class="large-track" bind:this={trackElement} onscroll={refreshScrollState} role="region" aria-label={section.title}>
      {#each section.items as item (item.id)}
        <HomeCard item={item.record} {onOpenAlbum} {onOpenArtist} {onOpenPlaylist} {onPlaySong} />
      {/each}
    </div>
  {/if}
</section>

<style>
  .shelf { width:100%; padding:0 0 24px; }
  .header { box-sizing:border-box; height:var(--home-shelf-header-height,46px); padding:0 var(--home-shelf-header-inset-inline,28px); display:flex; align-items:center; justify-content:space-between; gap:12px; }
  h2 { min-width:0; overflow:hidden; margin:0; font-size:19px; line-height:24px; font-weight:700; text-overflow:ellipsis; white-space:nowrap; }
  .header-actions { display:flex; flex:none; align-items:center; gap:12px; }
  .see-all { padding:5px 0; border:0; background:transparent; color:inherit; font-family:inherit; font-size:13px; font-weight:600; cursor:pointer; }
  .see-all:hover { color:var(--sideb-highlight,#D06C70); }
  .see-all:focus-visible,.scroll-button:focus-visible { outline:2px solid var(--sideb-highlight,#D06C70); outline-offset:2px; }
  .scroll-controls { display:flex; gap:6px; }
  .scroll-button { box-sizing:border-box; display:grid; width:28px; height:28px; padding:0; place-items:center; border:0; border-radius:50%; background:var(--sideb-surface,rgba(255,255,255,.05)); color:inherit; cursor:pointer; }
  .scroll-button svg { display:block; width:16px; height:16px; fill:none; stroke:currentColor; stroke-width:1.6; stroke-linecap:round; stroke-linejoin:round; }
  .scroll-button:hover:not(:disabled) { background:var(--sideb-surface-hover,rgba(255,255,255,.08)); }
  .scroll-button:disabled { opacity:.4; cursor:default; }
  .large-track { box-sizing:border-box; width:100%; height:var(--home-card-height,254px); padding:0 var(--home-shelf-inset-inline,28px); display:flex; gap:var(--home-shelf-column-gap,16px); overflow-x:auto; overflow-y:hidden; scrollbar-width:none; scroll-behavior:smooth; }
  .large-track::-webkit-scrollbar,.compact-track::-webkit-scrollbar { display:none; }
  .compact-track { box-sizing:border-box; height:var(--home-compact-shelf-height,230px); padding:0 var(--home-shelf-inset-inline,28px); display:grid; grid-auto-flow:column; grid-template-rows:repeat(4,var(--home-compact-card-height,56px)); grid-auto-columns:var(--home-compact-card-width,330px); column-gap:var(--home-shelf-column-gap,16px); row-gap:1px; overflow-x:auto; overflow-y:hidden; scrollbar-width:none; scroll-behavior:smooth; }
  @container home-content (width < 760px) {
    .large-track { height:calc(var(--home-card-artwork-size-narrow,140px) + 94px); }
    .compact-track { grid-auto-columns:var(--home-compact-card-width-narrow,286px); }
  }
  @media (max-width:520px) { .header { padding-inline:18px; gap:6px; } .header-actions { gap:6px; } .scroll-controls { gap:3px; } .scroll-button { width:26px; height:26px; } }
</style>





