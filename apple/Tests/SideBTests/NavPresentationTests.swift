import XCTest
@testable import SideB

final class NavPresentationTests: XCTestCase {
    func testDeepDestinationUsesVisitedMainRoute() {
        let history: [PageDestination] = [.home, .library, .album(browseId: "album"), .search(query: "future")]
        XCTAssertEqual(MainNavigationDestination.selected(history: history, currentIndex: 2, searchPresented: false), .library)
        XCTAssertEqual(MainNavigationDestination.selected(history: history, currentIndex: 0, searchPresented: false), .home)
    }

    func testSearchModalOverridesSelectionAndHistoryBelongsToLibrary() {
        XCTAssertEqual(MainNavigationDestination.selected(history: [.home, .history], currentIndex: 1, searchPresented: false), .library)
        XCTAssertEqual(MainNavigationDestination.selected(history: [.library], currentIndex: 0, searchPresented: true), .search)
    }

    func testFullscreenSuppressesCollapsedNavigation() {
        XCTAssertTrue(NavPresentation.showsTopNavigation(sidebarExpanded: false, fullscreenPresented: false))
        XCTAssertFalse(NavPresentation.showsTopNavigation(sidebarExpanded: false, fullscreenPresented: true))
        XCTAssertFalse(NavPresentation.showsTopNavigation(sidebarExpanded: true, fullscreenPresented: false))
    }

    @MainActor func testExploreDetailsKeepSelectionAndBackForwardRestoreTheirCategory() {
        let router = NavigationRouter()
        router.navigate(to: .explore(.discover))
        router.navigate(to: .explore(.category("rock")))
        router.navigate(to: .playlist(browseId: "list"))
        XCTAssertEqual(MainNavigationDestination.selected(history: router.history, currentIndex: router.currentIndex, searchPresented: false), .explore)
        router.goBack()
        XCTAssertEqual(router.currentPage, .explore(.category("rock")))
        router.goBack()
        XCTAssertEqual(router.currentPage, .explore(.discover))
        router.goForward()
        XCTAssertEqual(router.currentPage, .explore(.category("rock")))
        XCTAssertEqual(MainNavigationDestination.selected(history: router.history, currentIndex: router.currentIndex, searchPresented: true), .search)
    }
}
