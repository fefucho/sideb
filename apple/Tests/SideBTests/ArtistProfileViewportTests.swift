import AppKit
import SwiftUI
import SideBCore
import XCTest
@testable import SideB

@MainActor final class ArtistProfileViewportTests: XCTestCase {
    private func section(_ index: Int, count: Int = 500, kind: String = "album") -> ArtistCarouselRecord {
        ArtistCarouselRecord(title: "Sección \(index)", items: (0..<count).map {
            BrowseCardRecord(kind: kind, id: "\(index)-\($0)", title: "Item \($0)", subtitle: "Artista", thumbnail: nil, duration: nil)
        }, moreBrowseId: "catalog-\(index)", moreParams: "params-\(index)")
    }
    private func artist(_ sections: [ArtistCarouselRecord], id: String = "artist") -> ArtistDetailRecord {
        ArtistDetailRecord(channelId: id, name: "Artista", thumbnail: nil, description: nil,
            subscribers: nil, monthlyListeners: nil, subscribed: false, radioPlaylistId: nil,
            topSongs: [], topSongsId: nil, sections: sections)
    }
    private func viewport(_ sections: [ArtistCarouselRecord], onMore: @escaping (ArtistCarouselRecord) -> Void = { _ in }) -> ArtistProfileViewport {
        ArtistProfileViewport(artist: artist(sections), header: AnyView(Text("Cabecera").frame(height: 180)),
            makeCard: { AnyView(Text($0.title)) }, onMore: onMore)
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func layout(_ scroll: NSScrollView) {
        scroll.layoutSubtreeIfNeeded()
        scroll.documentView?.layoutSubtreeIfNeeded()
        scroll.documentView?.viewWillDraw()
        descendants(scroll).forEach { $0.layoutSubtreeIfNeeded() }
    }
    func testDeepVerticalAndHorizontalScrollRecycleRowsAndCardsAndRestoreOffsets() throws {
        let view = viewport((0..<60).map { section($0) })
        let coordinator = view.makeCoordinator()
        let scroll = view.makeScrollView(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scroll
        defer { ArtistProfileViewport.dismantleNSView(scroll, coordinator: coordinator); window.contentView = nil }
        layout(scroll)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        for row in [1, 35, 59, 1] {
            table.scrollRowToVisible(row)
            layout(scroll)
            let mounted = descendants(table).compactMap { $0 as? ArtistProfileShelf }
            XCTAssertFalse(mounted.isEmpty)
            XCTAssertLessThan(mounted.count, 10)
            let shelf = try XCTUnwrap(table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ArtistProfileShelf)
            let collection = shelf.collection
            let horizontal = try XCTUnwrap(collection.enclosingScrollView)
            collection.scrollToItems(at: [IndexPath(item: 450, section: 0)], scrollPosition: .left)
            layout(scroll)
            XCTAssertTrue(collection.indexPathsForVisibleItems().contains { $0.item >= 450 })
            XCTAssertLessThan(collection.visibleItems().count, 20)
            XCTAssertTrue(collection.visibleItems().contains { ($0 as? ArtistProfileCardItem)?.hasContent == true })
            XCTAssertGreaterThan(horizontal.contentView.bounds.minX, 1000)
            let area = horizontal.convert(horizontal.bounds, to: scroll)
            XCTAssertTrue(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: area.midX, y: area.midY), in: scroll))
            let heading = shelf.convert(NSPoint(x: 100, y: 10), to: scroll)
            XCTAssertFalse(HorizontalNavigationGestureRouting.contentOwnsGesture(at: heading, in: scroll))
        }
        XCTAssertGreaterThan(coordinator.offsets[0] ?? 0, 1000)
        table.scrollRowToVisible(40); layout(scroll)
        table.scrollRowToVisible(1); layout(scroll)
        let restored = try XCTUnwrap(table.view(atColumn: 0, row: 1, makeIfNecessary: false) as? ArtistProfileShelf)
        XCTAssertGreaterThan(try XCTUnwrap(restored.collection.enclosingScrollView).contentView.bounds.minX, 1000)
        XCTAssertFalse(window.isVisible)
    }
    func testUnchangedDataKeepsRowsAndObscuringSuspendsCardHosts() throws {
        var view = viewport([section(0, count: 10)])
        let coordinator = view.makeCoordinator()
        let scroll = view.makeScrollView(coordinator: coordinator)
        scroll.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        defer { ArtistProfileViewport.dismantleNSView(scroll, coordinator: coordinator) }
        layout(scroll)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        let shelf = try XCTUnwrap(table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? ArtistProfileShelf)
        let configured = coordinator.configuredShelves
        view.update(scroll, coordinator: coordinator)
        XCTAssertEqual(coordinator.configuredShelves, configured)
        XCTAssertTrue(table.view(atColumn: 0, row: 1, makeIfNecessary: false) === shelf)
        view.isObscured = true
        view.update(scroll, coordinator: coordinator); layout(scroll)
        XCTAssertTrue(scroll.isHidden)
        XCTAssertEqual(shelf.collection.numberOfItems(inSection: 0), 0)
        XCTAssertFalse(shelf.collection.visibleItems().contains { ($0 as? ArtistProfileCardItem)?.hasContent == true })
        view.isObscured = false
        view.update(scroll, coordinator: coordinator); layout(scroll)
        XCTAssertFalse(scroll.isHidden)
        XCTAssertEqual(shelf.collection.numberOfItems(inSection: 0), 10)
    }
    func testDuplicateSectionTitlesResizeAndDataReplacementKeepValidGeometry() throws {
        var first = section(0, count: 20)
        var second = section(1, count: 20)
        first.title = "Álbumes"; second.title = "Álbumes"
        let view = viewport([first, second])
        let coordinator = view.makeCoordinator()
        let scroll = view.makeScrollView(coordinator: coordinator)
        defer { ArtistProfileViewport.dismantleNSView(scroll, coordinator: coordinator) }
        for width: CGFloat in [1000, 600, 1200] {
            scroll.frame = NSRect(x: 0, y: 0, width: width, height: 900)
            layout(scroll)
            let table = try XCTUnwrap(scroll.documentView as? NSTableView)
            XCTAssertEqual(table.numberOfRows, 4)
            for row in [1, 2] {
                XCTAssertEqual(table.rect(ofRow: row).height, 258, accuracy: 0.5)
                let shelf = try XCTUnwrap(table.view(atColumn: 0, row: row, makeIfNecessary: true) as? ArtistProfileShelf)
                XCTAssertEqual(shelf.collection.numberOfItems(inSection: 0), 20)
                XCTAssertEqual(shelf.bounds.width, scroll.contentView.bounds.width, accuracy: 1)
            }
        }
        coordinator.offsets[0] = 1000
        let changed = viewport([section(2, count: 1, kind: "video")])
        changed.update(scroll, coordinator: coordinator); layout(scroll)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        XCTAssertEqual(table.numberOfRows, 3)
        XCTAssertEqual(table.rect(ofRow: 1).height, 226, accuracy: 0.5)
        XCTAssertEqual(coordinator.offsets[0] ?? 0, 0)
    }

    func testReusedShelfMoreActionAndGeometryMatchNewSection() throws {
        let shelf = ArtistProfileShelf(frame: NSRect(x: 0, y: 0, width: 900, height: 258))
        var opened: [String] = []
        for index in [0, 1] {
            let data = section(index, count: 4, kind: index == 0 ? "album" : "video")
            shelf.configure(section: data, offset: 0, active: true, makeCard: { AnyView(Text($0.id)) },
                onMore: { opened.append(data.moreBrowseId!) }, offsetChanged: { _ in })
            shelf.layoutSubtreeIfNeeded()
            try XCTUnwrap(shelf.subviews.compactMap { $0 as? NSButton }.first).performClick(nil)
            XCTAssertEqual(ArtistProfileShelf.cardSize(data.items[0]).width, index == 0 ? 144 : 200)
            XCTAssertEqual(ArtistProfileShelf.height(for: data), index == 0 ? 258 : 226)
        }
        XCTAssertEqual(opened, ["catalog-0", "catalog-1"])
        let hosts = shelf.collection.visibleItems().compactMap { $0 as? ArtistProfileCardItem }
        shelf.suspend()
        XCTAssertTrue(hosts.allSatisfy { !$0.hasContent })
        try XCTUnwrap(shelf.subviews.compactMap { $0 as? NSButton }.first).performClick(nil)
        XCTAssertEqual(opened.count, 2)
    }
}
