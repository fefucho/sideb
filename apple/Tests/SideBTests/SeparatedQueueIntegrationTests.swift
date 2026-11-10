import AppKit
import Testing
import SideBCore
@testable import SideB

private func separatedFixture(_ index: Int) -> SongItemRecord {
    SongItemRecord(videoId: "queue-fixture-\(index)", title: "Track \(index)", artists: "Artist",
        album: "Album", duration: "3:00", thumbnail: nil, artistId: nil, albumId: nil,
        setVideoId: "set-\(index)", isVideo: false, isUpload: false, library: nil)
}

@MainActor
@Test func separatedQueueProjectionRemainsBoundedWithTenThousandSourceItemsAndManualTail() throws {
    let player = PlayerViewModel(rustCore: nil)
    let q = player.queueManager
    q.replaceQueue(with: (0..<10_000).map(separatedFixture), context: .playlist(browseId: "fixture", title: "Fixture"))
    player.currentTrack = q.currentTrack
    q.addTrackToQueue(separatedFixture(20_000))
    q.appendRadioTracks((30_000..<31_000).map(separatedFixture))
    let view = NativeSeparatedQueueView(manager: q, revision: q.presentationRevision, player: player,
        router: nil, liked: [], playing: false, loading: false, error: nil)
    let coordinator = view.makeCoordinator()
    coordinator.buildRows()
    #expect(q.queue.count == 10_001)
    #expect(coordinator.rows.count < 150)
    #expect(coordinator.proposalIndices.count == 25)
    let lastID = try #require(q.occurrenceIDs.last)
    #expect(coordinator.committedIndices[lastID] == 10_000)
    #expect(coordinator.rows.contains(.more))
    let revision = q.presentationRevision
    for tick in 0..<100 { player.audioService.currentTime = Double(tick) / 10 }
    #expect(q.presentationRevision == revision)
    #expect(coordinator.rows.count < 150)
    player.audioService.stop()
}

@MainActor
@Test func separatedQueueCellsRecycleWithinViewportAndMenusKeepOccurrenceIdentity() throws {
    let player = PlayerViewModel(rustCore: nil)
    let q = player.queueManager
    q.replaceQueue(with: (0..<2_000).map(separatedFixture), context: .playlist(browseId: "fixture", title: "Fixture"))
    player.currentTrack = q.currentTrack
    let view = NativeSeparatedQueueView(manager: q, revision: q.presentationRevision, player: player,
        router: nil, liked: [], playing: false, loading: false, error: nil)
    let coordinator = view.makeCoordinator()
    let scroll = view.makeScrollView(coordinator: coordinator)
    scroll.setFrameSize(NSSize(width: 600, height: 500))
    scroll.layoutSubtreeIfNeeded()
    let table = try #require(coordinator.table)
    table.layoutSubtreeIfNeeded()
    let range = table.rows(in: NSRect(x: 0, y: 0, width: 600, height: 500))
    #expect(range.length > 0)
    for row in range.location..<NSMaxRange(range) { _ = table.view(atColumn: 0, row: row, makeIfNecessary: true) }
    var live = 0
    table.enumerateAvailableRowViews { _, _ in live += 1 }
    #expect(live > 0 && live < 30)
    #expect(table.numberOfRows < 130)
    let id = q.occurrenceIDs[1]
    let row = try #require(coordinator.rows.firstIndex(of: .committed(id)))
    let menu = try #require(coordinator.menu(row: row))
    #expect(menu.items.contains { $0.title == L10n.text("menu.play_now") })
    // A delayed menu command from an old queue must not affect the new one.
    let play = try #require(menu.items.first { $0.title == L10n.text("menu.play_now") })
    q.replaceQueue(with: [separatedFixture(90_000)])
    if let action = play.action { _ = play.target?.perform(action, with: play) }
    #expect(q.currentTrack?.videoId == "queue-fixture-90000")
}

@MainActor
@Test func separatedQueuePlayerSelectsRecommendationWithoutReplacingChosenSource() throws {
    let player = PlayerViewModel(rustCore: nil)
    let q = player.queueManager
    q.replaceQueue(with: [separatedFixture(0), separatedFixture(1), separatedFixture(2)], context: .playlist(browseId: "fixture", title: "Fixture"))
    player.currentTrack = q.currentTrack
    q.appendRadioTracks([separatedFixture(3), separatedFixture(4)])
    let proposal = try #require(q.recommendationEntries.first)
    player.playQueueRecommendation(id: proposal.id, sessionID: q.recommendationSessionID)
    #expect(player.currentTrack?.videoId == "queue-fixture-3")
    #expect(q.upNextTracks.map(\.videoId) == ["queue-fixture-1", "queue-fixture-2"])
    #expect(q.recommendationEntries.map { $0.track.videoId } == ["queue-fixture-4"])
    let current = q.currentOccurrenceID
    player.playQueueRecommendation(id: proposal.id, sessionID: UUID())
    #expect(q.currentOccurrenceID == current)
}

@MainActor
@Test func separatedQueueRadioRestoreRetainsProviderCursorAndChosenOccurrenceIdentity() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = PlayerViewModel(rustCore: nil, audioService: AudioPlayerService(), playbackStore: PlaybackStateStore(directory: directory))
    first.switchPlaybackSession(to: "account:queue-round-trip")
    first.queueManager.replaceQueue(with: [separatedFixture(0), separatedFixture(1), separatedFixture(2)],
        context: .radio(seedVideoId: "seed", title: "Radio", seedName: "Seed"), radioSeed: "RD-seed")
    _ = first.queueManager.nextTrack(isManualSkip: true)
    first.queueManager.radioCursorVideoID = "provider-cursor"
    first.queueManager.playNext(separatedFixture(3))
    first.currentTrack = first.queueManager.currentTrack
    let snapshot = first.queueManager.orderSnapshot
    first.flushPlaybackState()
    let second = PlayerViewModel(rustCore: nil, audioService: AudioPlayerService(), playbackStore: PlaybackStateStore(directory: directory))
    second.switchPlaybackSession(to: "account:queue-round-trip")
    #expect(second.queueManager.orderSnapshot == snapshot)
    #expect(second.queueManager.radioCursorVideoID == "provider-cursor")
    #expect(second.queueManager.recommendationEntries.isEmpty)
    #expect(second.queueManager.upNextTracks.map(\.videoId) == ["queue-fixture-3"])
    #expect(second.audioService.avPlayer.currentItem == nil)
}

@MainActor
@Test func separatedQueueRemovingTailKeepsPreviousAsHistoryAndRestoresStoppedState() throws {
    let q = QueueManager()
    q.replaceQueue(with: [separatedFixture(0), separatedFixture(1)], startingAt: 1)
    #expect(q.advanceAfterRemovingCurrent() == nil)
    #expect(q.currentTrack == nil)
    #expect(q.previousTracks.count == 1)
    let snapshot = q.orderSnapshot
    let restored = QueueManager()
    restored.replaceQueue(with: q.queue, startingAt: q.currentIndex, restoringCommittedQueue: true)
    #expect(restored.restoreOrder(snapshot, isShuffle: false))
    #expect(restored.currentTrack == nil)
    #expect(restored.previousTrack()?.videoId == "queue-fixture-0")
}

@MainActor
@Test func separatedQueueLargeManualBatchesDoNotExpandTheWholeViewOrDuplicateMovedRows() {
    let q = QueueManager()
    q.replaceQueue(with: [separatedFixture(0)], context: .radio(seedVideoId: "seed", title: "Radio", seedName: "Seed"))
    q.playNext((1...10_000).map(separatedFixture))
    #expect(q.visiblePendingIndices.count <= 200)
    let id = q.occurrenceIDs[10]
    q.moveTrack(from: 10, to: q.queue.count - 1)
    if let index = q.occurrenceIndex(id: id) { q.moveTrack(from: index, to: q.queue.count - 2) }
    #expect(Set(q.visiblePendingIndices).count == q.visiblePendingIndices.count)
    q.revealMorePendingTracks()
    #expect(q.visiblePendingIndices.count <= 300)
}

@MainActor
@Test func continuousQueueShowsPreviousCurrentAndPendingUnderOneHeading() throws {
    let player = PlayerViewModel(rustCore: nil)
    let q = player.queueManager
    q.replaceQueue(with: (0..<5).map(separatedFixture), startingAt: 2)
    player.currentTrack = q.currentTrack
    q.appendRadioTracks([separatedFixture(100)])
    let view = NativeSeparatedQueueView(manager: q, revision: q.presentationRevision, player: player,
        router: nil, liked: [], playing: false, loading: false, error: nil)
    let coordinator = view.makeCoordinator()
    coordinator.buildRows()
    #expect(coordinator.rows == [.heading("queue.now")] + q.occurrenceIDs.map { .committed($0) }
        + [.heading("queue.recommendations")] + q.recommendationEntries.map { .proposal($0.id) })
    #expect(coordinator.destination(1) == nil) // Earlier occurrence cannot accept a drop.
    #expect(coordinator.destination(3) == nil) // Current occurrence cannot accept a drop.
    #expect(coordinator.destination(4) == 3)
    #expect(coordinator.destination(coordinator.rows.count) == 5)
}

@MainActor
@Test func continuousRadioOmitsEmptyChosenAndRecommendationExplanations() throws {
    let player = PlayerViewModel(rustCore: nil)
    let q = player.queueManager
    q.replaceQueue(with: [separatedFixture(0)], context: .radio(seedVideoId: "seed", title: "Radio", seedName: "Seed"))
    player.currentTrack = q.currentTrack
    let view = NativeSeparatedQueueView(manager: q, revision: q.presentationRevision, player: player,
        router: nil, liked: [], playing: false, loading: false, error: nil)
    let coordinator = view.makeCoordinator()
    coordinator.buildRows()
    #expect(coordinator.rows == [.heading("queue.now"), .committed(q.occurrenceIDs[0])])
    q.appendRadioTracks([separatedFixture(1)])
    coordinator.buildRows()
    #expect(coordinator.rows.count == 4)
    q.isRepeat = true
    coordinator.buildRows()
    #expect(coordinator.rows.contains(.status("queue.repeatNote")))
    let loading = NativeSeparatedQueueView(manager: q, revision: q.presentationRevision, player: player,
        router: nil, liked: [], playing: false, loading: true, error: nil).makeCoordinator()
    loading.buildRows()
    #expect(loading.rows.contains(.status("common.loading")))
    let failure = NativeSeparatedQueueView(manager: q, revision: q.presentationRevision, player: player,
        router: nil, liked: [], playing: false, loading: false, error: "Unavailable").makeCoordinator()
    failure.buildRows()
    #expect(failure.rows.contains(.retry))
}

@MainActor
@Test func continuousQueueRealContainerFitsViewportAndLocksXAcrossResizes() throws {
    let player = PlayerViewModel(rustCore: nil)
    let q = player.queueManager
    q.replaceQueue(with: (0..<2000).map(separatedFixture), startingAt: 1000)
    player.currentTrack = q.currentTrack
    q.appendRadioTracks([separatedFixture(3000)])
    let view = NativeSeparatedQueueView(manager: q, revision: q.presentationRevision, player: player,
        router: nil, liked: [], playing: false, loading: false, error: nil)
    let coordinator = view.makeCoordinator()
    let scroll = view.makeScrollView(coordinator: coordinator)
    let table = try #require(coordinator.table)
    for width in [600.0, 350.0, 480.0, 320.0, 600.0] {
        scroll.setFrameSize(NSSize(width: width, height: 400))
        scroll.layoutSubtreeIfNeeded()
        #expect(table.style == .plain)
        #expect(!scroll.hasHorizontalScroller)
        #expect(scroll.horizontalScrollElasticity == .none)
        #expect(abs(table.frame.width - scroll.contentView.bounds.width) <= 1)
        #expect(abs(table.tableColumns[0].width - scroll.contentView.bounds.width) <= 1)
        var proposed = scroll.contentView.bounds
        proposed.origin.x = 25
        proposed.origin.y = 200
        let constrained = scroll.contentView.constrainBoundsRect(proposed)
        #expect(constrained.origin.x == 0)
        #expect(constrained.origin.y > 0) // Vertical scrolling remains available.
    }
    #expect(coordinator.positionedInitially)
    #expect(table.visibleRect.minY > 0)
    #expect(coordinator.rows.count < 240)
}

@MainActor
@Test func continuousQueuePrependingPreviousRowsPreservesVisibleOccurrenceAndOffset() throws {
    let player = PlayerViewModel(rustCore: nil)
    let q = player.queueManager
    q.replaceQueue(with: (0..<2000).map(separatedFixture), startingAt: 1000)
    player.currentTrack = q.currentTrack
    let view = NativeSeparatedQueueView(manager: q, revision: q.presentationRevision, player: player,
        router: nil, liked: [], playing: false, loading: false, error: nil)
    let coordinator = view.makeCoordinator()
    let scroll = view.makeScrollView(coordinator: coordinator)
    scroll.setFrameSize(NSSize(width: 500, height: 300))
    scroll.layoutSubtreeIfNeeded()
    #expect(coordinator.historyStart == 900)
    coordinator.followsCurrent = false
    coordinator.scroll(to: 140)
    let before = try #require(coordinator.viewportAnchor())
    coordinator.historyStart = 800
    coordinator.refresh(parent: view, force: true)
    let after = try #require(coordinator.viewportAnchor())
    #expect(after.0 == before.0)
    #expect(abs(after.1 - before.1) < 1)
    #expect(coordinator.rows.first == .heading("queue.now"))
    #expect(coordinator.committedIndices[q.occurrenceIDs[800]] == 800)
    // Moving near the top progressively exposes another batch without a Previous category.
    coordinator.scroll(to: 20)
    coordinator.viewportChanged()
    #expect(coordinator.historyStart == 700)
    let anchor = try #require(coordinator.viewportAnchor())
    q.appendRadioTracks([separatedFixture(5000)])
    coordinator.refresh(parent: view, force: true)
    let afterReserve = try #require(coordinator.viewportAnchor())
    #expect(anchor.0 == afterReserve.0)
    #expect(abs(anchor.1 - afterReserve.1) < 1)
    player.currentTrack = q.nextTrack(isManualSkip: true)
    coordinator.refresh(parent: view, force: true)
    let afterAdvance = try #require(coordinator.viewportAnchor())
    #expect(anchor.0 == afterAdvance.0)
    #expect(abs(anchor.1 - afterAdvance.1) < 1)
}


@MainActor
@Test func continuousQueueHasNoBlueSelectionAndHeadingsNeverUseSongHoverRows() throws {
    let player = PlayerViewModel(rustCore: nil)
    let q = player.queueManager
    q.replaceQueue(with: [separatedFixture(0), separatedFixture(1)])
    player.currentTrack = q.currentTrack
    q.appendRadioTracks([separatedFixture(2)])
    let view = NativeSeparatedQueueView(manager: q, revision: q.presentationRevision, player: player,
        router: nil, liked: [], playing: false, loading: false, error: nil)
    let coordinator = view.makeCoordinator()
    let scroll = view.makeScrollView(coordinator: coordinator)
    scroll.setFrameSize(NSSize(width: 600, height: 400))
    scroll.layoutSubtreeIfNeeded()
    let table = try #require(coordinator.table)
    #expect(table.selectionHighlightStyle == .none)
    for (index, row) in coordinator.rows.enumerated() {
        let rowView = try #require(coordinator.tableView(table, rowViewForRow: index))
        if case .heading = row {
            #expect(!(rowView is NativeTrackRowView))
            #expect(!coordinator.tableView(table, shouldSelectRow: index))
            #expect(coordinator.menu(row: index) == nil)
        }
        if case .proposal = row {
            #expect(coordinator.tableView(table, viewFor: table.tableColumns[0], row: index) is NativeQueueTrackCellView)
        }
    }
    // Preserve keyboard selection internally while suppressing the default blue paint.
    table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    #expect(table.selectedRow == 1)
    #expect(table.selectionHighlightStyle == .none)
}

@MainActor
@Test func previousAndCurrentExposeNativeDragAndKeyboardRequeueWithoutRestartingAudio() throws {
    let player = PlayerViewModel(rustCore: nil)
    let q = player.queueManager
    q.replaceQueue(with: [separatedFixture(0), separatedFixture(1), separatedFixture(2)], startingAt: 1)
    player.currentTrack = q.currentTrack
    let ids = q.occurrenceIDs
    let view = NativeSeparatedQueueView(manager: q, revision: q.presentationRevision, player: player,
        router: nil, liked: [], playing: false, loading: false, error: nil)
    let coordinator = view.makeCoordinator()
    coordinator.buildRows()
    let table = NativeSeparatedQueueView.QueueTable()
    for id in ids.prefix(2) {
        let row = try #require(coordinator.rows.firstIndex(of: .committed(id)))
        #expect(coordinator.tableView(table, pasteboardWriterForRow: row) != nil)
    }
    let previous = try #require(coordinator.rows.firstIndex(of: .committed(ids[0])))
    coordinator.reorderSelected(row: previous, delta: 1)
    #expect(q.currentOccurrenceID == ids[1])
    #expect(q.queue.map(\.videoId) == ["queue-fixture-0", "queue-fixture-1", "queue-fixture-0", "queue-fixture-2"])
    #expect(player.currentTrack?.videoId == "queue-fixture-1")
    #expect(coordinator.focusAfterMutationID == "track:" + q.occurrenceIDs[2])
}
