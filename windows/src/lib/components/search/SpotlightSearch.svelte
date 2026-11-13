<script lang="ts">
  import {t} from '$lib/i18n';
  import { onMount, tick } from 'svelte';
  import type { BrowseCardDto, SearchSuggestionEntryDto, SongDto } from '$lib/types';
  import type { SearchPreviewData } from '$lib/search/provider-preview';
  import QuickResults from './QuickResults.svelte';

  interface Props {
    preview: SearchPreviewData;
    onRemoveSuggestion?:(token:string)=>void;
    backendReady: boolean;
    onQueryChange: (query: string) => void;
    onCommit: (query: string) => void;
    onDismiss: () => void;
    onSelectCard: (card: BrowseCardDto) => void;
    onPlaySong: (song: SongDto) => void;
    /** Hangs the field and results under the top navigation capsules instead of centering a modal. */
    anchored?: boolean;
    /** Side B's own recents (opened artists/albums/playlists and played songs), shaped as suggestion entries. */
    local?: SearchSuggestionEntryDto[];
    canUndoRecents?: boolean;
    onRemoveLocal?: (key: string) => void;
    onClearRecents?: () => void;
    onUndoRecents?: () => void;
  }
  let {anchored=false,local=[],canUndoRecents=false,onRemoveLocal,onClearRecents,onUndoRecents,onRemoveSuggestion,preview,backendReady,onQueryChange,onCommit,onDismiss,onSelectCard,onPlaySong}:Props=$props();
  let input = $state<HTMLInputElement>();
  let dialog = $state<HTMLDivElement>();
  let restoreFocus: HTMLElement | null = null;
  let wasOpen = $state(false);
  let composing=false;
  const hasQuery = $derived(Boolean(preview.query.trim()));
  const showPanel = $derived(hasQuery || preview.isLoading || Boolean(preview.error) || Boolean(preview.entries?.length) || local.length > 0);

  onMount(() => {
    restoreFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    void tick().then(() => input?.focus());
    wasOpen = true;
  });
  function dismiss() {
    if (!wasOpen) return;
    wasOpen = false;
    onDismiss();
    queueMicrotask(() => restoreFocus?.focus());
  }
  function handleKeydown(event: KeyboardEvent) {
    if (event.isComposing || event.defaultPrevented || document.querySelector('[role="menu"]')) return;
    if (event.key === 'Escape') {
      event.preventDefault(); event.stopPropagation(); dismiss(); return;
    }
    if ((event.key === 'ArrowDown' || event.key === 'ArrowUp') && dialog) {
      const rows=[...dialog.querySelectorAll<HTMLElement>('.results-scroll button[data-search-primary]:not(:disabled)')].filter(element=>element.offsetParent!==null);
      const index=rows.indexOf(document.activeElement as HTMLElement);
      const next=event.key==='ArrowDown'?Math.min(index+1,rows.length-1):index<=0?-1:index-1;
      event.preventDefault(); if(next<0)input?.focus();else rows[next]?.focus(); return;
    }
    if (event.key !== 'Tab' || !dialog) return;
    const focusable = [...dialog.querySelectorAll<HTMLElement>('button:not(:disabled), input:not(:disabled), [tabindex="0"]')]
      .filter((element) => element.offsetParent !== null);
    if (!focusable.length) { event.preventDefault(); input?.focus(); return; }
    const first = focusable[0], last = focusable[focusable.length - 1];
    if (event.shiftKey && (document.activeElement === first || !dialog.contains(document.activeElement))) {
      event.preventDefault(); last.focus();
    } else if (!event.shiftKey && (document.activeElement === last || !dialog.contains(document.activeElement))) {
      event.preventDefault(); first.focus();
    }
  }
  function commit() {
    const query = preview.query.trim();
    if (composing || !query || !backendReady) return;
    dismissForNavigation();
    onCommit(query);
  }
  function dismissForNavigation() {
    if (!wasOpen) return;
    wasOpen = false;
    onDismiss();
  }
  function outsidePointer(event: PointerEvent) {
    if (!anchored || !wasOpen || !(event.target instanceof Node) || dialog?.contains(event.target)) return;
    dismiss();
  }
  function selectCard(card: BrowseCardDto) { dismissForNavigation(); onSelectCard(card); }
  function playSong(song: SongDto) { dismissForNavigation(); onPlaySong(song); }
</script>

<svelte:window onkeydown={handleKeydown} onpointerdown={outsidePointer} />

{#if anchored}
<div class="anchored" bind:this={dialog} role="dialog" aria-modal="false" aria-label="Búsqueda rápida">
  <form class="capsule" onsubmit={(event) => { event.preventDefault(); commit(); }}>
    <svg class="search-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7.5"/><path d="m16.5 16.5 4 4"/></svg>
    <input oncompositionstart={()=>composing=true} oncompositionend={()=>composing=false} bind:this={input} value={preview.query} oninput={(event) => onQueryChange(event.currentTarget.value)} disabled={!backendReady} placeholder={$t('search.spotlight.placeholder')} aria-label="Buscar canciones, álbumes, artistas y playlists" autocomplete="off" />
    {#if preview.isLoading}<span class="spinner" aria-label="Buscando"></span>{:else if preview.query}<button type="button" class="clear" aria-label="Limpiar búsqueda" onclick={() => { onQueryChange(''); input?.focus(); }}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 7 10 10M17 7 7 17"/></svg></button>{/if}
  </form>
  {#if showPanel}
  <div class="panel" class:has-query={hasQuery}>
    <div class="results-scroll" aria-live="polite">
      <QuickResults preview={preview} variant="spotlight" {onRemoveSuggestion} {local} {canUndoRecents} {onRemoveLocal} {onClearRecents} {onUndoRecents} onSelectCard={selectCard} onPlaySong={playSong} onQuery={query=>{dismissForNavigation();onCommit(query);}} />{#if preview.error}<button type="button" class="retry-preview" onclick={()=>onQueryChange(preview.query)}>{$t('common.retry')}</button>{/if}
    </div>
    {#if hasQuery}<div class="divider footer-divider"></div><button type="button" class="commit" disabled={!backendReady} onclick={commit}>
      <span class="return-key"><svg viewBox="0 0 16 16" aria-hidden="true"><path d="M13 3v4H4m0 0 3-3M4 7l3 3"/></svg></span>
      <span class="all-results">Ver todos los resultados para <strong>«{preview.query.trim()}»</strong></span><span class="enter-hint">Enter</span>
    </button>{/if}
  </div>
  {/if}
</div>
{:else}
<div class="scrim" aria-hidden="true" onclick={dismiss}></div>
<div class="positioner">
  <div class="spotlight" class:has-query={hasQuery} style:height="520px" bind:this={dialog} role="dialog" aria-modal="true" aria-label="Búsqueda rápida" tabindex="-1">
    <form class="search-header" onsubmit={(event) => { event.preventDefault(); commit(); }}>
      <svg class="search-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7.5"/><path d="m16.5 16.5 4 4"/></svg>
      <input oncompositionstart={()=>composing=true} oncompositionend={()=>composing=false} bind:this={input} value={preview.query} oninput={(event) => onQueryChange(event.currentTarget.value)} disabled={!backendReady} placeholder={$t('search.spotlight.placeholder')} aria-label="Buscar canciones, álbumes, artistas y playlists" autocomplete="off" />
      {#if preview.isLoading}<span class="spinner" aria-label="Buscando"></span>{:else if preview.query}<button type="button" class="clear" aria-label="Limpiar búsqueda" onclick={() => { onQueryChange(''); input?.focus(); }}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 7 10 10M17 7 7 17"/></svg></button>{/if}
      <span class="esc">ESC</span>
    </form>
    <div class="divider"></div>
    <div class="results-scroll" aria-live="polite">
      <QuickResults preview={preview} variant="spotlight" {onRemoveSuggestion} {local} {canUndoRecents} {onRemoveLocal} {onClearRecents} {onUndoRecents} onSelectCard={selectCard} onPlaySong={playSong} onQuery={query=>{dismissForNavigation();onCommit(query);}} />{#if preview.error}<button type="button" class="retry-preview" onclick={()=>onQueryChange(preview.query)}>{$t('common.retry')}</button>{/if}
    </div>
    {#if hasQuery}<div class="divider footer-divider"></div><button type="button" class="commit" disabled={!backendReady} onclick={commit}>
      <span class="return-key"><svg viewBox="0 0 16 16" aria-hidden="true"><path d="M13 3v4H4m0 0 3-3M4 7l3 3"/></svg></span>
      <span class="all-results">Ver todos los resultados para <strong>«{preview.query.trim()}»</strong></span><span class="enter-hint">Enter</span>
    </button>{/if}
  </div>
</div>
{/if}

<style>
 .retry-preview{margin:0 16px 12px;padding:6px 12px;border:0;border-radius:6px;background:var(--sideb-accent,#a33d45);color:white;cursor:pointer}

  .scrim { position:fixed; z-index:219; inset:0; background:rgb(0 0 0 / 45%); animation:fade-in 250ms ease both; }
  .positioner { position:fixed; z-index:220; inset:calc(var(--titlebar-height, 32px) + 16px) 0 94px; display:flex; align-items:center; justify-content:center; pointer-events:none; }
  .spotlight { box-sizing:border-box; display:flex; flex-direction:column; width:min(calc(100vw - 48px), 620px); height:220px; max-height:100%; min-height:0; overflow:hidden; pointer-events:auto; border:1px solid var(--sideb-acrylic-border, rgb(255 255 255 / 20%)); border-radius:18px; color:#fff; background:#25252a; box-shadow:0 14px 42px rgb(0 0 0 / 40%); animation:spotlight-in 250ms ease both; }
  @supports ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) { .spotlight { background:rgb(37 37 42 / 92%); backdrop-filter:var(--sideb-acrylic-blur, blur(20px) saturate(1.4)); -webkit-backdrop-filter:var(--sideb-acrylic-blur, blur(20px) saturate(1.4)); } }
  .search-header { display:flex; flex:none; align-items:center; gap:14px; min-width:0; padding:16px 20px; }
  .search-icon { width:18px; height:18px; flex:none; fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; }
  input { flex:1; min-width:0; padding:0; border:0; outline:0; color:#fff; background:transparent; font-family:inherit; font-size:16px; font-weight:400; line-height:1.35; }
  input::placeholder { color:rgb(255 255 255 / 40%); }
  input:disabled { opacity:.55; }
  .clear { display:grid; width:22px; height:22px; padding:3px; place-items:center; border:0; border-radius:50%; color:rgb(255 255 255 / 66%); background:transparent; cursor:pointer; }
  .clear:hover { background:rgb(255 255 255 / 10%); color:#fff; }
  .clear svg { width:14px; height:14px; fill:none; stroke:currentColor; stroke-width:2; stroke-linecap:round; }
  .esc { flex:none; padding:3px 6px; border-radius:4px; color:rgb(255 255 255 / 55%); background:rgb(255 255 255 / 8%); font-size:10px; font-weight:700; }
  .spinner { width:15px; height:15px; flex:none; border:2px solid rgb(255 255 255 / 20%); border-top-color:rgb(255 255 255 / 80%); border-radius:50%; animation:spin .8s linear infinite; }
  .divider { flex:none; height:1px; background:rgb(255 255 255 / 18%); }
  .results-scroll { flex:1; min-height:0; overflow-y:auto; padding:14px 16px; }
  .has-query .results-scroll { display:flex; flex-direction:column; gap:8px; }
  .footer-divider { opacity:.85; }
  .commit { display:flex; flex:none; align-items:center; gap:8px; min-width:0; padding:10px 16px; border:0; color:inherit; background:rgb(255 255 255 / 4%); text-align:left; cursor:pointer; }
  .commit:hover:not(:disabled) { background:rgb(255 255 255 / 8%); }
  .commit:disabled { opacity:.5; cursor:default; }
  .return-key { display:grid; width:22px; height:22px; flex:none; place-items:center; border-radius:4px; background:rgb(255 255 255 / 8%); }
  .return-key svg { width:14px; height:14px; fill:none; stroke:currentColor; stroke-width:1.5; stroke-linecap:round; stroke-linejoin:round; }
  .all-results { flex:1; min-width:0; overflow:hidden; color:rgb(255 255 255 / 60%); font-size:12.5px; text-overflow:ellipsis; white-space:nowrap; }
  .all-results strong { color:rgb(255 255 255 / 94%); font-weight:600; }
  .enter-hint { color:rgb(255 255 255 / 38%); font-size:10px; }
  /* Anchored: same glass family as the top navigation capsules; it starts where the search button sits (inset + 42 reopen + 10 gap). */
  .anchored { display:contents; }
  .capsule { position:fixed; z-index:220; top:var(--topnav-top, 28px); left:calc(var(--topnav-inset, 28px) + 52px); box-sizing:border-box; display:flex; align-items:center; gap:10px; width:298px; height:42px; padding:0 14px; border:1px solid var(--sideb-acrylic-border, rgb(255 255 255 / 20%)); border-radius:21px; color:#fff; background:var(--sideb-acrylic-surface, rgb(43 43 49 / 62%)); backdrop-filter:var(--sideb-acrylic-blur); -webkit-backdrop-filter:var(--sideb-acrylic-blur); box-shadow:0 0 0 1px rgb(0 0 0 / 14%), 0 4px 14px rgb(0 0 0 / 22%); }
  .capsule input { font-size:14px; }
  .panel { position:fixed; z-index:220; top:calc(var(--topnav-top, 28px) + 50px); left:calc(var(--topnav-inset, 28px) + 52px); box-sizing:border-box; display:flex; flex-direction:column; width:min(560px, calc(100vw - var(--topnav-inset, 28px) - 70px)); max-height:min(640px, calc(100dvh - 170px)); min-height:0; overflow:hidden; border:1px solid var(--sideb-acrylic-border, rgb(255 255 255 / 20%)); border-radius:18px; color:#fff; background:#25252a; box-shadow:0 14px 42px rgb(0 0 0 / 40%); animation:fade-in 140ms ease both; }
  @supports ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) { .panel { background:rgb(37 37 42 / 92%); backdrop-filter:var(--sideb-acrylic-blur, blur(20px) saturate(1.4)); -webkit-backdrop-filter:var(--sideb-acrylic-blur, blur(20px) saturate(1.4)); } }
  @media (prefers-reduced-transparency: reduce) { .capsule { background:var(--sideb-acrylic-fallback, #353538); backdrop-filter:none; -webkit-backdrop-filter:none; } .panel { background:#25252a; backdrop-filter:none; -webkit-backdrop-filter:none; } }
  @media (forced-colors: active) { .capsule, .panel { background:Canvas; color:CanvasText; border-color:CanvasText; box-shadow:none; backdrop-filter:none; } }
  @keyframes spin { to { transform:rotate(360deg); } }
  @keyframes spotlight-in { from { opacity:0; transform:scale(.96); } to { opacity:1; transform:scale(1); } }
  @keyframes fade-in { from { opacity:0; } to { opacity:1; } }
  @media (prefers-reduced-motion: reduce) { .scrim,.spotlight,.panel { animation:none; } }
</style>
