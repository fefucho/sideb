<script lang="ts">
 import {t} from '$lib/i18n';
 import type {SearchChipDto} from '$lib/types';
 import ControlFilter from '../common/ControlFilter.svelte';
 import HorizontalNavigation from '../common/HorizontalNavigation.svelte';
 let {chips,disabled=false,active=true,onSelect}: {chips:SearchChipDto[];disabled?:boolean;active?:boolean;onSelect:(params:string|null)=>void}=$props();
</script>
{#if chips.length}
 <HorizontalNavigation {active} small label={$t('search.title')} items=".chip-strip > button">
 <nav class="mode-tabs" data-horizontal-scroll aria-label={$t('search.title')}>
  <div class="chip-strip">
   {#each chips as chip,index (`${chip.id}:${index}`)}
    <ControlFilter selected={chip.selected} type="button" {disabled} onclick={()=>onSelect(chip.params)}>{chip.title}</ControlFilter>
   {/each}
  </div>
 </nav>
 </HorizontalNavigation>
{/if}
<style>
 .mode-tabs{box-sizing:border-box;width:100%;min-width:0;overflow-x:auto;scrollbar-width:none;}
 .mode-tabs::-webkit-scrollbar{display:none;}
 .chip-strip{display:flex;width:max-content;min-width:100%;align-items:center;gap:var(--control-category-gap);padding:4px 0;}
</style>
