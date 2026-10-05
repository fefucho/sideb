import Testing
import SideBCore
@testable import SideB

private func detailProjectionTrack(_ id: String, title: String, artist: String = "Artista", album: String? = nil,
                                  duration: String? = nil, setID: String? = nil) -> SongItemRecord {
    SongItemRecord(videoId: id, title: title, artists: artist, album: album, duration: duration,
                   thumbnail: nil, artistId: nil, albumId: nil, setVideoId: setID,
                   isVideo: false, isUpload: false, library: nil, artistRuns: [])
}

@Test func detailProjectionFiltersDiacriticsAcrossTrackCreditsAndPreservesDuplicateOccurrences() {
    let tracks = [
        detailProjectionTrack("a", title: "Canción", artist: "José", album: "Verano", setID: "occurrence-a"),
        detailProjectionTrack("a", title: "Cancion", artist: "Jose", album: "Invierno", setID: "occurrence-b"),
        detailProjectionTrack("b", title: "Otra", artist: "Luz", album: "Verano")
    ]
    let byArtist = DetailTrackProjection.make(tracks: tracks, query: "JOSE", order: .custom)
    #expect(byArtist.map(\.originalIndex) == [0, 1])
    #expect(byArtist[0].id != byArtist[1].id)
    #expect(DetailTrackProjection.make(tracks: tracks, query: "veráno", order: .custom).map(\.originalIndex) == [0, 2])
}

@Test func detailProjectionSortsDurationNumericallyKeepsTiesStableAndPutsUnknownLast() {
    let tracks = [
        detailProjectionTrack("a", title: "Unknown", duration: nil),
        detailProjectionTrack("b", title: "Long", duration: "1:02:03"),
        detailProjectionTrack("c", title: "Short", duration: "9:08"),
        detailProjectionTrack("d", title: "Same", duration: "09:08"),
        detailProjectionTrack("e", title: "Bad", duration: "3:99")
    ]
    #expect(DetailTrackProjection.make(tracks: tracks, query: "", order: .duration).map(\.originalIndex) == [2, 3, 1, 0, 4])
}

@Test func customProjectionUsesOriginalOrderAndOnlySupportedOrdersAreExposed() {
    let tracks = [detailProjectionTrack("a", title: "A"), detailProjectionTrack("b", title: "B")]
    #expect(DetailTrackProjection.make(tracks: tracks, query: "", order: .custom).map(\.originalIndex) == [0, 1])
    #expect(DetailTrackOrder.allCases.map(\.rawValue) == ["custom", "title", "artist", "album", "recentlyAdded", "oldestAdded", "duration"])
}
