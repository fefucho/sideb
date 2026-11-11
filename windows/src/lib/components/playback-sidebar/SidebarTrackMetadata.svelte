<script lang="ts">
  /**
   * Fixed 68 px metadata block of the side player (macOS `SidebarTrackMetadata`): title (featured-artist
   * links) and credits (artist/album links, content rating), then dislike · like · "+" · menu. It reads no clock
   * and loads no image, so the same instance can sit under the cover or above the progress bar in Letras/Cola.
   *
   * Title and credits move (marquee via the shared `titleMotion` action) only when they overflow.
   *
   * Props (W3 composes this file; every action is optional and its button appears only when supplied, so the
   * macOS layout — heart + menu — is obtained by omitting `onDislike`/`onAddToQueue`):
   * - `session`, `playback`: the usual FullscreenNowPlaying contract (`playback.currentTrack`, `.error`, `.isLoading`).
   * - `loggedIn`, `liked`, `likePending`, `likeError`, `onToggleLike()`: heart button (needs a signed-in account).
   * - `onDislike()`: dislike and remove from the queue (same handler PlayerBar receives).
   * - `onAddToQueue()`: add the current song to the end of the queue.
   * - `onOpenArtist(id, title?)`, `onOpenAlbum(id)`: credit links (as FullscreenNowPlaying).
   * - `onOpenMenu(event)`: the common track menu (also from the context menu / Shift+F10 / Menu key).
   * - `onRetryPlayback()`: retry action of the error line.
   */
  import { t, language, resolveMessage } from '$lib/i18n';
  import type { PlaybackStateDto } from '$lib/types';
  import ArtistCredits from '$lib/components/ArtistCredits.svelte';
  import FeaturedTrackTitle from '$lib/components/FeaturedTrackTitle.svelte';
  import MoreIcon from '$lib/components/common/MoreIcon.svelte';
  import DislikeIcon from '$lib/components/common/DislikeIcon.svelte';

  interface Props {
    session: number;
    playback: PlaybackStateDto;
    loggedIn?: boolean; liked?: boolean; likePending?: boolean; likeError?: string | null;
    onToggleLike?: () => void; onDislike?: () => void; onAddToQueue?: () => void;
    onOpenArtist?: (id: string, title?: string) => void; onOpenAlbum?: (id: string) => void;
    onOpenMenu?: (event: MouseEvent | KeyboardEvent) => void; onRetryPlayback?: () => void;
  }
  let { playback, loggedIn = false, liked = false, likePending = false, likeError = null, onToggleLike, onDislike, onAddToQueue, onOpenArtist, onOpenAlbum, onOpenMenu, onRetryPlayback }: Props = $props();
  const track = $derived(playback.currentTrack);
  const busy = $derived(likePending || playback.isLoading);

  function menuKey(event: KeyboardEvent) {
    if (track && onOpenMenu && (event.key === 'ContextMenu' || (event.key === 'F10' && event.shiftKey))) {
      event.preventDefault(); event.stopPropagation(); onOpenMenu(event);
    }
  }
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="metadata" role="group" aria-label={$t('windows.ui.currentSong')} oncontextmenu={event => { if (onOpenMenu && track) { event.preventDefault(); onOpenMenu(event); } }}>
  <div class="text">
    <h2 class="title" title={track?.title ?? $t('player.noPlayback')}>
      {#if track}<FeaturedTrackTitle {track} {onOpenArtist} prefetch scrollTitle />{:else}{$t('player.noPlayback')}{/if}
    </h2>
    {#if playback.error}
      <button type="button" class="retry" onclick={onRetryPlayback} disabled={!onRetryPlayback} aria-label={$t('player.retryPlayback')} title={resolveMessage(playback.error, $language)}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 12a8 8 0 1 1-2.34-5.66M20 4v5h-5" /></svg>
        <span>{resolveMessage(playback.error, $language)}</span>
      </button>
    {:else if track}
      <div class="credits">
        <ArtistCredits {track} artistRuns={track.artistRuns} artists={track.artists} artistId={track.artistId} {onOpenArtist}
          album={track.album} albumId={track.albumId} {onOpenAlbum} scroll />
      </div>
    {/if}
  </div>

  <div class="actions">
    {#if likeError}<span class="like-error" role="alert" title={resolveMessage(likeError, $language)}>!</span>{/if}
    {#if onDislike}
      <button type="button" class="action" disabled={!loggedIn || !track || busy} onkeydown={menuKey} onclick={onDislike}
        aria-label={$t('windows.queue.dislike', [track?.title ?? ''])} title={!loggedIn ? $t('windows.ui.signInToUseLike') : $t('windows.ui.dislikeAndRemoveFromQueue')}>
        <DislikeIcon />
      </button>
    {/if}
    {#if onToggleLike}
      <button type="button" class="action like" class:liked disabled={!loggedIn || !track || busy} onkeydown={menuKey} onclick={onToggleLike}
        aria-pressed={liked} aria-busy={likePending || undefined} aria-label={$t(liked ? 'detail.track.unlike' : 'detail.track.like')}
        title={!loggedIn ? $t('windows.ui.signInToUseLike') : $t(liked ? 'detail.track.unlike' : 'detail.track.like')}>
        <svg viewBox="2 1.68 20 20" aria-hidden="true" fill={liked ? 'currentColor' : 'none'} stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 8.7c0 4.2-6.4 9.1-8.8 11-2.4-1.9-8.8-6.8-8.8-11a4.9 4.9 0 0 1 8.8-3.1 4.9 4.9 0 0 1 8.8 3.1Z" /></svg>
      </button>
    {/if}
    {#if onAddToQueue}
      <button type="button" class="action" disabled={!track || playback.isLoading} onkeydown={menuKey} onclick={onAddToQueue}
        aria-label={$t('menu.add_to_queue')} title={$t('menu.add_to_queue')}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14" /></svg>
      </button>
    {/if}
    {#if onOpenMenu}
      <button type="button" class="action more" disabled={!track} onclick={onOpenMenu} onkeydown={menuKey}
        aria-label={$t('detail.track.moreOptionsForSong')} title={$t('menu.more_options')}>
        <MoreIcon />
      </button>
    {/if}
  </div>
</div>

<style>
  .metadata { box-sizing:border-box; display:flex; align-items:flex-start; gap:8px; width:100%; height:68px; min-width:0; color:#fff; }
  .text { display:flex; flex:1 1 auto; flex-direction:column; gap:5px; min-width:0; }
  .title { margin:0; min-width:0; overflow:hidden; font-size:24px; font-weight:700; line-height:1.2; white-space:nowrap; }
  .credits { display:flex; min-width:0; overflow:hidden; color:rgb(255 255 255 / 70%); font-size:14px; font-weight:500; line-height:1.3; white-space:nowrap;
    --credit-artist-weight:500; --credit-album-size:1em; --credit-album-weight:500; --credit-album-color:rgb(255 255 255 / 60%);
    --credit-separator-size:13px; --credit-separator-weight:400; --credit-separator-color:rgb(255 255 255 / 40%); }
  .retry { display:flex; align-items:center; gap:6px; max-width:100%; padding:0; border:0; background:transparent; color:#ffd60a; font:inherit; font-size:12px; text-align:left; cursor:pointer; }
  .retry:disabled { cursor:default; }
  .retry svg { flex:none; width:14px; height:14px; } .retry span { min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .actions { display:flex; flex:none; align-items:center; gap:0; height:44px; }
  .action { display:grid; place-items:center; box-sizing:border-box; width:36px; height:44px; padding:0; border:0; border-radius:8px; background:transparent; color:rgb(255 255 255 / 70%); cursor:pointer; }
  .action svg { display:block; width:22px; height:22px; }
  .action :global(.dislike-icon) { width:20px; height:20px; }
  .action.more { width:28px; } .action.more :global(svg) { width:16px; height:16px; }
  .action:hover:not(:disabled), .action:focus-visible { color:#fff; background:rgb(255 255 255 / 10%); }
  .action.like.liked { color:#d06c70; }
  .action:disabled { opacity:.5; cursor:default; }
  .action:focus-visible, .retry:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:2px; }
  .like-error { align-self:center; margin-right:4px; color:#ffd60a; font-weight:700; }
  @media (forced-colors:active) { .action { color:ButtonText; } .action.like.liked { color:Highlight; } }
</style>
