import AppKit
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class WindowGestureShellRoutingTests: XCTestCase {
    func testRealPlayerAndNativeVerticalListDoNotExcludeCentralViewport() throws {
        let player = PlayerViewModel()
        let presentation = WindowGesturePresentation()
        func shell(sidebar: Bool) -> some View {
            ZStack {
                HStack(spacing: 0) {
                    if sidebar { Color.clear.frame(width: ShellLayout.sidebarReserveWidth(expanded: true)) }
                    NativeTrackTableView(tracks: [], currentTrackVideoId: nil, isPlaying: false,
                        onPlayTrack: { _ in })
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .windowGestureRegion(.content)
                .modifier(GesturePageVisibility(presentation: presentation, fullscreenPresented: false))

                FullscreenCanvas(viewModel: player, isSidebarExpanded: .constant(sidebar), router: nil)
                    .windowGestureRegion(.content, active: false)
                    .modifier(FullscreenGestureMotion(presentation: presentation))

                if sidebar {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: ShellLayout.sidebarWidth)
                            .windowGestureRegion(.excluded)
                            .padding(ShellLayout.sidebarInset)
                        Spacer(minLength: 0)
                    }
                }
                PlayerBarView(viewModel: player)
                    .windowGestureRegion(.excluded)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.leading, ShellLayout.sidebarReserveWidth(expanded: sidebar))
                NavigationGestureIndicatorView(presentation: presentation)
                    .padding(.leading, ShellLayout.sidebarReserveWidth(expanded: sidebar))
            }
        }
        let host = NSHostingView(rootView: shell(sidebar: true))
        host.sizingOptions = []
        let router = NavigationRouter()
        router.navigate(to: .explore(.discover))
        router.navigate(to: .library)
        let coordinator = WindowNavigationCoordinator(performHaptic: {})
        coordinator.setup(router: router, presentation: presentation, isFullscreenPresented: false,
            canHandleGestures: true, reduceMotion: true, onDismissFullscreen: {})
        for (width, sidebar): (CGFloat, Bool) in [(1100, true), (960, false), (1512, true)] {
            host.rootView = shell(sidebar: sidebar)
            host.frame = NSRect(x: 0, y: 0, width: width, height: 700)
            host.layoutSubtreeIfNeeded()
            for point in [NSPoint(x: 400, y: 200), NSPoint(x: 700, y: 400),
                          NSPoint(x: width - 40, y: 250)] {
                let route = WindowGestureRegions.routing(at: point, in: host)
                XCTAssertTrue(route.allowsHistory, "\(width)/\(sidebar) \(point): \(route)")
            }
            let playerMarker = try XCTUnwrap(descendants(host).compactMap { $0 as? WindowGestureRegionView }
                .first { $0.region == .excluded && $0.bounds.height < 100 })
            let playerFrame = playerMarker.convert(playerMarker.bounds, to: host)
            XCTAssertEqual(playerFrame.height, 74, accuracy: 0.5)
            XCTAssertTrue(WindowGestureRegions.routing(at: NSPoint(x: playerFrame.midX, y: playerFrame.midY),
                in: host).isExcluded)
            XCTAssertTrue(WindowGestureRegions.routing(at: NSPoint(x: playerFrame.midX, y: playerFrame.midY),
                in: host).allowsHistory)
            // Exercise actual routing + adapter + router across the entire shell,
            // including sidebar, player, table rows and space around the content.
            for x in stride(from: CGFloat(12), to: width, by: 80) {
                for y in stride(from: CGFloat(12), to: 700, by: 80) {
                    assertHistoryRoundTrip(at: NSPoint(x: x, y: y), in: host,
                        coordinator: coordinator, router: router, presentation: presentation)
                }
            }
            assertHistoryRoundTrip(at: NSPoint(x: playerFrame.midX, y: playerFrame.midY), in: host,
                coordinator: coordinator, router: router, presentation: presentation)
        }
        XCTAssertNil(host.window)
    }

    func testHistoryNavigatesOverRealSwiftUIHorizontalAndVerticalScrollViews() {
        func page() -> some View {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { Button("Todos") {}; Button("Álbumes") {} }
                }
                .frame(height: 50)
                .windowGestureRegion(.horizontalContent)
                ScrollView(.vertical) {
                    VStack { ForEach(0..<30) { Text("Pista \($0)").frame(height: 50) } }
                        .frame(maxWidth: .infinity)
                }
            }
            .windowGestureRegion(.content)
        }
        let host = NSHostingView(rootView: page())
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        host.layoutSubtreeIfNeeded()
        let horizontal = WindowGestureRegions.routing(at: NSPoint(x: 500, y: 20), in: host)
        XCTAssertTrue(horizontal.ownsHorizontal)
        XCTAssertTrue(horizontal.allowsHistory)
        let vertical = WindowGestureRegions.routing(at: NSPoint(x: 500, y: 200), in: host)
        XCTAssertTrue(vertical.allowsHistory, "\(vertical)")
        XCTAssertFalse(vertical.ownsHorizontal)
        let router = NavigationRouter()
        router.navigate(to: .explore(.discover))
        router.navigate(to: .library)
        let presentation = WindowGesturePresentation()
        let coordinator = WindowNavigationCoordinator(performHaptic: {})
        coordinator.setup(router: router, presentation: presentation, isFullscreenPresented: false,
            canHandleGestures: true, reduceMotion: true, onDismissFullscreen: {})
        for point in [NSPoint(x: 500, y: 20), NSPoint(x: 500, y: 200)] {
            assertHistoryRoundTrip(at: point, in: host, coordinator: coordinator,
                router: router, presentation: presentation)
            let verticalInput = coordinator.handleScrollInput(.init(deltaY: 120, phase: .began), enabled: true) {
                coordinator.scrollContext(at: point, in: host, enabled: true)
            }
            XCTAssertEqual(verticalInput.disposition, .passThrough)
            XCTAssertNil(coordinator.handleScrollInput(.init(phase: .ended), enabled: true) {
                coordinator.scrollContext(at: point, in: host, enabled: true)
            }.commit)
            XCTAssertEqual(router.currentPage, .library)
        }
        XCTAssertNil(host.window)
    }

    private func assertHistoryRoundTrip(at point: NSPoint, in host: NSView,
                                        coordinator: WindowNavigationCoordinator, router: NavigationRouter,
                                        presentation: WindowGesturePresentation,
                                        file: StaticString = #filePath, line: UInt = #line) {
        for direction: CGFloat in [1, -1] {
            let context = coordinator.scrollContext(at: point, in: host, enabled: true)
            XCTAssertTrue(context.allowsHorizontalNavigation, "\(point)", file: file, line: line)
            coordinator.handleScrollInput(.init(phase: .mayBegin), enabled: true) { context }
            let pull = coordinator.handleScrollInput(.init(deltaX: direction * 90, phase: .changed), enabled: true) { context }
            XCTAssertEqual(pull.disposition, .consume, "\(point)", file: file, line: line)
            XCTAssertTrue(presentation.horizontalVisible, "\(point)", file: file, line: line)
            let release = coordinator.handleScrollInput(.init(phase: .ended), enabled: true) { context }
            XCTAssertEqual(release.commit, direction > 0 ? .back : .forward, "\(point)", file: file, line: line)
            XCTAssertEqual(router.currentPage, direction > 0 ? .explore(.discover) : .library,
                "\(point)", file: file, line: line)
            let momentum = coordinator.handleScrollInput(.init(deltaX: 250, momentumPhase: .changed), enabled: true) { context }
            XCTAssertEqual(momentum.disposition, .consume, file: file, line: line)
            XCTAssertNil(momentum.commit, file: file, line: line)
            coordinator.handleScrollInput(.init(momentumPhase: .ended), enabled: true) { context }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    func testExternalRouteChangeUpdatesActualBridgeAndCancelsPull() throws {
        for fullscreen in [false, true] {
            let router = NavigationRouter()
            let presentation = WindowGesturePresentation()
            let host = NSHostingView(rootView: RoutedGestureBridgeShell(router: router, presentation: presentation,
                                                                      fullscreen: fullscreen))
            host.sizingOptions = []
            host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
            host.layoutSubtreeIfNeeded()
            let bridge = try XCTUnwrap(descendants(host).compactMap { $0 as? WindowNavigationHostingView }.first)
            let coordinator = try XCTUnwrap(bridge.coordinator)
            // Below the activation threshold: do not perform a device haptic in this UI test.
            coordinator.handleScrollInput(.init(deltaX: fullscreen ? 0 : 30,
                                               deltaY: fullscreen ? 30 : 0, phase: .began), enabled: true) {
                .init(mode: fullscreen ? .fullscreen : .history)
            }
            if fullscreen { XCTAssertEqual(presentation.fullscreenStage, .pulling) }
            else { XCTAssertTrue(presentation.horizontalVisible) }
            router.navigate(to: .library)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(presentation.fullscreenStage, .idle)
            XCTAssertEqual(presentation.fullscreenOffset, 0)
            XCTAssertFalse(presentation.revealUnderlying)
            XCTAssertNil(presentation.horizontal)
            XCTAssertNil(host.window)
        }
    }
}

private struct RoutedGestureBridgeShell: View {
    let router: NavigationRouter
    let presentation: WindowGesturePresentation
    let fullscreen: Bool

    var body: some View {
        GestureRouteContent(router: router)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WindowNavigationGestureBridge(router: router, presentation: presentation,
                isFullscreenPresented: fullscreen, canHandleGestures: true, reduceMotion: true,
                sessionRevision: 0, onDismissFullscreen: {}))
    }
}

private struct GestureRouteContent: View {
    let router: NavigationRouter
    var body: some View { Text(router.currentPage.gestureTitle) }
}
