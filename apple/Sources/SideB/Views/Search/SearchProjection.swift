import Foundation
import SideBCore

/// A deterministic projection; provider order within a category remains intact.
enum SearchProjection {
    /// Artist top-result shelves can omit repeated credits in their associated song rows.
    /// Restore only missing credits; never replace a song's own collaborators or playback tokens.
    static func associatedSong(_ source: SongItemRecord, in results: SearchResultsRecord) -> SongItemRecord {
        var song = source
        func hasText(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !hasText(song.artists), song.artistRuns.isEmpty,
           let complete = results.songs.first(where: {
               $0.videoId == song.videoId && $0.isVideo == song.isVideo && (hasText($0.artists) || !$0.artistRuns.isEmpty)
           }) {
            song.artists = complete.artists
            song.artistRuns = complete.artistRuns
            song.artistId = song.artistId ?? complete.artistId
        }
        if !hasText(song.artists), !song.artistRuns.isEmpty {
            song.artists = song.artistRuns.map(\.text).joined()
        }
        if !hasText(song.artists), song.artistRuns.isEmpty,
           let artist = results.top.first, artist.kind.lowercased() == "artist", hasText(artist.title),
           song.artistId == nil || song.artistId == artist.id {
            song.artists = artist.title
            song.artistId = artist.id
            song.artistRuns = [HomeArtistRunRecord(text: artist.title, id: artist.id)]
        }
        return song
    }

    static func originalSongs(_ source: SearchResultsRecord) -> [SongItemRecord] {
        var seen = Set<String>()
        let payloads = source.topSongs + source.songs
        let primary = source.top.filter { ["song", "video"].contains($0.kind.lowercased()) }.map { card in
            payloads.first { $0.videoId == card.id } ?? SongItemRecord(fromCard: card)
        }
        return (primary + payloads).filter { seen.insert(($0.isVideo ? "video:" : "song:") + $0.videoId).inserted }
    }

    static func originalCards(_ source: SearchResultsRecord, kind: String) -> [BrowseCardRecord] {
        var seen = Set<String>()
        let category: [BrowseCardRecord]
        switch kind { case "artist": category = source.artists; case "album": category = source.albums; default: category = source.playlists }
        return (source.top.filter { $0.kind.lowercased() == kind } + category).filter { seen.insert($0.searchEntityKey).inserted }
    }

    /// Autocomplete cards are already ordered by the provider. Typed tracks are payloads
    /// for those same cards, rather than a related-songs shelf under the first result.
    static func suggestions(_ source: SearchResultsRecord, budget: Int = 8) -> SearchResultsRecord {
        var seen = Set<String>()
        let cards = Array(source.top.filter { !$0.id.isEmpty && seen.insert($0.searchEntityKey).inserted }.prefix(max(0, budget)))
        let trackIDs = Set(cards.filter { ["song", "video"].contains($0.kind.lowercased()) }.map(\.id))
        let tracks = source.topSongs.filter { trackIDs.contains($0.videoId) }
        return SearchResultsRecord(topSongs: tracks, top: cards, songs: [], albums: [], artists: [], playlists: [])
    }

    static func make(_ source: SearchResultsRecord, budget: Int = .max) -> SearchResultsRecord {
        var seen = Set<String>(); var remaining = budget
        func cards(_ values: [BrowseCardRecord]) -> [BrowseCardRecord] {
            values.filter { item in
                let payload = (source.topSongs + source.songs).first { $0.videoId == item.id }
                let key = ["song", "video"].contains(item.kind.lowercased())
                    ? payload.map { ($0.isVideo ? "video:" : "song:") + $0.videoId } ?? item.searchEntityKey
                    : item.searchEntityKey
                guard !item.id.isEmpty, remaining > 0, seen.insert(key).inserted else { return false }
                remaining -= 1; return true
            }
        }
        func songs(_ values: [SongItemRecord]) -> [SongItemRecord] {
            values.filter { item in
                guard !item.videoId.isEmpty, remaining > 0,
                    seen.insert((item.isVideo ? "video:" : "song:") + item.videoId).inserted else { return false }
                remaining -= 1; return true
            }
        }
        let top = cards(Array(source.top.prefix(1)))
        let associated = songs(Array(source.topSongs.map { associatedSong($0, in: source) }.filter { !seen.contains(($0.isVideo ? "video:" : "song:") + $0.videoId) }.prefix(3)))
        let tracks = songs(source.songs)
        let artists = cards(source.artists)
        let albums = cards(source.albums)
        let playlists = cards(source.playlists)
        return SearchResultsRecord(topSongs: Array(associated), top: top, songs: tracks, albums: albums, artists: artists, playlists: playlists)
    }
}

extension BrowseCardRecord {
    var searchEntityKey: String { kind.lowercased() + ":" + id }
}
