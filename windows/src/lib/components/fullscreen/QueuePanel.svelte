<script lang="ts">
  import { t, language, count, resolveMessage, type AppMessage  } from '$lib/i18n';
  import { onMount, tick } from 'svelte';
  import TrackArtwork from '$lib/components/common/TrackArtwork.svelte';
  import TrackActivity from '$lib/components/common/TrackActivity.svelte';
  import { visibleTrackRange, trackSegments } from '$lib/components/common/trackList';
  import type { PlaybackStateDto, QueueEntryDto } from '$lib/types';
  import ArtistCredits from '$lib/components/ArtistCredits.svelte';

  interface Props {
    playback: PlaybackStateDto;
    onSelectQueue: (index: number) => void;
    onTogglePlayback?: () => void;
    onOpenArtist?: (id: string, title: string) => void;
    onOpenAlbum?: (id: string) => void;
    onMoveQueue: (entryId: string, beforeEntryId: string | null) => void | Promise<void>;
    onQueueContextMenu?: (event: MouseEvent, entry: QueueEntryDto) => void;
    onRetryRadio?: () => void;
    onRetrySource?: () => void;
    loggedIn?: boolean;
    likedIds?: Set<string>;
    pendingIds?: Set<string>;
    likesLoading?: boolean;
    onToggleLike?: (entry: QueueEntryDto) => void;
    onDislike?: (entry: QueueEntryDto) => void;
  }
  let { playback, onSelectQueue, onTogglePlayback, onOpenArtist, onOpenAlbum, onMoveQueue, onQueueContextMenu, onRetryRadio, onRetrySource, loggedIn = false,
    likedIds = new Set<string>(), pendingIds = new Set<string>(), likesLoading = false, onToggleLike, onDislike }: Props = $props();
  let draggingId = $state<string | null>(null);
  let dropId = $state<string | null>(null);
  let dropAfter = $state(false);
  let movePending = $state(false);
  let moveError = $state<string | null>(null);
  let announcement = $state<AppMessage | null>(null);
  let queueList = $state<HTMLDivElement>();
  let awake = $state(false);
  let scrollTop = $state(0);
  let viewportHeight = $state(480);
  let focusedEntryId = $state<string | null>(null);
  const rowPitch = 48;
  const visibleEntries = $derived.by(() => {
    const items = playback.queue.items;
    const range = visibleTrackRange(items.length, scrollTop, viewportHeight, rowPitch);
    const pinned = [focusedEntryId, draggingId].map(id => id ? items.findIndex(entry => entry.entryId === id) : -1);
    return trackSegments(items.length, range, pinned).flatMap(([start, end]) =>
      items.slice(start, end).map((entry, offset) => ({ entry, index: start + offset })));
  });
  function observeViewport(node: HTMLDivElement) {
    let frame = 0;
    const sync = () => { scrollTop = node.scrollTop; viewportHeight = node.clientHeight; };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(() => { frame = 0; sync(); }); };
    const observer = new ResizeObserver(schedule);
    observer.observe(node);
    node.addEventListener('scroll', schedule, { passive: true });
    // Keyboard events originate from native buttons; the group itself is not focusable.
    node.addEventListener('keydown', handleTab);
    sync();
    return { destroy() { observer.disconnect(); node.removeEventListener('scroll', schedule); node.removeEventListener('keydown', handleTab); if (frame) cancelAnimationFrame(frame); } };
  }
  function entryIdOf(target: EventTarget | null) {
    return target instanceof Element ? target.closest<HTMLElement>('[data-entry-id]')?.dataset.entryId ?? null : null;
  }
  async function handleTab(event: KeyboardEvent) {
    if (event.key !== 'Tab' || event.altKey || event.ctrlKey || event.metaKey || !(event.target instanceof HTMLButtonElement)) return;
    const row = event.target.closest<HTMLElement>('[data-entry-id]');
    if (!row || !queueList) return;
    const controls = Array.from(row.querySelectorAll<HTMLButtonElement>('button:not(:disabled)'));
    const atBoundary = event.target === (event.shiftKey ? controls[0] : controls.at(-1));
    if (!atBoundary) return;
    const index = playback.queue.items.findIndex(entry => entry.entryId === row.dataset.entryId);
    const nextIndex = index + (event.shiftKey ? -1 : 1);
    const nextEntry = playback.queue.items[nextIndex];
    if (!nextEntry) return;
    event.preventDefault();
    const rowTop = nextIndex * rowPitch;
    if (rowTop < queueList.scrollTop) queueList.scrollTop = rowTop;
    else if (rowTop + rowPitch > queueList.scrollTop + queueList.clientHeight) queueList.scrollTop = rowTop + rowPitch - queueList.clientHeight;
    scrollTop = queueList.scrollTop;
    await tick();
    const nextRow = Array.from(queueList.querySelectorAll<HTMLElement>('[data-entry-id]')).find(node => node.dataset.entryId === nextEntry.entryId);
    const nextControls = Array.from(nextRow?.querySelectorAll<HTMLButtonElement>('button:not(:disabled)') ?? []);
    (event.shiftKey ? nextControls.at(-1) : nextControls[0])?.focus();
  }
  onMount(() => {
    const sync = () => { awake = !document.hidden && document.hasFocus(); };
    sync();
    document.addEventListener('visibilitychange', sync);
    window.addEventListener('focus', sync);
    window.addEventListener('blur', sync);
    return () => {
      document.removeEventListener('visibilitychange', sync);
      window.removeEventListener('focus', sync);
      window.removeEventListener('blur', sync);
    };
  });

  function activateEntry(entry: QueueEntryDto) {
    if (draggingId) return;
    // Resolve the occurrence at activation time, including after an authoritative reorder.
    const index = playback.queue.items.findIndex(item => item.entryId === entry.entryId);
    if (index < 0) return;
    if (index === playback.queue.currentIndex && onTogglePlayback) {
      if (!playback.isLoading) onTogglePlayback();
    } else {
      onSelectQueue(index);
    }
  }
  function openArtist(entry: QueueEntryDto, id: string) {
    const title = entry.artistRuns?.find(run => run.id === id)?.text || entry.artists;
    onOpenArtist?.(id, title);
  }
  const queueTitle = $derived(playback.queue.source?.kind === 'radio'
    ? $t('windows.queue.radio', [playback.queue.source.title || playback.currentTrack?.title || $t('windows.queue.thisSong')])
    : playback.queue.source?.title
      ? playback.queue.source.kind === 'album' ? $t('queue.albumContext', [playback.queue.source.title])
        : playback.queue.source.kind === 'playlist' ? $t('queue.playlistContext', [playback.queue.source.title])
        : playback.queue.source.title
      : $t('queue.title'));

  function formatDuration(seconds: number | null) {
    if (seconds === null || !Number.isFinite(seconds) || seconds <= 0) return '';
    const total = Math.floor(seconds);
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
  }
  function resetDrag() { draggingId = null; dropId = null; dropAfter = false; }
  $effect(() => {
    if (draggingId && !playback.queue.items.some(entry => entry.entryId === draggingId)) resetDrag();
  });
  function handleContextMenu(event: MouseEvent, entry: QueueEntryDto) {
    if (!onQueueContextMenu) return;
    event.preventDefault();
    onQueueContextMenu(event, entry);
  }
  function contextMenuFromKeyboard(event: KeyboardEvent, entry: QueueEntryDto) {
    if (!onQueueContextMenu || !(event.key === 'ContextMenu' || (event.key === 'F10' && event.shiftKey))) return;
    event.preventDefault(); event.stopPropagation();
    const anchor = (event.target as HTMLElement).getBoundingClientRect();
    handleContextMenu(new MouseEvent('contextmenu', {
      cancelable: true, button: 2, clientX: anchor.left + anchor.width / 2, clientY: anchor.bottom,
    }), entry);
  }
  function startDrag(event: DragEvent, entry: QueueEntryDto) {
    if (movePending || !event.dataTransfer) { event.preventDefault(); return; }
    draggingId = entry.entryId;
    moveError = null;
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('application/x-sideb-queue-entry', entry.entryId);
    event.dataTransfer.setData('text/plain', entry.title);
    const row = (event.currentTarget as HTMLElement).closest('.queue-row');
    if (row) event.dataTransfer.setDragImage(row, 24, 23);
  }
  function overRow(event: DragEvent, entry: QueueEntryDto) {
    if (!draggingId || movePending) return;
    event.preventDefault();
    event.stopPropagation();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
    dropId = entry.entryId;
    dropAfter = event.clientY >= rect.top + rect.height / 2;
    // Only the queue list scrolls; artwork and playback controls remain fixed.
    if (!queueList) return;
    const listRect = queueList.getBoundingClientRect();
    if (event.clientY < listRect.top + 32) queueList.scrollTop -= 12;
    else if (event.clientY > listRect.bottom - 32) queueList.scrollTop += 12;
  }
  async function move(entryId: string, beforeEntryId: string | null) {
    const index = playback.queue.items.findIndex(entry => entry.entryId === entryId);
    if (index < 0 || movePending) return;
    if (entryId === beforeEntryId || (playback.queue.items[index + 1]?.entryId ?? null) === beforeEntryId) return;
    movePending = true;
    moveError = null;
    const title = playback.queue.items[index].title;
    try {
      await onMoveQueue(entryId, beforeEntryId);
      announcement = { key: 'windows.queue.moved', args: [title] };
    } catch (error) {
      moveError = error instanceof Error ? error.message : $t('windows.ui.couldnTMoveTheSongTryAgain');
    } finally { movePending = false; }
  }
  function dropOnRow(event: DragEvent, entry: QueueEntryDto) {
    if (!draggingId) return;
    event.preventDefault();
    event.stopPropagation();
    const source = draggingId;
    const targetIndex = playback.queue.items.findIndex(item => item.entryId === entry.entryId);
    if (targetIndex < 0) { resetDrag(); return; }
    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
    const after = event.clientY >= rect.top + rect.height / 2;
    const before = after ? playback.queue.items[targetIndex + 1]?.entryId ?? null : entry.entryId;
    resetDrag();
    void move(source, before);
  }
  function overList(event: DragEvent) {
    if (!draggingId || (event.target !== event.currentTarget && !(event.target instanceof Element && event.target.classList.contains('queue-canvas')))) return;
    event.preventDefault();
    dropId = null;
    dropAfter = true;
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
  }
  function dropAtEnd(event: DragEvent) {
    if (!draggingId || (event.target !== event.currentTarget && !(event.target instanceof Element && event.target.classList.contains('queue-canvas')))) return;
    event.preventDefault();
    const source = draggingId;
    resetDrag();
    void move(source, null);
  }
  function reorderWithKeyboard(event: KeyboardEvent, entry: QueueEntryDto) {
    if (event.key === 'Escape') { resetDrag(); return; }
    if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;
    event.preventDefault();
    event.stopPropagation();
    const index = playback.queue.items.findIndex(item => item.entryId === entry.entryId);
    if (index < 0) return;
    if (event.key === 'ArrowUp' && index > 0) void move(entry.entryId, playback.queue.items[index - 1].entryId);
    else if (event.key === 'ArrowDown' && index < playback.queue.items.length - 1) {
      void move(entry.entryId, playback.queue.items[index + 2]?.entryId ?? null);
    }
  }
</script>

<svelte:window onkeydown={(event) => { if (event.key === 'Escape') resetDrag(); }} />

<div class="queue-content" data-queue-dragging={draggingId !== null}>
  {#if playback.queue.items.length || playback.sourceLoad?.loading || playback.sourceLoad?.error || playback.sourceLoad?.hasMore || playback.queue.radio?.loading || playback.queue.radio?.error || moveError}
  <header class="queue-heading">
    {#if playback.queue.items.length}
    <div class="queue-context">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        {#if playback.queue.source?.kind === 'radio'}<circle cx="12" cy="12" r="2" /><path d="M7 7a7 7 0 0 0 0 10M17 7a7 7 0 0 1 0 10M4 4a11 11 0 0 0 0 16M20 4a11 11 0 0 1 0 16" />
        {:else if playback.queue.source?.kind === 'album'}<circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="3" />
        {:else if playback.queue.source?.kind === 'playlist'}<path d="M3 5h10M3 10h10M3 15h6M17 5v13" /><ellipse cx="14" cy="18" rx="3" ry="2" />
        {:else}<path d="M8 6h12M8 12h12M8 18h12" /><path d="M3 6h.01M3 12h.01M3 18h.01" stroke-width="3" />{/if}
      </svg>
      <span class="context-title">{queueTitle}</span><span class="separator" aria-hidden="true">•</span><span class="count">{count('common.songCount', playback.queue.items.length, $language)}</span>
      {#if playback.sourceLoad?.loading || playback.queue.radio?.loading}<span class="context-loading">
        {#if playback.sourceLoad?.loading}<span class="radio-state" role="status"><span class="spinner" aria-hidden="true"></span>{$t('detail.collection.preparingSongs')}</span>{/if}
        {#if playback.queue.radio?.loading}<span class="radio-state" role="status"><span class="spinner" aria-hidden="true"></span>{$t('windows.ui.preparingRadio')}</span>{/if}
      </span>{/if}
    </div>
    {:else}
      {#if playback.sourceLoad?.loading}<span class="radio-state" role="status"><span class="spinner" aria-hidden="true"></span>{$t('detail.collection.preparingSongs')}</span>{/if}
      {#if playback.queue.radio?.loading}<span class="radio-state" role="status"><span class="spinner" aria-hidden="true"></span>{$t('windows.ui.preparingRadio')}</span>{/if}
    {/if}
    {#if !playback.sourceLoad?.loading && playback.sourceLoad?.error}<div class="radio-error" role="alert"><span>{resolveMessage(playback.sourceLoad.error, $language)}</span>{#if playback.sourceLoad.canRetry && onRetrySource}<button type="button" onclick={onRetrySource}>{$t('common.retry')}</button>{/if}</div>{/if}
    {#if playback.sourceLoad?.hasMore}<span class="radio-state">{$t('windows.queue.partial', [playback.sourceLoad.loadedCount])}</span>{/if}
    {#if !playback.queue.radio?.loading && playback.queue.radio?.error}<div class="radio-error" role="alert"><span>{resolveMessage(playback.queue.radio.error, $language)}</span>{#if playback.queue.radio.canRetry && onRetryRadio}<button type="button" onclick={onRetryRadio}>{$t('sidebar.retry')}</button>{/if}</div>{/if}
    {#if moveError}<div class="radio-error" role="alert">{resolveMessage(moveError, $language)}</div>{/if}
  </header>
  {/if}
  <span class="sr-only" aria-live="polite">{resolveMessage(announcement, $language)}</span>
  <span id="queue-reorder-help" class="sr-only">{$t('windows.ui.dragToMoveTheSongOrUseTheUpAndDownArrowsWithThisButtonFocused')}</span>
  {#if playback.queue.items.length}
    <div class="queue-list" class:drop-end={draggingId && dropId === null && dropAfter} bind:this={queueList} use:observeViewport onfocusin={(event) => focusedEntryId = entryIdOf(event.target)} onfocusout={(event) => focusedEntryId = entryIdOf(event.relatedTarget)} role="group" aria-label={$t('windows.ui.queuedTracks')} ondragover={overList} ondrop={dropAtEnd} ondragleave={(event) => { if (!queueList?.contains(event.relatedTarget as Node | null)) { dropId = null; dropAfter = false; } }}>
      <div class="queue-canvas" style={`height:${playback.queue.items.length * rowPitch}px`}>
      {#each visibleEntries as { entry, index } (entry.entryId)}
        {@const current = index === playback.queue.currentIndex}
        <div class="queue-row track-row" data-entry-id={entry.entryId} style={`top:${index * rowPitch}px`} role="group" aria-label={$t('common.moreOptionsFor', [entry.title])} class:current={index === playback.queue.currentIndex} class:dragging={draggingId === entry.entryId} class:drop-before={draggingId && dropId === entry.entryId && !dropAfter} class:drop-after={draggingId && dropId === entry.entryId && dropAfter} oncontextmenu={(event) => handleContextMenu(event, entry)} ondragover={(event) => overRow(event, entry)} ondrop={(event) => dropOnRow(event, entry)}>
          <button type="button" class="queue-select" aria-current={current ? 'true' : undefined} aria-label={`${current && playback.isPlaying ? $t('player.pause') : $t('player.play')} ${entry.title}`} disabled={current && playback.isLoading} onkeydown={(event) => contextMenuFromKeyboard(event, entry)} onclick={() => activateEntry(entry)}></button>
          <span class="queue-index" aria-hidden="true"><TrackActivity active={current} playing={playback.isPlaying} number={index + 1} {awake} presentation="queue" /></span>
          <span class="queue-art"><TrackArtwork title={entry.title} thumbnail={entry.thumbnail} active={current} playing={playback.isPlaying} pending={current && playback.isLoading} size={36} showPlayOverlay={false} onPlay={() => activateEntry(entry)} /></span>
          <span class="queue-meta"><span class="queue-title">{entry.title}</span><ArtistCredits artistRuns={entry.artistRuns} artists={entry.artists} artistId={entry.artistId} album={entry.album} albumId={entry.albumId} onOpenArtist={onOpenArtist ? (id) => openArtist(entry, id) : undefined} {onOpenAlbum} /></span>
          <span class="queue-actions">
          {#if onDislike}
            <button type="button" class="queue-action dislike-action" aria-label={$t('windows.queue.dislike', [entry.title])} title={$t('windows.ui.dislikeAndRemoveFromQueue')} disabled={movePending || playback.isLoading} onclick={(event) => { event.stopPropagation(); onDislike?.(entry); }} onpointerdown={(event) => event.stopPropagation()}>
              <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4H3v10h4M7 13l4 7a2 2 0 0 0 3-2l-1-4h5a3 3 0 0 0 3-3l-2-5a3 3 0 0 0-3-2H7Z" /></svg>
            </button>
          {/if}
          {#if loggedIn && onToggleLike}
            {@const liked = likedIds.has(entry.videoId)}
            {@const likePending = (likesLoading && !liked) || pendingIds.has(entry.videoId)}
            <button type="button" class="queue-action like-action" class:liked aria-pressed={liked} aria-label={liked ? $t('windows.queue.unlike', [entry.title]) : $t('windows.queue.like', [entry.title])} title={likePending ? $t('windows.ui.updatingLike') : liked ? $t('windows.ui.removeLike') : $t('detail.track.like')} disabled={likePending} onclick={(event) => { event.stopPropagation(); onToggleLike?.(entry); }} onpointerdown={(event) => event.stopPropagation()}>
              <svg viewBox="2 1.68 20 20" aria-hidden="true" fill={liked ? "currentColor" : "none"} stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 8.7c0 4.2-6.4 9.1-8.8 11-2.4-1.9-8.8-6.8-8.8-11a4.9 4.9 0 0 1 8.8-3.1 4.9 4.9 0 0 1 8.8 3.1Z" /></svg>
            </button>
          {/if}
          </span>
          <span class="queue-timing"><span class="queue-duration">{formatDuration(entry.duration)}</span>
          <button type="button" class="reorder-handle" aria-label={$t('windows.queue.move', [entry.title])} aria-describedby="queue-reorder-help" title={$t('windows.ui.dragToReorderOnKeyboard')} disabled={movePending} draggable={!movePending} ondragstart={(event) => startDrag(event, entry)} ondragend={resetDrag} onkeydown={(event) => reorderWithKeyboard(event, entry)} onclick={(event) => event.stopPropagation()}>
            <svg viewBox="0 0 16 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><path d="M1 3h14M1 7h14M1 11h14" /></svg>
          </button>
          </span>
        </div>
      {/each}
      </div>
    </div>
  {:else}
    <div class="empty-panel"><svg class="empty-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" aria-hidden="true"><path d="M3 5h10M3 10h10M3 15h6M18 5v13" /><ellipse cx="15" cy="18" rx="3" ry="2" /></svg><p>{$t('windows.ui.noTracksInTheQueue')}</p></div>
  {/if}
</div>

<style>
  .queue-content { display: flex; width: 100%; min-width: 0; min-height: 0; flex: 1; flex-direction: column; overflow: hidden; }
  .queue-heading { display: flex; flex: none; min-width: 0; flex-direction: column; gap: 8px; padding: 2px 8px 8px; }
  .queue-context { display: flex; min-width: 0; align-items: center; flex-wrap: wrap; gap: 4px 8px; color: rgb(255 255 255 / 90%); font-size: 12px; font-weight: 600; }
  .queue-context > svg { flex: 0 0 11px; width: 11px; height: 11px; }
  .context-title { min-width: 0; flex: 0 1 auto; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .separator { flex: none; color: rgb(255 255 255 / 30%); font-size: 10px; font-weight: 400; }
  .count { flex: none; color: rgb(255 255 255 / 50%); font-size: 11px; font-weight: 500; white-space: nowrap; }
  .context-loading { display: flex; flex-wrap: wrap; gap: 4px 8px; margin-left: auto; }
  .context-loading .radio-state { gap: 4px; font-size: 10px; color: rgb(255 255 255 / 60%); }
  .radio-state, .radio-error { display: flex; align-items: center; gap: 8px; color: rgb(255 255 255 / 67%); font-size: 11px; }
  .radio-error { color: #ffb7bb; }
  .radio-error button { flex: none; padding: 3px 8px; border: 1px solid rgb(255 255 255 / 15%); border-radius: 999px; color: #fff; background: rgb(255 255 255 / 8%); font: inherit; cursor: pointer; }
  .spinner { width: 12px; height: 12px; border: 2px solid rgb(255 255 255 / 24%); border-top-color: #d06c70; border-radius: 50%; animation: spin .8s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .queue-list { min-width: 0; min-height: 0; flex: 1; overflow-y: auto; overscroll-behavior: contain; scrollbar-color: rgb(255 255 255 / 28%) transparent; scrollbar-width: thin; }
  .queue-canvas { position: relative; min-height: 100%; }
  .queue-row { position: absolute; left: 0; right: 0; display: grid; grid-template-columns: 24px 46px minmax(0, 1fr) 64px 36px; box-sizing: border-box; min-width: 0; height: 46px; align-items: center; margin: 0; padding: 0 18px 0 16px; border-radius: 6px; }
  .queue-select::before { position: absolute; inset: 1px 10px; border: .5px solid transparent; border-radius: 6px; content: ''; pointer-events: none; }
  .queue-row:hover .queue-select::before { background: rgb(255 255 255 / 4.5%); }
  .queue-row.current .queue-select::before { border-color: rgb(255 255 255 / 9%); background: rgb(255 255 255 / 6.5%); }
  .queue-row.dragging { opacity: .5; }
  .queue-row.drop-before::before, .queue-row.drop-after::after { position: absolute; z-index: 3; left: 4px; right: 4px; height: 2px; background: #d06c70; content: ''; pointer-events: none; }
  .queue-row.drop-before::before { top: 0; }
  .queue-row.drop-after::after { bottom: 0; }
  .queue-list.drop-end { box-shadow: inset 0 -2px #d06c70; }
  /* The activation target is a sibling below controls, never a parent of credit buttons. */
  .queue-select { position: absolute; inset: 0; z-index: 0; display: block; width: 100%; height: 100%; padding: 0; border: 0; border-radius: inherit; color: inherit; background: transparent; cursor: pointer; }
  .queue-select:disabled { cursor: wait; }
  .queue-index { display: grid; place-items: center; pointer-events: none; }
  .queue-art { position: relative; z-index: 1; display: block; width: 36px; height: 36px; margin-left: 10px; }
  .queue-meta { position: relative; z-index: 1; display: flex; min-width: 0; margin: 0 12px; flex-direction: column; gap: 3px; pointer-events: none; }
  .queue-title { display: block; min-width: 0; overflow: hidden; color: rgb(255 255 255 / 92%); font-size: 13px; font-weight: 500; line-height: 16px; text-overflow: ellipsis; white-space: nowrap; }
  .current .queue-title { font-weight: 650; }
  .queue-meta :global(.artist-credits) { color: rgb(255 255 255 / 60%); font-size: 11.5px; line-height: 14px; }
  .queue-meta :global(.credit-link) { pointer-events: auto; }
  .queue-duration { width: max-content; min-width: 28px; color: rgb(255 255 255 / 45%); font-size: 11.5px; font-variant-numeric: tabular-nums; text-align: center; white-space: nowrap; pointer-events: none; }
  .queue-timing { position: relative; z-index: 1; display: grid; grid-template-columns: minmax(0, 1fr); place-items: center; width: 28px; height: 30px; margin-left: 8px; pointer-events: none; }
  .queue-actions { position: relative; z-index: 1; display: grid; grid-template-columns: repeat(2, 28px); gap: 8px; align-items: center; }
  .dislike-action { grid-column: 1; }
  .like-action { grid-column: 2; }
  .reorder-handle { position: absolute; inset: 0; z-index: 1; display: grid; place-items: center; width: 28px; height: 30px; padding: 0; border: 0; border-radius: 6px; color: rgb(255 255 255 / 45%); background: transparent; cursor: grab; opacity: 0; pointer-events: none; }
  .queue-row:hover .queue-duration, .queue-row:focus-within .queue-duration { visibility: hidden; }
  .queue-row:hover .reorder-handle, .queue-row:focus-within .reorder-handle { opacity: 1; pointer-events: auto; }
  .reorder-handle svg { width: 16px; height: 14px; }
  .reorder-handle:hover { color: #fff; }
  .reorder-handle:active { cursor: grabbing; }
  .reorder-handle:disabled { cursor: wait; }
  .queue-action { display: grid; place-items: center; width: 28px; height: 30px; padding: 0; border: 0; border-radius: 6px; color: rgb(255 255 255 / 65%); background: transparent; cursor: pointer; opacity: 0; pointer-events: none; }
  .queue-action svg { width: 12px; height: 12px; }
  .queue-row:hover .queue-action, .queue-row:focus-within .queue-action { opacity: 1; pointer-events: auto; }
  .queue-action:hover { color: #fff; background: rgb(255 255 255 / 10%); }
  .queue-action.liked { color: #fff; opacity: 1; pointer-events: auto; }
  .queue-action:disabled { cursor: wait; opacity: .45; }
  .empty-panel { display: flex; min-width: 0; min-height: 0; flex: 1; flex-direction: column; align-items: center; justify-content: center; gap: 12px; padding: 20px; color: rgb(255 255 255 / 55%); text-align: center; }
  .empty-panel p { max-width: 32ch; margin: 0; font-size: 14px; font-weight: 500; }
  .empty-icon { width: 38px; height: 38px; color: rgb(255 255 255 / 25%); }
  .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
  button:focus-visible { outline: 2px solid #d06c70; outline-offset: 3px; }
  @media (prefers-reduced-motion: reduce) { .spinner { animation: none; } }
</style>
