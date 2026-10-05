import Testing
import AppKit
import SideBCore
@testable import SideB

private func tableTestTrack(_ id: String) -> SongItemRecord {
    SongItemRecord(videoId: id, title: id, artists: "Artist", album: nil, duration: nil,
                   thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
                   isVideo: false, isUpload: false, library: nil, artistRuns: [])
}

@MainActor private func tableMouseDownEvent(flags: NSEvent.ModifierFlags, number: Int = 0) -> NSEvent {
    NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: flags,
                       timestamp: 0, windowNumber: 0, context: nil,
                       eventNumber: number, clickCount: 1, pressure: 1)!
}

@Test func singleClickAndThumbnailPlayDelegateOneOccurrence() {
    let repeated = tableTestTrack("same-video")
    let projection = TrackTableRowProjection.make(sections: [
        TrackTableSection(id: "day-1", title: "Today", tracks: [repeated]),
        TrackTableSection(id: "day-2", title: "Yesterday", tracks: [repeated])
    ])
    let trackRows = projection.rows.compactMap { row -> TableRowItem? in
        if case .track = row { return row }
        return nil
    }

    #expect(trackRows.count == 2)
    #expect(TrackTableInteractionPolicy.playbackIndex(for: trackRows[0], source: .row) == 0)
    #expect(TrackTableInteractionPolicy.playbackIndex(for: trackRows[1], source: .row) == 1)
    #expect(TrackTableInteractionPolicy.playbackIndex(for: trackRows[1], source: .thumbnailPlay) == 1)

    var delegatedIndices: [Int] = []
    let didDispatch = TrackTableInteractionPolicy.dispatchPlayback(for: trackRows[1], source: .row) {
        delegatedIndices.append($0)
    }
    #expect(didDispatch)
    #expect(delegatedIndices == [1])
}

@Test func creditsMenuAndSelectionGesturesDoNotDelegatePlayback() {
    let row = TrackTableRowProjection.make(sections: [
        TrackTableSection(tracks: [tableTestTrack("video")])
    ]).rows[0]

    #expect(TrackTableInteractionPolicy.playbackIndex(for: row, source: .artistLink) == nil)
    #expect(TrackTableInteractionPolicy.playbackIndex(for: row, source: .albumLink) == nil)
    #expect(TrackTableInteractionPolicy.playbackIndex(for: row, source: .menu) == nil)
    #expect(TrackTableInteractionPolicy.playbackIndex(for: row, source: .row, isSelectionGesture: true) == nil)
    var delegatedIndices: [Int] = []
    #expect(!TrackTableInteractionPolicy.dispatchPlayback(for: row, source: .menu) {
        delegatedIndices.append($0)
    })
    #expect(delegatedIndices.isEmpty)
}

@Test @MainActor func nativeTrackCellSeparatesPrimaryCreditsAndMenuCallbacks() {
    let track = SongItemRecord(videoId: "video", title: "Song", artists: "Artist", album: "Album",
                               duration: "3:00", thumbnail: nil, artistId: "artist-id", albumId: "album-id",
                               setVideoId: nil, isVideo: false, isUpload: false, library: nil, artistRuns: [])
    let cell = NativeTrackCellView(frame: .zero)
    var playbackCount = 0
    var artistCount = 0
    var albumCount = 0
    var menuCount = 0
    var selectionDelegations = 0
    cell.onPlay = { playbackCount += 1 }
    cell.onArtist = { _ in artistCount += 1 }
    cell.onAlbum = { _ in albumCount += 1 }
    cell.onMenu = { _ in menuCount += 1 }
    cell.onSelectionMouseDown = { _ in selectionDelegations += 1 }
    cell.configure(track: track, index: 0, isCurrentTrack: true, isPlaying: true,
                   hideAlbum: true, showAlbumInSubtitle: true, rowHeight: 46)

    let hoverControls = cell.subviews.compactMap { $0 as? NSButton }.filter {
        $0.identifier?.rawValue == "NativeTrackThumbnailPlay" || $0.identifier?.rawValue == "NativeTrackMenu"
    }
    #expect(hoverControls.count == 2)
    #expect(hoverControls.allSatisfy { $0.isHidden })
    cell.updateSelection(isSelected: true)
    #expect(hoverControls.allSatisfy { $0.isHidden })

    let event = tableMouseDownEvent(flags: [])
    cell.titleLabel.mouseDown(with: event)
    cell.artworkImageView.mouseDown(with: event)
    cell.updateHover(isHovered: true)
    #expect(hoverControls.allSatisfy { !$0.isHidden })
    cell.subviews.compactMap { $0 as? NSButton }
        .first { $0.identifier?.rawValue == "NativeTrackThumbnailPlay" }?.performClick(nil)
    #expect(playbackCount == 3)

    for (number, flags) in [
        (1, NSEvent.ModifierFlags.command),
        (2, .shift),
        (3, .control)
    ] {
        let modifiedEvent = tableMouseDownEvent(flags: flags, number: number)
        cell.titleLabel.mouseDown(with: modifiedEvent)
        cell.artworkImageView.mouseDown(with: modifiedEvent)
        let credits = cell.subviews.compactMap { $0 as? NativeTrackCreditField }
        credits.forEach { $0.mouseDown(with: modifiedEvent) }
    }
    #expect(selectionDelegations == 12)
    #expect(playbackCount == 3)
    #expect(artistCount == 0)
    #expect(albumCount == 0)

    cell.updateHover(isHovered: false)
    #expect(hoverControls.allSatisfy { $0.isHidden })
    // Selección persistente y estado de pista actual no deben dejar los controles pegados.
    cell.updateSelection(isSelected: true)
    #expect(hoverControls.allSatisfy { $0.isHidden })
    cell.updateCreditFocus(true)
    #expect(hoverControls.allSatisfy { !$0.isHidden })
    #expect(playbackCount == 3)
    cell.updateCreditFocus(false)
    #expect(hoverControls.allSatisfy { $0.isHidden })
    #expect(selectionDelegations == 12)

    let credits = cell.subviews.compactMap { $0 as? NativeTrackCreditField }
    let artistLink = credits.first { $0.stringValue == "Artist" }
    let albumLink = credits.first { $0.stringValue == "• Album" }
    #expect(artistLink?.acceptsFirstResponder == true)
    #expect(albumLink?.acceptsFirstResponder == true)
    #expect(artistLink?.accessibilityPerformPress() == true)
    #expect(albumLink?.accessibilityPerformPress() == true)
    cell.subviews.compactMap { $0 as? NSButton }
        .first { $0.identifier?.rawValue == "NativeTrackMenu" }?.performClick(nil)
    #expect(artistCount == 1)
    #expect(albumCount == 1)
    #expect(menuCount == 1)
    #expect(playbackCount == 3)
}

@Test @MainActor func queueRowsFollowExactOccurrenceWhenTheVideoIDRepeats() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "TrackOccurrence.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
    let player = PlayerViewModel(rustCore: nil, audioService: audio,
                               playbackStore: PlaybackStateStore(directory: directory))
    let repeated = tableTestTrack("same-video")
    player.queueManager.replaceQueue(with: [repeated, repeated], startingAt: 0,
                                    context: .custom(title: "Queue"))
    func table() -> NativeTrackTableView {
        NativeTrackTableView(tracks: player.queueManager.queue, currentTrackVideoId: repeated.videoId,
                            playerViewModel: player, menuOrigin: { .queue(occurrenceIndex: $0) }, onPlayTrack: { _ in })
    }
    let first = table()
    let coordinator = first.makeCoordinator()
    #expect(coordinator.isCurrentOccurrence(videoId: repeated.videoId, index: 0))
    #expect(!coordinator.isCurrentOccurrence(videoId: repeated.videoId, index: 1))
    _ = player.queueManager.selectTrack(at: 1)
    let second = table()
    #expect(first.currentQueueOccurrenceID != second.currentQueueOccurrenceID)
    coordinator.update(parent: second)
    #expect(!coordinator.isCurrentOccurrence(videoId: repeated.videoId, index: 0))
    #expect(coordinator.isCurrentOccurrence(videoId: repeated.videoId, index: 1))
    audio.stop()
}

@Test @MainActor func queuePresentationUsesSeparateCellsWhileStandardListsKeepMediaControls() {
    let track = tableTestTrack("queue-track")
    let table = NativeTrackTableViewInternal()
    var played: [Int] = []
    let queueView = NativeTrackTableView(tracks: [track, track], presentation: .queue,
                                        isReorderable: true, rowHeight: 46,
                                        menuOrigin: { .queue(occurrenceIndex: $0) },
                                        onPlayTrack: { played.append($0) })
    let queueCoordinator = queueView.makeCoordinator()
    let first = queueCoordinator.tableView(table, viewFor: nil, row: 0)
    let duplicate = queueCoordinator.tableView(table, viewFor: nil, row: 1)
    #expect(first is NativeQueueTrackCellView)
    #expect(duplicate is NativeQueueTrackCellView)
    #expect(first?.identifier == NSUserInterfaceItemIdentifier("NativeQueueTrackCellView"))
    #expect(played.isEmpty)
    #expect(queueCoordinator.tableView(table, pasteboardWriterForRow: 1) != nil)

    let standardView = NativeTrackTableView(tracks: [track], onPlayTrack: { played.append($0) })
    let standardCoordinator = standardView.makeCoordinator()
    let standard = standardCoordinator.tableView(table, viewFor: nil, row: 0)
    #expect(standard is NativeTrackCellView)
    #expect(standard?.identifier == NSUserInterfaceItemIdentifier("NativeTrackCellView"))
    #expect(standardCoordinator.tableView(table, pasteboardWriterForRow: 0) == nil)
    (standard as? NativeTrackCellView)?.performPrimaryAction()
    #expect(played == [0])
}
