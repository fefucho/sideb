import CryptoKit
import Foundation
import Testing
import SideBCore
@testable import SideB

private func recentSong(_ id: String, upload: Bool = false) -> SongItemRecord {
    SongItemRecord(videoId: id, title: id, artists: "Artist", album: nil, duration: nil, thumbnail: nil,
        artistId: nil, albumId: nil, setVideoId: "NEVER-SAVE", isVideo: false, isUpload: upload, library: nil, artistRuns: [])
}
private func recentDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("sideb-search-test-" + UUID().uuidString) }

@Test @MainActor func recentQueriesShareUnicodeFixtureAndIntentSemantics() throws {
    let directory = recentDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let store = SearchRecentStore(directory: directory)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("windows/scripts/fixtures/search-recents-behavior.json"))) as? [String: Any])
    let queries = try #require(fixture["queries"] as? [[String: String]])
    for row in queries {
        store.recordQuery(try #require(row["input"]))
        #expect(store.entries.first?.key == row["key"])
        #expect(store.entries.first?.query == row["visible"])
    }
    #expect(store.entries.count == 3)
    for index in 0..<60 { store.recordQuery(String(index)) }
    #expect(store.entries.count == 50)
    #expect(store.entries.first?.query == "59")
    #expect(SearchOrigin.submit.recordsHistory)
    #expect(SearchOrigin.recentQuery.recordsHistory)
    #expect(!SearchOrigin.navigationRestore.recordsHistory)
    #expect(!SearchOrigin.refresh.recordsHistory)
    #expect(!SearchOrigin.artistResolution.recordsHistory)
}

@Test @MainActor func recentTrackConfirmationRejectsReplacedCancelledAndWrongAccount() {
    let directory = recentDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let store = SearchRecentStore(directory: directory)
    let first = store.beginTrack(recentSong("first"))
    let second = store.beginTrack(recentSong("second"))
    store.confirmTrack(first, videoId: "first")
    #expect(store.entries.isEmpty)
    store.confirmTrack(second, videoId: "wrong")
    #expect(store.entries.isEmpty)
    store.setAccount("guest") // Repeated account publication must preserve the accepted intent.
    store.confirmTrack(second, videoId: "second")
    #expect(store.entries.first?.track?.song.videoId == "second")
    store.confirmTrack(second, videoId: "second")
    #expect(store.entries.count == 1)
    let cancelled = store.beginTrack(recentSong("cancelled")); store.cancelTrack(cancelled)
    store.confirmTrack(cancelled, videoId: "cancelled")
    #expect(store.entries.count == 1)
    let failed = store.beginTrack(recentSong("failed")); store.failTrack(failed)
    #expect(store.unavailableTrack?.song.videoId == "failed")
    #expect(store.entries.count == 1)
    let account = store.beginTrack(recentSong("account")); store.setAccount("account:other")
    store.confirmTrack(account, videoId: "account")
    #expect(store.entries.isEmpty)
    store.setAccount("guest")
    #expect(store.entries.first?.track?.song.videoId == "second")
}

@Test @MainActor func recentPersistenceUndoAndUploadNamespace() throws {
    let directory = recentDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let store = SearchRecentStore(directory: directory)
    store.recordQuery("query")
    let song = store.beginTrack(recentSong("song")); store.confirmTrack(song, videoId: "song")
    let upload = store.beginTrack(recentSong("song", upload: true)); store.confirmTrack(upload, videoId: "song")
    #expect(store.entries.count == 3)
    store.remove(store.entries[0].key); #expect(store.entries.count == 2)
    store.undo(); #expect(store.entries.count == 3)
    store.clear(); #expect(store.entries.isEmpty); #expect(store.canUndo)
    store.undo()
    let reopened = SearchRecentStore(directory: directory)
    #expect(reopened.entries.count == 3)
    let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
    let payload = try String(contentsOf: file, encoding: .utf8)
    #expect(!payload.contains("NEVER-SAVE"))
    let corrupt: [String: Any] = ["version": 1, "entries": [["kind": "query", "key": "incorrect", "query": "valid", "lastUsedAt": 1], ["kind": "track", "key": "bad", "lastUsedAt": 2]]]
    try JSONSerialization.data(withJSONObject: corrupt).write(to: file)
    let recovered = SearchRecentStore(directory: directory)
    #expect(recovered.entries.count == 1)
    #expect(recovered.entries.first?.query == "valid")
}

@Test @MainActor func recentSharedStoreSerializesWindowDecisions() {
    let directory = recentDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let windowA = SearchRecentStore(directory: directory)
    let windowB = windowA // Production windows use shared, never two independent writers.
    windowA.recordQuery("first"); windowB.recordQuery("second")
    #expect(windowA.entries.map(\.query) == ["second", "first"])
}

@Test func searchProjectionCapsAssociatedTracksBeforeOtherSections() {
    func card(_ kind: String, _ id: String) -> BrowseCardRecord { BrowseCardRecord(kind: kind, id: id, title: id, subtitle: nil, thumbnail: nil, duration: nil) }
    let mixed = SearchResultsRecord(topSongs: [recentSong("hero"), recentSong("a"), recentSong("b"), recentSong("c"), recentSong("d")], top: [card("song", "hero")], songs: [recentSong("hero"), recentSong("a"), recentSong("d"), recentSong("e")], albums: [card("album", "album")], artists: [card("artist", "artist")], playlists: [])
    let projection = SearchProjection.make(mixed, budget: 8)
    #expect(projection.topSongs.map(\.videoId) == ["a", "b", "c"])
    #expect(projection.songs.map(\.videoId) == ["d", "e"])
    #expect(projection.artists.count == 1)
    #expect(projection.albums.count == 1)
}

private final class StoreClock { var seconds = 1_000.0 }
private func entityCard(_ kind: String, _ id: String) -> BrowseCardRecord {
    BrowseCardRecord(kind: kind, id: id, title: "T \(id)", subtitle: "S \(id)", thumbnail: "thumb", duration: nil)
}

@Test @MainActor func openedEntitiesPersistDeduplicateAndReloadWithTheirCard() throws {
    let directory = recentDirectory(), clock = StoreClock()
    let store = SearchRecentStore(directory: directory, now: { Date(timeIntervalSince1970: clock.seconds) })
    store.recordEntity(entityCard("artist", "a1")); clock.seconds += 1
    store.recordEntity(entityCard("album", "b1")); clock.seconds += 1
    store.recordEntity(entityCard("artist", "a1")); clock.seconds += 1   // reopened: moves up, no duplicate
    store.recordEntity(entityCard("song", "s1"))                         // songs enter only through confirmed playback
    store.recordEntity(entityCard("playlist", ""))                       // no id: nothing to reopen
    #expect(store.entries.map(\.key) == ["entity:artist:a1", "entity:album:b1"])

    let reloaded = SearchRecentStore(directory: directory)
    #expect(reloaded.entries.map(\.key) == ["entity:artist:a1", "entity:album:b1"])
    #expect(reloaded.entries.first?.card?.title == "T a1")
    #expect(reloaded.entries.first?.card?.record.kind == "artist")

    reloaded.remove("entity:album:b1")
    #expect(reloaded.entries.count == 1 && reloaded.canUndo)
    reloaded.undo()
    #expect(reloaded.entries.count == 2)
    reloaded.clear()
    #expect(reloaded.entries.isEmpty)
}

@Test @MainActor func filesWithoutEntitiesStillLoadAndMalformedEntitiesAreDropped() throws {
    let directory = recentDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = SearchRecentStore(directory: directory)
    let digest = SHA256.hash(data: Data(store.accountIdentity.utf8)).map { String(format: "%02x", $0) }.joined()
    let file = directory.appendingPathComponent(digest + ".json")
    let json = """
    {"version":1,"entries":[
      {"key":"query:old","kind":"query","lastUsedAt":3,"query":"old"},
      {"key":"x","kind":"artist","lastUsedAt":2},
      {"key":"y","kind":"planet","lastUsedAt":1,"card":{"kind":"planet","id":"p","title":"P"}},
      {"key":"z","kind":"album","lastUsedAt":4,"card":{"kind":"album","id":"b","title":"B"}}]}
    """
    try json.write(to: file, atomically: true, encoding: .utf8)
    let reloaded = SearchRecentStore(directory: directory)
    #expect(reloaded.entries.map(\.key) == ["entity:album:b", "query:old"],
            "a query-only legacy file keeps working; an entity without its card or an unknown kind is ignored")
}
