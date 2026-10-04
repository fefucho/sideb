import AppKit
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
}
