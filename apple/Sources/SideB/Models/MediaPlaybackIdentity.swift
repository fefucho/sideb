import Foundation

/// Cards describe the playback source, independently of the track currently heard.
enum MediaPlaybackIdentity {
    static func isRadioOrigin(videoID: String, context: QueueContext?) -> Bool {
        guard !videoID.isEmpty, case .radio(let seed, _, _) = context else { return false }
        return !seed.isEmpty && seed == videoID
    }

    static func isCollectionActive(kind: String, id: String, context: QueueContext?) -> Bool {
        guard !id.isEmpty else { return false }
        switch (kind.lowercased(), context) {
        case ("album", .album(let activeID, _)):
            return MenuIDNormalizer.normalize(id) == MenuIDNormalizer.normalize(activeID)
        case ("playlist", .playlist(let activeID, _)), ("mix", .playlist(let activeID, _)):
            return MenuIDNormalizer.canonicalPlaylistId(id) == MenuIDNormalizer.canonicalPlaylistId(activeID)
        default: return false
        }
    }
}
