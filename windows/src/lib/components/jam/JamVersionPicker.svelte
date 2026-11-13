<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import { t } from '$lib/i18n';
  import type { JamMatchedSong } from '$lib/jam/types';
  import type { SongDto } from '$lib/types';
  import { matchedFromSong } from './view';

  interface Props {
    /** Pre-filled search ("title artists" of the Spotify track). */
    query: string;
    /** `videoId` of the version that plays now (marked, not selectable). */
    currentVideoId?: string | null;
    search: (query: string) => Promise<SongDto[]>;
    onPick: (song: JamMatchedSong) => void;
    onClose?: () => void;
  }
  let { query, currentVideoId = null, search, onPick, onClose }: Props = $props();
  let draft = $state(untrack(() => query));
  let results = $state<SongDto[]>([]);
  let loading = $state(false);
  let failed = $state(false);
  let revision = 0;
  let input = $state<HTMLInputElement>();

  async function run() {
    const text = draft.trim();
    if (!text) return;
    const mine = ++revision;
    loading = true; failed = false;
    try {
      const found = await search(text);
      if (mine === revision) results = found.slice(0, 10);
    } catch {
      if (mine === revision) { results = []; failed = true; }
    } finally {
      if (mine === revision) loading = false;
    }
  }
  onMount(() => { void run(); });
</script>

<section class="picker" aria-label={$t('jam.versions.title')}>
  <header>
    <h3>{$t('jam.versions.title')}</h3>
    {#if onClose}<button type="button" class="close" onclick={onClose} aria-label={$t('windows.jam.versions.close')} title={$t('windows.jam.versions.close')}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M6 6 18 18M18 6 6 18" /></svg></button>{/if}
  </header>
  <form onsubmit={(event) => { event.preventDefault(); void run(); }}>
    <input bind:this={input} type="search" bind:value={draft} placeholder={$t('windows.jam.versions.searchLabel')} aria-label={$t('windows.jam.versions.searchLabel')} />
    <button type="submit" class="go" disabled={loading || !draft.trim()}>{$t('windows.jam.versions.search')}</button>
  </form>
  <div class="results" role="list" aria-busy={loading}>
    {#if loading}
      <p class="note" role="status"><span class="spinner" aria-hidden="true"></span>{$t('windows.jam.versions.searching')}</p>
    {:else if failed}
      <p class="note warn" role="alert">{$t('windows.jam.versions.failed')}</p>
    {:else if !results.length}
      <p class="note" role="status">{$t('jam.versions.empty')}</p>
    {/if}
    {#each loading ? [] : results as song (song.videoId)}
      {@const current = song.videoId === currentVideoId}
      <div role="listitem">
        <button type="button" class="row" class:current aria-current={current ? 'true' : undefined} aria-label={`${song.title}, ${song.artists}`} title={current ? $t('jam.versions.current') : $t('jam.versions.use')} disabled={current} onclick={() => onPick(matchedFromSong(song))}>
          <span class="cover" aria-hidden="true">{#if song.thumbnail}<img src={song.thumbnail} alt="" loading="lazy" draggable="false" />{:else}<svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>{/if}</span>
          <span class="text"><span class="name">{song.title}</span><span class="artists">{song.artists}</span></span>
          {#if song.isVideo}<span class="tag">{$t('jam.tag.video')}</span>{/if}
          {#if song.duration}<span class="duration">{song.duration}</span>{/if}
          <span class="state" aria-hidden="true">{current ? '✓' : ''}</span>
        </button>
      </div>
    {/each}
  </div>
</section>

<style>
  .picker { display: flex; flex-direction: column; gap: 8px; box-sizing: border-box; min-width: 0; padding: 8px; border: 1px solid var(--sideb-surface-border); border-radius: 12px; background: var(--sideb-surface); }
  header { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 2px 4px 0; }
  h3 { margin: 0; color: rgb(255 255 255 / 52%); font-size: 10px; font-weight: 600; letter-spacing: .6px; text-transform: uppercase; }
  .close { display: grid; place-items: center; width: 22px; height: 22px; padding: 0; border: 0; border-radius: 6px; color: rgb(255 255 255 / 60%); background: transparent; cursor: pointer; }
  .close:hover { color: #fff; background: rgb(255 255 255 / 10%); } .close svg { width: 11px; height: 11px; }
  form { display: flex; gap: 6px; }
  input { flex: 1; min-width: 0; box-sizing: border-box; height: 30px; padding: 0 10px; border: 1px solid var(--sideb-surface-border); border-radius: 8px; color: #f3f3f6; background: rgb(0 0 0 / 22%); font: inherit; font-size: 12px; }
  .go { flex: none; height: 30px; padding: 0 12px; border: 1px solid var(--control-prominent-border); border-radius: 8px; color: #fff; background: var(--control-prominent); font: inherit; font-size: 12px; font-weight: 600; cursor: pointer; }
  .go:disabled { opacity: .45; cursor: default; }
  .results { display: flex; flex-direction: column; gap: 2px; max-height: 196px; overflow-y: auto; overscroll-behavior: contain; scrollbar-width: thin; scrollbar-color: rgb(255 255 255 / 28%) transparent; }
  .note { display: flex; align-items: center; gap: 8px; margin: 0; padding: 8px; color: rgb(255 255 255 / 62%); font-size: 12px; } .note.warn { color: #ffb7bb; }
  .spinner { width: 12px; height: 12px; border: 2px solid rgb(255 255 255 / 24%); border-top-color: var(--sideb-highlight); border-radius: 50%; animation: spin .8s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .row { display: flex; align-items: center; gap: 9px; box-sizing: border-box; width: 100%; padding: 6px 8px; border: 0; border-radius: 8px; color: inherit; background: transparent; font: inherit; text-align: left; cursor: pointer; }
  .row:hover:not(:disabled) { background: rgb(255 255 255 / 7%); }
  .row.current { background: color-mix(in srgb, var(--sideb-accent) 22%, transparent); cursor: default; }
  .cover { display: grid; place-items: center; flex: none; width: 32px; height: 32px; overflow: hidden; border-radius: 5px; color: rgb(255 255 255 / 45%); background: rgb(255 255 255 / 8%); }
  .cover img { width: 100%; height: 100%; object-fit: cover; } .cover svg { width: 14px; height: 14px; }
  .text { display: flex; flex: 1; flex-direction: column; gap: 1px; min-width: 0; }
  .name, .artists { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .name { font-size: 12px; font-weight: 500; } .artists { color: rgb(255 255 255 / 60%); font-size: 11px; }
  .tag { flex: none; padding: 1px 4px; border: .75px solid rgb(255 255 255 / 24%); border-radius: 3px; color: rgb(255 255 255 / 70%); font-size: 9px; font-weight: 700; letter-spacing: .4px; }
  .duration { flex: none; color: rgb(255 255 255 / 52%); font-size: 11px; font-variant-numeric: tabular-nums; }
  .state { flex: none; width: 12px; color: var(--sideb-highlight); font-size: 12px; font-weight: 700; }
  button:focus-visible, input:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 2px; }
</style>
