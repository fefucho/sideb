import AppKit
import SideBCore
import SwiftUI
import XCTest
@testable import SideB

@MainActor final class ExploreCatalogGridTests: XCTestCase {
    private func cards(_ count: Int) -> [BrowseCardRecord] {
        (0..<count).map { .init(kind: "album", id: "MPRE-\($0)", title: "Album \($0)", subtitle: "Album • Artist",
                              thumbnail: nil, duration: nil) }
    }

    private func grid(_ cards: [BrowseCardRecord], session: Int = 1,
                      axis: ExploreCatalogGridView.Axis = .vertical,
                      onOpen: @escaping (BrowseCardRecord) -> Void = { _ in },
                      onPlay: @escaping (BrowseCardRecord) -> Void = { _ in }) -> ExploreCatalogGridView {
        ExploreCatalogGridView(cards: cards, route: .releases, sessionRevision: session, axis: axis,
                               onOpen: onOpen, onPlay: onPlay, menuProvider: { card in
            let menu = NSMenu(title: card.id)
            menu.addItem(withTitle: card.title, action: nil, keyEquivalent: "")
            return menu
        })
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func layout(_ scroll: NSScrollView, _ coordinator: ExploreCatalogGridView.Coordinator,
                        size: NSSize = NSSize(width: 1000, height: 760)) {
        scroll.frame.size = size
        scroll.layoutSubtreeIfNeeded()
        coordinator.updateGeometry()
        // Fixture windows stay hidden. Deliver the native layout/display
        // lifecycle explicitly, without opening or driving the user's UI.
        scroll.documentView?.needsLayout = true
        scroll.documentView?.layoutSubtreeIfNeeded()
        scroll.documentView?.viewWillDraw()
        descendants(scroll).forEach { $0.layoutSubtreeIfNeeded() }
    }

    func testFiveThousandAlbumsMountOnlyTheViewport() throws {
        let view = grid(cards(5000))
        let coordinator = view.makeCoordinator()
        let scroll = view.makeScrollView(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.contentView = nil; window.close() }
        defer { ExploreCatalogGridView.dismantleNSView(scroll, coordinator: coordinator) }
        layout(scroll, coordinator)
        let collection = try XCTUnwrap(scroll.documentView as? NSCollectionView)
        let flow = try XCTUnwrap(collection.collectionViewLayout as? NSCollectionViewFlowLayout)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 5000)
        var maximumMounted = 0
        for index in stride(from: 0, through: 4980, by: 140) {
            let rect = try XCTUnwrap(flow.layoutAttributesForItem(at: IndexPath(item: index, section: 0))).frame
            scroll.contentView.scroll(to: NSPoint(x: 0, y: rect.minY))
            scroll.reflectScrolledClipView(scroll.contentView)
            layout(scroll, coordinator)
            XCTAssertGreaterThanOrEqual(collection.indexPathsForVisibleItems().map(\.item).min() ?? -1, index - 7)
            let mounted = descendants(collection).compactMap { $0 as? HomeItemView }
            maximumMounted = max(maximumMounted, mounted.count)
            XCTAssertFalse(mounted.isEmpty)
            XCTAssertLessThan(mounted.count, 80)
        }
        XCTAssertFalse(window.isVisible)
        print("EXPLORE_5000 maxMounted=\(maximumMounted) configured=\(coordinator.configuredItems)")
    }

    func testPlaybackAndMetadataRefreshKeepNativeCardsAndScroll() throws {
        var view = grid(cards(101))
        let coordinator = view.makeCoordinator()
        let scroll = view.makeScrollView(coordinator: coordinator)
        defer { ExploreCatalogGridView.dismantleNSView(scroll, coordinator: coordinator) }
        layout(scroll, coordinator)
        let collection = try XCTUnwrap(scroll.documentView as? NSCollectionView)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 900))
        scroll.reflectScrolledClipView(scroll.contentView)
        layout(scroll, coordinator)
        let mounted = Dictionary(uniqueKeysWithValues: collection.indexPathsForVisibleItems().compactMap { index in
            collection.item(at: index).map { (index, $0.view) }
        })
        XCTAssertFalse(mounted.isEmpty)
        let configured = coordinator.configuredItems
        view.isPlaying = true
        view.queueContext = .album(browseId: "MPRE-0", title: "Album")
        view.updateScrollView(scroll, coordinator: coordinator)
        XCTAssertEqual(coordinator.configuredItems, configured) // Player state never rebuilds/rebinds album data.
        for (index, original) in mounted { XCTAssertTrue(collection.item(at: index)?.view === original) }
        XCTAssertEqual(scroll.contentView.bounds.minY, 900, accuracy: 1)

        let index = try XCTUnwrap(mounted.keys.first)
        var updated = view.cards
        updated[index.item].title = "Updated album"
        var refreshed = grid(updated)
        refreshed.isPlaying = true
        refreshed.queueContext = view.queueContext
        refreshed.updateScrollView(scroll, coordinator: coordinator)
        layout(scroll, coordinator)
        for (index, original) in mounted { XCTAssertTrue(collection.item(at: index)?.view === original) }
        let card = try XCTUnwrap(collection.item(at: index) as? HomeCollectionItem)
        XCTAssertTrue(card.content.cardButton.accessibilityLabel()?.contains("Updated album") == true)
        XCTAssertEqual(scroll.contentView.bounds.minY, 900, accuracy: 1)
    }

    func testResizePreservesFlatItemIdentityAndSessionResetReturnsToTop() throws {
        let view = grid(cards(101))
        let coordinator = view.makeCoordinator()
        let scroll = view.makeScrollView(coordinator: coordinator)
        defer { ExploreCatalogGridView.dismantleNSView(scroll, coordinator: coordinator) }
        layout(scroll, coordinator)
        let collection = try XCTUnwrap(scroll.documentView as? NSCollectionView)
        let first = try XCTUnwrap(collection.item(at: IndexPath(item: 0, section: 0)))
        for size in [NSSize(width: 1100, height: 760), NSSize(width: 1250, height: 760), NSSize(width: 900, height: 760)] {
            layout(scroll, coordinator, size: size)
            XCTAssertTrue(collection.item(at: IndexPath(item: 0, section: 0)) === first)
            XCTAssertEqual(collection.numberOfItems(inSection: 0), 101)
        }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1200))
        scroll.reflectScrolledClipView(scroll.contentView)
        layout(scroll, coordinator)
        grid(cards(101), session: 2).updateScrollView(scroll, coordinator: coordinator)
        layout(scroll, coordinator)
        XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
        XCTAssertFalse(scroll.hasHorizontalScroller)
    }

    func testRecycledActionsAndLoadingMatchTheDisplayedAlbum() throws {
        var opened: [String] = [], played: [String] = []
        var view = grid(cards(2), onOpen: { opened.append($0.id) }, onPlay: { played.append($0.id) })
        let coordinator = view.makeCoordinator()
        let item = HomeCollectionItem()
        item.view.frame = NSRect(x: 0, y: 0, width: 180, height: 274)
        for index in [0, 1] {
            coordinator.configure(item, at: IndexPath(item: index, section: 0))
            item.content.layoutSubtreeIfNeeded()
            item.content.cardButton.performClick(nil)
            item.content.setHovered(true)
            let play = try XCTUnwrap(item.content.subviews.compactMap { $0 as? HomePlayHitButton }.first)
            play.performClick(nil)
        }
        XCTAssertEqual(opened, ["MPRE-0", "MPRE-1"])
        XCTAssertEqual(played, ["MPRE-0", "MPRE-1"])
        view.loadingAlbumID = "MPRE-1"
        coordinator.parent = view
        coordinator.configure(item, at: IndexPath(item: 1, section: 0))
        let play = try XCTUnwrap(item.content.subviews.compactMap { $0 as? HomePlayHitButton }.first)
        XCTAssertFalse(play.isEnabled)
        XCTAssertEqual(item.content.subviews.compactMap { $0 as? NSProgressIndicator }.count, 1)
        item.content.prepareForReuse()
        XCTAssertTrue(play.isEnabled)
        XCTAssertFalse(item.content.subviews.contains { $0 is NSProgressIndicator })
        view.loadingAlbumID = nil
        view.isObscured = true
        coordinator.parent = view
        coordinator.configure(item, at: IndexPath(item: 1, section: 0))
        item.content.cardButton.performClick(nil)
        play.performClick(nil)
        coordinator.open(at: IndexPath(item: 1, section: 0))
        XCTAssertEqual(opened, ["MPRE-0", "MPRE-1"])
        XCTAssertEqual(played, ["MPRE-0", "MPRE-1"])
    }

    func testHorizontalPreviewAndSwiftUIBridgeHaveExplicitViewportSizes() throws {
        let preview = grid(cards(12), axis: .horizontal)
        let coordinator = preview.makeCoordinator()
        let scroll = preview.makeScrollView(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 264),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.contentView = nil; window.close() }
        defer { ExploreCatalogGridView.dismantleNSView(scroll, coordinator: coordinator) }
        layout(scroll, coordinator, size: NSSize(width: 800, height: 264))
        let collection = try XCTUnwrap(scroll.documentView as? NSCollectionView)
        let flow = try XCTUnwrap(collection.collectionViewLayout as? NSCollectionViewFlowLayout)
        XCTAssertGreaterThan(flow.collectionViewContentSize.width, scroll.contentView.bounds.width)
        XCTAssertFalse(scroll.hasVerticalScroller)
        XCTAssertTrue(scroll.hasHorizontalScroller)
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
        let last = try XCTUnwrap(flow.layoutAttributesForItem(at: IndexPath(item: 11, section: 0)))
        let first = try XCTUnwrap(flow.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(first.frame.minY, last.frame.minY, accuracy: 1)
        scroll.contentView.scroll(to: NSPoint(x: last.frame.minX, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        layout(scroll, coordinator, size: NSSize(width: 800, height: 264))
        XCTAssertGreaterThan(scroll.contentView.bounds.minX, 0)
        XCTAssertTrue(collection.indexPathsForVisibleItems().contains(IndexPath(item: 11, section: 0)))
        XCTAssertFalse(window.isVisible)

        let host = NSHostingView(rootView: grid(cards(5000)).frame(maxWidth: .infinity, maxHeight: .infinity))
        host.sizingOptions = []
        for size in [NSSize(width: 1100, height: 760), NSSize(width: 700, height: 480)] {
            host.frame.size = size
            host.layoutSubtreeIfNeeded()
            let viewport = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
            XCTAssertEqual(viewport.frame.width, size.width, accuracy: 1)
            XCTAssertEqual(viewport.frame.height, size.height, accuracy: 1)
        }
    }

    func testEmptyAndLoadedCatalogKeepOneMeasuredScrollingHeader() async throws {
        var view = grid([])
        view.header = AnyView(Text("Lanzamientos").padding(30))
        view.headerIdentity = .init(route: .releases, session: 1, loading: true, error: nil, empty: true)
        let coordinator = view.makeCoordinator()
        let scroll = view.makeScrollView(coordinator: coordinator)
        defer { ExploreCatalogGridView.dismantleNSView(scroll, coordinator: coordinator) }
        layout(scroll, coordinator)
        for _ in 0..<5 { await Task.yield(); layout(scroll, coordinator) }
        let header = try XCTUnwrap(descendants(scroll).compactMap { $0 as? ExploreCatalogHeaderView }.first)
        let flow = try XCTUnwrap(coordinator.layout)
        XCTAssertGreaterThan(flow.headerReferenceSize.height, 60)
        XCTAssertLessThan(flow.headerReferenceSize.height, 110)
        view.header = AnyView(Text("Loaded").padding(50))
        view.headerIdentity = .init(route: .releases, session: 1, loading: false, error: nil, empty: false)
        view = ExploreCatalogGridView(cards: cards(101), route: view.route, sessionRevision: view.sessionRevision,
            header: view.header, headerIdentity: view.headerIdentity, onOpen: { _ in }, onPlay: { _ in }, menuProvider: { _ in nil })
        view.updateScrollView(scroll, coordinator: coordinator)
        layout(scroll, coordinator)
        for _ in 0..<5 { await Task.yield(); layout(scroll, coordinator) }
        XCTAssertEqual(descendants(scroll).compactMap { $0 as? ExploreCatalogHeaderView }.count, 1)
        XCTAssertGreaterThan(flow.headerReferenceSize.height, 100)
        XCTAssertLessThan(flow.headerReferenceSize.height, 150)
        XCTAssertEqual(coordinator.collection?.numberOfItems(inSection: 0), 101)
        // The original empty header can be recycled, with a single hosting subtree.
        XCTAssertLessThanOrEqual(descendants(scroll).filter { $0 is NSHostingView<AnyView> }.count, 1)
        _ = header
    }
}
