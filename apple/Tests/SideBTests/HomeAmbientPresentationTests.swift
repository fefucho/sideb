import AppKit
import QuartzCore
import XCTest
@testable import SideB

@MainActor
final class HomeAmbientPresentationTests: XCTestCase {
    func testEnablingReduceMotionAfterAnIntermediateFadeRequestsItsFinalFrame() {
        let view = HomeAmbientLayerNSView(initialTime: 17, fixedTime: 17)
        let first = HomeAmbientPalette.neutral
        let final = HomeAmbientPalette(left: .init(red: 0.8, green: 0.1, blue: 0.2),
                                       right: .init(red: 0.1, green: 0.3, blue: 0.8))
        view.configure(palette: first, smokeMask: nil, active: false, reduceMotion: false, displayScale: 1)
        view.didSubmitFrame() // Initial frame has reached the presentation queue.
        XCTAssertFalse(view.needsPresentation)

        view.configure(palette: final, smokeMask: nil, active: false, reduceMotion: false,
                       displayScale: 1, paletteDuration: 1)
        XCTAssertTrue(view.needsPresentation)
        view.didSubmitFrame() // A fade frame has been submitted; the animation is still running.
        XCTAssertTrue(view.needsPresentation)

        view.configure(palette: final, smokeMask: nil, active: false, reduceMotion: true, displayScale: 1)
        XCTAssertTrue(view.needsPresentation, "Retiring fades must still request their final model-state frame")
        view.didSubmitFrame()
        XCTAssertFalse(view.needsPresentation, "A paused, clean renderer should stop requesting frames")
        view.releaseContent()
    }
}
