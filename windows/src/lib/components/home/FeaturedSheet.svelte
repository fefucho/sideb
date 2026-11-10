<script lang="ts">
  import { onMount, tick, untrack } from 'svelte';
  import { t } from '$lib/i18n';
  import type { HomeItemDto } from '$lib/types';
  import type { FeaturedMetadata } from '$lib/home/metadata';
  import { metadataFor } from '$lib/home/collectionMetadata';
  import { FEATURED, gridVisibleIndexes } from '$lib/home/rail';
  import CollectionCard from './CollectionCard.svelte';

  /** «Ver todo»: every featured collection of the current selection, with the current card actions. */
  interface Props {
    title: string;
    items: HomeItemDto[];
    metadata: Record<string, FeaturedMetadata>;
    onClose: () => void;
    onOpen: (item: HomeItemDto) => void;
    onOpenArtist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void;
    onVisible: (items: HomeItemDto[]) => void;
  }
  let { title, items, metadata, onClose, onOpen, onOpenArtist, onOpenAlbum, onVisible }: Props = $props();
  let dialog = $state<HTMLDivElement>();
  let scroller = $state<HTMLDivElement>();
  let grid = $state<HTMLDivElement>();
  let closeButton = $state<HTMLButtonElement>();
  let top = $state(0), viewport = $state(0), columns = $state(1);
  let previousFocus: HTMLElement | null = null;
  const rowHeight = FEATURED.sheetCardWidth + FEATURED.albumTextHeight;
  const visibleItems = $derived(gridVisibleIndexes(items.length, columns, rowHeight, FEATURED.sheetGap, top - 4, viewport).map(index => items[index]));

  function measure() {
    if (!scroller || !grid) return;
    top = scroller.scrollTop;
    viewport = scroller.clientHeight;
    // repeat(auto-fill, minmax(180px, 1fr)) with a 14px gap.
    columns = Math.max(1, Math.floor((grid.clientWidth + FEATURED.sheetGap) / (FEATURED.sheetCardWidth + FEATURED.sheetGap)));
  }
  let published = '';
  $effect(() => {
    const selected = visibleItems;
    const signature = selected.map(item => `${item.kind}|${item.id}`).join('\u0000');
    untrack(() => { if (signature === published) return; published = signature; onVisible(selected); });
  });
  onMount(() => {
    previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    closeButton?.focus();
    measure();
    const observer = new ResizeObserver(measure);
    if (scroller) observer.observe(scroller);
    const keydown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); onClose(); return; }
      if (event.key !== 'Tab' || !dialog) return;
      const focusable = Array.from(dialog.querySelectorAll<HTMLElement>('button:not(:disabled), a[href], [tabindex]:not([tabindex="-1"])'));
      if (!focusable.length) { event.preventDefault(); return; }
      const first = focusable[0], last = focusable[focusable.length - 1];
      if (event.shiftKey && (document.activeElement === first || !dialog.contains(document.activeElement))) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && (document.activeElement === last || !dialog.contains(document.activeElement))) { event.preventDefault(); first.focus(); }
    };
    document.addEventListener('keydown', keydown, true);
    return () => {
      observer.disconnect();
      document.removeEventListener('keydown', keydown, true);
      onVisible([]);
      void tick().then(() => { if (previousFocus?.isConnected) previousFocus.focus(); });
    };
  });
</script>

<div class="scrim" role="presentation" onclick={event => { if (event.target === event.currentTarget) onClose(); }}>
  <div class="dialog" bind:this={dialog} role="dialog" aria-modal="true" aria-labelledby="featured-sheet-title" data-featured-sheet>
    <header><h2 id="featured-sheet-title">{title}</h2><button bind:this={closeButton} type="button" class="close" onclick={onClose}>{$t('home.close')}</button></header>
    <div class="scroller" bind:this={scroller} onscroll={measure}>
      <div class="grid" bind:this={grid}>
        {#each items as item (`${item.kind}|${item.id}`)}
          <CollectionCard {item} detail={metadata[`${item.kind}|${item.id}`] ?? metadataFor(item)} width={FEATURED.sheetCardWidth} {onOpen} {onOpenArtist} {onOpenAlbum} />
        {/each}
      </div>
    </div>
  </div>
</div>

<style>
  .scrim { position:fixed; inset:0; z-index:40; display:grid; place-items:center; padding:24px; background:rgb(0 0 0 / 52%); }
  .dialog { box-sizing:border-box; width:min(840px,100%); height:min(500px,100%); min-width:0; display:flex; flex-direction:column; gap:12px; padding:24px; border:1px solid var(--sideb-surface-border); border-radius:16px; color:#f7f7f8; background:#29292f; box-shadow:0 24px 80px #0009; }
  header { flex:none; display:flex; align-items:center; justify-content:space-between; gap:20px; }
  h2 { margin:0; font-size:22px; line-height:28px; }
  .close { flex:none; padding:6px 14px; border:0; border-radius:8px; color:inherit; background:#ffffff14; font:inherit; font-size:13px; cursor:pointer; }
  .close:hover { background:#ffffff24; } .close:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:3px; }
  .scroller { min-height:0; flex:1; overflow-y:auto; overflow-x:hidden; padding:4px 4px 8px; margin:-4px; }
  .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(180px,1fr)); gap:14px; }
</style>
