<script lang="ts">
  import { nextArtworkUrl, rejectArtworkAttempt, type ArtworkFailures } from '$lib/images/artwork';
  import { fullscreenBackdropCandidates } from './backdrop';

  let { thumbnail, trackKey }: { thumbnail: string | null | undefined; trackKey: string } = $props();
  const candidates = $derived(fullscreenBackdropCandidates(thumbnail));
  const requestKey = $derived(JSON.stringify([trackKey, candidates]));
  let failures = $state<ArtworkFailures>({ key: '', urls: [] });
  let loadedAttempt = $state('');
  const selectedUrl = $derived(nextArtworkUrl(candidates, failures.key === requestKey ? failures.urls : []));
  const attemptKey = $derived(JSON.stringify([requestKey, selectedUrl]));

  function reject(key: string, url: string) {
    failures = rejectArtworkAttempt(failures, requestKey, candidates, key, url);
  }
  function loaded(key: string, url: string) {
    if (key === requestKey && url === selectedUrl) loadedAttempt = JSON.stringify([key, url]);
  }
</script>

{#snippet artworkAttempt(key: string, url: string)}
  <img src={url} alt="" decoding="async" draggable="false" onload={() => loaded(key, url)} onerror={() => reject(key, url)} />
{/snippet}

<!-- Static artwork, no palette extraction, animation or RAF while hidden/awake.
     Apple order: aspectFill → scale 1.4 → blur 75 → black 72%. -->
<div class="fullscreen-backdrop" class:missing={!thumbnail} aria-hidden="true">
  {#if selectedUrl}
    <div class="art-layer" class:loaded={loadedAttempt === attemptKey}>
      {#key attemptKey}{@render artworkAttempt(requestKey, selectedUrl)}{/key}
    </div>
    {#if loadedAttempt === attemptKey}<div class="shade"></div>{/if}
  {/if}
</div>

<style>
  /* Keep artwork sampling window-sized as Apple does, even though Windows clips
     the visible canvas at its sidebar. Foreground reservation stays independent. */
  .fullscreen-backdrop { position: absolute; inset: 0; left: calc(-1 * var(--sidebar-width, 0px)); width: 100vw; z-index: -1; overflow: hidden; pointer-events: none; background: #1b1b1e; }
  .missing { background: linear-gradient(180deg, rgb(7% 7% 8%), #1b1b1e); }
  .art-layer { position: absolute; inset: 0; filter: blur(75px); opacity: 0; }
  .art-layer.loaded { opacity: 1; }
  img { display: block; width: 100%; height: 100%; object-fit: cover; object-position: center; transform: scale(1.4); }
  .shade { position: absolute; inset: 0; background: rgb(0 0 0 / 72%); }
</style>
