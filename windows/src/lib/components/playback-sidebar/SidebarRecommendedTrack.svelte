<script lang="ts">
  /*
   * PLAN-023 W5 - one recommended song row of the sidebar feed (macOS: NativeQueueTrackCellView
   * with setSidebarRecommendationAppearance). Internal to SidebarRecommendations.
   *
   * Actions are ordered dislike - like - "+" (FIX-297). "+" takes the duration's slot while the row
   * is hovered/focused and adds to the END of the native queue through `onAddToQueue`; it never
   * edits queue state itself. The row click is a button under the content (z-index -1), so the
   * glass surface above can never swallow it (FIX-292).
   */
  import { t } from '$lib/i18n';
  import { createMenuHandlers } from '$lib/menu/hooks';
  import type { SongDto } from '$lib/types';
  import TrackArtwork from '../common/TrackArtwork.svelte';
  import FeaturedTrackTitle from '../FeaturedTrackTitle.svelte';
  import ArtistCredits from '../ArtistCredits.svelte';

  interface Props {
    id: string;
    index: number;
    song: SongDto;
    current: boolean;
    playing: boolean;
    loggedIn: boolean;
    liked: boolean;
    likePending: boolean;
    onActivate: (song: SongDto) => void;
    onAddToQueue: (song: SongDto) => void;
    onToggleLike?: (song: SongDto) => void;
    onDislike?: (song: SongDto) => void;
    onOpenArtist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void;
    onSongContextMenu?: (event: MouseEvent, song: SongDto) => void;
  }
  let { id, index, song, current, playing, loggedIn, liked, likePending, onActivate, onAddToQueue, onToggleLike, onDislike, onOpenArtist, onOpenAlbum, onSongContextMenu }: Props = $props();
  const menu = createMenuHandlers()(() => ({ kind: 'song', song }), () => ({ view: 'recommendations' }));
  const activate = () => onActivate(song);
  function context(event: MouseEvent) { if (onSongContextMenu) onSongContextMenu(event, song); else menu.onContextMenu(event); }
  const stop = (event: Event) => event.stopPropagation();
</script>

<article class="sb-rec-track" class:current data-sidebar-row={id} data-sidebar-track={index} oncontextmenu={context}>
  <button type="button" class="primary" aria-label={`${current && playing ? $t('player.pause') : $t('player.play')} ${song.title}`} aria-current={current ? 'true' : undefined} onclick={activate} onkeydown={menu.onKeyDown}></button>
  <TrackArtwork title={song.title} thumbnail={song.thumbnail} active={current} {playing} size={40} showPlayOverlay={false} onPlay={activate} />
  <div class="copy">
    <div class="title"><FeaturedTrackTitle track={song} {onOpenArtist} onPlay={activate} /></div>
    <div class="credits"><ArtistCredits track={song} artistRuns={song.artistRuns} artists={song.artists} artistId={song.artistId} {onOpenArtist} album={song.album} albumId={song.albumId} {onOpenAlbum} /></div>
  </div>
  <div class="actions">
    {#if loggedIn && onDislike}
      <button type="button" class="action dislike" data-sidebar-action="dislike" aria-label={$t('windows.sidebar.recommendationDislike', [song.title])} title={$t('windows.sidebar.recommendationDislike', [song.title])} onclick={event => { stop(event); onDislike?.(song); }}>
        <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4H3v10h4M7 13l4 7a2 2 0 0 0 3-2l-1-4h5a3 3 0 0 0 3-3l-2-5a3 3 0 0 0-3-2H7Z" /></svg>
      </button>
    {/if}
    {#if loggedIn && onToggleLike}
      <button type="button" class="action like" class:liked data-sidebar-action="like" aria-pressed={liked} disabled={likePending} aria-label={liked ? $t('windows.queue.unlike', [song.title]) : $t('windows.queue.like', [song.title])} title={likePending ? $t('windows.ui.updatingLike') : liked ? $t('windows.ui.removeLike') : $t('detail.track.like')} onclick={event => { stop(event); onToggleLike?.(song); }}>
        <svg viewBox="2 1.68 20 20" aria-hidden="true" fill={liked ? 'currentColor' : 'none'} stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 8.7c0 4.2-6.4 9.1-8.8 11-2.4-1.9-8.8-6.8-8.8-11a4.9 4.9 0 0 1 8.8-3.1 4.9 4.9 0 0 1 8.8 3.1Z" /></svg>
      </button>
    {/if}
    <span class="slot">
      <span class="duration">{song.duration ?? ''}</span>
      <button type="button" class="action add" data-sidebar-action="add" aria-label={$t('windows.queue.addEnd', [song.title])} title={$t('menu.add_to_queue')} onclick={event => { stop(event); onAddToQueue(song); }}>
        <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M5 12h14" /></svg>
      </button>
    </span>
  </div>
</article>

<style>
  .sb-rec-track { position: relative; isolation: isolate; box-sizing: border-box; display: flex; align-items: center; gap: 10px; height: 54px; padding: 7px 14px 7px 14px; margin-inline: 6px; border-radius: 8px; min-width: 0; color: #fff; }
  .sb-rec-track:hover, .sb-rec-track:focus-within { background: rgb(255 255 255 / 8%); }
  .sb-rec-track.current { background: rgb(255 255 255 / 11%); }
  .primary { position: absolute; inset: 0; z-index: -1; width: 100%; padding: 0; border: 0; border-radius: 8px; background: transparent; cursor: pointer; }
  .primary:focus-visible { outline: 2px solid var(--sideb-highlight, #d06c70); outline-offset: -2px; }
  .copy { min-width: 0; flex: 1; pointer-events: none; }
  .copy :global(button), .copy :global(a) { pointer-events: auto; }
  .title { overflow: hidden; white-space: nowrap; font-size: 13px; line-height: 17px; font-weight: 500; color: rgb(255 255 255 / 95%); }
  .credits { margin-top: 1px; overflow: hidden; white-space: nowrap; font-size: 11.5px; line-height: 15px; color: rgb(255 255 255 / 62%); }
  .credits :global(.artist-credits) { color: rgb(255 255 255 / 62%); }
  .actions { flex: none; display: flex; align-items: center; gap: 6px; }
  .action { display: grid; place-items: center; width: 22px; height: 22px; padding: 0; border: 0; border-radius: 6px; background: transparent; color: rgb(255 255 255 / 65%); cursor: pointer; }
  .action svg { width: 13px; height: 13px; }
  .action:hover { color: #fff; background: rgb(255 255 255 / 12%); }
  .action:disabled { cursor: wait; opacity: .45; }
  .action:focus-visible { outline: 2px solid var(--sideb-highlight, #d06c70); outline-offset: 1px; }
  /* Dislike, like and "+" stay out of the way until the row is interacted with; a liked heart stays visible. */
  .dislike, .add, .like:not(.liked) { opacity: 0; pointer-events: none; }
  .sb-rec-track:hover .action, .sb-rec-track:focus-within .action, .sb-rec-track.current .action { opacity: 1; pointer-events: auto; }
  .like.liked { opacity: 1; pointer-events: auto; color: #fff; }
  .slot { position: relative; display: grid; place-items: center; min-width: 30px; height: 28px; }
  .slot > * { grid-area: 1 / 1; }
  .duration { color: rgb(255 255 255 / 48%); font-size: 11.5px; font-variant-numeric: tabular-nums; white-space: nowrap; pointer-events: none; }
  .sb-rec-track:hover .duration, .sb-rec-track:focus-within .duration, .sb-rec-track.current .duration { visibility: hidden; }
  @media (prefers-reduced-motion: no-preference) { .action { transition: opacity .12s, background .12s; } }
</style>
