<script lang="ts">
  import { onMount } from 'svelte';
  import type { Window as TauriWindow } from '@tauri-apps/api/window';
  import type { UnlistenFn } from '@tauri-apps/api/event';

  interface Props {
    onBack: () => void;
    onForward: () => void;
    onToggleSidebar: () => void;
    canBack: boolean;
    canForward: boolean;
    sidebarCollapsed: boolean;
  }

  let { onBack, onForward, onToggleSidebar, canBack, canForward, sidebarCollapsed }: Props = $props();
  let nativeWindow: TauriWindow | null = null;
  let isMaximized = $state(false);
  let windowError = $state<string | null>(null);

  async function resolveWindow() {
    if (nativeWindow) return nativeWindow;
    if (typeof window === 'undefined') throw new Error('Los controles de ventana requieren la aplicación de escritorio.');
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
      windowError = error instanceof Error ? error.message : 'No se pudo completar el control de ventana.';
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
          windowError = error instanceof Error ? error.message : 'No se pudo actualizar el estado de la ventana.';
        }); });
        if (active) unlisten = stop;
        else stop();
      } catch (error) {
        if (active) windowError = error instanceof Error ? error.message : 'No se pudieron activar los controles de ventana.';
      }
    })();
    return () => { active = false; unlisten?.(); };
  });

  function toggleFromDragRegion() { void runWindowAction(current => current.toggleMaximize()); }
</script>

<header class="titlebar" aria-label="Barra de título de Side B">
  <div class="sidebar-slot">
    <button type="button" class="titlebar-button sidebar-button" aria-label={sidebarCollapsed ? 'Expandir barra lateral' : 'Contraer barra lateral'} title={sidebarCollapsed ? 'Expandir barra lateral' : 'Contraer barra lateral'} aria-pressed={!sidebarCollapsed} onclick={onToggleSidebar}>
      <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2" /><path d="M9 4v16" /></svg>
    </button>
  </div>
  <div class="navigation-controls">
    <button type="button" class="titlebar-button" aria-label="Atrás" title="Atrás" disabled={!canBack} onclick={onBack}>
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 18 9 12l6-6" /></svg>
    </button>
    <button type="button" class="titlebar-button" aria-label="Adelante" title="Adelante" disabled={!canForward} onclick={onForward}>
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 18 6-6-6-6" /></svg>
    </button>
  </div>

  <div class="drag-region" data-tauri-drag-region role="button" tabindex="0" aria-label={isMaximized ? 'Restaurar ventana' : 'Maximizar ventana'} title={isMaximized ? 'Doble clic para restaurar' : 'Doble clic para maximizar'} onkeydown={event => {
    if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); toggleFromDragRegion(); }
  }}></div>

  <div class="window-controls" aria-label="Controles de ventana">
    <button type="button" class="window-button" aria-label="Minimizar" title="Minimizar" onclick={() => runWindowAction(current => current.minimize())}>
      <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8h10" /></svg>
    </button>
    <button type="button" class="window-button" aria-label={isMaximized ? 'Restaurar' : 'Maximizar'} title={isMaximized ? 'Restaurar' : 'Maximizar'} onclick={() => runWindowAction(current => current.toggleMaximize())}>
      {#if isMaximized}<svg viewBox="0 0 16 16" aria-hidden="true"><rect x="5" y="3" width="8" height="8" rx="1" /><path d="M3 6v7h7" /></svg>
      {:else}<svg viewBox="0 0 16 16" aria-hidden="true"><rect x="3" y="3" width="10" height="10" rx="1" /></svg>{/if}
    </button>
    <button type="button" class="window-button close-button" aria-label="Cerrar" title="Cerrar" onclick={() => runWindowAction(current => current.close())}>
      <svg viewBox="0 0 16 16" aria-hidden="true"><path d="m4 4 8 8m0-8-8 8" /></svg>
    </button>
  </div>
  <span class="sr-only" role="status" aria-live="polite">{windowError ?? ''}</span>
</header>

<style>
  .titlebar {
    position: fixed;
    z-index: 200;
    inset: 0 0 auto;
    height: 40px;
    display: flex;
    align-items: center;
    background: transparent;
    user-select: none;
    -webkit-user-select: none;
  }
  .sidebar-slot, .navigation-controls, .window-controls { display: flex; align-items: center; height: 100%; }
  .sidebar-slot { flex: 0 0 var(--sidebar-width, 230px); width: var(--sidebar-width, 230px); justify-content: center; }
  .navigation-controls { gap: 2px; padding-left: 8px; }
  .window-controls { width: 138px; flex: 0 0 138px; justify-content: stretch; }
  .titlebar-button, .window-button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border: 0;
    color: #dedee2;
    background: transparent;
    cursor: pointer;
  }
  .titlebar-button {
    width: 32px;
    height: 30px;
    border-radius: 6px;
  }
  .titlebar-button:hover:not(:disabled) { background: rgb(255 255 255 / 9%); }
  .titlebar-button:disabled { color: #68686f; cursor: default; }
  .titlebar-button svg { width: 18px; height: 18px; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
  .sidebar-button { flex: 0 0 32px; }
  .drag-region { height: 100%; flex: 1; cursor: default; }
  .drag-region:focus-visible { outline: 2px solid #d06c70; outline-offset: -3px; }
  .window-button { height: 100%; flex: 1; }
  .window-button:hover { background: rgb(255 255 255 / 10%); }
  .window-button.close-button:hover { background: #c42b1c; color: #fff; }
  .window-button svg { width: 16px; height: 16px; fill: none; stroke: currentColor; stroke-width: 1.2; stroke-linecap: round; }
  .titlebar-button:focus-visible, .window-button:focus-visible { outline: 2px solid #d06c70; outline-offset: -3px; }
  .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0; }
</style>
