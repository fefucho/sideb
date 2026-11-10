<script lang="ts">
  import { onMount } from 'svelte';
  import { t, language } from '$lib/i18n';
  import { providerHeading } from '$lib/i18n/presentation';
  import ControlButton from '$lib/components/common/ControlButton.svelte';
  import HorizontalNavigation from '../common/HorizontalNavigation.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  import { ARTIST_CARD_STRIDE, ARTIST_CARD_WIDTH, ARTIST_CARD_HEIGHT, artistShelfWindow } from '$lib/detail/artistShelf';
  import type { ArtistCarouselDto, BrowseCardDto } from '$lib/types';

  interface Props {
    section: ArtistCarouselDto;
    /** Last horizontal offset of this shelf; restored when the shelf is mounted again. */
    offset?: number;
    revision?: unknown;
    onOffset?: (value: number) => void;
    onMore: () => void;
    onOpen: (card: BrowseCardDto) => void;
    onPlay?: (card: BrowseCardDto) => void;
    onOpenArtist: (id: string) => void;
    onOpenAlbum: (id: string) => void;
  }
  let { section, offset = 0, revision, onOffset, onMore, onOpen, onPlay, onOpenArtist, onOpenAlbum }: Props = $props();

  let scroller = $state<HTMLElement | null>(null);
  let left = $state(0);
  let viewport = $state(1000);
  let rtl = $state(false);
  const heading = $derived(providerHeading(section.title, $language));
  const view = $derived(artistShelfWindow(section.items.length, left, viewport, rtl));
  const cards = $derived(section.items.slice(view.start, view.end));
  const hasMore = $derived(Boolean(section.moreBrowseId && !section.moreBrowseId.startsWith('FE')));

  onMount(() => {
    const element = scroller;
    if (!element) return;
    let frame = 0;
    const read = () => {
      frame = 0;
      rtl = getComputedStyle(element).direction === 'rtl';
      viewport = element.clientWidth || viewport;
      left = element.scrollLeft;
    };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(read); };
    const scrolled = () => { schedule(); onOffset?.(rtl ? -element.scrollLeft : element.scrollLeft); };
    // Restore before the first paint so a recycled shelf reopens where it was left.
    rtl = getComputedStyle(element).direction === 'rtl';
    viewport = element.clientWidth || viewport;
    if (offset > 0) { element.scrollLeft = rtl ? -offset : offset; left = element.scrollLeft; }
    const observer = new ResizeObserver(schedule);
    observer.observe(element);
    element.addEventListener('scroll', scrolled, { passive: true });
    return () => { observer.disconnect(); element.removeEventListener('scroll', scrolled); if (frame) cancelAnimationFrame(frame); };
  });
</script>

<section class="shelf" aria-label={heading} data-artist-shelf>
  <div class="section-heading">
    <h2>{heading}</h2>
    {#if hasMore}
      <ControlButton emphasis="quiet" size="utility" type="button" onclick={onMore}>{$t('home.see_all')}</ControlButton>
    {/if}
  </div>
  <HorizontalNavigation label={heading} {revision} center="80px" stride={ARTIST_CARD_STRIDE}>
    <!-- The shelf owns horizontal input: ordinary wheel never reaches history and an Alt wheel over it stays local. -->
    <div class="carousel" data-horizontal-scroll data-gesture-local data-artist-carousel bind:this={scroller}
      style:--artist-card-width={`${ARTIST_CARD_WIDTH}px`} style:--artist-card-height={`${ARTIST_CARD_HEIGHT}px`}>
      <div class="track" style:padding-inline-start={`${view.before}px`} style:padding-inline-end={`${view.after}px`}>
        {#each cards as card, index (`${card.kind}:${card.id}:${view.start + index}`)}
          <div class="carousel-card"><MediaCard {card} onOpen={() => onOpen(card)} onPlay={() => onPlay?.(card)} {onOpenArtist} {onOpenAlbum} /></div>
        {/each}
      </div>
    </div>
  </HorizontalNavigation>
</section>

<style>
  .shelf { display:flex; flex-direction:column; gap:14px; height:100%; min-width:0; box-sizing:border-box; padding-bottom:32px; }
  .section-heading { display:flex; align-items:center; justify-content:space-between; gap:12px; height:30px; padding-inline:32px; }
  h2 { margin:0; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-size:20px; font-weight:700; }
  .carousel { overflow-x:auto; overflow-y:hidden; overscroll-behavior-x:contain; padding:0 32px 8px; scrollbar-width:thin; }
  .track { display:flex; gap:16px; width:max-content; box-sizing:content-box; }
  .carousel-card { display:flex; flex:none; width:var(--artist-card-width); height:var(--artist-card-height); overflow:hidden; flex-direction:column; align-items:flex-start; padding:0; color:inherit; text-align:left; font:inherit; }
  @media (max-width:760px) { .section-heading { padding-inline:20px; } .carousel { padding-inline:20px; } }
</style>
