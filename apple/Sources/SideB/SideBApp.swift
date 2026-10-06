import SwiftUI
import SideBCore

@main
struct SideBApp: App {
    @State private var rustCore: SideBCore?
    @State private var playerViewModel = PlayerViewModel()
    @State private var playbackSpaceShortcut = PlaybackSpaceShortcut()
    @State private var cookieStorage = CookieStorage()
    @State private var initError: String?
    @State private var showLoginSheet = false
    @State private var accountViewModel = AccountViewModel()
    @State private var libraryViewModel = LibraryViewModel()
    @State private var homeViewModel = HomeViewModel()
    @State private var homeSessionRevision = 0
    @State private var hasBootstrappedSession = false

    init() {
        do {
            let appSupport = HomeLabConfiguration.appSupportURL
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let core = try SideBCore(dataDir: appSupport.path)
            core.setCipherJsRuntime(runtime: NativeCipherJsRuntime())
            _rustCore = State(initialValue: core)
            _playerViewModel = State(initialValue: PlayerViewModel(rustCore: core))
        } catch {
            _initError = State(initialValue: "Error al iniciar Rust Core: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if let error = initError {
                ContentUnavailableView {
                    Label("Error al iniciar Side B", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(error)
                } actions: {
                    Button("Cerrar aplicación") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(minWidth: 600, minHeight: 400)
                .preferredColorScheme(.dark)
            } else if let core = rustCore {
                WindowRootView(
                    rustCore: core,
                    playerViewModel: playerViewModel,
                    cookieStorage: cookieStorage,
                    accountViewModel: accountViewModel,
                    libraryViewModel: libraryViewModel,
                    homeViewModel: homeViewModel,
                    showLoginSheet: $showLoginSheet,
                    homeSessionRevision: $homeSessionRevision
                )
                .task {
                    guard !hasBootstrappedSession else { return }
                    hasBootstrappedSession = true
                    playerViewModel.rustCore = core
                    playbackSpaceShortcut.install(player: playerViewModel)
                    libraryViewModel.rustCore = core
                    let hasSession = accountViewModel.restoreSession(core: core, storage: cookieStorage)
                    homeViewModel.prepareSession(identity: cookieStorage.homeCacheIdentity(), purgePrevious: false)
                    homeSessionRevision &+= 1
                    if hasSession {
                        await accountViewModel.fetchAccount(core: core)
                        playerViewModel.switchPlaybackSession(to: PlaybackStateStore.identity(for: accountViewModel.account, cookieStorage: cookieStorage))
                        if accountViewModel.isLoggedIn {
                            await libraryViewModel.loadLibrary(core: core)
                        }
                    } else {
                        playerViewModel.switchPlaybackSession(to: "guest")
                    }
                    Task {
                        // Esperar 2 segundos tras el bootstrap para no competir con el arranque de la app
                        try? await Task.sleep(for: .seconds(2))
                        await UpdateService.shared.checkForUpdates(manual: false)

                        // Comprobación periódica cada 24 horas en segundo plano
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(86400))
                            guard !Task.isCancelled else { break }
                            await UpdateService.shared.checkForUpdates(manual: false)
                        }
                    }
                }
                .sheet(isPresented: $showLoginSheet) {
                    LoginSheet(cookieStorage: cookieStorage, rustCore: core) {
                        let loginIdentity = PlaybackStateStore.identity(for: nil, cookieStorage: cookieStorage)
                        playerViewModel.switchPlaybackSession(to: loginIdentity)
                        libraryViewModel.clear()
                        homeViewModel.prepareSession(identity: cookieStorage.homeCacheIdentity())
                        homeSessionRevision &+= 1
                        Task {
                            await accountViewModel.fetchAccount(core: core)
                            guard PlaybackStateStore.identity(for: nil, cookieStorage: cookieStorage) == loginIdentity else { return }
                            playerViewModel.switchPlaybackSession(to: PlaybackStateStore.identity(for: accountViewModel.account, cookieStorage: cookieStorage))
                            await libraryViewModel.loadLibrary(core: core)
                        }
                    }
                }
                .sheet(isPresented: Bindable(UpdateService.shared).isSheetPresented) {
                    UpdateModalSheet()
                }
            }
        }
        .commands {
            SideBMenuCommands()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowBackgroundDragBehavior(.enabled)
    }
}

// MARK: - WindowRootView (Ámbito de Estado por Ventana - A26)

struct WindowRootView: View {
    let rustCore: SideBCore
    var playerViewModel: PlayerViewModel
    var cookieStorage: CookieStorage
    var accountViewModel: AccountViewModel
    var libraryViewModel: LibraryViewModel
    var homeViewModel: HomeViewModel
    @Binding var showLoginSheet: Bool
    @Binding var homeSessionRevision: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Estado de Navegación y Shell específico por ventana
    @State private var isSidebarExpanded: Bool = true
    @State private var titlebarHeight: CGFloat = 0
    @State private var navigationHeaderWidth: CGFloat = 620
    @State private var router = NavigationRouter()
    @State private var isSpotlightPresented: Bool = false
    @State private var isHomeSettingsPresented: Bool = false
    @State private var homeToolbarBottom: CGFloat = 0
    @State private var searchViewModel = SearchViewModel()
    @State private var exploreViewModel = ExploreViewModel()
    @State private var isCreatePlaylistPresented = false
    @State private var pendingPlaylistVideoId: String?
    @State private var playlistCreationError: String?
    @State private var menuContext = AppMenuContext()
    @State private var collectionBackground = CollectionBackgroundController()
    @State private var gesturePresentation = WindowGesturePresentation()

    private var collectionBackgroundIdentity: String? {
        let session = playerViewModel.mediaSessionIdentity.uuidString
        switch router.currentPage {
        case .album(let id): return session + ":album:" + id
        case .playlist(let id): return session + ":playlist:" + id
        default: return nil
        }
    }

    private var pageTopInset: CGFloat {
        switch router.currentPage {
        case .home, .album, .playlist: return 0
        default: return titlebarHeight
        }
    }

    private var sidebarBinding: Binding<Bool> {
        Binding(get: { isSidebarExpanded }, set: { expanded in
            withAnimation(NavPresentation.animation(reduceMotion: reduceMotion)) {
                isSidebarExpanded = expanded
            }
        })
    }

    private var searchBinding: Binding<Bool> {
        Binding(get: { isSpotlightPresented }, set: { presented in
            if presented { playerViewModel.dismissFullscreen() }
            withAnimation(NavPresentation.animation(reduceMotion: reduceMotion)) {
                isSpotlightPresented = presented
            }
        })
    }

    private var windowNavigationToolbar: some View {
                let showsTopNavigation = NavPresentation.showsTopNavigation(
                    sidebarExpanded: isSidebarExpanded,
                    fullscreenPresented: playerViewModel.isFullscreenPresented
                )
                return AnimatedWindowNavigationToolbarView(
                    selection: MainNavigationDestination.selected(history: router.history, currentIndex: router.currentIndex, searchPresented: isSpotlightPresented),
                    isPresented: showsTopNavigation,
                    reduceMotion: reduceMotion,
                    revealProgress: showsTopNavigation ? 1 : 0,
                    router: router,
                    isHistoryDisabled: isSpotlightPresented || playerViewModel.isFullscreenPresented,
                    showsHistory: !playerViewModel.isFullscreenPresented,
                    viewportWidth: navigationHeaderWidth,
                    isHomeSettingsPresented: isHomeSettingsPresented && canPresentHomeSettings,
                    onHistoryFrameChanged: { frame in
                        if abs(homeToolbarBottom - frame.maxY) > 0.5 { homeToolbarBottom = frame.maxY }
                    },
                    onHomeSettings: { setHomeSettingsPresented(!isHomeSettingsPresented) },
                    onHome: { navigateMain(to: .home) },
                    onExplore: { navigateMain(to: .explore(.discover)) },
                    onLibrary: { navigateMain(to: .library) },
                    onSearch: openSearch
                )
                .frame(width: navigationHeaderWidth, height: ShellLayout.toolbarHostHeight)
                .windowGestureRegion(.excluded)
                .animation(NavPresentation.animation(reduceMotion: reduceMotion), value: showsTopNavigation)
    }

    private func openSearch() { searchBinding.wrappedValue = true }

    private var canPresentHomeSettings: Bool {
        HomeSettingsVisibility.canPresent(page: router.currentPage,
                                          fullscreenPresented: playerViewModel.isFullscreenPresented,
                                          searchPresented: isSpotlightPresented)
    }

    private func setHomeSettingsPresented(_ presented: Bool) {
        withAnimation(NavPresentation.animation(reduceMotion: reduceMotion)) {
            isHomeSettingsPresented = presented && canPresentHomeSettings
        }
    }

    private func navigateMain(to destination: PageDestination) {
        playerViewModel.dismissFullscreen()
        searchBinding.wrappedValue = false
        if destination == .library && router.currentPage == .library {
            PlaylistCatalog.shared.invalidateAll()
            NotificationCenter.default.post(name: .sideBLibraryRefreshRequested, object: nil)
        } else {
            router.navigate(to: destination)
        }
    }

    var body: some View {
        ZStack {
            // Pages are the bottom content layer. Their fading backgrounds must
            // not cover the fullscreen backdrop on only one side of the window.
            HStack(alignment: .top, spacing: 0) {
                // Reserve the same width as the floating sidebar overlay.
                if isSidebarExpanded {
                    Color.clear.frame(width: ShellLayout.sidebarReserveWidth(expanded: true))
                }

                // MARK: - Navegador de páginas
                ZStack(alignment: .bottom) {
                    // Capa 1: Navegador de Páginas
                    ZStack(alignment: .topTrailing) {
                        // Contenido de la Página según router.currentPage
                        Group {
                            switch router.currentPage {
                            case .home:
                                HomeView(
                                    playerViewModel: playerViewModel,
                                    homeViewModel: homeViewModel,
                                    sessionRevision: homeSessionRevision,
                                    accountName: accountViewModel.isLoggedIn ? accountViewModel.account?.name : nil,
                                    accountThumbnail: accountViewModel.isLoggedIn ? accountViewModel.account?.thumbnail : nil,
                                    topContentInset: titlebarHeight,
                                    router: router,
                                    onNavigate: { dest in
                                        router.navigate(to: dest)
                                    }
                                )
                            case .explore(let route):
                                ExploreView(route: route, rustCore: rustCore, model: exploreViewModel,
                                    playerViewModel: playerViewModel, router: router, sessionRevision: homeSessionRevision,
                                    isObscured: playerViewModel.isFullscreenPresented || isSpotlightPresented)
                            case .playlist(let id):
                                PlaylistDetailView(
                                    playlistId: id,
                                    rustCore: rustCore,
                                    playerViewModel: playerViewModel,
                                    router: router,
                                    topContentInset: titlebarHeight
                                )
                                .id(id)
                            case .album(let id):
                                AlbumDetailView(
                                    browseId: id,
                                    rustCore: rustCore,
                                    playerViewModel: playerViewModel,
                                    router: router,
                                    topContentInset: titlebarHeight
                                )
                                .id(id)
                            case .artist(let id):
                                ArtistDetailView(
                                    browseId: id,
                                    rustCore: rustCore,
                                    playerViewModel: playerViewModel,
                                    router: router
                                )
                                .id(id)
                            case .catalog(let id, let params, let title):
                                ArtistCatalogView(
                                    browseId: id,
                                    params: params,
                                    title: title,
                                    rustCore: rustCore,
                                    playerViewModel: playerViewModel,
                                    router: router
                                )
                                .id("\(id)|\(params ?? "")")
                            case .history:
                                HistoryView(
                                    rustCore: rustCore,
                                    playerViewModel: playerViewModel,
                                    libraryViewModel: libraryViewModel,
                                    router: router
                                )
                            case .library:
                                LibraryView(
                                    rustCore: rustCore,
                                    playerViewModel: playerViewModel,
                                    libraryViewModel: libraryViewModel,
                                    accountViewModel: accountViewModel,
                                    router: router
                                )
                            case .search(let query):
                                SearchView(
                                    initialQuery: query ?? "",
                                    rustCore: rustCore,
                                    playerViewModel: playerViewModel,
                                    router: router,
                                    searchViewModel: searchViewModel
                                )
                                .id(query ?? "empty_search")
                            default:
                                HomeView(
                                    playerViewModel: playerViewModel,
                                    homeViewModel: homeViewModel,
                                    sessionRevision: homeSessionRevision,
                                    accountName: accountViewModel.isLoggedIn ? accountViewModel.account?.name : nil,
                                    accountThumbnail: accountViewModel.isLoggedIn ? accountViewModel.account?.thumbnail : nil,
                                    topContentInset: titlebarHeight,
                                    router: router,
                                    onNavigate: { dest in
                                        router.navigate(to: dest)
                                    }
                                )
                            }
                        }
                        .padding(.top, pageTopInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .windowGestureRegion(.content, active: !playerViewModel.isFullscreenPresented)
                    .modifier(GesturePageVisibility(presentation: gesturePresentation,
                        fullscreenPresented: playerViewModel.isFullscreenPresented))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .zIndex(0)

            // A separate overlay leaves the feed viewport and player geometry intact.
            // Both fullscreen layers remain above it throughout their transition.
            if isHomeSettingsPresented && canPresentHomeSettings {
                HomeSettingsPanel(homeViewModel: homeViewModel,
                                  titlebarHeight: titlebarHeight,
                                  toolbarBottom: homeToolbarBottom,
                                  onClose: { setHomeSettingsPresented(false) })
                    .padding(ShellLayout.sidebarInset)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .zIndex(0.5)
            }

            FullscreenBackdrop(thumbnail: playerViewModel.currentTrack?.thumbnail,
                               trackID: playerViewModel.currentTrack?.videoId)
                .opacity(playerViewModel.isFullscreenPresented ? 1 : 0)
                .modifier(FullscreenGestureMotion(presentation: gesturePresentation))
                .zIndex(1)

            FullscreenCanvas(viewModel: playerViewModel,
                             isSidebarExpanded: sidebarBinding, router: router)
                .overlay(alignment: .top) {
                    FullscreenDismissGestureIndicatorView(presentation: gesturePresentation)
                        .padding(.top, titlebarHeight + 12)
                }
                .windowGestureRegion(.content, active: playerViewModel.isFullscreenPresented)
                .modifier(FullscreenGestureMotion(presentation: gesturePresentation))
                .zIndex(2)

            // Separate overlays preserve one continuous background behind both
            // sidebar and content throughout fullscreen's presentation.
            HStack(alignment: .top, spacing: 0) {
                if isSidebarExpanded {
                    SidebarView(
                        isExpanded: sidebarBinding,
                        titlebarHeight: titlebarHeight,
                        router: router,
                        accountViewModel: accountViewModel,
                        libraryViewModel: libraryViewModel,
                        rustCore: rustCore,
                        cookieStorage: cookieStorage,
                        playerViewModel: playerViewModel,
                        isSearchPresented: isSpotlightPresented,
                        onOpenSearch: openSearch,
                        onNavigate: navigateMain,
                        onOpenLogin: {
                            showLoginSheet = true
                        },
                        onLogout: {
                            playerViewModel.switchPlaybackSession(to: "guest")
                            libraryViewModel.clear()
                            homeViewModel.prepareSession(identity: cookieStorage.homeCacheIdentity())
                            homeSessionRevision &+= 1
                            router.navigate(to: .home)
                        }
                    )
                    .windowGestureRegion(.excluded)
                    .padding(ShellLayout.sidebarInset)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                    .zIndex(50)
                }
                Spacer(minLength: 0)
            }
            .zIndex(3)

            PlayerBarView(viewModel: playerViewModel, router: router)
                .windowGestureRegion(.excluded)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.leading, ShellLayout.sidebarReserveWidth(expanded: isSidebarExpanded))
                .zIndex(4)

            NavigationGestureIndicatorView(presentation: gesturePresentation)
                .padding(.leading, ShellLayout.sidebarReserveWidth(expanded: isSidebarExpanded))
                .padding(.top, titlebarHeight)
                .zIndex(4.5)

            if isSpotlightPresented {
                SpotlightSearchModal(
                    isPresented: $isSpotlightPresented,
                    searchViewModel: searchViewModel,
                    router: router,
                    playerViewModel: playerViewModel,
                    rustCore: rustCore
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .padding(.leading, ShellLayout.sidebarReserveWidth(expanded: isSidebarExpanded))
                .zIndex(5)
            }
        }
        .background {
            Button("") {
                openSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        }
        .background {
            ZStack {
                if router.currentPage == .home {
                    HomeAmbientBackground(thumbnails: homeViewModel.featured.ambientThumbnails,
                                          sessionRevision: homeSessionRevision,
                                          isObscured: playerViewModel.isFullscreenPresented)
                } else {
                    Color.sidebDarkBackground
                }
                CollectionWindowBackground(controller: collectionBackground,
                                           identity: collectionBackgroundIdentity,
                                           enabled: !playerViewModel.isFullscreenPresented)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .background(WindowConfigurator(
            isFullscreenPresented: playerViewModel.isFullscreenPresented,
            titlebarHeight: $titlebarHeight,
            onContentWidthChange: { width in
                navigationHeaderWidth = max(ShellLayout.navigationMinimumWidth, width - 280)
            }
        ))
        .background(
            WindowNavigationGestureBridge(
                router: router,
                presentation: gesturePresentation,
                isFullscreenPresented: playerViewModel.isFullscreenPresented,
                canHandleGestures: !isSpotlightPresented && !showLoginSheet &&
                    !isCreatePlaylistPresented && !isHomeSettingsPresented,
                reduceMotion: reduceMotion,
                sessionRevision: homeSessionRevision,
                onDismissFullscreen: {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { playerViewModel.isFullscreenPresented = false }
                }
            )
        )
        .environment(\.sideBMenuContext, menuContext)
        .environment(\.collectionBackgroundController, collectionBackground)
        .focusedSceneValue(\.sideBMenuContext, menuContext)
        .onAppear {
            menuContext.player = playerViewModel
            menuContext.router = router
            menuContext.core = rustCore
            menuContext.account = accountViewModel
            menuContext.library = libraryViewModel
            menuContext.cookieStorage = cookieStorage
            menuContext.sidebar = sidebarBinding
            menuContext.search = searchBinding
            menuContext.loginSheet = $showLoginSheet
            menuContext.createPlaylistSheet = $isCreatePlaylistPresented
            let sessionRevision = $homeSessionRevision
            menuContext.onLogout = { [libraryViewModel, homeViewModel, cookieStorage, router] in
                playerViewModel.switchPlaybackSession(to: "guest")
                libraryViewModel.clear()
                homeViewModel.prepareSession(identity: cookieStorage.homeCacheIdentity())
                sessionRevision.wrappedValue &+= 1
                router.navigate(to: .home)
            }
            DispatchQueue.main.async { AppMenuBarOrganizer.normalize() }
        }
        .modifier(HomeSupplementalSync(home: homeViewModel, library: libraryViewModel,
            core: playerViewModel.rustCore, sessionRevision: homeSessionRevision))
        .onChange(of: homeSessionRevision) { _, _ in
            searchViewModel.clear()
            exploreViewModel.prepareSession(homeSessionRevision)
            isSpotlightPresented = false
            setHomeSettingsPresented(false)
        }
        .onChange(of: canPresentHomeSettings) { _, canPresent in
            if !canPresent { setHomeSettingsPresented(false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            DispatchQueue.main.async { AppMenuBarOrganizer.normalize() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            playerViewModel.flushPlaybackState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            playerViewModel.flushPlaybackState()
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                SidebarToolbarToggle(isExpanded: sidebarBinding)
                    .frame(height: ShellLayout.toolbarHostHeight)
            }
            .compatToolbarBackgroundHidden()
            ToolbarItem(placement: .primaryAction) {
                windowNavigationToolbar
            }
            .compatToolbarBackgroundHidden()
        }


        .scrollIndicators(.hidden, axes: .horizontal)
        .compatScrollEdgesHidden()
        .toolbarBackground(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $isCreatePlaylistPresented) {
            PlaylistEditorSheet(core: rustCore, playlist: nil) { id in
                let videoId = pendingPlaylistVideoId
                pendingPlaylistVideoId = nil
                router.navigate(to: .playlist(browseId: id))
                if let videoId {
                    Task {
                        do {
                            try await rustCore.addToPlaylist(playlistId: id, videoId: videoId)
                            NotificationCenter.default.post(name: .sideBPlaylistsChanged, object: nil)
                        } catch {
                            playlistCreationError = error.localizedDescription
                        }
                    }
                }
            }
        }
        .alert("No se pudo añadir la canción", isPresented: Binding(
            get: { playlistCreationError != nil },
            set: { if !$0 { playlistCreationError = nil } }
        )) {
            Button("Aceptar", role: .cancel) { playlistCreationError = nil }
        } message: {
            Text(playlistCreationError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBRequestCreatePlaylist)) { notification in
            guard accountViewModel.isLoggedIn else {
                showLoginSheet = true
                return
            }
            pendingPlaylistVideoId = notification.userInfo?["videoId"] as? String
            isCreatePlaylistPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBPlaylistsChanged)) { _ in
            Task { await libraryViewModel.loadLibrary(core: rustCore) }
        }
        .onChange(of: router.currentPage) { _, _ in
            playerViewModel.dismissFullscreen()
            menuContext.clearSelection()
        }
    }
}

/// Keeps the window shell's view expression small and performs list work outside scroll callbacks.
private struct HomeSupplementalSync: ViewModifier {
    let home: HomeViewModel
    let library: LibraryViewModel
    let core: SideBCore?
    let sessionRevision: Int

    func body(content: Content) -> some View {
        content
            .task(id: "\(sessionRevision)|\(home.featuredCollectionKind.rawValue)|\(home.selectionRevision)") {
                synchronize()
                if let core { await home.loadSupplementalIfNeeded(core: core, library: library) }
            }
            .onChange(of: library.isLoading) { _, loading in
                if !loading, let core {
                    Task { await home.loadSupplementalIfNeeded(core: core, library: library) }
                }
            }
            .onChange(of: library.albums) { _, _ in synchronize() }
            .onChange(of: library.playlists) { _, _ in synchronize() }
            .onChange(of: library.historyGroups) { _, _ in synchronize() }
    }

    private func synchronize() {
        guard core?.isLoggedIn() == true else {
            home.updateSupplemental(albums: [], playlists: [], history: [])
            return
        }
        home.updateSupplemental(albums: library.albums, playlists: library.playlists, history: library.historyGroups)
    }
}
