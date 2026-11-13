import Foundation
import SideBCore

/// Picks the YouTube Music song that corresponds to a Spotify track. Exact sync needs the same
/// recording, so duration closeness weighs as much as the names.
enum JamMatcher {
    struct Candidate: Identifiable {
        let song: SongItemRecord
        let score: Double
        /// YouTube Music duration minus Spotify duration, in seconds.
        let durationDelta: Double?
        var id: String { song.videoId }
        var isConfident: Bool { score >= 4 }
    }

    static func query(for track: JamTrack) -> String {
        [track.title, track.artists.first].compactMap { $0 }.joined(separator: " ")
    }

    /// Lowercased, accent-free, without bracketed or dash-suffixed version notes.
    static func normalize(_ value: String) -> String {
        var text = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        for pair in [("(", ")"), ("[", "]")] {
            while let open = text.range(of: pair.0), let close = text.range(of: pair.1, range: open.upperBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            }
        }
        if let dash = text.range(of: " - ") { text = String(text[..<dash.lowerBound]) }
        let kept = text.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    static func seconds(_ duration: String?) -> Double? {
        guard let duration else { return nil }
        let parts = duration.split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.count <= 3, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    static func rank(track: JamTrack, candidates: [SongItemRecord]) -> [Candidate] {
        let title = normalize(track.title ?? "")
        let artists = track.artists.map(normalize).filter { !$0.isEmpty }
        let wanted = track.durationMs.map { $0 / 1000 }
        let ranked = candidates.enumerated().map { index, song -> (Int, Candidate) in
            var score = 0.0
            let candidateTitle = normalize(song.title)
            if !title.isEmpty, candidateTitle == title { score += 3 }
            else if !title.isEmpty, !candidateTitle.isEmpty, candidateTitle.contains(title) || title.contains(candidateTitle) { score += 1.5 }
            let candidateArtists = normalize(song.artists)
            if artists.contains(where: { candidateArtists.contains($0) }) { score += 2 }
            var delta: Double?
            if let wanted, let actual = seconds(song.duration) {
                delta = actual - wanted
                // The catalog reports whole seconds, so anything within one second is "the same".
                switch abs(actual - wanted) {
                case ..<1.6: score += 2
                case ..<4: score += 1
                case ..<10: score += 0.3
                default: score -= 1
                }
            }
            if song.isVideo { score -= 1 }
            return (index, Candidate(song: song, score: score, durationDelta: delta))
        }
        return ranked.sorted { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0 }.map(\.1)
    }
}
