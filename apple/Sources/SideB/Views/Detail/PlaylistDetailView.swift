import SwiftUI
import SideBCore

struct PlaylistDetailView: View {
    let playlistId: String
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    var router: NavigationRouter? = nil

    @State private var viewModel = PlaylistDetailViewModel()
    @State private var showDescriptionModal = false
    @State private var isHoveringDesc = false
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
                        .padding(.top, 36)
                    }
                } else if let playlist = viewModel.playlist {
                    VStack(alignment: .leading, spacing: 0) {
                        // Cabecera SwiftUI nativa interactiva
                        headerView(playlist: playlist)
                            .padding(.horizontal, 32)
                            .padding(.top, 28)
                            .padding(.bottom, 16)

                        Divider()
                            .opacity(0.2)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 8)

                        // Tabla AppKit nativa a 120 FPS con Cell Recycling, soporte de Click Derecho y Álbum
                        NativeTrackTableView(
                            tracks: playlist.items,
                            currentTrackVideoId: playerViewModel.currentTrack?.videoId,
                            isPlaying: playerViewModel.isPlaying,
                            playerViewModel: playerViewModel,
                            router: router,
                            rustCore: rustCore,
                            hideAlbumColumn: false,
                            isReorderable: playlist.owned
                                && (playlist.sort == nil || playlist.sort == "default")
                                && !viewModel.isMovingTrack
                                && playlist.items.allSatisfy { $0.setVideoId?.isEmpty == false },
                            likedVideoIds: playerViewModel.likedVideoIds,
                            playlistContext: (playlistId: playlist.id, isOwned: playlist.owned),
                            menuOrigin: { _ in .playlist(id: playlist.id) },
                            onPlayTrack: { index in
                                viewModel.playTrack(at: index, player: playerViewModel)
                            },
                            onLikeTrack: { track in
                                playerViewModel.toggleTrackLike(track)
                            },
                            onDislikeTrack: { track in
                                playerViewModel.dislikeTrack(track)
                            },
                            onRemoveTrackFromPlaylist: { track in
                                Task {
                                    do {
                                        try await viewModel.removeTrack(track: track, core: rustCore)
                                    } catch {
                                        mutationError = error.localizedDescription
                                    }
                                }
                            },
                            onMoveTrack: { from, to in
                                Task {
                                    do {
                                        try await viewModel.moveTrack(from: from, to: to, core: rustCore)
                                    } catch {
                                        mutationError = error.localizedDescription
                                    }
                                }
                            },
                            onNearBottom: {
                                Task {
                                    await viewModel.loadMore(core: rustCore)
                                }
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .task(id: playlistId) {
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

    @ViewBuilder
    private func headerView(playlist: PlaylistDetailRecord) -> some View {
        HStack(alignment: .top, spacing: 24) {
            // Artwork con ImageCache y aplanado GPU
            if let thumb = playlist.thumbnail, let url = URL(string: thumb) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 180, height: 180)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderArtwork
                }
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            } else {
                placeholderArtwork
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            }

            // Metadata
            VStack(alignment: .leading, spacing: 8) {
                Text(playlist.id == "LM" ? "COLECCIÓN" : "PLAYLIST")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                Text(playlist.title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let subtitle = playlist.subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if let desc = playlist.description, !desc.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDescriptionModal = true
                        }
                    } label: {
                        HStack(alignment: .bottom, spacing: 4) {
                            Text(desc)
                                .font(.system(size: 12))
                                .foregroundStyle(isHoveringDesc ? .secondary : .tertiary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text("más")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.top, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringDesc = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .help("Haz clic para leer la descripción completa")
                }

                Text("\(playlist.items.count) canciones")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                // Botones de reproducción y acciones
                HStack(spacing: 12) {
                    Button {
                        viewModel.playAll(player: playerViewModel)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Reproducir")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .compatGlass(interactive: true, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.shuffle(player: playerViewModel)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 13, weight: .medium))
                            Text("Aleatorio")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(.primary)
                        .compatGlass(interactive: true, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    if !playlist.owned && playlist.id != "LM" {
                        Button {
                            Task {
                                await viewModel.toggleLibrary(core: rustCore)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.inLibrary ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 13, weight: .medium))
                                Text(viewModel.inLibrary ? "En biblioteca" : "Guardar")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(.primary)
                            .compatGlass(interactive: true, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // Botón de más opciones (•••)
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
                            isOwned: .known(playlist.owned),
                            sortEditable: playlist.sortEditable,
                            userPlaylists: AppContextMenuFactory.cachedUserPlaylists,
                            onEditPlaylist: { showEditor = true },
                            onDeletePlaylist: { showDeleteConfirmation = true },
                            onSortPlaylist: { value in
                                Task {
                                    do {
                                        try await viewModel.setSort(value, core: rustCore)
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
                        SideBEllipsisLabel()
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .accessibilityLabel("Más opciones")
                }
            }
            .frame(height: 180, alignment: .leading)
            Spacer()
        }
    }

    private func sortButton(_ title: String, value: String, playlist: PlaylistDetailRecord) -> some View {
        Button {
            Task {
                do {
                    try await viewModel.setSort(value, core: rustCore)
                } catch {
                    mutationError = error.localizedDescription
                }
            }
        } label: {
            if playlist.sort == value {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func deletePlaylist() async {
        guard let playlist = viewModel.playlist, playlist.owned, !isDeleting else { return }
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

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.pink.opacity(0.6), Color.purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: playlistId == "LM" ? "heart.fill" : "music.note.list")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.8))
            }
    }

}
