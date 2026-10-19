import AppKit
import SwiftUI
import XCTest
import SideBCore
@testable import SideB

private final class SidebarStyleCore: SideBCore, @unchecked Sendable {
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
}

@MainActor private final class SidebarStyleFixture {
    let router = NavigationRouter()
    let account = AccountViewModel()
    let library = LibraryViewModel()
    let host: NSHostingView<AnyView>
    let window: NSWindow
    var searchOpened = 0

    init() {
        account.isLoggedIn = true
        account.account = AccountInfoRecord(name: "Side B", handle: "@collection", email: nil, thumbnail: nil, channelId: nil)
        library.playlists = (0..<120).map {
            BrowseCardRecord(kind: "playlist", id: "playlist-\($0)", title: "Playlist \($0)",
                subtitle: "Your collection • 24 tracks", thumbnail: nil, duration: nil)
        }
        library.albums = [BrowseCardRecord(kind: "album", id: "album-1", title: "Album title",
            subtitle: "Artist", thumbnail: nil, duration: nil)]
        host = NSHostingView(rootView: AnyView(EmptyView()))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: ShellLayout.sidebarWidth, height: 650)
        host.appearance = NSAppearance(named: .darkAqua)
        window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.rootView = AnyView(SidebarView(isExpanded: .constant(true), titlebarHeight: 32,
            router: router, accountViewModel: account, libraryViewModel: library,
            rustCore: SidebarStyleCore(), cookieStorage: CookieStorage(),
            onOpenSearch: { [weak self] in self?.searchOpened += 1 }, onOpenLogin: {}, onLogout: {})
            .background(AppTheme.homeSolidBackground).preferredColorScheme(.dark))
    }
    func close() { window.contentView = nil; window.close() }
    func settle() async {
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    func descendants(_ view: NSView? = nil) -> [NSView] {
        let view = view ?? host
        return [view] + view.subviews.flatMap { descendants($0) }
    }
    func scrollView() throws -> NSScrollView { try XCTUnwrap(descendants().compactMap { $0 as? NSScrollView }.first) }
    func capture(_ name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["SIDEB_SIDEBAR_REVIEW_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
    }
}

@MainActor final class SidebarStyleTests: XCTestCase {
    private let preferences = HomeAppearance.preferences
    private var previousStyle: Any?

    override func setUp() {
        super.setUp()
        previousStyle = preferences.object(forKey: SidebarStyle.preferenceKey)
        preferences.removeObject(forKey: SidebarStyle.preferenceKey)
    }
    override func tearDown() {
        if let previousStyle { preferences.set(previousStyle, forKey: SidebarStyle.preferenceKey) }
        else { preferences.removeObject(forKey: SidebarStyle.preferenceKey) }
        super.tearDown()
    }

    func testCollectionIsDefaultAndOldCurrentPreferenceFallsBackWithoutLosingSavedGrid() {
        let router = NavigationRouter(), account = AccountViewModel(), library = LibraryViewModel()
        func sidebar() -> SidebarView {
            SidebarView(isExpanded: .constant(true), router: router, accountViewModel: account,
                libraryViewModel: library, rustCore: SidebarStyleCore(), cookieStorage: CookieStorage(),
                onOpenLogin: {}, onLogout: {})
        }
        XCTAssertEqual(sidebar().sidebarStyle, .collection)
        for raw in ["classic", "future-unknown-style", "collection"] {
            preferences.set(raw, forKey: SidebarStyle.preferenceKey)
            XCTAssertEqual(sidebar().sidebarStyle, .collection)
        }
        preferences.set("covers", forKey: SidebarStyle.preferenceKey)
        XCTAssertEqual(sidebar().sidebarStyle, .covers)
    }

    func testSearchSelectionOverridesExploreAncestryAndBackForwardRestoreIt() {
        for origin: PageDestination in [.home, .library, .explore(.discover), .explore(.genres), .history, .playlist(browseId: "LM")] {
            let router = NavigationRouter()
            router.navigate(to: origin)
            func sidebar(searchPresented: Bool = false) -> SidebarView {
                SidebarView(isExpanded: .constant(true), router: router,
                    accountViewModel: AccountViewModel(), libraryViewModel: LibraryViewModel(),
                    rustCore: SidebarStyleCore(), cookieStorage: CookieStorage(),
                    isSearchPresented: searchPresented, onOpenLogin: {}, onLogout: {})
            }
            let originalExploreSelection = sidebar().isExploreSelected
            XCTAssertTrue(sidebar(searchPresented: true).isSearchSelected)
            XCTAssertFalse(sidebar(searchPresented: true).isExploreSelected)
            XCTAssertFalse(sidebar(searchPresented: true).isLikedMusicSelected)
            XCTAssertEqual(sidebar().isExploreSelected, originalExploreSelection, "Closing Spotlight restores its origin")
            for query: String? in [nil, "AAA"] {
                router.navigate(to: .search(query: query))
                XCTAssertTrue(sidebar().isSearchSelected)
                XCTAssertFalse(sidebar().isExploreSelected, "Search from \(origin) must be selected alone")
                router.goBack()
                XCTAssertEqual(router.currentPage, origin)
                XCTAssertEqual(sidebar().isExploreSelected, originalExploreSelection)
                XCTAssertFalse(sidebar().isSearchSelected)
                router.goForward()
                XCTAssertTrue(sidebar().isSearchSelected)
                XCTAssertFalse(sidebar().isExploreSelected)
                router.goBack()
            }
            if originalExploreSelection {
                router.navigate(to: .album(browseId: "explore-album"))
                XCTAssertTrue(sidebar().isExploreSelected, "Details retain their Explore ancestry")
                XCTAssertFalse(sidebar().isSearchSelected)
            }
        }
    }

    func testLiveLayoutChangesKeepLibraryScrollAndPreserveSelectionAndHistory() async throws {
        let fixture = SidebarStyleFixture()
        defer { fixture.close() }
        fixture.router.navigate(to: .playlist(browseId: "playlist-4"))
        let history = fixture.router.history
        await fixture.settle()
        let originalScrollHeight = try fixture.scrollView().bounds.height
        XCTAssertGreaterThan(originalScrollHeight, 100)
        XCTAssertLessThan(originalScrollHeight, fixture.host.bounds.height - 220)
        try fixture.capture("sidebar-list")
        for style in [SidebarStyle.covers, .collection, .covers] {
            preferences.set(style.rawValue, forKey: SidebarStyle.preferenceKey)
            await fixture.settle()
            XCTAssertEqual(SidebarStyle.resolve(preferences.string(forKey: SidebarStyle.preferenceKey) ?? ""), style)
            let scroll = try fixture.scrollView()
            XCTAssertEqual(scroll.bounds.height, originalScrollHeight, accuracy: 1)
            XCTAssertGreaterThan(scroll.documentView?.bounds.height ?? 0, scroll.contentView.bounds.height)
            try fixture.capture("sidebar-\(style.rawValue)")
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
            scroll.reflectScrolledClipView(scroll.contentView)
            await fixture.settle()
            XCTAssertEqual(scroll.contentView.bounds.minY, 120, accuracy: 1)
            XCTAssertEqual(fixture.router.history, history)
            XCTAssertEqual(fixture.router.currentPage, .playlist(browseId: "playlist-4"))
            XCTAssertEqual(fixture.library.playlists.count, 120)
            XCTAssertTrue(fixture.account.isLoggedIn)
            fixture.library.selectedTab = .albums
            await fixture.settle()
            XCTAssertEqual(fixture.library.selectedTab, .albums)
            fixture.library.selectedTab = .playlists
            await fixture.settle()
        }
        XCTAssertFalse(fixture.window.isVisible)
    }

}
