<script lang="ts">
  import type { PlaybackStateDto, QueueEntryDto } from '$lib/types';
  import ArtistCredits from '$lib/components/ArtistCredits.svelte';

  interface Props {
    playback: PlaybackStateDto;
    onSelectQueue: (index: number) => void;
    onMoveQueue: (entryId: string, beforeEntryId: string | null) => void | Promise<void>;
    onQueueContextMenu?: (event: MouseEvent, entry: QueueEntryDto) => void;
    onRetryRadio?: () => void;
    loggedIn?: boolean;
    likedIds?: Set<string>;
    pendingIds?: Set<string>;
    likesLoading?: boolean;
    onToggleLike?: (entry: QueueEntryDto) => void;
    onDislike?: (entry: QueueEntryDto) => void;
  }
  let { playback, onSelectQueue, onMoveQueue, onQueueContextMenu, onRetryRadio, loggedIn = false,
    likedIds = new Set<string>(), pendingIds = new Set<string>(), likesLoading = false, onToggleLike, onDislike }: Props = $props();
  let draggingId = $state<string | null>(null);
  let dropId = $state<string | null>(null);
  let dropAfter = $state(false);
  let movePending = $state(false);
  let moveError = $state<string | null>(null);
  let announcement = $state('');
  let queueList = $state<HTMLDivElement>();
  const queueTitle = $derived(playback.queue.source?.kind === 'radio'
    ? `Radio de ${playback.queue.source.title || playback.currentTrack?.title || 'esta canción'}`
    : playback.queue.source?.title || 'Cola de reproducción');

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
      announcement = `Se movió ${title} en la cola.`;
    } catch (error) {
      moveError = error instanceof Error ? error.message : 'No se pudo mover la canción. Volvé a intentar.';
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
    if (!draggingId || event.target !== event.currentTarget) return;
    event.preventDefault();
    dropId = null;
    dropAfter = true;
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
  }
  function dropAtEnd(event: DragEvent) {
    if (!draggingId || event.target !== event.currentTarget) return;
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
  <header class="queue-heading">
    <div class="queue-context"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16" /></svg><span>{queueTitle}</span><span class="separator" aria-hidden="true">·</span><span class="count">{playback.queue.items.length} canciones</span></div>
    {#if playback.queue.radio?.loading}<span class="radio-state" role="status"><span class="spinner" aria-hidden="true"></span>Preparando radio…</span>
    {:else if playback.queue.radio?.error}<div class="radio-error" role="alert"><span>{playback.queue.radio.error}</span>{#if playback.queue.radio.canRetry && onRetryRadio}<button type="button" onclick={onRetryRadio}>Reintentar</button>{/if}</div>{/if}
    {#if moveError}<div class="radio-error" role="alert">{moveError}</div>{/if}
  </header>
  <span class="sr-only" aria-live="polite">{announcement}</span>
  <span id="queue-reorder-help" class="sr-only">Arrastrá para mover la canción, o usá las flechas arriba y abajo con este botón enfocado.</span>
  {#if playback.queue.items.length}
    <div class="queue-list" class:drop-end={draggingId && dropId === null && dropAfter} bind:this={queueList} role="group" aria-label="Pistas en cola" ondragover={overList} ondrop={dropAtEnd} ondragleave={(event) => { if (!queueList?.contains(event.relatedTarget as Node | null)) { dropId = null; dropAfter = false; } }}>
      {#each playback.queue.items as entry, index (entry.entryId)}
        <div class="queue-row" role="group" aria-label={`Opciones de ${entry.title}`} class:current={index === playback.queue.currentIndex} class:dragging={draggingId === entry.entryId} class:drop-before={draggingId && dropId === entry.entryId && !dropAfter} class:drop-after={draggingId && dropId === entry.entryId && dropAfter} class:has-menu={!!onQueueContextMenu} oncontextmenu={(event) => handleContextMenu(event, entry)} ondragover={(event) => overRow(event, entry)} ondrop={(event) => dropOnRow(event, entry)}>
          <button type="button" class="queue-select" aria-current={index === playback.queue.currentIndex ? 'true' : undefined} aria-label={`Reproducir ${entry.title}`} onclick={() => { if (!draggingId) onSelectQueue(index); }}>
            <span class="queue-index">{#if index === playback.queue.currentIndex}<svg viewBox="0 0 24 24" aria-label={playback.isPlaying ? 'Sonando' : 'Pausado'} fill="currentColor"><path d="M3 9v6h4l5 5V4L7 9zm12.5 3a4 4 0 0 0-2-3.46v6.92a4 4 0 0 0 2-3.46" /></svg>{:else}{index + 1}{/if}</span>
            <span class="queue-art">{#if entry.thumbnail}<img src={entry.thumbnail} alt="" loading="lazy" draggable="false" />{:else}<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>{/if}</span>
            <span class="queue-meta"><span class="queue-title">{entry.title}</span><ArtistCredits artistRuns={entry.artistRuns} artists={entry.artists} album={entry.album} /></span>
            <span class="queue-duration">{formatDuration(entry.duration)}</span>
          </button>
          <button type="button" class="reorder-handle" aria-label={`Mover ${entry.title} en la cola`} aria-describedby="queue-reorder-help" title="Arrastrar para reordenar (↑/↓ con el teclado)" disabled={movePending} draggable={!movePending} ondragstart={(event) => startDrag(event, entry)} ondragend={resetDrag} onkeydown={(event) => reorderWithKeyboard(event, entry)} onclick={(event) => event.stopPropagation()}>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16" /></svg>
          </button>
          {#if loggedIn && onToggleLike}
            {@const liked = likedIds.has(entry.videoId)}
            {@const likePending = (likesLoading && !liked) || pendingIds.has(entry.videoId)}
            <button type="button" class="queue-action like-action" class:liked aria-pressed={liked} aria-label={liked ? `Quitar Me gusta de ${entry.title}` : `Marcar ${entry.title} como Me gusta`} title={likePending ? "Actualizando Me gusta…" : liked ? "Quitar Me gusta" : "Me gusta"} disabled={likePending} onclick={(event) => { event.stopPropagation(); onToggleLike?.(entry); }} onpointerdown={(event) => event.stopPropagation()}>
              <svg viewBox="0 0 24 24" aria-hidden="true" fill={liked ? "currentColor" : "none"} stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 8.7c0 4.2-6.4 9.1-8.8 11-2.4-1.9-8.8-6.8-8.8-11a4.9 4.9 0 0 1 8.8-3.1 4.9 4.9 0 0 1 8.8 3.1Z" /></svg>
            </button>
          {/if}
          {#if onDislike}
            <button type="button" class="queue-action dislike-action" aria-label={`No me gusta y quitar ${entry.title} de la cola`} title="No me gusta y quitar de la cola" disabled={movePending || playback.isLoading} onclick={(event) => { event.stopPropagation(); onDislike?.(entry); }} onpointerdown={(event) => event.stopPropagation()}>
              <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 10V4H4a2 2 0 0 0-2 2v4a2 2 0 0 0 2 2h3m0-2 3-7a2 2 0 0 1 2-1h5a2 2 0 0 1 2 2l-1 6h2a2 2 0 0 1 2 2l-2 8a2 2 0 0 1-2 2h-7l-6-5v-7Z" /></svg>
            </button>
          {/if}
          {#if onQueueContextMenu}<button type="button" class="row-menu" aria-label={`Más opciones para ${entry.title}`} title="Más opciones" onclick={(event) => onQueueContextMenu?.(event, entry)}><svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg></button>{/if}
        </div>
      {/each}
    </div>
  {:else}
    <div class="empty-panel"><svg class="empty-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16" /></svg><p>No hay pistas en la cola</p></div>
  {/if}
</div>

<style>
  .queue-content { display: flex; width: 100%; min-width: 0; min-height: 0; flex: 1; flex-direction: column; overflow: hidden; }
  .queue-heading { display: flex; flex: none; min-width: 0; flex-direction: column; gap: 8px; padding: 2px 8px 8px; }
  .queue-context { display: flex; min-width: 0; align-items: center; gap: 8px; color: rgb(255 255 255 / 90%); font-size: 12px; font-weight: 650; }
  .queue-context svg { flex: 0 0 14px; width: 14px; height: 14px; }
  .queue-context > span:nth-child(2) { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .count { flex: none; color: rgb(255 255 255 / 53%); font-size: 11px; font-weight: 500; white-space: nowrap; }
  .radio-state, .radio-error { display: flex; align-items: center; gap: 8px; color: rgb(255 255 255 / 67%); font-size: 11px; }
  .radio-error { color: #ffb7bb; }
  .radio-error button { flex: none; padding: 3px 8px; border: 1px solid rgb(255 255 255 / 15%); border-radius: 999px; color: #fff; background: rgb(255 255 255 / 8%); font: inherit; cursor: pointer; }
  .spinner { width: 12px; height: 12px; border: 2px solid rgb(255 255 255 / 24%); border-top-color: #d06c70; border-radius: 50%; animation: spin .8s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .queue-list { min-width: 0; min-height: 0; flex: 1; overflow-y: auto; overscroll-behavior: contain; scrollbar-color: rgb(255 255 255 / 28%) transparent; scrollbar-width: thin; }
  .queue-row { position: relative; display: flex; min-width: 0; align-items: center; gap: 6px; margin-bottom: 2px; padding: 0 4px; border-radius: 8px; }
  .queue-row:hover, .queue-row.current { background: rgb(255 255 255 / 7%); }
  .queue-row.dragging { opacity: .5; }
  .queue-row.drop-before::before, .queue-row.drop-after::after { position: absolute; z-index: 1; left: 4px; right: 4px; height: 2px; background: #d06c70; content: ''; pointer-events: none; }
  .queue-row.drop-before::before { top: 0; }
  .queue-row.drop-after::after { bottom: 0; }
  .queue-list.drop-end { box-shadow: inset 0 -2px #d06c70; }
  .queue-select { box-sizing: border-box; display: flex; min-width: 0; flex: 1; height: 46px; align-items: center; gap: 6px; padding: 3px 122px 3px 2px; border: 0; border-radius: 7px; color: inherit; background: transparent; font: inherit; text-align: left; cursor: pointer; }
  .queue-art { display: grid; flex: 0 0 36px; margin-right: 9px; place-items: center; width: 36px; height: 36px; overflow: hidden; border-radius: 6px; color: rgb(255 255 255 / 58%); background: rgb(255 255 255 / 10%); }
  .queue-art img { width: 100%; height: 100%; object-fit: cover; }
  .queue-art svg { width: 19px; height: 19px; }
  .queue-meta { display: flex; min-width: 0; flex: 1; flex-direction: column; gap: 3px; }
  .queue-title { display: block; min-width: 0; overflow: hidden; padding: 0; border: 0; color: rgb(255 255 255 / 92%); background: transparent; font: inherit; font-size: 13px; font-weight: 500; line-height: 16px; text-align: left; text-overflow: ellipsis; white-space: nowrap; }
  .current .queue-title { font-weight: 650; }
  .queue-meta :global(.artist-credits) { color: rgb(255 255 255 / 60%); font-size: 11.5px; line-height: 14px; }
  .queue-index { display: grid; flex: 0 0 22px; place-items: center; color: rgb(255 255 255 / 55%); font-size: 11.5px; }
  .queue-index svg { width: 12px; height: 12px; color: white; }
  .queue-duration { position: absolute; right: 6px; }
  .has-menu .queue-duration { right: 42px; }
  .queue-duration { flex: 0 0 36px; color: rgb(255 255 255 / 45%); font-size: 11.5px; font-variant-numeric: tabular-nums; text-align: right; }
  .queue-row:hover .queue-duration, .queue-row:focus-within .queue-duration { visibility: hidden; }
  .reorder-handle { position: absolute; top: 8px; right: 6px; display: grid; place-items: center; width: 36px; height: 30px; padding: 6px; border: 0; border-radius: 6px; color: rgb(255 255 255 / 45%); background: transparent; cursor: grab; opacity: 0; }
  .has-menu .reorder-handle { right: 42px; }
  .queue-row:hover .reorder-handle, .queue-row:focus-within .reorder-handle { opacity: 1; }
  .reorder-handle svg { width: 18px; height: 16px; }
  .reorder-handle:hover { color: #fff; }
  .reorder-handle:active { cursor: grabbing; }
  .reorder-handle:disabled { cursor: wait; opacity: .4; }
  .queue-action { position: absolute; top: 8px; display: grid; place-items: center; width: 30px; height: 30px; padding: 6px; border: 0; border-radius: 6px; color: rgb(255 255 255 / 68%); background: transparent; cursor: pointer; opacity: 0; pointer-events: none; }
  .queue-action svg { width: 17px; height: 17px; }
  .like-action { right: 50px; }
  .has-menu .like-action { right: 86px; }
  .dislike-action { right: 86px; }
  .has-menu .dislike-action { right: 122px; }
  .queue-row:hover .queue-action, .queue-row:focus-within .queue-action { opacity: 1; pointer-events: auto; }
  .queue-action:hover { color: #fff; background: rgb(255 255 255 / 10%); }
  .queue-action.liked { color: #d06c70; opacity: 1; pointer-events: auto; }
  .queue-row:hover .dislike-action:disabled, .queue-row:focus-within .dislike-action:disabled { opacity: .45; }
  .queue-action:disabled { cursor: wait; }
  .row-menu { display: grid; flex: 0 0 30px; place-items: center; width: 30px; height: 30px; border: 0; border-radius: 6px; color: rgb(255 255 255 / 60%); background: transparent; cursor: pointer; }
  .row-menu svg { width: 16px; height: 16px; }
  .row-menu:hover { color: #fff; background: rgb(255 255 255 / 10%); }
  .empty-panel { display: flex; min-width: 0; min-height: 0; flex: 1; flex-direction: column; align-items: center; justify-content: center; gap: 12px; padding: 20px; color: rgb(255 255 255 / 55%); text-align: center; }
  .empty-panel p { max-width: 32ch; margin: 0; font-size: 14px; }
  .empty-icon { width: 36px; height: 36px; color: rgb(255 255 255 / 28%); }
  .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
  button:focus-visible { outline: 2px solid #d06c70; outline-offset: 3px; }
  @media (prefers-reduced-motion: reduce) { .spinner { animation: none; } }
</style>
