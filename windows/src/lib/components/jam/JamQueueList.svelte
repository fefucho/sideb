<script lang="ts">
  import { readable } from 'svelte/store';
  import { t, language, count } from '$lib/i18n';
  import TrackActivity from '$lib/components/common/TrackActivity.svelte';
  import { emptyJamState, type JamMatchedSong, type JamTrackView } from '$lib/jam/types';
  import type { PlaybackStateDto, QueueEntryDto } from '$lib/types';
  import JamVersionPicker from './JamVersionPicker.svelte';
  import { useJamUi } from './context';
  import { formatMs, formatSecs, jamTitle, mergeJamQueue, trackArtists, trackTitle } from './view';

  /**
   * Queue of a live Jam (replaces the native list + recommendations while the Jam owns the queue). The Jam order is the
   * truth: matched rows mirror a native occurrence (activation, context menu); `searching` / `unavailable` rows exist
   * only here and are dimmed (macOS `JamPlaceholderCellView`).
   */
  interface Props {
    playback: PlaybackStateDto;
    onSelectQueue?: (index: number) => void;
    onTogglePlayback?: () => void;
    onQueueContextMenu?: (event: MouseEvent, entry: QueueEntryDto) => void;
  }
  let { playback, onSelectQueue, onTogglePlayback, onQueueContextMenu }: Props = $props();
  const ui = useJamUi();
  const jamState = ui?.state ?? readable(emptyJamState());

  const rows = $derived(mergeJamQueue($jamState.queue, playback));
  const current = $derived($jamState.current);
  const total = $derived((current ? 1 : 0) + $jamState.queue.length);
  let pickerKey = $state<string | null>(null);
  let dragFrom = $state<number | null>(null);
  let dropSlot = $state<number | null>(null);
  let announcement = $state('');
  const pickerTrack = $derived(pickerKey === null ? null : (current?.key === pickerKey ? current : $jamState.queue.find(track => track.key === pickerKey) ?? null));
  $effect(() => { if (pickerKey !== null && !pickerTrack) pickerKey = null; });
  $effect(() => { if (dragFrom !== null && dragFrom >= $jamState.queue.length) { dragFrom = null; dropSlot = null; } });

  const statusText = (track: JamTrackView) => track.status === 'unavailable' ? $t('jam.queue.unavailable') : $t('jam.queue.resolving');
  const playable = (track: JamTrackView) => track.status === 'matched' && !!track.matched;

  function pick(song: JamMatchedSong) {
    if (pickerKey === null) return;
    void ui?.actions.correctMatch(pickerKey, song);
    pickerKey = null;
  }
  function activate(row: (typeof rows)[number]) {
    if (dragFrom !== null || row.nativeIndex === null) return;
    onSelectQueue?.(row.nativeIndex);
  }
  function contextMenu(event: MouseEvent, entry: QueueEntryDto | null) {
    if (!entry || !onQueueContextMenu) return;
    event.preventDefault();
    onQueueContextMenu(event, entry);
  }
  function move(from: number, to: number) {
    const size = $jamState.queue.length;
    if (!ui || from === to || to < 0 || to >= size) return;
    announcement = $t('jam.action.moved', [trackTitle($jamState.queue[from])]);
    void ui.actions.moveQueue(from, to);
  }
  function startDrag(event: DragEvent, index: number) {
    if (!event.dataTransfer) { event.preventDefault(); return; }
    dragFrom = index;
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', trackTitle($jamState.queue[index]));
    const row = (event.currentTarget as HTMLElement).closest('[data-jam-row]');
    if (row) event.dataTransfer.setDragImage(row, 24, 23);
  }
  function overRow(event: DragEvent, index: number) {
    if (dragFrom === null) return;
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
    dropSlot = event.clientY >= rect.top + rect.height / 2 ? index + 1 : index;
  }
  function drop(event: DragEvent) {
    if (dragFrom === null || dropSlot === null) { resetDrag(); return; }
    event.preventDefault();
    const from = dragFrom, slot = dropSlot;
    resetDrag();
    // `to` is the final position of the moved track in the Jam queue (array-move semantics).
    move(from, slot > from ? slot - 1 : slot);
  }
  function resetDrag() { dragFrom = null; dropSlot = null; }
  function reorderKey(event: KeyboardEvent, index: number) {
    if (event.key === 'Escape') { resetDrag(); return; }
    if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;
    event.preventDefault(); event.stopPropagation();
    move(index, index + (event.key === 'ArrowDown' ? 1 : -1));
  }
</script>

<svelte:window onkeydown={(event) => { if (event.key === 'Escape') resetDrag(); }} />

<div class="jam-queue" data-jam-queue data-queue-dragging={dragFrom !== null}>
  <header class="heading">
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="8" cy="8" r="3.2" /><path d="M2 20c0-3.800 2.700-6 6-6s6 2.200 6 6Z" /><circle cx="16.500" cy="9" r="2.600" /><path d="M15.500 14.400c3.800-.6 6.500 1.400 6.500 5.600h-5.500c0-2.400-.3-4.200-1-5.600Z" /></svg>
    <span class="context" data-jam-queue-title>{jamTitle($jamState, $language)}</span><span class="separator" aria-hidden="true">•</span><span class="count">{count('common.songCount', total, $language)}</span>
  </header>
  <span class="sr-only" aria-live="polite">{announcement}</span>
  <span id="jam-queue-reorder-help" class="sr-only">{$t('windows.ui.dragToMoveTheSongOrUseTheUpAndDownArrowsWithThisButtonFocused')}</span>
  {#if pickerTrack}
    {#key pickerTrack.key}
      <div class="picker"><JamVersionPicker query={[pickerTrack.title, pickerTrack.artists].filter(Boolean).join(' ')} currentVideoId={pickerTrack.matched?.videoId ?? null} search={ui?.searchSongs ?? (async () => [])} onPick={pick} onClose={() => pickerKey = null} /></div>
    {/key}
  {/if}
  {#if total}
    <div class="list" role="group" aria-label={$t('windows.ui.queuedTracks')} class:drop-end={dragFrom !== null && dropSlot === rows.length} ondragover={(event) => { if (dragFrom !== null && event.target === event.currentTarget) { event.preventDefault(); dropSlot = rows.length; } }} ondrop={drop} ondragleave={(event) => { if (!(event.currentTarget as HTMLElement).contains(event.relatedTarget as Node | null)) dropSlot = null; }}>
      {#if current}
        {@const art = current.matched?.thumbnail ?? null}
        <div class="row now" data-jam-row="current" data-status={current.status} role="group" aria-label={`${$t('windows.jam.queue.nowPlaying')}: ${trackTitle(current)}`} oncontextmenu={(event) => { const entry = playback.queue.currentIndex === null ? null : playback.queue.items[playback.queue.currentIndex] ?? null; contextMenu(event, entry); }}>
          <button type="button" class="select" disabled={!onTogglePlayback || playback.isLoading} aria-label={`${playback.isPlaying ? $t('player.pause') : $t('player.play')} ${trackTitle(current)}`} onclick={() => onTogglePlayback?.()}></button>
          <span class="num" aria-hidden="true"><TrackActivity active playing={playback.isPlaying} presentation="queue" /></span>
          <span class="art" aria-hidden="true">{#if art}<img src={art} alt="" loading="lazy" decoding="async" draggable="false" />{:else if playable(current)}<svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>{:else if current.status === 'unavailable'}<svg class="alert" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><circle cx="12" cy="12" r="9" /><path d="M12 7v6M12 16.500v.5" stroke-linecap="round" /></svg>{:else}<span class="spinner"></span>{/if}</span>
          <span class="meta"><span class="title">{trackTitle(current)}</span><span class="sub">{trackArtists(current)}</span></span>
          <span class="actions"><button type="button" class="action" data-jam-pick={current.key} aria-label={$t('windows.jam.queue.pickVersion', [trackTitle(current)])} title={$t('jam.versions.choose')} onclick={() => pickerKey = pickerKey === current.key ? null : current.key}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.500-3.500" /></svg></button></span>
          <span class="timing"><span class="duration">{current.matched?.durationSecs ? formatSecs(current.matched.durationSecs) : formatMs(current.durationMs)}</span></span>
        </div>
      {/if}
      {#each rows as row (row.track.key + ':' + row.index)}
        {@const track = row.track}
        {@const ok = playable(track)}
        {@const searching = track.status !== 'matched' && track.status !== 'unavailable'}
        <div class="row" class:dim={!ok} class:dragging={dragFrom === row.index} class:drop-before={dragFrom !== null && dropSlot === row.index}
          data-jam-row={row.index} data-status={track.status} role="group" aria-label={ok ? $t('common.moreOptionsFor', [trackTitle(track)]) : `${trackTitle(track)}, ${statusText(track)}`}
          draggable={!!ui} ondragstart={(event) => { if (event.target === event.currentTarget) startDrag(event, row.index); }} ondragend={resetDrag}
          oncontextmenu={(event) => contextMenu(event, row.entry)} ondragover={(event) => overRow(event, row.index)} ondrop={drop}>
          <button type="button" class="select" disabled={row.nativeIndex === null} aria-label={`${$t('player.play')} ${trackTitle(track)}`} onclick={() => activate(row)}></button>
          <span class="num" aria-hidden="true">{row.number}</span>
          <span class="art" aria-hidden="true">
            {#if ok && track.matched?.thumbnail}<img src={track.matched.thumbnail} alt="" loading="lazy" decoding="async" draggable="false" />
            {:else if ok}<svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>
            {:else if searching}<span class="spinner"></span>
            {:else}<svg class="alert" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><circle cx="12" cy="12" r="9" /><path d="M12 7v6M12 16.500v.5" stroke-linecap="round" /></svg>{/if}
          </span>
          <span class="meta">
            <span class="title" title={trackTitle(track)}>{trackTitle(track)}</span>
            {#if ok}<span class="sub" title={trackArtists(track)}>{trackArtists(track)}</span>
            {:else}<span class="sub status" class:warn={track.status === 'unavailable'} data-jam-row-status title={trackArtists(track)}>{statusText(track)}</span>{/if}
          </span>
          <span class="actions">
            <button type="button" class="action" data-jam-pick={track.key} aria-label={$t('windows.jam.queue.pickVersion', [trackTitle(track)])} title={$t('jam.versions.choose')} onclick={() => pickerKey = pickerKey === track.key ? null : track.key}>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.500-3.500" /></svg>
            </button>
            <button type="button" class="action" data-jam-remove={row.index} aria-label={$t('windows.jam.queue.remove', [trackTitle(track)])} title={$t('windows.jam.queue.remove', [trackTitle(track)])} onclick={() => void ui?.actions.removeQueue(row.index)}>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.200" stroke-linecap="round" aria-hidden="true"><path d="M6 6 18 18M18 6 6 18" /></svg>
            </button>
          </span>
          <span class="timing has-handle"><span class="duration">{formatMs(track.durationMs)}</span>
            <button type="button" class="handle" data-jam-handle={row.index} aria-label={$t('windows.jam.queue.move', [trackTitle(track)])} aria-describedby="jam-queue-reorder-help" title={$t('windows.ui.dragToReorderOnKeyboard')} draggable="true" ondragstart={(event) => startDrag(event, row.index)} ondragend={resetDrag} onkeydown={(event) => reorderKey(event, row.index)} onclick={(event) => event.stopPropagation()}>
              <svg viewBox="0 0 16 14" fill="none" stroke="currentColor" stroke-width="1.500" stroke-linecap="round" aria-hidden="true"><path d="M1 3h14M1 7h14M1 11h14" /></svg>
            </button>
          </span>
        </div>
      {/each}
    </div>
  {:else}
    <div class="empty"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.600" stroke-linecap="round" aria-hidden="true"><path d="M3 5h10M3 10h10M3 15h6M18 5v13" /><ellipse cx="15" cy="18" rx="3" ry="2" /></svg><p>{$t('windows.jam.queue.empty')}</p></div>
  {/if}
</div>

<style>
  .jam-queue { display: flex; flex-direction: column; width: 100%; min-width: 0; min-height: 0; flex: 1; overflow: hidden; }
  .heading { display: flex; flex: none; align-items: center; flex-wrap: wrap; gap: 4px 8px; min-width: 0; padding: 2px 8px 8px; color: rgb(255 255 255 / 90%); font-size: 12px; font-weight: 600; }
  .heading > svg { flex: 0 0 12px; width: 12px; height: 12px; }
  .context { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .separator { flex: none; color: rgb(255 255 255 / 30%); font-size: 10px; font-weight: 400; }
  .count { flex: none; color: rgb(255 255 255 / 50%); font-size: 11px; font-weight: 500; white-space: nowrap; }
  .picker { flex: none; padding: 0 8px 8px; }
  .list { min-width: 0; min-height: 0; flex: 1; overflow-x: hidden; overflow-y: auto; overscroll-behavior: contain; scrollbar-color: rgb(255 255 255 / 28%) transparent; scrollbar-width: thin; }
  .list.drop-end { box-shadow: inset 0 -2px var(--sideb-highlight); }
  .row { position: relative; display: grid; grid-template-columns: 24px 46px minmax(0, 1fr) 58px 36px; box-sizing: border-box; min-width: 0; height: 46px; align-items: center; padding: 0 18px 0 16px; border-radius: 6px; }
  .select { position: absolute; inset: 0; z-index: 0; display: block; width: 100%; height: 100%; padding: 0; border: 0; border-radius: inherit; background: transparent; cursor: pointer; }
  .select:disabled { cursor: default; }
  .select::before { position: absolute; inset: 1px 10px; border: .5px solid transparent; border-radius: 6px; content: ''; pointer-events: none; }
  .row:hover .select::before { background: rgb(255 255 255 / 4.5%); }
  .row.now .select::before { border-color: rgb(255 255 255 / 9%); background: rgb(255 255 255 / 6.5%); }
  .row.dragging { opacity: .5; }
  .row.drop-before::before { position: absolute; z-index: 3; top: 0; left: 4px; right: 4px; height: 2px; background: var(--sideb-highlight); content: ''; pointer-events: none; }
  .num { display: grid; place-items: center; color: rgb(255 255 255 / 45%); font-size: 11.5px; font-variant-numeric: tabular-nums; pointer-events: none; }
  .art { position: relative; z-index: 1; display: grid; place-items: center; width: 36px; height: 36px; margin-left: 10px; overflow: hidden; border-radius: var(--sideb-track-artwork-radius, 2px); color: rgb(255 255 255 / 40%); background: rgb(255 255 255 / 5%); pointer-events: none; }
  .row.dim .art { box-shadow: inset 0 0 0 1px rgb(255 255 255 / 7%); }
  .art img { width: 100%; height: 100%; object-fit: cover; } .art svg { width: 16px; height: 16px; } .art .alert { color: rgb(242 184 107 / 90%); }
  .meta { position: relative; z-index: 1; display: flex; min-width: 0; flex-direction: column; gap: 3px; margin: 0 12px; pointer-events: none; }
  .title { overflow: hidden; color: rgb(255 255 255 / 92%); font-size: 13px; font-weight: 500; line-height: 16px; text-overflow: ellipsis; white-space: nowrap; }
  .row.dim .title { color: rgb(255 255 255 / 42%); } .row.now .title { font-weight: 650; }
  .sub { overflow: hidden; color: rgb(255 255 255 / 60%); font-size: 11.5px; line-height: 14px; text-overflow: ellipsis; white-space: nowrap; }
  .sub.status { color: rgb(255 255 255 / 55%); } .sub.status.warn { color: rgb(242 184 107 / 90%); }
  .actions { position: relative; z-index: 1; display: flex; align-items: center; justify-content: flex-end; gap: 2px; }
  .action { display: grid; place-items: center; width: 28px; height: 30px; padding: 0; border: 0; border-radius: 6px; color: rgb(255 255 255 / 65%); background: transparent; cursor: pointer; opacity: 0; pointer-events: none; }
  .action svg { width: 13px; height: 13px; }
  .row:hover .action, .row:focus-within .action { opacity: 1; pointer-events: auto; }
  .action:hover { color: #fff; background: rgb(255 255 255 / 10%); }
  .timing { position: relative; z-index: 1; display: grid; place-items: center; width: 28px; height: 30px; margin-left: 8px; }
  .duration { color: rgb(255 255 255 / 45%); font-size: 11.5px; font-variant-numeric: tabular-nums; white-space: nowrap; pointer-events: none; }
  .row.dim .duration { color: rgb(255 255 255 / 32%); }
  .handle { position: absolute; inset: 0; display: grid; place-items: center; width: 28px; height: 30px; padding: 0; border: 0; border-radius: 6px; color: rgb(255 255 255 / 45%); background: transparent; cursor: grab; opacity: 0; pointer-events: none; }
  .handle svg { width: 16px; height: 14px; } .handle:hover { color: #fff; } .handle:active { cursor: grabbing; }
  .row:hover .handle, .row:focus-within .handle { opacity: 1; pointer-events: auto; }
  .row:hover .has-handle .duration, .row:focus-within .has-handle .duration { visibility: hidden; }
  .spinner { width: 14px; height: 14px; border: 2px solid rgb(255 255 255 / 24%); border-top-color: var(--sideb-highlight); border-radius: 50%; animation: spin .8s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .empty { display: flex; min-width: 0; min-height: 0; flex: 1; flex-direction: column; align-items: center; justify-content: center; gap: 12px; padding: 20px; color: rgb(255 255 255 / 55%); text-align: center; }
  .empty svg { width: 38px; height: 38px; color: rgb(255 255 255 / 25%); } .empty p { max-width: 32ch; margin: 0; font-size: 14px; font-weight: 500; }
  .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 3px; }
  @media (prefers-reduced-motion: reduce) { .spinner { animation-duration: 2.4s; } }
</style>
