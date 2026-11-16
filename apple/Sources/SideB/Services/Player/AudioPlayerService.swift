import Foundation
import AVFoundation
import Combine

/// Servicio de audio nativo para macOS basado en AVPlayer.
/// Maneja streaming HTTP directo (AAC itag 140/141), buffering, control de tiempo y eventos.
@MainActor
@Observable
public final class AudioPlayerService {
    public static let shared = AudioPlayerService()

    // MARK: - Estado Observable
    public var isPlaying: Bool = false
    public var isBuffering: Bool = false
    public var currentTime: Double = 0.0
    public var duration: Double = 0.0
    public private(set) var seekSnapshot: AudioPlayerSeekSnapshot = .idle
    @ObservationIgnored private(set) var volumeAssignmentRevision = 0
    private var storedVolume: Float = 1.0
    public var volume: Float {
        get { storedVolume }
        set {
            guard newValue.isFinite else { return }
            volumeAssignmentRevision &+= 1
            let effective = min(1, max(0, newValue))
            guard effective != storedVolume else { return }
            if effective == 0 && storedVolume > 0 {
                previousVolume = storedVolume
                preferences.set(previousVolume, forKey: previousVolumeKey)
            }
            storedVolume = effective
            player.volume = outputVolume
            preferences.set(effective, forKey: volumeKey)
        }
    }

    /// Optional exponential volume (Windows FIX-143 / PAR-024): off by default. The slider value,
    /// percentage, mute and maximum are unchanged; only the gain applied to the player changes.
    public var exponentialVolume: Bool {
        get { storedExponentialVolume }
        set {
            guard newValue != storedExponentialVolume else { return }
            storedExponentialVolume = newValue
            preferences.set(newValue, forKey: exponentialVolumeKey)
            player.volume = outputVolume
        }
    }
    private var storedExponentialVolume = false

    /// Automix (beta, PLAN-024): off by default. Stored like the other playback preferences, under the same
    /// prefix (the HomeLab uses its own). The player itself only keeps the flag; the coordinator reacts to it.
    public var automixEnabled: Bool {
        get { storedAutomixEnabled }
        set {
            guard newValue != storedAutomixEnabled else { return }
            storedAutomixEnabled = newValue
            preferences.set(newValue, forKey: automixEnabledKey)
            onAutomixEnabledChanged?(newValue)
        }
    }
    private var storedAutomixEnabled = false
    private var automixEnabledKey: String { "\(preferencePrefix).automixEnabled" }
    @ObservationIgnored public var onAutomixEnabledChanged: ((Bool) -> Void)?
    private var exponentialVolumeKey: String { "\(preferencePrefix).exponentialVolume" }
    private var outputVolume: Float { Self.outputVolume(forSlider: storedVolume, exponential: storedExponentialVolume) }

    /// Extra attenuation of up to 30 dB, as in Windows: gain = 10^(-30 (1 - v) / 20). 0 stays silent
    /// and 1 stays at full scale; linear (unchanged) when `exponential` is false.
    static func outputVolume(forSlider volume: Float, exponential: Bool) -> Float {
        let v = min(1, max(0, volume))
        guard exponential, v > 0 else { return v }
        return v * Float(pow(10.0, -30.0 * Double(1 - v) / 20.0))
    }
    private var previousVolume: Float = 0.75
    private let preferences: UserDefaults
    private let preferencePrefix: String
    private var volumeKey: String { "\(preferencePrefix).volume" }
    private var previousVolumeKey: String { "\(preferencePrefix).previousVolume" }

    public func toggleMute() {
        if volume > 0 {
            previousVolume = volume
            preferences.set(previousVolume, forKey: previousVolumeKey)
            volume = 0.0
        } else {
            volume = previousVolume.isFinite && previousVolume > 0 ? previousVolume : 0.75
        }
    }

    public var onTrackDidEnd: (() -> Void)?
    public var onPlaybackProgress: ((Double, Double) -> Void)?
    /// Reports the accepted item actually entering playback, including a later resume.
    public var onPlaybackStarted: ((UUID) -> Void)?
    public var onPlaybackFailed: ((UUID) -> Void)?
    public var currentUrl: String?
    public var hasReachedEnd: Bool { hasTriggeredTrackEnd }
    /// Automix splice (PLAN-024). `none` outside a transition; see `AudioSpliceStage`.
    private(set) var spliceStage: AudioSpliceStage = .none
    /// The file entered playback (gaplessly at the cut, or late): the UI still shows the previous song.
    @ObservationIgnored public var onSpliceEntered: (() -> Void)?
    /// The file reached its handover second. The receiver must call `completeHandover(playbackID:)` synchronously.
    @ObservationIgnored public var onSpliceHandover: (() -> Void)?
    /// The queued file could not be played and was dropped; the current song goes on.
    @ObservationIgnored public var onSpliceFailed: (() -> Void)?
    private var expectedDuration: Double?

    // MARK: - Privados
    private var player: AVPlayer
    public var avPlayer: AVPlayer { player }
    /// Displayed song seconds = player item seconds − `timeBias`. Zero for a streamed song; while the transition
    /// file plays it maps the file to the song the UI shows (see `AudioSpliceTimeline.bias`).
    @ObservationIgnored private(set) var timeBias: Double = 0
    private struct ActiveSplice {
        var plan: AudioSplice
        var fileItem: AVPlayerItem
        var stage: AudioSpliceStage
        var originalForwardEnd: CMTime
        var handoverFired = false
        /// A song that is itself playing out of a previous transition file keeps its mapping while the next
        /// file is queued behind it (chained A→B→C); disarming gives it back.
        var base: [ActiveSplice] = []
    }
    @ObservationIgnored private var splice: ActiveSplice?
    @ObservationIgnored private var spliceItemObserver: NSKeyValueObservation?
    @ObservationIgnored private var currentItemObserver: NSKeyValueObservation?
    /// The item the end/status observers were installed for. A queue player drops a finished item (and
    /// moves `currentItem`) before the end notification is delivered, so equality with `currentItem` is not enough.
    @ObservationIgnored private weak var observedItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var playbackStatusObserver: NSKeyValueObservation?
    private var loadedPlaybackID: UUID?
    private var reportedPlaybackID: UUID?
    private var itemBufferEmptyObserver: NSKeyValueObservation?
    private var itemBufferKeepUpObserver: NSKeyValueObservation?
    private var itemEndObserver: NSObjectProtocol?
    private var itemStalledObserver: NSObjectProtocol?
    private var hasTriggeredTrackEnd: Bool = false
    @ObservationIgnored private var seekState = AudioPlayerSeekState()
    @ObservationIgnored private var itemGeneration = UUID()
    @ObservationIgnored private var seekExecutor: (AVPlayer, CMTime, @escaping @Sendable (Bool) -> Void) -> Void
    @ObservationIgnored private var measuredTime: (AVPlayer) -> Double
    @ObservationIgnored private var monotonicTime: () -> TimeInterval
    @ObservationIgnored private var waitForSeekDeadline: () async throws -> Void
    @ObservationIgnored private var seekDeadlineTask: Task<Void, Never>?

    func isPlayingItem(playbackID: UUID) -> Bool {
        loadedPlaybackID == playbackID && player.currentItem != nil && player.timeControlStatus == .playing
    }

    public convenience init() {
        self.init(preferences: .standard, preferencePrefix: HomeLabConfiguration.enabled ? "sideb.lab" : "sideb")
    }

    init(preferences: UserDefaults, preferencePrefix: String,
         player: AVPlayer = AVQueuePlayer(),
         seekExecutor: @escaping (AVPlayer, CMTime, @escaping @Sendable (Bool) -> Void) -> Void = { player, time, completion in
             player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: completion)
         },
         measuredTime: @escaping (AVPlayer) -> Double = { $0.currentTime().seconds },
         monotonicTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         waitForSeekDeadline: @escaping () async throws -> Void = {
             try await Task.sleep(for: .seconds(AudioPlayerSeekState.maximumPendingInterval))
         }) {
        self.preferences = preferences
        self.preferencePrefix = preferencePrefix
        self.player = player
        self.seekExecutor = seekExecutor
        self.measuredTime = measuredTime
        self.monotonicTime = monotonicTime
        self.waitForSeekDeadline = waitForSeekDeadline
        self.player.automaticallyWaitsToMinimizeStalling = true
        if let saved = preferences.object(forKey: volumeKey) as? NSNumber {
            let value = saved.floatValue
            if value.isFinite { storedVolume = min(1, max(0, value)) }
        }
        if let saved = preferences.object(forKey: previousVolumeKey) as? NSNumber {
            let value = saved.floatValue
            if value.isFinite && value > 0 { previousVolume = min(1, value) }
        }
        storedExponentialVolume = preferences.bool(forKey: exponentialVolumeKey)
        storedAutomixEnabled = preferences.bool(forKey: automixEnabledKey)
        player.volume = outputVolume
        currentItemObserver = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.currentItemDidChange() }
        }
    }

    deinit {
        // La limpieza de observadores se gestiona activamente en stop()
    }

    // MARK: - Control de Reproducción

    /// Carga una URL de streaming directa (AAC m4a) y comienza la reproducción inmediata.
    /// Si se proporciona `expectedDuration` (o si la URL contiene el parámetro `dur`),
    /// se previene el bug conocido de CoreMedia que duplica la duración (2x) en streams fMP4 con sidx.
    public func play(urlString: String, headers: [String: String] = [:], expectedDuration: Double? = nil, playbackID: UUID = UUID()) {
        guard let url = URL(string: urlString) else {
            print("[AudioPlayerService] URL inválida: \(urlString)")
            onPlaybackFailed?(playbackID)
            return
        }

        clearSplice()
        invalidateSeek(playbackID: playbackID, mediaSeconds: 0)

        self.currentUrl = urlString
        self.isBuffering = true
        self.currentTime = 0.0
        self.hasTriggeredTrackEnd = false

        // Resolver duración esperada: parámetro explícito o parámetro 'dur' en URL de googlevideo
        var resolvedExpected = expectedDuration
        if resolvedExpected == nil || resolvedExpected! <= 0 {
            if let components = URLComponents(string: urlString),
               let durStr = components.queryItems?.first(where: { $0.name == "dur" })?.value,
               let d = Double(durStr), d > 0 {
                resolvedExpected = d
            }
        }
        self.expectedDuration = resolvedExpected
        if let exp = resolvedExpected, exp > 0 {
            self.duration = exp
        } else {
            self.duration = 0.0
        }

        cleanupItemObservers()
        loadedPlaybackID = playbackID
        reportedPlaybackID = nil

        let options: [String: Any] = headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: options)
        let playerItem = AVPlayerItem(asset: asset)

        // Capa 1: Fijar forwardPlaybackEndTime en la duración real para que AVPlayer termine de forma nativa
        if let exp = resolvedExpected, exp > 0 {
            playerItem.forwardPlaybackEndTime = CMTime(seconds: exp, preferredTimescale: 600)
        }

        observePlayerItem(playerItem)

        installItem(playerItem)
        playbackStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self, weak playerItem] _, change in
            guard change.newValue == .playing else { return }
            Task { @MainActor in
                guard let self, let playerItem,
                      self.loadedPlaybackID == playbackID,
                      self.player.currentItem === playerItem else { return }
                self.reportPlaybackStartedIfNeeded()
            }
        }
        setupTimeObserver(for: playerItem, playbackID: playbackID)
        player.play()
        self.isPlaying = true
    }

    public func pause() {
        reportedPlaybackID = nil
        player.pause()
        self.isPlaying = false
    }

    public func resume() {
        player.play()
        self.isPlaying = true
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// Salto a una posición absoluta en segundos.
    @discardableResult
    public func seek(toSeconds seconds: Double) -> Bool {
        guard let item = player.currentItem,
              let target = AudioPlayerSeekBounds.target(seconds: seconds, duration: seekDuration(for: item),
                                                       seekableRanges: validSeekableRanges(for: item)) else { return false }
        // `target` is in displayed song seconds; the player item runs `timeBias` ahead of it.
        let targetTime = CMTime(seconds: target + timeBias, preferredTimescale: 1000)
        guard targetTime.isNumeric else { return false }
        // A superseded request may complete with finished=false later; its ticket can
        // never publish into this request or a replacement item's playback occurrence.
        item.cancelPendingSeeks()
        let ticket = seekState.begin(targetSeconds: target, playbackID: loadedPlaybackID,
                                     itemGeneration: itemGeneration,
                                     mediaSeconds: displayedMediaTime(), now: monotonicTime())
        seekSnapshot = seekState.snapshot
        self.currentTime = target
        if !(duration.isFinite && duration > 0) || target < duration - 1.0 {
            self.hasTriggeredTrackEnd = false
        }

        seekExecutor(player, targetTime) { [weak self, weak item] finished in
            Task { @MainActor in
                guard let self, let item else { return }
                self.finishSeek(ticket, item: item, finished: finished)
            }
        }
        installSeekDeadline(ticket, item: item)
        return true
    }

    /// Salto a una posición normalizada (0.0 ... 1.0).
    @discardableResult
    public func seek(toFraction fraction: Double) -> Bool {
        guard fraction.isFinite, duration.isFinite, duration > 0 else { return false }
        let clamped = max(0.0, min(fraction, 1.0))
        return seek(toSeconds: clamped * duration)
    }

    public func stop() {
        clearSplice()
        invalidateSeek(playbackID: nil, mediaSeconds: 0)
        loadedPlaybackID = nil
        reportedPlaybackID = nil
        cleanupItemObservers()
        cleanupTimeObserver()
        player.pause()
        installItem(nil)
        self.isPlaying = false
        self.isBuffering = false
        self.hasTriggeredTrackEnd = false
        self.currentTime = 0.0
        self.duration = 0.0
        self.currentUrl = nil
        self.expectedDuration = nil
    }

    // MARK: - Observadores y Manejo de Fin de Pista

    /// The status notification can be missed; the existing progress observer also
    /// verifies the accepted item. Reporting once avoids work on every 100 ms tick.
    private func reportPlaybackStartedIfNeeded() {
        guard let playbackID = loadedPlaybackID, reportedPlaybackID != playbackID,
              isPlayingItem(playbackID: playbackID) else { return }
        reportedPlaybackID = playbackID
        onPlaybackStarted?(playbackID)
    }

    private func setupTimeObserver(for item: AVPlayerItem, playbackID: UUID) {
        cleanupTimeObserver()
        let generation = itemGeneration

        // Actualización a 10Hz (cada 0.1s) para animaciones suaves a 120Hz sin sobrecargar el hilo principal
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak item] _ in
            MainActor.assumeIsolated {
                guard let self, let item, self.player.currentItem === item,
                      self.itemGeneration == generation, self.loadedPlaybackID == playbackID else { return }
                self.reportPlaybackStartedIfNeeded()
                // Read the accepted item now, not the callback's possibly queued
                // pre-seek CMTime. No time is synthesized after the seek settles.
                self.samplePlaybackProgress()
            }
        }
    }

    private func cleanupTimeObserver() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    /// The existing observer also checks the request deadline. Callable by deterministic
    /// service tests; it never advances a preview using elapsed wall time.
    func samplePlaybackProgress() {
        let hadPending = seekState.pendingTicket != nil
        let sampled = seekState.sampledPosition(mediaSeconds: displayedMediaTime(), now: monotonicTime())
        if hadPending && seekState.pendingTicket == nil {
            seekDeadlineTask?.cancel()
            seekDeadlineTask = nil
            player.currentItem?.cancelPendingSeeks()
        }
        if seekSnapshot != seekState.snapshot { seekSnapshot = seekState.snapshot }
        guard var seconds = sampled else { return }
        // Until the handover the UI shows the previous song, whose length the file may outrun.
        if spliceStage == .inFile, duration > 0 { seconds = min(seconds, duration) }
        currentTime = seconds
        // This callback feeds listened-history accounting. An unresolved target is
        // UI preview only and must never count as effective playback progress.
        guard seekState.pendingTicket == nil else { return }
        if var active = splice, active.stage == .inFile, !active.handoverFired,
           measuredTime(player) >= active.plan.timeline.handover {
            active.handoverFired = true
            splice = active
            onSpliceHandover?()
            return
        }
        onPlaybackProgress?(seconds, duration)
        if isPlaying && duration > 0 && seconds >= duration - 0.25 && !suppressesSongEndHeuristics {
            handleTrackEnded()
        }
    }

    /// While a transition is queued or its file still shows the previous song, "near the displayed duration"
    /// is not the end of anything: the file's own end (or the handover mapping) decides.
    private var suppressesSongEndHeuristics: Bool { spliceStage == .armed || spliceStage == .inFile }

    private func displayedMediaTime() -> Double { measuredTime(player) - timeBias }

    private func validSeekableRanges(for item: AVPlayerItem) -> [ClosedRange<Double>] {
        item.seekableTimeRanges.compactMap { value in
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = CMTimeRangeGetEnd(range).seconds
            guard start.isFinite, end.isFinite, end > start else { return nil }
            return start...end
        }
    }

    private func seekDuration(for item: AVPlayerItem) -> Double {
        if duration.isFinite && duration > 0 { return duration }
        let itemDuration = item.duration.seconds
        return itemDuration.isFinite && itemDuration > 0 ? itemDuration : 0
    }

    private func invalidateSeek(playbackID: UUID?, mediaSeconds: Double?) {
        itemGeneration = UUID()
        seekDeadlineTask?.cancel()
        seekDeadlineTask = nil
        player.currentItem?.cancelPendingSeeks()
        seekState.reset(playbackID: playbackID, mediaSeconds: mediaSeconds)
        seekSnapshot = seekState.snapshot
    }

    private func finishSeek(_ ticket: AudioPlayerSeekState.Ticket, item: AVPlayerItem,
                            finished: Bool, cancelPending: Bool = false) {
        guard player.currentItem === item, itemGeneration == ticket.itemGeneration,
              loadedPlaybackID == ticket.playbackID,
              seekState.complete(ticket, finished: finished, mediaSeconds: displayedMediaTime()) else { return }
        seekDeadlineTask?.cancel()
        seekDeadlineTask = nil
        if cancelPending { item.cancelPendingSeeks() }
        seekSnapshot = seekState.snapshot
        if let actual = seekSnapshot.mediaSeconds {
            currentTime = actual
            onPlaybackProgress?(actual, duration)
        }
    }

    /// One cancellation deadline per request also resolves a seek while paused or
    /// stalled, when AVPlayer's media-time observer may not emit. It never ticks or
    /// advances playback time, and stale deadlines cannot cancel a newer request.
    private func installSeekDeadline(_ ticket: AudioPlayerSeekState.Ticket, item: AVPlayerItem) {
        seekDeadlineTask?.cancel()
        let wait = waitForSeekDeadline
        seekDeadlineTask = Task { [weak self, weak item] in
            do { try await wait() } catch { return }
            guard !Task.isCancelled, let self, let item else { return }
            self.finishSeek(ticket, item: item, finished: false, cancelPending: true)
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        observedItem = item
        // Observar status
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
            Task { @MainActor in
                guard let self = self else { return }
                // A queue player drops an item that fails to load, so `currentItem` is not a reliable identity here.
                guard playerItem === self.observedItem else { return }
                switch playerItem.status {
                case .readyToPlay:
                    let itemDuration = CMTimeGetSeconds(playerItem.duration)
                    if self.splice != nil {
                        // The transition file: the displayed duration comes from the splice mapping.
                    } else if !itemDuration.isNaN && !itemDuration.isInfinite && itemDuration > 0 {
                        if let expected = self.expectedDuration, expected > 0 {
                            self.duration = expected
                            playerItem.forwardPlaybackEndTime = CMTime(seconds: expected, preferredTimescale: 600)
                        } else {
                            self.duration = itemDuration
                        }
                    }
                    self.isBuffering = false
                case .failed:
                    self.invalidateSeek(playbackID: self.loadedPlaybackID,
                                        mediaSeconds: self.displayedMediaTime())
                    self.isBuffering = false
                    self.isPlaying = false
                    if let id = self.loadedPlaybackID { self.onPlaybackFailed?(id) }
                    print("[AudioPlayerService] Error de reproducción: \(String(describing: playerItem.error))")
                case .unknown:
                    self.isBuffering = true
                @unknown default:
                    break
                }
            }
        }

        // Observar si el buffer se vacía
        itemBufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] playerItem, change in
            Task { @MainActor in
                guard let self = self, playerItem == self.player.currentItem else { return }
                if let isEmpty = change.newValue, isEmpty {
                    self.isBuffering = true
                    // Si el buffer se vacía cuando el tiempo actual está casi al final (<= 1.5s), es el fin de la pista
                    if self.seekState.pendingTicket == nil && self.duration > 0 && self.currentTime >= self.duration - 1.5
                        && !self.suppressesSongEndHeuristics {
                        self.handleTrackEnded()
                    }
                }
            }
        }

        // Observar si el buffer ya puede continuar
        itemBufferKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] playerItem, change in
            Task { @MainActor in
                guard let self = self, playerItem == self.player.currentItem else { return }
                if let keepUp = change.newValue, keepUp {
                    self.isBuffering = false
                }
            }
        }

        // Capa 1: Notificación directa de fin de pista en este playerItem
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // A queue player may already have moved `currentItem` on; the observed item is what ended.
                guard let self = self, item === self.observedItem else { return }
                // A queued transition: the item reached its forward end time at the cut and the file takes over.
                if self.spliceStage == .armed { self.commitSpliceEntered(); return }
                self.handleTrackEnded()
            }
        }

        // Capa 3: Notificación de stream estancado cerca del final
        itemStalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, item == self.player.currentItem else { return }
                if self.seekState.pendingTicket == nil && self.duration > 0 && self.currentTime >= self.duration - 1.5
                    && !self.suppressesSongEndHeuristics {
                    self.handleTrackEnded()
                }
            }
        }
    }

    private func cleanupItemObservers() {
        observedItem = nil
        playbackStatusObserver?.invalidate()
        playbackStatusObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        itemBufferEmptyObserver?.invalidate()
        itemBufferEmptyObserver = nil
        itemBufferKeepUpObserver?.invalidate()
        itemBufferKeepUpObserver = nil
        if let obs = itemEndObserver {
            NotificationCenter.default.removeObserver(obs)
            itemEndObserver = nil
        }
        if let obs = itemStalledObserver {
            NotificationCenter.default.removeObserver(obs)
            itemStalledObserver = nil
        }
    }

    /// Manejador unificado de fin de pista con seguro atómico para evitar llamadas duplicadas
    private func handleTrackEnded() {
        guard seekState.pendingTicket == nil, !hasTriggeredTrackEnd else { return }
        hasTriggeredTrackEnd = true

        print("[AudioPlayerService] 🏁 Fin de pista detectado (currentTime: \(currentTime)s / duration: \(duration)s). Avanzando a la siguiente pista...")
        self.isPlaying = false
        self.onTrackDidEnd?()
    }
}

// MARK: - Automix splice (PLAN-024)

/// The rendered transition as the player needs it: the WAV and where everything sits in it.
struct AudioSplice {
    var asset: AVURLAsset
    var nextVideoID: String
    var timeline: AudioSpliceTimeline
}

enum AudioSpliceArmResult: Equatable {
    /// The file is queued behind the current song; AVFoundation advances gaplessly at the cut.
    case armed
    /// The cut had passed but the file is still the song untouched: the player entered the file.
    case enteredLate
    case tooLate
    case unavailable
}

extension AudioPlayerService {
    /// Replaces whatever is loaded. A queue player keeps its remaining items on `replaceCurrentItem` and
    /// advances on `nil`, so it is emptied explicitly; a plain `AVPlayer` (tests) just replaces.
    fileprivate func installItem(_ item: AVPlayerItem?) {
        if let queue = player as? AVQueuePlayer {
            queue.removeAllItems()
            if let item { queue.insert(item, after: nil) }
        } else {
            player.replaceCurrentItem(with: item)
        }
    }

    fileprivate func clearSplice() {
        if splice != nil { AutomixDiagnostics.shared.record("player", "empalme descartado (\(spliceStage)) por reproducción nueva o stop") }
        spliceItemObserver?.invalidate()
        spliceItemObserver = nil
        splice = nil
        if spliceStage != .none { spliceStage = .none }
        timeBias = 0
    }

    fileprivate func currentItemDidChange() {
        if let active = splice, active.stage == .armed, player.currentItem === active.fileItem {
            commitSpliceEntered()
        }
    }

    /// Queues the transition file behind the current song and ends the song at `cut` (gapless), or, when the
    /// cut is just behind and the file is still the song itself, enters the file at the current position.
    @discardableResult
    func armSplice(_ plan: AudioSplice) -> AudioSpliceArmResult {
        guard splice == nil || splice?.stage == .handedOver, let queue = player as? AVQueuePlayer,
              let item = queue.currentItem, observedItem === item, loadedPlaybackID != nil,
              !hasTriggeredTrackEnd else {
            AutomixDiagnostics.shared.record("player", "armar imposible: sin elemento observado, empalme previo o fin ya disparado")
            return .unavailable
        }
        let position = displayedMediaTime()
        let decision = plan.timeline.armDecision(position: position)
        if decision == .giveUp {
            AutomixDiagnostics.shared.record("player", "armar rechazado: la canción (\(Self.fmt(position)) s) ya pasó el solape del archivo")
            return .tooLate
        }

        let fileItem = AVPlayerItem(asset: plan.asset)
        let originalEnd = item.forwardPlaybackEndTime
        AutomixDiagnostics.shared.record("player", "armar: canción en \(Self.fmt(position)) s, corte en \(Self.fmt(plan.timeline.cut)) s, decisión \(decision), "
            + "sesgo \(Self.fmt(timeBias)), tiempo crudo \(Self.fmt(measuredTime(player))) s")
        splice = ActiveSplice(plan: plan, fileItem: fileItem, stage: .armed, originalForwardEnd: originalEnd,
                              base: splice.map { [$0] } ?? [])
        spliceStage = .armed
        spliceItemObserver = fileItem.observe(\.status, options: [.new]) { [weak self] observed, _ in
            guard observed.status == .failed else { return }
            Task { @MainActor in self?.fileItemFailed(observed) }
        }
        // Sample-exact end of the current song: its item seconds are the cut plus the mapping in force.
        let endSeconds = plan.timeline.cut + timeBias
        item.forwardPlaybackEndTime = CMTime(value: Int64((endSeconds * 44_100).rounded()), timescale: 44_100)
        queue.insert(fileItem, after: item)

        if case .lateEntry = decision {
            // The file is identical to the song from the cut on: step into it and resume where we were.
            queue.advanceToNextItem()
            commitSpliceEntered()
            seek(toSeconds: position + 0.15)
            AutomixDiagnostics.shared.record("player", "entrada tardía: salta al archivo y busca la canción \(Self.fmt(position + 0.15)) s")
            return .enteredLate
        }
        AutomixDiagnostics.shared.record("player", "empalme armado: fin del elemento en \(Self.fmt(endSeconds)) s (tiempo del elemento), archivo en cola")
        return .armed
    }

    /// Takes the queued file out and gives the current song back its own end. Harmless when nothing is queued
    /// or the file already plays (it cannot be un-heard; the handover completes normally).
    func disarmSplice() {
        guard let active = splice, active.stage == .armed else { return }
        spliceItemObserver?.invalidate()
        spliceItemObserver = nil
        (player as? AVQueuePlayer)?.remove(active.fileItem)
        observedItem?.forwardPlaybackEndTime = active.originalForwardEnd
        AutomixDiagnostics.shared.record("player", "empalme desarmado: archivo fuera de la cola, fin de la canción restituido")
        splice = active.base.first
        spliceStage = splice?.stage ?? .none
    }

    /// The video id of the song the file hands over to; nil when no file is queued or playing.
    var spliceNextVideoID: String? { splice?.plan.nextVideoID }

    /// Where a seek to `seconds` (displayed song seconds) must go given the current splice.
    func seekRoute(forSeconds seconds: Double) -> AudioSeekRoute {
        guard let active = splice else { return .direct }
        return active.plan.timeline.route(forSeek: seconds, stage: active.stage)
    }

    /// Steps into the queued file now and seeks it to the displayed song second `seconds`.
    @discardableResult
    func seekIntoSplice(toSeconds seconds: Double) -> Bool {
        guard let active = splice, active.stage == .armed, let queue = player as? AVQueuePlayer else { return false }
        queue.advanceToNextItem()
        commitSpliceEntered()
        return seek(toSeconds: seconds)
    }

    /// The UI now shows the next song: from here the file reads as that song, from its own second 0 mapping.
    func completeHandover(playbackID: UUID) {
        guard var active = splice, active.stage == .inFile else { return }
        active.stage = .handedOver
        splice = active
        spliceStage = .handedOver
        timeBias = active.plan.timeline.bias(for: .handedOver)
        AutomixDiagnostics.shared.record("player", "traspaso: sesgo \(Self.fmt(timeBias)), duración mostrada \(Self.fmt(active.plan.timeline.nextDuration)) s")
        duration = active.plan.timeline.nextDuration
        expectedDuration = nil
        loadedPlaybackID = playbackID
        reportedPlaybackID = playbackID
        hasTriggeredTrackEnd = false
        invalidateSeek(playbackID: playbackID, mediaSeconds: displayedMediaTime())
        setupTimeObserver(for: active.fileItem, playbackID: playbackID)
        currentTime = max(0, displayedMediaTime())
    }

    fileprivate func commitSpliceEntered() {
        guard var active = splice, active.stage == .armed else { return }
        active.stage = .inFile
        active.base = []
        splice = active
        spliceStage = .inFile
        spliceItemObserver?.invalidate()
        spliceItemObserver = nil
        timeBias = active.plan.timeline.bias(for: .inFile)
        AutomixDiagnostics.shared.record("player", "el archivo entró en reproducción: sesgo \(Self.fmt(timeBias)), tiempo crudo \(Self.fmt(measuredTime(player))) s")
        invalidateSeek(playbackID: loadedPlaybackID, mediaSeconds: displayedMediaTime())
        cleanupItemObservers()
        observePlayerItem(active.fileItem)
        if let id = loadedPlaybackID { setupTimeObserver(for: active.fileItem, playbackID: id) }
        hasTriggeredTrackEnd = false
        isBuffering = false
        onSpliceEntered?()
    }

    private func fileItemFailed(_ item: AVPlayerItem) {
        guard let active = splice, active.stage == .armed, active.fileItem === item else { return }
        AutomixDiagnostics.shared.record("player", "el archivo en cola falló al cargar")
        disarmSplice()
        onSpliceFailed?()
    }
}

// MARK: - Diagnóstico (PLAN-024)

extension AudioPlayerService {
    fileprivate static func fmt(_ value: Double) -> String { value.isFinite ? String(format: "%.3f", value) : "—" }

    /// Línea de tiempo del archivo vigente (armado, sonando o ya traspasado); nil sin transición.
    var spliceTimeline: AudioSpliceTimeline? { splice?.plan.timeline }

    /// Estado del reproductor para la ventana de diagnóstico. Sólo lectura: no cambia nada.
    func diagnosticsSnapshot() -> AutomixPlayerSnapshot {
        let queueItems = (player as? AVQueuePlayer)?.items() ?? (player.currentItem.map { [$0] } ?? [])
        let current = player.currentItem
        let descriptions = queueItems.enumerated().map { index, item -> String in
            let kind: String
            if let url = (item.asset as? AVURLAsset)?.url { kind = url.isFileURL ? url.lastPathComponent : "stream" } else { kind = "?" }
            let status: String
            switch item.status {
            case .readyToPlay: status = "listo"
            case .failed: status = "falló"
            default: status = "sin cargar"
            }
            let end = item.forwardPlaybackEndTime
            let endText = end.isValid && end.isNumeric ? ", fin \(Self.fmt(end.seconds)) s" : ""
            return "[\(index)]\(item === current ? " ● actual" : "") \(kind) · \(status)\(endText)"
        }
        let end = current?.forwardPlaybackEndTime
        return AutomixPlayerSnapshot(
            stage: spliceStage, items: descriptions,
            currentIndex: current.flatMap { item in queueItems.firstIndex { $0 === item } },
            rawItemSeconds: measuredTime(player), timeBias: timeBias, displayedSeconds: currentTime,
            forwardEndSeconds: end.flatMap { $0.isValid && $0.isNumeric ? $0.seconds : nil },
            isPlaying: isPlaying, isBuffering: isBuffering,
            timeControlStatus: {
                switch player.timeControlStatus {
                case .paused: "paused"
                case .waitingToPlayAtSpecifiedRate: "waitingToPlayAtSpecifiedRate"
                case .playing: "playing"
                @unknown default: "?"
                }
            }(),
            waitingReason: player.reasonForWaitingToPlay?.rawValue)
    }
}
