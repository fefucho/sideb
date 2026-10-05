import AppKit
import SwiftUI
import Observation
import SideBCore
import XCTest
@testable import SideB

@MainActor @Observable private final class CollectionSearchFixture {
    var query = ""
    var headerHeight: CGFloat = 360
    let tracks = (0..<94).map { collectionDetailFixtureTrack("song-\($0)") }
}

private struct CollectionSearchFixtureView: View {
    let model: CollectionSearchFixture
    let presentation: TrackTablePresentation

    var body: some View {
        NativeTrackTableView(tracks: model.query.isEmpty ? model.tracks : [], presentation: presentation,
                             rowHeight: CollectionTrackMetrics.rowHeight, onPlayTrack: { _ in },
                             scrollingHeader: AnyView(CollectionDetailHeaderView(
                                kind: "PLAYLIST", title: "Fixture", thumbnail: nil, artworkSymbol: "music.note.list",
                                onExpandDescription: {}, onPlay: {}, onShuffle: {},
                                query: Binding(get: { model.query }, set: { model.query = $0 }))
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                    if abs(model.headerHeight - height) > 0.5 { model.headerHeight = height }
                                }),
                             scrollingHeaderHeight: model.headerHeight,
                             footer: model.query.isEmpty ? nil : AnyView(CollectionDetailEmptyResultsView(query: model.query)),
                             footerHeight: 72)
    }
}

@MainActor private func collectionDescendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let found = view as? T, !found.isHiddenOrHasHiddenAncestor { return found }
    for child in view.subviews {
        if let found = collectionDescendant(type, in: child) { return found }
    }
    return nil
}

// XCTest runs this native UI scenario separately from the parallel model tests.
// Window/SwiftUI initialization must not consume their short provider deadlines.
final class CollectionSearchIntegrationTests: XCTestCase {
    @MainActor func testArtworkPaintsTheTopEdgeInAWindowWithANativeTitlebar() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "CollectionBackdropFixture")
        window.toolbarStyle = .unifiedCompact
        defer { window.close() }
        let root = CollectionBackgroundCanvas(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        window.contentView = root
        let canvas = CollectionBackgroundCanvas(frame: root.bounds)
        root.addSubview(canvas)
        let scroll = NSScrollView(frame: root.bounds)
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        root.addSubview(scroll)
        let document = NativeTrackTableViewInternal(frame: NSRect(x: 0, y: 0, width: 1000, height: 2000))
        document.headerView = nil
        scroll.documentView = document
        let controller = CollectionBackgroundController()
        controller.activate(identity: "fixture:album", enabled: true, reduceMotion: true, scenePhase: .active)
        controller.register(owner: UUID(), identity: "fixture:album", document: document, headerHeight: 400) { _ in
            AnyView(GeometryReader { geometry in
                Rectangle().fill(Color.red).frame(width: geometry.size.width, height: geometry.size.height)
            })
        }
        controller.attach(canvas)
        let host = try XCTUnwrap(controller.host)
        for _ in 0..<5 {
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(host.safeAreaInsets.top, 0, "Fixture must include the actual window titlebar")
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let top = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 1)?.usingColorSpace(.deviceRGB))
        let body = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(top.alphaComponent, 0.95, "Artwork must paint above the titlebar safe area")
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 2)).alphaComponent, 0.95)
        XCTAssertGreaterThan(top.redComponent, 0.8)
        XCTAssertEqual(top.redComponent, body.redComponent, accuracy: 0.01)
        XCTAssertFalse(window.isVisible)
    }

    @MainActor func testClearButtonRestoresSongsThroughTheMountedSwiftUIAndNativeTable() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        for presentation: TrackTablePresentation in [.collectionAlbum, .collectionPlaylist] {
            let model = CollectionSearchFixture()
            let hosting = NSHostingView(rootView: CollectionSearchFixtureView(model: model, presentation: presentation))
            hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 700)
            window.contentView = hosting
            for _ in 0..<10 {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            let table = try XCTUnwrap(collectionDescendant(NativeTrackTableViewInternal.self, in: hosting))
            let field = try XCTUnwrap(collectionDescendant(CollectionSearchTextField.self, in: hosting))
            let prefix = presentation == .collectionPlaylist ? 2 : 1
            XCTAssertTrue(table.numberOfRows == model.tracks.count + prefix)
            let initialSearchFrame = field.convert(field.bounds, to: hosting)
            let initialHeaderHeight = table.rect(ofRow: 0).height
            XCTAssertTrue(window.makeFirstResponder(field))
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            XCTAssertFalse(editor.drawsBackground, "Focus must be transparent before the first keystroke")
            // Start editing through the actual delegate path, then press the same
            // native button used by mouse/keyboard, while no songs match.
            editor.insertText("no-match", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            for _ in 0..<10 {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(table.numberOfRows, prefix + 1)
            XCTAssertEqual(table.rect(ofRow: 0).height, initialHeaderHeight, accuracy: 0.5)
            XCTAssertEqual(field.convert(field.bounds, to: hosting).minY, initialSearchFrame.minY, accuracy: 0.5)
            XCTAssertTrue(!editor.drawsBackground)
            let search = try XCTUnwrap(collectionDescendant(CollectionSearchControl.self, in: hosting))
            let clear = search.clearButton
            XCTAssertTrue(clear.isEnabled && clear.accessibilityLabel() == "Borrar búsqueda")
            clear.performClick(nil)
            for _ in 0..<10 {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(model.query.isEmpty)
            XCTAssertTrue(field.stringValue.isEmpty && editor.string.isEmpty)
            XCTAssertTrue(window.firstResponder === editor)
            XCTAssertTrue(table.numberOfRows == model.tracks.count + prefix)
            XCTAssertTrue(collectionDescendant(CollectionSearchTextField.self, in: hosting) === field)
            XCTAssertEqual(table.rect(ofRow: 0).height, initialHeaderHeight, accuracy: 0.5)
            XCTAssertEqual(field.convert(field.bounds, to: hosting).minY, initialSearchFrame.minY, accuracy: 0.5)
            XCTAssertTrue(!clear.isEnabled && clear.alphaValue == 0)
            // Mouse activation runs the local monitor before the button action.
            // Clear belongs to this editing control; only actual outside clicks dismiss it.
            model.query = "no-match"
            for _ in 0..<10 {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(table.numberOfRows == prefix + 1)
            let point = clear.convert(NSPoint(x: clear.bounds.midX, y: clear.bounds.midY), to: nil)
            field.releaseFocusIfClickedOutside(in: window, at: point)
            XCTAssertTrue(window.firstResponder === editor)
            clear.performClick(nil)
            for _ in 0..<10 {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(model.query.isEmpty && field.stringValue.isEmpty)
            XCTAssertTrue(window.firstResponder === editor)
            XCTAssertTrue(table.numberOfRows == model.tracks.count + prefix)
            XCTAssertTrue(collectionDescendant(CollectionSearchControl.self, in: hosting) === search)
            XCTAssertTrue(!window.isVisible)
        }
    }
}
