import Foundation
import SwiftUI
import MediaPlayer
import SideBCore

// SAFETY: SideBCore está protegido internamente por Arc<Mutex<T>> en Rust.
// UniFFI garantiza que todas las funciones exportadas son Send + Sync sin mutabilidad no sincronizada.
extension SideBCore: @unchecked Sendable {}
extension SongItemRecord: @unchecked Sendable {}
extension BrowseCardRecord: @unchecked Sendable {}

extension Notification.Name {
    public static let sideBLikedTrackToggled = Notification.Name("sideBLikedTrackToggled")
    public static let sideBPlaybackRecorded = Notification.Name("sideBPlaybackRecorded")
    public static let sideBLibraryAlbumToggled = Notification.Name("sideBLibraryAlbumToggled")
    public static let sideBLibraryPlaylistToggled = Notification.Name("sideBLibraryPlaylistToggled")
    public static let sideBPlaylistTrackRemoved = Notification.Name("sideBPlaylistTrackRemoved")
    public static let sideBPlaylistsChanged = Notification.Name("sideBPlaylistsChanged")
    public static let sideBRequestCreatePlaylist = Notification.Name("sideBRequestCreatePlaylist")
    public static let sideBSongLibraryChanged = Notification.Name("sideBSongLibraryChanged")
    public static let sideBLibraryRefreshRequested = Notification.Name("sideBLibraryRefreshRequested")
}

// MARK: - Modelo de Recomendaciones
public struct RecommendedData: Sendable {
    public var artistName: String?
    public var artistBrowseId: String?
    public var artistSongs: [SongItemRecord] = []
    public var albumTitle: String?
    public var albumBrowseId: String?
    public var albumSongs: [SongItemRecord] = []
    public var similarSongs: [SongItemRecord] = []
    public var relatedArtists: [BrowseCardRecord] = []
    public var loadedVideoId: String? = nil
    
    public var isEmpty: Bool {
        artistSongs.isEmpty && albumSongs.isEmpty && similarSongs.isEmpty && relatedArtists.isEmpty
    }
}

/// ViewModel de reproducción reactivo a 120Hz para macOS.
/// Conecta la resolución de streams de SideBCore (Rust) con AudioPlayerService (AVPlayer)
/// y mantiene actualizados los metadatos y controles de MPRemoteCommandCenter.
@MainActor
@Observable
public final class PlayerViewModel {
    // MARK: - Estado de Pista y Stream
    public var currentTrack: SongItemRecord? {
        didSet {
            schedulePlaybackSave()
            if currentTrack == nil { genius.reset() }
        }
    }
    public var currentAlbumBrowseId: String?
    public var currentArtistBrowseId: String?
    public var currentPlaylistBrowseId: String?
    public var streamInfo: StreamPlaybackInfo?
    public var isLoadingStream: Bool = false
    private var errorDescriptor: AppMessage?
    public var errorMessage: String? {
        get { errorDescriptor?.text }
        set { errorDescriptor = newValue.map { AppMessage(verbatim: $0) } }
    }
    private var hasRecordedHistoryForCurrentTrack: Bool = false

    // MARK: - Modo Fullscreen y Cola
    public var isFullscreenPresented: Bool = false
    public var selectedFullscreenPanel: FullscreenPanel = .queue
    public var isShowingGeniusLyrics: Bool = false
    public var queueManager: QueueManager = QueueManager()
    public var recommendedTracks: [SongItemRecord] = []
    
    // MARK: - Recomendaciones (Relacionado)
    public var recommendedData: RecommendedData? = nil
    public var isLoadingRecommended: Bool = false
    private var recommendedReloadCount: Int = 0
    private var recommendedTask: Task<Void, Never>? = nil
    
    public func toggleFullscreenPanel(_ panel: FullscreenPanel) {
        if isFullscreenPresented && selectedFullscreenPanel == panel {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                isFullscreenPresented = false
            }
        } else {
            selectedFullscreenPanel = panel
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                isFullscreenPresented = true
            }
            if panel == .recommended, let track = currentTrack {
                fetchRecommendations(for: track)
            }
        }
    }

    public func toggleLyricsPanel(genius: Bool) {
        if isFullscreenPresented && selectedFullscreenPanel == .lyrics && isShowingGeniusLyrics == genius {
            dismissFullscreen()
            return
        }
        isShowingGeniusLyrics = genius
        selectedFullscreenPanel = .lyrics
        if genius { self.genius.ensureNow() }
        if !isFullscreenPresented {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                isFullscreenPresented = true
            }
        }
    }
    
    public func dismissFullscreen() {
        guard isFullscreenPresented else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isFullscreenPresented = false
        }
    }
    
    // MARK: - Letras Sincronizadas
    public var lyricsInfo: LyricsInfo?
    public var isLoadingLyrics: Bool = false
    let genius = GeniusViewModel()
    
    // MARK: - Estado de Me Gusta (Rating)
    public var isCurrentTrackLiked: Bool = false
    public var likedVideoIds: Set<String> = []

    // MARK: - Control de Concurrencia y Sincronización
    private var resolveStreamTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var radioTask: Task<Void, Never>?
    private var automixTask: Task<Void, Never>?
    private var collectionRadioTask: Task<Void, Never>?
    private var playlistPlaybackTask: Task<Void, Never>?
    private var isCompletingActivePlaylistSource = false
    private var recommendedCollectionPlaybackTask: Task<Void, Never>?
    private var recommendedCollectionRequest = UUID()
    public private(set) var loadingRecommendedAlbumID: String?
    public private(set) var loadingRecommendedPlaylistID: String?
    private var likedHydrationTask: Task<Void, Never>?
    private var accountGeneration = UUID()
    var mediaSessionIdentity: UUID { accountGeneration }
    private var playlistRequest = UUID()
    private var playlistContinuationTask: Task<Void, Never>?
    public private(set) var isLoadingPlaylistContinuation: Bool = false
    private var currentPlaybackToken: UUID = UUID()
    private var pendingTailSkipToken: UUID?
    private var currentRadioToken: UUID = UUID()
    private var currentAutomixToken: UUID = UUID()

    // MARK: - Dependencias
    public var rustCore: SideBCore? {
        didSet {
            if rustCore != nil {
                hydrateLikedSongs()
            }
        }
    }
    public let audioService: AudioPlayerService
    private let playbackStore: PlaybackStateStore
    private let playlistCatalog: PlaylistCatalog
    private var currentPlaybackIdentity: String?
    private var isSwitchingPlaybackSession = false

    public convenience init(rustCore: SideBCore? = nil, audioService: AudioPlayerService = .shared) {
        self.init(rustCore: rustCore, audioService: audioService, playbackStore: PlaybackStateStore())
    }

    init(rustCore: SideBCore?, audioService: AudioPlayerService, playbackStore: PlaybackStateStore,
         playlistCatalog: PlaylistCatalog? = nil) {
        self.rustCore = rustCore
        self.audioService = audioService
        self.playbackStore = playbackStore
        self.playlistCatalog = playlistCatalog ?? .shared
        setupRemoteCommands()
        setupTrackEndListener()
        setupPlaybackProgressListener()
        queueManager.onStateChange = { [weak self] in self?.schedulePlaybackSave() }
        if rustCore != nil {
            hydrateLikedSongs()
        }
    }

    private func playbackSnapshot() -> SavedPlaybackState {
        SavedPlaybackState(
            version: SavedPlaybackState.currentVersion,
            tracks: queueManager.queue.map(SavedPlaybackState.Track.init),
            currentIndex: queueManager.currentIndex,
            currentTrack: currentTrack.map(SavedPlaybackState.Track.init),
            context: SavedPlaybackState.Context(queueManager.context, localizationKey: queueManager.contextLocalizationKey,
                localizationArguments: queueManager.contextLocalizationArguments),
            contextTitle: queueManager.contextTitle,
            radioSeed: queueManager.radioSeed,
            isShuffle: queueManager.isShuffle,
            isRepeat: queueManager.isRepeat,
            order: queueManager.orderSnapshot
        )
    }

    private func schedulePlaybackSave() {
        guard !isSwitchingPlaybackSession else { return }
        playbackStore.scheduleSave(playbackSnapshot())
    }

    public func flushPlaybackState() {
        guard currentPlaybackIdentity != nil else { return }
        playbackStore.saveNow(playbackSnapshot())
    }

    public func switchPlaybackSession(to identity: String) {
        guard currentPlaybackIdentity != identity else { return }
        if currentPlaybackIdentity != nil { flushPlaybackState() }
        isSwitchingPlaybackSession = true
        defer {
            isSwitchingPlaybackSession = false
            hydrateLikedSongs()
        }
        accountGeneration = UUID()
        likedHydrationTask?.cancel()
        playlistCatalog.invalidateAll()
        likedVideoIds.removeAll()
        PlaylistDetailViewModel.recentlyLikedTracks.removeAll()
        resolveStreamTask?.cancel()
        lyricsTask?.cancel()
        recommendedTask?.cancel()
        genius.reset()
        cancelInFlightRadioTasks()
        currentPlaybackToken = UUID()
        pendingTailSkipToken = nil
        audioService.stop()
        streamInfo = nil
        currentTrack = nil
        queueManager.clearQueue()
        queueManager.setShuffle(false)
        queueManager.isRepeat = false
        queueManager.isLoadingRadio = false
        queueManager.isLoadingAutoplay = false
        currentAlbumBrowseId = nil
        currentArtistBrowseId = nil
        currentPlaylistBrowseId = nil
        recommendedData = nil
        lyricsInfo = nil
        errorMessage = nil
        isLoadingStream = false
        isLoadingLyrics = false
        isLoadingRecommended = false
        playbackStore.activate(identity)
        currentPlaybackIdentity = identity
        guard let saved = playbackStore.load() else {
            updateNowPlayingInfo()
            isSwitchingPlaybackSession = false
            return
        }
        let tracks = saved.tracks.map(\.song)
        queueManager.replaceQueue(with: tracks, startingAt: saved.currentIndex,
                                  context: saved.context?.queueContext,
                                  contextTitle: saved.contextTitle,
                                  radioSeed: saved.radioSeed)
        queueManager.setContextLocalizationKey(saved.context?.localizationKey, args: saved.context?.localizationArguments ?? [])
        guard queueManager.restoreOrder(saved.order, isShuffle: saved.isShuffle) else {
            queueManager.clearQueue()
            isSwitchingPlaybackSession = false
            updateNowPlayingInfo()
            return
        }
        queueManager.isRepeat = saved.isRepeat
        currentTrack = queueManager.currentTrack ?? saved.currentTrack?.song
        currentPlaylistBrowseId = {
            if case .playlist(let id, _) = queueManager.context { return id }
            return nil
        }()
        isCurrentTrackLiked = currentTrack.map { likedVideoIds.contains($0.videoId) } ?? false
        updateNowPlayingInfo()
        isSwitchingPlaybackSession = false
    }

    private func setupTrackEndListener() {
        self.audioService.onTrackDidEnd = { [weak self] in
            self?.playNext(isManualSkip: false)
        }
    }

    private func setupPlaybackProgressListener() {
        self.audioService.onPlaybackProgress = { [weak self] current, duration in
            self?.checkAndRecordPlaybackHistory(current: current, duration: duration)
        }
    }

    private func checkAndRecordPlaybackHistory(current: Double, duration: Double) {
        guard !hasRecordedHistoryForCurrentTrack, let track = currentTrack, let core = rustCore else { return }
        // Umbral de reproducción: a la mitad del tema o a los 30 segundos (lo menor)
        let threshold = min(30.0, max(1.0, duration > 1.0 ? duration / 2.0 : 30.0))
        if current >= threshold {
            hasRecordedHistoryForCurrentTrack = true
            let videoId = track.videoId
            let playlistId = currentPlaylistBrowseId
            Task {
                let trackDict: [String: Any] = [
                    "video_id": track.videoId,
                    "title": track.title,
                    "artists": track.artists,
                    "duration": track.duration ?? "",
                    "thumbnail": track.thumbnail ?? "",
                    "album": track.album ?? "",
                    "album_id": track.albumId ?? "",
                    "artist_id": track.artistId ?? "",
                    "artist_runs": track.artistRuns.map { ["text": $0.text, "id": $0.id as Any? ?? NSNull()] }
                ]
                let trackJson = try? JSONSerialization.data(withJSONObject: trackDict)
                let jsonString = trackJson.flatMap { String(data: $0, encoding: .utf8) }
                do {
                    try await core.recordPlayback(videoId: videoId, songJson: jsonString, playlistId: playlistId)
                    print("[PlayerViewModel] 📻 Historial registrado con éxito en Rust y YouTube Music para \(videoId)")
                    NotificationCenter.default.post(
                        name: .sideBPlaybackRecorded,
                        object: nil,
                        userInfo: ["track": track]
                    )
                } catch {
                    print("[PlayerViewModel] ⚠️ Error registrando historial para \(videoId): \(error)")
                }
            }
        }
    }

    // MARK: - Propiedades de Progreso
    public var isPlaying: Bool {
        audioService.isPlaying
    }

    public var isBuffering: Bool {
        audioService.isBuffering || isLoadingStream
    }

    public var currentTime: Double {
        audioService.currentTime
    }

    public var duration: Double {
        audioService.duration
    }

    public var progressFraction: Double {
        guard duration > 0 else { return 0.0 }
        return min(max(0.0, currentTime / duration), 1.0)
    }

    public var formattedElapsed: String {
        formatTime(currentTime)
    }

    public var formattedDuration: String {
        duration.isFinite && duration > 0 ? formatTime(duration) : "—:—"
    }

    public func formattedTime(at seconds: Double) -> String {
        formatTime(seconds)
    }

    public var formattedRemaining: String {
        let remaining = max(0.0, duration - currentTime)
        return "-\(formatTime(remaining))"
    }

    public var volume: Float {
        get { audioService.volume }
        set { audioService.volume = newValue }
    }

    public func toggleMute() {
        audioService.toggleMute()
    }

    // MARK: - Acciones de Reproducción de Alto Nivel

    private func cancelInFlightRadioTasks() {
        recommendedCollectionRequest = UUID()
        recommendedCollectionPlaybackTask?.cancel()
        recommendedCollectionPlaybackTask = nil
        loadingRecommendedAlbumID = nil
        loadingRecommendedPlaylistID = nil
        playlistRequest = UUID()
        playlistPlaybackTask?.cancel()
        playlistPlaybackTask = nil
        isCompletingActivePlaylistSource = false
        collectionRadioTask?.cancel()
        collectionRadioTask = nil
        radioTask?.cancel()
        radioTask = nil
        automixTask?.cancel()
        automixTask = nil
        playlistContinuationTask?.cancel()
        playlistContinuationTask = nil
        isLoadingPlaylistContinuation = false
        currentRadioToken = UUID()
        currentAutomixToken = UUID()
    }
    
    /// Reproduce una canción e inicia una radio dinámica de YouTube Music (reemplazo limpio de cola).
    public func playWithRadio(_ song: SongItemRecord, albumBrowseId: String? = nil, artistBrowseId: String? = nil) {
        cancelInFlightRadioTasks()
        self.currentPlaylistBrowseId = nil
        let radioTitle = L10n.text("player.radioFor", args: [song.title])
        queueManager.replaceQueue(
            with: [song],
            startingAt: 0,
            context: .radio(seedVideoId: song.videoId, title: radioTitle, seedName: song.title),
            contextTitle: radioTitle,
            radioSeed: "RDAMVM\(song.videoId)"
        )
        
        // Arrancar reproducción de inmediato (cero latencia de UI)
        playSongNow(song, overrideAlbumBrowseId: albumBrowseId, overrideArtistBrowseId: artistBrowseId)
        
        // Cargar recomendaciones de radio en segundo plano
        fetchRadio(for: song)
    }
    
    /// A radio's originating card controls that radio, even after it advances to another track.
    func activateMediaRadio(_ song: SongItemRecord) {
        if MediaPlaybackIdentity.isRadioOrigin(videoID: song.videoId, context: queueManager.context), currentTrack != nil {
            cancelPendingMediaCollectionLoad()
            togglePlayPause()
        } else {
            playWithRadio(song)
        }
    }

    /// All cards use the same collection identity and guarded catalog loading path.
    func activateMediaCollection(id: String, kind: String) {
        guard !id.isEmpty else { return }
        if MediaPlaybackIdentity.isCollectionActive(kind: kind, id: id, context: queueManager.context), currentTrack != nil {
            cancelPendingMediaCollectionLoad()
            togglePlayPause()
            return
        }
        let canonicalID = MenuIDNormalizer.normalize(id)
        let loading = kind.lowercased() == "album" ? loadingRecommendedAlbumID : loadingRecommendedPlaylistID
        guard loading.map(MenuIDNormalizer.normalize) != canonicalID else { return }
        switch kind.lowercased() {
        case "album": playRecommendedAlbum(browseId: id)
        case "playlist", "mix": playRecommendedPlaylist(browseId: MenuIDNormalizer.canonicalPlaylistId(id))
        default: break
        }
    }

    private func cancelPendingMediaCollectionLoad() {
        recommendedCollectionRequest = UUID()
        recommendedCollectionPlaybackTask?.cancel()
        recommendedCollectionPlaybackTask = nil
        loadingRecommendedAlbumID = nil
        loadingRecommendedPlaylistID = nil
        // Pausing the current collection must not cancel completion of its own source.
        if !isCompletingActivePlaylistSource {
            playlistRequest = UUID()
            playlistPlaybackTask?.cancel()
            playlistPlaybackTask = nil
            isLoadingPlaylistContinuation = false
        }
    }

    /// Loads a Home recommendation without letting an older request replace a newer session/queue.
    public func playRecommendedAlbum(browseId: String, shuffle: Bool = false) {
        playRecommendedCollection(browseId: browseId, kind: .albums, shuffle: shuffle)
    }

    public func playRecommendedPlaylist(browseId: String, shuffle: Bool = false) {
        playRecommendedCollection(browseId: browseId, kind: .playlists, shuffle: shuffle)
    }

    private func playRecommendedCollection(browseId: String, kind: HomeFeaturedCollectionKind, shuffle: Bool) {
        guard !browseId.isEmpty, let core = rustCore else { return }
        cancelInFlightRadioTasks()
        let request = recommendedCollectionRequest
        let generation = accountGeneration
        let queueToken = queueManager.queueToken
        let playbackToken = currentPlaybackToken
        loadingRecommendedAlbumID = kind == .albums ? browseId : nil
        loadingRecommendedPlaylistID = kind == .playlists ? browseId : nil
        errorMessage = nil
        recommendedCollectionPlaybackTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.recommendedCollectionRequest == request {
                    self.loadingRecommendedAlbumID = nil
                    self.loadingRecommendedPlaylistID = nil
                    self.recommendedCollectionPlaybackTask = nil
                }
            }
            do {
                let collection = try await self.fetchRecommendedCollection(core: core, browseId: browseId, kind: kind)
                guard !Task.isCancelled, self.recommendedCollectionRequest == request,
                      self.accountGeneration == generation, self.queueManager.queueToken == queueToken,
                      self.currentPlaybackToken == playbackToken else { return }
                guard !collection.tracks.isEmpty else {
                    self.errorDescriptor = AppMessage(key: kind == .albums ? "player.error.noAlbumTracks" : "player.error.noPlaylistTracks")
                    return
                }
                if kind == .albums {
                    self.playAlbum(browseId: collection.id, title: collection.title, tracks: collection.tracks,
                                   artistBrowseId: collection.artistID, shuffle: shuffle)
                } else {
                    self.playPlaylist(browseId: browseId, title: collection.title, tracks: collection.tracks, shuffle: shuffle)
                }
            } catch {
                guard !Task.isCancelled, self.recommendedCollectionRequest == request,
                      self.accountGeneration == generation, self.queueManager.queueToken == queueToken,
                      self.currentPlaybackToken == playbackToken else { return }
                let key = kind == .albums ? "player.error.loadAlbum" : "player.error.loadPlaylist"
                self.errorDescriptor = (error as? PlaylistCatalogError)?.appMessage
                    ?? AppMessage(key: key, args: [error.localizedDescription])
            }
        }
    }

    private func fetchRecommendedCollection(core: SideBCore, browseId: String, kind: HomeFeaturedCollectionKind) async throws
        -> (id: String, title: String, tracks: [SongItemRecord], artistID: String?) {
        if kind == .albums {
            let album = try await core.getAlbum(browseId: browseId)
            return (album.browseId, album.title, album.items, album.artistId)
        }
        let playlist = try await playlistCatalog.load(id: browseId, core: core)
        return (playlist.id, playlist.title, playlist.items, nil)
    }

    /// Reproduce un álbum completo reemplazando la cola activa.
    public func playAlbum(browseId: String, title: String, tracks: [SongItemRecord], startingAt: Int = 0, artistBrowseId: String? = nil, shuffle: Bool = false) {
        guard !tracks.isEmpty else { return }
        cancelInFlightRadioTasks()
        self.currentAlbumBrowseId = browseId
        self.currentArtistBrowseId = artistBrowseId
        self.currentPlaylistBrowseId = nil
        
        queueManager.replaceQueue(
            with: tracks,
            startingAt: startingAt,
            context: .album(browseId: browseId, title: title),
            contextTitle: L10n.text("queue.albumContext", args: [title]),
            shuffle: shuffle
        )
        
        if let selected = queueManager.currentTrack {
            playSongNow(selected, overrideAlbumBrowseId: browseId, overrideArtistBrowseId: artistBrowseId)
        }
    }
    
    /// Normal playback starts from the loaded occurrence; the remaining catalog fills in without resetting audio.
    /// Initial shuffle still waits for the whole catalog so every source occurrence can be selected.
    public func playPlaylist(browseId: String, title: String, tracks: [SongItemRecord], startingAt: Int = 0, continuation: String? = nil, shuffle: Bool = false) {
        guard !tracks.isEmpty else { return }
        cancelInFlightRadioTasks()
        guard let continuation, !continuation.isEmpty else {
            beginPlaylist(browseId: browseId, title: title, tracks: tracks, startingAt: startingAt, shuffle: shuffle)
            return
        }
        if let cached = playlistCatalog.cached(id: browseId),
           tracks == Array(cached.items.prefix(tracks.count)) {
            beginPlaylist(browseId: browseId, title: title, tracks: cached.items, startingAt: startingAt, shuffle: shuffle)
            return
        }
        guard let core = rustCore else {
            errorDescriptor = AppMessage(key: "player.error.completePlaylistCoreUnavailable")
            return
        }
        let initial = PlaylistDetailRecord(id: browseId, title: title, subtitle: nil, thumbnail: nil,
            description: nil, items: tracks, continuation: continuation, owned: false, inLibrary: false,
            privacy: nil, collaborative: false, sort: nil, sortEditable: false)
        let request = playlistRequest
        let generation = accountGeneration
        if !shuffle {
            beginPlaylist(browseId: browseId, title: title, tracks: tracks, startingAt: startingAt,
                          shuffle: false, continuation: continuation)
        }
        let queueToken = queueManager.queueToken
        let playbackToken = currentPlaybackToken
        isLoadingPlaylistContinuation = true
        isCompletingActivePlaylistSource = !shuffle
        if shuffle { errorMessage = nil }
        playlistPlaybackTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.playlistRequest == request {
                    self.isLoadingPlaylistContinuation = false
                    self.isCompletingActivePlaylistSource = false
                    self.playlistPlaybackTask = nil
                }
            }
            do {
                let complete = try await playlistCatalog.load(id: browseId, core: core, initial: initial)
                guard !Task.isCancelled, self.playlistRequest == request,
                      self.accountGeneration == generation, self.queueManager.queueToken == queueToken else { return }
                if shuffle {
                    guard self.currentPlaybackToken == playbackToken else { return }
                    self.beginPlaylist(browseId: browseId, title: title, tracks: complete.items,
                                       startingAt: startingAt, shuffle: true)
                } else {
                    guard case .playlist(let activeID, _) = self.queueManager.context,
                          MenuIDNormalizer.canonicalPlaylistId(activeID) == MenuIDNormalizer.canonicalPlaylistId(browseId),
                          tracks == Array(complete.items.prefix(tracks.count)) else { return }
                    // Only append unseen source positions: moves/removals/manual insertions in the loaded prefix remain intact.
                    self.queueManager.completePlaylistSource(Array(complete.items.dropFirst(tracks.count)))
                    self.resumeAfterQueueExtension()
                }
            } catch {
                guard !Task.isCancelled, self.playlistRequest == request,
                      self.accountGeneration == generation, self.queueManager.queueToken == queueToken else { return }
                self.errorDescriptor = (error as? PlaylistCatalogError)?.appMessage
                    ?? AppMessage(key: "player.error.completePlaylist", args: [error.localizedDescription])
            }
        }
    }

    private func beginPlaylist(browseId: String, title: String, tracks: [SongItemRecord], startingAt: Int, shuffle: Bool,
                               continuation: String? = nil) {
        currentAlbumBrowseId = nil
        currentArtistBrowseId = nil
        currentPlaylistBrowseId = browseId
        queueManager.replaceQueue(with: tracks, startingAt: startingAt,
            context: .playlist(browseId: browseId, title: title), contextTitle: L10n.text("queue.playlistContext", args: [title]),
            continuation: continuation, shuffle: shuffle)
        if let selected = queueManager.currentTrack { playSongNow(selected) }
    }

    public func playCollection(tracks: [SongItemRecord], title: String, artistBrowseId: String? = nil, shuffle: Bool = false, startingAt: Int = 0) {
        guard !tracks.isEmpty else { return }
        cancelInFlightRadioTasks()
        currentAlbumBrowseId = nil
        currentPlaylistBrowseId = nil
        currentArtistBrowseId = artistBrowseId
        queueManager.replaceQueue(with: tracks, startingAt: startingAt, context: .custom(title: title), shuffle: shuffle)
        if let selected = queueManager.currentTrack {
            playSongNow(selected, overrideArtistBrowseId: artistBrowseId)
        }
    }

    /// Inicia una sesión de radio continua o mix a partir de una colección (artista, playlist o álbum).
    public func startRadioForCollection(
        id: String,
        title: String,
        prefix: String = "RDAMPL",
        directRadioId: String? = nil,
        fallbackTracks: [SongItemRecord] = []
    ) {
        guard let core = rustCore else { return }
        let radioPid: String
        if let direct = directRadioId, !direct.isEmpty {
            radioPid = direct
        } else if id.hasPrefix("RD") {
            radioPid = id
        } else {
            radioPid = "\(prefix)\(id)"
        }
        let radioTitle = L10n.text("player.radioFor", args: [title])

        cancelInFlightRadioTasks()

        let token = UUID()
        self.currentRadioToken = token

        collectionRadioTask = Task {
            do {
                let next = try await core.getNext(videoId: nil, playlistId: radioPid)
                guard !Task.isCancelled, self.currentRadioToken == token else { return }
                if !next.items.isEmpty {
                    self.queueManager.replaceQueue(
                        with: next.items,
                        startingAt: 0,
                        context: .radio(seedVideoId: "", title: radioTitle, seedName: title),
                        contextTitle: radioTitle,
                        radioSeed: radioPid,
                        continuation: next.continuation
                    )
                    self.playQueueIndex(0)
                    return
                }
            } catch {
                guard !Task.isCancelled, self.currentRadioToken == token else { return }
                print("[PlayerViewModel] Error al iniciar radio para \(title): \(error)")
            }

            guard !Task.isCancelled, self.currentRadioToken == token else { return }
            if !fallbackTracks.isEmpty {
                self.queueManager.replaceQueue(
                    with: fallbackTracks,
                    startingAt: 0,
                    context: .radio(seedVideoId: "", title: radioTitle, seedName: title),
                    contextTitle: radioTitle,
                    radioSeed: radioPid
                )
                self.playQueueIndex(0)
            }
        }
    }
    
    /// Inserta una canción justo a continuación del tema en reproducción.
    public func playNext(song: SongItemRecord) {
        if currentTrack == nil {
            playWithRadio(song)
        } else {
            queueManager.playNext(song)
        }
    }

    /// Inserta un lote de canciones justo a continuación del tema en reproducción.
    public func playNext(tracks: [SongItemRecord]) {
        guard !tracks.isEmpty else { return }
        if currentTrack == nil {
            cancelInFlightRadioTasks()
            if let first = tracks.first {
                queueManager.clearQueue()
                queueManager.playNext(tracks)
                playSongNow(first)
            }
        } else {
            queueManager.playNext(tracks)
        }
    }
    
    /// Añade una canción al final de la cola activa.
    public func addToQueue(song: SongItemRecord) {
        if currentTrack == nil {
            playWithRadio(song)
        } else {
            queueManager.addTrackToQueue(song)
        }
    }

    /// Añade un lote de canciones al final de la cola activa.
    public func addToQueue(tracks: [SongItemRecord]) {
        guard !tracks.isEmpty else { return }
        if currentTrack == nil {
            cancelInFlightRadioTasks()
            if let first = tracks.first {
                queueManager.clearQueue()
                queueManager.addTracksToQueue(tracks)
                playSongNow(first)
            }
        } else {
            queueManager.addTracksToQueue(tracks)
        }
    }

    /// Resuelve el stream de audio vía Rust y arranca la reproducción con AVPlayer.
    public func playSongNow(
        _ song: SongItemRecord,
        overrideAlbumBrowseId: String? = nil,
        overrideArtistBrowseId: String? = nil,
        deferStreamResolution: Bool = false
    ) {
        // 1. Cancelar tareas en vuelo previas para evitar carreras al skipear
        resolveStreamTask?.cancel()
        lyricsTask?.cancel()
        recommendedTask?.cancel()

        // 2. Generar token de correlación exclusivo
        let token = UUID()
        self.currentPlaybackToken = token
        self.pendingTailSkipToken = nil

        // 3. Soltar el item anterior: si falla la resolución, Play no debe reanudar otra canción.
        self.audioService.stop()
        self.streamInfo = nil

        // 4. Sincronizar estado visual de inmediato
        self.currentTrack = song
        self.genius.prepare(for: song, core: self.rustCore, identity: token)
        self.queueManager.syncCurrentIndex(for: song.videoId)

        // Limpiar o asignar IDs de procedencia de artista y álbum de la nueva pista
        self.currentArtistBrowseId = overrideArtistBrowseId ?? ((song.artistId?.isEmpty == false) ? song.artistId : nil)
        self.currentAlbumBrowseId = overrideAlbumBrowseId ?? ((song.albumId?.isEmpty == false) ? song.albumId : nil)
        self.isCurrentTrackLiked = likedVideoIds.contains(song.videoId)
        self.hasRecordedHistoryForCurrentTrack = false
        self.isLoadingStream = true
        self.errorMessage = nil
        
        // Lazy Load de Recomendaciones: si el usuario ya está viendo la pestaña Relacionado, cargar de inmediato
        if isFullscreenPresented && selectedFullscreenPanel == .recommended {
            fetchRecommendations(for: song)
        } else {
            // Se invalida para cargar bajo demanda cuando el usuario entre
            self.recommendedData = nil
        }

        self.lyricsInfo = nil
        self.isLoadingLyrics = false

        guard let core = rustCore else {
            self.errorDescriptor = AppMessage(key: "player.error.coreUnavailable")
            self.isLoadingStream = false
            return
        }

        // 5. Iniciar resolución de stream con token de correlación
        resolveStreamTask = Task {
            do {
                // Agrupar saltos manuales rápidos antes de cruzar a UniFFI/InnerTube.
                // Cancelar una llamada Rust ya iniciada no garantiza detener su trabajo de red.
                if deferStreamResolution {
                    try await Task.sleep(for: .milliseconds(180))
                }
                try Task.checkCancellation()
                // Las letras también cruzan UniFFI; no solicitarlas por pistas saltadas durante la espera.
                self.loadLyrics(for: song, token: token)
                print("[PlayerViewModel] Resolviendo stream para videoId: \(song.videoId)")
                let playbackInfo = try await core.resolveStream(videoId: song.videoId, isUpload: song.isUpload)

                // Verificación de consistencia: si el usuario skipeó mientras se resolvía, descartar
                guard !Task.isCancelled,
                      self.currentPlaybackToken == token,
                      self.currentTrack?.videoId == song.videoId else {
                    print("[PlayerViewModel] Descartando stream obsoleto para: \(song.title)")
                    return
                }

                self.streamInfo = playbackInfo
                self.isLoadingStream = false

                // Extraer duración esperada en segundos (desde metadata oficial de YouTube Music)
                var expectedSecs: Double? = nil
                if let durStr = playbackInfo.duration, let s = Double(durStr), s > 0 {
                    expectedSecs = s
                } else if let durStr = song.duration {
                    let parts = durStr.split(separator: ":").compactMap { Double($0) }
                    if parts.count == 2 {
                        expectedSecs = parts[0] * 60 + parts[1]
                    } else if parts.count == 3 {
                        expectedSecs = parts[0] * 3600 + parts[1] * 60 + parts[2]
                    }
                }

                print("[PlayerViewModel] Stream resuelto. itag: \(playbackInfo.itag), client: \(playbackInfo.streamClient), dur: \(expectedSecs ?? 0)s")
                self.audioService.play(
                    urlString: playbackInfo.streamUrl,
                    headers: playbackInfo.headers,
                    expectedDuration: expectedSecs
                )
                self.genius.playbackStarted(identity: token)
                self.updateNowPlayingInfo()
            } catch {
                guard !Task.isCancelled, self.currentPlaybackToken == token else { return }
                self.isLoadingStream = false
                self.errorDescriptor = AppMessage(key: "player.error.resolveStream", args: [error.localizedDescription])
                print("[PlayerViewModel] ❌ Error: \(error)")
            }
        }
    }

    /// Reintenta la resolución y reproducción de la pista actual tras un fallo de red o stream.
    public func retryPlayback() {
        guard let track = currentTrack else { return }
        self.errorMessage = nil
        playSongNow(track)
    }
    
    /// Compatibilidad hacia atrás: si `addToQueue` es true, inicia una radio limpia; si no, reproduce de inmediato.
    public func playSong(_ song: SongItemRecord, addToQueue: Bool = true, albumBrowseId: String? = nil, artistBrowseId: String? = nil) {
        if addToQueue {
            playWithRadio(song, albumBrowseId: albumBrowseId, artistBrowseId: artistBrowseId)
        } else {
            playSongNow(song, overrideAlbumBrowseId: albumBrowseId, overrideArtistBrowseId: artistBrowseId)
        }
    }

    public func playNext(isManualSkip: Bool = true) {
        if let next = queueManager.nextTrack(isManualSkip: isManualSkip) {
            playSongNow(next, deferStreamResolution: isManualSkip)
            checkAutomixTrigger()
        } else if queueManager.isNearTail {
            if isManualSkip {
                // El usuario pidió avanzar aunque la página siguiente aún no llegó.
                resolveStreamTask?.cancel()
                lyricsTask?.cancel()
                currentPlaybackToken = UUID()
                pendingTailSkipToken = currentPlaybackToken
                audioService.stop()
                streamInfo = nil
                isLoadingStream = false
            }
            if case .playlist = queueManager.context,
               let continuation = queueManager.continuationToken,
               !continuation.isEmpty {
                extendPlaylistIfNeeded()
            } else {
                extendRadioIfNeeded()
            }
        }
    }

    public func playPrevious() {
        if let prev = queueManager.previousTrack() {
            playSongNow(prev, deferStreamResolution: true)
        }
    }

    func resumeAfterQueueExtension() {
        let manualSkipIsPending = pendingTailSkipToken == currentPlaybackToken
        guard manualSkipIsPending || audioService.hasReachedEnd else { return }
        pendingTailSkipToken = nil
        guard let next = queueManager.nextTrack(isManualSkip: manualSkipIsPending) else { return }
        playSongNow(next)
        checkAutomixTrigger()
    }

    public func playQueueIndex(_ index: Int) {
        if let track = queueManager.selectTrack(at: index) {
            playSongNow(track, deferStreamResolution: true)
            checkAutomixTrigger()
        }
    }

    public func toggleCurrentTrackLike() {
        guard let track = currentTrack else { return }
        toggleTrackLike(track)
    }

    public func toggleTrackLike(_ track: SongItemRecord) {
        playlistCatalog.invalidate("LM")
        let generation = accountGeneration
        let wasLiked = likedVideoIds.contains(track.videoId)
        let newStatus = !wasLiked
        if newStatus {
            likedVideoIds.insert(track.videoId)
        } else {
            likedVideoIds.remove(track.videoId)
        }
        if currentTrack?.videoId == track.videoId {
            self.isCurrentTrackLiked = newStatus
        }

        // Notificación de UI optimista inmediata (para que las vistas de 'LM' se actualicen de inmediato)
        NotificationCenter.default.post(
            name: .sideBLikedTrackToggled,
            object: nil,
            userInfo: ["track": track, "isLiked": newStatus]
        )

        guard let core = rustCore else { return }
        Task {
            do {
                try await core.rateSong(videoId: track.videoId, rating: newStatus ? "LIKE" : "INDIFFERENT")
                guard self.accountGeneration == generation else { return }
                playlistCatalog.invalidate("LM")
                NotificationCenter.default.post(name: .sideBSongLibraryChanged, object: nil)
                print("[PlayerViewModel] Calificación enviada para \(track.videoId): \(newStatus ? "LIKE" : "INDIFFERENT")")
            } catch {
                guard self.accountGeneration == generation else { return }
                playlistCatalog.invalidate("LM")
                // Reversión optimista si la llamada remota falla
                if wasLiked {
                    self.likedVideoIds.insert(track.videoId)
                } else {
                    self.likedVideoIds.remove(track.videoId)
                }
                if self.currentTrack?.videoId == track.videoId {
                    self.isCurrentTrackLiked = wasLiked
                }
                NotificationCenter.default.post(
                    name: .sideBLikedTrackToggled,
                    object: nil,
                    userInfo: ["track": track, "isLiked": wasLiked]
                )
                self.errorDescriptor = AppMessage(key: "player.error.updateRating", args: [error.localizedDescription])
                print("[PlayerViewModel] Error al calificar \(track.videoId): \(error)")
            }
        }
    }

    public func dislikeTrack(_ track: SongItemRecord) {
        playlistCatalog.invalidate("LM")
        let generation = accountGeneration
        let wasLiked = likedVideoIds.contains(track.videoId)
        likedVideoIds.remove(track.videoId)
        if currentTrack?.videoId == track.videoId {
            self.isCurrentTrackLiked = false
        }

        NotificationCenter.default.post(
            name: .sideBLikedTrackToggled,
            object: nil,
            userInfo: ["track": track, "isLiked": false]
        )

        // 1. Enviar calificación remota con reversión si falla
        if let core = rustCore {
            Task {
                do {
                    try await core.rateSong(videoId: track.videoId, rating: "DISLIKE")
                    guard self.accountGeneration == generation else { return }
                    playlistCatalog.invalidate("LM")
                    NotificationCenter.default.post(name: .sideBSongLibraryChanged, object: nil)
                    print("[PlayerViewModel] Calificación DISLIKE enviada para \(track.videoId)")
                } catch {
                    guard self.accountGeneration == generation else { return }
                    playlistCatalog.invalidate("LM")
                    if wasLiked {
                        self.likedVideoIds.insert(track.videoId)
                    }
                    if self.currentTrack?.videoId == track.videoId {
                        self.isCurrentTrackLiked = wasLiked
                    }
                    NotificationCenter.default.post(
                        name: .sideBLikedTrackToggled,
                        object: nil,
                        userInfo: ["track": track, "isLiked": wasLiked]
                    )
                    self.errorDescriptor = AppMessage(key: "player.error.dislike", args: [error.localizedDescription])
                    print("[PlayerViewModel] Error al calificar DISLIKE \(track.videoId): \(error)")
                }
            }
        }

        // Eliminar la ocurrencia activa, no la primera canción que comparte videoId.
        if currentTrack?.videoId == track.videoId {
            removeQueueTrack(at: queueManager.currentIndex)
        } else {
            queueManager.removeTrack(videoId: track.videoId)
        }

        // 3. Remover también de recomendaciones si estaba presente
        recommendedTracks.removeAll(where: { $0.videoId == track.videoId })
        if var data = recommendedData {
            data.artistSongs.removeAll(where: { $0.videoId == track.videoId })
            data.albumSongs.removeAll(where: { $0.videoId == track.videoId })
            data.similarSongs.removeAll(where: { $0.videoId == track.videoId })
            recommendedData = data
        }
    }

    public func moveQueueTrack(from source: Int, to destination: Int) {
        queueManager.moveTrack(from: source, to: destination)
    }

    public func removeQueueTrack(at index: Int) {
        guard index >= 0, index < queueManager.queue.count else { return }
        if index == queueManager.currentIndex {
            let nextAvailable = queueManager.upNextTracks.first
            _ = queueManager.removeTrack(at: index)
            if let next = nextAvailable {
                playSongNow(next)
                checkAutomixTrigger()
            } else if let first = queueManager.selectTrack(at: 0) {
                playSongNow(first)
            } else {
                audioService.stop()
                currentTrack = nil
                updateNowPlayingInfo()
            }
        } else {
            _ = queueManager.removeTrack(at: index)
        }
    }

    public func rateSong(videoId: String, rating: String) {
        guard let core = rustCore else { return }
        let generation = accountGeneration
        playlistCatalog.invalidate("LM")
        Task {
            do {
                try await core.rateSong(videoId: videoId, rating: rating)
                guard self.accountGeneration == generation else { return }
                playlistCatalog.invalidate("LM")
                NotificationCenter.default.post(name: .sideBSongLibraryChanged, object: nil)
                print("[PlayerViewModel] Calificación enviada para \(videoId): \(rating)")
            } catch {
                guard self.accountGeneration == generation else { return }
                playlistCatalog.invalidate("LM")
                self.errorDescriptor = AppMessage(key: "player.error.rateSong", args: [error.localizedDescription])
                print("[PlayerViewModel] Error al calificar \(videoId): \(error)")
            }
        }
    }

    /// Reutiliza el mismo catálogo completo que las acciones de reproducción de Tus Me Gusta.
    public func hydrateLikedSongs() {
        guard let core = rustCore, core.isLoggedIn() else { return }
        likedHydrationTask?.cancel()
        let generation = accountGeneration
        let catalog = playlistCatalog
        likedHydrationTask = Task { [weak self] in
            do {
                let lm = try await catalog.load(id: "LM", core: core)
                guard let self, !Task.isCancelled, self.accountGeneration == generation else { return }
                self.likedVideoIds.formUnion(lm.items.map(\.videoId))
                if let current = self.currentTrack {
                    self.isCurrentTrackLiked = self.likedVideoIds.contains(current.videoId)
                }
            } catch {
                guard !Task.isCancelled else { return }
                print("[PlayerViewModel] No se pudo hidratar Tus Me Gusta: \(error)")
            }
        }
    }

    /// Limpia datos privados y rechaza respuestas de la sesión anterior.
    public func clearAccountState() {
        accountGeneration = UUID()
        likedHydrationTask?.cancel()
        playlistCatalog.invalidateAll()
        PlaylistDetailViewModel.recentlyLikedTracks.removeAll()
        likedVideoIds.removeAll()
        isCurrentTrackLiked = false
    }

    public func rateSong(rating: String) {
        guard let track = currentTrack else { return }
        rateSong(videoId: track.videoId, rating: rating)
    }

    // MARK: - Carga de Letras y Pistas de Radio
    public func loadLyrics(for track: SongItemRecord, token: UUID? = nil) {
        guard let core = rustCore else { return }
        self.isLoadingLyrics = true
        self.lyricsInfo = nil
        let targetToken = token ?? currentPlaybackToken

        let durSecs: UInt64? = {
            guard let dur = track.duration else { return nil }
            let parts = dur.split(separator: ":").compactMap { UInt64($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
            if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
            return nil
        }()

        lyricsTask = Task {
            do {
                let info = try await core.getLyrics(
                    videoId: track.videoId,
                    title: track.title,
                    artist: track.artists,
                    album: track.album,
                    durationSecs: durSecs
                )
                guard !Task.isCancelled,
                      self.currentPlaybackToken == targetToken,
                      self.currentTrack?.videoId == track.videoId else {
                    return
                }
                self.lyricsInfo = info
                self.isLoadingLyrics = false
            } catch {
                guard !Task.isCancelled, self.currentPlaybackToken == targetToken else { return }
                self.isLoadingLyrics = false
                print("[PlayerViewModel] No se pudieron obtener letras: \(error)")
            }
        }
    }

    /// Consulta la radio de YouTube Music y puebla la cola Up Next de forma dinámica.
    public func fetchRadio(for track: SongItemRecord) {
        guard let core = rustCore else { return }

        radioTask?.cancel()
        let token = UUID()
        self.currentRadioToken = token
        let targetQueueToken = queueManager.queueToken
        let targetVideoId = track.videoId

        queueManager.isLoadingRadio = true

        radioTask = Task {
            defer {
                if !Task.isCancelled && self.currentRadioToken == token {
                    self.queueManager.isLoadingRadio = false
                }
            }
            do {
                let radioResult = try await core.getRadio(videoId: targetVideoId)
                guard !Task.isCancelled,
                      self.currentRadioToken == token,
                      self.queueManager.queueToken == targetQueueToken,
                      self.currentTrack?.videoId == targetVideoId else {
                    return
                }
                if !radioResult.items.isEmpty {
                    self.recommendedTracks = radioResult.items
                    self.queueManager.appendRadioTracks(radioResult.items, continuation: radioResult.continuation)
                    if let seed = radioResult.automixPlaylistId {
                        self.queueManager.radioSeed = seed
                    }
                    
                    // Si el audio finalizó mientras se cargaba la radio y la cola quedó a la espera, reanudar de inmediato
                    self.resumeAfterQueueExtension()

                    // Completar álbum y enlaces ausentes con los metadatos de la misma pista en la radio.
                    if let cur = self.currentTrack, cur.videoId == targetVideoId,
                       cur.album == nil || cur.artistRuns.isEmpty {
                        if let match = radioResult.items.first(where: { $0.videoId == targetVideoId }) {
                            self.currentTrack = SongItemRecord(
                                videoId: cur.videoId,
                                title: cur.title,
                                artists: cur.artists,
                                album: cur.album ?? match.album,
                                duration: cur.duration,
                                thumbnail: cur.thumbnail,
                                artistId: cur.artistId ?? match.artistId,
                                albumId: cur.albumId ?? match.albumId,
                                setVideoId: cur.setVideoId,
                                isVideo: cur.isVideo,
                                isUpload: cur.isUpload,
                                library: cur.library,
                                artistRuns: cur.artistRuns.isEmpty ? match.artistRuns : cur.artistRuns
                            )
                            if let albId = self.currentTrack?.albumId {
                                self.currentAlbumBrowseId = albId
                            }
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled, self.currentRadioToken == token else { return }
                print("[PlayerViewModel] Error al cargar radio para \(track.title): \(error)")
            }
        }
    }

    // MARK: - Recomendaciones Completas (Estilo Liquid Glass & sideb OLD)
    public func fetchRecommendations(for track: SongItemRecord, forceRefresh: Bool = false) {
        guard let core = rustCore else { return }
        
        // Si no es refresco forzado y ya tenemos cargadas las recomendaciones para esta canción, reutilizar (Lazy Cache)
        if !forceRefresh, let data = recommendedData, data.loadedVideoId == track.videoId {
            return
        }
        
        recommendedTask?.cancel()
        isLoadingRecommended = true
        
        if forceRefresh {
            recommendedReloadCount += 1
        } else {
            recommendedReloadCount = 0
        }
        let currentReload = recommendedReloadCount
        let targetVideoId = track.videoId
        let targetArtistId = track.artistId ?? currentArtistBrowseId
        let targetAlbumId = track.albumId ?? currentAlbumBrowseId
        let artistName = track.displayArtist
        let albumTitle = track.displayAlbum
        
        recommendedTask = Task {
            // 1. Canciones parecidas a la actual (Endpoint Related MPTR... de YouTube Music)
            async let similarFetch: [SongItemRecord] = {
                do {
                    let items = try await core.getRelatedTracks(videoId: targetVideoId)
                    let filtered = items.filter { $0.videoId != targetVideoId }
                    if currentReload > 0 && filtered.count > 4 {
                        let offset = (currentReload * 4) % filtered.count
                        return Array(filtered.dropFirst(offset) + filtered.prefix(offset))
                    }
                    return filtered
                } catch {
                    print("[PlayerViewModel] Error obteniendo canciones parecidas (related): \(error)")
                    return []
                }
            }()
            
            // 2. Artista: Pistas populares y Artistas similares (priorizando los devueltos por el endpoint Related de la canción)
            async let artistFetch: (songs: [SongItemRecord], relatedArtists: [BrowseCardRecord]) = {
                var songRelatedArtists: [BrowseCardRecord] = []
                do {
                    songRelatedArtists = try await core.getRelatedArtists(videoId: targetVideoId)
                } catch {
                    print("[PlayerViewModel] Error obteniendo artistas similares de la canción: \(error)")
                }

                guard let aId = targetArtistId, !aId.isEmpty else {
                    return ([], songRelatedArtists)
                }
                do {
                    let detail = try await core.getArtist(browseId: aId)
                    let songs = detail.topSongs.filter { $0.videoId != targetVideoId }
                    
                    var related = songRelatedArtists
                    if related.isEmpty {
                        for section in detail.sections {
                            let titleLower = section.title.lowercased()
                            if titleLower.contains("fans") || titleLower.contains("similares") || titleLower.contains("similar") || titleLower.contains("like") {
                                related.append(contentsOf: section.items)
                            } else if related.isEmpty && section.items.contains(where: { $0.kind.lowercased() == "artist" }) {
                                related.append(contentsOf: section.items.filter { $0.kind.lowercased() == "artist" })
                            }
                        }
                    }
                    return (songs, related)
                } catch {
                    print("[PlayerViewModel] Error obteniendo artista para recomendaciones: \(error)")
                    return ([], songRelatedArtists)
                }
            }()
            
            // 3. Álbum: Pistas del mismo disco
            async let albumFetch: [SongItemRecord] = {
                guard let alId = targetAlbumId, !alId.isEmpty else { return [] }
                do {
                    let detail = try await core.getAlbum(browseId: alId)
                    return detail.items.filter { $0.videoId != targetVideoId }
                } catch {
                    print("[PlayerViewModel] Error obteniendo álbum para recomendaciones: \(error)")
                    return []
                }
            }()
            
            let (simSongs, artData, albSongs) = await (similarFetch, artistFetch, albumFetch)
            
            guard !Task.isCancelled, self.currentTrack?.videoId == targetVideoId else { return }
            
            self.recommendedData = RecommendedData(
                artistName: artistName,
                artistBrowseId: targetArtistId,
                artistSongs: artData.songs,
                albumTitle: albumTitle,
                albumBrowseId: targetAlbumId,
                albumSongs: albSongs,
                similarSongs: simSongs,
                relatedArtists: artData.relatedArtists,
                loadedVideoId: targetVideoId
            )
            self.recommendedTracks = simSongs
            self.isLoadingRecommended = false
        }
    }
    
    public func refreshRecommendations() {
        guard let track = currentTrack else { return }
        fetchRecommendations(for: track, forceRefresh: true)
    }

    /// Disparo transparente de Automix o Continuación de Playlist:
    /// Si la cola activa es una playlist con continuación disponible, carga la siguiente página de la misma playlist.
    /// Si no, o si es radio, extiende vía Automix.
    public func checkAutomixTrigger() {
        guard queueManager.isNearTail else { return }

        // 1. Si es playlist con continuación pendiente, paginar la playlist
        if case .playlist = queueManager.context,
           let continuation = queueManager.continuationToken,
           !continuation.isEmpty {
            extendPlaylistIfNeeded()
            return
        }

        // 2. Extender vía Automix
        guard !queueManager.isLoadingAutoplay, !queueManager.isLoadingRadio else { return }
        extendRadioIfNeeded()
    }

    /// Extiende la cola activa solicitando la siguiente página de la playlist actual.
    public func extendPlaylistIfNeeded() {
        guard let core = rustCore, !isLoadingPlaylistContinuation else { return }
        guard case .playlist = queueManager.context,
              let continuation = queueManager.continuationToken,
              !continuation.isEmpty else { return }

        let targetQueueToken = queueManager.queueToken
        isLoadingPlaylistContinuation = true

        playlistContinuationTask?.cancel()
        playlistContinuationTask = Task {
            defer {
                if !Task.isCancelled {
                    self.isLoadingPlaylistContinuation = false
                }
            }
            do {
                print("[PlayerViewModel] Cargando continuación de playlist con token: \(continuation)")
                let res = try await core.getPlaylistContinuation(token: continuation)
                guard !Task.isCancelled,
                      self.queueManager.queueToken == targetQueueToken,
                      case .playlist = self.queueManager.context else {
                    return
                }
                guard res.continuation != continuation else {
                    self.errorDescriptor = AppMessage(key: "queue.error.repeatedContinuation")
                    return
                }
                if !res.items.isEmpty {
                    self.queueManager.appendPlaylistTracks(res.items, nextContinuation: res.continuation)
                    print("[PlayerViewModel] Playlist extendida con \(res.items.count) temas adicionales.")

                    // Si el audio finalizó esperando la siguiente página, reanudar de inmediato
                    self.resumeAfterQueueExtension()
                } else {
                    self.queueManager.continuationToken = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard self.queueManager.queueToken == targetQueueToken else { return }
                self.errorDescriptor = AppMessage(key: "player.error.completePlaylist", args: [error.localizedDescription])
            }
        }
    }

    public func extendRadioIfNeeded() {
        guard let core = rustCore, !queueManager.isLoadingAutoplay else { return }
        guard let lastVideo = queueManager.queue.last?.videoId else { return }

        automixTask?.cancel()
        let token = UUID()
        self.currentAutomixToken = token
        let targetQueueToken = queueManager.queueToken
        let targetSeed = queueManager.radioSeed

        queueManager.isLoadingAutoplay = true
        automixTask = Task {
            defer {
                if !Task.isCancelled && self.currentAutomixToken == token {
                    self.queueManager.isLoadingAutoplay = false
                }
            }
            do {
                print("[PlayerViewModel] Disparando Automix continuo desde semilla: \(targetSeed ?? "auto")")
                let nextResult = try await core.getRadioContinuation(lastVideoId: lastVideo, radioSeed: targetSeed)
                guard !Task.isCancelled,
                      self.currentAutomixToken == token,
                      self.queueManager.queueToken == targetQueueToken,
                      self.queueManager.radioSeed == targetSeed else {
                    return
                }
                if !nextResult.items.isEmpty {
                    self.queueManager.appendRadioTracks(nextResult.items, continuation: nextResult.continuation)
                    print("[PlayerViewModel] Automix extendió la cola con \(nextResult.items.count) temas.")

                    // Si el audio finalizó mientras se extendía el automix, continuar de inmediato
                    self.resumeAfterQueueExtension()
                }
            } catch {
                guard !Task.isCancelled, self.currentAutomixToken == token else { return }
                print("[PlayerViewModel] Error al extender Automix: \(error)")
            }
        }
    }


    public func togglePlayPause() {
        if audioService.isPlaying {
            audioService.pause()
        } else {
            playCurrentTrack()
        }
        updateNowPlayingPlaybackRate()
    }

    private func playCurrentTrack() {
        guard let track = currentTrack else { return }
        if audioService.avPlayer.currentItem == nil {
            guard !isLoadingStream else { return }
            playSongNow(track)
        } else {
            audioService.resume()
        }
    }

    public func seek(toFraction fraction: Double) {
        audioService.seek(toFraction: fraction)
    }

    // MARK: - Formateo de Tiempo

    private func formatTime(_ totalSeconds: Double) -> String {
        guard !totalSeconds.isNaN && !totalSeconds.isInfinite && totalSeconds >= 0 else {
            return "0:00"
        }
        let total = Int(totalSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Integración con macOS Now Playing y Teclas Multimedia

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playCurrentTrack()
                self?.updateNowPlayingPlaybackRate()
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.audioService.pause()
                self?.updateNowPlayingPlaybackRate()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playNext()
            }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playPrevious()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self?.audioService.seek(toSeconds: posEvent.positionTime)
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artists,
            MPNowPlayingInfoPropertyPlaybackRate: audioService.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audioService.currentTime,
        ]

        if audioService.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = audioService.duration
        }

        if let album = track.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }

        // Integrar carátula en Now Playing de macOS
        if let thumbStr = track.thumbnail,
           let thumbUrl = ImageURLHelper.optimizedThumbnailURL(from: thumbStr, targetPixelSize: 300) {
            if let cached = ImageCache.shared.imageFromMemoryCache(for: thumbUrl, targetSize: CGSize(width: 300, height: 300)) {
                info[MPMediaItemPropertyArtwork] = Self.makeNowPlayingArtwork(from: cached)
            } else {
                let videoId = track.videoId
                Task {
                    if let loaded = await ImageCache.shared.image(for: thumbUrl, targetSize: CGSize(width: 300, height: 300)) {
                        guard self.currentTrack?.videoId == videoId else { return }
                        var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        updated[MPMediaItemPropertyArtwork] = Self.makeNowPlayingArtwork(from: loaded)
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                    }
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private nonisolated static func makeNowPlayingArtwork(from image: NSImage) -> MPMediaItemArtwork {
        let size = image.size
        return MPMediaItemArtwork(boundsSize: size) { _ in
            image
        }
    }

    private func updateNowPlayingPlaybackRate() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = audioService.isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioService.currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// MARK: - Normalización de Metadatos Artista / Álbum
extension SongItemRecord {
    public init(
        videoId: String, title: String, artists: String, album: String?, duration: String?,
        thumbnail: String?, artistId: String?, albumId: String?, setVideoId: String?
    ) {
        self.init(
            videoId: videoId, title: title, artists: artists, album: album, duration: duration,
            thumbnail: thumbnail, artistId: artistId, albumId: albumId, setVideoId: setVideoId,
            isVideo: false, isUpload: false, library: nil
        )
    }
    public init(
        videoId: String, title: String, artists: String, album: String?, duration: String?,
        thumbnail: String?, artistId: String?, albumId: String?, setVideoId: String?,
        isVideo: Bool, isUpload: Bool, library: LibraryToggleRecord?
    ) {
        self.init(
            videoId: videoId, title: title, artists: artists, album: album, duration: duration,
            thumbnail: thumbnail, artistId: artistId, albumId: albumId, setVideoId: setVideoId,
            isVideo: isVideo, isUpload: isUpload, library: library, artistRuns: []
        )
    }

    /// Devuelve el nombre limpio del artista desprendiendo el álbum si venía compuesto en la cadena ("Artista • Álbum")
    public var displayArtist: String {
        if artists.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.text("detail.track.variousArtists")
        }
        if let alb = album, !alb.isEmpty, artists.contains(" • ") {
            return artists.components(separatedBy: " • ").first?.trimmingCharacters(in: .whitespaces) ?? artists
        }
        if (album == nil || album?.isEmpty == true) && artists.contains(" • ") {
            let parts = artists.components(separatedBy: " • ")
            return parts.first?.trimmingCharacters(in: .whitespaces) ?? artists
        }
        return artists
    }

    /// Devuelve el álbum explícito si existe, o el extraído de la cadena compuesta de artistas si venía allí
    public var displayAlbum: String? {
        if let alb = album, !alb.isEmpty {
            return alb
        }
        if artists.contains(" • ") {
            let parts = artists.components(separatedBy: " • ")
            if parts.count >= 2 {
                let candidate = parts[1].trimmingCharacters(in: .whitespaces)
                return candidate.isEmpty ? nil : candidate
            }
        }
        return nil
    }

    /// Construye un SongItemRecord a partir de un HomeItemRecord desglosando artista y álbum si vienen concatenados
    public init(fromHomeItem item: HomeItemRecord) {
        var artistName = item.artists ?? item.subtitle ?? ""
        var albumName: String? = item.album
        if albumName == nil, let sub = item.subtitle, sub.contains(" • ") {
            let parts = sub.components(separatedBy: " • ")
            if parts.count >= 2 {
                artistName = parts[0].trimmingCharacters(in: .whitespaces)
                let candidate = parts[1].trimmingCharacters(in: .whitespaces)
                albumName = candidate.isEmpty ? nil : candidate
            }
        }
        self.init(
            videoId: item.id,
            title: item.title,
            artists: artistName,
            album: albumName,
            duration: item.duration,
            thumbnail: item.thumbnail,
            artistId: item.artistId,
            albumId: item.albumId,
            setVideoId: nil,
            isVideo: false, isUpload: false, library: nil,
            artistRuns: item.artistRuns
        )
    }

    /// Construye un SongItemRecord a partir de un BrowseCardRecord desglosando artista y álbum si vienen concatenados
    public init(fromCard card: BrowseCardRecord, fallbackArtist: String? = nil, knownArtistId: String? = nil) {
        var artistName = card.subtitle ?? fallbackArtist ?? ""
        var albumName: String? = nil
        if let sub = card.subtitle, sub.contains(" • ") {
            let parts = sub.components(separatedBy: " • ")
            if parts.count >= 2 {
                artistName = parts[0].trimmingCharacters(in: .whitespaces)
                let candidate = parts[1].trimmingCharacters(in: .whitespaces)
                albumName = candidate.isEmpty ? nil : candidate
            }
        }
        self.init(
            videoId: card.id,
            title: card.title,
            artists: artistName,
            album: albumName,
            duration: card.duration,
            thumbnail: card.thumbnail,
            artistId: knownArtistId,
            albumId: nil,
            setVideoId: nil
        )
    }
}
