import Foundation
import SideBCore
import Testing
@testable import SideB

@Suite("Jam: queue mapping and edits")
struct JamQueueMappingTests {
    @Test("Rows map to the Jam indices of the matched tracks only")
    func rowsSkipUnmatched() {
        let map = JamQueueMapping(matched: [true, false, true, true, false])
        #expect(map.rowCount == 3)
        #expect(map.jamIndex(forRow: 0) == 0)
        #expect(map.jamIndex(forRow: 1) == 2)
        #expect(map.jamIndex(forRow: 2) == 3)
        #expect(map.jamIndex(forRow: 3) == nil)
        #expect(map.row(forJamIndex: 3) == 2)
        #expect(map.row(forJamIndex: 1) == nil)
    }

    @Test("Insertion lands before the Jam track of that row, or at the end")
    func insertion() {
        let map = JamQueueMapping(matched: [false, true, false, true, false])
        #expect(map.insertionJamIndex(atRow: 0) == 1)
        #expect(map.insertionJamIndex(atRow: 1) == 3)
        #expect(map.insertionJamIndex(atRow: 2) == 5)
        #expect(map.insertionJamIndex(atRow: 9) == 5)
        #expect(JamQueueMapping(matched: []).insertionJamIndex(atRow: 0) == 0)
    }

    @Test("Moving a row takes the Jam slot of the row it displaces")
    func moves() {
        let map = JamQueueMapping(matched: [true, false, true, false, true])
        #expect(map.move(fromRow: 0, toRow: 2)?.from == 0)
        #expect(map.move(fromRow: 0, toRow: 2)?.to == 4)
        #expect(map.move(fromRow: 2, toRow: 1)?.from == 4)
        #expect(map.move(fromRow: 2, toRow: 1)?.to == 2)
        #expect(map.move(fromRow: 1, toRow: 1) == nil)
        #expect(map.move(fromRow: 0, toRow: 7) == nil)
    }

    @Test("Entry ids stay distinct for repeated tracks")
    func entryIDs() {
        #expect(JamQueueMapping.entryIDs(for: ["a", "b", "a"]) == ["a#0", "b#0", "a#1"])
    }

    @Test("Edits are applied only when the next state shows them")
    func satisfaction() {
        let old = ["a", "b", "c", "d"]
        #expect(JamQueueEdit.move(from: 0, to: 2).isSatisfied(old: old, new: ["b", "c", "a", "d"]))
        #expect(!JamQueueEdit.move(from: 0, to: 2).isSatisfied(old: old, new: old))
        #expect(JamQueueEdit.remove(index: 1).isSatisfied(old: old, new: ["a", "c", "d"]))
        #expect(!JamQueueEdit.remove(index: 1).isSatisfied(old: old, new: old))
        #expect(JamQueueEdit.insert(uri: "x", index: 1).isSatisfied(old: old, new: ["a", "x", "b", "c", "d"]))
        #expect(!JamQueueEdit.insert(uri: "x", index: 1).isSatisfied(old: old, new: ["a", "b", "x", "c", "d"]))
        #expect(JamQueueEdit.insert(uri: "x", index: 4).isSatisfied(old: old, new: old + ["x"]))
        #expect(JamQueueEdit.add(uri: "x").isSatisfied(old: old, new: ["a", "x", "b", "c", "d"]))
        #expect(!JamQueueEdit.add(uri: "x").isSatisfied(old: old, new: old))
    }

    @Test("Edits outside the queue are not sent; commands carry revision and request id")
    func commands() {
        let queue = ["a", "b"]
        #expect(!JamQueueEdit.remove(index: 2).isValid(on: queue))
        #expect(!JamQueueEdit.move(from: 0, to: 2).isValid(on: queue))
        #expect(JamQueueEdit.insert(uri: "x", index: 2).isValid(on: queue))
        let move = JamQueueEdit.move(from: 0, to: 1).command(revision: "r7", requestId: "q1")
        #expect(move["action"] as? String == "move")
        #expect(move["from"] as? Int == 0)
        #expect(move["to"] as? Int == 1)
        #expect(move["revision"] as? String == "r7")
        #expect(move["requestId"] as? String == "q1")
        let add = JamQueueEdit.add(uri: "spotify:track:1").command(revision: nil, requestId: "q2")
        #expect(add["uri"] as? String == "spotify:track:1")
        #expect(add["revision"] == nil)
    }
}

@Suite("Jam: plugin events")
struct JamEventDecodingTests {
    private func decode(_ json: String) throws -> JamEvent {
        try JSONDecoder().decode(JamEvent.self, from: Data(json.utf8))
    }

    @Test("State carries the whole queue, providers and the revision")
    func state() throws {
        let event = try decode(#"""
        {"type":"state","queueRevision":"rev-9","queue":[
          {"uri":"spotify:track:1","title":"A","artists":["X"],"album":null,"durationMs":1000,"isrc":null,"provider":"queue"},
          {"uri":"spotify:track:2","title":"B","artists":[],"provider":"enhanced_recommendation"}]}
        """#)
        #expect(event.queueRevision == "rev-9")
        #expect(event.queue?.count == 2)
        #expect(event.queue?[0].isAddedByPerson == true)
        #expect(event.queue?[1].isAddedByPerson == false)
    }

    @Test("Resolved reply, with and without a match")
    func resolved() throws {
        let hit = try decode(#"{"type":"resolved","requestId":"r1","uri":"spotify:track:9","title":"T","artists":["A"],"durationMs":200000}"#)
        #expect(hit.requestId == "r1")
        #expect(JamResolved(event: hit)?.uri == "spotify:track:9")
        #expect(JamResolved(event: hit)?.artists == ["A"])
        let miss = try decode(#"{"type":"resolved","requestId":"r2","uri":null}"#)
        #expect(miss.requestId == "r2")
        #expect(JamResolved(event: miss) == nil)
    }

    @Test("Command result keeps the request id and the stale detail")
    func commandResult() throws {
        let event = try decode(#"{"type":"commandResult","action":"move","ok":false,"detail":"stale","requestId":"q1"}"#)
        #expect(event.requestId == "q1")
        #expect(event.detail == "stale")
        #expect(event.ok == false)
    }
}

private func song(_ id: String) -> SongItemRecord {
    SongItemRecord(videoId: id, title: "T \(id)", artists: "Artist", album: nil, duration: nil, thumbnail: nil,
                   artistId: nil, albumId: nil, setVideoId: nil, isVideo: false, isUpload: false, library: nil)
}

@MainActor
private final class FakeEditor: QueueSessionEditing {
    var log: [String] = []
    func sessionAppend(_ tracks: [SongItemRecord]) { log.append("append \(tracks.map(\.videoId))") }
    func sessionInsert(_ tracks: [SongItemRecord], atUpcomingRow row: Int) { log.append("insert \(tracks.map(\.videoId)) @\(row)") }
    func sessionMove(fromUpcomingRow from: Int, toUpcomingRow to: Int) { log.append("move \(from)->\(to)") }
    func sessionRemove(upcomingRow row: Int) { log.append("remove \(row)") }
    func sessionRejected(_ reason: QueueSessionRejection) { log.append("rejected \(reason)") }
}

@Suite("Jam: session-owned queue")
@MainActor
struct JamQueueSessionTests {
    private func lockedManager(_ editor: FakeEditor) -> QueueManager {
        let manager = QueueManager()
        manager.mirrorSession(current: song("c"), upcoming: ["a", "b", "d"].map(song), title: "Spotify Jam")
        manager.sessionEditor = editor
        return manager
    }

    @Test("Mirroring keeps the identity of unchanged rows and of the current item")
    func mirrorKeepsIdentity() {
        let manager = QueueManager()
        manager.mirrorSession(current: song("c"), upcoming: ["a", "b"].map(song), title: "Spotify Jam")
        let ids = manager.occurrenceIDs
        manager.mirrorSession(current: song("c"), upcoming: ["a", "x", "b"].map(song), title: "Spotify Jam")
        #expect(manager.queue.map(\.videoId) == ["c", "a", "x", "b"])
        #expect(manager.occurrenceIDs[0] == ids[0])
        #expect(manager.occurrenceIDs[1] == ids[1])
        #expect(manager.occurrenceIDs[3] == ids[2])
        #expect(manager.currentIndex == 0)
        // The Jam advances: what was first upcoming becomes the current item and keeps its row.
        let before = manager.occurrenceIDs
        manager.mirrorSession(current: song("a"), upcoming: ["x", "b"].map(song), title: "Spotify Jam")
        #expect(manager.queue.map(\.videoId) == ["a", "x", "b"])
        #expect(manager.occurrenceIDs == [before[1], before[2], before[3]])
    }

    @Test("Edit entry points are handed to the session and leave the local queue alone")
    func editsAreRouted() {
        let editor = FakeEditor()
        let manager = lockedManager(editor)
        let ids = manager.occurrenceIDs
        manager.playNext([song("n")])
        manager.addTracksToQueue([song("e")])
        manager.moveTrack(from: 1, to: 3)
        _ = manager.removeTrack(at: 2)
        _ = manager.removeTrack(at: 0)
        _ = manager.placeQueueOccurrence(id: ids[1], beforeID: ids[3])
        _ = manager.placeQueueOccurrence(id: ids[0], beforeID: nil)
        #expect(editor.log == ["insert [\"n\"] @0", "append [\"e\"]", "move 0->2", "remove 1", "rejected removeCurrent",
                               "move 0->1", "insert [\"c\"] @3"])
        #expect(manager.queue.map(\.videoId) == ["c", "a", "b", "d"])
    }

    @Test("Shuffle and repeat stay off during a session")
    func shuffleAndRepeatInert() {
        let editor = FakeEditor()
        let manager = lockedManager(editor)
        manager.toggleShuffle()
        manager.isRepeat = true
        #expect(!manager.isShuffle)
        #expect(!manager.isRepeat)
        #expect(editor.log == ["rejected shuffleRepeat", "rejected shuffleRepeat"])
    }

    @Test("Nothing extends the queue while a session owns it")
    func noExtensions() {
        let editor = FakeEditor()
        let manager = lockedManager(editor)
        manager.appendRadioTracks([song("r1")])
        manager.appendPlaylistTracks([song("p1")])
        #expect(manager.queue.map(\.videoId) == ["c", "a", "b", "d"])
        #expect(manager.recommendationEntries.isEmpty)
        withExtendedLifetime(editor) {}
    }

    @Test("Playing something else asks first; the user's session is what gets saved and restored")
    func exitAndSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "SideBJam.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let player = PlayerViewModel(rustCore: nil, audioService: AudioPlayerService(preferences: preferences, preferencePrefix: "jam"),
                                     playbackStore: PlaybackStateStore(directory: directory))
        player.switchPlaybackSession(to: "account:J")
        let own = ["u1", "u2", "u3"].map(song)
        player.queueManager.replaceQueue(with: own, startingAt: 1, context: .album(browseId: "alb", title: "Mi álbum"))
        player.currentTrack = own[1]

        let editor = FakeEditor()
        player.beginJamSession(editor: editor, control: { _ in })
        #expect(player.isJamSessionActive)
        player.queueManager.mirrorSession(current: song("j0"), upcoming: [song("j1")], title: "Spotify Jam")
        player.currentTrack = song("j0")
        player.flushPlaybackState()

        // Persisted: the user's queue, not the Jam's.
        let reader = PlaybackStateStore(directory: directory)
        reader.activate("account:J")
        #expect(reader.load()?.tracks.map(\.videoId) == ["u1", "u2", "u3"])
        #expect(reader.load()?.currentTrack?.videoId == "u2")

        // Starting playback of something else is held back.
        player.playAlbum(browseId: "other", title: "Otro", tracks: [song("o1")])
        #expect(player.pendingJamExit != nil)
        #expect(player.queueManager.queue.map(\.videoId) == ["j0", "j1"])
        player.cancelJamExit()
        #expect(player.pendingJamExit == nil)
        #expect(player.isJamSessionActive)

        // Enqueueing goes to the Jam instead.
        player.addToQueue(song: song("e1"))
        player.playNext(song: song("e2"))
        #expect(editor.log == ["append [\"e1\"]", "insert [\"e2\"] @0"])
        player.playQueueIndex(1)
        #expect(editor.log.last == "rejected playRow")

        // Leaving restores the saved queue and track.
        player.endJamSession(restore: .stateOnly)
        #expect(!player.isJamSessionActive)
        #expect(player.queueManager.queue.map(\.videoId) == ["u1", "u2", "u3"])
        #expect(player.currentTrack?.videoId == "u2")
        #expect(player.queueManager.currentIndex == 1)
        #expect(!player.queueManager.isSessionLocked)

        // Confirming the exit runs the held request.
        player.beginJamSession(editor: editor, control: { _ in })
        player.playAlbum(browseId: "other", title: "Otro", tracks: [song("o1")])
        player.confirmJamExit()
        #expect(!player.isJamSessionActive)
        #expect(player.pendingJamExit == nil)
        #expect(player.queueManager.queue.map(\.videoId) == ["o1"])
    }
}
