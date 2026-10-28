import AppKit
import SwiftUI
import SideBCore
import XCTest
@testable import SideB

final class RecommendedRequestTests: XCTestCase {
    private func key(_ video: String = "A", account: UUID, album: String? = nil) -> RecommendedRequestState.Key {
        .init(videoID: video, artistID: "artist", albumID: album, account: account)
    }
    func testTabAndMountShareThePendingRequest() throws {
        var state = RecommendedRequestState()
        let key = key(account: UUID())
        let first = try XCTUnwrap(state.begin(key, force: false))
        XCTAssertNil(state.begin(key, force: false))
        XCTAssertTrue(state.owns(first))
    }
    func testRefreshAndABARejectEarlierCompletions() throws {
        var state = RecommendedRequestState()
        let account = UUID()
        let first = try XCTUnwrap(state.begin(key(account: account), force: false))
        let refresh = try XCTUnwrap(state.begin(key(account: account), force: true))
        XCTAssertFalse(state.finish(first))
        XCTAssertTrue(state.owns(refresh))
        _ = state.begin(key("B", account: account), force: false)
        let last = try XCTUnwrap(state.begin(key(account: account), force: false))
        XCTAssertFalse(state.finish(refresh))
        XCTAssertTrue(state.finish(last))
        XCTAssertNil(state.token)
    }
    func testAccountAndMetadataArePartOfLoadIdentity() throws {
        var state = RecommendedRequestState()
        let account = UUID()
        let first = try XCTUnwrap(state.begin(key(account: account), force: false))
        let metadata = try XCTUnwrap(state.begin(key(account: account, album: "album"), force: false))
        let switched = try XCTUnwrap(state.begin(key(account: UUID(), album: "album"), force: false))
        XCTAssertFalse(state.finish(first))
        XCTAssertFalse(state.finish(metadata))
        XCTAssertTrue(state.owns(switched))
    }
    func testUnmountInvalidatesRequestAndAllowsRetry() throws {
        var state = RecommendedRequestState()
        let key = key(account: UUID())
        let first = try XCTUnwrap(state.begin(key, force: false))
        state.cancel()
        XCTAssertFalse(state.finish(first))
        XCTAssertNotNil(state.begin(key, force: false))
    }
}

@MainActor final class RecommendedViewportTests: XCTestCase {
    private func track(_ id: String) -> SongItemRecord {
        SongItemRecord(videoId: id, title: "Song \(id)", artists: "Artist", album: "Album",
                       duration: "3:00", thumbnail: nil, artistId: nil, albumId: nil,
                       setVideoId: nil, isVideo: false, isUpload: false, library: nil, artistRuns: [])
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func viewport(_ data: RecommendedData, player: PlayerViewModel? = nil) -> RecommendedShelfViewport {
        RecommendedShelfViewport(data: data, player: player ?? PlayerViewModel(), router: nil)
    }
    func testProjectionKeepsOrderDuplicateOccurrencesAndPartialLastColumn() throws {
        let songs = [track("a"), track("a"), track("b"), track("c")]
        let data = RecommendedData(artistSongs: songs, similarSongs: [track("b")], loadedVideoId: "origin")
        let shelves = RecommendedShelf.make(from: data)
        XCTAssertEqual(shelves.map(\.kind), [.artist, .similar])
        XCTAssertEqual(shelves[0].items.count, 2)
        let projected = shelves[0].items.flatMap { item -> [RecommendedShelf.Song] in
            if case .songs(let songs) = item { return songs }; return []
        }
        XCTAssertEqual(projected.map(\.track.videoId), ["a", "a", "b", "c"])
        XCTAssertEqual(Set(projected.map(\.id)).count, 4)
        // Three 52pt rows and two 6pt gaps must fit: the old162pt viewport clipped the last row.
        XCTAssertEqual(shelves[0].contentHeight, 52 * 3 + 6 * 2)
        XCTAssertTrue(RecommendedShelf.make(from: RecommendedData()).isEmpty)
    }
    func testThousandsOfTracksMountOnlyVisibleColumns() throws {
        let data = RecommendedData(similarSongs: (0..<3000).map { track(String($0)) }, loadedVideoId: "origin")
        let feed = viewport(data)
        let coordinator = feed.makeCoordinator()
        let scroll = feed.makeScrollView(coordinator: coordinator)
        defer { RecommendedShelfViewport.dismantleNSView(scroll, coordinator: coordinator) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.orderOut(nil) }
        scroll.frame = NSRect(x: 0, y: 0, width: 580, height: 400)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        table.frame.size.width = 580
        table.reloadData()
        table.layoutSubtreeIfNeeded()
        let shelf = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? RecommendedNativeShelf)
        shelf.frame = NSRect(x: 0, y: 0, width: 580, height: 218)
        shelf.layoutSubtreeIfNeeded()
        shelf.collection.layoutSubtreeIfNeeded()
        XCTAssertEqual(shelf.collection.numberOfItems(inSection: 0), 1000)
        let horizontal = try XCTUnwrap(descendants(shelf).compactMap { $0 as? NSScrollView }.first)
        var maximumMounted = 0
        for index in stride(from: 0, to: 990, by: 90) {
            horizontal.contentView.scroll(to: NSPoint(x: CGFloat(index) * 284, y: 0))
            horizontal.reflectScrolledClipView(horizontal.contentView)
            shelf.collection.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
            let mounted = shelf.collection.visibleItems().compactMap { $0 as? RecommendedHostedItem }
            let visibleIndices = shelf.collection.indexPathsForVisibleItems().map(\.item)
            XCTAssertGreaterThanOrEqual(visibleIndices.min() ?? -1, max(0, index - 1))
            maximumMounted = max(maximumMounted, mounted.count)
            XCTAssertTrue(mounted.allSatisfy(\.hasContent))
        }
        XCTAssertGreaterThan(maximumMounted, 0)
        XCTAssertLessThan(maximumMounted, 12)
        XCTAssertLessThan(shelf.configuredItemCount, 150)
        print("RELATED_REUSE tracks=3000 columns=1000 maxVisible=\(maximumMounted) configured=\(shelf.configuredItemCount)")
        shelf.suspend()
        XCTAssertTrue(shelf.collection.visibleItems().compactMap { $0 as? RecommendedHostedItem }.allSatisfy { !$0.hasContent })
    }
    func testSameSnapshotKeepsNativeShelfAndHorizontalPosition() throws {
        let player = PlayerViewModel()
        let data = RecommendedData(similarSongs: (0..<60).map { track(String($0)) }, loadedVideoId: "a")
        let feed = viewport(data, player: player)
        let coordinator = feed.makeCoordinator()
        let scroll = feed.makeScrollView(coordinator: coordinator)
        defer { RecommendedShelfViewport.dismantleNSView(scroll, coordinator: coordinator) }
        scroll.frame = NSRect(x: 0, y: 0, width: 580, height: 400)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        table.frame.size.width = 580
        let shelf = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? RecommendedNativeShelf)
        shelf.frame.size = NSSize(width: 580, height: 218)
        shelf.layoutSubtreeIfNeeded()
        let horizontal = try XCTUnwrap(descendants(shelf).compactMap { $0 as? NSScrollView }.first)
        horizontal.contentView.scroll(to: NSPoint(x: 450, y: 0))
        feed.update(scroll, coordinator: coordinator)
        XCTAssertTrue(table.view(atColumn: 0, row: 0, makeIfNecessary: false) === shelf)
        XCTAssertEqual(horizontal.contentView.bounds.minX, 450, accuracy: 1)
        XCTAssertEqual(coordinator.offsets[.similar] ?? -1, 450, accuracy: 1)
        let replacement = viewport(RecommendedData(similarSongs: [track("new")], loadedVideoId: "b"), player: player)
        replacement.update(scroll, coordinator: coordinator)
        XCTAssertTrue(coordinator.offsets.isEmpty)
        XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
    }
    func testVerticalReentryRestoresMountedColumnsAndHorizontalOffset() throws {
        let tracks = (0..<60).map { track(String($0)) }
        let feed = viewport(RecommendedData(artistSongs: tracks, albumSongs: tracks, similarSongs: tracks, loadedVideoId: "a"))
        let coordinator = feed.makeCoordinator()
        let scroll = feed.makeScrollView(coordinator: coordinator)
        defer { RecommendedShelfViewport.dismantleNSView(scroll, coordinator: coordinator) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 220), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.orderOut(nil) }
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        scroll.layoutSubtreeIfNeeded()
        table.layoutSubtreeIfNeeded()
        let first = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? RecommendedNativeShelf)
        first.layoutSubtreeIfNeeded()
        let horizontal = try XCTUnwrap(descendants(first).compactMap { $0 as? NSScrollView }.first)
        horizontal.contentView.scroll(to: NSPoint(x: 450, y: 0))
        horizontal.reflectScrolledClipView(horizontal.contentView)
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        XCTAssertEqual(coordinator.offsets[.artist] ?? -1, 450, accuracy: 1)
        for offset: CGFloat in [430, 0, 430, 0] {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
            table.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        let restored = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? RecommendedNativeShelf)
        restored.layoutSubtreeIfNeeded()
        let restoredScroll = try XCTUnwrap(descendants(restored).compactMap { $0 as? NSScrollView }.first)
        XCTAssertEqual(restoredScroll.contentView.bounds.minX, 450, accuracy: 1)
        let visible = restored.collection.visibleItems().compactMap { $0 as? RecommendedHostedItem }
        XCTAssertFalse(visible.isEmpty)
        XCTAssertTrue(visible.allSatisfy(\.hasContent))
    }

    func testLateAlbumMetadataChangesTheMountedLoadKey() throws {
        let player = PlayerViewModel()
        player.currentTrack = track("a")
        let original = try XCTUnwrap(player.recommendationContextKey)
        player.currentAlbumBrowseId = "album"
        let hydrated = try XCTUnwrap(player.recommendationContextKey)
        XCTAssertNotEqual(original, hydrated)
        XCTAssertEqual(original.account, hydrated.account)
        XCTAssertEqual(hydrated.albumID, "album")
    }

    func testFourShelvesRenderAtCompactAndWideWidths() throws {
        let player = PlayerViewModel()
        player.recommendedData = RecommendedData(artistName: "Artista", artistBrowseId: "artist",
            artistSongs: (0..<9).map { track(String($0)) }, albumTitle: "Álbum", albumBrowseId: "album",
            albumSongs: (10..<19).map { track(String($0)) }, similarSongs: (20..<29).map { track(String($0)) },
            relatedArtists: (0..<8).map { BrowseCardRecord(kind: "artist", id: "artist-\($0)", title: "Artista \($0)", subtitle: nil, thumbnail: nil, duration: nil) },
            loadedVideoId: "origin")
        let router = NavigationRouter()
        for width: CGFloat in [340, 600] {
            let host = NSHostingView(rootView: RecommendedContentView(viewModel: player, router: router, height: 760)
                .padding(12).background(Color(red: 0.13, green: 0.10, blue: 0.14)).preferredColorScheme(.dark))
            host.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 784), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: width, height: 784)
            host.layoutSubtreeIfNeeded()
            for view in descendants(host) { view.layoutSubtreeIfNeeded() }
            let table = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTableView }.first)
            XCTAssertEqual(table.numberOfRows, 4)
            XCTAssertGreaterThan(table.bounds.width, width - 60)
            if let folder = ProcessInfo.processInfo.environment["SIDEB_RELATED_CAPTURE_DIR"] {
                let directory = URL(fileURLWithPath: folder, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                host.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("related-\(Int(width)).png"))
            }
            window.orderOut(nil)
        }
    }

    func testChangingOrClearingTrackRetiresPreviousRecommendationData() {
        let player = PlayerViewModel()
        player.currentTrack = track("a")
        player.recommendedData = RecommendedData(similarSongs: [track("other")], loadedVideoId: "a")
        player.recommendedTracks = [track("other")]
        player.isLoadingRecommended = true
        player.currentTrack = track("b")
        XCTAssertNil(player.recommendedData)
        XCTAssertTrue(player.recommendedTracks.isEmpty)
        XCTAssertFalse(player.isLoadingRecommended)
        player.recommendedData = RecommendedData(similarSongs: [track("other")], loadedVideoId: "b")
        player.currentTrack = nil
        XCTAssertNil(player.recommendedData)
    }

    func testViewportUsesProposedSizeAndCancelsLoadingWithoutCore() throws {
        let player = PlayerViewModel()
        let feed = viewport(RecommendedData(), player: player)
        let host = NSHostingView(rootView: feed)
        host.sizingOptions = []
        for size in [NSSize(width: 600, height: 450), NSSize(width: 340, height: 280)] {
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
            XCTAssertEqual(scroll.frame.size.width, size.width, accuracy: 1)
            XCTAssertEqual(scroll.frame.size.height, size.height, accuracy: 1)
        }
        player.isLoadingRecommended = true
        player.fetchRecommendations(for: track("a"))
        XCTAssertFalse(player.isLoadingRecommended)
    }
}
