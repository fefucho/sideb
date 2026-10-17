<script lang="ts">
  import {t} from '$lib/i18n';
  import { onMount, tick } from 'svelte';
  import type { BrowseCardDto, SongDto } from '$lib/types';
  import type { SearchPreviewData } from '$lib/search/preview';
  import type { SearchRecent } from '$lib/search/recents';
  import SearchSongRow from './SearchSongRow.svelte';
  import QuickResults from './QuickResults.svelte';

  interface Props {
    preview: SearchPreviewData;
    recents?: SearchRecent[];
    unavailableTrack?: SongDto|null;
    canUndo?: boolean;
    onRecentQuery?: (query:string)=>void;
    onRemoveRecent?: (key:string)=>void;
    onClearRecents?: ()=>void;
    onUndoRecents?: ()=>void;
    backendReady: boolean;
    onQueryChange: (query: string) => void;
    onCommit: (query: string) => void;
    onDismiss: () => void;
    onSelectCard: (card: BrowseCardDto) => void;
    onPlaySong: (song: SongDto) => void;
  }
  let { unavailableTrack=null, recents=[], canUndo=false, onRecentQuery, onRemoveRecent=()=>{}, onClearRecents=()=>{}, onUndoRecents=()=>{}, preview, backendReady, onQueryChange, onCommit, onDismiss, onSelectCard, onPlaySong }: Props = $props();
  let input: HTMLInputElement;
  let dialog: HTMLDivElement;
  let restoreFocus: HTMLElement | null = null;
  let wasOpen = $state(false);
  const hasQuery = $derived(Boolean(preview.query.trim()));
  const recentHeight = $derived(Math.min(540,Math.max(220,96+recents.reduce((height,item)=>height+(item.kind==='track'?66:50),0)+(unavailableTrack?86:0))));

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
    if (event.defaultPrevented || document.querySelector('[role="menu"]')) return;
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
    if (!query || !backendReady) return;
    dismissForNavigation();
    onCommit(query);
  }
  function dismissForNavigation() {
    if (!wasOpen) return;
    wasOpen = false;
    onDismiss();
  }
  function selectCard(card: BrowseCardDto) { dismissForNavigation(); onSelectCard(card); }
  function playSong(song: SongDto) { dismissForNavigation(); onPlaySong(song); }
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="scrim" aria-hidden="true" onclick={dismiss}></div>
<div class="positioner">
  <div class="spotlight" class:has-query={hasQuery} style:height={`${hasQuery?520:recentHeight}px`} bind:this={dialog} role="dialog" aria-modal="true" aria-label="Búsqueda rápida" tabindex="-1">
    <form class="search-header" onsubmit={(event) => { event.preventDefault(); commit(); }}>
      <svg class="search-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7.5"/><path d="m16.5 16.5 4 4"/></svg>
      <input bind:this={input} value={preview.query} oninput={(event) => onQueryChange(event.currentTarget.value)} disabled={!backendReady} placeholder={$t('search.spotlight.placeholder')} aria-label="Buscar canciones, álbumes, artistas y playlists" autocomplete="off" />
      {#if preview.isLoading}<span class="spinner" aria-label="Buscando"></span>{:else if preview.query}<button type="button" class="clear" aria-label="Limpiar búsqueda" onclick={() => { onQueryChange(''); input?.focus(); }}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 7 10 10M17 7 7 17"/></svg></button>{/if}
      <span class="esc">ESC</span>
    </form>
    <div class="divider"></div>
    <div class="results-scroll" aria-live="polite">
      {#if unavailableTrack && !hasQuery}<div class="unavailable" role="alert"><span>{$t('search.recents.unavailable')}</span><button type="button" onclick={()=>{const song=unavailableTrack!;dismissForNavigation();onCommit(`${song.title} ${song.artists}`);}}>{$t('search.recents.search_track')}</button><button type="button" onclick={()=>onRemoveRecent(`track:${unavailableTrack!.isUpload?'upload:':'youtube:'}${unavailableTrack!.videoId}`)}>{$t('search.recents.remove')}</button></div>{/if}
      {#if !hasQuery && (recents.length || canUndo)}
        <div class="recent-heading"><strong>{$t('search.recents.title')}</strong>{#if recents.length}<button type="button" onclick={onClearRecents}>{$t('search.recents.clear')}</button>{/if}{#if canUndo}<button type="button" onclick={onUndoRecents}>{$t('common.undo')}</button>{/if}</div>
        {#each recents as recent (recent.key)}<div class="recent-row">
          {#if recent.kind==='query'}<button type="button" class="recent-query" data-search-primary onclick={()=>{dismissForNavigation();(onRecentQuery ?? onCommit)(recent.query);}}><span aria-hidden="true">⌕</span><span>{recent.query}</span></button>
          {:else}<SearchSongRow spotlight song={recent.track} onPlay={playSong} onOpenArtist={id=>selectCard({kind:'artist',id,title:'',subtitle:null,thumbnail:null,duration:null})} onOpenAlbum={id=>selectCard({kind:'album',id,title:'',subtitle:null,thumbnail:null,duration:null})} />{/if}
          <button type="button" class="recent-remove" aria-label={$t('search.recents.remove')} onclick={()=>onRemoveRecent(recent.key)}>×</button>
        </div>{/each}
      {:else if !hasQuery}<div class="empty"><svg viewBox="0 0 32 32" aria-hidden="true"><circle cx="13" cy="13" r="8"/><path d="m19 19 7 7M12 9v8m-4-4h8"/></svg><span>{$t('search.spotlight.prompt_title')}</span><small>{$t('search.spotlight.prompt_description')}</small></div>
      {:else}<QuickResults preview={preview} variant="spotlight" onSelectCard={selectCard} onPlaySong={playSong} onQuery={query=>{dismissForNavigation();onCommit(query);}} />{#if preview.error}<button type="button" class="retry-preview" onclick={()=>onQueryChange(preview.query)}>{$t('common.retry')}</button>{/if}{/if}
    </div>
    {#if hasQuery}<div class="divider footer-divider"></div><button type="button" class="commit" disabled={!backendReady} onclick={commit}>
      <span class="return-key"><svg viewBox="0 0 16 16" aria-hidden="true"><path d="M13 3v4H4m0 0 3-3M4 7l3 3"/></svg></span>
      <span class="all-results">Ver todos los resultados para <strong>«{preview.query.trim()}»</strong></span><span class="enter-hint">Enter</span>
    </button>{/if}
  </div>
</div>

<style>
 .retry-preview{margin:0 16px 12px;padding:6px 12px;border:0;border-radius:6px;background:var(--sideb-accent,#a33d45);color:white;cursor:pointer}
 .unavailable{display:flex;flex-wrap:wrap;gap:8px;padding:12px 16px;font-size:12px;color:#e6babc}.unavailable span{flex-basis:100%}.unavailable button{border:0;background:transparent;color:inherit;text-decoration:underline;cursor:pointer}
 .recent-heading{display:flex;align-items:center;gap:10px;padding:12px 16px;font-size:12px}.recent-heading strong{margin-right:auto}.recent-heading button,.recent-remove{border:0;background:transparent;color:var(--sideb-secondary,#aaa);cursor:pointer}.recent-row{display:flex;align-items:center;padding:2px 12px}.recent-row :global(.song-row){flex:1;min-width:0}.recent-query{display:flex;flex:1;min-width:0;gap:12px;text-align:left;padding:14px;border:0;background:transparent;color:inherit;cursor:pointer}.recent-query span:last-child{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.recent-remove{padding:10px;font-size:18px}.recent-query:focus-visible,.recent-remove:focus-visible{outline:2px solid var(--sideb-highlight,#d06c70);outline-offset:-2px}

  .scrim { position:fixed; z-index:219; inset:40px 0 0; background:rgb(0 0 0 / 45%); animation:fade-in 250ms ease both; }
  .positioner { position:fixed; z-index:220; inset:40px 0 94px; display:flex; align-items:center; justify-content:center; pointer-events:none; }
  .spotlight { box-sizing:border-box; display:flex; flex-direction:column; width:min(calc(100vw - 48px), 620px); height:220px; max-height:calc(100dvh - 174px); min-height:180px; overflow:hidden; pointer-events:auto; border:1px solid var(--sideb-acrylic-border, rgb(255 255 255 / 20%)); border-radius:18px; color:#fff; background:#25252a; box-shadow:0 14px 42px rgb(0 0 0 / 40%); animation:spotlight-in 250ms ease both; }
  .has-query { height:min(520px, calc(100dvh - 174px)); }
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
  .empty { display:flex; height:100%; flex-direction:column; align-items:center; justify-content:center; gap:8px; color:rgb(255 255 255 / 68%); text-align:center; }
  .empty svg { width:32px; height:32px; margin-bottom:2px; fill:none; stroke:rgb(255 255 255 / 42%); stroke-width:1.6; stroke-linecap:round; stroke-linejoin:round; }
  .empty span { font-size:13px; font-weight:500; }
  .empty small { color:rgb(255 255 255 / 44%); font-size:11.5px; }
  .footer-divider { opacity:.85; }
  .commit { display:flex; flex:none; align-items:center; gap:8px; min-width:0; padding:10px 16px; border:0; color:inherit; background:rgb(255 255 255 / 4%); text-align:left; cursor:pointer; }
  .commit:hover:not(:disabled) { background:rgb(255 255 255 / 8%); }
  .commit:disabled { opacity:.5; cursor:default; }
  .return-key { display:grid; width:22px; height:22px; flex:none; place-items:center; border-radius:4px; background:rgb(255 255 255 / 8%); }
  .return-key svg { width:14px; height:14px; fill:none; stroke:currentColor; stroke-width:1.5; stroke-linecap:round; stroke-linejoin:round; }
  .all-results { flex:1; min-width:0; overflow:hidden; color:rgb(255 255 255 / 60%); font-size:12.5px; text-overflow:ellipsis; white-space:nowrap; }
  .all-results strong { color:rgb(255 255 255 / 94%); font-weight:600; }
  .enter-hint { color:rgb(255 255 255 / 38%); font-size:10px; }
  @keyframes spin { to { transform:rotate(360deg); } }
  @keyframes spotlight-in { from { opacity:0; transform:scale(.96); } to { opacity:1; transform:scale(1); } }
  @keyframes fade-in { from { opacity:0; } to { opacity:1; } }
  @media (prefers-reduced-motion: reduce) { .scrim,.spotlight { animation:none; } }
</style>
