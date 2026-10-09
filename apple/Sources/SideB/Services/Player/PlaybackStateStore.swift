import Foundation
import CryptoKit
import SideBCore

/// Solo metadata durable: las URLs de streaming y las cookies nunca se escriben aquí.
struct SavedPlaybackState: Codable {
    static let currentVersion = 2
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

        init(_ song: SongItemRecord) {
            videoId = song.videoId; title = song.title; artists = song.artists
            album = song.album; duration = song.duration; thumbnail = song.thumbnail
            artistId = song.artistId; albumId = song.albumId; setVideoId = song.setVideoId
            isVideo = song.isVideo; isUpload = song.isUpload
            artistRuns = song.artistRuns.map { Artist(text: $0.text, id: $0.id) }
        }

        var song: SongItemRecord {
            SongItemRecord(videoId: videoId, title: title, artists: artists, album: album,
                           duration: duration, thumbnail: thumbnail, artistId: artistId,
                           albumId: albumId, setVideoId: setVideoId, isVideo: isVideo,
                           isUpload: isUpload, library: nil,
                           artistRuns: (artistRuns ?? []).map { HomeArtistRunRecord(text: $0.text, id: $0.id) })
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
    private var activeIdentity: String?

    init(directory: URL = HomeLabConfiguration.appSupportURL.appendingPathComponent("Playback", isDirectory: true)) {
        self.directory = directory
    }

    static func identity(for account: AccountInfoRecord?, cookieStorage: CookieStorage) -> String {
        let fingerprint = cookieStorage.homeCacheIdentity()
        let mappingKey = HomeLabConfiguration.enabled ? "sideb.lab.playbackAccounts" : "sideb.playbackAccounts"
        if let id = account?.channelId ?? account?.email ?? account?.handle, !id.isEmpty {
            let identity = "account:\(id)"
            if fingerprint != "guest" {
                var mapping = UserDefaults.standard.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
                mapping[fingerprint] = identity
                UserDefaults.standard.set(mapping, forKey: mappingKey)
            }
            return identity
        }
        guard fingerprint != "guest" else { return "guest" }
        let mapping = UserDefaults.standard.dictionary(forKey: mappingKey) as? [String: String]
        return mapping?[fingerprint] ?? "session:\(fingerprint)"
    }

    func activate(_ identity: String) {
        flush()
        activeIdentity = identity
    }

    func load() -> SavedPlaybackState? {
        guard let activeIdentity,
              let data = try? Data(contentsOf: fileURL(for: activeIdentity)),
              let state = try? JSONDecoder().decode(SavedPlaybackState.self, from: data),
              (1...SavedPlaybackState.currentVersion).contains(state.version),
              state.currentIndex >= 0,
              state.tracks.isEmpty || state.currentIndex < state.tracks.count else { return nil }
        return state
    }

    func scheduleSave(_ state: SavedPlaybackState) {
        guard activeIdentity != nil else { return }
        pendingState = state
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func saveNow(_ state: SavedPlaybackState) {
        pendingSave?.cancel()
        pendingState = state
        flush()
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let activeIdentity, let state = pendingState else { return }
        pendingState = nil
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            let url = fileURL(for: activeIdentity)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            #if DEBUG
            print("[PlaybackStateStore] No se pudo guardar la cola: \(error)")
            #endif
        }
    }

    private func fileURL(for identity: String) -> URL {
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("queue-\(digest).json")
    }
}
