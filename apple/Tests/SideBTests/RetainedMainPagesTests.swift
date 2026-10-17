import AppKit
import SideBCore
import SwiftUI
import XCTest
@testable import SideB

@MainActor private final class PageProbes {
    var views: [String: NSScrollView] = [:]
    var created: [String: Int] = [:]
    var retired: [String: Int] = [:]
    var updates: [String: Int] = [:]
    var active: [String: Bool] = [:]
    var menus: [String: AppMenuContext] = [:]
    var backgrounds: [String: CollectionBackgroundController] = [:]
}

private struct PageProbe: NSViewRepresentable {
    let name: String
    let probes: PageProbes
    @Environment(\.sideBPageIsActive) private var active
    @Environment(\.sideBMenuContext) private var menuContext
    @Environment(\.collectionBackgroundController) private var backgroundController
    func makeCoordinator() -> Coordinator { Coordinator(name: name, probes: probes) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 2000))
        scroll.documentView = document
        probes.created[name, default: 0] += 1
        probes.views[name] = scroll
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        probes.updates[name, default: 0] += 1
        probes.active[name] = active
        probes.menus[name] = menuContext
        probes.backgrounds[name] = backgroundController
        scroll.isHidden = !active
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? 600)
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.probes.retired[coordinator.name, default: 0] += 1
    }
    @MainActor final class Coordinator {
        let name: String
        let probes: PageProbes
        init(name: String, probes: PageProbes) { self.name = name; self.probes = probes }
    }
}

@MainActor final class RetainedMainPagesTests: XCTestCase {
    func testViewportResizesKeepNativePageIdentityAndScroll() throws {
        let probes = PageProbes()
        let host = NSHostingView(rootView: RetainedMainPages(page: .home,
            home: { PageProbe(name: "home", probes: probes) },
            explore: { _ in PageProbe(name: "explore", probes: probes) },
            library: { PageProbe(name: "library", probes: probes) },
            detail: { EmptyView() }))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1512, height: 700)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        let home = try XCTUnwrap(probes.views["home"])
        home.contentView.scroll(to: NSPoint(x: 0, y: 210))
        let updates = probes.updates["home", default: 0]
        // Same contents, with intermediate widths and interrupted reversals.
        let closing: [CGFloat] = (0..<40).map { 1512 - CGFloat($0) * 6 }
        let opening: [CGFloat] = (0..<40).map { 1278 + CGFloat($0) * 6 }
        let widths: [CGFloat] = closing + opening + [899, 960, 1100, 1512]
        for width in widths {
            host.frame.size.width = width
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(home.frame.width, width, accuracy: 0.5)
            XCTAssertEqual(home.contentView.bounds.minY, 210, accuracy: 0.5)
        }
        let extraUpdates = probes.updates["home", default: 0] - updates
        print("Retained viewport: \(widths.count) resizes, \(extraUpdates) content updates")
        XCTAssertEqual(extraUpdates, 0, "Geometry alone must not reconfigure the native document")
        XCTAssertEqual(probes.created["home"], 1)
        XCTAssertNil(probes.views["explore"])
        XCTAssertNil(probes.views["library"])
    }

    func testRetainedPagesReceiveCurrentWindowServicesAcrossNavigation() throws {
        let probes = PageProbes()
        let menus = AppMenuContext(), replacementMenus = AppMenuContext()
        let background = CollectionBackgroundController(), replacementBackground = CollectionBackgroundController()
        func shell(_ page: PageDestination, menus: AppMenuContext,
                   background: CollectionBackgroundController) -> some View {
            RetainedMainPages(page: page,
                home: { PageProbe(name: "home", probes: probes) },
                explore: { _ in PageProbe(name: "explore", probes: probes) },
                library: { PageProbe(name: "library", probes: probes) },
                detail: { EmptyView() })
                .environment(\.sideBMenuContext, menus)
                .environment(\.collectionBackgroundController, background)
        }
        let host = NSHostingView(rootView: shell(.home, menus: menus, background: background))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        host.layoutSubtreeIfNeeded()
        for page: PageDestination in [.explore(.discover), .library, .home] {
            host.rootView = shell(page, menus: menus, background: background)
            host.layoutSubtreeIfNeeded()
        }
        for name in ["home", "explore", "library"] {
            XCTAssertTrue(probes.menus[name] === menus)
            XCTAssertTrue(probes.backgrounds[name] === background)
            XCTAssertEqual(probes.created[name], 1)
        }
        host.rootView = shell(.library, menus: replacementMenus, background: replacementBackground)
        host.layoutSubtreeIfNeeded()
        for name in ["home", "explore", "library"] {
            XCTAssertTrue(probes.menus[name] === replacementMenus)
            XCTAssertTrue(probes.backgrounds[name] === replacementBackground)
            XCTAssertEqual(probes.created[name], 1)
        }
    }

    func testVisitedNativePagesKeepTheirIdentityAndScrollAcrossRoutesAndResizes() throws {
        let probes = PageProbes()
        func shell(_ page: PageDestination, session: Int = 1, covered: Bool = false) -> some View {
            RetainedMainPages(page: page, isCovered: covered,
                home: { PageProbe(name: "home", probes: probes) },
                explore: { _ in PageProbe(name: "explore", probes: probes) },
                library: { PageProbe(name: "library", probes: probes) },
                detail: { PageProbe(name: "detail", probes: probes) })
                .id(session)
        }
        let host = NSHostingView(rootView: shell(.home))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 700)
        host.layoutSubtreeIfNeeded()
        let home = try XCTUnwrap(probes.views["home"])
        func pageHost(for view: NSView) -> RetainedPageHostView? {
            var ancestor = view.superview
            while let view = ancestor {
                if let host = view as? RetainedPageHostView { return host }
                ancestor = view.superview
            }
            return nil
        }
        let homeHost = try XCTUnwrap(pageHost(for: home))
        XCTAssertTrue(homeHost.accessibilityActive)
        XCTAssertTrue(homeHost.accessibilityChildren()?.first as? NSView === homeHost.hostedView)
        XCTAssertTrue(homeHost.hostedView.safeAreaRegions.isEmpty)
        XCTAssertNil(probes.views["explore"])
        XCTAssertNil(probes.views["library"])
        home.contentView.scroll(to: NSPoint(x: 0, y: 210))
        for page: PageDestination in [.explore(.discover), .library, .home, .album(browseId: "album"), .library, .home] {
            host.rootView = shell(page)
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(probes.views["home"] === home)
            XCTAssertEqual(home.contentView.bounds.minY, 210, accuracy: 0.5)
        }
        XCTAssertEqual(probes.created["home"], 1)
        XCTAssertEqual(probes.created["explore"], 1)
        XCTAssertEqual(probes.created["library"], 1)
        XCTAssertNil(probes.retired["home"])
        XCTAssertNil(probes.retired["explore"])
        XCTAssertNil(probes.retired["library"])
        host.rootView = shell(.library)
        host.layoutSubtreeIfNeeded()
        let retainedSize = home.frame.size
        host.frame.size = NSSize(width: 800, height: 500)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(home.frame.size, retainedSize)
        XCTAssertEqual(homeHost.frame.size, host.frame.size)
        XCTAssertEqual(homeHost.hostedView.frame.size, retainedSize)
        XCTAssertEqual(probes.active["home"], false)
        XCTAssertEqual(probes.active["explore"], false)
        XCTAssertEqual(probes.active["library"], true)
        XCTAssertTrue(homeHost.isHidden)
        XCTAssertTrue(homeHost.accessibilityChildren()?.isEmpty == true)
        host.rootView = shell(.home)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(home.frame.size, host.frame.size)
        XCTAssertEqual(home.contentView.bounds.minY, 210, accuracy: 0.5)
        host.rootView = shell(.home, covered: true)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(probes.active["home"], false)
        XCTAssertFalse(homeHost.isHidden) // Retain the selected page for fullscreen gesture preview.
        XCTAssertFalse(homeHost.accessibilityActive)
        XCTAssertTrue(homeHost.accessibilityChildren()?.isEmpty == true)
        host.frame.size = NSSize(width: 960, height: 640)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(homeHost.frame.size, host.frame.size)
        XCTAssertEqual(homeHost.hostedView.frame.size, host.frame.size)
        host.rootView = shell(.home, session: 2)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(probes.views["home"] === home)
        XCTAssertEqual(probes.retired["home"], 1)
        XCTAssertEqual(probes.retired["explore"], 1)
        XCTAssertEqual(probes.retired["library"], 1)
    }

    func testHiddenCatalogsDeferDataAndRestoreLatestSnapshotOnTheSameNativeView() throws {
        let cards = (0..<4).map { BrowseCardRecord(kind: "album", id: "\($0)", title: "Album \($0)", subtitle: nil, thumbnail: nil, duration: nil) }
        func explore(_ cards: [BrowseCardRecord], hidden: Bool) -> ExploreCatalogGridView {
            ExploreCatalogGridView(cards: cards, route: .releases, sessionRevision: 1,
                isObscured: hidden, onOpen: { _ in }, onPlay: { _ in }, menuProvider: { _ in nil })
        }
        let initial = explore(Array(cards.prefix(2)), hidden: false)
        let coordinator = initial.makeCoordinator()
        let scroll = initial.makeScrollView(coordinator: coordinator)
        defer { ExploreCatalogGridView.dismantleNSView(scroll, coordinator: coordinator) }
        scroll.frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
        scroll.layoutSubtreeIfNeeded()
        explore(cards, hidden: true).updateScrollView(scroll, coordinator: coordinator)
        XCTAssertTrue(scroll.isHidden)
        XCTAssertTrue(scroll.isAccessibilityHidden())
        XCTAssertEqual(coordinator.parent.cards.count, 2)
        scroll.frame.size.width = 800
        coordinator.updateGeometry()
        explore(cards, hidden: false).updateScrollView(scroll, coordinator: coordinator)
        XCTAssertFalse(scroll.isHidden)
        XCTAssertFalse(scroll.isAccessibilityHidden())
        XCTAssertEqual(coordinator.parent.cards.count, 4)
        XCTAssertEqual(coordinator.collection?.numberOfItems(inSection: 0), 4)

        func library(_ cards: [BrowseCardRecord], hidden: Bool) -> LibraryCollectionViewport {
            LibraryCollectionViewport(cards: cards, tab: "Albums", accountRevision: 1, list: false,
                scrollOffset: .constant(0), isObscured: hidden,
                onOpen: { _ in }, onPlay: { _ in }, onPin: { _ in }, menuProvider: { _ in nil })
        }
        let libraryView = library(Array(cards.prefix(2)), hidden: false)
        let libraryCoordinator = libraryView.makeCoordinator()
        let libraryScroll = libraryView.makeScrollView(coordinator: libraryCoordinator)
        defer { LibraryCollectionViewport.dismantleNSView(libraryScroll, coordinator: libraryCoordinator) }
        libraryScroll.frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
        libraryScroll.layoutSubtreeIfNeeded()
        library(cards, hidden: true).updateScrollView(libraryScroll, coordinator: libraryCoordinator)
        XCTAssertTrue(libraryScroll.isHidden)
        XCTAssertTrue(libraryScroll.isAccessibilityHidden())
        XCTAssertEqual(libraryCoordinator.parent.cards.count, 2)
        let configured = libraryCoordinator.configuredItems
        libraryScroll.frame.size.width = 800
        libraryCoordinator.updateGeometry()
        XCTAssertEqual(libraryCoordinator.configuredItems, configured)
        library(cards, hidden: false).updateScrollView(libraryScroll, coordinator: libraryCoordinator)
        XCTAssertFalse(libraryScroll.isHidden)
        XCTAssertFalse(libraryScroll.isAccessibilityHidden())
        XCTAssertEqual(libraryCoordinator.collection?.numberOfItems(inSection: 0), 4)
    }

    func testRetainedTrackTableDefersHiddenRowsAndAppliesCurrentRowsWhenShown() throws {
        let tracks = (0..<4).map { SongItemRecord(videoId: "\($0)", title: "Song \($0)", artists: "Artist",
            album: nil, duration: nil, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
            isVideo: false, isUpload: false, library: nil, artistRuns: []) }
        func songs(_ count: Int, active: Bool, preview: Bool = false) -> some View {
            RetainedMainPages(page: .library, isCovered: !active,
                home: { EmptyView() }, explore: { _ in EmptyView() }, library: {
                    NativeTrackTableView(tracks: Array(tracks.prefix(count)), currentTrackVideoId: nil,
                        isPlaying: false, onPlayTrack: { _ in })
                }, detail: { EmptyView() })
                .environment(\.sideBGesturePreviewVisible, preview)
        }
        let host = NSHostingView(rootView: songs(2, active: true))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let table = try XCTUnwrap(descendants(host).compactMap { $0 as? NativeTrackTableViewInternal }.first)
        XCTAssertEqual(table.numberOfRows, 2)
        host.rootView = songs(4, active: false)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertTrue(table.enclosingScrollView?.isHidden == true)
        XCTAssertTrue(table.enclosingScrollView?.isAccessibilityHidden() == true)
        host.rootView = songs(4, active: false, preview: true)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertTrue(table.enclosingScrollView?.isHidden == false)
        XCTAssertTrue(table.enclosingScrollView?.isAccessibilityHidden() == true)
        host.rootView = songs(4, active: true)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.numberOfRows, 4)
        XCTAssertTrue(table.enclosingScrollView?.isHidden == false)
        XCTAssertTrue(table.enclosingScrollView?.isAccessibilityHidden() == false)
    }

    func testFeaturedHostingReceivesSuspensionInsteadOfDefaultActiveEnvironment() throws {
        let probes = PageProbes()
        let player = PlayerViewModel()
        func feed(_ hidden: Bool) -> HomeFeedTableView {
            HomeFeedTableView(featuredContent: { _ in AnyView(PageProbe(name: "featured", probes: probes)) },
                featuredHeight: { _ in 120 }, sections: [], isObscured: hidden, revision: 1,
                selectedChip: nil, hasMore: false, isLoadingMore: false, currentTrackID: nil,
                isPlaying: false, player: player, router: nil, onNavigate: { _ in }, onLoadMore: {})
        }
        let original = feed(false)
        XCTAssertFalse(feed(true).makeCoordinator().featuredViewport.isActive)
        let coordinator = original.makeCoordinator()
        let scroll = original.makeNativeScrollView(coordinator: coordinator)
        defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
        scroll.frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
        scroll.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        let row = try XCTUnwrap(coordinator.tableView(table, viewFor: table.tableColumns.first, row: 0))
        table.addSubview(row)
        row.frame = NSRect(x: 0, y: 0, width: 1000, height: 120)
        row.layoutSubtreeIfNeeded()
        XCTAssertEqual(probes.active["featured"], true)
        feed(true).updateNativeScrollView(scroll, coordinator: coordinator)
        row.layoutSubtreeIfNeeded()
        XCTAssertEqual(probes.active["featured"], false)
        XCTAssertTrue(scroll.isAccessibilityHidden())
        feed(false).updateNativeScrollView(scroll, coordinator: coordinator)
        row.layoutSubtreeIfNeeded()
        XCTAssertEqual(probes.active["featured"], true)
        XCTAssertFalse(scroll.isAccessibilityHidden())
        XCTAssertEqual(probes.created["featured"], 1)
    }
}
