import AppKit
import SwiftUI
import XCTest
import SideBCore
@testable import SideB

@MainActor final class LibraryCollectionViewportTests: XCTestCase {
    private func cards(_ count: Int, kind: String = "album") -> [BrowseCardRecord] {
        (0..<count).map { BrowseCardRecord(kind: kind, id: "\(kind)-\($0)", title: "Title \($0)", subtitle: "Subtitle \($0)", thumbnail: nil, duration: nil) }
    }
    private func viewport(_ cards: [BrowseCardRecord], list: Bool = false, tab: String = "Álbumes", account: UInt = 1, offset: Binding<CGFloat> = .constant(0), onOpen: @escaping (BrowseCardRecord) -> Void = { _ in }, onPlay: @escaping (BrowseCardRecord) -> Void = { _ in }, onPin: @escaping (BrowseCardRecord) -> Void = { _ in }) -> LibraryCollectionViewport {
        LibraryCollectionViewport(cards: cards, tab: tab, accountRevision: account, list: list, scrollOffset: offset,
            onOpen: onOpen, onPlay: onPlay, onPin: onPin, menuProvider: { card in NSMenu(title: card.id) })
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func layout(_ scroll: NSScrollView, _ coordinator: LibraryCollectionViewport.Coordinator) {
        scroll.frame.size = NSSize(width: 1000, height: 760)
        scroll.layoutSubtreeIfNeeded(); coordinator.updateGeometry()
        scroll.documentView?.needsLayout = true; scroll.documentView?.layoutSubtreeIfNeeded(); scroll.documentView?.viewWillDraw()
        descendants(scroll).forEach { $0.layoutSubtreeIfNeeded() }
    }
    func testVerticalGeometryMatchesViewportAndWholeDocument() throws {
        let view = viewport(cards(5000))
        let coordinator = view.makeCoordinator()
        let scroll = view.makeScrollView(coordinator:coordinator)
        defer { LibraryCollectionViewport.dismantleNSView(scroll,coordinator:coordinator) }
        layout(scroll,coordinator)
        let collection = try XCTUnwrap(scroll.documentView as? NSCollectionView)
        let flow = try XCTUnwrap(collection.collectionViewLayout as? NSCollectionViewFlowLayout)
        XCTAssertEqual(flow.scrollDirection,.vertical)
        XCTAssertGreaterThan(flow.itemSize.width,160)
        XCTAssertEqual(collection.frame.width,scroll.contentView.bounds.width,accuracy:1)
        XCTAssertGreaterThan(collection.frame.height,scroll.contentView.bounds.height)
        XCTAssertLessThan(collection.visibleItems().count,85)
    }
    func testFiveThousandCollectionsRecycleGridAndListViewport() throws {
        for kind in ["album", "playlist", "artist"] {
            for list in [false, true] {
                let view = viewport(cards(5000, kind: kind), list: list)
                let coordinator = view.makeCoordinator()
                let mountedScroll = view.makeScrollView(coordinator: coordinator)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = mountedScroll
                defer { LibraryCollectionViewport.dismantleNSView(mountedScroll, coordinator: coordinator); window.contentView = nil; window.close() }
                layout(mountedScroll, coordinator)
                let collection = try XCTUnwrap(mountedScroll.documentView as? NSCollectionView)
                let flow = try XCTUnwrap(collection.collectionViewLayout as? NSCollectionViewFlowLayout)
                XCTAssertEqual(collection.numberOfItems(inSection: 0), 5000)
                var maximum = 0
                for index in stride(from: 0, through: 4900, by: 350) {
                    let rect = try XCTUnwrap(flow.layoutAttributesForItem(at: IndexPath(item: index, section: 0))).frame
                    mountedScroll.contentView.scroll(to: NSPoint(x: 0, y: rect.minY)); mountedScroll.reflectScrolledClipView(mountedScroll.contentView)
                    layout(mountedScroll, coordinator)
                    let cells = descendants(collection).compactMap { $0 as? LibraryCollectionCell }
                    maximum = max(maximum, cells.count)
                    XCTAssertGreaterThan(cells.count, 0); XCTAssertLessThan(cells.count, 85)
                    XCTAssertGreaterThanOrEqual(collection.indexPathsForVisibleItems().map(\.item).min() ?? -1, index - 7)
                    XCTAssertFalse(descendants(collection).contains { String(describing: type(of: $0)).contains("NSHosting") })
                }
                XCTAssertFalse(window.isVisible)
                print("LIBRARY_5000 kind=\(kind) list=\(list) maxMounted=\(maximum)")
            }
        }
    }
    func testPlaybackAndPinsPreserveCellsAndOffsetWhileAccountAndTabRestoreSavedPosition() throws {
        var offset: CGFloat = 900
        let binding = Binding(get: { offset }, set: { offset = $0 })
        var view = viewport(cards(200), offset: binding)
        let coordinator = view.makeCoordinator()
        let mountedScroll = view.makeScrollView(coordinator: coordinator)
        defer { LibraryCollectionViewport.dismantleNSView(mountedScroll, coordinator: coordinator) }
        layout(mountedScroll, coordinator)
        let collection = try XCTUnwrap(mountedScroll.documentView as? NSCollectionView)
        let configured = coordinator.configuredItems
        let mounted = Dictionary(uniqueKeysWithValues: collection.indexPathsForVisibleItems().compactMap { index in collection.item(at: index).map { (index, $0.view) } })
        XCTAssertFalse(mounted.isEmpty)
        view.isPlaying = true; view.queueContext = .album(browseId: "album-0", title: "Title 0"); view.pinned = ["album:album-0"]
        view.updateScrollView(mountedScroll, coordinator: coordinator)
        XCTAssertEqual(coordinator.configuredItems, configured)
        for (index, cell) in mounted { XCTAssertTrue(collection.item(at: index)?.view === cell) }
        XCTAssertEqual(mountedScroll.contentView.bounds.minY, 900, accuracy: 1)
        var other = viewport(cards(200), tab: "Playlists", account: 1, offset: .constant(350))
        other.updateScrollView(mountedScroll, coordinator: coordinator); layout(mountedScroll, coordinator)
        XCTAssertEqual(mountedScroll.contentView.bounds.minY, 350, accuracy: 1)
        other = viewport(cards(200), tab: "Playlists", account: 2, offset: .constant(0))
        other.updateScrollView(mountedScroll, coordinator: coordinator); layout(mountedScroll, coordinator)
        XCTAssertEqual(mountedScroll.contentView.bounds.minY, 0, accuracy: 1)
    }
    func testRecycledCallbacksMatchCardAndObscuredControlsCannotAct() throws {
        for list in [false, true] {
            var opened: [String] = [], played: [String] = [], pinned: [String] = []
            var view = viewport(cards(2), list: list, onOpen: { opened.append($0.id) }, onPlay: { played.append($0.id) }, onPin: { pinned.append($0.id) })
            let coordinator = view.makeCoordinator(), item = LibraryCollectionItem()
            item.view.frame = NSRect(x: 0, y: 0, width: 300, height: list ? 68 : 350)
            for index in [0, 1] {
                coordinator.configure(item, at: IndexPath(item: index, section: 0)); item.cell.layoutSubtreeIfNeeded()
                if list { item.cell.row?.title.performClick(nil); item.cell.row?.play.performClick(nil) }
                else {
                    item.cell.cardView.cardButton.performClick(nil); item.cell.cardView.setHovered(true)
                    try XCTUnwrap(item.cell.cardView.subviews.compactMap { $0 as? HomePlayHitButton }.first).performClick(nil)
                }
                item.cell.pin.performClick(nil)
            }
            XCTAssertEqual(opened, ["album-0", "album-1"]); XCTAssertEqual(played, opened); XCTAssertEqual(pinned, opened)
            view.isObscured = true; coordinator.parent = view
            coordinator.configure(item, at: IndexPath(item: 1, section: 0)); item.cell.pin.performClick(nil); coordinator.open(at: IndexPath(item: 1, section: 0))
            if list { item.cell.row?.title.performClick(nil); item.cell.row?.play.performClick(nil) }
            else { item.cell.cardView.cardButton.performClick(nil) }
            XCTAssertEqual(opened.count, 2); XCTAssertEqual(played.count, 2); XCTAssertEqual(pinned.count, 2)
            item.cell.prepareForReuse(); item.cell.pin.performClick(nil)
            XCTAssertEqual(pinned.count, 2)
        }
    }
    func testArtistCoverOpensWithoutPlayControlAndRecycledPlaylistRestoresPlay() throws {
        let item = LibraryCollectionItem()
        item.view.frame = NSRect(x:0,y:0,width:200,height:330)
        var opened:[String] = [], played:[String] = []
        var view = viewport(cards(1,kind:"artist"),onOpen:{ opened.append($0.id) },onPlay:{ played.append($0.id) })
        let coordinator = view.makeCoordinator()
        coordinator.configure(item,at:IndexPath(item:0,section:0)); item.cell.layoutSubtreeIfNeeded()
        item.cell.cardView.setHovered(true)
        let play = try XCTUnwrap(item.cell.cardView.subviews.compactMap { $0 as? HomePlayHitButton }.first)
        XCTAssertTrue(play.isHidden)
        item.cell.cardView.cardButton.performClick(nil)
        XCTAssertEqual(opened,["artist-0"]); XCTAssertTrue(played.isEmpty)
        item.cell.prepareForReuse()
        view = viewport(cards(1,kind:"playlist"),onOpen:{ opened.append($0.id) },onPlay:{ played.append($0.id) })
        coordinator.parent = view
        coordinator.configure(item,at:IndexPath(item:0,section:0)); item.cell.layoutSubtreeIfNeeded()
        item.cell.cardView.setHovered(true)
        XCTAssertFalse(play.isHidden)
        play.performClick(nil)
        XCTAssertEqual(played,["playlist-0"])
    }
    func testDeepOffsetClampsWhenFilterShrinksAndLayoutChangesRemainScrollable() throws {
        var view = viewport(cards(5000),offset:.constant(20000))
        let coordinator = view.makeCoordinator()
        let scroll = view.makeScrollView(coordinator:coordinator)
        defer { LibraryCollectionViewport.dismantleNSView(scroll,coordinator:coordinator) }
        layout(scroll,coordinator)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY,19000)
        view = viewport(cards(3))
        view.updateScrollView(scroll,coordinator:coordinator); layout(scroll,coordinator)
        XCTAssertEqual(scroll.contentView.bounds.minY,0,accuracy:1)
        view = viewport(cards(5000),list:true)
        view.updateScrollView(scroll,coordinator:coordinator); layout(scroll,coordinator)
        let collection = try XCTUnwrap(scroll.documentView as? NSCollectionView)
        XCTAssertGreaterThan(collection.frame.height,scroll.contentView.bounds.height)
        XCTAssertGreaterThan(collection.visibleItems().count,0)
        XCTAssertLessThan(collection.visibleItems().count,24)
    }
    func testProjectionCacheDoesNotRepeatFilterSortForPlaybackOrScroll() {
        let cache = LibraryCardProjectionCache(), source = cards(5000)
        var computations = 0
        func project(_ input: [BrowseCardRecord], query: String = "", order: String = "name") -> [BrowseCardRecord] {
            cache.cards(input, query: query, order: order) { computations += 1; return input.reversed() }
        }
        for _ in 0..<60 { _ = project(source) }
        XCTAssertEqual(computations, 1)
        _ = project(source, query: "Title 1"); _ = project(source, query: "Title 1", order: "original")
        var changed = source; changed[0].title = "Changed"; _ = project(changed)
        XCTAssertEqual(computations, 4)
    }
}
