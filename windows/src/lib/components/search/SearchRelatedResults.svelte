<script lang="ts">
 import {t} from '$lib/i18n';
 import type {SearchSectionDto,SongDto,BrowseCardDto,AlbumCardDto} from '$lib/types';
 import type {SearchSectionRow} from '$lib/search/provider-rows';
 import ControlButton from '$lib/components/common/ControlButton.svelte';
 import SearchSongRow from './SearchSongRow.svelte';
 import MediaCard from '../common/MediaCard.svelte';
 import SearchResultCard from './SearchResultCard.svelte';
 interface Props {rows:SearchSectionRow[];section:SearchSectionDto;currentTrackId:string|null;isPlaying:boolean;onPlaySong:(song:SongDto)=>void;onOpenArtist?:(id:string)=>void;onOpenAlbum:(album:AlbumCardDto)=>void;onOpenPlaylist?:(id:string)=>void;openCard:(card:BrowseCardDto)=>void;openAlbumForSong:(song:SongDto,id:string)=>void;expanded?:boolean;onExpandedChange?:(value:boolean)=>void}
 let {rows,section,currentTrackId,isPlaying,onPlaySong,onOpenArtist,onOpenAlbum,onOpenPlaylist,openCard,openAlbumForSong,expanded=$bindable(false),onExpandedChange}:Props=$props();
 const visible=$derived(expanded?rows:rows.slice(0,3));
 function activate(card:BrowseCardDto){if(card.kind==='artist')onOpenArtist?.(card.id);else if(card.kind==='album')onOpenAlbum({id:card.id,title:card.title,subtitle:card.subtitle,thumbnail:card.thumbnail});else if(card.kind==='playlist')onOpenPlaylist?.(card.id);else openCard(card);}
</script>
{#if rows.length}<aside class="related" aria-label={$t('search.provider.related')}>
 <h3>{$t('search.provider.related')}</h3>
 <div class="related-list">
 {#each visible as row,index (`${row.itemIndex??'song'}:${index}`)}
  {#if row.song}{@const song=row.song}<SearchSongRow {song} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={id=>openAlbumForSong(song,id)}/>
  {:else if row.card}{@const card=row.card}{#if section.layout==='carousel'}<SearchResultCard {card} size={card.kind==='artist'?'artist':card.kind==='playlist'?'playlist':'album'} onActivate={()=>activate(card)}/>{:else}<MediaCard {card} layout="compact" onOpen={()=>activate(card)} {onOpenArtist} onOpenAlbum={id=>onOpenAlbum({id,title:card.album??'',subtitle:card.artists??null,thumbnail:card.thumbnail})}/>{/if}{/if}
 {/each}
 </div>
 {#if rows.length>3}<ControlButton emphasis="quiet" size="utility" type="button" onclick={()=>{expanded=!expanded;onExpandedChange?.(expanded);}}>{$t(expanded?'search.provider.hide_related':'search.provider.show_related',[rows.length])}</ControlButton>{/if}
</aside>{/if}
<style>
 .related{min-width:0;display:flex;flex-direction:column;gap:4px}.related h3{margin:0 0 2px;color:#aaa;font-size:13px;font-weight:600}.related-list{display:flex;min-width:0;flex-direction:column;gap:0}
 .related :global(.song-row){min-height:58px;padding:7px 8px}.related :global(.play){width:44px;height:44px}
</style>
