<script lang="ts">
  import type { Snippet } from 'svelte';
  import { t } from '$lib/i18n';
  import { barSurface, interactiveSurfaces, surfaceTransform, type PlaybackMode } from '$lib/player/playbackPresentation';

  interface Props {
    mode: PlaybackMode;
    /** Shared transition progress: 0 = bar, 1 = lateral panel. */
    progress: number;
    reduced?: boolean;
    /** The search modal sits above everything; the dock is inert while it is open. */
    modalOpen?: boolean;
    onToggleSidebar: () => void;
    children: Snippet;
  }
  let { mode, progress, reduced = false, modalOpen = false, onToggleSidebar, children }: Props = $props();

  let trigger = $state<HTMLButtonElement>();
  const surface = $derived(barSurface(progress, reduced));
  // The retiring surface is inert from the first frame; no timer decides when it stops listening.
  const interactive = $derived(interactiveSurfaces(mode).bar && !modalOpen);
  const hidden = $derived(!interactiveSurfaces(mode).bar);

  /** Returns focus to the outer trigger after the panel closes (only if focus was inside or lost). */
  export function focusTrigger() {
    const active = document.activeElement;
    const panel = document.getElementById('playback-sidebar');
    if (!trigger || (active && active !== document.body && !panel?.contains(active))) return;
    trigger.focus({ preventScroll: true });
  }
</script>

<div class="player-dock" inert={!interactive} aria-hidden={hidden ? 'true' : undefined}
  style:opacity={surface.opacity} style:transform={surfaceTransform(surface)}>
  <div class="dock-bar">{@render children()}</div>
  <button bind:this={trigger} type="button" class="sidebar-trigger" aria-expanded={mode === 'sidebar'} aria-controls="playback-sidebar"
    aria-label={$t('playbackSidebar.open')} title={$t('playbackSidebar.open')} onclick={onToggleSidebar}>
    <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4.5" width="18" height="15" rx="3.5" /><path d="M14.5 4.5v15" /><path d="M17 8.5h1.5M17 11h1.5M17 13.5h1.5" /></svg>
  </button>
</div>

<style>
  /* Symmetric room on both sides keeps the bar centered in the content column while the outer
     trigger sits at the window's trailing margin: 20 margin + 44 button + 16 gap. */
  .player-dock {
    position: fixed;
    z-index: 100;
    left: var(--sidebar-width, 0px);
    right: 0;
    bottom: 20px;
    box-sizing: border-box;
    display: flex;
    justify-content: center;
    padding-inline: 80px;
    /* No will-change: an opacity/transform group would become the backdrop root and flatten the acrylic. */
    pointer-events: none;
  }
  .dock-bar { display: flex; justify-content: center; width: 100%; min-width: 0; }
  .player-dock :global(.player-bar) { pointer-events: auto; }
  .sidebar-trigger {
    position: absolute;
    right: 20px;
    bottom: 15px;
    display: grid;
    place-items: center;
    box-sizing: border-box;
    width: 44px;
    height: 44px;
    padding: 0;
    border: 1px solid var(--sideb-acrylic-border, rgb(255 255 255 / 20%));
    border-radius: 50%;
    color: #f2f2f4;
    background: var(--sideb-acrylic-fallback, #353538);
    box-shadow: 0 8px 24px rgb(0 0 0 / 34%);
    cursor: pointer;
    pointer-events: auto;
    transition: background-color var(--control-transition, 120ms ease), color var(--control-transition, 120ms ease);
  }
  @supports ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
    .sidebar-trigger { background: var(--sideb-acrylic-surface); backdrop-filter: var(--sideb-acrylic-blur); -webkit-backdrop-filter: var(--sideb-acrylic-blur); }
  }
  .sidebar-trigger:hover { color: #fff; background-color: rgb(255 255 255 / 14%); }
  .sidebar-trigger:focus-visible { outline: 2px solid #d06c70; outline-offset: 3px; }
  .sidebar-trigger svg { width: 22px; height: 22px; }
  @media (prefers-reduced-motion: reduce) { .sidebar-trigger { transition: none; } }
  @media (forced-colors: active) {
    .sidebar-trigger { color: ButtonText; background: ButtonFace; border-color: ButtonText; backdrop-filter: none; -webkit-backdrop-filter: none; }
  }
</style>
