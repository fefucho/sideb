import AppKit
import SideBCore
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class HomeGestureRoutingTests: XCTestCase {
    private final class PagedContent: NSView, HorizontalNavigationGestureOwner {
        var ownsHorizontalNavigationGesture = true
    }
    func testPagedRegionKeepsGestureAndOrdinaryContentAllowsHistory() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let panel = PagedContent(frame: NSRect(x: 28, y: 100, width: 420, height: 480))
        root.addSubview(panel)
        // Overlay hitTest is intentionally irrelevant for zero-delta gesture beginnings.
        XCTAssertTrue(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: 200, y: 300), in: root))
        XCTAssertFalse(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: 700, y: 300), in: root))
        panel.ownsHorizontalNavigationGesture = false
        XCTAssertFalse(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: 200, y: 300), in: root))
        panel.ownsHorizontalNavigationGesture = true
        panel.isHidden = true
        XCTAssertFalse(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: 200, y: 300), in: root))
        XCTAssertNil(root.window)
    }

    func testChipsReserveOnlyTheirBoundsAndForegroundShellWinsOverContent() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let chips = WindowGestureRegionView(frame: NSRect(x: 240, y: 600, width: 660, height: 42))
        chips.region = .horizontalContent
        root.addSubview(chips)
        XCTAssertTrue(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: 400, y: 620), in: root))
        XCTAssertFalse(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: 400, y: 580), in: root))
        chips.isRegionActive = false
        XCTAssertFalse(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: 400, y: 620), in: root))
        chips.isRegionActive = true
        let foreground = WindowGestureRegionView(frame: NSRect(x: 300, y: 610, width: 300, height: 74))
        foreground.region = .excluded
        root.addSubview(foreground)
        XCTAssertFalse(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: 400, y: 620), in: root))
        XCTAssertTrue(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: 750, y: 620), in: root))
        XCTAssertNil(root.window)
    }

    func testNativeShelfOwnsItsViewportAtEveryOffsetButNeverItsHeader() throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 700))
        let shelf = HomeShelfRowView(frame: NSRect(x: 28, y: 200, width: 1000, height: 300))
        root.addSubview(shelf)
        let items = (0..<24).map { index in
            HomeItemPresentation(id: "album-\(index)", sectionID: "albums", style: .largeCard,
                                 record: record(kind: "album", id: index))
        }
        let section = HomeSectionPresentation(id: "albums", title: "Álbumes", style: .largeCard,
                                             items: items, moreBrowseId: nil, moreParams: nil)
        shelf.configure(section: section, horizontalOffset: 0, onHorizontalOffset: { _ in },
            onMore: {}, onActivate: { _ in }, onConfigure: { _, _ in })
        shelf.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendants(shelf).compactMap { $0 as? NSScrollView }.first)
        let collection = try XCTUnwrap(scroll.documentView as? NSCollectionView)
        collection.layoutSubtreeIfNeeded()
        let viewport = scroll.convert(scroll.bounds, to: root)
        let layout = try XCTUnwrap(collection.collectionViewLayout)
        let maxOffset = max(0, layout.collectionViewContentSize.width - scroll.contentView.bounds.width)
        XCTAssertGreaterThan(maxOffset, 1000)
        for offset in [CGFloat(0), maxOffset / 2, maxOffset] {
            scroll.contentView.scroll(to: NSPoint(x: offset, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            for x in [viewport.minX + 1, viewport.midX, viewport.maxX - 1] {
                XCTAssertTrue(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: x, y: viewport.midY), in: root))
            }
            let header = shelf.convert(NSPoint(x: 500, y: 16), to: root)
            XCTAssertFalse(HorizontalNavigationGestureRouting.contentOwnsGesture(at: header, in: root))
            XCTAssertFalse(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: viewport.minX - 10, y: viewport.midY), in: root))
        }
        // A short carousel also keeps the contact; lack of overflow is not a handoff.
        let short = HomeSectionPresentation(id: "short", title: "Corto", style: .largeCard,
            items: Array(items.prefix(1)), moreBrowseId: nil, moreParams: nil)
        shelf.configure(section: short, horizontalOffset: 0, onHorizontalOffset: { _ in },
            onMore: {}, onActivate: { _ in }, onConfigure: { _, _ in })
        shelf.layoutSubtreeIfNeeded()
        XCTAssertTrue(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: viewport.midX, y: viewport.midY), in: root))
        shelf.isHidden = true
        XCTAssertFalse(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: viewport.midX, y: viewport.midY), in: root))
        XCTAssertNil(root.window)
    }

    func testRealFeaturedOwnersCoverCardsButExcludeHeadersFootersAndOuterPadding() throws {
        for width: CGFloat in [700, 1100, 1512] {
            let layout = HomeFeaturedLayout(width: width, hasSongs: true, hasAlbums: true, songCount: 27, albumCount: 12)
            let featured = HomeFeaturedView(songs: (0..<27).map { record(kind: "song", id: $0) },
                collections: (0..<12).map { record(kind: "album", id: $0) }, collectionKind: .albums,
                width: width, resetKey: "gesture-test", loadingCollectionID: nil, core: nil,
                onSong: { _ in }, onCollection: { _ in }, onArtist: { _ in }, onPlayCollection: { _, _ in })
            let host = NSHostingView(rootView: featured)
            host.sizingOptions = []
            host.frame = NSRect(x: 0, y: 0, width: width, height: layout.totalHeight)
            host.layoutSubtreeIfNeeded()
            let owners = descendants(host).filter { ($0 as? HorizontalNavigationGestureOwner)?.ownsHorizontalNavigationGesture == true }
            XCTAssertEqual(owners.count, 2, "\(width)")
            for owner in owners {
                let area = owner.convert(owner.bounds, to: host)
                XCTAssertTrue(HorizontalNavigationGestureRouting.contentOwnsGesture(at: NSPoint(x: area.midX, y: area.midY), in: host))
                let expectedHeights = [layout.songGridHeight, layout.albumContentHeight]
                XCTAssertTrue(expectedHeights.contains { abs($0 - area.height) < 0.5 }, "\(width): \(area)")
                for point in [NSPoint(x: area.midX, y: area.minY - 15),
                              NSPoint(x: area.midX, y: area.maxY + 16),
                              NSPoint(x: 14, y: area.midY)] {
                    XCTAssertTrue(host.bounds.contains(point))
                    XCTAssertFalse(HorizontalNavigationGestureRouting.contentOwnsGesture(at: point, in: host), "\(width): \(point)")
                }
            }
            XCTAssertNil(host.window)
        }
    }

    func testHomeContactKeepsItsOwnerAfterPointerLeavesOrReachesAnEdge() {
        let router = NavigationRouter()
        router.navigate(to: .library)
        router.navigate(to: .home)
        router.navigate(to: .explore(.discover))
        router.goBack()
        let presentation = WindowGesturePresentation()
        var haptics = 0
        let coordinator = WindowNavigationCoordinator(performHaptic: { haptics += 1 })
        coordinator.setup(router: router, presentation: presentation, isFullscreenPresented: false,
            canHandleGestures: true, reduceMotion: true, onDismissFullscreen: {})
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        root.addSubview(PagedContent(frame: NSRect(x: 28, y: 100, width: 420, height: 480)))
        let cards = NSPoint(x: 200, y: 300)
        let header = NSPoint(x: 200, y: 620)
        @discardableResult
        func input(_ event: WindowGestureStateMachine.Event, at point: NSPoint) -> WindowGestureStateMachine.Output {
            coordinator.handleScrollInput(event, enabled: true) {
                coordinator.scrollContext(at: point, in: root, enabled: true)
            }
        }
        for direction: CGFloat in [1, -1] {
            input(.init(phase: .mayBegin), at: cards)
            input(.init(phase: .began), at: cards)
            var paging = HomeFeaturedWheelInput()
            let first = input(.init(deltaX: direction * 50, phase: .changed), at: cards)
            XCTAssertEqual(first.disposition, .passThrough)
            XCTAssertNotNil(paging.consume(x: direction * 50, y: 0, timestamp: 1, momentum: false))
            XCTAssertEqual(input(.init(deltaX: direction * 300, phase: .changed), at: header).disposition, .passThrough)
            XCTAssertNil(paging.consume(x: direction * 300, y: 0, timestamp: 1.1, momentum: false))
            XCTAssertNil(input(.init(phase: .ended), at: header).commit)
            XCTAssertEqual(input(.init(deltaX: direction * 500, momentumPhase: .changed), at: header).disposition, .passThrough)
            input(.init(momentumPhase: .ended), at: header)
            XCTAssertEqual(router.currentPage, .home)
            XCTAssertNil(presentation.horizontal)
            XCTAssertEqual(haptics, 0)
        }
        // A fresh contact on the title uses history even when it later enters cards.
        input(.init(phase: .mayBegin), at: header)
        XCTAssertEqual(input(.init(deltaX: 90, phase: .changed), at: cards).disposition, .consume)
        XCTAssertEqual(input(.init(phase: .ended), at: cards).commit, .back)
        XCTAssertEqual(router.currentPage, .library)
        XCTAssertEqual(haptics, 1)
        // The explicit reservation is scoped to Home, leaving other pages untouched.
        XCTAssertTrue(coordinator.scrollContext(at: cards, in: root, enabled: true).allowsHorizontalNavigation)
        XCTAssertNil(root.window)
    }

    private func record(kind: String, id: Int) -> HomeItemRecord {
        HomeItemRecord(kind: kind, id: "\(kind)-\(id)", title: "\(kind) \(id)", subtitle: nil,
            thumbnail: nil, duration: nil, artists: nil, artistId: nil, album: nil, albumId: nil,
            artistRuns: [], explicit: false)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
