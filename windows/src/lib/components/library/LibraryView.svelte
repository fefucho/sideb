<script lang="ts">
  import type { BrowseCardDto } from "$lib/types";
  import type { AccountSongDto as SongDto } from "$lib/account/types";
  import AccountTrackTable from "./AccountTrackTable.svelte";
  import { createMenuHandlers } from "$lib/menu/hooks";
  import { targetFromCard } from "$lib/menu/types";

  type LibraryTab = "songs" | "playlists" | "albums" | "artists";
  interface Props {
    loggedIn: boolean; tab: LibraryTab; songs: SongDto[];
    playlists: BrowseCardDto[]; albums: BrowseCardDto[]; artists: BrowseCardDto[];
    loading: boolean; loadingMore: boolean; error: string | null; continuation: string | null;
    currentTrackId: string | null; isPlaying: boolean; likedIds: Set<string>; pendingIds: Set<string>;
    onTab: (tab: LibraryTab) => void; onRefresh: () => void; onLoadMore: () => void;
    onPlay: (index: number) => void; onOpenCard: (card: BrowseCardDto) => void;
    onOpenArtist?: (id: string) => void; onOpenAlbum?: (id: string) => void;
    onToggleLike: (track: SongDto) => void; onToggleSaved: (track: SongDto) => void;
    onCreatePlaylist: (title: string, description: string) => Promise<void>; onLogin: () => void;
  }
  let {
    loggedIn, tab, songs, playlists, albums, artists, loading, loadingMore, error, continuation,
    currentTrackId, isPlaying, likedIds, pendingIds, onTab, onRefresh, onLoadMore, onPlay,
    onOpenCard, onOpenArtist, onOpenAlbum, onToggleLike, onToggleSaved, onCreatePlaylist, onLogin,
  }: Props = $props();

  const tabs: { id: LibraryTab; label: string }[] = [
    { id: "songs", label: "Canciones" }, { id: "playlists", label: "Playlists" },
    { id: "albums", label: "Álbumes" }, { id: "artists", label: "Artistas" },
  ];
  let showCreate = $state(false);
  let title = $state("");
  let description = $state("");
  let createError = $state<string | null>(null);
  let creating = $state(false);
  let createDialog: HTMLDialogElement;
  let titleInput: HTMLInputElement;
  let restoreFocus: HTMLElement | null = null;
  let failedImages = $state(new Set<string>());
  const createMenu = createMenuHandlers();
  const cards = $derived(tab === "playlists" ? playlists : tab === "albums" ? albums : artists);
  const icon = $derived(tab === "playlists" ? "♫" : tab === "albums" ? "◉" : "♙");
  const emptyTitle = $derived(tab === "playlists" ? "No tenés playlists" : tab === "albums" ? "No tenés álbumes guardados" : "No tenés artistas en tu biblioteca");
  const heading = $derived(tab === "playlists" ? "Playlists" : tab === "albums" ? "Álbumes" : "Artistas");

  $effect(() => {
    if (showCreate && createDialog && !createDialog.open) {
      createDialog.showModal();
      requestAnimationFrame(() => titleInput?.focus());
    }
  });

  function openCreate(event: MouseEvent) {
    restoreFocus = event.currentTarget instanceof HTMLElement ? event.currentTarget : null;
    createError = null;
    showCreate = true;
  }

  function closeCreate() {
    if (creating) return;
    if (createDialog?.open) createDialog.close();
    else resetCreateForm();
  }
  function handleDialogClose() {
    showCreate = false;
    resetCreateForm();
    restoreFocus?.focus();
    restoreFocus = null;
  }
  function resetCreateForm() {
    title = "";
    description = "";
    createError = null;
  }
  function handleDialogCancel(event: Event) {
    if (creating) event.preventDefault();
  }
  async function submitCreate(event: SubmitEvent) {
    event.preventDefault();
    const cleanTitle = title.trim();
    if (!cleanTitle || creating) return;
    creating = true;
    createError = null;
    try {
      await onCreatePlaylist(cleanTitle, description.trim());
      if (createDialog?.open) createDialog.close();
      else handleDialogClose();
    } catch (cause) {
      createError = cause instanceof Error ? cause.message : String(cause);
    } finally {
      creating = false;
    }
  }
</script>

<main class="library" aria-busy={loading}>
  <header class="heading">
    <div><div class="eyebrow">COLECCIÓN</div><h1>Biblioteca</h1></div>
    <div class="heading-actions">
      {#if loggedIn}<button class="new-playlist" type="button" onclick={openCreate}>＋ <span>Nueva playlist</span></button>{/if}
    </div>
  </header>

  <nav class="tabs" aria-label="Secciones de la biblioteca">
    {#each tabs as item (item.id)}<button type="button" aria-pressed={tab === item.id} class:selected={tab === item.id} onclick={() => onTab(item.id)}>{item.label}</button>{/each}
    {#if loggedIn}<button class="refresh" type="button" aria-label="Actualizar biblioteca" title="Actualizar biblioteca" onclick={onRefresh}>↻</button>{/if}
  </nav>
  <div class="divider"></div>

  {#if !loggedIn}
    <section class="state"><div class="state-icon" aria-hidden="true">♙</div><h2>Iniciá sesión para ver tu biblioteca</h2><button class="primary" type="button" onclick={onLogin}>Iniciar sesión</button></section>
  {:else if tab === "songs"}
    {#if loading && songs.length === 0}<section class="state" role="status"><span class="spinner"></span><p>Cargando canciones…</p></section>
    {:else if error && songs.length === 0}<section class="state" role="alert"><h2>No se pudieron cargar las canciones</h2><p>{error}</p><button class="primary" type="button" onclick={onRefresh}>Reintentar</button></section>
    {:else if songs.length === 0}<section class="state"><div class="state-icon" aria-hidden="true">♫</div><h2>No hay canciones en tu biblioteca</h2></section>
    {:else}
      <AccountTrackTable items={songs} {currentTrackId} {isPlaying} onPlay={onPlay} {likedIds} {pendingIds} {onToggleLike} {onToggleSaved} {onOpenArtist} {onOpenAlbum} />
      {#if error}<div class="inline-error" role="alert">No se pudo actualizar: {error}<button type="button" onclick={onRefresh}>Reintentar</button></div>{/if}
      {#if continuation}<div class="more"><button type="button" disabled={loadingMore} onclick={onLoadMore}>{loadingMore ? "Cargando…" : "Cargar más canciones"}</button></div>{/if}
      <div class="bottom-space" aria-hidden="true"></div>
    {/if}
  {:else if loading && cards.length === 0}<section class="state" role="status"><span class="spinner"></span><p>Cargando {heading.toLocaleLowerCase()}…</p></section>
  {:else if error && cards.length === 0}<section class="state" role="alert"><h2>No se pudo cargar la biblioteca</h2><p>{error}</p><button class="primary" type="button" onclick={onRefresh}>Reintentar</button></section>
  {:else if cards.length === 0}<section class="state"><div class="state-icon" aria-hidden="true">{icon}</div><h2>{emptyTitle}</h2></section>
  {:else}
    <section class="card-content" aria-label={heading}>
      {#if loading}<div class="updating" role="status">Actualizando…</div>{/if}
      {#if error}<div class="inline-error" role="alert">No se pudo actualizar: {error}<button type="button" onclick={onRefresh}>Reintentar</button></div>{/if}
      <div class="grid" class:artists-grid={tab === "artists"}>
        {#each cards as card, index (`${card.kind}-${card.id}-${index}`)}
          {@const key = `${card.kind}-${card.id}-${index}`}
          {@const menu = createMenu(() => targetFromCard(card), { view: 'library' })}
          <button class="card" type="button" aria-label={`Abrir ${card.title}${card.subtitle ? `, ${card.subtitle}` : ""}`} onclick={() => onOpenCard(card)} oncontextmenu={menu.onContextMenu} onkeydown={menu.onKeyDown}>
            {#if card.thumbnail && !failedImages.has(key)}<img class:artist-art={tab === "artists"} src={card.thumbnail} alt="" loading="lazy" onerror={() => failedImages = new Set(failedImages).add(key)} />{:else}<div class="art-fallback" class:artist-art={tab === "artists"} aria-hidden="true">{icon}</div>{/if}
            <span class="card-title">{card.title}</span>{#if card.subtitle}<span class="card-subtitle">{card.subtitle}</span>{/if}
          </button>
        {/each}
      </div>
      {#if continuation}<div class="more"><button type="button" disabled={loadingMore} onclick={onLoadMore}>{loadingMore ? "Cargando…" : "Cargar más"}</button></div>{/if}
      <div class="bottom-space" aria-hidden="true"></div>
    </section>
  {/if}

  <dialog class="create-dialog" bind:this={createDialog} onclose={handleDialogClose} oncancel={handleDialogCancel} onclick={(event) => { if (event.target === createDialog) closeCreate(); }} aria-labelledby="create-title">
        <h2 id="create-title">Nueva playlist</h2>
        <form onsubmit={submitCreate}>
          <label for="playlist-title">Nombre</label><input id="playlist-title" bind:this={titleInput} bind:value={title} maxlength="150" required autocomplete="off" />
          <label for="playlist-description">Descripción <span>(opcional)</span></label><textarea id="playlist-description" bind:value={description} maxlength="500" rows="3"></textarea>
          {#if createError}<p class="form-error" role="alert">{createError}</p>{/if}
          <div class="dialog-actions"><button class="secondary" type="button" disabled={creating} onclick={closeCreate}>Cancelar</button><button class="primary" type="submit" disabled={creating || !title.trim()}>{creating ? "Creando…" : "Crear playlist privada"}</button></div>
        </form>
  </dialog>
</main>

<style>
  .library { position: relative; box-sizing: border-box; min-width: 0; min-height: 100%; color: #f7f7f8; background: var(--sideb-background, #1b1b1e); }
  .heading { display: flex; align-items: flex-end; justify-content: space-between; gap: 16px; padding: 24px 142px 18px 32px; }
  .eyebrow { margin-bottom: 4px; color: #aaaab1; font-size: 11px; font-weight: 700; letter-spacing: 1.2px; }
  h1 { margin: 0; font-size: 32px; font-weight: 700; line-height: 1.15; }
  .heading-actions { display: flex; align-items: center; gap: 12px; }
  .new-playlist, .refresh { border: 1px solid var(--sideb-surface-border); border-radius: 999px; color: #f6f6f7; background: var(--sideb-surface); font: inherit; cursor: pointer; }
  .new-playlist { padding: 8px 14px; font-size: 13px; font-weight: 600; } .new-playlist:hover, .refresh:hover { background: var(--sideb-surface-hover); }
  .refresh { width: 34px; height: 34px; font-size: 21px; line-height: 1; }
  .tabs { display: flex; align-items: center; gap: 8px; padding: 0 32px 14px; }
  .tabs button { padding: 8px 15px; border: 0; border-radius: 999px; color: #e7e7eb; background: var(--sideb-surface); font: inherit; font-size: 13px; font-weight: 600; cursor: pointer; }
  .tabs button:hover { background: var(--sideb-surface-hover); }.tabs button.selected { color: white; background: var(--sideb-accent); }
  .tabs .refresh { margin-left: auto; }
  .divider { height: 1px; margin: 0 32px 8px; background: rgb(255 255 255 / 9%); }
  .state { display: flex; min-height: 320px; flex-direction: column; align-items: center; justify-content: center; gap: 12px; padding: 24px; color: #b9b9c0; text-align: center; }
  .state h2 { margin: 0; color: #f3f3f5; font-size: 17px; }.state p { max-width: 50ch; margin: 0; font-size: 13px; }
  .state-icon { color: #c8c8ce; font-size: 38px; }.spinner { width: 22px; height: 22px; border: 2px solid #ffffff30; border-top-color: var(--sideb-highlight); border-radius: 50%; animation: spin .8s linear infinite; }
  .primary, .secondary { padding: 8px 15px; border: 0; border-radius: 999px; color: white; background: var(--sideb-accent); font: inherit; font-size: 13px; cursor: pointer; }
  .secondary { color: #eee; background: var(--sideb-surface-hover); }.primary:disabled, .secondary:disabled { opacity: .55; cursor: wait; }
  .card-content { position: relative; }.updating { padding: 8px 32px 0; color: #aaaab1; font-size: 11px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 160px), 1fr)); align-items: start; gap: 24px 18px; padding: 20px 32px 0; }
  .card { display: flex; width: 100%; max-width: 220px; min-width: 0; flex-direction: column; align-items: flex-start; gap: 7px; padding: 0; border: 0; border-radius: 8px; color: inherit; background: transparent; text-align: left; font: inherit; cursor: pointer; }
  .card img, .art-fallback { display: grid; box-sizing: border-box; width: 100%; aspect-ratio: 1; place-items: center; overflow: hidden; border-radius: 10px; object-fit: cover; color: #c8c8ce; background: var(--sideb-surface); font-size: 38px; }
  .artists-grid .card img, .artists-grid .card .art-fallback { width: 100%; height: auto; aspect-ratio: 1; }
  .card img.artist-art, .art-fallback.artist-art { border-radius: 50%; }.card:hover img, .card:hover .art-fallback { filter: brightness(1.08); }
  .card-title { display: -webkit-box; max-width: 100%; overflow: hidden; color: #f1f1f3; font-size: 13px; font-weight: 600; line-height: 18px; -webkit-box-orient: vertical; -webkit-line-clamp: 2; line-clamp: 2; }
  .card-subtitle { max-width: 100%; overflow: hidden; color: #aaaab1; font-size: 11px; text-overflow: ellipsis; white-space: nowrap; }
  .inline-error { display: flex; align-items: center; gap: 10px; margin: 8px 32px; padding: 8px 12px; border-radius: 7px; color: #ffd5d5; background: #9d303033; font-size: 12px; }.inline-error button { margin-left: auto; border: 0; color: inherit; background: transparent; font: inherit; text-decoration: underline; cursor: pointer; }
  .more { display: flex; justify-content: center; padding: 18px 32px; }.more button { padding: 8px 16px; border: 1px solid var(--sideb-surface-border); border-radius: 999px; color: white; background: var(--sideb-surface); font: inherit; cursor: pointer; }.more button:disabled { opacity: .55; }
  .bottom-space { height: 130px; }
  .create-dialog { box-sizing: border-box; width: min(calc(100% - 48px), 460px); max-width: 460px; max-height: calc(100% - 48px); margin: auto; padding: 24px; overflow-y: auto; border: 1px solid var(--sideb-surface-border); border-radius: 14px; color: #f5f5f6; background: #28282d; box-shadow: 0 20px 70px #0009; }
  .create-dialog::backdrop { background: rgb(0 0 0 / 58%); }
  .create-dialog h2 { margin: 0 0 20px; font-size: 21px; }.create-dialog form { display: flex; flex-direction: column; gap: 9px; }.create-dialog label { margin-top: 5px; color: #e9e9ec; font-size: 13px; font-weight: 600; }.create-dialog label span { color: #aaaab1; font-weight: 400; }
  .create-dialog input, .create-dialog textarea { box-sizing: border-box; width: 100%; padding: 10px 11px; border: 1px solid #ffffff26; border-radius: 7px; color: white; background: #17171a; font: inherit; font-size: 13px; resize: vertical; }
  .form-error { margin: 3px 0; color: #ffb7bb; font-size: 12px; }.dialog-actions { display: flex; justify-content: flex-end; gap: 10px; margin-top: 12px; }
  button:focus-visible, input:focus-visible, textarea:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 3px; }
  @keyframes spin { to { transform: rotate(360deg); } }
  @media (max-width: 640px) { .heading { padding-inline: 20px; }.tabs { overflow-x: auto; padding-inline: 20px; }.divider { margin-inline: 20px; }.grid { padding-inline: 20px; } }
  @media (prefers-reduced-motion: reduce) { .spinner { animation: none; } }
</style>
