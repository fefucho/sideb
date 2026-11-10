import Foundation
import CryptoKit
import SideBCore

/// Solo metadata durable: las URLs de streaming y las cookies nunca se escriben aquí.
struct SavedPlaybackState: Codable {
    static let currentVersion = 3
    let version: Int
    let tracks: [Track]
    let currentIndex: Int
    let currentTrack: Track?
    let context: Context?
    let contextTitle: String
    let radioSeed: String?
    let isShuffle: Bool
    let isRepeat: Bool
    var order: QueueOrderSnapshot? = nil
    var radioCursorVideoID: String? = nil

    struct Track: Codable {
        let videoId: String
        let title: String
        let artists: String
        let album: String?
        let duration: String?
        let thumbnail: String?
        struct Artist: Codable {
            let text: String
            let id: String?
        }
        // Optional to read sessions saved before per-artist links were introduced.
        let artistRuns: [Artist]?
        let artistId: String?
        let albumId: String?
        let setVideoId: String?
        let isVideo: Bool
        let isUpload: Bool
        let contentRating: String?

        init(_ song: SongItemRecord) {
            videoId = song.videoId; title = song.title; artists = song.artists
            album = song.album; duration = song.duration; thumbnail = song.thumbnail
            artistId = song.artistId; albumId = song.albumId; setVideoId = song.setVideoId
            isVideo = song.isVideo; isUpload = song.isUpload
            contentRating = ContentRatingMetadata.encode(song.contentRating)
            artistRuns = song.artistRuns.map { Artist(text: $0.text, id: $0.id) }
        }

        var song: SongItemRecord {
            SongItemRecord(videoId: videoId, title: title, artists: artists, album: album,
                           duration: duration, thumbnail: thumbnail, artistId: artistId,
                           albumId: albumId, setVideoId: setVideoId, isVideo: isVideo,
                           isUpload: isUpload, library: nil,
                           artistRuns: (artistRuns ?? []).map { HomeArtistRunRecord(text: $0.text, id: $0.id) }, contentRating: ContentRatingMetadata.decode(contentRating))
        }
    }

    struct Context: Codable {
        let kind: String
        let id: String?
        let title: String
        let seedName: String?
        var localizationKey: String? = nil
        var localizationArguments: [String]? = nil

        init?(_ context: QueueContext?, localizationKey: String? = nil, localizationArguments: [String] = []) {
            guard let context else { return nil }
            self.localizationKey = localizationKey
            self.localizationArguments = localizationArguments.isEmpty ? nil : localizationArguments
            switch context {
            case .radio(let seed, let title, let name):
                kind = "radio"; id = seed; self.title = title; seedName = name
            case .album(let id, let title):
                kind = "album"; self.id = id; self.title = title; seedName = nil
            case .playlist(let id, let title):
                kind = "playlist"; self.id = id; self.title = title; seedName = nil
            case .custom(let title):
                kind = "custom"; id = nil; self.title = title; seedName = nil
            }
        }

        var queueContext: QueueContext? {
            switch kind {
            case "radio":
                guard let id, let seedName else { return nil }
                return .radio(seedVideoId: id, title: title, seedName: seedName)
            case "album":
                guard let id else { return nil }
                return .album(browseId: id, title: title)
            case "playlist":
                guard let id else { return nil }
                return .playlist(browseId: id, title: title)
            case "custom": return .custom(title: title)
            default: return nil
            }
        }
    }
}

@MainActor
final class PlaybackStateStore {
    private let directory: URL
    private var pendingSave: Task<Void, Never>?
    private var pendingState: SavedPlaybackState?
    private var pendingSnapshot: (@MainActor () -> SavedPlaybackState?)?
    private var activeIdentity: String?
    private let writer = DispatchQueue(label: "com.fefucho.SideB.playback-state-writer", qos: .utility)

    init(directory: URL = HomeLabConfiguration.appSupportURL.appendingPathComponent("PlaybackQueueExperiment", isDirectory: true)) {
        self.directory = directory
    }

    static func identity(for account: AccountInfoRecord?, cookieStorage: CookieStorage) -> String {
        let fingerprint = cookieStorage.playbackCacheIdentity()
        let mappingKey = "sideb.queueExperiment.playbackAccounts"
        if let id = account?.channelId ?? account?.email ?? account?.handle, !id.isEmpty {
            let identity = "account:\(id)"
            if fingerprint != "guest" {
                var mapping = UserDefaults.standard.dictionary(forKey: mappingKey) as? [String:String] ?? [:]
                mapping[fingerprint] = identity
                UserDefaults.standard.set(mapping, forKey: mappingKey)
            }
            return identity
        }
        guard fingerprint != "guest" else { return "guest" }
        let mapping = UserDefaults.standard.dictionary(forKey: mappingKey) as? [String:String]
        // Read the stable identity mapping for offline continuity; never write its keys or files.
        let stableKey = HomeLabConfiguration.enabled ? "sideb.lab.playbackAccounts" : "sideb.playbackAccounts"
        let stable = UserDefaults.standard.dictionary(forKey: stableKey) as? [String:String]
        return mapping?[fingerprint] ?? stable?[cookieStorage.legacyPlaybackCacheIdentity()] ?? "session:\(fingerprint)"
    }

    func activate(_ identity: String) {
        flush()
        activeIdentity = identity
    }

    func load() -> SavedPlaybackState? {
        writer.sync {}
        guard let activeIdentity,
              let data = try? Data(contentsOf: fileURL(for: activeIdentity)),
              let state = try? JSONDecoder().decode(SavedPlaybackState.self, from: data),
              (1...SavedPlaybackState.currentVersion).contains(state.version),
              state.currentIndex >= 0,
              state.tracks.isEmpty || state.currentIndex < state.tracks.count || (state.currentIndex == state.tracks.count && state.order?.stoppedAtEnd == true) else { return nil }
        return state
    }

    func scheduleSave(_ state: SavedPlaybackState) {
        guard activeIdentity != nil else { return }
        pendingState = state
        pendingSnapshot = nil
        scheduleFlush()
    }

    func scheduleSave(snapshot: @escaping @MainActor () -> SavedPlaybackState?) {
        guard activeIdentity != nil else { return }
        pendingState = nil
        pendingSnapshot = snapshot
        scheduleFlush()
    }

    private func scheduleFlush() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.persistPendingSynchronously(false)
        }
    }

    func saveNow(_ state: SavedPlaybackState) {
        pendingSave?.cancel()
        pendingState = state
        persistPendingSynchronously(true)
    }

    func flush() {
        persistPendingSynchronously(true)
        writer.sync {} // Drain any write already enqueued by the debounce before returning.
    }

    private func persistPendingSynchronously(_ waitForWrite: Bool) {
        pendingSave?.cancel()
        pendingSave = nil
        guard let activeIdentity else { return }
        let state = pendingState ?? pendingSnapshot?()
        pendingSnapshot = nil
        guard let state else { return }
        pendingState = nil
        let url = fileURL(for: activeIdentity)
        let directory = self.directory
        let write = {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let data = try JSONEncoder().encode(state)
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch { /* Persistence failures must not expose private state in logs. */ }
        }
        if waitForWrite { writer.sync(execute: write) } else { writer.async(execute: write) }
    }

    private func fileURL(for identity: String) -> URL {
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("queue-\(digest).json")
    }
}
