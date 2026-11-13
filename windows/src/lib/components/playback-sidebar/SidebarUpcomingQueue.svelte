<script lang="ts">
  /**
   * "Up next" block (macOS `SidebarUpcomingQueue`): the next two committed queue occurrences. Reading never
   * promotes radio recommendations, extends a source or copies the queue (see `sidebarUpcomingPreview`).
   *
   * Props (W3 composes this file; size it ≈ 122 px tall, shown only when `showsUpcoming(...)`):
   * - `session`, `playback`: the usual FullscreenNowPlaying contract; the list derives from `playback.queue`.
   * - `onSelectQueue(queueIndex)`: play that occurrence (same handler as FullscreenNowPlaying's `onSelectQueue`).
   * - `onOpenQueue()`: "View queue ›" — select the Cola tab of the sidebar.
   */
  import { readable } from 'svelte/store';
  import { t, language } from '$lib/i18n';
  import { emptyJamState } from '$lib/jam/types';
  import { useJamUi } from '$lib/components/jam/context';
  import { formatMs, isJamLive, jamTitle, trackArtists, trackTitle } from '$lib/components/jam/view';
  import type { PlaybackStateDto } from '$lib/types';
  import { cardArtworkCandidates, nextArtworkUrl } from '$lib/images/artwork';
  import { formatSidebarDuration, sidebarUpcomingPreview } from '$lib/player/sidebarUpcoming';

  interface Props {
    session: number;
    playback: PlaybackStateDto;
    onSelectQueue: (queueIndex: number) => void;
    onOpenQueue?: () => void;
  }
  let { playback, onSelectQueue, onOpenQueue }: Props = $props();
  // During a Jam the preview follows the Jam order (first two tracks) and cannot jump to a row.
  const jamUi = useJamUi();
  const jamState = jamUi?.state ?? readable(emptyJamState());
  const jamLive = $derived(isJamLive($jamState));
  const jamRows = $derived(jamLive ? $jamState.queue.slice(0, 2) : []);
  const entries = $derived(jamLive ? [] : sidebarUpcomingPreview(playback.queue));
  let failed = $state<Record<string, string[]>>({});
  const pixelRatio = () => (typeof window === 'undefined' ? 1 : window.devicePixelRatio || 1);
  const coverFor = (entryId: string, thumbnail: string | null) => nextArtworkUrl(cardArtworkCandidates(thumbnail, 36, pixelRatio()), failed[entryId] ?? []);
  const rejectCover = (entryId: string, url: string) => { failed = { ...failed, [entryId]: [...(failed[entryId] ?? []), url] }; };
</script>

<section class="upcoming" aria-label={$t('playbackSidebar.upNext')} data-jam-upcoming={jamLive ? '' : undefined}>
  <header>
    <h3>{jamLive ? jamTitle($jamState, $language) : $t('playbackSidebar.upNext')}</h3>
    {#if onOpenQueue}
      <button type="button" class="view-queue" onclick={onOpenQueue}>
        {$t('playbackSidebar.viewQueue')}
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 5 7 7-7 7" /></svg>
      </button>
    {/if}
  </header>
  {#if !entries.length && !jamRows.length}
    <p class="empty">{$t('queue.empty')}</p>
  {/if}
  {#each jamRows as track (track.key)}
    {@const ok = track.status === 'matched' && !!track.matched}
    <div class="row jam-row" class:dim={!ok} data-status={track.status} aria-label={ok ? `${trackTitle(track)}, ${trackArtists(track)}` : `${trackTitle(track)}, ${track.status === 'unavailable' ? $t('jam.queue.unavailable') : $t('jam.queue.resolving')}`}>
      <span class="cover" aria-hidden="true">
        {#if ok && track.matched?.thumbnail}<img src={track.matched.thumbnail} alt="" decoding="async" draggable="false" />
        {:else if !ok && track.status !== 'unavailable'}<span class="spinner"></span>
        {:else if !ok}<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="9" /><path d="M12 7v6M12 16.5v.5" /></svg>
        {:else}<svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>{/if}
      </span>
      <span class="text">
        <span class="name" title={trackTitle(track)}>{trackTitle(track)}</span>
        <span class="artist" class:warn={track.status === 'unavailable'} title={trackArtists(track)}>{ok ? trackArtists(track) : track.status === 'unavailable' ? $t('jam.queue.unavailable') : $t('jam.queue.resolving')}</span>
      </span>
      {#if formatMs(track.durationMs)}<span class="duration">{formatMs(track.durationMs)}</span>{/if}
    </div>
  {/each}
  {#each entries as { entry, queueIndex } (entry.entryId)}
    {@const cover = coverFor(entry.entryId, entry.thumbnail)}
    <button type="button" class="row" onclick={() => onSelectQueue(queueIndex)}>
      <span class="cover" aria-hidden="true">
        {#if cover}
          {#key cover}<img src={cover} alt="" decoding="async" draggable="false" onerror={() => rejectCover(entry.entryId, cover)} />{/key}
        {:else}
          <svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>
        {/if}
      </span>
      <span class="text">
        <span class="name" title={entry.title}>{entry.title}</span>
        <span class="artist" title={entry.artists}>{entry.artists}</span>
      </span>
      {#if formatSidebarDuration(entry.duration)}<span class="duration">{formatSidebarDuration(entry.duration)}</span>{/if}
    </button>
  {/each}
</section>

<style>
  .upcoming { display:flex; flex-direction:column; gap:8px; width:100%; min-width:0; color:#fff; }
  header { display:flex; align-items:center; justify-content:space-between; gap:8px; }
  h3 { margin:0; font-size:12px; font-weight:600; }
  .view-queue { display:flex; align-items:center; gap:4px; padding:0; border:0; background:transparent; color:rgb(255 255 255 / 60%); font:inherit; font-size:11px; font-weight:500; cursor:pointer; }
  .view-queue svg { width:9px; height:9px; } .view-queue:hover { color:#fff; }
  .empty { display:flex; align-items:center; min-height:36px; margin:0; color:rgb(255 255 255 / 60%); font-size:12px; }
  .row { display:flex; align-items:center; gap:10px; width:100%; min-width:0; padding:0; border:0; border-radius:6px; background:transparent; color:inherit; font:inherit; text-align:left; cursor:pointer; }
  .row:hover { background:rgb(255 255 255 / 6%); }
  .jam-row { cursor:default; } .jam-row:hover { background:transparent; } .jam-row.dim .name { color:rgb(255 255 255 / 45%); } .artist.warn { color:rgb(242 184 107 / 90%); }
  .spinner { width:14px; height:14px; border:2px solid rgb(255 255 255 / 24%); border-top-color:var(--sideb-highlight, #d06c70); border-radius:50%; animation:spin .8s linear infinite; } @keyframes spin { to { transform:rotate(360deg); } }
  .cover { display:grid; place-items:center; flex:none; width:36px; height:36px; overflow:hidden; border-radius:5px; background:rgb(255 255 255 / 8%); color:rgb(255 255 255 / 55%); }
  .cover img { display:block; width:100%; height:100%; object-fit:cover; } .cover svg { width:16px; height:16px; }
  .text { display:flex; flex:1 1 auto; flex-direction:column; gap:3px; min-width:0; }
  .name, .artist { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .name { font-size:12px; font-weight:500; } .artist { color:rgb(255 255 255 / 60%); font-size:11px; }
  .duration { flex:none; color:rgb(255 255 255 / 60%); font-size:10px; font-variant-numeric:tabular-nums; }
  button:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:2px; }
</style>
