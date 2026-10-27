<script lang="ts">
 import {getContext} from 'svelte';
 import {t} from '$lib/i18n';
 import type {SongDto} from '$lib/types';
 import {MEDIA_CONTEXT,type MediaService} from '$lib/player/media';
 import {createMenuHandlers} from '$lib/menu/hooks';
 import MediaArtwork from '../common/MediaArtwork.svelte';
 import FeaturedTrackTitle from '../FeaturedTrackTitle.svelte';
 import ArtistCredits from '../ArtistCredits.svelte';
 let {song,index,currentTrackId,isPlaying,onPlaySong,onOpenArtist,onOpenAlbum,onSongContextMenu}:{song:SongDto;index:number;currentTrackId:string|null;isPlaying:boolean;onPlaySong:(song:SongDto)=>void;onOpenArtist?:(id:string)=>void;onOpenAlbum?:(id:string)=>void;onSongContextMenu?:(event:MouseEvent,song:SongDto)=>void}=$props();
 const media=getContext<MediaService|undefined>(MEDIA_CONTEXT);
 const menu=createMenuHandlers()(()=>({kind:'song',song}),()=>({view:'recommendations'}));
 const active=$derived(currentTrackId===song.videoId);
 function activate(){if(active&&media)media.toggle();else onPlaySong(song);}
 function context(event:MouseEvent){if(onSongContextMenu)onSongContextMenu(event,song);else menu.onContextMenu(event);}
</script>
<article class="recommended-song media-card" class:active data-rec-song={index} oncontextmenu={context}>
 <button type="button" class="primary" aria-label={$t(active&&isPlaying?'home.pause_named':'home.play_named',[song.title])} onclick={activate} onkeydown={menu.onKeyDown}></button>
 <div class="art"><MediaArtwork thumbnail={song.thumbnail} title={song.title} {active} playing={active&&isPlaying} song onPlay={activate} onMenu={context}/></div>
 <div class="copy"><div class="title"><FeaturedTrackTitle track={song} {onOpenArtist} onPlay={activate}/></div><div class="credits"><ArtistCredits track={song} artistRuns={song.artistRuns} artists={song.artists} artistId={song.artistId} {onOpenArtist} album={song.album} albumId={song.albumId} {onOpenAlbum}/></div></div>
</article>
<style>.recommended-song{position:relative;isolation:isolate;box-sizing:border-box;display:flex;align-items:center;gap:10px;height:52px;padding:4px 6px;border:0;border-radius:8px;min-width:0}.recommended-song:hover{background:#ffffff17}.recommended-song.active{background:var(--sideb-active-row-background,#ffffff12);box-shadow:inset 0 0 0 1px var(--sideb-active-row-border,#ffffff18)}.primary{position:absolute;inset:0;z-index:-1;width:100%;border:0;border-radius:8px;background:transparent;cursor:pointer}.primary:focus-visible{outline:2px solid var(--sideb-highlight,#d06c70);outline-offset:-2px}.art{width:44px;height:44px;flex:none}.art :global(.artwork){border-radius:2px}.art :global(.play){width:28px;height:28px}.art :global(.menu){width:20px;height:20px;top:0;right:0}.copy{min-width:0;flex:1;pointer-events:none}.copy :global(button),.copy :global(a){pointer-events:auto}.title{font-size:12.5px;line-height:16px;font-weight:500;color:#fffffff2;overflow:hidden;white-space:nowrap}.credits{margin-top:2px;font-size:11px;line-height:14px;color:#ffffff8c;overflow:hidden;white-space:nowrap}</style>
