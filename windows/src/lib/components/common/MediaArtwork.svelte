<script lang="ts">
  import { t } from '$lib/i18n';
  import MoreIcon from '$lib/components/common/MoreIcon.svelte';
  import { getContext, onMount } from 'svelte';
  import { PRESENTATION_CONTEXT, type PresentationService } from './presentation';
  import { cardArtworkCandidates, nextArtworkUrl, rejectArtworkAttempt, type ArtworkFailures } from '$lib/images/artwork';
  interface Props { thumbnail: string | null; title: string; active?: boolean; playing?: boolean; pending?: boolean; song?: boolean; round?: boolean; onPlay?: () => void; onMenu: (event: MouseEvent) => void }
  let { thumbnail, title, active = false, playing = false, pending = false, song = false, round = false, onPlay, onMenu }: Props = $props();
  let root = $state<HTMLDivElement>(); let visible = $state(false); let awake = $state(false);
  let imageSize = $state(160); let pixelRatio = $state(1); let failures = $state<ArtworkFailures>({key:'',urls:[]});
  const presentation = getContext<PresentationService | undefined>(PRESENTATION_CONTEXT);
  const foreground = $derived(presentation?.active(root) ?? true);
  const candidates = $derived(cardArtworkCandidates(thumbnail, imageSize, pixelRatio));
  const requestKey = $derived(JSON.stringify(candidates));
  const selectedUrl = $derived(nextArtworkUrl(candidates, failures.key === requestKey ? failures.urls : []));
  $effect(() => { if(failures.key !== requestKey)failures={key:requestKey,urls:[]}; });
  function reject(key: string, url: string) { failures = rejectArtworkAttempt(failures, requestKey, candidates, key, url); }
  function measure() { if (!foreground || !root) return; const width = root.getBoundingClientRect().width; if(width>0)imageSize=Math.ceil(width/32)*32; pixelRatio=window.devicePixelRatio || 1; }
  $effect(() => { if(foreground)measure(); });
  onMount(() => {
    const sync = () => awake = !document.hidden && document.hasFocus(); sync();
    const observer = new IntersectionObserver(([entry]) => visible = entry.isIntersecting);
    const resize = new ResizeObserver(measure); if(root)resize.observe(root); measure();
    if (root) observer.observe(root); document.addEventListener('visibilitychange', sync); window.addEventListener('focus', sync); window.addEventListener('blur', sync);
    return () => { observer.disconnect(); resize.disconnect(); document.removeEventListener('visibilitychange', sync); window.removeEventListener('focus', sync); window.removeEventListener('blur', sync); };
  });
</script>
{#snippet imageAttempt(key: string, url: string)}<img src={url} alt="" loading="lazy" decoding="async" onerror={() => reject(key, url)} />{/snippet}
<div class="artwork" class:round class:song class:active class:pending bind:this={root}>
  {#if selectedUrl}{#key `${requestKey}\u0000${selectedUrl}`}{@render imageAttempt(requestKey, selectedUrl)}{/key}{:else}<span class="fallback" aria-hidden="true">{round ? '♙' : '♫'}</span>{/if}
  {#if active}<span class="bars" class:moving={playing && visible && awake && foreground} class:paused={!playing} aria-label={playing ? $t('windows.ui.playingFromThisSource') : $t('windows.ui.sourcePaused')}>{#each [0,1,2,3,4] as bar}<i style={`--bar:${bar}`} ></i>{/each}</span>{/if}
  {#if onPlay}<button type="button" class="play" disabled={pending} aria-label={pending ? $t('home.loading_named', [title]) : active && playing ? $t('home.pause_named', [title]) : $t('home.play_named', [title])} onclick={onPlay}>
    {#if pending}<span class="spinner" aria-hidden="true"></span>{:else if active && playing}<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 5h4v14H7zm6 0h4v14h-4z"/></svg>{:else}<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m8 5 11 7-11 7z"/></svg>{/if}
  </button>{/if}
  <button type="button" class="menu" aria-label={$t('common.moreOptionsFor', [title])} onclick={onMenu}><MoreIcon /></button>
</div>
<style>
  .artwork { position:relative; width:100%; height:100%; aspect-ratio:1; border-radius:10px; overflow:hidden; background:var(--sideb-surface-hover); }
  .round { border-radius:50%; } img { width:100%; height:100%; object-fit:cover; } .fallback { display:grid; height:100%; place-items:center; font-size:30px; color:#aaa; }
  button { position:absolute; display:grid; place-items:center; border:0; color:white; background:#0009; cursor:pointer; opacity:0; pointer-events:none; transition:opacity .15s; }
  .play { right:8px; bottom:8px; width:32px; height:32px; border-radius:50%; } .song .play { top:50%; left:50%; right:auto; bottom:auto; transform:translate(-50%,-50%); }
  .menu { top:6px; right:6px; width:28px; height:28px; border-radius:7px; padding:0; }
  :global(.media-card:hover) button, :global(.media-card:focus-within) button, .artwork:focus-within button, .pending .play { opacity:1; pointer-events:auto; }
  .artwork:not(.song) .play:hover { background:var(--sideb-accent); } .menu:hover { background:#000c; } svg { width:18px; height:18px; fill:currentColor; }
  button:focus-visible { opacity:1; outline:2px solid white; outline-offset:-3px; } button:disabled { cursor:wait; }
  .bars { position:absolute; inset:0; display:flex; justify-content:center; align-items:center; gap:3px; background:#0005; pointer-events:none; }
  .bars i { width:3px; height:calc(12px + var(--bar) * 3px); max-height:40%; border-radius:2px; background:white; transform-origin:center; }
  .moving i { animation:wave calc(1.48s + var(--bar) * .09s) ease-in-out infinite alternate; animation-delay:calc(var(--bar) * -.37s); } .paused { opacity:.4; }
  :global(.media-card:hover) .bars, :global(.media-card:focus-within) .bars { opacity:0; }
  .spinner { width:14px; height:14px; border:2px solid #fff5; border-top-color:white; border-radius:50%; animation:spin .8s linear infinite; }
  @keyframes wave { from { transform:scaleY(.35); } to { transform:scaleY(1); } } @keyframes spin { to { transform:rotate(360deg); } }
  @media (prefers-reduced-motion:reduce) { .moving i,.spinner { animation:none; } button { transition:none; } }
</style>
