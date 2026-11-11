<script lang="ts">
  /**
   * "Ahora suena" hero of the side player (macOS `NowPlayingSidebarArtwork`).
   *
   * Fills its parent (width/height 100%, measured) and draws: a square rounded poster card, or — only once a
   * portrait video frame is ready — the immersive tall video from the top edge with a faded bottom and a static
   * blurred backdrop. The poster is always shown first; the video replaces it after its first frame. Scroll only
   * changes the *transport policy* (pause + 30 s idle release); the <video> and its decode identity stay mounted.
   *
   * Props (W3 composes this file):
   * - `session`, `playback`: the usual FullscreenNowPlaying contract.
   * - `scrollOffset` (px, default 0): how far the owner of the vertical scroll moved the feed past the hero.
   * - `presented` (default true): the sidebar is open and not covered by fullscreen; false releases the video now.
   * - `active` (default true): the "Ahora suena" tab is the selected one; false suspends (pause + idle release).
   * - `palette`: shared sidebar palette. If omitted the component resolves its own from the cover.
   * - `metadata`: snippet drawn *anchored* at the geometry's metadata position (below the card, or over the
   *   bottom of an immersive video). Pass `<SidebarTrackMetadata …/>`. The slot is interactive; a feed stacked
   *   above the hero must let pointer events through where this slot sits.
   * - `onPortraitChange(portrait)`: fires when the cover becomes/stops being portrait, so the owner can hide
   *   "Up next" and recompute `sidebarFooterHeight(…, isPortrait)`.
   */
  import { onDestroy, onMount, untrack, type Snippet } from 'svelte';
  import { t } from '$lib/i18n';
  import type { PlaybackStateDto } from '$lib/types';
  import AnimatedArtwork from '$lib/components/fullscreen/AnimatedArtwork.svelte';
  import { animatedArtworkAlbumKey } from '$lib/artwork/policy';
  import { artworkCandidates, cardArtworkCandidates, nextArtworkUrl } from '$lib/images/artwork';
  import { heroScroll, sidebarArtworkGeometry, sidebarArtworkPresentation, sidebarMotionSuspended, type VideoSize } from '$lib/player/sidebarLayout';
  import { SidebarPaletteController, neutralSidebarPalette, rgbCss, sidebarTopSurface, type SidebarPalette } from '$lib/player/sidebarPalette';
  import { sidebarFeedTop } from '$lib/player/sidebarRecommendations';

  interface Props {
    session: number;
    playback: PlaybackStateDto;
    scrollOffset?: number;
    presented?: boolean;
    active?: boolean;
    palette?: SidebarPalette;
    metadata?: Snippet;
    onPortraitChange?: (portrait: boolean) => void;
  }
  let { session, playback, scrollOffset = 0, presented = true, active = true, palette, metadata, onPortraitChange }: Props = $props();

  let width = $state(0), height = $state(0);
  let reducedMotion = $state(false), reducedTransparency = $state(false);
  const track = $derived(playback.currentTrack);

  // Geometry belongs to the album/session identity: a new track of the same album reuses the resolved video
  // (and its orientation); a new album, account or orientation request discards it.
  const geometryKey = $derived(`${session}\u0000${animatedArtworkAlbumKey(track)}`);
  let ready = $state<(VideoSize & { key: string }) | null>(null);
  const readySize = $derived(ready && ready.key === geometryKey ? ready : null);
  const presentation = $derived(sidebarArtworkPresentation(readySize, reducedMotion));
  const geometry = $derived(sidebarArtworkGeometry(width, height, presentation.tall));
  const scroll = $derived(heroScroll(scrollOffset, height));
  // The recommendations sheet rises over this hero (macOS: metadata fixed *behind* the feed, FIX-282). Once its top edge
  // passes the metadata's bottom the block is hidden by the sheet, so it must not keep receiving clicks or focus.
  const metadataCovered = $derived(sidebarFeedTop(height, scrollOffset) < geometry.metadataTop + 68);
  const suspended = $derived(sidebarMotionSuspended({ panelActive: active, scroll, reducedMotion }));

  // Poster candidates follow the fullscreen policy (original → max quality → 544 px → provider URL).
  const trackKey = $derived(track ? `${track.videoId}\u0000${track.thumbnail ?? ''}` : '');
  let failures = $state<{ key: string; urls: string[] }>({ key: '', urls: [] });
  const posterUrl = $derived(nextArtworkUrl(artworkCandidates(track?.thumbnail), failures.key === trackKey ? failures.urls : []));
  const blurUrl = $derived(cardArtworkCandidates(track?.thumbnail, 96)[0] ?? null);
  function posterFailed(key: string, url: string) {
    if (key !== trackKey || url !== posterUrl) return;
    failures = { key, urls: [...new Set([...(failures.key === key ? failures.urls : []), url])] };
  }

  let ownPalette = $state<SidebarPalette>(neutralSidebarPalette);
  const paletteController = new SidebarPaletteController(next => { ownPalette = next; });
  $effect(() => {
    if (palette) return;
    const thumbnail = track?.thumbnail, account = session;
    untrack(() => { void account; void paletteController.update(thumbnail); });
  });
  const tint = $derived(rgbCss(sidebarTopSurface(palette ?? ownPalette, { reduceTransparency: reducedTransparency }), 0.28));

  let portraitReported = false;
  $effect(() => {
    const portrait = presentation.tall;
    untrack(() => { if (portrait !== portraitReported) { portraitReported = portrait; onPortraitChange?.(portrait); } });
  });

  onMount(() => {
    const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
    const transparency = window.matchMedia('(prefers-reduced-transparency: reduce)');
    const sync = () => { reducedMotion = motion.matches; reducedTransparency = transparency.matches; };
    sync();
    motion.addEventListener('change', sync); transparency.addEventListener('change', sync);
    return () => { motion.removeEventListener('change', sync); transparency.removeEventListener('change', sync); };
  });
  onDestroy(() => paletteController.dispose());
</script>

<div class="sidebar-artwork" bind:clientWidth={width} bind:clientHeight={height} role="img"
  aria-label={track ? `${$t('detail.track.artwork')}: ${track.title} — ${track.artists}` : $t('player.noPlayback')}>
  {#if presentation.tall && !reducedTransparency && blurUrl}
    <div class="backdrop" style:width="{geometry.width}px" style:height="{geometry.height}px" aria-hidden="true">
      <img src={blurUrl} alt="" decoding="async" draggable="false" />
      <span class="tint" style:background={tint}></span>
    </div>
  {/if}

  <!-- The immediate poster is always square; it yields only after the video confirms a displayable frame. -->
  <div class="poster" class:hidden={presentation.showVideo} aria-hidden="true"
    style:width="{geometry.cardSide}px" style:height="{geometry.cardSide}px" style:left="{(geometry.width - geometry.cardSide) / 2}px" style:top="{geometry.cardTop}px">
    {#if posterUrl && track}
      {#key `${trackKey}\u0000${posterUrl}`}
        <img src={posterUrl} alt="" decoding="async" draggable="false" onerror={() => posterFailed(trackKey, posterUrl)} />
      {/key}
    {:else}
      <svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>
    {/if}
  </div>

  <div class="video" class:tall={presentation.tall} class:shown={presentation.showVideo} aria-hidden="true"
    style:width="{geometry.videoWidth}px" style:height="{geometry.videoHeight}px" style:left="{(geometry.width - geometry.videoWidth) / 2}px" style:top="{geometry.videoTop}px">
    <AnimatedArtwork {track} {session} audioDuration={playback.duration}
      isPlaying={playback.isPlaying && !playback.isLoading} flipped={false}
      preferTall prepareWhilePaused {suspended} {presented} enabled={!reducedMotion} bottomFade={presentation.tall ? 0.32 : 0}
      onFirstFrame={size => { ready = { ...size, key: geometryKey }; }} onFrameUnavailable={() => { ready = null; }} />
  </div>

  {#if metadata}
    <div class="metadata" class:covered={metadataCovered} inert={metadataCovered} style:left="{(geometry.width - geometry.metadataWidth) / 2}px" style:top="{geometry.metadataTop}px" style:width="{geometry.metadataWidth}px">
      {@render metadata()}
    </div>
  {/if}
</div>

<style>
  .sidebar-artwork { position:relative; width:100%; height:100%; min-width:0; min-height:0; overflow:hidden; }
  .backdrop, .poster, .video { position:absolute; pointer-events:none; }
  .backdrop { left:0; top:0; overflow:hidden; -webkit-mask-image:linear-gradient(to bottom,#000 0%,#000 65%,transparent 100%); mask-image:linear-gradient(to bottom,#000 0%,#000 65%,transparent 100%); }
  .backdrop img { display:block; width:100%; height:100%; object-fit:cover; transform:scale(1.12); filter:blur(36px); }
  .tint { position:absolute; inset:0; }
  .poster { display:grid; place-items:center; overflow:hidden; border-radius:12px; color:rgb(255 255 255 / 30%); background:rgb(255 255 255 / 4%); opacity:1; transition:opacity 180ms ease-out; }
  .poster.hidden { opacity:0; }
  .poster img { display:block; width:100%; height:100%; object-fit:cover; }
  .poster svg { width:26%; max-width:80px; }
  .video { overflow:hidden; border-radius:12px; opacity:0; }
  .video.tall { border-radius:0; }
  .video.shown { opacity:1; }
  /* No z-index: the feed is a later sibling and must paint over the metadata (a z-index here lifted the title and the
     like/dislike buttons above the rising sheet, on top of its rows). */
  .metadata { position:absolute; height:68px; pointer-events:auto; }
  .metadata.covered { pointer-events:none; }
  @media (prefers-reduced-motion:reduce) { .poster { transition:none; } }
  @media (forced-colors:active) { .backdrop { display:none; } }
</style>
