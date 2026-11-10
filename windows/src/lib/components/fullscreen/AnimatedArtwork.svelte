<script lang="ts">
  import { onMount, tick, untrack } from 'svelte';
  import type { PlaybackTrackDto } from '$lib/types';
  import { appearance } from '$lib/appearance/preferences';
  import { cancelAnimatedArtwork, prepareAnimatedArtwork, animatedArtworkUrl, registerAnimatedArtworkRelease, animatedArtworkClearState, type AnimatedArtworkAsset, type AnimatedArtworkRequest } from '$lib/artwork/animated';
  import { acceptsArtworkFrameRate, acceptsArtworkVideo, animatedArtworkAlbumKey, animatedArtworkPrimaryArtist, isVisualProviderAsset } from '$lib/artwork/policy';
  import { onVisualProviderWillChange, prepareVisualProviderArtwork, releaseVisualProviderArtwork } from '$lib/visualProvider/api';
  import { resolveVisualArtwork } from '$lib/visualProvider/routing';
  import { visualProviderEnabled, visualProviderIdentitySalt } from '$lib/visualProvider/store';
  import { contentRating } from '$lib/contentRating';
  import { initialAnimatedArtworkRuntimeState, observeAnimatedArtworkRuntime } from '$lib/artwork/runtime';
  import { AnimatedArtworkController } from '$lib/artwork/controller';

  /**
   * Fullscreen uses only `track/session/isPlaying/flipped/enabled/audioDuration` (square video, as before).
   * The side player adds, all optional (macOS `AnimatedArtworkView` contract):
   * - `preferTall`: ask the core for the portrait (3:4) variant; it falls back to square, and either is accepted.
   *   Changing it counts as a new request (the previous orientation is released).
   * - `suspended`: scroll/idle/tab policy. Pauses and starts the 30 s idle release; the <video> stays mounted.
   * - `prepareWhilePaused`: resolve and show the first frame even while audio is paused.
   * - `presented`: false (sidebar closed/covered) releases the video immediately.
   * - `bottomFade`: 0…1 height fraction faded to transparent at the bottom (portrait cover).
   * - `onFirstFrame` / `onFrameUnavailable`: the revealed frame size, and its release (poster must take over).
   *
   * Optional visual provider (PLAN-023 W6): Apple is always asked first. Only an instance with `preferTall` (the
   * sidebar's vertical player) may fall back to the provider — when it is enabled and Apple returned nothing or
   * failed (`resolveVisualArtwork`). Fullscreen never reaches it, and provider changes never unmount its player.
   * With the provider enabled the sidebar identity is per track (`identitySalt`), so a provider video is never
   * shared across songs of one album and a configuration change re-requests. The provider file is leased by request
   * id and released with the video; `visual-provider-will-change` drops the `src` before files disappear.
   */
  interface Props {
    track: PlaybackTrackDto | null; session: number; isPlaying: boolean; flipped: boolean; enabled?: boolean; audioDuration?: number | null;
    preferTall?: boolean; suspended?: boolean; prepareWhilePaused?: boolean; presented?: boolean; bottomFade?: number;
    onFirstFrame?: (size: { width: number; height: number }) => void; onFrameUnavailable?: () => void;
  }
  let { track, session, isPlaying, flipped, enabled = true, audioDuration, preferTall = false, suspended = false, prepareWhilePaused = false, presented = true, bottomFade = 0, onFirstFrame, onFrameUnavailable }: Props = $props();
  let video = $state<HTMLVideoElement>();
  let reduced = $state(false);
  let visible = $state(false);
  let runtime = $state(initialAnimatedArtworkRuntimeState);
  let source = $state<{ url: string; id: string; asset: AnimatedArtworkAsset } | null>(null);
  let ready = $state(false);
  let hasFrame = $state(false);
  let frameCancel: (() => void) | undefined;
  let frameReported = false;
  // Only the vertical player may use the provider (Mac `preferTall`), and then only while it is enabled.
  const providerEnabled = $derived(preferTall && $visualProviderEnabled);
  const providerSalt = $derived(providerEnabled ? $visualProviderIdentitySalt : null);
  const albumKey = $derived(`${session}\u0000${animatedArtworkAlbumKey(track, providerSalt)}\u0000${preferTall ? 'tall' : 'square'}`);
  const preferenceEnabled = $derived(enabled && presented && $appearance.animatedArtwork);
  const nativeVisible = $derived(runtime.visible && !runtime.minimized && !runtime.cloaked);
  const resourceAllowed = $derived(!runtime.powerSaver && !runtime.memoryPressure);
  const surfaceEligible = $derived(!flipped && !reduced && visible && nativeVisible && resourceAllowed && !suspended);
  // Resolving (fetch + first frame) may precede playing when the owner asks for a paused cover.
  const canResolve = $derived(surfaceEligible && (isPlaying || prepareWhilePaused));
  const canPlay = $derived(surfaceEligible && isPlaying);
  const fadeMask = $derived.by(() => {
    const fade = Math.min(1, Math.max(0, Number.isFinite(bottomFade) ? bottomFade : 0));
    if (fade <= 0) return undefined;
    const start = 1 - fade, at = (fraction: number) => `${Math.round((start + (1 - start) * fraction) * 1000) / 10}%`;
    return `linear-gradient(to bottom, #000 0%, #000 ${at(0)}, rgb(0 0 0 / .88) ${at(.3)}, rgb(0 0 0 / .45) ${at(.7)}, transparent 100%)`;
  });

  function detachVideo() {
    frameCancel?.(); frameCancel = undefined; ready = false; hasFrame = false;
    if (video) { video.pause(); video.removeAttribute('src'); video.load(); }
    if (frameReported) { frameReported = false; onFrameUnavailable?.(); }
  }
  // Requests that reached the provider (lease to release) and the abort handles of in-flight ones.
  const providerLeases = new Set<string>();
  const aborts = new Map<string, AbortController>();
  function prepare(request: AnimatedArtworkRequest, id: string): Promise<AnimatedArtworkAsset | null> {
    const abort = new AbortController(); aborts.set(id, abort);
    const extensionEnabled = providerEnabled;
    return resolveVisualArtwork<AnimatedArtworkAsset>({
      verticalPlayer: !!request.preferTall, extensionEnabled, signal: abort.signal,
      primary: () => prepareAnimatedArtwork(request, id),
      secondary: () => { providerLeases.add(id); return prepareVisualProviderArtwork(request, id); },
    }).finally(() => aborts.delete(id));
  }
  async function cancel(id: string) {
    aborts.get(id)?.abort();
    const provider = providerLeases.delete(id);
    await Promise.all([cancelAnimatedArtwork(id), provider ? releaseVisualProviderArtwork(id).catch(() => {}) : undefined]);
  }
  const controller = new AnimatedArtworkController<AnimatedArtworkRequest, AnimatedArtworkAsset>({
    isClearing: animatedArtworkClearState,
    prepare, cancel,
    id: () => `animated-artwork-${crypto.randomUUID()}`,
    publish: (asset, id) => {
      detachVideo();
      source = asset && id ? { url: animatedArtworkUrl(asset), id, asset } : null;
    },
    detach: async () => { detachVideo(); await tick(); },
  });

  onMount(() => {
    const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
    const updateMotion = () => reduced = motion.matches;
    const updateVisibility = () => visible = !document.hidden;
    updateMotion(); updateVisibility();
    motion.addEventListener('change', updateMotion);
    document.addEventListener('visibilitychange', updateVisibility);
    const stopRuntime = observeAnimatedArtworkRuntime(state => runtime = state);
    const unregister = registerAnimatedArtworkRelease(() => controller.clear());
    // Drop the provider's `src` synchronously before the host releases its files, then ask again.
    let stopProvider: (() => void) | undefined, disposed = false;
    void onVisualProviderWillChange(() => { if (preferTall && (providerLeases.size > 0 || isVisualProviderAsset(source?.asset.assetId))) void controller.refresh().catch(() => {}); })
      .then(stop => { if (disposed) stop(); else stopProvider = stop; }).catch(() => {});
    return () => {
      disposed = true; stopProvider?.();
      unregister(); motion.removeEventListener('change', updateMotion);
      document.removeEventListener('visibilitychange', updateVisibility);
      stopRuntime();
      void controller.dispose().catch(() => {});
    };
  });

  $effect(() => {
    const currentTrack = track;
    const trackDuration = currentTrack?.duration;
    const duration = typeof trackDuration === 'number' && Number.isFinite(trackDuration) && trackDuration > 0 ? trackDuration : audioDuration;
    const request: AnimatedArtworkRequest | null = currentTrack ? {
      videoId: currentTrack.videoId, title: currentTrack.title, artists: animatedArtworkPrimaryArtist(currentTrack),
      album: currentTrack.album ?? null, albumId: currentTrack.albumId ?? null,
      durationSecs: typeof duration === 'number' && Number.isFinite(duration) && duration > 0 ? Math.max(1, Math.round(duration)) : null,
      storefront: 'us', preferHevc: false, preferTall,
      ...(preferTall && currentTrack ? { explicit: contentRating(currentTrack) === 'explicit' ? true : null } : {}),
    } : null;
    const key = albumKey; const enabledNow = preferenceEnabled && !reduced && resourceAllowed;
    const eligible = canResolve;
    const hasAlbumIdentity = !!(request?.albumId?.trim() || request?.album?.trim());
    const metadataKey = JSON.stringify([request?.albumId, request?.album?.trim().toLowerCase(), request?.artists.trim().toLowerCase(),
      ...(hasAlbumIdentity ? [] : [request?.title.trim().toLowerCase(), request?.durationSecs])]);
    untrack(() => controller.update(key, request, enabledNow, eligible, metadataKey));
  });

  $effect(() => {
    const current = source; const element = video; const playing = canPlay;
    if (!current || !element) return;
    if (!playing) { element.pause(); return; }
    // pause()/load() can reject an older play promise after this source resumes.
    // Only the currently eligible attempt may classify that rejection as failure.
    let interrupted = false;
    void element.play().catch(() => {
      if (!interrupted && canPlay && source === current && video === element) void controller.fail().catch(() => {});
    });
    return () => { interrupted = true; };
  });

  $effect(() => {
    // Match the Mac presentation contract: retain a late first frame during
    // pause/flip/hidden, but begin its fade only when the surface becomes eligible.
    if (source && canResolve && hasFrame) ready = true;
  });
  $effect(() => {
    if (!source || !ready || !video) return;
    const size = { width: video.videoWidth, height: video.videoHeight };
    untrack(() => { frameReported = true; onFirstFrame?.(size); });
  });

  // One cancellable startup deadline, including a player that never emits loadeddata.
  $effect(() => {
    const current = source;
    if (!current || !canResolve || ready) return;
    const timeout = setTimeout(() => { if (source === current) void controller.fail().catch(() => {}); }, 8000);
    return () => clearTimeout(timeout);
  });

  function validMetadata(element: HTMLVideoElement, asset: AnimatedArtworkAsset) {
    return acceptsArtworkVideo({ width: element.videoWidth, height: element.videoHeight }, asset, preferTall)
      && Number.isFinite(element.duration) && element.duration > 0 && element.duration <= 60
      && acceptsArtworkFrameRate(asset.frameRate, asset.assetId)
      && /^(avc1|h264)/i.test(asset.codec);
  }
  function loadedData(event: Event) {
    const element = event.currentTarget as HTMLVideoElement;
    const current = source;
    if (!current || element !== video) return;
    if (!validMetadata(element, current.asset)) { void controller.fail().catch(() => {}); return; }
    frameCancel?.();
    let cancelled = false; let callbackId: number | undefined; let raf: number | undefined;
    const frameVideo = element as HTMLVideoElement & {
      requestVideoFrameCallback?: (callback: () => void) => number;
      cancelVideoFrameCallback?: (id: number) => void;
    };
    const isCurrent = () => !cancelled && source === current && video === element && element.getAttribute('src') === current.url;
    let pausedFallback: ReturnType<typeof setTimeout> | undefined;
    frameCancel = () => {
      cancelled = true;
      if (callbackId !== undefined) frameVideo.cancelVideoFrameCallback?.(callbackId);
      if (raf !== undefined) cancelAnimationFrame(raf);
      if (pausedFallback !== undefined) clearTimeout(pausedFallback);
    };
    const reveal = () => {
      if (!isCurrent()) return;
      hasFrame = true;
    };
    if (frameVideo.requestVideoFrameCallback) callbackId = frameVideo.requestVideoFrameCallback(reveal);
    else raf = requestAnimationFrame(() => {
      if (isCurrent() && element.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) reveal();
    });
    // A paused cover may have presented its only frame before the callback was registered.
    if (prepareWhilePaused && element.paused) {
      pausedFallback = setTimeout(() => { if (isCurrent() && element.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) reveal(); }, 300);
    }
  }
</script>

{#if source}
  {#key source.id}
    <video bind:this={video} class="motion" class:shown={ready} style:mask-image={fadeMask} style:-webkit-mask-image={fadeMask} src={source.url} muted loop playsinline aria-hidden="true" tabindex="-1" preload="auto"
      onloadeddata={loadedData} onerror={event => { if (event.currentTarget === video) void controller.fail().catch(() => {}); }}></video>
  {/key}
{/if}

<style>
  .motion { position:absolute; inset:0; width:100%; height:100%; object-fit:cover; border-radius:inherit; opacity:0; pointer-events:none; transition:opacity 225ms ease; }
  .motion.shown { opacity:1; }
  @media(prefers-reduced-motion:reduce) { .motion { transition:none; } }
</style>
