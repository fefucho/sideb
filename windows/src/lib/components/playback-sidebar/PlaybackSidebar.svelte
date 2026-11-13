<script lang="ts">
  import { onDestroy, onMount, type ComponentProps, type Snippet } from 'svelte';
  import ControlSegments from '$lib/components/common/ControlSegments.svelte';
  import PlayerIcon from '$lib/components/player/PlayerIcon.svelte';
  import { t } from '$lib/i18n';
  import type { PlaybackStateDto } from '$lib/types';
  import type { LyricsState } from '$lib/player/lyrics';
  import { sidebarLyricsPreviewEnabled } from '$lib/player/sidebarPreferences';
  import { SidebarPaletteController, neutralSidebarPalette, sidebarPaletteCss } from '$lib/player/sidebarPalette';
  import {
    SIDEBAR, footerHeight, panelSurface, progressToTransportSpacing, showsUpcoming, sidebarWidth, surfaceTransform,
    type SidebarPanel,
  } from '$lib/player/playbackPresentation';
  import SidebarArtwork from './SidebarArtwork.svelte';
  import SidebarLyricsPreview from './SidebarLyricsPreview.svelte';
  import SidebarRecommendations from './SidebarRecommendations.svelte';
  import SidebarTrackMetadata from './SidebarTrackMetadata.svelte';
  import SidebarUpcomingQueue from './SidebarUpcomingQueue.svelte';
  import { readable } from 'svelte/store';
  import { emptyJamState } from '$lib/jam/types';
  import { useJamUi } from '$lib/components/jam/context';
  import { isJamLive } from '$lib/components/jam/view';

  type LyricsMode = 'synced' | 'genius';
  interface Props {
    session: number;
    playback: PlaybackStateDto;
    /** The shared player controls (same actions and state as the bottom bar) in their vertical footer form. */
    controls: Snippet<[Snippet | undefined, Snippet | undefined, number | null]>;
    panel: SidebarPanel;
    onSelectPanel: (panel: SidebarPanel) => void;
    lyricsMode: LyricsMode;
    onLyricsMode: (mode: LyricsMode) => void;
    /** Shared transition progress: 0 = bar, 1 = this panel. */
    progress: number;
    reduced?: boolean;
    width?: number;
    /** False while the panel is retiring, covered by the search modal or otherwise not the active surface. */
    interactive?: boolean;
    onClose: () => void;
    onExpand: () => void;
    /** Existing queue / lyrics hosts of the fullscreen player; the shell never duplicates their engines. */
    queueBody: Snippet;
    lyricsBody: Snippet<[LyricsMode]>;
    /** Page state the contents need; callbacks are the page's own handlers (nothing is stored here). */
    lyricsState: LyricsState;
    onSelectQueue: (queueIndex: number) => void;
    metadataProps: Omit<ComponentProps<typeof SidebarTrackMetadata>, 'session' | 'playback'>;
    recommendationsProps: Omit<ComponentProps<typeof SidebarRecommendations>, 'session' | 'playback' | 'heroHeight' | 'initialOffset' | 'occurrenceId' | 'onScrollOffset'>;
  }
  let { session, playback, controls, panel, onSelectPanel, lyricsMode, onLyricsMode, progress, reduced = false, width = SIDEBAR.idealWidth, interactive = true, onClose, onExpand, queueBody, lyricsBody, lyricsState, onSelectQueue, metadataProps, recommendationsProps }: Props = $props();

  let closeButton = $state<HTMLButtonElement>();
  let height = $state(0);
  // Portrait artwork is reported by the artwork host (W4); the square layout is the default.
  let isPortrait = $state(false);

  const surface = $derived(panelSurface(progress, reduced));
  const panelWidth = $derived(sidebarWidth(width));
  const footer = $derived(Math.round(footerHeight(height, panel, isPortrait, panelWidth)));
  const upcoming = $derived(showsUpcoming(height, panel, isPortrait));
  const spacing = $derived(panel === 'artwork' && !isPortrait ? progressToTransportSpacing(height) : null);
  // One palette for the whole panel (as the macOS scene): background, hero and header scrim follow the cover.
  let palette = $state(neutralSidebarPalette);
  let reduceTransparency = $state(false), increasedContrast = $state(false);
  const paletteController = new SidebarPaletteController(next => { palette = next; });
  $effect(() => { void paletteController.update(playback.currentTrack?.thumbnail ?? null); });
  const surfaceCss = $derived(sidebarPaletteCss(palette, { reduceTransparency, increasedContrast }));
  // The hero and its recommendation feed share one scroll owner (the feed); the offset fades/suspends the hero.
  let feedOffset = $state(0), heroHeight = $state(0);
  // Recommendations (and their fetching) are off while a Jam owns the queue.
  const jamState = (useJamUi()?.state ?? readable(emptyJamState()));
  const jamLive = $derived(isJamLive($jamState));
  const occurrence = $derived(playback.queue.items[playback.queue.currentIndex ?? -1]?.entryId ?? null);

  const sections = $derived<{ id: SidebarPanel; label: string }[]>([
    { id: 'lyrics', label: $t('fullscreen.lyrics') },
    { id: 'artwork', label: $t('playbackSidebar.nowPlaying') },
    { id: 'queue', label: $t('queue.title') },
  ]);

  // Opening moves focus into the panel (its first control); closing returns it to the trigger in the shell.
  onMount(() => {
    if (interactive) closeButton?.focus({ preventScroll: true });
    const media = [matchMedia('(prefers-reduced-transparency: reduce)'), matchMedia('(prefers-contrast: more)')];
    const sync = () => { reduceTransparency = media[0].matches; increasedContrast = media[1].matches; };
    sync(); media.forEach(item => item.addEventListener('change', sync));
    return () => media.forEach(item => item.removeEventListener('change', sync));
  });
  onDestroy(() => paletteController.dispose());
</script>

<aside bind:clientHeight={height} id="playback-sidebar" class="playback-sidebar"
  aria-label={$t('windows.playbackSidebar.region')} inert={!interactive} aria-hidden={interactive ? undefined : 'true'}
  style:width={`${panelWidth}px`} style:opacity={surface.opacity} style:transform={surfaceTransform(surface)}
  data-panel={panel} style:--sidebar-surface={surfaceCss.background} style:--sidebar-top={surfaceCss.top}>

  <header class="header" style:height={`${SIDEBAR.headerHeight}px`} data-volume-excluded>
    <button bind:this={closeButton} type="button" class="icon-button" onclick={onClose}
      aria-label={$t('playbackSidebar.close')} title={$t('playbackSidebar.close')}>
      <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4.5" width="18" height="15" rx="3.5" /><path d="M3.5 14.5h17" /></svg>
    </button>
    <div class="segments">
      <ControlSegments appearance="toolbar" id="playback-sidebar-tab" panelId="playback-sidebar-body" label={$t('windows.playbackSidebar.sections')}
        options={sections} value={panel} onChange={onSelectPanel} collapseLabels>
        {#snippet icon(id)}
          {#if id === 'artwork'}
            <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>
          {:else}
            <PlayerIcon name={id} size={14} />
          {/if}
        {/snippet}
      </ControlSegments>
    </div>
    <button type="button" class="icon-button" onclick={onExpand}
      aria-label={$t('player.openFullscreen')} title={$t('player.openFullscreen')}>
      <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7" /></svg>
    </button>
  </header>

  <div id="playback-sidebar-body" class="body" role="tabpanel" aria-labelledby={`playback-sidebar-tab-${panel}`}
    style:padding-top={panel === 'artwork' ? '0' : `${SIDEBAR.headerHeight}px`}>
    {#if panel === 'lyrics'}
      <div class="lyrics-body">
        <div class="lyrics-source" role="group" aria-label={$t('windows.playbackSidebar.lyricsSource')}>
          {#each [['synced', $t('playbackSidebar.synced')], ['genius', 'Genius']] as [mode, label] (mode)}
            <button type="button" class="pill" class:selected={lyricsMode === mode} aria-pressed={lyricsMode === mode}
              onclick={() => onLyricsMode(mode as LyricsMode)}>{label}</button>
          {/each}
        </div>
        <div class="lyrics-host">{@render lyricsBody(lyricsMode)}</div>
      </div>
    {:else if panel === 'queue'}
      <div class="queue-host">{@render queueBody()}</div>
    {:else}
      <div class="artwork-area" bind:clientHeight={heroHeight}>
        <SidebarArtwork {session} {playback} scrollOffset={feedOffset} presented={interactive} active={panel === 'artwork'} {palette}
          onPortraitChange={portrait => isPortrait = portrait}>
          {#snippet metadata()}<SidebarTrackMetadata {session} {playback} {...metadataProps} />{/snippet}
        </SidebarArtwork>
        {#if !jamLive}
        <SidebarRecommendations {session} {playback} {heroHeight} initialOffset={feedOffset} occurrenceId={occurrence}
          onScrollOffset={offset => feedOffset = offset} {...recommendationsProps} />
        {/if}
      </div>
    {/if}
  </div>

  {#snippet lead()}
  {#if panel !== 'artwork'}<div class="lead"><SidebarTrackMetadata {session} {playback} {...metadataProps} /></div>{/if}
{/snippet}
{#snippet tail()}
  {#if upcoming}
    {#if $sidebarLyricsPreviewEnabled}
      <SidebarLyricsPreview {session} {playback} {lyricsState} active={interactive} onOpen={() => onSelectPanel('lyrics')} />
    {:else}
      <SidebarUpcomingQueue {session} {playback} {onSelectQueue} onOpenQueue={() => onSelectPanel('queue')} />
    {/if}
  {/if}
{/snippet}

<footer class="footer" style:height={`${footer}px`}>
    {@render controls(panel !== 'artwork' ? lead : undefined, upcoming ? tail : undefined, spacing)}
  </footer>
</aside>

<style>
  .playback-sidebar {
    position: fixed;
    z-index: 70;
    /* Only the native window buttons sit above the panel, also when the top navigation makes the strip taller. */
    top: calc(var(--playback-top, var(--titlebar-height, 32px)) + 6px);
    right: 6px;
    bottom: 6px;
    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    border-radius: 16px;
    color: #fff;
    background: var(--sidebar-surface, #1b1b1e);
    box-shadow: 0 6px 16px rgb(0 0 0 / 28%), inset 0 0 0 .5px rgb(255 255 255 / 12%);
    isolation: isolate;
    user-select: none;
  }
  .header { position: absolute; z-index: 3; top: 0; left: 0; right: 0; box-sizing: border-box; display: flex; align-items: center; gap: 6px; padding: 0 12px; background: linear-gradient(to bottom, rgb(0 0 0 / 22%), transparent); }
  .playback-sidebar[data-panel='artwork'] .header { background: linear-gradient(to bottom, rgb(0 0 0 / 34%), transparent); }
  /* Labels never fit in 350-420 px next to the two header buttons: the shared control collapses to icons (name and tooltip stay). */
  .segments { display: flex; flex: 1; justify-content: center; min-width: 0; container-type: inline-size; }
  .icon-button { display: grid; flex: none; place-items: center; width: 28px; height: 34px; padding: 0; border: 0; border-radius: 8px; color: rgb(255 255 255 / 92%); background: transparent; cursor: pointer; }
  .icon-button:hover { background: rgb(255 255 255 / 12%); }
  .icon-button svg { width: 20px; height: 20px; }
  .icon-button:focus-visible, .pill:focus-visible { outline: 2px solid #d06c70; outline-offset: 2px; }
  .artwork-area { position: absolute; inset: 0; }
  .body { position: relative; z-index: 1; box-sizing: border-box; flex: 1 1 0; min-height: 0; overflow: hidden; }
  .lyrics-body { display: flex; flex-direction: column; gap: 8px; height: 100%; min-height: 0; }
  .lyrics-source { display: flex; flex: none; gap: 4px; padding: 0 20px; }
  .pill { flex: 1; padding: 6px 0; border: 0; border-radius: 999px; color: inherit; background: transparent; font: inherit; font-size: 12px; font-weight: 500; cursor: pointer; }
  .pill.selected { background: rgb(255 255 255 / 15%); }
  .lyrics-host, .queue-host { display: flex; flex: 1; min-width: 0; min-height: 0; }
  /* The body is not a flex container: without its height the queue grows to its full length and is clipped instead of scrolling. */
  .queue-host { box-sizing: border-box; height: 100%; padding-inline: 12px; }
  .footer { position: relative; z-index: 2; flex: none; min-height: 0; overflow: hidden; }
  .lead { flex: none; margin-bottom: 16px; }

  /* Reduced transparency / high contrast (palette surfaces are already opaque): readable header instead of a scrim. */
  @media (prefers-reduced-transparency: reduce), (prefers-contrast: more) {
    .header, .playback-sidebar[data-panel='artwork'] .header { background: var(--sidebar-top, #1b1b1e); }
  }
  @media (forced-colors: active) {
    .playback-sidebar { color: CanvasText; background: Canvas; border: 1px solid CanvasText; box-shadow: none; }
  }
</style>
