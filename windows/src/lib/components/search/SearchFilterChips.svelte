<script lang="ts">
 import {onMount} from 'svelte';
 import {t} from '$lib/i18n';
 import type {SearchChipDto} from '$lib/types';
 import ControlFilter from '../common/ControlFilter.svelte';
 let {chips,disabled=false,active=true,onSelect}: {chips:SearchChipDto[];disabled?:boolean;active?:boolean;onSelect:(params:string|null)=>void}=$props();
 let nav=$state<HTMLElement>();
 let strip=$state<HTMLDivElement>();
 let mounted=$state(false);
 let leading=$state(false),trailing=$state(false);
 let measure=()=>{};
 onMount(()=>{mounted=true;});
 $effect(()=>{
  if(!active||!mounted||!nav||!strip)return;
  const element=nav,content=strip;
  const update=()=>{leading=element.scrollLeft>.5;trailing=element.scrollLeft+element.clientWidth<element.scrollWidth-.5;};
  measure=update;
  const observer=new ResizeObserver(update);observer.observe(element);observer.observe(content);
  element.addEventListener('scroll',update,{passive:true});update();
  return ()=>{observer.disconnect();element.removeEventListener('scroll',update);measure=()=>{};};
 });
 $effect(()=>{chips;active;if(active)queueMicrotask(()=>measure());});
</script>
{#if chips.length}
 <nav class="mode-tabs" class:fade-leading={leading} class:fade-trailing={trailing} bind:this={nav} aria-label={$t('search.title')}>
  <div class="chip-strip" bind:this={strip}>
   {#each chips as chip,index (`${chip.id}:${index}`)}
    <ControlFilter selected={chip.selected} type="button" {disabled} onclick={()=>onSelect(chip.params)}>{chip.title}</ControlFilter>
   {/each}
  </div>
 </nav>
{/if}
<style>
 .mode-tabs{--leading-edge:#000;--trailing-edge:#000;box-sizing:border-box;width:100%;min-width:0;overflow-x:auto;scrollbar-width:none;mask-image:linear-gradient(to right,var(--leading-edge),#000 24px,#000 calc(100% - 24px),var(--trailing-edge));}
 .mode-tabs::-webkit-scrollbar{display:none;}
 .fade-leading{--leading-edge:transparent;}.fade-trailing{--trailing-edge:transparent;}
 .chip-strip{display:flex;width:max-content;min-width:100%;align-items:center;gap:var(--control-category-gap);padding:4px 0;}
</style>
