import SwiftUI
import AppKit
import SideBCore

// MARK: - RecommendedContentView
/// Vista de descubrimiento y recomendaciones musicales en modo Fullscreen.
/// Organiza 4 estantes Liquid Glass a 120 FPS inspirados en el diseño probado de sideb OLD:
/// 1. "Más de [Artista]" (canciones populares del artista)
/// 2. "Del mismo álbum: [Álbum]" (pistas del disco en reproducción)
/// 3. "Canciones parecidas" (canciones con estilo, género y vibra afines devueltas por el endpoint Related de YouTube Music)
/// 4. "A los fans también les gusta" (artistas similares con avatares circulares)
struct RecommendedContentView: View {
    @Bindable var viewModel: PlayerViewModel
    var router: NavigationRouter?
    let height: CGFloat
    
    @State private var isSpinningRefresh: Bool = false
    
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
                shelvesScrollView(data: data)
            } else {
                emptyStateView
            }
        }
        .frame(height: height)
        .task(id: viewModel.currentTrack?.videoId) {
            // Lazy load garantizado: al activarse este panel, carga si no estaba en caché
            if let track = viewModel.currentTrack {
                viewModel.fetchRecommendations(for: track)
            }
        }
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
                withAnimation(.linear(duration: 0.6)) {
                    isSpinningRefresh = true
                }
                viewModel.refreshRecommendations()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    isSpinningRefresh = false
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(isSpinningRefresh ? 360 : 0))
                    
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
            .help(L10n.text("fullscreen.refreshRecommendations"))
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }
    
    // MARK: - 2. Scroll de Estantes (Shelves)
    private func shelvesScrollView(data: RecommendedData) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                // Estante 1: Más del Artista
                if !data.artistSongs.isEmpty {
                    artistShelf(name: data.artistName, browseId: data.artistBrowseId, songs: data.artistSongs)
                }
                
                // Estante 2: Del mismo Álbum
                if !data.albumSongs.isEmpty {
                    albumShelf(title: data.albumTitle, browseId: data.albumBrowseId, songs: data.albumSongs)
                }
                
                // Estante 3: Te podría gustar (Pistas afines de YouTube Music)
                if !data.similarSongs.isEmpty {
                    similarSongsShelf(songs: data.similarSongs)
                }
                
                // Estante 4: A los fans también les gusta (Artistas similares)
                if !data.relatedArtists.isEmpty {
                    relatedArtistsShelf(artists: data.relatedArtists)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 24)
        }
    }
    
    // MARK: - Estante 1: Más del Artista
    private func artistShelf(name: String?, browseId: String?, songs: [SongItemRecord]) -> some View {
        let title = name.map { L10n.text("fullscreen.moreByArtist", args: [$0]) } ?? L10n.text("fullscreen.moreByThisArtist")
        let columns = chunkSongs(songs, chunkSize: 3)
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                
                Spacer()
                
                if let bId = browseId {
                    Button {
                        navigateToArtist(browseId: bId)
                    } label: {
                        HStack(spacing: 3) {
                            Text(L10n.text("detail.viewArtist"))
                                .font(.system(size: 11.5, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            horizontalSongColumns(columns: columns)
        }
    }
    
    // MARK: - Estante 2: Del mismo Álbum
    private func albumShelf(title: String?, browseId: String?, songs: [SongItemRecord]) -> some View {
        let displayTitle = title.map { L10n.text("fullscreen.fromAlbum", args: [$0]) } ?? L10n.text("fullscreen.fromSameAlbum")
        let columns = chunkSongs(songs, chunkSize: 3)
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(displayTitle)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                
                Spacer()
                
                if let bId = browseId {
                    Button {
                        navigateToAlbum(browseId: bId)
                    } label: {
                        HStack(spacing: 3) {
                            Text(L10n.text("detail.viewAlbum"))
                                .font(.system(size: 11.5, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            horizontalSongColumns(columns: columns)
        }
    }
    
    // MARK: - Estante 3: Canciones parecidas
    private func similarSongsShelf(songs: [SongItemRecord]) -> some View {
        let columns = chunkSongs(songs, chunkSize: 3)
        
        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("fullscreen.similarSongs"))
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
            
            horizontalSongColumns(columns: columns)
        }
    }
    
    // MARK: - Estante 4: A los fans también les gusta (Artistas)
    private func relatedArtistsShelf(artists: [BrowseCardRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("fullscreen.fansAlsoLike"))
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(artists, id: \.id) { card in
                        RecommendedArtistCard(card: card) {
                            navigateToArtist(browseId: card.id)
                        }
                        .browseCardContextMenu(card: card, player: viewModel, router: router, core: viewModel.rustCore, origin: .recommendations)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 118)
        }
    }
    
    // MARK: - Helper: Columnas Horizontales de Canciones
    private func horizontalSongColumns(columns: [[SongItemRecord]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(columns.indices, id: \.self) { colIndex in
                    VStack(spacing: 6) {
                        ForEach(columns[colIndex], id: \.videoId) { track in
                            RecommendedTrackRow(
                                track: track,
                                isCurrent: viewModel.currentTrack?.videoId == track.videoId,
                                isPlaying: viewModel.currentTrack?.videoId == track.videoId && viewModel.isPlaying,
                                viewModel: viewModel,
                                router: router
                            )
                        }
                    }
                    .frame(width: 270)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 162)
    }
    
    private func chunkSongs(_ songs: [SongItemRecord], chunkSize: Int) -> [[SongItemRecord]] {
        stride(from: 0, to: songs.count, by: chunkSize).map {
            Array(songs[$0..<min($0 + chunkSize, songs.count)])
        }
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
    
    // MARK: - Navegación
    private func navigateToArtist(browseId: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            viewModel.isFullscreenPresented = false
        }
        router?.navigate(to: .artist(browseId: browseId))
    }
    
    private func navigateToAlbum(browseId: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            viewModel.isFullscreenPresented = false
        }
        router?.navigate(to: .album(browseId: browseId))
    }
}

// MARK: - RecommendedTrackRow
/// Fila de canción estilizada para estantes de recomendaciones (44px, Liquid Glass, 120 FPS).
private struct RecommendedTrackRow: View {
    let track: SongItemRecord
    let isCurrent: Bool
    let isPlaying: Bool
    @Bindable var viewModel: PlayerViewModel
    var router: NavigationRouter?
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            MediaArtworkControls(
                isCollection: false,
                isActive: false,
                isPlaying: false,
                showsIndicator: false,
                accessibilityTitle: track.title,
                onOpen: { viewModel.activateMediaRadio(track) },
                onPlay: { viewModel.activateMediaRadio(track) },
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
                Text(track.title)
                    .font(.system(size: 12.5, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1)
                    .allowsHitTesting(false)
                metadataLinks
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        .mediaCardActivation(label: L10n.text("player.playNamedTrack", args: [track.title])) { viewModel.activateMediaRadio(track) }
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
    
    @ViewBuilder
    private var metadataLinks: some View {
        HStack(spacing: 4) {
            let linkedRuns = track.artistRuns.filter { $0.id?.isEmpty == false }
            if !linkedRuns.isEmpty {
                ForEach(Array(track.artistRuns.enumerated()), id: \.offset) { index, run in
                    if index > 0 {
                        Text("•").foregroundStyle(.white.opacity(0.45)).allowsHitTesting(false)
                    }
                    if let id = run.id, !id.isEmpty {
                        Button { router?.navigate(to: .artist(browseId: id)) } label: {
                            Text(run.text).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .mediaCardFocusControl()
                    } else {
                        Text(run.text).foregroundStyle(.white.opacity(0.55)).lineLimit(1).allowsHitTesting(false)
                    }
                }
            } else if let artistId = track.artistId, !artistId.isEmpty {
                Button { router?.navigate(to: .artist(browseId: artistId)) } label: {
                    Text(track.displayArtist).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                .buttonStyle(.plain)
                .mediaCardFocusControl()
            } else {
                Text(track.displayArtist).foregroundStyle(.white.opacity(0.55)).lineLimit(1).allowsHitTesting(false)
            }

            if let album = track.displayAlbum, !album.isEmpty {
                Text("•").foregroundStyle(.white.opacity(0.45)).allowsHitTesting(false)
                if let albumId = track.albumId, !albumId.isEmpty {
                    Button { router?.navigate(to: .album(browseId: albumId)) } label: {
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

// MARK: - RecommendedArtistCard
/// Tarjeta circular de artista similar inspirada en sideb OLD.
private struct RecommendedArtistCard: View {
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
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(L10n.text("detail.artist.viewNamed", args: [card.title]))
    }
}
