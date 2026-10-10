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

@Test @MainActor func queueDurationFallsBackToPlayerOnlyForTheCurrentOccurrence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "QueueDuration.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
    let player = PlayerViewModel(rustCore: nil, audioService: audio,
                               playbackStore: PlaybackStateStore(directory: directory))
    defer { audio.stop() }
    let repeated = tableTestTrack("same-video")
    player.queueManager.replaceQueue(with: [repeated, repeated], startingAt: 0,
                                    context: .custom(title: "Queue"))
    player.currentTrack = repeated
    func view() -> NativeTrackTableView {
        NativeTrackTableView(tracks: player.queueManager.queue, currentTrackVideoId: repeated.videoId,
                            playerViewModel: player, presentation: .queue,
                            menuOrigin: { .queue(occurrenceIndex: $0) }, onPlayTrack: { _ in })
    }
    let table = NativeTrackTableViewInternal()
    let coordinator = view().makeCoordinator()
    func duration(at index: Int) throws -> String {
        let cell = try #require(coordinator.tableView(table, viewFor: nil, row: index) as? NativeQueueTrackCellView)
        let label = try #require(cell.subviews.first {
            $0.accessibilityIdentifier() == "NativeQueueTrackDuration"
        } as? NSTextField)
        #expect(!label.isHidden)
        return label.stringValue
    }
    #expect(try duration(at: 0) == "—:—")
    #expect(try duration(at: 1).isEmpty)
    audio.duration = 255
    let resolved = view()
    #expect(resolved.currentQueueDuration == "4:15")
    coordinator.update(parent: resolved)
    #expect(try duration(at: 0) == "4:15")
    #expect(try duration(at: 1).isEmpty)
    #expect(player.queueManager.queue == [repeated, repeated])
    #expect(player.currentTrack?.duration == nil)

    // Advance to the duplicate while its own stream is still resolving.
    _ = player.queueManager.selectTrack(at: 1)
    audio.duration = 0
    coordinator.update(parent: view())
    #expect(try duration(at: 0).isEmpty)
    #expect(try duration(at: 1) == "—:—")
    for invalid in [Double.nan, .infinity, -1] {
        audio.duration = invalid
        coordinator.update(parent: view())
        #expect(try duration(at: 1) == "—:—")
    }
    audio.duration = 200
    coordinator.update(parent: view())
    #expect(try duration(at: 1) == "3:20")
    let cell = try #require(coordinator.tableView(table, viewFor: nil, row: 1) as? NativeQueueTrackCellView)
    let catalogTrack = SongItemRecord(videoId: repeated.videoId, title: repeated.title, artists: repeated.artists,
                                     album: nil, duration: "3:19", thumbnail: nil, artistId: nil, albumId: nil,
                                     setVideoId: nil, isVideo: false, isUpload: false, library: nil, artistRuns: [])
    cell.configure(track: catalogTrack, index: 1, isCurrentTrack: true, isPlaying: false, isLiked: false,
                   hideAlbum: true, showAlbumInSubtitle: true, isReorderable: true, rowHeight: 46)
    cell.updatePlaybackDuration("3:20")
    let catalogLabel = try #require(cell.subviews.first {
        $0.accessibilityIdentifier() == "NativeQueueTrackDuration"
    } as? NSTextField)
    #expect(catalogLabel.stringValue == "3:19")
    player.currentTrack = tableTestTrack("different-track")
    #expect(view().currentQueueDuration == nil)
}

@Test @MainActor func queuePlayedTrackKeepsDurationAndLikeAfterSkippingAndRestoring() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "QueuePlayedDuration.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
    let player = PlayerViewModel(rustCore: nil, audioService: audio,
                               playbackStore: PlaybackStateStore(directory: directory))
    defer { audio.stop() }
    player.switchPlaybackSession(to: "account:queue-duration")
    let repeated = tableTestTrack("same-video")
    player.queueManager.replaceQueue(with: [repeated, repeated], startingAt: 0,
                                    context: .custom(title: "Queue"))
    player.currentTrack = repeated
    let token = player.queueManager.queueToken
    let occurrenceIDs = player.queueManager.orderSnapshot.occurrenceIDs
    audio.duration = 255
    audio.onPlaybackProgress?(1, 255)
    #expect(player.currentTrack?.duration == "4:15")
    #expect(player.queueManager.queue[0].duration == "4:15")
    #expect(player.queueManager.queue[1].duration == nil)
    #expect(player.queueManager.queueToken == token)
    #expect(player.queueManager.orderSnapshot.occurrenceIDs == occurrenceIDs)

    player.playNext()
    #expect(player.queueManager.currentIndex == 1)
    #expect(player.currentTrack?.duration == nil)
    #expect(player.queueManager.queue[0].duration == "4:15")
    let table = NativeTrackTableViewInternal()
    func checkFirstRow(_ source: PlayerViewModel) throws {
        let view = NativeTrackTableView(tracks: source.queueManager.tracks,
                                       currentTrackVideoId: source.currentTrack?.videoId,
                                       playerViewModel: source, presentation: .queue,
                                       menuOrigin: { .queue(occurrenceIndex: $0) }, onPlayTrack: { _ in })
        let coordinator = view.makeCoordinator()
        let cell = try #require(coordinator.tableView(table, viewFor: nil, row: 0) as? NativeQueueTrackCellView)
        let duration = try #require(cell.subviews.first {
            $0.accessibilityIdentifier() == "NativeQueueTrackDuration"
        } as? NSTextField)
        let like = try #require(cell.subviews.first {
            $0.accessibilityIdentifier() == "NativeQueueTrackLike"
        } as? NSButton)
        #expect(!duration.isHidden && duration.stringValue == "4:15")
        #expect(!like.isHidden && like.alphaValue == 1)
    }
    try checkFirstRow(player)
    audio.onPlaybackProgress?(1, 200)
    #expect(player.queueManager.queue.map(\.duration) == ["4:15", "3:20"])
    audio.onPlaybackProgress?(2, 400)
    #expect(player.queueManager.queue[1].duration == "3:20")
    player.playPrevious()
    #expect(player.currentTrack?.duration == "4:15")
    try checkFirstRow(player)

    player.flushPlaybackState()
    let restoredAudio = AudioPlayerService(preferences: preferences, preferencePrefix: "restored")
    defer { restoredAudio.stop() }
    let restored = PlayerViewModel(rustCore: nil, audioService: restoredAudio,
                                   playbackStore: PlaybackStateStore(directory: directory))
    restored.switchPlaybackSession(to: "account:queue-duration")
    #expect(restored.queueManager.queue.map(\.duration) == ["4:15", "3:20"])
    #expect(restored.queueManager.orderSnapshot.occurrenceIDs == occurrenceIDs)
    try checkFirstRow(restored)
    restored.switchPlaybackSession(to: "account:other")
    restoredAudio.onPlaybackProgress?(1, 500)
    #expect(restored.queueManager.queue.isEmpty && restored.currentTrack == nil)
}

@Test @MainActor func queueDurationEnrichmentRejectsInvalidAndMismatchedPlayback() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "QueueInvalidDuration.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
    let player = PlayerViewModel(rustCore: nil, audioService: audio,
                               playbackStore: PlaybackStateStore(directory: directory))
    defer { audio.stop() }
    let track = tableTestTrack("video")
    player.queueManager.replaceQueue(with: [track], startingAt: 0, context: .custom(title: "Queue"))
    player.currentTrack = track
    for invalid in [Double.nan, .infinity, 0, -1, Double(Int.max)] {
        audio.onPlaybackProgress?(0, invalid)
        #expect(player.queueManager.queue[0].duration == nil)
    }
    player.currentTrack = tableTestTrack("different-video")
    audio.onPlaybackProgress?(1, 255)
    #expect(player.queueManager.queue[0].duration == nil && player.currentTrack?.duration == nil)
    var catalogTrack = track
    catalogTrack.duration = "3:19"
    player.queueManager.replaceQueue(with: [catalogTrack], startingAt: 0, context: .custom(title: "Queue"))
    player.currentTrack = catalogTrack
    audio.onPlaybackProgress?(1, 200)
    #expect(player.queueManager.queue[0].duration == "3:19")
}
