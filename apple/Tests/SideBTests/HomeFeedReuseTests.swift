import AppKit
import SideBCore
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class HomeFeedReuseTests: XCTestCase {
    private func section(_ id: String, style: HomeSectionStyle = .largeCard, count: Int = 24,
                         kind: String = "album") -> HomeSectionPresentation {
        HomeSectionPresentation(id: id, title: id, style: style, items: (0..<count).map { index in
            HomeItemPresentation(id: "\(id)-\(index)", sectionID: id, style: style, record: HomeItemRecord(
                kind: kind, id: "\(id)-\(index)", title: "\(id) \(index)", subtitle: "Artista",
                thumbnail: nil, duration: nil, artists: "Artista", artistId: "UC-\(id)",
                album: nil, albumId: nil, artistRuns: [], explicit: false))
        }, moreBrowseId: nil, moreParams: nil)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func configure(_ shelf: HomeShelfRowView, section: HomeSectionPresentation,
                           offset: CGFloat = 0, action: @escaping (String) -> Void = { _ in }) {
        shelf.configure(section: section, horizontalOffset: offset, onHorizontalOffset: { _ in },
                        onMore: {}, onActivate: { action($0.id) }) { cell, item in
            cell.content.configure(record: item.record, style: item.style, currentTrackID: nil, isPlaying: false,
                                   onCard: { action(item.id) }, onCover: {}, onTitle: {},
                                   onArtist: {}, onAlbum: {}, menuProvider: { nil })
        }
        shelf.layoutSubtreeIfNeeded()
        for view in descendants(shelf) { view.layoutSubtreeIfNeeded() }
    }

    func testShelfRestoresItsHorizontalOffsetAndReloadsWhenCountChanges() throws {
        let shelf = HomeShelfRowView(frame: .zero)
        shelf.frame = NSRect(x: 0, y: 0, width: 1000, height: 288)
        configure(shelf, section: section("a"), offset: 450)
        let scroll = try XCTUnwrap(descendants(shelf).compactMap { $0 as? NSScrollView }.first)
        XCTAssertEqual(scroll.contentView.bounds.minX, 450, accuracy: 1)
        configure(shelf, section: section("b"), offset: 0)
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 1)
        configure(shelf, section: section("a"), offset: 450)
        XCTAssertEqual(scroll.contentView.bounds.minX, 450, accuracy: 1)
        configure(shelf, section: section("short", count: 2), offset: 450)
        let collection = try XCTUnwrap(scroll.documentView as? NSCollectionView)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 2)
        XCTAssertLessThanOrEqual(scroll.contentView.bounds.minX, 1)
        XCTAssertNil(collection.item(at: IndexPath(item: 20, section: 0)))
    }

    func testFiveThousandCategoriesKeepOnlyViewportShelvesAndCards() throws {
        // No network/images or NSWindow. This verifies allocation bounds and identities, not FPS.
        let sections = (0..<5000).map { section("category-\($0)", style: $0 % 5 == 0 ? .compactSong : .largeCard) }
        let feed = HomeFeedTableView(sections: sections, isObscured: false, revision: 1, selectedChip: nil,
                                    hasMore: false, isLoadingMore: false, currentTrackID: nil, isPlaying: false,
                                    player: PlayerViewModel(), router: nil, onNavigate: { _ in }, onLoadMore: {})
        let coordinator = feed.makeCoordinator()
        let scroll = feed.makeNativeScrollView(coordinator: coordinator)
        defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
        scroll.frame = NSRect(x: 0, y: 0, width: 1000, height: 760)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        table.frame.size.width = 1000
        table.reloadData()
        // Retain visited instances so reused allocation addresses cannot undercount creation.
        var seen: [ObjectIdentifier: HomeShelfRowView] = [:]
        var maxShelves = 0
        var maxCards = 0
        for row in stride(from: 0, through: 4995, by: 45) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: row).minY))
            scroll.reflectScrolledClipView(scroll.contentView)
            scroll.layoutSubtreeIfNeeded()
            table.layoutSubtreeIfNeeded()
            let views = descendants(table)
            let shelves = views.compactMap { $0 as? HomeShelfRowView }
            let cards = views.compactMap { $0 as? HomeItemView }
            shelves.forEach { seen[ObjectIdentifier($0)] = $0 }
            maxShelves = max(maxShelves, shelves.count)
            maxCards = max(maxCards, cards.count)
        }
        XCTAssertEqual(table.numberOfRows, 5000)
        XCTAssertGreaterThan(maxShelves, 0)
        XCTAssertGreaterThan(maxCards, 0)
        XCTAssertLessThan(maxShelves, 12)
        XCTAssertLessThan(maxCards, 180)
        XCTAssertLessThan(seen.count, 24)
        XCTAssertNil(scroll.window)
        print("HOME_REUSE_5000 shelves=\(maxShelves) cards=\(maxCards) shelfInstances=\(seen.count)")
    }

    func testSwiftUIViewportFollowsHostSizeInsteadOfDocumentSize() throws {
        let feed = HomeFeedTableView(sections: (0..<50).map { section("category-\($0)") },
                                    isObscured: false, revision: 1, selectedChip: nil,
                                    hasMore: false, isLoadingMore: false, currentTrackID: nil, isPlaying: false,
                                    player: PlayerViewModel(), router: nil, onNavigate: { _ in }, onLoadMore: {})
        let host = NSHostingView(rootView: feed.frame(maxWidth: .infinity, maxHeight: .infinity))
        host.sizingOptions = []
        for size in [NSSize(width: 1100, height: 760), NSSize(width: 700, height: 480), NSSize(width: 900, height: 640)] {
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }
                .first { $0.documentView is NSTableView })
            XCTAssertEqual(scroll.frame.width, size.width, accuracy: 1)
            XCTAssertEqual(scroll.frame.height, size.height, accuracy: 1)
            let table = try XCTUnwrap(scroll.documentView as? NSTableView)
            XCTAssertGreaterThan(table.frame.height, size.height * 10)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 1000))
            scroll.reflectScrolledClipView(scroll.contentView)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(scroll.frame.width, size.width, accuracy: 1)
            XCTAssertEqual(scroll.frame.height, size.height, accuracy: 1)
            XCTAssertNil(scroll.window)
        }
    }
}
