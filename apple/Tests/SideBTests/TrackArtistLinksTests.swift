import Foundation
import Testing
import SideBCore
@testable import SideB

private func collaboration(_ runs: [HomeArtistRunRecord]) -> SongItemRecord {
    SongItemRecord(videoId: "pair", title: "Song", artists: "Future & Metro Boomin", album: nil,
                   duration: nil, thumbnail: nil, artistId: "UCfuture", albumId: nil,
                   setVideoId: nil, isVideo: false, isUpload: false, library: nil, artistRuns: runs)
}

@Test func trackArtistLinksKeepSeparateDestinations() {
    let song = collaboration([
        .init(text: "Future", id: "UCfuture"), .init(text: ", ", id: nil),
        .init(text: "Metro Boomin", id: "UCmetro")
    ])
    #expect(song.displayArtistRuns.map(\.text) == ["Future", " & ", "Metro Boomin"])
    #expect(song.displayArtistRuns.map(\.id) == ["UCfuture", nil, "UCmetro"])
}

@Test func trackArtistLinksPreserveUnlinkedCredits() {
    let song = collaboration([
        .init(text: "Future", id: "UCfuture"), .init(text: " & ", id: nil),
        .init(text: "Metro Boomin", id: nil)
    ])
    #expect(song.displayArtistRuns == song.artistRuns)
}

@Test func trackArtistLinksSurviveRestoringPlayback() throws {
    let song = collaboration([
        .init(text: "Future", id: "UCfuture"), .init(text: " & ", id: nil),
        .init(text: "Metro Boomin", id: "UCmetro")
    ])
    let saved = SavedPlaybackState.Track(song)
    let data = try JSONEncoder().encode(saved)
    #expect(try JSONDecoder().decode(SavedPlaybackState.Track.self, from: data).song == song)
    var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    old.removeValue(forKey: "artistRuns")
    let restored = try JSONDecoder().decode(SavedPlaybackState.Track.self, from: JSONSerialization.data(withJSONObject: old)).song
    #expect(restored.artistRuns.isEmpty)
    #expect(restored.artistId == "UCfuture")
}
