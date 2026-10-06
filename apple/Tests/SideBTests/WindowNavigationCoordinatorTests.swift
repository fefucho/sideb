import AppKit
import XCTest
@testable import SideB

@MainActor
final class WindowNavigationCoordinatorTests: XCTestCase {
    private typealias Machine = WindowGestureStateMachine

    @MainActor private final class Harness {
        let router = NavigationRouter()
        var presentation: WindowGesturePresentation!
        var coordinator: WindowNavigationCoordinator!
        var fullscreen = false
        var enabled = true
        var session = 0
        var haptics = 0
        var closed = 0
        var captures = 0
        var completions: [() -> Void] = []
        var context = Machine.Context(mode: .history, canGoBack: true, canGoForward: true)

        init(fullscreen: Bool = false) {
            self.fullscreen = fullscreen
            router.navigate(to: .explore(.discover))
            router.navigate(to: .library)
            presentation = WindowGesturePresentation(animateSettlement: { [weak self] _, update, complete in
                update()
                self?.completions.append(complete)
            })
            coordinator = WindowNavigationCoordinator(performHaptic: { [weak self] in self?.haptics += 1 },
                interactionIsAllowed: { [weak self] in self?.enabled == true })
            context.mode = fullscreen ? .fullscreen : .history
            configure()
        }

        func configure() {
            coordinator.setup(router: router, presentation: presentation,
                isFullscreenPresented: fullscreen, canHandleGestures: enabled,
                reduceMotion: true, sessionRevision: session, onDismissFullscreen: { [weak self] in
                    guard let self else { return }
                    self.closed += 1
                    self.fullscreen = false
                    self.configure()
                })
        }

        @discardableResult
        func input(_ input: Machine.Event) -> Machine.Output {
            coordinator.handleScrollInput(input, enabled: enabled) {
                captures += 1
                var start = context
                start.canGoBack = router.canGoBack
                start.canGoForward = router.canGoForward
                return start
            }
        }

        @discardableResult
        func input(_ input: Machine.Event, at point: NSPoint, in root: NSView) -> Machine.Output {
            coordinator.handleScrollInput(input, enabled: enabled) {
                captures += 1
                return coordinator.scrollContext(at: point, in: root, enabled: enabled)
            }
        }
    }

    func testActualWindowContextNavigatesOverExclusionsControlsAndHorizontalScroll() {
        let h = Harness()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        for region: WindowGestureRegion in [.excluded, .horizontalContent, .verticalContent] {
            let marker = WindowGestureRegionView(frame: root.bounds)
            marker.region = region
            root.addSubview(marker)
        }
        let carousel = NSScrollView(frame: NSRect(x: 0, y: 100, width: 900, height: 400))
        carousel.horizontalScrollElasticity = .allowed
        carousel.verticalScrollElasticity = .none
        carousel.hasHorizontalScroller = true
        carousel.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 4000, height: 400))
        root.addSubview(carousel)
        let slider = NSSlider(frame: NSRect(x: 20, y: 20, width: 200, height: 30))
        root.addSubview(slider)
        let text = NSTextField(frame: NSRect(x: 300, y: 20, width: 200, height: 40))
        text.isEditable = true
        root.addSubview(text)
        let selection = NSTextView(frame: NSRect(x: 600, y: 20, width: 200, height: 40))
        selection.string = "Selected text"
        selection.isEditable = false
        selection.isSelectable = true
        selection.setSelectedRange(NSRange(location: 0, length: 8))
        root.addSubview(selection)

        for point in [NSPoint(x: 80, y: 30), NSPoint(x: 350, y: 30), NSPoint(x: 650, y: 30),
                      NSPoint(x: 5, y: 300), NSPoint(x: 450, y: 300), NSPoint(x: 895, y: 300),
                      NSPoint(x: 450, y: 650)] {
            for direction: CGFloat in [1, -1] {
                h.input(.init(phase: .mayBegin), at: point, in: root)
                let pull = h.input(.init(deltaX: direction * 90, phase: .changed), at: point, in: root)
                XCTAssertEqual(pull.disposition, .consume, "\(point)")
                XCTAssertTrue(h.presentation.horizontalVisible, "\(point)")
                XCTAssertEqual(h.input(.init(phase: .ended), at: point, in: root).commit,
                    direction > 0 ? .back : .forward, "\(point)")
                XCTAssertEqual(h.router.currentPage, direction > 0 ? .explore(.discover) : .library)
            }
        }
        let outside = NSPoint(x: -20, y: 300)
        XCTAssertEqual(h.input(.init(deltaX: 100, phase: .began), at: outside, in: root).disposition, .passThrough)
        XCTAssertNil(h.input(.init(phase: .ended), at: outside, in: root).commit)
        h.enabled = false
        h.configure()
        let context = h.coordinator.scrollContext(at: NSPoint(x: 450, y: 300), in: root, enabled: true)
        XCTAssertFalse(context.allowsHorizontalNavigation)
        XCTAssertFalse(context.allowsFullscreenDismissal)
        XCTAssertNil(root.window)
    }

    func testAggressiveHistoryDoesNotChangeFullscreenPanelOwnershipOrMode() {
        let h = Harness(fullscreen: true)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let panel = WindowGestureRegionView(frame: NSRect(x: 450, y: 0, width: 450, height: 700))
        panel.region = .verticalContent
        root.addSubview(panel)
        let free = NSPoint(x: 200, y: 300)
        let queue = NSPoint(x: 650, y: 300)
        XCTAssertFalse(h.coordinator.scrollContext(at: free, in: root, enabled: true).allowsHorizontalNavigation)
        XCTAssertTrue(h.coordinator.scrollContext(at: free, in: root, enabled: true).allowsFullscreenDismissal)
        XCTAssertFalse(h.coordinator.scrollContext(at: queue, in: root, enabled: true).allowsFullscreenDismissal)
        h.input(.init(phase: .mayBegin), at: queue, in: root)
        XCTAssertEqual(h.input(.init(deltaY: 300, phase: .changed), at: free, in: root).disposition, .passThrough)
        XCTAssertNil(h.input(.init(phase: .ended), at: free, in: root).commit)
        XCTAssertEqual(h.presentation.fullscreenStage, .idle)
        h.input(.init(deltaX: 100, phase: .began), at: free, in: root)
        XCTAssertNil(h.input(.init(phase: .ended), at: free, in: root).commit)
        XCTAssertEqual(h.router.currentPage, .library)
        h.input(.init(deltaY: 30, phase: .began), at: free, in: root)
        XCTAssertEqual(h.presentation.fullscreenStage, .pulling)
        XCTAssertEqual(h.presentation.fullscreenOffset, 30)
        h.input(.init(phase: .ended), at: free, in: root)
        h.completions[0]()
        XCTAssertEqual(h.presentation.fullscreenStage, .idle)
        XCTAssertEqual(h.closed, 0)
        XCTAssertNil(root.window)
    }

    func testBackAndForwardCommitOnceAndNeverOnMomentum() {
        let h = Harness()
        h.input(.init(deltaX: 90, phase: .began))
        XCTAssertEqual(h.presentation.horizontal?.title, "Explorar")
        XCTAssertTrue(h.presentation.horizontalVisible)
        XCTAssertEqual(h.haptics, 1)
        h.input(.init(phase: .ended))
        XCTAssertEqual(h.router.currentPage, .explore(.discover))
        XCTAssertFalse(h.presentation.horizontalVisible)
        for phase: Machine.EventPhase in [.began, .changed, .ended] {
            XCTAssertEqual(h.input(.init(deltaX: 300, momentumPhase: phase)).disposition, .consume)
            XCTAssertEqual(h.router.currentPage, .explore(.discover))
            XCTAssertFalse(h.presentation.horizontalVisible)
        }
        h.input(.init(deltaX: -90, phase: .began))
        XCTAssertEqual(h.presentation.horizontal?.title, "Biblioteca")
        h.input(.init(phase: .ended))
        h.input(.init(phase: .ended))
        XCTAssertEqual(h.router.currentPage, .library)
        XCTAssertEqual(h.haptics, 2)
        XCTAssertEqual(h.captures, 2)
    }

    func testZeroDeltaMayBeginCapturesWindowEligibilityUntilReleaseAndNewBeganRecaptures() {
        let h = Harness()
        h.context.allowsHorizontalNavigation = false
        h.input(.init(phase: .mayBegin))
        h.context.allowsHorizontalNavigation = true
        h.input(.init(phase: .began))
        XCTAssertEqual(h.input(.init(deltaX: 100, phase: .changed)).disposition, .passThrough)
        h.input(.init(phase: .ended))
        XCTAssertEqual(h.captures, 1)
        XCTAssertEqual(h.router.currentPage, .library)
        h.input(.init(deltaX: 100, phase: .began))
        h.input(.init(phase: .ended))
        XCTAssertEqual(h.captures, 2)
        XCTAssertEqual(h.router.currentPage, .explore(.discover))
    }

    func testExternalRouteChangeCancelsAndDrainsThenNewContactUsesNewHistory() {
        let h = Harness()
        h.input(.init(deltaX: 100, phase: .began))
        h.router.navigate(to: .history)
        h.configure()
        XCTAssertNil(h.presentation.horizontal)
        XCTAssertEqual(h.input(.init(deltaX: 200, phase: .changed)).disposition, .consume)
        XCTAssertNil(h.input(.init(phase: .ended)).commit)
        XCTAssertEqual(h.router.currentPage, .history)
        h.input(.init(deltaX: 100, phase: .began))
        h.input(.init(phase: .ended))
        XCTAssertEqual(h.router.currentPage, .library)
    }

    func testSessionOrModalChangeCancelsWithoutReusingOldContact() {
        for changesSession in [false, true] {
            let h = Harness()
            h.input(.init(deltaX: 100, phase: .began))
            if changesSession { h.session += 1 } else { h.enabled = false }
            h.configure()
            XCTAssertNil(h.presentation.horizontal)
            h.input(.init(phase: .ended))
            XCTAssertEqual(h.router.currentPage, .library)
            h.enabled = true
            h.configure()
            h.input(.init(deltaX: 100, phase: .began))
            h.input(.init(phase: .ended))
            XCTAssertEqual(h.router.currentPage, .explore(.discover))
        }
    }

    func testFullscreenClosesOnlyAfterCompletionAndDrainsOldMomentumAfterModeChange() {
        let h = Harness(fullscreen: true)
        h.input(.init(deltaY: 200, phase: .began))
        XCTAssertEqual(h.presentation.fullscreenStage, .pulling)
        XCTAssertTrue(h.presentation.revealUnderlying)
        h.input(.init(phase: .ended))
        XCTAssertEqual(h.presentation.fullscreenStage, .closing)
        XCTAssertTrue(h.fullscreen)
        XCTAssertEqual(h.closed, 0)
        XCTAssertEqual(h.completions.count, 1)
        h.completions[0]()
        h.completions[0]()
        XCTAssertEqual(h.closed, 1)
        XCTAssertFalse(h.fullscreen)
        XCTAssertEqual(h.presentation.fullscreenStage, .idle)
        XCTAssertEqual(h.input(.init(deltaX: 500, momentumPhase: .changed)).disposition, .consume)
        XCTAssertEqual(h.router.currentPage, .library)
        XCTAssertEqual(h.input(.init(momentumPhase: .ended)).disposition, .consume)
        h.context.mode = .history
        h.input(.init(deltaX: 100, phase: .began))
        h.input(.init(phase: .ended))
        XCTAssertEqual(h.router.currentPage, .explore(.discover))
    }

    func testRouteSessionAndModalChangesInvalidatePendingFullscreenCompletion() {
        for reason in 0..<3 {
            let h = Harness(fullscreen: true)
            h.input(.init(deltaY: 200, phase: .began))
            h.input(.init(phase: .ended))
            if reason == 0 { h.router.navigate(to: .history) }
            if reason == 1 { h.session += 1 }
            if reason == 2 { h.enabled = false }
            h.configure()
            h.completions[0]()
            XCTAssertEqual(h.closed, 0)
            XCTAssertTrue(h.fullscreen)
            XCTAssertEqual(h.presentation.fullscreenOffset, 0)
            XCTAssertFalse(h.presentation.revealUnderlying)
        }
    }

    func testFullscreenShortPullReturnsAndVerticalPanelNeverMovesSurface() {
        let h = Harness(fullscreen: true)
        h.input(.init(deltaY: 30, phase: .began))
        h.input(.init(phase: .ended))
        XCTAssertEqual(h.presentation.fullscreenStage, .returning)
        h.completions[0]()
        XCTAssertTrue(h.fullscreen)
        XCTAssertEqual(h.closed, 0)
        h.context.verticalContentOwnsGesture = true
        h.input(.init(phase: .mayBegin))
        h.context.verticalContentOwnsGesture = false
        XCTAssertEqual(h.input(.init(deltaY: 400, phase: .changed)).disposition, .passThrough)
        h.input(.init(phase: .ended))
        XCTAssertEqual(h.presentation.fullscreenStage, .idle)
        XCTAssertFalse(h.presentation.revealUnderlying)
    }
}
