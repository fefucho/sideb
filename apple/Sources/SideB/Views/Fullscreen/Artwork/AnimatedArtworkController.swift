import AppKit
import AVFoundation
import SideBCore

struct AnimatedArtworkIdentity: Equatable {
    let sessionID: UUID
    let albumKey: String

    init(track: SongItemRecord, sessionID: UUID) {
        self.sessionID = sessionID
        let normalize: (String) -> String = {
            $0.precomposedStringWithCanonicalMapping.lowercased()
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        if let id = track.albumId, !id.isEmpty {
            albumKey = "album:\(id)"
        } else if let album = track.album, !normalize(album).isEmpty {
            albumKey = "metadata:\(normalize(Self.principalArtist(track)))|\(normalize(album))"
        } else {
            albumKey = "track:\(track.videoId)"
        }
    }

    static func principalArtist(_ track: SongItemRecord) -> String {
        track.artistRuns.first {
            !($0.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.text ?? track.artists
    }
}

/// Metadata can improve while an album ID stays stable. This does not own player identity.
struct AnimatedArtworkRequestFingerprint: Equatable {
    let title: String
    let artist: String
    let album: String?
    let albumID: String?
    let duration: UInt64?
    let storefront: String

    init(track: SongItemRecord, storefront: String, audioDuration: Double? = nil) {
        title = track.title
        artist = AnimatedArtworkIdentity.principalArtist(track)
        album = track.album
        albumID = track.albumId
        duration = ExperimentalLyricsRequest.effectiveDurationSeconds(metadata: track.duration, audioDuration: audioDuration)
        self.storefront = storefront
    }
}

/// First-frame callbacks can arrive while flipped/hidden/paused, or after a replacement.
struct AnimatedArtworkPresentation {
    private(set) var revision = UUID()
    private(set) var hasFrame = false
    private(set) var revealed = false

    mutating func reset(revision: UUID) {
        self.revision = revision
        hasFrame = false
        revealed = false
    }

    mutating func receiveFrame(revision: UUID, eligible: Bool) -> Bool {
        guard self.revision == revision else { return false }
        hasFrame = true
        return resume(eligible: eligible)
    }

    mutating func resume(eligible: Bool) -> Bool {
        guard hasFrame, eligible, !revealed else { return false }
        revealed = true
        return true
    }
}

struct AnimatedArtworkPolicy: Equatable {
    var enabled = true
    var presented = false
    var visible = false
    var playing = false
    var flipped = false
    var constrained = false
    var mustRelease: Bool { !enabled || !presented || constrained }
    var canPrepare: Bool { !mustRelease && visible && playing && !flipped }
}

/// Independent from audio and the lyrics clock. Only first-frame/error KVO touches presentation.
@MainActor
final class AnimatedArtworkController {
    typealias Fetch = (String, Bool) async throws -> AnimatedArtworkAsset?
    typealias Release = (String) -> Void
    let layer = AVPlayerLayer()
    private(set) var identity: AnimatedArtworkIdentity?
    private(set) var policy = AnimatedArtworkPolicy()
    private(set) var requestID: String?
    var isReady: Bool { presentation.hasFrame }
    private var presentation = AnimatedArtworkPresentation()
    private var fetch: Fetch?
    private var release: Release?
    private(set) var preparation: Task<Void, Never>?
    private var idleRelease: Task<Void, Never>?
    private var readyTimeout: Task<Void, Never>?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var observations: [NSKeyValueObservation] = []
    private var itemObservation: NSKeyValueObservation?
    private var generation = UUID()
    private var attempted = false
    private var preferHevc = true
    private var fallbackUsed = false
    private var assetIsHevc = false
    private var fingerprint: AnimatedArtworkRequestFingerprint?
    private var suppressed = false
    private var managerToken: UUID?
    private let preparationDelay: Duration
    private let manager: AnimatedArtworkManager

    init(preparationDelay: Duration = .milliseconds(300), manager: AnimatedArtworkManager? = nil) {
        let manager = manager ?? AnimatedArtworkManager.shared
        self.preparationDelay = preparationDelay
        self.manager = manager
        layer.videoGravity = .resizeAspectFill
        layer.opacity = 0
        managerToken = manager.register { [weak self] in
            self?.suppressed = true
            self?.releaseResources()
        }
    }

    func update(identity next: AnimatedArtworkIdentity?, policy nextPolicy: AnimatedArtworkPolicy,
                fingerprint nextFingerprint: AnimatedArtworkRequestFingerprint? = nil,
                fetch: Fetch?, release: Release?) {
        if managerToken == nil {
            managerToken = manager.register { [weak self] in
                self?.suppressed = true
                self?.releaseResources()
            }
        }
        let reopened = !policy.presented && nextPolicy.presented
        if identity != next || reopened {
            releaseResources()
            identity = next
            attempted = false
            suppressed = false
            preferHevc = true
            fallbackUsed = false
        } else if fingerprint != nextFingerprint && player == nil && !suppressed {
            releaseResources()
            attempted = false
            preferHevc = true
            fallbackUsed = false
        }
        fingerprint = nextFingerprint
        policy = nextPolicy
        self.fetch = fetch
        self.release = release
        if nextPolicy.mustRelease || next == nil {
            releaseResources()
            attempted = false
            return
        }
        if !nextPolicy.canPrepare {
            player?.pause()
            if preparation != nil { releaseResources(); attempted = false }
            scheduleIdleRelease()
            return
        }
        idleRelease?.cancel()
        idleRelease = nil
        if let player {
            player.play()
            if presentation.resume(eligible: nextPolicy.canPrepare) { reveal() }
        } else if !attempted && !suppressed && !manager.isClearing,
                  let fetch {
            prepare(fetch)
        }
    }

    func detach() {
        releaseResources()
        if let managerToken { manager.unregister(managerToken) }
        managerToken = nil
        policy.presented = false
        attempted = false
    }

    func memoryPressure() {
        // Do not immediately recreate buffers under pressure; resume on the next presentation.
        suppressed = true
        releaseResources()
    }

    private func scheduleIdleRelease() {
        guard idleRelease == nil, player != nil else { return }
        idleRelease = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, !self.policy.canPrepare else { return }
            self.releaseResources()
            self.attempted = false
        }
    }

    private func prepare(_ fetch: @escaping Fetch, debounce: Bool = true) {
        attempted = true
        let revision = UUID()
        generation = revision
        presentation.reset(revision: revision)
        let id = UUID().uuidString
        requestID = id
        let requestedHevc = preferHevc
        preparation = Task { [weak self] in
            do {
                if debounce { try await Task.sleep(for: self?.preparationDelay ?? .milliseconds(300)) }
                guard let asset = try await fetch(id, requestedHevc) else {
                    self?.finishEmpty(revision)
                    return
                }
                try Task.checkCancellation()
                guard let self, self.generation == revision else { return }
                self.assetIsHevc = Self.isHevc(asset.codec)
                do {
                    let avAsset = try await Self.validate(asset)
                    try Task.checkCancellation()
                    guard self.generation == revision, self.policy.canPrepare else { return }
                    self.preparation = nil
                    self.install(avAsset, revision: revision)
                } catch {
                    self.failedAsset(revision)
                }
            } catch {
                self?.finishEmpty(revision)
            }
        }
    }

    private static func isHevc(_ codec: String) -> Bool {
        let codec = codec.lowercased()
        return codec.contains("hevc") || codec.hasPrefix("hvc1") || codec.hasPrefix("hev1") || codec == "h265"
    }

    /// Stat and AVFoundation loading execute away from the UI executor.
    nonisolated private static func validate(_ asset: AnimatedArtworkAsset) async throws -> AVAsset {
        let path = asset.localPath
        let url = URL(fileURLWithPath: path)
        try await Task.detached(priority: .utility) {
            let file = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard file.isRegularFile == true, let bytes = file.fileSize,
                  bytes > 0, bytes <= 128 * 1024 * 1024 else { throw ArtworkError.invalidAsset }
        }.value
        try Task.checkCancellation()
        let avAsset = AVURLAsset(url: url)
        guard asset.sizeBytes <= 128 * 1024 * 1024,
              asset.width > 0, asset.width == asset.height, asset.width <= 1080,
              asset.frameRate.isFinite, asset.frameRate > 0, asset.frameRate <= 60.1,
              try await avAsset.load(.isPlayable) else { throw ArtworkError.invalidAsset }
        let duration = try await avAsset.load(.duration).seconds
        let tracks = try await avAsset.loadTracks(withMediaType: .video)
        guard duration.isFinite, duration > 0, duration <= 60, tracks.count == 1,
              let track = tracks.first else { throw ArtworkError.invalidAsset }
        let size = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        guard size.width > 0, abs(size.width - size.height) <= 1,
              max(size.width, size.height) <= 1080, fps > 0, fps <= 60.1 else {
            throw ArtworkError.invalidAsset
        }
        return avAsset
    }

    private func failedAsset(_ revision: UUID) {
        guard generation == revision else { return }
        let canFallback = assetIsHevc && !isReady && !fallbackUsed && !suppressed
        releaseResources()
        guard canFallback else { return }
        fallbackUsed = true
        preferHevc = false
        if policy.canPrepare && !manager.isClearing, let fetch {
            prepare(fetch, debounce: false)
        } else {
            attempted = false
        }
    }

    private func reveal() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.225
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        CATransaction.commit()
        layer.add(fade, forKey: "artworkReveal")
    }

    private func finishEmpty(_ revision: UUID) {
        guard generation == revision else { return }
        releaseResources()
        // One attempt per album/presentation: unavailable and failures never spin on body updates.
    }

    private func install(_ asset: AVAsset, revision: UUID) {
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.volume = 0
        queue.preventsDisplaySleepDuringVideoPlayback = false
        queue.automaticallyWaitsToMinimizeStalling = true
        player = queue
        looper = AVPlayerLooper(player: queue, templateItem: item)
        layer.player = queue
        observations.append(layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            Task { @MainActor [weak self] in
                guard let self, self.generation == revision, ready else { return }
                let reveal = self.presentation.receiveFrame(revision: revision, eligible: self.policy.canPrepare)
                self.readyTimeout?.cancel()
                self.readyTimeout = nil
                if reveal { self.reveal() }
            }
        })
        observations.append(queue.observe(\.status, options: [.new]) { [weak self] queue, _ in
            let failed = queue.status == .failed
            Task { @MainActor [weak self] in
                guard failed else { return }
                self?.failedAsset(revision)
            }
        })
        observations.append(queue.observe(\.currentItem, options: [.initial, .new]) { [weak self] queue, _ in
            let item = queue.currentItem
            Task { @MainActor [weak self, weak queue] in
                guard let self, self.generation == revision, let queue,
                      queue.currentItem === item else { return }
                self.itemObservation = item?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    let failed = item.status == .failed
                    Task { @MainActor [weak self] in
                        guard failed else { return }
                        self?.failedAsset(revision)
                    }
                }
            }
        })
        observations.append(looper!.observe(\.status, options: [.new]) { [weak self] loop, _ in
            let failed = loop.status == .failed
            Task { @MainActor [weak self] in
                guard failed else { return }
                self?.failedAsset(revision)
            }
        })
        readyTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, !self.isReady else { return }
            self.failedAsset(revision)
        }
        queue.play()
    }

    private func releaseResources() {
        generation = UUID()
        preparation?.cancel()
        preparation = nil
        idleRelease?.cancel()
        idleRelease = nil
        readyTimeout?.cancel()
        readyTimeout = nil
        observations.removeAll()
        itemObservation = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.player = nil
        layer.removeAllAnimations()
        layer.opacity = 0
        CATransaction.commit()
        player = nil
        presentation.reset(revision: generation)
        assetIsHevc = false
        if let requestID { release?(requestID) }
        requestID = nil
    }

    private enum ArtworkError: Error { case invalidAsset }
}
