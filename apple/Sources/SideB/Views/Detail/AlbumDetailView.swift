import SwiftUI
import SideBCore

struct AlbumDetailView: View {
    let browseId: String
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    var router: NavigationRouter? = nil
    var topContentInset: CGFloat = 0

    @State private var viewModel = AlbumDetailViewModel()
    @State private var showDescriptionModal = false
    @State private var headerHeight: CGFloat = 360

    var body: some View {
        ZStack {
            Group {
                if viewModel.isLoading || (viewModel.album == nil && viewModel.errorMessage == nil) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            DetailLoadingHeaderView()
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 36 + topContentInset)
                    }
                } else if let album = viewModel.album {
                    NativeTrackTableView(
                        tracks: viewModel.displayedTracks,
                        currentTrackVideoId: playerViewModel.currentTrack?.videoId,
                        isPlaying: playerViewModel.isPlaying,
                        playerViewModel: playerViewModel,
                        router: router,
                        rustCore: rustCore,
                        presentation: .collectionAlbum,
                        hideAlbumColumn: true,
                        rowHeight: CollectionTrackMetrics.rowHeight,
                        likedVideoIds: playerViewModel.likedVideoIds,
                        menuOrigin: { _ in .album(browseId: album.browseId) },
                        onPlayTrack: { index in
                            viewModel.playDisplayedTrack(at: index, player: playerViewModel)
                        },
                        onLikeTrack: { playerViewModel.toggleTrackLike($0) },
                        onDislikeTrack: { playerViewModel.dislikeTrack($0) },
                        contentInsets: album.sections.isEmpty
                            ? NSEdgeInsets(top: 0, left: 0, bottom: 120, right: 0)
                            : NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                        scrollingHeader: AnyView(headerView(album: album)),
                        scrollingHeaderHeight: headerHeight,
                        scrollingBackground: { visible in
                            AnyView(CollectionAmbientBackground(thumbnail: album.thumbnail,
                                                                identity: playerViewModel.mediaSessionIdentity.uuidString + ":album:" + browseId,
                                                                isInViewport: visible))
                        },
                        scrollingBackgroundIdentity: playerViewModel.mediaSessionIdentity.uuidString + ":album:" + browseId,
                        footer: album.sections.isEmpty && !viewModel.displayedTracks.isEmpty ? nil : AnyView(
                            VStack(alignment: .leading, spacing: 0) {
                                if viewModel.displayedTracks.isEmpty {
                                    CollectionDetailEmptyResultsView(query: viewModel.searchQuery)
                                }
                                if !album.sections.isEmpty { albumSectionsFooter(album) }
                            }
                        ),
                        footerHeight: (viewModel.displayedTracks.isEmpty ? 72 : 0) +
                            (album.sections.isEmpty ? 0 : CGFloat(album.sections.count) * 276 + 120)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    DetailErrorStateView(
                        title: "No se pudo cargar el álbum",
                        message: error,
                        onRetry: {
                            Task {
                                await viewModel.loadAlbum(core: rustCore, browseId: browseId)
                            }
                        }
                    )
                }
            }
            .task(id: browseId + ":" + playerViewModel.mediaSessionIdentity.uuidString) {
                viewModel.resetForSession()
                await viewModel.loadAlbum(core: rustCore, browseId: browseId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sideBLibraryAlbumToggled)) { notification in
                guard let info = notification.userInfo,
                      let notifBrowseId = info["browseId"] as? String,
                      let inLibrary = info["inLibrary"] as? Bool else { return }
                viewModel.handleLibraryAlbumToggled(browseId: notifBrowseId, inLibrary: inLibrary)
            }

            // Modal flotante de descripción expandida Liquid Glass
            if showDescriptionModal, let album = viewModel.album, let desc = album.description, !desc.isEmpty {
                DescriptionCardModal(
                    title: album.title,
                    subtitle: "Descripción del álbum",
                    description: desc,
                    isPresented: $showDescriptionModal
                )
            }
        }
    }

    // MARK: - Subviews

    private func albumSectionsFooter(_ album: AlbumDetailRecord) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(album.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 14) {
                    Text(section.title)
                        .font(.system(size: 20, weight: .bold))
                        .padding(.horizontal, 32)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(section.items, id: \.id) { card in
                                CatalogCardView(
                                    card: card,
                                    rustCore: rustCore,
                                    playerViewModel: playerViewModel,
                                    router: router,
                                    artistBrowseId: album.artistId
                                )
                                .frame(width: 160)
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerView(album: AlbumDetailRecord) -> some View {
        CollectionDetailHeaderView(
            kind: "ÁLBUM",
            title: album.title,
            thumbnail: album.thumbnail,
            artworkSymbol: "opticaldisc",
            credit: album.artist,
            onCredit: albumCreditAction(album),
            metadata: [album.subtitle, album.secondSubtitle ?? "\(album.items.count) canciones"].compactMap { $0 },
            description: album.description,
            onExpandDescription: {
                withAnimation(.easeInOut(duration: 0.2)) { showDescriptionModal = true }
            },
            onPlay: { viewModel.playAll(player: playerViewModel) },
            onShuffle: { viewModel.shuffle(player: playerViewModel) },
            showsSave: album.playlistId != nil,
            isSaved: album.inLibrary,
            onSave: { Task { await viewModel.toggleLibrary(core: rustCore) } },
            additionalActions: AnyView(albumActions(album)),
            query: $viewModel.searchQuery
        )
        .padding(.top, topContentInset)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredHeight in
            if abs(headerHeight - measuredHeight) > 0.5 { headerHeight = measuredHeight }
        }
    }

    private func albumCreditAction(_ album: AlbumDetailRecord) -> (() -> Void)? {
        guard let artistId = album.artistId, !artistId.isEmpty else { return nil }
        return { router?.navigate(to: .artist(browseId: artistId)) }
    }

    private func albumActions(_ album: AlbumDetailRecord) -> some View {
        Menu {
            let target = MenuTarget.album(
                browseId: album.browseId,
                playlistId: album.playlistId,
                title: album.title,
                artist: album.artist,
                artistId: album.artistId,
                thumbnail: album.thumbnail
            )
            let facts = MenuFacts(
                isLoggedIn: rustCore.isLoggedIn(),
                inLibrary: .known(album.inLibrary),
                userPlaylists: AppContextMenuFactory.cachedUserPlaylists
            )
            let executor = MenuActionExecutor(player: playerViewModel, router: router, core: rustCore)
            let sections = MenuPolicy.resolveSections(
                target: target,
                origin: .album(browseId: album.browseId),
                facts: facts
            )
            MenuSectionContentView(
                sections: sections,
                target: target,
                facts: facts,
                executor: executor
            )
        } label: {
            SideBEllipsisLabel(iconSize: 15.6)
                .frame(width: 33.6, height: 33.6)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Más opciones")
        .font(.system(size: 15.6))
    }
}
