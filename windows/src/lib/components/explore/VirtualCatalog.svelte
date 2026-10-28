<script lang="ts">
  import {onMount,type Snippet} from 'svelte';
  import type {BrowseCardDto} from '$lib/types';
  import HorizontalNavigation from '../common/HorizontalNavigation.svelte';
  import {t} from '$lib/i18n';
  interface Props {items:BrowseCardDto[];children:Snippet<[BrowseCardDto]>;horizontal?:boolean;active?:boolean;scrollSelector?:string;rowExtra?:number}
  let {items,children,horizontal=false,active=true,scrollSelector='.explore-scroll',rowExtra=78}:Props=$props();
  let host:HTMLDivElement; let width=$state(800);let top=$state(0);let viewport=$state(600);let left=$state(0); let measure=()=>{};
  const gap=18; const columns=$derived(Math.max(1,Math.floor((width+gap)/178)));
  const cellWidth=$derived(horizontal?162:(width-gap*(columns-1))/columns);
  const rowHeight=$derived(cellWidth+rowExtra);
  const count=$derived(horizontal?items.length:Math.ceil(items.length/columns));
  const start=$derived(horizontal?Math.max(0,Math.floor(left/180)-1):Math.max(0,Math.floor(top/rowHeight)-1));
  const end=$derived(Math.min(count,horizontal?Math.ceil((left+width)/180)+1:Math.ceil((top+viewport)/rowHeight)+1));
  const visible=$derived(items.slice(horizontal?start:start*columns,horizontal?end:end*columns));
  $effect(()=>{items;horizontal;active;if(active){const frame=requestAnimationFrame(()=>measure());return()=>cancelAnimationFrame(frame);}});
  let mounted=$state(false);
  onMount(()=>{mounted=true;});
  $effect(()=>{
    if(!mounted||!active)return;
    // bind:this is cleared before every teardown path has finished. Keep the
    // subscribed node, so removal/aborted mounts cannot leave a resize listener.
    const element=host,root=element.closest<HTMLElement>(scrollSelector);
    const sync=()=>{if(!active||!element.isConnected)return;const rect=element.getBoundingClientRect();const boundary=root?.getBoundingClientRect();width=element.clientWidth||800;top=Math.max(0,(boundary?.top??0)-rect.top);viewport=root?.clientHeight??window.innerHeight;left=element.scrollLeft;};
    measure=sync;sync();root?.addEventListener('scroll',sync,{passive:true});element.addEventListener('scroll',sync,{passive:true});window.addEventListener('resize',sync);
    const observer=new ResizeObserver(sync);observer.observe(element);if(root)observer.observe(root);
    return()=>{measure=()=>{};observer.disconnect();root?.removeEventListener('scroll',sync);element.removeEventListener('scroll',sync);window.removeEventListener('resize',sync);};
  });
</script>
<HorizontalNavigation enabled={horizontal} {active} label={$t('explore.section.new_albums_singles')} stride={180} center="81px">
<div class="viewport" data-horizontal-scroll={horizontal?true:undefined} class:horizontal class:suspended={!active} bind:this={host} inert={!active}>
  <div class="canvas" style:height={`${horizontal?240:count*rowHeight}px`} style:width={horizontal?`${count*180}px`:'100%'}>
    {#each visible as item,index (`${item.kind}:${item.id}`)}
      {@const ordinal=(horizontal?start:start*columns)+index}
      <div class="cell" style:width={`${cellWidth}px`} style:left={`${horizontal?ordinal*180:(ordinal%columns)*(cellWidth+gap)}px`} style:top={`${horizontal?0:Math.floor(ordinal/columns)*rowHeight}px`}>
        {@render children(item)}
      </div>
    {/each}
  </div>
</div>
</HorizontalNavigation>
<style>.viewport{width:100%;min-width:0;}.horizontal{overflow-x:auto;scrollbar-width:thin;}.canvas{position:relative;}.cell{position:absolute;}.suspended :global(*){animation-play-state:paused!important;}</style>
