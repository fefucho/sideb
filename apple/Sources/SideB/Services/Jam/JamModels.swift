import Foundation
import SideBCore

/// Wire types of the `spotify-jam` plugin (session protocol v2, JSON lines).
struct JamTrack: Decodable, Equatable, Sendable, Identifiable {
    let uri: String
    let title: String?
    let artists: [String]
    let album: String?
    let durationMs: Double?
    let isrc: String?
    let provider: String?
    var id: String { uri }
    var displayTitle: String { title ?? uri }
    var displayArtists: String { artists.joined(separator: ", ") }
    /// Added to the Jam queue by a person; any other provider is Spotify's own suggestion.
    var isAddedByPerson: Bool { provider == "queue" }
}

struct JamMember: Decodable, Equatable, Sendable {
    let name: String?
    let imageUrl: String?
    let isHost: Bool
    let isMe: Bool
}

struct JamEvent: Decodable, Sendable {
    let type: String
    var members: [JamMember]?
    var canControl: Bool?
    var hostActive: Bool?
    var track: JamTrack?
    var positionMs: Double?
    var atLocalMs: Double?
    var paused: Bool?
    var durationMs: Double?
    var queue: [JamTrack]?
    var reason: String?
    var code: String?
    var retryable: Bool?
    var action: String?
    var ok: Bool?
    var detail: String?
    /// Opaque version of the Jam queue; edit commands carry the one they were built against.
    var queueRevision: String?
    var requestId: String?
    /// `resolved` reply: Spotify equivalent of a YouTube Music song (`uri` nil = no confident match).
    var uri: String?
    var title: String?
    var artists: [String]?
}

/// Spotify equivalent of a YouTube Music song, from the plugin's `resolve` request.
struct JamResolved: Equatable, Sendable {
    let uri: String
    let title: String?
    let artists: [String]
    let durationMs: Double?

    init(uri: String) {
        self.uri = uri
        title = nil
        artists = []
        durationMs = nil
    }

    init?(event: JamEvent) {
        guard event.type == "resolved", let uri = event.uri, !uri.isEmpty else { return nil }
        self.uri = uri
        title = event.title
        artists = event.artists ?? []
        durationMs = event.durationMs
    }
}

/// How a Jam track fares against YouTube Music.
enum JamMatchState: Equatable {
    case matched(SongItemRecord)
    case unavailable
}

/// One upcoming Jam track as the UI shows it: the Spotify track, its YouTube Music match (if any)
/// and where it stands. Mirrors the whole Jam queue, including rows with no playable equivalent.
struct JamQueueEntry: Identifiable, Equatable {
    enum Status: Equatable { case resolving, matched, unavailable }
    /// Stable across updates: the Spotify URI plus how many earlier entries share it.
    let id: String
    /// Index in the Jam queue (0 = plays next).
    let index: Int
    let track: JamTrack
    let song: SongItemRecord?
    let status: Status
    var isAddedByPerson: Bool { track.isAddedByPerson }
    var isSpotifySuggestion: Bool { !track.isAddedByPerson }
}

/// Result of a queue action, for the UI to show as a toast. `key` is a localisation key.
struct JamActionMessage: Identifiable, Equatable {
    let id = UUID()
    let key: String
    let args: [String]
}

/// Shared playback position as last reported by the Jam.
struct JamPlaybackState: Equatable, Sendable {
    var positionMs: Double
    /// Local-clock instant (ms since 1970) at which `positionMs` was true.
    var atLocalMs: Double
    var paused: Bool
    var durationMs: Double?

    func livePositionSeconds(nowMs: Double) -> Double {
        let elapsed = paused ? 0 : max(0, nowMs - atLocalMs)
        return (positionMs + elapsed) / 1000
    }
}
