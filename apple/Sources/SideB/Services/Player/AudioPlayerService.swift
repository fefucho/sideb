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
            player.volume = effective
            preferences.set(effective, forKey: volumeKey)
        }
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
    private var expectedDuration: Double?

    // MARK: - Privados
    private var player: AVPlayer
    public var avPlayer: AVPlayer { player }
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

    func isPlayingItem(playbackID: UUID) -> Bool {
        loadedPlaybackID == playbackID && player.currentItem != nil && player.timeControlStatus == .playing
    }

    public convenience init() {
        self.init(preferences: .standard, preferencePrefix: HomeLabConfiguration.enabled ? "sideb.lab" : "sideb")
    }

    init(preferences: UserDefaults, preferencePrefix: String) {
        self.preferences = preferences
        self.preferencePrefix = preferencePrefix
        self.player = AVPlayer()
        self.player.automaticallyWaitsToMinimizeStalling = true
        if let saved = preferences.object(forKey: volumeKey) as? NSNumber {
            let value = saved.floatValue
            if value.isFinite { storedVolume = min(1, max(0, value)) }
        }
        if let saved = preferences.object(forKey: previousVolumeKey) as? NSNumber {
            let value = saved.floatValue
            if value.isFinite && value > 0 { previousVolume = min(1, value) }
        }
        player.volume = volume
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
        setupTimeObserver()
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
    public func seek(toSeconds seconds: Double) {
        guard duration > 0 else { return }
        let target = max(0, min(seconds, duration))
        let targetTime = CMTime(seconds: target, preferredTimescale: 600)
        self.currentTime = target
        if target < duration - 1.0 {
            self.hasTriggeredTrackEnd = false
        }

        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = target
            }
        }
    }

    /// Salto a una posición normalizada (0.0 ... 1.0).
    public func seek(toFraction fraction: Double) {
        let clamped = max(0.0, min(fraction, 1.0))
        seek(toSeconds: clamped * duration)
    }

    public func stop() {
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

    private func setupTimeObserver() {
        cleanupTimeObserver()

        // Actualización a 10Hz (cada 0.1s) para animaciones suaves a 120Hz sin sobrecargar el hilo principal
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.reportPlaybackStartedIfNeeded()
                let secs = CMTimeGetSeconds(time)
                if !secs.isNaN && !secs.isInfinite {
                    self.currentTime = secs
                    self.onPlaybackProgress?(secs, self.duration)

                    // Capa 2: Centinela de fin de pista en tiempo real (si está a <= 0.25s del final esperado)
                    if self.isPlaying && self.duration > 0 && secs >= self.duration - 0.25 {
                        self.handleTrackEnded()
                    }
                }
            }
        }
    }

    private func cleanupTimeObserver() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        // Observar status
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard playerItem == self.player.currentItem else { return }
                switch playerItem.status {
                case .readyToPlay:
                    let itemDuration = CMTimeGetSeconds(playerItem.duration)
                    if !itemDuration.isNaN && !itemDuration.isInfinite && itemDuration > 0 {
                        if let expected = self.expectedDuration, expected > 0 {
                            self.duration = expected
                            playerItem.forwardPlaybackEndTime = CMTime(seconds: expected, preferredTimescale: 600)
                        } else {
                            self.duration = itemDuration
                        }
                    }
                    self.isBuffering = false
                case .failed:
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
                    if self.duration > 0 && self.currentTime >= self.duration - 1.5 {
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
                guard let self = self, item == self.player.currentItem else { return }
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
                if self.duration > 0 && self.currentTime >= self.duration - 1.5 {
                    self.handleTrackEnded()
                }
            }
        }
    }

    private func cleanupItemObservers() {
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
        guard !hasTriggeredTrackEnd else { return }
        hasTriggeredTrackEnd = true

        print("[AudioPlayerService] 🏁 Fin de pista detectado (currentTime: \(currentTime)s / duration: \(duration)s). Avanzando a la siguiente pista...")
        self.isPlaying = false
        self.onTrackDidEnd?()
    }
}
