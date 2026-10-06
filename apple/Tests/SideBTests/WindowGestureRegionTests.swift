import AppKit
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class WindowGestureRegionTests: XCTestCase {
    private final class PagedContent: NSView, HorizontalNavigationGestureOwner {
        var ownsHorizontalNavigationGesture = true
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private func root() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        view.addSubview(marker(.content, frame: view.bounds))
        return view
    }

    private func marker(_ region: WindowGestureRegion, frame: NSRect) -> WindowGestureRegionView {
        let marker = WindowGestureRegionView(frame: frame)
        marker.region = region
        return marker
    }

    func testSemanticPanelOwnsAnEmptyViewportWithoutInterceptingClicks() {
        let root = root()
        let panel = marker(.verticalContent, frame: NSRect(x: 470, y: 100, width: 400, height: 500))
        root.addSubview(panel)
        let input = WindowGestureRegions.routing(at: NSPoint(x: 600, y: 300), in: root)
        XCTAssertTrue(input.isInContent)
        XCTAssertTrue(input.ownsVertical)
        XCTAssertTrue(input.allowsHistory)
        XCTAssertFalse(input.allowsFullscreenDismissal)
        XCTAssertNil(panel.hitTest(NSPoint(x: 600, y: 300)))
        XCTAssertFalse(panel.isAccessibilityElement())
        XCTAssertTrue(WindowGestureRegions.routing(at: NSPoint(x: 200, y: 300), in: root).allowsFullscreenDismissal)
        XCTAssertNil(root.window)
    }

    func testInactiveFlippedArtworkAndInvisibleRegionsDoNotOwnGesture() {
        let root = root()
        let panel = marker(.verticalContent, frame: NSRect(x: 100, y: 100, width: 300, height: 300))
        root.addSubview(panel)
        let point = NSPoint(x: 200, y: 200)
        XCTAssertFalse(WindowGestureRegions.routing(at: point, in: root).allowsFullscreenDismissal)
        panel.isRegionActive = false
        XCTAssertTrue(WindowGestureRegions.routing(at: point, in: root).allowsFullscreenDismissal)
        panel.isRegionActive = true
        panel.isHidden = true
        XCTAssertTrue(WindowGestureRegions.routing(at: point, in: root).allowsFullscreenDismissal)
        panel.isHidden = false
        panel.alphaValue = 0
        XCTAssertTrue(WindowGestureRegions.routing(at: point, in: root).allowsFullscreenDismissal)
    }

    func testBoundsAndAncestorVisibilityLimitNonHittableOwners() {
        let root = root()
        let clipped = NSView(frame: NSRect(x: 100, y: 100, width: 100, height: 100))
        let panel = marker(.horizontalContent, frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        clipped.addSubview(panel)
        root.addSubview(clipped)
        let inside = WindowGestureRegions.routing(at: NSPoint(x: 150, y: 150), in: root)
        XCTAssertTrue(inside.ownsHorizontal)
        XCTAssertTrue(inside.allowsHistory)
        XCTAssertTrue(WindowGestureRegions.routing(at: NSPoint(x: 250, y: 150), in: root).allowsHistory)
        clipped.alphaValue = 0
        XCTAssertTrue(WindowGestureRegions.routing(at: NSPoint(x: 150, y: 150), in: root).allowsHistory)
        XCTAssertFalse(WindowGestureRegions.routing(at: NSPoint(x: 1000, y: 150), in: root).isInContent)
    }

    func testPagedOwnerRemainsDetectableWithoutAnEventDependentHitTarget() {
        let root = root()
        let paged = PagedContent(frame: NSRect(x: 100, y: 100, width: 300, height: 300))
        root.addSubview(paged)
        let routing = WindowGestureRegions.routing(at: NSPoint(x: 200, y: 200), in: root)
        XCTAssertTrue(routing.ownsHorizontal)
        XCTAssertTrue(routing.allowsHistory)
        paged.ownsHorizontalNavigationGesture = false
        XCTAssertTrue(WindowGestureRegions.routing(at: NSPoint(x: 200, y: 200), in: root).allowsHistory)
    }

    func testAutomaticElasticityDoesNotClaimHorizontalOnAVerticalList() {
        let root = root()
        let scroll = NSScrollView(frame: NSRect(x: 100, y: 100, width: 300, height: 300))
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = true
        scroll.horizontalScrollElasticity = .automatic
        scroll.verticalScrollElasticity = .allowed
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 1200))
        root.addSubview(scroll)
        scroll.tile()
        scroll.documentView?.frame.size.width = scroll.contentView.bounds.width
        let input = WindowGestureRegions.routing(at: NSPoint(x: 200, y: 200), in: root)
        XCTAssertTrue(input.ownsVertical)
        XCTAssertFalse(input.ownsHorizontal)
        XCTAssertTrue(input.allowsHistory)
        XCTAssertFalse(input.allowsFullscreenDismissal)
    }

    func testNativeHorizontalRegionKeepsOwnershipWithNoOverflow() {
        let root = root()
        let scroll = NSScrollView(frame: NSRect(x: 100, y: 100, width: 300, height: 300))
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.documentView = NSView(frame: scroll.bounds)
        root.addSubview(scroll)
        scroll.tile()
        scroll.documentView?.frame.size = scroll.contentView.bounds.size
        let input = WindowGestureRegions.routing(at: NSPoint(x: 200, y: 200), in: root)
        XCTAssertTrue(input.ownsHorizontal)
        XCTAssertFalse(input.ownsVertical)
        XCTAssertTrue(input.allowsHistory)
        XCTAssertFalse(input.allowsFullscreenDismissal)
    }

    func testUnderlyingNativeScrollCannotOwnForegroundInput() {
        let root = root()
        let scroll = NSScrollView(frame: NSRect(x: 100, y: 100, width: 300, height: 300))
        scroll.hasVerticalScroller = true
        scroll.verticalScrollElasticity = .allowed
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 1200))
        root.addSubview(scroll)
        let foreground = NSView(frame: scroll.frame)
        root.addSubview(foreground)
        let input = WindowGestureRegions.routing(at: NSPoint(x: 200, y: 200), in: root)
        XCTAssertFalse(input.ownsVertical)
        XCTAssertTrue(input.allowsFullscreenDismissal)
    }

    func testFullscreenUsesSemanticRegionsWithoutUnderlyingScrollOrPagedOwner() {
        let root = root()
        let scroll = NSScrollView(frame: NSRect(x: 100, y: 100, width: 300, height: 300))
        scroll.hasVerticalScroller = true
        scroll.verticalScrollElasticity = .allowed
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 1200))
        root.addSubview(scroll)
        root.addSubview(PagedContent(frame: scroll.frame))
        let point = NSPoint(x: 200, y: 200)
        let history = WindowGestureRegions.routing(at: point, in: root)
        XCTAssertTrue(history.ownsHorizontal)
        XCTAssertTrue(history.ownsVertical)
        let fullscreen = WindowGestureRegions.routing(at: point, in: root, includeNativeFallback: false)
        XCTAssertTrue(fullscreen.allowsFullscreenDismissal)
        root.addSubview(marker(.verticalContent, frame: scroll.frame))
        XCTAssertFalse(WindowGestureRegions.routing(at: point, in: root,
                                                   includeNativeFallback: false).allowsFullscreenDismissal)
    }

    func testExclusionsAndControlsOnlyProtectFullscreenDismissal() {
        let root = root()
        let excluded = marker(.excluded, frame: NSRect(x: 10, y: 10, width: 70, height: 70))
        root.addSubview(excluded)
        let exclusion = WindowGestureRegions.routing(at: NSPoint(x: 30, y: 30), in: root)
        XCTAssertTrue(exclusion.isExcluded)
        XCTAssertTrue(exclusion.allowsHistory)
        XCTAssertFalse(exclusion.allowsFullscreenDismissal)

        // Botones e imágenes no bloquean la navegación por trackpad
        let button = NSButton(frame: NSRect(x: 100, y: 100, width: 100, height: 40))
        root.addSubview(button)
        XCTAssertFalse(WindowGestureRegions.routing(at: NSPoint(x: 130, y: 120), in: root).isExcluded)
        XCTAssertTrue(WindowGestureRegions.routing(at: NSPoint(x: 130, y: 120), in: root).allowsHistory)

        let image = NSImageView(frame: NSRect(x: 100, y: 150, width: 50, height: 50))
        root.addSubview(image)
        XCTAssertFalse(WindowGestureRegions.routing(at: NSPoint(x: 120, y: 170), in: root).isExcluded)
        XCTAssertTrue(WindowGestureRegions.routing(at: NSPoint(x: 120, y: 170), in: root).allowsHistory)

        // Labels no editables permiten historial
        let label = NSTextField(labelWithString: "Álbum")
        label.frame = NSRect(x: 250, y: 100, width: 100, height: 40)
        root.addSubview(label)
        XCTAssertTrue(WindowGestureRegions.routing(at: NSPoint(x: 280, y: 120), in: root).allowsHistory)

        // Editing and sliders protect dismissal, while history has priority.
        let editableField = NSTextField(frame: NSRect(x: 250, y: 200, width: 100, height: 40))
        editableField.isEditable = true
        root.addSubview(editableField)
        let editing = WindowGestureRegions.routing(at: NSPoint(x: 280, y: 220), in: root)
        XCTAssertTrue(editing.isExcluded)
        XCTAssertTrue(editing.allowsHistory)
        XCTAssertFalse(editing.allowsFullscreenDismissal)

        let slider = NSSlider(frame: NSRect(x: 400, y: 100, width: 100, height: 20))
        root.addSubview(slider)
        let scrubbing = WindowGestureRegions.routing(at: NSPoint(x: 430, y: 110), in: root)
        XCTAssertTrue(scrubbing.isExcluded)
        XCTAssertTrue(scrubbing.allowsHistory)
        XCTAssertFalse(scrubbing.allowsFullscreenDismissal)
    }

    func testPreviewRevealsSuspendedHomeWithoutMeasurementsOrReplacingViewport() throws {
        let player = PlayerViewModel()
        var measurements = 0
        func feed(obscured: Bool, preview: Bool) -> some View {
            HomeFeedTableView(featuredContent: { AnyView(Text("Featured \($0)")) },
                featuredHeight: { _ in measurements += 1; return 500 },
                sections: [], isObscured: obscured, revision: 1, selectedChip: nil,
                hasMore: false, isLoadingMore: false, currentTrackID: nil, isPlaying: false,
                player: player, router: nil, onNavigate: { _ in }, onLoadMore: {})
                .environment(\.sideBGesturePreviewVisible, preview)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        let host = NSHostingView(rootView: feed(obscured: false, preview: false))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 300)
        host.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? HomeFeedScrollView }.first)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 90))
        scroll.reflectScrolledClipView(scroll.contentView)
        let offset = scroll.contentView.bounds.minY
        let retainedSize = scroll.frame.size
        host.rootView = feed(obscured: true, preview: false)
        host.layoutSubtreeIfNeeded()
        let suspendedMeasurements = measurements
        for preview in [true, false, true, false] {
            host.rootView = feed(obscured: true, preview: preview)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(scroll.isHidden, !preview)
            XCTAssertEqual(measurements, suspendedMeasurements)
            XCTAssertEqual(scroll.frame.size, retainedSize)
            XCTAssertEqual(scroll.contentView.bounds.minY, offset, accuracy: 0.5)
            XCTAssertTrue(scroll === descendants(host).compactMap { $0 as? HomeFeedScrollView }.first)
        }
        host.rootView = feed(obscured: false, preview: false)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(scroll.isHidden)
        XCTAssertGreaterThan(measurements, suspendedMeasurements)
        XCTAssertEqual(scroll.contentView.bounds.minY, offset, accuracy: 0.5)
        XCTAssertNil(host.window)
    }

    func testVerticalTrackTableAndButtonsPermitHistoryNavigation() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let scroll = NSScrollView(frame: NSRect(x: 200, y: 0, width: 700, height: 700))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .allowed

        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 700, height: 1200))
        let row = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 700, height: 50))
        let button = NSButton(frame: NSRect(x: 10, y: 10, width: 30, height: 30))
        let artwork = NSImageView(frame: NSRect(x: 50, y: 5, width: 40, height: 40))
        row.addSubview(button)
        row.addSubview(artwork)
        table.addSubview(row)
        scroll.documentView = table
        root.addSubview(scroll)

        let routing = WindowGestureRegions.routing(at: NSPoint(x: 220, y: 20), in: root)
        XCTAssertTrue(routing.isInContent)
        XCTAssertFalse(routing.isExcluded)
        XCTAssertFalse(routing.ownsHorizontal)
        XCTAssertTrue(routing.ownsVertical)
        XCTAssertTrue(routing.allowsHistory)
    }

    func testViewportWithoutSemanticMarkerStillRecognizesNavigableContent() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let routing = WindowGestureRegions.routing(at: NSPoint(x: 500, y: 350), in: root)
        XCTAssertTrue(routing.isInContent)
        XCTAssertFalse(routing.isExcluded)
        XCTAssertFalse(routing.ownsHorizontal)
        XCTAssertTrue(routing.allowsHistory)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
