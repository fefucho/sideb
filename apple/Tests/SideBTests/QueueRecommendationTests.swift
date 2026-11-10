import Testing
import SideBCore
@testable import SideB

@MainActor
private func recommendationSong(_ id: String) -> SongItemRecord {
    SongItemRecord(videoId: id, title: id, artists: "Artist", album: nil, duration: nil,
                   thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
                   isVideo: false, isUpload: false, library: nil)
}

@MainActor
@Test func radioBatchReservesTracksAndPromotesOnlyOnePerAdvance() {
    let q = QueueManager()
    q.replaceQueue(with: ["R1", "R2"].map(recommendationSong), context: .radio(seedVideoId: "R1", title: "Radio", seedName: "R1"))
    q.playNext(recommendationSong("X")); q.addTrackToQueue(recommendationSong("Y"))
    #expect(q.queue.map(\.videoId) == ["R1", "X", "Y"])
    #expect(q.recommendationEntries.map { $0.track.videoId } == ["R2"])
    #expect(q.nextTrack(isManualSkip: true)?.videoId == "X")
    #expect(q.nextTrack(isManualSkip: true)?.videoId == "Y")
    #expect(q.nextTrack(isManualSkip: true)?.videoId == "R2")
    #expect(q.recommendationEntries.isEmpty)
}

@MainActor
@Test func intermediateRecommendationCanBeChosenWithoutDroppingEarlierEntries() {
    let q = QueueManager()
    q.replaceQueue(with: [recommendationSong("A")], context: .custom(title: "test"))
    q.appendRadioTracks(["R1", "R2", "R3"].map(recommendationSong))
    let chosenID = q.recommendationEntries[1].id
    #expect(q.playRecommendation(id: chosenID)?.videoId == "R2")
    #expect(q.currentTrack?.videoId == "R2")
    #expect(q.recommendationEntries.map { $0.track.videoId } == ["R1", "R3"])
    #expect(q.previousTracks.map(\.videoId) == ["A"])
}

@MainActor
@Test func repeatDoesNotPromoteAndCommittedRestoreKeepsQueue() {
    let q = QueueManager()
    q.replaceQueue(with: [recommendationSong("A"), recommendationSong("B")], startingAt: 0,
                   context: .radio(seedVideoId: "A", title: "Radio", seedName: "A"), restoringCommittedQueue: true)
    q.appendRadioTracks([recommendationSong("C")])
    q.isRepeat = true; q.selectTrack(at: 1)
    #expect(q.nextTrack(isManualSkip: true)?.videoId == "A")
    #expect(q.recommendationEntries.count == 1)
}

@MainActor
@Test func playlistPagesStayBeforeManualEndAndVisibleWindowCanGrowIncrementally() {
    let q = QueueManager()
    q.replaceQueue(with: (0..<10_000).map { recommendationSong("S\($0)") }, context: .playlist(browseId: "p", title: "P"))
    q.addTrackToQueue(recommendationSong("manual"))
    q.appendPlaylistTracks([recommendationSong("page2")])
    #expect(q.queue.last?.videoId == "manual")
    #expect(q.queue[q.queue.count - 2].videoId == "page2")
    #expect(q.visiblePendingIndices.count <= 100)
    q.revealMorePendingTracks()
    #expect(q.visiblePendingIndices.count <= 201) // 200 source rows plus the explicit manual tail.
}

@MainActor
@Test func radioStartingIndexCommitsOnlySelectedTrackAndDropsUnplayedPrefix() {
    let q = QueueManager()
    q.replaceQueue(with: ["old", "selected", "reserved", "reserved"].map(recommendationSong), startingAt: 1,
                   context: .radio(seedVideoId: "selected", title: "Radio", seedName: "selected"))
    #expect(q.queue.map(\.videoId) == ["selected"])
    #expect(q.currentIndex == 0)
    #expect(q.recommendationEntries.map { $0.track.videoId } == ["reserved"])
}

@MainActor
@Test func removingTailNeverFallsBackToAnEarlierTrackAndLeavesCollectionForPaging() {
    let q = QueueManager()
    q.replaceQueue(with: [recommendationSong("A"), recommendationSong("B")])
    q.selectTrack(at: 1)
    #expect(q.advanceAfterRemovingCurrent() == nil)
    #expect(q.queue.map(\.videoId) == ["A"])
    #expect(q.currentIndex == q.queue.count)
    #expect(q.currentTrack == nil)
}

@MainActor
@Test func recommendationsWaitForCollectionContinuation() {
    let q = QueueManager()
    q.replaceQueue(with: [recommendationSong("A")], context: .playlist(browseId: "p", title: "P"), continuation: "more")
    q.appendRadioTracks([recommendationSong("R")])
    #expect(q.nextTrack(isManualSkip: true) == nil)
    #expect(q.recommendationEntries.map { $0.track.videoId } == ["R"])
}

@MainActor
@Test func radioHistoryIsCappedWithoutPromotingWholeReservation() {
    let q = QueueManager()
    q.replaceQueue(with: [recommendationSong("R0")], context: .radio(seedVideoId: "R0", title: "Radio", seedName: "R0"))
    q.appendRadioTracks((1...300).map { recommendationSong("R\($0)") })
    for _ in 0..<300 { _ = q.nextTrack(isManualSkip: true) }
    #expect(q.queue.count <= 221)
    #expect(q.recommendationEntries.count == 0)
}

@MainActor
@Test func movingTrackToEndKeepsLargePlaylistWindowBounded() {
    let q = QueueManager()
    q.replaceQueue(with: (0..<10_000).map { recommendationSong("M\($0)") }, context: .playlist(browseId: "p", title: "P"))
    let movedID = q.occurrenceIDs[10]
    q.moveTrack(from: 10, to: 9_999)
    #expect(q.occurrenceIndex(id: movedID) == 9_999)
    #expect(q.tracks.count <= 100)
    #expect(q.visiblePendingIndices.last == 9_999)
}

@MainActor
@Test func choosingRecommendationWhileShuffleOffKeepsCurrentBeforePending() {
    let q = QueueManager()
    q.replaceQueue(with: (0..<20).map { recommendationSong("P\($0)") }, context: .playlist(browseId: "p", title: "P"))
    q.selectTrack(at: 17)
    q.appendRadioTracks([recommendationSong("picked")])
    let id = q.recommendationEntries[0].id
    _ = q.playRecommendation(id: id)
    q.setShuffle(false)
    #expect(q.currentTrack?.videoId == "picked")
    #expect(q.queue.prefix(q.currentIndex + 1).map(\.videoId).last == "picked")
    #expect(q.queue.suffix(from: q.currentIndex + 1).map(\.videoId).contains("P18"))
}

@MainActor
@Test func draggingPreviousAndCurrentCreatesExplicitRepeatsWithoutMovingActiveOccurrence() throws {
    let q = QueueManager()
    q.replaceQueue(with: ["same", "same", "B", "C"].map(recommendationSong), startingAt: 1)
    q.appendRadioTracks([recommendationSong("R")])
    let ids = q.occurrenceIDs
    let active = q.currentOccurrenceID
    let repeated = try #require(q.placeQueueOccurrence(id: ids[0], beforeID: ids[2]))
    #expect(!ids.contains(repeated))
    #expect(q.occurrenceIDs == [ids[0], ids[1], repeated, ids[2], ids[3]])
    #expect(q.currentOccurrenceID == active && q.currentIndex == 1)
    #expect(q.recommendationEntries.map { $0.track.videoId } == ["R"])
    let replayCurrent = try #require(q.placeQueueOccurrence(id: ids[1], beforeID: nil))
    #expect(replayCurrent != ids[1] && replayCurrent != repeated)
    #expect(q.occurrenceIDs.last == replayCurrent)
    #expect(q.currentOccurrenceID == active)
    q.setShuffle(true, seed: 77)
    q.setShuffle(false)
    #expect(q.currentOccurrenceID == active)
    #expect(q.occurrenceIDs.firstIndex(of: repeated)! < q.occurrenceIDs.firstIndex(of: ids[2])!)
    #expect(q.occurrenceIDs.last == replayCurrent)
}

@MainActor
@Test func droppingPendingMovesSameOccurrenceAndInvalidDropsAreAtomic() throws {
    let q = QueueManager()
    q.replaceQueue(with: ["A", "B", "C", "D"].map(recommendationSong), startingAt: 1)
    let ids = q.occurrenceIDs
    #expect(q.placeQueueOccurrence(id: ids[3], beforeID: ids[2]) == ids[3])
    #expect(q.occurrenceIDs == [ids[0], ids[1], ids[3], ids[2]])
    let snapshot = q.orderSnapshot
    #expect(q.placeQueueOccurrence(id: ids[0], beforeID: ids[1]) == nil)
    #expect(q.placeQueueOccurrence(id: ids[1], beforeID: ids[0]) == nil)
    #expect(q.placeQueueOccurrence(id: "stale", beforeID: nil) == nil)
    #expect(q.placeQueueOccurrence(id: ids[0], beforeID: "stale") == nil)
    #expect(q.orderSnapshot == snapshot)
}

@MainActor
@Test func radioCurrentCanBeDraggedToChosenTailBeforeTheRecommendationReserve() throws {
    let q = QueueManager()
    q.replaceQueue(with: ["R1", "R2"].map(recommendationSong), context: .radio(seedVideoId: "R1", title: "Radio", seedName: "R1"))
    let active = try #require(q.currentOccurrenceID)
    let copy = try #require(q.placeQueueOccurrence(id: active, beforeID: nil))
    #expect(copy != active)
    #expect(q.queue.map(\.videoId) == ["R1", "R1"])
    #expect(q.currentOccurrenceID == active)
    #expect(q.recommendationEntries.map { $0.track.videoId } == ["R2"])
    #expect(q.nextTrack(isManualSkip: true)?.videoId == "R1")
    #expect(q.currentOccurrenceID == copy)
    #expect(q.nextTrack(isManualSkip: true)?.videoId == "R2")
}

@MainActor
@Test func selectingLaterRecommendationAdvancesPrefixAndPreservesChosenPendingSongs() throws {
    let q = QueueManager()
    q.replaceQueue(with: ["A", "B", "C", "D"].map(recommendationSong), startingAt: 1)
    q.appendRadioTracks(["R1", "R2", "R3", "R4"].map(recommendationSong))
    let chosenIDs = q.occurrenceIDs
    let selected = q.recommendationEntries[2].id
    #expect(q.playRecommendation(id: selected, advanceThrough: true)?.videoId == "R3")
    #expect(q.queue.map(\.videoId) == ["A", "B", "R1", "R2", "R3", "C", "D"])
    #expect(q.currentIndex == 4 && q.currentTrack?.videoId == "R3")
    #expect(q.recommendationEntries.map { $0.track.videoId } == ["R4"])
    #expect(Array(q.occurrenceIDs.prefix(2)) == Array(chosenIDs.prefix(2)))
    #expect(Array(q.occurrenceIDs.suffix(2)) == Array(chosenIDs.suffix(2)))
    let skipped = Set(q.orderSnapshot.radioOccurrenceIDs ?? [])
    #expect(skipped.contains(q.occurrenceIDs[2]) && skipped.contains(q.occurrenceIDs[3]))
    #expect(!skipped.contains(q.occurrenceIDs[4]))
    let active = q.currentOccurrenceID
    q.setShuffle(true, seed: 4); q.setShuffle(false)
    #expect(q.currentOccurrenceID == active)
    #expect(q.upNextTracks.map(\.videoId) == ["C", "D"])
    let restored = QueueManager()
    restored.replaceQueue(with: q.queue, startingAt: q.currentIndex, context: q.context,
                          contextTitle: q.contextTitle, restoringCommittedQueue: true)
    #expect(restored.restoreOrder(q.orderSnapshot, isShuffle: q.isShuffle))
    #expect(restored.currentOccurrenceID == active)
}

@MainActor
@Test func playOnlySelectionKeepsEarlierProposalsAndEmptyQueueKeepsRemainingReserve() throws {
    let q = QueueManager()
    q.replaceQueue(with: [recommendationSong("A"), recommendationSong("B")])
    q.appendRadioTracks(["R1", "R2", "R3"].map(recommendationSong))
    let selected = q.recommendationEntries[1].id
    #expect(q.playRecommendation(id: selected, advanceThrough: false)?.videoId == "R2")
    #expect(q.queue.map(\.videoId) == ["A", "R2", "B"])
    #expect(q.recommendationEntries.map { $0.track.videoId } == ["R1", "R3"])
    let empty = QueueManager()
    empty.appendRadioTracks(["R1", "R2", "R3"].map(recommendationSong))
    let second = empty.recommendationEntries[1].id
    #expect(empty.playRecommendation(id: second, advanceThrough: true)?.videoId == "R2")
    #expect(empty.queue.map(\.videoId) == ["R1", "R2"])
    #expect(empty.recommendationEntries.map { $0.track.videoId } == ["R3"])
    let unchanged = empty.orderSnapshot
    #expect(empty.playRecommendation(id: "stale", advanceThrough: true) == nil)
    #expect(empty.orderSnapshot == unchanged)
}
