<script lang="ts">
  import { t } from '$lib/i18n';
  import { onMount } from 'svelte';
  let { title, active, playing, number, onPlay }: { title:string; active:boolean; playing:boolean; number?:number; onPlay:(event:MouseEvent)=>void } = $props();
  let root:HTMLButtonElement;let visible=$state(false);let awake=$state(false);
  onMount(()=>{
    const sync=()=>awake=!document.hidden&&document.hasFocus();sync();const observer=new IntersectionObserver(([entry])=>visible=entry.isIntersecting);observer.observe(root);
    document.addEventListener('visibilitychange',sync);window.addEventListener('focus',sync);window.addEventListener('blur',sync);
    return()=>{observer.disconnect();document.removeEventListener('visibilitychange',sync);window.removeEventListener('focus',sync);window.removeEventListener('blur',sync);};
  });
</script>
<button type="button" bind:this={root} aria-label={`${active&&playing?$t('player.pause'):$t('player.play')} ${title}`} onclick={onPlay}>
  <span class="idle" class:paused={active&&!playing}>{#if active}<span class="bars" class:moving={playing&&visible&&awake}>{#each [0,1,2,3] as i}<i style={`--i:${i}`}></i>{/each}</span>{:else}{number??'♪'}{/if}</span>
  <span class="control" aria-hidden="true">{active&&playing?'Ⅱ':'▶'}</span>
</button>
<style>
  button{position:relative;width:30px;height:32px;padding:0;border:0;border-radius:6px;color:inherit;background:transparent;font:inherit;cursor:pointer;}.control{display:none;color:white;font-size:13px;}.idle{display:grid;place-items:center;}.paused{opacity:.4;}
  :global(tr:hover) .control,button:focus-visible .control{display:block;}:global(tr:hover) .idle,button:focus-visible .idle{display:none;}button:focus-visible{outline:2px solid var(--sideb-highlight);outline-offset:2px;}
  .bars{display:flex;align-items:center;gap:2px;height:16px;}.bars i{width:2px;height:calc(8px + var(--i)*2px);border-radius:1px;background:white;}.moving i{animation:wave calc(1.48s + var(--i)*.1s) ease-in-out infinite alternate;animation-delay:calc(var(--i)*-.4s);}@keyframes wave{from{transform:scaleY(.35);}to{transform:scaleY(1);}}@media(prefers-reduced-motion:reduce){.moving i{animation:none;}}
</style>
