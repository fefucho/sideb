import SwiftUI
import AppKit
import SideBCore

struct LibraryView: View {
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    @Bindable var libraryViewModel: LibraryViewModel
    @Bindable var accountViewModel: AccountViewModel
    @Bindable var router: NavigationRouter

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 18)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COLECCIÓN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                    Text("Biblioteca")
                        .font(.system(size: 32, weight: .bold))
                }
                Spacer()
                if accountViewModel.isLoggedIn {
                    Button {
                        NotificationCenter.default.post(name: .sideBRequestCreatePlaylist, object: nil)
                    } label: {
                        Label("Nueva playlist", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .help("Crear una playlist")
                }
            }
            .padding(.horizontal, 32)
            .padding(.trailing, 110)
            .padding(.top, 24)
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                ForEach(LibraryPageTab.allCases) { tab in
                    Button {
                        libraryViewModel.selectedPageTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .foregroundStyle(libraryViewModel.selectedPageTab == tab ? Color.white : Color.primary)
                            .background(
                                libraryViewModel.selectedPageTab == tab ? Color.sidebAccent : Color.primary.opacity(0.08),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(libraryViewModel.selectedPageTab == tab ? .isSelected : [])
                }
                Spacer()
                Button {
                    Task { await reloadSelectedTab() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Actualizar biblioteca")
                .accessibilityLabel("Actualizar biblioteca")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 14)

            Divider().opacity(0.2).padding(.horizontal, 32)

            Group {
                if !accountViewModel.isLoggedIn {
                    emptyState("Iniciá sesión para ver tu biblioteca", icon: "person.crop.circle")
                } else {
                    switch libraryViewModel.selectedPageTab {
                    case .songs: songsContent
                    case .playlists: cardsContent(libraryViewModel.playlists, icon: "music.note.list", title: "No tenés playlists")
                    case .albums: cardsContent(libraryViewModel.albums, icon: "opticaldisc", title: "No tenés álbumes guardados")
                    case .artists: cardsContent(libraryViewModel.artists, icon: "person.crop.circle", title: "No tenés artistas en tu biblioteca")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: libraryViewModel.selectedPageTab) {
            await reloadSelectedTab()
        }
        .onAppear {
            Task { await reloadSelectedTab() }
        }
        .onChange(of: accountViewModel.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                Task { await reloadSelectedTab() }
            }
        }
        .onChange(of: router.currentPage) { _, newPage in
            if newPage == .library {
                Task { await reloadSelectedTab() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBLibraryRefreshRequested)) { _ in
            Task { await reloadSelectedTab() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBSongLibraryChanged)) { _ in
            if libraryViewModel.selectedPageTab == .songs {
                Task { await libraryViewModel.loadSongs(core: rustCore) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBLibraryAlbumToggled)) { _ in
            if libraryViewModel.selectedPageTab == .songs {
                Task { await libraryViewModel.loadSongs(core: rustCore) }
            }
        }
    }

    @ViewBuilder
    private var songsContent: some View {
        if libraryViewModel.isSongsLoading && libraryViewModel.songs.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = libraryViewModel.songsErrorMessage, libraryViewModel.songs.isEmpty {
            DetailErrorStateView(title: "No se pudieron cargar las canciones", message: error) {
                Task { await libraryViewModel.loadSongs(core: rustCore) }
            }
        } else if libraryViewModel.songs.isEmpty {
            emptyState("No hay canciones en tu biblioteca", icon: "music.note")
        } else {
            VStack(spacing: 0) {
                NativeTrackTableView(
                    tracks: libraryViewModel.songs,
                    currentTrackVideoId: playerViewModel.currentTrack?.videoId,
                    isPlaying: playerViewModel.isPlaying,
                    playerViewModel: playerViewModel,
                    router: router,
                    rustCore: rustCore,
                    likedVideoIds: playerViewModel.likedVideoIds,
                    menuOrigin: { _ in .library },
                    onPlayTrack: { index in
                        playerViewModel.playPlaylist(
                            browseId: "FEmusic_liked_videos", title: "Biblioteca",
                            tracks: libraryViewModel.songs, startingAt: index,
                            continuation: libraryViewModel.songsContinuation
                        )
                    },
                    onLikeTrack: { playerViewModel.toggleTrackLike($0) },
                    onDislikeTrack: { playerViewModel.dislikeTrack($0) },
                    onNearBottom: {
                        Task { await libraryViewModel.loadMoreSongs(core: rustCore) }
                    }
                )
                if let error = libraryViewModel.songsErrorMessage {
                    HStack(spacing: 10) {
                        Text("No se pudo actualizar Canciones: \(error)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Button("Reintentar") {
                            Task { await libraryViewModel.loadSongs(core: rustCore) }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if libraryViewModel.isSongsLoadingMore {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Cargando más canciones...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 110)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    @ViewBuilder
    private func cardsContent(_ cards: [BrowseCardRecord], icon: String, title: String) -> some View {
        if libraryViewModel.isLoading && cards.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if libraryViewModel.selectedPageTab == .artists && libraryViewModel.isArtistsLoading && cards.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = cardError, cards.isEmpty {
            DetailErrorStateView(title: "No se pudo cargar la biblioteca", message: error) {
                Task { await reloadSelectedTab() }
            }
        } else if cards.isEmpty {
            emptyState(title, icon: icon)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(cards, id: \.id) { card in
                        libraryCard(card, icon: icon)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
                .padding(.bottom, 130)
            }
        }
    }

    private func openLibraryCard(_ card: BrowseCardRecord) {
        switch libraryViewModel.selectedPageTab {
        case .playlists: router.navigate(to: .playlist(browseId: card.id))
        case .albums: router.navigate(to: .album(browseId: card.id))
        case .artists: router.navigate(to: .artist(browseId: card.id))
        case .songs: break
        }
    }

    private func libraryCard(_ card: BrowseCardRecord, icon: String) -> some View {
        let isArtist = libraryViewModel.selectedPageTab == .artists
        let kind = libraryViewModel.selectedPageTab == .albums ? "album" : "playlist"
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
                    showsIndicator: true, accessibilityTitle: card.title,
                    onOpen: { openLibraryCard(card) },
                    onPlay: { playerViewModel.activateMediaCollection(id: card.id, kind: kind) },
                    menuProvider: { libraryCardMenu(card, kind: kind) }
                ) {
                    libraryArtwork(card, icon: icon, isArtist: false)
                }.aspectRatio(1, contentMode: .fit)
            }
            Button { openLibraryCard(card) } label: {
                Text(card.title).font(.system(size: 13, weight: .semibold))
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).mediaCardFocusControl()
            if let subtitle = card.subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .mediaCardActivation(label: "Abrir \(card.title)") { openLibraryCard(card) }
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
        if kind == "album" {
            return AppContextMenuFactory.shared.buildAlbumNSMenu(browseId: card.id, playlistId: nil,
                title: card.title, artist: card.subtitle, thumbnail: card.thumbnail,
                origin: .library, player: playerViewModel, router: router, core: rustCore)
        }
        return AppContextMenuFactory.shared.buildPlaylistNSMenu(id: card.id, title: card.title,
            subtitle: card.subtitle, thumbnail: card.thumbnail, origin: .library,
            player: playerViewModel, router: router, core: rustCore)
    }

    private var cardError: String? {
        switch libraryViewModel.selectedPageTab {
        case .playlists: libraryViewModel.playlistsErrorMessage
        case .albums: libraryViewModel.albumsErrorMessage
        case .artists: libraryViewModel.artistsErrorMessage
        case .songs: nil
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
}
