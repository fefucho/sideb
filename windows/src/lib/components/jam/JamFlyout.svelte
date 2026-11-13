<script lang="ts">
  import { onMount, tick, type Snippet } from 'svelte';

  interface Props {
    /** The control that opened it: clicks on it do not count as "outside" and it gets the focus back on Escape. */
    anchor: HTMLElement | undefined;
    open: boolean;
    onClose: () => void;
    label: string;
    /** Side of the anchor the flyout opens on (the player bar is at the bottom, the sidebar badge at the top). */
    placement?: 'above' | 'below';
    width?: number;
    id?: string;
    children: Snippet;
  }
  let { anchor, open, onClose, label, placement = 'above', width = 340, id, children }: Props = $props();
  let flyout = $state<HTMLDivElement>();
  let box = $state<{ left: number; top?: number; bottom?: number; maxHeight: number }>({ left: 8, maxHeight: 480 });

  function place() {
    if (!anchor) return;
    const rect = anchor.getBoundingClientRect(), gap = 10, margin = 8;
    const left = Math.max(margin, Math.min(rect.right - width, window.innerWidth - width - margin));
    box = placement === 'above'
      ? { left, bottom: window.innerHeight - rect.top + gap, maxHeight: Math.max(160, rect.top - gap - margin) }
      : { left, top: rect.bottom + gap, maxHeight: Math.max(160, window.innerHeight - rect.bottom - gap - margin) };
  }
  // The flyout lives under <body>: the player bar, sidebar and fullscreen scene clip, transform or `inert` their children.
  function portal(node: HTMLElement) {
    document.body.appendChild(node);
    return { destroy: () => node.remove() };
  }
  function outside(event: PointerEvent) {
    if (!open || !(event.target instanceof Node)) return;
    if (flyout?.contains(event.target) || anchor?.contains(event.target)) return;
    onClose();
  }
  function keydown(event: KeyboardEvent) {
    if (!open || event.key !== 'Escape' || event.defaultPrevented) return;
    event.preventDefault(); event.stopPropagation();
    onClose();
    anchor?.focus({ preventScroll: true });
  }
  $effect(() => {
    if (!open) return;
    place();
    void tick().then(() => { place(); (flyout?.querySelector<HTMLElement>('[data-autofocus]') ?? flyout)?.focus({ preventScroll: true }); });
  });
  onMount(() => {
    window.addEventListener('resize', place);
    return () => window.removeEventListener('resize', place);
  });
</script>

<svelte:document onpointerdown={outside} onkeydown={keydown} />

{#if open}
  <div use:portal bind:this={flyout} {id} class="flyout" data-placement={placement} role="dialog" aria-label={label} tabindex="-1"
    style:left={`${box.left}px`} style:top={box.top === undefined ? undefined : `${box.top}px`} style:bottom={box.bottom === undefined ? undefined : `${box.bottom}px`}
    style:width={`${width}px`} style:max-height={`${box.maxHeight}px`}>
    {@render children()}
  </div>
{/if}

<style>
  .flyout:focus { outline: none; }
  .flyout { position: fixed; z-index: 800; box-sizing: border-box; max-width: calc(100vw - 16px); overflow-x: hidden; overflow-y: auto; border: 1px solid rgb(255 255 255 / 12%); border-radius: 14px; color: #f3f3f6; background: #29292f; box-shadow: 0 16px 44px rgb(0 0 0 / 50%); font-family: var(--sideb-font-family, inherit); overscroll-behavior: contain; scrollbar-width: thin; scrollbar-color: rgb(255 255 255 / 28%) transparent; user-select: none; }
  @media (forced-colors: active) { .flyout { color: CanvasText; background: Canvas; border-color: CanvasText; box-shadow: none; } }
</style>
