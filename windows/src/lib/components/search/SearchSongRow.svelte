<script lang="ts">
  import type { SongDto } from '$lib/types';
  import ArtistCredits from '$lib/components/ArtistCredits.svelte';
  import { createMenuHandlers } from '$lib/menu/hooks';

  interface Props {
    song: SongDto;
    currentTrackId: string | null;
    isPlaying: boolean;
    onPlay: (song: SongDto) => void;
    onOpenArtist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void;
    showVideo?: boolean;
  }

  let { song, currentTrackId, isPlaying, onPlay, onOpenArtist, onOpenAlbum, showVideo = false }: Props = $props();
  const createMenu = createMenuHandlers();
  const menu = createMenu(() => ({ kind: 'song', song }), { view: 'search_results' });
  const active = $derived(currentTrackId === song.videoId);
</script>

<div class="song-row" class:active role="group" aria-label={`Opciones de ${song.title}`} oncontextmenu={menu.onContextMenu}>
  <button class="artwork" type="button" aria-label={`Reproducir ${song.title}`} onclick={() => onPlay(song)} onkeydown={menu.onKeyDown}>
    {#if song.thumbnail}<img src={song.thumbnail} alt="" loading="lazy" />{:else}<span aria-hidden="true">♫</span>{/if}
  </button>
  <div class="song-copy">
    <button class="song-title" type="button" title={song.title} onclick={() => onPlay(song)} onkeydown={menu.onKeyDown}>{song.title}</button>
    <div class="credits"><ArtistCredits artistRuns={song.artistRuns} artists={song.artists} artistId={song.artistId} {onOpenArtist} album={song.album} albumId={song.albumId} {onOpenAlbum} /></div>
  </div>
  <div class="song-meta">
    {#if active && isPlaying}<span class="playing">SONANDO</span>{/if}
    {#if showVideo || song.isVideo}<span class="tag">VIDEO</span>{/if}
    {#if song.duration}<span class="duration">{song.duration}</span>{/if}
  </div>
</div>

<style>
  .song-row { box-sizing:border-box; display:flex; width:100%; min-width:0; min-height:52px; align-items:center; gap:12px; padding:6px 10px; border-radius:8px; color:#f3f3f5; }
  .song-row:hover { background:rgb(255 255 255 / 6%); }
  .song-row.active .song-title { color:var(--sideb-highlight, #d06c70); font-weight:650; }
  .artwork { position:relative; display:grid; width:40px; height:40px; flex:none; place-items:center; overflow:hidden; padding:0; border:0; border-radius:6px; background:rgb(255 255 255 / 7%); color:rgb(255 255 255 / 55%); font-size:19px; cursor:pointer; }
  .artwork img { width:100%; height:100%; object-fit:cover; }
  .song-copy { display:flex; min-width:0; flex:1; flex-direction:column; gap:2px; }
  .song-title { display:block; max-width:100%; overflow:hidden; padding:0; border:0; background:transparent; color:#f4f4f6; font:inherit; font-size:13px; font-weight:500; text-align:left; text-overflow:ellipsis; white-space:nowrap; cursor:pointer; }
  .song-title:hover { color:#fff; }
  .credits { min-width:0; overflow:hidden; color:rgb(255 255 255 / 59%); font-size:11px; line-height:15px; }
  .song-meta { display:flex; flex:none; align-items:center; gap:7px; }
  .duration { color:rgb(255 255 255 / 48%); font-size:11px; font-variant-numeric:tabular-nums; }
  .tag,.playing { display:inline-flex; align-items:center; padding:2px 5px; border-radius:4px; background:rgb(255 255 255 / 10%); color:rgb(255 255 255 / 68%); font-size:9px; font-weight:700; }
  .playing { background:rgb(208 108 112 / 18%); color:#ef9da0; }
  button:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:2px; }
</style>
