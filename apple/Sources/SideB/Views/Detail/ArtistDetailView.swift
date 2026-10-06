import SwiftUI
import AppKit
import SideBCore

struct ArtistDetailView: View {
    let browseId: String
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    var router: NavigationRouter? = nil

    @State private var viewModel = ArtistDetailViewModel()
    @State private var showDescriptionModal = false
    @State private var isHoveringDesc = false
    @State private var hoveredTopSongId: String? = nil

    var body: some View {
        ZStack {
            Group {
                if viewModel.isLoading || (viewModel.artist == nil && viewModel.errorMessage == nil) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            loadingHeader
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 36)
                    }
                } else if let artist = viewModel.artist {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            // Cabecera interactiva del Artista
                            headerView(artist: artist)
                                .padding(.horizontal, 32)
                                .padding(.top, 28)

                            Divider()
                                .opacity(0.2)
                                .padding(.horizontal, 32)

                            // Top Canciones
                            if !artist.topSongs.isEmpty {
                                topSongsSection(artist: artist)
                                    .padding(.horizontal, 32)
                            }

                            // Carruseles de Secciones (Álbumes, Sencillos, Vídeos, etc.)
                            ForEach(artist.sections, id: \.title) { section in
                                if !section.items.isEmpty {
                                    carouselSection(section: section)
                                }
                            }
                        }
                        .padding(.bottom, 120) // Espacio para la barra de reproducción flotante
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No se pudo cargar el artista")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Reintentar") {
                            Task {
                                await viewModel.loadArtist(core: rustCore, browseId: browseId)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .task(id: browseId) {
                await viewModel.loadArtist(core: rustCore, browseId: browseId)
            }

            // Modal flotante de biografía expandida Liquid Glass
            if showDescriptionModal, let artist = viewModel.artist, let desc = artist.description, !desc.isEmpty {
                DescriptionCardModal(
                    title: artist.name,
                    subtitle: "Biografía del artista",
                    description: desc,
                    isPresented: $showDescriptionModal
                )
            }
        }
    }

    // MARK: - Header
    @ViewBuilder
    private func headerView(artist: ArtistDetailRecord) -> some View {
        HStack(alignment: .center, spacing: 28) {
            // Avatar Circular del Artista
            if let thumb = artist.thumbnail, let url = URL(string: thumb) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 180, height: 180)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderAvatar
                }
                .frame(width: 180, height: 180)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            } else {
                placeholderAvatar
                    .frame(width: 180, height: 180)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            }

            // Metadatos y Acciones
            VStack(alignment: .leading, spacing: 8) {
                Text("ARTISTA")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                Text(artist.name)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let subs = artist.subscribers, !subs.isEmpty {
                        Text(subs)
                    }
                    if let listeners = artist.monthlyListeners, !listeners.isEmpty {
                        if artist.subscribers != nil {
                            Text("•")
                        }
                        Text(listeners)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

                if let desc = artist.description, !desc.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDescriptionModal = true
                        }
                    } label: {
                        HStack(alignment: .bottom, spacing: 4) {
                            Text(desc)
                                .font(.system(size: 12))
                                .foregroundStyle(isHoveringDesc ? .secondary : .tertiary)
                                .lineLimit(3)
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
                    .help("Haz clic para leer la biografía completa")
                }

                Spacer(minLength: 8)

                // Botones de acción principales
                HStack(spacing: 12) {
                    // Iniciar mix
                    Button {
                        viewModel.startRadio(core: rustCore, player: playerViewModel)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Iniciar mix")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.16))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // Aleatorio
                    if !artist.topSongs.isEmpty {
                        Button {
                            viewModel.shuffleTopSongs(player: playerViewModel)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Aleatorio")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .foregroundStyle(.primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // Suscribirse / Suscrito
                    Button {
                        Task {
                            await viewModel.toggleSubscription(core: rustCore)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: artist.subscribed ? "bell.fill" : "bell")
                                .font(.system(size: 13, weight: .medium))
                            Text(artist.subscribed ? "Suscrito" : "Suscribirse")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(artist.subscribed ? Color.white.opacity(0.18) : Color.white.opacity(0.1))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // Botón de más opciones (•••)
                    Menu {
                        let target = MenuTarget.artist(
                            channelId: artist.channelId,
                            name: artist.name,
                            thumbnail: artist.thumbnail,
                            radioPlaylistId: nil
                        )
                        let facts = MenuFacts(
                            isLoggedIn: rustCore.isLoggedIn(),
                            isSubscribed: .known(artist.subscribed),
                            userPlaylists: AppContextMenuFactory.cachedUserPlaylists
                        )
                        let executor = MenuActionExecutor(player: playerViewModel, router: router, core: rustCore)
                        let sections = MenuPolicy.resolveSections(
                            target: target,
                            origin: .artist(channelId: artist.channelId),
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

    // MARK: - Top Canciones
    @ViewBuilder
    private func topSongsSection(artist: ArtistDetailRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Canciones principales")
                    .font(.system(size: 20, weight: .bold))

                Spacer()

                if let topSongsId = artist.topSongsId, !topSongsId.isEmpty {
                    Button("Ver todo") {
                        router?.navigate(to: .playlist(browseId: topSongsId))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ver todas las canciones principales")
                }
            }

            VStack(spacing: 4) {
                ForEach(Array(artist.topSongs.prefix(5).enumerated()), id: \.element.videoId) { index, song in
                    topSongRow(song: song, index: index + 1)
                }
            }
        }
    }

    private func topSongRow(song: SongItemRecord, index: Int) -> some View {
        let origin = MenuOrigin.artist(channelId: viewModel.artist?.channelId ?? browseId)
        let playSong = { viewModel.playTopSong(at: index - 1, player: playerViewModel) }
        let row = HStack(spacing: 14) {
            Text("\(index)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
                .allowsHitTesting(false)

            MediaArtworkControls(
                isCollection: false,
                accessibilityTitle: song.title,
                onOpen: playSong,
                onPlay: playSong,
                menuProvider: {
                    AppContextMenuFactory.shared.buildSongNSMenu(song: song, player: playerViewModel,
                        router: router, core: rustCore, origin: origin)
                }
            ) {
                if let thumb = song.thumbnail, let url = URL(string: thumb) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 44, height: 44)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color.secondary.opacity(0.15) }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "music.note").font(.system(size: 16)))
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                    .allowsHitTesting(false)
                HStack(spacing: 4) {
                    if let artistId = song.artistId, !artistId.isEmpty {
                        Button { router?.navigate(to: .artist(browseId: artistId)) } label: {
                            Text(song.artists).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .mediaCardFocusControl()
                    } else {
                        Text(song.artists).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    if let album = song.album, !album.isEmpty {
                        Text("·").font(.system(size: 12)).foregroundStyle(.tertiary)
                        if let albumId = song.albumId, !albumId.isEmpty {
                            Button { router?.navigate(to: .album(browseId: albumId)) } label: {
                                Text(album).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .mediaCardFocusControl()
                        } else {
                            Text(album).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let duration = song.duration {
                Text(duration).font(.system(size: 12)).foregroundStyle(.secondary).allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(hoveredTopSongId == song.videoId ? Color.white.opacity(0.045) : Color.clear))
        .contentShape(Rectangle())
        .mediaCardActivation(action: playSong)
        .mediaCardSurface()
        .onHover { hoveredTopSongId = $0 ? song.videoId : nil }

        return row.songContextMenu(
            song: song,
            player: playerViewModel,
            router: router,
            core: rustCore,
            origin: origin
        )
    }

    // MARK: - Secciones de Carruseles (Álbumes, Sencillos, etc.)
    @ViewBuilder
    private func carouselSection(section: ArtistCarouselRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(section.title)
                    .font(.system(size: 20, weight: .bold))

                Spacer()

                if let moreBrowseId = section.moreBrowseId, !moreBrowseId.isEmpty {
                    Button("Ver todo") {
                        router?.navigate(to: .catalog(
                            browseId: moreBrowseId,
                            params: section.moreParams,
                            title: section.title
                        ))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ver todo: \(section.title)")
                }
            }
            .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(section.items, id: \.id) { card in
                        artistCardItem(card: card)
                    }
                }
                .padding(.horizontal, 32)
            }
            .windowGestureRegion(.horizontalContent, active: !playerViewModel.isFullscreenPresented)
        }
    }

    @ViewBuilder
    private func artistCardItem(card: BrowseCardRecord) -> some View {
        let isArtist = card.kind.lowercased() == "artist"
        let isVideo = card.kind.lowercased() == "video"
        let isCollection = ["album", "playlist"].contains(card.kind.lowercased())
        let cardWidth: CGFloat = isVideo ? 200 : 144
        let cardHeight: CGFloat = isVideo ? 112 : 144
        let isActive = MediaPlaybackIdentity.isCollectionActive(
            kind: card.kind, id: card.id, context: playerViewModel.queueManager.context
        )
        let artwork = Group {
            if let thumb = card.thumbnail,
               let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: isVideo ? 400 : 288) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: cardWidth, height: cardHeight)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.12)
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: AppTheme.artworkCardRadius, style: .continuous)))
            } else {
                RoundedRectangle(cornerRadius: isArtist ? cardWidth / 2 : AppTheme.artworkCardRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: cardWidth, height: cardHeight)
                    .overlay(Image(systemName: isArtist ? "person.crop.circle" : "music.note").font(.system(size: 28)))
            }
        }

        let cardView = VStack(alignment: .leading, spacing: 8) {
            if isCollection {
                MediaArtworkControls(
                    isCollection: true,
                    isActive: isActive,
                    isPlaying: isActive && playerViewModel.isPlaying,
                    isLoading: isCollectionLoading(card),
                    showsIndicator: isActive,
                    accessibilityTitle: card.title,
                    onOpen: { handleCardClick(card) },
                    onPlay: { playerViewModel.activateMediaCollection(id: card.id, kind: card.kind) },
                    menuProvider: { artistCardMenu(card) }
                ) { artwork }
                    .frame(width: cardWidth, height: cardHeight)
            } else if isArtist {
                Button { handleCardClick(card) } label: { artwork }
                    .buttonStyle(.plain)
                    .mediaCardFocusControl()
            } else {
                let song = SongItemRecord(
                    fromCard: card,
                    fallbackArtist: viewModel.artist?.name,
                    knownArtistId: viewModel.artist?.channelId ?? browseId
                )
                MediaArtworkControls(
                    isCollection: false,
                    accessibilityTitle: card.title,
                    onOpen: { playerViewModel.activateMediaRadio(song) },
                    onPlay: { playerViewModel.activateMediaRadio(song) },
                    menuProvider: { artistCardMenu(card) }
                ) { artwork }
                    .frame(width: cardWidth, height: cardHeight)
            }

            Button { handleCardClick(card) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle = card.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .mediaCardFocusControl()
        }
        .frame(width: cardWidth, alignment: .leading)

        cardView
        .mediaCardActivation(label: card.kind == "song" || card.kind == "video"
            ? "Reproducir \(card.title)" : "Abrir \(card.title)") { handleCardClick(card) }
        .mediaCardSurface()
        .browseCardContextMenu(
            card: card,
            player: playerViewModel,
            router: router,
            core: rustCore,
            origin: .artist(channelId: viewModel.artist?.channelId ?? browseId),
            fallbackArtist: viewModel.artist?.name,
            knownArtistId: viewModel.artist?.channelId ?? browseId
        )
    }

    private func artistCardMenu(_ card: BrowseCardRecord) -> NSMenu? {
        let factory = AppContextMenuFactory.shared
        let origin = MenuOrigin.artist(channelId: viewModel.artist?.channelId ?? browseId)
        switch card.kind.lowercased() {
        case "album":
            return factory.buildAlbumNSMenu(browseId: card.id, playlistId: nil, title: card.title,
                artist: card.subtitle ?? viewModel.artist?.name, thumbnail: card.thumbnail, origin: origin,
                player: playerViewModel, router: router, core: rustCore)
        case "playlist":
            return factory.buildPlaylistNSMenu(id: card.id, title: card.title, subtitle: card.subtitle,
                thumbnail: card.thumbnail, origin: origin, player: playerViewModel, router: router, core: rustCore)
        case "song", "video":
            return factory.buildSongNSMenu(song: SongItemRecord(fromCard: card,
                fallbackArtist: viewModel.artist?.name, knownArtistId: viewModel.artist?.channelId ?? browseId),
                player: playerViewModel, router: router, core: rustCore, origin: origin)
        default:
            return nil
        }
    }

    private func isCollectionLoading(_ card: BrowseCardRecord) -> Bool {
        if card.kind.lowercased() == "album" {
            return playerViewModel.loadingRecommendedAlbumID.map(MenuIDNormalizer.normalize) == MenuIDNormalizer.normalize(card.id)
        }
        return playerViewModel.loadingRecommendedPlaylistID.map(MenuIDNormalizer.canonicalPlaylistId) == MenuIDNormalizer.canonicalPlaylistId(card.id)
    }

    private func handleCardClick(_ card: BrowseCardRecord) {
        if card.kind == "album" {
            router?.navigate(to: .album(browseId: card.id))
        } else if card.kind == "playlist" {
            router?.navigate(to: .playlist(browseId: card.id))
        } else if card.kind == "artist" {
            router?.navigate(to: .artist(browseId: card.id))
        } else if card.kind == "song" || card.kind == "video" {
            let song = SongItemRecord(
                fromCard: card,
                fallbackArtist: viewModel.artist?.name,
                knownArtistId: viewModel.artist?.channelId ?? browseId
            )
            playerViewModel.activateMediaRadio(song)
        }
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.sidebAccent.opacity(0.4), Color(red: 0.12, green: 0.04, blue: 0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.85))
            }
    }

    private var loadingHeader: some View {
        HStack(alignment: .center, spacing: 28) {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 180, height: 180)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 60, height: 12)

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 260, height: 32)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 160, height: 14)
            }
            Spacer()
        }
    }
}
