import AppKit
import XCTest
@testable import SideB

@MainActor
final class WindowNavigationToolbarTests: XCTestCase {
    func testNativeHistoryIsFixedAndContainsOnlyWorkingBackForwardControls() throws {
        let router = NavigationRouter()
        var settingsCalls = 0
        var view = HistoryToolbarView(router: router, isDisabled: false,
                                      onHomeSettings: { settingsCalls += 1 })
        let coordinator = view.makeCoordinator()
        let container = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: false)
        let bar = try XCTUnwrap(coordinator.bar)

        XCTAssertEqual(bar.fittingSize.width, 76)
        XCTAssertEqual(bar.fittingSize.height, 42)
        XCTAssertEqual(container.contentView.fittingSize.width, 76)
        XCTAssertEqual(container.contentView.fittingSize.height, 42)
        bar.layoutSubtreeIfNeeded()
        let visibleDividers = bar.subviews.compactMap { $0 as? NSBox }.filter { !$0.isHidden }
        XCTAssertEqual(visibleDividers.count, 1)
        XCTAssertEqual(try XCTUnwrap(visibleDividers.first).frame,
                       NSRect(x: 37.5, y: 13, width: 1, height: 16))

        XCTAssertTrue(bar.refresh.isHidden)
        XCTAssertTrue(bar.settings.isHidden)
        XCTAssertFalse(bar.refresh.isAccessibilityElement())
        XCTAssertFalse(bar.settings.isAccessibilityElement())
        XCTAssertNil(bar.refresh.target)
        XCTAssertNil(bar.refresh.action)
        XCTAssertNil(bar.settings.target)
        XCTAssertNil(bar.settings.action)
        XCTAssertEqual(bar.refresh.keyEquivalent, "")
        XCTAssertEqual(bar.settings.keyEquivalent, "")

        XCTAssertFalse(bar.back.isEnabled)
        XCTAssertFalse(bar.forward.isEnabled)
        router.navigate(to: .library)
        view.updateNativeContainer(container, coordinator: coordinator, reduceTransparency: true)
        XCTAssertTrue(bar.back.isEnabled)
        XCTAssertFalse(bar.forward.isEnabled)
        XCTAssertTrue(bar.refresh.isHidden)
        XCTAssertTrue(bar.settings.isHidden)
        XCTAssertEqual(bar.fittingSize, NSSize(width: 76, height: 42))

        bar.back.sendAction(try XCTUnwrap(bar.back.action), to: bar.back.target)
        XCTAssertEqual(router.currentPage, .home)
        view.updateNativeContainer(container, coordinator: coordinator, reduceTransparency: false)
        XCTAssertFalse(bar.back.isEnabled)
        XCTAssertTrue(bar.forward.isEnabled)
        bar.forward.sendAction(try XCTUnwrap(bar.forward.action), to: bar.forward.target)
        XCTAssertEqual(router.currentPage, .library)
        XCTAssertEqual(settingsCalls, 0)

        view = HistoryToolbarView(router: router, isDisabled: true,
                                  onHomeSettings: { settingsCalls += 1 })
        view.updateNativeContainer(container, coordinator: coordinator, reduceTransparency: true)
        XCTAssertFalse(bar.back.isEnabled)
        XCTAssertFalse(bar.forward.isEnabled)
        XCTAssertEqual(bar.fittingSize, NSSize(width: 76, height: 42))
        XCTAssertEqual(settingsCalls, 0)
    }

    func testHeaderKeepsThreeCapsuleGeometryAcrossWidthsTransparencyAndPresentationStates() throws {
        for reduceTransparency in [false, true] {
            let router = NavigationRouter()
            var view = makeToolbar(router: router)
            let coordinator = view.makeCoordinator()
            let header = view.makeNativeHeader(coordinator: coordinator,
                                               reduceTransparency: reduceTransparency)

            for width: CGFloat in [420, 620, 900] {
                header.frame = NSRect(x: 0, y: 0, width: width, height: 72)
                view.isSidebarExpanded = false
                view.isSearchExpanded = false
                view.updateNativeHeader(header, coordinator: coordinator,
                                        reduceTransparency: reduceTransparency)
                header.layoutSubtreeIfNeeded()

                let collapsedSearch = header.searchHost.frame
                let destinations = header.navigationHost.frame
                let closedHistory = header.history.frame
                XCTAssertEqual(collapsedSearch.size, NSSize(width: 42, height: 42))
                XCTAssertEqual(destinations.size, NSSize(width: 246, height: 42))
                XCTAssertEqual(closedHistory.size, NSSize(width: 76, height: 42))
                XCTAssertEqual(collapsedSearch.minY, 18, accuracy: 0.001)
                XCTAssertEqual(destinations.minY, collapsedSearch.minY, accuracy: 0.001)
                XCTAssertEqual(closedHistory.minY, collapsedSearch.minY, accuracy: 0.001)
                XCTAssertLessThan(closedHistory.maxY, header.bounds.maxY)
                XCTAssertEqual(collapsedSearch.minX, (width - 384) / 2, accuracy: 0.001)
                XCTAssertEqual(closedHistory.maxX - collapsedSearch.minX, 384, accuracy: 0.001)
                XCTAssertEqual(collapsedSearch.maxX + 10, destinations.minX, accuracy: 0.001)
                XCTAssertEqual(destinations.maxX + 10, closedHistory.minX, accuracy: 0.001)
                XCTAssertEqual((collapsedSearch.minX + closedHistory.maxX) / 2,
                               header.bounds.midX, accuracy: 0.001)

                view.isSearchExpanded = true
                view.updateNativeHeader(header, coordinator: coordinator,
                                        reduceTransparency: reduceTransparency)
                header.layoutSubtreeIfNeeded()
                XCTAssertEqual(header.searchHost.frame.size, NSSize(width: 298, height: 42))
                XCTAssertEqual(header.searchHost.frame.maxX, destinations.maxX, accuracy: 0.001)
                XCTAssertEqual(header.history.frame, closedHistory)

                view.isSidebarExpanded = true
                view.updateNativeHeader(header, coordinator: coordinator,
                                        reduceTransparency: reduceTransparency)
                header.layoutSubtreeIfNeeded()
                XCTAssertEqual(header.searchHost.frame.minX, 18, accuracy: 0.001)
                XCTAssertEqual(header.history.frame.maxX, header.bounds.maxX - 18, accuracy: 0.001)
                XCTAssertEqual(header.history.frame.size, NSSize(width: 76, height: 42))
                XCTAssertTrue(header.navigationHost.isHidden)
                XCTAssertFalse(header.searchHost.isHidden)
                XCTAssertFalse(header.history.isHidden)

                view.isSidebarExpanded = false
                view.isSearchExpanded = false
                let hiddenHistoryView = makeToolbar(router: router, showsHistory: false)
                hiddenHistoryView.updateNativeHeader(header, coordinator: coordinator,
                                                     reduceTransparency: reduceTransparency)
                header.layoutSubtreeIfNeeded()
                XCTAssertTrue(header.navigationHost.isHidden)
                XCTAssertTrue(header.searchHost.isHidden)
                XCTAssertTrue(header.history.isHidden)
            }
        }
    }

    func testClusterFramesInterpolateWithinZeroAndOffsetBounds() {
        let boundsList = [
            CGRect(x: 0, y: 0, width: 420, height: 72),
            CGRect(x: 25, y: 11, width: 620, height: 72),
            CGRect(x: 80, y: 7, width: 900, height: 72)
        ]

        for bounds in boundsList {
            let center = CGPoint(x: bounds.midX, y: bounds.minY + 28)
            let leading = bounds.minX + 18
            let trailing = bounds.maxX - 18
            let clusterWidth: CGFloat = 384
            let startX = bounds.midX - clusterWidth / 2
            let closedHistoryX = startX + 308
            let openHistoryX = trailing - 76
            for sidebarProgress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                for searchProgress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                    let frames = NavigationClusterFrames.make(
                        bounds: bounds, center: center, leading: leading, trailing: trailing,
                        sidebarProgress: sidebarProgress, searchProgress: searchProgress,
                        reduceMotion: true, windowTop: bounds.minY)

                    XCTAssertEqual(frames.search.height, 42, accuracy: 0.001)
                    XCTAssertEqual(frames.destinations.size, CGSize(width: 246, height: 42))
                    XCTAssertEqual(frames.history.size, CGSize(width: 76, height: 42))
                    XCTAssertEqual(frames.search.width, 42 + 256 * searchProgress, accuracy: 0.001)
                    XCTAssertEqual(frames.search.minX,
                                   startX + (leading - startX) * sidebarProgress, accuracy: 0.001)
                    XCTAssertEqual(frames.history.minX,
                                   closedHistoryX + (openHistoryX - closedHistoryX) * sidebarProgress,
                                   accuracy: 0.001)
                    XCTAssertGreaterThanOrEqual(frames.search.minX, bounds.minX - 0.001)
                    XCTAssertLessThanOrEqual(frames.search.maxX, frames.history.minX - 10 + 0.001)
                    XCTAssertGreaterThanOrEqual(frames.history.minX, bounds.minX - 0.001)
                    XCTAssertLessThanOrEqual(frames.history.maxX, bounds.maxX + 0.001)
                    if sidebarProgress == 0 {
                        XCTAssertEqual(frames.history.minX - frames.destinations.maxX, 10, accuracy: 0.001)
                        if searchProgress == 0 {
                            XCTAssertEqual(frames.destinations.minX - frames.search.maxX, 10, accuracy: 0.001)
                        }
                        if searchProgress == 1 {
                            XCTAssertEqual(frames.search.maxX, frames.destinations.maxX,
                                           accuracy: 0.001, "Expanded search fuses across the destination surface")
                        }
                    }
                }
            }
        }
    }

    func testSearchAnimationCanReverseFromItsCurrentProgressWithoutJumping() {
        let startedAt: CFTimeInterval = 10
        let forward = NavigationProgressAnimation(start: 0, target: 1,
                                                  startTime: startedAt, duration: 0.42)
        let currentProgress = forward.value(at: startedAt + 0.18)
        XCTAssertGreaterThan(currentProgress, 0)
        XCTAssertLessThan(currentProgress, 1)

        let reversed = NavigationProgressAnimation(start: currentProgress, target: 0,
                                                    startTime: startedAt + 0.18, duration: 0.42)
        XCTAssertEqual(reversed.value(at: startedAt + 0.18), currentProgress, accuracy: 0.001)
        XCTAssertLessThan(reversed.value(at: startedAt + 0.19), currentProgress)
        XCTAssertTrue(reversed.isComplete(at: startedAt + 0.60))
    }

    func testSearchCallbacksUseCurrentHeaderBindings() throws {
        let router = NavigationRouter()
        var expansionEvents: [Bool] = []
        var queries: [String] = []
        let view = makeToolbar(router: router, isSidebarExpanded: true,
                               onSearchExpansionChange: { expansionEvents.append($0) },
                               onSearchQueryChange: { queries.append($0) })
        let coordinator = view.makeCoordinator()
        let header = view.makeNativeHeader(coordinator: coordinator, reduceTransparency: false)

        header.searchBar.onToggleExpand?(true)
        header.searchBar.onQueryChange?("ambient")

        XCTAssertEqual(expansionEvents, [true])
        XCTAssertEqual(queries, ["ambient"])
    }

    private func makeToolbar(
        router: NavigationRouter,
        isSidebarExpanded: Bool = false,
        showsHistory: Bool = true,
        onSearchExpansionChange: @escaping (Bool) -> Void = { _ in },
        onSearchQueryChange: @escaping (String) -> Void = { _ in }
    ) -> WindowNavigationToolbarView {
        WindowNavigationToolbarView(
            navigation: TopNavigationView(selection: .home, isPresented: true, reduceMotion: true,
                                          onHome: {}, onLibrary: {}, onSearch: {}),
            history: HistoryToolbarView(router: router, isDisabled: false), showsHistory: showsHistory,
            isSidebarExpanded: isSidebarExpanded,
            onSearchExpansionChange: onSearchExpansionChange,
            onSearchQueryChange: onSearchQueryChange)
    }
}
