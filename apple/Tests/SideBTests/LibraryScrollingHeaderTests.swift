import AppKit
import SwiftUI
import XCTest
import SideBCore
@testable import SideB

private final class LibraryScrollingCore: SideBCore, @unchecked Sendable {
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { true }
    override func getLibraryPlaylists() async throws -> [BrowseCardRecord] { Self.cards("playlist") }
    override func getLibraryAlbums() async throws -> [BrowseCardRecord] { Self.cards("album") }
    override func getLibraryArtists() async throws -> [BrowseCardRecord] { Self.cards("artist") }
    override func getHistory() async throws -> [HistoryGroupRecord] { [] }
    override func getLibrarySongs() async throws -> PlaylistContinuationRecord {
        PlaylistContinuationRecord(items: (0..<180).map { index in
            SongItemRecord(videoId: "song-\(index)", title: "Song \(index)", artists: "Artist", album: nil,
                           duration: nil, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
                           isVideo: false, isUpload: false, library: nil, artistRuns: [])
        }, continuation: nil)
    }
    private static func cards(_ kind: String) -> [BrowseCardRecord] {
        (0..<180).map { BrowseCardRecord(kind: kind, id: "\(kind)-\($0)", title: "Collection \($0)",
                                       subtitle: "Artist", thumbnail: nil, duration: nil) }
    }
}

@MainActor private final class LibraryScrollingFixture {
    let defaultsName = "LibraryScrollingHeader.\(UUID())"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryScrollingHeader-" + UUID().uuidString)
    let core = LibraryScrollingCore()
    let library: LibraryViewModel
    let player: PlayerViewModel
    let host: NSHostingView<LibraryView>
    let window: NSWindow

    init(tab: LibraryPageTab, list: Bool = false, width: CGFloat = 1100) async {
        let defaults = UserDefaults(suiteName: defaultsName)!
        library = LibraryViewModel(preferences: defaults)
        library.configureAccount(identity: "fixture")
        library.selectedPageTab = tab; library.collectionList = list
        await library.ensureSelectedPageTab(core: core)
        let account = AccountViewModel(); account.isLoggedIn = true
        let store = SearchRecentStore(directory: directory.appendingPathComponent("recents"))
        player = PlayerViewModel(rustCore: nil,
            audioService: AudioPlayerService(preferences: defaults, preferencePrefix: "fixture"),
            playbackStore: PlaybackStateStore(directory: directory.appendingPathComponent("playback")), searchRecents: store)
        host = NSHostingView(rootView: LibraryView(rustCore: core, playerViewModel: player,
            libraryViewModel: library, accountViewModel: account, router: NavigationRouter()))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: width, height: 760)
        window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.appearance = NSAppearance(named: .darkAqua)
        await settle()
    }
    func close() {
        player.audioService.stop()
        window.contentView = nil; window.close()
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
        try? FileManager.default.removeItem(at: directory)
    }
    func settle() async {
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    func descendants(_ view: NSView? = nil) -> [NSView] {
        let view = view ?? host
        return [view] + view.subviews.flatMap { descendants($0) }
    }
    func categoryMarker() throws -> WindowGestureRegionView {
        try XCTUnwrap(descendants().compactMap { $0 as? WindowGestureRegionView }.first {
            if case .horizontalContent = $0.region { return true }; return false
        })
    }
    func verticalOwners(of view: NSView) -> [NSScrollView] {
        var current = view.superview
        var owners: [NSScrollView] = []
        while let ancestor = current {
            if let scroll = ancestor as? NSScrollView,
               scroll.hasVerticalScroller || (scroll.documentView?.bounds.height ?? 0) > scroll.contentView.bounds.height + 2 {
                owners.append(scroll)
            }
            current = ancestor.superview
        }
        return owners
    }
    func capture(_ name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SIDEB_LAYOUT_REVIEW_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
}

@MainActor final class LibraryScrollingHeaderTests: XCTestCase {
    func testHeaderAndCategoriesMoveWithTheOnlyVerticalViewportInEveryTab() async throws {
        for (tab, list) in [(LibraryPageTab.all, false), (.playlists, false), (.albums, false), (.artists, false),
                            (.playlists, true), (.albums, true), (.artists, true), (.songs, false)] {
            let fixture = await LibraryScrollingFixture(tab: tab, list: list)
            defer { fixture.close() }
            let marker = try fixture.categoryMarker()
            let owners = fixture.verticalOwners(of: marker)
            XCTAssertEqual(owners.count, 1, "Header must share one vertical scroll with \(tab), list=\(list)")
            let scroll = try XCTUnwrap(owners.first)
            XCTAssertEqual(scroll.frame.height, fixture.host.bounds.height, accuracy: 1)
            XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).bounds.height, scroll.contentView.bounds.height + 90)
            if let collection = scroll.documentView as? NSCollectionView {
                XCTAssertEqual(collection.numberOfItems(inSection: 0), 180)
                XCTAssertLessThan(collection.visibleItems().count, 30)
            }
            if let table = scroll.documentView as? NSTableView {
                XCTAssertEqual(table.numberOfRows, 181) // One header and 180 virtual rows.
                XCTAssertLessThan(fixture.descendants(table).compactMap { $0 as? NativeTrackCellView }.count, 30)
            }
            try fixture.capture("library-\(tab.rawValue)-\(list)-top")
            let before = marker.convert(marker.bounds, to: fixture.host)
            let originalOffset = scroll.contentView.bounds.minY
            scroll.contentView.scroll(to: NSPoint(x: 0, y: originalOffset + 90))
            scroll.reflectScrolledClipView(scroll.contentView)
            await fixture.settle()
            XCTAssertNotNil(marker.superview)
            let after = marker.convert(marker.bounds, to: fixture.host)
            XCTAssertEqual(abs(before.midY - after.midY), 90, accuracy: 1)
            XCTAssertEqual(scroll.contentView.bounds.minY, originalOffset + 90, accuracy: 1)
            try fixture.capture("library-\(tab.rawValue)-\(list)-scrolled")
            XCTAssertFalse(fixture.window.isVisible)
        }
    }

    func testCatalogSearchFieldStaysAttachedAndFocusedThroughEmptyFilterAndGridListChange() async throws {
        let fixture = await LibraryScrollingFixture(tab: .albums)
        defer { fixture.close() }
        let header = try XCTUnwrap(fixture.descendants().compactMap { $0 as? LibraryCollectionHeaderView }.first)
        let field = try XCTUnwrap(fixture.descendants(header).compactMap { $0 as? NSTextField }.first { $0.isEditable })
        XCTAssertTrue(fixture.window.makeFirstResponder(field))
        let editor = try XCTUnwrap(fixture.window.firstResponder as? NSTextView)
        fixture.library.libraryQuery = "no collection matches this"
        await fixture.settle()
        XCTAssertTrue(fixture.descendants().contains { $0 === header })
        XCTAssertTrue(fixture.descendants(header).contains { $0 === field })
        XCTAssertTrue(fixture.window.firstResponder === editor)
        let collection = try XCTUnwrap(header.superview as? NSCollectionView)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 0)
        fixture.library.libraryQuery = "Collection 1"; fixture.library.collectionList = true
        await fixture.settle()
        XCTAssertTrue(fixture.window.firstResponder === editor)
        XCTAssertTrue(field.isDescendant(of: header))
        XCTAssertGreaterThan(collection.numberOfItems(inSection: 0), 0)
        XCTAssertLessThan(collection.visibleItems().count, 25)
        XCTAssertFalse(fixture.window.isVisible)
    }

    func testSongsSearchFieldKeepsFocusAndHeaderWhenResultsBecomeEmpty() async throws {
        let fixture = await LibraryScrollingFixture(tab: .songs)
        defer { fixture.close() }
        let table = try XCTUnwrap(fixture.descendants().compactMap { $0 as? NSTableView }.first)
        let header = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: false) as? NativeTrackFooterCellView)
        let field = try XCTUnwrap(fixture.descendants(header).compactMap { $0 as? NSTextField }.first { $0.isEditable })
        XCTAssertTrue(fixture.window.makeFirstResponder(field))
        let editor = try XCTUnwrap(fixture.window.firstResponder as? NSTextView)
        fixture.library.libraryQuery = "no songs match this"
        await fixture.settle()
        XCTAssertEqual(table.numberOfRows, 2) // Header and empty-results footer share the same table.
        XCTAssertTrue(table.view(atColumn: 0, row: 0, makeIfNecessary: false) === header)
        XCTAssertTrue(fixture.window.firstResponder === editor)
        fixture.library.libraryQuery = "Song 1"
        await fixture.settle()
        XCTAssertGreaterThan(table.numberOfRows, 2)
        XCTAssertTrue(fixture.window.firstResponder === editor)
        XCTAssertFalse(fixture.window.isVisible)
    }

    func testEmptySongFilterRendersPartialFailureAndClearsItAfterReload() async throws {
        let fixture = await LibraryScrollingFixture(tab: .songs)
        defer { fixture.close() }
        let query = "no songs match this"
        fixture.library.libraryQuery = query
        await fixture.settle()
        let table = try XCTUnwrap(fixture.descendants().compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.numberOfRows, 2)
        table.scrollRowToVisible(1)
        await fixture.settle()
        let source = fixture.library.songs
        let clean = try footerBitmap(in: table)
        fixture.library.songsErrorMessage = "Fixture continuation failed"
        await fixture.settle()
        let failed = try footerBitmap(in: table)
        XCTAssertEqual(fixture.library.songs, source)
        XCTAssertEqual(fixture.library.libraryQuery, query)
        XCTAssertNotEqual(failed, clean, "A partial error must remain visible alongside zero filter matches")
        try fixture.capture("library-songs-empty-partial-error")
        // Offscreen SwiftUI does not publish virtual AX buttons. Exercise the
        // same reload operation directly; physical Retry activation stays QA.
        await fixture.library.loadSongs(core: fixture.core)
        await fixture.settle()
        let recovered = try footerBitmap(in: table)
        XCTAssertNil(fixture.library.songsErrorMessage)
        XCTAssertEqual(fixture.library.songs, source)
        XCTAssertEqual(fixture.library.libraryQuery, query)
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(recovered, clean, "The same empty filter must return to its clean render after reload")
        XCTAssertFalse(fixture.window.isVisible)
    }

    private func footerBitmap(in table: NSTableView) throws -> Data {
        let footer = try XCTUnwrap(table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? NativeTrackFooterCellView)
        footer.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(footer.bounds.height, 200)
        let bitmap = try XCTUnwrap(footer.bitmapImageRepForCachingDisplay(in: footer.bounds))
        footer.cacheDisplay(in: footer.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 500)
        let bytes = try XCTUnwrap(bitmap.bitmapData)
        return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
}
