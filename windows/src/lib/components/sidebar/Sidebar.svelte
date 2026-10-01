<script lang="ts" module>
  export type SidebarDestination = "home" | "search" | "album" | "likes" | "library" | "history" | "playlist" | "artist";
</script>

<script lang="ts">
  import { tick } from "svelte";
  import SidebarIcon from "./SidebarIcon.svelte";
  import type { AuthStatusDto } from "$lib/types";
  import type { BrowseCardDto } from "$lib/types";
  import { createMenuHandlers } from "$lib/menu/hooks";
  import { targetFromCard } from "$lib/menu/types";
  const createMenu = createMenuHandlers();

  type LibraryTab = "playlists" | "albums";

  type Props = {
    activeDestination: SidebarDestination;
    onHome: () => void;
    onSearch: () => void;
    collapsed?: boolean;
    auth: AuthStatusDto;
    onLogin: () => void;
    onCancelLogin: () => void;
    onLogout: () => void;
    onLikes?: () => void;
    onLibrary?: () => void;
    onHistory?: () => void;
    playlists?: BrowseCardDto[];
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
    collapsed = false,
    auth,
    onLogin,
    onCancelLogin,
    onLogout,
    onLikes,
    onLibrary,
    onHistory,
    playlists = [],
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

<aside class:collapsed aria-label="Barra lateral de Side B">
  <div class="scroll-region">
    <nav aria-label="Navegación principal" class="primary-section">
      <button
        class:active={activeDestination === "home"}
        class="sidebar-row"
        type="button"
        aria-current={activeDestination === "home" ? "page" : undefined}
        aria-label="Inicio"
        title={collapsed ? "Inicio" : undefined}
        onclick={onHome}
      >
        <span class="icon"><SidebarIcon name="home" /></span>
        <span class="row-label">Inicio</span>
      </button>
      <button
        class:active={activeDestination === "search"}
        class="sidebar-row"
        type="button"
        aria-current={activeDestination === "search" ? "page" : undefined}
        aria-label="Buscar"
        title={collapsed ? "Buscar" : undefined}
        onclick={onSearch}
      >
        <span class="icon"><SidebarIcon name="search" /></span>
        <span class="row-label">Buscar</span>
        <kbd class="shortcut" aria-hidden="true">Ctrl K</kbd>
      </button>
    </nav>

    <section class="collection-section" aria-labelledby="collection-heading">
      <h2 id="collection-heading">COLECCIÓN</h2>
      <button class="sidebar-row" class:active={activeDestination === "likes"} type="button" aria-current={activeDestination === "likes" ? "page" : undefined} onclick={() => onLikes?.()}>
        <span class="icon"><SidebarIcon name="liked" /></span>
        <span class="row-label">Tus Me Gusta</span>
      </button>
      <button class="sidebar-row" class:active={activeDestination === "library"} type="button" aria-current={activeDestination === "library" ? "page" : undefined} onclick={() => onLibrary?.()}>
        <span class="icon"><SidebarIcon name="library" /></span>
        <span class="row-label">Biblioteca</span>
      </button>
      <button class="sidebar-row" class:active={activeDestination === "history"} type="button" aria-current={activeDestination === "history" ? "page" : undefined} onclick={() => onHistory?.()}>
        <span class="icon"><SidebarIcon name="history" /></span>
        <span class="row-label">Historial</span>
      </button>
    </section>

    <section class="library-section" aria-label="Música guardada">
      <div class="library-tabs" role="group" aria-label="Tipo de colección">
        <button
          type="button"
          class:selected={libraryTab === "playlists"}
          aria-pressed={libraryTab === "playlists"}
          onclick={() => (libraryTab = "playlists")}
        >Playlists</button>
        <button
          type="button"
          class:selected={libraryTab === "albums"}
          aria-pressed={libraryTab === "albums"}
          onclick={() => (libraryTab = "albums")}
        >Álbumes</button>
      </div>
      {#if auth.state !== "ready"}
        <p class="guest-message">Inicia sesión para ver tu música guardada</p>
      {:else if libraryLoading && currentItems.length === 0}
        <p class="guest-message" role="status">Cargando {libraryTab === "playlists" ? "playlists" : "álbumes"}…</p>
      {:else if libraryError && currentItems.length === 0}
        <p class="guest-message error" role="alert">{libraryError}</p>
      {:else if currentItems.length === 0}
        <p class="guest-message">{libraryTab === "playlists" ? "No tienes playlists" : "No tienes álbumes guardados"}</p>
      {:else}
        <div class="collection-list" aria-label={libraryTab === "playlists" ? "Playlists" : "Álbumes guardados"}>
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
    <button bind:this={profileButton} class="profile" type="button" aria-label={auth.state === "ready" ? "Abrir opciones de cuenta" : auth.state === "authorizing" ? "Cancelar inicio de sesión" : "Iniciar sesión"} aria-expanded={accountOpen} aria-controls="account-popover" onclick={toggleAccount}>
      {#if auth.state === "ready" && auth.thumbnail}
        <img class="profile-avatar" src={auth.thumbnail} alt="" />
      {:else}
        <span class="profile-icon"><SidebarIcon name="profile" /></span>
      {/if}
      <span class="profile-copy">
        <strong>{auth.state === "ready" ? (auth.name ?? "Tu cuenta") : "Modo Invitado"}</strong>
        <small>{auth.state === "ready" ? (auth.email ?? "Sesión iniciada") : auth.state === "authorizing" ? "Abriendo acceso… · Cancelar" : auth.state === "error" ? "No se pudo iniciar sesión · Reintentar" : "Iniciar sesión"}</small>
      </span>
    </button>
    {#if auth.message}<small class="auth-error" role="alert">{auth.message}</small>{/if}
    {#if auth.state === "ready" && accountOpen}
      <div bind:this={accountPopover} id="account-popover" class="account-popover" style:left={`${popoverPosition.left}px`} style:top={`${popoverPosition.top}px`} role="dialog" aria-label="Cuenta" aria-modal="false">
        <div class="popover-account">
          {#if auth.thumbnail}<img class="popover-avatar" src={auth.thumbnail} alt="" />{:else}<span class="popover-avatar fallback">●</span>{/if}
          <span><strong>{auth.name ?? "Tu cuenta"}</strong><small>{auth.email ?? "Sesión activa de YouTube Music"}</small></span>
        </div>
        <div class="account-active">✓ Sesión activa de YouTube Music</div>
        {#if onCheckUpdates}
          <button class="update-check-btn" type="button" onclick={() => { accountOpen = false; onCheckUpdates(); }}>Buscar actualizaciones…</button>
        {/if}
        <button class="signout" type="button" onclick={() => { accountOpen = false; onLogout(); }}>Cerrar sesión</button>
      </div>
    {/if}
  </div>
</aside>

<style>
  aside {
    --sidebar-accent: var(--sideb-accent, #a33d45);
    --sidebar-surface: var(--sideb-sidebar, #24242a);
    display: flex;
    flex-direction: column;
    width: 230px;
    min-width: 230px;
    height: 100%;
    min-height: 0;
    box-sizing: border-box;
    padding-top: 52px;
    color: #f3f1f2;
    background: var(--sidebar-surface);
    border-right: 1px solid rgb(255 255 255 / 8%);
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
    padding-bottom: 10px;
    border-bottom: 1px solid rgb(255 255 255 / 9%);
  }

  .collection-section,
  .library-section {
    margin-top: 18px;
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
    min-height: 34px;
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
    padding-inline: 8px;
  }

  .collapsed .profile-wrap {
    justify-content: center;
    margin-inline: 10px;
    padding-inline: 0;
  }

  @media (prefers-reduced-motion: no-preference) {
    button.sidebar-row,
    .library-tabs button {
      transition: background-color 120ms ease;
    }
  }
</style>
