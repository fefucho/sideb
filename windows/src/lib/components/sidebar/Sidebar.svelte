<script lang="ts" module>
  export type SidebarDestination = "home" | "search" | "explore" | "album" | "likes" | "library" | "history" | "playlist" | "artist";
</script>

<script lang="ts">
  import { t , language, resolveMessage } from '$lib/i18n';
  import { tick } from "svelte";
  import SidebarIcon from "./SidebarIcon.svelte";
  import type { AuthStatusDto } from "$lib/types";
  import type { BrowseCardDto, PlaylistDetailDto } from "$lib/types";
  import { createMenuHandlers } from "$lib/menu/hooks";
  import { targetFromCard } from "$lib/menu/types";
  import { likedPlaylistTarget } from '$lib/menu/sidebar';
  const createMenu = createMenuHandlers();

  type LibraryTab = "playlists" | "albums";

  type Props = {
    activeDestination: SidebarDestination;
    onHome: () => void;
    onSearch: () => void;
    onExplore?: () => void;
    onRetryLibrary?: () => void;
    collapsed?: boolean;
    onToggleSidebar: () => void;
    onCreatePlaylist?: () => void;
    auth: AuthStatusDto;
    onLogin: () => void;
    onCancelLogin: () => void;
    onLogout: () => void;
    onLikes?: () => void;
    onLibrary?: () => void;
    onHistory?: () => void;
    playlists?: BrowseCardDto[];
    likesDetail?: PlaylistDetailDto | null;
    albums?: BrowseCardDto[];
    libraryLoading?: boolean;
    libraryError?: string | null;
    selectedCollectionId?: string | null;
    onOpenPlaylist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void;
    onCheckUpdates?: () => void;
  };

  let {
    activeDestination,
    onHome,
    onSearch,
    onExplore,
    onRetryLibrary,
    collapsed = false,
    onToggleSidebar, onCreatePlaylist,
    auth,
    onLogin,
    onCancelLogin,
    onLogout,
    onLikes,
    onLibrary,
    onHistory,
    playlists = [],
    likesDetail = null,
    albums = [],
    libraryLoading = false,
    libraryError = null,
    selectedCollectionId = null,
    onOpenPlaylist,
    onOpenAlbum,
    onCheckUpdates,
  }: Props = $props();

  let libraryTab = $state<LibraryTab>("playlists");
  let accountOpen = $state(false);
  let profileButton: HTMLButtonElement;
  let accountPopover = $state<HTMLDivElement>();
  let popoverPosition = $state({ left: 12, top: 12 });
  const currentItems = $derived(libraryTab === "playlists" ? playlists : albums);
  const likesMenu = createMenu(
    () => likedPlaylistTarget(auth.state === 'ready', $t('sidebar.liked'), playlists, likesDetail),
    () => ({ view: activeDestination === 'likes' ? 'playlist_detail' : activeDestination, currentId: activeDestination === 'likes' ? 'LM' : selectedCollectionId, playbackScope: 'source' }),
  );

  function positionAccountPopover() {
    const anchor = profileButton?.getBoundingClientRect();
    const popover = accountPopover;
    if (!anchor || !popover) return;

    const margin = 12;
    const viewportWidth = document.documentElement.clientWidth;
    const viewportHeight = document.documentElement.clientHeight;
    const width = popover.getBoundingClientRect().width;
    const height = popover.getBoundingClientRect().height;
    const left = Math.max(margin, Math.min(anchor.left, viewportWidth - width - margin));
    const above = anchor.top - height - 8;
    const below = anchor.bottom + 8;
    const top = above >= margin ? above : Math.min(below, viewportHeight - height - margin);
    popoverPosition = { left, top: Math.max(margin, top) };
  }

  async function toggleAccount() {
    if (auth.state === "ready") {
      accountOpen = !accountOpen;
      if (accountOpen) {
        await tick();
        positionAccountPopover();
        accountPopover?.querySelector<HTMLButtonElement>("button")?.focus();
      }
    } else if (auth.state === "authorizing") {
      onCancelLogin();
    } else {
      onLogin();
    }
  }

  function closeAccount(restoreFocus = false) {
    if (!accountOpen) return;
    accountOpen = false;
    if (restoreFocus) void tick().then(() => profileButton?.focus());
  }

  function handleWindowKeydown(event: KeyboardEvent) {
    if (event.key === "Escape" && accountOpen) {
      event.preventDefault();
      closeAccount(true);
    }
  }

  function handleWindowResize() {
    if (accountOpen) positionAccountPopover();
  }

  function handleWindowClick(event: MouseEvent) {
    if (accountOpen && event.target instanceof Node && !event.target.parentElement?.closest(".profile-wrap")) {
      closeAccount();
    }
  }

  $effect(() => {
    if (auth.state !== "ready") accountOpen = false;
  });

  $effect(() => {
    const open = accountOpen;
    collapsed;
    if (open) void tick().then(positionAccountPopover);
  });
</script>

<svelte:window onkeydown={handleWindowKeydown} onclick={handleWindowClick} onresize={handleWindowResize} />

<aside class:collapsed aria-label={$t('windows.ui.sideBSidebar')}>
  <div class="sidebar-drag-region" data-tauri-drag-region aria-hidden="true"></div>
  <div class="sidebar-toolbar" role="group" aria-label={$t('windows.ui.sidebarAndNavigationControls')}>
    <button type="button" class="toolbar-button" aria-label={collapsed ? $t('windows.ui.expandSidebar') : $t('windows.ui.collapseSidebar')} title={collapsed ? $t('windows.ui.expandSidebar') : $t('windows.ui.collapseSidebar')} aria-pressed={!collapsed} onclick={onToggleSidebar}>
      <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16"/></svg>
    </button>
  </div>
  <div class="scroll-region">
    <nav aria-label={$t('navigation.main')} class="primary-section">
      <button
        class:active={activeDestination === "home"}
        class="sidebar-row"
        type="button"
        aria-current={activeDestination === "home" ? "page" : undefined}
        aria-label={$t('sidebar.home')}
        title={collapsed ? $t('sidebar.home') : undefined}
        onclick={onHome}
      >
        <span class="icon"><SidebarIcon name="home" /></span>
        <span class="row-label">{$t('sidebar.home')}</span>
      </button>
      <button
        class:active={activeDestination === "search"}
        class="sidebar-row"
        type="button"
        aria-current={activeDestination === "search" ? "page" : undefined}
        aria-label={$t('sidebar.search')}
        title={collapsed ? $t('sidebar.search') : undefined}
        onclick={onSearch}
      >
        <span class="icon"><SidebarIcon name="search" /></span>
        <span class="row-label">{$t('sidebar.search')}</span>
        <kbd class="shortcut" aria-hidden="true">Ctrl K</kbd>
      </button>
      {#if onExplore}<button class="sidebar-row" class:active={activeDestination === 'explore'} type="button" aria-current={activeDestination === 'explore' ? 'page' : undefined} aria-label={$t('sidebar.explore')} title={collapsed ? $t('sidebar.explore') : undefined} onclick={onExplore}><span class="icon" aria-hidden="true"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="9"/><path d="m16 8-2.5 5.5L8 16l2.5-5.5Z"/></svg></span><span class="row-label">{$t('sidebar.explore')}</span></button>{/if}
    </nav>

    <section class="collection-section" aria-labelledby="collection-heading">
      <h2 id="collection-heading">{$t('detail.kind.collection')}</h2>
      <button class="sidebar-row" class:active={activeDestination === "likes"} type="button" aria-label={$t('sidebar.liked')} title={collapsed ? $t('sidebar.liked') : undefined} aria-current={activeDestination === "likes" ? "page" : undefined} aria-haspopup={auth.state === 'ready' ? 'menu' : undefined} onclick={() => onLikes?.()} oncontextmenu={likesMenu.onContextMenu} onkeydown={likesMenu.onKeyDown}>
        <span class="icon"><SidebarIcon name="liked" /></span>
        <span class="row-label">{$t('sidebar.liked')}</span>
      </button>
      <button class="sidebar-row" class:active={activeDestination === "library"} type="button" aria-label={$t('sidebar.library')} title={collapsed ? $t('sidebar.library') : undefined} aria-current={activeDestination === "library" ? "page" : undefined} onclick={() => onLibrary?.()}>
        <span class="icon"><SidebarIcon name="library" /></span>
        <span class="row-label">{$t('sidebar.library')}</span>
      </button>
      <button class="sidebar-row" class:active={activeDestination === "history"} type="button" aria-label={$t('sidebar.history')} title={collapsed ? $t('sidebar.history') : undefined} aria-current={activeDestination === "history" ? "page" : undefined} onclick={() => onHistory?.()}>
        <span class="icon"><SidebarIcon name="history" /></span>
        <span class="row-label">{$t('sidebar.history')}</span>
      </button>
    </section>

    <section class="library-section" aria-label={$t('windows.ui.savedMusic')}>
      <div class="library-heading"><div class="library-tabs" role="group" aria-label={$t('windows.ui.collectionType')}>
        <button
          type="button"
          class:selected={libraryTab === "playlists"}
          aria-pressed={libraryTab === "playlists"}
          onclick={() => (libraryTab = "playlists")}
        >{$t('windows.ui.playlists')}</button>
        <button
          type="button"
          class:selected={libraryTab === "albums"}
          aria-pressed={libraryTab === "albums"}
          onclick={() => (libraryTab = "albums")}
        >{$t('sidebar.albums')}</button>
      </div>{#if onCreatePlaylist}<button type="button" class="create-playlist" aria-label={$t('windows.ui.createPlaylist')} title={$t('windows.ui.createPlaylist')} disabled={auth.state !== 'ready'} onclick={onCreatePlaylist}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg></button>{/if}</div>
      {#if auth.state !== "ready"}
        <p class="guest-message">{$t('windows.ui.signInToSeeYourSavedMusic')}</p>
      {:else if libraryLoading && currentItems.length === 0}
        <p class="guest-message" role="status">{$t('windows.sidebar.loading', [libraryTab === 'playlists' ? $t('windows.ui.playlists') : $t('sidebar.albums')])}</p>
      {:else if libraryError && currentItems.length === 0}
        <p class="guest-message error" role="alert">{resolveMessage(libraryError, $language)}</p>
        {#if onRetryLibrary}<button type="button" class="toolbar-button" onclick={onRetryLibrary}>{$t('sidebar.retry')}</button>{/if}
      {:else if currentItems.length === 0}
        <p class="guest-message">{libraryTab === "playlists" ? $t('windows.ui.noPlaylistsYet') : $t('windows.ui.noSavedAlbumsYet')}</p>
      {:else}
        <div class="collection-list" aria-label={libraryTab === "playlists" ? $t('windows.ui.playlists') : $t('settings.source.libraryAlbums')}>
          {#each currentItems as item, index (`${item.id || `${item.kind}-${item.title}`}-${index}`)}
            {@const menu = createMenu(() => targetFromCard(item), () => ({ view: activeDestination, currentId: selectedCollectionId }))}
            <button class="sidebar-row item-row" class:active={selectedCollectionId === item.id} type="button" title={item.title} onclick={() => libraryTab === "playlists" ? onOpenPlaylist?.(item.id) : onOpenAlbum?.(item.id)} oncontextmenu={menu.onContextMenu} onkeydown={menu.onKeyDown}>
              {#if item.thumbnail}<img class="item-art" src={item.thumbnail} alt="" />{:else}<span class="item-art placeholder" aria-hidden="true">♪</span>{/if}
              <span class="row-label">{item.title}</span>
            </button>
          {/each}
        </div>
      {/if}
    </section>
  </div>

  <div class="profile-wrap">
    <button bind:this={profileButton} class="profile" type="button" aria-label={auth.state === "ready" ? $t('windows.ui.openAccountOptions') : auth.state === "authorizing" ? $t('windows.ui.cancelSignIn') : $t('account.sign_in')} aria-expanded={accountOpen} aria-controls="account-popover" onclick={toggleAccount}>
      {#if auth.state === "ready" && auth.thumbnail}
        <img class="profile-avatar" src={auth.thumbnail} alt="" />
      {:else}
        <span class="profile-icon"><SidebarIcon name="profile" /></span>
      {/if}
      <span class="profile-copy">
        <strong>{auth.state === "ready" ? (auth.name ?? $t('windows.ui.yourAccount')) : $t('account.guest_mode')}</strong>
        <small>{auth.state === "ready" ? (auth.email || auth.handle || $t('windows.ui.signedIn')) : auth.state === "authorizing" ? $t('windows.ui.openingSignInCancel') : auth.state === "error" ? $t('windows.ui.couldnTSignInRetry') : $t('account.sign_in')}</small>
      </span>
    </button>
    {#if auth.message}<small class="auth-error" role="alert">{resolveMessage(auth.message, $language)}</small>{/if}
    {#if auth.state !== 'ready' && onCheckUpdates}<button class="guest-update" type="button" title={$t('menu.check_updates')} aria-label={$t('menu.check_updates')} onclick={onCheckUpdates}>{collapsed ? '↻' : $t('menu.check_updates')}</button>{/if}
    {#if auth.state === "ready" && accountOpen}
      <div bind:this={accountPopover} id="account-popover" class="account-popover" style:left={`${popoverPosition.left}px`} style:top={`${popoverPosition.top}px`} role="dialog" aria-label={$t('menu.account')} aria-modal="false">
        <div class="popover-account">
          {#if auth.thumbnail}<img class="popover-avatar" src={auth.thumbnail} alt="" />{:else}<span class="popover-avatar fallback">●</span>{/if}
          <span><strong>{auth.name ?? $t('windows.ui.yourAccount')}</strong><small>{auth.email || auth.handle || $t('account.active_session')}</small></span>
        </div>
        <div class="account-active">✓ {$t('account.active_session')}</div>
        {#if onCheckUpdates}
          <button class="update-check-btn" type="button" onclick={() => { accountOpen = false; onCheckUpdates(); }}>{$t('menu.check_updates')}</button>
        {/if}
        <button class="signout" type="button" onclick={() => { accountOpen = false; onLogout(); }}>{$t('account.sign_out')}</button>
      </div>
    {/if}
  </div>
</aside>

<style>
  .guest-update { display: block; max-width: 100%; margin: 4px auto; border: 0; padding: 6px; border-radius: 6px; background: transparent; color: #ffffff99; font: inherit; font-size: 11px; cursor: pointer; } .guest-update:hover { color: white; background: #ffffff0d; } .guest-update:focus-visible { outline: 2px solid var(--sideb-highlight); }
  aside {
    --sidebar-accent: var(--sideb-accent, #a33d45);
    --sidebar-surface: var(--sideb-sidebar, #24242a);
    position: relative;
    display: flex;
    flex-direction: column;
    width: 230px;
    min-width: 230px;
    height: 100%;
    min-height: 0;
    box-sizing: border-box;
    padding-top: 0;
    color: #f3f1f2;
    background: var(--sidebar-surface);
    box-shadow: inset -1px 0 0 rgb(255 255 255 / 8%);
    font: 13px/1.3 system-ui, "Segoe UI", sans-serif;
  }

  .scroll-region {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overflow-x: hidden;
    padding: 0 10px 16px;
    box-sizing: border-box;
    scrollbar-width: thin;
  }

  .primary-section,
  .collection-section {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .primary-section {
    padding-bottom: 12px;
    border-bottom: 1px solid rgb(255 255 255 / 9%);
  }

  .collection-section,
  .library-section {
    margin-top: 12px;
  }

  h2 {
    margin: 0 4px 4px;
    color: rgb(255 255 255 / 47%);
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.08em;
  }

  .sidebar-row {
    display: flex;
    align-items: center;
    gap: 11px;
    min-height: 40px;
    width: 100%;
    padding: 6px 10px;
    box-sizing: border-box;
    border: 1px solid transparent;
    border-radius: 8px;
    background: transparent;
    color: inherit;
    text-align: left;
    font: inherit;
    white-space: nowrap;
  }

  button.sidebar-row {
    cursor: pointer;
  }

  button.sidebar-row:hover {
    background: rgb(255 255 255 / 6%);
  }

  button.sidebar-row:focus-visible,
  .library-tabs button:focus-visible {
    outline: 2px solid var(--sideb-accent-highlight, #d06c70);
    outline-offset: 2px;
  }

  .sidebar-row.active,
  button.sidebar-row.active:hover {
    background: rgb(163 61 69 / 55%);
    border-color: rgb(163 61 69 / 65%);
    font-weight: 600;
  }

  .icon {
    display: flex;
    flex: 0 0 20px;
    align-items: center;
    justify-content: center;
  }

  .row-label {
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .shortcut {
    margin-left: auto;
    padding: 2px 5px;
    border-radius: 4px;
    background: rgb(255 255 255 / 6%);
    color: rgb(255 255 255 / 48%);
    font: 600 10px system-ui, "Segoe UI", sans-serif;
  }

  .library-tabs {
    display: flex;
    gap: 2px;
    width: fit-content;
    max-width: 100%;
    padding: 2px;
    border-radius: 7px;
    background: rgb(255 255 255 / 6%);
  }
  .sidebar-drag-region { position:absolute; inset:0 0 auto; height:var(--titlebar-height,32px); }
  .sidebar-toolbar { position:relative; display:flex; flex:none; align-items:center; gap:4px; padding:10px; pointer-events:none; }
  .toolbar-button { display:grid; flex:none; place-items:center; width:40px; height:40px; padding:0; border:0; border-radius:8px; background:transparent; color:inherit; cursor:pointer; pointer-events:auto; }
  .toolbar-button:hover:not(:disabled) { background:var(--sideb-surface-hover); }
  .toolbar-button:disabled { color:rgb(255 255 255 / 28%); cursor:default; }
  .toolbar-button:focus-visible,.create-playlist:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:-2px; }
  .toolbar-button svg,.create-playlist svg { width:18px; height:18px; fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
  .library-heading { display:flex; align-items:center; justify-content:space-between; gap:8px; }
  .create-playlist { display:grid; flex:none; place-items:center; width:28px; height:28px; padding:0; border:0; border-radius:6px; color:inherit; background:transparent; cursor:pointer; }
  .create-playlist:hover:not(:disabled) { background:var(--sideb-surface-hover); }
  .create-playlist:disabled { opacity:.35; cursor:default; }

  .library-tabs button {
    border: 0;
    border-radius: 5px;
    padding: 5px 8px;
    background: transparent;
    color: rgb(255 255 255 / 60%);
    font: 500 11px system-ui, "Segoe UI", sans-serif;
    cursor: pointer;
  }

  .library-tabs button.selected {
    background: rgb(255 255 255 / 12%);
    color: #f3f1f2;
    font-weight: 600;
  }

  .guest-message {
    margin: 8px 4px 0;
    color: rgb(255 255 255 / 48%);
    font-size: 11px;
    line-height: 1.4;
  }
  .guest-message.error { color: #ef9a9e; }
  .collection-list { display: flex; flex-direction: column; gap: 2px; margin-top: 5px; }
  .item-row { min-height: 36px; cursor: pointer; }
  .item-art { flex: 0 0 24px; width: 24px; height: 24px; border-radius: 4px; object-fit: cover; }
  .item-art.placeholder { display: grid; place-items: center; background: rgb(255 255 255 / 8%); color: #bbb; }

  .profile-wrap { position: relative; flex: 0 0 auto; margin: 0 12px; padding: 8px 0; border-top: 1px solid rgb(255 255 255 / 10%); }
  .profile {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 44px;
    width: 100%;
    padding: 4px 2px;
    box-sizing: border-box;
    border: 0;
    border-radius: 6px;
    background: transparent;
    color: inherit;
    text-align: left;
    cursor: pointer;
  }
  .profile:hover { background: rgb(255 255 255 / 6%); }
  .profile-avatar { width: 32px; height: 32px; flex: 0 0 32px; border-radius: 50%; object-fit: cover; }

  .profile-icon {
    display: flex;
    color: rgb(255 255 255 / 65%);
  }

  .profile-copy {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .auth-error { color: #ef9a9e !important; }

  .account-popover { position: fixed; z-index: 220; box-sizing: border-box; width: min(260px, calc(100vw - 24px)); max-height: calc(100vh - 24px); overflow-y: auto; padding: 13px; border: 1px solid rgb(255 255 255 / 13%); border-radius: 12px; background: #303036; box-shadow: 0 12px 30px rgb(0 0 0 / 45%); }
  .popover-account { display: flex; align-items: center; gap: 10px; padding: 2px 2px 11px; }
  .popover-account > span:last-child { display: flex; flex-direction: column; gap: 3px; min-width: 0; }
  .popover-account strong, .popover-account small { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .popover-account strong { font-size: 13px; }
  .popover-account small, .account-active { color: rgb(255 255 255 / 60%); font-size: 11px; }
  .popover-avatar { width: 42px; height: 42px; border-radius: 50%; object-fit: cover; }
  .popover-avatar.fallback { display: grid; place-items: center; background: rgb(255 255 255 / 12%); }
  .account-active { padding: 10px 2px; border-top: 1px solid rgb(255 255 255 / 10%); border-bottom: 1px solid rgb(255 255 255 / 10%); }
  .update-check-btn { width: 100%; margin-top: 8px; padding: 8px 10px; border: 0; border-radius: 7px; background: rgb(255 255 255 / 5%); color: inherit; font-size: 12px; text-align: left; cursor: pointer; transition: background 0.15s ease; }
  .update-check-btn:hover { background: rgb(255 255 255 / 12%); }
  .signout { width: 100%; margin-top: 6px; padding: 8px 10px; border: 0; border-radius: 7px; background: rgb(255 255 255 / 5%); color: inherit; text-align: left; cursor: pointer; }
  .signout:hover { background: rgb(220 70 80 / 18%); color: #ff9ba1; }

  .profile-copy strong {
    font-size: 13px;
    font-weight: 500;
  }

  .profile-copy small {
    color: rgb(255 255 255 / 48%);
    font-size: 11px;
  }

  aside.collapsed {
    width: 60px;
    min-width: 60px;
  }

  .collapsed .scroll-region {
    padding-inline: 10px;
  }

  .collapsed h2,
  .collapsed .row-label,
  .collapsed .shortcut,
  .collapsed .library-section,
  .collapsed .profile-copy {
    display: none;
  }

  .collapsed .sidebar-row {
    justify-content: center;
    width:40px;
    height:40px;
    padding:0;
  }
  .collapsed .sidebar-toolbar { flex-direction:column; }
  .collapsed .primary-section { gap:4px; padding-bottom:10px; }
  .collapsed .collection-section { gap:4px; margin-top:10px; }

  .collapsed .profile-wrap {
    justify-content: center;
    margin-inline: 10px;
    padding-inline: 0;
  }
  .collapsed .profile { justify-content:center; width:40px; height:40px; min-height:40px; padding:0; }

  @media (prefers-reduced-motion: no-preference) {
    button.sidebar-row,
    .library-tabs button {
      transition: background-color 120ms ease;
    }
  }
</style>
