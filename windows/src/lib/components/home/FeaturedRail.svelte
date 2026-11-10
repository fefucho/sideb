<script lang="ts" generics="T">
  import { onMount, tick, untrack, type Snippet } from 'svelte';
  import HorizontalNavigation from '../common/HorizontalNavigation.svelte';
  import { FEATURED, railAnchorId, railAnchorOffset, railContentWidth, railVisibleIds, railWindow } from '$lib/home/rail';

  /** One continuous Home rail: fixed-size cards in `rows` rows, recycled by column. */
  interface Props {
    items: T[];
    itemKey: (item: T) => string;
    label: string;
    itemWidth: number;
    itemHeight: number;
    gap: number;
    rows?: number;
    active?: boolean;
    /** Ask the rail to move to `left` (bumped by the parent when a selection is restored). */
    restore?: { token: number; left: number };
    onScroll?: (left: number) => void;
    onVisible?: (keys: string[]) => void;
    children: Snippet<[T]>;
  }
  let { items, itemKey, label, itemWidth, itemHeight, gap, rows = 1, active = true,
    restore, onScroll, onVisible, children }: Props = $props();

  let track = $state<HTMLDivElement>();
  let viewport = $state(0);
  let left = $state(0);
  let mounted = $state(false);
  // `display:none` (retained page) resets the scroller; the last real offset is kept here.
  let kept = 0;
  let anchor: string | null = null;
  let anchorOffset = 0;
  let applied = -1;

  const rowCount = $derived(Math.max(1, rows));
  const stride = $derived(itemWidth + gap);
  const keys = $derived(items.map(itemKey));
  const keySignature = $derived(keys.join('\u0000'));
  const range = $derived(railWindow(items.length, rowCount, stride, left - FEATURED.inset, viewport));
  const visible = $derived(items.slice(range.start * rowCount, range.end * rowCount));
  const height = $derived(rowCount * itemHeight + (rowCount - 1) * FEATURED.songGap);

  function sync() {
    if (!track || !active) return;
    viewport = track.clientWidth;
    left = track.scrollLeft;
    kept = left;
    const offset = Math.max(0, left - FEATURED.inset);
    anchor = railAnchorId(untrack(() => keys), rowCount, stride, offset);
    anchorOffset = stride > 0 ? Math.floor(offset / stride) * stride : 0;
    onScroll?.(left);
  }
  let frame = 0;
  function schedule() { if (!frame) frame = requestAnimationFrame(() => { frame = 0; sync(); }); }

  onMount(() => { mounted = true; });
  $effect(() => {
    if (!mounted || !active || !track) return;
    const element = track;
    // Coming back from a hidden retained page: put the scroller where the user left it.
    if (Math.abs(element.scrollLeft - kept) > 1) element.scrollLeft = kept;
    sync();
    const observer = new ResizeObserver(schedule);
    observer.observe(element);
    return () => { observer.disconnect(); cancelAnimationFrame(frame); frame = 0; };
  });

  // The list changed (more feed pages, library or source changes): keep the first visible card in place.
  let lastSignature = '';
  $effect(() => {
    const signature = keySignature;
    if (signature === lastSignature) return;
    const previous = lastSignature;
    lastSignature = signature;
    if (!previous || !active || !track) return;
    const target = railAnchorOffset(keys, anchor, rowCount, stride);
    if (target === null || target === anchorOffset) return;
    const element = track, delta = target - anchorOffset;
    void tick().then(() => { element.scrollLeft += delta; sync(); });
  });

  // Explicit restore (selection changed, account switched).
  $effect(() => {
    const request = restore;
    if (!request || request.token === applied) return;
    applied = request.token;
    kept = request.left;
    if (!mounted) return;
    void tick().then(() => {
      if (!track) return;
      if (active) { track.scrollLeft = request.left; sync(); }
    });
  });

  // Metadata is requested only for cards that intersect the viewport.
  let published = '';
  $effect(() => {
    const ids = active && mounted
      ? railVisibleIds(keys, itemWidth, rowCount, gap, left - FEATURED.inset, viewport)
      : [];
    const signature = ids.join('\u0000');
    untrack(() => {
      if (signature === published) return;
      published = signature;
      onVisible?.(ids);
    });
  });
</script>

<HorizontalNavigation {active} {label} {stride} revision={keySignature} center={`${height / 2}px`}>
  <div class="fade left" aria-hidden="true"></div>
  <div class="fade right" aria-hidden="true"></div>
  <!-- Keyboard scrolling is available independently of the cards. -->
  <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
  <div class="track" data-horizontal-scroll data-featured-rail={label} bind:this={track} onscroll={schedule} role="region" aria-label={label} tabindex="0"
    style:--rail-height={`${height}px`} style:--lead={`${FEATURED.inset}px`}>
    <div class="space" style:width={`${railContentWidth(range.columns, stride, gap)}px`}>
      <div class="window" style:left={`${range.start * stride}px`} style:grid-template-rows={`repeat(${rowCount},${itemHeight}px)`}
        style:grid-auto-columns={`${itemWidth}px`} style:gap={`${rowCount > 1 ? FEATURED.songGap : 0}px ${gap}px`}>
        {#each visible as item (itemKey(item))}{@render children(item)}{/each}
      </div>
    </div>
  </div>
</HorizontalNavigation>

<style>
  /* 4px of vertical room keeps focus rings of the first row from being clipped by the scroller. */
  .track { box-sizing:border-box; width:100%; height:calc(var(--rail-height) + 8px); margin:-4px 0; padding:4px var(--featured-trailing,28px) 4px var(--lead); overflow-x:auto; overflow-y:hidden; scrollbar-width:none; overscroll-behavior-x:contain; }
  .track::-webkit-scrollbar { display:none; width:0; height:0; }
  .track:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:-2px; }
  .space { position:relative; height:100%; }
  .window { position:absolute; top:0; display:grid; grid-auto-flow:column; }
  .fade { position:absolute; top:0; bottom:0; z-index:2; width:44px; pointer-events:none; opacity:0; }
  .fade.left { left:0; background:linear-gradient(to right, #00000038, transparent); }
  .fade.right { right:0; background:linear-gradient(to left, #00000038, transparent); }
  :global(.horizontal-navigation.leading) .fade.left, :global(.horizontal-navigation.trailing) .fade.right { opacity:1; }
  @media(forced-colors:active) { .fade { display:none; } }
</style>
