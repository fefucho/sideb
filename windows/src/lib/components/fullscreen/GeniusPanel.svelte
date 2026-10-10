<script lang="ts">
  import { t, language, resolveMessage } from '$lib/i18n';
  import type { GeniusController } from '$lib/genius/controller';
  import { externalUrl, lyricSpans, type GeniusState, type GeniusAnnotation } from '$lib/genius/types';
  import TrackInformation from './TrackInformation.svelte';
  import GeniusAnnotationView from './GeniusAnnotation.svelte';
  import { annotationPalette, annotationTint, annotationText, type AnnotationColorMode } from '$lib/genius/highlight';
  let { state: geniusState, controller, title = '', artists = '', artwork = null, onOpenExternal }: { state: GeniusState; controller: GeniusController; title?: string; artists?: string; artwork?: string | null; onOpenExternal?: (url: string) => void } = $props();
  let colorMode=$state<AnnotationColorMode>('artwork');
  let palette=$state(annotationPalette());
  const tint=$derived(annotationTint(palette,colorMode));
  const activeTint=$derived(annotationTint(palette,colorMode,true));
  $effect(()=>{
    const url=artwork;let current=true;palette=annotationPalette();
    if(url){const image=new Image();image.crossOrigin='anonymous';image.src=url;
      void image.decode().then(()=>{if(!current)return;const canvas=document.createElement('canvas');canvas.width=canvas.height=32;const context=canvas.getContext('2d');if(!context)return;context.drawImage(image,0,0,32,32);palette=annotationPalette(context.getImageData(0,0,32,32).data);}).catch(()=>{/* Artwork unavailable/CORS: neutral fallback, lyrics remain usable. */});}
    return()=>{current=false;};
  });
  let mode = $state<'lyrics' | 'information' | 'annotations'>('lyrics');
  let correcting = $state(false); let options = $state(false); let query = $state('');
  let selected = $state<GeniusAnnotation | null>(null); let anchor = $state<HTMLElement | null>(null); let anchorRectIndex = $state(0);
  let annotationRequest = 0;
  let pendingAnchor: HTMLElement | null = null;
  let hovered = $state<number | null>(null);
  const trackKey = $derived(geniusState.trackKey);
  $effect(() => { trackKey; ++annotationRequest; pendingAnchor = null; mode = 'lyrics'; correcting = false; selected = null; options = false; query = ''; });
  function closeAnnotation(restoreFocus = true) { ++annotationRequest; pendingAnchor = null; selected = null; if (restoreFocus) anchor?.focus({ preventScroll: true }); anchor = null; }
  function cancelPendingAnnotation(event: PointerEvent) {
    if (pendingAnchor && !event.composedPath().includes(pendingAnchor)) { ++annotationRequest; pendingAnchor = null; }
  }
  async function showAnnotation(id: number, event: MouseEvent) {
    const key = trackKey; const button = event.currentTarget as HTMLElement;
    const selection = window.getSelection();
    if (event.detail > 0 && selection && !selection.isCollapsed && selection.containsNode(button, true)) return;
    const rectangles=Array.from(button.getClientRects());
    const clip=button.closest('.genius-panel')?.getBoundingClientRect();
    const clickedRect=event.detail>0?rectangles.findIndex(rect=>event.clientX>=rect.left&&event.clientX<=rect.right&&event.clientY>=rect.top&&event.clientY<=rect.bottom):rectangles.findIndex(rect=>rect.bottom>Math.max(0,clip?.top??0)&&rect.top<Math.min(window.innerHeight,clip?.bottom??window.innerHeight));
    const request = ++annotationRequest;
    pendingAnchor = button;
    await controller.ensureAnnotation(id);
    if (request !== annotationRequest || key !== trackKey || !button.isConnected) return;
    pendingAnchor = null;
    const annotation = geniusState.annotations.find(item => item.referentId === id || item.id === id); if (!annotation) return;
    anchor = button;
    anchorRectIndex = Math.max(0,clickedRect);
    selected = annotation;
  }
  function annotationKey(event: KeyboardEvent) {
    if(event.key==='Enter'||event.key===' '){event.preventDefault();event.stopPropagation();if(!event.repeat)(event.currentTarget as HTMLElement).click();}
  }
  function cancelMovingRequest(){if(pendingAnchor){++annotationRequest;pendingAnchor=null;}}
  function openListAnnotation(annotation: GeniusAnnotation, event: MouseEvent) { void showAnnotation(annotation.referentId, event); }
  function changeMode(next: typeof mode) { ++annotationRequest; pendingAnchor = null; mode = next; options = false; selected = null; }
  async function choose(candidate: import('$lib/genius/types').GeniusCandidate) { await controller.choose(candidate); if (geniusState.resolution?.song?.id === candidate.id) correcting = false; }
  const candidates = $derived(geniusState.searchResults.length ? geniusState.searchResults : geniusState.resolution?.candidates ?? []);
</script>
<svelte:window onpointerdown={cancelPendingAnnotation} onresize={cancelMovingRequest} />
<section class="genius-panel" data-owns-space aria-label={$t('genius.lyricsAndAnnotations')} style:--annotation-tint={tint} style:--annotation-active-tint={activeTint} onscroll={cancelMovingRequest}>
  <div class="options">
    <button class="menu-trigger" aria-label={$t('genius.options')} aria-expanded={options} onclick={() => options = !options}>⋯</button>
    {#if options}<div class="menu" role="group" aria-label={$t('genius.options')}>
      <button onclick={() => changeMode('lyrics')}>{$t('genius.backToLyrics')}</button>
      <button onclick={() => changeMode('information')}>{$t('fullscreen.songInformation')}</button>
      <button onclick={() => changeMode('annotations')}>{$t('genius.annotations')}</button>
      <button onclick={() => { correcting = true; options = false; }}>{$t('genius.changeMatch')}</button>
      <button onclick={() => { options = false; void controller.refresh(); }}>{$t('genius.refreshData')}</button>
      <label class="color-choice">{$t('windows.genius.annotationColor')}<select bind:value={colorMode} aria-label={$t('windows.genius.annotationColor')}><option value="artwork">{$t('windows.genius.colorArtwork')}</option><option value="contrast">{$t('windows.genius.colorContrast')}</option><option value="neutral">{$t('windows.genius.colorNeutral')}</option></select></label>
      {#if externalUrl(geniusState.resolution?.song?.url) && onOpenExternal}<button onclick={() => onOpenExternal?.(externalUrl(geniusState.resolution?.song?.url)!)}>{$t('genius.viewOnGenius')}</button>{/if}
      <label><input type="checkbox" checked={geniusState.automaticFetch} onchange={(e) => controller.setAutomaticFetch(e.currentTarget.checked)} />{$t('genius.automaticSearch')}</label>
      <label><input type="checkbox" checked={geniusState.diagnostics} onchange={(e) => controller.setDiagnostics(e.currentTarget.checked)} />{$t('genius.showDiagnostics')}</label>
    </div>{/if}
  </div>
  {#if geniusState.error}<p role="alert">{resolveMessage(geniusState.error, $language)} <button onclick={() => geniusState.resolution?.song ? controller.retryContents() : controller.refresh()}>{$t('common.retry')}</button></p>{/if}
  {#if geniusState.diagnostics}<p class="diagnostics">{$t('genius.diagnostics')} · {geniusState.phase} · {geniusState.annotations.length}</p>{/if}
  {#if correcting || geniusState.phase === 'ambiguous' || geniusState.phase === 'notFound'}
    <div class="candidates">
      <h2>{geniusState.phase === 'ambiguous' ? $t('genius.multipleMatches') : $t('genius.chooseMatchingTrack')}</h2>
      <form onsubmit={(event) => { event.preventDefault(); void controller.search(query); }}><input bind:value={query} aria-label={$t('genius.titleAndArtist')} placeholder={$t('genius.titleAndArtist')} /><button disabled={geniusState.searching || !query.trim()}>{$t('genius.searchAnotherVersion')}</button></form>
      {#if geniusState.searching}<p role="status">{$t('genius.searching')}</p>{/if}
      {#each candidates as candidate (candidate.id)}<button class="candidate" title={$t('genius.useTrackHint')} onclick={() => choose(candidate)}><strong>{candidate.title}</strong><span>{candidate.artist}</span></button>{/each}
      {#if correcting}<button onclick={() => correcting = false}>{$t('common.cancel')}</button>{/if}
      {#if geniusState.phase === 'ambiguous' || geniusState.phase === 'notFound'}<p>{$t('genius.noMatchGuidance')}</p><button disabled={geniusState.reporting || geniusState.reportSaved} onclick={() => controller.reportCurrentMiss()}>{geniusState.reportSaved ? $t('genius.savedForReview') : $t('genius.saveTrackForReview')}</button>{/if}
    </div>
  {:else if mode === 'information'}<TrackInformation song={geniusState.resolution?.song} {title} {artists} {onOpenExternal} />
  {:else if mode === 'annotations'}
    {#each geniusState.annotations as annotation (annotation.id)}<button class="annotation-row" onclick={(event) => openListAnnotation(annotation, event)}>{annotation.fragment}</button>{/each}
    {#if geniusState.nextPage}<button disabled={geniusState.loadingAnnotations} onclick={() => controller.loadMoreAnnotations()}>{$t('genius.loadMoreAnnotations')}</button>{/if}
  {:else if geniusState.phase === 'loading'}<p role="status">{$t('genius.searchingInformation')}</p>
  {:else if geniusState.phase === 'error' || geniusState.phase === 'idle'}<p>{$t('genius.tryAgainLater')}</p><button onclick={() => controller.refresh()}>{$t('common.retry')}</button>
  {:else if geniusState.loadingLyrics && !geniusState.lyrics.length}<p role="status">{$t('genius.loadingLyrics')}</p>
  {:else if !geniusState.lyrics.length}<p>{$t('genius.noLyricsAvailable')}</p>
  {:else}
    <div class="lyrics" aria-label={$t('genius.lyricsAndAnnotations')}>
      {#each geniusState.lyrics as line, index (index)}<p class:header={line.isHeader}>{#each lyricSpans(line) as span, spanIndex (spanIndex)}{@const pieces=annotationText(span.text)}{#if span.referentId !== null && pieces.text}{pieces.before}<span role="button" tabindex="0" class="lyric-span" class:highlighted={hovered === span.referentId} class:active={selected?.referentId === span.referentId} aria-label={`${$t('genius.annotation')}: ${span.text}`} aria-pressed={selected?.referentId === span.referentId} onkeydown={annotationKey} onmouseenter={() => hovered = span.referentId} onmouseleave={() => hovered = null} onfocus={() => hovered = span.referentId} onblur={() => hovered = null} onclick={(event) => showAnnotation(span.referentId!, event)}>{pieces.text}</span>{pieces.after}{:else}{span.text}{/if}{/each}</p>{/each}
    </div>
  {/if}
  {#if selected && anchor}{#key `${trackKey}:${selected.id}:${anchorRectIndex}`}<GeniusAnnotationView annotation={selected} {anchor} {anchorRectIndex} onClose={closeAnnotation} {onOpenExternal} />{/key}{/if}
</section>
<style>
  .genius-panel { height: 100%; overflow: auto; scrollbar-gutter:stable; position: relative; padding: 16px 50px 30px 12px; color: #f4f4f5; box-sizing: border-box; } button,input { font: inherit; color: inherit; } button { border: 1px solid #ffffff20; border-radius: 8px; padding: 8px 10px; background: #ffffff0d; cursor: pointer; } button:focus-visible,input:focus-visible { outline: 2px solid white; outline-offset: 3px; } button:disabled { opacity: .5; cursor: default; } .options { position: absolute; right: 8px; top: 8px; z-index: 2; } .menu-trigger { font-size: 24px; border: none; background: transparent; } .menu { position: absolute; right: 0; width: 270px; display: grid; padding: 8px; border: 1px solid #ffffff20; border-radius: 12px; background: #29292e; box-shadow: 0 8px 28px #0008; } .menu button { text-align: left; border: none; } .menu label { padding: 8px; font-size: 13px; } form { display: flex; gap: 8px; flex-wrap: wrap; } input:not([type=checkbox]) { background: #ffffff0d; border: 1px solid #ffffff30; border-radius: 8px; padding: 8px; flex: 1; min-width: 100px; } .candidate,.annotation-row { display: grid; text-align: left; margin: 8px 0; width: 100%; } .candidate span { opacity: .65; } .lyrics { text-align: left; user-select: text; font-size: 20px; font-weight: 600; line-height: 1.45; white-space: pre-wrap; overflow-wrap: anywhere; } .lyrics p { margin: 0 0 7px; } .lyrics p.header { font-size: 16px; font-weight: 700; opacity: .6; margin: 18px 0 6px; } .lyrics p.header:first-child { margin-top:4px; } .lyrics .lyric-span { display: inline; font: inherit; line-height: inherit; white-space: pre-wrap; color: inherit; padding: 0; border: 0; border-radius: 1px; background: rgb(var(--annotation-tint) / .16); user-select: text; box-decoration-break: clone; -webkit-box-decoration-break: clone; cursor: pointer; text-align: left; } .lyrics .lyric-span.highlighted { background: rgb(var(--annotation-tint) / .28); } .lyrics .lyric-span.active { background: rgb(var(--annotation-active-tint) / .48); } .diagnostics { font-size: 12px; opacity: .6; }
.lyric-span:focus-visible {outline:2px solid white;outline-offset:2px;} .color-choice {display:flex;align-items:center;gap:8px;justify-content:space-between;} .color-choice select {max-width:130px;font:inherit;color:inherit;background:#29292e;border:1px solid #ffffff30;border-radius:5px;padding:4px;}
</style>
