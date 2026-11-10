<script lang="ts">
  /**
   * Lyrics sample under the transport controls (macOS `SidebarLyricsPreviewCard` + the real karaoke renderer at
   * 26 px). The same document, `KaraokePhrase` ink and `KaraokeClock` as the Letras tab, with its own scroll: no
   * header, no arrow, no controls, no hit testing — the whole card opens the full Letras tab, and a "Show more"
   * capsule appears on hover/focus. The active line is centered with symmetric top/bottom padding; the first
   * positioning of every mount/occurrence/layout is immediate (no travel from the list start), later ones animate.
   *
   * Props (W3 composes this file; give it the remaining height of the footer — it fills its parent):
   * - `session`, `playback`: the usual FullscreenNowPlaying contract (position/duration/queue come from here).
   * - `lyricsState`: classic lyrics state of the page (`LyricsController`), used as fallback and while rich loads.
   * - `active` (default true): the sample is on screen (Ahora suena tab, square layout, tall panel, preference
   *   "lyrics", sidebar presented). false stops the clock, cancels the karaoke request and removes the content.
   * - `onOpen()`: open the full lyrics (select the Letras tab / `openPlayerPanel('lyrics')`).
   * Per-song source (`lyrics.sources`) chosen in the Letras tab is honored.
   */
  import { onDestroy, onMount, tick, untrack } from 'svelte';
  import { invoke } from '@tauri-apps/api/core';
  import { t } from '$lib/i18n';
  import type { PlaybackStateDto } from '$lib/types';
  import type { LyricsState } from '$lib/player/lyrics';
  import { KaraokeController, prepareKaraoke, karaokeFocus, karaokeGapIndex, type KaraokeState } from '$lib/player/karaoke';
  import { KaraokeClock } from '$lib/player/karaoke-clock';
  import { LyricScroller } from '$lib/player/lyric-scroll';
  import { initialAnimatedArtworkRuntimeState, observeAnimatedArtworkRuntime } from '$lib/artwork/runtime';
  import { currentClassicLyrics, lyricsCenterPlan, lyricsOccurrence, readLyricSources } from '$lib/player/sidebarLyrics';
  import { sidebarLayout } from '$lib/player/sidebarLayout';
  import KaraokePhrase from '$lib/components/fullscreen/KaraokePhrase.svelte';
  import LyricsWait from '$lib/components/fullscreen/LyricsWait.svelte';

  interface Props {
    session: number;
    playback: PlaybackStateDto;
    lyricsState: LyricsState;
    active?: boolean;
    onOpen: () => void;
  }
  let { session, playback, lyricsState, active = true, onOpen }: Props = $props();

  const size = sidebarLayout.lyricsPreviewFontSize;
  let rich = $state<KaraokeState>({ occurrence: null, status: 'idle', refreshing: false, document: null, error: null });
  const controller = new KaraokeController(invoke, next => { rich = next; });
  const clock = new KaraokeClock(), scroller = new LyricScroller();
  let reduced = $state(false), contrast = $state(false), webHidden = $state(false);
  let runtime = $state(initialAnimatedArtworkRuntimeState);
  let focus = $state<number | null>(null), gapIndex = $state(-1);
  let container = $state<HTMLDivElement | null>(null), height = $state(0);

  const visible = $derived(active && !webHidden && runtime.visible && !runtime.minimized && !runtime.cloaked);
  const track = $derived(playback.currentTrack);
  const occurrence = $derived(lyricsOccurrence(session, playback));
  const duration = $derived(Number.isFinite(playback.duration) && playback.duration > 0 ? playback.duration : track?.duration ?? 0);
  const source = $derived.by(() => { void active; return readLyricSources()[track?.videoId ?? ''] ?? 'auto'; });
  const classic = $derived.by(() => {
    const lyrics = currentClassicLyrics(lyricsState, playback, session);
    return lyrics ? prepareKaraoke({ ...lyrics, instrumental: false, lines: lyrics.lines.map(line => ({ ...line, words: [] })) }, duration) : null;
  });
  const lyricDocument = $derived(rich.occurrence === occurrence && rich.document ? rich.document : source !== 'auto' ? null : classic);
  const isRich = $derived(rich.occurrence === occurrence && !!rich.document);
  const groupOrdinal = $derived(focus === null ? -1 : lyricDocument?.ordinals.get(focus) ?? -1);
  const loading = $derived(rich.status === 'loading' || (source === 'auto' && lyricsState.status === 'loading'));
  const geometry = $derived(JSON.stringify([size, lyricDocument?.provider ?? '', lyricDocument?.lines.length ?? 0]));

  $effect(() => {
    const current = track, key = occurrence, seconds = duration, enabled = active, provider = source;
    untrack(() => controller.setContext(current, key, seconds, enabled, provider));
  });
  $effect(() => { const slow = runtime.powerSaver || runtime.memoryPressure; untrack(() => clock.setSlow(slow)); });
  $effect(() => { const boundaries = lyricDocument?.boundaries ?? []; untrack(() => clock.setBoundaries(boundaries, 0)); });
  $effect(() => {
    const pending = typeof playback.seekPending === 'number';
    const position = pending ? playback.seekPending! : playback.position;
    const playing = visible && playback.isPlaying && !playback.isLoading;
    const key = `${occurrence}:${playback.seekRevision ?? 0}`;
    untrack(() => clock.observe(position, playing, pending, key));
  });
  $effect(() => {
    if (!active) return;
    const doc = lyricDocument;
    return untrack(() => clock.subscribe(ms => {
      const next = doc ? karaokeFocus(doc, ms) : null; if (focus !== next) focus = next;
      const gap = doc ? karaokeGapIndex(doc, ms) : -1; if (gapIndex !== gap) gapIndex = gap;
      return false;
    }));
  });

  let centerState: { occurrence: string; layout: string; centered: boolean } | null = null;
  let centerRevision = 0;
  $effect(() => {
    const doc = lyricDocument, index = focus, element = container, h = height, gap = gapIndex, key = occurrence, layout = `${h}|${geometry}`;
    const revision = ++centerRevision; scroller.cancel();
    // Leaving the screen forgets the positioning, so reopening centers immediately instead of travelling.
    if (!active) { centerState = null; return; }
    if (!element || !doc || index === null || h <= 0) return;
    void tick().then(() => {
      if (revision !== centerRevision || container !== element) return;
      const row = element.querySelector<HTMLElement>(gap >= 0 ? `[data-gap="${gap}"]` : `[data-line="${index}"]`);
      if (!row) return;
      const top = element.scrollTop + row.getBoundingClientRect().top - element.getBoundingClientRect().top - element.clientHeight / 2 + row.clientHeight / 2;
      const plan = lyricsCenterPlan(centerState, { occurrence: key, layout }, reduced);
      scroller.center(element, top, plan.animate);
      centerState = { occurrence: key, layout, centered: plan.centered };
    });
  });

  onMount(() => {
    const media = window.matchMedia('(prefers-reduced-motion:reduce)'), high = window.matchMedia('(prefers-contrast:more)'), forced = window.matchMedia('(forced-colors:active)');
    const sync = () => { reduced = media.matches; contrast = high.matches || forced.matches; };
    const visibility = () => { webHidden = document.hidden; };
    sync(); visibility();
    media.addEventListener('change', sync); high.addEventListener('change', sync); forced.addEventListener('change', sync);
    document.addEventListener('visibilitychange', visibility);
    const stopRuntime = observeAnimatedArtworkRuntime(next => { runtime = next; });
    return () => {
      media.removeEventListener('change', sync); high.removeEventListener('change', sync); forced.removeEventListener('change', sync);
      document.removeEventListener('visibilitychange', visibility); stopRuntime();
    };
  });
  onDestroy(() => { controller.dispose(); clock.dispose(); scroller.cancel(); });

  function key(event: KeyboardEvent) {
    if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onOpen(); }
  }
</script>

<!-- The card is a single control; its lyrics are decoration (inert, hidden from assistive technology). -->
<div class="card" role="button" tabindex="0" aria-label={$t('playbackSidebar.lyricsPreview.openLyrics')} onclick={onOpen} onkeydown={key}
  class:reduced class:contrast style={`--size:${size}px`}>
  <div class="content" aria-hidden="true" inert>
    {#if !active}
      <!-- Nothing is rendered or ticking while the sample is not on screen. -->
    {:else if lyricDocument?.instrumental}
      <div class="status"><p>{$t('lyrics.experimental.instrumental')}</p></div>
    {:else if lyricDocument?.lines.length}
      <div class="lyrics-scroll" bind:this={container} bind:clientHeight={height}
        style={`--edge:${lyricDocument.hasTiming ? height / 2 : 12}px`}>
        <div class="lines">
          {#each lyricDocument.groups as group, ordinal (group.anchor)}
            {#each lyricDocument.gapsByBefore.get(ordinal) ?? [] as item}<LyricsWait gap={item.gap} index={item.index} {clock} offset={0} animate={!reduced && visible} />{/each}
            {@const distance = groupOrdinal < 0 ? 0 : Math.min(3, Math.abs(groupOrdinal - ordinal))}
            {@const blur = !reduced && !contrast && distance > 0 ? [0, 1.2, 2.1, 3][distance] : 0}
            <div class="group" class:focused={group.anchor === focus} style={`--blur:${blur}px;--opacity:${distance === 0 ? 1 : contrast ? .78 : .40};--scale:${distance === 0 || reduced ? 1 : .98}`}>
              {#each group.indices as index}
                {@const line = lyricDocument.lines[index]}
                <div class="row" class:background={line.background} data-line={index}>
                  <div class="line"><KaraokePhrase {line} {clock} enabled={isRich} motion {reduced} offset={0} {geometry} /></div>
                  {#if isRich && line.translation}<p class="translation">{line.translation}</p>{/if}
                </div>
              {/each}
            </div>
          {/each}
          {#each lyricDocument.gapsByBefore.get(lyricDocument.groups.length) ?? [] as item}<LyricsWait gap={item.gap} index={item.index} {clock} offset={0} animate={!reduced && visible} />{/each}
        </div>
      </div>
    {:else}
      <div class="status">
        {#if loading}
          <span class="spinner" aria-hidden="true"></span>
        {:else}
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" aria-hidden="true"><path d="M4 5h16v11H9l-5 4z" /></svg>
        {/if}
        <p>{$t(loading ? 'playbackSidebar.lyricsPreview.searching' : track ? 'playbackSidebar.lyricsPreview.noLyrics' : 'lyrics.experimental.noTrack')}</p>
      </div>
    {/if}
  </div>
  <span class="more" aria-hidden="true">{$t('playbackSidebar.lyricsPreview.showMore')}</span>
</div>

<style>
  .card { position:relative; box-sizing:border-box; width:100%; height:100%; min-width:0; min-height:0; overflow:hidden; border-radius:16px; background:rgb(255 255 255 / 6%); box-shadow:inset 0 0 0 .8px rgb(255 255 255 / 8%); color:#fff; cursor:pointer; transition:box-shadow 160ms ease-in-out; }
  .card:hover, .card:focus-visible { box-shadow:inset 0 0 0 .8px rgb(255 255 255 / 20%); }
  .card:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:2px; }
  .content { position:absolute; inset:0; pointer-events:none; user-select:none; }
  .lyrics-scroll { height:100%; overflow:hidden; mask-image:linear-gradient(to bottom,transparent,#000 22%,#000 78%,transparent); }
  /* Symmetric margins: equal padding on both sides and equal fade at top and bottom. */
  .lines { padding:var(--edge) 20px; }
  .group { overflow-clip-margin:24px; }
  .row { filter:blur(var(--blur)); opacity:var(--opacity); transform:scale(var(--scale)); transform-origin:left center; transition:opacity .788s,transform .788s,filter .788s; padding-block:10px; }
  .row:has(:global(.voice-active)) { filter:none; opacity:1; transform:none; }
  .row+.row { padding-top:8px; }
  .line { display:block; width:100%; margin:0; padding:0; color:inherit; font-family:inherit; font-size:var(--size); font-weight:700; letter-spacing:-.18px; line-height:1.25; text-align:start; }
  .background { --row-size:max(16px,calc(var(--size)*.68)); } .background .line { font-size:var(--row-size); }
  .translation { margin:7px 0 0; font-size:max(13px,calc(var(--size)*.57)); font-weight:500; line-height:1.25; opacity:.8; }
  .status { display:flex; align-items:center; justify-content:center; gap:8px; width:100%; height:100%; padding:0 20px; box-sizing:border-box; color:rgb(255 255 255 / 60%); font-size:13px; font-weight:500; }
  .status p { margin:0; } .status svg { flex:none; width:16px; height:16px; opacity:.7; }
  .spinner { flex:none; width:14px; height:14px; border:2px solid rgb(255 255 255 / 25%); border-top-color:#fff; border-radius:50%; animation:spin .8s linear infinite; }
  @keyframes spin { to { transform:rotate(360deg); } }
  .more { position:absolute; right:10px; bottom:10px; padding:6px 12px; border-radius:999px; background:#fff; color:#000; font-size:11px; font-weight:700; box-shadow:0 3px 8px rgb(0 0 0 / 35%); opacity:0; transform:scale(.92); transition:opacity 160ms ease-in-out,transform 160ms ease-in-out; pointer-events:none; }
  .card:hover .more, .card:focus-visible .more { opacity:1; transform:none; }
  .contrast .lyrics-scroll { mask-image:none; } .contrast .row, .reduced .row { filter:none; } .reduced .row { transition:none; }
  .card.reduced, .reduced .more { transition:none; } .reduced .more { transform:none; } .reduced .spinner { animation-duration:2s; }
  @media (forced-colors:active) { .lyrics-scroll { mask-image:none; } .row { filter:none!important; opacity:1!important; } .line { color:CanvasText; } .more { background:Canvas; color:CanvasText; border:1px solid CanvasText; } }
</style>
