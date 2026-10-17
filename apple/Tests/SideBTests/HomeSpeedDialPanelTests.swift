import AppKit
import SideBCore
import Observation
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class HomeSpeedDialPanelTests: XCTestCase {
    private func songs(count: Int = 27, prefix: String = "song") -> [HomeItemRecord] {
        (0..<count).map { index in
            HomeItemRecord(kind: "song", id: "\(prefix)-\(index)", title: "Song \(index)", subtitle: nil,
                thumbnail: nil, duration: nil, artists: "Artist", artistId: nil,
                album: nil, albumId: nil, artistRuns: [], explicit: false)
        }
    }

    func testFortyParentResizesDoNotRebuildFixedSpeedDialButTileChangesStillApply() throws {
        let probes = SpeedDialProbes(), state = SpeedDialPageState()
        let page = Binding(get: { state.page }, set: { state.page = $0 })
        let tile: (HomeItemRecord, CGFloat) -> SpeedDialArtworkProbe = { record, size in
            probes.builds += 1
            return SpeedDialArtworkProbe(record: record, tile: size, caption: L10n.text("app.home.speedDial"), probes: probes)
        }
        let activate: (HomeItemRecord) -> Void = { _ in }
        let records = songs()
        func root(_ width: CGFloat) -> SpeedDialFixture {
            SpeedDialFixture(width: width, songs: records, page: page,
                onSong: activate, menuProvider: nil, tile: tile)
        }
        let host = NSHostingView(rootView: root(1100))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 600)
        host.layoutSubtreeIfNeeded()
        // Settle LazyVGrid's first mounted proposal before recording the resize
        // series. This is a one-time initialization check, not measured work.
        for width: CGFloat in [1110, 1100] {
            host.rootView = root(width)
            host.frame.size.width = width
            host.layoutSubtreeIfNeeded()
        }
        let originals = probes.views
        XCTAssertEqual(originals.count, 9)
        let builds = probes.builds, updates = probes.updates
        for index in 0..<40 {
            // Both directions, entirely within the fixed144pt tile range.
            let width = CGFloat(1100 + (index.isMultiple(of: 2) ? index * 7 : -index * 3))
            host.rootView = root(width)
            host.frame.size.width = width
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(probes.views.keys.sorted(), originals.keys.sorted())
            for (id, original) in originals { XCTAssertTrue(probes.views[id] === original) }
        }
        print("Speed Dial: 40 fixed-tile parent resizes, \(probes.builds - builds) tile builds, \(probes.updates - updates) native artwork updates")
        XCTAssertEqual(probes.builds, builds)
        XCTAssertEqual(probes.updates, updates)

        host.rootView = root(930)
        host.frame.size.width = 930
        host.layoutSubtreeIfNeeded()
        let expected = HomeFeaturedLayout(width: 930, hasSongs: true, hasAlbums: true).tile
        XCTAssertLessThan(expected, 144)
        for (id, original) in originals {
            XCTAssertTrue(probes.views[id] === original)
            XCTAssertEqual(original.tile, expected, accuracy: 0.000001)
        }
        XCTAssertGreaterThan(probes.builds, builds)
        XCTAssertGreaterThan(probes.updates, updates)
        XCTAssertNil(host.window)
    }

    func testSemanticChangesAndCurrentMenusReachMountedArtworkWithoutResizing() throws {
        let probes = SpeedDialProbes(), state = SpeedDialPageState()
        let page = Binding(get: { state.page }, set: { state.page = $0 })
        let tile: (HomeItemRecord, CGFloat) -> SpeedDialArtworkProbe = { record, size in
            probes.builds += 1
            return SpeedDialArtworkProbe(record: record, tile: size, caption: L10n.text("app.home.speedDial"), probes: probes)
        }
        let action: (HomeItemRecord) -> Void = { _ in }
        let firstMenu: (HomeItemRecord) -> NSMenu? = { NSMenu(title: "first:\($0.id)") }
        let currentMenu: (HomeItemRecord) -> NSMenu? = { NSMenu(title: "current:\($0.id)") }
        var records = songs()
        func root(menu: @escaping (HomeItemRecord) -> NSMenu?,
                  playing: Bool = false, active: Bool = true) -> SpeedDialFixture {
            SpeedDialFixture(width: 1100, songs: records, page: page, isPlaying: playing,
                playbackContext: .radio(seedVideoId: "song-0", title: "Radio", seedName: "Song"),
                active: active, onSong: action, menuProvider: menu, tile: tile)
        }
        let host = NSHostingView(rootView: root(menu: firstMenu))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 600)
        host.layoutSubtreeIfNeeded()
        let original = try XCTUnwrap(probes.views["song-0"])
        let menus = descendants(host).compactMap { $0 as? NativeContextMenuNSView }
        XCTAssertEqual(menus.count, 9)
        XCTAssertTrue(menus.allSatisfy { $0.menuBuilder?()?.title.hasPrefix("first:") == true })
        records[0].title = "Updated song"
        host.rootView = root(menu: currentMenu, playing: true)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(probes.views["song-0"] === original)
        XCTAssertEqual(original.title, "Updated song")
        XCTAssertTrue(menus.allSatisfy { $0.menuBuilder?()?.title.hasPrefix("current:") == true })

        let previousLanguage = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previousLanguage) }
        AppLanguageStore.shared.setLanguage(previousLanguage == .es ? .en : .es)
        host.layoutSubtreeIfNeeded()
        // Localized content supplied by the tile renderer must refresh through
        // the extracted panel. SwiftUI text is not assumed to be NSTextField.
        XCTAssertEqual(original.caption, L10n.text("app.home.speedDial"))
        host.rootView = root(menu: currentMenu, active: false)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(original.isActive)
        host.rootView = root(menu: currentMenu, active: true)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(original.isActive)
    }

    func testPagingAndBreakpointsKeepBoundedPagesAndSongIdentity() throws {
        let probes = SpeedDialProbes(), state = SpeedDialPageState()
        let page = Binding(get: { state.page }, set: { state.page = $0 })
        let records = songs()
        let tile: (HomeItemRecord, CGFloat) -> SpeedDialArtworkProbe = { record, size in
            SpeedDialArtworkProbe(record: record, tile: size, caption: L10n.text("app.home.speedDial"), probes: probes)
        }
        func root(_ width: CGFloat) -> SpeedDialFixture {
            SpeedDialFixture(width: width, songs: records, page: page,
                onSong: { _ in }, menuProvider: { NSMenu(title: $0.id) }, tile: tile)
        }
        let host = NSHostingView(rootView: root(1100))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 600)
        host.layoutSubtreeIfNeeded()
        let initial = probes.views
        for width: CGFloat in [1512, 1920, 1512, 899, 900, 960, 1100] {
            host.rootView = root(width)
            host.frame.size.width = width
            host.layoutSubtreeIfNeeded()
            for (id, view) in initial { XCTAssertTrue(probes.views[id] === view) }
        }
        let wheel = try XCTUnwrap(descendants(host).compactMap { $0 as? HomeFeaturedWheelView }.first)
        XCTAssertTrue(wheel.ownsHorizontalNavigationGesture)
        wheel.onPage?(1)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(state.page, 1)
        let menuIDs = descendants(host).compactMap { ($0 as? NativeContextMenuNSView)?.menuBuilder?()?.title }
        XCTAssertEqual(Set(menuIDs), Set(records[9..<18].map(\.id)))
        XCTAssertLessThanOrEqual(menuIDs.count, 9)
        wheel.onPage?(-1)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(state.page, 0)
        let restoredIDs = descendants(host).compactMap { ($0 as? NativeContextMenuNSView)?.menuBuilder?()?.title }
        XCTAssertEqual(Set(restoredIDs), Set(records[0..<9].map(\.id)))
        XCTAssertEqual(host.frame.width, 1100)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }


}

@MainActor @Observable private final class SpeedDialPageState { var page = 0 }
@MainActor private final class SpeedDialProbes {
    var builds = 0
    var updates = 0
    var views: [String: SpeedDialArtworkProbeView] = [:]
}

private struct SpeedDialFixture: View {
    let width: CGFloat
    let songs: [HomeItemRecord]
    let page: Binding<Int>
    var isPlaying = false
    var playbackContext: QueueContext? = nil
    var active = true
    let onSong: (HomeItemRecord) -> Void
    let menuProvider: ((HomeItemRecord) -> NSMenu?)?
    let tile: (HomeItemRecord, CGFloat) -> SpeedDialArtworkProbe
    var body: some View {
        let geometry = HomeFeaturedLayout(width: width, hasSongs: true, hasAlbums: true)
        HStack(alignment: .top, spacing: 24) {
            HomeSpeedDialPanel(songs: songs, page: page, tileSize: geometry.tile,
                gridHeight: geometry.songGridHeight, panelHeight: geometry.songPanelHeight,
                playbackContext: playbackContext, isPlaying: isPlaying, onSong: onSong,
                menuProvider: menuProvider, tile: tile)
                .frame(width: geometry.songWidth)
            Color.clear.frame(maxWidth: .infinity)
        }
        .environment(\.sideBPageIsActive, active)
        // Exercise pagination semantics without retaining outgoing controls
        // for the production crossfade in an off-window hosting fixture.
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        .frame(width: width, height: geometry.totalHeight, alignment: .topLeading)
    }
}

private struct SpeedDialArtworkProbe: NSViewRepresentable {
    let record: HomeItemRecord
    let tile: CGFloat
    let caption: String
    let probes: SpeedDialProbes
    @Environment(\.sideBPageIsActive) private var isActive
    func makeNSView(context: Context) -> SpeedDialArtworkProbeView {
        let view = SpeedDialArtworkProbeView()
        probes.views[record.id] = view
        return view
    }
    func updateNSView(_ view: SpeedDialArtworkProbeView, context: Context) {
        probes.updates += 1
        view.tile = tile
        view.title = record.title
        view.caption = caption
        view.isActive = isActive
    }
}
@MainActor private final class SpeedDialArtworkProbeView: NSView {
    var tile: CGFloat = 0
    var title = ""
    var caption = ""
    var isActive = true
}
