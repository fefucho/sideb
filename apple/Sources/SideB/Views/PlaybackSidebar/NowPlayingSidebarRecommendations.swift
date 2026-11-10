import SwiftUI
import AppKit
import SideBCore

/// An individually identifiable item in a recommended song shelf.
struct SidebarRecommendedItem: Identifiable, Equatable, Sendable {
    let id: String
    let shelf: String
    let index: Int
    let track: SongItemRecord

    init(shelf: String, index: Int, track: SongItemRecord) {
        self.id = "\(shelf)-\(index)-\(track.videoId)"
        self.shelf = shelf
        self.index = index
        self.track = track
    }
}

/// Prepared content for the recommendations shelves, created once per data revision.
struct PreparedSidebarRecommendations: Equatable {
    let revisionId: String
    let artists: [BrowseCardRecord]
    let similarSongs: [SidebarRecommendedItem]
    let artistSongs: [SidebarRecommendedItem]
    let albumSongs: [SidebarRecommendedItem]
    let artistName: String?
    let artistBrowseId: String?
    let albumTitle: String?
    let albumBrowseId: String?

    init(data: RecommendedData, maxPerShelf: Int = 10) {
        self.revisionId = data.loadedVideoId ?? ""
        self.artists = Array(data.relatedArtists.prefix(maxPerShelf))
        self.similarSongs = data.similarSongs.prefix(maxPerShelf).enumerated().map { idx, song in
            SidebarRecommendedItem(shelf: "similar", index: idx, track: song)
        }
        self.artistSongs = data.artistSongs.prefix(maxPerShelf).enumerated().map { idx, song in
            SidebarRecommendedItem(shelf: "artist", index: idx, track: song)
        }
        self.albumSongs = data.albumSongs.prefix(maxPerShelf).enumerated().map { idx, song in
            SidebarRecommendedItem(shelf: "album", index: idx, track: song)
        }
        self.artistName = data.artistName
        self.artistBrowseId = data.artistBrowseId
        self.albumTitle = data.albumTitle
        self.albumBrowseId = data.albumBrowseId
    }

    var isEmpty: Bool {
        artists.isEmpty && similarSongs.isEmpty && artistSongs.isEmpty && albumSongs.isEmpty
    }
}
