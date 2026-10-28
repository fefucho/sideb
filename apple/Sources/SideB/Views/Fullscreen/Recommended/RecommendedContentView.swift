import SwiftUI
import AppKit
import SideBCore

/// Fullscreen discovery keeps its compact shelves; native viewports own scrolling and reuse.
struct RecommendedContentView: View {
    @Bindable var viewModel: PlayerViewModel
    var router: NavigationRouter?
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: PlayerViewModel, router: NavigationRouter? = nil, height: CGFloat) {
        self.viewModel = viewModel
        self.router = router
        self.height = height
    }

    var body: some View {
        VStack(spacing: 10) {
            // Cabecera Contextual con Botón de Actualizar
            headerBar

            // Contenido dinámico según el estado de carga y datos
            if viewModel.isLoadingRecommended && viewModel.recommendedData == nil {
                loadingSkeletonView
            } else if let data = viewModel.recommendedData, !data.isEmpty {
                RecommendedShelfViewport(data: data, player: viewModel, router: router)
                    .padding(.horizontal, 4)
            } else {
                emptyStateView
            }
        }
        .frame(height: height)
        .task(id: viewModel.recommendationContextKey) {
            // Lazy load garantizado: al activarse este panel, carga si no estaba en caché
            if let track = viewModel.currentTrack {
                viewModel.fetchRecommendations(for: track)
            }
        }
        .onDisappear { viewModel.cancelRecommendationLoading() }
    }

    // MARK: - 1. Cabecera Contextual
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Text(L10n.text("fullscreen.recommendations"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Spacer(minLength: 8)

            // Botón Cápsula "Actualizar" (aplica rotación y diversidad a la radio)
            Button {
                viewModel.refreshRecommendations()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .symbolEffect(.rotate, options: .repeating, isActive: viewModel.isLoadingRecommended && !reduceMotion)

                    Text(L10n.text("common.refresh"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.80))
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentTrack == nil || viewModel.isLoadingRecommended)
            .accessibilityLabel(L10n.text("fullscreen.refreshRecommendations"))
            .help(L10n.text("fullscreen.refreshRecommendations"))
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }

    // MARK: - 3. Estado de Carga (Skeletons)
    private var loadingSkeletonView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 140, height: 16)

                        HStack(spacing: 12) {
                            ForEach(0..<2, id: \.self) { _ in
                                VStack(spacing: 8) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        HStack(spacing: 10) {
                                            RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius)
                                                .fill(Color.white.opacity(0.10))
                                                .frame(width: 44, height: 44)
                                            VStack(alignment: .leading, spacing: 4) {
                                                RoundedRectangle(cornerRadius: 3)
                                                    .fill(Color.white.opacity(0.12))
                                                    .frame(width: 120, height: 12)
                                                RoundedRectangle(cornerRadius: 3)
                                                    .fill(Color.white.opacity(0.08))
                                                    .frame(width: 80, height: 10)
                                            }
                                        }
                                        .frame(width: 250, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 4. Estado Vacío
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.25))

            Text(L10n.text("fullscreen.noRecommendations"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.60))

            Button(L10n.text("common.retry")) {
                if let track = viewModel.currentTrack {
                    viewModel.fetchRecommendations(for: track, forceRefresh: true)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

// MARK: - RecommendedTrackRow
/// Shared artwork controls with observation confined to the visible song row.
struct RecommendedTrackRow: View {
    let track: SongItemRecord
    @Bindable var viewModel: PlayerViewModel
    var router: NavigationRouter?

    @State private var isHovered: Bool = false
    private var isCurrent: Bool { viewModel.currentTrack?.videoId == track.videoId }
    private var isPlaying: Bool { isCurrent && viewModel.isPlaying }

    var body: some View {
        HStack(spacing: 10) {
            MediaArtworkControls(
                isCollection: false,
                isActive: isCurrent,
                isPlaying: isPlaying,
                showsIndicator: isCurrent,
                accessibilityTitle: track.title,
                onOpen: { activate() },
                onPlay: { activate() },
                menuProvider: {
                    AppContextMenuFactory.shared.buildSongNSMenu(song: track, player: viewModel,
                        router: router, core: viewModel.rustCore, origin: .recommendations)
                }
            ) {
                if let thumb = track.thumbnail,
                   let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 96) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 44, height: 44)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                FeaturedTrackTitle(track: track, font: .system(size: 12.5, weight: .medium),
                                   color: .white.opacity(0.95), pointSize: 12.5, onNavigate: navigateToArtist)
                metadataLinks
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 44)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCurrent ? Color.sidebActiveRowBackground : (isHovered ? Color.white.opacity(0.09) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isCurrent ? Color.sidebActiveRowBorder : Color.clear, lineWidth: AppTheme.cardBorderWidth)
                )
        )
        .contentShape(Rectangle())
        .mediaCardActivation(label: L10n.text(isPlaying ? "player.pauseNamedTrack" : "player.playNamedTrack", args: [track.title])) { activate() }
        .mediaCardSurface()
        .onHover { isHovered = $0 }
        .songContextMenu(
            song: track,
            player: viewModel,
            router: router,
            core: viewModel.rustCore,
            origin: .recommendations
        )
    }

    private func activate() {
        if isCurrent { viewModel.togglePlayPause() }
        else { viewModel.activateMediaRadio(track) }
    }

    private func navigate(_ destination: PageDestination) {
        guard let router else { return }
        viewModel.dismissFullscreen()
        router.navigate(to: destination)
    }

    private func navigateToArtist(_ id: String?, _ name: String) {
        navigate(id.map { .artist(browseId: $0) } ?? .search(query: name))
    }

    @ViewBuilder
    private var metadataLinks: some View {
        ContentRatedMetadata(rating: track.contentRating, fontSize: 11) {
            HStack(spacing: 4) {
                TrackArtistLinks(track: track, font: .system(size: 11), color: .white.opacity(0.55),
                                 hoverColor: .white, onNavigate: navigateToArtist)

                if let album = track.displayAlbum, !album.isEmpty {
                    Text("•").foregroundStyle(.white.opacity(0.45)).allowsHitTesting(false)
                    if let albumId = track.albumId, !albumId.isEmpty {
                        Button { navigate(.album(browseId: albumId)) } label: {
                            Text(album).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .mediaCardFocusControl()
                    } else {
                        Text(album).foregroundStyle(.white.opacity(0.55)).lineLimit(1).allowsHitTesting(false)
                    }
                }
            }
            .font(.system(size: 11, weight: .regular))
        }
    }
}

// MARK: - RecommendedArtistCard
/// Tarjeta circular de artista similar inspirada en sideb OLD.
struct RecommendedArtistCard: View {
    let card: BrowseCardRecord
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    if let thumb = card.thumbnail,
                       let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 160) {
                        CachedAsyncImage(url: url, targetSize: CGSize(width: 76, height: 76)) { img in
                            img
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 76, height: 76)
                                .clipShape(Circle())
                        } placeholder: {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 76, height: 76)
                        }
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 76, height: 76)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                    }

                    if isHovered {
                        Circle()
                            .fill(Color.black.opacity(0.38))
                            .overlay {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                    }
                }
                .frame(width: 76, height: 76)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isHovered ? 0.25 : 0.10), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.10), radius: 6, x: 0, y: 3)

                Text(card.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 86)
                if card.contentRating != .unknown {
                    ContentRatedMetadata(rating: card.contentRating, fontSize: 11) {
                        if let subtitle = card.subtitle, !subtitle.isEmpty { Text(subtitle).lineLimit(1) }
                    }
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(L10n.text("detail.artist.viewNamed", args: [card.title]))
    }
}
