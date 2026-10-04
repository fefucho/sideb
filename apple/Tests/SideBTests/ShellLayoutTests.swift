import XCTest
@testable import SideB

final class ShellLayoutTests: XCTestCase {
    func testFlippedContentClearanceWithNonzeroOrigin() {
        XCTAssertEqual(ShellLayout.topClearance(
            bounds: CGRect(x: 20, y: 100, width: 800, height: 600),
            contentLayoutRect: CGRect(x: 20, y: 150, width: 800, height: 550),
            windowControlsRect: CGRect(x: 40, y: 110, width: 70, height: 16),
            isFlipped: true
        ), 50)
    }

    func testUnflippedContentClearanceWithNonzeroOrigin() {
        XCTAssertEqual(ShellLayout.topClearance(
            bounds: CGRect(x: 20, y: 100, width: 800, height: 600),
            contentLayoutRect: CGRect(x: 20, y: 100, width: 800, height: 550),
            windowControlsRect: CGRect(x: 40, y: 674, width: 70, height: 16),
            isFlipped: false
        ), 50)
    }

    func testVisibleControlsClearFullSizeContentInBothCoordinateSystems() {
        let bounds = CGRect(x: 0, y: 100, width: 800, height: 600)
        XCTAssertEqual(ShellLayout.topClearance(bounds: bounds, contentLayoutRect: bounds,
            windowControlsRect: CGRect(x: 20, y: 108, width: 70, height: 16), isFlipped: true), 24)
        XCTAssertEqual(ShellLayout.topClearance(bounds: bounds, contentLayoutRect: bounds,
            windowControlsRect: CGRect(x: 20, y: 676, width: 70, height: 16), isFlipped: false), 24)
    }

    func testClearanceClampsWhenContentAndControlsExtendBeyondTop() {
        let bounds = CGRect(x: 0, y: 100, width: 800, height: 600)
        XCTAssertEqual(ShellLayout.topClearance(bounds: bounds,
            contentLayoutRect: CGRect(x: 0, y: 90, width: 800, height: 610),
            windowControlsRect: CGRect(x: 20, y: 80, width: 70, height: 10), isFlipped: true), 0)
        XCTAssertEqual(ShellLayout.topClearance(bounds: bounds,
            contentLayoutRect: CGRect(x: 0, y: 100, width: 800, height: 610),
            windowControlsRect: nil, isFlipped: false), 0)
    }

    func testSidebarReserveCompensatesItsOuterInset() {
        XCTAssertEqual(ShellLayout.sidebarInset + ShellLayout.sidebarHeaderInset(titlebarHeight: 38), 48)
        XCTAssertEqual(ShellLayout.sidebarHeaderInset(titlebarHeight: 0), 10)
    }
    func testNativeGroupTranslationPreservesSpacingAndSizesWithoutAccumulation() {
        let bounds = CGRect(x: 10, y: 100, width: 800, height: 600)
        let close = CGRect(x: 22, y: 114, width: 14, height: 14)
        let next = close.offsetBy(dx: 23, dy: 0)
        let offset = ShellLayout.controlsOffset(closeRect: close, bounds: bounds, isFlipped: true)
        XCTAssertEqual(offset, CGSize(width: 9, height: 7))
        let aligned = ShellLayout.translatedControl(close, offset: offset, isFlipped: true)
        let alignedNext = ShellLayout.translatedControl(next, offset: offset, isFlipped: true)
        XCTAssertEqual(aligned.size, close.size)
        XCTAssertEqual(alignedNext.midX - aligned.midX, 23)
        XCTAssertEqual(aligned.midX - bounds.minX, 28)
        XCTAssertEqual(aligned.midY - bounds.minY, 28)
        XCTAssertEqual(ShellLayout.controlsOffset(closeRect: aligned, bounds: bounds, isFlipped: true), .zero)
        XCTAssertEqual(ShellLayout.translatedControl(close, offset: offset, isFlipped: true), aligned)
        XCTAssertEqual(ShellLayout.translatedControl(aligned, offset: CGSize(width: -offset.width, height: -offset.height), isFlipped: true), close)
    }

    func testNativeGroupAnchorSurvivesUnflippedResize() {
        for height: CGFloat in [600, 900] {
            let bounds = CGRect(x: 10, y: 100, width: 800, height: height)
            let close = CGRect(x: 22, y: bounds.maxY - 28, width: 14, height: 14)
            let offset = ShellLayout.controlsOffset(closeRect: close, bounds: bounds, isFlipped: false)
            let aligned = ShellLayout.translatedControl(close, offset: offset, isFlipped: false)
            XCTAssertEqual(aligned.midX - bounds.minX, 28)
            XCTAssertEqual(bounds.maxY - aligned.midY, 28)
            XCTAssertEqual(aligned.size, close.size)
        }
    }

    func testToolbarBarsStartAtTrafficLightsAndKeepMatchingTrailingMargin() {
        for width: CGFloat in [960, 1440] {
            for flipped in [false, true] {
                let bounds = CGRect(x: 10, y: 100, width: width, height: 900)
                let host = CGRect(x: bounds.midX - 200, y: 100, width: 400, height: 88)
                let main = ShellLayout.toolbarControlFrame(size: CGSize(width: 262, height: ShellLayout.navigationSurfaceHeight),
                    windowBounds: bounds, hostRect: host, isFlipped: flipped, topInset: 21)
                let history = ShellLayout.toolbarControlFrame(size: CGSize(width: 145, height: ShellLayout.navigationSurfaceHeight),
                    windowBounds: bounds, hostRect: host, isFlipped: flipped, topInset: 21, trailingInset: 21)
                let close = CGRect(x: bounds.minX + 21,
                    y: flipped ? bounds.minY + 21 : bounds.maxY - 35, width: 14, height: 14)
                XCTAssertEqual(flipped ? main.minY : main.maxY, flipped ? close.minY : close.maxY)
                XCTAssertEqual(flipped ? history.minY : history.maxY, flipped ? close.minY : close.maxY)
                XCTAssertEqual(bounds.maxX - history.maxX, 21)
                XCTAssertEqual(main.midX, host.midX)
                XCTAssertEqual(main.midY, history.midY)
                XCTAssertEqual(main.height, history.height)
            }
        }
    }

}
