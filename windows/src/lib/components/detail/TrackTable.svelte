<script lang="ts">
  import type { SongDto } from "$lib/types";
  import ArtistCredits from "$lib/components/ArtistCredits.svelte";
  import type { MenuOrigin } from "$lib/menu/types";
  import { createMenuHandlers } from "$lib/menu/hooks";
  interface Props {
    items: SongDto[]; currentTrackId: string | null; isPlaying: boolean;
    onPlay: (index: number) => void; onOpenArtist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void; hideAlbumColumn?: boolean; numbered?: boolean; flush?: boolean; origin?: MenuOrigin;
  }
  let { items, currentTrackId, isPlaying, onPlay, onOpenArtist, onOpenAlbum, hideAlbumColumn = false, numbered = true, flush = false, origin = {} }: Props = $props();
  const createMenu = createMenuHandlers();
  let failedImages = $state(new Set<number>());
  const hasAlbumColumn = $derived(!hideAlbumColumn && items.some((track) => Boolean(track.album)));
  function markImageFailed(index: number) { failedImages = new Set(failedImages).add(index); }
</script>

<div class="table-scroll" class:flush role="region" aria-label="Canciones">
  <table class:with-album={hasAlbumColumn}>
    <thead><tr><th class="index" scope="col">{#if numbered}#{/if}</th><th class="track-heading" scope="col">Título</th>{#if hasAlbumColumn}<th class="album-heading" scope="col">Álbum</th>{/if}<th class="duration" scope="col"><span class="sr-only">Duración</span>◷</th></tr></thead>
    <tbody>
      {#each items as track, index (track.videoId + ":" + index)}
        {@const active = currentTrackId === track.videoId}
        {@const menu = createMenu(() => ({ kind: 'song', song: track }), () => origin)}
        <tr class:active oncontextmenu={menu.onContextMenu}>
          <td class="index"><button type="button" class="row-play" aria-label={`Reproducir ${track.title}`} onclick={() => onPlay(index)}>{#if active && isPlaying}<span aria-hidden="true">♫</span>{:else if numbered}<span aria-hidden="true">{index + 1}</span>{:else}<span aria-hidden="true">▶</span>{/if}</button></td>
          <td class="track-cell">
            <div class="track-cell-content">
              {#if track.thumbnail && !failedImages.has(index)}<img class="cover" src={track.thumbnail} alt="" loading="lazy" onerror={() => markImageFailed(index)} />{:else}<div class="cover fallback" aria-hidden="true">♫</div>{/if}
              <div class="song-meta"><button class="song-title" type="button" onclick={() => onPlay(index)} onkeydown={menu.onKeyDown} title={track.title}>{track.title}</button>
                <div class="artist-line"><ArtistCredits artistRuns={track.artistRuns} artists={track.artists} artistId={track.artistId} {onOpenArtist} /></div>
              </div>
            </div>
          </td>
          {#if hasAlbumColumn}<td class="album-cell">{#if track.albumId && onOpenAlbum}<button type="button" class="metadata-link" onclick={() => onOpenAlbum!(track.albumId!)}>{track.album}</button>{:else}<span>{track.album}</span>{/if}</td>{/if}
          <td class="duration">{track.duration ?? "—"}</td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>

<style>
  .table-scroll { min-width: 0; overflow-x: auto; padding: 0 20px 0 16px; outline: none; }
  .table-scroll:focus-visible { box-shadow: inset 0 0 0 2px var(--sideb-highlight); }
  .table-scroll.flush { padding-inline: 0; }
  table { width: 100%; min-width: 430px; border-collapse: collapse; table-layout: fixed; color: #aaaab1; font-size: 12px; }
  table.with-album { min-width: 600px; }
  th { height: 32px; border-bottom: 1px solid rgb(255 255 255 / 9%); font-size: 11px; font-weight: 450; text-align: left; }
  td { box-sizing: border-box; height: 52px; border-bottom: 1px solid rgb(255 255 255 / 4%); vertical-align: middle; }
  tbody tr:hover { background: rgb(255 255 255 / 5%); }
  tbody tr.active .song-title { color: var(--sideb-highlight, #d06c70); font-weight: 650; }
  .index { width: 42px; text-align: center; }
  .row-play { width: 30px; height: 32px; border: 0; color: inherit; background: transparent; font: inherit; cursor: pointer; }
  .row-play:hover, .row-play:focus-visible, tr:hover .row-play { color: #fff; }
  .track-heading { padding-left: 8px; }
  .track-cell { min-width: 0; padding: 0 8px; }
  .track-cell-content { display: flex; width: 100%; min-width: 0; height: 50px; align-items: center; gap: 11px; }
  .cover { flex: none; width: 40px; height: 40px; border-radius: 6px; object-fit: cover; background: #303036; }
  .fallback { display: grid; place-items: center; color: #c9c9cf; font-size: 20px; }
  .song-meta { display: flex; min-width: 0; flex-direction: column; gap: 3px; }
  .song-title, .metadata-link { display: block; max-width: 100%; overflow: hidden; padding: 0; border: 0; color: #f2f2f4; background: none; font: inherit; text-align: left; text-overflow: ellipsis; white-space: nowrap; cursor: pointer; }
  .song-title { font-size: 13px; font-weight: 550; }
  .artist-line { display: flex; min-width: 0; align-items: center; gap: 5px; overflow: hidden; color: #a6a6ad; white-space: nowrap; }
  .metadata-link { display: inline; color: #aaaab1; font-size: 12px; }
  .metadata-link:hover { color: #fff; }
  .album-heading, .album-cell { width: 22%; padding: 0 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .duration { width: 70px; padding-right: 8px; text-align: right; font-variant-numeric: tabular-nums; }
  .sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0,0,0,0); white-space: nowrap; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 2px; }
</style>
