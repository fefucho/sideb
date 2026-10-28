<script lang="ts">
  import { onMount, type Snippet } from 'svelte';
  import { t } from '$lib/i18n';
  import { horizontalOffset, horizontalPageTarget } from '$lib/horizontal/scroll';
  import ControlButton from './ControlButton.svelte';

  interface Props {
    children: Snippet;
    label: string;
    active?: boolean;
    enabled?: boolean;
    small?: boolean;
    fill?: boolean;
    center?: string;
    stride?: number;
    items?: string;
    revision?: unknown;
    previous?: () => void;
    next?: () => void;
    canPrevious?: boolean;
    canNext?: boolean;
    previousLabel?: string;
    nextLabel?: string;
  }
  let { children, label, active = true, enabled = true, small = false, fill = false, center = '50%',
    stride, items, revision, previous, next, canPrevious = false, canNext = false, previousLabel, nextLabel }: Props = $props();
  let host: HTMLDivElement;
  let mounted = $state(false), leading = $state(false), trailing = $state(false);
  let focused = $state<-1 | 1 | null>(null);
  let scroll: HTMLElement | null = null;
  let desired: number | null = null;
  let read = () => {};
  let rtl = false, extent = 0, maximum = 0, padding = 0;
  const paged = $derived(Boolean(previous || next));
  const hasPrevious = $derived(active && enabled && (paged ? canPrevious : leading));
  const hasNext = $derived(active && enabled && (paged ? canNext : trailing));
  onMount(() => { mounted = true; });

  $effect(() => {
    if (!mounted || !active || !enabled || paged) return;
    let frame = 0, observed: Element | null = null;
    const resize = new ResizeObserver(() => schedule());
    const measure = () => {
      frame = 0;
      const element = host.querySelector<HTMLElement>('[data-horizontal-scroll]');
      if (scroll !== element) {
        detach(); scroll = element; desired = null;
        if (scroll) {
          resize.observe(scroll);
          scroll.addEventListener('scroll', schedule, { passive: true });
          scroll.addEventListener('scrollend', settled);
          for (const name of ['wheel', 'pointerdown', 'keydown', 'touchstart']) scroll.addEventListener(name, interrupted, { passive: true });
        }
      }
      if (!scroll) { leading = trailing = false; return; }
      const content = scroll.firstElementChild;
      if (observed !== content) {
        if (observed) resize.unobserve(observed);
        observed = content;
        if (observed) resize.observe(observed);
      }
      const style = getComputedStyle(scroll), nextMaximum = Math.max(0, scroll.scrollWidth - scroll.clientWidth);
      const nextExtent = scroll.clientWidth - (parseFloat(style.paddingLeft) || 0) - (parseFloat(style.paddingRight) || 0);
      const nextRTL = style.direction === 'rtl';
      if (maximum !== nextMaximum || extent !== nextExtent || rtl !== nextRTL) {
        if (desired !== null) scroll.scrollTo({ left: scroll.scrollLeft, behavior: 'instant' });
        desired = null;
      }
      rtl = nextRTL; maximum = nextMaximum; extent = nextExtent;
      padding = parseFloat(rtl ? style.paddingRight : style.paddingLeft) || 0;
      const offset = horizontalOffset(scroll.scrollLeft, maximum, rtl);
      leading = offset > 1; trailing = offset < maximum - 1;
    };
    function schedule() { if (!frame) frame = requestAnimationFrame(measure); }
    function interrupted() { desired = null; }
    function settled() { desired = null; schedule(); }
    function detach() {
      if (!scroll) return;
      resize.unobserve(scroll);
      scroll.removeEventListener('scroll', schedule);
      scroll.removeEventListener('scrollend', settled);
      for (const name of ['wheel', 'pointerdown', 'keydown', 'touchstart']) scroll.removeEventListener(name, interrupted);
    }
    read = measure;
    // Child recycling schedules an O(1) bounds read, never an all-items measurement.
    const mutation = new MutationObserver(schedule);
    mutation.observe(host, { childList: true, subtree: true });
    // Direction can change without a resize or a new list (e.g. an RTL host).
    for (let ancestor = host.parentElement; ancestor; ancestor = ancestor.parentElement) mutation.observe(ancestor, { attributes: true, attributeFilter: ['dir'] });
    measure();
    return () => {
      cancelAnimationFrame(frame); mutation.disconnect(); detach(); resize.disconnect();
      if (desired !== null && scroll) scroll.scrollTo({ left: scroll.scrollLeft, behavior: 'instant' });
      scroll = null; desired = null; read = () => {};
    };
  });
  $effect(() => {
    revision; stride; items;
    if (desired !== null && scroll) { scroll.scrollTo({ left: scroll.scrollLeft, behavior: 'instant' }); desired = null; }
    if (active && enabled) read();
  });

  function move(event: MouseEvent, direction: -1 | 1) {
    event.stopPropagation();
    if (!paged) read();
    if (direction < 0 ? !hasPrevious : !hasNext) return;
    if (paged) { (direction < 0 ? previous : next)?.(); return; }
    if (!scroll) return;
    const element = scroll, rect = element.getBoundingClientRect();
    const children = items ? element.querySelectorAll<HTMLElement>(items) : element.children;
    const position = desired ?? horizontalOffset(element.scrollLeft, maximum, rtl);
    const observed = horizontalOffset(element.scrollLeft, maximum, rtl);
    desired = horizontalPageTarget({ position, extent, maximum, direction, stride, count: children.length,
      startAt: index => {
        const box = children[index].getBoundingClientRect();
        return (rtl ? rect.right - box.right : box.left - rect.left) + observed - padding;
      } });
    element.scrollTo({ left: rtl ? -desired : desired, behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth' });
  }
  function keydown(event: KeyboardEvent) {
    if (event.key === ' ' || event.key === 'Enter') event.stopPropagation();
  }
</script>

<div class="horizontal-navigation" class:bypass={!enabled} class:fill class:small class:leading={hasPrevious} class:trailing={hasNext}
  bind:this={host} style:--horizontal-center={center} data-horizontal-navigation={label}>
  {@render children()}
  {#if enabled}
    <ControlButton iconOnly class={`horizontal-arrow previous ${!active || (!hasPrevious && focused !== -1) ? 'hidden' : ''}`} data-horizontal-arrow="previous"
      aria-label={previousLabel ?? $t('windows.carousel.previous', [label])} aria-disabled={!hasPrevious}
      tabindex={hasPrevious || focused === -1 ? 0 : -1} onclick={event => move(event, -1)} onkeydown={keydown}
      onfocus={() => { focused = -1; read(); }} onblur={() => focused = null}>
      <svg viewBox="0 0 20 20" aria-hidden="true"><path d="m12 4-6 6 6 6" /></svg>
    </ControlButton>
    <ControlButton iconOnly class={`horizontal-arrow next ${!active || (!hasNext && focused !== 1) ? 'hidden' : ''}`} data-horizontal-arrow="next"
      aria-label={nextLabel ?? $t('windows.carousel.next', [label])} aria-disabled={!hasNext}
      tabindex={hasNext || focused === 1 ? 0 : -1} onclick={event => move(event, 1)} onkeydown={keydown}
      onfocus={() => { focused = 1; read(); }} onblur={() => focused = null}>
      <svg viewBox="0 0 20 20" aria-hidden="true"><path d="m8 4 6 6-6 6" /></svg>
    </ControlButton>
  {/if}
</div>

<style>
  .horizontal-navigation { position:relative; width:100%; min-width:0; flex:1 1 auto; isolation:isolate; }
  .bypass { display:contents; }.fill { height:100%; min-height:0; }
  .horizontal-navigation :global(.horizontal-arrow.sideb-control) { position:absolute; z-index:3; top:var(--horizontal-center); transform:translateY(-50%); width:40px; height:40px; padding:0; border:0; border-radius:50%; background:none; box-shadow:none; backdrop-filter:none; -webkit-backdrop-filter:none; color:var(--control-foreground,#fff); }
  .horizontal-navigation :global(.horizontal-arrow::before) { content:''; position:absolute; inset:0; border:1px solid var(--control-border,#ffffff30); border-radius:50%; background:var(--sideb-surface-raised,#343438); box-shadow:0 3px 12px #0005; }
  .horizontal-navigation :global(.horizontal-arrow .sideb-control-content) { position:relative; }
  .horizontal-navigation :global(.horizontal-arrow svg) { width:20px; height:20px; fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
  .horizontal-navigation :global(.horizontal-arrow.previous) { left:6px; }.horizontal-navigation :global(.horizontal-arrow.next) { right:6px; }
  .horizontal-navigation:dir(rtl) :global(.horizontal-arrow.previous) { left:auto; right:6px; }
  .horizontal-navigation:dir(rtl) :global(.horizontal-arrow.next) { right:auto; left:6px; }
  .horizontal-navigation:dir(rtl) :global(.horizontal-arrow svg) { transform:rotate(180deg); }
  .horizontal-navigation :global(.horizontal-arrow:hover::before) { background:var(--control-hover,#45454b); }
  .horizontal-navigation :global(.horizontal-arrow[aria-disabled=true]) { opacity:.5; cursor:default; }
  .horizontal-navigation :global(.horizontal-arrow.hidden) { visibility:hidden; pointer-events:none; }
  .small :global(.horizontal-arrow::before) { inset:4px; }.small :global(.horizontal-arrow svg) { width:16px; height:16px; }
  @media(pointer:coarse) { .horizontal-navigation :global(.horizontal-arrow.sideb-control) { width:44px; height:44px; } }
  @media(forced-colors:active) {
    .horizontal-navigation :global(.horizontal-arrow.sideb-control) { color:ButtonText; }
    .horizontal-navigation :global(.horizontal-arrow::before) { background:ButtonFace; border-color:ButtonText; box-shadow:none; }
    .horizontal-navigation :global(.horizontal-arrow[aria-disabled=true]) { color:GrayText; opacity:1; }
  }
</style>
