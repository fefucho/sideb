<script lang="ts">
  import { t } from '$lib/i18n';
  import { externalUrl, type GeniusSong } from '$lib/genius/types';
  let { song = null, title = '', artists = '', album = '', loading = false, onClose, onShowGenius, onOpenExternal }: { song?: GeniusSong | null; title?: string; artists?: string; album?: string; loading?: boolean; onClose?: () => void; onShowGenius?: () => void; onOpenExternal?: (url: string) => void } = $props();
</script>
<article class="track-information" class:card={!!onClose} aria-label={$t('fullscreen.songInformation')}>
  {#if onClose}<header><span><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10" fill="currentColor"/><path d="M12 10v7" stroke="#1a1a1f" stroke-width="2"/><circle cx="12" cy="7" r="1.2" fill="#1a1a1f"/></svg>{$t('fullscreen.information')}</span><button class="close" aria-label={$t('fullscreen.backToArtwork')} title={$t('fullscreen.backToArtwork')} onclick={onClose}><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10" fill="currentColor"/><path d="m8 8 8 8m0-8-8 8" stroke="#1a1a1f" stroke-width="2" stroke-linecap="round"/></svg></button></header>{/if}
  <h2>{song?.title || title}</h2>
  <p class="artist">{song?.artist || artists}</p>
  <div class="information-scroll">
    {#if song}
      <p class="description">{song.description || $t('genius.noSongDescription')}</p>
      {#if song.releaseDate}<p class="date">{song.releaseDate}</p>{/if}
      {#if song.producers.length}<h3>{$t('genius.production')}</h3><p>{song.producers.join(', ')}</p>{/if}
      {#if song.writers.length}<h3>{$t('genius.composition')}</h3><p>{song.writers.join(', ')}</p>{/if}
      {#each song.performances as performance}<h3>{performance.label}</h3><p>{performance.artists.join(', ')}</p>{/each}
      {#if !onClose && externalUrl(song.url) && onOpenExternal}<button onclick={() => onOpenExternal?.(externalUrl(song?.url)!)}>{$t('genius.viewOnGenius')}</button>{/if}
    {:else}<div class="empty">{#if loading}<p role="status">{$t('genius.searchingInformation')}</p>{:else}<p>{$t('genius.noAdditionalInformation')}</p>{#if album}<p class="album">{album}</p>{/if}{/if}</div>{/if}
  </div>
  {#if onShowGenius}<button class="show-lyrics" onclick={onShowGenius}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><path d="M5 3h14v18H5zM8 7h8M8 11h8M8 15h5"/></svg>{$t('genius.lyricsAndAnnotations')}</button>{/if}
</article>
<style>
  .track-information { box-sizing:border-box; display:flex; flex-direction:column; gap:13px; width:100%; max-width:640px; min-width:0; min-height:0; padding:22px; overflow-wrap:anywhere; color:white; }
  .track-information.card {height:100%;max-width:none;background:#1a1a1f;border-radius:8px;}
  header {display:flex;justify-content:space-between;align-items:center;gap:4px;color:#ffffffd9;font-size:15px;font-weight:600;flex:none;}
  header span {display:flex;align-items:center;gap:6px;} header svg {width:17px;height:17px;flex:none;}
  .close {display:grid;place-items:center;padding:0;color:#ffffffb8;} .close svg {width:18px;height:18px;}
  h2 {margin:0;font-size:20px;font-weight:700;line-height:1.25;display:-webkit-box;line-clamp:2;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;flex:none;}
  .artist {margin:0;color:#ffffffa8;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;flex:none;}
  .information-scroll {min-width:0;min-height:0;flex:1;overflow:auto;scrollbar-gutter:stable;user-select:text;}
  h3 {font-size:10px;text-transform:uppercase;font-weight:700;margin:12px 0 3px;}
  p {margin:0;line-height:1.45;font-size:13px;color:#ffffffdb;}
  .description {white-space:pre-wrap;font-size:14px;margin-bottom:12px;} .date {font-size:12px;color:#ffffffb3;}
  .empty {height:100%;min-height:70px;display:flex;flex-direction:column;justify-content:center;gap:6px;text-align:center;}
  .empty p {color:#ffffffa6;} .empty .album {font-size:12px;color:#ffffff80;}
  button {font:inherit;color:inherit;border:0;background:transparent;cursor:pointer;} button:focus-visible {outline:2px solid white;outline-offset:3px;}
  .show-lyrics {display:flex;align-items:center;gap:6px;padding:0;font-size:12px;font-weight:600;text-align:left;flex:none;}
  .show-lyrics svg {width:14px;height:14px;flex:none;}
  @container(max-width:299px) { .track-information {padding:16px;gap:8px;} header {font-size:13px;} h2 {font-size:16px;} .description {font-size:12px;} }
</style>
