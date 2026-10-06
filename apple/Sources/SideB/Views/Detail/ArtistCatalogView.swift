import SwiftUI
import AppKit
import SideBCore

/// The filtered browse page behind an artist carousel's "Ver todo" action.
struct ArtistCatalogView: View {
    let browseId: String
    let params: String?
    let title: String
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    var router: NavigationRouter?

    @State private var cards: [BrowseCardRecord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))

                if isLoading {
                    ProgressView("Cargando…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text("No se pudo cargar el catálogo")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Reintentar") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else if cards.isEmpty {
                    ContentUnavailableView("No hay publicaciones", systemImage: "square.stack")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18)], alignment: .leading, spacing: 24) {
                        ForEach(cards, id: \.id) { card in
                            CatalogCardView(
                                card: card,
                                rustCore: rustCore,
                                playerViewModel: playerViewModel,
                                router: router,
                                artistBrowseId: browseId
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 120)
        }
        .task(id: "\(browseId)|\(params ?? "")") { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            cards = try await rustCore.getBrowseGrid(browseId: browseId, params: params)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct CatalogCardView: View {
    let card: BrowseCardRecord
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    var router: NavigationRouter?
    var artistBrowseId: String? = nil
    var origin: MenuOrigin? = nil

    var body: some View {
        let isArtist = card.kind.lowercased() == "artist"
        let isCollection = ["album", "playlist"].contains(card.kind.lowercased())
        let isActive = MediaPlaybackIdentity.isCollectionActive(
            kind: card.kind, id: card.id, context: playerViewModel.queueManager.context
        )
        let artwork = Group {
            if let thumbnail = card.thumbnail,
               let url = ImageURLHelper.optimizedThumbnailURL(from: thumbnail, targetPixelSize: 360) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 180, height: 180)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { placeholder }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: AppTheme.artworkCardRadius)))
            } else {
                placeholder
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: AppTheme.artworkCardRadius)))
            }
        }

        let content = VStack(alignment: .leading, spacing: 7) {
            if isCollection {
                MediaArtworkControls(
                    isCollection: true,
                    isActive: isActive,
                    isPlaying: isActive && playerViewModel.isPlaying,
                    isLoading: isCollectionLoading,
                    showsIndicator: isActive,
                    accessibilityTitle: card.title,
                    onOpen: open,
                    onPlay: { playerViewModel.activateMediaCollection(id: card.id, kind: card.kind) },
                    menuProvider: collectionMenu
                ) { artwork }
                    .aspectRatio(1, contentMode: .fit)
            } else if isArtist {
                Button(action: open) { artwork }
                    .buttonStyle(.plain)
                    .mediaCardFocusControl()
            } else {
                MediaArtworkControls(
                    isCollection: false,
                    accessibilityTitle: card.title,
                    onOpen: open,
                    onPlay: open,
                    menuProvider: songMenu
                ) { artwork }
                    .aspectRatio(1, contentMode: .fit)
            }

            Button(action: open) {
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .mediaCardFocusControl()
        }

        content
        .mediaCardActivation(label: "Abrir \(card.title)", action: open)
        .mediaCardSurface()
        .browseCardContextMenu(
            card: card,
            player: playerViewModel,
            router: router,
            core: rustCore,
            origin: origin ?? (artistBrowseId.map { .artist(channelId: $0) } ?? .album(browseId: card.id)),
            knownArtistId: artistBrowseId
        )
    }

    private func collectionMenu() -> NSMenu? {
        let factory = AppContextMenuFactory.shared
        if card.kind.lowercased() == "album" {
            return factory.buildAlbumNSMenu(browseId: card.id, playlistId: nil, title: card.title,
                artist: card.subtitle, thumbnail: card.thumbnail,
                origin: cardMenuOrigin,
                player: playerViewModel, router: router, core: rustCore)
        }
        return factory.buildPlaylistNSMenu(id: card.id, title: card.title, subtitle: card.subtitle,
            thumbnail: card.thumbnail, origin: cardMenuOrigin,
            player: playerViewModel, router: router, core: rustCore)
    }

    private var isCollectionLoading: Bool {
        if card.kind.lowercased() == "album" {
            return playerViewModel.loadingRecommendedAlbumID.map(MenuIDNormalizer.normalize) == MenuIDNormalizer.normalize(card.id)
        }
        return playerViewModel.loadingRecommendedPlaylistID.map(MenuIDNormalizer.canonicalPlaylistId) == MenuIDNormalizer.canonicalPlaylistId(card.id)
    }

    private var cardMenuOrigin: MenuOrigin {
        if let origin { return origin }
        if let artistBrowseId { return .artist(channelId: artistBrowseId) }
        if card.kind.lowercased() == "album" { return .album(browseId: card.id) }
        return .playlist(id: card.id)
    }

    private func songMenu() -> NSMenu? {
        guard card.kind == "song" || card.kind == "video" else { return nil }
        return AppContextMenuFactory.shared.buildSongNSMenu(
            song: SongItemRecord(fromCard: card, knownArtistId: artistBrowseId),
            player: playerViewModel, router: router, core: rustCore,
            origin: cardMenuOrigin
        )
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: AppTheme.artworkCardRadius)
            .fill(Color.secondary.opacity(0.12))
            .overlay(Image(systemName: "opticaldisc").foregroundStyle(.secondary))
    }

    private func open() {
        switch card.kind {
        case "album": router?.navigate(to: .album(browseId: card.id))
        case "artist": router?.navigate(to: .artist(browseId: card.id))
        case "playlist": router?.navigate(to: .playlist(browseId: card.id))
        case "song", "video":
            playerViewModel.activateMediaRadio(SongItemRecord(fromCard: card, knownArtistId: artistBrowseId))
        default: break
        }
    }
}
