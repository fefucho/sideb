import XCTest
@testable import SideB

final class PlaybackBarShellLayoutTests: XCTestCase {
    func testFullscreenKeepsPlaybackControlsAvailable() {
        XCTAssertTrue(PlaybackBarShellLayout.showsBar(in: .fullscreen))
        XCTAssertTrue(PlaybackBarShellLayout.showsBar(in: .bar))
        XCTAssertFalse(PlaybackBarShellLayout.showsBar(in: .sidebar))
    }
    func testBarKeepsItsCenterWithoutOverlappingTrailingTrigger() {
        for width in [CGFloat(360), 640, 900, 1200, 1800] {
            let barWidth = PlaybackBarShellLayout.barWidth(contentWidth: width)
            let barRight = (width + barWidth) / 2
            let buttonLeft = width - PlaybackBarShellLayout.margin - PlaybackBarShellLayout.buttonSize
            XCTAssertLessThanOrEqual(barRight + PlaybackBarShellLayout.gap, buttonLeft)
            XCTAssertLessThanOrEqual(barWidth, 820)
        }
    }

    func testDegenerateWidthNeverProducesNegativeFrame() {
        XCTAssertEqual(PlaybackBarShellLayout.barWidth(contentWidth: 0), 0)
    }
}
