import SwiftUI
import SideBCore

struct AlbumDetailView: View {
    let browseId: String
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    var router: NavigationRouter? = nil

    @State private var viewModel = AlbumDetailViewModel()
    @State private var showDescriptionModal = false
    @State private var isHoveringDesc = false

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
                        .padding(.top, 36)
                    }
                } else if let album = viewModel.album {
                    VStack(alignment: .leading, spacing: 0) {
                        // Cabecera SwiftUI nativa interactiva
                        headerView(album: album)
                            .padding(.horizontal, 32)
                            .padding(.top, 28)
                            .padding(.bottom, 16)

                        Divider()
                            .opacity(0.2)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 8)

                        // Tabla AppKit nativa a 120 FPS con soporte de Click Derecho
                        NativeTrackTableView(
                            tracks: album.items,
                            currentTrackVideoId: playerViewModel.currentTrack?.videoId,
                            isPlaying: playerViewModel.isPlaying,
                            playerViewModel: playerViewModel,
                            router: router,
                            rustCore: rustCore,
                            hideAlbumColumn: true,
                            likedVideoIds: playerViewModel.likedVideoIds,
                            menuOrigin: { _ in .album(browseId: album.browseId) },
                            onPlayTrack: { index in
                                viewModel.playTrack(at: index, player: playerViewModel)
                            },
                            onLikeTrack: { track in
                                playerViewModel.toggleTrackLike(track)
                            },
                            onDislikeTrack: { track in
                                playerViewModel.dislikeTrack(track)
                            },
                            contentInsets: album.sections.isEmpty
                                ? NSEdgeInsets(top: 0, left: 0, bottom: 120, right: 0)
                                : NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                            footer: album.sections.isEmpty ? nil : AnyView(albumSectionsFooter(album)),
                            footerHeight: CGFloat(album.sections.count) * 276 + 120
                        )
                    }
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
            .task(id: browseId) {
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

    @ViewBuilder
    private func headerView(album: AlbumDetailRecord) -> some View {
        HStack(alignment: .top, spacing: 24) {
            // Artwork con ImageCache y aplanado GPU
            if let thumb = album.thumbnail, let url = URL(string: thumb) {
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
                Text("ÁLBUM")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                Text(album.title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let artist = album.artist {
                    if let artistId = album.artistId, !artistId.isEmpty {
                        Button {
                            router?.navigate(to: .artist(browseId: artistId))
                        } label: {
                            Text(artist)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(artist)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 6) {
                    if let subtitle = album.subtitle {
                        Text(subtitle)
                    }
                    if let second = album.secondSubtitle {
                        Text("• \(second)")
                    } else {
                        Text("• \(album.items.count) canciones")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                if let desc = album.description, !desc.isEmpty {
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
                                .frame(maxWidth: 620, alignment: .leading)

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

                Spacer(minLength: 8)

                // Botones de acción principales
                HStack(spacing: 10) {
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

                    if album.playlistId != nil {
                        Button {
                            Task {
                                await viewModel.toggleLibrary(core: rustCore)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: album.inLibrary ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 13, weight: .medium))
                                Text(album.inLibrary ? "En biblioteca" : "Guardar")
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

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.sidebAccent.opacity(0.30), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.85))
            }
    }

}
