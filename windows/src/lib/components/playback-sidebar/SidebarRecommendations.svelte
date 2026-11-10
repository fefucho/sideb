<script lang="ts">
  /*
   * PLAN-023 W5 - recommendations feed of the playback sidebar ("Ahora suena"), port of
   * NativeSidebarRecommendationsView / NowPlayingSidebarRecommendations (macOS, final state).
   *
   * LAYOUT CONTRACT (for W3, who composes this component):
   *   Mount it as a SIBLING AFTER the hero (artwork + metadata, W4) inside the same positioned box
   *   that fills the Ahora suena area (between header and fixed player). It is `position:absolute; inset:0`,
   *   and it is the ONLY vertical scroller: a transparent spacer row of `heroHeight` px exposes the fixed
   *   hero behind it; recommendations scroll over the hero on a blurred, tinted surface that starts at
   *   `max(0, heroHeight - scrollTop)`. Only rows are interactive (`pointer-events:auto`), so the hero's
   *   metadata stays clickable; wheel gestures that start over the hero are forwarded to the feed.
   *   `heroHeight` should be >= the visible height of that area so no recommendation shows before scrolling.
   *
   * PROPS
   *   session: number                       account session revision (page `sessionRevision`); change => back to the hero
   *   playback: PlaybackStateDto            current song + isPlaying; the native queue is never read or copied
   *   snapshot: RecommendationsSnapshot     `recommendationsState` of the page's RecommendationsController
   *   heroHeight?: number = 0               px height of the transparent hero spacer
   *   initialOffset?: number = 0            scrollTop to restore when the tab is shown again
   *   occurrenceId?: string | null          optional queue-entry id: replaying the same song resets the feed
   *   loggedIn?: boolean = false            like/dislike only exist when signed in
   *   likedIds?: Set<string>, pendingIds?: Set<string>   account.data.likedIds / pendingIds
   *   onRequestLoad: () => void             = `() => void recommendations.load()`; called ONLY after the first scroll
   *                                         (offset >= 24 px) and whenever the controller was invalidated afterwards
   *   onRefresh: () => void                 = `() => void recommendations.load(true)` (refresh/retry buttons)
   *   onSuspend?: () => void                = `() => recommendations.suspend()`; called when the feed unmounts
   *   onScrollOffset?: (px: number) => void report scrollTop so W3/W4 can fade/suspend the hero and save the offset
   *   onPlaySong: (song) => void            = `player.startRadio(song)` (row click on a song that is not current)
   *   onTogglePlayback: () => void          row click on the current song
   *   onAddToQueue: (song) => void          = `player.enqueue([song], 'end')` (native command; nothing is stored here)
   *   onToggleLike?: (song) => void         = `account.toggleLike(song)`
   *   onDislike?: (song) => void            = dislikeCurrentTrack({videoId, session, currentSession, rate: account.dislike,
   *                                           removeRecommendation: recommendations.removeSong,
   *                                           filterRecommendations: player.filterDislikedRecommendations, removeEntry})
   *                                           without `entryId` (a recommendation is not a queue entry)
   *   onOpenArtist?, onOpenAlbum?: (browseId) => void
   *   onSongContextMenu?: (event, song) => void / onArtistContextMenu?: (event, card) => void   optional overrides of the shared menu
   *
   * Behaviour: rows are virtualized (flat list, fixed heights 44/40/54/140/180, bounded overscan); artist shelves
   * (max 10 cards) and songs (max 10 per shelf) are not constructed until activation; stale data (other song,
   * other account session) is never rendered; errors keep partial shelves and offer retry.
   */
  import { onDestroy, onMount, untrack } from 'svelte';
  import { t, language, resolveMessage } from '$lib/i18n';
  import { recommendedRange } from '$lib/player/recommended-viewport';
  import {
    SidebarRecommendationsGate, currentSidebarData, projectSidebarRecommendations, shouldRequestSidebarRecommendations,
    sidebarFeedTop, sidebarLayout, sidebarRequestKey, wheelPixels, type SidebarRecommendationRow,
  } from '$lib/player/sidebarRecommendations';
  import type { RecommendationsSnapshot } from '$lib/player/recommendations';
  import type { BrowseCardDto, PlaybackStateDto, SongDto } from '$lib/types';
  import SidebarArtistShelf from './SidebarArtistShelf.svelte';
  import SidebarRecommendedTrack from './SidebarRecommendedTrack.svelte';

  interface Props {
    session: number;
    playback: PlaybackStateDto;
    snapshot: RecommendationsSnapshot;
    heroHeight?: number;
    initialOffset?: number;
    occurrenceId?: string | null;
    loggedIn?: boolean;
    likedIds?: Set<string>;
    pendingIds?: Set<string>;
    onRequestLoad: () => void;
    onRefresh: () => void;
    onSuspend?: () => void;
    onScrollOffset?: (offset: number) => void;
    onPlaySong: (song: SongDto) => void;
    onTogglePlayback: () => void;
    onAddToQueue: (song: SongDto) => void;
    onToggleLike?: (song: SongDto) => void;
    onDislike?: (song: SongDto) => void;
    onOpenArtist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void;
    onSongContextMenu?: (event: MouseEvent, song: SongDto) => void;
    onArtistContextMenu?: (event: MouseEvent, artist: BrowseCardDto) => void;
  }
  let {
    session, playback, snapshot, heroHeight = 0, initialOffset = 0, occurrenceId = null, loggedIn = false,
    likedIds = new Set<string>(), pendingIds = new Set<string>(), onRequestLoad, onRefresh, onSuspend, onScrollOffset,
    onPlaySong, onTogglePlayback, onAddToQueue, onToggleLike, onDislike, onOpenArtist, onOpenAlbum, onSongContextMenu, onArtistContextMenu,
  }: Props = $props();

  const OVERSCAN = 240;
  const track = $derived(playback.currentTrack);
  const hasTrack = $derived(Boolean(track?.videoId?.trim()));
  const requestKey = $derived(sidebarRequestKey(session, track, occurrenceId));

  let root = $state<HTMLDivElement>();
  let scroller = $state<HTMLDivElement>();
  let material = $state<HTMLDivElement>();
  let position = $state(0), extent = $state(600), activated = $state(false);
  let focusedId = $state<string | null>(null), menuId = $state<string | null>(null);
  let mounted = $state(false);
  const gate = new SidebarRecommendationsGate();
  const rejectedContexts = new Set<string>();
  const shelfOffsets = new Map<string, number>();
  let lastSession = untrack(() => session), restored = false;

  // Invalidate before anything renders: account session, song or queue occurrence changed.
  $effect.pre(() => {
    const key = requestKey, current = session;
    untrack(() => {
      if (current !== lastSession) {
        // Whatever data was on screen belongs to the previous account: never show it again.
        if (snapshot.data?.contextKey) rejectedContexts.add(snapshot.data.contextKey);
        lastSession = current;
      }
      if (gate.sync(key)) {
        activated = false; shelfOffsets.clear();
        if (restored) { position = 0; if (scroller) scroller.scrollTop = 0; onScrollOffset?.(0); }
      }
    });
  });

  // Stale responses (other song / pre-switch account context) are discarded here too, not only in the controller.
  const currentData = $derived.by(() => { session; return currentSidebarData(snapshot.data, track, rejectedContexts); });
  const rows = $derived(projectSidebarRecommendations({ data: currentData, activated, loading: snapshot.loading, error: snapshot.error }));
  const layout = $derived(sidebarLayout(rows, heroHeight));
  const range = $derived(recommendedRange(layout.offsets, position, extent, OVERSCAN));
  const visible = $derived.by(() => {
    const indices = new Set<number>();
    for (let index = range.start; index < range.end && index < rows.length; index++) indices.add(index);
    // A focused row or the owner of an open menu must not be recycled out from under the user.
    for (const id of [focusedId, menuId]) { const index = id === null ? -1 : rows.findIndex(row => row.id === id); if (index >= 0) indices.add(index); }
    return [...indices].sort((a, b) => a - b);
  });

  // First activation, and re-request after the controller dropped its state (the page passes null while a song loads).
  $effect(() => {
    if (shouldRequestSidebarRecommendations({ activated, hasTrack, loading: snapshot.loading, hasData: currentData !== null, error: snapshot.error })) untrack(() => onRequestLoad());
  });

  function applyMaterial(top: number) {
    if (material) material.style.transform = `translateY(${sidebarFeedTop(heroHeight, top)}px)`;
  }
  function read() {
    if (!scroller) return;
    const top = Math.max(0, scroller.scrollTop);
    position = top; extent = scroller.clientHeight || extent;
    activated = gate.update(top, hasTrack);
    applyMaterial(top);
    onScrollOffset?.(top);
  }
  let frame = 0;
  function schedule() { if (!frame) frame = requestAnimationFrame(() => { frame = 0; read(); }); }
  // Song/session changes and hero resizes re-evaluate against the (reset) offset.
  $effect(() => { requestKey; hasTrack; heroHeight; if (mounted) untrack(read); });

  onMount(() => {
    mounted = true;
    if (scroller && initialOffset > 0) scroller.scrollTop = initialOffset;
    restored = true;
    untrack(read);
    const host = root?.parentElement;
    const resize = new ResizeObserver(schedule);
    if (scroller) resize.observe(scroller);
    // The scroller sits over the hero without capturing its clicks, so wheel over the hero is forwarded.
    const forward = (event: WheelEvent) => {
      if (!scroller || event.defaultPrevented || event.ctrlKey || Math.abs(event.deltaY) < Math.abs(event.deltaX)) return;
      const target = event.target instanceof Element ? event.target : null;
      if (target?.closest('[data-sidebar-row],[role="menu"]')) return; // rows scroll natively
      scroller.scrollTop += wheelPixels(event, scroller.clientHeight);
      schedule();
    };
    host?.addEventListener('wheel', forward, { passive: true });
    return () => { cancelAnimationFrame(frame); frame = 0; resize.disconnect(); host?.removeEventListener('wheel', forward); };
  });
  onDestroy(() => onSuspend?.());

  const rowOf = (target: EventTarget | null) => (target instanceof Element ? target.closest('[data-sidebar-row]')?.getAttribute('data-sidebar-row') : null) ?? null;
  function focusOut() { queueMicrotask(() => { if (!root?.contains(document.activeElement)) focusedId = null; }); }
  function rememberMenu(event: MouseEvent | KeyboardEvent) {
    const target = event.target instanceof Element ? event.target : null;
    const keyboard = event instanceof KeyboardEvent && (event.key === 'ContextMenu' || (event.shiftKey && event.key === 'F10'));
    if (event.type !== 'contextmenu' && !keyboard && !target?.closest('.menu,.more')) return;
    const id = rowOf(event.target), key = requestKey;
    queueMicrotask(() => { if (root?.isConnected && key === requestKey && document.querySelector('[role="menu"]')) menuId = id; });
  }
  $effect(() => {
    if (menuId === null) return;
    const observer = new MutationObserver(() => { if (!document.querySelector('[role="menu"]')) menuId = null; });
    observer.observe(document.body, { childList: true, subtree: true });
    return () => observer.disconnect();
  });

  function headingTitle(row: Extract<SidebarRecommendationRow, { kind: 'heading' }>) { return $t(row.title.key, row.title.args); }
  function statusText(row: Extract<SidebarRecommendationRow, { kind: 'status' }>) {
    return row.state === 'error' ? resolveMessage(row.error, $language) : row.state === 'loading' ? $t('common.loading') : row.state === 'empty' ? $t('fullscreen.noRecommendations') : '';
  }
  function activateSong(song: SongDto) { if (song.videoId === track?.videoId) onTogglePlayback(); else onPlaySong(song); }
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<div class="sidebar-recommendations" bind:this={root} role="region" aria-label={$t('fullscreen.recommendations')} aria-busy={snapshot.loading}
  data-sidebar-recommendations data-activated={activated ? 'true' : 'false'} data-mounted-rows={visible.length}
  onfocusin={event => focusedId = rowOf(event.target)} onfocusout={focusOut} onclick={rememberMenu} oncontextmenu={rememberMenu} onkeydown={rememberMenu}>
  <div class="material" bind:this={material} aria-hidden="true"></div>
  <div class="scroller" bind:this={scroller} onscroll={schedule}>
    <div class="content" style:height={`${layout.total}px`}>
      {#each visible as index (rows[index].id)}
        {@const row = rows[index]}
        {#if row.kind !== 'hero'}
          <div class="entry" class:passive={row.kind === 'status' && row.state === 'idle'} data-sidebar-row={row.id} style:height={`${layout.offsets[index + 1] - layout.offsets[index]}px`} style:transform={`translateY(${layout.offsets[index]}px)`}>
            {#if row.kind === 'refresh'}
              <div class="bar"><h2>{$t('fullscreen.recommendations')}</h2>
                <button type="button" class="pill" disabled={snapshot.loading || !hasTrack} onclick={onRefresh}>{$t('common.refresh')}</button></div>
            {:else if row.kind === 'heading'}
              <div class="bar"><h2 title={headingTitle(row)}>{headingTitle(row)}</h2>
                {#if row.target && row.browseId && (row.target === 'artist' ? onOpenArtist : onOpenAlbum)}
                  <button type="button" class="pill link" onclick={() => row.target === 'artist' ? onOpenArtist?.(row.browseId!) : onOpenAlbum?.(row.browseId!)}>{$t(row.target === 'artist' ? 'detail.viewArtist' : 'detail.viewAlbum')}</button>
                {/if}</div>
            {:else if row.kind === 'track'}
              <SidebarRecommendedTrack id={row.id} index={row.index} song={row.song} current={row.song.videoId === track?.videoId} playing={playback.isPlaying}
                {loggedIn} liked={likedIds.has(row.song.videoId)} likePending={pendingIds.has(row.song.videoId)}
                onActivate={activateSong} {onAddToQueue} {onToggleLike} {onDislike} {onOpenArtist} {onOpenAlbum} {onSongContextMenu} />
            {:else if row.kind === 'artists'}
              <SidebarArtistShelf {session} cards={row.cards} label={$t('fullscreen.fansAlsoLike')} contextKey={requestKey}
                offset={shelfOffsets.get('artists') ?? 0} onOffset={offset => shelfOffsets.set('artists', offset)} {onOpenArtist} {onArtistContextMenu} />
            {:else if row.kind === 'status' && row.state !== 'idle'}
              <div class="status" role={row.state === 'error' ? 'alert' : 'status'} data-sidebar-status={row.state}>
                <p>{statusText(row)}</p>
                {#if activated && !snapshot.loading && hasTrack}<button type="button" class="pill" onclick={onRefresh}>{$t('common.retry')}</button>{/if}
              </div>
            {/if}
          </div>
        {/if}
      {/each}
    </div>
  </div>
</div>

<style>
  .sidebar-recommendations { position: absolute; inset: 0; overflow: hidden; pointer-events: none; color: #fff; isolation: isolate; }
  /* One viewport-sized glass surface; only its top edge moves (set from scroll without re-rendering rows). */
  .material { position: absolute; inset: 0; z-index: 0; pointer-events: none; will-change: transform;
    background: linear-gradient(rgb(14 14 14 / 28%), rgb(14 14 14 / 28%)), rgb(34 34 36 / 50%);
    -webkit-backdrop-filter: blur(28px) saturate(1.2); backdrop-filter: blur(28px) saturate(1.2); }
  .scroller { position: absolute; inset: 0; z-index: 1; overflow-x: hidden; overflow-y: auto; overscroll-behavior: contain; overflow-anchor: none; pointer-events: none; scrollbar-width: thin; scrollbar-color: rgb(255 255 255 / 25%) transparent; }
  .content { position: relative; width: 100%; min-width: 0; }
  .entry { position: absolute; inset: 0 auto auto 0; width: 100%; box-sizing: border-box; min-width: 0; pointer-events: auto; }
  .entry.passive { pointer-events: none; }
  .bar { display: flex; align-items: center; gap: 8px; height: 100%; padding: 0 14px; }
  h2 { min-width: 0; flex: 1; margin: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 13px; font-weight: 600; color: #fff; }
  .pill { flex: none; padding: 3px 10px; border: 0; border-radius: 999px; background: rgb(255 255 255 / 10%); color: rgb(255 255 255 / 88%); font: inherit; font-size: 11.5px; font-weight: 500; cursor: pointer; }
  .pill.link { padding-inline: 4px; background: transparent; }
  .pill:hover:not(:disabled) { background: rgb(255 255 255 / 18%); color: #fff; }
  .pill:disabled { opacity: .45; cursor: default; }
  .pill:focus-visible { outline: 2px solid var(--sideb-highlight, #d06c70); outline-offset: 2px; }
  .status { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 12px; height: 100%; padding: 0 24px; text-align: center; color: rgb(255 255 255 / 70%); font-size: 13px; }
  .status p { margin: 0; }
  @media (prefers-reduced-transparency: reduce), (prefers-contrast: more), (forced-colors: active) {
    .material { background: rgb(14 14 14); -webkit-backdrop-filter: none; backdrop-filter: none; }
  }
</style>
