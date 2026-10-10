<script lang="ts">
  import { t } from '$lib/i18n';
  import { getContext, onMount, tick } from 'svelte';
  import type { SongDto } from '$lib/types';
  import { MEDIA_CONTEXT, type MediaService } from '$lib/player/media';
  import { MENU_CONTEXT, type MenuOrigin, type MenuService } from '$lib/menu/types';
  import ArtistCredits from '$lib/components/ArtistCredits.svelte';
  import MoreIcon from './MoreIcon.svelte';
  import TrackArtwork from './TrackArtwork.svelte';
  import TrackActivity from './TrackActivity.svelte';
  import { occurrenceKey, selectionFor, trackSegments, visibleTrackRange } from './trackList';

  interface Props {
    items: SongDto[]; source?: { kind: string; id: string }; indexOffset?: number; occurrenceIndices?: number[]; occurrenceKeys?: string[];
    currentTrackId: string | null; isPlaying: boolean; onPlay: (index: number) => void;
    onOpenArtist?: (id: string) => void; onOpenAlbum?: (id: string) => void;
    hideAlbumColumn?: boolean; showAlbumInSubtitle?: boolean; numbered?: boolean; flush?: boolean;
    origin?: MenuOrigin; onContextMenu?: (event: MouseEvent | KeyboardEvent, track: SongDto) => void;
    onRemoveTrack?: (track: SongDto) => void;
    onMoveTrack?: (setVideoId: string, successorSetVideoId: string | null) => void;
    canReorder?: boolean; mutationPending?: boolean; detail?: boolean;
    likedIds?: Set<string>; pendingIds?: Set<string>; onToggleLike?: (track: SongDto) => void;
  }
  let { items, source, indexOffset = 0, currentTrackId, isPlaying, onPlay, onOpenArtist, onOpenAlbum,
    hideAlbumColumn = false, showAlbumInSubtitle = false, numbered = true, flush = false, origin = {},
    onContextMenu, onRemoveTrack, onMoveTrack, canReorder = false, mutationPending = false, occurrenceIndices, occurrenceKeys,
    detail = false, likedIds, pendingIds, onToggleLike }: Props = $props();
  const media = getContext<MediaService | undefined>(MEDIA_CONTEXT);
  const menu = getContext<MenuService | undefined>(MENU_CONTEXT);
  let root: HTMLDivElement;
  let selected = $state(new Set<string>());
  let anchorKey = $state<string | null>(null);
  let focusedKey = $state<string | null>(null);
  let draggingKey = $state<string | null>(null);
  let draggingSetVideoId = $state<string | null>(null);
  let awake = $state(false);
  let range = $state<[number, number]>([0, 40]);
  let visibleRange = $state<[number, number]>([0, 0]);
  let measure = () => {};
  const keys = $derived(occurrenceKeys ?? items.map(occurrenceKey));
  const rowHeight = $derived(detail ? 58 : 52);
  function sourceIndex(index: number) { return occurrenceIndices?.[index] ?? index + indexOffset; }
  const anchor = $derived(Math.max(0, anchorKey === null ? 0 : keys.indexOf(anchorKey)));
  const focusedIndex = $derived(focusedKey === null ? -1 : keys.indexOf(focusedKey));
  const draggingIndex = $derived(draggingKey === null ? -1 : keys.indexOf(draggingKey));
  const fallbackActiveIndex = $derived(items.findIndex(track => track.videoId === currentTrackId));
  const virtual = $derived(items.length > 160);
  const segments = $derived(trackSegments(items.length, virtual ? range : [0, items.length], [focusedIndex, draggingIndex]));
  const hasAlbum = $derived(!hideAlbumColumn && !showAlbumInSubtitle && items.some(track => Boolean(track.album)));
  const editable = $derived(Boolean(canReorder && onMoveTrack || onRemoveTrack));
  const actionWidth = $derived(36 + (onToggleLike ? 28 : 0) + (canReorder && onMoveTrack ? 48 : 0) + (onRemoveTrack ? 24 : 0));
  const lastEnd = $derived(segments.at(-1)?.[1] ?? 0);
  const entries = $derived(segments.flatMap(([start, end], segmentIndex) => Array.from({ length: end - start }, (_, localIndex) => ({ index: start + localIndex, gap: localIndex === 0 ? start - (segments[segmentIndex - 1]?.[1] ?? 0) : 0 }))));

  function activate(index: number, event: MouseEvent) {
    const selection = selectionFor(keys, selected, index, anchor, event.shiftKey, event.ctrlKey || event.metaKey);
    selected = selection.selected; anchorKey = keys[selection.anchor];
    if (!selection.activate) return;
    if (media?.rowActive(items[index], sourceIndex(index), source) && media.state().isLoading) return;
    if (media?.rowActive(items[index], sourceIndex(index), source)) media.toggle(); else onPlay(index);
    if (event.detail > 0) root.focus();
  }
  function rowClick(event: MouseEvent, index: number) {
    if ((event.target as HTMLElement).closest('button,a,input,select')) return;
    activate(index, event);
  }
  function openMenu(event: MouseEvent | KeyboardEvent, track: SongDto) {
    event.preventDefault();
    if (onContextMenu) onContextMenu(event, track); else menu?.open(event, { kind: 'song', song: track }, origin);
  }
  function reorderBefore(track: SongDto, index: number) {
    if (!canReorder || !track.setVideoId || !onMoveTrack || mutationPending) return;
    const successor = items[index]?.setVideoId ?? null;
    if (successor !== track.setVideoId) onMoveTrack(track.setVideoId, successor);
  }
  function dropOn(event: DragEvent, index: number) {
    if (!draggingSetVideoId) return;
    event.preventDefault();
    const sourceTrack = items.find(track => track.setVideoId === draggingSetVideoId);
    const bounds = (event.currentTarget as HTMLElement).getBoundingClientRect();
    if (sourceTrack) reorderBefore(sourceTrack, event.clientY > bounds.top + bounds.height / 2 ? index + 1 : index);
    draggingSetVideoId = null; draggingKey = null;
  }
  async function keydown(event: KeyboardEvent, index: number) {
    const track = items[index];
    if (event.key === 'Tab' && virtual) {
      const row = event.currentTarget as HTMLTableRowElement;
      const buttons = [...row.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')];
      const boundary = event.shiftKey ? buttons[0] : buttons.at(-1);
      const next = index + (event.shiftKey ? -1 : 1);
      if (event.target === boundary && next >= 0 && next < items.length && !entries.some(entry => entry.index === next)) {
        event.preventDefault();
        const nextKey = keys[next]; focusedKey = nextKey;
        await tick();
        const adjacentButtons = findRow(nextKey)?.querySelectorAll<HTMLButtonElement>('button:not(:disabled)');
        const button = event.shiftKey ? adjacentButtons?.[adjacentButtons.length - 1] : adjacentButtons?.[0];
        button?.focus({ preventScroll: true }); button?.scrollIntoView({ block: 'nearest' });
      }
      return;
    }
    if (event.key === 'ContextMenu' || event.shiftKey && event.key === 'F10') { openMenu(event, track); return; }
    if (event.altKey && canReorder && (event.key === 'ArrowUp' || event.key === 'ArrowDown')) {
      event.preventDefault();
      if (event.key === 'ArrowUp' && index > 0) reorderBefore(track, index - 1);
      if (event.key === 'ArrowDown' && index < items.length - 1) reorderBefore(track, index + 2);
      return;
    }
    if (event.ctrlKey || event.metaKey || event.altKey || !['ArrowUp','ArrowDown','Home','End'].includes(event.key)) return;
    event.preventDefault();
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? items.length - 1 : Math.max(0, Math.min(items.length - 1, index + (event.key === 'ArrowUp' ? -1 : 1)));
    if (event.shiftKey) selected = selectionFor(keys, selected, next, anchor, true, false).selected;
    const nextKey = keys[next]; focusedKey = nextKey;
    await tick();
    const button = findRow(nextKey)?.querySelector<HTMLButtonElement>('.song-title');
    button?.focus({ preventScroll: true }); button?.scrollIntoView({ block: 'nearest' });
  }
  function findRow(key: string) {
    return [...root.querySelectorAll<HTMLTableRowElement>('[data-occurrence-key]')].find(row => row.dataset.occurrenceKey === key);
  }
  function viewport(node: HTMLDivElement) {
    let parent = node.parentElement;
    while (parent && !/(auto|scroll)/.test(getComputedStyle(parent).overflowY)) parent = parent.parentElement;
    const scroller = parent;
    const target = scroller ?? window;
    let frame = 0;
    const update = () => {
      const box = node.getBoundingClientRect();
      const view = scroller?.getBoundingClientRect();
      const top = view?.top ?? 0;
      const height = view?.height ?? window.innerHeight;
      const relativeTop = Math.max(0, top - box.top);
      const intersection = Math.max(0, Math.min(top + height, box.bottom) - Math.max(top, box.top));
      range = visibleTrackRange(items.length, relativeTop, height, rowHeight);
      visibleRange = intersection > 0 ? visibleTrackRange(items.length, relativeTop, intersection, rowHeight, 0) : [0, 0];
    };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(() => { frame = 0; update(); }); };
    measure = schedule;
    const resize = new ResizeObserver(schedule); resize.observe(node); if (scroller) resize.observe(scroller);
    target.addEventListener('scroll', schedule, { passive: true }); window.addEventListener('resize', schedule); update();
    return { destroy() { cancelAnimationFrame(frame); resize.disconnect(); target.removeEventListener('scroll', schedule); window.removeEventListener('resize', schedule); measure = () => {}; } };
  }
  $effect(() => { items; rowHeight; measure(); });
  onMount(() => {
    const sync = () => awake = !document.hidden && document.hasFocus(); sync();
    document.addEventListener('visibilitychange', sync); window.addEventListener('focus', sync); window.addEventListener('blur', sync);
    return () => { document.removeEventListener('visibilitychange', sync); window.removeEventListener('focus', sync); window.removeEventListener('blur', sync); };
  });
</script>

<!-- The region retains focus after pointer playback; Space is handled by the app shortcut. -->
<!-- svelte-ignore a11y_no_noninteractive_tabindex -->
<div bind:this={root} use:viewport class="table-scroll" class:flush class:detail style={`--row-height:${rowHeight}px`} tabindex="0" role="region" aria-label={$t('search.filter.songs')}
  onfocusin={event => focusedKey = (event.target as HTMLElement).closest<HTMLElement>('[data-occurrence-key]')?.dataset.occurrenceKey ?? null}
  onfocusout={event => { if (!(event.relatedTarget instanceof Node) || !root.contains(event.relatedTarget)) focusedKey = null; }}>
  <table aria-label={$t('search.filter.songs')} aria-rowcount={items.length} class:with-album={hasAlbum} class:editable style={`--track-actions-width:${actionWidth}px`}>
    <colgroup><col class="index-column" /><col />{#if hasAlbum}<col class="album-column" />{/if}<col class="duration-column" /><col class="actions-column" /></colgroup>
    {#if detail && !hideAlbumColumn}<thead><tr><th></th><th>{$t('windows.ui.songArtist')}</th>{#if hasAlbum}<th>{$t('metadata.album')}</th>{/if}<th>{$t('detail.track.duration')}</th><th></th></tr></thead>{/if}
    <tbody>
      {#each entries as entry (keys[entry.index])}
          {@const index = entry.index}
          {@const track = items[index]}
          {#if entry.gap > 0}<tr class="spacer" aria-hidden="true"><td colspan={hasAlbum ? 5 : 4} style={`height:${entry.gap * rowHeight}px`}></td></tr>{/if}
          {@const active = media?.rowActive(track, sourceIndex(index), source) ?? index === fallbackActiveIndex}
          <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
          <tr class="track-row" class:active class:selected={selected.has(keys[index])} class:dragging={draggingSetVideoId !== null && draggingSetVideoId === track.setVideoId}
            data-index={index} data-occurrence-key={keys[index]} aria-rowindex={index + 1} onclick={event => rowClick(event, index)} onkeydown={event => keydown(event, index)}
            oncontextmenu={event => openMenu(event, track)} draggable={canReorder && Boolean(track.setVideoId) && !mutationPending}
            ondragstart={event => { if (!canReorder || !track.setVideoId || mutationPending) { event.preventDefault(); return; } draggingKey = keys[index]; draggingSetVideoId = track.setVideoId; event.dataTransfer?.setData('text/plain', track.setVideoId); if (event.dataTransfer) event.dataTransfer.effectAllowed = 'move'; }}
            ondragend={() => { draggingKey = null; draggingSetVideoId = null; }}
            ondragover={event => { if (draggingSetVideoId) { event.preventDefault(); if (event.dataTransfer) event.dataTransfer.dropEffect = 'move'; } }} ondrop={event => dropOn(event, index)}>
            <td class="index"><TrackActivity {active} playing={isPlaying} number={numbered ? index + 1 : undefined} awake={awake && index >= visibleRange[0] && index < visibleRange[1]} /></td>
            <td class="track-cell"><div class="track-content">
              <TrackArtwork title={track.title} thumbnail={track.thumbnail} size={detail ? 44 : 40} {active} playing={isPlaying} pending={Boolean(active && media?.state().isLoading)} onPlay={event => activate(index, event)} />
              <div class="song-meta"><button class="song-title" type="button" onclick={event => activate(index, event)} title={track.title}>{track.title}</button>
                <div class="artist-line"><ArtistCredits artistRuns={track.artistRuns} artists={track.artists} artistId={track.artistId} {onOpenArtist} album={showAlbumInSubtitle ? track.album : null} albumId={track.albumId} {onOpenAlbum} /></div>
              </div>
            </div></td>
            {#if hasAlbum}<td class="album-cell">{#if track.albumId && onOpenAlbum}<button class="metadata-link" type="button" onclick={() => onOpenAlbum?.(track.albumId!)} title={track.album ?? ''}>{track.album}</button>{:else}<span title={track.album ?? ''}>{track.album}</span>{/if}</td>{/if}
            <td class="duration">{track.duration ?? '—'}</td>
            <td class="actions"><div class="action-group">
              {#if onToggleLike}<button class="action-button like" class:liked={likedIds?.has(track.videoId)} type="button" disabled={pendingIds?.has(track.videoId)} aria-pressed={likedIds?.has(track.videoId) ?? false} aria-label={$t('windows.track.like', [track.title])} onclick={() => onToggleLike?.(track)}>♥</button>{/if}
              {#if canReorder && onMoveTrack && track.setVideoId}
                <button class="action-button" type="button" disabled={mutationPending || index === 0} aria-label={$t('windows.track.moveUp', [track.title])} title={$t('windows.ui.moveUpAlt')} onclick={() => reorderBefore(track, index - 1)}><svg viewBox="0 0 20 20"><path d="m5 12 5-5 5 5" /></svg></button>
                <button class="action-button" type="button" disabled={mutationPending || index === items.length - 1} aria-label={$t('windows.track.moveDown', [track.title])} title={$t('windows.ui.moveDownAlt')} onclick={() => reorderBefore(track, index + 2)}><svg viewBox="0 0 20 20"><path d="m5 8 5 5 5-5" /></svg></button>
              {/if}
              {#if onRemoveTrack && track.setVideoId}<button class="action-button" type="button" disabled={mutationPending} aria-label={$t('windows.track.remove', [track.title])} title={$t('windows.ui.removeFromPlaylist')} onclick={() => onRemoveTrack?.(track)}><svg viewBox="0 0 20 20"><path d="m6 6 8 8m0-8-8 8" /></svg></button>{/if}
              <button class="action-button track-menu" type="button" aria-label={$t('common.moreOptionsFor', [track.title])} title={$t('menu.more_options')} onclick={event => openMenu(event, track)}><MoreIcon /></button>
            </div></td>
          </tr>
      {/each}
      {#if lastEnd < items.length}<tr class="spacer" aria-hidden="true"><td colspan={hasAlbum ? 5 : 4} style={`height:${(items.length - lastEnd) * rowHeight}px`}></td></tr>{/if}
    </tbody>
  </table>
</div>

<style>
  .index-column {width:34px;} .album-column {width:clamp(60px,18vw,160px);} .duration-column {width:44px;} .actions-column {width:var(--track-actions-width);}
  .detail td { height:58px; } .detail .track-content {height:56px;} .detail :global(.play-control) {width:32px;height:32px;} .detail .action-button {width:28px;height:28px;} .action-button.liked {opacity:1;color:var(--sideb-highlight);} th {height:32px;font-weight:500;font-size:11px;text-align:left;color:#aaaab1;} th:nth-last-child(2){text-align:right;}
  .table-scroll { min-width:0;max-width:100%;padding:0 20px 0 16px;outline:none; }.table-scroll.flush {padding-inline:0;}.table-scroll:focus-visible {box-shadow:inset 0 0 0 2px var(--sideb-highlight);border-radius:7px;}
  table {width:100%;table-layout:fixed;border-collapse:separate;border-spacing:0;color:#aaaab1;font-size:12px;}td {box-sizing:border-box;height:52px;padding:0;vertical-align:middle;border-block:1px solid transparent;}
  .track-row:hover td {background:#ffffff08;}.track-row.active td {background:rgb(255 255 255 / 6.5%);border-block-color:rgb(255 255 255 / 9%);}.track-row.selected td {background:#ffffff0b;}.track-row.selected.active td {background:rgb(255 255 255 / 6.5%);}.track-row td:first-child {border-radius:7px 0 0 7px;border-left:1px solid transparent;}.track-row td:last-child {border-radius:0 7px 7px 0;border-right:1px solid transparent;}.track-row.active td:first-child,.track-row.active td:last-child {border-inline-color:rgb(255 255 255 / 9%);}.dragging {opacity:.42;}
  .index {width:34px;padding-left:8px;}.track-cell {padding:0 8px;}.track-content {display:flex;align-items:center;gap:12px;min-width:0;height:50px;}.song-meta {display:flex;flex-direction:column;gap:3px;min-width:0;flex:1;}.song-title,.metadata-link {display:block;max-width:100%;overflow:hidden;padding:0;border:0;background:none;color:#f2f2f4;font:inherit;text-align:left;text-overflow:ellipsis;white-space:nowrap;cursor:pointer;}.song-title {font-size:14px;font-weight:500;}.artist-line {min-width:0;overflow:hidden;white-space:nowrap;font-size:12px;color:#a6a6ad;}.album-cell {width:clamp(60px,18vw,160px);padding:0 12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}.metadata-link {color:#aaaab1;font-size:12px;}.metadata-link:hover {color:white;}.duration {width:44px;text-align:right;font-variant-numeric:tabular-nums;}.actions {width:var(--track-actions-width);padding-inline:4px;}.action-group {display:flex;align-items:center;justify-content:flex-end;gap:0;}.action-button {display:grid;place-items:center;flex:none;width:24px;height:28px;padding:0;border:0;border-radius:6px;background:transparent;color:#aaaab1;cursor:pointer;opacity:0;}.track-row:hover .action-button,.track-row:focus-within .action-button {opacity:1;}.action-button:hover:not(:disabled) {background:var(--sideb-surface-hover);color:white;}.action-button:disabled {cursor:wait;color:#777;}.action-button svg {width:16px;height:16px;fill:none;stroke:currentColor;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round;}.track-menu {width:28px;}button:focus-visible {outline:2px solid var(--sideb-highlight);outline-offset:1px;opacity:1;}.spacer td {padding:0;border:0;}
  @media(max-width:700px){.album-column,.album-cell {width:18%;}.album-cell {padding-inline:6px;}.table-scroll {padding-inline:8px;}.track-content {gap:8px;}}
  @media(max-width:500px){.editable .actions-column,.editable .actions {width:min(var(--track-actions-width),88px);}.editable .action-button {width:20px;}.track-cell {padding-inline:4px;}.index-column,.index {width:26px;}.index {padding-left:2px;}}
</style>
