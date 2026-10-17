import AppKit
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class NavigationSearchPanelTests: XCTestCase {
    func testPanelAnchorsBelowTheWholeCapsuleAndFitsAbovePlayer() {
        for viewport in [CGRect(x: 0, y: 0, width: 960, height: 640), CGRect(x: 20, y: 10, width: 1440, height: 900)] {
            for x in [viewport.minX + 260, viewport.midX, viewport.maxX - 300] {
                let search = CGRect(x: x, y: viewport.minY + 18, width: 298, height: 42)
                let panel = NavigationSearchPanelLayout.frame(search: search, viewport: viewport)
                XCTAssertEqual(panel.minY, search.maxY + 8)
                XCTAssertLessThanOrEqual(panel.maxY, viewport.maxY - 114)
                XCTAssertGreaterThanOrEqual(panel.minX, viewport.minX + 18)
                XCTAssertLessThanOrEqual(panel.maxX, viewport.maxX - 18)
                XCTAssertLessThanOrEqual(panel.width, 560)
                XCTAssertLessThanOrEqual(panel.height, 540)
            }
        }
    }

    func testPanelIsHittableInsideViewportAndDoesNotCloseSearch() throws {
        let (window, header, coordinator) = makeHeader()
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        header.setPresentation(sidebarExpanded: false, searchExpanded: true, visible: true, reduceMotion: true)
        header.layoutSubtreeIfNeeded()
        XCTAssertFalse(header.searchResultsHost.isHidden)
        XCTAssertTrue(header.bounds.contains(header.searchResultsHost.frame))
        var requests: [Bool] = []
        header.searchBar.onToggleExpand = { requests.append($0) }
        let panelPoint = header.searchResultsHost.convert(NSPoint(x: 40, y: 40), to: header)
        let hit = try XCTUnwrap(header.hitTest(header.convert(panelPoint, to: header.superview)))
        XCTAssertTrue(hit.isDescendant(of: header.searchResultsHost))
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: header.convert(panelPoint, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        header.handleOutsideSearchClick(event)
        XCTAssertTrue(header.searchBar.isExpanded)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(header.hitTest(header.convert(NSPoint(x: 12, y: 600), to: header.superview)), "Transparent viewport must pass through to the page")
        header.searchResultsHost.setContent(nil)
        header.layoutSubtreeIfNeeded()
        XCTAssertTrue(header.searchResultsHost.isHidden)
        XCTAssertNil(header.hitTest(header.convert(panelPoint, to: header.superview)))
    }

    func testPanelSharesSidebarCompositorTimingWithoutStartingWidthClock() throws {
        let (window, header, coordinator) = makeHeader()
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        window.setContentSize(NSSize(width: 1400, height: 900))
        header.setPresentation(sidebarExpanded: false, searchExpanded: true, visible: true, reduceMotion: true)
        header.layoutSubtreeIfNeeded()
        header.setPresentation(sidebarExpanded: true, searchExpanded: true, visible: true, reduceMotion: false)
        XCTAssertFalse(header.isFrameClockRunning)
        let capsule = try XCTUnwrap(header.searchHost.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey) as? CAKeyframeAnimation)
        let panel = try XCTUnwrap(header.searchResultsHost.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey) as? CAKeyframeAnimation)
        XCTAssertEqual(capsule.duration, panel.duration)
        XCTAssertEqual(capsule.beginTime, panel.beginTime)
        let capsuleOffset = try XCTUnwrap(capsule.values?.first as? NSValue).pointValue
        let panelOffset = try XCTUnwrap(panel.values?.first as? NSValue).pointValue
        XCTAssertEqual(capsuleOffset.x, panelOffset.x, accuracy: 0.001)
        XCTAssertEqual(header.searchHost.frame.minX, header.searchResultsHost.frame.minX, accuracy: 0.001)
        header.setPresentation(sidebarExpanded: true, searchExpanded: true, visible: false, reduceMotion: false)
        XCTAssertTrue(header.searchResultsHost.isHidden)
        XCTAssertNil(header.searchResultsHost.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey))
    }

    func testSessionChangeReappliesUnchangedPresentationAfterClearingInput() {
        let (window, header, coordinator) = makeHeader()
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        header.setPresentation(sidebarExpanded: false, searchExpanded: true, visible: true, reduceMotion: true)
        header.searchBar.setQuery("previous account")
        header.setSearchSession(revision: 2, query: "")
        XCTAssertFalse(header.searchBar.isExpanded)
        header.setPresentation(sidebarExpanded: false, searchExpanded: true, visible: true, reduceMotion: true)
        XCTAssertTrue(header.searchBar.isExpanded)
        XCTAssertEqual(header.searchBar.textField.stringValue, "")
        XCTAssertTrue(window.firstResponder === header.searchBar.textField.currentEditor())
        XCTAssertEqual(header.searchHost.frame.width, 298, accuracy: 0.001)
    }

    private func makeHeader() -> (NSWindow, NativeNavigationHeader, WindowNavigationToolbarView.Coordinator) {
        let router = NavigationRouter()
        let spec = WindowNavigationToolbarView(
            navigation: TopNavigationView(selection: .home, isPresented: true, reduceMotion: false,
                onHome: {}, onLibrary: {}, onSearch: {}),
            history: HistoryToolbarView(router: router, isDisabled: false), showsHistory: true,
            viewportWidth: 960, searchResultsContent: AnyView(Text("Recent results").frame(maxWidth: .infinity, maxHeight: .infinity)))
        let coordinator = spec.makeCoordinator()
        let header = spec.makeNativeHeader(coordinator: coordinator, reduceTransparency: true)
        let window = NSWindow(contentRect: CGRect(x: -2000, y: -2000, width: 960, height: 640),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = header
        header.layoutSubtreeIfNeeded()
        return (window, header, coordinator)
    }
}
