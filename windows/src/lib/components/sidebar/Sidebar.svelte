<script lang="ts" module>
  export type SidebarDestination = "home" | "search" | "explore" | "album" | "likes" | "library" | "history" | "playlist" | "artist";
</script>

<script lang="ts">
  import { t , language, resolveMessage } from '$lib/i18n';
  import { tick } from "svelte";
  import { appearance } from '$lib/appearance/preferences';
  import { fallbackArtworkUrl } from '$lib/images/artwork';
  import { canonicalId } from '$lib/home/settings';
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
  <div class="sidebar-content">
    <nav aria-label={$t('navigation.main')} class="primary-section">
      <button class="sidebar-row" class:active={activeDestination === 'home'} type="button" aria-current={activeDestination === 'home' ? 'page' : undefined} aria-label={$t('sidebar.home')} title={collapsed ? $t('sidebar.home') : undefined} onclick={onHome}>
        <span class="icon"><SidebarIcon name="home" /></span><span class="row-label">{$t('sidebar.home')}</span>
      </button>
      <button class="sidebar-row" class:active={activeDestination === 'library'} type="button" aria-current={activeDestination === 'library' ? 'page' : undefined} aria-label={$t('sidebar.library')} title={collapsed ? $t('sidebar.library') : undefined} onclick={() => onLibrary?.()}>
        <span class="icon"><SidebarIcon name="library" /></span><span class="row-label">{$t('sidebar.library')}</span>
      </button>
      {#if onExplore}<button class="sidebar-row" class:active={activeDestination === 'explore'} type="button" aria-current={activeDestination === 'explore' ? 'page' : undefined} aria-label={$t('sidebar.explore')} title={collapsed ? $t('sidebar.explore') : undefined} onclick={onExplore}>
        <span class="icon"><SidebarIcon name="explore" /></span><span class="row-label">{$t('sidebar.explore')}</span>
      </button>{/if}
      <button class="sidebar-row" class:active={activeDestination === 'search'} type="button" aria-current={activeDestination === 'search' ? 'page' : undefined} aria-label={$t('sidebar.search')} title={collapsed ? $t('sidebar.search') : undefined} onclick={onSearch}>
        <span class="icon"><SidebarIcon name="search" /></span><span class="row-label">{$t('sidebar.search')}</span><kbd class="shortcut" aria-hidden="true">Ctrl K</kbd>
      </button>
    </nav>

    <section class="collection-section" aria-label={$t('sidebar.collection')}>
      <button class="sidebar-row" class:active={activeDestination === 'likes'} type="button" aria-label={$t('sidebar.liked')} title={collapsed ? $t('sidebar.liked') : undefined} aria-current={activeDestination === 'likes' ? 'page' : undefined} aria-haspopup={auth.state === 'ready' ? 'menu' : undefined} onclick={() => onLikes?.()} oncontextmenu={likesMenu.onContextMenu} onkeydown={likesMenu.onKeyDown}>
        <span class="icon"><SidebarIcon name="liked" /></span><span class="row-label">{$t('sidebar.liked')}</span>
      </button>
      <button class="sidebar-row" class:active={activeDestination === 'history'} type="button" aria-label={$t('sidebar.history')} title={collapsed ? $t('sidebar.history') : undefined} aria-current={activeDestination === 'history' ? 'page' : undefined} onclick={() => onHistory?.()}>
        <span class="icon"><SidebarIcon name="history" /></span><span class="row-label">{$t('sidebar.history')}</span>
      </button>
    </section>

    <section class="library-section" aria-labelledby="sidebar-library-heading">
      <div class="library-heading">
        <h2 id="sidebar-library-heading">{$t('sidebar.your_collection')}</h2>
        <div class="library-actions">
          <button type="button" class="collection-action layout-toggle" aria-label={$t($appearance.sidebarLayout === 'list' ? 'sidebar.layout.show_grid' : 'sidebar.layout.show_list')}
            title={$t($appearance.sidebarLayout === 'list' ? 'sidebar.layout.show_grid' : 'sidebar.layout.show_list')} onclick={() => appearance.toggleSidebarLayout()}>
            <svg viewBox="0 0 24 24" aria-hidden="true">{#if $appearance.sidebarLayout === 'list'}<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>{:else}<path d="M8 5h13M8 12h13M8 19h13"/><circle cx="3" cy="5" r=".7"/><circle cx="3" cy="12" r=".7"/><circle cx="3" cy="19" r=".7"/>{/if}</svg>
          </button>
          {#if onCreatePlaylist}<button type="button" class="collection-action create-playlist" aria-label={$t('windows.ui.createPlaylist')} title={$t('windows.ui.createPlaylist')} disabled={auth.state !== 'ready'} onclick={onCreatePlaylist}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg></button>{/if}
        </div>
      </div>
      <div class="library-tabs" role="group" aria-label={$t('windows.ui.collectionType')}>
        <button type="button" class:selected={libraryTab === 'playlists'} aria-pressed={libraryTab === 'playlists'} onclick={() => libraryTab = 'playlists'}>{$t('windows.ui.playlists')}</button>
        <button type="button" class:selected={libraryTab === 'albums'} aria-pressed={libraryTab === 'albums'} onclick={() => libraryTab = 'albums'}>{$t('sidebar.albums')}</button>
      </div>
      <div class="scroll-region">
        {#if auth.state !== 'ready'}
          <p class="guest-message">{$t('windows.ui.signInToSeeYourSavedMusic')}</p>
        {:else if libraryLoading && currentItems.length === 0}
          <p class="guest-message" role="status">{$t('windows.sidebar.loading', [libraryTab === 'playlists' ? $t('windows.ui.playlists') : $t('sidebar.albums')])}</p>
        {:else if libraryError && currentItems.length === 0}
          <p class="guest-message error" role="alert">{resolveMessage(libraryError, $language)}</p>
          {#if onRetryLibrary}<button type="button" class="retry-library" onclick={onRetryLibrary}>{$t('sidebar.retry')}</button>{/if}
        {:else if currentItems.length === 0}
          <p class="guest-message">{libraryTab === 'playlists' ? $t('windows.ui.noPlaylistsYet') : $t('windows.ui.noSavedAlbumsYet')}</p>
        {:else}
          <div class="collection-list" class:grid={$appearance.sidebarLayout === 'grid'} aria-label={libraryTab === 'playlists' ? $t('windows.ui.playlists') : $t('settings.source.libraryAlbums')}>
            {#each currentItems as item, index (`${item.id || `${item.kind}-${item.title}`}-${index}`)}
              {@const menu = createMenu(() => targetFromCard(item), () => ({ view: activeDestination, currentId: selectedCollectionId }))}
              {@const selected = selectedCollectionId !== null && canonicalId(libraryTab === 'playlists' ? 'playlist' : 'album', selectedCollectionId) === canonicalId(libraryTab === 'playlists' ? 'playlist' : 'album', item.id) && (libraryTab === 'playlists' ? activeDestination === 'playlist' || activeDestination === 'likes' : activeDestination === 'album')}
              <button class="sidebar-row item-row" class:active={selected} type="button" aria-current={selected ? 'page' : undefined} title={[item.title,item.subtitle].filter(Boolean).join(' — ')} onclick={() => libraryTab === 'playlists' ? onOpenPlaylist?.(item.id) : onOpenAlbum?.(item.id)} oncontextmenu={menu.onContextMenu} onkeydown={menu.onKeyDown}>
                {#if item.thumbnail}<img class="item-art" src={fallbackArtworkUrl(item.thumbnail, $appearance.sidebarLayout === 'grid' ? 256 : 96) ?? item.thumbnail} loading="lazy" decoding="async" alt="" />{:else}<span class="item-art placeholder" aria-hidden="true">♪</span>{/if}
                <span class="item-copy"><span class="row-label">{item.title}</span>{#if item.subtitle}<small>{item.subtitle}</small>{/if}</span>
              </button>
            {/each}
          </div>
        {/if}
      </div>
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
  aside {
    --sidebar-surface: var(--sideb-sidebar, #24242a);
    position: relative; display: flex; flex-direction: column;
    width: var(--sidebar-width, 253px); min-width: var(--sidebar-width, 253px); height: 100%; min-height: 0;
    box-sizing: border-box; color: #fff; background: var(--sidebar-surface);
    box-shadow: inset -1px 0 0 rgb(255 255 255 / 8%);
    font: 13px/1.3 var(--sideb-font-family);
  }
  .sidebar-drag-region { position:absolute; inset:0 0 auto; height:var(--titlebar-height,32px); }
  .sidebar-toolbar { position:relative; display:flex; flex:none; align-items:center; padding:10px; pointer-events:none; }
  .toolbar-button { display:grid; flex:none; place-items:center; width:40px; height:40px; padding:0; border:0; border-radius:8px; background:transparent; color:inherit; cursor:pointer; pointer-events:auto; }
  .toolbar-button svg { width:18px; height:18px; fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
  .sidebar-content { flex:1; min-height:0; display:flex; flex-direction:column; padding:0 12px 8px; }
  .primary-section { display:flex; flex:none; flex-direction:column; gap:2px; padding-bottom:10px; }
  .sidebar-row { display:flex; align-items:center; gap:12px; min-height:38px; width:100%; padding:7px 10px; box-sizing:border-box; border:1px solid transparent; border-radius:8px; background:transparent; color:#fff; text-align:left; font:inherit; white-space:nowrap; cursor:pointer; }
  .primary-section .sidebar-row { font-size:14px; font-weight:500; }
  button.sidebar-row:hover { background:rgb(255 255 255 / 7%); }
  .sidebar-row.active, button.sidebar-row.active:hover { color:var(--sideb-highlight, #d06c70); background:rgb(255 255 255 / 10%); border-color:rgb(255 255 255 / 10%); font-weight:600; }
  button:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:-2px; }
  .icon { display:flex; flex:0 0 20px; align-items:center; justify-content:center; }
  .icon :global(svg) { width:18px; height:18px; }
  .row-label { overflow:hidden; text-overflow:ellipsis; }
  .shortcut { margin-left:auto; padding:2px 5px; border-radius:4px; background:rgb(255 255 255 / 8%); color:rgb(255 255 255 / 80%); font:600 10px var(--sideb-font-family); }
  .collection-section { display:flex; flex:none; gap:3px; padding:8px 0; border-block:1px solid rgb(255 255 255 / 10%); }
  .collection-section .sidebar-row { flex:1; min-width:0; min-height:32px; padding:5px 3px; justify-content:center; gap:6px; font-size:12px; }
  .collection-section .icon { flex-basis:15px; }
  .collection-section .icon :global(svg) { width:15px; height:15px; }
  .library-section { display:flex; flex:1; flex-direction:column; min-height:0; margin-top:12px; }
  .library-heading { display:flex; flex:none; align-items:center; justify-content:space-between; gap:6px; padding-inline:8px; }
  h2 { margin:0; min-width:0; color:#fff; font-size:13px; font-weight:600; }
  .library-actions { display:flex; flex:none; gap:4px; }
  .collection-action { display:grid; flex:none; place-items:center; width:28px; height:28px; padding:0; border:0; border-radius:6px; color:#fff; background:transparent; cursor:pointer; }
  .collection-action svg { width:16px; height:16px; fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
  .collection-action:disabled { opacity:.35; cursor:default; }
  .toolbar-button:hover, .collection-action:hover:not(:disabled) { background:var(--sideb-surface-hover, #ffffff14); }
  .library-tabs { display:flex; flex:none; gap:2px; padding:8px 8px 6px; }
  .library-tabs button { border:0; border-radius:5px; padding:5px 9px; background:transparent; color:#fff; font:500 12px var(--sideb-font-family); cursor:pointer; }
  .library-tabs button.selected { background:rgb(255 255 255 / 12%); color:var(--sideb-highlight, #d06c70); font-weight:600; }
  .scroll-region { flex:1; min-height:0; overflow-y:auto; overflow-x:hidden; padding:3px 0 10px; scrollbar-width:thin; scrollbar-color:#ffffff40 transparent; }
  .guest-message { margin:8px; color:rgb(255 255 255 / 80%); font-size:12px; line-height:1.4; }
  .guest-message.error { color:#ef9a9e; }
  .retry-library { padding:7px 9px; color:#fff; background:transparent; border:0; border-radius:6px; cursor:pointer; }
  .collection-list { display:flex; flex-direction:column; gap:2px; }
  .item-row { min-height:48px; padding:6px 8px; gap:10px; }
  .item-art { flex:0 0 34px; width:34px; height:34px; border-radius:4px; object-fit:cover; border:1px solid #ffffff26; box-sizing:border-box; }
  .item-art.placeholder { display:grid; place-items:center; background:#ffffff1a; color:#ffffffcc; font-size:18px; }
  .item-copy { display:flex; flex:1; flex-direction:column; gap:3px; min-width:0; }
  .item-copy > .row-label { font-size:13px; font-weight:500; }
  .item-copy small { overflow:hidden; text-overflow:ellipsis; color:#ffffffbf; font-size:11px; }
  .collection-list.grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:16px 12px; padding:3px 8px; }
  .grid .item-row { flex-direction:column; align-items:stretch; gap:8px; padding:0; border:0; min-width:0; }
  .grid .item-art { flex:none; width:100%; height:auto; aspect-ratio:1; border-radius:6px; }
  .grid .item-copy > .row-label { font-size:12px; }
  .grid .item-copy small { font-size:10.5px; }
  .grid .item-row.active { background:transparent; }
  .grid .item-row.active .item-art { border:2px solid var(--sideb-highlight, #d06c70); }
  .guest-update { display:block; max-width:100%; margin:4px auto; border:0; padding:6px; border-radius:6px; background:transparent; color:#ffffffbf; font:inherit; font-size:11px; cursor:pointer; }
  .guest-update:hover { color:white; background:#ffffff0d; }
  .guest-update:focus-visible { outline:2px solid var(--sideb-highlight); }

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
    color: rgb(255 255 255 / 80%);
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
  .popover-account small, .account-active { color: rgb(255 255 255 / 75%); font-size: 11px; }
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
    color: rgb(255 255 255 / 75%);
    font-size: 11px;
  }

  aside.collapsed {
    width: 60px;
    min-width: 60px;
  }

  .collapsed .sidebar-content { padding-inline:10px; }
  .collapsed h2, .collapsed .row-label, .collapsed .shortcut, .collapsed .library-section, .collapsed .profile-copy { display:none; }
  .collapsed .sidebar-row { justify-content:center; width:40px; height:40px; padding:0; flex:none; }
  .collapsed .sidebar-toolbar { flex-direction:column; }
  .collapsed .primary-section { gap:4px; padding-bottom:10px; }
  .collapsed .collection-section { flex-direction:column; gap:4px; padding-block:10px; }
  .collapsed .collection-section .icon { flex-basis:20px; }
  .collapsed .collection-section .icon :global(svg) { width:18px; height:18px; }
  .collapsed .profile-wrap { justify-content:center; margin-inline:10px; padding-inline:0; }
  .collapsed .profile { justify-content:center; width:40px; height:40px; min-height:40px; padding:0; }

  @media (prefers-reduced-motion: no-preference) {
    button.sidebar-row,
    .library-tabs button {
      transition: background-color 120ms ease;
    }
  }
</style>
