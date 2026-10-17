import AppKit
import Observation
import SideBCore
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class HomeGeometryUpdateTests: XCTestCase {
    private func identity(revision: UInt64 = 1, session: Int = 1, greeting: String = "Hola",
                          thumbnail: String? = nil, chips: [HomeChipRecord] = [], loading: String? = nil)
        -> HomeFeedHostedContentIdentity {
        HomeFeedHostedContentIdentity(revision: revision, selectionRevision: 0, sessionRevision: session,
            greeting: greeting, accountThumbnail: thumbnail, chips: chips, loadingCollectionID: loading,
            coreIdentity: nil, homeIdentity: nil)
    }

    private func feed(player: PlayerViewModel, probes: GeometryHostedProbes,
                      identity: HomeFeedHostedContentIdentity, text: String = "Original",
                      obscured: Bool = false, track: String? = nil, playing: Bool = false,
                      queue: QueueContext? = nil, onNavigate: @escaping (PageDestination) -> Void = { _ in })
        -> HomeFeedTableView {
        HomeFeedTableView(featuredNavigationContent: { width, actions in
            probes.builders += 1
            return AnyView(GeometryHostedProbe(width: width, text: text, capturedActivity: !obscured, actions: actions))
        }, hostedContentIdentity: identity, featuredHeight: { _ in 120 },
            sections: [], isObscured: obscured, revision: identity.revision, selectedChip: nil,
            hasMore: false, isLoadingMore: false, currentTrackID: track, isPlaying: playing,
            queueContext: queue, player: player, router: nil,
            onNavigate: onNavigate, onLoadMore: {})
    }

    private func mount(_ feed: HomeFeedTableView) throws
        -> (HomeFeedTableView.Coordinator, NSScrollView, NSTableView, NSView) {
        let coordinator = feed.makeCoordinator()
        let scroll = feed.makeNativeScrollView(coordinator: coordinator)
        scroll.frame = NSRect(x: 0, y: 0, width: 1100, height: 300)
        scroll.contentView.setBoundsSize(NSSize(width: 1100, height: 300))
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        table.frame.size.width = 1100
        scroll.layoutSubtreeIfNeeded()
        let host = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true))
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 120)
        host.layoutSubtreeIfNeeded()
        return (coordinator, scroll, table, host)
    }

    func testGeometryDoesNotSubscribeNativeUpdateToTheWidthItPublishes() throws {
        let probes = GeometryHostedProbes()
        let first = feed(player: PlayerViewModel(), probes: probes, identity: identity())
        let (coordinator, scroll, table, host) = try mount(first)
        defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
        nonisolated(unsafe) var invalidations = 0
        withObservationTracking {
            first.updateNativeScrollView(scroll, coordinator: coordinator)
        } onChange: { invalidations += 1 }

        for width: CGFloat in [1400, 1512, 1416, 1100, 960, 899, 900, 1100] {
            scroll.frame.size.width = width
            scroll.contentView.setBoundsSize(NSSize(width: width, height: 300))
            table.frame.size.width = width
            coordinator.updateFeatured()
            host.frame.size.width = width
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(coordinator.featuredViewport.width, width, accuracy: 0.000001)
            let probe = try XCTUnwrap(descendants(host).compactMap { $0 as? GeometryHostedProbeView }.first)
            XCTAssertEqual(probe.renderedWidth, width, accuracy: 0.000001)
        }
        XCTAssertEqual(invalidations, 0)
        XCTAssertNil(scroll.window)
    }

    func testUnchangedSemanticInputsKeepRootAndMountedCallbackUsesLatestConfiguration() throws {
        let player = PlayerViewModel(), probes = GeometryHostedProbes()
        var firstClicks = 0, latestClicks = 0
        let first = feed(player: player, probes: probes, identity: identity(),
            onNavigate: { _ in firstClicks += 1 })
        let (coordinator, scroll, _, host) = try mount(first)
        defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
        let probe = try XCTUnwrap(descendants(host).compactMap { $0 as? GeometryHostedProbeView }.first)
        let builds = probes.builders
        XCTAssertGreaterThan(builds, 0)
        probe.button.performClick(nil)
        XCTAssertEqual(firstClicks, 1)

        for _ in 0..<20 {
            feed(player: player, probes: probes, identity: identity(), text: "Unpublished",
                onNavigate: { _ in latestClicks += 1 }).updateNativeScrollView(scroll, coordinator: coordinator)
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(probes.builders, builds)
        XCTAssertEqual(probe.renderedText, "Original")
        probe.button.performClick(nil)
        XCTAssertEqual(firstClicks, 1)
        XCTAssertEqual(latestClicks, 1)

        feed(player: player, probes: probes, identity: identity(), obscured: true,
            onNavigate: { _ in latestClicks += 1 }).updateNativeScrollView(scroll, coordinator: coordinator)
        probe.button.performClick(nil)
        XCTAssertEqual(latestClicks, 1, "A mounted hidden control must not navigate")
        feed(player: player, probes: probes, identity: identity(revision: 2), text: "Current",
            onNavigate: { _ in latestClicks += 1 }).updateNativeScrollView(scroll, coordinator: coordinator)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(probe === descendants(host).compactMap { $0 as? GeometryHostedProbeView }.first)
        XCTAssertEqual(probe.renderedText, "Current")
        probe.button.performClick(nil)
        XCTAssertEqual(latestClicks, 2)
    }

    func testInitiallyHiddenHostedContentRefreshesItsCapturedActivityWhenRevealed() throws {
        let player = PlayerViewModel(), probes = GeometryHostedProbes()
        let first = feed(player: player, probes: probes, identity: identity(), obscured: true)
        let (coordinator, scroll, _, host) = try mount(first)
        defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
        let probe = try XCTUnwrap(descendants(host).compactMap { $0 as? GeometryHostedProbeView }.first)
        XCTAssertFalse(probe.capturedActivity)
        XCTAssertFalse(probe.environmentActivity)
        feed(player: player, probes: probes, identity: identity(), obscured: false)
            .updateNativeScrollView(scroll, coordinator: coordinator)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(probe === descendants(host).compactMap { $0 as? GeometryHostedProbeView }.first)
        XCTAssertTrue(probe.capturedActivity)
        XCTAssertTrue(probe.environmentActivity)
        XCTAssertFalse(scroll.isHidden)
    }

    func testHostedDataHeaderLoadingPlaybackAndLanguageUpdateWithoutResize() throws {
        let player = PlayerViewModel(), probes = GeometryHostedProbes()
        let first = feed(player: player, probes: probes, identity: identity())
        let (coordinator, scroll, _, host) = try mount(first)
        defer { HomeFeedTableView.dismantleNSView(scroll, coordinator: coordinator) }
        let probe = try XCTUnwrap(descendants(host).compactMap { $0 as? GeometryHostedProbeView }.first)
        let changes: [HomeFeedHostedContentIdentity] = [
            identity(revision: 2), identity(greeting: "Buenas tardes"), identity(thumbnail: "avatar"),
            identity(chips: [HomeChipRecord(title: "Focus", params: "focus")]),
            identity(loading: "loading-album"), identity(session: 2)
        ]
        for (index, value) in changes.enumerated() {
            let text = "Changed \(index)"
            feed(player: player, probes: probes, identity: value, text: text)
                .updateNativeScrollView(scroll, coordinator: coordinator)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(probe.renderedText, text)
        }
        feed(player: player, probes: probes, identity: identity(), text: "Track", track: "track-b")
            .updateNativeScrollView(scroll, coordinator: coordinator)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(probe.renderedText, "Track")
        feed(player: player, probes: probes, identity: identity(), text: "Playing", track: "track-b", playing: true)
            .updateNativeScrollView(scroll, coordinator: coordinator)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(probe.renderedText, "Playing")
        feed(player: player, probes: probes, identity: identity(), text: "Queue", track: "track-b", playing: true,
             queue: .album(browseId: "album", title: "Album"))
            .updateNativeScrollView(scroll, coordinator: coordinator)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(probe.renderedText, "Queue")

        let previousLanguage = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previousLanguage) }
        AppLanguageStore.shared.setLanguage(previousLanguage == .es ? .en : .es)
        feed(player: player, probes: probes, identity: identity(), text: "Language", track: "track-b", playing: true,
             queue: .album(browseId: "album", title: "Album"))
            .updateNativeScrollView(scroll, coordinator: coordinator)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(probe.renderedText, "Language")
        XCTAssertEqual(scroll.frame.width, 1100)
    }

    func testCapacityRepartitionsImmediatelyWithoutRepublishingProviderOrCategoriesAndPurgesSession() async throws {
        let suite = "SideB.HomeGeometry.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let model = HomeViewModel(cacheStore: HomeFeedCacheStore(directory: directory), preferences: preferences)
        model.prepareSession(identity: "geometry-account-a", purgePrevious: false)
        await model.loadHomeFeed(core: GeometryHomeCore())
        let provider = model.sections
        let categories = model.receivedCategories
        nonisolated(unsafe) var providerChanges = 0
        nonisolated(unsafe) var categoryChanges = 0
        withObservationTracking { _ = model.sections } onChange: { providerChanges += 1 }
        withObservationTracking { _ = model.receivedCategories } onChange: { categoryChanges += 1 }
        for capacity in [4, 6, 2, 4, 2] {
            model.setFeaturedCapacity(capacity)
            XCTAssertEqual(model.featured.collections.count, capacity * 6)
            let featuredIDs = Set(model.featured.collections.map(\.id))
            let remaining = model.featured.remainingSections.flatMap(\.items).map(\.record.id)
            XCTAssertEqual(remaining.count, 40 - capacity * 6)
            XCTAssertTrue(featuredIDs.isDisjoint(with: remaining))
            XCTAssertEqual(model.sections, provider)
            XCTAssertEqual(model.receivedCategories, categories)
        }
        XCTAssertEqual(providerChanges, 0)
        XCTAssertEqual(categoryChanges, 0)
        nonisolated(unsafe) var featuredChanges = 0
        withObservationTracking { _ = model.featured } onChange: { featuredChanges += 1 }
        let revision = model.contentRevision
        model.setFeaturedCapacity(2)
        XCTAssertEqual(featuredChanges, 0)
        XCTAssertEqual(model.contentRevision, revision)
        model.prepareSession(identity: "geometry-account-b", purgePrevious: false)
        model.setFeaturedCapacity(6)
        XCTAssertTrue(model.sections.isEmpty)
        XCTAssertTrue(model.receivedCategories.isEmpty)
        XCTAssertTrue(model.featured.collections.isEmpty)
        XCTAssertTrue(model.featured.remainingSections.isEmpty)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

@MainActor private final class GeometryHostedProbes {
    var builders = 0
}

private struct GeometryHostedProbe: NSViewRepresentable {
    let width: CGFloat
    let text: String
    let capturedActivity: Bool
    let actions: HomeFeedNavigationActions
    @Environment(\.sideBPageIsActive) private var isActive
    func makeNSView(context: Context) -> GeometryHostedProbeView { GeometryHostedProbeView() }
    func updateNSView(_ view: GeometryHostedProbeView, context: Context) {
        view.renderedWidth = width
        view.renderedText = text
        view.capturedActivity = capturedActivity
        view.environmentActivity = isActive
        view.onClick = { actions.navigate(.album(browseId: "clicked")) }
    }
}

@MainActor private final class GeometryHostedProbeView: NSView {
    let button = NSButton(title: "Open", target: nil, action: nil)
    var renderedWidth: CGFloat = 0
    var renderedText = ""
    var capturedActivity = true
    var environmentActivity = true
    var onClick: (() -> Void)?
    init() {
        super.init(frame: .zero)
        button.target = self
        button.action = #selector(activate)
        addSubview(button)
        button.frame = NSRect(x: 0, y: 0, width: 80, height: 28)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
    @objc private func activate() { onClick?() }
}

private final class GeometryHomeCore: SideBCore, @unchecked Sendable {
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { true }
    override func getHomePage(chipParams: String?) async throws -> HomePageRecord {
        let items = (0..<40).map { index in
            HomeItemRecord(kind: "album", id: "album-\(index)", title: "Album \(index)", subtitle: nil,
                thumbnail: nil, duration: nil, artists: nil, artistId: nil, album: nil, albumId: nil,
                artistRuns: [], explicit: false)
        }
        return HomePageRecord(chips: [], sections: [HomeSectionRecord(title: "Albums for you", format: .largeCards,
            items: items, moreBrowseId: nil, moreParams: nil)], continuation: nil)
    }
}
