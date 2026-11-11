<script lang="ts">
  import { t } from '$lib/i18n';
  import { onMount, untrack } from 'svelte';
  import type { HomeItemDto } from '$lib/types';
  import { mosaicLayout, mosaicSeed } from '$lib/home/mosaic';
  import HorizontalNavigation from '../common/HorizontalNavigation.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  const CELL = 144, GAP = 8, STRIDE = CELL + GAP, MARGIN = 2;
  interface Props {
    songs: HomeItemDto[]; active?: boolean; session: string; offset?: number; onScroll?: (offset: number) => void;
    onPlaySong?: (item: HomeItemDto) => void; onOpenArtist?: (id: string) => void; onOpenAlbum?: (id: string) => void;
  }
  let { songs, active = true, session, offset = 0, onScroll, onPlaySong, onOpenArtist, onOpenAlbum }: Props = $props();
  let track = $state<HTMLDivElement>();
  let width = $state(1000), left = $state(0), mounted = $state(false);
  // La disposición sólo depende de la lista de IDs: la misma lista dibuja siempre lo mismo.
  const key = $derived(songs.map(song => song.id).join('\u001f'));
  const layout = $derived.by(() => { key; const ids = untrack(() => songs.map(song => song.id)); return mosaicLayout(ids.length, mosaicSeed(ids)); });
  const start = $derived(Math.max(0, Math.floor(left / STRIDE) - MARGIN)), end = $derived(Math.ceil((left + width) / STRIDE) + MARGIN);
  const visible = $derived(layout.cells.filter(cell => cell.column + cell.columns > start && cell.column < end));
  function sync() { if (!track || !active) return; width = track.clientWidth; left = track.scrollLeft; onScroll?.(left); }
  $effect(() => { if (active) { const frame = requestAnimationFrame(sync); return () => cancelAnimationFrame(frame); } });
  onMount(() => { track!.scrollLeft = offset; lastOffset = offset; lastKey = key; mounted = true; });
  $effect(() => { if (!mounted || !active) return; sync(); const observer = new ResizeObserver(sync); observer.observe(track!); return () => observer.disconnect(); });
  // El padre manda la posición; una lista nueva sin posición nueva vuelve al inicio.
  let lastOffset = 0, lastKey = '';
  $effect(() => {
    const nextKey = key, wanted = offset;
    untrack(() => {
      if (!mounted || !track) return;
      const target = nextKey !== lastKey && wanted === lastOffset ? 0 : wanted;
      lastKey = nextKey; lastOffset = wanted;
      if (Math.abs(track.scrollLeft - target) > 1) { track.scrollLeft = target; sync(); }
    });
  });
</script>
<section class="mosaic" aria-label={$t('provider.heading.speed-dial')}>
  <h2>{$t('provider.heading.speed-dial')}</h2>
  <div class="rail">
    <HorizontalNavigation {active} label={$t('provider.heading.speed-dial')} stride={STRIDE} revision={key} center="232px">
      <!-- Keyboard scrolling is available independently of individual cards. -->
      <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
      <div class="track" data-horizontal-scroll bind:this={track} onscroll={sync} role="region" aria-label={$t('provider.heading.speed-dial')} tabindex="0">
        <div class="space" style={`width:${Math.max(0, layout.columns * STRIDE - GAP)}px`}>
          {#each visible as cell (songs[cell.index].id)}{@const item = songs[cell.index]}
            <div class="cell" style={`left:${cell.column * STRIDE}px;top:${cell.row * STRIDE}px;width:${cell.columns * STRIDE - GAP}px;height:${cell.rows * STRIDE - GAP}px`}>
              <MediaCard card={item} layout="mosaic" size={cell.size} coverSession={session} onPlay={() => onPlaySong?.(item)} {onOpenArtist} {onOpenAlbum} />
            </div>
          {/each}
        </div>
      </div>
    </HorizontalNavigation>
  </div>
</section>
<style>
  .mosaic { width:100%; padding:8px 0 16px; }
  h2 { margin:0 0 16px; padding:0 var(--featured-trailing,28px) 0 28px; font-size:19px; line-height:24px; }
  /* Margen negativo: el padding vertical da sitio a la elevación y las sombras sin cambiar la separación visual. */
  .rail { display:flow-root; margin:-8px 0 -32px; }
  .track { box-sizing:border-box; width:100%; height:488px; padding:8px var(--featured-trailing,28px) 32px 28px; overflow-x:auto; overflow-y:hidden; scrollbar-width:none; }
  .track::-webkit-scrollbar { display:none; width:0; height:0; }
  .track:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:-2px; }
  .space { position:relative; height:448px; }
  .cell { position:absolute; }
</style>
