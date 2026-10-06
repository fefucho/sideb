import AppKit
import XCTest
@testable import SideB

@MainActor
final class TopNavigationViewTests: XCTestCase {
    func testSharedProgressSlidesWholeSurfaceAndCanReverseWithoutAStaleCompletion() throws {
        let view = TopNavigationView(selection: .home, isPresented: false, reduceMotion: false,
                                     onHome: {}, onLibrary: {}, onSearch: {})
        let coordinator = view.makeCoordinator()
        let host = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: false)
        let bar = try XCTUnwrap(coordinator.bar)
        let glass = try XCTUnwrap(host.contentView.subviews.first)
        XCTAssertTrue(host.isHidden)
        coordinator.setPresentation(progress: 0.5, isPresented: true, reduceMotion: false)
        XCTAssertFalse(host.isHidden)
        XCTAssertFalse(bar.control.isHidden)
        XCTAssertEqual(host.alphaValue, 1)
        XCTAssertEqual(host.contentView.alphaValue, 1)
        XCTAssertEqual(bar.control.alphaValue, 1)
        XCTAssertEqual(glass.alphaValue, 1)
        let exitDistance = ShellLayout.navigationRowCenter + host.contentView.fittingSize.height / 2 + 8
        XCTAssertEqual(host.presentationOffset, -exitDistance / 2)
        XCTAssertFalse(bar.control.isEnabled)
        coordinator.setPresentation(progress: 0.25, isPresented: false, reduceMotion: false)
        XCTAssertEqual(glass.alphaValue, 1)
        XCTAssertEqual(host.presentationOffset, -exitDistance * 0.75)
        coordinator.setPresentation(progress: 1, isPresented: true, reduceMotion: false)
        XCTAssertFalse(host.isHidden)
        XCTAssertEqual(glass.alphaValue, 1)
        XCTAssertEqual(host.presentationOffset, 0)
        XCTAssertTrue(bar.control.isEnabled(forSegment: 0))
        XCTAssertTrue(bar.control.isEnabled(forSegment: 1))
        coordinator.setPresentation(progress: 0.5, isPresented: false, reduceMotion: true)
        XCTAssertEqual(host.presentationOffset, 0)
        XCTAssertEqual(glass.alphaValue, 0.5)
        coordinator.setPresentation(progress: 0, isPresented: false, reduceMotion: true)
        XCTAssertTrue(host.isHidden)
        XCTAssertTrue(glass.isHidden)
        XCTAssertEqual(host.presentationOffset, 0)
    }

    func testNativeActionsDispatchAndHiddenControlCannotNavigate() throws {
        var events: [String] = []
        let view = TopNavigationView(selection: .home, isPresented: true, reduceMotion: true,
            onHome: { events.append("home") }, onExplore: { events.append("explore") }, onLibrary: { events.append("library") }, onSearch: { events.append("search") })
        let coordinator = view.makeCoordinator()
        let host = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: false)
        defer { withExtendedLifetime(host) {} }
        let control = try XCTUnwrap(coordinator.bar?.control)
        XCTAssertTrue(control.target === coordinator)
        let action = try XCTUnwrap(control.action)
        XCTAssertEqual(action, #selector(TopNavigationView.Coordinator.select(_:)))
        for index in [0, 2, 3, 1] {
            control.selectedSegment = index
            XCTAssertTrue(control.sendAction(action, to: control.target))
        }
        XCTAssertEqual(events, ["home", "library", "search", "explore"])
        coordinator.setPresentation(progress: 0, isPresented: false, reduceMotion: true)
        control.selectedSegment = 0
        control.sendAction(action, to: control.target)
        XCTAssertEqual(events.count, 4)
    }

    func testSystemSegmentedCellKeepsIntrinsicSizeAndNativeTracking() throws {
        let view = TopNavigationView(selection: .library, isPresented: true, reduceMotion: true,
                                     onHome: {}, onLibrary: {}, onSearch: {})
        let coordinator = view.makeCoordinator()
        let host = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: false)
        let bar = try XCTUnwrap(coordinator.bar)
        XCTAssertEqual(bar.control.selectedSegment, 2)
        XCTAssertEqual(bar.fittingSize.height, bar.control.frame.height + 2 * NativeNavigationBar.inset)
        XCTAssertGreaterThanOrEqual(bar.fittingSize.width, 250)
        XCTAssertEqual(host.contentView.fittingSize, bar.fittingSize)
    }

    func testNativeControlRemainsCenteredAfterGlassResizesItsContentPlane() throws {
        for reduceTransparency in [false, true] {
            let view = TopNavigationView(selection: .home, isPresented: true, reduceMotion: false,
                                         onHome: {}, onLibrary: {}, onSearch: {})
            let coordinator = view.makeCoordinator()
            let host = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: reduceTransparency)
            host.usesWindowAlignment = false
            host.frame = NSRect(origin: .zero, size: host.contentView.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bar = try XCTUnwrap(coordinator.bar)
            let nativeSize = bar.control.frame.size
            for extraHeight: CGFloat in [0, 10, 0] {
                bar.frame.size.height = bar.fittingSize.height + extraHeight
                bar.needsLayout = true
                bar.layoutSubtreeIfNeeded()
                XCTAssertEqual(bar.control.frame.size, nativeSize)
                XCTAssertEqual(bar.control.frame.midY, bar.bounds.midY, accuracy: 0.001)
                XCTAssertEqual(bar.control.frame.midX, bar.bounds.midX, accuracy: 0.001)
                XCTAssertEqual(bar.control.frame.minY, bar.bounds.maxY - bar.control.frame.maxY, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(bar.control.frame.minY, NativeNavigationBar.inset)
                XCTAssertTrue(bar.bounds.contains(bar.control.frame))
                XCTAssertTrue(bar.hitTest(bar.control.frame.center) === bar.control)
            }
        }
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}
