<script lang="ts">
  import { t } from '$lib/i18n';
  import type { TrackOrder } from '$lib/detail/projection';
  let { query = $bindable(''), order = $bindable<TrackOrder>('custom'), allowOrder = true, busy = false, compact = false }:
    { query?: string; order?: TrackOrder; allowOrder?: boolean; busy?: boolean; compact?:boolean } = $props();
  let editor: HTMLInputElement;
</script>
<div class="track-tools" class:compact>
  {#if allowOrder}<label>{$t('menu.sort')} <select bind:value={order} disabled={busy} aria-label={$t('windows.ui.songOrder')}><option value="custom">{$t('detail.sort.custom')}</option><option value="title">{$t('metadata.song')}</option><option value="artist">{$t('menu.sort_artist')}</option><option value="album">{$t('metadata.album')}</option><option value="duration">{$t('detail.track.duration')}</option></select></label>{/if}
  <div class="filter"><input bind:this={editor} bind:value={query} placeholder={$t('detail.search.songs')} aria-label={$t('detail.search.songsInCollection')} onkeydown={event => { if(event.key === 'Escape') { event.preventDefault(); editor.blur(); } }} onfocusout={() => {}} /><button type="button" class:empty={!query} tabindex={query ? 0 : -1} aria-label={$t('detail.search.clear')} onclick={() => { query = ''; editor.focus(); }}>×</button></div>
</div>
<style>
  .track-tools.compact {padding:0;min-height:38px;flex-wrap:wrap;gap:8px 16px;} .compact .filter {flex:1 1 160px;width:auto;max-width:260px;} .compact label {flex:0 1 auto;} .compact select {max-width:100%;min-width:0;}
  .track-tools { display:flex;align-items:center;justify-content:flex-end;gap:16px;padding:12px 32px;min-height:34px;color:#aaaab1;font-size:12px; }
  label { display:flex;align-items:center;gap:8px; } select { color:inherit;background:var(--sideb-background);border:1px solid #ffffff20;border-radius:6px;padding:6px;font:inherit; }
  .filter { display:flex;align-items:center;width:min(240px,50%);border-bottom:1px solid #ffffff20; } input { min-width:0;flex:1;background:transparent;border:0;outline:none;color:inherit;padding:8px 0;font:inherit; } .filter:focus-within { border-color:var(--sideb-highlight);color:white; } button { width:28px;height:28px;flex:none;border:0;border-radius:50%;background:transparent;color:inherit;font-size:20px;cursor:pointer; } .empty { visibility:hidden; } button:focus-visible,select:focus-visible { outline:2px solid var(--sideb-highlight); }
  @media(max-width:600px) { .track-tools {padding-inline:16px;gap:8px;} .filter {width:50%;} }
</style>
