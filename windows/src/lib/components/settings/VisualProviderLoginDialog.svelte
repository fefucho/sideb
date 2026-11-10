<script lang="ts">
  import { onMount } from 'svelte';
  import { t } from '$lib/i18n';
  import type { VisualProviderLoginState } from '$lib/visualProvider';
  import ControlButton from '../common/ControlButton.svelte';

  interface Props { providerName: string; progress: VisualProviderLoginState; onClose: () => void }
  let { providerName, progress, onClose }: Props = $props();
  const id = $props.id();
  let closeButton = $state<HTMLButtonElement>();
  // The provider's own sign-in page lives in a separate window; this dialog only reports progress.
  onMount(() => closeButton?.focus());
  function keydown(event: KeyboardEvent) {
    if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); onClose(); }
    // A single control: keep focus inside the modal.
    else if (event.key === 'Tab') { event.preventDefault(); closeButton?.focus(); }
  }
</script>

<div class="scrim" role="presentation">
  <div class="dialog" role="dialog" aria-modal="true" aria-labelledby={`${id}-title`} aria-describedby={`${id}-body`} tabindex="-1" onkeydown={keydown}>
    <div class="head">
      <div class="titles">
        <h3 id={`${id}-title`}>{$t('visualProvider.loginSheetTitle', [providerName])}</h3>
        <p>{$t('windows.visualProvider.loginHint')}</p>
      </div>
      <ControlButton size="utility" bind:element={closeButton} onclick={onClose}>{$t('visualProvider.close')}</ControlButton>
    </div>
    <div class="body" id={`${id}-body`} role="status" aria-live="polite">
      {#if progress === 'connected'}
        <svg class="done" viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.5" /><path d="m5.2 8.2 2 2 3.6-4" /></svg>
        <span class="ok">{$t('visualProvider.accountConnected')}</span>
      {:else if progress === 'failed'}
        <span class="error">{$t('windows.visualProvider.loginFailed')}</span>
      {:else if progress === 'extracting'}
        <span class="spinner" aria-hidden="true"></span><span>{$t('visualProvider.authenticating')}</span>
      {:else}
        <span class="spinner" aria-hidden="true"></span><span>{$t('windows.visualProvider.loginWaiting')}</span>
      {/if}
    </div>
  </div>
</div>

<style>
  .scrim { position:fixed; z-index:130; inset:0; display:grid; place-items:center; padding:16px; background:rgb(0 0 0 / 46%); }
  .dialog { box-sizing:border-box; width:min(420px,100%); display:flex; flex-direction:column; gap:14px; padding:16px; border-radius:14px; color:var(--control-foreground,#f3f3f6);
    background:var(--sideb-acrylic-surface,#26262c); border:1px solid var(--sideb-surface-border,rgb(255 255 255 / 12%)); box-shadow:0 12px 24px #0006, 0 16px 50px #0007; }
  .dialog:focus { outline:none; }
  .head { display:flex; align-items:flex-start; justify-content:space-between; gap:12px; }
  .titles { display:flex; flex-direction:column; gap:4px; min-width:0; }
  h3 { margin:0; font-size:14px; font-weight:600; line-height:19px; }
  p { margin:0; font-size:12px; line-height:17px; color:var(--control-muted,#c3c3cb); }
  .body { display:flex; align-items:center; gap:8px; min-height:22px; font-size:12.5px; }
  .ok { color:#7fe3a2; font-weight:500; }
  .error { color:#ffb9c0; }
  .done { width:16px; height:16px; fill:none; stroke:#7fe3a2; stroke-width:1.5; stroke-linecap:round; stroke-linejoin:round; }
  .spinner { width:14px; height:14px; border-radius:50%; border:2px solid rgb(255 255 255 / 22%); border-top-color:var(--sideb-highlight,#d06c70); animation:spin 900ms linear infinite; }
  @keyframes spin { to { transform:rotate(360deg); } }
  @media (prefers-reduced-motion:reduce) { .spinner { animation:none; border-top-color:rgb(255 255 255 / 60%); } }
</style>
