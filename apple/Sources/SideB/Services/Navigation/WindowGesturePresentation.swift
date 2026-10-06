import Observation
import SwiftUI

/// Per-window compositor state. Observe the continuously changing values only in
/// the indicator/motion hosts, never in the shell, player model or catalog feed.
@MainActor
@Observable
final class WindowGesturePresentation {
    struct HorizontalSnapshot: Equatable {
        enum Direction: Equatable { case back, forward }

        let direction: Direction
        let title: String
        let progress: CGFloat
        let offset: CGFloat
        let available: Bool
        let armed: Bool

        init(direction: Direction, title: String, progress: CGFloat, offset: CGFloat,
             available: Bool, armed: Bool) {
            self.direction = direction
            self.title = title
            self.progress = WindowGesturePresentation.unitProgress(progress)
            self.offset = offset.isFinite ? max(0, offset) : 0
            self.available = available
            self.armed = available && armed
        }
    }

    enum FullscreenStage: Equatable { case idle, pulling, returning, closing }

    /// Injection lets cancellation tests resolve real completion callbacks in an
    /// arbitrary order, without creating a window or depending on timer sleeps.
    typealias SettlementAnimator = (_ animation: Animation?, _ updates: () -> Void,
                                   _ completion: @escaping () -> Void) -> Void

    private(set) var horizontal: HorizontalSnapshot?
    private(set) var horizontalVisible = false
    private(set) var fullscreenOffset: CGFloat = 0
    private(set) var fullscreenProgress: CGFloat = 0
    private(set) var fullscreenArmed = false
    private(set) var fullscreenStage: FullscreenStage = .idle
    /// Changes once when contact actually starts moving, and once after resolution.
    /// The underlying page may observe this flag without observing each delta.
    private(set) var revealUnderlying = false

    var fullscreenIsBusy: Bool { fullscreenStage != .idle }

    @ObservationIgnored private var horizontalGeneration: UInt64 = 0
    @ObservationIgnored private var horizontalRemovalTask: Task<Void, Never>?
    @ObservationIgnored private var fullscreenGeneration: UInt64 = 0
    @ObservationIgnored private let animateSettlement: SettlementAnimator

    init(animateSettlement: @escaping SettlementAnimator = { animation, updates, completion in
        withAnimation(animation, completionCriteria: .removed, updates, completion: completion)
    }) {
        self.animateSettlement = animateSettlement
    }

    func updateHorizontal(_ snapshot: HorizontalSnapshot) {
        horizontalGeneration &+= 1
        horizontalRemovalTask?.cancel()
        horizontalRemovalTask = nil
        withoutAnimation {
            horizontal = snapshot
            horizontalVisible = true
        }
    }

    /// Retain the candidate while its capsule fades, instead of removing the
    /// layout/content at release. A new gesture interrupts this fade immediately.
    func finishHorizontal(reduceMotion: Bool) {
        guard horizontal != nil else { return }
        horizontalGeneration &+= 1
        let generation = horizontalGeneration
        horizontalRemovalTask?.cancel()
        withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.16)) {
            horizontalVisible = false
        }
        horizontalRemovalTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 160)) }
            catch { return }
            guard let self, self.horizontalGeneration == generation else { return }
            self.horizontal = nil
            self.horizontalRemovalTask = nil
        }
    }

    func resetHorizontal() {
        horizontalGeneration &+= 1
        horizontalRemovalTask?.cancel()
        horizontalRemovalTask = nil
        withoutAnimation {
            horizontal = nil
            horizontalVisible = false
        }
    }

    func beginFullscreenPull() {
        guard fullscreenStage == .idle else { return }
        fullscreenGeneration &+= 1
        withoutAnimation {
            fullscreenStage = .pulling
            fullscreenArmed = false
        }
    }

    func updateFullscreenPull(offset: CGFloat, progress: CGFloat, armed: Bool) {
        guard fullscreenStage == .pulling else { return }
        let offset = offset.isFinite ? max(0, offset) : 0
        withoutAnimation {
            fullscreenOffset = offset
            fullscreenProgress = Self.unitProgress(progress)
            fullscreenArmed = armed
            if offset > 0, !revealUnderlying { revealUnderlying = true }
        }
    }

    func settleFullscreen(shouldClose: Bool, travel: CGFloat, reduceMotion: Bool,
                          onClosed: @escaping @MainActor () -> Void) {
        guard fullscreenStage == .pulling else { return }
        fullscreenGeneration &+= 1
        let generation = fullscreenGeneration
        fullscreenStage = shouldClose ? .closing : .returning
        fullscreenArmed = false
        let distance = travel.isFinite ? max(1, travel) : 1
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.12)
            : shouldClose ? .easeOut(duration: 0.24)
                : .spring(response: 0.3, dampingFraction: 0.86)
        animateSettlement(animation, {
            fullscreenOffset = shouldClose ? distance : 0
            fullscreenProgress = shouldClose ? 1 : 0
        }, { [weak self] in
            guard let self, self.fullscreenGeneration == generation else { return }
            self.fullscreenGeneration &+= 1
            // Finish after the compositor reaches its endpoint. External closure
            // or a reset invalidates this callback and cannot dismiss a later pull.
            self.withoutAnimation {
                if shouldClose { onClosed() }
                self.fullscreenOffset = 0
                self.fullscreenProgress = 0
                self.fullscreenArmed = false
                self.revealUnderlying = false
                self.fullscreenStage = .idle
            }
        })
    }

    func resetFullscreen() {
        fullscreenGeneration &+= 1
        withoutAnimation {
            fullscreenOffset = 0
            fullscreenProgress = 0
            fullscreenArmed = false
            revealUnderlying = false
            fullscreenStage = .idle
        }
    }

    nonisolated private static func unitProgress(_ value: CGFloat) -> CGFloat {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    private func withoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }
}
