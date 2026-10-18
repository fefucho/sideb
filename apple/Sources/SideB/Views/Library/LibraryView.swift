import SwiftUI
import AppKit
import SideBCore

struct LibraryView: View {
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    @Bindable var libraryViewModel: LibraryViewModel
    @Bindable var accountViewModel: AccountViewModel
    @Bindable var router: NavigationRouter

    @Environment(\.sideBMenuContext) private var menuContext
    @State private var collectionPosition = ScrollPosition(y: 0)
    @State private var cardProjection = LibraryCardProjectionCache()
    @State private var needsRefresh = false
    @State private var songsHeaderHeight: CGFloat = 220
    @Environment(\.sideBPageIsActive) private var pageIsActive
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 18)]

    var body: some View {
        let _ = L10n.revision
        Group {
            if !accountViewModel.isLoggedIn {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        libraryPageHeader
                        VStack(spacing: 14) {
                            emptyState(L10n.text("library.login_required"), icon: "person.crop.circle")
                            Button(L10n.text("account.sign_in")) { menuContext?.loginSheet?.wrappedValue = true }
                                .buttonStyle(SideBControlStyle(prominent: true))
                        }
                        .frame(maxWidth: .infinity).frame(minHeight: 280).padding(.bottom, 130)
                    }
                }
            } else {
                switch libraryViewModel.selectedPageTab {
                case .all: overviewContent
                case .songs: songsContent
                case .playlists: cardsContent(libraryViewModel.playlists, icon: "music.note.list", title: L10n.text("library.empty.playlists"))
                case .albums: cardsContent(libraryViewModel.providerAlbums, icon: "opticaldisc", title: L10n.text("library.empty.albums"))
                case .artists: cardsContent(libraryViewModel.artists, icon: "person.crop.circle", title: L10n.text("library.empty.artists"))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: LibraryPageRequest(tab: libraryViewModel.selectedPageTab, active: pageIsActive)) {
            guard pageIsActive, accountViewModel.isLoggedIn else { return }
            if needsRefresh {
                needsRefresh = false
                await reloadSelectedTab()
            } else { await libraryViewModel.ensureSelectedPageTab(core: rustCore) }
        }
        .onChange(of: libraryViewModel.accountRevision) { _, _ in collectionPosition.scrollTo(y: 0) }
        .onChange(of: libraryViewModel.libraryQuery) { _, _ in libraryViewModel.cancelLibrarySearch() }
        .onChange(of: libraryViewModel.selectedPageTab) { _, _ in
            libraryViewModel.cancelLibrarySearch()
            collectionPosition.scrollTo(y: libraryViewModel.collectionScrollOffsets[libraryViewModel.selectedPageTab.rawValue] ?? 0)
        }
        .onChange(of: accountViewModel.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                requestRefresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBLibraryRefreshRequested)) { _ in
            requestRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBSongLibraryChanged)) { _ in
            if libraryViewModel.selectedPageTab == .songs {
                requestRefresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBLibraryAlbumToggled)) { _ in
            if libraryViewModel.selectedPageTab == .songs {
                requestRefresh()
            }
        }
    }

    private var songsContent: some View {
        let tracks = libraryViewModel.presentedSongs
        return NativeTrackTableView(
            tracks: tracks,
            currentTrackVideoId: playerViewModel.currentTrack?.videoId,
            isPlaying: playerViewModel.isPlaying,
            playerViewModel: playerViewModel,
            router: router,
            rustCore: rustCore,
            likedVideoIds: playerViewModel.likedVideoIds,
            menuOrigin: { _ in .library },
            onPlayTrack: { index in
                playerViewModel.playPlaylist(
                    browseId: "FEmusic_liked_videos", title: L10n.text("library.title"),
                    tracks: tracks, startingAt: index,
                    continuation: !libraryViewModel.hasLibraryQuery && libraryViewModel.libraryOrder == "original" ? libraryViewModel.songsContinuation : nil
                )
            },
            onLikeTrack: { playerViewModel.toggleTrackLike($0) },
            onDislikeTrack: { playerViewModel.dislikeTrack($0) },
            onNearBottom: {
                if pageIsActive && !libraryViewModel.hasLibraryQuery { Task { await libraryViewModel.loadMoreSongs(core: rustCore) } }
            },
            scrollingHeader: AnyView(libraryPageHeader
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.sideBPageIsActive, pageIsActive)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if height > 0, abs(songsHeaderHeight - height) > 0.5 { songsHeaderHeight = ceil(height) }
                }),
            scrollingHeaderHeight: songsHeaderHeight,
            footer: tracks.isEmpty || libraryViewModel.songsErrorMessage != nil ? AnyView(songsStatus(tracks: tracks)) : nil,
            footerHeight: tracks.isEmpty ? 300 : 80,
            scrollOffset: libraryScrollOffset(for: "Canciones")
        )
        .id(libraryViewModel.accountRevision)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if libraryViewModel.isSongsLoadingMore {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("library.loading_more_songs"))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 110)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    @ViewBuilder
    private func songsStatus(tracks: [SongItemRecord]) -> some View {
        if libraryViewModel.isSongsLoading && libraryViewModel.songs.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = libraryViewModel.songsErrorMessage, libraryViewModel.songs.isEmpty {
            DetailErrorStateView(title: L10n.text("library.error.load_songs"), message: error) {
                Task { await libraryViewModel.loadSongs(core: rustCore) }
            }
        } else if tracks.isEmpty {
            VStack(spacing: 12) {
                emptyState(L10n.text(libraryViewModel.songs.isEmpty && libraryViewModel.songsContinuation == nil && !libraryViewModel.hasLibraryQuery ? "library.empty.songs" : "library.search.empty"), icon: "music.note")
                if libraryViewModel.songsContinuation != nil {
                    Text(L10n.text("library.search.pending")).font(.caption).foregroundStyle(.secondary)
                    Button(L10n.text("library.search.rest")) { Task { await libraryViewModel.searchRemainingSongs(core: rustCore) } }
                }
                if let error = libraryViewModel.songsErrorMessage {
                    songsUpdateError(error)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = libraryViewModel.songsErrorMessage {
            songsUpdateError(error)
        }
    }

    private func songsUpdateError(_ error: String) -> some View {
        HStack(spacing: 10) {
            Text(L10n.text("library.error.update_songs", args: [error]))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Button(L10n.text("library.retry")) { Task { await libraryViewModel.loadSongs(core: rustCore) } }
                .buttonStyle(SideBControlStyle())
        }
        .padding(.horizontal, 38.4).padding(.vertical, 8)
    }

    private func cardsContent(_ source: [BrowseCardRecord], icon: String, title: String) -> some View {
        let cards = cardProjection.cards(source, query: libraryViewModel.libraryQuery, order: libraryViewModel.effectiveLibraryOrder) {
            libraryViewModel.presentedCards(source)
        }
        let tab = libraryViewModel.selectedPageTab.rawValue
        return LibraryCollectionViewport(cards: cards, tab: tab, accountRevision: libraryViewModel.accountRevision,
            list: libraryViewModel.collectionList,
            scrollOffset: libraryScrollOffset(for: tab),
            scrollingHeader: AnyView(VStack(alignment: .leading, spacing: 0) {
                libraryPageHeader
                cardsStatus(source: source, cards: cards, icon: icon, title: title)
            }.environment(\.sideBPageIsActive, pageIsActive)),
            pinned: Set(libraryViewModel.pins.map(\.key)),
            isObscured: !pageIsActive || playerViewModel.isFullscreenPresented,
            queueContext: playerViewModel.queueManager.context, isPlaying: playerViewModel.isPlaying,
            loadingAlbumID: playerViewModel.loadingRecommendedAlbumID,
            loadingPlaylistID: playerViewModel.loadingRecommendedPlaylistID,
            onOpen: openLibraryCard,
            onPlay: { playerViewModel.activateMediaCollection(id: $0.id, kind: $0.kind) },
            onPin: { libraryViewModel.togglePin($0) },
            menuProvider: { card in
                if card.kind == "artist" {
                    let menu = AppContextMenuFactory.shared.buildArtistNSMenu(channelId: card.id, name: card.title,
                        thumbnail: card.thumbnail, radioPlaylistId: nil, origin: .library,
                        player: playerViewModel, router: router, core: rustCore)
                    menu.addItem(.separator())
                    menu.addItem(LibraryPinMenuItem(title: pinTitle(card)) { libraryViewModel.togglePin(card) })
                    return menu
                }
                return libraryCardMenu(card, kind: card.kind)
            })
    }

    @ViewBuilder
    private func cardsStatus(source: [BrowseCardRecord], cards: [BrowseCardRecord], icon: String, title: String) -> some View {
        if (libraryViewModel.isLoading || libraryViewModel.selectedPageTab == .artists && libraryViewModel.isArtistsLoading) && source.isEmpty {
            ProgressView().frame(maxWidth: .infinity).frame(height: 280)
        } else if let error = cardError, source.isEmpty {
            DetailErrorStateView(title: L10n.text("library.error.load"), message: error) {
                Task { await reloadSelectedTab() }
            }.frame(height: 300)
        } else if cards.isEmpty {
            emptyState(!libraryViewModel.hasLibraryQuery ? title : L10n.text("library.search.empty"), icon: icon).frame(height: 280)
        } else {
            if libraryViewModel.isLoading || libraryViewModel.isArtistsLoading {
                Text(L10n.text("common.loading")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 38.4)
            }
            if let error = cardError {
                HStack(spacing: 12) {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button(L10n.text("library.retry")) { Task { await reloadSelectedTab() } }.buttonStyle(SideBControlStyle())
                }.padding(.horizontal, 38.4)
            }
        }
    }

    private func libraryScrollOffset(for tab: String) -> Binding<CGFloat> {
        let revision = libraryViewModel.accountRevision
        return Binding(get: {
            guard libraryViewModel.accountRevision == revision else { return 0 }
            return libraryViewModel.collectionScrollOffsets[tab] ?? 0
        }, set: { offset in
            // Native table scroll notifications are delivered asynchronously.
            guard libraryViewModel.accountRevision == revision else { return }
            libraryViewModel.collectionScrollOffsets[tab] = offset
        })
    }

    private func openLibraryCard(_ card: BrowseCardRecord) {
        switch card.kind {
        case "artist": router.navigate(to: .artist(browseId: card.id))
        case "album": router.navigate(to: .album(browseId: card.id))
        default: router.navigate(to: .playlist(browseId: card.id))
        }
    }

    private func libraryCard(_ card: BrowseCardRecord, icon: String) -> some View {
        let isArtist = card.kind == "artist"
        let kind = card.kind == "album" ? "album" : "playlist"
        return VStack(alignment: .leading, spacing: 7) {
            if isArtist {
                Button { openLibraryCard(card) } label: {
                    libraryArtwork(card, icon: icon, isArtist: true)
                }.buttonStyle(.plain).mediaCardFocusControl()
            } else {
                MediaArtworkControls(
                    isCollection: true,
                    isActive: MediaPlaybackIdentity.isCollectionActive(kind: kind, id: card.id,
                                                                       context: playerViewModel.queueManager.context),
                    isPlaying: playerViewModel.isPlaying,
                    isLoading: (kind == "album" ? playerViewModel.loadingRecommendedAlbumID : playerViewModel.loadingRecommendedPlaylistID)
                        .map(MenuIDNormalizer.normalize) == MenuIDNormalizer.normalize(card.id),
                    showsIndicator: true, accessibilityTitle: card.displayTitle,
                    onOpen: { openLibraryCard(card) },
                    onPlay: { playerViewModel.activateMediaCollection(id: card.id, kind: kind) },
                    menuProvider: { libraryCardMenu(card, kind: kind) }
                ) {
                    libraryArtwork(card, icon: icon, isArtist: false)
                }.aspectRatio(1, contentMode: .fit)
            }
            Button { openLibraryCard(card) } label: {
                Text(card.displayTitle).font(.system(size: 13, weight: .semibold))
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).mediaCardFocusControl()
            if let subtitle = card.subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    .allowsHitTesting(false)
            }
            pinControls(card)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .mediaCardActivation(label: L10n.text("library.open_card", args: [card.displayTitle])) { openLibraryCard(card) }
        .mediaCardSurface()
        .browseCardContextMenu(card: card, player: playerViewModel, router: router, core: rustCore, origin: .library)
    }

    private func libraryArtwork(_ card: BrowseCardRecord, icon: String, isArtist: Bool) -> some View {
        CachedAsyncImage(url: ImageURLHelper.optimizedThumbnailURL(from: card.thumbnail, targetPixelSize: 400),
                         targetSize: CGSize(width: 200, height: 200)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: { artworkPlaceholder(icon) }
        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: isArtist ? 100 : AppTheme.artworkCardRadius))
    }

    private func libraryCardMenu(_ card: BrowseCardRecord, kind: String) -> NSMenu {
        let menu: NSMenu
        if kind == "album" {
            menu = AppContextMenuFactory.shared.buildAlbumNSMenu(browseId: card.id, playlistId: nil,
                title: card.title, artist: card.subtitle, thumbnail: card.thumbnail,
                origin: .library, player: playerViewModel, router: router, core: rustCore)
        } else {
        menu = AppContextMenuFactory.shared.buildPlaylistNSMenu(id: card.id, title: card.title,
            subtitle: card.subtitle, thumbnail: card.thumbnail, origin: .library,
            player: playerViewModel, router: router, core: rustCore)
        }
        menu.addItem(.separator())
        menu.addItem(LibraryPinMenuItem(title: pinTitle(card)) { libraryViewModel.togglePin(card) })
        return menu
    }

    private var cardError: String? {
        switch libraryViewModel.selectedPageTab {
        case .playlists: libraryViewModel.playlistsErrorMessage
        case .albums: libraryViewModel.albumsErrorMessage
        case .artists: libraryViewModel.artistsErrorMessage
        case .songs: nil
        case .all: libraryViewModel.errorMessage
        }
    }

    private func artworkPlaceholder(_ icon: String) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .overlay { Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.secondary) }
            .clipShape(RoundedRectangle(cornerRadius: libraryViewModel.selectedPageTab == .artists ? 100 : AppTheme.artworkCardRadius))
    }

    private func emptyState(_ title: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 38)).foregroundStyle(.tertiary)
            Text(title).font(.headline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reloadSelectedTab() async {
        guard accountViewModel.isLoggedIn else { return }
        await libraryViewModel.reloadSelectedPageTab(core: rustCore)
    }

    private func requestRefresh() {
        guard pageIsActive else { needsRefresh = true; return }
        Task { await reloadSelectedTab() }
    }
}

private struct LibraryPageRequest: Equatable {
    let tab: LibraryPageTab
    let active: Bool
}

private extension LibraryView {
    var libraryPageHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            libraryHeader
            categoryNavigation
            if accountViewModel.isLoggedIn { libraryToolbar }
        }
    }

    var isRefreshingSelectedTab: Bool {
        switch libraryViewModel.selectedPageTab {
        case .songs: libraryViewModel.isSongsLoading
        case .artists: libraryViewModel.isArtistsLoading
        case .all: libraryViewModel.isLoading || libraryViewModel.isArtistsLoading || libraryViewModel.isSongsLoading
        case .albums, .playlists: libraryViewModel.isLoading
        }
    }

    var libraryHeader: some View {
        Text(L10n.text("library.title"))
            .font(.system(size: 38.4, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 38.4)
            .padding(.top, 28)
            .padding(.bottom, 22)
    }

    var categoryNavigation: some View {
        HStack(alignment: .center, spacing: 16) {
            ScrollView(.horizontal) {
                HStack(spacing: SideBControlMetrics.categorySpacing) {
                    ForEach(LibraryPageTab.allCases) { tab in
                        let selected = libraryViewModel.selectedPageTab == tab
                        Button { libraryViewModel.selectedPageTab = tab } label: {
                            SideBControlLabel(title: tab.displayTitle, symbol: categorySymbol(tab))
                        }
                        .buttonStyle(SideBControlStyle(size: .category, selected: selected))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .windowGestureRegion(.horizontalContent, active: pageIsActive && !playerViewModel.isFullscreenPresented)
            .frame(height: SideBControlMetrics.categoryHeight + 8)

            if accountViewModel.isLoggedIn {
                libraryActions
                    .fixedSize()
            }
        }
        .padding(.horizontal, 38.4)
        .padding(.bottom, 16)
    }

    private var libraryActions: some View {
        HStack(spacing: 16) {
            Button {
                NotificationCenter.default.post(name: .sideBRequestCreatePlaylist, object: nil)
            } label: {
                SideBControlLabel(title: L10n.text("library.new_playlist"), symbol: "plus")
            }
            .buttonStyle(SideBControlStyle())
            .help(L10n.text("library.create_playlist"))
            Button { Task { await reloadSelectedTab() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(SideBControlStyle(iconOnly: true, loading: isRefreshingSelectedTab))
            .disabled(isRefreshingSelectedTab)
            .help(L10n.text("library.refresh"))
            .accessibilityLabel(L10n.text("library.refresh"))
        }
    }

    func categorySymbol(_ tab: LibraryPageTab) -> String {
        switch tab {
        case .all: "square.grid.2x2"
        case .songs: "music.note"
        case .playlists: "music.note.list"
        case .albums: "opticaldisc"
        case .artists: "person.2"
        }
    }

    var libraryToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    librarySearchField
                    Spacer(minLength: 16)
                    libraryPresentationControls
                }
                VStack(alignment: .leading, spacing: 12) {
                    librarySearchField
                    HStack { Spacer(minLength: 0); libraryPresentationControls }
                }
            }
            if libraryViewModel.hasLibraryQuery {
                HStack(spacing: 12) {
                    Text(L10n.text(libraryViewModel.selectedPageTab == .songs ? (libraryViewModel.songsContinuation == nil ? "library.search.complete" : "library.search.loaded") : "library.search.collections", args: [String(libraryViewModel.songs.count)]))
                        .font(.caption).foregroundStyle(.secondary)
                    if libraryViewModel.selectedPageTab == .songs, libraryViewModel.songsContinuation != nil {
                        if libraryViewModel.isSearchingRest {
                            ProgressView().controlSize(.small)
                            Button(L10n.text("library.search.cancel")) { libraryViewModel.cancelLibrarySearch() }.buttonStyle(SideBControlStyle())
                        } else {
                            Button(L10n.text(libraryViewModel.searchedPages == 0 ? "library.search.rest" : "library.search.continue")) { Task { await libraryViewModel.searchRemainingSongs(core: rustCore) } }
                                .buttonStyle(SideBControlStyle())
                                .disabled(libraryViewModel.isSongsLoading || libraryViewModel.isSongsLoadingMore)
                        }
                    }
                    if libraryViewModel.searchedPages > 0 { Text(L10n.text("library.search.progress", args: [String(libraryViewModel.searchedPages)])).font(.caption) }
                }
            }
        }
        .padding(.horizontal, 38.4)
        .padding(.bottom, 16)
    }

    var librarySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L10n.text("library.search.placeholder"), text: $libraryViewModel.libraryQuery)
                .textFieldStyle(.plain)
                .accessibilityLabel(L10n.text("library.search.placeholder"))
            if !libraryViewModel.libraryQuery.isEmpty {
                Button { libraryViewModel.libraryQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("detail.search.clear"))
            }
        }
        .font(.system(size: 14.4))
        .padding(.horizontal, 14)
        .frame(minWidth: 180, idealWidth: 300, maxWidth: 320)
        .frame(height: 40)
        .compatGlass(interactive: true, in: Capsule())
    }

    var libraryPresentationControls: some View {
        HStack(spacing: 10) {
            Menu {
                libraryOrderOption("original")
                libraryOrderOption("name")
                if libraryViewModel.selectedPageTab == .songs || libraryViewModel.selectedPageTab == .albums {
                    libraryOrderOption("artist")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(libraryOrderTitle(libraryViewModel.effectiveLibraryOrder))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .sidebControlLabel()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(L10n.text("library.sort.label"))
            if libraryViewModel.selectedPageTab != .songs {
                Button { libraryViewModel.collectionList.toggle() } label: {
                    Image(systemName: libraryViewModel.collectionList ? "square.grid.2x2" : "list.bullet")
                }
                .buttonStyle(SideBControlStyle(iconOnly: true))
                .help(L10n.text(libraryViewModel.collectionList ? "library.view.grid" : "library.view.list"))
                .accessibilityLabel(L10n.text(libraryViewModel.collectionList ? "library.view.grid" : "library.view.list"))
            }
        }
    }

    func libraryOrderTitle(_ order: String) -> String {
        switch order {
        case "name": L10n.text("library.sort.name")
        case "artist": L10n.text("library.sort.artist")
        default: L10n.text("library.sort.original")
        }
    }

    func libraryOrderOption(_ order: String) -> some View {
        Button { libraryViewModel.libraryOrder = order } label: {
            if libraryViewModel.effectiveLibraryOrder == order {
                Label(libraryOrderTitle(order), systemImage: "checkmark")
            } else {
                Text(libraryOrderTitle(order))
            }
        }
    }

    var overviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                libraryPageHeader
                VStack(alignment: .leading, spacing: 24) {
                    if !libraryViewModel.pinnedCards.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(L10n.text("library.pinned"), systemImage: "pin.fill").font(.title3.bold())
                            overviewCardsLayout(libraryViewModel.pinnedCards.filter { libraryViewModel.matches($0.title, $0.subtitle) }, icon: "pin")
                        }
                    }
                    overviewSection(.playlists, cards: libraryViewModel.playlists, icon: "music.note.list")
                    overviewSection(.albums, cards: libraryViewModel.providerAlbums, icon: "opticaldisc")
                    overviewSection(.artists, cards: libraryViewModel.artists, icon: "person.crop.circle")
                    if libraryViewModel.isLoading || libraryViewModel.isArtistsLoading { ProgressView() }
                    if let error = libraryViewModel.errorMessage ?? libraryViewModel.artistsErrorMessage {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button(L10n.text("library.retry")) { Task { await reloadSelectedTab() } }.buttonStyle(SideBControlStyle())
                    } else if libraryViewModel.playlists.isEmpty && libraryViewModel.providerAlbums.isEmpty && libraryViewModel.artists.isEmpty && !libraryViewModel.isLoading && !libraryViewModel.isArtistsLoading {
                        Text(L10n.text("library.empty.all")).foregroundStyle(.secondary)
                    } else if libraryViewModel.hasLibraryQuery && libraryViewModel.presentedCards(libraryViewModel.playlists + libraryViewModel.providerAlbums + libraryViewModel.artists).isEmpty {
                        Text(L10n.text("library.search.empty")).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 38.4).padding(.top, 20).padding(.bottom, 130)
            }
        }
        .scrollPosition($collectionPosition)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in libraryViewModel.collectionScrollOffsets["Todo"] = offset }
        .onAppear { collectionPosition.scrollTo(y: libraryViewModel.collectionScrollOffsets["Todo"] ?? 0) }
    }
    @ViewBuilder func overviewSection(_ tab: LibraryPageTab, cards: [BrowseCardRecord], icon: String) -> some View {
        let matching = libraryViewModel.presentedCards(cards)
        if !matching.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(tab.displayTitle).font(.title3.bold())
                    Spacer()
                    Button { libraryViewModel.selectedPageTab = tab } label: {
                        HStack(spacing: 6) {
                            Text(L10n.text("library.see_all"))
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        }.font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                overviewCardsLayout(Array(matching.prefix(6)), icon: icon)
            }
        }
    }
    @ViewBuilder func overviewCardsLayout(_ cards: [BrowseCardRecord], icon: String) -> some View {
        if libraryViewModel.collectionList {
            cardsLayout(cards, icon: icon)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(cards, id: \.libraryIdentity) { card in
                        libraryCard(card, icon: icon).frame(width: 180)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .windowGestureRegion(.horizontalContent, active: pageIsActive && !playerViewModel.isFullscreenPresented)
        }
    }
    @ViewBuilder func cardsLayout(_ cards: [BrowseCardRecord], icon: String) -> some View {
        if libraryViewModel.collectionList {
            LazyVStack(spacing: 8) {
                ForEach(cards, id: \.libraryIdentity) { card in
                    HStack(spacing: 12) {
                        libraryArtwork(card, icon: icon, isArtist: card.kind == "artist").frame(width: 52, height: 52)
                        Button { openLibraryCard(card) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                if let subtitle = card.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        if card.kind != "artist" {
                            Button { playerViewModel.activateMediaCollection(id: card.id, kind: card.kind) } label: { Image(systemName: MediaPlaybackIdentity.isCollectionActive(kind: card.kind, id: card.id, context: playerViewModel.queueManager.context) && playerViewModel.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.plain).accessibilityLabel(L10n.text(MediaPlaybackIdentity.isCollectionActive(kind: card.kind, id: card.id, context: playerViewModel.queueManager.context) && playerViewModel.isPlaying ? "player.pause" : "player.play"))
                        }
                        pinControls(card)
                    }.padding(8).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .browseCardContextMenu(card: card, player: playerViewModel, router: router, core: rustCore, origin: .library)
                }
            }
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(cards, id: \.libraryIdentity) { card in libraryCard(card, icon: icon) }
            }
        }
    }
    func pinTitle(_ card: BrowseCardRecord) -> String {
        L10n.text(libraryViewModel.pins.contains { $0.key == LibraryPin.key(card) } ? "library.unpin" : "library.pin", args: [card.displayTitle])
    }
    func pinControls(_ card: BrowseCardRecord) -> some View {
        HStack(spacing: 10) {
            Button { libraryViewModel.togglePin(card) } label: { Image(systemName: libraryViewModel.pins.contains { $0.key == LibraryPin.key(card) } ? "pin.fill" : "pin") }
                .buttonStyle(.plain).help(pinTitle(card)).accessibilityLabel(pinTitle(card))
            if libraryViewModel.selectedPageTab == .all, let index = libraryViewModel.pins.firstIndex(where: { $0.key == LibraryPin.key(card) }) {
                Button { libraryViewModel.movePin(card, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).accessibilityLabel(L10n.text("library.pin.up", args: [card.displayTitle]))
                Button { libraryViewModel.movePin(card, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index == libraryViewModel.pins.count - 1).accessibilityLabel(L10n.text("library.pin.down", args: [card.displayTitle]))
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

@MainActor private final class LibraryPinMenuItem: NSMenuItem {
    private let perform: () -> Void
    init(title: String, perform: @escaping () -> Void) {
        self.perform = perform
        super.init(title: title, action: #selector(activate), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func activate() { perform() }
}

private extension BrowseCardRecord {
    var libraryIdentity: String { LibraryPin.key(self) }
}
