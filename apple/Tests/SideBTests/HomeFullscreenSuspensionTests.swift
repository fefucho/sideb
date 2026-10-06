import AppKit
import SideBCore
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class HomeFullscreenSuspensionTests: XCTestCase {
    private func section(_ id: String) -> HomeSectionPresentation {
        HomeSectionPresentation(id: id, title: id, style: .largeCard,
                                items: [], moreBrowseId: nil, moreParams: nil)
    }

    func testHiddenFeedDefersMeasurementsAndLatestSnapshotUntilItResumes() throws {
        let player = PlayerViewModel()
        var measurements = 0
        func feed(obscured: Bool, revision: UInt64, sections: [HomeSectionPresentation]) -> HomeFeedTableView {
            HomeFeedTableView(featuredContent: { AnyView(Text("Featured \($0)")) },
                featuredHeight: { width in
                    measurements += 1
                    return HomeFeaturedLayout.height(width: width, hasSongs: true, hasAlbums: true)
                }, sections: sections, isObscured: obscured, revision: revision, selectedChip: nil,
                hasMore: false, isLoadingMore: false, currentTrackID: revision == 1 ? "a" : "b",
                isPlaying: false, player: player, router: nil, onNavigate: { _ in }, onLoadMore: {})
        }
        let original = [section("one"), section("two")]
        let first = feed(obscured: false, revision: 1, sections: original)
        let coordinator = first.makeCoordinator()
        let scroll = first.makeNativeScrollView(coordinator: coordinator)
        defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        scroll.frame = NSRect(x: 0, y: 0, width: 1100, height: 300)
        table.frame.size.width = 1100
        scroll.layoutSubtreeIfNeeded()
        coordinator.updateFeatured()
        let host = try XCTUnwrap(coordinator.tableView(table, viewFor: table.tableColumns.first, row: 0))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 90))
        scroll.reflectScrolledClipView(scroll.contentView)
        let offset = scroll.contentView.bounds.minY
        let priorWidth = coordinator.featuredViewport.width
        feed(obscured: true, revision: 1, sections: original)
            .updateNativeScrollView(scroll, coordinator: coordinator)
        let hiddenMeasurements = measurements
        for width: CGFloat in [1040, 980, 920, 899, 850, 820, 760, 700] {
            scroll.frame.size.width = width
            scroll.contentView.setBoundsSize(NSSize(width: width, height: 300))
            table.frame.size.width = width
            scroll.layoutSubtreeIfNeeded()
            coordinator.updateFeatured(force: true)
            coordinator.boundsChanged(Notification(name: NSView.boundsDidChangeNotification))
        }
        feed(obscured: true, revision: 2, sections: [section("intermediate")])
            .updateNativeScrollView(scroll, coordinator: coordinator)
        let latest = [section("latest-one"), section("latest-two"), section("latest-three")]
        feed(obscured: true, revision: 3, sections: latest)
            .updateNativeScrollView(scroll, coordinator: coordinator)
        XCTAssertEqual(measurements, hiddenMeasurements)
        XCTAssertEqual(coordinator.featuredViewport.width, priorWidth)
        XCTAssertEqual(coordinator.parent.sections, original)
        XCTAssertEqual(table.numberOfRows, 3)
        XCTAssertTrue(scroll.isHidden)

        feed(obscured: false, revision: 3, sections: latest)
            .updateNativeScrollView(scroll, coordinator: coordinator)
        XCTAssertFalse(scroll.isHidden)
        XCTAssertEqual(coordinator.parent.sections, latest)
        XCTAssertEqual(coordinator.parent.currentTrackID, "b")
        XCTAssertEqual(table.numberOfRows, 4)
        XCTAssertGreaterThan(measurements, hiddenMeasurements)
        XCTAssertEqual(coordinator.featuredViewport.width, scroll.contentView.bounds.width)
        XCTAssertEqual(table.rect(ofRow: 0).height,
            HomeFeaturedLayout.height(width: scroll.contentView.bounds.width, hasSongs: true, hasAlbums: true), accuracy: 0.5)
        XCTAssertTrue(host === coordinator.tableView(table, viewFor: table.tableColumns.first, row: 0))
        XCTAssertEqual(scroll.contentView.bounds.minY, offset, accuracy: 1)
        XCTAssertNil(scroll.window)
    }

    func testSwiftUIKeepsHiddenNativeViewportFixedThenAppliesCurrentSize() throws {
        let player = PlayerViewModel()
        func feed(_ obscured: Bool) -> HomeFeedTableView {
            HomeFeedTableView(sections: [section("one"), section("two")],
                isObscured: obscured, revision: 1, selectedChip: nil,
                hasMore: false, isLoadingMore: false, currentTrackID: nil,
                isPlaying: false, player: player, router: nil, onNavigate: { _ in }, onLoadMore: {})
        }
        let host = NSHostingView(rootView: feed(false).frame(maxWidth: .infinity, maxHeight: .infinity))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 640)
        host.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? HomeFeedScrollView }.first)
        XCTAssertEqual(scroll.frame.size, NSSize(width: 1100, height: 640))
        host.rootView = feed(true).frame(maxWidth: .infinity, maxHeight: .infinity)
        host.layoutSubtreeIfNeeded()
        for size in [NSSize(width: 1200, height: 760), NSSize(width: 700, height: 400)] {
            host.frame.size = size
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(scroll.isHidden)
            XCTAssertEqual(scroll.frame.size, NSSize(width: 1100, height: 640))
        }
        host.rootView = feed(false).frame(maxWidth: .infinity, maxHeight: .infinity)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(scroll === descendants(host).compactMap { $0 as? HomeFeedScrollView }.first)
        XCTAssertFalse(scroll.isHidden)
        XCTAssertEqual(scroll.frame.size, NSSize(width: 700, height: 400))
        XCTAssertNil(scroll.window)
    }

    func testHiddenHomeCannotExpandShellWhenSidebarOpensOrWindowResizes() async throws {
        let player = PlayerViewModel()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let home = HomeViewModel(cacheStore: HomeFeedCacheStore(directory: directory),
                                 preferences: UserDefaults(suiteName: UUID().uuidString)!)
        home.prepareSession(identity: UUID().uuidString)
        await home.loadHomeFeed(core: ShellHomeCoreStub())
        func shell(reserve: CGFloat) -> some View {
            ZStack {
                HStack(spacing: 0) {
                    Color.clear.frame(width: reserve)
                    HomeView(playerViewModel: player, homeViewModel: home, sessionRevision: 0)
                        .opacity(player.isFullscreenPresented ? 0 : 1)
                }
                ShellFrameProbe(name: "canvas")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 0) {
                    ShellFrameProbe(name: "sidebar")
                        .frame(width: ShellLayout.sidebarWidth)
                        .padding(ShellLayout.sidebarInset)
                    Spacer(minLength: 0)
                }
            }
        }
        let host = NSHostingView(rootView: shell(reserve: 0))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 640)
        host.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? HomeFeedScrollView }.first)
        let retainedSize = scroll.frame.size
        XCTAssertEqual(retainedSize.width, 1100, accuracy: 0.5)
        player.isFullscreenPresented = true
        host.layoutSubtreeIfNeeded()

        // Include intermediate/reversed sidebar widths and a smaller window.
        for (width, reserve): (CGFloat, CGFloat) in [
            (1100, 0), (1100, 60), (1100, 121), (1100, 242),
            (1100, 121), (1512, 242), (960, 242), (1100, 0), (1100, 242)
        ] {
            host.rootView = shell(reserve: reserve)
            host.frame.size.width = width
            host.layoutSubtreeIfNeeded()
            let canvas = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "canvas" })
            let sidebar = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "sidebar" })
            let canvasFrame = canvas.convert(canvas.bounds, to: host)
            let sidebarFrame = sidebar.convert(sidebar.bounds, to: host)
            XCTAssertEqual(canvasFrame.minX, 0, accuracy: 0.5, "Shell shifted at \(width)/\(reserve)")
            XCTAssertEqual(canvasFrame.maxX, width, accuracy: 0.5, "Shell grew at \(width)/\(reserve)")
            XCTAssertEqual(sidebarFrame.minX, ShellLayout.sidebarInset, accuracy: 0.5)
            XCTAssertEqual(sidebarFrame.width, ShellLayout.sidebarWidth, accuracy: 0.5)
            XCTAssertTrue(scroll.isHidden)
            XCTAssertEqual(scroll.frame.size, retainedSize)
        }
        player.isFullscreenPresented = false
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(scroll.isHidden)
        XCTAssertEqual(scroll.frame.width, 1100 - ShellLayout.sidebarReserveWidth(expanded: true), accuracy: 0.5)
        XCTAssertTrue(scroll === descendants(host).compactMap { $0 as? HomeFeedScrollView }.first)
        XCTAssertNil(host.window)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

private struct ShellFrameProbe: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(name)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

private final class ShellHomeCoreStub: SideBCore, @unchecked Sendable {
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        super.init(unsafeFromRawPointer: pointer)
    }
    init() { super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { true }
    override func getHomePage(chipParams: String?) async throws -> HomePageRecord {
        // Geometry needs both featured panels and a shelf, without launching
        // unrelated image decoding/prefetch work into later test suites.
        func items(_ kind: String, count: Int) -> [HomeItemRecord] {
            (0..<count).map { index in
                HomeItemRecord(kind: kind, id: "\(kind)-\(index)", title: "\(kind) \(index)",
                    subtitle: nil, thumbnail: nil, duration: nil, artists: nil, artistId: nil,
                    album: nil, albumId: nil, artistRuns: [], explicit: false)
            }
        }
        return HomePageRecord(chips: [], sections: [
            HomeSectionRecord(title: "Quick picks", format: .compactSongs,
                items: items("song", count: 9), moreBrowseId: nil, moreParams: nil),
            HomeSectionRecord(title: "Albums for you", format: .largeCards,
                items: items("album", count: 12), moreBrowseId: nil, moreParams: nil),
            HomeSectionRecord(title: "Listen again", format: .largeCards,
                items: items("playlist", count: 8), moreBrowseId: nil, moreParams: nil)
        ], continuation: nil)
    }
}
