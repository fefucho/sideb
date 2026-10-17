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
        for index in [0, 2, 1] {
            control.selectedSegment = index
            XCTAssertTrue(control.sendAction(action, to: control.target))
        }
        XCTAssertEqual(events, ["home", "library", "explore"])
        coordinator.setPresentation(progress: 0, isPresented: false, reduceMotion: true)
        control.selectedSegment = 0
        control.sendAction(action, to: control.target)
        XCTAssertEqual(events.count, 3)
    }

    func testNativeDestinationsUseThreeEqualSlotsInsideFixedSurface() throws {
        let view = TopNavigationView(selection: .library, isPresented: true, reduceMotion: true,
                                     onHome: {}, onLibrary: {}, onSearch: {})
        let coordinator = view.makeCoordinator()
        let host = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: false)
        let bar = try XCTUnwrap(coordinator.bar)
        XCTAssertEqual(bar.control.selectedSegment, 2)
        XCTAssertEqual(bar.fittingSize.height, bar.control.frame.height + 2 * NativeNavigationBar.inset)
        XCTAssertEqual(bar.control.segmentCount, 3)
        XCTAssertEqual(bar.fittingSize, NSSize(width: 246, height: 42))
        XCTAssertEqual(bar.control.frame.size, NSSize(width: 240, height: 36))
        XCTAssertEqual(bar.control.segmentDistribution, .fillEqually)
        for index in 0..<3 {
            XCTAssertEqual(bar.control.width(forSegment: index), 0,
                           "The fixed control frame defines the slots; explicit widths add native padding")
        }
        XCTAssertEqual(host.contentView.fittingSize, bar.fittingSize)
    }

    func testNativeSelectionLensKeepsSymmetricInsetsAtBothEnds() async throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Native glass selection layers require macOS 26")
        }
        for reduceTransparency in [false, true] {
            let view = TopNavigationView(selection: .home, isPresented: true, reduceMotion: true,
                                         onHome: {}, onLibrary: {}, onSearch: {})
            let coordinator = view.makeCoordinator()
            let host = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: reduceTransparency)
            host.usesWindowAlignment = false
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView?.addSubview(host)
            host.frame = NSRect(origin: .zero, size: host.contentView.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bar = try XCTUnwrap(coordinator.bar)
            var endInsets: [CGFloat] = []
            let tolerance = 1 / window.backingScaleFactor
            for index in [0, 1, 2] {
                bar.select(index)
                bar.control.needsLayout = true
                bar.control.layoutSubtreeIfNeeded()
                CATransaction.flush()
                try await Task.sleep(for: .milliseconds(30))
                bar.needsLayout = true
                bar.layoutSubtreeIfNeeded()
                let hosting = try XCTUnwrap(bar.control.subviews.first {
                    NSStringFromClass(type(of: $0)).contains("NSCoreHostingView")
                })
                let layers = try XCTUnwrap(hosting.layer?.sublayers)
                let track = try XCTUnwrap(layers.first)
                XCTAssertTrue(hosting.bounds.contains(track.frame), "Native track must fit the 240pt control")
                XCTAssertEqual(track.opacity, 0, "KVO must continue suppressing only the native track")
                // Inspect the system lens without fixing its dimensions to one SDK's metrics.
                let lens = try XCTUnwrap(layers.first { layer in
                    layer.frame.width > 0 && layer.frame.width < hosting.bounds.width &&
                    layer.frame.height > 0 && layer.frame.height < hosting.bounds.height
                })
                let lensRect = hosting.convert(lens.frame, to: bar)
                XCTAssertTrue(bar.bounds.contains(lensRect))
                XCTAssertGreaterThan(lensRect.minX - bar.bounds.minX, 0)
                XCTAssertGreaterThan(bar.bounds.maxX - lensRect.maxX, 0)
                XCTAssertGreaterThan(lensRect.minY - bar.bounds.minY, 0)
                XCTAssertEqual(lensRect.minY - bar.bounds.minY, bar.bounds.maxY - lensRect.maxY,
                               accuracy: tolerance)
                XCTAssertEqual(lens.opacity, 1)
                if index == 0 { endInsets.append(lensRect.minX - bar.bounds.minX) }
                if index == 2 { endInsets.append(bar.bounds.maxX - lensRect.maxX) }
                let slotCenter = NSPoint(x: bar.control.frame.minX + (CGFloat(index) + 0.5) * 80,
                                         y: bar.bounds.midY)
                XCTAssertTrue(bar.hitTest(slotCenter) === bar.control)
            }
            XCTAssertEqual(endInsets[0], endInsets[1], accuracy: tolerance)
            withExtendedLifetime(window) {}
        }
    }

    func testSearchCompatibilityCallbackDoesNotCreateANativeDestination() throws {
        var searches = 0
        let view = TopNavigationView(selection: .home, isPresented: true, reduceMotion: false,
            onHome: {}, onLibrary: {}, onSearch: { searches += 1 })
        let coordinator = view.makeCoordinator()
        let host = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: false)
        defer { withExtendedLifetime(host) {} }
        XCTAssertEqual(coordinator.bar?.control.segmentCount, 3)
        XCTAssertEqual(coordinator.bar?.control.tag(forSegment: 2), 2)
        XCTAssertEqual(searches, 0)
    }

    func testHostingSublayerObservationHidesReinsertedTrackAndRebindsReplacementLayer() async throws {
        let view = TopNavigationView(selection: .home, isPresented: true, reduceMotion: false,
                                     onHome: {}, onLibrary: {}, onSearch: {})
        let coordinator = view.makeCoordinator()
        let host = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: false)
        defer { withExtendedLifetime(host) {} }
        let bar = try XCTUnwrap(coordinator.bar)
        let firstHostingLayer = CALayer()
        let firstTrack = CALayer()
        firstTrack.opacity = 1
        firstHostingLayer.addSublayer(firstTrack)
        bar.observeSublayers(of: firstHostingLayer)
        bar.hideMiddleTrack(in: firstHostingLayer)
        XCTAssertEqual(firstTrack.opacity, 0)

        let reinsertedTrack = CALayer()
        reinsertedTrack.opacity = 1
        firstHostingLayer.sublayers = [reinsertedTrack]
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(reinsertedTrack.opacity, 0)

        let replacementHostingLayer = CALayer()
        let replacementTrack = CALayer()
        replacementTrack.opacity = 1
        replacementHostingLayer.addSublayer(replacementTrack)
        bar.observeSublayers(of: replacementHostingLayer)
        bar.hideMiddleTrack(in: replacementHostingLayer)
        XCTAssertEqual(replacementTrack.opacity, 0)
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

    func testReinsertingTrackRestoresSelectionLayerThatTemporarilyBecameFirst() throws {
        let view = TopNavigationView(selection: .home, isPresented: true, reduceMotion: false,
                                     onHome: {}, onLibrary: {}, onSearch: {})
        let coordinator = view.makeCoordinator()
        let host = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: false)
        defer { withExtendedLifetime(host) {} }
        let bar = try XCTUnwrap(coordinator.bar)
        let hostingLayer = CALayer()
        let track = CALayer()
        let selection = CALayer()
        hostingLayer.sublayers = [track, selection]
        bar.observeSublayers(of: hostingLayer)
        XCTAssertEqual(track.opacity, 0)
        XCTAssertEqual(selection.opacity, 1)

        track.removeFromSuperlayer()
        let replacementTrack = CALayer()
        hostingLayer.insertSublayer(replacementTrack, at: 0)
        XCTAssertEqual(replacementTrack.opacity, 0)
        XCTAssertEqual(selection.opacity, 1, "Only the current first layer should retain our opacity override")
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}
