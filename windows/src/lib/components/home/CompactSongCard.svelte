<script lang="ts">
  import type { HomeItemDto } from '$lib/types';
  import MediaCard from '../common/MediaCard.svelte';
  import { normalizeHomeSongCard } from '$lib/home/songMetadata';
  export let item:HomeItemDto;
  export let onPlaySong:((item:HomeItemDto)=>void)|undefined=undefined;
  export let onOpenArtist:((id:string)=>void)|undefined=undefined;
  export let onOpenAlbum:((id:string)=>void)|undefined=undefined;
  $: songCard = normalizeHomeSongCard(item);
</script>
<MediaCard card={songCard} layout="compact" onPlay={()=>onPlaySong?.(songCard)} {onOpenArtist} {onOpenAlbum} />
