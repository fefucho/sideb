import AppKit
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
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorSchemeContrast) var contrast
    @Bindable var viewModel: PlayerViewModel
    let canvasSize: CGSize
    var sidebarProgress: CGFloat
    var router: NavigationRouter? = nil
    // The canvas may retain the outgoing surface for its closing animation.
    // Only presentation is retained: fetch/playback guards still use the live model.
    var presentationMode: PlaybackPresentation? = nil

    init(viewModel: PlayerViewModel, canvasSize: CGSize, sidebarProgress: CGFloat,
         router: NavigationRouter? = nil, presentationMode: PlaybackPresentation? = nil) {
        self.viewModel = viewModel
        self.canvasSize = canvasSize
        self.sidebarProgress = sidebarProgress
        self.router = router
        self.presentationMode = presentationMode
        // The lateral panel must mount lyrics at their final size. Changing it after the
        // first layout re-centers the list and shows up as a jump when the panel opens.
        let lateral = (presentationMode ?? viewModel.playbackPresentation.mode) == .sidebar
        let settings = LyricsPresentationSettings()
        if lateral { settings.fontSize = PlaybackSidebarLayout.lyricsFontSize }
        _lyricsPresentation = State(initialValue: settings)
    }

    private var isSidebarPresentation: Bool {
        (presentationMode ?? viewModel.playbackPresentation.mode) == .sidebar
    }

    var selectedPanel: FullscreenPanel {
        get { viewModel.selectedFullscreenPanel }
        nonmutating set { viewModel.selectedFullscreenPanel = newValue }
    }

    private var localizedQueueContextTitle: String {
        viewModel.queueManager.displayContextTitle
    }
    @State private var isArtworkFlipped = false
    @State private var isHoveringArtwork: Bool = false
    @State private var isHoveringAlbum: Bool = false
    @State private var failedOriginalURL: URL? = nil
    @State private var failedMaxQualityURL: URL? = nil
    @State private var geniusAnnotationColorMode = GeniusAnnotationColorMode.artwork
    @State private var isShowingExperimentalLyrics = true
    @AppStorage("lyrics.sources") private var lyricSourcesJSON = "{}"
    private var lyricSources: [String: String] {
        guard let data = lyricSourcesJSON.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
    private var lyricSource: String { lyricSources[viewModel.currentTrack?.videoId ?? ""] ?? "auto" }
    private func chooseLyricSource(_ source: String) {
        guard let id = viewModel.currentTrack?.videoId else { return }
        var sources = lyricSources; sources[id] = source
        if let data = try? JSONEncoder().encode(sources), let json = String(data: data, encoding: .utf8) { lyricSourcesJSON = json }
        isShowingExperimentalLyrics = true
    }
    @State private var experimentalLyrics = ExperimentalLyricsController()
    @State private var lyricsPresentation: LyricsPresentationSettings
    @State var sidebarPreviewPresentation: LyricsPresentationSettings = {
        let settings = LyricsPresentationSettings()
        settings.fontSize = PlaybackSidebarLayout.lyricsPreviewFontSize
        return settings
    }()
    /// Set by the lateral scene while the footer shows the lyrics sample.
    @State var sidebarLyricsPreviewVisible = false
    @AppStorage(SidebarBottomContentPreferences.preferenceKey, store: HomeAppearance.preferences)
    var sidebarBottomContentRaw = SidebarBottomContent.queue.rawValue
    @State private var queueViewport = PlaybackQueueViewport()
    @State var sidebarPalette = PlaybackSidebarPalette.neutral
    @State var sidebarArtworkScroll = SidebarArtworkScrollState()

    var animatableData: CGFloat {
        get { sidebarProgress }
        set { sidebarProgress = newValue }
    }

    @FocusState var sidebarCloseFocused: Bool

    var sidebarArtworkOccurrenceKey: SidebarArtworkOccurrenceKey {
        SidebarArtworkOccurrenceKey(
            sessionID: viewModel.mediaSessionIdentity,
            playbackID: viewModel.experimentalLyricsPlaybackIdentity,
            videoID: viewModel.currentTrack?.videoId,
            occurrenceID: viewModel.queueManager.currentOccurrenceID
        )
    }

    var sidebarPaletteTaskID: String {
        "\(viewModel.mediaSessionIdentity.uuidString)|\(viewModel.currentTrack?.videoId ?? "")|\(viewModel.currentTrack?.thumbnail ?? "")"
    }

    var sidebarTint: Color {
        sidebarPalette.surfaceColor(
            reduceTransparency: reduceTransparency,
            increasedContrast: contrast == .increased
        )
    }

    var sidebarBottomTint: Color {
        sidebarPalette.bottomSurfaceColor(
            reduceTransparency: reduceTransparency,
            increasedContrast: contrast == .increased
        )
    }

    private var isLyricsPanelVisible: Bool {
        viewModel.isPlaybackSidebarPresented
            ? viewModel.selectedSidebarPanel == .lyrics
            : viewModel.isFullscreenPresented && selectedPanel == .lyrics
    }

    var body: some View {
        ZStack {
            if isSidebarPresentation { sidebarScene }
            else { fullscreenScene }
        }
        .onExitCommand {
            if viewModel.isPlaybackSidebarPresented { viewModel.closePlaybackSidebar() }
            else { viewModel.dismissFullscreen() }
        }
        .onChange(of: isSidebarPresentation, initial: true) { _, isSidebar in
            lyricsPresentation.fontSize = isSidebar ? PlaybackSidebarLayout.lyricsFontSize : ExperimentalLyricsStyle.defaultFontSize
        }
        .onDisappear {
            viewModel.volumeScroll.cancel()
            experimentalLyrics.deactivate()
            lyricsPresentation.beginPanelVisit()
        }
        .onChange(of: isLyricsPanelVisible, initial: true) { _, visible in
            // Reset while leaving, before the next renderer mounts and schedules its initial scroll.
            if !visible { lyricsPresentation.beginPanelVisit() }
        }
        .onChange(of: experimentalLyricsRequest, initial: true) { _, request in
            experimentalLyrics.activate(request, fetch: fetchExperimentalLyrics)
        }
        .onChange(of: sidebarArtworkOccurrenceKey, initial: true) { _, key in
            _ = sidebarArtworkScroll.synchronizeOccurrence(key)
        }
        .onChange(of: viewModel.currentTrack?.videoId) { _, _ in
            failedOriginalURL = nil
            failedMaxQualityURL = nil
        }
        .task(id: sidebarPaletteTaskID) {
            if viewModel.currentTrack?.thumbnail == nil {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                    sidebarPalette = .neutral
                }
                return
            }
            let resolved = await PlaybackSidebarPalette.resolve(thumbnail: viewModel.currentTrack?.thumbnail)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                sidebarPalette = resolved
            }
        }
    }

    private var fullscreenScene: some View {
        let geometry = FullscreenSidebarGeometry(canvasSize: canvasSize, progress: sidebarProgress)
        let layout = geometry.metrics
        return VStack(spacing: 0) {
            Color.clear.frame(height: layout.topPadding)
            HStack(alignment: .top, spacing: layout.columnSpacing) {
                // One block and one interpolated coordinate system for
                // artwork, title, credits and actions throughout resize.
                VStack(alignment: .leading, spacing: layout.metadataSpacing) {
                    artworkView(size: layout.artworkSize)
                    trackInfoView(width: layout.artworkSize)
                        .frame(height: layout.metadataHeight, alignment: .top)
                        .windowGestureRegion(.excluded)
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
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        // Only the shared sidebar progress interpolates this scene's geometry.
        .transaction { if geometry.isTransitioning { $0.animation = nil } }
        .compositingGroup()
    }

    // MARK: - Módulo Artwork (1:1 Cuadrado en Fullscreen con Play/Pause en click y oscurecimiento en hover)
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
            .windowGestureRegion(.volumeFullscreen, active: !isArtworkFlipped &&
                viewModel.isFullscreenPresented && viewModel.currentTrack != nil)

            artworkInformationCard(size: size)
                .opacity(isArtworkFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(isArtworkFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .allowsHitTesting(isArtworkFlipped)
                .windowGestureRegion(.verticalContent, active: isArtworkFlipped)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.42), radius: 22, x: 0, y: 10)
        .overlay(alignment: .topTrailing) {
            FullscreenBackVolumeFeedback(player: viewModel, flipped: isArtworkFlipped)
                .offset(y: -38)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.48), value: isArtworkFlipped)
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

            AnimatedArtworkView(track: viewModel.currentTrack,
                                sessionID: viewModel.mediaSessionIdentity,
                                core: viewModel.rustCore,
                                isPlaying: viewModel.isPlaying,
                                isPresented: viewModel.isFullscreenPresented,
                                isFlipped: isArtworkFlipped,
                                audioDuration: viewModel.duration)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous))

            FullscreenArtworkVolumeFeedback(player: viewModel, size: size, hovered: isHoveringArtwork)

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
                Group {
                    if let track = viewModel.currentTrack {
                        FeaturedTrackTitle(track:track,font:.system(size:titleSize,weight:.bold),color:.white,pointSize:titleSize) { id,name in navigateToArtist(track:track,artistId:id,name:name) }
                    } else { Text(L10n.text("player.noPlayback")).font(.system(size:titleSize,weight:.bold)).foregroundStyle(.white).lineLimit(1) }
                }

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
        SideBSegmentedControl(
            segments: FullscreenPanel.allCases.map { SideBControlSegment(id: $0, title: $0.title, symbol: $0.icon) },
            selection: selectedPanel
        ) { panel in
            selectedPanel = panel
            if panel == .recommended, let track = viewModel.currentTrack {
                viewModel.fetchRecommendations(for: track)
            }
        }
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
    func queuePanel(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.queueManager.context?.iconName ?? "music.note.list")
                Text(localizedQueueContextTitle).lineLimit(1)
                Spacer(minLength: 4)
                if viewModel.isLoadingPlaylistContinuation { ProgressView().controlSize(.small) }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            NativeSeparatedQueueView(manager: viewModel.queueManager,
                revision: viewModel.queueManager.presentationRevision,
                player: viewModel, router: router, liked: viewModel.likedVideoIds,
                playing: viewModel.isPlaying,
                loading: viewModel.queueManager.isLoadingRadio || viewModel.queueManager.isLoadingAutoplay,
                error: viewModel.queueRecommendationError, viewport: queueViewport)
        }
        .frame(height: height)
    }

    // MARK: - Contenido: Letras Sincronizadas
    func lyricsPanel(height: CGFloat) -> some View {
        Group {
            if viewModel.isShowingGeniusLyrics {
                GeniusPanelView(model: viewModel.genius, artwork: viewModel.currentTrack?.thumbnail,
                                annotationColorMode: $geniusAnnotationColorMode)
                    .id(viewModel.currentTrack?.videoId)
            } else if !isDisplayingOriginalLyrics {
                experimentalLyricsPanel
            } else {
                nativeLyricsPanel(height: height)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay(alignment: .topTrailing) {
            // Loaded new lyrics supply their own menu with presentation settings.
            if !viewModel.isShowingGeniusLyrics && (!isShowingExperimentalLyrics || !hasExperimentalLyrics) {
                LyricsOptionsMenu(
                    isShowingNewLyrics: !isDisplayingOriginalLyrics,
                    onToggleLyrics: {
                        if isDisplayingOriginalLyrics {
                            if isShowingExperimentalLyrics { refreshExperimentalLyrics() }
                            else { isShowingExperimentalLyrics = true }
                        } else { isShowingExperimentalLyrics = false }
                    },
                    onRefresh: refreshExperimentalLyrics,
                    isRefreshing: experimentalLyrics.isLoading
                ) {
                    LyricsSourceOptions(source: lyricSource, onSelect: chooseLyricSource)
                    LyricsPresentationOptions(settings: lyricsPresentation)
                }
                .padding(.trailing, 8)
            }
        }
    }

    private var isDisplayingOriginalLyrics: Bool {
        if isShowingExperimentalLyrics && lyricSource != "auto" { return false }
        return LyricsPanelSelection.usesOriginal(prefersNew: isShowingExperimentalLyrics,
                                          hasNew: hasExperimentalLyrics,
                                          hasOriginal: viewModel.lyricsInfo?.lines.isEmpty == false)
    }

    private var currentExperimentalDocument: ExperimentalLyricsDocument? {
        guard let active = experimentalLyrics.activeRequest,
              active.playbackID == viewModel.experimentalLyricsPlaybackIdentity,
              active.sessionID == viewModel.mediaSessionIdentity,
              active.videoID == viewModel.currentTrack?.videoId, active.source == lyricSource else { return nil }
        return experimentalLyrics.document
    }

    private var hasExperimentalLyrics: Bool {
        guard let document = currentExperimentalDocument else { return false }
        return document.instrumental || !document.lines.isEmpty
    }

    private func refreshExperimentalLyrics() {
        experimentalLyrics.refresh(fetch: fetchExperimentalLyrics)
    }

    private var experimentalLyricsRequest: ExperimentalLyricsRequest? {
        let previewOnly = viewModel.isPlaybackSidebarPresented && sidebarLyricsPreviewVisible && viewModel.selectedSidebarPanel == .artwork
        guard isShowingExperimentalLyrics, previewOnly || !viewModel.isShowingGeniusLyrics, viewModel.isPlaybackSurfaceVisible,
              (viewModel.isPlaybackSidebarPresented ? (viewModel.selectedSidebarPanel == .lyrics || previewOnly) : selectedPanel == .lyrics), let track = viewModel.currentTrack,
              viewModel.rustCore != nil else { return nil }
        var request = ExperimentalLyricsRequest(track: track,
                                         playbackID: viewModel.experimentalLyricsPlaybackIdentity,
                                         sessionID: viewModel.mediaSessionIdentity,
                                         audioDuration: viewModel.duration)
        request.source = lyricSource
        return request
    }

    @MainActor
    private func fetchExperimentalLyrics(_ request: ExperimentalLyricsRequest,
                                         forceRefresh: Bool) async throws -> ExperimentalLyricsDocument? {
        guard let core = viewModel.rustCore else { throw CancellationError() }
        let document = try await ExperimentalLyricsController.fetch(request, forceRefresh: forceRefresh, core: core)
        guard !Task.isCancelled,
              request.playbackID == viewModel.experimentalLyricsPlaybackIdentity,
              request.sessionID == viewModel.mediaSessionIdentity,
              request.videoID == viewModel.currentTrack?.videoId else { throw CancellationError() }
        return document
    }

    @ViewBuilder
    private var experimentalLyricsPanel: some View {
        if let document = currentExperimentalDocument,
           document.instrumental || !document.lines.isEmpty {
            ExperimentalLyricsPanel(
                document: document,
                player: viewModel.audioService.avPlayer,
                playbackIdentity: viewModel.experimentalLyricsPlaybackIdentity,
                duration: viewModel.duration,
                seekSnapshot: viewModel.audioService.seekSnapshot,
                onSeek: { _ = viewModel.seekToLyric(seconds: $0) },
                onShowOriginalLyrics: { isShowingExperimentalLyrics = false },
                onRefresh: refreshExperimentalLyrics,
                isRefreshing: experimentalLyrics.isLoading,
                presentation: lyricsPresentation,
                source: lyricSource, onSelectSource: chooseLyricSource
            )
            .id(viewModel.experimentalLyricsPlaybackIdentity)
            .overlay(alignment: .bottom) {
                if let errorKey = experimentalLyrics.errorKey {
                    Text(L10n.text(errorKey))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(8)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel(L10n.text(errorKey))
                }
            }
        } else {
            VStack(spacing: 12) {
                if experimentalLyrics.isLoading {
                    ProgressView()
                    Text(L10n.text("lyrics.experimental.loading"))
                } else if experimentalLyricsRequest == nil {
                    Image(systemName: "music.note")
                    Text(L10n.text("lyrics.experimental.noTrack"))
                } else if experimentalLyrics.errorKey != nil {
                    Image(systemName: "exclamationmark.bubble")
                    Text(L10n.text("lyrics.experimental.error"))
                    Button(L10n.text("lyrics.experimental.retry")) {
                        experimentalLyrics.refresh(fetch: fetchExperimentalLyrics)
                    }
                    .buttonStyle(SideBControlStyle())
                } else {
                    Image(systemName: "quote.bubble")
                    Text(L10n.text(lyricSource == "auto" ? "lyrics.experimental.empty" : "lyrics.source.empty"))
                    Text(L10n.text("lyrics.experimental.emptyDetail"))
                        .font(.system(size: 11.5))
                }
            }
            .font(.system(size: 13.5))
            .foregroundStyle(.white.opacity(0.65))
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
            ClassicLyricsClockHost(
                viewModel: viewModel,
                lyrics: lyrics,
                duration: viewModel.duration,
                height: height,
                playbackIdentity: viewModel.experimentalLyricsPlaybackIdentity,
                presentation: lyricsPresentation
            )
            .id(viewModel.experimentalLyricsPlaybackIdentity)
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

    // MARK: - Muestra de letras del lateral

    /// The same renderers as the Lyrics tab at a smaller size, with their own scroll state,
    /// without controls and without hit testing; the card around it opens the full tab.
    @ViewBuilder
    func sidebarLyricsPreview(height: CGFloat) -> some View {
        SidebarLyricsPreviewCard(viewModel: viewModel, onOpen: openSidebarLyricsFromPreview) {
            Group {
                if !isDisplayingOriginalLyrics, let document = currentExperimentalDocument,
                   document.instrumental || !document.lines.isEmpty {
                    ExperimentalLyricsPanel(
                        document: document,
                        player: viewModel.audioService.avPlayer,
                        playbackIdentity: viewModel.experimentalLyricsPlaybackIdentity,
                        duration: viewModel.duration,
                        seekSnapshot: viewModel.audioService.seekSnapshot,
                        onSeek: { _ in },
                        presentation: sidebarPreviewPresentation,
                        source: lyricSource,
                        showsControls: false
                    )
                    .id(viewModel.experimentalLyricsPlaybackIdentity)
                } else if isDisplayingOriginalLyrics, !viewModel.isLoadingLyrics,
                          let lyrics = viewModel.lyricsInfo, !lyrics.lines.isEmpty {
                    ClassicLyricsClockHost(
                        viewModel: viewModel, lyrics: lyrics, duration: viewModel.duration, height: height,
                        playbackIdentity: viewModel.experimentalLyricsPlaybackIdentity,
                        presentation: sidebarPreviewPresentation
                    )
                    .id(viewModel.experimentalLyricsPlaybackIdentity)
                } else {
                    SidebarLyricsPreviewStatus(
                        loading: experimentalLyrics.isLoading || viewModel.isLoadingLyrics,
                        hasTrack: viewModel.currentTrack != nil)
                }
            }
            .frame(height: height)
        }
    }

    private func openSidebarLyricsFromPreview() {
        viewModel.selectedFullscreenPanel = .lyrics
        viewModel.selectedSidebarPanel = .lyrics
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

/// Keeps the frequently changing playback clock at the edge of the classic renderer.
private struct ClassicLyricsClockHost: View {
    @Bindable var viewModel: PlayerViewModel
    let lyrics: LyricsInfo
    let duration: Double
    let height: CGFloat
    let playbackIdentity: UUID
    let presentation: LyricsPresentationSettings

    var body: some View {
        let activeIndex = LyricTiming.activeIndex(in: lyrics, at: viewModel.currentTime)
        SyncedLyricsPanel(
            lyrics: lyrics,
            activeIndex: activeIndex,
            duration: duration,
            height: height,
            playbackIdentity: playbackIdentity,
            presentation: presentation,
            onSeek: { _ = viewModel.seekToLyric(seconds: $0) }
        )
        // The clock ticks at 10 Hz but the active line changes rarely; without this the
        // fresh `onSeek` closure forces the whole row list to re-evaluate on every tick.
        .equatable()
    }
}

struct SyncedLyricsPanel: View, Equatable {
    /// `onSeek` is intentionally ignored: it always forwards to the same player.
    /// Presentation state is observed by the panel itself, so identity is enough here.
    static func == (lhs: SyncedLyricsPanel, rhs: SyncedLyricsPanel) -> Bool {
        lhs.activeIndex == rhs.activeIndex && lhs.duration == rhs.duration && lhs.height == rhs.height
            && lhs.playbackIdentity == rhs.playbackIdentity && lhs.presentation === rhs.presentation
            && lhs.lyrics == rhs.lyrics
    }

    let lyrics: LyricsInfo
    let activeIndex: Int?
    let duration: Double
    let height: CGFloat
    let playbackIdentity: UUID
    let presentation: LyricsPresentationSettings
    let onSeek: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorSchemeContrast) var contrast
    @State private var visibleIndices: Set<Int> = []

    private var canFollow: Bool { activeIndex != nil && lyrics.isSynced }
    private var isFollowing: Bool { presentation.classicScroll.isFollowing }
    private var karaoke: Bool { presentation.mode == .karaoke }

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding = LyricsLayoutMetrics.horizontalMargin
            let textWidth = LyricsLayoutMetrics.textWidth(viewportWidth: geometry.size.width)
            let verticalPadding = LyricsLayoutMetrics.verticalCenteringPadding(
                viewportHeight: geometry.size.height,
                canCenterActiveLine: canFollow
            )
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                            lyricRow(index: index, line: line, proxy: proxy)
                                .frame(width: textWidth, alignment: .leading)
                                .padding(.vertical, karaoke ? 10 : 8)
                                .id(index)
                                .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                                    recordRowVisibility(index: index, isVisible: isVisible)
                                }
                        }
                    }
                    .frame(width: textWidth, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollIndicators(.hidden)
                .mask { LyricsViewportMask(height: geometry.size.height, increasedContrast: contrast == .increased) }
                .onScrollPhaseChange { _, phase in
                    if canFollow && (phase == .tracking || phase == .interacting) {
                        presentation.noteUserScrolled()
                        updateManualAnchor()
                    }
                }
                .overlay(alignment: .bottom) {
                    if canFollow && !isFollowing {
                        Button {
                            presentation.noteFollowResumed()
                            if let command = presentation.classicScroll.resumeFollowing(
                                activeTarget: activeIndex,
                                reduceMotion: reduceMotion
                            ) {
                                applyImmediately(command, using: proxy)
                            }
                        } label: {
                            SideBControlLabel(title: L10n.text("fullscreen.returnToCurrentLyric"), symbol: "location.fill")
                        }
                        .buttonStyle(SideBControlStyle())
                        .padding(.bottom, 12)
                        .help(L10n.text("fullscreen.resumeLyricsTracking"))
                        .accessibilityLabel(L10n.text("fullscreen.resumeLyricsTracking"))
                        .accessibilityHint(L10n.text("fullscreen.resumeLyricsTrackingHint"))
                    }
                }
                .onAppear {
                    presentation.activate(playbackIdentity)
                    if let command = presentation.classicScroll.restoreOnAppear(
                        activeTarget: activeIndex,
                        canFollow: canFollow
                    ) {
                        scheduleCommand(command, using: proxy)
                    }
                }
                .onDisappear {
                    presentation.classicScroll.invalidatePending()
                    presentation.followState.invalidateRequests()
                }
                .onChange(of: playbackIdentity) { _, next in
                    visibleIndices.removeAll()
                    presentation.activate(next)
                    if let command = presentation.classicScroll.restoreOnAppear(
                        activeTarget: activeIndex,
                        canFollow: canFollow
                    ) {
                        scheduleCommand(command, using: proxy)
                    }
                }
                .onChange(of: activeIndex) { _, next in
                    if let command = presentation.classicScroll.activeTargetChanged(
                        to: next,
                        canFollow: canFollow,
                        reduceMotion: reduceMotion
                    ) {
                        scheduleCommand(command, using: proxy)
                    }
                }
                .onChange(of: geometry.size) { _, _ in recenterForLayout(using: proxy) }
                .onChange(of: presentation.fontSize) { _, _ in recenterForLayout(using: proxy) }
                .onChange(of: karaoke) { _, _ in recenterForLayout(using: proxy) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    @ViewBuilder
    private func lyricRow(index: Int, line: LyricLineInfo, proxy: ScrollViewProxy) -> some View {
        let active = activeIndex == nil || index == activeIndex
        let distance = ExperimentalLyricsStyle.visualDistance(abs(index - (activeIndex ?? index)))
        let text = LyricsPhraseText(text: line.text, fontSize: presentation.fontSize, karaoke: karaoke)
            .modifier(LyricsContextPresentation(karaoke: karaoke, active: active, distance: distance,
                                               isFollowing: isFollowing && canFollow, reduceMotion: reduceMotion,
                                               increasedContrast: contrast == .increased))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

        if let milliseconds = line.timeMs {
            Button {
                presentation.noteFollowResumed()
                let command = presentation.classicScroll.seek(to: index, reduceMotion: reduceMotion)
                onSeek(Double(milliseconds) / 1_000)
                applyImmediately(command, using: proxy)
            } label: { text }
            .buttonStyle(.plain)
            .accessibilityAddTraits(index == activeIndex ? [.isSelected] : [])
            .accessibilityHint(L10n.text("fullscreen.goToLyricLine"))
        } else { text }
    }

    private func recenterForLayout(using proxy: ScrollViewProxy) {
        if let command = presentation.classicScroll.recenterForLayoutChange(
            activeTarget: activeIndex,
            canFollow: canFollow,
            reduceMotion: reduceMotion
        ) {
            scheduleCommand(command, using: proxy)
        }
    }

    private func scheduleCommand(_ command: LyricsScrollCoordinator<Int>.Command, using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            guard presentation.classicScroll.canApply(command) else { return }
            applyImmediately(command, using: proxy)
        }
    }

    private func applyImmediately(_ command: LyricsScrollCoordinator<Int>.Command, using proxy: ScrollViewProxy) {
        if command.animated && !reduceMotion {
            withAnimation(.spring(response: ExperimentalLyricsStyle.focusTransitionDuration, dampingFraction: 0.96)) {
                proxy.scrollTo(command.target, anchor: .center)
            }
        } else {
            proxy.scrollTo(command.target, anchor: .center)
        }
    }

    private func recordRowVisibility(index: Int, isVisible: Bool) {
        let changed = isVisible ? visibleIndices.insert(index).inserted : visibleIndices.remove(index) != nil
        if changed && !isFollowing {
            updateManualAnchor()
        }
    }

    private func updateManualAnchor() {
        guard !isFollowing, !visibleIndices.isEmpty else { return }
        let sorted = visibleIndices.sorted()
        presentation.classicScroll.recordVisibleManualAnchor(sorted[sorted.count / 2])
    }
}

/// Observes only the feedback and effective audio value; the image subtree is retained.
private struct FullscreenArtworkVolumeFeedback: View {
    let player: PlayerViewModel
    let size: CGFloat
    let hovered: Bool
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        let visible = player.volumeScroll.isVisible
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous)
                .fill(Color.black.opacity(hovered || visible ? 0.22 : 0))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hovered)
            if visible {
                Text(VolumeScrollFeedback.percentage(player.volume))
                    .font(.system(size: max(28, size * 0.14), weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background((reduceTransparency || contrast == .increased) ? Color.black.opacity(0.8) : .clear,
                                in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            } else {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: max(28, size * 0.14), weight: .bold))
                    .foregroundStyle(Color.white.opacity(hovered ? 0.92 : 0))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hovered)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FullscreenBackVolumeFeedback: View {
    let player: PlayerViewModel
    let flipped: Bool
    var body: some View {
        if flipped && player.volumeScroll.isVisible {
            Text(VolumeScrollFeedback.percentage(player.volume))
                .font(.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(.black.opacity(0.8), in: Capsule())
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
