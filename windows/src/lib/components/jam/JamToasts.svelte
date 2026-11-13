<script lang="ts">
  import { onDestroy } from 'svelte';
  import { t, language } from '$lib/i18n';
  import type { JamNoticeView } from '$lib/jam/types';
  import { noticeText, noticeTone } from './view';

  /** Transient notices of the Jam (port of `JamToastView`): top centre, one per notice, auto-dismissed. */
  let { toasts, onDismiss, duration = 4500 }: { toasts: Array<JamNoticeView & { id: number }>; onDismiss: (id: number) => void; duration?: number } = $props();
  const timers = new Map<number, ReturnType<typeof setTimeout>>();
  // Each toast gets its own timer, started when it first shows and dropped once the logic removes it.
  $effect(() => {
    const live = new Set(toasts.map(toast => toast.id));
    for (const toast of toasts) if (!timers.has(toast.id)) timers.set(toast.id, setTimeout(() => { timers.delete(toast.id); onDismiss(toast.id); }, duration));
    for (const [id, timer] of timers) if (!live.has(id)) { clearTimeout(timer); timers.delete(id); }
  });
  onDestroy(() => { for (const timer of timers.values()) clearTimeout(timer); timers.clear(); });
  const dismiss = (id: number) => { clearTimeout(timers.get(id)); timers.delete(id); onDismiss(id); };
</script>

<div class="toasts" data-jam-toasts role="region" aria-label={$t('jam.panel.title')}>
  {#each toasts as toast (toast.id)}
    {@const tone = noticeTone(toast.key)}
    <div class={`toast ${tone}`} role={tone === 'warning' ? 'alert' : 'status'} data-toast-id={toast.id} data-toast-key={toast.key}>
      <svg class="icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        {#if tone === 'success'}<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm4.600 7.600-5.400 6a.9.9 0 0 1-1.300.1l-2.600-2.400 1.200-1.300 1.900 1.700 4.800-5.300Z" />
        {:else if tone === 'warning'}<path d="M12 2.500 1.500 21h21Zm-1 6h2v6h-2Zm0 8h2v2h-2Z" />
        {:else}<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm-1 5h2v2h-2Zm0 4h2v6h-2Z" />{/if}
      </svg>
      <span class="text">{noticeText(toast, $language)}</span>
      <button type="button" class="dismiss" title={$t('jam.toast.dismiss')} aria-label={$t('jam.toast.dismiss')} onclick={() => dismiss(toast.id)}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.800" stroke-linecap="round" aria-hidden="true"><path d="M6 6 18 18M18 6 6 18" /></svg>
      </button>
    </div>
  {/each}
</div>

<style>
  .toasts { position: fixed; z-index: 850; top: 14px; left: 50%; display: flex; flex-direction: column; align-items: center; gap: 8px; width: max-content; max-width: min(420px, calc(100vw - 32px)); transform: translateX(-50%); pointer-events: none; }
  .toast { display: flex; align-items: center; gap: 10px; box-sizing: border-box; max-width: 100%; padding: 10px 10px 10px 14px; border: .75px solid var(--sideb-acrylic-border, rgb(255 255 255 / 20%)); border-radius: 16px; color: #fff; background: var(--sideb-acrylic-fallback, #353538); box-shadow: 0 4px 12px rgb(0 0 0 / 25%); font-size: 13px; font-weight: 500; line-height: 1.35; pointer-events: auto; }
  .toast { animation: toast-in 200ms ease-out; }
  @keyframes toast-in { from { opacity: 0; transform: translateY(-12px); } }
  @media (prefers-reduced-motion: reduce) { .toast { animation: none; } }
  @supports ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
    .toast { background: color-mix(in srgb, #000 45%, var(--sideb-acrylic-surface, rgb(43 43 49 / 78%))); backdrop-filter: var(--sideb-acrylic-blur); -webkit-backdrop-filter: var(--sideb-acrylic-blur); }
  }
  .icon { flex: none; width: 15px; height: 15px; } .success .icon { color: #34c759; } .warning .icon { color: #ff9f0a; } .info .icon { color: rgb(255 255 255 / 80%); }
  .text { display: -webkit-box; min-width: 0; overflow: hidden; -webkit-line-clamp: 3; line-clamp: 3; -webkit-box-orient: vertical; overflow-wrap: anywhere; }
  .dismiss { display: grid; flex: none; place-items: center; width: 20px; height: 20px; padding: 0; border: 0; border-radius: 6px; color: rgb(255 255 255 / 60%); background: transparent; cursor: pointer; }
  .dismiss:hover { color: #fff; background: rgb(255 255 255 / 12%); } .dismiss svg { width: 10px; height: 10px; }
  .dismiss:focus-visible { outline: 2px solid var(--sideb-highlight, #d06c70); outline-offset: 2px; }
  @media (forced-colors: active) { .toast { color: CanvasText; background: Canvas; border-color: CanvasText; backdrop-filter: none; box-shadow: none; } }
</style>
