<script lang="ts">
  import { t , language, resolveMessage } from '$lib/i18n';
  import { onDestroy, tick } from 'svelte';
  import PlayerIcon from '../player/PlayerIcon.svelte';
  import { activeLyricIndex, lyricSeekSeconds, type LyricsState } from '$lib/player/lyrics';
  import { LyricScroller } from '$lib/player/lyric-scroll';

  interface Props {
    state: LyricsState;
    position: number;
    duration: number;
    onSeek: (seconds: number) => void;
    onRetry: () => void;
  }
  let { state: lyricState, position, duration, onSeek, onRetry }: Props = $props();
  let container = $state<HTMLDivElement | null>(null);
  let following = $state(true);
  const scroller = new LyricScroller();
  let centeredTrack: string | null = null;
  onDestroy(() => scroller.cancel());
  const activeIndex = $derived(lyricState.lyrics ? activeLyricIndex(lyricState.lyrics, position) : null);

  function centerCurrent(animate = true) {
    if (!container || activeIndex === null) return;
    const line = container.querySelector<HTMLElement>(`[data-line="${activeIndex}"]`);
    if (!line) return;
    const containerRect = container.getBoundingClientRect();
    const lineRect = line.getBoundingClientRect();
    const top = container.scrollTop + lineRect.top - containerRect.top - container.clientHeight / 2 + lineRect.height / 2;
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    // Scroll this panel only: scrollIntoView would also move the artwork and app shell.
    scroller.center(container, top, animate && !reduceMotion);
  }
  function pauseFollowing() {
    scroller.cancel();
    if (activeIndex !== null) following = false;
  }
  function onScrollKey(event: KeyboardEvent) {
    if (['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End', ' '].includes(event.key)) pauseFollowing();
  }
  function onPointerDown(event: PointerEvent) {
    // Scrollbar interaction only; pressing a lyric keeps normal line seeking.
    if (!container || event.target !== container) return;
    const rect = container.getBoundingClientRect();
    if (event.clientX >= rect.left + container.clientWidth) pauseFollowing();
  }
  function resumeFollowing() { following = true; }
  function seekLine(seconds: number) { scroller.cancel(); following = true; onSeek(seconds); }

  $effect(() => {
    lyricState.trackKey;
    scroller.cancel();
    centeredTrack = null;
    following = true;
    if (container) container.scrollTop = 0;
  });
  $effect(() => {
    const index = activeIndex;
    const key = lyricState.trackKey;
    const element = container;
    const ready = lyricState.status === 'ready';
    const shouldFollow = following;
    if (ready && shouldFollow && element && index !== null) {
      void tick().then(() => {
        if (following && container === element && index === activeIndex && key === lyricState.trackKey) {
          centerCurrent(centeredTrack === key);
          centeredTrack = key;
        }
      });
    }
  });
</script>

<section class="lyrics-panel" aria-label={$t('windows.ui.songLyrics')}>
  {#if lyricState.status === 'loading'}
    <div class="message" role="status"><span class="spinner" aria-hidden="true"></span><p>{$t('windows.ui.searchingForSynchronizedLyrics')}</p></div>
  {:else if lyricState.status === 'error'}
    <div class="message" role="status"><PlayerIcon name="lyrics" size={36} /><p>{resolveMessage(lyricState.error, $language)}</p><button type="button" class="retry" onclick={onRetry}>{$t('sidebar.retry')}</button></div>
  {:else if lyricState.status === 'ready' && lyricState.lyrics}
    <!-- A scrollable named region must accept focus for keyboard reading of plain lyrics. -->
    <!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
    <div class="lyrics-scroll" bind:this={container} tabindex="0" role="region" aria-label={$t('windows.ui.lyricsText')}
      onwheel={pauseFollowing} ontouchstart={pauseFollowing} onkeydown={onScrollKey} onpointerdown={onPointerDown}>
      <div class="lines">
        {#each lyricState.lyrics.lines as line, index}
          {@const seconds = lyricSeekSeconds(line, duration)}
          {@const active = index === activeIndex}
          {@const opacity = activeIndex === null ? 0.82 : active ? 1 : Math.abs(index - activeIndex) === 1 ? 0.60 : 0.36}
          {#if seconds !== null}
            <button type="button" class="line" class:active data-line={index} style={`--line-opacity: ${opacity}`}
              aria-current={active ? 'true' : undefined} title={$t('fullscreen.goToLyricLine')} onclick={() => seekLine(seconds)}>{line.text || '•••'}</button>
          {:else}
            <p class="line" class:active data-line={index} style={`--line-opacity: ${opacity}`}>{line.text || '•••'}</p>
          {/if}
        {/each}
        {#if lyricState.lyrics.provider}<p class="provider">{$t('windows.lyrics.provider', [lyricState.lyrics.provider])}</p>{/if}
      </div>
    </div>
    {#if activeIndex !== null && !following}
      <button type="button" class="follow" onclick={resumeFollowing} title={$t('fullscreen.resumeLyricsTracking')}>
        <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="m3 10 18-7-7 18-3-8-8-3Z" /></svg>{$t('fullscreen.returnToCurrentLyric')}
      </button>
    {/if}
  {:else}
    <div class="message"><PlayerIcon name="lyrics" size={36} /><p>{$t('fullscreen.noLyrics')}</p><small>{$t('windows.ui.noLyricsFoundForThisTrack')}</small>
      {#if lyricState.status === 'empty'}<button type="button" class="retry" onclick={onRetry}>{$t('windows.ui.searchAgain')}</button>{/if}
    </div>
  {/if}
</section>

<style>
  .lyrics-panel { flex: 1; width: 100%; height: 100%; min-height: 0; min-width: 0; position: relative; }
  .lyrics-scroll { height: 100%; overflow-y: auto; overflow-x: hidden; overscroll-behavior: contain; scrollbar-width: none; }
  .lyrics-scroll::-webkit-scrollbar { display: none; }
  .lines { display: flex; flex-direction: column; gap: 20px; padding: 12px 8px; }
  .line { display: block; width: 100%; margin: 0; padding: 0; border: 0; background: transparent; color: rgb(255 255 255 / var(--line-opacity)); font-family: inherit; font-size: 25.2px; font-weight: 500; line-height: 1.35; text-align: left; overflow-wrap: anywhere; transform-origin: left center; transition: color .48s ease, transform .48s ease, text-shadow .48s ease; }
  button.line { cursor: pointer; }
  button.line:hover { color: #fff; }
  .line.active { font-weight: 600; transform: scale(1.025); text-shadow: 0 0 9px rgb(255 255 255 / .22); }
  .line:focus-visible { outline: 2px solid rgb(255 255 255 / .7); outline-offset: 5px; border-radius: 3px; }
  .provider { margin: 10px 0; color: rgb(255 255 255 / .45); font-size: 11.5px; }
  .message { height: 100%; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 12px; color: rgb(255 255 255 / .55); text-align: center; padding: 20px; box-sizing: border-box; font-size: 14.5px; }
  .message p { margin: 0; }
  .message small { color: rgb(255 255 255 / .35); font-size: 11.5px; }
  .message :global(svg) { opacity: .45; }
  .spinner { width: 22px; height: 22px; border: 2px solid rgb(255 255 255 / .15); border-top-color: rgb(255 255 255 / .75); border-radius: 50%; animation: spin 1s linear infinite; }
  .retry { border: 0; background: transparent; color: rgb(255 255 255 / .75); padding: 7px 12px; font: inherit; cursor: pointer; }
  .retry:hover { color: #fff; }
  .follow { position: absolute; bottom: 18px; left: 50%; transform: translateX(-50%); display: flex; align-items: center; gap: 8px; white-space: nowrap; padding: 10px 17px; color: #fff; font-family: inherit; font-size: 13px; font-weight: 600; background: var(--sideb-acrylic-fallback, #2c292a); border: 1px solid var(--sideb-acrylic-border, rgb(255 255 255 / .18)); border-radius: 50px; box-shadow: 0 5px 12px rgb(0 0 0 / .3); cursor: pointer; }
  @supports ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
    .follow { background: var(--sideb-acrylic-surface); backdrop-filter: var(--sideb-acrylic-blur); -webkit-backdrop-filter: var(--sideb-acrylic-blur); }
  }
  .follow svg { width: 14px; height: 14px; }
  @keyframes spin { to { transform: rotate(360deg); } }
  @media (prefers-reduced-motion: reduce) { .line { transition: none; } .spinner { animation: none; } }
  @media (forced-colors: active) { .follow { color: ButtonText; background: ButtonFace; border-color: ButtonText; backdrop-filter: none; -webkit-backdrop-filter: none; } }
</style>
