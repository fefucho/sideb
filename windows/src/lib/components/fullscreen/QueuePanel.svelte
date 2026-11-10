<script lang="ts">
  import { t, language, count, resolveMessage, type AppMessage  } from '$lib/i18n';
  import { onMount, tick, untrack } from 'svelte';
  import TrackArtwork from '$lib/components/common/TrackArtwork.svelte';
  import TrackActivity from '$lib/components/common/TrackActivity.svelte';
  import { visibleTrackRange, trackSegments } from '$lib/components/common/trackList';
  import type { PlaybackStateDto, QueueEntryDto } from '$lib/types';
  import ArtistCredits from '$lib/components/ArtistCredits.svelte';
  import FeaturedTrackTitle from '$lib/components/FeaturedTrackTitle.svelte';
  import { promotedEntryId, queueDropDestination, queueIndexAtSlot, queueRowAt, queueRowCount, queueSections, queueSlotForEntry } from './queueProjection';

  interface Props {
    playback: PlaybackStateDto;
    focusQueueEntryId?: string | null;
    onQueueFocusHandled?: (entryId: string) => void;
    onSelectQueue: (index: number) => void;
    onTogglePlayback?: () => void;
    onOpenArtist?: (id: string, title: string) => void;
    onOpenAlbum?: (id: string) => void;
    onMoveQueue: (entryId: string, beforeEntryId: string | null) => void | PlaybackStateDto | Promise<void | PlaybackStateDto>;
    onRevealQueueWindow?: (startIndex: number, generation: number) => void | Promise<void>;
    onQueueContextMenu?: (event: MouseEvent, entry: QueueEntryDto) => void;
    onRetryRadio?: () => void;
    onRetrySource?: () => void;
    loggedIn?: boolean;
    likedIds?: Set<string>;
    pendingIds?: Set<string>;
    likesLoading?: boolean;
    onToggleLike?: (entry: QueueEntryDto) => void;
    onDislike?: (entry: QueueEntryDto) => void;
    onRecommendationAction?: (entryId: string, placement: 'next' | 'end' | 'now' | 'remove', generation: number) => void | PlaybackStateDto | Promise<void | PlaybackStateDto>;
  }
  let { playback, focusQueueEntryId = null, onQueueFocusHandled, onSelectQueue, onTogglePlayback, onOpenArtist, onOpenAlbum, onMoveQueue, onRevealQueueWindow, onQueueContextMenu, onRetryRadio, onRetrySource, loggedIn = false,
    likedIds = new Set<string>(), pendingIds = new Set<string>(), likesLoading = false, onToggleLike, onDislike, onRecommendationAction }: Props = $props();
  let draggingId = $state<string | null>(null);
  let draggingRecommendation = $state(false);
  let dropId = $state<string | null>(null);
  let dropAfter = $state(false);
  let movePending = $state(false);
  let moveError = $state<string | null>(null);
  let announcement = $state<AppMessage | null>(null);
  let queueList = $state<HTMLDivElement>();
  let awake = $state(false);
  let followingCurrent = true;
  let lastCurrentId: string | null = null;
  let lastIdentityIds: Set<string> | null = null;
  let lastAuthGeneration: number | undefined;
  let viewportAnchor: { id: string; offset: number } | null = null;
  let scrollTop = $state(untrack(() => Math.max(0, (playback.queue.currentIndex == null ? 0 : playback.queue.items[playback.queue.currentIndex]?.queueIndex ?? playback.queue.currentIndex) - 1) * 48));
  let viewportHeight = $state(480);
  let focusedEntryId = $state<string | null>(null);
  let revealInFlight: number | null = null;
  let revealRequested: number | null = null;
  const rowPitch = 48;
  const currentQueueIndex = $derived(playback.queue.currentIndex == null ? -1
    : playback.queue.items[playback.queue.currentIndex]?.queueIndex ?? playback.queue.currentIndex);
  const totalQueueCount = $derived(playback.queue.totalCount ?? Math.max(playback.queue.items.length,
    ...playback.queue.items.map((entry, index) => (entry.queueIndex ?? index) + 1)));
  const firstPendingQueueIndex = $derived(currentQueueIndex >= 0 ? currentQueueIndex + 1
    : Math.max(0, totalQueueCount - (playback.queue.pendingCount ?? totalQueueCount)));
  const sections = $derived(queueSections(playback.queue));
  const projectedRowCount = $derived(queueRowCount(sections));
  const visibleRows = $derived.by(() => {
    const range = visibleTrackRange(projectedRowCount, scrollTop, viewportHeight, rowPitch);
    const pinned = [focusedEntryId, draggingId].map(id => id ? queueSlotForEntry(sections, id) ?? -1 : -1);
    return trackSegments(projectedRowCount, range, pinned).flatMap(([start, end]) =>
      Array.from({ length: end - start }, (_, offset) => queueRowAt(sections, start + offset)).filter(Boolean));
  });
  function rememberAnchor() {
    const slot = Math.max(0, Math.floor(scrollTop / rowPitch));
    for (let i = slot; i < Math.min(projectedRowCount, slot + 8); i++) {
      const row = queueRowAt(sections, i);
      if (row?.kind === 'track') { viewportAnchor = { id: row.entry.entryId, offset: i * rowPitch - scrollTop }; return; }
    }
  }
  function stopFollowing() { followingCurrent = false; }
  $effect(() => {
    const list = queueList;
    const currentId = playback.queue.currentIndex == null ? null : playback.queue.items[playback.queue.currentIndex]?.entryId ?? null;
    const authGeneration = playback.authGeneration;
    const identityIds = new Set(playback.queue.items.map(entry => entry.entryId));
    const projection = sections;
    if (!list) return;
    untrack(() => {
      const newSession = lastIdentityIds === null || lastAuthGeneration !== authGeneration
        || identityIds.size > 0 && ![...identityIds].some(id => lastIdentityIds?.has(id));
      // Playback generation changes on every advance; occurrence IDs identify queue continuity.
      if (newSession) { followingCurrent = true; viewportAnchor = null; }
      const changed = lastCurrentId !== currentId;
      lastCurrentId = currentId; lastIdentityIds = identityIds; lastAuthGeneration = authGeneration;
      let target: number | null = null;
      if ((newSession || followingCurrent && changed) && currentId) {
        const slot = queueSlotForEntry(projection, currentId);
        if (slot !== null) target = Math.max(0, slot - 2) * rowPitch;
      } else if (viewportAnchor && !focusQueueEntryId) {
        const slot = queueSlotForEntry(projection, viewportAnchor.id);
        if (slot !== null) target = slot * rowPitch - viewportAnchor.offset;
      }
      if (target !== null) { list.scrollTop = Math.max(0, target); scrollTop = list.scrollTop; }
    });
  });
  function requestVisibleQueueWindow() {
    if (!onRevealQueueWindow || revealInFlight !== null) return;
    const [start, end] = visibleTrackRange(projectedRowCount, scrollTop, viewportHeight, rowPitch);
    for (let slot = start; slot < end; slot++) {
      const index = queueIndexAtSlot(sections, slot);
      if (index === null) continue;
      const loaded = playback.queue.items.some((entry, localIndex) => (entry.queueIndex ?? localIndex) === index);
      if (loaded || index === revealRequested) continue;
      revealRequested = index;
      revealInFlight = index;
      void Promise.resolve(onRevealQueueWindow(index, playback.generation)).catch(error => {
        moveError = error instanceof Error ? error.message : $t('windows.ui.couldnTCompleteTheUpdateOperation');
      }).finally(() => { if (revealInFlight === index) revealInFlight = null; });
      return;
    }
  }
  $effect(() => {
    const entryId = focusQueueEntryId;
    if (!entryId || !playback.queue.items.some(item => item.entryId === entryId) || !queueList) return;
    const slot = queueSlotForEntry(sections, entryId);
    if (slot === null) return;
    const rowTop = slot * rowPitch;
    if (rowTop < queueList.scrollTop) queueList.scrollTop = rowTop;
    else if (rowTop + rowPitch > queueList.scrollTop + queueList.clientHeight) queueList.scrollTop = rowTop + rowPitch - queueList.clientHeight;
    scrollTop = queueList.scrollTop;
    void tick().then(() => {
      const row = Array.from(queueList?.querySelectorAll<HTMLElement>('[data-entry-id]') ?? []).find(node => node.dataset.entryId === entryId);
      row?.querySelector<HTMLButtonElement>('button:not(:disabled)')?.focus();
      onQueueFocusHandled?.(entryId);
    });
  });
  $effect(() => {
    playback.queue; projectedRowCount; scrollTop; viewportHeight;
    requestVisibleQueueWindow();
  });
  function observeViewport(node: HTMLDivElement) {
    let frame = 0;
    const sync = () => { scrollTop = node.scrollTop; viewportHeight = node.clientHeight; rememberAnchor(); requestVisibleQueueWindow(); };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(() => { frame = 0; sync(); }); };
    const observer = new ResizeObserver(schedule);
    observer.observe(node);
    node.addEventListener('scroll', schedule, { passive: true });
    node.addEventListener('wheel', stopFollowing, { passive: true });
    node.addEventListener('pointerdown', stopFollowing);
    node.addEventListener('keydown', stopFollowing);
    // Keyboard events originate from native buttons; the group itself is not focusable.
    node.addEventListener('keydown', handleTab);
    node.scrollTop = scrollTop;
    sync();
    return { destroy() { observer.disconnect(); node.removeEventListener('scroll', schedule); node.removeEventListener('wheel', stopFollowing); node.removeEventListener('pointerdown', stopFollowing); node.removeEventListener('keydown', stopFollowing); node.removeEventListener('keydown', handleTab); if (frame) cancelAnimationFrame(frame); } };
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
    const slot = queueSlotForEntry(sections, row.dataset.entryId ?? '');
    if (slot === null) return;
    let nextSlot = slot + (event.shiftKey ? -1 : 1);
    let nextRow = queueRowAt(sections, nextSlot);
    while (nextRow?.kind === 'header') { nextSlot += event.shiftKey ? -1 : 1; nextRow = queueRowAt(sections, nextSlot); }
    if (!nextRow || nextRow.kind !== 'track') return;
    const nextEntryId = nextRow.entry.entryId;
    event.preventDefault();
    const rowTop = nextSlot * rowPitch;
    if (rowTop < queueList.scrollTop) queueList.scrollTop = rowTop;
    else if (rowTop + rowPitch > queueList.scrollTop + queueList.clientHeight) queueList.scrollTop = rowTop + rowPitch - queueList.clientHeight;
    scrollTop = queueList.scrollTop;
    await tick();
    const targetTrack = Array.from(queueList.querySelectorAll<HTMLElement>('[data-entry-id]')).find(node => node.dataset.entryId === nextEntryId);
    const nextControls = Array.from(targetTrack?.querySelectorAll<HTMLButtonElement>('button:not(:disabled)') ?? []);
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
    const proposal = playback.queue.recommendations?.some(item => item.entryId === entry.entryId);
    if (proposal) { void applyRecommendationAction(entry.entryId, 'now'); return; }
    const index = playback.queue.items.findIndex(item => item.entryId === entry.entryId);
    if (index < 0) return;
    if (index === playback.queue.currentIndex && onTogglePlayback) {
      if (!playback.isLoading) onTogglePlayback();
    } else {
      onSelectQueue(index);
    }
  }
  async function applyRecommendationAction(entryId: string, placement: 'next' | 'end' | 'now' | 'remove', beforeEntryId?: string | null) {
    if (!onRecommendationAction) return;
    try {
      stopFollowing();
      const oldIds = new Set(playback.queue.items.map(item => item.entryId));
      let result = await onRecommendationAction(entryId, placement, playback.generation);
      if (placement === 'remove') return;
      const addedId = result ? promotedEntryId(oldIds, result.queue) : null;
      if (beforeEntryId !== undefined && addedId) {
        const moved = await onMoveQueue(addedId, beforeEntryId);
        if (moved && typeof moved === 'object' && 'queue' in moved) result = moved;
      }
      if (!result || !addedId || !queueList) return;
      const slot = queueSlotForEntry(queueSections(result.queue), addedId);
      if (slot === null) return;
      const rowTop = slot * rowPitch;
      if (rowTop < queueList.scrollTop) queueList.scrollTop = rowTop;
      else if (rowTop + rowPitch > queueList.scrollTop + queueList.clientHeight) queueList.scrollTop = rowTop + rowPitch - queueList.clientHeight;
      scrollTop = queueList.scrollTop;
      await tick();
      const promotedRow = Array.from(queueList.querySelectorAll<HTMLElement>('[data-entry-id]')).find(node => node.dataset.entryId === addedId);
      promotedRow?.querySelector<HTMLButtonElement>('button:not(:disabled)')?.focus();
    } catch (error) {
      moveError = error instanceof Error ? error.message : $t('windows.ui.couldnTCompleteTheUpdateOperation');
    }
  }
  function sectionLabel(kind: string) {
    return $t(kind === 'recommendations' ? 'windows.queue.recommendations' : 'windows.queue.now');
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
  function resetDrag() { draggingId = null; draggingRecommendation = false; dropId = null; dropAfter = false; }
  $effect(() => {
    if (!draggingId) return;
    const sourceExists = draggingRecommendation
      ? playback.queue.recommendations?.some(entry => entry.entryId === draggingId)
      : playback.queue.items.some(entry => entry.entryId === draggingId);
    if (!sourceExists) resetDrag();
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
    const isRecommendation = playback.queue.recommendations?.some(item => item.entryId === entry.entryId) ?? false;
    const queueIndex = entry.queueIndex ?? playback.queue.items.findIndex(item => item.entryId === entry.entryId);
    draggingId = entry.entryId;
    draggingRecommendation = isRecommendation;
    moveError = null;
    event.dataTransfer.effectAllowed = isRecommendation || queueIndex >= firstPendingQueueIndex ? 'move' : 'copyMove';
    event.dataTransfer.setData('application/x-sideb-queue-entry', entry.entryId);
    event.dataTransfer.setData('text/plain', entry.title);
    const row = (event.currentTarget as HTMLElement).closest('.queue-row');
    if (row) event.dataTransfer.setDragImage(row, 24, 23);
  }
  function overRow(event: DragEvent, entry: QueueEntryDto) {
    if (!draggingId || movePending) return;
    const targetIndex = entry.queueIndex ?? playback.queue.items.findIndex(item => item.entryId === entry.entryId);
    const sourceIndex = draggingRecommendation ? currentQueueIndex + 1
      : playback.queue.items.find(item => item.entryId === draggingId)?.queueIndex
        ?? playback.queue.items.findIndex(item => item.entryId === draggingId);
    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
    const after = event.clientY >= rect.top + rect.height / 2;
    if (targetIndex < firstPendingQueueIndex && !(targetIndex === currentQueueIndex && after)) return;
    event.preventDefault();
    event.stopPropagation();
    if (event.dataTransfer) event.dataTransfer.dropEffect = !draggingRecommendation && sourceIndex < firstPendingQueueIndex ? 'copy' : 'move';
    dropId = entry.entryId;
    dropAfter = after;
    // Only the queue list scrolls; artwork and playback controls remain fixed.
    if (!queueList) return;
    const listRect = queueList.getBoundingClientRect();
    if (event.clientY < listRect.top + 32) queueList.scrollTop -= 12;
    else if (event.clientY > listRect.bottom - 32) queueList.scrollTop += 12;
  }
  async function move(entryId: string, beforeEntryId: string | null) {
    const index = playback.queue.items.findIndex(entry => entry.entryId === entryId);
    if (index < 0 || movePending) return;
    const sourceIndex = playback.queue.items[index].queueIndex ?? index;
    const destinationIndex = beforeEntryId === null ? null : playback.queue.items.find(item => item.entryId === beforeEntryId)?.queueIndex
      ?? playback.queue.items.findIndex(item => item.entryId === beforeEntryId);
    if (destinationIndex !== null && destinationIndex < firstPendingQueueIndex) return;
    if (sourceIndex >= firstPendingQueueIndex && (entryId === beforeEntryId || destinationIndex === sourceIndex + 1)) return;
    movePending = true;
    moveError = null;
    const title = playback.queue.items[index].title;
    const oldIds = new Set(playback.queue.items.map(item => item.entryId));
    stopFollowing();
    try {
      const result = await onMoveQueue(entryId, beforeEntryId);
      const placedId = result ? promotedEntryId(oldIds, result.queue) ?? entryId : entryId;
      if (result && queueList) {
        const slot = queueSlotForEntry(queueSections(result.queue), placedId);
        if (slot !== null) {
          const top = slot * rowPitch;
          if (top < queueList.scrollTop) queueList.scrollTop = top;
          else if (top + rowPitch > queueList.scrollTop + queueList.clientHeight) queueList.scrollTop = top + rowPitch - queueList.clientHeight;
          scrollTop = queueList.scrollTop;
          await tick();
          const row = Array.from(queueList.querySelectorAll<HTMLElement>('[data-entry-id]')).find(node => node.dataset.entryId === placedId);
          row?.querySelector<HTMLButtonElement>('button:not(:disabled)')?.focus();
        }
      }
      announcement = { key: sourceIndex < firstPendingQueueIndex ? 'windows.queue.requeued' : 'windows.queue.moved', args: [title] };
    } catch (error) {
      moveError = error instanceof Error ? error.message : $t('windows.ui.couldnTMoveTheSongTryAgain');
    } finally { movePending = false; }
  }
  function dropOnRow(event: DragEvent, entry: QueueEntryDto) {
    if (!draggingId) return;
    event.preventDefault();
    event.stopPropagation();
    const source = draggingId;
    if (draggingRecommendation) {
      const targetIndex = entry.queueIndex ?? playback.queue.items.findIndex(item => item.entryId === entry.entryId);
      const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
      const after = event.clientY >= rect.top + rect.height / 2;
      if (targetIndex < firstPendingQueueIndex && !(targetIndex === currentQueueIndex && after)) { resetDrag(); return; }
      const beforeEntryId = queueDropDestination(playback.queue.items, entry.entryId, after, totalQueueCount);
      resetDrag();
      if (beforeEntryId === undefined) return;
      void applyRecommendationAction(source, 'end', beforeEntryId);
      return;
    }
    const targetIndex = playback.queue.items.findIndex(item => item.entryId === entry.entryId);
    const targetGlobalIndex = entry.queueIndex ?? targetIndex;
    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
    const after = event.clientY >= rect.top + rect.height / 2;
    if (targetIndex < 0 || targetGlobalIndex < firstPendingQueueIndex && !(targetGlobalIndex === currentQueueIndex && after)) { resetDrag(); return; }
    const before = queueDropDestination(playback.queue.items, entry.entryId, after, totalQueueCount);
    resetDrag();
    if (before === undefined) return;
    void move(source, before);
  }
  function overList(event: DragEvent) {
    if (!draggingId || (event.target !== event.currentTarget && !(event.target instanceof Element && (event.target.classList.contains('queue-canvas') || event.target.closest('[data-queue-section="recommendations"]'))))) return;
    event.preventDefault();
    dropId = null;
    dropAfter = true;
    const source = playback.queue.items.find((entry, index) => entry.entryId === draggingId && (entry.queueIndex ?? index) < firstPendingQueueIndex);
    if (event.dataTransfer) event.dataTransfer.dropEffect = source ? 'copy' : 'move';
  }
  function dropAtEnd(event: DragEvent) {
    if (!draggingId || (event.target !== event.currentTarget && !(event.target instanceof Element && (event.target.classList.contains('queue-canvas') || event.target.closest('[data-queue-section="recommendations"]'))))) return;
    event.preventDefault();
    const source = draggingId;
    if (draggingRecommendation) {
      resetDrag();
      void applyRecommendationAction(source, 'end', null);
      return;
    }
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
    const globalIndex = entry.queueIndex ?? index;
    if (globalIndex < firstPendingQueueIndex) {
      if (event.key === 'ArrowDown') {
        const next = playback.queue.items.find(item => (item.queueIndex ?? playback.queue.items.indexOf(item)) === firstPendingQueueIndex);
        if (next) void move(entry.entryId, next.entryId);
        else if (firstPendingQueueIndex >= totalQueueCount) void move(entry.entryId, null);
      }
      return;
    }
    if (event.key === 'ArrowUp' && index > 0) {
      const previous = playback.queue.items[index - 1];
      if ((previous.queueIndex ?? index - 1) === globalIndex - 1 && (previous.queueIndex ?? index - 1) > currentQueueIndex) void move(entry.entryId, previous.entryId);
    } else if (event.key === 'ArrowDown' && globalIndex < totalQueueCount - 1) {
      const before = playback.queue.items.find(item => (item.queueIndex ?? playback.queue.items.indexOf(item)) === globalIndex + 2);
      if (before) void move(entry.entryId, before.entryId);
      else if (globalIndex + 1 === totalQueueCount - 1) void move(entry.entryId, null);
    }
  }
</script>

<svelte:window onkeydown={(event) => { if (event.key === 'Escape') resetDrag(); }} />

<div class="queue-content" data-queue-dragging={draggingId !== null}>
  {#if playback.queue.items.length || playback.queue.recommendations?.length || playback.sourceLoad?.loading || playback.sourceLoad?.error || playback.sourceLoad?.hasMore || playback.queue.radio?.loading || playback.queue.radio?.error || moveError}
  <header class="queue-heading">
    {#if playback.queue.items.length}
    <div class="queue-context">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        {#if playback.queue.source?.kind === 'radio'}<circle cx="12" cy="12" r="2" /><path d="M7 7a7 7 0 0 0 0 10M17 7a7 7 0 0 1 0 10M4 4a11 11 0 0 0 0 16M20 4a11 11 0 0 1 0 16" />
        {:else if playback.queue.source?.kind === 'album'}<circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="3" />
        {:else if playback.queue.source?.kind === 'playlist'}<path d="M3 5h10M3 10h10M3 15h6M17 5v13" /><ellipse cx="14" cy="18" rx="3" ry="2" />
        {:else}<path d="M8 6h12M8 12h12M8 18h12" /><path d="M3 6h.01M3 12h.01M3 18h.01" stroke-width="3" />{/if}
      </svg>
      <span class="context-title">{queueTitle}</span><span class="separator" aria-hidden="true">•</span><span class="count">{count('common.songCount', totalQueueCount, $language)}</span>
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
    {#if playback.isRepeat && playback.queue.recommendations?.length}<div class="radio-state" role="status">{$t('windows.queue.repeatStopsRadio')}</div>{/if}
    {#if moveError}<div class="radio-error" role="alert">{resolveMessage(moveError, $language)}</div>{/if}
  </header>
  {/if}
  <span class="sr-only" aria-live="polite">{resolveMessage(announcement, $language)}</span>
  <span id="queue-reorder-help" class="sr-only">{$t('windows.ui.dragToMoveTheSongOrUseTheUpAndDownArrowsWithThisButtonFocused')}</span>
  {#if projectedRowCount}
    <div class="queue-list" class:drop-end={draggingId && dropId === null && dropAfter} bind:this={queueList} use:observeViewport onfocusin={(event) => { stopFollowing(); focusedEntryId = entryIdOf(event.target); }} onfocusout={(event) => focusedEntryId = entryIdOf(event.relatedTarget)} role="group" aria-label={$t('windows.ui.queuedTracks')} ondragover={overList} ondrop={dropAtEnd} ondragleave={(event) => { if (!queueList?.contains(event.relatedTarget as Node | null)) { dropId = null; dropAfter = false; } }}>
      <div class="queue-canvas" style={`height:${projectedRowCount * rowPitch}px`}>
      {#each visibleRows as row (row?.slot)}
        {#if row?.kind === 'header'}
          <div class="queue-section-heading" data-queue-section={row.section} style={`top:${row.slot * rowPitch}px`} role="heading" aria-level="2">
            {sectionLabel(row.section)}
          </div>
        {:else if row?.kind === 'track'}
        {@const entry = row.entry}
        {@const index = row.queueLocalIndex}
        {@const proposal = row.section === 'recommendations'}
        {@const current = index !== null && index === playback.queue.currentIndex}
        <div class="queue-row track-row" data-entry-id={entry.entryId} style={`top:${row.slot * rowPitch}px`} role="group" aria-label={$t('common.moreOptionsFor', [entry.title])} class:current class:proposal class:previous={row.section === 'previous'} class:dragging={draggingId === entry.entryId} class:drop-before={draggingId && dropId === entry.entryId && !dropAfter} class:drop-after={draggingId && dropId === entry.entryId && dropAfter} draggable={!movePending} ondragstart={(event) => { if (event.target === event.currentTarget) startDrag(event, entry); }} ondragend={resetDrag} oncontextmenu={(event) => handleContextMenu(event, entry)} ondragover={(event) => overRow(event, entry)} ondrop={(event) => dropOnRow(event, entry)}>
          <button type="button" class="queue-select" aria-current={current ? 'true' : undefined} aria-label={`${current && playback.isPlaying ? $t('player.pause') : $t('player.play')} ${entry.title}`} disabled={current && playback.isLoading} onkeydown={(event) => contextMenuFromKeyboard(event, entry)} onclick={() => activateEntry(entry)}></button>
          <span class="queue-index" aria-hidden="true">{#if index !== null}<TrackActivity active={current} playing={playback.isPlaying} number={index + 1} {awake} presentation="queue" />{:else}<span>•</span>{/if}</span>
          <span class="queue-art"><TrackArtwork title={entry.title} thumbnail={entry.thumbnail} active={current} playing={playback.isPlaying} pending={current && playback.isLoading} size={36} showPlayOverlay={false} onPlay={() => activateEntry(entry)} /></span>
          <span class="queue-meta"><span class="queue-title"><FeaturedTrackTitle track={entry} onOpenArtist={onOpenArtist ? (id) => openArtist(entry,id) : undefined} onPlay={()=>activateEntry(entry)} /></span><ArtistCredits track={entry} artistRuns={entry.artistRuns} artists={entry.artists} artistId={entry.artistId} album={entry.album} albumId={entry.albumId} onOpenArtist={onOpenArtist ? (id) => openArtist(entry, id) : undefined} {onOpenAlbum} /></span>
          <span class="queue-actions">
          {#if onDislike}
            <button type="button" class="queue-action dislike-action" aria-label={$t('windows.queue.dislike', [entry.title])} title={$t('windows.ui.dislikeAndRemoveFromQueue')} disabled={movePending || playback.isLoading} onclick={(event) => { event.stopPropagation(); onDislike?.(entry); }} onpointerdown={(event) => event.stopPropagation()}>
              <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4H3v10h4M7 13l4 7a2 2 0 0 0 3-2l-1-4h5a3 3 0 0 0 3-3l-2-5a3 3 0 0 0-3-2H7Z" /></svg>
            </button>
          {/if}
          {#if loggedIn && onToggleLike}
            {@const liked = likedIds.has(entry.videoId)}
            {@const likePending = pendingIds.has(entry.videoId)}
            <button type="button" class="queue-action like-action" class:liked aria-pressed={liked} aria-label={liked ? $t('windows.queue.unlike', [entry.title]) : $t('windows.queue.like', [entry.title])} title={likePending ? $t('windows.ui.updatingLike') : liked ? $t('windows.ui.removeLike') : $t('detail.track.like')} disabled={likePending} onclick={(event) => { event.stopPropagation(); onToggleLike?.(entry); }} onpointerdown={(event) => event.stopPropagation()}>
              <svg viewBox="2 1.68 20 20" aria-hidden="true" fill={liked ? "currentColor" : "none"} stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 8.7c0 4.2-6.4 9.1-8.8 11-2.4-1.9-8.8-6.8-8.8-11a4.9 4.9 0 0 1 8.8-3.1 4.9 4.9 0 0 1 8.8 3.1Z" /></svg>
            </button>
          {/if}
          </span>
          <span class="queue-timing" class:has-trailing-action={proposal && !!onRecommendationAction || index !== null}><span class="queue-duration">{formatDuration(entry.duration)}</span>
          {#if proposal && onRecommendationAction}
            <button type="button" class="proposal-action" aria-label={$t('windows.queue.addEnd', [entry.title])} title={$t('windows.queue.addEnd', [entry.title])} onclick={(event) => { event.stopPropagation(); void applyRecommendationAction(entry.entryId, 'end'); }}>＋</button>
          {/if}

          {#if !proposal && index !== null}<button type="button" class="reorder-handle" aria-label={$t('windows.queue.move', [entry.title])} aria-describedby="queue-reorder-help" title={$t('windows.ui.dragToReorderOnKeyboard')} disabled={movePending} draggable={!movePending} ondragstart={(event) => startDrag(event, entry)} ondragend={resetDrag} onkeydown={(event) => reorderWithKeyboard(event, entry)} onclick={(event) => event.stopPropagation()}>
            <svg viewBox="0 0 16 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><path d="M1 3h14M1 7h14M1 11h14" /></svg>
          </button>{/if}
          </span>
        </div>
        {/if}
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
  .queue-list { min-width: 0; min-height: 0; flex: 1; overflow-x: hidden; overflow-y: auto; overscroll-behavior: contain; scrollbar-color: rgb(255 255 255 / 28%) transparent; scrollbar-width: thin; }
  .queue-canvas { position: relative; min-height: 100%; }
  .queue-section-heading { position: absolute; left: 0; right: 0; display: flex; align-items: center; box-sizing: border-box; height: 46px; padding: 0 18px; color: rgb(255 255 255 / 58%); font-size: 12px; font-weight: 600; }
  .queue-row { position: absolute; left: 0; right: 0; display: grid; grid-template-columns: 24px 46px minmax(0, 1fr) 86px 36px; box-sizing: border-box; min-width: 0; height: 46px; align-items: center; margin: 0; padding: 0 18px 0 16px; border-radius: 6px; }
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
  .previous .queue-title { color: rgb(255 255 255 / 60%); }
  .previous .queue-art { opacity: .6; }
  .current .queue-title { font-weight: 650; }
  .queue-meta :global(.artist-credits) { color: rgb(255 255 255 / 60%); font-size: 11.5px; line-height: 14px; }
  .queue-meta :global(.credit-link),.queue-meta :global(.featured-link),.queue-meta :global(.title-text) { pointer-events: auto; }
  .queue-duration { width: max-content; min-width: 28px; color: rgb(255 255 255 / 45%); font-size: 11.5px; font-variant-numeric: tabular-nums; text-align: center; white-space: nowrap; pointer-events: none; }
  .queue-timing { position: relative; z-index: 1; display: grid; grid-template-columns: minmax(0, 1fr); place-items: center; width: 28px; height: 30px; margin-left: 8px; pointer-events: none; }
  .queue-actions { position: relative; z-index: 1; display: flex; justify-content: flex-end; gap: 2px; align-items: center; }
  .proposal-action { position: absolute; inset: 0; z-index: 1; display: grid; place-items: center; width: 28px; height: 30px; padding: 0; border: 0; border-radius: 6px; color: rgb(255 255 255 / 65%); background: transparent; font-size: 16px; cursor: pointer; opacity: 0; pointer-events: none; }
  .queue-row:hover .proposal-action, .queue-row:focus-within .proposal-action { opacity: 1; pointer-events: auto; }
  .proposal-action:hover { color: #fff; background: rgb(255 255 255 / 10%); }
  .dislike-action { grid-column: 1; }
  .like-action { grid-column: 2; }
  .reorder-handle { position: absolute; inset: 0; z-index: 1; display: grid; place-items: center; width: 28px; height: 30px; padding: 0; border: 0; border-radius: 6px; color: rgb(255 255 255 / 45%); background: transparent; cursor: grab; opacity: 0; pointer-events: none; }
  .queue-row:hover .has-trailing-action .queue-duration, .queue-row:focus-within .has-trailing-action .queue-duration { visibility: hidden; }
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
