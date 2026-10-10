<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import { t } from '$lib/i18n';
  import { externalUrl, type GeniusAnnotation } from '$lib/genius/types';
  import { annotationVisibleRect, annotationPlacement, type AnnotationPlacement } from '$lib/genius/popover';
  let { annotation, anchor, anchorRectIndex = 0, onClose, onOpenExternal }: { annotation: GeniusAnnotation; anchor: HTMLElement; anchorRectIndex?: number; onClose: (restoreFocus?: boolean) => void; onOpenExternal?: (url: string) => void } = $props();
  let closeButton: HTMLButtonElement;
  let bubble: HTMLDivElement;
  let placement = $state<AnnotationPlacement>({ top: 16, left: 16, width: 400, maxHeight: 520, arrowSide: 'right', arrowOffset: 30 });
  // Fullscreen has a transform during its pull gesture; a portal keeps fixed coordinates in the viewport.
  function portal(node: HTMLDivElement) { document.body.appendChild(node); return { destroy: () => node.remove() }; }
  $effect(() => { anchor; anchorRectIndex; untrack(() => { if (bubble) reposition(); }); });
  function reposition() {
    if (!anchor?.isConnected || !bubble?.isConnected) { onClose(false); return; }
    const rectangles = anchor.getClientRects();
    const rect = rectangles[Math.min(anchorRectIndex, rectangles.length - 1)] ?? anchor.getBoundingClientRect();
    const viewport = { width: window.innerWidth, height: window.innerHeight };
    const clip = anchor.closest('.genius-panel')?.getBoundingClientRect();
    const visibleRect = annotationVisibleRect(rect, viewport, clip);
    if (!visibleRect) { onClose(false); return; }
    placement = annotationPlacement(visibleRect, bubble.getBoundingClientRect().height, viewport);
  }
  onMount(() => {
    reposition(); closeButton?.focus({ preventScroll: true });
    const outside = (event: PointerEvent) => {
      const path = event.composedPath();
      if (!path.includes(bubble) && !path.includes(anchor)) onClose(false);
    };
    const keyboard = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { event.preventDefault(); event.stopImmediatePropagation(); onClose(); }
    };
    const observer = new ResizeObserver(reposition); observer.observe(bubble);
    const anchorObserver = new MutationObserver(() => { if (!anchor.isConnected) onClose(false); });
    anchorObserver.observe(document.body, { childList: true, subtree: true });
    window.addEventListener('pointerdown', outside, true);
    window.addEventListener('keydown', keyboard, true);
    window.addEventListener('resize', reposition);
    window.addEventListener('scroll', reposition, true);
    return () => {
      observer.disconnect(); anchorObserver.disconnect(); window.removeEventListener('pointerdown', outside, true);
      window.removeEventListener('keydown', keyboard, true); window.removeEventListener('resize', reposition);
      window.removeEventListener('scroll', reposition, true);
    };
  });
</script>
<div use:portal bind:this={bubble} data-owns-space tabindex="-1" class="annotation" class:arrow-left={placement.arrowSide==='left'} class:arrow-right={placement.arrowSide==='right'} class:arrow-top={placement.arrowSide==='top'} class:arrow-bottom={placement.arrowSide==='bottom'} style:top={`${placement.top}px`} style:left={`${placement.left}px`} style:width={`${placement.width}px`} style:max-height={`${placement.maxHeight}px`} style:--arrow-offset={`${placement.arrowOffset}px`} role="dialog" aria-label={$t('genius.annotation')}>
  <div class="heading">
    <span>{annotation.verified ? $t('genius.verifiedAnnotation') : annotation.author ? $t('genius.annotationBy', [annotation.author]) : $t('genius.annotation')}{annotation.verified ? ' ✓' : ''}</span>
    <button class="close" bind:this={closeButton} aria-label={$t('genius.closeAnnotation')} onclick={() => onClose()}>×</button>
  </div>
  <div class="annotation-scroll">
    <blockquote>{annotation.fragment}</blockquote>
    <p class="body">{#if annotation.bodySpans.length}{#each annotation.bodySpans as span}{#if externalUrl(span.url) && onOpenExternal}<a href={externalUrl(span.url)!} onclick={(event) => { event.preventDefault(); onOpenExternal?.(externalUrl(span.url)!); }}>{span.text}</a>{:else}{span.text}{/if}{/each}{:else}{annotation.body}{/if}</p>
    {#each annotation.imageUrls as url}{#if externalUrl(url)}<img src={externalUrl(url)!} alt="" loading="lazy" referrerpolicy="no-referrer" />{/if}{/each}
    {#if externalUrl(annotation.shareUrl) && onOpenExternal}<button onclick={() => onOpenExternal?.(externalUrl(annotation.shareUrl)!)}>{$t('genius.openAnnotationOnGenius')}</button>{/if}
  </div>
</div>
<style>
  .annotation { position: fixed; z-index: 1300; display:flex; flex-direction:column; box-sizing: border-box; background: #29292e; border: 1px solid #ffffff26; border-radius: 12px; padding: 20px; box-shadow: 0 12px 50px #0008; color: white; }
  .annotation::before { content:''; position:absolute; width:12px; height:12px; background:#29292e; border:1px solid #ffffff26; transform:rotate(45deg); pointer-events:none; }
  .arrow-right::before {right:-7px;top:calc(var(--arrow-offset) - 6px);border-left:0;border-bottom:0;}
  .arrow-left::before {left:-7px;top:calc(var(--arrow-offset) - 6px);border-right:0;border-top:0;}
  .arrow-top::before {top:-7px;left:calc(var(--arrow-offset) - 6px);border-right:0;border-bottom:0;}
  .arrow-bottom::before {bottom:-7px;left:calc(var(--arrow-offset) - 6px);border-left:0;border-top:0;}
  .heading { display:flex; align-items:center; justify-content:space-between; gap:12px; flex:none; padding-bottom:14px; font-size:13px; font-weight:600; }
  .close {display:grid;place-items:center;width:24px;height:24px;padding:0;flex:none;font-size:22px;line-height:1;}
  .annotation-scroll { overflow:auto; min-height:0; scrollbar-gutter:stable; user-select:text; }
  blockquote { margin:0 0 14px; font-size:13px; font-weight:600; color:#ffffffa6; }
  .body { margin:0 0 14px; white-space:pre-wrap; font-size:14px; line-height:1.55; overflow-wrap:anywhere; }
  a { color:#d99b9f; } img {display:block;max-width:100%;margin:14px 0;border-radius:9px;}
  button {font:inherit;font-size:12px;color:inherit;background:transparent;border:0;cursor:pointer;}
  button:focus-visible,a:focus-visible {outline:2px solid white;outline-offset:3px;}
</style>
