import Testing
import SideBCore
@testable import SideB

@MainActor
private func queueSongs(_ count: Int, prefix: String = "song") -> [SongItemRecord] {
    (0..<count).map { index in
        SongItemRecord(videoId: "\(prefix)-\(index)", title: "Song \(index)", artists: "Artist",
                       album: nil, duration: nil, thumbnail: nil, artistId: nil,
                       albumId: nil, setVideoId: nil, isVideo: false, isUpload: false,
                       library: nil)
    }
}

@MainActor
private func playlistQueue(_ songs: [SongItemRecord], startingAt index: Int = 0) -> QueueManager {
    let manager = QueueManager()
    manager.replaceQueue(with: songs, startingAt: index,
                         context: .playlist(browseId: "playlist", title: "Playlist"))
    return manager
}

@MainActor
@Test func globalShuffleCanStartInLatePlaylistAndOffRestoresCurrentOccurrence() {
    let songs = queueSongs(2_000)
    let manager = QueueManager()
    manager.replaceQueue(with: songs, startingAt: 0,
                         context: .playlist(browseId: "playlist", title: "Playlist"),
                         shuffle: true, shuffleSeed: 0x1234)

    #expect(manager.currentIndex == 0)
    #expect(manager.tracks.count == 100)
    #expect(manager.currentTrack?.videoId == songs[1_616].videoId)
    let shuffledIDs = manager.queue.map(\.videoId)
    #expect(Set(shuffledIDs) == Set(songs.map(\.videoId)))
    #expect(shuffledIDs.count == 2_000)
    let activeID = manager.currentOccurrenceID
    let activeSong = manager.currentTrack

    manager.setShuffle(false)
    #expect(manager.currentOccurrenceID == activeID)
    #expect(manager.currentTrack?.videoId == activeSong?.videoId)
    #expect(manager.currentIndex == Int(activeSong!.videoId.split(separator: "-").last!)!)
    #expect(manager.tracks.count >= min(2_000, manager.currentIndex + 100))
    while manager.nextTrack(isManualSkip: true) != nil {}
    #expect(manager.currentIndex == 1_999)
    #expect(manager.currentTrack?.videoId == songs[1_999].videoId)
}

@MainActor
@Test func duplicateOccurrencesKeepIdentityAcrossShuffleTransitions() {
    let duplicate = queueSongs(1, prefix: "duplicate")[0]
    let songs = [duplicate, duplicate, queueSongs(1, prefix: "tail")[0]]
    let manager = playlistQueue(songs)
    let ids = manager.occurrenceIDs
    #expect(ids.count == 3 && Set(ids).count == 3)

    manager.selectTrack(at: 1)
    let active = manager.currentOccurrenceID
    manager.setShuffle(true, seed: 7)
    manager.setShuffle(false)
    #expect(manager.currentOccurrenceID == active)
    #expect(manager.queue.map(\.videoId) == songs.map(\.videoId))
    #expect(manager.occurrenceIDs == ids)
    manager.setShuffle(true, seed: 9)
    #expect(manager.occurrenceIDs.count == 3)
    #expect(Set(manager.occurrenceIDs) == Set(ids))
}

@MainActor
@Test func playNextAnchorsAndLongManualChainsSurviveRestoreAndDeletion() {
    let manager = playlistQueue(queueSongs(2_000))
    manager.selectTrack(at: 900)
    manager.setShuffle(true, seed: 33)
    let activeID = manager.currentOccurrenceID!
    let manuals = queueSongs(2_000, prefix: "manual")
    manager.playNext(manuals)
    #expect(Array(manager.upNextTracks.prefix(2)).map(\.videoId) == manuals.prefix(2).map(\.videoId))
    let shuffledSnapshot = manager.orderSnapshot
    let shuffledRestore = playlistQueue(manager.queue)
    #expect(shuffledRestore.restoreOrder(shuffledSnapshot, isShuffle: true))
    #expect(shuffledRestore.orderSnapshot == shuffledSnapshot)
    let restoredActiveID = shuffledRestore.currentOccurrenceID
    shuffledRestore.setShuffle(false)
    #expect(shuffledRestore.currentOccurrenceID == restoredActiveID)
    #expect(shuffledRestore.upNextTracks.first?.videoId == manuals.first?.videoId)
    manager.setShuffle(false)
    #expect(manager.currentOccurrenceID == activeID)
    #expect(Array(manager.upNextTracks.prefix(2)).map(\.videoId) == manuals.prefix(2).map(\.videoId))
    #expect(manager.queue.count == 4_000)

    let snapshot = manager.orderSnapshot
    let restored = playlistQueue(manager.queue)
    #expect(restored.restoreOrder(snapshot, isShuffle: false))
    #expect(restored.orderSnapshot == snapshot)
    #expect(restored.currentOccurrenceID == manager.currentOccurrenceID)

    let firstManualID = manager.occurrenceIDs[manager.currentIndex + 2]
    if let firstManualIndex = manager.occurrenceIDs.firstIndex(of: firstManualID) {
        manager.removeTrack(at: firstManualIndex)
    }
    manager.setShuffle(true, seed: 12)
    manager.setShuffle(false)
    #expect(manager.queue.count == 3_999)
    #expect(manager.occurrenceIDs.count == manager.queue.count)
}

@MainActor
@Test func dragPlacementCyclesAndDeleteDoNotLoseOccurrences() {
    let manager = playlistQueue(queueSongs(12))
    manager.setShuffle(true, seed: 100)
    manager.moveTrack(from: 1, to: 5)
    let forwardMovedID = manager.occurrenceIDs[5]
    let forwardAnchorID = manager.occurrenceIDs[6]
    manager.setShuffle(false)
    #expect(manager.occurrenceIDs.firstIndex(of: forwardMovedID).map { $0 + 1 } == manager.occurrenceIDs.firstIndex(of: forwardAnchorID))
    #expect(manager.orderSnapshot.placements[forwardMovedID] == .before(forwardAnchorID))

    manager.setShuffle(true, seed: 100)
    manager.moveTrack(from: 8, to: 2)
    let movedID = manager.occurrenceIDs[2]
    manager.setShuffle(false)
    #expect(manager.occurrenceIDs.contains(movedID))
    #expect(manager.queue.count == 12)

    manager.moveTrack(from: 2, to: 11)
    let movedToEnd = manager.occurrenceIDs.last
    manager.setShuffle(true, seed: 101)
    manager.setShuffle(false)
    #expect(manager.occurrenceIDs.last == movedToEnd)

    let removeID = manager.occurrenceIDs[3]
    manager.removeTrack(at: 3)
    manager.setShuffle(true, seed: 102)
    manager.setShuffle(false)
    #expect(!manager.occurrenceIDs.contains(removeID))
    #expect(manager.queue.count == 11)
}

@MainActor
@Test func nestedPlayNextAnchorsFollowManualActiveAndDetachWhenAnchorIsDeleted() {
    let manager = playlistQueue(queueSongs(8))
    manager.setShuffle(true, seed: 123)
    let firstManual = queueSongs(1, prefix: "first-manual")[0]
    let secondManual = queueSongs(1, prefix: "second-manual")[0]
    manager.playNext(firstManual)
    let firstIndex = manager.queue.firstIndex(where: { $0.videoId == firstManual.videoId })!
    manager.selectTrack(at: firstIndex)
    manager.playNext(secondManual)
    manager.setShuffle(false)
    #expect(manager.currentTrack?.videoId == firstManual.videoId)
    #expect(manager.upNextTracks.first?.videoId == secondManual.videoId)

    manager.removeTrack(at: manager.currentIndex)
    manager.setShuffle(true, seed: 124)
    manager.setShuffle(false)
    #expect(manager.queue.contains(where: { $0.videoId == secondManual.videoId }))
    #expect(manager.occurrenceIDs.count == manager.queue.count)
}

@MainActor
@Test func legacyRestoreDoesNotInventCanonicalRanksAndV2ValidationIsStrict() {
    let songs = queueSongs(4)
    let manager = playlistQueue(songs)
    manager.selectTrack(at: 2)
    manager.setShuffle(true, seed: 5)
    #expect(manager.restoreOrder(nil, isShuffle: true))
    let legacyOrder = manager.queue.map(\.videoId)
    #expect(manager.orderSnapshot.sourceRanks.isEmpty)
    manager.setShuffle(false)
    #expect(manager.queue.map(\.videoId) == legacyOrder)

    let snapshot = manager.orderSnapshot
    let restored = playlistQueue(manager.queue)
    #expect(restored.restoreOrder(snapshot, isShuffle: false))
    #expect(restored.occurrenceIDs == snapshot.occurrenceIDs)

    var invalid = snapshot
    invalid.occurrenceIDs[1] = invalid.occurrenceIDs[0]
    #expect(!restored.restoreOrder(invalid, isShuffle: false))
    invalid = snapshot
    invalid.visibleCount = 99
    #expect(!restored.restoreOrder(invalid, isShuffle: false))
    invalid = snapshot
    invalid.placements[invalid.occurrenceIDs[0]] = .after(invalid.occurrenceIDs[0])
    #expect(!restored.restoreOrder(invalid, isShuffle: false))
}

@MainActor
@Test func playlistPagingAndRadioDedupRespectSourceSemantics() {
    let songs = queueSongs(250)
    let manager = playlistQueue(Array(songs.prefix(100)))
    #expect(manager.tracks.count == 100)
    manager.appendPlaylistTracks(Array(songs.dropFirst(100).prefix(100)), nextContinuation: "next")
    #expect(manager.queue.count == 200)
    #expect(manager.tracks.count == 100)
    manager.selectTrack(at: 89)
    #expect(manager.tracks.count == 200)
    manager.appendPlaylistTracks(Array(songs.dropFirst(200)), nextContinuation: nil)
    while manager.nextTrack(isManualSkip: true) != nil {}
    #expect(manager.queue.count == 250)
    #expect(manager.tracks.count == 250)
    manager.isRepeat = true
    #expect(manager.nextTrack(isManualSkip: true)?.videoId == songs[0].videoId)
    #expect(manager.currentIndex == 0)

    let shortFirstPage = playlistQueue(Array(songs.prefix(3)))
    shortFirstPage.appendPlaylistTracks(Array(songs.dropFirst(3).prefix(100)))
    #expect(shortFirstPage.tracks.count == 100)

    let radio = QueueManager()
    radio.replaceQueue(with: [songs[0]], context: .radio(seedVideoId: "seed", title: "Radio", seedName: "Seed"))
    radio.appendRadioTracks([songs[1], songs[1], songs[0]])
    #expect(radio.queue.map(\.videoId) == [songs[0].videoId, songs[1].videoId])
    #expect(radio.orderSnapshot.sourceRanks.count == 2)

    let shuffledRadio = QueueManager()
    shuffledRadio.replaceQueue(with: Array(songs.prefix(12)),
                               context: .radio(seedVideoId: "seed", title: "Radio", seedName: "Seed"),
                               shuffle: true, shuffleSeed: 88)
    let priorOrder = shuffledRadio.queue.map(\.videoId)
    shuffledRadio.appendRadioTracks(Array(songs.dropFirst(12).prefix(3)))
    #expect(Array(shuffledRadio.queue.prefix(12)).map(\.videoId) == priorOrder)
    #expect(shuffledRadio.queue.suffix(3).map(\.videoId) == songs.dropFirst(12).prefix(3).map(\.videoId))
}

@MainActor
@Test func shuffleDoesNotChangeQueueTokenAndEachMutationPublishesOneSnapshot() {
    let manager = playlistQueue(queueSongs(20))
    let token = manager.queueToken
    var callbacks = 0
    manager.onStateChange = { callbacks += 1 }
    manager.setShuffle(true, seed: 5)
    #expect(manager.queueToken == token)
    #expect(callbacks == 1)
    callbacks = 0
    manager.setShuffle(false)
    #expect(manager.queueToken == token)
    #expect(callbacks == 1)
    manager.clearQueue()
    #expect(manager.queueToken != token)
}

@MainActor
@Test func manualOnlyBlocksAreExplicitAndLatestPlayNextBlockStaysFirst() {
    let manual = queueSongs(12, prefix: "manual-only")
    let queue = QueueManager()
    queue.addTracksToQueue(manual)
    #expect(queue.orderSnapshot.sourceRanks.isEmpty)
    let ids = queue.occurrenceIDs
    queue.setShuffle(true, seed: 1234)
    #expect(queue.queue == manual)
    queue.setShuffle(false)
    #expect(queue.occurrenceIDs == ids)

    let latest = queueSongs(2, prefix: "latest")
    let earlier = queueSongs(3, prefix: "earlier")
    queue.playNext(earlier)
    queue.playNext(latest)
    queue.setShuffle(true, seed: 99)
    queue.setShuffle(false)
    #expect(Array(queue.upNextTracks.prefix(5)) == latest + earlier)
    #expect(queue.queue.count == 17)
}

@MainActor
@Test func completingPlaylistSourcePreservesManualPlacementsRemovedRowsAndDuplicateOccurrences() {
    let prefix = queueSongs(4)
    let manager = playlistQueue(prefix, startingAt: 1)
    let active = manager.currentOccurrenceID
    let queueToken = manager.queueToken
    let manualNext = queueSongs(1, prefix: "manual-next")[0]
    let manualEnd = queueSongs(1, prefix: "manual-end")[0]
    manager.playNext(manualNext)
    manager.addTrackToQueue(manualEnd)
    _ = manager.removeTrack(at: 0)
    let extra = [prefix[1], queueSongs(1, prefix: "new")[0]]
    manager.completePlaylistSource(extra)
    #expect(manager.currentOccurrenceID == active)
    #expect(manager.queueToken == queueToken)
    #expect(manager.currentTrack == prefix[1])
    #expect(manager.queue == [prefix[1], manualNext, prefix[2], prefix[3]] + extra + [manualEnd])
    #expect(Set(manager.occurrenceIDs).count == manager.queue.count)
    #expect(manager.continuationToken == nil)
}

@MainActor
@Test func completingPlaylistSourceDuringShuffleRestoresWholeCanonicalSourceWithoutChangingCurrent() {
    let songs = queueSongs(30)
    let manager = playlistQueue(Array(songs.prefix(6)), startingAt: 2)
    let active = manager.currentOccurrenceID
    let token = manager.queueToken
    manager.setShuffle(true, seed: 37)
    manager.completePlaylistSource(Array(songs.dropFirst(6)))
    #expect(manager.currentOccurrenceID == active)
    #expect(manager.queueToken == token)
    #expect(manager.currentTrack == songs[2])
    #expect(manager.queue.count == songs.count)
    manager.setShuffle(false)
    #expect(manager.queue == songs)
    #expect(manager.currentIndex == 2)
    #expect(manager.currentOccurrenceID == active)
}
