import AppKit
import XCTest
@testable import SideB

@MainActor
final class NavigationHeaderAnimationTests: XCTestCase {
    func testDisplayStepChangesActualGlassBoundsAndLeavesHistoryFixed() throws {
        for solid in [false, true] {
            let (window, header, coordinator) = makeHeader(solid: solid)
            defer { window.close(); withExtendedLifetime(coordinator) {} }
            let historyFrame = header.history.frame
            header.setPresentation(sidebarExpanded: false, searchExpanded: true, visible: true, reduceMotion: false)
            XCTAssertTrue(header.isAnimating)
            header.advanceAnimation(at: CACurrentMediaTime() + 0.02)
            XCTAssertGreaterThan(header.searchHost.frame.width, 42)
            XCTAssertLessThan(header.searchHost.frame.width, 298)
            let effect = try XCTUnwrap(header.searchHost.subviews.first)
            XCTAssertEqual(effect.bounds.width, header.searchHost.frame.width, accuracy: 0.001)
            XCTAssertEqual(header.searchBar.bounds.width, effect.bounds.width, accuracy: 0.001)
            XCTAssertEqual(header.history.frame, historyFrame)
            XCTAssertLessThan(header.navigationHost.alphaValue, 1)
            let destinationSurface = try XCTUnwrap(coordinator.navigation.surface)
            let destinationGlass = try XCTUnwrap(destinationSurface.subviews.first)
            XCTAssertEqual(destinationGlass.alphaValue, 1)
            XCTAssertFalse(destinationGlass.isHidden)
            XCTAssertFalse(try XCTUnwrap(coordinator.navigation.bar).control.isHidden)

            header.advanceAnimation(at: CACurrentMediaTime() + 1)
            XCTAssertEqual(header.searchHost.frame.width, 298, accuracy: 0.001)
            XCTAssertEqual(header.history.frame, historyFrame)
            XCTAssertFalse(header.isAnimating)
            XCTAssertTrue(header.navigationHost.isHidden)
            XCTAssertTrue(header.searchBar.textField.currentEditor() === window.firstResponder)
        }
    }

    func testSidebarAndSearchTransitionsKeepIndependentTargetsAndDetachStopsClock() {
        let (window, header, coordinator) = makeHeader(solid: true)
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        header.setPresentation(sidebarExpanded: true, searchExpanded: false, visible: true, reduceMotion: false)
        header.setPresentation(sidebarExpanded: true, searchExpanded: true, visible: true, reduceMotion: false)
        header.advanceAnimation(at: CACurrentMediaTime() + 1)
        XCTAssertEqual(header.sidebarProgress, 1)
        XCTAssertEqual(header.searchProgress, 1)

        header.setPresentation(sidebarExpanded: false, searchExpanded: true, visible: true, reduceMotion: false)
        XCTAssertTrue(header.isAnimating)
        let parent = NSView(frame: header.frame)
        window.contentView = parent
        XCTAssertNil(header.window)
        XCTAssertFalse(header.isAnimating)
        XCTAssertEqual(header.sidebarProgress, 0)
        XCTAssertEqual(header.searchProgress, 1)
    }

    func testReduceMotionSnapsGeometryAndFinishesFadeWithoutRemovingHistory() {
        let (window, header, coordinator) = makeHeader(solid: true)
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        let history = header.history.frame
        header.setPresentation(sidebarExpanded: false, searchExpanded: true, visible: true, reduceMotion: true)
        header.layoutSubtreeIfNeeded()
        XCTAssertEqual(header.searchHost.frame.width, 298, accuracy: 0.001)
        XCTAssertEqual(header.history.frame, history)
        header.advanceAnimation(at: CACurrentMediaTime() + 0.16)
        XCTAssertFalse(header.isAnimating)
        XCTAssertFalse(header.history.isHidden)
        XCTAssertTrue(header.navigationHost.isHidden)
    }

    func testSidebarUsesAdditiveCompositorTranslationWithoutSearchClockOrLayoutRestart() throws {
        let (window, header, coordinator) = makeHeader(solid: true)
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        let originalSearch = header.searchHost.frame
        let originalHistory = header.history.frame
        let originalPositions = [header.searchHost.layer!.position, header.history.layer!.position]
        header.searchBar.needsLayout = false
        header.setPresentation(sidebarExpanded: true, searchExpanded: false, visible: true, reduceMotion: false)
        XCTAssertTrue(header.isAnimating)
        XCTAssertFalse(header.isFrameClockRunning, "A translation must survive without a main-runloop frame clock")
        XCTAssertEqual(header.searchHost.frame.width, 42)
        XCTAssertNotEqual(header.searchHost.frame.minX, originalSearch.minX)
        XCTAssertNotEqual(header.history.frame.minX, originalHistory.minX)
        XCTAssertFalse(header.searchBar.needsLayout, "Translation must not invalidate the stable search contents")
        let hosts: [NSView] = [header.searchHost, header.history]
        for (index, host) in hosts.enumerated() {
            let animation = try XCTUnwrap(host.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey)
                                         as? CAKeyframeAnimation)
            XCTAssertEqual(animation.keyPath, "position")
            XCTAssertTrue(animation.isAdditive)
            XCTAssertEqual(animation.duration, 0.42, accuracy: 0.001)
            let values = try XCTUnwrap(animation.values as? [NSValue])
            XCTAssertEqual(values.first!.pointValue.x, originalPositions[index].x - host.layer!.position.x, accuracy: 0.001)
            XCTAssertEqual(values.last!.pointValue, .zero)
            let model = host.frame
            header.needsLayout = true
            header.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.frame, model)
            let afterLayout = try XCTUnwrap(host.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey))
            XCTAssertEqual(afterLayout.beginTime, animation.beginTime, "An ordinary layout cannot restart translation")
        }
        XCTAssertNotNil(header.navigationHost.layer?.animation(forKey: NativeNavigationHeader.destinationsOpacityAnimationKey))
        XCTAssertFalse(header.isFrameClockRunning)
    }

    func testSidebarReversalAndResizeRetargetOnlyCompositorWithStableWidth() throws {
        let (window, header, coordinator) = makeHeader(solid: true)
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        let closedHistory = header.history.frame
        header.setPresentation(sidebarExpanded: true, searchExpanded: false, visible: true, reduceMotion: false)
        header.setPresentation(sidebarExpanded: false, searchExpanded: false, visible: true, reduceMotion: false)
        XCTAssertFalse(header.isFrameClockRunning)
        XCTAssertEqual(header.history.frame, closedHistory)
        // An immediate reversal may need no motion if the first animation has
        // not yet presented; it must still restore the exact endpoint.
        header.setPresentation(sidebarExpanded: true, searchExpanded: false, visible: true, reduceMotion: false)
        let beforeResize = try XCTUnwrap(header.history.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey))
        window.setContentSize(NSSize(width: 1_100, height: 72))
        header.layoutSubtreeIfNeeded()
        let afterResize = try XCTUnwrap(header.history.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey))
        XCTAssertGreaterThanOrEqual(afterResize.beginTime, beforeResize.beginTime)
        XCTAssertLessThanOrEqual(afterResize.duration, beforeResize.duration)
        XCTAssertEqual(header.history.frame.maxX, header.bounds.maxX - 18, accuracy: 0.001)
        XCTAssertEqual(header.searchHost.frame.width, 42)
        XCTAssertFalse(header.isFrameClockRunning)
        header.advanceAnimation(at: CACurrentMediaTime() + 1)
        XCTAssertNil(header.history.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey))
        XCTAssertTrue(header.navigationHost.isHidden)
        XCTAssertFalse(header.isAnimating)
    }

    func testHitTestingFollowsTranslatedPresentationInSuperviewCoordinates() throws {
        let (window, header, coordinator) = makeHeader(solid: true)
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        let initialSearch = header.searchHost.frame
        let initialHistory = header.history.frame
        header.setPresentation(sidebarExpanded: true, searchExpanded: false, visible: true, reduceMotion: false)
        // Without a visible presentation tree the same additive timeline is
        // evaluated analytically; this fixture never needs a display callback.
        let searchPoint = header.convert(NSPoint(x: initialSearch.midX, y: initialSearch.midY), to: header.superview)
        let historyPoint = header.convert(NSPoint(x: initialHistory.minX + 20, y: initialHistory.midY), to: header.superview)
        XCTAssertTrue(header.hitTest(searchPoint) === header.searchBar.iconButton)
        XCTAssertTrue(header.hitTest(historyPoint) === coordinator.history.bar?.back)
        let emptyPoint = header.convert(NSPoint(x: 2, y: 2), to: header.superview)
        XCTAssertNil(header.hitTest(emptyPoint))
    }

    func testMouseTrackingPreservesNativeTargetCoordinatesAndRetargetsCurrentState() throws {
        let (window, header, coordinator) = makeHeader(solid: true)
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        let button = try XCTUnwrap(coordinator.history.bar?.back)
        let recorder = NativeTrackingActionRecorder()
        button.isEnabled = true
        button.target = recorder
        button.action = #selector(NativeTrackingActionRecorder.activate(_:))
        let closedHistory = header.history.frame
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        recorder.onAction = {
            header.setPresentation(sidebarExpanded: false, searchExpanded: false, visible: true, reduceMotion: false)
        }
        header.setPresentation(sidebarExpanded: true, searchExpanded: false, visible: true, reduceMotion: false)
        let target = header.beginMouseTracking(at: header.convert(point, from: nil), buttonNumber: 0)
        XCTAssertTrue(target === button, "AppKit must receive the native target through its original event dispatch")
        XCTAssertTrue(button.bounds.contains(button.convert(point, from: nil)), "The actual model must be under the pointer")
        XCTAssertNil(header.history.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey))
        header.needsLayout = true
        header.layoutSubtreeIfNeeded()
        XCTAssertTrue(button.bounds.contains(button.convert(point, from: nil)), "Layout cannot move the tracking target")
        // performClick exercises the real AppKit action. Synthetic direct
        // mouseDown is unsupported by modern NSControl tracking on this SDK.
        button.performClick(nil)
        XCTAssertEqual(recorder.count, 1)
        header.endMouseTracking()
        XCTAssertEqual(header.history.frame, closedHistory)
        XCTAssertFalse(header.isFrameClockRunning)
        header.advanceAnimation(at: CACurrentMediaTime() + 1)
        XCTAssertFalse(header.isAnimating)
        XCTAssertEqual(header.sidebarProgress, 0)
    }

    func testExpandedFieldEditorRemainsInMovingGlassAndWidthClockIsIndependent() throws {
        let (window, header, coordinator) = makeHeader(solid: true)
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        header.setPresentation(sidebarExpanded: false, searchExpanded: true, visible: true, reduceMotion: false)
        XCTAssertTrue(header.isFrameClockRunning)
        header.advanceAnimation(at: CACurrentMediaTime() + 1)
        XCTAssertFalse(header.isFrameClockRunning)
        let editor = try XCTUnwrap(header.searchBar.textField.currentEditor() as? NSTextView)
        XCTAssertTrue(editor.isDescendant(of: header.searchHost), "The shared field editor must translate with the glass")
        editor.string = "Massive Attack"
        editor.setSelectedRange(NSRange(location: 2, length: 3))
        header.setPresentation(sidebarExpanded: true, searchExpanded: true, visible: true, reduceMotion: false)
        XCTAssertFalse(header.isFrameClockRunning)
        XCTAssertEqual(header.searchHost.frame.width, 298)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertTrue(editor.isDescendant(of: header.searchHost))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 3))
        let position = try XCTUnwrap(header.searchHost.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey))
        header.setPresentation(sidebarExpanded: true, searchExpanded: false, visible: true, reduceMotion: false)
        XCTAssertTrue(header.isFrameClockRunning)
        header.advanceAnimation(at: CACurrentMediaTime() + 0.02)
        XCTAssertGreaterThan(header.searchHost.frame.width, 42)
        XCTAssertLessThan(header.searchHost.frame.width, 298)
        XCTAssertEqual(header.searchHost.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey)?.beginTime,
                       position.beginTime, "Changing real search width must not restart additive translation")
        XCTAssertEqual(header.history.frame.width, 76)
    }

    func testReducedMotionSidebarSnapsAndFullscreenCleansCompositorAndClock() throws {
        let (window, header, coordinator) = makeHeader(solid: true)
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        header.setPresentation(sidebarExpanded: true, searchExpanded: false, visible: true, reduceMotion: true)
        XCTAssertFalse(header.isFrameClockRunning)
        XCTAssertNil(header.history.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey))
        let fade = try XCTUnwrap(header.navigationHost.layer?.animation(forKey: NativeNavigationHeader.destinationsOpacityAnimationKey))
        XCTAssertEqual(fade.duration, 0.15, accuracy: 0.001)
        header.setPresentation(sidebarExpanded: false, searchExpanded: true, visible: true, reduceMotion: false)
        XCTAssertTrue(header.isFrameClockRunning)
        header.setPresentation(sidebarExpanded: false, searchExpanded: true, visible: false, reduceMotion: false)
        XCTAssertFalse(header.isAnimating)
        XCTAssertFalse(header.isFrameClockRunning)
        XCTAssertTrue(header.searchHost.isHidden)
        XCTAssertTrue(header.history.isHidden)
        for host in [header.searchHost as NSView, header.history, header.navigationHost] {
            XCTAssertNil(host.layer?.animation(forKey: NativeNavigationHeader.sidebarPositionAnimationKey))
        }
        XCTAssertNil(header.navigationHost.layer?.animation(forKey: NativeNavigationHeader.destinationsOpacityAnimationKey))
        header.setPresentation(sidebarExpanded: false, searchExpanded: false, visible: false, reduceMotion: false)
        header.setPresentation(sidebarExpanded: false, searchExpanded: false, visible: true, reduceMotion: false)
        header.advanceAnimation(at: CACurrentMediaTime() + 1)
        XCTAssertFalse(header.navigationHost.isHidden, "Leaving fullscreen restores the selector with unchanged sidebar state")
        XCTAssertFalse(header.searchHost.isHidden)
        XCTAssertFalse(header.history.isHidden)
    }

    func testOutsideSearchClickKeepsInsideEditingAndOtherWindowsThenCollapsesOnce() throws {
        let (window, header, coordinator) = makeHeader(solid: true)
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        header.setPresentation(sidebarExpanded: false, searchExpanded: true, visible: true, reduceMotion: true)
        header.searchBar.setQuery("Björk")
        let editor = try XCTUnwrap(header.searchBar.textField.currentEditor())
        var requests: [Bool] = []
        header.searchBar.onToggleExpand = { requests.append($0) }
        let inside = header.searchHost.convert(NSPoint(x: 90, y: 21), to: nil)
        header.handleOutsideSearchClick(try mouseEvent(window: window, point: inside))
        XCTAssertTrue(header.searchBar.isExpanded)
        XCTAssertTrue(window.firstResponder === editor)

        let otherWindow = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        otherWindow.isReleasedWhenClosed = false
        defer { otherWindow.close() }
        header.handleOutsideSearchClick(try mouseEvent(window: otherWindow, point: .zero))
        XCTAssertTrue(header.searchBar.isExpanded)
        let outside = header.convert(NSPoint(x: 12, y: 68), to: nil)
        header.handleOutsideSearchClick(try mouseEvent(window: window, point: outside, type: .leftMouseUp))
        XCTAssertTrue(header.searchBar.isExpanded)
        header.handleOutsideSearchClick(try mouseEvent(window: window, point: outside))
        header.handleOutsideSearchClick(try mouseEvent(window: window, point: outside))
        XCTAssertFalse(header.searchBar.isExpanded)
        XCTAssertEqual(requests, [false])
        XCTAssertEqual(header.searchBar.textField.stringValue, "Björk")
        XCTAssertFalse(window.firstResponder === editor)
    }

    func testOutsideClickUsesMovingSearchPresentationAndIgnoresDetachedHeader() throws {
        let (window, header, coordinator) = makeHeader(solid: true)
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        window.setContentSize(NSSize(width: 1_400, height: ShellLayout.toolbarHostHeight))
        header.layoutSubtreeIfNeeded()
        header.setPresentation(sidebarExpanded: false, searchExpanded: true, visible: true, reduceMotion: true)
        let visibleCenter = header.searchHost.convert(NSPoint(x: 149, y: 21), to: nil)
        header.setPresentation(sidebarExpanded: true, searchExpanded: true, visible: true, reduceMotion: false)
        XCTAssertFalse(header.searchHost.frame.contains(header.convert(visibleCenter, from: nil)),
                       "The endpoint must differ from the visible surface in this scenario")
        header.handleOutsideSearchClick(try mouseEvent(window: window, point: visibleCenter))
        XCTAssertTrue(header.searchBar.isExpanded, "A click on the moving glass stays inside")
        let event = try mouseEvent(window: window, point: .zero)
        window.contentView = NSView(frame: header.frame)
        header.handleOutsideSearchClick(event)
        XCTAssertTrue(header.searchBar.isExpanded)
    }

    private func mouseEvent(window: NSWindow, point: NSPoint, type: NSEvent.EventType = .leftMouseDown) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil,
                                        eventNumber: 1, clickCount: 1, pressure: 1))
    }

    private func makeHeader(solid: Bool) -> (NSWindow, NativeNavigationHeader, WindowNavigationToolbarView.Coordinator) {
        let router = NavigationRouter()
        let spec = WindowNavigationToolbarView(
            navigation: TopNavigationView(selection: .home, isPresented: true, reduceMotion: false,
                                          onHome: {}, onLibrary: {}, onSearch: {}),
            history: HistoryToolbarView(router: router, isDisabled: false), showsHistory: true,
            viewportWidth: 900)
        let coordinator = spec.makeCoordinator()
        let header = spec.makeNativeHeader(coordinator: coordinator, reduceTransparency: solid)
        let window = NSWindow(contentRect: NSRect(x: -2_000, y: -2_000, width: 900, height: 72),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = header
        header.layoutSubtreeIfNeeded()
        return (window, header, coordinator)
    }
}

@MainActor
private final class NativeTrackingActionRecorder: NSObject {
    var count = 0
    var onAction: (() -> Void)?
    @objc func activate(_ sender: NSButton) {
        count += 1
        onAction?()
    }
}
