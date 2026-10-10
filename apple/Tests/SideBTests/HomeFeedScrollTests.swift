import AppKit
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class HomeFeedScrollTests: XCTestCase {
    private func makeFeed(hasHeader: Bool, hasMore: Bool = true, isLoadingMore: Bool = false,
                          message: String? = nil, onLoadMore: @escaping () -> Void = {}) -> HomeFeedTableView {
        HomeFeedTableView(
            headerContent: hasHeader ? AnyView(Text("Inicio y filtros")) : nil,
            headerHeight: hasHeader ? 144 : 0,
            sections: [
                HomeSectionPresentation(id: "first", title: "Primera", style: .largeCard, items: [], moreBrowseId: nil, moreParams: nil),
                HomeSectionPresentation(id: "last", title: "Última", style: .compactSong, items: [], moreBrowseId: nil, moreParams: nil)
            ],
            isObscured: false, revision: 1, selectedChip: nil, hasMore: hasMore, isLoadingMore: isLoadingMore,
            loadMoreMessage: message,
            currentTrackID: nil, isPlaying: false, player: PlayerViewModel(), router: nil,
            onNavigate: { _ in }, onLoadMore: onLoadMore
        )
    }

    func testPaginationButtonDispatchesDisablesWhileLoadingAndShowsEnd() throws {
        var clicks = 0
        let feed = makeFeed(hasHeader: false, onLoadMore: { clicks += 1 })
        let coordinator = feed.makeCoordinator()
        let scroll = feed.makeNativeScrollView(coordinator: coordinator)
        defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
        scroll.frame = NSRect(x: 0, y: 0, width: 900, height: 1000)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        table.frame.size.width = 900
        scroll.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap(coordinator.rows.loadMoreRow)
        var footer = try XCTUnwrap(table.view(atColumn: 0, row: row, makeIfNecessary: true))
        var button = try XCTUnwrap(footer.subviews.compactMap { $0 as? NSButton }.first)
        button.performClick(nil)
        XCTAssertEqual(clicks, 1)

        let loading = makeFeed(hasHeader: false, isLoadingMore: true, onLoadMore: { clicks += 1 })
        loading.updateNativeScrollView(scroll, coordinator: coordinator)
        // AppKit can replace the mounted footer during layout; inspect the current row.
        footer = try XCTUnwrap(table.view(atColumn: 0, row: row, makeIfNecessary: true))
        button = try XCTUnwrap(footer.subviews.compactMap { $0 as? NSButton }.first)
        XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(button.title, "Cargando recomendaciones…")
        button.performClick(nil)
        XCTAssertEqual(clicks, 1)

        let failed = makeFeed(hasHeader: false, message: "No se pudieron cargar más recomendaciones.",
                              onLoadMore: { clicks += 1 })
        failed.updateNativeScrollView(scroll, coordinator: coordinator)
        footer = try XCTUnwrap(table.view(atColumn: 0, row: row, makeIfNecessary: true))
        button = try XCTUnwrap(footer.subviews.compactMap { $0 as? NSButton }.first)
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(footer.subviews.contains { ($0 as? NSTextField)?.stringValue == failed.loadMoreMessage && !$0.isHidden })
        button.performClick(nil)
        XCTAssertEqual(clicks, 2)

        let ended = makeFeed(hasHeader: false, hasMore: false, message: "No hay más recomendaciones por ahora.")
        ended.updateNativeScrollView(scroll, coordinator: coordinator)
        let endRow = try XCTUnwrap(coordinator.rows.loadMoreRow)
        XCTAssertEqual(table.numberOfRows, 3)
        let endFooter = try XCTUnwrap(table.view(atColumn: 0, row: endRow, makeIfNecessary: true))
        let endButton = try XCTUnwrap(endFooter.subviews.compactMap { $0 as? NSButton }.first)
        XCTAssertTrue(endButton.isHidden)
        XCTAssertFalse(endButton.isEnabled)
        XCTAssertTrue(endFooter.subviews.contains { ($0 as? NSTextField)?.stringValue == ended.loadMoreMessage && !$0.isHidden })
    }

    func testHeaderIsARealScrollingRowAndShelvesAndPaginationKeepTheirMapping() throws {
        let feed = makeFeed(hasHeader: true)
        let coordinator = feed.makeCoordinator()
        let scroll = feed.makeNativeScrollView(coordinator: coordinator)
        defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
        scroll.frame = CGRect(x: 0, y: 0, width: 900, height: 300)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        table.frame.size.width = 900
        table.reloadData()
        XCTAssertNil(table.headerView) // AppKit must not pin the header above the document.
        XCTAssertEqual(table.numberOfRows, 4)
        XCTAssertNil(coordinator.rows.sectionIndex(forRow: 0))
        XCTAssertEqual(coordinator.rows.sectionIndex(forRow: 1), 0)
        XCTAssertEqual(coordinator.rows.sectionIndex(forRow: 2), 1)
        XCTAssertEqual(coordinator.rows.loadMoreRow, 3)
        XCTAssertTrue(coordinator.tableView(table, viewFor: table.tableColumns.first, row: 0) is NSHostingView<AnyView>)
        XCTAssertEqual(coordinator.tableView(table, viewFor: table.tableColumns.first, row: 2)?.identifier?.rawValue, "HomeShelfRow")
        XCTAssertEqual(coordinator.tableView(table, heightOfRow: 2), 284)
        XCTAssertEqual(coordinator.tableView(table, heightOfRow: 3), 68)
        let headerRect = table.rect(ofRow: 0)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: headerRect.maxY + 1))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertGreaterThanOrEqual(scroll.contentView.bounds.minY, headerRect.maxY)
        XCTAssertFalse(headerRect.intersects(table.visibleRect))
        XCTAssertFalse(scroll.hasHorizontalScroller)
        XCTAssertNil(scroll.horizontalScroller)
    }

    func testFeaturedUsesNativeViewportAtEverySidebarWidthAndRetainsHostingIdentity() throws {
        let base = makeFeed(hasHeader: true)
        let feed = HomeFeedTableView(
            headerContent: base.headerContent, headerHeight: 158,
            featuredContent: { width in AnyView(HomeFeaturedWidthProbe(width: width)) },
            featuredHeight: { HomeFeaturedLayout.height(width: $0, hasSongs: true, hasAlbums: true) },
            sections: base.sections, isObscured: false, revision: 1, selectedChip: nil,
            hasMore: true, isLoadingMore: false, currentTrackID: nil, isPlaying: false,
            player: base.player, router: nil, onNavigate: { _ in }, onLoadMore: {}
        )
        let coordinator = feed.makeCoordinator()
        let scroll = feed.makeNativeScrollView(coordinator: coordinator)
        defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        XCTAssertEqual(table.numberOfRows, 5)
        XCTAssertEqual(coordinator.rows.featuredRow, 1)
        XCTAssertNil(coordinator.rows.sectionIndex(forRow: 1))
        XCTAssertEqual(coordinator.rows.sectionIndex(forRow: 2), 0)
        XCTAssertEqual(coordinator.rows.sectionIndex(forRow: 3), 1)
        XCTAssertEqual(coordinator.rows.loadMoreRow, 4)
        let host = try XCTUnwrap(coordinator.tableView(table, viewFor: table.tableColumns.first, row: 1))
        // AppKit coordinate conversions can introduce sub-pixel floating-point error.
        // Keep this far below a visible point while still catching viewport/layout drift.
        let geometryAccuracy: CGFloat = 0.000001
        for width: CGFloat in [1100, 960, 900, 899, 820, 760, 700, 640, 820, 900, 1100] {
            scroll.frame = NSRect(x: 0, y: 0, width: width, height: 300)
            scroll.contentView.setBoundsSize(NSSize(width: width, height: 300))
            table.frame.size.width = width
            coordinator.boundsChanged(Notification(name: NSView.boundsDidChangeNotification, object: scroll.contentView))
            XCTAssertEqual(coordinator.featuredViewport.width, width, accuracy: geometryAccuracy)
            host.layoutSubtreeIfNeeded()
            let probe = try XCTUnwrap(descendants(host).compactMap { $0 as? HomeFeaturedWidthProbeView }.first)
            XCTAssertEqual(probe.renderedWidth, width, accuracy: geometryAccuracy)
            let expected = HomeFeaturedLayout.height(width: width, hasSongs: true, hasAlbums: true)
            XCTAssertEqual(coordinator.tableView(table, heightOfRow: 0), 158)
            XCTAssertEqual(coordinator.tableView(table, heightOfRow: 1), expected, accuracy: geometryAccuracy)
            XCTAssertEqual(table.rect(ofRow: 1).height, expected, accuracy: 0.5)
            XCTAssertEqual(table.rect(ofRow: 2).minY, table.rect(ofRow: 1).maxY, accuracy: 0.5)
            XCTAssertTrue(host === coordinator.tableView(table, viewFor: table.tableColumns.first, row: 1))
        }
        XCTAssertNil(scroll.window) // No app interaction or window mounting.
        XCTAssertFalse(scroll.hasHorizontalScroller)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    func testFeaturedRevisionDoesNotReloadUnchangedShelvesAndOnlyChangedShelfIsReloaded() throws {
        let base = makeFeed(hasHeader: false)
        func feed(revision: UInt64, sections: [HomeSectionPresentation]) -> HomeFeedTableView {
            HomeFeedTableView(featuredContent: { AnyView(Text("Destacados \($0)")) },
                featuredHeight: { _ in 300 }, sections: sections, isObscured: false,
                revision: revision, selectedChip: nil, hasMore: true, isLoadingMore: false,
                currentTrackID: nil, isPlaying: false, player: base.player, router: nil,
                onNavigate: { _ in }, onLoadMore: {})
        }
        let first = feed(revision: 1, sections: base.sections)
        let coordinator = first.makeCoordinator()
        let scroll = first.makeNativeScrollView(coordinator: coordinator)
        defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
        let table = HomeReloadTrackingTableView()
        table.headerView = nil
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("test")))
        table.delegate = coordinator
        table.dataSource = coordinator
        scroll.documentView = table
        coordinator.table = table
        scroll.frame = NSRect(x: 0, y: 0, width: 1100, height: 640)
        scroll.contentView.setBoundsSize(NSSize(width: 1100, height: 640))
        table.frame.size.width = 1100
        table.reloadData()
        scroll.layoutSubtreeIfNeeded()
        table.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(scroll.contentView.bounds.width, 900)
        coordinator.wasCompact = scroll.contentView.bounds.width < 760
        table.fullReloads = 0
        table.reloadedRows.removeAll()

        feed(revision: 2, sections: base.sections).updateNativeScrollView(scroll, coordinator: coordinator)
        XCTAssertEqual(table.fullReloads, 0)
        XCTAssertTrue(table.reloadedRows.isEmpty)

        var changed = base.sections
        changed[1] = HomeSectionPresentation(id: "updated", title: "Actualizada", style: .compactSong,
            items: [], moreBrowseId: nil, moreParams: nil)
        feed(revision: 3, sections: changed).updateNativeScrollView(scroll, coordinator: coordinator)
        XCTAssertEqual(table.fullReloads, 0)
        XCTAssertEqual(table.reloadedRows, [IndexSet(integer: 2)]) // Feature row + second shelf.

        feed(revision: 4, sections: Array(changed.prefix(1))).updateNativeScrollView(scroll, coordinator: coordinator)
        XCTAssertEqual(table.fullReloads, 1)
        XCTAssertEqual(table.numberOfRows, 3)
        XCTAssertNil(scroll.window)
    }

    func testRemountReconcilesCachedHeightEvenWhenDelegateBuiltAtNewWidthFirst() throws {
        let base = makeFeed(hasHeader: false)
        let feed = HomeFeedTableView(
            featuredContent: { width in AnyView(Text("Cabecera y destacados \(width)")) },
            featuredHeight: { 158 + HomeFeaturedLayout.height(width: $0, hasSongs: true, hasAlbums: true, songCount: 27, albumCount: 6) },
            sections: base.sections, isObscured: false, revision: 1, selectedChip: nil,
            hasMore: true, isLoadingMore: false, currentTrackID: nil, isPlaying: false,
            player: base.player, router: nil, onNavigate: { _ in }, onLoadMore: {}
        )
        // Each recreation models returning Home from another destination.
        for _ in 0..<3 {
            let coordinator = feed.makeCoordinator()
            let scroll = feed.makeNativeScrollView(coordinator: coordinator)
            defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
            let table = try XCTUnwrap(scroll.documentView as? NSTableView)
            (scroll as? HomeFeedScrollView)?.onViewportLayout = nil
            scroll.contentView.postsBoundsChangedNotifications = false
            let firstHeight = table.rect(ofRow: 0).height
            scroll.frame = NSRect(x: 0, y: 0, width: 1512, height: 640)
            scroll.contentView.setBoundsSize(NSSize(width: 1512, height: 640))
            table.frame.size.width = 1512
            _ = coordinator.tableView(table, viewFor: table.tableColumns.first, row: 0)
            let expected = try XCTUnwrap(feed.featuredHeight)(1512)
            XCTAssertNotEqual(firstHeight, expected)
            coordinator.updateFeatured()
            XCTAssertEqual(table.rect(ofRow: 0).height, expected, accuracy: 0.5)
            XCTAssertEqual(table.rect(ofRow: 1).minY, expected, accuracy: 0.5)
            XCTAssertEqual(scroll.contentInsets.top, 0)
            XCTAssertNil(scroll.window)
        }
    }

    func testFeedWithoutHeaderKeepsFirstAndLastShelfAndOptionalPagination() {
        let feed = makeFeed(hasHeader: false, hasMore: false)
        let coordinator = feed.makeCoordinator()
        XCTAssertEqual(coordinator.rows.count, 2)
        XCTAssertEqual(coordinator.rows.sectionIndex(forRow: 0), 0)
        XCTAssertEqual(coordinator.rows.sectionIndex(forRow: 1), 1)
        XCTAssertNil(coordinator.rows.sectionIndex(forRow: 2))
        XCTAssertNil(coordinator.rows.loadMoreRow)
    }

    func testNativeScrollViewCannotRecreateHorizontalScroller() {
        let scroll = HomeFeedScrollView()

        scroll.hasHorizontalScroller = true
        let scroller = NSScroller(frame: NSRect(x: 0, y: 0, width: 100, height: 12))
        scroll.horizontalScroller = scroller
        scroll.tile()
        XCTAssertNil(scroller.superview)

        XCTAssertFalse(scroll.hasHorizontalScroller)
        XCTAssertNil(scroll.horizontalScroller)
    }

    func testTopContentInsetSetsInitialScrollPositionAndTracksLaterWindowMeasurement() {
        var feed = makeFeed(hasHeader: true)
        let coordinator = feed.makeCoordinator()
        let scroll = feed.makeNativeScrollView(coordinator: coordinator)
        defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
        scroll.frame = NSRect(x: 0, y: 0, width: 900, height: 300)
        XCTAssertEqual(scroll.contentInsets.top, 0)
        XCTAssertEqual(scroll.contentView.bounds.minY, 0)

        feed = HomeFeedTableView(
            headerContent: feed.headerContent, headerHeight: 144, topContentInset: 72,
            sections: feed.sections, isObscured: false, revision: 1, selectedChip: nil, hasMore: true,
            isLoadingMore: false, currentTrackID: nil, isPlaying: false,
            player: feed.player, router: nil, onNavigate: { _ in }, onLoadMore: {}
        )
        feed.updateNativeScrollView(scroll, coordinator: coordinator)
        XCTAssertEqual(scroll.contentInsets.top, 72)
        XCTAssertEqual(scroll.contentView.bounds.minY, -72)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 150))
        feed.updateNativeScrollView(scroll, coordinator: coordinator)
        XCTAssertEqual(scroll.contentView.bounds.minY, 150)
    }
}

private struct HomeFeaturedWidthProbe: NSViewRepresentable {
    let width: CGFloat
    func makeNSView(context: Context) -> HomeFeaturedWidthProbeView { HomeFeaturedWidthProbeView() }
    func updateNSView(_ view: HomeFeaturedWidthProbeView, context: Context) { view.renderedWidth = width }
}

private final class HomeFeaturedWidthProbeView: NSView {
    var renderedWidth: CGFloat = 0
}

@MainActor
private final class HomeReloadTrackingTableView: NSTableView {
    var fullReloads = 0
    var reloadedRows: [IndexSet] = []
    override func reloadData() {
        fullReloads += 1
        super.reloadData()
    }
    override func reloadData(forRowIndexes rowIndexes: IndexSet, columnIndexes: IndexSet) {
        reloadedRows.append(rowIndexes)
        super.reloadData(forRowIndexes: rowIndexes, columnIndexes: columnIndexes)
    }
}
