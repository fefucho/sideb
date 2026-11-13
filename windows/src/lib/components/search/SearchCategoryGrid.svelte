<script lang="ts">
 import type {SongDto} from '$lib/types';
 import type {SearchSectionRow} from '$lib/search/provider-rows';
 import {GRID_ROWS, gridColumns} from '$lib/search/categories';
 import SearchSongRow from './SearchSongRow.svelte';
 interface Props {rows:SearchSectionRow[];label:string;currentTrackId:string|null;isPlaying:boolean;onPlaySong:(song:SongDto)=>void;onOpenArtist?:(id:string)=>void;openAlbumForSong:(song:SongDto,id:string)=>void}
 let {rows,label,currentTrackId,isPlaying,onPlaySong,onOpenArtist,openAlbumForSong}:Props=$props();
 let width=$state(1000);
 // The grid always has GRID_ROWS rows and is filled column by column; only the number of columns follows the width,
 // so its height never changes (Apple Music's song grid).
 const columns=$derived(gridColumns(width));
 const visible=$derived(rows.filter(row=>row.song).slice(0,columns*GRID_ROWS));
</script>
<div class="song-grid" role="group" aria-label={label} bind:clientWidth={width} style:--columns={columns}>
 {#each visible as row,index (`${row.itemIndex??'song'}:${row.songIndex??index}`)}{@const song=row.song!}
  <SearchSongRow {song} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={id=>openAlbumForSong(song,id)}/>
 {/each}
</div>
<style>
 .song-grid{display:grid;grid-auto-flow:column;grid-template-rows:repeat(3,58px);grid-template-columns:repeat(var(--columns,1),minmax(0,1fr));column-gap:24px;min-width:0;padding-bottom:8px}
</style>
