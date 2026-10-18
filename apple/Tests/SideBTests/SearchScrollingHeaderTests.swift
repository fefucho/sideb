import AppKit
import SwiftUI
import SideBCore
import XCTest
@testable import SideB

private func scrollingSearchSong(_ index: Int, video: Bool = false) -> SongItemRecord {
    SongItemRecord(videoId: "\(video ? "video" : "song")-\(index)", title: "Track \(index)",
        artists: "Artist", album: "Album", duration: "3:00", thumbnail: nil,
        artistId: nil, albumId: nil, setVideoId: nil, isVideo: video, isUpload: false, library: nil)
}

private final class ScrollingSearchCore: SideBCore, @unchecked Sendable {
    let tracks = (0..<5_000).map { scrollingSearchSong($0) }
    let videos = (0..<5_000).map { scrollingSearchSong($0, video: true) }
    let catalogDelay: Duration
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { catalogDelay = .zero; super.init(unsafeFromRawPointer: pointer) }
    init(catalogDelay: Duration = .zero) { self.catalogDelay = catalogDelay; super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { false }
    override func searchCatalog(query: String, recordHistory: Bool, ignoreSpelling: Bool) async throws -> SearchCatalogRecord {
        if catalogDelay > .zero { try await Task.sleep(for: catalogDelay) }
        return SearchCatalogRecord(results: SearchResultsRecord(topSongs: [], top: [], songs: tracks + videos,
            albums: [], artists: [], playlists: []), correction: nil)
    }
    override func searchSongs(query: String, recordHistory: Bool) async throws -> [SongItemRecord] { tracks }
    override func searchVideos(query: String) async throws -> [SongItemRecord] { videos }
    override func searchCards(query: String, category: String) async throws -> [BrowseCardRecord] { [] }
    override func searchSuggestions(query: String) async throws -> SearchSuggestionsRecord {
        SearchSuggestionsRecord(queries: [query + " first", query + " second"],
            results: SearchResultsRecord(topSongs: [], top: [], songs: [], albums: [], artists: [], playlists: []))
    }
}

@MainActor
final class SearchScrollingHeaderTests: XCTestCase {
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SearchScrollingHeader-" + UUID().uuidString)
        let defaultsName = "SearchScrollingHeader." + UUID().uuidString
        let core: ScrollingSearchCore
        let store: SearchRecentStore
        let model: SearchViewModel
        let player: PlayerViewModel
        let router = NavigationRouter()
        let window: NSWindow
        let host: NSHostingView<SearchView>

        init(filter: SearchFilter, core: ScrollingSearchCore = ScrollingSearchCore()) {
            self.core = core
            store = SearchRecentStore(directory: directory.appendingPathComponent("recents"))
            model = SearchViewModel(recentStore: store)
            model.selectedFilter = filter
            let defaults = UserDefaults(suiteName: defaultsName)!
            player = PlayerViewModel(rustCore: nil,
                audioService: AudioPlayerService(preferences: defaults, preferencePrefix: "test"),
                playbackStore: PlaybackStateStore(directory: directory.appendingPathComponent("playback")), searchRecents: store)
            host = NSHostingView(rootView: SearchView(initialQuery: "", rustCore: core,
                playerViewModel: player, router: router, searchViewModel: model))
            window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 1000, height: 400),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
        }

        func close() {
            model.clear()
            player.audioService.stop()
            window.contentView = nil
            window.close()
            UserDefaults.standard.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func scrollAncestors(of view: NSView) -> [NSScrollView] {
        var parent = view.superview
        var result: [NSScrollView] = []
        while let current = parent {
            if let scroll = current as? NSScrollView { result.append(scroll) }
            parent = current.superview
        }
        return result
    }

    private func field(in fixture: Fixture) throws -> NSTextField {
        try XCTUnwrap(descendants(fixture.host).compactMap { $0 as? NSTextField }
            .first { $0.isEditable && !$0.isHiddenOrHasHiddenAncestor })
    }

    private func settle(_ fixture: Fixture, until condition: () -> Bool = { true }) async {
        let deadline = ContinuousClock.now + .seconds(2)
        repeat {
            fixture.host.layoutSubtreeIfNeeded()
            fixture.host.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        } while !condition() && ContinuousClock.now < deadline
        // SwiftUI geometry observations update the native row on a following turn.
        for _ in 0..<4 {
            fixture.host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }

    private func captureIfRequested(_ fixture: Fixture, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["SIDEB_LAYOUT_REVIEW_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(fixture.host.bitmapImageRepForCachingDisplay(in: fixture.host.bounds))
        fixture.host.cacheDisplay(in: fixture.host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("search-\(name).png"))
    }

    func testMixedAndEveryCardCategoryPlaceTheHeaderInTheResultsViewport() async throws {
        for filter: SearchFilter in [.all, .albums, .artists, .playlists] {
            let fixture = Fixture(filter: filter)
            defer { fixture.close() }
            fixture.model.committedQuery = "Fixture"
            fixture.model.query = "Fixture"
            if filter == .all {
                fixture.model.committedResults = SearchResultsRecord(topSongs: [], top: [],
                    songs: Array(fixture.core.tracks.prefix(5)) + Array(fixture.core.videos.prefix(4)),
                    albums: [], artists: [], playlists: [])
            } else {
                let kind = filter == .artists ? "artist" : filter == .albums ? "album" : "playlist"
                fixture.model.filteredCards = (0..<100).map {
                    BrowseCardRecord(kind: kind, id: "\(kind)-\($0)", title: "Card \($0)",
                        subtitle: "Artist", thumbnail: nil, duration: nil)
                }
            }
            await settle(fixture)
            let field = try field(in: fixture)
            let scroll = try XCTUnwrap(field.enclosingScrollView, "\(filter) must scroll the actual search field")
            XCTAssertTrue(scrollAncestors(of: scroll).isEmpty, "The results must not have an outer vertical scroll")
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
            try captureIfRequested(fixture, name: "\(filter)-top")
            let before = field.convert(field.bounds, to: fixture.host)
            let originalOffset = scroll.contentView.bounds.minY
            scroll.contentView.scroll(to: NSPoint(x: 0, y: originalOffset + 70))
            scroll.reflectScrolledClipView(scroll.contentView)
            fixture.host.layoutSubtreeIfNeeded()
            let after = field.convert(field.bounds, to: fixture.host)
            XCTAssertEqual(abs(after.minY - before.minY), 70, accuracy: 1, "\(filter) must move its header with results")
            XCTAssertLessThanOrEqual(scroll.bounds.height, fixture.host.bounds.height + 1)
            try captureIfRequested(fixture, name: "\(filter)-scrolled")
            XCTAssertFalse(fixture.window.isVisible)
        }
    }

    func testTrackHeadersScrollInTheNativeDocumentAndFiveThousandRowsStayBounded() async throws {
        for filter: SearchFilter in [.songs, .videos] {
            let fixture = Fixture(filter: filter)
            defer { fixture.close() }
            fixture.model.commitSearch(query: "Fixture", core: fixture.core)
            await settle(fixture, until: { !fixture.model.isCommittedLoading && !fixture.model.isSongsLoading && !fixture.model.isVideosLoading })
            let field = try field(in: fixture)
            let table = try XCTUnwrap(descendants(fixture.host).compactMap { $0 as? NativeTrackTableViewInternal }.first)
            let scroll = try XCTUnwrap(table.enclosingScrollView)
            XCTAssertTrue(field.enclosingScrollView === scroll)
            XCTAssertTrue(scrollAncestors(of: scroll).isEmpty)
            XCTAssertNil(table.headerView, "A pinned AppKit header would reproduce the reported bug")
            XCTAssertEqual(table.numberOfRows, 5_001)
            XCTAssertEqual(table.coordinator?.parent.rowItems.first, .scrollingHeader)
            XCTAssertLessThanOrEqual(scroll.contentView.bounds.height, 400)
            XCTAssertGreaterThan(table.bounds.height, 200_000)
            XCTAssertLessThan(descendants(table).filter { $0 is NativeTrackRowView }.count, 35)
            try captureIfRequested(fixture, name: "\(filter)-top")
            let header = table.rect(ofRow: 0)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: header.maxY + 1))
            scroll.reflectScrolledClipView(scroll.contentView)
            fixture.host.layoutSubtreeIfNeeded()
            XCTAssertFalse(header.intersects(table.visibleRect))
            XCTAssertGreaterThan(scroll.contentView.bounds.minY, header.maxY)
            XCTAssertLessThan(descendants(table).filter { $0 is NativeTrackRowView }.count, 35)
            try captureIfRequested(fixture, name: "\(filter)-scrolled")
            XCTAssertFalse(fixture.window.isVisible)
        }
    }

    func testHeaderFieldKeepsTheSameHorizontalOriginInSwiftUIAndNativeResults() async throws {
        var referenceX: CGFloat?
        for filter: SearchFilter in [.all, .songs, .videos, .albums, .artists, .playlists] {
            let fixture = Fixture(filter: filter)
            defer { fixture.close() }
            await settle(fixture)
            let field = try field(in: fixture)
            let x = field.convert(field.bounds, to: fixture.host).minX
            if let referenceX { XCTAssertEqual(x, referenceX, accuracy: 1, "Header alignment must survive \(filter)") }
            else { referenceX = x }
        }
    }

    func testLoadingKeepsTheHeaderInTheSameViewportUntilResultsArrive() async throws {
        for filter: SearchFilter in [.all, .songs, .videos, .albums] {
            let fixture = Fixture(filter: filter, core: ScrollingSearchCore(catalogDelay: .milliseconds(500)))
            defer { fixture.close() }
            fixture.model.commitSearch(query: "Fixture", core: fixture.core)
            await settle(fixture)
            XCTAssertTrue(fixture.model.isCommittedLoading)
            let field = try field(in: fixture)
            let scroll = try XCTUnwrap(field.enclosingScrollView)
            XCTAssertTrue(scrollAncestors(of: scroll).isEmpty)
            XCTAssertLessThanOrEqual(scroll.bounds.height, fixture.host.bounds.height + 1)
            let table = scroll.documentView as? NativeTrackTableViewInternal
            if filter == .songs || filter == .videos {
                XCTAssertEqual(table?.numberOfRows, 2, "Loading follows the header inside the native document")
            }
            await settle(fixture, until: { !fixture.model.isCommittedLoading })
            XCTAssertTrue(try self.field(in: fixture) === field, "Loading must not replace the editor")
            XCTAssertTrue(field.enclosingScrollView === scroll)
        }
    }

    func testEmptyAndErrorsKeepTheSameScrollingHeaderAndEditorWhileResultsChange() async throws {
        let fixture = Fixture(filter: .songs)
        defer { fixture.close() }
        await settle(fixture)
        let field = try field(in: fixture)
        let table = try XCTUnwrap(descendants(fixture.host).compactMap { $0 as? NativeTrackTableViewInternal }.first)
        XCTAssertEqual(table.numberOfRows, 2, "Empty state follows the scrolling header in the same document")
        fixture.model.filteredSongs = Array(fixture.core.tracks.prefix(100))
        await settle(fixture, until: { table.numberOfRows == 101 })
        XCTAssertTrue(try self.field(in: fixture) === field)
        let collapsedHeaderHeight = table.rect(ofRow: 0).height
        XCTAssertTrue(fixture.window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("sample", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        await settle(fixture, until: { fixture.model.associatedQuickQuery == "sample" })
        XCTAssertGreaterThan(table.rect(ofRow: 0).height, collapsedHeaderHeight + 80,
            "The native scrolling row must reserve the rendered suggestion panel's height")
        editor.setSelectedRange(NSRange(location: 1, length: 3))
        let initialHeaderHeight = table.rect(ofRow: 0).height
        fixture.model.filteredSongs = []
        fixture.model.partialErrors = [.songs: "Fixture error"]
        await settle(fixture, until: { table.numberOfRows == 2 })
        XCTAssertTrue(try self.field(in: fixture) === field)
        XCTAssertTrue(fixture.window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 3))
        XCTAssertEqual(fixture.model.query, "sample")
        XCTAssertEqual(fixture.model.associatedQuickQuery, "sample")
        XCTAssertEqual(fixture.model.querySuggestions, ["sample first", "sample second"])
        XCTAssertGreaterThan(table.rect(ofRow: 0).height, initialHeaderHeight, "Partial error belongs inside the scrolling header")
        XCTAssertTrue(fixture.store.entries.isEmpty, "Typing and rendering must not record a committed query")
        try captureIfRequested(fixture, name: "suggestions-and-partial-error")
        // The hidden native window does not publish SwiftUI button AX nodes.
        // Exercise the real commit/history path separately; mouse activation
        // and VoiceOver against a visible application remain manual QA.
        // The page's submit action also leaves the editor before committing.
        // Mirror that focus boundary so query observation cannot start a new
        // preview for the changed text while this fixture is still editing.
        XCTAssertTrue(fixture.window.makeFirstResponder(nil))
        await settle(fixture)
        fixture.model.commitSearch(query: "sample first", core: fixture.core, origin: .submit)
        await settle(fixture, until: { fixture.model.committedQuery == "sample first" && !fixture.model.isCommittedLoading })
        XCTAssertEqual(fixture.store.entries.first?.query, "sample first")
        XCTAssertFalse(fixture.model.isTopdownVisible)
    }

    func testChangingBetweenNativeFiltersPreservesTheFocusedDraftAndSuggestions() async throws {
        let fixture = Fixture(filter: .songs)
        defer { fixture.close() }
        fixture.model.commitSearch(query: "Fixture", core: fixture.core)
        await settle(fixture, until: { !fixture.model.isCommittedLoading && !fixture.model.isSongsLoading })
        let field = try field(in: fixture)
        let table = try XCTUnwrap(descendants(fixture.host).compactMap { $0 as? NativeTrackTableViewInternal }.first)
        XCTAssertTrue(fixture.window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("uncommitted", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        await settle(fixture, until: { fixture.model.associatedQuickQuery == "uncommitted" })
        editor.setSelectedRange(NSRange(location: 2, length: 4))
        fixture.model.selectFilter(.videos, core: fixture.core)
        await settle(fixture, until: { !fixture.model.isVideosLoading })
        XCTAssertTrue(descendants(fixture.host).contains { $0 === table })
        XCTAssertTrue(try self.field(in: fixture) === field)
        XCTAssertTrue(fixture.window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 4))
        XCTAssertEqual(fixture.model.query, "uncommitted")
        XCTAssertEqual(fixture.model.committedQuery, "Fixture")
        XCTAssertEqual(fixture.model.associatedQuickQuery, "uncommitted")
        XCTAssertEqual(fixture.model.querySuggestions, ["uncommitted first", "uncommitted second"])
        XCTAssertTrue(fixture.store.entries.isEmpty)
    }

}
