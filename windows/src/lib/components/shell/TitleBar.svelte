<script lang="ts">
  import { t } from '$lib/i18n';
  import { onMount } from 'svelte';
  import type { Window as TauriWindow } from '@tauri-apps/api/window';
  import type { UnlistenFn } from '@tauri-apps/api/event';

  let { onBack, onForward, canBack = false, canForward = false }:
    { onBack?: () => void; onForward?: () => void; canBack?: boolean; canForward?: boolean } = $props();

  let nativeWindow: TauriWindow | null = null;
  let isMaximized = $state(false);
  let windowError = $state<string | null>(null);

  async function resolveWindow() {
    if (nativeWindow) return nativeWindow;
    if (typeof window === 'undefined') throw new Error($t('windows.ui.windowControlsRequireTheDesktopApp'));
    const { getCurrentWindow } = await import('@tauri-apps/api/window');
    nativeWindow = getCurrentWindow();
    return nativeWindow;
  }

  async function syncMaximized() {
    const current = await resolveWindow();
    isMaximized = await current.isMaximized();
  }

  async function runWindowAction(action: (current: TauriWindow) => Promise<void>) {
    windowError = null;
    try {
      const current = await resolveWindow();
      await action(current);
      await syncMaximized();
    } catch (error) {
      windowError = error instanceof Error ? error.message : $t('windows.ui.couldnTCompleteTheWindowAction');
    }
  }

  onMount(() => {
    let active = true;
    let unlisten: UnlistenFn | undefined;
    void (async () => {
      try {
        const current = await resolveWindow();
        if (!active) return;
        await syncMaximized();
        const stop = await current.onResized(() => { void syncMaximized().catch(error => {
          windowError = error instanceof Error ? error.message : $t('windows.ui.couldnTUpdateTheWindowState');
        }); });
        if (active) unlisten = stop;
        else stop();
      } catch (error) {
        if (active) windowError = error instanceof Error ? error.message : $t('windows.ui.couldnTEnableWindowControls');
      }
    })();
    return () => { active = false; unlisten?.(); };
  });

  function toggleFromDragRegion() { void runWindowAction(current => current.toggleMaximize()); }
</script>

<header class="titlebar" aria-label={$t('windows.ui.sideBTitleBar')}>
  <div class="drag-region" data-tauri-drag-region role="button" tabindex="0" aria-label={isMaximized ? $t('windows.ui.restoreWindow') : $t('windows.ui.maximizeWindow')} title={isMaximized ? $t('windows.ui.doubleClickToRestore') : $t('windows.ui.doubleClickToMaximize')} onkeydown={event => {
    if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); toggleFromDragRegion(); }
  }}></div>

  <nav class="history-controls" aria-label={$t('windows.ui.sidebarAndNavigationControls')}>
    <button type="button" class="history-button" aria-label={$t('navigation.back')} title={$t('navigation.back')} disabled={!canBack} onclick={onBack}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg></button>
    <button type="button" class="history-button" aria-label={$t('navigation.forward')} title={$t('navigation.forward')} disabled={!canForward} onclick={onForward}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg></button>
  </nav>
  <div class="window-controls" aria-label={$t('windows.ui.windowControls')}>
    <button type="button" class="window-button" aria-label={$t('windows.ui.minimize')} title={$t('windows.ui.minimize')} onclick={() => runWindowAction(current => current.minimize())}>
      <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8h10" /></svg>
    </button>
    <button type="button" class="window-button" aria-label={isMaximized ? $t('windows.ui.restore') : $t('windows.ui.maximize')} title={isMaximized ? $t('windows.ui.restore') : $t('windows.ui.maximize')} onclick={() => runWindowAction(current => current.toggleMaximize())}>
      {#if isMaximized}<svg viewBox="0 0 16 16" aria-hidden="true"><rect x="5" y="3" width="8" height="8" rx="1" /><path d="M3 6v7h7" /></svg>
      {:else}<svg viewBox="0 0 16 16" aria-hidden="true"><rect x="3" y="3" width="10" height="10" rx="1" /></svg>{/if}
    </button>
    <button type="button" class="window-button close-button" aria-label={$t('update.close')} title={$t('update.close')} onclick={() => runWindowAction(current => current.close())}>
      <svg viewBox="0 0 16 16" aria-hidden="true"><path d="m4 4 8 8m0-8-8 8" /></svg>
    </button>
  </div>
  <span class="sr-only" role="status" aria-live="polite">{windowError ?? ''}</span>
</header>

<style>
  .titlebar {
    position: fixed;
    z-index: 200;
    inset: 0 0 auto var(--sidebar-width, 230px);
    height: var(--titlebar-height, 32px);
    display: flex;
    align-items: center;
    background: transparent;
    user-select: none;
    -webkit-user-select: none;
  }
  .window-controls { display: flex; align-items: center; height: 100%; }
  .history-button:hover:not(:disabled) { background:rgb(255 255 255 / 10%); }
  .history-button:focus-visible { outline:2px solid #d06c70; outline-offset:-3px; }
  .history-controls { display:flex; height:100%; margin-right:8px; flex:none; }
  .history-button { display:grid; place-items:center; width:32px; border:0; border-radius:5px; background:transparent; color:#dedee2; cursor:pointer; }
  .history-button:disabled { opacity:.3; cursor:default; }
  .history-button svg { width:18px; height:18px; fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
  .window-controls { width: 138px; flex: 0 0 138px; justify-content: stretch; }
  .window-button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border: 0;
    color: #dedee2;
    background: transparent;
    cursor: pointer;
  }
  .drag-region { height: 100%; flex: 1; cursor: default; }
  .drag-region:focus-visible { outline: 2px solid #d06c70; outline-offset: -3px; }
  .window-button { height: 100%; flex: 1; }
  .window-button:hover { background: rgb(255 255 255 / 10%); }
  .window-button.close-button:hover { background: #c42b1c; color: #fff; }
  .window-button svg { width: 16px; height: 16px; fill: none; stroke: currentColor; stroke-width: 1.2; stroke-linecap: round; }
  .window-button:focus-visible { outline: 2px solid #d06c70; outline-offset: -3px; }
  .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0; }
</style>
