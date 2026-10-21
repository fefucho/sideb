<script lang="ts">
  import { onMount, tick, untrack } from 'svelte';
  import type { PlaybackTrackDto } from '$lib/types';
  import { appearance } from '$lib/appearance/preferences';
  import { cancelAnimatedArtwork, prepareAnimatedArtwork, animatedArtworkUrl, registerAnimatedArtworkRelease, animatedArtworkClearState, type AnimatedArtworkAsset, type AnimatedArtworkRequest } from '$lib/artwork/animated';
  import { animatedArtworkAlbumKey, animatedArtworkPrimaryArtist } from '$lib/artwork/policy';
  import { initialAnimatedArtworkRuntimeState, observeAnimatedArtworkRuntime } from '$lib/artwork/runtime';
  import { AnimatedArtworkController } from '$lib/artwork/controller';

  let { track, session, isPlaying, flipped, enabled = true, audioDuration }: { track: PlaybackTrackDto | null; session: number; isPlaying: boolean; flipped: boolean; enabled?: boolean; audioDuration?: number | null } = $props();
  let video = $state<HTMLVideoElement>();
  let reduced = $state(false);
  let visible = $state(false);
  let runtime = $state(initialAnimatedArtworkRuntimeState);
  let source = $state<{ url: string; id: string; asset: AnimatedArtworkAsset } | null>(null);
  let ready = $state(false);
  let frameCancel: (() => void) | undefined;
  const albumKey = $derived(`${session}\u0000${animatedArtworkAlbumKey(track)}`);
  const preferenceEnabled = $derived(enabled && $appearance.animatedArtwork);
  const nativeVisible = $derived(runtime.visible && !runtime.minimized && !runtime.cloaked);
  const resourceAllowed = $derived(!runtime.powerSaver && !runtime.memoryPressure);
  const canPlay = $derived(isPlaying && !flipped && !reduced && visible && nativeVisible && resourceAllowed);

  function detachVideo() {
    frameCancel?.(); frameCancel = undefined; ready = false;
    if (video) { video.pause(); video.removeAttribute('src'); video.load(); }
  }
  const controller = new AnimatedArtworkController<AnimatedArtworkRequest, AnimatedArtworkAsset>({
    isClearing: animatedArtworkClearState,
    prepare: prepareAnimatedArtwork, cancel: cancelAnimatedArtwork,
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
    return () => {
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
      storefront: 'us', preferHevc: false,
    } : null;
    const key = albumKey; const enabledNow = preferenceEnabled && !reduced && resourceAllowed;
    const eligible = canPlay;
    const hasAlbumIdentity = !!(request?.albumId?.trim() || request?.album?.trim());
    const metadataKey = JSON.stringify([request?.albumId, request?.album?.trim().toLowerCase(), request?.artists.trim().toLowerCase(),
      ...(hasAlbumIdentity ? [] : [request?.title.trim().toLowerCase(), request?.durationSecs])]);
    untrack(() => controller.update(key, request, enabledNow, eligible, metadataKey));
  });

  $effect(() => {
    const current = source; const element = video; const playing = canPlay;
    if (!current || !element) return;
    if (!playing) { element.pause(); return; }
    void element.play().catch(() => { if (source === current && video === element) void controller.fail().catch(() => {}); });
  });

  // One cancellable startup deadline, including a player that never emits loadeddata.
  $effect(() => {
    const current = source;
    if (!current || !canPlay || ready) return;
    const timeout = setTimeout(() => { if (source === current) void controller.fail().catch(() => {}); }, 8000);
    return () => clearTimeout(timeout);
  });

  function validMetadata(element: HTMLVideoElement, asset: AnimatedArtworkAsset) {
    return element.videoWidth > 0 && element.videoWidth === element.videoHeight && element.videoWidth <= 1080
      && Number.isFinite(element.duration) && element.duration > 0 && element.duration <= 60
      && asset.width === element.videoWidth && asset.height === element.videoHeight
      && Number.isFinite(asset.frameRate) && asset.frameRate > 0 && asset.frameRate <= 60
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
    frameCancel = () => {
      cancelled = true;
      if (callbackId !== undefined) frameVideo.cancelVideoFrameCallback?.(callbackId);
      if (raf !== undefined) cancelAnimationFrame(raf);
    };
    const reveal = () => {
      if (!isCurrent()) return;
      ready = true;
    };
    if (frameVideo.requestVideoFrameCallback) callbackId = frameVideo.requestVideoFrameCallback(reveal);
    else raf = requestAnimationFrame(() => {
      if (isCurrent() && element.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) reveal();
    });
  }
</script>

{#if source}
  {#key source.id}
    <video bind:this={video} class="motion" class:shown={ready} src={source.url} muted loop playsinline aria-hidden="true" tabindex="-1" preload="auto"
      onloadeddata={loadedData} onerror={event => { if (event.currentTarget === video) void controller.fail().catch(() => {}); }}></video>
  {/key}
{/if}

<style>
  .motion { position:absolute; inset:0; width:100%; height:100%; object-fit:cover; border-radius:inherit; opacity:0; pointer-events:none; transition:opacity 225ms ease; }
  .motion.shown { opacity:1; }
  @media(prefers-reduced-motion:reduce) { .motion { transition:none; } }
</style>
