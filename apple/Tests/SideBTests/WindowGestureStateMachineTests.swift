import Foundation
import XCTest
@testable import SideB

final class WindowGestureStateMachineTests: XCTestCase {
    private typealias Machine = WindowGestureStateMachine
    private let history = Machine.Context(mode: .history, canGoBack: true, canGoForward: true)
    private let fullscreen = Machine.Context(mode: .fullscreen, fullscreenHeight: 700)

    func testAdapterContextCaptureMatchesActualAndProvisionalContactStarts() {
        var machine = Machine()
        let mayBegin = Machine.Event(phase: .mayBegin)
        let began = Machine.Event(phase: .began)
        let changed = Machine.Event(deltaX: 100, phase: .changed)
        XCTAssertTrue(machine.requiresStartContext(for: mayBegin))
        _ = machine.handle(mayBegin, context: history)
        XCTAssertFalse(machine.requiresStartContext(for: mayBegin))
        XCTAssertFalse(machine.requiresStartContext(for: began))
        XCTAssertFalse(machine.requiresStartContext(for: changed))
        _ = machine.handle(began, context: fullscreen)
        // Once began resolved the provisional start, another began is a new
        // physical contact and must recapture the region under its pointer.
        XCTAssertTrue(machine.requiresStartContext(for: began))
        _ = machine.handle(changed, context: fullscreen)
        XCTAssertEqual(machine.snapshot.action, .back)
        _ = machine.handle(.init(phase: .ended), context: history)
        XCTAssertTrue(machine.requiresStartContext(for: changed))
        XCTAssertFalse(machine.requiresStartContext(for: .init(deltaX: 100)))
        XCTAssertFalse(machine.requiresStartContext(for: .init(phase: .began, momentumPhase: .changed)))
        XCTAssertFalse(machine.requiresStartContext(for: .init(phase: .changed, hasPreciseScrollingDeltas: false)))

        _ = machine.handle(mayBegin, context: history)
        machine.invalidate()
        XCTAssertTrue(machine.requiresStartContext(for: began))
        XCTAssertTrue(machine.requiresStartContext(for: mayBegin))
    }

    func testDiagonalRemainsUndecidedUntilOneAxisBecomesDeliberate() {
        var machine = Machine()
        let diagonal = machine.handle(.init(deltaX: 24, deltaY: 24, phase: .began), context: history)
        XCTAssertEqual(diagonal.snapshot.axis, .undecided)
        XCTAssertEqual(diagonal.disposition, .passThrough)
        XCTAssertNil(diagonal.snapshot.action)

        let horizontal = machine.handle(.init(deltaX: 54, phase: .changed), context: history)
        XCTAssertEqual(horizontal.snapshot.action, .back)
        XCTAssertTrue(horizontal.snapshot.isArmed)
        XCTAssertEqual(horizontal.disposition, .consume)
        XCTAssertEqual(machine.handle(.init(phase: .ended), context: history).commit, .back)

        var verticalMachine = Machine()
        _ = verticalMachine.handle(.init(deltaX: 24, deltaY: 24, phase: .began), context: history)
        let vertical = verticalMachine.handle(.init(deltaY: 30, phase: .changed), context: history)
        XCTAssertEqual(vertical.snapshot.axis, .vertical)
        XCTAssertEqual(vertical.disposition, .passThrough)
        XCTAssertNil(verticalMachine.handle(.init(phase: .ended), context: history).commit)
    }

    func testWindowEligibilityIsCapturedAtZeroDeltaStartUntilInertiaEnds() {
        for direction: CGFloat in [1, -1] {
            var machine = Machine()
            var outsideWindow = history
            outsideWindow.allowsHorizontalNavigation = false
            _ = machine.handle(.init(phase: .mayBegin), context: outsideWindow)
            // A contact starting outside the window cannot acquire it later.
            _ = machine.handle(.init(phase: .began), context: history)
            let edge = machine.handle(.init(deltaX: direction * 300, phase: .changed), context: history)
            XCTAssertEqual(edge.disposition, .passThrough)
            XCTAssertNil(edge.snapshot.action)
            XCTAssertNil(machine.handle(.init(phase: .ended), context: history).commit)
            let momentum = machine.handle(.init(deltaX: direction * 200, momentumPhase: .changed), context: history)
            XCTAssertEqual(momentum.disposition, .passThrough)
            XCTAssertNil(momentum.commit)
            XCTAssertEqual(machine.handle(.init(momentumPhase: .ended), context: history).disposition, .passThrough)
        }
    }

    func testVerticalPanelOwnsWholeFullscreenContactEvenAfterPointerLeaves() {
        var machine = Machine()
        var queue = fullscreen
        queue.verticalContentOwnsGesture = true
        _ = machine.handle(.init(phase: .began), context: queue)
        let outsidePanel = machine.handle(.init(deltaY: 300, phase: .changed), context: fullscreen)
        XCTAssertEqual(outsidePanel.disposition, .passThrough)
        XCTAssertNil(outsidePanel.snapshot.action)
        XCTAssertNil(machine.handle(.init(phase: .ended), context: fullscreen).commit)
        XCTAssertEqual(machine.handle(.init(deltaY: 300, momentumPhase: .began), context: fullscreen).disposition, .passThrough)
    }

    func testArmDisarmHysteresisIsReversibleAndHapticOccursOnlyOnce() {
        var machine = Machine()
        _ = machine.handle(.init(deltaX: 3, phase: .began), context: history)
        let armed = machine.handle(.init(deltaX: 66, phase: .changed), context: history)
        XCTAssertTrue(armed.didArm)
        XCTAssertTrue(armed.snapshot.isArmed)

        let nearThreshold = machine.handle(.init(deltaX: -20, phase: .changed), context: history)
        XCTAssertTrue(nearThreshold.snapshot.isArmed)
        XCTAssertFalse(nearThreshold.didArm)

        let disarmed = machine.handle(.init(deltaX: -5, phase: .changed), context: history)
        XCTAssertFalse(disarmed.snapshot.isArmed)
        XCTAssertEqual(disarmed.snapshot.phase, .pulling)
        let rearmed = machine.handle(.init(deltaX: 40, phase: .changed), context: history)
        XCTAssertTrue(rearmed.snapshot.isArmed)
        XCTAssertFalse(rearmed.didArm)
        XCTAssertEqual(machine.handle(.init(phase: .ended), context: history).commit, .back)
    }

    func testReversalThroughNeutralCancelsWithoutArmingOppositeDestination() {
        var machine = Machine()
        _ = machine.handle(.init(deltaX: 80, phase: .began), context: history)
        let reversed = machine.handle(.init(deltaX: -180, phase: .changed), context: history)
        XCTAssertEqual(reversed.snapshot.action, .back)
        XCTAssertEqual(reversed.snapshot.offset, 0)
        XCTAssertFalse(reversed.snapshot.isArmed)
        let release = machine.handle(.init(phase: .ended), context: history)
        XCTAssertNil(release.commit)
        XCTAssertEqual(release.snapshot.phase, .cancelled)
    }

    func testFullscreenOffsetFollowsContactAndSettlesFromCurrentPosition() {
        var machine = Machine()
        let initial = machine.handle(.init(deltaY: 40, phase: .began), context: fullscreen)
        XCTAssertEqual(initial.snapshot.offset, 40)
        let pull = machine.handle(.init(deltaY: 35, phase: .changed), context: fullscreen)
        XCTAssertEqual(pull.snapshot.offset, 75)
        XCTAssertFalse(pull.snapshot.isArmed)
        let shortRelease = machine.handle(.init(phase: .ended), context: fullscreen)
        XCTAssertNil(shortRelease.commit)
        XCTAssertEqual(shortRelease.snapshot.offset, 75)
        XCTAssertEqual(shortRelease.snapshot.phase, .cancelled)

        // The next changed is a valid fallback beginning, not stale inertia.
        let nextPull = machine.handle(.init(deltaY: 190, phase: .changed), context: fullscreen)
        XCTAssertEqual(nextPull.snapshot.offset, 190)
        XCTAssertTrue(nextPull.snapshot.isArmed)
        let close = machine.handle(.init(phase: .ended), context: fullscreen)
        XCTAssertEqual(close.commit, .dismissFullscreen)
        XCTAssertEqual(close.snapshot.offset, 190)
        XCTAssertEqual(close.snapshot.phase, .committed)
    }

    func testUpwardFullscreenGestureDoesNotBecomeDismissalWhenReversed() {
        var machine = Machine()
        let upward = machine.handle(.init(deltaY: -30, phase: .began), context: fullscreen)
        XCTAssertEqual(upward.disposition, .passThrough)
        let downAgain = machine.handle(.init(deltaY: 300, phase: .changed), context: fullscreen)
        XCTAssertEqual(downAgain.disposition, .passThrough)
        XCTAssertNil(downAgain.snapshot.action)
        XCTAssertNil(machine.handle(.init(phase: .ended), context: fullscreen).commit)
    }

    func testUnavailableHistoryProvidesFeedbackButNeverArmsOrCommits() {
        var machine = Machine()
        let beginning = Machine.Context(mode: .history)
        _ = machine.handle(.init(phase: .began), context: beginning)
        let pull = machine.handle(.init(deltaX: 300, phase: .changed), context: history)
        XCTAssertEqual(pull.snapshot.action, .back)
        XCTAssertFalse(pull.snapshot.isAvailable)
        XCTAssertFalse(pull.snapshot.isArmed)
        XCTAssertFalse(pull.didArm)
        XCTAssertEqual(pull.snapshot.progress, 0)
        XCTAssertEqual(pull.snapshot.offset, 18)
        XCTAssertEqual(pull.disposition, .consume)
        XCTAssertNil(machine.handle(.init(phase: .ended), context: history).commit)
    }

    func testModesAndWindowEligibilityDoNotLeakBetweenAxes() {
        var historyMachine = Machine()
        var disabledPaging = history
        disabledPaging.allowsHorizontalNavigation = false
        let disabled = historyMachine.handle(.init(deltaX: 200, phase: .began), context: disabledPaging)
        XCTAssertEqual(disabled.disposition, .passThrough)
        XCTAssertNil(historyMachine.handle(.init(phase: .ended), context: disabledPaging).commit)

        var fullscreenMachine = Machine()
        var fullscreenWithPagingDisabled = fullscreen
        fullscreenWithPagingDisabled.allowsHorizontalNavigation = false
        let dismissal = fullscreenMachine.handle(.init(deltaY: 200, phase: .began), context: fullscreenWithPagingDisabled)
        XCTAssertTrue(dismissal.snapshot.isArmed)
        XCTAssertEqual(fullscreenMachine.handle(.init(phase: .ended), context: fullscreenWithPagingDisabled).commit, .dismissFullscreen)

        var horizontalInFullscreen = Machine()
        XCTAssertEqual(horizontalInFullscreen.handle(.init(deltaX: 200, phase: .began), context: fullscreen).disposition, .passThrough)
        XCTAssertNil(horizontalInFullscreen.handle(.init(phase: .ended), context: fullscreen).commit)
    }

    func testOneReleaseCommitsAndDrainsMomentumWithoutMovingTheDestination() {
        var machine = Machine()
        _ = machine.handle(.init(deltaX: -100, phase: .began), context: history)
        XCTAssertEqual(machine.handle(.init(phase: .ended), context: history).commit, .forward)
        XCTAssertFalse(machine.isTracking)
        XCTAssertTrue(machine.isClaimed)
        let retainedSnapshot = machine.snapshot
        XCTAssertNil(machine.handle(.init(phase: .ended), context: history).commit)
        for phase: Machine.EventPhase in [.began, .changed, .changed, .ended] {
            let momentum = machine.handle(.init(deltaX: 500, momentumPhase: phase), context: history)
            XCTAssertEqual(momentum.disposition, .consume)
            XCTAssertEqual(momentum.snapshot, retainedSnapshot)
            XCTAssertNil(momentum.commit)
            XCTAssertFalse(momentum.didArm)
        }
        XCTAssertFalse(machine.isClaimed)
        XCTAssertEqual(machine.handle(.init(deltaY: 100, momentumPhase: .changed), context: history).disposition, .passThrough)
    }

    func testMomentumCannotStartOrReleaseAnArmedContact() {
        var idle = Machine()
        XCTAssertEqual(idle.handle(.init(deltaX: 500, momentumPhase: .began), context: history).disposition, .passThrough)
        XCTAssertEqual(idle.snapshot, .idle)
        XCTAssertFalse(idle.isTracking)

        var active = Machine()
        _ = active.handle(.init(deltaX: 100, phase: .began), context: history)
        let inertiaBeforeRelease = active.handle(.init(deltaX: 100, momentumPhase: .began), context: history)
        XCTAssertNil(inertiaBeforeRelease.commit)
        XCTAssertEqual(inertiaBeforeRelease.snapshot.phase, .cancelled)
        XCTAssertEqual(inertiaBeforeRelease.disposition, .consume)
        XCTAssertNil(active.handle(.init(phase: .ended), context: history).commit)
    }

    func testInvalidationCancelsAndDrainsContactThenAllowsFreshSequence() {
        var machine = Machine()
        _ = machine.handle(.init(deltaY: 200, phase: .began), context: fullscreen)
        XCTAssertEqual(machine.invalidate().snapshot.phase, .cancelled)
        let lateMovement = machine.handle(.init(deltaY: 300, phase: .changed), context: history)
        XCTAssertEqual(lateMovement.disposition, .consume)
        XCTAssertFalse(lateMovement.snapshot.isArmed)
        XCTAssertNil(machine.handle(.init(phase: .ended), context: history).commit)
        XCTAssertEqual(machine.handle(.init(deltaY: 100, momentumPhase: .changed), context: history).disposition, .consume)

        // A new began replaces a stale momentum marker with a new fixed owner.
        _ = machine.handle(.init(phase: .began), context: history)
        _ = machine.handle(.init(deltaX: 100, phase: .changed), context: history)
        XCTAssertEqual(machine.handle(.init(phase: .ended), context: history).commit, .back)
    }

    func testCancellationNeverCommitsAndWheelEventsDoNotUseChangedFallback() {
        var machine = Machine()
        _ = machine.handle(.init(deltaX: 100, phase: .began), context: history)
        let cancel = machine.handle(.init(phase: .cancelled), context: history)
        XCTAssertNil(cancel.commit)
        XCTAssertEqual(cancel.snapshot.phase, .cancelled)
        XCTAssertEqual(cancel.disposition, .consume)

        let wheel = machine.handle(.init(deltaX: 500), context: history)
        XCTAssertEqual(wheel.disposition, .passThrough)
        XCTAssertNil(wheel.commit)
        XCTAssertFalse(machine.isTracking)
        XCTAssertFalse(machine.isClaimed)

        let impreciseWheel = machine.handle(.init(deltaX: 500, phase: .changed, hasPreciseScrollingDeltas: false), context: history)
        XCTAssertEqual(impreciseWheel.disposition, .passThrough)
        XCTAssertFalse(machine.isTracking)
        let contact = machine.handle(.init(deltaX: -100, phase: .changed), context: history)
        XCTAssertEqual(contact.snapshot.action, .forward)
        XCTAssertEqual(machine.handle(.init(phase: .ended), context: history).commit, .forward)
    }

    func testRepeatedContactsDoNotReuseDirectionProgressOrOwner() {
        var machine = Machine()
        for index in 0..<30 {
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            _ = machine.handle(.init(phase: .began), context: history)
            let candidate = machine.handle(.init(deltaX: direction * 80, phase: .changed), context: history)
            XCTAssertTrue(candidate.didArm)
            let expected: Machine.Action = direction > 0 ? .back : .forward
            XCTAssertEqual(candidate.snapshot.action, expected)
            XCTAssertEqual(machine.handle(.init(phase: .ended), context: history).commit, expected)
        }
    }

    func testMalformedDeltasDoNotPoisonLaterContactOrThresholds() {
        var machine = Machine()
        let malformed = machine.handle(.init(deltaX: .nan, deltaY: .infinity, phase: .began), context: history)
        XCTAssertEqual(malformed.snapshot.axis, .undecided)
        let recovered = machine.handle(.init(deltaX: 100, phase: .changed), context: history)
        XCTAssertTrue(recovered.snapshot.offset.isFinite)
        XCTAssertEqual(machine.handle(.init(phase: .ended), context: history).commit, .back)
        XCTAssertEqual(Machine.fullscreenActivationDistance(height: .nan), 138)
        XCTAssertEqual(Machine.fullscreenActivationDistance(height: 200), 100)
        XCTAssertEqual(Machine.fullscreenActivationDistance(height: 2_000), 160)
    }
}
