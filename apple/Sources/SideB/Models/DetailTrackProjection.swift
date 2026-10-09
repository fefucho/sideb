import Foundation
import SideBCore

public enum DetailTrackOrder: String, CaseIterable, Identifiable {
    case custom
    case title
    case artist
    case album
    case recentlyAdded
    case oldestAdded
    case duration

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .custom: L10n.text("detail.sort.custom")
        case .title: L10n.text("detail.sort.title")
        case .artist: L10n.text("detail.sort.artist")
        case .album: L10n.text("detail.sort.album")
        case .recentlyAdded: L10n.text("detail.sort.recentlyAdded")
        case .oldestAdded: L10n.text("detail.sort.oldestAdded")
        case .duration: L10n.text("detail.sort.duration")
        }
    }
}

public struct DetailTrackEntry: Identifiable {
    public let originalIndex: Int
    public let track: SongItemRecord
    public let id: String

    public init(originalIndex: Int, track: SongItemRecord, id: String? = nil) {
        self.originalIndex = originalIndex
        self.track = track
        self.id = id ?? Self.identity(track: track, index: originalIndex, duplicateOrdinal: 0)
    }

    fileprivate static func identity(track: SongItemRecord, index: Int, duplicateOrdinal: Int) -> String {
        if let setVideoId = track.setVideoId, !setVideoId.isEmpty {
            return "set:\(setVideoId):\(duplicateOrdinal)"
        }
        return "index:\(index):video:\(track.videoId)"
    }
}

public enum DetailTrackProjection {
    public static func make(
        tracks: [SongItemRecord],
        query: String,
        order: DetailTrackOrder,
        customOrder: [Int]? = nil
    ) -> [DetailTrackEntry] {
        var ordinals: [String: Int] = [:]
        let all = tracks.enumerated().map { index, track -> DetailTrackEntry in
            if let setVideoId = track.setVideoId, !setVideoId.isEmpty {
                let ordinal = ordinals[setVideoId, default: 0]
                ordinals[setVideoId] = ordinal + 1
                return DetailTrackEntry(originalIndex: index, track: track,
                                        id: DetailTrackEntry.identity(track: track, index: index, duplicateOrdinal: ordinal))
            }
            return DetailTrackEntry(originalIndex: index, track: track)
        }

        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let filtered = needle.isEmpty ? all : all.filter { entry in
            [entry.track.title, entry.track.displayArtist, entry.track.displayAlbum ?? ""]
                .contains { normalized($0).contains(needle) }
        }

        switch order {
        case .custom, .recentlyAdded, .oldestAdded:
            if order == .custom, let customOrder {
                let rank = Dictionary(customOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
                return filtered.sorted {
                    let left = rank[$0.originalIndex] ?? Int.max
                    let right = rank[$1.originalIndex] ?? Int.max
                    return left == right ? $0.originalIndex < $1.originalIndex : left < right
                }
            }
            return filtered
        case .title:
            return stableSort(filtered) { normalized($0.track.title).localizedStandardCompare(normalized($1.track.title)) }
        case .artist:
            return stableSort(filtered) { normalized($0.track.displayArtist).localizedStandardCompare(normalized($1.track.displayArtist)) }
        case .album:
            return stableSort(filtered) { normalized($0.track.displayAlbum ?? "").localizedStandardCompare(normalized($1.track.displayAlbum ?? "")) }
        case .duration:
            return stableSort(filtered) { lhs, rhs in
                switch (seconds(lhs.track.duration), seconds(rhs.track.duration)) {
                case let (a?, b?): return a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
                case (_?, nil): return .orderedAscending
                case (nil, _?): return .orderedDescending
                case (nil, nil): return .orderedSame
                }
            }
        }
    }

    private static func stableSort(
        _ entries: [DetailTrackEntry],
        by compare: (DetailTrackEntry, DetailTrackEntry) -> ComparisonResult
    ) -> [DetailTrackEntry] {
        entries.sorted {
            let result = compare($0, $1)
            return result == .orderedSame ? $0.originalIndex < $1.originalIndex : result == .orderedAscending
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func seconds(_ duration: String?) -> Int? {
        guard let duration else { return nil }
        let parts = duration.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count, values.allSatisfy({ $0 >= 0 }),
              values.dropFirst().allSatisfy({ (0..<60).contains($0) }) else { return nil }
        if values.count == 2 { return values[0] * 60 + values[1] }
        return values[0] * 3600 + values[1] * 60 + values[2]
    }
}
