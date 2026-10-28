import Foundation
import SideBCore

/// Structural roles are accepted only when they identify one coherent block in this section.
/// Item indices are occurrence indices; card IDs are deliberately never used to infer a role.
struct ProviderSearchSectionRoles: Equatable {
    let primaryIndex: Int
    let relatedIndices: [Int]
}

enum ProviderSearchPrincipalLayout: Equatable {
    case fullStrip
    case artistStacked
    case artistRelatedBelow
    case artistSplit
}

/// Compatibility only: provider presentation consumes its ordered entries/sections directly.
/// This adapter keeps older navigation and playback helpers working during migration.
enum ProviderSearchProjection {
    static func roles(for section: SearchSectionRecord) -> ProviderSearchSectionRoles? {
        guard section.layout == "top", let rawPrimary = section.primaryItemIndex else { return nil }
        let primary = Int(rawPrimary)
        let related = section.relatedItemIndices.map(Int.init)
        guard section.items.indices.contains(primary),
              ["song", "video", "album", "artist", "playlist"].contains(section.items[primary].kind),
              Set(related).count == related.count,
              related == related.sorted(), related.allSatisfy({ $0 > primary }),
              !related.contains(primary),
              related.allSatisfy(section.items.indices.contains) else { return nil }
        return ProviderSearchSectionRoles(primaryIndex: primary, relatedIndices: related)
    }

    static func principalLayout(kind: String, hasRelated: Bool, width: CGFloat) -> ProviderSearchPrincipalLayout {
        guard kind == "artist", hasRelated else { return .fullStrip }
        if width >= 960 { return .artistSplit }
        if width >= 680 { return .artistRelatedBelow }
        return .artistStacked
    }

    /// Associates song payloads by their occurrence position in the media-card sequence.
    /// An ID lookup is allowed only when it has exactly one candidate, avoiding cross-wiring
    /// duplicate video IDs with distinct setVideoId / playback payloads.
    static func song(for cardIndex: Int, in section: SearchSectionRecord) -> SongItemRecord? {
        songsByItemIndex(in: section)[cardIndex]
    }

    /// Prepares every song/video occurrence once so row builders can do an O(1) lookup.
    /// Payloads first pair by their ordinal among media cards, preserving duplicate IDs with
    /// different setVideoId values. A mismatched ordinal falls back to an ID only when unique.
    static func songsByItemIndex(in section: SearchSectionRecord) -> [Int: SongItemRecord] {
        var payloadCounts: [String: Int] = [:]
        var uniquePayloadByID: [String: SongItemRecord] = [:]
        for song in section.songs {
            payloadCounts[song.videoId, default: 0] += 1
            uniquePayloadByID[song.videoId] = song
        }

        var result: [Int: SongItemRecord] = [:]
        result.reserveCapacity(min(section.items.count, section.songs.count))
        var mediaPosition = 0
        for (itemIndex, card) in section.items.enumerated() where ["song", "video"].contains(card.kind) {
            if section.songs.indices.contains(mediaPosition),
               section.songs[mediaPosition].videoId == card.id {
                result[itemIndex] = section.songs[mediaPosition]
            } else if payloadCounts[card.id] == 1, let uniqueMatch = uniquePayloadByID[card.id] {
                result[itemIndex] = uniqueMatch
            } else {
                result[itemIndex] = SongItemRecord(fromCard: card)
            }
            if let song = result[itemIndex] { result[itemIndex] = mergingRating(song, from: card) }
            mediaPosition += 1
        }
        return result
    }

    /// A known rating belongs to this exact recording, never to a neighbouring occurrence.
    static func mergingRating(_ song: SongItemRecord, from card: BrowseCardRecord) -> SongItemRecord {
        guard song.videoId == card.id, song.contentRating == .unknown else { return song }
        var result = song
        result.contentRating = card.contentRating
        return result
    }

    static func song(for entry: SearchSuggestionEntryRecord) -> SongItemRecord? {
        guard let song = entry.song else { return nil }
        return entry.card.map { mergingRating(song, from: $0) } ?? song
    }

    static func displayCard(_ card: BrowseCardRecord, song: SongItemRecord?) -> BrowseCardRecord {
        guard let song, song.videoId == card.id, card.contentRating == .unknown else { return card }
        var result = card
        result.contentRating = song.contentRating
        return result
    }

    static func results(entries: [SearchSuggestionEntryRecord]) -> SearchResultsRecord {
        SearchResultsRecord(topSongs: entries.compactMap { song(for: $0) }, top: entries.compactMap(\.card),
                            songs: [], albums: [], artists: [], playlists: [])
    }

    static func results(page: SearchPageRecord) -> SearchResultsRecord {
        var top: [BrowseCardRecord] = [], topSongs: [SongItemRecord] = [], songs: [SongItemRecord] = []
        var albums: [BrowseCardRecord] = [], artists: [BrowseCardRecord] = [], playlists: [BrowseCardRecord] = []
        for section in page.sections {
            if section.layout == "top" { top += section.items; topSongs += section.songs; continue }
            songs += section.songs
            albums += section.items.filter { $0.kind == "album" }
            artists += section.items.filter { $0.kind == "artist" }
            playlists += section.items.filter { $0.kind == "playlist" }
        }
        return SearchResultsRecord(topSongs: topSongs, top: top, songs: songs,
                                   albums: albums, artists: artists, playlists: playlists)
    }

    static func appending(_ next: SearchPageRecord, to page: SearchPageRecord,
                          consumedTokens: Set<String>) -> SearchPageRecord {
        // Continuations may restart section indices; keep every occurrence and assign page IDs.
        let offset = page.sections.count
        let sections = next.sections.enumerated().map { index, section in
            SearchSectionRecord(id: "page:\(offset):\(index):\(section.id)", title: section.title,
                layout: section.layout, items: section.items, songs: section.songs,
                primaryItemIndex: section.primaryItemIndex, relatedItemIndices: section.relatedItemIndices,
                moreQuery: section.moreQuery, moreParams: section.moreParams,
                moreBrowseId: section.moreBrowseId, actions: section.actions)
        }
        let token = next.continuation.flatMap { consumedTokens.contains($0) ? nil : $0 }
        return SearchPageRecord(chips: page.chips, correction: page.correction,
                                sections: page.sections + sections, continuation: token)
    }
}

extension SearchSuggestionEntryRecord {
    var displayTitle: String { card?.title ?? query ?? runs.map(\.text).joined() }
}
