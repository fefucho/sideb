<script lang="ts">
  import type { BrowseCardDto } from '$lib/types';
  import MediaCard from '../common/MediaCard.svelte';
  interface Props {card:BrowseCardDto;size:'artist'|'album'|'playlist';filtered?:boolean;onActivate:()=>void}
  let {card,size,filtered=false,onActivate}:Props=$props();
</script>
<div class="result-card" class:filtered class:artist={size==='artist'}><MediaCard card={{...card,kind:size}} onOpen={onActivate}/></div>
<style>.result-card{width:144px;flex:none;} .artist{width:130px;} .filtered{width:100%;max-width:180px;}</style>
