import SwiftUI
import Darwin
import SideBCore

@main
struct SideBApp: App {
    @State private var rustCore: SideBCore?
    @State private var playerViewModel = PlayerViewModel()
    @State private var playbackSpaceShortcut = PlaybackSpaceShortcut()
    @State private var cookieStorage = CookieStorage()
    @State private var initError: AppMessage?
    @State private var showLoginSheet = false
    @State private var accountViewModel = AccountViewModel()
    @State private var libraryViewModel = LibraryViewModel()
    @State private var homeViewModel = HomeViewModel()
    @State private var homeSessionRevision = 0
    @State private var hasBootstrappedSession = false

    init() {
        if HomeLabConfiguration.enabled && CommandLine.arguments.contains("--localization-diagnostics") {
            let report: [String: Any] = [
                "resourceURL": L10n.resourceURL.path,
                "es": L10n.text("destination.home", language: .es),
                "en": L10n.text("destination.home", language: .en),
                "esPlurals": [0, 1, 2].map { L10n.songCount($0, language: .es) },
                "enPlurals": [0, 1, 2].map { L10n.songCount($0, language: .en) }
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                print("[Localization diagnostics] \(json)")
            }
            Darwin.exit(0)
        }
        do {
            let appSupport = HomeLabConfiguration.appSupportURL
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let core = try SideBCore(dataDir: appSupport.path)
            core.setCipherJsRuntime(runtime: NativeCipherJsRuntime())
            _rustCore = State(initialValue: core)
            _playerViewModel = State(initialValue: PlayerViewModel(rustCore: core))
        } catch {
            _initError = State(initialValue: AppMessage(key: "app.startDetails", args: [error.localizedDescription]))
        }
    }

    private func switchPersonalSession(to identity: String) {
        configurePersonalFeatures(identity: identity, core: rustCore, library: libraryViewModel)
        playerViewModel.switchPlaybackSession(to: identity)
    }

    var body: some Scene {
        WindowGroup {
            if let error = initError {
                ContentUnavailableView {
                    Label(L10n.text("app.startError"), systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(error.text)
                } actions: {
                    Button(L10n.text("app.close")) {
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
                        switchPersonalSession(to: PlaybackStateStore.identity(for: accountViewModel.account, cookieStorage: cookieStorage))
                        if accountViewModel.isLoggedIn {
                            await libraryViewModel.loadLibrary(core: core)
                        }
                    } else {
                        switchPersonalSession(to: "guest")
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
                        switchPersonalSession(to: loginIdentity)
                        libraryViewModel.clear()
                        homeViewModel.prepareSession(identity: cookieStorage.homeCacheIdentity())
                        homeSessionRevision &+= 1
                        Task {
                            await accountViewModel.fetchAccount(core: core)
                            guard PlaybackStateStore.identity(for: nil, cookieStorage: cookieStorage) == loginIdentity else { return }
                            switchPersonalSession(to: PlaybackStateStore.identity(for: accountViewModel.account, cookieStorage: cookieStorage))
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

    @AppStorage(HomeAppearance.solidBackgroundKey, store: HomeAppearance.preferences)
    private var useSolidHomeBackground = false

    // Estado de Navegación y Shell específico por ventana
    @State private var isSidebarExpanded: Bool = true
    @State private var titlebarHeight: CGFloat = 0
    @State private var navigationHeaderWidth: CGFloat = 620
    @State private var router = NavigationRouter()
    @State private var isSpotlightPresented: Bool = false
    @State private var spotlightSearchDraft = ""
    @State private var isNavigationSearchExpanded = false
    @State private var navigationSearchDraft = ""
    @State private var navigationSearchFocusRevision = 0
    @State private var navigationSearchCommands = QuickSearchCommandChannel()
    @State private var navigationSearchSelectionLabel: String?
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
    @State private var spotlightFocusSnapshot: SearchFocusSnapshot?
    @State private var spotlightPreviousPage: PageDestination?

    private func switchPersonalSession(to identity: String) {
        configurePersonalFeatures(identity: identity, core: rustCore, library: libraryViewModel)
        playerViewModel.switchPlaybackSession(to: identity)
    }

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
        default: return navigationContentTopInset
        }
    }

    private var navigationContentTopInset: CGFloat {
        titlebarHeight + ShellLayout.navigationContentSpacing
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
            if presented, !isSpotlightPresented {
                let wasInlineSearch = isNavigationSearchExpanded
                isNavigationSearchExpanded = false
                setHomeSettingsPresented(false)
                searchViewModel.cancelPreview()
                spotlightFocusSnapshot = wasInlineSearch ? nil : SearchFocusSnapshot(window: NSApp.keyWindow)
                spotlightPreviousPage = router.currentPage
                playerViewModel.dismissFullscreen()
            }
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
                let searchSession = homeSessionRevision
                return AnimatedWindowNavigationToolbarView(
                    selection: MainNavigationDestination.selected(history: router.history, currentIndex: router.currentIndex),
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
                    onSearch: openNavigationSearch,
                    isSidebarExpanded: isSidebarExpanded,
                    isSearchExpanded: isNavigationSearchExpanded,
                    searchQuery: navigationSearchDraft,
                    searchFocusRevision: navigationSearchFocusRevision,
                    searchSessionRevision: searchSession,
                    onSearchExpansionChange: { expanded in
                        if expanded { openNavigationSearch() }
                        else { isNavigationSearchExpanded = false }
                    },
                    onSearchQueryChange: { value in
                        guard homeSessionRevision == searchSession, isNavigationSearchExpanded else { return }
                        navigationSearchDraft = value
                    },
                    onSearchSubmit: { _ in sendNavigationSearchCommand(.submit) },
                    onSearchMoveSelection: { delta in sendNavigationSearchCommand(delta < 0 ? .moveUp : .moveDown) },
                    searchSelectionLabel: navigationSearchSelectionLabel,
                    searchResultsContent: navigationSearchResultsContent
                )
                .frame(width: navigationHeaderWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(alignment: .top) {
                    Color.clear.frame(height: ShellLayout.toolbarHostHeight)
                        .windowGestureRegion(.excluded, active: !playerViewModel.isFullscreenPresented)
                }
    }

    private var navigationSearchResultsContent: AnyView? {
        guard isNavigationSearchExpanded, !isSpotlightPresented,
              !playerViewModel.isFullscreenPresented else { return nil }
        return AnyView(
            QuickSearchContentView(isPresented: navigationSearchBinding, draft: $navigationSearchDraft,
                searchViewModel: searchViewModel, router: router, playerViewModel: playerViewModel,
                rustCore: rustCore, style: .anchored, commandChannel: navigationSearchCommands,
                onSelectionLabelChange: { label in
                    if navigationSearchSelectionLabel != label { navigationSearchSelectionLabel = label }
                })
                .id(homeSessionRevision)
                .environment(\.sideBMenuContext, menuContext)
                .preferredColorScheme(.dark)
                .tint(.white)
                .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
                .windowGestureRegion(.excluded)
        )
    }

    private func sendNavigationSearchCommand(_ kind: QuickSearchCommand.Kind) {
        guard isNavigationSearchExpanded else { return }
        navigationSearchCommands.commands.send(kind)
    }

    private var playlistCreationErrorBinding: Binding<Bool> {
        Binding<Bool>(get: { playlistCreationError != nil }, set: { presented in
            if !presented { playlistCreationError = nil }
        })
    }

    private func restoreSpotlightFocus() {
        let snapshot = spotlightFocusSnapshot
        let page = spotlightPreviousPage
        let session = homeSessionRevision
        Task { @MainActor in
            await Task.yield()
            if homeSessionRevision == session, router.currentPage == page,
               !isNavigationSearchExpanded, !isSpotlightPresented,
               snapshot?.window === NSApp.keyWindow { _ = snapshot?.restoreIfUnclaimed() }
        }
        spotlightFocusSnapshot = nil
        spotlightPreviousPage = nil
    }

    private func openSearch() { searchBinding.wrappedValue = true }

    /// The integrated editor and quick Spotlight keep separate drafts and preview owners.
    private func openNavigationSearch() {
        playerViewModel.dismissFullscreen()
        searchBinding.wrappedValue = false
        setHomeSettingsPresented(false)
        if !isNavigationSearchExpanded {
            searchViewModel.cancelPreview()
            navigationSearchSelectionLabel = nil
        }
        isNavigationSearchExpanded = true
        navigationSearchFocusRevision &+= 1
    }

    private var navigationSearchBinding: Binding<Bool> {
        Binding(get: { isNavigationSearchExpanded }, set: { expanded in
            if expanded { openNavigationSearch() }
            else { isNavigationSearchExpanded = false }
        })
    }

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

    private func openHomeSettingsFromMenu() {
        playerViewModel.dismissFullscreen()
        isNavigationSearchExpanded = false
        searchBinding.wrappedValue = false
        if router.currentPage != .home { router.navigate(to: .home) }
        setHomeSettingsPresented(true)
    }

    private func navigateMain(to destination: PageDestination) {
        playerViewModel.dismissFullscreen()
        isNavigationSearchExpanded = false
        searchBinding.wrappedValue = false
        if destination == .library && router.currentPage == .library {
            PlaylistCatalog.shared.invalidateAll()
            NotificationCenter.default.post(name: .sideBLibraryRefreshRequested, object: nil)
        } else {
            router.navigate(to: destination)
        }
    }

    private func configureMenuContext() {
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
        menuContext.onOpenSettings = openHomeSettingsFromMenu
        let sessionRevision = $homeSessionRevision
        menuContext.onLogout = { [libraryViewModel, homeViewModel, cookieStorage, router] in
            switchPersonalSession(to: "guest")
            libraryViewModel.clear()
            homeViewModel.prepareSession(identity: cookieStorage.homeCacheIdentity())
            sessionRevision.wrappedValue &+= 1
            router.navigate(to: .home)
        }
        DispatchQueue.main.async { AppMenuBarOrganizer.normalize() }
    }

    private var windowContent: some View {
        ZStack {
            // Pages are the bottom content layer. Their fading backgrounds must
            // not cover the fullscreen backdrop on only one side of the window.
            HStack(alignment: .top, spacing: 0) {
                // Reserve the same width as the floating sidebar overlay.
                Color.clear
                    .frame(width: ShellLayout.sidebarReserveWidth(expanded: isSidebarExpanded))
                    .allowsHitTesting(false)

                // MARK: - Navegador de páginas
                ZStack(alignment: .bottom) {
                    // Capa 1: Navegador de Páginas
                    ZStack(alignment: .topTrailing) {
                        // Contenido de la Página según router.currentPage
                        RetainedMainPages(page: router.currentPage,
                            isCovered: playerViewModel.isFullscreenPresented || isSpotlightPresented,
                            retainInactiveVisuals: isSpotlightPresented && !playerViewModel.isFullscreenPresented,
                            home: {
                                HomeView(playerViewModel: playerViewModel, homeViewModel: homeViewModel,
                                    sessionRevision: homeSessionRevision,
                                    accountName: accountViewModel.isLoggedIn ? accountViewModel.account?.name : nil,
                                    accountThumbnail: accountViewModel.isLoggedIn ? accountViewModel.account?.thumbnail : nil,
                                    topContentInset: navigationContentTopInset, router: router,
                                    onNavigate: { router.navigate(to: $0) })
                            }, explore: { route in
                                ExploreView(route: route, rustCore: rustCore, model: exploreViewModel,
                                    playerViewModel: playerViewModel, router: router, sessionRevision: homeSessionRevision,
                                    isObscured: playerViewModel.isFullscreenPresented || isSpotlightPresented)
                            }, library: {
                                LibraryView(rustCore: rustCore, playerViewModel: playerViewModel,
                                    libraryViewModel: libraryViewModel, accountViewModel: accountViewModel, router: router)
                            }) {
                            switch router.currentPage {
                            case .home, .explore, .library:
                                EmptyView()
                            case .playlist(let id):
                                PlaylistDetailView(
                                    playlistId: id,
                                    rustCore: rustCore,
                                    playerViewModel: playerViewModel,
                                    router: router,
                                    topContentInset: navigationContentTopInset
                                )
                                .id(id)
                            case .album(let id):
                                AlbumDetailView(
                                    browseId: id,
                                    rustCore: rustCore,
                                    playerViewModel: playerViewModel,
                                    router: router,
                                    topContentInset: navigationContentTopInset
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
                            case .search(let query):
                                SearchView(
                                    initialQuery: query ?? "",
                                    rustCore: rustCore,
                                    playerViewModel: playerViewModel,
                                    router: router,
                                    searchViewModel: searchViewModel
                                )
                                .id(query ?? "empty_search")
                            }
                        }
                        .id(homeSessionRevision)
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
                                  rustCore: rustCore,
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
                        switchPersonalSession(to: "guest")
                        libraryViewModel.clear()
                        homeViewModel.prepareSession(identity: cookieStorage.homeCacheIdentity())
                        homeSessionRevision &+= 1
                        router.navigate(to: .home)
                    }
                )
                // Resolve the moving surface as a unit before passing its
                // position to the fixed-width sidebar's controls.
                .geometryGroup()
                .windowGestureRegion(.excluded, active: isSidebarExpanded)
                .padding(ShellLayout.sidebarInset)
                .offset(x: isSidebarExpanded || reduceMotion ? 0 : -ShellLayout.sidebarReserveWidth(expanded: true))
                .opacity(reduceMotion ? (isSidebarExpanded ? 1 : 0) : 1)
                .allowsHitTesting(isSidebarExpanded)
                .accessibilityHidden(!isSidebarExpanded)
                .zIndex(50)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(isSidebarExpanded)
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
                    rustCore: rustCore,
                    persistedDraft: $spotlightSearchDraft,
                    onRestoreFocus: restoreSpotlightFocus
                )
                .id(homeSessionRevision)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .padding(.leading, ShellLayout.sidebarReserveWidth(expanded: isSidebarExpanded))
                .zIndex(5)
            }
        }
    }

    private var configuredWindowContent: some View {
        windowContent
        // AppKit changes the automatic segmented-control renderer inside an
        // NSToolbar item. Keep the prototype's native glass/lens in the content
        // plane; the header still aligns its capsules in window coordinates.
        .overlay(alignment: .top) {
            windowNavigationToolbar
        }
        .background {
            Button("") {
                openNavigationSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        }
        .background {
            ZStack {
                Color.sidebDarkBackground
                if useSolidHomeBackground {
                    AppTheme.homeSolidBackground
                        .ignoresSafeArea(.container, edges: .top)
                        .opacity(router.currentPage == .home ? 1 : 0)
                } else {
                    HomeAmbientBackground(thumbnails: homeViewModel.featured.ambientThumbnails,
                                              sessionRevision: homeSessionRevision,
                                              isObscured: router.currentPage != .home || playerViewModel.isFullscreenPresented || isSpotlightPresented)
                        .opacity(router.currentPage == .home ? 1 : 0)
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
                navigationHeaderWidth = max(ShellLayout.navigationMinimumWidth, width)
            }
        ))
        .background(
            WindowNavigationGestureBridge(
                router: router,
                presentation: gesturePresentation,
                isFullscreenPresented: playerViewModel.isFullscreenPresented,
                canHandleGestures: !isSpotlightPresented && !isNavigationSearchExpanded && !showLoginSheet &&
                    !isCreatePlaylistPresented && !isHomeSettingsPresented,
                reduceMotion: reduceMotion,
                sessionRevision: homeSessionRevision,
                volumePlayer: playerViewModel,
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
        .onAppear(perform: configureMenuContext)
    }

    var body: some View {
        configuredWindowContent
        .modifier(HomeSupplementalSync(home: homeViewModel, library: libraryViewModel,
            core: playerViewModel.rustCore, sessionRevision: homeSessionRevision))
        .onChange(of: homeSessionRevision) { _, _ in
            spotlightFocusSnapshot = nil
            spotlightSearchDraft = ""
            spotlightPreviousPage = nil
            searchViewModel.clear()
            exploreViewModel.prepareSession(homeSessionRevision)
            isSpotlightPresented = false
            isNavigationSearchExpanded = false
            navigationSearchDraft = ""
            navigationSearchSelectionLabel = nil
            setHomeSettingsPresented(false)
        }
        .onChange(of: playerViewModel.isFullscreenPresented) { _, presented in
            if presented { isNavigationSearchExpanded = false }
        }
        .onChange(of: isSpotlightPresented) { _, presented in
            if presented { isNavigationSearchExpanded = false }
        }
        .onChange(of: canPresentHomeSettings) { _, canPresent in
            if !canPresent { setHomeSettingsPresented(false) }
        }
        .onChange(of: L10n.revision) { _, _ in
            DispatchQueue.main.async { AppMenuBarOrganizer.normalize() }
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
        .alert(L10n.text("app.addSongError"), isPresented: playlistCreationErrorBinding) {
            Button(L10n.text("app.accept"), role: .cancel) { playlistCreationError = nil }
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
            isNavigationSearchExpanded = false
            menuContext.clearSelection()
            // A retained hidden page must not keep receiving keyboard input.
            NSApp.keyWindow?.makeFirstResponder(nil)
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

/// Configure account-scoped feature services before library requests or playback restore.
@MainActor
private func configurePersonalFeatures(identity: String, core: SideBCore?, library: LibraryViewModel) {
    library.configureAccount(identity: identity)
    guard let core else { return }
    FeaturedArtistResolver.shared.configure(search: { query in
        try await core.searchCards(query: query, category: "artists")
            .filter { $0.kind == "artist" && !$0.id.isEmpty }
            .map { FeaturedArtistCandidate(id: $0.id, name: $0.title, subtitle: $0.subtitle) }
    }, scope: identity)
}
