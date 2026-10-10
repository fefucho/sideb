<script lang="ts">
  import { t } from '$lib/i18n';
  import { onMount } from 'svelte';
  import { cardArtworkCandidates, nextArtworkUrl, rejectArtworkAttempt, type ArtworkFailures } from '$lib/images/artwork';
  let { title, thumbnail, active, playing, pending = false, size = 40, showPlayOverlay = true, onPlay }: {
    title: string; thumbnail: string | null; active: boolean; playing: boolean;
    pending?: boolean; size?: number; showPlayOverlay?: boolean; onPlay: (event: MouseEvent) => void;
  } = $props();
  let pixelRatio = $state(1); let failures = $state<ArtworkFailures>({key:'',urls:[]});
  const candidates = $derived(cardArtworkCandidates(thumbnail, size, pixelRatio));
  const requestKey = $derived(JSON.stringify(candidates));
  const selectedUrl = $derived(nextArtworkUrl(candidates, failures.key === requestKey ? failures.urls : []));
  $effect(() => { if(failures.key !== requestKey)failures={key:requestKey,urls:[]}; });
  function reject(key: string, url: string) { failures = rejectArtworkAttempt(failures, requestKey, candidates, key, url); }
  onMount(() => { const sync=()=>pixelRatio=window.devicePixelRatio||1;sync();window.addEventListener('resize',sync);return()=>window.removeEventListener('resize',sync); });
</script>
{#snippet imageAttempt(key: string, url: string)}<img src={url} alt="" loading="lazy" decoding="async" onerror={() => reject(key, url)} />{/snippet}

<button class="track-artwork" type="button" style={`--art-size:${size}px`} disabled={pending} aria-busy={pending}
  aria-label={`${pending ? $t('common.loading') : active && playing ? $t('player.pause') : $t('player.play')} ${title}`} onclick={onPlay}>
  {#if selectedUrl}{#key `${requestKey}\u0000${selectedUrl}`}{@render imageAttempt(requestKey, selectedUrl)}{/key}
  {:else}<span class="fallback" aria-hidden="true">♪</span>{/if}
  {#if showPlayOverlay}<span class="play-control" class:pending aria-hidden="true">
    {#if pending}<span class="spinner"></span>
    {:else if active && playing}<svg viewBox="0 0 20 20"><path d="M6 4h3v12H6zm5 0h3v12h-3z" fill="currentColor" /></svg>
    {:else}<svg viewBox="0 0 20 20"><path d="m7 4 9 6-9 6z" fill="currentColor" /></svg>{/if}
  </span>{/if}
</button>

<style>
  .track-artwork { display:grid; place-items:center; position:relative; flex:none; width:var(--art-size); height:var(--art-size); padding:0; border:0; border-radius:2px; overflow:hidden; background:#303036; color:white; cursor:pointer; }
  img,.fallback { width:100%;height:100%;grid-area:1/1;object-fit:cover; }.fallback { display:grid;place-items:center;color:#c9c9cf;font-size:20px; }
  .play-control { display:grid;place-items:center;grid-area:1/1;z-index:1;width:28px;height:28px;border-radius:7px;background:rgb(0 0 0 / 58%);opacity:0;transition:opacity .12s;pointer-events:none; }svg { width:18px;height:18px; }
  :global(.track-row:hover) .play-control,:global(.track-row:focus-within) .play-control,.track-artwork:hover .play-control,.track-artwork:focus-visible .play-control,.play-control.pending { opacity:1; }
  .track-artwork:focus-visible { outline:2px solid var(--sideb-highlight);outline-offset:2px; }.track-artwork:disabled { cursor:wait; }
  .spinner { width:14px;height:14px;border:2px solid #ffffff55;border-top-color:white;border-radius:50%;animation:spin .8s linear infinite; }@keyframes spin {to {transform:rotate(360deg);}}@media(prefers-reduced-motion:reduce){.play-control {transition:none;}.spinner {animation:none;}}
</style>
