import SwiftUI
import SideBCore

struct PlaylistDetailView: View {
    let playlistId: String
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    var router: NavigationRouter? = nil
    var topContentInset: CGFloat = 0

    @State private var viewModel = PlaylistDetailViewModel()
    @State private var showDescriptionModal = false
    @State private var headerHeight: CGFloat = 360
    @State private var showEditor = false
    @State private var showDeleteConfirmation = false
    @State private var mutationError: String?
    @State private var isDeleting = false

    var body: some View {
        ZStack {
            Group {
                if viewModel.isLoading || (viewModel.playlist == nil && viewModel.errorMessage == nil) {
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
                } else if let playlist = viewModel.playlist {
                    NativeTrackTableView(
                        tracks: viewModel.displayedTracks,
                        currentTrackVideoId: playerViewModel.currentTrack?.videoId,
                        isPlaying: playerViewModel.isPlaying,
                        playerViewModel: playerViewModel,
                        router: router,
                        rustCore: rustCore,
                        presentation: .collectionPlaylist,
                        hideAlbumColumn: false,
                        isReorderable: viewModel.canReorderDisplayedTracks,
                        rowHeight: CollectionTrackMetrics.rowHeight,
                        likedVideoIds: playerViewModel.likedVideoIds,
                        playlistContext: (playlistId: playlist.id,
                                          isOwned: playlist.owned && playlist.id != "LM" && playlist.id != "VLLM"),
                        menuOrigin: { _ in .playlist(id: playlist.id) },
                        onPlayTrack: { index in
                            viewModel.playDisplayedTrack(at: index, player: playerViewModel)
                        },
                        onLikeTrack: { playerViewModel.toggleTrackLike($0) },
                        onDislikeTrack: { playerViewModel.dislikeTrack($0) },
                        onRemoveTrackFromPlaylist: { track in
                            Task {
                                do { try await viewModel.removeTrack(track: track, core: rustCore) }
                                catch { mutationError = error.localizedDescription }
                            }
                        },
                        onMoveTrack: { from, to in
                            Task {
                                do { try await viewModel.moveDisplayedTrack(from: from, to: to, core: rustCore) }
                                catch { mutationError = error.localizedDescription }
                            }
                        },
                        onNearBottom: {
                            guard playlist.continuation?.isEmpty == false else { return }
                            Task { await viewModel.loadMore(core: rustCore) }
                        },
                        contentInsets: NSEdgeInsets(top: 0, left: 0, bottom: 120, right: 0),
                        scrollingHeader: AnyView(headerView(playlist: playlist)),
                        scrollingHeaderHeight: headerHeight,
                        scrollingBackground: { visible in
                            AnyView(CollectionAmbientBackground(thumbnail: playlist.thumbnail,
                                                                identity: playerViewModel.mediaSessionIdentity.uuidString + ":playlist:" + playlistId,
                                                                isInViewport: visible))
                        },
                        scrollingBackgroundIdentity: playerViewModel.mediaSessionIdentity.uuidString + ":playlist:" + playlistId,
                        footer: viewModel.displayedTracks.isEmpty && playlist.continuation?.isEmpty != false
                            ? AnyView(CollectionDetailEmptyResultsView(query: viewModel.searchQuery)) : nil,
                        footerHeight: 72
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task(id: playlist.id + "|" + viewModel.searchQuery + "|" + viewModel.selectedOrder.rawValue + "|" + (playlist.continuation ?? "complete") + "|" + String(playlist.items.count)) {
                        await viewModel.prepareDisplayedTracks(core: rustCore)
                    }
                    .overlay(alignment: .bottom) {
                        if viewModel.isLoadingMore {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Cargando más canciones...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .compatGlass(in: Capsule())
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                            .padding(.bottom, 110)
                        }
                    }
                } else if let error = viewModel.errorMessage {
                    DetailErrorStateView(
                        title: "No se pudo cargar la playlist",
                        message: error,
                        onRetry: {
                            Task {
                                await viewModel.loadPlaylist(core: rustCore, playlistId: playlistId, forceRefresh: true)
                            }
                        }
                    )
                }
            }
            .task(id: playlistId + ":" + playerViewModel.mediaSessionIdentity.uuidString) {
                viewModel.resetForSession()
                await viewModel.loadPlaylist(core: rustCore, playlistId: playlistId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sideBLikedTrackToggled)) { notification in
                if let track = notification.userInfo?["track"] as? SongItemRecord,
                   let isLiked = notification.userInfo?["isLiked"] as? Bool {
                    viewModel.handleLikedTrackToggled(track: track, isLiked: isLiked)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sideBLibraryPlaylistToggled)) { notification in
                if let notifPlaylistId = notification.userInfo?["playlistId"] as? String,
                   let inLibrary = notification.userInfo?["inLibrary"] as? Bool {
                    viewModel.handleLibraryPlaylistToggled(playlistId: notifPlaylistId, inLibrary: inLibrary)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sideBPlaylistsChanged)) { _ in
                Task { await viewModel.loadPlaylist(core: rustCore, playlistId: playlistId, forceRefresh: true) }
            }

            // Modal flotante de descripción expandida Liquid Glass
            if showDescriptionModal, let playlist = viewModel.playlist, let desc = playlist.description, !desc.isEmpty {
                DescriptionCardModal(
                    title: playlist.title,
                    subtitle: "Descripción de la playlist",
                    description: desc,
                    isPresented: $showDescriptionModal
                )
            }
        }
        .sheet(isPresented: $showEditor) {
            if let playlist = viewModel.playlist {
                PlaylistEditorSheet(core: rustCore, playlist: playlist) { _ in
                    Task { await viewModel.loadPlaylist(core: rustCore, playlistId: playlistId, forceRefresh: true) }
                }
            }
        }
        .confirmationDialog(
            "¿Eliminar esta playlist?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar playlist", role: .destructive) {
                Task { await deletePlaylist() }
            }
        } message: {
            Text("También se eliminará de YouTube Music.")
        }
        .alert("No se pudo completar la acción", isPresented: Binding(
            get: { mutationError != nil },
            set: { if !$0 { mutationError = nil } }
        )) {
            Button("Aceptar", role: .cancel) { mutationError = nil }
        } message: {
            Text(mutationError ?? "")
        }
    }

    // MARK: - Subviews

    private func headerView(playlist: PlaylistDetailRecord) -> some View {
        CollectionDetailHeaderView(
            kind: playlist.id == "LM" || playlist.id == "VLLM" ? "COLECCIÓN" : "PLAYLIST",
            title: playlist.title,
            thumbnail: playlist.thumbnail,
            artworkSymbol: playlist.id == "LM" || playlist.id == "VLLM" ? "heart.fill" : "music.note.list",
            credit: playlist.subtitle,
            creditFontSize: 16.8,
            metadata: ["\(playlist.items.count) canciones\(playlist.continuation?.isEmpty == false ? " cargadas" : "")"],
            description: playlist.description,
            onExpandDescription: {
                withAnimation(.easeInOut(duration: 0.2)) { showDescriptionModal = true }
            },
            onPlay: { viewModel.playAll(player: playerViewModel) },
            onShuffle: { viewModel.shuffle(player: playerViewModel) },
            showsSave: !playlist.owned && playlist.id != "LM" && playlist.id != "VLLM",
            isSaved: viewModel.inLibrary,
            onSave: { Task { await viewModel.toggleLibrary(core: rustCore) } },
            additionalActions: AnyView(playlistActions(playlist)),
            query: $viewModel.searchQuery,
            selectedOrder: viewModel.selectedOrder,
            canSort: { viewModel.sortIsAvailable($0) },
            onSelectOrder: { order in
                Task {
                    do { try await viewModel.selectOrder(order, core: rustCore) }
                    catch { mutationError = error.localizedDescription }
                }
            },
            isCompletingCatalog: viewModel.isCompletingCatalog || viewModel.isChangingOrder,
            isPlaybackUnavailable: viewModel.needsCompletePlaybackOrder || viewModel.isChangingOrder,
            catalogError: viewModel.errorMessage,
            onRetryCatalog: { Task { await viewModel.prepareDisplayedTracks(core: rustCore) } }
        )
        .padding(.top, topContentInset)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredHeight in
            if abs(headerHeight - measuredHeight) > 0.5 { headerHeight = measuredHeight }
        }
    }

    private func playlistActions(_ playlist: PlaylistDetailRecord) -> some View {
        Menu {
            let isMix = MenuIDNormalizer.isDynamicRadioMix(id: playlist.id)
            let target = MenuTarget.playlist(
                id: playlist.id,
                title: playlist.title,
                subtitle: playlist.subtitle,
                thumbnail: playlist.thumbnail,
                isRadioMix: isMix
            )
            let facts = MenuFacts(
                isLoggedIn: rustCore.isLoggedIn(),
                inLibrary: .known(viewModel.inLibrary),
                isOwned: .known(playlist.owned && playlist.id != "LM" && playlist.id != "VLLM"),
                sortEditable: playlist.sortEditable && playlist.id != "LM" && playlist.id != "VLLM",
                userPlaylists: AppContextMenuFactory.cachedUserPlaylists,
                onEditPlaylist: { showEditor = true },
                onDeletePlaylist: { showDeleteConfirmation = true },
                onSortPlaylist: { value in
                    Task {
                        do {
                            let order: DetailTrackOrder? = switch value {
                            case "default": .custom
                            case "newest": .recentlyAdded
                            case "oldest": .oldestAdded
                            case "title": .title
                            case "artist": .artist
                            case "album": .album
                            default: nil
                            }
                            if let order {
                                try await viewModel.selectOrder(order, core: rustCore)
                            } else {
                                try await viewModel.setSort(value, core: rustCore)
                            }
                        } catch {
                            mutationError = error.localizedDescription
                        }
                    }
                }
            )
            let executor = MenuActionExecutor(player: playerViewModel, router: router, core: rustCore)
            let sections = MenuPolicy.resolveSections(
                target: target,
                origin: .playlist(id: playlist.id),
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

    private func deletePlaylist() async {
        guard let playlist = viewModel.playlist, playlist.owned,
              playlist.id != "LM", playlist.id != "VLLM", !isDeleting else { return }
        isDeleting = true
        do {
            try await rustCore.deletePlaylist(playlistId: playlist.id)
            NotificationCenter.default.post(name: .sideBPlaylistsChanged, object: nil)
            router?.navigate(to: .library)
        } catch {
            mutationError = error.localizedDescription
        }
        isDeleting = false
    }

}
