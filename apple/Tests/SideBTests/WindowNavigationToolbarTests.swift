import AppKit
import XCTest
@testable import SideB

@MainActor
final class WindowNavigationToolbarTests: XCTestCase {
    func testSettingsActionUsesLatestCallbackAndOnlyRunsOnInteractiveHome() throws {
        let router = NavigationRouter()
        var events: [String] = []
        var view = HistoryToolbarView(router: router, isDisabled: false,
                                      onHomeSettings: { events.append("initial") })
        let coordinator = view.makeCoordinator()
        let container = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: false)
        let bar = try XCTUnwrap(coordinator.bar)
        let action = try XCTUnwrap(bar.settings.action)

        XCTAssertFalse(bar.settings.isHidden)
        XCTAssertTrue(bar.settings.isEnabled)
        XCTAssertEqual(bar.settings.accessibilityLabel(), L10n.text("navigation.home_settings"))
        XCTAssertEqual(bar.settings.accessibilityValue() as? String, "Cerrada")
        bar.settings.sendAction(action, to: bar.settings.target)
        XCTAssertEqual(events, ["initial"])

        view = HistoryToolbarView(router: router, isDisabled: false,
                                  isHomeSettingsPresented: true,
                                  onHomeSettings: { events.append("updated") })
        view.updateNativeContainer(container, coordinator: coordinator, reduceTransparency: true)
        XCTAssertTrue(coordinator.bar === bar)
        XCTAssertEqual(bar.settings.state, .on)
        XCTAssertEqual(bar.settings.accessibilityValue() as? String, "Abierta")
        bar.settings.sendAction(action, to: bar.settings.target)
        XCTAssertEqual(events, ["initial", "updated"])

        router.navigate(to: .library)
        view.updateNativeContainer(container, coordinator: coordinator, reduceTransparency: true)
        XCTAssertTrue(bar.settings.isHidden)
        XCTAssertTrue(bar.refresh.isHidden)
        XCTAssertFalse(bar.settings.isEnabled)
        // A stale delivered action must also be rejected by the coordinator.
        bar.settings.isEnabled = true
        bar.settings.sendAction(action, to: bar.settings.target)
        XCTAssertEqual(events.count, 2)

        router.goBack()
        view = HistoryToolbarView(router: router, isDisabled: true,
                                  onHomeSettings: { events.append("disabled") })
        view.updateNativeContainer(container, coordinator: coordinator, reduceTransparency: false)
        XCTAssertTrue(bar.settings.isHidden)
        XCTAssertTrue(bar.refresh.isHidden)
        XCTAssertFalse(bar.back.isEnabled)
        XCTAssertFalse(bar.forward.isEnabled)
        bar.settings.isEnabled = true
        bar.settings.sendAction(action, to: bar.settings.target)
        XCTAssertEqual(events.count, 2)
    }

    func testGearFitsAfterForwardWithoutOverlapAtMinimumToolbarWidth() throws {
        for reduceTransparency in [false, true] {
            let router = NavigationRouter()
            let view = WindowNavigationToolbarView(
                navigation: TopNavigationView(selection: .home, isPresented: true, reduceMotion: true,
                                              onHome: {}, onLibrary: {}, onSearch: {}),
                history: HistoryToolbarView(router: router, isDisabled: false), showsHistory: true)
            let coordinator = view.makeCoordinator()
            let header = view.makeNativeHeader(coordinator: coordinator, reduceTransparency: reduceTransparency)
            let bar = try XCTUnwrap(coordinator.history.bar)

            for width in [ShellLayout.navigationMinimumWidth, 620, 900] {
                for destination in [PageDestination.home, .library, .home] {
                    router.navigate(to: destination)
                    view.history.updateNativeContainer(header.history, coordinator: coordinator.history,
                                                       reduceTransparency: reduceTransparency)
                    header.frame = NSRect(x: 0, y: 0, width: width, height: ShellLayout.toolbarHostHeight)
                    header.needsLayout = true
                    header.layoutSubtreeIfNeeded()

                    XCTAssertTrue(header.bounds.contains(header.navigationHost.frame))
                    XCTAssertTrue(header.bounds.contains(header.history.frame))
                    XCTAssertGreaterThanOrEqual(header.history.frame.minX - header.navigationHost.frame.maxX, 16)
                    XCTAssertEqual(header.history.frame.maxX, header.bounds.maxX, accuracy: 0.001)
                    XCTAssertNil(header.hitTest(NSPoint(x: 2, y: 68)), "Unused toolbar space must allow window dragging")
                    if destination == .home {
                        XCTAssertGreaterThan(bar.settings.frame.minX, bar.forward.frame.maxX)
                        XCTAssertEqual(bar.settings.frame.size, bar.refresh.frame.size)
                        XCTAssertTrue(bar.bounds.contains(bar.settings.frame))
                        XCTAssertTrue(bar.hitTest(NSPoint(x: bar.settings.frame.midX, y: bar.settings.frame.midY)) === bar.settings)
                    } else {
                        XCTAssertTrue(bar.settings.isHidden)
                        XCTAssertEqual(bar.fittingSize.width, 62)
                    }
                }
            }
        }
    }

    func testSettingsPanelCenterFitsWideAndSidebarShiftedToolbarBounds() {
        let menuSize = CGSize(width: 236, height: 34)
        let historySize = CGSize(width: 112, height: 34)
        let windowWidth: CGFloat = 1_200
        let panelCenter = windowWidth - ShellLayout.sidebarInset - ShellLayout.homeSettingsWidth / 2
        // The second viewport models a toolbar shifted by the sidebar's 280-point reservation.
        let viewports = [
            CGRect(x: 0, y: 0, width: windowWidth, height: ShellLayout.toolbarHostHeight),
            CGRect(x: 280, y: 0, width: windowWidth - 280, height: ShellLayout.toolbarHostHeight)
        ]

        for bounds in viewports {
            let frames = ShellLayout.navigationFrames(bounds: bounds, menuSize: menuSize,
                                                       historySize: historySize,
                                                       requestedCenter: CGPoint(x: bounds.midX, y: 28),
                                                       historyCenterX: panelCenter)
            XCTAssertEqual(frames.history.midX, panelCenter, accuracy: 0.001)
            XCTAssertTrue(bounds.contains(frames.menu))
            XCTAssertTrue(bounds.contains(frames.history))
            XCTAssertGreaterThanOrEqual(frames.history.minX - frames.menu.maxX, 16)
        }
    }

    func testRequestedHistoryCentersStayInBoundsAndLeaveSelectorClearanceAtMinimumWidth() {
        let bounds = CGRect(x: 0, y: 0, width: ShellLayout.navigationMinimumWidth,
                            height: ShellLayout.toolbarHostHeight)
        let menuSize = CGSize(width: 236, height: 34)
        let historySize = CGSize(width: 112, height: 34)
        for requestedCenterX: CGFloat in [-100, 170, 1_000] {
            let frames = ShellLayout.navigationFrames(bounds: bounds, menuSize: menuSize,
                                                       historySize: historySize,
                                                       requestedCenter: CGPoint(x: bounds.midX, y: 28),
                                                       historyCenterX: requestedCenterX)
            XCTAssertTrue(bounds.contains(frames.menu))
            XCTAssertTrue(bounds.contains(frames.history))
            XCTAssertGreaterThanOrEqual(frames.history.minX - frames.menu.maxX, 16)
        }
    }

    func testRealNativeGroupsStayAlignedInsideOneHostThroughResizeAndHistoryChanges() throws {
        let router = NavigationRouter()
        let view = WindowNavigationToolbarView(
            navigation: TopNavigationView(selection: .home, isPresented: true, reduceMotion: false,
                                          onHome: {}, onLibrary: {}, onSearch: {}),
            history: HistoryToolbarView(router: router, isDisabled: false), showsHistory: true)
        let coordinator = view.makeCoordinator()
        let header = view.makeNativeHeader(coordinator: coordinator, reduceTransparency: false)
        header.frame = NSRect(x: 0, y: 0, width: 620, height: 72)
        header.layoutSubtreeIfNeeded()

        let initialMenuFrame = header.navigationHost.frame
        let initialHistoryFrame = header.history.frame
        XCTAssertEqual(initialHistoryFrame.maxX, header.bounds.maxX, accuracy: 0.5)
        XCTAssertLessThanOrEqual(initialMenuFrame.maxX + 16, initialHistoryFrame.minX)

        header.frame = NSRect(x: 0, y: 0, width: 900, height: 72)
        header.layoutSubtreeIfNeeded()
        XCTAssertEqual(header.history.frame.maxX, header.bounds.maxX, accuracy: 0.5)
        XCTAssertNotEqual(header.navigationHost.frame.origin.x, initialMenuFrame.origin.x)

        header.history.isHidden = true
        coordinator.history.surface?.setEffectHidden(true)
        header.layoutSubtreeIfNeeded()
        XCTAssertTrue(header.history.isHidden)
        XCTAssertFalse(header.navigationHost.isHidden)
    }

    func testNativeHistoryActionsKeepRefreshBackForwardAndDisabledContract() throws {
        let router = NavigationRouter()
        let initialRefresh = router.refreshTrigger
        let view = HistoryToolbarView(router: router, isDisabled: false)
        let coordinator = view.makeCoordinator()
        let container = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: false)
        let bar = try XCTUnwrap(coordinator.bar)

        XCTAssertFalse(bar.back.isEnabled)
        XCTAssertFalse(bar.forward.isEnabled)
        XCTAssertTrue(bar.refresh.isEnabled)

        bar.refresh.sendAction(try XCTUnwrap(bar.refresh.action), to: bar.refresh.target)
        XCTAssertEqual(router.refreshTrigger, initialRefresh + 1)

        router.navigate(to: .library)
        view.updateNativeContainer(container, coordinator: coordinator, reduceTransparency: false)
        XCTAssertTrue(bar.back.isEnabled)
        XCTAssertFalse(bar.forward.isEnabled)
        XCTAssertFalse(bar.refresh.isEnabled)

        bar.back.sendAction(try XCTUnwrap(bar.back.action), to: bar.back.target)
        XCTAssertEqual(router.currentPage, .home)
        view.updateNativeContainer(container, coordinator: coordinator, reduceTransparency: false)
        XCTAssertFalse(bar.back.isEnabled)
        XCTAssertTrue(bar.forward.isEnabled)

        bar.forward.sendAction(try XCTUnwrap(bar.forward.action), to: bar.forward.target)
        XCTAssertEqual(router.currentPage, .library)
        view.updateNativeContainer(container, coordinator: coordinator, reduceTransparency: false)

        router.navigate(to: .playlist(browseId: "123"))
        view.updateNativeContainer(container, coordinator: coordinator, reduceTransparency: false)
        XCTAssertTrue(bar.back.isEnabled)
        bar.back.sendAction(try XCTUnwrap(bar.back.action), to: bar.back.target)
        XCTAssertEqual(router.currentPage, .library)
    }

    func testTopNavigationPresentationInterpolatesOffsetImmediatelyInLayout() throws {
        let router = NavigationRouter()
        let view = WindowNavigationToolbarView(
            navigation: TopNavigationView(selection: .home, isPresented: true, reduceMotion: false,
                                          revealProgress: 0.5, onHome: {}, onLibrary: {}, onSearch: {}),
            history: HistoryToolbarView(router: router, isDisabled: false), showsHistory: true)
        let coordinator = view.makeCoordinator()
        let header = view.makeNativeHeader(coordinator: coordinator, reduceTransparency: true)
        header.frame = NSRect(x: 0, y: 0, width: 620, height: 72)
        view.navigation.updateNativeContainer(header.navigationHost, coordinator: coordinator.navigation, reduceTransparency: true)
        header.needsLayout = true
        header.layoutSubtreeIfNeeded()
        let restingFrames = ShellLayout.navigationFrames(
            bounds: header.bounds,
            menuSize: header.navigationHost.contentView.fittingSize,
            historySize: header.history.contentView.fittingSize,
            requestedCenter: NSPoint(x: header.bounds.midX, y: ShellLayout.navigationRowCenter)
        )
        XCTAssertEqual(header.navigationHost.presentationOffset, -(restingFrames.menu.maxY + 8) / 2, accuracy: 0.001)
        XCTAssertEqual(header.navigationHost.frame.origin.y, restingFrames.menu.origin.y + header.navigationHost.presentationOffset, accuracy: 0.001)
    }

    func testMenuTravelsCompletelyAboveTopAndHistoryDoesNotMove() throws {
        let router = NavigationRouter()
        let view = WindowNavigationToolbarView(
            navigation: TopNavigationView(selection: .home, isPresented: true, reduceMotion: false,
                                          onHome: {}, onLibrary: {}, onSearch: {}),
            history: HistoryToolbarView(router: router, isDisabled: false), showsHistory: true)
        let coordinator = view.makeCoordinator()
        let header = view.makeNativeHeader(coordinator: coordinator, reduceTransparency: false)
        header.frame = NSRect(x: 0, y: 0, width: 620, height: 72)
        header.layoutSubtreeIfNeeded()
        let restingMenu = header.navigationHost.frame
        let restingHistory = header.history.frame
        for progress in [0.75, 0.5, 0.25, 0.0, 0.25, 0.5, 1.0] {
            coordinator.navigation.setPresentation(progress: progress, isPresented: progress == 1, reduceMotion: false)
            header.needsLayout = true
            header.layoutSubtreeIfNeeded()
            XCTAssertEqual(header.history.frame, restingHistory)
            XCTAssertEqual(header.navigationHost.frame.size, restingMenu.size)
            XCTAssertEqual(header.navigationHost.frame.minX, restingMenu.minX, accuracy: 0.001)
            if progress == 0 {
                XCTAssertLessThan(header.navigationHost.frame.maxY, header.bounds.minY)
                XCTAssertTrue(header.navigationHost.isHidden)
            } else {
                XCTAssertFalse(header.navigationHost.isHidden)
            }
        }
        XCTAssertEqual(header.navigationHost.frame, restingMenu)
    }
}
