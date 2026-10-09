import SwiftUI
import SideBCore

// MARK: - FullscreenPanel

public enum FullscreenPanel: String, CaseIterable, Identifiable {
    case queue = "Cola"
    case lyrics = "Letras"
    case recommended = "Relacionado"
    
    public var id: String { self.rawValue }
    var title: String {
        switch self {
        case .queue: L10n.text("queue.title")
        case .lyrics: L10n.text("fullscreen.lyrics")
        case .recommended: L10n.text("fullscreen.related")
        }
    }
    
    public var icon: String {
        switch self {
        case .queue: return "list.bullet"
        case .lyrics: return "quote.bubble"
        case .recommended: return "music.note.list"
        }
    }
}

// MARK: - FullscreenNowPlayingView (Proporcional 60/40, Sólido y Resistente a Resizing)

struct FullscreenNowPlayingView: View, Animatable {
    @Bindable var viewModel: PlayerViewModel
    let canvasSize: CGSize
    var sidebarProgress: CGFloat
    var router: NavigationRouter? = nil
    
    private var selectedPanel: FullscreenPanel {
        get { viewModel.selectedFullscreenPanel }
        nonmutating set { viewModel.selectedFullscreenPanel = newValue }
    }

    private var localizedQueueContextTitle: String {
        viewModel.queueManager.displayContextTitle
    }
    @State private var isHoveringArtwork: Bool = false
    @State private var isHoveringAlbum: Bool = false
    @State private var failedOriginalURL: URL? = nil
    @State private var failedMaxQualityURL: URL? = nil
    @State private var isArtworkFlipped = false
    
    @Namespace private var tabNamespace
    
    var animatableData: CGFloat {
        get { sidebarProgress }
        set { sidebarProgress = newValue }
    }

    var body: some View {
        let geometry = FullscreenSidebarGeometry(canvasSize: canvasSize, progress: sidebarProgress)
        let layout = geometry.metrics
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.topPadding)
            HStack(alignment: .top, spacing: layout.columnSpacing) {
                // One block and one interpolated coordinate system for
                // artwork, title, credits and actions throughout resize.
                VStack(alignment: .leading, spacing: layout.metadataSpacing) {
                    artworkView(size: layout.artworkSize)
                    trackInfoView(width: layout.artworkSize)
                        .frame(height: layout.metadataHeight, alignment: .top)
                }
                .frame(width: layout.artworkSize, height: layout.artworkBlockHeight)
                .frame(width: layout.leftWidth, height: layout.availableContentHeight, alignment: .center)

                VStack(alignment: .center, spacing: 14) {
                    compactTabBar
                    contentPanelView(height: layout.contentPanelHeight)
                        .frame(width: layout.rightWidth, height: layout.contentPanelHeight)
                }
                .frame(width: layout.rightWidth, height: layout.availableContentHeight, alignment: .top)
                .windowGestureRegion(.verticalContent)
            }
            .frame(height: layout.availableContentHeight)
            .padding(.horizontal, layout.horizontalPadding)
            Spacer(minLength: 0)
            Color.clear.frame(height: layout.bottomReservedHeight)
        }
        .frame(width: layout.viewport.width, height: layout.viewport.height)
        .clipped()
        .offset(x: geometry.contentOffset)
        // Only the shared sidebar progress interpolates this scene's geometry.
        .transaction { if geometry.isTransitioning { $0.animation = nil } }
        .compositingGroup()
        .onExitCommand {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                viewModel.isFullscreenPresented = false
            }
        }
        .onChange(of: viewModel.currentTrack?.videoId) { _, _ in
            failedOriginalURL = nil
            failedMaxQualityURL = nil
            isArtworkFlipped = false
        }
    }
    
    // MARK: - Módulo Artwork (1:1 Cuadrado con Play/Pause en click y oscurecimiento en hover)
    private func artworkView(size: CGFloat) -> some View {
        let originalUrl = ImageURLHelper.originalArtworkURL(from: viewModel.currentTrack?.thumbnail)
        let maxQualityUrl = ImageURLHelper.maxQualityArtworkURL(
            from: viewModel.currentTrack?.thumbnail,
            videoId: viewModel.currentTrack?.videoId
        )
        let fallbackUrl = ImageURLHelper.fallbackThumbnailURL(
            from: viewModel.currentTrack?.thumbnail,
            targetPixelSize: 544
        )

        let activeArtworkUrl: URL? = {
            if let originalUrl, failedOriginalURL != originalUrl {
                return originalUrl
            }
            if let maxQualityUrl, failedMaxQualityURL != maxQualityUrl {
                return maxQualityUrl
            }
            return fallbackUrl
        }()

        return ZStack {
            artworkFront(
                size: size,
                originalUrl: originalUrl,
                maxQualityUrl: maxQualityUrl,
                activeArtworkUrl: activeArtworkUrl
            )
            .opacity(isArtworkFlipped ? 0 : 1)
            .rotation3DEffect(.degrees(isArtworkFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .allowsHitTesting(!isArtworkFlipped)

            artworkInformationCard(size: size)
                .opacity(isArtworkFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(isArtworkFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .allowsHitTesting(isArtworkFlipped)
                .windowGestureRegion(.verticalContent, active: isArtworkFlipped)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.42), radius: 22, x: 0, y: 10)
        .animation(.easeInOut(duration: 0.48), value: isArtworkFlipped)
    }

    private func artworkFront(size: CGFloat, originalUrl: URL?, maxQualityUrl: URL?, activeArtworkUrl: URL?) -> some View {
        ZStack {
            if let activeArtworkUrl {
                CachedAsyncImage(
                    url: activeArtworkUrl,
                    targetSize: CGSize(width: 1200, height: 1200),
                    onFailure: {
                        if activeArtworkUrl == originalUrl {
                            self.failedOriginalURL = originalUrl
                        } else if activeArtworkUrl == maxQualityUrl {
                            self.failedMaxQualityURL = maxQualityUrl
                        }
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                } placeholder: {
                    artworkPlaceholder(size: size)
                }
                .id("art_\(viewModel.currentTrack?.videoId ?? activeArtworkUrl.absoluteString)")
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous))
            } else {
                fallbackArtwork(size: size)
                    .frame(width: size, height: size)
            }

            // Capa de oscurecimiento sutil en hover
            RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous)
                .fill(Color.black.opacity(isHoveringArtwork ? 0.22 : 0.0))
                .animation(.easeInOut(duration: 0.18), value: isHoveringArtwork)

            // Icono sutil de play/pausa que aparece en hover
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: max(28, size * 0.14), weight: .bold))
                .foregroundStyle(Color.white.opacity(isHoveringArtwork ? 0.92 : 0.0))
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                .animation(.easeInOut(duration: 0.18), value: isHoveringArtwork)
        }
        .frame(width: size, height: size)
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous))
        .onHover { isHoveringArtwork = $0 }
        .onTapGesture {
            viewModel.togglePlayPause()
        }
    }

    private func artworkInformationCard(size: CGFloat) -> some View {
        let song = viewModel.genius.resolution?.song
        let track = viewModel.currentTrack
        let displayTitle = song?.title ?? track?.title ?? L10n.text("common.untitled")
        let displayArtist = song?.artist ?? track?.displayArtist ?? ""

        return VStack(alignment: .leading, spacing: size < 300 ? 8 : 13) {
            HStack(alignment: .center) {
                Label(L10n.text("fullscreen.information"), systemImage: "info.circle.fill")
                    .font(.system(size: size < 300 ? 13 : 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 4)
                Button {
                    isArtworkFlipped = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .buttonStyle(.plain)
                .help(L10n.text("fullscreen.backToArtwork"))
                .accessibilityLabel(L10n.text("fullscreen.backToArtwork"))
            }

            Text(displayTitle)
                .font(.system(size: size < 300 ? 16 : 20, weight: .bold))
                .lineLimit(2)
            if !displayArtist.isEmpty {
                Text(displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }

            if let song {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let description = song.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: size < 300 ? 12 : 14))
                                .foregroundStyle(.white.opacity(0.88))
                                .textSelection(.enabled)
                        } else {
                            Text(L10n.text("fullscreen.noSongDescription"))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        if let date = song.releaseDate, !date.isEmpty {
                            Label(date, systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        if !song.producers.isEmpty {
                            informationCredit(L10n.text("genius.production"), names: song.producers)
                        }
                        if !song.writers.isEmpty {
                            informationCredit(L10n.text("genius.composition"), names: song.writers)
                        }
                        ForEach(Array(song.performances.enumerated()), id: \.offset) { _, item in
                            informationCredit(item.label, names: item.artists)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer(minLength: 4)
                if viewModel.genius.phase == .loading {
                    ProgressView(L10n.text("genius.searchingInformation"))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack(alignment: .center, spacing: 6) {
                        Text(L10n.text("genius.noAdditionalInformation"))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                        if let album = track?.album, !album.isEmpty {
                            Label(album, systemImage: "opticaldisc")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.50))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                Spacer(minLength: 4)
            }

            Button {
                viewModel.toggleLyricsPanel(genius: true)
            } label: {
                Label(L10n.text("genius.lyricsAndAnnotations"), systemImage: "text.book.closed")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .padding(size < 300 ? 16 : 22)
        .frame(width: size, height: size, alignment: .topLeading)
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous))
        .onAppear { if isArtworkFlipped { viewModel.genius.ensureNow() } }
    }

    private func informationCredit(_ title: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary)
            Text(names.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.86))
        }
    }

    @ViewBuilder
    private func artworkPlaceholder(size: CGFloat) -> some View {
        if let thumbStr = viewModel.currentTrack?.thumbnail {
            let cachedImage: NSImage? = {
                if let url1200 = ImageURLHelper.maxQualityArtworkURL(from: thumbStr),
                   let img = ImageCache.shared.imageFromMemoryCache(for: url1200, targetSize: CGSize(width: 1200, height: 1200)) {
                    return img
                }
                if let url544 = ImageURLHelper.fallbackThumbnailURL(from: thumbStr, targetPixelSize: 544),
                   let img = ImageCache.shared.imageFromMemoryCache(for: url544, targetSize: CGSize(width: 1200, height: 1200)) {
                    return img
                }
                if let url300 = ImageURLHelper.optimizedThumbnailURL(from: thumbStr, targetPixelSize: 300),
                   let img = ImageCache.shared.imageFromMemoryCache(for: url300, targetSize: CGSize(width: 300, height: 300)) {
                    return img
                }
                if let url92 = ImageURLHelper.optimizedThumbnailURL(from: thumbStr, targetPixelSize: 92),
                   let img = ImageCache.shared.imageFromMemoryCache(for: url92, targetSize: CGSize(width: 92, height: 92)) {
                    return img
                }
                return nil
            }()

            if let cachedImage {
                Image(nsImage: cachedImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            } else {
                fallbackArtwork(size: size)
            }
        } else {
            fallbackArtwork(size: size)
        }
    }
    
    private func fallbackArtwork(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: min(size * 0.25, 60)))
                    .foregroundStyle(.white.opacity(0.3))
            )
    }
    
    // MARK: - Módulo Track Info (Título + Artista • Álbum + Me Gusta, directo sobre el fondo)
    private func trackInfoView(width: CGFloat) -> some View {
        let typography = FullscreenSceneMetrics.typography(artworkWidth: width)
        let titleSize = typography.title
        let subtitleSize = typography.subtitle
        
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                // Título de la Canción (Bold prominente estilo cartel Now Playing)
                Text(viewModel.currentTrack?.title ?? L10n.text("player.noPlayback"))
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                // Artista • Álbum con enlaces interactivos (sin subrayado)
                HStack(spacing: 7) {
                    if let track = viewModel.currentTrack, !track.displayArtist.isEmpty {
                        TrackArtistLinks(track: track, font: .system(size: subtitleSize, weight: .semibold), color: .white.opacity(0.78), hoverColor: .white) { id, name in
                            navigateToArtist(track: track, artistId: id, name: name)
                        }
                    } else {
                        Text(L10n.text("player.selectTrack"))
                            .font(.system(size: subtitleSize, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    
                    if let track = viewModel.currentTrack, let album = track.displayAlbum, !album.isEmpty {
                        Text("•")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.40))
                        
                        Button {
                            navigateToAlbum(track: track)
                        } label: {
                            Text(album)
                                .font(.system(size: max(12, subtitleSize - 0.5), weight: .medium))
                                .foregroundStyle(isHoveringAlbum ? Color.white : Color.white.opacity(0.60))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .onHover { isHoveringAlbum = $0 }
                        .help(L10n.text("player.goToAlbum", args: [album]))
                        .accessibilityLabel(L10n.text("player.goToAlbum", args: [album]))
                    }
                }
            }
            .contextMenu {
                if let track = viewModel.currentTrack {
                    SongMenuItems(song: track, player: viewModel, router: router, core: viewModel.rustCore, origin: .nowPlaying)
                }
            }
            
            Spacer(minLength: 8)
            
            // Botón Me Gusta (Sutil y sincronizado con PlayerViewModel)
            Button {
                viewModel.toggleCurrentTrackLike()
            } label: {
                Image(systemName: viewModel.isCurrentTrackLiked ? "heart.fill" : "heart")
                    .font(.system(size: typography.action, weight: .semibold))
                    .foregroundStyle(viewModel.isCurrentTrackLiked ? Color.white : Color.white.opacity(0.70))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.text(viewModel.isCurrentTrackLiked ? "detail.track.unlike" : "detail.track.like"))
            .accessibilityLabel(L10n.text(viewModel.isCurrentTrackLiked ? "detail.track.unlike" : "detail.track.like"))

            Button {
                isArtworkFlipped.toggle()
                if isArtworkFlipped { viewModel.genius.ensureNow() }
            } label: {
                Image(systemName: isArtworkFlipped ? "info.circle.fill" : "info.circle")
                    .font(.system(size: typography.action, weight: .semibold))
                    .foregroundStyle(isArtworkFlipped ? Color.white : Color.white.opacity(0.70))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentTrack == nil)
            .help(L10n.text(isArtworkFlipped ? "fullscreen.backToArtwork" : "fullscreen.songInformation"))
            .accessibilityLabel(L10n.text(isArtworkFlipped ? "fullscreen.backToArtwork" : "fullscreen.songInformation"))
        }
        .frame(width: width, alignment: .leading)
    }
    
    // MARK: - Selector de Pestañas Cápsula (Centrado en su columna, estilo Apple Music / sideb OLD)
    private var compactTabBar: some View {
        HStack(spacing: 0) {
            ForEach(FullscreenPanel.allCases) { panel in
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                        selectedPanel = panel
                    }
                    if panel == .recommended, let track = viewModel.currentTrack {
                        viewModel.fetchRecommendations(for: track)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: panel.icon)
                            .font(.system(size: 12.5, weight: selectedPanel == panel ? .semibold : .medium))
                Text(panel.title)
                            .font(.system(size: 13, weight: selectedPanel == panel ? .semibold : .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundStyle(selectedPanel == panel ? Color.white : Color.white.opacity(0.65))
                    .background {
                        if selectedPanel == panel {
                            Capsule()
                                .fill(Color.sidebAccent)
                                .matchedGeometryEffect(id: "fullscreenTabIndicator", in: tabNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }
    
    // MARK: - Panel de Contenido (Sin tarjeta gris ni borde, flotando directo sobre el fondo)
    private func contentPanelView(height: CGFloat) -> some View {
        ZStack {
            switch selectedPanel {
            case .queue:
                queuePanel(height: height)
            case .lyrics:
                lyricsPanel(height: height)
            case .recommended:
                recommendedPanel(height: height)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
    
    // MARK: - Contenido: Cola de Reproducción (120 FPS, transparente, sin columnas innecesarias)
    @ViewBuilder
    private func queuePanel(height: CGFloat) -> some View {
        if viewModel.queueManager.queue.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 38))
                    .foregroundStyle(.white.opacity(0.25))
                Text(L10n.text("queue.empty"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                // Cabecera Contextual de la Cola Dinámica
                HStack(spacing: 8) {
                    Image(systemName: viewModel.queueManager.context?.iconName ?? "music.note.list")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(localizedQueueContextTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .fixedSize()
                    
                    Text(L10n.songCount(viewModel.queueManager.queue.count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize()
                    
                    Spacer(minLength: 4)
                    
                    if viewModel.queueManager.isLoadingRadio || viewModel.queueManager.isLoadingAutoplay {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text(L10n.text("common.loading"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .fixedSize()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
                
                NativeTrackTableView(
                    tracks: viewModel.queueManager.tracks,
                    currentTrackVideoId: viewModel.currentTrack?.videoId,
                    isPlaying: viewModel.isPlaying,
                    playerViewModel: viewModel,
                    router: router,
                    presentation: .queue,
                    hideAlbumColumn: true,
                    showAlbumInSubtitle: true,
                    isReorderable: true,
                    rowHeight: 46.0,
                    likedVideoIds: viewModel.likedVideoIds,
                    menuOrigin: { .queue(occurrenceIndex: $0) },
                    onPlayTrack: { index in
                        viewModel.playQueueIndex(index)
                    },
                    onLikeTrack: { track in
                        viewModel.toggleTrackLike(track)
                    },
                    onDislikeTrack: { track in
                        viewModel.dislikeTrack(track)
                    },
                    onMoveTrack: { from, to in
                        viewModel.moveQueueTrack(from: from, to: to)
                    },
                    contentInsets: NSEdgeInsets(top: 2, left: 0, bottom: 4, right: 0)
                )
                .frame(maxWidth: .infinity)
                .frame(height: max(0, height - 28))
            }
            .frame(height: height)
        }
    }
    
    // MARK: - Contenido: Letras Sincronizadas
    private func lyricsPanel(height: CGFloat) -> some View {
        Group {
            if viewModel.isShowingGeniusLyrics {
                GeniusPanelView(model: viewModel.genius)
                    .id(viewModel.currentTrack?.videoId)
            } else {
                nativeLyricsPanel(height: height)
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func nativeLyricsPanel(height: CGFloat) -> some View {
        if viewModel.isLoadingLyrics {
            VStack(spacing: 12) {
                ProgressView()
                Text(L10n.text("fullscreen.searchingSyncedLyrics"))
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let lyrics = viewModel.lyricsInfo, !lyrics.lines.isEmpty {
            SyncedLyricsPanel(
                lyrics: lyrics,
                currentTime: viewModel.currentTime,
                duration: viewModel.duration,
                height: height,
                onSeek: { viewModel.seek(toFraction: $0) }
            )
            .id(viewModel.currentTrack?.videoId)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.25))
                Text(L10n.text("fullscreen.noLyrics"))
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(L10n.text("fullscreen.noSyncedLyricsForTrack"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Contenido: Recomendaciones (Estantes Liquid Glass a 120 FPS)
    @ViewBuilder
    private func recommendedPanel(height: CGFloat) -> some View {
        RecommendedContentView(viewModel: viewModel, router: router, height: height)
    }
    
    // MARK: - Navegación
    private func navigateToArtist(track: SongItemRecord, artistId: String?, name: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            viewModel.isFullscreenPresented = false
        }
        if let browseId = artistId ?? (track.artistRuns.isEmpty ? track.artistId ?? viewModel.currentArtistBrowseId : nil) {
            router?.navigate(to: .artist(browseId: browseId))
        } else {
            router?.navigate(to: .search(query: name))
        }
    }
    
    private func navigateToAlbum(track: SongItemRecord) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            viewModel.isFullscreenPresented = false
        }
        if let browseId = track.albumId ?? viewModel.currentAlbumBrowseId {
            router?.navigate(to: .album(browseId: browseId))
        } else if let albumName = track.displayAlbum {
            router?.navigate(to: .search(query: "\(albumName) \(track.displayArtist)"))
        }
    }
}

// MARK: - Lyrics presentation and follow mode

enum LyricTiming {
    static func activeIndex(in lyrics: LyricsInfo, at seconds: Double) -> Int? {
        guard lyrics.isSynced, seconds.isFinite else { return nil }
        let timeMs = max(0, seconds) * 1_000
        var firstTimed: (index: Int, start: UInt64)?
        var active: (index: Int, start: UInt64)?
        for (index, line) in lyrics.lines.enumerated() {
            guard let start = line.timeMs else { continue }
            if firstTimed == nil || start < firstTimed!.start {
                firstTimed = (index, start)
            }
            if Double(start) <= timeMs && (active == nil || start >= active!.start) {
                active = (index, start)
            }
        }
        return active?.index ?? firstTimed?.index
    }
}

private struct SyncedLyricsPanel: View {
    let lyrics: LyricsInfo
    let currentTime: Double
    let duration: Double
    let height: CGFloat
    let onSeek: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isFollowing = true

    private var activeIndex: Int? { LyricTiming.activeIndex(in: lyrics, at: currentTime) }
    private var canFollow: Bool { activeIndex != nil }
    private var transition: Animation? {
        reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86)
    }

    var body: some View {
        ScrollViewReader { proxy in
            let currentIndex = activeIndex
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                        lyricRow(index: index, line: line, activeIndex: currentIndex)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                // Keep natural scroll bounds: the first and last lines only
                // reach center when the surrounding content allows it.
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                // Programmatic scrollTo enters .animating. Only an input gesture
                // should take control away from the lyric follower.
                if canFollow && (phase == .tracking || phase == .interacting) {
                    isFollowing = false
                }
            }
            .overlay(alignment: .bottom) {
                if canFollow && !isFollowing {
                    Button {
                        isFollowing = true
                        centerCurrentLine(using: proxy, animated: true)
                    } label: {
                        Label(L10n.text("fullscreen.returnToCurrentLyric"), systemImage: "location.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 10)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if reduceTransparency {
                            Capsule().fill(Color.sidebDarkBackground)
                        } else {
                            Capsule().fill(.clear).compatGlass(interactive: true, in: Capsule())
                        }
                    }
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .help(L10n.text("fullscreen.resumeLyricsTracking"))
                    .accessibilityLabel(L10n.text("fullscreen.resumeLyricsTracking"))
                    .accessibilityHint(L10n.text("fullscreen.resumeLyricsTrackingHint"))
                }
            }
            .animation(transition, value: isFollowing)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .onAppear {
                // Wait for the ScrollView to lay out before the initial centering.
                Task { @MainActor in
                    await Task.yield()
                    if isFollowing { centerCurrentLine(using: proxy, animated: false) }
                }
            }
            .onChange(of: currentIndex) { _, _ in
                if isFollowing { centerCurrentLine(using: proxy, animated: true) }
            }
        }
    }

    @ViewBuilder
    private func lyricRow(index: Int, line: LyricLineInfo, activeIndex: Int?) -> some View {
        let text = Text(line.text.isEmpty ? "•••" : line.text)
            .font(.system(size: 25.2, weight: index == activeIndex ? .semibold : .medium))
            .foregroundStyle(Color.white.opacity(opacity(for: index, activeIndex: activeIndex)))
            .scaleEffect(index == activeIndex ? 1.025 : 1, anchor: .leading)
            .shadow(color: .white.opacity(index == activeIndex ? 0.22 : 0), radius: 9)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(transition, value: activeIndex)

        if let milliseconds = line.timeMs, duration.isFinite, duration > 0 {
            Button {
                onSeek(min(1, max(0, Double(milliseconds) / 1_000 / duration)))
            } label: {
                text
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(index == activeIndex ? [.isSelected] : [])
            .accessibilityHint(L10n.text("fullscreen.goToLyricLine"))
        } else {
            text
        }
    }

    private func opacity(for index: Int, activeIndex: Int?) -> Double {
        guard let activeIndex else { return 0.82 }
        if index == activeIndex { return 1 }
        return abs(index - activeIndex) == 1 ? 0.60 : 0.36
    }

    private func centerCurrentLine(using proxy: ScrollViewProxy, animated: Bool) {
        guard let activeIndex else { return }
        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.94)) {
                proxy.scrollTo(activeIndex, anchor: .center)
            }
        } else {
            proxy.scrollTo(activeIndex, anchor: .center)
        }
    }
}
