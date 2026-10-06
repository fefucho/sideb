import Observation
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class WindowGesturePresentationTests: XCTestCase {
    func testFullscreenRemainsPresentedThroughSettlementAndClosesExactlyOnce() {
        var completions: [() -> Void] = []
        let presentation = WindowGesturePresentation { _, updates, completion in
            updates()
            completions.append(completion)
        }
        var closes = 0
        presentation.beginFullscreenPull()
        presentation.updateFullscreenPull(offset: 130, progress: 0.22, armed: true)
        presentation.settleFullscreen(shouldClose: true, travel: 600, reduceMotion: false) { closes += 1 }
        presentation.settleFullscreen(shouldClose: true, travel: 600, reduceMotion: false) { closes += 1 }

        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(presentation.fullscreenStage, .closing)
        XCTAssertTrue(presentation.fullscreenIsBusy)
        XCTAssertTrue(presentation.revealUnderlying)
        XCTAssertEqual(presentation.fullscreenOffset, 600)
        XCTAssertEqual(closes, 0)
        completions[0]()
        completions[0]()
        XCTAssertEqual(closes, 1)
        XCTAssertEqual(presentation.fullscreenStage, .idle)
        XCTAssertEqual(presentation.fullscreenOffset, 0)
        XCTAssertFalse(presentation.revealUnderlying)
    }

    func testResetInvalidatesOldCloseCompletionWithoutDisturbingNewContact() {
        var completions: [() -> Void] = []
        let presentation = WindowGesturePresentation { _, updates, completion in
            updates()
            completions.append(completion)
        }
        var closes = 0
        presentation.beginFullscreenPull()
        presentation.updateFullscreenPull(offset: 140, progress: 0.25, armed: true)
        presentation.settleFullscreen(shouldClose: true, travel: 600, reduceMotion: true) { closes += 1 }
        presentation.resetFullscreen()
        presentation.beginFullscreenPull()
        presentation.updateFullscreenPull(offset: 35, progress: 0.06, armed: false)
        completions[0]()

        XCTAssertEqual(closes, 0)
        XCTAssertEqual(presentation.fullscreenStage, .pulling)
        XCTAssertEqual(presentation.fullscreenOffset, 35)
        XCTAssertTrue(presentation.revealUnderlying)
        presentation.settleFullscreen(shouldClose: false, travel: 600, reduceMotion: true) { closes += 1 }
        XCTAssertEqual(presentation.fullscreenStage, .returning)
        XCTAssertTrue(presentation.revealUnderlying)
        completions[1]()
        XCTAssertEqual(closes, 0)
        XCTAssertEqual(presentation.fullscreenStage, .idle)
        XCTAssertFalse(presentation.revealUnderlying)
    }

    func testContactDeltasDoNotInvalidateUnderlyingPageVisibilityObservation() {
        let presentation = WindowGesturePresentation()
        presentation.beginFullscreenPull()
        XCTAssertFalse(presentation.revealUnderlying)
        presentation.updateFullscreenPull(offset: 1, progress: 0.002, armed: false)
        XCTAssertTrue(presentation.revealUnderlying)

        nonisolated(unsafe) var visibilityChanges = 0
        withObservationTracking {
            _ = presentation.revealUnderlying
        } onChange: {
            visibilityChanges += 1
        }
        for offset in 2...100 {
            presentation.updateFullscreenPull(offset: CGFloat(offset),
                                              progress: CGFloat(offset) / 600, armed: offset >= 90)
        }
        XCTAssertEqual(visibilityChanges, 0)
        presentation.resetFullscreen()
        XCTAssertEqual(visibilityChanges, 1)
    }
}
