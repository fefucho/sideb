<script lang="ts">
  import { onMount } from 'svelte';
  import { t } from '$lib/i18n';
  import type { KaraokeGap } from '$lib/player/karaoke';
  import type { KaraokeClock } from '$lib/player/karaoke-clock';
  let {gap,index,clock,offset,animate}:{gap:KaraokeGap;index:number;clock:KaraokeClock;offset:number;animate:boolean}=$props();
  let host:HTMLDivElement;let dots:HTMLSpanElement[]=[];let visible=false;let stop:(()=>void)|undefined;
  function paint(ms:number){
    ms+=offset;const current=ms>=gap.start&&ms<gap.end;host.classList.toggle('current',current);
    const progress=Math.min(1,Math.max(0,(ms-gap.start)/(gap.end-gap.start)));
    for(let i=0;i<dots.length;i++)dots[i].style.opacity=String(animate?Math.min(1,Math.max(.25,progress*3-i)):.4);
    return visible&&animate&&current;
  }
  onMount(()=>{
    const observer=typeof IntersectionObserver==='undefined'?null:new IntersectionObserver(entries=>{visible=entries[0]?.isIntersecting??false;stop?.();stop=visible?clock.subscribe(paint):undefined;});
    observer?.observe(host);if(!observer){visible=true;stop=clock.subscribe(paint);}
    return()=>{observer?.disconnect();stop?.();};
  });
</script>
<div class="wait" bind:this={host} data-gap={index} aria-label={$t(`lyrics.experimental.wait.${gap.kind}`)}><span bind:this={dots[0]}>•</span><span bind:this={dots[1]}>•</span><span bind:this={dots[2]}>•</span></div>
<style>.wait{display:flex;gap:7px;font-size:var(--size);height:1.25em;padding:10px 0;opacity:.4;}.wait:global(.current){opacity:1;}.wait span{display:block;}</style>
