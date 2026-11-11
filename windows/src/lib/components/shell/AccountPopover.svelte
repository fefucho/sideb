<script lang="ts" module>
  export interface AccountShortcut { id: string; label: string; disabled?: boolean; onSelect: () => void }
</script>

<script lang="ts">
  import { t } from '$lib/i18n';
  import { onMount, tick } from 'svelte';
  import type { AuthStatusDto } from '$lib/types';

  /** Signed-in account menu shared by the sidebar profile and the top navigation. The host owns the open state; this component owns Escape, outside click and resize while mounted. */
  interface Props {
    auth: AuthStatusDto;
    anchor: HTMLElement | undefined;
    onClose: (restoreFocus: boolean) => void;
    onLogout: () => void;
    onLogin?: () => void;
    onCancelLogin?: () => void;
    onCheckUpdates?: () => void;
    shortcuts?: AccountShortcut[];
    /** Changing this value repositions the menu (for example when the sidebar collapses). */
    layoutKey?: unknown;
  }
  let { auth, anchor, onClose, onLogout, onLogin, onCancelLogin, onCheckUpdates, shortcuts = [], layoutKey }: Props = $props();
  let popover = $state<HTMLDivElement>();
  let position = $state({ left: 12, top: 12 });

  function place() {
    const rect = anchor?.getBoundingClientRect();
    if (!rect || !popover) return;
    const margin = 12;
    const viewportWidth = document.documentElement.clientWidth;
    const viewportHeight = document.documentElement.clientHeight;
    const box = popover.getBoundingClientRect();
    const left = Math.max(margin, Math.min(rect.left, viewportWidth - box.width - margin));
    const above = rect.top - box.height - 8;
    const below = rect.bottom + 8;
    const top = above >= margin ? above : Math.min(below, viewportHeight - box.height - margin);
    position = { left, top: Math.max(margin, top) };
  }

  onMount(() => {
    place();
    popover?.querySelector<HTMLButtonElement>('button')?.focus();
  });
  $effect(() => { layoutKey; void tick().then(place); });

  function keydown(event: KeyboardEvent) {
    if (event.key === 'Escape') { event.preventDefault(); onClose(true); }
  }
  function click(event: MouseEvent) {
    const target = event.target;
    if (target instanceof Node && !popover?.contains(target) && !anchor?.contains(target)) onClose(false);
  }
</script>

<svelte:window onkeydown={keydown} onclick={click} onresize={place} />

<div bind:this={popover} id="account-popover" class="account-popover" style:left={`${position.left}px`} style:top={`${position.top}px`} role="dialog" aria-label={$t('menu.account')} aria-modal="false">
  <div class="popover-account">
    {#if auth.state === 'ready' && auth.thumbnail}<img class="popover-avatar" src={auth.thumbnail} alt="" />{:else}<span class="popover-avatar fallback">●</span>{/if}
    {#if auth.state === 'ready'}<span><strong>{auth.name ?? $t('windows.ui.yourAccount')}</strong><small>{auth.email || auth.handle || $t('account.active_session')}</small></span>
    {:else}<span><strong>{$t('account.guest_mode')}</strong><small>{auth.state === 'authorizing' ? $t('windows.ui.openingSignInCancel') : $t('account.sign_in')}</small></span>{/if}
  </div>
  {#if auth.state === 'ready'}<div class="account-active">✓ {$t('account.active_session')}</div>{:else}<div class="account-active account-rule"></div>{/if}
  {#each shortcuts as shortcut (shortcut.id)}
    <button class="update-check-btn shortcut-btn" type="button" disabled={shortcut.disabled} onclick={() => { onClose(false); shortcut.onSelect(); }}>{shortcut.label}</button>
  {/each}
  {#if onCheckUpdates}
    <button class="update-check-btn" type="button" onclick={() => { onClose(false); onCheckUpdates(); }}>{$t('menu.check_updates')}</button>
  {/if}
  {#if auth.state === 'ready'}<button class="signout" type="button" onclick={() => { onClose(false); onLogout(); }}>{$t('account.sign_out')}</button>
  {:else if auth.state === 'authorizing'}<button class="update-check-btn" type="button" onclick={() => { onClose(false); onCancelLogin?.(); }}>{$t('windows.ui.cancelSignIn')}</button>
  {:else}<button class="update-check-btn" type="button" onclick={() => { onClose(false); onLogin?.(); }}>{$t('account.sign_in')}</button>{/if}
</div>

<style>
  .account-popover { position: fixed; z-index: 220; box-sizing: border-box; width: min(260px, calc(100vw - 24px)); max-height: calc(100vh - 24px); overflow-y: auto; padding: 13px; border: 1px solid rgb(255 255 255 / 13%); border-radius: 12px; background: #303036; color: #fff; font: 13px/1.3 var(--sideb-font-family); box-shadow: 0 12px 30px rgb(0 0 0 / 45%); }
  .popover-account { display: flex; align-items: center; gap: 10px; padding: 2px 2px 11px; }
  .popover-account > span:last-child { display: flex; flex-direction: column; gap: 3px; min-width: 0; }
  .popover-account strong, .popover-account small { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .popover-account strong { font-size: 13px; }
  .popover-account small, .account-active { color: rgb(255 255 255 / 75%); font-size: 11px; }
  .popover-avatar { width: 42px; height: 42px; border-radius: 50%; object-fit: cover; }
  .popover-avatar.fallback { display: grid; place-items: center; background: rgb(255 255 255 / 12%); }
  .account-active { padding: 10px 2px; border-top: 1px solid rgb(255 255 255 / 10%); border-bottom: 1px solid rgb(255 255 255 / 10%); }
  .account-active.account-rule { padding: 0; border-bottom: 0; }
  .update-check-btn { width: 100%; margin-top: 8px; padding: 8px 10px; border: 0; border-radius: 7px; background: rgb(255 255 255 / 5%); color: inherit; font-size: 12px; text-align: left; cursor: pointer; transition: background 0.15s ease; }
  .update-check-btn:hover:not(:disabled) { background: rgb(255 255 255 / 12%); }
  .update-check-btn:disabled { opacity: .4; cursor: default; }
  .signout { width: 100%; margin-top: 6px; padding: 8px 10px; border: 0; border-radius: 7px; background: rgb(255 255 255 / 5%); color: inherit; text-align: left; cursor: pointer; }
  .signout:hover { background: rgb(220 70 80 / 18%); color: #ff9ba1; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight, #d06c70); outline-offset: -2px; }
</style>
