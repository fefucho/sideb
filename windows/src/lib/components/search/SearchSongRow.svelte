<script lang="ts">
  import {t} from '$lib/i18n';
 import type {SongDto} from '$lib/types';
 import {createMenuHandlers} from '$lib/menu/hooks';
 import ArtistCredits from '../ArtistCredits.svelte';
 import TrackActivity from '../common/TrackActivity.svelte';
 import MoreIcon from '../common/MoreIcon.svelte';
 interface Props {song:SongDto;currentTrackId?:string|null;isPlaying?:boolean;onPlay:(song:SongDto)=>void;onOpenArtist?:(id:string)=>void;onOpenAlbum?:(id:string)=>void;showVideo?:boolean}
 let {song,currentTrackId=null,isPlaying=false,onPlay,onOpenArtist,onOpenAlbum,showVideo=false}:Props=$props();
 const menu=createMenuHandlers()(()=>({kind:'song',song}),{view:'search_results'});
</script>
<article class="song-row" oncontextmenu={menu.onContextMenu}>
 <button type="button" class="play" onclick={()=>onPlay(song)} onkeydown={menu.onKeyDown} aria-label={$t('search.play_card',[song.title])}>
  {#if song.thumbnail}<img src={song.thumbnail} alt="" loading="lazy"/>{:else}<span aria-hidden="true">â™«</span>{/if}
  {#if currentTrackId===song.videoId}<span class="activity"><TrackActivity active playing={isPlaying}/></span>{/if}
 </button>
 <div class="copy"><button class="title" type="button" onclick={()=>onPlay(song)} onkeydown={menu.onKeyDown}>{song.title}</button><div class="credits"><ArtistCredits artistRuns={song.artistRuns} artists={song.artists} artistId={song.artistId} {onOpenArtist} album={song.album} albumId={song.albumId} {onOpenAlbum}/></div></div>
 {#if showVideo}<span class="duration">VIDEO</span>{/if}{#if song.duration}<span class="duration">{song.duration}</span>{/if}<button class="more" type="button" aria-label={`MÃ¡s opciones para ${song.title}`} onclick={menu.onContextMenu}><MoreIcon/></button>
</article>
<style>.song-row{display:flex;align-items:center;gap:10px;padding:6px 10px;min-width:0;border-radius:8px;}.song-row:hover{background:#ffffff0c;}.play{position:relative;display:grid;place-items:center;width:44px;height:44px;padding:0;flex:none;border:0;border-radius:6px;overflow:hidden;background:#ffffff0c;color:white;cursor:pointer;}.play img{height:100%;width:100%;object-fit:cover;}.activity{position:absolute;inset:0;display:grid;place-items:center;background:#0006;}.copy{min-width:0;flex:1;}.title{display:block;max-width:100%;text-align:left;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;border:0;background:transparent;color:inherit;font:inherit;font-size:13px;font-weight:600;padding:0;cursor:pointer;}.credits{font-size:11px;color:#aaa;margin-top:4px;overflow:hidden;white-space:nowrap;}.duration{font-size:11px;color:#aaa;}.more{display:grid;place-items:center;width:28px;height:28px;padding:0;border:0;border-radius:6px;background:transparent;color:white;cursor:pointer;}.more:hover{background:#ffffff18;}button:focus-visible{outline:2px solid var(--sideb-highlight);outline-offset:2px;}</style>
