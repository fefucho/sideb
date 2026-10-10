<script lang="ts">
  import type { HomeItemDto } from '$lib/types';
  import MediaCard from '../common/MediaCard.svelte';
  import { normalizeHomeSongCard } from '$lib/home/songMetadata';
  export let item: HomeItemDto;
  export let onOpenAlbum: ((id:string)=>void)|undefined=undefined;
  export let onOpenPlaylist: ((id:string)=>void)|undefined=undefined;
  export let onOpenArtist: ((id:string)=>void)|undefined=undefined;
  export let onPlaySong: ((item:HomeItemDto)=>void)|undefined=undefined;
  function open(){if(item.kind==='artist')onOpenArtist?.(item.id);else if(item.kind==='album')onOpenAlbum?.(item.id);else onOpenPlaylist?.(item.id);}
  $: songCard = normalizeHomeSongCard(item);
</script>
<div class="home-card"><MediaCard card={songCard} onOpen={open} onPlay={()=>onPlaySong?.(songCard)} {onOpenArtist} {onOpenAlbum} /></div>
<style>.home-card {width:var(--home-card-artwork-size,160px);flex:none;} @container home-content (width<760px){.home-card{width:var(--home-card-artwork-size-narrow,140px);}}</style>
