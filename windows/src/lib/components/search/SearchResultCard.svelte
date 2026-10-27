<script lang="ts">
  import type { BrowseCardDto } from '$lib/types';
  import MediaCard from '../common/MediaCard.svelte';
  interface Props {card:BrowseCardDto;size:'artist'|'album'|'playlist';filtered?:boolean;onActivate:()=>void}
  let {card,size,filtered=false,onActivate}:Props=$props();
</script>
<div class="result-card" class:filtered class:artist={size==='artist'}><MediaCard card={{...card,kind:size}} onOpen={onActivate}/></div>
<style>.result-card{width:180px;flex:none;} .filtered{width:100%;max-width:180px;}</style>
