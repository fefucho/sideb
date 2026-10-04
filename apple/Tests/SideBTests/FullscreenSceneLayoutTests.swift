import SwiftUI
import XCTest
@testable import SideB

final class FullscreenSceneLayoutTests: XCTestCase {
    func testSidebarProgressKeepsCanvasFixedAndForegroundRightEdgeAnchoredDuringReversal() {
        let canvas = CGSize(width: 1440, height: 900)
        let initial = FullscreenSidebarGeometry(canvasSize: canvas, progress: 0).metrics
        for progress: CGFloat in [0, 0.25, 0.5, 0.75, 1, 0.75, 0.5, 0] {
            let geometry = FullscreenSidebarGeometry(canvasSize: canvas, progress: progress)
            let frame = geometry.metrics
            XCTAssertEqual(geometry.canvasSize, canvas)
            XCTAssertEqual(geometry.isTransitioning, progress > 0 && progress < 1)
            XCTAssertEqual(geometry.contentOffset + frame.viewport.width, canvas.width, accuracy: 0.001)
            XCTAssertEqual(frame.leftWidth + frame.rightWidth + frame.columnSpacing + frame.horizontalPadding * 2,
                           frame.viewport.width, accuracy: 0.001)
            XCTAssertLessThanOrEqual(frame.artworkBlockHeight, frame.availableContentHeight)
            XCTAssertEqual(frame.viewport.height, initial.viewport.height)
            XCTAssertEqual(frame.metadataSpacing, initial.metadataSpacing)
            XCTAssertEqual(frame.metadataHeight, initial.metadataHeight)
        }
        let restored = FullscreenSidebarGeometry(canvasSize: canvas, progress: 0).metrics
        XCTAssertEqual(restored.artworkSize, initial.artworkSize)
        XCTAssertEqual(restored.leftWidth, initial.leftWidth)
    }

    func testArtworkAndTypographyDoNotJumpAcrossSidebarWidthsOrOldFontBreakpoints() {
        for height: CGFloat in [640, 900, 1200] {
            var previous = FullscreenSceneMetrics(viewport: CGSize(width: 718, height: height))
            for width in stride(from: CGFloat(719), through: 1700, by: 1) {
                let current = FullscreenSceneMetrics(viewport: CGSize(width: width, height: height))
                XCTAssertGreaterThanOrEqual(current.artworkSize, previous.artworkSize)
                XCTAssertLessThanOrEqual(current.artworkSize - previous.artworkSize, 1)
                previous = current
            }
        }
        for boundary: CGFloat in [300, 340, 460, 500] {
            let before = FullscreenSceneMetrics.typography(artworkWidth: boundary - 0.1)
            let after = FullscreenSceneMetrics.typography(artworkWidth: boundary + 0.1)
            XCTAssertLessThan(abs(after.title - before.title), 0.01)
            XCTAssertLessThan(abs(after.subtitle - before.subtitle), 0.01)
            XCTAssertLessThan(abs(after.action - before.action), 0.01)
        }
    }

    func testArtworkLeavesSpaceForMetadataAndPlayerAtBothSidebarEndpoints() {
        for window in [CGSize(width: 960, height: 640), CGSize(width: 1440, height: 900)] {
            for reservedWidth in [CGFloat.zero, ShellLayout.sidebarReserveWidth(expanded: true)] {
                let frame = FullscreenSceneMetrics(viewport: CGSize(width: window.width - reservedWidth,
                                                                   height: window.height))
                XCTAssertGreaterThanOrEqual(frame.artworkSize, 100)
                XCTAssertLessThanOrEqual(frame.artworkSize, frame.leftWidth)
                XCTAssertLessThanOrEqual(frame.artworkBlockHeight, frame.availableContentHeight)
                XCTAssertEqual(frame.topPadding + frame.availableContentHeight + frame.bottomReservedHeight,
                               window.height, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(frame.contentPanelHeight, 80)
            }
        }
    }
}
