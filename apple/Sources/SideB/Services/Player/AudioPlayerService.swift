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
    /// Se incrementa cada vez que el reproductor activo cambia de objeto (empalme de Automix con un segundo
    /// `AVPlayer`): quien lea `avPlayer` desde una vista de SwiftUI se vuelve a evaluar.
    private(set) var playerEpoch = 0
    public var avPlayer: AVPlayer { _ = playerEpoch; return player }
    /// Displayed song seconds = player item seconds − `timeBias`. Zero for a streamed song; while the transition
    /// file plays it maps the file to the song the UI shows (see `AudioSpliceTimeline.bias`).
    @ObservationIgnored private(set) var timeBias: Double = 0
    private struct ActiveSplice {
        var plan: AudioSplice
        /// El segundo `AVPlayer` con el archivo de la transición.
        var switcher: AudioSpliceSwitcher
        var stage: AudioSpliceStage
        var handoverFired = false
        /// A song that is itself playing out of a previous transition file keeps its mapping while the next
        /// file is prepared behind it (chained A→B→C); disarming gives it back.
        var base: [ActiveSplice] = []
    }
    @ObservationIgnored private var splice: ActiveSplice?
    @ObservationIgnored private var spliceItemObserver: NSKeyValueObservation?
    /// Hay una confirmación del empalme en curso (preparando o programando el arranque).
    @ObservationIgnored private var isCommitting = false
    /// El segundo `AVPlayer` de Side B, reciclado entre empalmes: junto con el principal son los dos únicos que existen.
    @ObservationIgnored private var sparePlayer: CountedPlayer?
    /// Gancho de pruebas: no precarga el archivo en el segundo reproductor (las pruebas de la máquina de estados no
    /// dependen de que el sistema arranque audio). Nunca se activa en la app.
    @ObservationIgnored var skipsSplicePrerollForTesting = false
    /// The item the end/status observers were installed for.
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
    /// Dispositivo de salida predeterminado (se sustituye en las pruebas).
    @ObservationIgnored private var outputDevice: () -> AudioOutputDevice?
    /// ¿Está el reproductor reproduciendo de verdad? (se sustituye en las pruebas).
    @ObservationIgnored private var isRendering: (AVPlayer) -> Bool
    @ObservationIgnored private var loggedUnrenderedEnd = false
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
         player: AVPlayer = CountedPlayer(),
         outputDevice: @escaping () -> AudioOutputDevice? = { AudioOutputDevice.current() },
         isRendering: @escaping (AVPlayer) -> Bool = { $0.timeControlStatus == .playing },
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
        self.outputDevice = outputDevice
        self.isRendering = isRendering
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
        loggedUnrenderedEnd = false
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

        player.replaceCurrentItem(with: playerItem)
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
        abortCommittedSwitch(reason: "pausa")
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
        abortCommittedSwitch(reason: "salto")
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
        player.replaceCurrentItem(with: nil)
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
        driveSplice()
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
            // Un tiempo que llega al final sin que el reproductor esté reproduciendo de verdad (salida de audio caída,
            // reloj falso) no es un fin de pista: se anota y se ignora.
            if isRendering(player) {
                handleTrackEnded(cause: "el tiempo llegó al final de la duración (\(Self.fmt(seconds)) ≥ \(Self.fmt(duration - 0.25)) s)")
            } else if !loggedUnrenderedEnd {
                loggedUnrenderedEnd = true
                AutomixDiagnostics.shared.record("player", "fin de pista IGNORADO: el tiempo (\(Self.fmt(seconds)) s) alcanzó la duración (\(Self.fmt(duration)) s) pero el reproductor no está reproduciendo (\(Self.describe(player.timeControlStatus)), tasa \(player.rate))")
            }
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
                        self.handleTrackEnded(cause: "búfer vacío cerca del final (\(Self.fmt(self.currentTime)) de \(Self.fmt(self.duration)) s)")
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
                self.handleTrackEnded(cause: "AVPlayerItemDidPlayToEndTime del elemento observado")
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
                    self.handleTrackEnded(cause: "reproducción estancada cerca del final (\(Self.fmt(self.currentTime)) de \(Self.fmt(self.duration)) s)")
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
    private func handleTrackEnded(cause: String) {
        guard seekState.pendingTicket == nil, !hasTriggeredTrackEnd else { return }
        hasTriggeredTrackEnd = true
        // La causa queda en el diagnóstico persistente: es lo que explica un avance automático de pistas.
        AutomixDiagnostics.shared.record("player", "FIN DE PISTA: \(cause); mostrado \(Self.fmt(currentTime)) s / duración \(Self.fmt(duration)) s, "
            + "crudo \(Self.fmt(measuredTime(player))) s, sesgo \(Self.fmt(timeBias)), empalme \(spliceStage), \(Self.describe(player.timeControlStatus)), "
            + "tasa \(player.rate), isPlaying \(isPlaying)")

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
    /// The file is loading in a second player; the switch happens by itself at the cut (or right away if late).
    case armed
    case tooLate
    case unavailable
}

extension AudioPlayerService {
    fileprivate static func fmt(_ value: Double) -> String { value.isFinite ? String(format: "%.3f", value) : "—" }

    fileprivate static func describe(_ status: AVPlayer.TimeControlStatus) -> String {
        switch status {
        case .paused: "pausado"
        case .waitingToPlayAtSpecifiedRate: "esperando"
        case .playing: "reproduciendo"
        @unknown default: "?"
        }
    }

    fileprivate func clearSplice() {
        if let active = splice {
            AutomixDiagnostics.shared.record("player", "empalme descartado (\(spliceStage)) por reproducción nueva o stop")
            retire(active.switcher)
            for base in active.base where base.switcher.player !== player { retire(base.switcher) }
        }
        spliceItemObserver?.invalidate()
        spliceItemObserver = nil
        splice = nil
        isCommitting = false
        if spliceStage != .none { spliceStage = .none }
        timeBias = 0
    }

    /// Carga el archivo en un segundo reproductor y lo precarga bien antes del corte. No toca el elemento que suena:
    /// ni su `forwardPlaybackEndTime`, ni una cola. El cambio lo hace `driveSplice` al acercarse el corte.
    @discardableResult
    func armSplice(_ plan: AudioSplice) -> AudioSpliceArmResult {
        guard splice == nil || splice?.stage == .handedOver, let item = player.currentItem,
              observedItem === item, loadedPlaybackID != nil, !hasTriggeredTrackEnd else {
            AutomixDiagnostics.shared.record("player", "armar imposible: sin elemento observado, empalme previo o fin ya disparado")
            return .unavailable
        }
        let position = displayedMediaTime()
        if plan.timeline.commitDecision(position: position) == .giveUp {
            AutomixDiagnostics.shared.record("player", "armar rechazado: la canción (\(Self.fmt(position)) s) ya pasó el solape del archivo")
            return .tooLate
        }
        let switcher = AudioSpliceSwitcher(asset: plan.asset, player: takeSparePlayer())
        splice = ActiveSplice(plan: plan, switcher: switcher, stage: .armed, base: splice.map { [$0] } ?? [])
        spliceStage = .armed
        observeSpliceItem(switcher)
        startPreroll(switcher, fileSeconds: 0)
        AutomixDiagnostics.shared.record("player", "armar: canción en \(Self.fmt(position)) s, corte en \(Self.fmt(plan.timeline.cut)) s; "
            + "segundo reproductor cargando el archivo, sesgo \(Self.fmt(timeBias)); el elemento que suena no se toca")
        return .armed
    }

    /// Cambia el archivo armado por otro de la misma pareja y el mismo corte (stems en lugar de la versión rápida)
    /// mientras el empalme no se haya comprometido (arranque programado).
    func replaceSplice(_ plan: AudioSplice) -> AudioSpliceArmResult {
        // El plan de stems puede tener otro corte y otro solape que la rápida: se vuelve a planear la línea de tiempo.
        // Sólo se rechaza si el empalme ya se comprometió o si a esta altura ya no cabe el fundido en el archivo nuevo.
        guard var active = splice, active.stage == .armed, !active.switcher.isCommitted, !isCommitting,
              plan.timeline.commitDecision(position: displayedMediaTime()) != .giveUp else {
            AutomixDiagnostics.shared.record("player", "sustitución rechazada: el empalme ya se comprometió, no hay empalme armado o el corte nuevo ya no cabe")
            return .unavailable
        }
        // El mismo reproductor, otro archivo: nunca hay un tercer AVPlayer vivo.
        let switcher = active.switcher
        switcher.reload(asset: plan.asset)
        active.plan = plan
        splice = active
        observeSpliceItem(switcher)
        startPreroll(switcher, fileSeconds: 0)
        AutomixDiagnostics.shared.record("player", "archivo sustituido antes de comprometer el empalme: corte \(Self.fmt(plan.timeline.cut)) s, solape \(Self.fmt(plan.timeline.overlapStart))–\(Self.fmt(plan.timeline.overlapEnd)) s")
        return .armed
    }

    private func observeSpliceItem(_ switcher: AudioSpliceSwitcher) {
        spliceItemObserver?.invalidate()
        spliceItemObserver = switcher.item.observe(\.status, options: [.new]) { [weak self, weak switcher] observed, _ in
            guard observed.status == .failed else { return }
            Task { @MainActor in
                guard let self, let switcher, self.splice?.switcher === switcher else { return }
                AutomixDiagnostics.shared.record("player", "el archivo del segundo reproductor falló al cargar")
                self.disarmSplice()
                self.onSpliceFailed?()
            }
        }
    }

    private func startPreroll(_ switcher: AudioSpliceSwitcher, fileSeconds: Double) {
        guard !skipsSplicePrerollForTesting else { return }
        Task { @MainActor [weak self, weak switcher] in
            guard let switcher else { return }
            let result = await switcher.prepare(fileSeconds: fileSeconds)
            guard let self, self.splice?.switcher === switcher else { return }
            switch result {
            case .ready:
                AutomixDiagnostics.shared.record("player", "precarga lista en el segundo \(Self.fmt(fileSeconds)) del archivo (\(String(format: "%.0f", switcher.diagnostics.prerollMilliseconds ?? 0)) ms)")
            case .failed:
                AutomixDiagnostics.shared.record("player", "la precarga del archivo falló")
                self.disarmSplice()
                self.onSpliceFailed?()
            case .superseded:
                break
            }
        }
    }

    /// Lo llama el reloj de 10 Hz: con el empalme armado decide cuándo programar el arranque del archivo.
    fileprivate func driveSplice() {
        guard let active = splice, active.stage == .armed else { return }
        let switcher = active.switcher
        if switcher.isCommitted {
            // Ya hay un arranque programado: si la canción deja de sonar con normalidad, se deshace.
            if player.timeControlStatus != .playing || seekState.pendingTicket != nil, switcher.phase != .done {
                abortCommittedSwitch(reason: "la canción dejó de sonar con normalidad (\(player.timeControlStatus.rawValue))")
            }
            return
        }
        guard !isCommitting, player.timeControlStatus == .playing, seekState.pendingTicket == nil else { return }
        if switcher.phase == .aborted || switcher.phase == .idle {
            startPreroll(switcher, fileSeconds: 0)
            return
        }
        guard switcher.phase == .prerolled else { return }
        let position = displayedMediaTime()
        switch active.plan.timeline.commitDecision(position: position) {
        case .wait: return
        case .giveUp:
            AutomixDiagnostics.shared.record("player", "empalme abandonado: la canción (\(Self.fmt(position)) s) ya no deja sitio al fundido dentro de la parte idéntica")
            disarmSplice()
            onSpliceFailed?()
        case .commit(let fileSeconds):
            commitSplice(fileSeconds: fileSeconds)
        }
    }

    /// Alinea el arranque del archivo con la posición de la canción y programa el fundido de 50 ms.
    private func commitSplice(fileSeconds first: Double) {
        guard !isCommitting, let active = splice, active.stage == .armed else { return }
        isCommitting = true
        let switcher = active.switcher
        let timeline = active.plan.timeline
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isCommitting = false }
            var file = first
            // Con el arranque simple el archivo arranca mudo `plainLeadIn` antes del punto de empalme: éste no puede caer
            // antes de ese margen dentro del archivo (el solape idéntico a la canción lo permite).
            let wantsPlain = AudioSpliceStartMode.choose(device: self.outputDevice(), forcePlain: switcher.forcePlain) == .plain
            if wantsPlain { file = max(file, AudioSpliceTimeline.plainLeadIn) }
            for attempt in 1...3 {
                guard timeline.fits(fileSeconds: file) else { break }
                let preparedAt = wantsPlain ? file - AudioSpliceTimeline.plainLeadIn : file
                if switcher.prerolledFileSeconds != preparedAt {
                    switch await switcher.prepare(fileSeconds: preparedAt) {
                    case .ready: break
                    case .superseded: return
                    case .failed:
                        AutomixDiagnostics.shared.record("player", "la precarga en el segundo \(Self.fmt(file)) falló")
                        self.disarmSplice(); self.onSpliceFailed?()
                        return
                    }
                }
                guard self.splice?.switcher === switcher, self.splice?.stage == .armed,
                      self.player.timeControlStatus == .playing, let oldItem = self.player.currentItem,
                      let timebase = oldItem.timebase else { return }
                // Segundo de la canción en que ocurre el empalme y hora de host a la que el elemento viejo llega a él.
                let song = timeline.cut + file
                let itemTime = CMTime(seconds: song + self.timeBias, preferredTimescale: 44_100)
                let host = CMSyncConvertTime(itemTime, from: timebase, to: CMClockGetHostTimeClock())
                let device = self.outputDevice()
                let mode = AudioSpliceStartMode.choose(device: device, forcePlain: switcher.forcePlain)
                if switcher.commit(fileSeconds: file, prerolledAt: mode == .plain ? file - AudioSpliceTimeline.plainLeadIn : file,
                                   hostTime: host, old: self.player, output: self.outputVolume, mode: mode, device: device,
                                   onFinished: { [weak self] advancing in self?.completeSwitch(advancing: advancing) }) {
                    AutomixDiagnostics.shared.record("player", "empalme comprometido: archivo en \(Self.fmt(file)) s ↔ canción en \(Self.fmt(song)) s; "
                        + "arranca en \(String(format: "%.0f", (switcher.diagnostics.scheduledLeadSeconds ?? 0) * 1000)) ms (intento \(attempt)); "
                        + "arranque \(mode == .hostSynced ? "sincronizado" : "con play()"); salida \(device?.summary ?? "desconocida"); "
                        + "AVPlayers vivos \(AutomixPlayerCounter.snapshot.alive)")
                    return
                }
                // Demasiado cerca para programarlo: se empalma un poco más adelante.
                file += 0.35
                guard timeline.fits(fileSeconds: file) else { break }
            }
            AutomixDiagnostics.shared.record("player", "no se pudo programar el arranque del archivo a tiempo")
            self.disarmSplice(); self.onSpliceFailed?()
        }
    }

    /// Deshace un arranque programado o un fundido en curso (pausa, salto, parada de la canción).
    fileprivate func abortCommittedSwitch(reason: String) {
        guard let active = splice, active.stage == .armed, active.switcher.isCommitted, active.switcher.phase != .done else { return }
        active.switcher.abort(restoring: player, output: outputVolume)
        AutomixDiagnostics.shared.record("player", "arranque programado deshecho (\(reason)); se vuelve a precargar")
    }

    /// Fin del fundido: el reproductor del archivo pasa a ser el del servicio y el viejo se retira.
    fileprivate func completeSwitch(immediate: Bool = false, advancing: Bool = true) {
        guard var active = splice, active.stage == .armed else { return }
        let switcher = active.switcher
        if !immediate, !advancing {
            // El archivo no estaba avanzando al terminar el fundido: la canción está callada. Se devuelve el volumen y se
            // repite el empalme con `play()` (si ya fue con `play()`, se renuncia al empalme y la canción sigue).
            switcher.abort(restoring: player, output: outputVolume)
            if switcher.lastMode == .hostSynced {
                switcher.fallBackToPlain()
                AutomixDiagnostics.shared.record("player", "el arranque sincronizado no avanzó (el archivo seguía en su sitio): se devuelve el volumen a la canción y se repite con play(); salida \(outputDevice()?.summary ?? "desconocida")")
            } else {
                AutomixDiagnostics.shared.record("player", "el archivo no avanzó ni con play(): se renuncia al empalme y la canción sigue; salida \(outputDevice()?.summary ?? "desconocida")")
                disarmSplice()
                onSpliceFailed?()
            }
            return
        }
        // Medida real de la alineación (diagnóstico): canción menos (aCut + archivo), en milisegundos.
        let oldSeconds = player.currentTime().seconds
        let fileSeconds = switcher.player.currentTime().seconds
        if !immediate, oldSeconds.isFinite, fileSeconds.isFinite {
            let offset = ((oldSeconds - timeBias) - (active.plan.timeline.cut + fileSeconds)) * 1000
            switcher.recordMeasuredOffset(milliseconds: offset)
            AutomixDiagnostics.shared.record("player", "fin del fundido: desfase medido entre reproductores \(String(format: "%.1f", offset)) ms")
        }
        // El nuevo debe estar sonando; si no, se arranca (red de seguridad).
        if switcher.player.rate == 0 && isPlaying && !skipsSplicePrerollForTesting { switcher.player.play() }
        // Retira el reproductor viejo con todos sus observadores.
        cleanupTimeObserver()
        cleanupItemObservers()
        let old = player
        old.pause()
        old.replaceCurrentItem(with: nil)
        player = switcher.player
        recycle(old) // el viejo queda de repuesto para el próximo empalme
        player.volume = outputVolume
        player.automaticallyWaitsToMinimizeStalling = true
        playerEpoch &+= 1

        active.stage = .inFile
        active.base = []
        splice = active
        spliceStage = .inFile
        spliceItemObserver?.invalidate()
        spliceItemObserver = nil
        timeBias = active.plan.timeline.bias(for: .inFile)
        AutomixDiagnostics.shared.record("player", "el archivo es ahora el reproductor activo: sesgo \(Self.fmt(timeBias)), tiempo crudo \(Self.fmt(measuredTime(player))) s")
        invalidateSeek(playbackID: loadedPlaybackID, mediaSeconds: displayedMediaTime())
        observePlayerItem(switcher.item)
        if let id = loadedPlaybackID { setupTimeObserver(for: switcher.item, playbackID: id) }
        hasTriggeredTrackEnd = false
        isBuffering = false
        onSpliceEntered?()
    }

    /// El reproductor de repuesto (el reciclado o uno nuevo).
    fileprivate func takeSparePlayer() -> CountedPlayer {
        if let spare = sparePlayer { sparePlayer = nil; return spare }
        return CountedPlayer()
    }

    /// Guarda un reproductor ya vacío como repuesto; si ya hay uno, se suelta (nunca más de dos vivos).
    fileprivate func recycle(_ candidate: AVPlayer) {
        guard let counted = candidate as? CountedPlayer, counted !== player, sparePlayer == nil else { return }
        counted.pause()
        counted.replaceCurrentItem(with: nil)
        counted.volume = 0
        counted.automaticallyWaitsToMinimizeStalling = false
        sparePlayer = counted
    }

    /// Descarta un empalme: suelta su elemento y recicla su reproductor.
    fileprivate func retire(_ switcher: AudioSpliceSwitcher) {
        switcher.dispose()
        recycle(switcher.player)
    }

    /// Takes the second player out and gives the current song back its volume. Harmless when nothing is armed
    /// or the file already plays (it cannot be un-heard; the handover completes normally).
    func disarmSplice() {
        guard let active = splice, active.stage == .armed else { return }
        spliceItemObserver?.invalidate()
        spliceItemObserver = nil
        isCommitting = false
        if active.switcher.isCommitted { active.switcher.abort(restoring: player, output: outputVolume) }
        retire(active.switcher)
        player.volume = outputVolume
        AutomixDiagnostics.shared.record("player", "empalme desarmado: segundo reproductor descartado, la canción sigue tal cual")
        splice = active.base.first
        spliceStage = splice?.stage ?? .none
    }

    /// The video id of the song the file hands over to; nil when no file is prepared or playing.
    var spliceNextVideoID: String? { splice?.plan.nextVideoID }

    /// Where a seek to `seconds` (displayed song seconds) must go given the current splice.
    func seekRoute(forSeconds seconds: Double) -> AudioSeekRoute {
        guard let active = splice else { return .direct }
        return active.plan.timeline.route(forSeek: seconds, stage: active.stage)
    }

    /// Enters the prepared file now at the displayed song second `seconds` (a seek, not a gapless switch).
    @discardableResult
    func seekIntoSplice(toSeconds seconds: Double) -> Bool {
        guard let active = splice, active.stage == .armed else { return false }
        let switcher = active.switcher
        let file = seconds - active.plan.timeline.cut
        guard file >= 0 else { return false }
        abortCommittedSwitch(reason: "salto dentro del archivo")
        isCommitting = true
        currentTime = seconds
        AutomixDiagnostics.shared.record("player", "salto dentro del archivo: canción \(Self.fmt(seconds)) s → archivo \(Self.fmt(file)) s (entrada inmediata)")
        if skipsSplicePrerollForTesting {
            switcher.markPrerolledForTesting(fileSeconds: file)
            isCommitting = false
            completeSwitch(immediate: true)
            return true
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isCommitting = false }
            guard await switcher.prepare(fileSeconds: file) == .ready, self.splice?.switcher === switcher, self.splice?.stage == .armed else { return }
            switcher.player.volume = self.outputVolume
            if self.isPlaying { switcher.player.play() }
            self.completeSwitch(immediate: true)
        }
        return true
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
        setupTimeObserver(for: active.switcher.item, playbackID: playbackID)
        currentTime = max(0, displayedMediaTime())
    }

    /// Gancho de pruebas: da por terminado el fundido y retira el reproductor viejo sin esperar al reloj de host.
    func completeSwitchForTesting() { completeSwitch(immediate: true) }

    /// True while a switch can still be replaced by another file of the same cut (nothing scheduled yet).
    var canReplaceSplice: Bool {
        guard let active = splice, active.stage == .armed else { return false }
        return !active.switcher.isCommitted && !isCommitting
    }

    /// Estado del segundo reproductor para el diagnóstico.
    var spliceDiagnostics: AutomixSpliceDiagnostics? { splice?.switcher.diagnostics }
}

// MARK: - Diagnóstico (PLAN-024)

extension AudioPlayerService {
    /// Segundos de la canción mostrada medidos ahora mismo sobre el reproductor activo (para el diagnóstico y las pruebas).
    var displayedPlaybackSeconds: Double { displayedMediaTime() }

    /// Línea de tiempo del archivo vigente (armado, sonando o ya traspasado); nil sin transición.
    var spliceTimeline: AudioSpliceTimeline? { splice?.plan.timeline }

    /// Estado del reproductor para la ventana de diagnóstico. Sólo lectura: no cambia nada.
    func diagnosticsSnapshot() -> AutomixPlayerSnapshot {
        let current = player.currentItem
        let queueItems = current.map { [$0] } ?? []
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
