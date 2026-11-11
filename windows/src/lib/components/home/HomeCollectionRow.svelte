<script lang="ts">
  import { language } from '$lib/i18n';
  import { collectionSummary } from '$lib/i18n/presentation';
  import { onMount, untrack } from 'svelte';
  import type { HomeItemDto } from '$lib/types';
  import { metadataFor } from '$lib/home/collectionMetadata';
  import type { FeaturedMetadata } from '$lib/home/metadata';
  import HorizontalNavigation from '../common/HorizontalNavigation.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  const GAP = 24, INSET = 28, LIFT = 8;
  interface Props {
    collections: HomeItemDto[]; metadata: Record<string, FeaturedMetadata>; label: string; active?: boolean; session: string;
    panelStyle: 'white' | 'tinted'; cardWidth: number; count: number; anchor?: number;
    onAnchor?: (index: number) => void; onVisible?: (items: HomeItemDto[]) => void; onOpen?: (item: HomeItemDto) => void;
    onOpenArtist?: (id: string) => void; onOpenAlbum?: (id: string) => void;
  }
  let { collections, metadata, label, active = true, session, panelStyle, cardWidth, count, anchor = 0, onAnchor, onVisible, onOpen, onOpenArtist, onOpenAlbum }: Props = $props();
  const identity = (item: HomeItemDto) => `${item.kind}|${item.id}`;
  let track = $state<HTMLDivElement>();
  let mounted = $state(false);
  const stride = $derived(cardWidth + GAP);
  const key = $derived(collections.map(identity).join('\u001f'));
  // Posición y ancho medidos; antes de medir se parte del ancla recibida para que su zona sea la primera en pedirse.
  let left = $state(untrack(() => anchor * (cardWidth + GAP)));
  let viewport = $state(0);
  const span = $derived(viewport > 0 ? viewport : count * stride + 2 * INSET);
  // Tarjetas que tocan el área útil (sin los márgenes de 28px): como mucho `count + 1` al desplazar.
  const visible = $derived(collections.filter((_, index) => {
    const from = INSET + index * stride - left;
    return from + cardWidth > INSET + 1 && from < span - INSET - 1;
  }));
  // Se piden los detalles de toda la fila de una vez; las tarjetas a la vista van primero.
  const wanted = $derived([...visible, ...collections.filter(item => !visible.includes(item))]);
  const signature = $derived(wanted.map(identity).join('\u001f'));
  $effect(() => { signature; if (active) untrack(() => onVisible?.(wanted)); });

  function anchorAt(offset: number) { return Math.min(Math.max(0, collections.length - 1), Math.max(0, Math.round(offset / stride))); }
  function sync() {
    if (!track || !active || track.clientWidth <= 0) return;
    viewport = track.clientWidth; left = track.scrollLeft;
    const next = anchorAt(left);
    if (next !== anchor) onAnchor?.(next);
  }
  onMount(() => { mounted = true; });
  // El padre manda el ancla; cambiar el ancho de tarjeta o la lista reubica la fila sobre ella.
  let lastStride = -1, lastKey = '';
  $effect(() => {
    const nextStride = stride, nextKey = key, wanted = anchor;
    if (!mounted || !track || !active) return;
    untrack(() => {
      const forced = nextStride !== lastStride || nextKey !== lastKey;
      lastStride = nextStride; lastKey = nextKey;
      if (!forced && Math.round(track!.scrollLeft / nextStride) === wanted) return;
      track!.scrollLeft = wanted * nextStride;
      sync();
    });
  });
  // Después de reubicar: así la primera medición ya parte del ancla y no la pisa.
  $effect(() => { if (!mounted || !active) return; sync(); const observer = new ResizeObserver(sync); observer.observe(track!); return () => observer.disconnect(); });
</script>
<HorizontalNavigation {active} {label} {stride} revision={`${key}|${cardWidth}`} center={`${LIFT + cardWidth / 2}px`}>
  <!-- Keyboard scrolling is available independently of individual cards. -->
  <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
  <div class="collection-row" data-horizontal-scroll bind:this={track} onscroll={sync} role="region" aria-label={label} tabindex="0">
    {#each collections as item (identity(item))}{@const detail = metadata[identity(item)] ?? metadataFor(item)}
      <div class="item" style:width={`${cardWidth}px`}>
        <MediaCard card={{ ...item, title: detail.title, subtitle: null, artists: detail.artists, artistId: detail.artistId, artistRuns: [] }} layout="panel" {panelStyle} coverSession={session}
          onOpen={() => onOpen?.(item)} {onOpenArtist} {onOpenAlbum} summary={collectionSummary(detail.summary, $language)} />
      </div>
    {/each}
  </div>
</HorizontalNavigation>
<style>
  /* El padding vertical da sitio a la elevación y la sombra del hover; el margen negativo superior mantiene la separación visual. */
  .collection-row { box-sizing:border-box; display:flex; align-items:stretch; gap:24px; width:100%; margin-top:-8px; padding:8px var(--featured-trailing,28px) 48px 28px; overflow-x:auto; overflow-y:hidden;
    scroll-snap-type:x proximity; scroll-padding-inline:28px; scrollbar-width:none;
    /* La separación (24) es menor que el margen (28): sin este recorte asomarían 4px de la tarjeta siguiente. */
    clip-path:inset(0 5px); }
  .collection-row::-webkit-scrollbar { display:none; width:0; height:0; }
  .collection-row:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:-8px; }
  .item { flex:none; min-width:0; scroll-snap-align:start; }
</style>
