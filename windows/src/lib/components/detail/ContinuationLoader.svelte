<script lang="ts">
  import { t } from '$lib/i18n';
  import { onMount } from 'svelte';
  import { ContinuationGate } from '$lib/library/continuation';

  interface Props {
    context: string; cursor: string | null; loading: boolean; disabled?: boolean;
    error: string | null; onLoadMore: () => void;
  }
  let { context, cursor, loading, disabled = false, error, onLoadMore }: Props = $props();
  let marker: HTMLDivElement;
  let nearBottom = $state(false);
  const gate = new ContinuationGate();

  onMount(() => {
    // Match the native list's threshold of approximately 15 regular rows.
    const observer = new IntersectionObserver(entries => {
      nearBottom = entries.some(entry => entry.isIntersecting);
    }, { root: marker.closest('.content-column'), rootMargin: '780px 0px', threshold: 0 });
    observer.observe(marker);
    return () => observer.disconnect();
  });

  $effect(() => {
    if (disabled) { gate.reset(); return; }
    if (gate.claim(context, cursor, nearBottom, loading, error)) onLoadMore();
  });
</script>

<div class="continuation" bind:this={marker}>
  {#if cursor && loading}<span class="spinner" aria-hidden="true"></span><span role="status">{$t('windows.ui.loadingSongs')}</span>
  {:else if cursor}<button type="button" disabled={disabled} onclick={onLoadMore}>{$t(error ? 'windows.ui.retryLoadingMoreSongs' : 'windows.ui.loadMoreSongs')}</button>{/if}
</div>

<style>
  .continuation { display:flex; min-height:1px; align-items:center; justify-content:center; gap:8px; color:#aaaab1; font-size:12px; }
  .continuation:has(span), .continuation:has(button) { padding:18px 20px; }
  .spinner { width:16px; height:16px; border:2px solid #ffffff30; border-top-color:var(--sideb-highlight); border-radius:50%; animation:spin .8s linear infinite; }
  button { padding:8px 16px; border:1px solid var(--sideb-surface-border); border-radius:999px; color:inherit; background:var(--sideb-surface); font:inherit; cursor:pointer; }
  button:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:3px; }
  button:disabled { opacity:.55; cursor:wait; }
  @keyframes spin { to { transform:rotate(360deg); } }
  @media (prefers-reduced-motion:reduce) { .spinner { animation:none; } }
</style>
