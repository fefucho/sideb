import AppKit
import SideBCore
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class ExplorePageLayoutTests: XCTestCase {
    private let widths: [CGFloat] = [730, 1100, 1512]

    func testScrollingFeedAndCatalogueHeaderUseHomesMarginsAtEveryWidth() throws {
        for bottomPadding: CGFloat in [16, 140] {
            let host = NSHostingView(rootView: ExplorePageContent(bottomPadding: bottomPadding) {
                VStack(alignment: .leading, spacing: 30) {
                    ExplorePageHeading(route: .discover)
                        .background(ExploreLayoutProbe(identifier: "heading"))
                    Color.clear.frame(height: 48)
                        .background(ExploreLayoutProbe(identifier: "tabs"))
                    Color.clear.frame(height: 80)
                        .background(ExploreLayoutProbe(identifier: "section"))
                }
            }.frame(maxHeight: .infinity, alignment: .top))
            host.sizingOptions = []
            for width in widths {
                host.frame = NSRect(x: 0, y: 0, width: width, height: 700)
                host.layoutSubtreeIfNeeded()
                let heading = try probeFrame("heading", in: host)
                let tabs = try probeFrame("tabs", in: host)
                let section = try probeFrame("section", in: host)
                // Home's title starts 24pt below the content edge, uses a 52pt
                // line box and 28pt margins. Measure AppKit views after SwiftUI
                // layout, including a width above the former 1400pt cap.
                XCTAssertEqual(heading.minX, 28, accuracy: 0.5, "width=\(width)")
                XCTAssertEqual(host.bounds.maxX - heading.maxX, 28, accuracy: 0.5)
                XCTAssertEqual(heading.minY, 24, accuracy: 0.5)
                XCTAssertEqual(heading.height, 52, accuracy: 0.5)
                XCTAssertEqual(tabs.minX, heading.minX, accuracy: 0.5)
                XCTAssertEqual(section.width, width - 56, accuracy: 0.5)
                XCTAssertEqual(section.minX, heading.minX, accuracy: 0.5)
                XCTAssertEqual(tabs.minY - heading.maxY, 30, accuracy: 0.5)
            }
        }
    }

    func testLocalizedHeadingUsesHomesNativeTextMetricsAndKeepsSubrouteTitles() {
        let previousLanguage = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previousLanguage) }
        for language: AppLanguage in [.en, .es] {
            AppLanguageStore.shared.setLanguage(language)
            for route: ExploreRoute in [.discover, .releases, .genres, .moods, .category("focus"), .chartCountry("UY")] {
                let title = route == .discover ? L10n.text("navigation.explore") : route.title
                let heading = NSHostingView(rootView: ExplorePageHeading(route: route).fixedSize())
                let reference = NSHostingView(rootView: Text(title)
                    .font(.system(size: 40, weight: .bold)).fixedSize())
                // Compare shaped native text widths, so the former 36/32pt
                // title or the longer Discover slogan cannot pass unnoticed.
                XCTAssertEqual(heading.fittingSize.width, reference.fittingSize.width, accuracy: 0.5,
                               "\(language): \(route)")
                XCTAssertEqual(heading.fittingSize.height, 52, accuracy: 0.5)
            }
        }
    }

    func testVerticalNativeCataloguesUseFullWidthAndKeepTheirViewportBounded() async throws {
        let cards = (0..<2000).map { index in
            BrowseCardRecord(kind: "album", id: "layout-\(index)", title: "Album \(index)",
                             subtitle: nil, thumbnail: nil, duration: nil)
        }
        let grid = ExploreCatalogGridView(cards: cards, route: .releases, sessionRevision: 1,
            header: AnyView(ExplorePageContent(bottomPadding: 16) {
                ExplorePageHeading(route: .releases)
                    .background(ExploreLayoutProbe(identifier: "catalogue-heading"))
            }),
            headerIdentity: .init(route: .releases, session: 1, loading: false, error: nil, empty: false),
            onOpen: { _ in }, onPlay: { _ in }, menuProvider: { _ in nil })
        let coordinator = grid.makeCoordinator()
        let scroll = grid.makeScrollView(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer {
            ExploreCatalogGridView.dismantleNSView(scroll, coordinator: coordinator)
            window.contentView = nil
            window.close()
        }
        let collection = try XCTUnwrap(scroll.documentView as? NSCollectionView)
        let flow = try XCTUnwrap(collection.collectionViewLayout as? NSCollectionViewFlowLayout)
        for width in widths {
            window.setContentSize(NSSize(width: width, height: 700))
            scroll.frame.size = NSSize(width: width, height: 700)
            for _ in 0..<5 {
                layout(scroll, coordinator: coordinator)
                await Task.yield()
            }
            let first = try XCTUnwrap(flow.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            let viewportWidth = scroll.contentView.bounds.width
            XCTAssertEqual(first.frame.minX, 28, accuracy: 0.5)
            XCTAssertEqual(flow.sectionInset.right, 28, accuracy: 0.5)
            let columns = max(1, Int((viewportWidth - 56 + 20) / 180))
            let last = try XCTUnwrap(flow.layoutAttributesForItem(at: IndexPath(item: columns - 1, section: 0)))
            // Integer item widths may leave less than one point per column.
            XCTAssertLessThanOrEqual(viewportWidth - 28 - last.frame.maxX, CGFloat(columns) + 0.5)
            XCTAssertGreaterThanOrEqual(viewportWidth - last.frame.maxX, 27.5)
            let heading = try probeFrame("catalogue-heading", in: collection)
            XCTAssertEqual(heading.minX, first.frame.minX, accuracy: 0.5)
            XCTAssertEqual(heading.minY, 24, accuracy: 0.5)
            XCTAssertEqual(heading.width, viewportWidth - 56, accuracy: 0.5)
            XCTAssertEqual(scroll.frame.height, 700, accuracy: 0.5)
            XCTAssertEqual(collection.numberOfItems(inSection: 0), 2000)
            let mounted = descendants(collection).compactMap { $0 as? HomeItemView }
            XCTAssertFalse(mounted.isEmpty)
            XCTAssertLessThan(mounted.count, 80)
        }
        XCTAssertFalse(window.isVisible)
    }

    func testOptionalRealExplorePageRendersWithoutNetworkOrAccount() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SIDEB_LAYOUT_REVIEW_DIR"] else { return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ExploreLayout-\(UUID())")
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
        let suite = "ExploreLayout-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let audio = AudioPlayerService(preferences: defaults, preferencePrefix: "fixture")
        let player = PlayerViewModel(rustCore: nil, audioService: audio,
                                    playbackStore: PlaybackStateStore(directory: fixtureDirectory))
        let core = ExploreLayoutCore(), model = ExploreViewModel()
        model.prepareSession(1)
        await model.load(route: .discover, core: core)
        let router = NavigationRouter()
        let host = NSHostingView(rootView: ExploreView(route: .discover, rustCore: core,
            model: model, playerViewModel: player, router: router, sessionRevision: 1)
            .preferredColorScheme(.dark)
            .background(Color(red: 0.10, green: 0.10, blue: 0.11)))
        host.sizingOptions = []
        host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for width in widths {
            window.setContentSize(NSSize(width: width, height: 850))
            host.frame.size = NSSize(width: width, height: 850)
            for _ in 0..<5 { host.layoutSubtreeIfNeeded(); await Task.yield() }
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: output.appendingPathComponent("explore-\(Int(width)).png"))
        }
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(player.isPlaying)
    }

    private func probeFrame(_ identifier: String, in root: NSView) throws -> NSRect {
        let probe = try XCTUnwrap(descendants(root).first { $0.identifier?.rawValue == identifier })
        let frame = probe.convert(probe.bounds, to: root)
        return root.isFlipped ? frame : NSRect(x: frame.minX, y: root.bounds.maxY - frame.maxY,
                                             width: frame.width, height: frame.height)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func layout(_ scroll: NSScrollView, coordinator: ExploreCatalogGridView.Coordinator) {
        scroll.layoutSubtreeIfNeeded()
        coordinator.updateGeometry()
        scroll.documentView?.needsLayout = true
        scroll.documentView?.layoutSubtreeIfNeeded()
        scroll.documentView?.viewWillDraw()
        descendants(scroll).forEach { $0.layoutSubtreeIfNeeded() }
    }
}

private struct ExploreLayoutProbe: NSViewRepresentable {
    let identifier: String
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ExploreLayoutCore: SideBCore, @unchecked Sendable {
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func getBrowseGrid(browseId: String, params: String?) async throws -> [BrowseCardRecord] {
        (0..<12).map { index in
            BrowseCardRecord(kind: "album", id: "preview-\(index)", title: "Preview album \(index)",
                             subtitle: "Fixture artist", thumbnail: nil, duration: nil)
        }
    }
}
