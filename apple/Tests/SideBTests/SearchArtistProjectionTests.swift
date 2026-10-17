import Foundation
import Testing
import SideBCore
@testable import SideB

private func associatedTrack(_ id: String, artists: String = "", runs: [HomeArtistRunRecord] = []) -> SongItemRecord {
    SongItemRecord(videoId: id, title: id, artists: artists, album: nil, duration: "3:44", thumbnail: "cover",
        artistId: nil, albumId: nil, setVideoId: "occurrence-\(id)", isVideo: false, isUpload: false, library: nil, artistRuns: runs)
}
private func artistSearch(_ tracks: [SongItemRecord], songs: [SongItemRecord] = [], kind: String = "artist") -> SearchResultsRecord {
    SearchResultsRecord(topSongs: tracks, top: [BrowseCardRecord(kind: kind, id: "UCkanye", title: "Kanye West", subtitle: nil, thumbnail: nil, duration: nil)], songs: songs, albums: [], artists: [], playlists: [])
}

@Test func searchArtistProjectionRestoresImplicitCreditsAndPreservesOrderAndOccurrence() {
    let tracks = [associatedTrack("All Falls Down"), associatedTrack("ALL THE LOVE", artists: "  "), associatedTrack("Stronger")]
    let source = artistSearch(tracks)
    let projected = SearchProjection.make(source, budget: 8)
    #expect(projected.topSongs.map(\.videoId) == tracks.map(\.videoId))
    for (song, original) in zip(projected.topSongs, tracks) {
        #expect(song.artists == "Kanye West")
        #expect(song.artistId == "UCkanye")
        #expect(song.artistRuns == [HomeArtistRunRecord(text: "Kanye West", id: "UCkanye")])
        #expect(song.setVideoId == original.setVideoId)
        #expect(song.duration == original.duration)
        #expect(song.thumbnail == original.thumbnail)
    }
    #expect(source.topSongs == tracks)
    #expect(SearchProjection.make(projected) == projected)
}

@Test func searchArtistProjectionPrefersExplicitCreditsAndMatchingSongMetadata() {
    let runs = [HomeArtistRunRecord(text: "Kanye West", id: "UCkanye"), HomeArtistRunRecord(text: " & ", id: nil), HomeArtistRunRecord(text: "Syleena Johnson", id: "UCsyleena")]
    let explicit = associatedTrack("All Falls Down", artists: "Kanye West & Syleena Johnson", runs: runs)
    let missing = associatedTrack("All Falls Down")
    let projected = SearchProjection.make(artistSearch([missing], songs: [explicit]))
    #expect(projected.topSongs.first?.artistRuns == runs)
    #expect(projected.topSongs.first?.artists == explicit.artists)
    #expect(projected.topSongs.first?.setVideoId == missing.setVideoId)
    #expect(projected.songs.isEmpty)
    #expect(SearchProjection.make(artistSearch([explicit])).topSongs == [explicit])
    #expect(SearchProjection.make(artistSearch([associatedTrack("runs", runs: runs)])).topSongs.first?.artists == "Kanye West & Syleena Johnson")
}

@Test @MainActor func searchAssociatedCreditsReachDropdownAndNeverBorrowCollectionTitles() {
    let source = artistSearch([associatedTrack("Stronger")])
    let model = SearchViewModel()
    #expect(model.relatedSongs(for: source).first?.artists == "Kanye West")
    for kind in ["album", "playlist", "song"] {
        #expect(SearchProjection.make(artistSearch([associatedTrack("Stronger")], kind: kind)).topSongs.first?.artists == "")
    }
    var conflicting = associatedTrack("other")
    conflicting.artistId = "UCother"
    #expect(SearchProjection.make(artistSearch([conflicting])).topSongs.first == conflicting)
}

@Test @MainActor func autocompletePreservesMixedProviderOrderAndTrackCreditsWithoutRelatedDuplicates() {
    let track = associatedTrack("track-first", artists: "Main & Guest", runs: [HomeArtistRunRecord(text: "Main", id: "main"), HomeArtistRunRecord(text: " & ", id: nil), HomeArtistRunRecord(text: "Guest", id: "guest")])
    let cards = [
        BrowseCardRecord(kind: "song", id: track.videoId, title: "Song", subtitle: "Main & Guest", thumbnail: nil, duration: nil),
        BrowseCardRecord(kind: "artist", id: "artist-second", title: "Artist", subtitle: nil, thumbnail: nil, duration: nil),
        BrowseCardRecord(kind: "album", id: "album-third", title: "Album", subtitle: nil, thumbnail: nil, duration: nil)
    ]
    let source = SearchResultsRecord(topSongs: [track, associatedTrack("unaccepted")], top: cards, songs: [], albums: [], artists: [], playlists: [])
    let projected = SearchProjection.suggestions(source)
    #expect(projected.top.map(\.id) == cards.map(\.id))
    #expect(projected.topSongs == [track])
    #expect(projected.songs.isEmpty)
    let model = SearchViewModel()
    #expect(model.song(for: cards[0], in: projected).artistRuns == track.artistRuns)
    #expect(model.song(for: cards[0], in: projected).setVideoId == track.setVideoId)
    #expect(SearchProjection.suggestions(source, budget: 2).top.map(\.id) == ["track-first", "artist-second"])
    #expect(SearchProjection.suggestions(source, budget: 0).top.isEmpty)
}

@Test func originalSearchFiltersKeepPrimaryCardsAndTypedTracks() {
    let track = associatedTrack("primary", artists: "Artist")
    let primary = BrowseCardRecord(kind: "song", id: "primary", title: "Primary", subtitle: nil, thumbnail: nil, duration: nil)
    let artist = BrowseCardRecord(kind: "artist", id: "artist", title: "Artist", subtitle: nil, thumbnail: nil, duration: nil)
    let source = SearchResultsRecord(topSongs: [track], top: [primary, artist], songs: [track], albums: [], artists: [artist], playlists: [])
    #expect(SearchProjection.originalSongs(source) == [track])
    #expect(SearchProjection.originalCards(source, kind: "artist") == [artist])
}

@Test @MainActor func typedVideoPayloadOverridesHistoricalSongCardKindWithoutMetadataLossOrDuplicate() {
    var video = associatedTrack("video", artists: "Actual Artist")
    video.isVideo = true
    let card = BrowseCardRecord(kind: "song", id: "video", title: "Video", subtitle: nil, thumbnail: nil, duration: nil)
    let source = SearchResultsRecord(topSongs: [video], top: [card], songs: [video], albums: [], artists: [], playlists: [])
    let suggestions = SearchProjection.suggestions(source)
    #expect(suggestions.topSongs == [video])
    #expect(SearchViewModel().song(for: card, in: suggestions).isVideo)
    #expect(SearchProjection.originalSongs(source) == [video])
    let catalog = SearchProjection.make(source)
    #expect(catalog.top.count == 1)
    #expect(catalog.topSongs.isEmpty)
    #expect(catalog.songs.isEmpty)
}
