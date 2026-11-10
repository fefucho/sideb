import AppKit
import Testing
import SwiftUI
import SideBCore
@testable import SideB

private func nativeSidebarSong(_ id: String) -> SongItemRecord {
    SongItemRecord(videoId: id, title: "Track \(id)", artists: "Artist", album: "Album", duration: "3:00", thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil)
}

@Suite(.serialized)
struct NativeSidebarRecommendationsTests {
@Test func nativeSidebarProjectionDefersAllContentAndKeepsDuplicateOccurrencesDistinct() {
    let repeated = nativeSidebarSong("same")
    let data = RecommendedData(artistSongs: [repeated, repeated], albumSongs: [repeated], similarSongs: [repeated, repeated])
    let deferred = NativeSidebarRecommendationsProjection(data: data, activated: false, loading: false)
    #expect(deferred.rows.count == 2)
    #expect(!deferred.rows.contains { if case .track = $0 { return true }; return false })
    let loaded = NativeSidebarRecommendationsProjection(data: data, activated: true, loading: false)
    let identities = loaded.rows.compactMap { row -> String? in
        if case .track = row { return row.identity }; return nil
    }
    #expect(identities.count == 5)
    #expect(Set(identities).count == 5)
}

@Test @MainActor func nativeSidebarLargePayloadUsesViewportAndPreservesScrollOnAppendAndRemount() throws {
    let suite = "NativeSidebarViewport.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer {
        preferences.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
    let player = PlayerViewModel(rustCore: nil,
        audioService: AudioPlayerService(preferences: preferences, preferencePrefix: suite),
        playbackStore: PlaybackStateStore(directory: directory))
    let current = nativeSidebarSong("current")
    player.currentTrack = current
    player.queueManager.replaceQueue(with: [current], startingAt: 0)
    let state = SidebarArtworkScrollState()
    let key = SidebarArtworkOccurrenceKey(sessionID: UUID(), playbackID: UUID(), videoID: "current", occurrenceID: "one")
    state.synchronizeOccurrence(key)
    state.savedOffsetY = 520
    let songs = (0..<10_000).map { nativeSidebarSong(String($0)) }
    var data = RecommendedData(similarSongs: songs, loadedVideoId: "current")
    var heroHeight: CGFloat = 500
    func viewport(loading: Bool = false, playing: Bool = false) -> NativeSidebarRecommendationsViewport {
        NativeSidebarRecommendationsViewport(player: player, router: nil, heroHeight: heroHeight, state: state,
            occurrenceKey: key, data: data, loading: loading, error: nil, liked: [], playing: playing,
            currentVideoID: "current", requestKey: nil)
    }
    let initial = viewport()
    let coordinator = initial.makeCoordinator()
    let scroll = initial.makeScrollView(coordinator: coordinator)
    scroll.frame = NSRect(x: 0, y: 0, width: 380, height: 320)
    scroll.layoutSubtreeIfNeeded()
    let table = try #require(scroll.documentView as? NSTableView)
    table.layoutSubtreeIfNeeded()
    // The existing shelf contract is ten items, irrespective of provider payload size.
    #expect(coordinator.rows.count == 13)
    let mounted = (0..<table.numberOfRows).filter { table.view(atColumn: 0, row: $0, makeIfNecessary: false) is NativeQueueTrackCellView }.count
    #expect(mounted < 10)
    #expect(player.queueManager.queue.count == 1)
    #expect(player.queueManager.recommendationEntries.isEmpty)
    let nativeScroll = try #require(scroll as? NativeSidebarScrollView)
    let heroMetadata = try #require(nativeScroll.heroMetadata)
    #expect(heroMetadata.superview === scroll)
    #expect(!(coordinator.tableView(table, viewFor: table.tableColumns[0], row: 0) is NSHostingView<SidebarArtworkMetadataHost>))
    let fixedFrame = heroMetadata.frame
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 250))
    nativeScroll.layoutHeroLayers()
    #expect(nativeScroll.feedTop == 250)
    #expect(heroMetadata.frame == fixedFrame, "Metadata must remain anchored while the feed boundary moves")
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 520))
    nativeScroll.layoutHeroLayers()
    #expect(nativeScroll.feedTop == 0)
    #expect(heroMetadata.isHidden, "Covered metadata must stop receiving clicks and accessibility focus")
    let builds = coordinator.projectionBuildCount
    for _ in 0..<30 { coordinator.update(viewport()) }
    #expect(coordinator.projectionBuildCount == builds, "Unchanged presentation must not rebuild recommendation rows")
    func refreshButton() throws -> NSButton {
        let cell = try #require(table.view(atColumn: 0, row: 1, makeIfNecessary: true))
        return try #require(cell.subviews.compactMap { $0 as? NSButton }.first)
    }
    coordinator.update(viewport(loading: true))
    #expect(try !refreshButton().isEnabled)
    coordinator.update(viewport(loading: false))
    #expect(try refreshButton().isEnabled)
    #expect(nativeScroll.heroMetadata === heroMetadata,
            "Arriving recommendations retain fixed metadata outside the recycled hero row")
    if let nativeTable = table as? NativeSidebarRecommendationsTable,
       let visibleTrack = (0..<table.numberOfRows).first(where: { table.view(atColumn: 0, row: $0, makeIfNecessary: false) is NativeQueueTrackCellView }) {
        nativeTable.updateHoveredRow(visibleTrack)
        coordinator.update(viewport(playing: true))
        #expect((table.rowView(atRow: visibleTrack, makeIfNecessary: false) as? NativeTrackRowView)?.isHovered == true)
    }
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 550))
    coordinator.scrolled()
    data.artistSongs = Array(songs.prefix(10))
    coordinator.update(viewport())
    #expect(abs(scroll.contentView.bounds.minY - 550) < 1)
    let previousRow = table.row(at: NSPoint(x: 1, y: scroll.contentView.bounds.minY + 1))
    let previousIdentity = coordinator.rows[previousRow].identity
    data.relatedArtists = [BrowseCardRecord(kind: "artist", id: "new-artist", title: "Artist", subtitle: nil, thumbnail: nil, duration: nil)]
    coordinator.update(viewport())
    let retainedRow = table.row(at: NSPoint(x: 1, y: scroll.contentView.bounds.minY + 1))
    #expect(coordinator.rows[retainedRow].identity == previousIdentity)
    let beforeResize = scroll.contentView.bounds.minY
    let anchorInset = beforeResize - table.rect(ofRow: retainedRow).minY
    heroHeight = 620
    coordinator.update(viewport())
    let resizedRow = table.row(at: NSPoint(x: 1, y: scroll.contentView.bounds.minY + 1))
    #expect(coordinator.rows[resizedRow].identity == previousIdentity)
    #expect(abs(scroll.contentView.bounds.minY - table.rect(ofRow: resizedRow).minY - anchorInset) < 1)
    heroHeight = 500
    coordinator.update(viewport())
    #expect(abs(scroll.contentView.bounds.minY - beforeResize) < 1)
    let savedOffset = scroll.contentView.bounds.minY
    NativeSidebarRecommendationsViewport.dismantleNSView(scroll, coordinator: coordinator)
    #expect(abs(state.savedOffsetY - savedOffset) < 1)
    let remount = viewport()
    let newCoordinator = remount.makeCoordinator()
    let newScroll = remount.makeScrollView(coordinator: newCoordinator)
    newScroll.frame = NSRect(x: 0, y: 0, width: 380, height: 320)
    newScroll.layoutSubtreeIfNeeded()
    newCoordinator.update(remount, initial: true)
    #expect(abs(newScroll.contentView.bounds.minY - savedOffset) < 1)
    NativeSidebarRecommendationsViewport.dismantleNSView(newScroll, coordinator: newCoordinator)
}

@Test @MainActor func sidebarFooterGrowsWithoutTakingSpaceFromMinimumControls() {
    #expect(PlaybackSidebarLayout.footerHeight(for: 628) == 284)
    #expect(PlaybackSidebarLayout.footerHeight(for: 988) > 300)
    #expect(PlaybackSidebarLayout.footerHeight(for: 1800) == 324)
    #expect(PlaybackSidebarLayout.footerHeight(for: 628, panel: .artwork) == 200)
    #expect(1800 - PlaybackSidebarLayout.footerHeight(for: 1800, panel: .artwork) == 494)
    #expect(PlaybackSidebarLayout.footerHeight(for: 1800, panel: .artwork, isPortrait: true) == 240)
}

@Test @MainActor func nativeSidebarRecommendationsAreClickableAndFeatureAddToQueueBesideLike() async throws {
    let suite = "NativeSidebarClickable.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer {
        preferences.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
    let player = PlayerViewModel(rustCore: nil,
        audioService: AudioPlayerService(preferences: preferences, preferencePrefix: suite),
        playbackStore: PlaybackStateStore(directory: directory))
    let current = nativeSidebarSong("current")
    player.currentTrack = current
    player.queueManager.replaceQueue(with: [current], startingAt: 0)
    let state = SidebarArtworkScrollState()
    let key = SidebarArtworkOccurrenceKey(sessionID: UUID(), playbackID: UUID(), videoID: "current", occurrenceID: "one")
    state.synchronizeOccurrence(key)
    state.savedOffsetY = 500

    let recSong = nativeSidebarSong("rec-1")
    let data = RecommendedData(similarSongs: [recSong], loadedVideoId: "current")
    let viewport = NativeSidebarRecommendationsViewport(player: player, router: nil, heroHeight: 500, state: state,
        occurrenceKey: key, data: data, loading: false, error: nil, liked: [], playing: false,
        currentVideoID: "current", requestKey: nil)

    let coordinator = viewport.makeCoordinator()
    let scroll = viewport.makeScrollView(coordinator: coordinator)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = scroll
    scroll.frame = NSRect(x: 0, y: 0, width: 380, height: 400)
    scroll.layoutSubtreeIfNeeded()
    let table = try #require(scroll.documentView as? NSTableView)
    table.layoutSubtreeIfNeeded()
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
    coordinator.scrolled()
    (scroll as? NativeSidebarScrollView)?.layoutHeroLayers()

    // 1. Verify hit testing returns buttons / table content and never passive feed blur
    let refreshCell = try #require(table.view(atColumn: 0, row: 1, makeIfNecessary: true))
    let refreshBtn = try #require(refreshCell.subviews.compactMap { $0 as? NSButton }.first)
    let refreshCenterInWindow = refreshBtn.convert(NSPoint(x: refreshBtn.bounds.midX, y: refreshBtn.bounds.midY), to: nil)
    let hitRefresh = window.contentView?.hitTest(refreshCenterInWindow)
    #expect(hitRefresh === refreshBtn, "Clicks on recommendations controls must reach the button, not blur material")

    // 2. Verify track row cell has + button beside heart
    let trackRow = 3 // row 0: hero, row 1: refresh, row 2: heading, row 3: track
    let trackCell = try #require(table.view(atColumn: 0, row: trackRow, makeIfNecessary: true) as? NativeQueueTrackCellView)
    trackCell.setFrameSize(NSSize(width: 380, height: 54))
    trackCell.layoutSubtreeIfNeeded()
    trackCell.updateHover(isHovered: true)

    let plus = try #require(trackCell.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "NativeQueueTrackAddToQueue" })
    let like = try #require(trackCell.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "NativeQueueTrackLike" })
    let dislike = try #require(trackCell.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "NativeQueueTrackDislike" })
    let duration = try #require(trackCell.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == "NativeQueueTrackDuration" })

    #expect(!plus.isHidden, "Plus button must be revealed on hover")
    #expect(!like.isHidden)
    #expect(!dislike.isHidden)
    #expect(duration.isHidden, "Plus takes the duration slot while the row is active")

    // Geometry check: dislike < like < plus, same size
    let plusFrame = trackCell.convert(plus.bounds, from: plus)
    let likeFrame = trackCell.convert(like.bounds, from: like)
    let dislikeFrame = trackCell.convert(dislike.bounds, from: dislike)
    let durationFrame = trackCell.convert(duration.bounds, from: duration)

    #expect(dislikeFrame.maxX <= likeFrame.minX, "Dislike sits to the left of like")
    #expect(likeFrame.maxX <= plusFrame.minX, "Plus sits to the right of like")
    #expect(abs(plusFrame.width - likeFrame.width) < 1 && abs(dislikeFrame.width - likeFrame.width) < 1, "All three share one size")
    #expect(abs((plusFrame.minX - likeFrame.maxX) - (likeFrame.minX - dislikeFrame.maxX)) < 0.5, "Even spacing")
    _ = durationFrame

    // 3. Clicking plus enqueues the song into player queueManager
    #expect(player.queueManager.queue.count == 1)
    plus.sendAction(plus.action!, to: plus.target)
    for _ in 0..<20 {
        if player.queueManager.queue.count == 2 { break }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(player.queueManager.queue.count == 2)
    #expect(player.queueManager.queue[1].videoId == recSong.videoId)

    NativeSidebarRecommendationsViewport.dismantleNSView(scroll, coordinator: coordinator)
    window.contentView = nil
    window.close()
}
}
