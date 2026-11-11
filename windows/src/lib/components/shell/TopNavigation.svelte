<script lang="ts">
  import { t } from '$lib/i18n';
  import type { AuthStatusDto } from '$lib/types';
  import SidebarIcon from '../sidebar/SidebarIcon.svelte';
  import AccountPopover, { type AccountShortcut } from './AccountPopover.svelte';

  type Destination = 'home' | 'explore' | 'library';
  /** Same value the sidebar receives; only home/explore/library mark a destination as selected. */
  interface Props {
    activeDestination: string;
    /** Player fullscreen: destinations/search/history/account hide and only a compact reopen control stays. */
    compact?: boolean;
    inert?: boolean;
    searchOpen?: boolean;
    canBack?: boolean;
    canForward?: boolean;
    auth: AuthStatusDto;
    onReopen: () => void;
    onHome: () => void;
    onExplore: () => void;
    onLibrary: () => void;
    onSearch: () => void;
    onBack?: () => void;
    onForward?: () => void;
    onLogin: () => void;
    onCancelLogin: () => void;
    onLogout: () => void;
    onCheckUpdates?: () => void;
    onLikes?: () => void;
    onHistory?: () => void;
    onCreatePlaylist?: () => void;
  }
  let { activeDestination, compact = false, inert = false, searchOpen = false, canBack = false, canForward = false, auth, onReopen, onHome, onExplore, onLibrary, onSearch,
    onBack, onForward, onLogin, onCancelLogin, onLogout, onCheckUpdates, onLikes, onHistory, onCreatePlaylist }: Props = $props();

  let accountOpen = $state(false);
  let accountButton = $state<HTMLButtonElement>();
  const destinations: { id: Destination; label: string; run: () => void }[] = $derived([
    { id: 'home', label: $t('sidebar.home'), run: onHome },
    { id: 'explore', label: $t('sidebar.explore'), run: onExplore },
    { id: 'library', label: $t('sidebar.library'), run: onLibrary },
  ]);
  const shortcuts: AccountShortcut[] = $derived([
    { id: 'likes', label: $t('sidebar.liked'), onSelect: () => onLikes?.() },
    { id: 'history', label: $t('sidebar.history'), onSelect: () => onHistory?.() },
    { id: 'create', label: $t('windows.ui.createPlaylist'), disabled: auth.state !== 'ready' || !onCreatePlaylist, onSelect: () => onCreatePlaylist?.() },
  ]);
  $effect(() => { if (compact || inert || searchOpen) accountOpen = false; });
  function closeAccount(restoreFocus: boolean) {
    accountOpen = false;
    if (restoreFocus) queueMicrotask(() => accountButton?.focus());
  }
</script>

<nav class="topnav" class:compact aria-label={$t('windows.ui.topNavigation')} {inert}>
  <div class="side start">
  <button type="button" class="reopen" data-topnav-reopen aria-label={$t('windows.ui.expandSidebar')} title={$t('windows.ui.expandSidebar')} aria-pressed="false" onclick={onReopen}>
    <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16"/></svg>
  </button>
  {#if !compact}
    <button type="button" class="glass search" class:away={searchOpen} data-topnav-search aria-label={$t('sidebar.search')} title={$t('windows.ui.searchSideB')} inert={searchOpen} onclick={onSearch}>
      <SidebarIcon name="search" />
    </button>
  {/if}
  </div>
  {#if !compact}
    <div class="glass destinations" class:away={searchOpen} role="group" aria-label={$t('navigation.main')} inert={searchOpen}>
      {#each destinations as destination (destination.id)}
        <button type="button" class="destination" class:selected={activeDestination === destination.id} aria-current={activeDestination === destination.id ? 'page' : undefined} aria-label={destination.label} title={destination.label} onclick={destination.run}>
          <SidebarIcon name={destination.id} />
        </button>
      {/each}
    </div>
    <div class="side end">
    <button bind:this={accountButton} type="button" class="glass account" aria-label={$t('windows.ui.openAccountOptions')} title={auth.state === 'ready' ? (auth.name ?? $t('windows.ui.yourAccount')) : $t('account.sign_in')} aria-haspopup="dialog" aria-expanded={accountOpen} aria-controls="account-popover" onclick={() => accountOpen = !accountOpen}>
      {#if auth.state === 'ready' && auth.thumbnail}<img src={auth.thumbnail} alt="" />{:else}<SidebarIcon name="profile" />{/if}
    </button>
    <div class="glass history" role="group" aria-label={$t('windows.ui.navigationHistory')}>
      <button type="button" aria-label={$t('navigation.back')} title={$t('navigation.back')} disabled={!canBack} onclick={onBack}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg></button>
      <span class="divider" aria-hidden="true"></span>
      <button type="button" aria-label={$t('navigation.forward')} title={$t('navigation.forward')} disabled={!canForward} onclick={onForward}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg></button>
    </div>
    </div>
    {#if accountOpen}
      <AccountPopover {auth} anchor={accountButton} onClose={closeAccount} {onLogout} {onLogin} {onCancelLogin} {onCheckUpdates} {shortcuts} />
    {/if}
  {/if}
</nav>

<style>
  .topnav {
    /* The strip spans the content: from its 28px inset to the window buttons, or to the playback sidebar when it is open. */
    position: fixed; z-index: 201; top: 0; left: 0; right: var(--topnav-right, 154px); height: var(--titlebar-height, 78px); box-sizing: border-box;
    /* The side groups never shrink; in a cramped strip only the destinations give way. */
    display: grid; grid-template-columns: minmax(max-content, 1fr) minmax(0, 246px) minmax(max-content, 1fr); align-items: center; column-gap: 10px;
    /* Same room above the capsules as on their left. */
    padding: var(--topnav-top, 28px) 0 8px var(--topnav-inset, 28px);
    color: #fff; font: 13px/1.3 var(--sideb-font-family); pointer-events: none;
  }
  .topnav > :global(*) { pointer-events: auto; }
  /* Search at the start, account and history at the end; the gaps stay free to drag the window. */
  .topnav > .side { display: flex; align-items: center; gap: 10px; min-width: 0; pointer-events: none; }
  .side > :global(*) { pointer-events: auto; }
  .side.end { justify-content: flex-end; }
  .topnav.compact { display: flex; right: auto; width: 40px; height: 32px; padding: 0 0 0 4px; }
  button { padding: 0; border: 0; color: inherit; background: transparent; font: inherit; cursor: pointer; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight, #d06c70); outline-offset: -3px; }
  button:disabled { opacity: .35; cursor: default; }
  svg { width: 18px; height: 18px; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
  .topnav :global(svg) { width: 18px; height: 18px; }
  .glass, .reopen {
    box-sizing: border-box; flex: none; display: flex; align-items: center; justify-content: center; height: 42px; border-radius: 21px;
    border: 1px solid var(--sideb-surface-border, rgb(255 255 255 / 8%)); color: #fff;
    background: var(--sideb-acrylic-surface, rgb(43 43 49 / 62%)); backdrop-filter: var(--sideb-acrylic-blur); -webkit-backdrop-filter: var(--sideb-acrylic-blur);
    box-shadow: 0 0 0 1px rgb(0 0 0 / 14%), 0 4px 14px rgb(0 0 0 / 22%), inset 0 1px 0 rgb(255 255 255 / 7%);
  }
  .reopen { width: 42px; }
  .compact .reopen { width: 32px; height: 32px; border: 0; border-radius: 5px; background: transparent; backdrop-filter: none; -webkit-backdrop-filter: none; box-shadow: none; color: #dedee2; }
  .compact .reopen:hover { background: rgb(255 255 255 / 10%); }
  .reopen:hover, .search:hover, .account:hover { background-color: color-mix(in srgb, var(--sideb-acrylic-surface, rgb(43 43 49 / 62%)), white 9%); }
  .compact .reopen:hover { background-color: rgb(255 255 255 / 10%); }
  .search, .account { width: 42px; padding: 0; overflow: hidden; }
  .account img { width: 32px; height: 32px; border-radius: 50%; object-fit: cover; }
  .away { visibility: hidden; }
  .destinations { width: 100%; padding: 0 2px; gap: 0; }
  .destination { flex: 1 1 0; min-width: 0; height: 36px; display: grid; place-items: center; border-radius: 18px; }
  .destination:hover { background: rgb(255 255 255 / 7%); }
  .destination.selected, .destination.selected:hover { color: var(--sideb-highlight, #d06c70); background: rgb(255 255 255 / 12%); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 10%); }
  .history { width: 76px; padding: 0 2px; }
  .history button { flex: 1 1 0; height: 36px; display: grid; place-items: center; min-width: 0; border-radius: 18px; }
  .history button:hover:not(:disabled) { background: rgb(255 255 255 / 9%); }
  .divider { flex: none; width: 1px; height: 16px; background: rgb(255 255 255 / 18%); }
  @media (prefers-reduced-transparency: reduce) {
    .glass, .reopen { background: var(--sideb-acrylic-fallback, #353538); backdrop-filter: none; -webkit-backdrop-filter: none; }
    .compact .reopen { background: transparent; }
  }
  @media (forced-colors: active) {
    .glass, .reopen { background: Canvas; color: CanvasText; border-color: CanvasText; box-shadow: none; backdrop-filter: none; }
    .destination.selected { background: Highlight; color: HighlightText; box-shadow: none; }
    .compact .reopen { border: 0; }
  }
  @media (prefers-reduced-motion: no-preference) {
    .destination, .history button, .reopen, .search, .account { transition: background-color 120ms ease; }
  }
</style>
