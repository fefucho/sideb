import Foundation
import CryptoKit
import Darwin
import Observation
import AVFoundation
import AppKit
import WebKit
import SideBCore

@MainActor @Observable
final class VisualProviderHost {
    static let shared = VisualProviderHost(bundledPackage: VisualProviderHost.bundledPackageInApp)
    private static let enabledKey = "sideb.visualProvider.enabled.v1"
    /// Provider ids the user uninstalled on purpose. A bundled package is never put back for these.
    private static let removedKey = "sideb.visualProvider.userRemoved.v1"
    /// Factory package inside the signed app: `Contents/Resources/VisualProviders/spotify-canvas`.
    static var bundledPackageInApp: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("VisualProviders", isDirectory: true).appendingPathComponent("spotify-canvas", isDirectory: true)
    }
    private let bundledPackage: URL?
    /// First-launch provisioning of `bundledPackage`; install/uninstall wait for it so they never interleave.
    private(set) var provisioning: Task<Void, Never>?
    private let preferences: UserDefaults
    private let root: URL
    /// The Spotify login, shared with the Jam. Used only while the installed provider's auth targets Spotify.
    private let spotifySession: CredentialSession
    /// Token of a provider whose login is not Spotify's (or that has no login descriptor). Never holds Spotify's.
    private let ownSession: CredentialSession
    private var authBlocked = false
    private var backoffUntil = Date.distantPast
    private var backgroundRecovery: Task<Void, Never>?
    private var lastForegroundRetry = Date.distantPast
    private static let ownSavedAtKey = "sideb.visualProvider.otherCredentialSavedAt.v1"
    private(set) var manifest: VisualProviderManifest?
    private(set) var revision: UInt64 = 0
    /// The session that serves the installed provider: Spotify's only when its auth is Spotify's.
    private var activeSession: CredentialSession { SpotifySession.matches(manifest?.auth) ? spotifySession : ownSession }
    /// Whether the installed provider has a credential (it can be the one shared with the Jam).
    var hasCredential: Bool { manifest != nil && activeSession.hasCredential }
    /// The installed provider shares the Spotify session, so signing out affects the Jam too.
    var usesSpotifySession: Bool { manifest != nil && SpotifySession.matches(manifest?.auth) }
    private(set) var statusKey = "visualProvider.status.idle"
    private var jobs: [String: VisualProviderJob] = [:]
    var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            invalidate()
            preferences.set(enabled, forKey: Self.enabledKey)
        }
    }
    var identitySalt: String? { enabled && manifest != nil && hasCredential ? "\(manifest!.id):\(revision)" : nil }

    init(root: URL? = nil, preferences: UserDefaults = HomeAppearance.preferences, credentials: (any VisualProviderCredentials)? = nil, tokenSource: (any VisualProviderTokenSource)? = nil, spotifySession: CredentialSession? = nil, bundledPackage: URL? = nil) {
        self.bundledPackage = bundledPackage
        self.root = root ?? HomeLabConfiguration.appSupportURL.appendingPathComponent("VisualProviders", isDirectory: true)
        self.preferences = preferences
        self.spotifySession = spotifySession ?? SpotifySession.shared
        self.ownSession = CredentialSession(credentials: credentials ?? KeychainVisualProviderCredentials(account: KeychainVisualProviderCredentials.otherProviderAccount),
                                            tokenSource: tokenSource ?? WebViewVisualProviderTokenSource(),
                                            preferences: preferences, savedAtKey: Self.ownSavedAtKey)
        enabled = preferences.bool(forKey: Self.enabledKey)
        manifest = try? Self.readManifest(at: self.root.appendingPathComponent("Installed", isDirectory: true))
        if manifest == nil { enabled = false }
        if manifest != nil, !hasCredential { statusKey = "visualProvider.status.tokenRequired" }
        for session in [self.spotifySession, self.ownSession] {
            session.subscribe { [weak self, weak session] event in
                guard let self, let session else { return false }
                MainActor.assumeIsolated { self.sessionEvent(event, from: session) }
                return true
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.retryAfterReturningToApp() }
        }
        let sessions = self.root.appendingPathComponent("Sessions", isDirectory: true)
        Task.detached(priority: .utility) {
            // Clean abandoned crash leftovers only; never remove a recent lease owned by another instance.
            let fm = FileManager.default
            for url in (try? fm.contentsOfDirectory(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      date < Date().addingTimeInterval(-86400),
                      let owner = try? String(contentsOf: url.appendingPathComponent(".owner"), encoding: .utf8),
                      let pid = Int32(owner), pid > 0 else { continue }
                // An old directory can still be leased by a long-running instance. Never remove it.
                if Darwin.kill(pid, 0) == -1 && errno == ESRCH { try? fm.removeItem(at: url) }
            }
        }
    }
    private var installed: URL { root.appendingPathComponent("Installed", isDirectory: true) }
    private var cacheRoot: URL { root.appendingPathComponent("Sessions", isDirectory: true) }
    private var mediaCacheRoot: URL { root.appendingPathComponent("Cache", isDirectory: true) }

    static func readManifest(at package: URL) throws -> VisualProviderManifest {
        let manifestURL = package.appendingPathComponent("manifest.json")
        let info = try manifestURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, let size = info.fileSize, size > 0, size <= 8192 else { throw VisualProviderFailure.invalid }
        let data = try Data(contentsOf: manifestURL)
        guard data.count <= 8192 else { throw VisualProviderFailure.invalid }
        let manifest = try JSONDecoder().decode(VisualProviderManifest.self, from: data)
        try manifest.validate()
        let executable = package.appendingPathComponent(manifest.executable)
        let values = try executable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 128 * 1024 * 1024 else { throw VisualProviderFailure.invalid }
        return manifest
    }

    /// Manual installation: the explicit fallback, and the way back after the user removed the bundled provider.
    /// Only the manifest and one executable are installed. No symlinks, extra files or arbitrary arguments.
    func install(from source: URL) async throws {
        await provisioning?.value
        let next = try Self.readManifest(at: source)
        try await performInstall(from: source, next: next, trustedBundle: false)
        // Installing again is an explicit decision that revokes an earlier removal.
        setRemoved(next.id, false)
    }

    /// Puts the app's bundled provider in place the first time (or upgrades it when the app ships a newer one).
    /// It never activates it: that needs the user's login/token. A provider the user removed is never reinstalled,
    /// and a different manually installed provider is left alone.
    func provisionBundledProvider() {
        guard provisioning == nil, bundledPackage != nil else { return }
        provisioning = Task { @MainActor [weak self] in await self?.installBundledProviderIfNeeded() }
    }

    private func installBundledProviderIfNeeded() async {
        guard let bundledPackage, let next = try? Self.readManifest(at: bundledPackage),
              !removedProviders.contains(next.id) else { return }
        if let current = manifest {
            guard current.id == next.id, Self.isNewer(next.version, than: current.version) else { return }
        }
        // A failed preinstall leaves the app exactly as it was; the manual installer remains available.
        try? await performInstall(from: bundledPackage, next: next, trustedBundle: true)
    }

    private func performInstall(from source: URL, next: VisualProviderManifest, trustedBundle: Bool) async throws {
        let isUpgrade = manifest?.id == next.id
        if !isUpgrade { enabled = false }
        invalidate()
        let destination = installed
        let parent = root
        try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let staging = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: staging) }
            let executable = staging.appendingPathComponent(next.executable)
            try fm.copyItem(at: source.appendingPathComponent(next.executable), to: executable)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            // Our own signed payload must run even when the downloaded app carries the quarantine flag.
            if trustedBundle { _ = removexattr(executable.path, "com.apple.quarantine", 0) }
            try JSONEncoder().encode(next).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: staging, to: destination)
        }.value
        // Another provider never inherits a token. The shared Spotify login is not the provider's to wipe.
        if !isUpgrade { try await ownSession.signOut() }
        manifest = next
        revision &+= 1
        statusKey = hasCredential ? "visualProvider.status.idle" : "visualProvider.status.tokenRequired"
    }

    private var removedProviders: Set<String> { Set(preferences.stringArray(forKey: Self.removedKey) ?? []) }
    private func setRemoved(_ id: String, _ removed: Bool) {
        var ids = removedProviders
        if removed { ids.insert(id) } else { ids.remove(id) }
        if ids.isEmpty { preferences.removeObject(forKey: Self.removedKey) } else { preferences.set(ids.sorted(), forKey: Self.removedKey) }
    }

    /// Dotted numeric comparison ("0.10.0" > "0.9.3"); anything else is not an upgrade.
    nonisolated static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let parse: (String) -> [Int]? = { text in
            let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
            return parts.isEmpty || parts.contains(where: { $0 == nil }) ? nil : parts.map { $0! }
        }
        guard var lhs = parse(candidate), var rhs = parse(installed) else { return false }
        let count = max(lhs.count, rhs.count)
        lhs += Array(repeating: 0, count: count - lhs.count)
        rhs += Array(repeating: 0, count: count - rhs.count)
        return rhs.lexicographicallyPrecedes(lhs)
    }
    /// Removes the provider for real and remembers the decision, so a bundled copy is not reinstalled at next launch.
    func uninstall() async throws {
        await provisioning?.value
        if let id = manifest?.id ?? bundledPackage.flatMap({ try? Self.readManifest(at: $0).id }) { setRemoved(id, true) }
        enabled = false
        invalidate()
        // The Spotify login is shared with the Jam: removing Canvas never signs the user out of Spotify.
        // Only a provider-private token goes away with its provider.
        if !usesSpotifySession { try await ownSession.signOut() }
        manifest = nil
        let destination = installed
        let cache = mediaCacheRoot
        try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            if fm.fileExists(atPath: cache.path) { try fm.removeItem(at: cache) }
        }.value
        revision &+= 1
    }
    private func invalidate() {
        // Native consumers synchronously detach AVPlayer before files are released.
        NotificationCenter.default.post(name: .visualProviderWillChange, object: nil)
        let active = Array(jobs.values); jobs.removeAll()
        for job in active { Task.detached(priority: .utility) { job.cancel() } }
        authBlocked = false
        backoffUntil = .distantPast
        backgroundRecovery?.cancel(); backgroundRecovery = nil
        revision &+= 1
    }

    /// Reacts to the session that serves the installed provider changing, whoever changed it (Settings, the Jam panel).
    private func sessionEvent(_ event: CredentialSession.Event, from session: CredentialSession) {
        guard session === activeSession else { return }
        switch event {
        case .signedIn:
            invalidate()
            statusKey = "visualProvider.status.idle"
        case .signedOut:
            invalidate()
            statusKey = manifest == nil ? "visualProvider.status.idle" : "visualProvider.status.tokenRequired"
        case .renewed:
            // Silent renewal must not detach running players; only a provider that was blocked re-queries.
            let wasBlocked = authBlocked
            authBlocked = false
            backgroundRecovery?.cancel(); backgroundRecovery = nil
            statusKey = "visualProvider.status.idle"
            if wasBlocked { revision &+= 1 }
        }
    }
    func release(_ requestID: String) {
        guard let job = jobs.removeValue(forKey: requestID) else { return }
        Task.detached(priority: .utility) { job.cancel() }
    }

    private func cacheKey(for track: SongItemRecord) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = track.videoId.unicodeScalars.filter { allowed.contains($0) }
        let key = String(String.UnicodeScalarView(sanitized))
        if !key.isEmpty && key.count <= 64 {
            return key
        }
        return SHA256.hash(data: Data(track.videoId.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }

    func prepare(track: SongItemRecord, duration: UInt64?, requestID: String) async throws -> AnimatedArtworkAsset? {
        try await prepare(track: track, duration: duration, requestID: requestID, isRetry: false)
    }

    private func prepare(track: SongItemRecord, duration: UInt64?, requestID: String, isRetry: Bool) async throws -> AnimatedArtworkAsset? {
        guard enabled, !authBlocked, backoffUntil < Date(), let manifest, hasCredential, jobs.count < 2 else { return nil }
        let session = activeSession
        if !authBlocked { await session.refreshIfStale(auth: manifest.auth) }
        guard let credential = session.currentCredential() else { return nil }

        let providerCache = mediaCacheRoot.appendingPathComponent(manifest.id, isDirectory: true)
        let key = cacheKey(for: track)
        let cachedFileURL = providerCache.appendingPathComponent("\(key).mp4")

        // 1. Check persistent cache: if already cached and valid, return immediately without network or subprocess.
        if FileManager.default.fileExists(atPath: cachedFileURL.path) {
            if let asset = try? await Self.loadAsset(url: cachedFileURL, assetId: "visual-extension:\(requestID)") {
                statusKey = "visualProvider.status.ready"
                return asset
            } else {
                try? FileManager.default.removeItem(at: cachedFileURL)
            }
        }

        let epoch = revision
        let directory = cacheRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(String(getpid()).utf8).write(to: directory.appendingPathComponent(".owner"), options: .atomic)
        let job = VisualProviderJob(directory: directory)
        jobs[requestID] = job
        let request = VisualProviderRequest(requestId: requestID, credential: credential, outputDirectory: directory.path,
            track: .init(videoId: track.videoId, title: track.title, artist: AnimatedArtworkIdentity.principalArtist(track),
                         album: track.album, durationSeconds: duration,
                         explicit: track.contentRating == .explicit ? true : track.contentRating == .clean ? false : nil))
        let input = try JSONEncoder().encode(request)
        let executable = installed.appendingPathComponent(manifest.executable)
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(22)) } catch { return }
            Task.detached { job.cancel() }
        }
        defer { timeout.cancel() }
        do {
            let data = try await withTaskCancellationHandler {
                try await Task.detached(priority: .utility) { try job.run(executable: executable, input: input) }.value
            } onCancel: { job.cancel() }
            try Task.checkCancellation()
            guard revision == epoch, jobs[requestID] === job else { throw VisualProviderFailure.cancelled }
            let reply = try JSONDecoder().decode(VisualProviderReply.self, from: data)
            try reply.validate(requestID: requestID)
            if reply.status == "authRequired" {
                session.noteRejected(credential)
                if !isRetry, manifest.auth?.type == "webview" {
                    // The provider refused this token: fetch another in the background and retry once.
                    release(requestID)
                    if await recoverCredential() != nil {
                        return try await prepare(track: track, duration: duration, requestID: requestID, isRetry: true)
                    }
                }
            }
            statusKey = "visualProvider.status.\(reply.status)"
            if reply.status == "authRequired" {
                authBlocked = true
                scheduleBackgroundRecovery()
            }
            if reply.status == "rateLimited" { backoffUntil = Date().addingTimeInterval(60) }
            guard reply.status == "ready" else { release(requestID); return nil }
            let tempAsset = try await Self.loadAsset(directory: directory, requestID: requestID)
            try Task.checkCancellation()
            guard revision == epoch, jobs[requestID] === job else { throw VisualProviderFailure.cancelled }

            // Store in persistent cache so repeated playback and seeks are instant and permanent.
            let finalAsset: AnimatedArtworkAsset = await Task.detached(priority: .utility) {
                let fm = FileManager.default
                try? fm.createDirectory(at: providerCache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let tempCopy = providerCache.appendingPathComponent("\(key).mp4.tmp")
                try? fm.removeItem(at: tempCopy)
                do {
                    try fm.copyItem(at: directory.appendingPathComponent("visual.mp4"), to: tempCopy)
                    if fm.fileExists(atPath: cachedFileURL.path) {
                        try? fm.removeItem(at: cachedFileURL)
                    }
                    try fm.moveItem(at: tempCopy, to: cachedFileURL)
                    return AnimatedArtworkAsset(assetId: "visual-extension:\(requestID)", localPath: cachedFileURL.path,
                                                codec: tempAsset.codec, width: tempAsset.width, height: tempAsset.height,
                                                frameRate: tempAsset.frameRate, sizeBytes: tempAsset.sizeBytes)
                } catch {
                    try? fm.removeItem(at: tempCopy)
                    return tempAsset
                }
            }.value

            pruneCacheIfNeeded(in: providerCache)
            return finalAsset
        } catch {
            if revision == epoch && !Task.isCancelled { statusKey = "visualProvider.status.unavailable" }
            release(requestID)
            throw error
        }
    }

    private func pruneCacheIfNeeded(in folder: URL) {
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let maxBudget: UInt64 = 200 * 1024 * 1024 // 200 MB
            let targetBudget: UInt64 = 150 * 1024 * 1024 // 150 MB
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: .skipsHiddenFiles) else { return }
            var total: UInt64 = 0
            var entries: [(url: URL, size: UInt64, date: Date)] = []
            for file in files where file.pathExtension == "mp4" {
                if let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                   let size = values.fileSize, let date = values.contentModificationDate {
                    total += UInt64(size)
                    entries.append((url: file, size: UInt64(size), date: date))
                }
            }
            if total > maxBudget {
                entries.sort { $0.date < $1.date }
                for entry in entries {
                    if total <= targetBudget { break }
                    if (try? fm.removeItem(at: entry.url)) != nil {
                        total = total > entry.size ? total - entry.size : 0
                    }
                }
            }
        }
    }

    func cacheSize() async -> UInt64 {
        let root = mediaCacheRoot
        return await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(atPath: root.path) else { return 0 }
            var total: UInt64 = 0
            while let file = enumerator.nextObject() as? String {
                let fileURL = root.appendingPathComponent(file)
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += UInt64(size)
                }
            }
            return total
        }.value
    }

    @discardableResult
    func clearCache() async -> UInt64 {
        let size = await cacheSize()
        let root = mediaCacheRoot
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: root)
        }.value
        return size
    }

    nonisolated static func loadAsset(url: URL, assetId: String) async throws -> AnimatedArtworkAsset {
        let values = try await Task.detached(priority: .utility) { try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) }.value
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let bytes = values.fileSize, bytes > 0, bytes <= 24 * 1024 * 1024 else { throw VisualProviderFailure.invalid }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard tracks.count == 1, let video = tracks.first, try await asset.load(.isPlayable) else { throw VisualProviderFailure.invalid }
        let duration = try await asset.load(.duration).seconds
        let size = try await video.load(.naturalSize)
        let fps = try await video.load(.nominalFrameRate)
        let formats = try await video.load(.formatDescriptions)
        guard let format = formats.first, CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264,
              duration.isFinite, (2.5...8.5).contains(duration), Self.validDimensions(size, fps: Double(fps)) else { throw VisualProviderFailure.invalid }
        return AnimatedArtworkAsset(assetId: assetId, localPath: url.path, codec: "h264",
            width: UInt32(size.width), height: UInt32(size.height), frameRate: Double(fps), sizeBytes: UInt64(bytes))
    }

    nonisolated static func loadAsset(directory: URL, requestID: String) async throws -> AnimatedArtworkAsset {
        try await loadAsset(url: directory.appendingPathComponent("visual.mp4"), assetId: "visual-extension:\(requestID)")
    }
    nonisolated static func validDimensions(_ size: CGSize, fps: Double) -> Bool {
        // Spotify's Web Player currently serves Canvas at 720×1280; honor its 9:16 source
        // dimensions while keeping a bounded portrait envelope for downloaded media.
        size.width > 0 && size.height >= 720 && size.height <= 1920 && size.width <= 1080 &&
            (0.55...0.58).contains(size.width / max(1, size.height)) && fps.isFinite && fps > 0 && fps <= 60.1
    }

    /// Stores a token the user pasted or the login window produced, in the session that serves the provider.
    func saveCredential(_ value: String) throws {
        try activeSession.save(value)
    }

    /// Signs out of Spotify for every feature that shares the session (Canvas and the Jam).
    func signOutOfSpotify() async throws {
        try await spotifySession.signOut()
    }

    // MARK: Autonomous credential recovery

    /// One recovery at a time (the session shares a single web view attempt between concurrent requests).
    @discardableResult
    func recoverCredential() async -> String? {
        guard let manifest, let auth = manifest.auth, auth.type == "webview" else { return nil }
        return await activeSession.recover(auth: auth)
    }

    /// While the session stays rejected keep looking for a working token, with growing pauses.
    private func scheduleBackgroundRecovery() {
        guard backgroundRecovery == nil, manifest?.auth != nil else { return }
        let delays: [Double] = [20, 90, 300, 900, 1800]
        backgroundRecovery = Task { @MainActor [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delays[min(attempt, delays.count - 1)]))
                guard let self, !Task.isCancelled, self.enabled, self.authBlocked else { self?.backgroundRecovery = nil; return }
                if await self.recoverCredential() != nil { return }
                attempt += 1
            }
        }
    }

    private func retryAfterReturningToApp() {
        guard enabled, authBlocked, manifest?.auth != nil, Date().timeIntervalSince(lastForegroundRetry) > 60 else { return }
        lastForegroundRetry = Date()
        Task { await recoverCredential() }
    }
}
