<script lang="ts">
  import { onMount, tick, setContext } from "svelte";
  import Sidebar from "$lib/components/sidebar/Sidebar.svelte";
  import PlayerBar from "$lib/components/player/PlayerBar.svelte";
  import HomeView from "$lib/components/home/HomeView.svelte";
  import AlbumDetailView from "$lib/components/detail/AlbumDetailView.svelte";
  import ArtistDetailView from "$lib/components/detail/ArtistDetailView.svelte";
  import CatalogView from "$lib/components/detail/CatalogView.svelte";
  import LibraryView from "$lib/components/library/LibraryView.svelte";
  import PlaylistDetailView from "$lib/components/detail/PlaylistDetailView.svelte";
  import HistoryView from "$lib/components/library/HistoryView.svelte";
  import { AccountController, emptyAccountData, type AccountNavigationSnapshot } from "$lib/account/controller";
  import TitleBar from "$lib/components/shell/TitleBar.svelte";
  import { NavigationHistory } from "$lib/navigation/history";
  import { WindowController } from "$lib/window/controller";
  import { MENU_CONTEXT, songFromHome, songFromQueue, type MenuService, type MenuOrigin, type MenuTarget } from "$lib/menu/types";
  import type { MenuAction, MenuRequest } from '$lib/menu/types';
  import { menuItems } from '$lib/menu/policy';
  import { MenuExecutor } from '$lib/menu/executor';
  import ContextMenu from '$lib/components/menu/ContextMenu.svelte';
  import PlaylistEditorDialog from '$lib/components/detail/PlaylistEditorDialog.svelte';
  import PlaylistDeleteDialog from '$lib/components/detail/PlaylistDeleteDialog.svelte';
  import UpdateModal from '$lib/components/update/UpdateModal.svelte';
  import { UpdaterController } from '$lib/updater/controller';
  import { CatalogController, emptyCatalogData, type CatalogData } from "$lib/catalog/controller";
  import { HomeController, emptyHomeData } from "$lib/home/controller";
  import SearchView from "$lib/components/search/SearchView.svelte";
  import { SearchController, emptySearchData, type SearchMode, type SearchData } from "$lib/search/controller";
  import { SearchPreviewController, emptySearchPreviewData } from "$lib/search/preview";
  import SpotlightSearch from "$lib/components/search/SpotlightSearch.svelte";
  import { PlaybackController, emptyPlaybackData, parseDuration } from "$lib/player/controller";
  import { LyricsController, emptyLyricsState } from '$lib/player/lyrics';
  import { RecommendationsController, emptyRecommendationsSnapshot } from '$lib/player/recommendations';
  import FullscreenNowPlaying from "$lib/components/fullscreen/FullscreenNowPlaying.svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { listen, type UnlistenFn } from "@tauri-apps/api/event";
  import type {
    AlbumCardDto,
    SongDto,
    HomeArtistRunDto,
    BrowseCardDto,
    BackendStatusDto,
    AuthStatusDto,
    CommandError,
    PlaylistDetailDto,
  } from "$lib/types";

  type PrimaryNav = "home" | "search" | "library" | "likes" | "history";
  type ActiveView = "feed" | "search_results" | "album_detail" | "artist_detail" | "catalog" | "library" | "playlist_detail" | "history";

  let primaryNav = $state<PrimaryNav>("home");
  let activeView = $state<ActiveView>("feed");
  let sidebarCollapsed = $state(false);
  let isFullscreenOpen = $state(false);
  let selectedPanel = $state<'queue' | 'lyrics' | 'related'>('queue');
  let shellError = $state<string | null>(null);
  const nativeWindow = new WindowController();
  const updater = new UpdaterController();
  let accountData = $state(emptyAccountData());
  const account = new AccountController((command, args) => invoke(command, args), data => { accountData = data; });
  let lastPlaylistId = $state<string | null>(null);

  let homeData = $state(emptyHomeData());
  const home = new HomeController((command, args) => invoke(command, args), data => { homeData = data; });
  const homePage = $derived(homeData.page);
  let searchData = $state(emptySearchData());
  const search = new SearchController((command, args) => invoke(command, args), data => { searchData = data; });
  let previewData = $state(emptySearchPreviewData());
  let draftQuery = $state('');
  let spotlightOpen = $state(false);
  const searchPreview = new SearchPreviewController((command, args) => invoke(command, args), data => { previewData = data; });

  let catalogData = $state(emptyCatalogData());
  const catalog = new CatalogController((command, args) => invoke(command, args), data => { catalogData = data; });
  const selectedAlbum = $derived(catalogData.album);
  const lastAlbumBrowseId = $derived(catalogData.albumId);
  const isAlbumLoading = $derived(catalogData.albumLoading);
  const albumError = $derived(catalogData.albumError);
  const selectedArtist = $derived(catalogData.artist);
  const lastArtistBrowseId = $derived(catalogData.artistId);
  const isArtistLoading = $derived(catalogData.artistLoading);
  const artistError = $derived(catalogData.artistError);
  const catalogItems = $derived(catalogData.items);
  const catalogTarget = $derived(catalogData.target);
  const isCatalogLoading = $derived(catalogData.loading);
  const catalogError = $derived(catalogData.error);
  type NavigationSnapshot = {
    view: ActiveView; primary: PrimaryNav; scroll: number;
    details: CatalogData; playlistId: string | null; account: AccountNavigationSnapshot; search: SearchData;
  };
  const navigationHistory = new NavigationHistory<NavigationSnapshot>();
  let canBack = $state(false);
  let canForward = $state(false);
  let navigationRevision = 0;
  let collectionPlayRevision = 0;
  let menuRequest = $state<MenuRequest | null>(null);
  let menuActionPending = $state(false);
  let editingPlaylist = $state<PlaylistDetailDto | null>(null);
  let deletingPlaylist = $state<PlaylistDetailDto | null>(null);
  let newPlaylistSong = $state<SongDto | null>(null);
  let createdPlaylistForSong: string | null = null;
  let menuNotice = $state<string | null>(null);
  const menuService: MenuService = {
    open(event, target, origin = {}) {
      event.preventDefault(); event.stopPropagation();
      if (menuActionPending || editingPlaylist || deletingPlaylist || newPlaylistSong) return;
      const anchor = event.currentTarget instanceof HTMLElement ? event.currentTarget : null;
      const rect = anchor?.getBoundingClientRect();
      const keyboard = event instanceof KeyboardEvent || (event instanceof MouseEvent && event.detail === 0 && event.button !== 2);
      menuRequest = { x: keyboard ? rect?.left ?? 20 : (event as MouseEvent).clientX,
        y: keyboard ? rect?.bottom ?? 60 : (event as MouseEvent).clientY, target,
        focus: document.activeElement instanceof HTMLElement ? document.activeElement : anchor,
        origin: { view: activeView, currentId: activeView === 'album_detail' ? lastAlbumBrowseId : activeView === 'artist_detail' ? lastArtistBrowseId : lastPlaylistId,
          currentQueueEntryId: playbackState.queue.currentIndex == null ? null : playbackState.queue.items[playbackState.queue.currentIndex]?.entryId,
          ...origin } };
    },
  };
  setContext(MENU_CONTEXT, menuService);

  // Estado Backend
  let backendStatus = $state<BackendStatusDto | null>(null);
  let statusError = $state<string | null>(null);
  let isRetryingInit = $state(false);
  let authStatus = $state<AuthStatusDto>({ state: "guest", name: null, email: null, thumbnail: null, message: null });
  const menu = $derived(menuRequest ? menuItems(menuRequest.target, menuRequest.origin,
    { loggedIn: authStatus.state === 'ready', likedIds: accountData.likedIds, playlists: accountData.playlists }) : []);

  let playbackState = $state(emptyPlaybackData());
  let playbackError = $state<string | null>(null);
  const player = new PlaybackController((command, args) => invoke(command, args),
    (name, handler) => listen(name, handler), snapshot => {
      playbackState = snapshot.state;
      playbackError = snapshot.error;
    });
  const playerBarState = $derived({ ...playbackState, error: playbackError || playbackState.error });
  let lyricsState = $state(emptyLyricsState());
  const lyrics = new LyricsController((command, args) => invoke(command, args), state => { lyricsState = state; });
  let recommendationsState = $state(emptyRecommendationsSnapshot());
  const recommendations = new RecommendationsController((command, args) => invoke(command, args), snapshot => { recommendationsState = snapshot; });

  $effect(() => {
    // Account changes invalidate pending requests even when the playing track is unchanged.
    authStatus.state; authStatus.email;
    lyrics.setTrack(playbackState.currentTrack, playbackState.generation, playbackState.duration);
    recommendations.setTrack(playbackState.currentTrack);
    if (isFullscreenOpen && selectedPanel === 'related') void recommendations.load();
  });

  let sessionRevision = 0;

  function applyAuthStatus(next: AuthStatusDto) {
    const changedAccount = (next.state === "guest" || next.state === "ready")
      && (authStatus.state !== next.state || authStatus.email !== next.email);
    authStatus = next;
    if (changedAccount) {
      home.reset();
      search.reset();
      searchPreview.reset(); draftQuery = '';
      spotlightOpen = false;
      catalog.reset();
      ++sessionRevision;
      player.invalidatePending();
      lyrics.reset();
      recommendations.reset();
      account.reset(next.state === "ready");
      lastPlaylistId = null;
      navigationHistory.clear(); updateHistoryAvailability();
      ++navigationRevision; ++collectionPlayRevision;
      menuRequest = null; editingPlaylist = null; deletingPlaylist = null; newPlaylistSong = null;
      createdPlaylistForSong = null; shellError = null; menuNotice = null;
      activeView = primaryNav === "home" ? "feed" : primaryNav === "search" ? "search_results" : primaryNav === "history" ? "history" : primaryNav === "likes" ? "playlist_detail" : "library";
      if (backendStatus?.ready) { loadHomePage(); void account.initialize(); }
      if (next.state === "ready") {
        if (primaryNav === "library") void account.load(accountData.tab);
        if (primaryNav === "history") void account.load('history');
        if (primaryNav === "likes") { lastPlaylistId = 'LM'; void account.openPlaylist('LM'); }
      }
    }
  }

  async function handleLogin() {
    try {
      await invoke("login_webview");
    } catch (error) {
      authStatus = { ...authStatus, state: "error", message: extractErrorMessage(error, "No se pudo abrir el acceso.") };
    }
  }

  async function handleCancelLogin() {
    try {
      applyAuthStatus(await invoke<AuthStatusDto>("cancel_login"));
    } catch (error) {
      authStatus = { ...authStatus, message: extractErrorMessage(error, "No se pudo cancelar el acceso.") };
    }
  }

  async function handleLogout() {
    try {
      applyAuthStatus(await invoke<AuthStatusDto>("sign_out"));
    } catch (error) {
      authStatus = { ...authStatus, message: extractErrorMessage(error, "No se pudo limpiar la sesión.") };
    }
  }

  function extractErrorMessage(err: unknown, fallback: string): string {
    if (err && typeof err === "object" && "message" in err) {
      return (err as CommandError).message;
    }
    if (typeof err === "string") {
      return err;
    }
    return fallback;
  }

  async function checkBackendStatus() {
    try {
      statusError = null;
      backendStatus = await invoke<BackendStatusDto>("get_backend_status");
      if (backendStatus?.ready && !homePage) {
        loadHomePage();
        if (authStatus.state === "ready") void account.initialize();
      }
    } catch (e: unknown) {
      statusError = extractErrorMessage(e, "Error al comprobar el estado del backend.");
    }
  }

  async function handleRetryInit() {
    isRetryingInit = true;
    statusError = null;
    try {
      backendStatus = await invoke<BackendStatusDto>("retry_init_core");
      if (backendStatus?.ready) {
        loadHomePage();
      }
    } catch (e: unknown) {
      statusError = extractErrorMessage(e, "No se pudo reconectar con el motor.");
    } finally {
      isRetryingInit = false;
    }
  }

  function loadHomePage(chipParams: string | null = null) { return home.load(chipParams); }
  function loadMoreHome() { return home.loadMore(); }
  function executeSearch(targetQuery: string, mode: SearchMode = searchData.mode, recordHistory = true) {
    if (!targetQuery.trim()) return;
    const query = targetQuery.trim();
    setPlayerFullscreen(false);
    draftQuery = query;
    spotlightOpen = false; searchPreview.cancel();
    if (activeView !== 'search_results' || searchData.lastSearchedQuery !== query || searchData.mode !== mode) pushNavigation();
    primaryNav = "search"; activeView = "search_results";
    void search.execute(query, mode, recordHistory);
    const revision = navigationRevision;
    void tick().then(() => {
      if (revision === navigationRevision && activeView === 'search_results' && searchData.lastSearchedQuery === query) {
        contentScrollElement()?.scrollTo({ top: 0 });
      }
    });
  }

  function handleSwitchNav(nav: PrimaryNav) {
    if (nav === 'search') { openSearchSpotlight(); return; }
    setPlayerFullscreen(false);
    if (nav === 'library' || nav === 'likes' || nav === 'history') { openAccountNav(nav); return; }
    if (nav === 'home' && activeView === 'feed') return;
    pushNavigation();
    primaryNav = nav;
    if (nav === "home") {
      activeView = "feed";
      if (!homePage && !homeData.loading) {
        loadHomePage();
      }
    } else {
      activeView = "search_results";
    }
    scrollContentToTop();
  }

  function scrollContentToTop() {
    contentScrollElement()?.scrollTo({ top: 0 });
  }

  function contentScrollElement(view: ActiveView = activeView) {
    return view === 'search_results'
      ? document.querySelector<HTMLElement>('.search-page .results-scroll')
      : document.querySelector<HTMLElement>('.content-column');
  }

  async function handleWindowKeydown(event: KeyboardEvent) {
    if (event.defaultPrevented || document.querySelector('[role="dialog"], [role="menu"]')) return;
    if (event.key === 'Escape' && document.querySelector('[data-queue-dragging="true"]')) return;
    if (event.key === 'Escape' && document.querySelector('[data-volume-popover]')) return;
    if (event.key === "Escape" && isFullscreenOpen) {
      event.preventDefault();
      await setPlayerFullscreen(false);
      return;
    }
    if (event.key === 'F11') {
      event.preventDefault();
      try { await nativeWindow.toggleNativeFullscreen(); } catch (error) { shellError = extractErrorMessage(error, 'No se pudo cambiar la ventana.'); }
      return;
    }
    const editable = event.target instanceof HTMLElement && (event.target.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(event.target.tagName));
    if (!editable && event.altKey && !event.ctrlKey && (event.key === 'ArrowLeft' || event.key === 'ArrowRight')) {
      event.preventDefault();
      if (event.key === 'ArrowLeft') void goBackFromDetail(); else void goForward();
      return;
    }
    if (event.ctrlKey && !event.altKey && !event.metaKey && event.key.toLowerCase() === "k") {
      event.preventDefault();
      openSearchSpotlight();
    }
  }

  function handleSwitchSearchMode(mode: SearchMode) {
    if (searchData.mode === mode && activeView === "search_results") return;
    activeView = "search_results";
    search.setMode(mode);
  }
  function openSearchSpotlight() {
    if (!draftQuery) draftQuery = searchData.lastSearchedQuery || searchData.query;
    spotlightOpen = true;
    searchPreview.setQuery(draftQuery);
  }
  function handleDraftChange(query: string) { draftQuery = query; searchPreview.setQuery(query); }
  function dismissSearchPreview() { spotlightOpen = false; searchPreview.cancel(); }
  function dismissInlinePreview() { if (!spotlightOpen) searchPreview.cancel(); }
  function focusInlinePreview() { searchPreview.setQuery(draftQuery); }
  function selectSearchCard(card: BrowseCardDto) {
    dismissSearchPreview();
    if (card.kind === 'artist') void openArtistDetail(card.id);
    else if (card.kind === 'album') void openAlbumDetail(card.id, 'search');
    else if (card.kind === 'playlist') void openPlaylist(card.id);
    else if (card.kind === 'song' || card.kind === 'video') {
      setPlayerFullscreen(false);
      ++collectionPlayRevision;
      void player.startRadio({ videoId: card.id, title: card.title, artists: card.artists ?? '',
        artistRuns: card.artistRuns, album: card.album ?? null, duration: card.duration, thumbnail: card.thumbnail,
        isVideo: card.isVideo ?? card.kind === 'video', artistId: card.artistId ?? null, albumId: card.albumId ?? null })
        .catch(error => shellError = extractErrorMessage(error, 'No se pudo iniciar la radio.'));
    } else executeSearch(card.title);
  }
  function playSearchPreviewSong(song: SongDto) {
    setPlayerFullscreen(false);
    dismissSearchPreview(); ++collectionPlayRevision;
    void player.startRadio(song).catch(error => shellError = extractErrorMessage(error, 'No se pudo iniciar la radio.'));
  }

  function invalidateDetails() { catalog.invalidate(); }

  function updateHistoryAvailability() { canBack = navigationHistory.canBack; canForward = navigationHistory.canForward; }
  function captureNavigation(): NavigationSnapshot {
    return { view: activeView, primary: primaryNav,
      scroll: contentScrollElement()?.scrollTop ?? 0,
      details: catalog.data, playlistId: lastPlaylistId, account: account.captureNavigation(),
      search: { ...searchData, songs: [...searchData.songs], albums: [...searchData.albums], top: [...searchData.top], artists: [...searchData.artists], playlists: [...searchData.playlists], videos: [...searchData.videos], partialErrors: { ...searchData.partialErrors } } };
  }
  function pushNavigation() {
    spotlightOpen = false; searchPreview.cancel();
    navigationHistory.visit(captureNavigation()); updateHistoryAvailability();
    ++navigationRevision; ++collectionPlayRevision;
    invalidateDetails();
    search.invalidate(); account.invalidatePlaylist();
    menuRequest = null;
  }

  async function openAlbumDetail(id: string, _origin?: "home" | "search", remember = true) {
    if (!id.trim()) return;
    setPlayerFullscreen(false);
    if (remember && activeView === 'album_detail' && lastAlbumBrowseId === id) return;
    if (remember) pushNavigation();
    activeView = "album_detail"; scrollContentToTop();
    await catalog.openAlbum(id);
  }
  async function openArtistDetail(id: string, remember = true) {
    if (!id.trim()) return;
    setPlayerFullscreen(false);
    if (remember && activeView === 'artist_detail' && lastArtistBrowseId === id) return;
    if (remember) pushNavigation();
    activeView = "artist_detail"; scrollContentToTop();
    await catalog.openArtist(id);
  }
  async function openCatalog(id: string, params: string | null, title: string, remember = true) {
    if (!id.trim()) return;
    setPlayerFullscreen(false);
    if (remember && activeView === 'catalog' && catalogTarget?.id === id && catalogTarget.params === params) return;
    if (remember) pushNavigation();
    activeView = "catalog"; scrollContentToTop();
    await catalog.openGrid(id, params, title);
  }

  async function goBackFromDetail() {
    if (isFullscreenOpen) await setPlayerFullscreen(false);
    const previous = navigationHistory.back(captureNavigation()); updateHistoryAvailability();
    if (previous) await restoreNavigation(previous);
  }
  async function goForward() {
    if (isFullscreenOpen) await setPlayerFullscreen(false);
    const next = navigationHistory.forward(captureNavigation()); updateHistoryAvailability();
    if (next) await restoreNavigation(next);
  }
  async function restoreNavigation(previous: NavigationSnapshot) {
    spotlightOpen = false; searchPreview.cancel();
    const revision = ++navigationRevision; ++collectionPlayRevision;
    invalidateDetails(); search.invalidate(); account.invalidatePlaylist();
    activeView = previous.view; primaryNav = previous.primary;
    catalog.restore(previous.details);
    search.restore(previous.search); account.restoreNavigation(previous.account);
    if (previous.view === 'search_results') draftQuery = previous.search.lastSearchedQuery || previous.search.query;
    lastPlaylistId = previous.playlistId;
    if (activeView === 'playlist_detail' && lastPlaylistId && !accountData.playlist && !accountData.playlistError) void account.openPlaylist(lastPlaylistId);
    if (activeView === "album_detail" && !selectedAlbum && lastAlbumBrowseId && !albumError) void openAlbumDetail(lastAlbumBrowseId, undefined, false);
    if (activeView === "artist_detail" && !selectedArtist && lastArtistBrowseId && !artistError) void openArtistDetail(lastArtistBrowseId, false);
    if (activeView === "catalog" && !catalogItems.length && catalogTarget && !catalogError) void openCatalog(catalogTarget.id, catalogTarget.params, catalogTarget.title, false);
    await tick();
    if (revision === navigationRevision) contentScrollElement(previous.view)?.scrollTo({ top: previous.scroll });
  }

  async function toggleAlbumLibrary() {
    const album = selectedAlbum;
    if (!album?.playlistId || authStatus.state !== "ready") throw new Error("Inicia sesión para guardar el álbum.");
    const revision = sessionRevision;
    const save = !album.inLibrary;
    try { await invoke("toggle_album_library", { playlistId: album.playlistId, save }); }
    catch (error) { throw new Error(extractErrorMessage(error, "No se pudo actualizar la biblioteca.")); }
    if (revision !== sessionRevision) return;
    catalog.updateAlbum(current => current.browseId === album.browseId ? { ...current, inLibrary: save } : current);
    navigationHistory.mapSnapshots(snapshot => ({ ...snapshot, details: { ...snapshot.details, album: snapshot.details.album?.browseId === album.browseId ? { ...snapshot.details.album, inLibrary: save } : snapshot.details.album } }));
    void account.load('albums');
  }

  async function toggleArtistSubscription() {
    const artist = selectedArtist;
    if (!artist || authStatus.state !== "ready") throw new Error("Inicia sesión para suscribirte.");
    const revision = sessionRevision;
    const subscribe = !artist.subscribed;
    try { await invoke("set_artist_subscription", { channelId: artist.channelId, subscribe }); }
    catch (error) { throw new Error(extractErrorMessage(error, "No se pudo actualizar la suscripción.")); }
    if (revision !== sessionRevision) return;
    catalog.updateArtist(current => current.channelId === artist.channelId ? { ...current, subscribed: subscribe } : current);
    navigationHistory.mapSnapshots(snapshot => ({ ...snapshot, details: { ...snapshot.details, artist: snapshot.details.artist?.channelId === artist.channelId ? { ...snapshot.details.artist, subscribed: subscribe } : snapshot.details.artist } }));
    void account.load('artists');
  }

  async function playCollection(items: SongDto[], index: number, source: {kind:string;id:string;title:string}, shuffle = false, fallbackThumbnail: string | null = null, fallbackArtist = "") {
    const indexed = items.map((song, originalIndex) => ({ song, originalIndex })).filter(({ song }) => song.videoId.trim());
    const entries = indexed.map(({ song }) => ({
      entryId: crypto.randomUUID(), videoId: song.videoId, title: song.title,
      artists: song.artists || fallbackArtist, thumbnail: song.thumbnail || fallbackThumbnail,
      duration: song.duration ? parseDuration(song.duration) : null,
      artistId: song.artistId, albumId: song.albumId, album: song.album,
      artistRuns: song.artistRuns?.map(run => ({ ...run })) ?? [],
    }));
    if (!entries.length) throw new Error("No hay canciones disponibles para reproducir.");
    let startIndex = indexed.findIndex((entry) => entry.originalIndex === index);
    if (shuffle) {
      for (let position = entries.length - 1; position > 0; position--) {
        const other = Math.floor(Math.random() * (position + 1));
        [entries[position], entries[other]] = [entries[other], entries[position]];
      }
      startIndex = 0;
    }
    startIndex = Math.max(0, startIndex);
    const track = entries[startIndex];
    await player.playSong(track, { queueItems: entries, queueIndex: startIndex, queueSource: source });
  }

  function playAlbum(index: number, shuffle = false) {
    ++collectionPlayRevision;
    const album = selectedAlbum;
    if (album) void playCollection(album.items.map(song => ({ ...song, artistId: song.artistId ?? album.artistId,
      albumId: song.albumId ?? album.browseId, album: song.album ?? album.title })), index,
      {kind: "album", id: album.browseId, title: album.title}, shuffle, album.thumbnail, album.artist ?? "").catch(() => {});
  }

  function playArtist(index: number, shuffle = false) {
    ++collectionPlayRevision;
    if (selectedArtist) void playCollection(selectedArtist.topSongs.map(song => ({ ...song, artistId: song.artistId ?? selectedArtist!.channelId })), index,
      {kind: "artist", id: selectedArtist.channelId, title: selectedArtist.name}, shuffle, selectedArtist.thumbnail, selectedArtist.name).catch(() => {});
  }

  function openAccountNav(destination: 'library' | 'likes' | 'history') {
    setPlayerFullscreen(false);
    if (primaryNav === destination && (activeView === 'library' || activeView === 'history' || activeView === 'playlist_detail' && lastPlaylistId === 'LM')) return;
    pushNavigation(); primaryNav = destination;
    if (destination === 'likes') { activeView = 'playlist_detail'; lastPlaylistId = 'LM'; void account.openPlaylist('LM'); }
    else if (destination === 'library') { activeView = 'library'; void account.load(accountData.tab); }
    else { activeView = 'history'; void account.load('history'); }
    scrollContentToTop();
  }
  function openPlaylist(id: string, remember = true) {
    if (!id.trim()) return;
    setPlayerFullscreen(false);
    if (remember && activeView === 'playlist_detail' && lastPlaylistId?.replace(/^VL/, '') === id.replace(/^VL/, '')) return;
    if (remember) pushNavigation();
    activeView = 'playlist_detail'; lastPlaylistId = id; scrollContentToTop(); void account.openPlaylist(id);
  }
  function openLibraryCard(card: BrowseCardDto) {
    if (card.kind === 'artist' || accountData.tab === 'artists') void openArtistDetail(card.id);
    else if (card.kind === 'album' || accountData.tab === 'albums') void openAlbumDetail(card.id);
    else openPlaylist(card.id);
  }
  function playLibrarySong(index: number) {
    ++collectionPlayRevision;
    void playCollection(accountData.songs, index, { kind: 'library', id: 'FEmusic_liked_videos', title: 'Biblioteca' }).catch(() => {});
  }
  async function playPlaylistSong(index: number, shuffle = false) {
    const playlist = accountData.playlist;
    if (!playlist) return;
    const revision = ++collectionPlayRevision;
    const session = sessionRevision; const navigation = navigationRevision;
    const valid = () => revision === collectionPlayRevision && session === sessionRevision && navigation === navigationRevision;
    try {
      const tracks = await account.resolvePlaylistTracks(playlist.id, valid);
      if (!valid()) return;
      const selected = playlist.items[index];
      const currentIndex = selected?.setVideoId ? tracks.findIndex(song => song.setVideoId === selected.setVideoId)
        : tracks[index]?.videoId === selected?.videoId ? index : tracks.findIndex(song => song.videoId === selected?.videoId);
      if (!shuffle && currentIndex < 0) throw new Error('Esta canción ya no está disponible en la playlist. Actualizá la lista.');
      await playCollection(tracks, Math.max(0, currentIndex), { kind: 'playlist', id: playlist.id, title: playlist.title }, shuffle, playlist.thumbnail);
    } catch (error) { if (valid()) shellError = extractErrorMessage(error, 'No se pudo reproducir la playlist completa.'); }
  }

  async function startArtistRadio() {
    const artist = selectedArtist;
    if (!artist?.radioPlaylistId) return;
    const revision = sessionRevision;
    const identity = catalog.captureIdentity();
    const playRevision = ++collectionPlayRevision;
    try {
      const items = await invoke<SongDto[]>("get_artist_radio", { playlistId: artist.radioPlaylistId });
      if (revision !== sessionRevision || playRevision !== collectionPlayRevision || !catalog.isCurrentIdentity(identity)) return;
      await playCollection(items, 0, {kind: "mix", id: artist.radioPlaylistId, title: `Mix de ${artist.name}`});
    } catch (error) { throw new Error(extractErrorMessage(error, "No se pudo iniciar el mix.")); }
  }

  async function handlePlaySong(videoId: string,
    meta?: { title?: string; artists?: string; thumbnail?: string | null; duration?: string | null; artistId?: string | null; artistRuns?: HomeArtistRunDto[]; albumId?: string | null; album?: string | null }) {
    ++collectionPlayRevision;
    await player.playSong({ videoId, title: meta?.title ?? "Canción", artists: meta?.artists ?? "",
      thumbnail: meta?.thumbnail ?? null, duration: meta?.duration ?? null,
      artistId: meta?.artistId, artistRuns: meta?.artistRuns, albumId: meta?.albumId, album: meta?.album }).catch(() => {});
  }
  function playQueueIndex(index: number) { ++collectionPlayRevision; void player.playQueueIndex(index).catch(() => {}); }
  function handleNext() { ++collectionPlayRevision; return player.next(); }
  function handlePrevious() { ++collectionPlayRevision; return player.previous(); }
  function handleSetShuffle(enabled: boolean) { return player.setShuffle(enabled); }
  function handleSetRepeat(enabled: boolean) { return player.setRepeat(enabled); }
  function handleTogglePlay() { ++collectionPlayRevision; return player.toggle().catch(() => {}); }
  function handleRetryPlayback() { ++collectionPlayRevision; return player.retry().catch(() => {}); }
  function handleSeek(seconds: number) { return player.seek(seconds); }
  function handleVolumeChange(volume: number) { return player.setVolume(volume); }

  function setPlayerFullscreen(open: boolean, panel = selectedPanel) {
    if (open) selectedPanel = panel;
    isFullscreenOpen = open;
  }
  function handleMouseNavigation(event: MouseEvent) {
    if (event.button !== 3 && event.button !== 4) return;
    event.preventDefault();
    if (event.type !== 'mousedown' || document.querySelector('[role="dialog"], [role="menu"]')) return;
    if (event.button === 3) void goBackFromDetail(); else void goForward();
  }

  function closeMenu(restoreFocus = true) {
    const focus = menuRequest?.focus; menuRequest = null;
    if (restoreFocus && focus?.isConnected) focus.focus();
  }
  function patchPlaylistSnapshots(id: string, removed = false) {
    navigationHistory.mapSnapshots(snapshot => {
      if (snapshot.playlistId?.replace(/^VL/, '') !== id.replace(/^VL/, '')) return snapshot;
      if (removed) return { ...snapshot, view: 'library', primary: 'library', playlistId: null, account: { ...snapshot.account, playlist: null } };
      return { ...snapshot, account: { ...snapshot.account, playlistLoading: false, playlistError: null,
        playlist: accountData.playlist?.id.replace(/^VL/, '') === id.replace(/^VL/, '') ? account.captureNavigation().playlist : null } };
    });
  }
  const menuExecutor = new MenuExecutor({
    rpc: (command, args) => invoke(command, args),
    begin(playIntent) {
      if (playIntent) ++collectionPlayRevision;
      const play = collectionPlayRevision, session = sessionRevision, navigation = navigationRevision;
      return () => play === collectionPlayRevision && session === sessionRevision && navigation === navigationRevision;
    },
    resolvePlaylist: (id, valid) => account.resolvePlaylistTracks(id, valid),
    play: (tracks, source, shuffle, artwork) => playCollection(tracks, 0, source, shuffle, artwork),
    radio: song => player.startRadio(song), enqueue: (tracks, position) => player.enqueue(tracks, position),
    removeQueue: id => player.removeQueueEntry(id), like: song => account.toggleLike(song), saveSong: song => account.toggleSaved(song),
    addPlaylist: (id, song) => account.addToPlaylist(id, song),
    removePlaylistSong: async (id, song) => { await account.removeFromPlaylist(id, song); patchPlaylistSnapshots(id); },
    sortPlaylist: async (id, sort) => { await account.setPlaylistSort(id, sort); patchPlaylistSnapshots(id); },
    async saveCollection(target) {
      if (target.kind !== 'album' && target.kind !== 'playlist') return;
      const detail = target.detail; if (!detail || authStatus.state !== 'ready') throw new Error('Iniciá sesión para guardar esta colección.');
      const id = target.kind === 'album' ? target.detail?.playlistId : target.card.id;
      if (!id) throw new Error('Esta colección no ofrece una acción de biblioteca.');
      const revision = sessionRevision;
      await invoke('toggle_album_library', { playlistId: id, save: !detail.inLibrary });
      if (revision !== sessionRevision) return;
      if (target.kind === 'album') {
        catalog.updateAlbum(album => album.browseId === target.card.id ? { ...album, inLibrary: !detail.inLibrary } : album);
        navigationHistory.mapSnapshots(snapshot => ({ ...snapshot, details: { ...snapshot.details, album: snapshot.details.album?.browseId === target.card.id ? { ...snapshot.details.album, inLibrary: !detail.inLibrary } : snapshot.details.album } }));
        void account.load('albums');
      } else {
        if (lastPlaylistId?.replace(/^VL/, '') === target.card.id.replace(/^VL/, '')) await account.refreshPlaylist(target.card.id);
        patchPlaylistSnapshots(target.card.id); void account.load('playlists');
      }
    },
    async subscribe(artist) {
      const revision = sessionRevision;
      await invoke('set_artist_subscription', { channelId: artist.channelId, subscribe: !artist.subscribed });
      if (revision !== sessionRevision) return;
      catalog.updateArtist(current => current.channelId === artist.channelId ? { ...current, subscribed: !artist.subscribed } : current);
      navigationHistory.mapSnapshots(snapshot => ({ ...snapshot, details: { ...snapshot.details, artist: snapshot.details.artist?.channelId === artist.channelId ? { ...snapshot.details.artist, subscribed: !artist.subscribed } : snapshot.details.artist } }));
      void account.load('artists');
    },
    open: (kind, id) => kind === 'album' ? openAlbumDetail(id) : kind === 'artist' ? openArtistDetail(id) : openPlaylist(id),
    editPlaylist: playlist => { editingPlaylist = playlist; }, deletePlaylist: playlist => { deletingPlaylist = playlist; },
    newPlaylist: song => { createdPlaylistForSong = null; newPlaylistSong = song; },
    async copy(url) { await navigator.clipboard.writeText(url); menuNotice = 'Enlace copiado'; },
  });
  async function executeMenu(action: MenuAction) {
    const request = menuRequest; if (!request || menuActionPending) return;
    closeMenu(false); menuActionPending = true; shellError = null; menuNotice = null;
    const revision = sessionRevision;
    try { await menuExecutor.execute(action, request.target, request.origin); }
    catch (error) { if (revision === sessionRevision) shellError = extractErrorMessage(error, 'No se pudo completar la acción.'); }
    finally {
      menuActionPending = false;
      if (!editingPlaylist && !deletingPlaylist && !newPlaylistSong && request.focus?.isConnected) request.focus.focus();
    }
  }
  function openNowPlayingMenu(event: MouseEvent) {
    if (playbackState.currentTrack) menuService.open(event, { kind: 'song', song: songFromQueue(playbackState.currentTrack) }, { nowPlaying: true });
  }
  function openPlaylistMenu(event: MouseEvent | KeyboardEvent) {
    const detail = accountData.playlist; if (!detail) return;
    menuService.open(event, { kind: 'playlist', card: { id: detail.id, kind: 'playlist', title: detail.title, subtitle: detail.subtitle, thumbnail: detail.thumbnail, duration: null }, detail });
  }
  function openPlaylistTrackMenu(event: MouseEvent | KeyboardEvent, song: SongDto) {
    menuService.open(event, { kind: 'song', song }, { playlistId: accountData.playlist?.id, playlistOwned: accountData.playlist?.owned });
  }
  async function savePlaylistDetails(details: { name: string; description: string; privacy: string }) {
    const playlist = editingPlaylist; if (!playlist) return;
    await account.editPlaylistDetails(playlist.id, details); patchPlaylistSnapshots(playlist.id);
  }
  async function deleteSelectedPlaylist() {
    const playlist = deletingPlaylist; if (!playlist) return;
    await account.deletePlaylist(playlist.id); patchPlaylistSnapshots(playlist.id, true);
    if (activeView === 'playlist_detail' && lastPlaylistId?.replace(/^VL/, '') === playlist.id.replace(/^VL/, '')) openAccountNav('library');
  }
  async function createPlaylistFromSong(details: { name: string; description: string; privacy: string }) {
    const song = newPlaylistSong; if (!song) return;
    const revision = sessionRevision;
    const existingId = createdPlaylistForSong;
    const id = existingId ?? await account.createPlaylist(details.name, details.description, details.privacy);
    if (revision !== sessionRevision) return;
    createdPlaylistForSong = id;
    if (existingId) await account.editPlaylistDetails(id, details);
    if (revision !== sessionRevision) return;
    await account.addToPlaylist(id, song);
  }

  let unlistenAuth: UnlistenFn | null = null;
  let mounted = false;

  onMount(() => {
    mounted = true;
    checkBackendStatus();
    invoke<AuthStatusDto>("get_auth_status").then(applyAuthStatus).catch(() => {});
    window.addEventListener("keydown", handleWindowKeydown);
    window.addEventListener('mousedown', handleMouseNavigation);
    window.addEventListener('auxclick', handleMouseNavigation);

    void player.connect();
    void updater.init();
    const updateCheckTimeout = setTimeout(() => {
      if (mounted) void updater.checkForUpdates(false);
    }, 3500);

    listen<AuthStatusDto>("auth-status-changed", (event) => applyAuthStatus(event.payload))
      .then((unlisten) => { if (mounted) unlistenAuth = unlisten; else unlisten(); });

    return () => {
      mounted = false;
      clearTimeout(updateCheckTimeout);
      account.reset(false);
      window.removeEventListener("keydown", handleWindowKeydown);
      window.removeEventListener('mousedown', handleMouseNavigation);
      window.removeEventListener('auxclick', handleMouseNavigation);
      void player.dispose();
      lyrics.dispose();
      recommendations.dispose();
      home.reset();
      search.reset();
      searchPreview.dispose();
      catalog.reset();
      unlistenAuth?.();
    };
  });
</script>

<div class="app-frame" class:sidebar-collapsed={sidebarCollapsed} class:fullscreen-open={isFullscreenOpen}>
  <TitleBar {canBack} {canForward} {sidebarCollapsed} onBack={goBackFromDetail} onForward={goForward}
    onToggleSidebar={() => { sidebarCollapsed = !sidebarCollapsed; }} />
  <div class="sidebar-host" inert={spotlightOpen}>
  <Sidebar
    activeDestination={activeView === 'playlist_detail' ? lastPlaylistId === 'LM' ? 'likes' : 'playlist' : activeView === 'library' ? 'library' : activeView === 'history' ? 'history' : activeView === 'artist_detail' ? 'artist' : activeView === 'album_detail' || activeView === 'catalog' ? 'album' : primaryNav}
    onHome={() => handleSwitchNav("home")}
    onSearch={() => handleSwitchNav("search")}
    collapsed={sidebarCollapsed}
    auth={authStatus}
    onLogin={handleLogin}
    onCancelLogin={handleCancelLogin}
    onLogout={handleLogout}
    onLikes={() => openAccountNav('likes')} onLibrary={() => openAccountNav('library')} onHistory={() => openAccountNav('history')}
    playlists={accountData.playlists} albums={accountData.albums}
    libraryLoading={accountData.loading.playlists || accountData.loading.albums}
    libraryError={accountData.errors.playlists || accountData.errors.albums}
    selectedCollectionId={activeView === 'playlist_detail' ? lastPlaylistId : activeView === 'album_detail' ? lastAlbumBrowseId : null}
    onOpenPlaylist={openPlaylist} onOpenAlbum={openAlbumDetail}
    onCheckUpdates={() => void updater.checkForUpdates(true)}
  />
  </div>
  <div class="content-column">
<main class="shell" class:home-shell={activeView !== "search_results"} class:search-shell={activeView === 'search_results'} class:player-covered={isFullscreenOpen} inert={isFullscreenOpen || spotlightOpen}>

  {#if (backendStatus && !backendStatus.ready) || statusError}
  <div class="backend-notice" role="status">
    {#if backendStatus && !backendStatus.ready}
      <div class="status-bar">
        <span class="dot error"></span>
        <span class="status-text error-text">{backendStatus.status}</span>
        <button
          type="button"
          class="reconnect-btn"
          disabled={isRetryingInit}
          onclick={handleRetryInit}
        >
          {isRetryingInit ? "Reconectando..." : "Reconectar"}
        </button>
      </div>
    {:else if statusError}
      <div class="status-bar">
        <span class="dot error"></span>
        <span class="status-text error-text">{statusError}</span>
        <button
          type="button"
          class="reconnect-btn"
          disabled={isRetryingInit}
          onclick={handleRetryInit}
        >
          {isRetryingInit ? "Reintentando..." : "Reintentar"}
        </button>
      </div>
    {/if}
  </div>
  {/if}

  {#if accountData.actionError}<div class="account-action-error" role="alert">{accountData.actionError}</div>{/if}
  {#if shellError}<div class="account-action-error shell-error" role="alert">{shellError}<button type="button" aria-label="Cerrar error" onclick={() => shellError = null}>×</button></div>{/if}
  {#if activeView === 'library'}
    <LibraryView loggedIn={authStatus.state === 'ready'} tab={accountData.tab}
      songs={accountData.songs} playlists={accountData.playlists} albums={accountData.albums} artists={accountData.artists}
      loading={accountData.loading[accountData.tab]} loadingMore={accountData.loadingMore} error={accountData.errors[accountData.tab]}
      continuation={accountData.tab === 'songs' ? accountData.songContinuation : null}
      currentTrackId={playbackState.currentTrack?.videoId ?? null} isPlaying={playbackState.isPlaying}
      likedIds={accountData.likedIds} pendingIds={accountData.pendingIds}
      onTab={(tab) => { if (tab !== accountData.tab) pushNavigation(); account.setTab(tab); }} onRefresh={() => account.load(accountData.tab)} onLoadMore={() => account.loadMoreSongs()}
      onPlay={playLibrarySong} onOpenCard={openLibraryCard} onOpenArtist={openArtistDetail} onOpenAlbum={openAlbumDetail}
      onToggleLike={(song) => account.toggleLike(song)} onToggleSaved={(song) => account.toggleSaved(song)}
      onCreatePlaylist={async (title, description) => { await account.createPlaylist(title, description); }} onLogin={handleLogin} />
  {:else if activeView === 'playlist_detail'}
    {#key lastPlaylistId}
      <PlaylistDetailView playlist={accountData.playlist} loading={accountData.playlistLoading} loadingMore={accountData.playlistLoadingMore}
        error={accountData.playlistError} loggedIn={authStatus.state === 'ready'}
        currentTrackId={playbackState.currentTrack?.videoId ?? null} isPlaying={playbackState.isPlaying}
        likedIds={accountData.likedIds} pendingIds={accountData.pendingIds}
        onBack={goBackFromDetail} onRetry={() => lastPlaylistId && account.refreshPlaylist(lastPlaylistId)} onLoadMore={() => account.loadMorePlaylist()}
        onPlay={playPlaylistSong} onToggleLike={(song) => account.toggleLike(song)} onToggleSaved={(song) => account.toggleSaved(song)}
        onOpenMenu={openPlaylistMenu} onTrackMenu={openPlaylistTrackMenu}
        mutationPending={menuActionPending || [...accountData.pendingIds].some(id => id.startsWith('playlist:'))}
        onSortChange={async (sort) => { const id = accountData.playlist?.id; if (id) { await account.setPlaylistSort(id, sort); patchPlaylistSnapshots(id); } }}
        onRemoveTrack={(song) => { const id = accountData.playlist?.id; if (id) void account.removeFromPlaylist(id, song).then(() => patchPlaylistSnapshots(id)).catch(() => {}); }}
        onMoveTrack={(setVideoId, successorSetVideoId) => { const id = accountData.playlist?.id; if (id) void account.movePlaylistTrack(id, setVideoId, successorSetVideoId).then(() => patchPlaylistSnapshots(id)).catch(() => {}); }}
        onToggleLibrary={() => account.togglePlaylistLibrary()} onOpenArtist={openArtistDetail} onOpenAlbum={openAlbumDetail} onLogin={handleLogin} />
    {/key}
  {:else if activeView === 'history'}
    <HistoryView loggedIn={authStatus.state === 'ready'} groups={accountData.history} loading={accountData.loading.history} error={accountData.errors.history}
      currentTrackId={playbackState.currentTrack?.videoId ?? null} isPlaying={playbackState.isPlaying}
      likedIds={accountData.likedIds} pendingIds={accountData.pendingIds} onLogin={handleLogin} onRefresh={() => account.load('history')}
      onPlay={(items, index) => { ++collectionPlayRevision; void playCollection(items, index, {kind:'history',id:'history',title:'Historial'}).catch(() => {}); }}
      onToggleLike={(song) => account.toggleLike(song)} onToggleSaved={(song) => account.toggleSaved(song)}
      onOpenArtist={openArtistDetail} onOpenAlbum={openAlbumDetail} />
  {:else if activeView === "album_detail"}
    {#key lastAlbumBrowseId}
      <AlbumDetailView album={selectedAlbum} isLoading={isAlbumLoading} error={albumError}
        currentTrackId={playbackState.currentTrack?.videoId ?? null} isPlaying={playbackState.isPlaying}
        loggedIn={authStatus.state === "ready"} onBack={goBackFromDetail}
        onRetry={() => lastAlbumBrowseId && openAlbumDetail(lastAlbumBrowseId, undefined, false)}
        onPlay={playAlbum} onOpenArtist={openArtistDetail} onOpenAlbum={openAlbumDetail}
        onOpenCatalog={openCatalog} onToggleLibrary={toggleAlbumLibrary} onOpenPlaylist={openPlaylist}
        onPlaySong={(item) => handlePlaySong(item.id, {title:item.title,artists:item.artists ?? item.subtitle ?? '',thumbnail:item.thumbnail,duration:item.duration,artistRuns:item.artistRuns,artistId:item.artistId,album:item.album,albumId:item.albumId})} />
    {/key}
  {:else if activeView === "artist_detail"}
    {#key lastArtistBrowseId}
      <ArtistDetailView artist={selectedArtist} isLoading={isArtistLoading} error={artistError}
        currentTrackId={playbackState.currentTrack?.videoId ?? null} isPlaying={playbackState.isPlaying}
        loggedIn={authStatus.state === "ready"} onBack={goBackFromDetail}
        onRetry={() => lastArtistBrowseId && openArtistDetail(lastArtistBrowseId, false)}
        onPlay={playArtist} onStartRadio={startArtistRadio} onToggleSubscription={toggleArtistSubscription}
        onOpenAlbum={openAlbumDetail} onOpenArtist={openArtistDetail} onOpenCatalog={openCatalog} onOpenPlaylist={openPlaylist}
        onPlaySong={(item) => handlePlaySong(item.id, {title:item.title,artists:item.artists ?? item.subtitle ?? '',thumbnail:item.thumbnail,duration:item.duration,artistRuns:item.artistRuns,artistId:item.artistId,album:item.album,albumId:item.albumId})} />
    {/key}
  {:else if activeView === "catalog"}
    {#key catalogTarget?.id}
      <CatalogView title={catalogTarget?.title ?? "Catálogo"} items={catalogItems}
        isLoading={isCatalogLoading} error={catalogError} onBack={goBackFromDetail}
        onRetry={() => catalogTarget && openCatalog(catalogTarget.id, catalogTarget.params, catalogTarget.title, false)}
        onOpenAlbum={openAlbumDetail} onOpenArtist={openArtistDetail} onOpenPlaylist={openPlaylist}
        onPlaySong={(item) => handlePlaySong(item.id, {title:item.title,artists:item.artists ?? item.subtitle ?? '',thumbnail:item.thumbnail,duration:item.duration,artistRuns:item.artistRuns,artistId:item.artistId,album:item.album,albumId:item.albumId})} />
    {/key}

  <!-- VISTA 2: Inicio como en macOS -->
  {:else if primaryNav === "home"}
    <HomeView
      chips={homePage?.chips ?? []}
      sections={homePage?.sections ?? []}
      selectedChipParams={homeData.chipParams}
      isLoading={homeData.loading}
      error={homeData.error}
      hasMore={Boolean(homePage?.continuation)}
      isLoadingMore={homeData.loadingMore}
      moreError={homeData.moreError}
      onLoadMore={() => loadMoreHome()}
      onOpenArtist={openArtistDetail}
      onOpenPlaylist={openPlaylist}
      onOpenCatalog={openCatalog}
      onSelectChip={(params) => loadHomePage(params)}
      onRetry={() => loadHomePage(homeData.chipParams)}
      onOpenAlbum={(browseId) => openAlbumDetail(browseId, "home")}
      onPlaySong={(item) => { ++collectionPlayRevision; void player.startRadio(songFromHome(item)).catch(() => {}); }}
    />

  <!-- VISTA 3: BUSCAR (Canciones y Álbumes con detalle W03/W04) -->
  {:else}
    <SearchView data={searchData} backendReady={backendStatus?.ready ?? false} draftQuery={draftQuery} preview={previewData}
      currentTrackId={playbackState.currentTrack?.videoId ?? null} isPlaying={playbackState.isPlaying}
      onSubmit={executeSearch} onRetry={(query: string, mode: SearchMode) => executeSearch(query, mode, false)} onDraftChange={handleDraftChange}
      onPreviewFocus={focusInlinePreview} onPreviewDismiss={dismissInlinePreview}
      onModeChange={handleSwitchSearchMode}
      onPlaySong={(song: SongDto) => { ++collectionPlayRevision; void player.startRadio(song).catch(error => shellError = extractErrorMessage(error, 'No se pudo iniciar la radio.')); }}
      onOpenArtist={openArtistDetail}
      onOpenAlbum={(album: AlbumCardDto) => openAlbumDetail(album.id, "search")}
      onOpenPlaylist={(id: string) => openPlaylist(id)} />
  {/if}
</main>

<div class="player-dock" inert={spotlightOpen}>
  <PlayerBar playback={playerBarState} onTogglePlayback={handleTogglePlay} onRetryPlayback={handleRetryPlayback} onPrevious={handlePrevious} onNext={handleNext} onSeek={handleSeek} onVolumeChange={handleVolumeChange} onSetShuffle={handleSetShuffle} onSetRepeat={handleSetRepeat} fullscreenOpen={isFullscreenOpen} onToggleFullscreen={() => setPlayerFullscreen(!isFullscreenOpen)}
    {selectedPanel} onSelectPanel={(panel) => setPlayerFullscreen(!(isFullscreenOpen && selectedPanel === panel), panel)}
    onOpenArtist={(id) => { void setPlayerFullscreen(false); void openArtistDetail(id); }}
    onOpenAlbum={(id) => { void setPlayerFullscreen(false); void openAlbumDetail(id); }} onOpenMenu={openNowPlayingMenu}
    loggedIn={authStatus.state === 'ready'} liked={accountData.likedIds.has(playbackState.currentTrack?.videoId ?? '')}
    likePending={(accountData.loading.likes && !accountData.likedIds.has(playbackState.currentTrack?.videoId ?? '')) || accountData.pendingIds.has(playbackState.currentTrack?.videoId ?? '')}
    likeError={accountData.actionError || accountData.errors.likes}
    onToggleLike={() => { if (playbackState.currentTrack) void account.toggleLike(playbackState.currentTrack); }} />
</div>
  </div>
  {#if isFullscreenOpen}
    <div class="fullscreen-host" inert={spotlightOpen}>
    <FullscreenNowPlaying playback={playerBarState} onSelectQueue={playQueueIndex} onClose={() => setPlayerFullscreen(false)}
      onMoveQueue={(entryId, beforeEntryId) => player.moveQueueEntry(entryId, beforeEntryId)}
      {lyricsState} {recommendationsState} onSeek={handleSeek} onRetryLyrics={() => { void lyrics.retry(); }}
      onRefreshRecommendations={() => { void recommendations.load(true); }}
      onPlayRecommendation={(song) => { ++collectionPlayRevision; void player.startRadio(song).catch(() => {}); }}
      onEnqueueRecommendation={(song) => { void player.enqueue([song], 'next').catch(error => shellError = extractErrorMessage(error, 'No se pudo agregar a la cola.')); }}
      onSongContextMenu={(event, song) => menuService.open(event, {kind:'song', song})}
      onArtistContextMenu={(event, card) => menuService.open(event, {kind:'artist', card})}
      {selectedPanel} onSelectPanel={(panel) => selectedPanel = panel}
      loggedIn={authStatus.state === 'ready'} liked={accountData.likedIds.has(playbackState.currentTrack?.videoId ?? '')}
      likePending={accountData.pendingIds.has(playbackState.currentTrack?.videoId ?? '')}
      onToggleLike={() => { if (playbackState.currentTrack) void account.toggleLike(playbackState.currentTrack); }}
      likedIds={accountData.likedIds} pendingIds={accountData.pendingIds} likesLoading={accountData.loading.likes}
      onToggleQueueLike={(entry) => { void account.toggleLike(entry); }}
      onDislikeQueueEntry={(entry) => { void account.dislike(entry); void player.removeQueueEntry(entry.entryId).catch(error => shellError = extractErrorMessage(error, 'No se pudo quitar la canción de la cola.')); }}
      onOpenArtist={(id) => { void setPlayerFullscreen(false); void openArtistDetail(id); }}
      onOpenAlbum={(id) => { void setPlayerFullscreen(false); void openAlbumDetail(id); }} onOpenMenu={openNowPlayingMenu}
      onQueueContextMenu={(event, entry) => menuService.open(event, {kind:'song',song:songFromQueue(entry),entryId:entry.entryId})}
      onRetryRadio={() => { void player.retryRadio().catch(error => shellError = extractErrorMessage(error, 'No se pudo reintentar la radio.')); }} />
    </div>
  {/if}
  {#if menuRequest}{#key menuRequest}<ContextMenu x={menuRequest.x} y={menuRequest.y} items={menu} onAction={executeMenu} onClose={() => closeMenu()} />{/key}{/if}
  {#if editingPlaylist}<PlaylistEditorDialog playlist={editingPlaylist} onSave={savePlaylistDetails} onClose={() => editingPlaylist = null} />{/if}
  {#if deletingPlaylist}<PlaylistDeleteDialog playlist={deletingPlaylist} onDelete={deleteSelectedPlaylist} onClose={() => deletingPlaylist = null} />{/if}
  {#if newPlaylistSong}<PlaylistEditorDialog playlist={{id:'',title:'',subtitle:null,thumbnail:null,description:'',items:[],continuation:null,owned:true,inLibrary:true,privacy:'PRIVATE',collaborative:false,sort:'default',sortEditable:false}}
    onSave={createPlaylistFromSong} onClose={() => { newPlaylistSong = null; createdPlaylistForSong = null; }} />{/if}
  {#if menuNotice}<div class="menu-notice" role="status">{menuNotice}<button type="button" aria-label="Cerrar aviso" onclick={() => menuNotice = null}>×</button></div>{/if}
  {#if spotlightOpen}
    <SpotlightSearch preview={previewData} backendReady={backendStatus?.ready ?? false}
      onQueryChange={handleDraftChange} onCommit={(query) => executeSearch(query)} onDismiss={dismissSearchPreview}
      onSelectCard={selectSearchCard} onPlaySong={playSearchPreviewSong} />
  {/if}

  <UpdateModal controller={updater} />
</div>

<style>
  .account-action-error { margin: 10px 32px; padding: 10px 14px; border-radius: 8px; background: #9d303033; color: #ffd5d5; font-size: 13px; }
  .shell-error { position: fixed; z-index: 600; top: 48px; right: 16px; display: flex; gap: 12px; max-width: min(420px, calc(100vw - 64px)); margin: 0; background: #552a30; box-shadow: 0 8px 24px #0006; }
  .shell-error button { border: 0; color: inherit; background: transparent; font: inherit; cursor: pointer; }
  .menu-notice { position: fixed; z-index: 600; bottom: 104px; left: 50%; transform: translateX(-50%); padding: 10px 18px; border: 1px solid #ffffff24; border-radius: 10px; color: white; background: #303038; font: inherit; }
  .menu-notice button { margin-left: 12px; border: 0; color: inherit; background: transparent; font: inherit; cursor: pointer; }
  :global(html), :global(body) {
    width: 100%;
    height: 100%;
    margin: 0;
    overflow: hidden;
  }

  :global(:root) {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    font-size: 15px;
    line-height: 1.5;
    color: #e4e4e7;
    background-color: #1b1b1e;
    user-select: none;
  }

  .app-frame {
    --titlebar-height: 40px;
    --sidebar-width: 230px;
    --sideb-sidebar: #24242a;
    --sideb-accent: #a33d45;
    --sideb-accent-highlight: #d06c70;
    display: flex;
    width: 100%;
    height: 100dvh;
    min-height: 0;
    box-sizing: border-box;
    background: #1b1b1e;
  }

  .app-frame.sidebar-collapsed { --sidebar-width: 60px; }
  .app-frame.fullscreen-open .content-column { overflow: hidden; }
  .sidebar-host { display: contents; }
  .fullscreen-host { display: contents; }

  .content-column {
    flex: 1;
    min-width: 0;
    height: 100%;
    box-sizing: border-box;
    padding-top: var(--titlebar-height);
    overflow-y: auto;
    overflow-x: hidden;
    overflow-anchor: none;
  }


  .shell {
    max-width: 900px;
    margin: 0 auto;
    padding: 2.2rem 1.5rem 6.5rem 1.5rem;
    display: flex;
    flex-direction: column;
    gap: 1.4rem;
  }

  .shell.home-shell {
    max-width: none;
    margin: 0;
    padding: 0;
    gap: 0;
  }

  .shell.search-shell {
    width: 100%;
    max-width: none;
    height: 100%;
    min-height: 0;
    margin: 0;
    padding: 0;
    gap: 0;
  }

  .content-column:has(.search-shell) { overflow: hidden; }

  .shell.player-covered { visibility: hidden; }

  .backend-notice:has(.status-bar) {
    padding: 12px 28px 0;
  }

  .status-bar {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    background: #24242a;
    border: 1px solid #32323a;
    padding: 0.35rem 0.9rem;
    border-radius: 9999px;
    font-size: 0.8rem;
    color: #9ca3af;
  }

  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .dot.error {
    background-color: #ef4444;
    box-shadow: 0 0 8px #ef4444;
  }

  .error-text {
    color: #fca5a5;
  }

  .reconnect-btn {
    background: #3f3f46;
    border: none;
    color: #ffffff;
    border-radius: 6px;
    padding: 0.15rem 0.5rem;
    font-size: 0.75rem;
    cursor: pointer;
    margin-left: 0.25rem;
    transition: background 0.15s;
  }

  .reconnect-btn:hover:not(:disabled) {
    background: #52525b;
  }

  .reconnect-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  /* Vista Detalle de Álbum */
  .player-dock {
    position: fixed;
    z-index: 100;
    left: calc(var(--sidebar-width) + 24px);
    right: 24px;
    bottom: 20px;
    display: flex;
    justify-content: center;
    pointer-events: none;
  }

  .player-dock :global(.player-bar) { pointer-events: auto; }

  @media (max-width: 640px) {
    .shell { padding-bottom: 9rem; }
    .player-dock {
      left: calc(var(--sidebar-width) + 8px);
      right: 8px;
      bottom: 8px;
    }
  }
</style>
