import Foundation
import CryptoKit
import Observation
import SideBCore

public enum SearchOrigin: Sendable {
    case submit, recentQuery, preview, filter, refresh, navigationRestore, artistResolution
    var recordsHistory: Bool { self == .submit || self == .recentQuery }
}

/// Local search decisions, separate from remote search and listening history.
@MainActor @Observable
public final class SearchRecentStore {
    public static let shared = SearchRecentStore()
    public struct Entry: Codable, Identifiable {
        public let key: String
        public let kind: String
        public let lastUsedAt: Double
        public let query: String?
        public let track: Track?
        public var id: String { key }
    }
    public struct Track: Codable {
        let videoId: String, title: String, artists: String
        let album: String?, duration: String?, thumbnail: String?, artistId: String?, albumId: String?
        let isVideo: Bool, isUpload: Bool
        let contentRating: String?
        struct Artist: Codable { let text: String; let id: String? }
        let artistRuns: [Artist]
        init(_ song: SongItemRecord) {
            videoId = song.videoId; title = song.title; artists = song.artists
            album = song.album; duration = song.duration; thumbnail = song.thumbnail
            artistId = song.artistId; albumId = song.albumId; isVideo = song.isVideo; isUpload = song.isUpload
            artistRuns = song.artistRuns.map { Artist(text: $0.text, id: $0.id) }
            contentRating = ContentRatingMetadata.encode(song.contentRating)
        }
        public var song: SongItemRecord {
            SongItemRecord(videoId: videoId, title: title, artists: artists, album: album,
                duration: duration, thumbnail: thumbnail, artistId: artistId, albumId: albumId,
                setVideoId: nil, isVideo: isVideo, isUpload: isUpload, library: nil,
                artistRuns: artistRuns.map { HomeArtistRunRecord(text: $0.text, id: $0.id) }, contentRating: ContentRatingMetadata.decode(contentRating))
        }
    }
    private struct Saved: Codable { let version: Int; let entries: [Entry] }
    private struct Intent { let token: UUID; let account: String; let track: Track }
    public private(set) var entries: [Entry] = []
    public private(set) var accountIdentity = "guest"
    public private(set) var canUndo = false
    public private(set) var persistenceError = false
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var undoEntries: [Entry]?
    @ObservationIgnored private var intent: Intent?
    @ObservationIgnored private var initialized = false
    public private(set) var unavailableTrack: Track?

    public init(directory: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.directory = directory ?? HomeLabConfiguration.appSupportURL.appendingPathComponent("SearchRecents", isDirectory: true)
        self.now = now
        setAccount("guest")
    }
    private var file: URL {
        let digest = SHA256.hash(data: Data(accountIdentity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }
    public static func normalizedQuery(_ query: String) -> String {
        query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").precomposedStringWithCanonicalMapping
    }
    public func setAccount(_ identity: String) {
        guard !initialized || accountIdentity != identity else { return }
        initialized = true; unavailableTrack = nil
        accountIdentity = identity; intent = nil; entries = []; undoEntries = nil; canUndo = false; persistenceError = false
        guard let data = try? Data(contentsOf: file) else { return }
        guard let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            document["version"] as? Int == 1, let raw = document["entries"] as? [Any] else { persistenceError = true; return }
        let valid = raw.compactMap { object -> Entry? in
            guard JSONSerialization.isValidJSONObject(object), let encoded = try? JSONSerialization.data(withJSONObject: object),
                let entry = try? JSONDecoder().decode(Entry.self, from: encoded), entry.lastUsedAt.isFinite else { return nil }
            if entry.kind == "query", let text = entry.query {
                let query = Self.normalizedQuery(text); guard !query.isEmpty else { return nil }
                return Entry(key: "query:" + query.lowercased(), kind: "query", lastUsedAt: entry.lastUsedAt, query: query, track: nil)
            }
            if entry.kind == "track", let track = entry.track, !track.videoId.isEmpty {
                return Entry(key: "track:" + (track.isUpload ? "upload:" : "youtube:") + track.videoId,
                    kind: "track", lastUsedAt: entry.lastUsedAt, query: nil, track: track)
            }
            return nil
        }.sorted { $0.lastUsedAt > $1.lastUsedAt }
        var seen = Set<String>()
        entries = Array(valid.filter { seen.insert($0.key).inserted }.prefix(50))
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(version: 1, entries: entries)).write(to: file, options: .atomic)
            persistenceError = false
        } catch { persistenceError = true }
    }
    private func use(_ entry: Entry) {
        entries.removeAll { $0.key == entry.key }; entries.insert(entry, at: 0)
        entries = Array(entries.prefix(50)); undoEntries = nil; canUndo = false; save()
    }
    public func recordQuery(_ text: String) {
        let query = Self.normalizedQuery(text); guard !query.isEmpty else { return }
        let key = query.lowercased()
        use(Entry(key: "query:" + key, kind: "query", lastUsedAt: now().timeIntervalSince1970 * 1000, query: query, track: nil))
    }
    /// Root binds this token to its accepted playback request and confirms only actual playback.
    @discardableResult public func beginTrack(_ song: SongItemRecord) -> UUID {
        let token = UUID(); unavailableTrack = nil; intent = Intent(token: token, account: accountIdentity, track: Track(song)); return token
    }
    public func failTrack(_ token: UUID? = nil) { if let pending = intent, token == nil || pending.token == token { unavailableTrack = pending.track; intent = nil } }
    public func cancelTrack(_ token: UUID? = nil) { if token == nil || intent?.token == token { intent = nil } }
    public func confirmTrack(_ token: UUID, videoId: String) {
        guard let pending = intent, pending.token == token, pending.account == accountIdentity, pending.track.videoId == videoId else { return }
        intent = nil
        use(Entry(key: "track:" + (pending.track.isUpload ? "upload:" : "youtube:") + videoId,
            kind: "track", lastUsedAt: now().timeIntervalSince1970 * 1000, query: nil, track: pending.track))
    }
    public func remove(_ key: String) { if let failed = unavailableTrack, key == "track:" + (failed.isUpload ? "upload:" : "youtube:") + failed.videoId { unavailableTrack = nil }; undoEntries = entries; canUndo = true; entries.removeAll { $0.key == key }; save() }
    public func clear() { undoEntries = entries; canUndo = true; entries = []; save() }
    public func undo() { guard let saved = undoEntries else { return }; entries = saved; undoEntries = nil; canUndo = false; save() }
}
