<script lang="ts">
  import { getContext } from 'svelte';
  import { PRESENTATION_CONTEXT, type PresentationService } from './presentation';
  let { active, playing, number, awake = true, presentation = 'bars' }: { active: boolean; playing: boolean; number?: number; awake?: boolean; presentation?: 'bars' | 'queue' } = $props();
  let root = $state<HTMLSpanElement>();
  const presentationService = getContext<PresentationService | undefined>(PRESENTATION_CONTEXT);
  const foreground = $derived(presentationService?.active(root) ?? true);
</script>
<span class="track-activity" class:queue={presentation === 'queue'} class:active aria-hidden="true" bind:this={root}>
  {#if active && presentation === 'queue'}<svg class="speaker" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 9h4l6-5v16l-6-5H3Z" fill="currentColor" />{#if playing}<path d="M16 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" />{/if}</svg>
  {:else if active}<span class="bars" class:paused={!playing} class:moving={playing && awake && foreground}>{#each [0,1,2,3] as i}<i style={`--i:${i}`}></i>{/each}</span>
  {:else}{number ?? ''}{/if}
</span>
<style>
  .track-activity.queue { display: flex; justify-content: flex-end; font-size: 11.5px; }
  .track-activity.queue.active { justify-content: center; }
  .speaker { display: block; width: 12px; height: 12px; color: #fff; }
  .track-activity {display:grid;place-items:center;width:24px;font-size:12px;color:#aaaab1;font-variant-numeric:tabular-nums;}.bars {display:flex;align-items:center;gap:2px;height:16px;}.bars i {width:2px;height:calc(8px + var(--i)*2px);border-radius:1px;background:white;}.paused {opacity:.4;}.moving i {animation:wave calc(1.48s + var(--i)*.1s) ease-in-out infinite alternate;animation-delay:calc(var(--i)*-.4s);}@keyframes wave {from{transform:scaleY(.35);}to{transform:scaleY(1);}}@media(prefers-reduced-motion:reduce){.moving i{animation:none;}}
</style>
