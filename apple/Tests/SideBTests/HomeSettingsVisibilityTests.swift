import XCTest
@testable import SideB

final class HomeSettingsVisibilityTests: XCTestCase {
    func testSettingsOnlyPresentOnHomeWithoutFullscreenOrSpotlight() {
        let pages: [PageDestination] = [
            .home, .library, .history, .search(query: nil), .search(query: "song"),
            .album(browseId: "album"), .playlist(browseId: "playlist"),
            .artist(browseId: "artist"), .catalog(browseId: "catalog", params: nil, title: "Catalog")
        ]
        for page in pages {
            for fullscreen in [false, true] {
                for search in [false, true] {
                    XCTAssertEqual(HomeSettingsVisibility.canPresent(page: page,
                                                                     fullscreenPresented: fullscreen,
                                                                     searchPresented: search),
                                   page == .home && !fullscreen && !search,
                                   "Unexpected settings availability for \(page), fullscreen \(fullscreen), search \(search)")
                }
            }
        }
    }
}
