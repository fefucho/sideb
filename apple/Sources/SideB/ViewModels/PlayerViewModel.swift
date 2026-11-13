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
public struct RecommendedData: Sendable, Equatable {
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
            if currentTrack?.videoId != oldValue?.videoId { volumeScroll.cancel() }
            if currentTrack?.videoId != oldValue?.videoId {
                pendingLyricSeek = nil
                cancelRecommendationLoading()
                recommendedData = nil
                recommendedLoadedKey = nil
                recommendedTracks = []
            }
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
    let volumeScroll = VolumeScrollFeedback()
    public var playbackPresentation = PlaybackPresentationState() {
        didSet { if oldValue.mode != playbackPresentation.mode { volumeScroll.cancel() } }
    }
    public var isFullscreenPresented: Bool {
        get { playbackPresentation.mode == .fullscreen }
        set {
            let returningToSidebar = isFullscreenPresented && !newValue
            playbackPresentation.setFullscreen(newValue)
            if returningToSidebar && isPlaybackSidebarPresented {
                switch selectedFullscreenPanel {
                case .lyrics: selectedSidebarPanel = .lyrics
                case .queue: selectedSidebarPanel = .queue
                case .recommended, .jam: selectedSidebarPanel = .artwork
                }
            }
        }
    }
    public var isPlaybackSidebarPresented: Bool { playbackPresentation.mode == .sidebar }
    public var isPlaybackSurfaceVisible: Bool { playbackPresentation.mode != .bar }
    public var selectedSidebarPanel: PlaybackSidebarPanel = .artwork

    public func togglePlaybackSidebar(_ panel: PlaybackSidebarPanel? = nil) {
        if isPlaybackSidebarPresented && (panel == nil || panel == selectedSidebarPanel) {
            playbackPresentation.closeSidebar()
        } else {
            if let panel { selectedSidebarPanel = panel }
            if selectedSidebarPanel == .lyrics { selectedFullscreenPanel = .lyrics }
            if selectedSidebarPanel == .queue { selectedFullscreenPanel = .queue }
            playbackPresentation.presentSidebar()
        }
    }

    public func closePlaybackSidebar() { playbackPresentation.closeSidebar() }

    public var selectedFullscreenPanel: FullscreenPanel = .queue
    public var isShowingGeniusLyrics: Bool = false
    public var queueManager: QueueManager = QueueManager()

    // MARK: - Modo sesión (Spotify Jam)
    enum JamControl { case togglePlayPause, next, previous, seek(fraction: Double) }
    /// Presente mientras se refleja un Jam: los controles de transporte se envían al Jam en lugar de
    /// mover el audio local, y la cola deja de extenderse con radio/recomendaciones propias.
    var jamControl: ((JamControl) -> Void)?
    var isJamSessionActive: Bool { jamControl != nil }

    /// What happens to the user's own playback when a session ends.
    enum JamExitRestore {
        /// Rebuild the saved queue and load the saved track paused at the saved position.
        case loadPaused
        /// Rebuild the saved queue and current track without loading audio.
        case stateOnly
        /// Leave nothing behind (the account is being switched).
        case discard
    }

    /// A playback request that was held back because a Jam is active. The UI asks the user and
    /// answers with `confirmJamExit()` or `cancelJamExit()`.
    struct PendingJamExit: Identifiable {
        let id = UUID()
        /// Title of what the user asked to play, for the confirmation text.
        let subject: String?
        fileprivate let action: @MainActor () -> Void
    }
    private(set) var pendingJamExit: PendingJamExit?
    /// The user's own queue, current track and position, taken when the Jam started. While a Jam
    /// is active this, not the mirrored Jam queue, is what gets persisted.
    private var jamSnapshot: SavedPlaybackState?
    private struct PendingResume { let videoID: String; let seconds: Double }
    private var pendingResume: PendingResume?

    /// Runs `action` now, or holds it as `pendingJamExit` when a Jam is active. Returns true when held.
    private func deferForJamExit(subject: String?, _ action: @escaping @MainActor () -> Void) -> Bool {
        guard isJamSessionActive else { return false }
        pendingJamExit = PendingJamExit(subject: subject, action: action)
        return true
    }

    /// Leaves the Jam (restoring the user's queue without loading audio), then runs the held request.
    func confirmJamExit() {
        guard let pending = pendingJamExit else { return }
        pendingJamExit = nil
        JamSessionController.shared.leave(restore: .stateOnly)
        if isJamSessionActive { endJamSession(restore: .stateOnly) } // Never run the request inside a Jam.
        pending.action()
    }

    func cancelJamExit() { pendingJamExit = nil }

    /// Called by the Jam controller once it is live: snapshots the user's session, silences local
    /// playback and hands queue control to the Jam.
    func beginJamSession(editor: any QueueSessionEditing, control: @escaping (JamControl) -> Void) {
        if jamSnapshot == nil {
            var snapshot = playbackSnapshot()
            snapshot.positionSeconds = currentTrack == nil ? nil : audioService.currentTime
            jamSnapshot = snapshot
        }
        pendingJamExit = nil
        pendingResume = nil
        cancelInFlightRadioTasks()
        resolveStreamTask?.cancel()
        lyricsTask?.cancel()
        currentPlaybackToken = UUID()
        pendingTailSkipToken = nil
        audioService.stop()
        streamInfo = nil
        isLoadingStream = false
        queueManager.isLoadingRadio = false
        queueManager.isLoadingAutoplay = false
        queueManager.isRepeat = false
        queueManager.clearQueue()
        currentTrack = nil
        queueManager.sessionEditor = editor
        jamControl = control
    }

    /// Called by the Jam controller when the session is over, whatever the reason.
    func endJamSession(restore: JamExitRestore) {
        let snapshot = jamSnapshot
        let wasSwitching = isSwitchingPlaybackSession
        isSwitchingPlaybackSession = true // The cleared Jam queue must never be written as the session.
        defer { isSwitchingPlaybackSession = wasSwitching }
        jamSnapshot = nil
        jamControl = nil
        pendingJamExit = nil
        queueManager.sessionEditor = nil
        cancelInFlightRadioTasks()
        resolveStreamTask?.cancel()
        lyricsTask?.cancel()
        currentPlaybackToken = UUID()
        audioService.stop()
        streamInfo = nil
        isLoadingStream = false
        queueManager.clearQueue()
        currentTrack = nil
        guard restore != .discard, let snapshot else { updateNowPlayingInfo(); return }
        _ = restoreQueue(from: snapshot)
        updateNowPlayingInfo()
        if restore == .loadPaused, let track = currentTrack {
            pendingResume = PendingResume(videoID: track.videoId, seconds: snapshot.positionSeconds ?? 0)
            playSongNow(track)
        }
    }
    public var recommendedTracks: [SongItemRecord] = []
    
    // MARK: - Recomendaciones (Relacionado)
    public private(set) var recommendedRevision: UInt64 = 0
    public var recommendedData: RecommendedData? = nil {
        didSet { recommendedRevision &+= 1; if recommendedData == nil { recommendedError = nil } }
    }
    public var recommendedError: String? = nil
    public var isLoadingRecommended: Bool = false
    private var recommendedReloadCount: Int = 0
    private var recommendedTask: Task<Void, Never>? = nil
    private var recommendedRequest = RecommendedRequestState()
    private var recommendedLoadedKey: RecommendedRequestState.Key?
    var recommendationContextKey: RecommendedRequestState.Key? {
        guard let track = currentTrack else { return nil }
        return RecommendedRequestState.Key(videoID: track.videoId,
            artistID: track.artistId ?? currentArtistBrowseId,
            albumID: track.albumId ?? currentAlbumBrowseId, account: accountGeneration)
    }
    
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
        if isFullscreenPresented {
            if selectedFullscreenPanel == .lyrics && isShowingGeniusLyrics == genius {
                dismissFullscreen()
                return
            }
        } else if isPlaybackSidebarPresented && selectedSidebarPanel == .lyrics && isShowingGeniusLyrics == genius {
            closePlaybackSidebar()
            return
        } else {
            selectedSidebarPanel = .lyrics
            playbackPresentation.presentSidebar()
        }
        isShowingGeniusLyrics = genius
        selectedFullscreenPanel = .lyrics
        if genius { self.genius.ensureNow() }
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
    private var lyricsAttemptedVideoID: String?
    private(set) var radioTask: Task<Void, Never>?
    private(set) var albumMetadataTask: Task<Void, Never>?
    private var albumMetadataRequest: (identity: UUID, token: UUID, albumID: String)?
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
    /// Read-only occurrence identity for the optional lyrics experiment.
    var experimentalLyricsPlaybackIdentity: UUID { currentPlaybackToken }
    private var playlistRequest = UUID()
    private var providerActionQueueToken: UUID?
    private var providerActionContinuations = Set<String>()
    private var playlistContinuationTask: Task<Void, Never>?
    public private(set) var isLoadingPlaylistContinuation: Bool = false
    private var currentPlaybackToken: UUID = UUID() {
        didSet {
            if oldValue != currentPlaybackToken {
                volumeScroll.cancel()
                pendingLyricSeek = nil
            }
        }
    }
    struct PendingLyricSeek: Equatable {
        let playbackID: UUID
        let sessionID: UUID
        let videoID: String
        let seconds: Double
    }
    private(set) var pendingLyricSeek: PendingLyricSeek?
    private var searchRecentIntent: (id: UUID, playbackID: UUID, videoID: String)?
    private var pendingTailSkipToken: UUID?
    public private(set) var queueRecommendationError: String?
    private var radioExhausted = false
    private var radioRequestCursors = Set<String>()
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
    private let searchRecents: SearchRecentStore
    private let playbackStore: PlaybackStateStore
    private let playlistCatalog: PlaylistCatalog
    private var currentPlaybackIdentity: String?
    private var isSwitchingPlaybackSession = false

    public convenience init(rustCore: SideBCore? = nil, audioService: AudioPlayerService = .shared) {
        self.init(rustCore: rustCore, audioService: audioService, playbackStore: PlaybackStateStore())
    }

    init(rustCore: SideBCore?, audioService: AudioPlayerService, playbackStore: PlaybackStateStore,
         playlistCatalog: PlaylistCatalog? = nil, searchRecents: SearchRecentStore? = nil) {
        self.rustCore = rustCore
        self.audioService = audioService
        self.playbackStore = playbackStore
        self.searchRecents = searchRecents ?? .shared
        self.playlistCatalog = playlistCatalog ?? .shared
        setupRemoteCommands()
        setupTrackEndListener()
        setupPlaybackProgressListener()
        audioService.onPlaybackStarted = { [weak self] playbackID in
            guard let self, let intent = self.searchRecentIntent,
                  intent.playbackID == playbackID, self.currentPlaybackToken == playbackID,
                  self.currentTrack?.videoId == intent.videoID else { return }
            self.searchRecents.confirmTrack(intent.id, videoId: intent.videoID)
            self.searchRecentIntent = nil
        }
        audioService.onPlaybackFailed = { [weak self] playbackID in
            guard let self, self.searchRecentIntent?.playbackID == playbackID else { return }
            self.failSearchRecentIntent()
        }
        queueManager.onStateChange = { [weak self] in self?.schedulePlaybackSave() }
        if rustCore != nil {
            hydrateLikedSongs()
        }
    }

    private func playbackSnapshot() -> SavedPlaybackState {
        if let jamSnapshot { return jamSnapshot }
        return SavedPlaybackState(
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
            order: queueManager.orderSnapshot,
            radioCursorVideoID: queueManager.radioCursorVideoID
        )
    }

    private func schedulePlaybackSave() {
        guard !isSwitchingPlaybackSession else { return }
        playbackStore.scheduleSave(snapshot: { [weak self] in self?.playbackSnapshot() })
    }

    public func flushPlaybackState() {
        guard currentPlaybackIdentity != nil else { return }
        playbackStore.saveNow(playbackSnapshot())
    }

    public func switchPlaybackSession(to identity: String) {
        guard currentPlaybackIdentity != identity else { return }
        searchRecents.setAccount(identity)
        cancelSearchRecentIntent()
        if currentPlaybackIdentity != nil { flushPlaybackState() }
        if isJamSessionActive { JamSessionController.shared.leave(restore: .discard) }
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
        cancelRecommendationLoading()
        albumMetadataTask?.cancel()
        albumMetadataRequest = nil
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
        recommendedTracks = []
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
        guard restoreQueue(from: saved) else {
            isSwitchingPlaybackSession = false
            updateNowPlayingInfo()
            return
        }
        updateNowPlayingInfo()
        isSwitchingPlaybackSession = false
    }

    /// Rebuilds the queue, order and current track from a saved session (launch restore and Jam exit).
    /// Returns false, leaving an empty queue, when the saved order does not validate.
    private func restoreQueue(from saved: SavedPlaybackState) -> Bool {
        let tracks = saved.tracks.map(\.song)
        queueManager.replaceQueue(with: tracks, startingAt: saved.currentIndex,
                                  context: saved.context?.queueContext,
                                  contextTitle: saved.contextTitle,
                                  radioSeed: saved.radioSeed, restoringCommittedQueue: true)
        queueManager.setContextLocalizationKey(saved.context?.localizationKey, args: saved.context?.localizationArguments ?? [])
        guard queueManager.restoreOrder(saved.order, isShuffle: saved.isShuffle) else {
            queueManager.clearQueue()
            return false
        }
        queueManager.radioCursorVideoID = saved.radioCursorVideoID
        queueManager.isRepeat = saved.isRepeat
        currentTrack = queueManager.currentTrack ?? saved.currentTrack?.song
        currentPlaylistBrowseId = {
            if case .playlist(let id, _) = queueManager.context { return id }
            return nil
        }()
        isCurrentTrackLiked = currentTrack.map { likedVideoIds.contains($0.videoId) } ?? false
        return true
    }

    private func setupTrackEndListener() {
        self.audioService.onTrackDidEnd = { [weak self] in
            guard let self, !self.isJamSessionActive else { return }
            self.playNext(isManualSkip: false)
        }
    }

    private func setupPlaybackProgressListener() {
        self.audioService.onPlaybackProgress = { [weak self] current, duration in
            self?.rememberCurrentTrackDuration(duration)
            self?.checkAndRecordPlaybackHistory(current: current, duration: duration)
        }
    }

    /// Preserve resolved metadata when this occurrence stops being the active row.
    /// Catalog duration wins, and already enriched tracks incur no repeated mutation.
    private func rememberCurrentTrackDuration(_ seconds: Double) {
        guard var track = currentTrack, HomeSongMetadata.clean(track.duration) == nil,
              seconds.isFinite, seconds > 0, seconds < Double(Int.max),
              let occurrenceID = queueManager.currentOccurrenceID,
              queueManager.currentTrack?.videoId == track.videoId else { return }
        let queueToken = queueManager.queueToken
        track.duration = formatTime(seconds)
        currentTrack = track
        queueManager.updateCurrentMetadata(track, occurrenceID: occurrenceID, queueToken: queueToken)
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
        queueRecommendationError = nil
        radioExhausted = false
        radioRequestCursors.removeAll()
        cancelSearchRecentIntent()
        providerActionQueueToken = nil
        providerActionContinuations = []
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
        if deferForJamExit(subject: song.title, { [weak self] in self?.playWithRadio(song, albumBrowseId: albumBrowseId, artistBrowseId: artistBrowseId) }) { return }
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
        if deferForJamExit(subject: song.title, { [weak self] in self?.activateMediaRadio(song) }) { return }
        if MediaPlaybackIdentity.isRadioOrigin(videoID: song.videoId, context: queueManager.context), currentTrack != nil {
            cancelPendingMediaCollectionLoad()
            togglePlayPause()
        } else {
            playWithRadio(song)
        }
    }

    /// Spotlight remembers the selected recording only after the accepted item starts.
    func activateSearchMediaRadio(_ song: SongItemRecord, restart: Bool = false) {
        if deferForJamExit(subject: song.title, { [weak self] in self?.activateSearchMediaRadio(song, restart: restart) }) { return }
        cancelSearchRecentIntent()
        if !restart, currentTrack?.videoId == song.videoId, errorMessage == nil,
           isLoadingStream || audioService.isPlaying {
            let intent = searchRecents.beginTrack(song)
            if audioService.isPlayingItem(playbackID: currentPlaybackToken) {
                searchRecents.confirmTrack(intent, videoId: song.videoId)
            } else {
                searchRecentIntent = (intent, currentPlaybackToken, song.videoId)
            }
            return
        }
        if !restart, currentTrack?.videoId == song.videoId,
           MediaPlaybackIdentity.isRadioOrigin(videoID: song.videoId, context: queueManager.context) {
            activateMediaRadio(song)
        } else {
            playWithRadio(song)
        }
        guard currentTrack?.videoId == song.videoId, errorMessage == nil,
              isLoadingStream || audioService.isPlaying else { return }
        searchRecentIntent = (searchRecents.beginTrack(song), currentPlaybackToken, song.videoId)
    }

    private func cancelSearchRecentIntent() {
        if let intent = searchRecentIntent { searchRecents.cancelTrack(intent.id) }
        searchRecentIntent = nil
    }

    private func failSearchRecentIntent() {
        if let intent = searchRecentIntent { searchRecents.failTrack(intent.id) }
        searchRecentIntent = nil
    }

    /// All cards use the same collection identity and guarded catalog loading path.
    func activateMediaCollection(id: String, kind: String) {
        guard !id.isEmpty else { return }
        if deferForJamExit(subject: nil, { [weak self] in self?.activateMediaCollection(id: id, kind: kind) }) { return }
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
        if deferForJamExit(subject: nil, { [weak self] in self?.playRecommendedCollection(browseId: browseId, kind: kind, shuffle: shuffle) }) { return }
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
        if deferForJamExit(subject: title, { [weak self] in self?.playAlbum(browseId: browseId, title: title, tracks: tracks, startingAt: startingAt, artistBrowseId: artistBrowseId, shuffle: shuffle) }) { return }
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
        if deferForJamExit(subject: title, { [weak self] in self?.playPlaylist(browseId: browseId, title: title, tracks: tracks, startingAt: startingAt, continuation: continuation, shuffle: shuffle) }) { return }
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
        if deferForJamExit(subject: title, { [weak self] in self?.playCollection(tracks: tracks, title: title, artistBrowseId: artistBrowseId, shuffle: shuffle, startingAt: startingAt) }) { return }
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
    /// Execute the exact provider watch destination, including radio/shuffle params.
    func activateProviderSearchAction(_ action: SearchActionRecord, title: String, source: BrowseCardRecord? = nil) {
        guard let core = rustCore, action.videoId != nil || action.playlistId != nil else { return }
        if deferForJamExit(subject: title, { [weak self] in self?.activateProviderSearchAction(action, title: title, source: source) }) { return }
        cancelInFlightRadioTasks()
        let token = UUID()
        currentRadioToken = token
        let generation = accountGeneration
        let queueToken = queueManager.queueToken
        let playbackToken = currentPlaybackToken
        collectionRadioTask = Task {
            do {
                let result = try await core.searchAction(videoId: action.videoId,
                    playlistId: action.playlistId, params: action.params)
                guard !Task.isCancelled, currentRadioToken == token, accountGeneration == generation,
                      queueManager.queueToken == queueToken, currentPlaybackToken == playbackToken else { return }
                guard !result.items.isEmpty else { return }
                let index = action.videoId.flatMap { video in result.items.firstIndex { $0.videoId == video } } ?? 0
                let context: QueueContext
                if let source, !MenuIDNormalizer.isDynamicRadioMix(id: action.playlistId ?? ""), source.kind == "album" {
                    context = .album(browseId: source.id, title: source.title)
                } else if let source, !MenuIDNormalizer.isDynamicRadioMix(id: action.playlistId ?? ""), source.kind == "playlist" {
                    context = .playlist(browseId: source.id, title: source.title)
                } else {
                    context = action.playlistId.flatMap { id in
                        MenuIDNormalizer.isDynamicRadioMix(id: id) ? nil : QueueContext.playlist(browseId: id, title: title)
                    } ?? .radio(seedVideoId: action.videoId ?? "", title: title, seedName: title)
                }
                queueManager.replaceQueue(with: result.items, startingAt: index,
                    context: context,
                    contextTitle: source?.title ?? title, radioSeed: result.automixPlaylistId ?? action.playlistId, continuation: result.continuation)
                providerActionQueueToken = queueManager.queueToken
                providerActionContinuations = []
                playQueueIndex(queueManager.currentIndex)
            } catch {
                guard !Task.isCancelled, currentRadioToken == token, accountGeneration == generation else { return }
                errorMessage = L10n.text("search.error.global")
            }
        }
    }

    public func startRadioForCollection(
        id: String,
        title: String,
        prefix: String = "RDAMPL",
        directRadioId: String? = nil,
        fallbackTracks: [SongItemRecord] = []
    ) {
        guard let core = rustCore else { return }
        if deferForJamExit(subject: title, { [weak self] in self?.startRadioForCollection(id: id, title: title, prefix: prefix, directRadioId: directRadioId, fallbackTracks: fallbackTracks) }) { return }
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
    
    /// Explicit choices made while stopped resume at the new occurrence, retaining previous songs.
    private func enqueueChosenTracks(_ tracks: [SongItemRecord], next: Bool) {
        guard !tracks.isEmpty else { return }
        if isJamSessionActive {
            // The Jam owns the queue: the manager hands the request to it (resolve on Spotify, then
            // insert/add); nothing is added locally.
            if next { queueManager.playNext(tracks) } else { queueManager.addTracksToQueue(tracks) }
            return
        }
        if currentTrack == nil, queueManager.queue.isEmpty, tracks.count == 1 {
            playWithRadio(tracks[0])
            return
        }
        if queueManager.queue.isEmpty { cancelInFlightRadioTasks() }
        if next { queueManager.playNext(tracks) } else { queueManager.addTracksToQueue(tracks) }
        if currentTrack == nil, let selected = queueManager.currentTrack {
            playSongNow(selected)
            checkAutomixTrigger()
        }
    }
    public func playNext(song: SongItemRecord) { enqueueChosenTracks([song], next: true) }
    public func playNext(tracks: [SongItemRecord]) { enqueueChosenTracks(tracks, next: true) }
    public func addToQueue(song: SongItemRecord) { enqueueChosenTracks([song], next: false) }
    public func addToQueue(tracks: [SongItemRecord]) { enqueueChosenTracks(tracks, next: false) }

    public func enqueueQueueRecommendation(id: String, sessionID: UUID, next: Bool) {
        guard !isJamSessionActive else { return }
        guard queueManager.recommendationSessionID == sessionID,
              queueManager.recommendationEntries.contains(where: { $0.id == id }) else { return }
        queueManager.enqueueRecommendation(id: id, next: next)
        if currentTrack == nil, let selected = queueManager.currentTrack {
            playSongNow(selected)
            checkAutomixTrigger()
        }
    }

    /// Resuelve el stream de audio vía Rust y arranca la reproducción con AVPlayer.
    public func playSongNow(
        _ song: SongItemRecord,
        overrideAlbumBrowseId: String? = nil,
        overrideArtistBrowseId: String? = nil,
        deferStreamResolution: Bool = false
    ) {
        cancelSearchRecentIntent()
        // 1. Cancelar tareas en vuelo previas para evitar carreras al skipear
        resolveStreamTask?.cancel()
        lyricsTask?.cancel()
        cancelRecommendationLoading()
        albumMetadataTask?.cancel()
        albumMetadataRequest = nil

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
            self.recommendedTracks = []
        }

        self.lyricsInfo = nil
        self.isLoadingLyrics = false

        guard let core = rustCore else {
            self.errorDescriptor = AppMessage(key: "player.error.coreUnavailable")
            self.isLoadingStream = false
            return
        }

        hydrateCurrentAlbumMetadata()

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
                    expectedDuration: expectedSecs,
                    playbackID: token
                )
                self.applyPendingLyricSeek(playbackID: token, videoID: song.videoId)
                self.applyPendingResume(videoID: song.videoId)
                self.rememberCurrentTrackDuration(self.audioService.duration)
                self.genius.playbackStarted(identity: token)
                self.updateNowPlayingInfo()
            } catch {
                guard !Task.isCancelled, self.currentPlaybackToken == token else { return }
                self.failSearchRecentIntent()
                self.pendingLyricSeek = nil
                self.isLoadingStream = false
                self.pendingResume = nil
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
        if deferForJamExit(subject: song.title, { [weak self] in self?.playSong(song, addToQueue: addToQueue, albumBrowseId: albumBrowseId, artistBrowseId: artistBrowseId) }) { return }
        if addToQueue {
            playWithRadio(song, albumBrowseId: albumBrowseId, artistBrowseId: artistBrowseId)
        } else {
            playSongNow(song, overrideAlbumBrowseId: albumBrowseId, overrideArtistBrowseId: artistBrowseId)
        }
    }

    public func playNext(isManualSkip: Bool = true) {
        if let jamControl { if isManualSkip { jamControl(.next) }; return }
        if currentTrack == nil, let selected = queueManager.currentTrack {
            playSongNow(selected, deferStreamResolution: isManualSkip)
            checkAutomixTrigger()
            return
        }
        if let next = queueManager.nextTrack(isManualSkip: isManualSkip) {
            playSongNow(next, deferStreamResolution: isManualSkip)
            checkAutomixTrigger()
        } else if queueManager.isNearTail {
            pendingTailSkipToken = currentPlaybackToken
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
        if let jamControl { jamControl(.previous); return }
        if let prev = queueManager.previousTrack() {
            playSongNow(prev, deferStreamResolution: true)
        }
    }

    func resumeAfterQueueExtension() {
        let manualSkipIsPending = pendingTailSkipToken == currentPlaybackToken
        guard manualSkipIsPending, !isLoadingStream else { return }
        pendingTailSkipToken = nil
        guard let next = currentTrack == nil ? (queueManager.currentTrack ?? queueManager.nextTrack(isManualSkip: true)) : queueManager.nextTrack(isManualSkip: manualSkipIsPending) else { return }
        playSongNow(next)
        checkAutomixTrigger()
    }

    public func playQueueIndex(_ index: Int) {
        // The Jam cannot jump to an arbitrary row: say so instead of silently doing nothing.
        guard !isJamSessionActive else { queueManager.sessionEditor?.sessionRejected(.playRow); return }
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

    public func dislikeTrack(_ track: SongItemRecord, occurrenceID: String? = nil, recommendationID: String? = nil) {
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
        queueManager.excludeRecommendationVideo(track.videoId)
        if recommendationID != nil {
            // A proposal rating must never remove a chosen duplicate.
        } else if let occurrenceID, let index = queueManager.occurrenceIndex(id: occurrenceID) {
            removeQueueTrack(at: index)
        } else if occurrenceID == nil, currentTrack?.videoId == track.videoId {
            removeQueueTrack(at: queueManager.currentIndex)
        } else if occurrenceID == nil {
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
        if isJamSessionActive {
            _ = queueManager.removeTrack(at: index) // Routed to the Jam; the current row is refused.
            return
        }
        if index == queueManager.currentIndex {
            if let next = queueManager.advanceAfterRemovingCurrent() {
                playSongNow(next)
                checkAutomixTrigger()
            } else {
                audioService.stop()
                resolveStreamTask?.cancel()
                currentTrack = nil
                currentPlaybackToken = UUID()
                updateNowPlayingInfo()
                if queueManager.continuationToken != nil || !radioExhausted {
                    pendingTailSkipToken = currentPlaybackToken
                    if queueManager.continuationToken != nil { extendPlaylistIfNeeded() }
                    else { extendRadioIfNeeded() }
                }
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
        albumMetadataTask?.cancel()
        albumMetadataRequest = nil
        cancelRecommendationLoading()
        recommendedData = nil
        recommendedLoadedKey = nil
        recommendedTracks = []
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
    /// The album link may be trustworthy while Home's positional label is not.
    /// Resolve its canonical title independently of the audio stream or radio page.
    private func hydrateCurrentAlbumMetadata() {
        guard let core = rustCore, let track = currentTrack,
              HomeSongMetadata.clean(track.album) == nil,
              let albumID = HomeSongMetadata.clean(track.albumId) else { return }
        let playbackToken = currentPlaybackToken
        guard albumMetadataRequest?.token != playbackToken || albumMetadataRequest?.albumID != albumID else { return }
        let requestIdentity = UUID()
        albumMetadataRequest = (requestIdentity, playbackToken, albumID)
        let generation = accountGeneration
        let queueToken = queueManager.queueToken
        let occurrenceID = queueManager.currentOccurrenceID
        albumMetadataTask = Task {
            defer {
                if self.albumMetadataRequest?.identity == requestIdentity {
                    self.albumMetadataRequest = nil
                }
            }
            do {
                let album = try await core.getAlbum(browseId: albumID)
                guard !Task.isCancelled, self.currentPlaybackToken == playbackToken,
                      self.accountGeneration == generation, self.queueManager.queueToken == queueToken,
                      self.queueManager.currentOccurrenceID == occurrenceID,
                      let current = self.currentTrack, current.videoId == track.videoId,
                      HomeSongMetadata.clean(current.albumId) == albumID else { return }
                let enriched = PlaybackAlbumMetadata.merging(current, album: album)
                guard enriched != current else { return }
                self.currentTrack = enriched
                self.queueManager.updateCurrentMetadata(enriched, occurrenceID: occurrenceID, queueToken: queueToken)
                self.updateNowPlayingInfo()
            } catch {
                // Missing/error metadata keeps the known destination and an absent name.
                // It must never fail playback or fall back to a view count.
            }
        }
    }

    /// Loads lyrics only when this track has not been attempted yet. Views use it so that
    /// reopening a panel never repeats a request that already finished empty or failed.
    func loadLyricsIfNeeded(for track: SongItemRecord) {
        guard lyricsInfo == nil, !isLoadingLyrics, lyricsAttemptedVideoID != track.videoId else { return }
        loadLyrics(for: track)
    }

    public func loadLyrics(for track: SongItemRecord, token: UUID? = nil) {
        guard let core = rustCore else { return }
        lyricsTask?.cancel()
        lyricsAttemptedVideoID = track.videoId
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
        guard !isJamSessionActive else { return }
        guard let core = rustCore else { return }

        radioTask?.cancel()
        let token = UUID()
        self.currentRadioToken = token
        let targetQueueToken = queueManager.queueToken
        let targetVideoId = track.videoId
        let targetPlaybackToken = currentPlaybackToken
        let targetAccountGeneration = accountGeneration
        let targetOccurrenceID = queueManager.currentOccurrenceID

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
                      self.currentPlaybackToken == targetPlaybackToken,
                      self.accountGeneration == targetAccountGeneration,
                      self.queueManager.queueToken == targetQueueToken,
                      self.currentTrack?.videoId == targetVideoId else {
                    return
                }
                if !radioResult.items.isEmpty {
                    self.queueManager.appendRadioTracks(radioResult.items, continuation: radioResult.continuation)
                    if let seed = radioResult.automixPlaylistId {
                        self.queueManager.radioSeed = seed
                    }
                    
                    // Si el audio finalizó mientras se cargaba la radio y la cola quedó a la espera, reanudar de inmediato
                    self.resumeAfterQueueExtension()

                    // Completar álbum y enlaces ausentes con los metadatos de la misma pista en la radio.
                    if self.currentPlaybackToken == targetPlaybackToken,
                       self.queueManager.currentOccurrenceID == targetOccurrenceID,
                       let cur = self.currentTrack, cur.videoId == targetVideoId,
                       cur.album == nil || cur.artistRuns.isEmpty {
                        if let match = radioResult.items.first(where: { $0.videoId == targetVideoId }) {
                            var enriched = PlaybackAlbumMetadata.merging(cur, radio: match)
                            if cur.artists.trimmingCharacters(in: .whitespacesAndNewlines)
                                .caseInsensitiveCompare(match.artists.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
                                enriched.artistId = cur.artistId ?? match.artistId
                                enriched.artistRuns = cur.artistRuns.isEmpty ? match.artistRuns : cur.artistRuns
                            }
                            if enriched != cur {
                                self.currentTrack = enriched
                                self.queueManager.updateCurrentMetadata(enriched, occurrenceID: targetOccurrenceID, queueToken: targetQueueToken)
                                self.updateNowPlayingInfo()
                            }
                            if let albId = enriched.albumId {
                                self.currentAlbumBrowseId = albId
                            }
                            self.hydrateCurrentAlbumMetadata()
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled, self.currentRadioToken == token else { return }
                queueRecommendationError = L10n.text("queue.recommendationsError")
            }
        }
    }

    // MARK: - Recomendaciones bajo demanda
    public func cancelRecommendationLoading() {
        recommendedRequest.cancel()
        recommendedTask?.cancel()
        recommendedTask = nil
        isLoadingRecommended = false
        recommendedError = nil
    }

    public func fetchRecommendations(for track: SongItemRecord, forceRefresh: Bool = false) {
        guard currentTrack?.videoId == track.videoId, let core = rustCore else {
            if currentTrack == nil || rustCore == nil { cancelRecommendationLoading() }
            return
        }
        guard let key = recommendationContextKey else { return }
        if !forceRefresh, recommendedLoadedKey == key, recommendedData != nil {
            if recommendedRequest.key != key { cancelRecommendationLoading() }
            return
        }
        guard let request = recommendedRequest.begin(key, force: forceRefresh) else { return }
        recommendedTask?.cancel()
        if recommendedData?.loadedVideoId != track.videoId {
            recommendedData = nil
            recommendedTracks = []
        }
        recommendedError = nil
        isLoadingRecommended = true

        if forceRefresh {
            recommendedReloadCount += 1
        } else {
            recommendedReloadCount = 0
        }
        let currentReload = recommendedReloadCount
        let targetVideoId = track.videoId
        let targetArtistId = key.artistID
        let targetAlbumId = key.albumID
        let artistName = track.displayArtist
        let albumTitle = track.displayAlbum

        recommendedTask = Task { [weak self] in
            defer {
                if let self, self.recommendedRequest.finish(request) {
                    self.isLoadingRecommended = false
                    self.recommendedTask = nil
                }
            }
            // Each endpoint publishes its section as soon as it arrives. The request
            // token and account key reject late results, including A → B → A.
            async let similarFailed: Bool = { @MainActor [weak self] in
                do {
                    let items = try await core.getRelatedTracks(videoId: targetVideoId)
                    var songs = items.filter { $0.videoId != targetVideoId }
                    if currentReload > 0 && songs.count > 4 {
                        let offset = (currentReload * 4) % songs.count
                        songs = Array(songs.dropFirst(offset) + songs.prefix(offset))
                    }
                    self?.applyRecommendedBatch(request: request, key: key) { $0.similarSongs = songs }
                    if let self, self.recommendedRequest.owns(request), self.recommendationContextKey == key { self.recommendedTracks = songs }
                    return false
                } catch { return !Task.isCancelled }
            }()
            async let artistFailed: Bool = { @MainActor [weak self] in
                async let detailResult: (ArtistDetailRecord?, Bool) = {
                    guard let id = targetArtistId, !id.isEmpty else { return (nil, false) }
                    do { return (try await core.getArtist(browseId: id), false) }
                    catch { return (nil, !Task.isCancelled) }
                }()
                var related: [BrowseCardRecord] = []
                var failed = false
                do {
                    related = try await core.getRelatedArtists(videoId: targetVideoId)
                    self?.applyRecommendedBatch(request: request, key: key) { $0.relatedArtists = related }
                } catch { failed = !Task.isCancelled }
                let (detail, detailFailed) = await detailResult
                if let detail {
                    if related.isEmpty {
                        for section in detail.sections {
                            let title = section.title.lowercased()
                            if title.contains("fans") || title.contains("similar") || title.contains("like") {
                                related.append(contentsOf: section.items.filter { $0.kind.lowercased() == "artist" })
                            } else if related.isEmpty {
                                related.append(contentsOf: section.items.filter { $0.kind.lowercased() == "artist" })
                            }
                        }
                    }
                    self?.applyRecommendedBatch(request: request, key: key) {
                        $0.artistSongs = detail.topSongs.filter { $0.videoId != targetVideoId }
                        $0.relatedArtists = related
                    }
                }
                return failed || detailFailed
            }()
            async let albumFailed: Bool = { @MainActor [weak self] in
                guard let id = targetAlbumId, !id.isEmpty else { return false }
                do {
                    let detail = try await core.getAlbum(browseId: id)
                    self?.applyRecommendedBatch(request: request, key: key) {
                        $0.albumSongs = detail.items.filter { $0.videoId != targetVideoId }
                    }
                    return false
                } catch { return !Task.isCancelled }
            }()
            let failures = await (similarFailed, artistFailed, albumFailed)
            guard !Task.isCancelled, let self, self.recommendedRequest.owns(request), self.recommendationContextKey == key else { return }
            if self.recommendedData == nil {
                self.recommendedData = RecommendedData(artistName: artistName, artistBrowseId: targetArtistId,
                    artistSongs: [], albumTitle: albumTitle, albumBrowseId: targetAlbumId, albumSongs: [],
                    similarSongs: [], relatedArtists: [], loadedVideoId: targetVideoId)
            }
            let failed = failures.0 || failures.1 || failures.2
            self.recommendedError = failed ? L10n.text("queue.recommendationsError") : nil
            self.recommendedLoadedKey = failed ? nil : key
        }
    }

    private func applyRecommendedBatch(request: UUID, key: RecommendedRequestState.Key, update: (inout RecommendedData) -> Void) {
        guard !Task.isCancelled, recommendedRequest.owns(request), recommendationContextKey == key else { return }
        var next = recommendedData?.loadedVideoId == key.videoID ? recommendedData! : RecommendedData(
            artistName: currentTrack?.displayArtist, artistBrowseId: key.artistID, artistSongs: [],
            albumTitle: currentTrack?.displayAlbum, albumBrowseId: key.albumID, albumSongs: [],
            similarSongs: [], relatedArtists: [], loadedVideoId: key.videoID)
        update(&next)
        if next != recommendedData { recommendedData = next }
    }

    public func refreshRecommendations() {
        guard let track = currentTrack else { return }
        fetchRecommendations(for: track, forceRefresh: true)
    }

    /// Disparo transparente de Automix o Continuación de Playlist:
    /// Si la cola activa es una playlist con continuación disponible, carga la siguiente página de la misma playlist.
    /// Si no, o si es radio, extiende vía Automix.
    public func checkAutomixTrigger() {
        guard !isJamSessionActive else { return }
        guard queueManager.isNearTail else { return }

        if providerActionQueueToken == queueManager.queueToken,
           (queueManager.continuationToken != nil || queueManager.radioContinuationToken != nil) {
            extendProviderActionIfNeeded()
            return
        }

        // 1. Si es playlist con continuación pendiente, paginar la playlist
        if case .playlist = queueManager.context,
           let continuation = queueManager.continuationToken,
           !continuation.isEmpty {
            extendPlaylistIfNeeded()
            return
        }

        // 2. Extender vía Automix
        guard !queueManager.isLoadingAutoplay, !queueManager.isLoadingRadio,
              queueManager.recommendationEntries.count < 3, !radioExhausted else { return }
        extendRadioIfNeeded()
    }

    /// Extiende la cola activa solicitando la siguiente página de la playlist actual.
    public func extendPlaylistIfNeeded() {
        guard !isJamSessionActive else { return }
        if providerActionQueueToken == queueManager.queueToken { extendProviderActionIfNeeded(); return }
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
                print("[PlayerViewModel] Cargando continuación de playlist")
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

    /// `/next` continuations from provider buttons must never be sent to `/browse`.
    func extendProviderActionIfNeeded() {
        guard !isJamSessionActive else { return }
        guard let core = rustCore, providerActionQueueToken == queueManager.queueToken,
              !isLoadingPlaylistContinuation, !queueManager.isLoadingAutoplay, let continuation = queueManager.continuationToken ?? queueManager.radioContinuationToken,
              !providerActionContinuations.contains(continuation) else { return }
        let queueToken = queueManager.queueToken
        let generation = accountGeneration
        let radioSession: Bool = { if case .radio = queueManager.context { return true }; return false }()
        if radioSession { queueManager.isLoadingAutoplay = true } else { isLoadingPlaylistContinuation = true }
        playlistContinuationTask?.cancel()
        playlistContinuationTask = Task {
            defer {
                if queueManager.queueToken == queueToken {
                    if radioSession { queueManager.isLoadingAutoplay = false } else { isLoadingPlaylistContinuation = false }
                }
            }
            do {
                let result = try await core.getNextContinuation(token: continuation)
                guard !Task.isCancelled, accountGeneration == generation, queueManager.queueToken == queueToken,
                      providerActionQueueToken == queueToken else { return }
                providerActionContinuations.insert(continuation)
                let next = result.continuation.flatMap { providerActionContinuations.contains($0) ? nil : $0 }
                // The provider owns playlist occurrences and ordering, including repeated songs.
                if case .radio = queueManager.context {
                    queueManager.radioContinuationToken = next
                    queueManager.appendRadioTracks(result.items, continuation: next)
                    if result.items.isEmpty || next == nil { radioExhausted = true }
                } else {
                    queueManager.appendPlaylistTracks(result.items, nextContinuation: next)
                }
                resumeAfterQueueExtension()
            } catch {
                guard !Task.isCancelled, accountGeneration == generation, queueManager.queueToken == queueToken else { return }
                if radioSession { queueRecommendationError = L10n.text("queue.recommendationsError") }
                else { errorMessage = L10n.text("search.error.global") }
            }
        }
    }

    public func retryQueueRecommendations() {
        queueRecommendationError = nil
        radioExhausted = false
        radioRequestCursors.removeAll()
        extendRadioIfNeeded()
    }

    public func playQueueRecommendation(id: String, sessionID: UUID) {
        if deferForJamExit(subject: nil, { [weak self] in self?.playQueueRecommendation(id: id, sessionID: sessionID) }) { return }
        guard sessionID == queueManager.recommendationSessionID,
              let track = queueManager.playRecommendation(id: id, advanceThrough: QueuePreferences.selection(in: HomeAppearance.preferences) == .advance) else { return }
        playSongNow(track, deferStreamResolution: true)
        checkAutomixTrigger()
    }

    public func extendRadioIfNeeded() {
        guard !isJamSessionActive else { return }
        if providerActionQueueToken == queueManager.queueToken,
           (queueManager.continuationToken != nil || queueManager.radioContinuationToken != nil) {
            extendProviderActionIfNeeded(); return
        }
        guard let core = rustCore, !queueManager.isLoadingAutoplay,
              !queueManager.isLoadingRadio, !isCompletingActivePlaylistSource,
              queueManager.continuationToken == nil, !radioExhausted else { return }
        guard let lastVideo = queueManager.radioCursorVideoID ?? queueManager.currentTrack?.videoId else { return }
        automixTask?.cancel()
        let token = UUID()
        currentAutomixToken = token
        let targetQueueToken = queueManager.queueToken
        let targetGeneration = accountGeneration
        let targetSeed = queueManager.radioSeed
        queueManager.isLoadingAutoplay = true
        queueRecommendationError = nil
        automixTask = Task {
            defer {
                if currentAutomixToken == token { queueManager.isLoadingAutoplay = false }
            }
            var cursor = lastVideo
            for _ in 0..<3 {
                do {
                    let opaque = queueManager.radioContinuationToken
                    let key = opaque ?? cursor
                    guard radioRequestCursors.insert(key).inserted else { radioExhausted = true; break }
                    let result = try await {
                        if let opaque { return try await core.getNextContinuation(token: opaque) }
                        return try await core.getRadioContinuation(lastVideoId: cursor, radioSeed: targetSeed)
                    }()
                    guard !Task.isCancelled, currentAutomixToken == token,
                          accountGeneration == targetGeneration,
                          queueManager.queueToken == targetQueueToken else { return }
                    let before = queueManager.recommendationEntries.count
                    queueManager.radioContinuationToken = result.continuation
                    queueManager.appendRadioTracks(result.items, continuation: result.continuation)
                    if let seed = result.automixPlaylistId { queueManager.radioSeed = seed }
                    if queueManager.recommendationEntries.count > before {
                        resumeAfterQueueExtension()
                        return
                    }
                    guard let nextCursor = result.items.last?.videoId, nextCursor != cursor else {
                        radioExhausted = true; break
                    }
                    cursor = nextCursor
                    queueManager.radioCursorVideoID = cursor
                } catch {
                    guard !Task.isCancelled, currentAutomixToken == token,
                          queueManager.queueToken == targetQueueToken else { return }
                    radioRequestCursors.removeAll()
                    queueRecommendationError = L10n.text("queue.recommendationsError")
                    return
                }
            }
            radioExhausted = true
        }
    }


    public func togglePlayPause() {
        if let jamControl { jamControl(.togglePlayPause); return }
        if pendingTailSkipToken != nil {
            pendingTailSkipToken = nil
            audioService.pause()
            updateNowPlayingPlaybackRate()
            return
        }
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
        if let jamControl { jamControl(.seek(fraction: fraction)); return }
        audioService.seek(toFraction: fraction)
    }

    /// Lyrics name an absolute media cue even before duration is known. Loaded
    /// playback keeps its paused/playing state; a restored track resolves once.
    @discardableResult
    func seekToLyric(seconds: Double) -> Bool {
        guard seconds.isFinite, seconds >= 0, let track = currentTrack else { return false }
        if audioService.avPlayer.currentItem != nil && !isLoadingStream {
            pendingLyricSeek = nil
            return audioService.seek(toSeconds: seconds)
        }
        guard rustCore != nil else { return false }
        if !isLoadingStream { playSongNow(track) }
        guard isLoadingStream, currentTrack?.videoId == track.videoId else { return false }
        pendingLyricSeek = PendingLyricSeek(playbackID: currentPlaybackToken, sessionID: accountGeneration,
                                           videoID: track.videoId, seconds: seconds)
        return true
    }

    /// After leaving a Jam the user's track is loaded but must stay paused at the saved position.
    private func applyPendingResume(videoID: String) {
        guard let resume = pendingResume else { return }
        pendingResume = nil
        guard resume.videoID == videoID, !isJamSessionActive else { return }
        if resume.seconds > 1 { audioService.seek(toSeconds: resume.seconds) }
        audioService.pause()
        updateNowPlayingPlaybackRate()
    }

    private func applyPendingLyricSeek(playbackID: UUID, videoID: String) {
        guard let intent = pendingLyricSeek else { return }
        pendingLyricSeek = nil
        guard intent.playbackID == playbackID, playbackID == currentPlaybackToken,
              intent.sessionID == accountGeneration, intent.videoID == videoID,
              currentTrack?.videoId == videoID else { return }
        audioService.seek(toSeconds: intent.seconds)
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
                self?.pendingTailSkipToken = nil
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
                return candidate.isEmpty || HomeSongMetadata.isStatistic(candidate) || HomeSongMetadata.isDuration(candidate) ? nil : candidate
            }
        }
        return nil
    }

    /// Construye un SongItemRecord a partir de un HomeItemRecord desglosando artista y álbum si vienen concatenados
    public init(fromHomeItem item: HomeItemRecord) {
        let artistName = HomeSongMetadata.artist(from: item)
        let albumName = HomeSongMetadata.album(from: item)
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
            isVideo: item.kind == "video", isUpload: false, library: nil,
            artistRuns: HomeSongMetadata.artistRuns(from: item),
            contentRating: item.effectiveContentRating
        )
    }

    /// Construye un SongItemRecord a partir de un BrowseCardRecord desglosando artista y álbum si vienen concatenados
    public init(fromCard card: BrowseCardRecord, fallbackArtist: String? = nil, knownArtistId: String? = nil) {
        let artistName = HomeSongMetadata.artist(subtitle: card.subtitle, fallback: fallbackArtist)
        // BrowseCard has no semantic album field/destination: a positional subtitle
        // cannot establish either. Radio metadata may complete them after selection.
        let albumName: String? = nil
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
        self.contentRating = card.contentRating
    }
}
