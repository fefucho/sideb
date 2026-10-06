import Foundation

/// The decision layer for one physical trackpad contact. AppKit normalizes the
/// deltas and captures the hit region; this type never reads a window or a view.
struct WindowGestureStateMachine {
    enum Mode: Equatable { case history, fullscreen }
    enum Axis: Equatable { case undecided, horizontal, vertical }
    enum Action: Equatable { case back, forward, dismissFullscreen }
    enum Disposition: Equatable { case passThrough, consume }

    enum EventPhase: Equatable {
        case none, mayBegin, began, changed, stationary, ended, cancelled
    }

    enum PresentationPhase: Equatable {
        case idle, detecting, passingThrough, pulling, armed, committed, cancelled
    }

    /// Capture at the initial mayBegin/began (even with zero deltas), or at the
    /// first changed if AppKit did not deliver a separate beginning.
    struct Context: Equatable {
        var mode: Mode
        var allowsHorizontalNavigation: Bool = true
        var allowsFullscreenDismissal: Bool = true
        var verticalContentOwnsGesture: Bool = false
        var canGoBack: Bool = false
        var canGoForward: Bool = false
        var fullscreenHeight: CGFloat = 600
    }

    struct Event: Equatable {
        /// Positive X means back; positive Y means pulling fullscreen down.
        var deltaX: CGFloat = 0
        var deltaY: CGFloat = 0
        var phase: EventPhase = .none
        var momentumPhase: EventPhase = .none
        var hasPreciseScrollingDeltas: Bool = true
    }

    struct Snapshot: Equatable {
        var action: Action? = nil
        var axis: Axis = .undecided
        var phase: PresentationPhase = .idle
        /// Nonnegative displacement in the initially selected direction.
        var offset: CGFloat = 0
        var progress: CGFloat = 0
        var threshold: CGFloat = 0
        var isAvailable: Bool = false
        var isArmed: Bool = false

        static let idle = Snapshot()
    }

    struct Output: Equatable {
        var snapshot: Snapshot
        var disposition: Disposition
        var commit: Action? = nil
        /// A single optional alignment haptic, even if the user rearms later.
        var didArm: Bool = false
    }

    static let axisThreshold: CGFloat = 10
    static let axisDominanceRatio: CGFloat = 1.35
    static let horizontalActivationDistance: CGFloat = 64
    static let disarmRatio: CGFloat = 0.72

    private struct Contact {
        let context: Context
        var isProvisionalStart: Bool
        var x: CGFloat = 0
        var y: CGFloat = 0
        var axis: Axis = .undecided
        var action: Action?
        var direction: CGFloat = 0
        var claimed = false
        var available = false
        var armed = false
        var hasArmed = false
        var invalidated = false
        var threshold: CGFloat = 0
    }

    private var contact: Contact?
    /// After release only explicit inertia/duplicate terminal events are drained.
    /// A phase-less wheel or a new contact must not be swallowed by this marker.
    private var consumesMomentum = false
    private(set) var snapshot: Snapshot = .idle

    var isTracking: Bool { contact != nil }
    var isClaimed: Bool { contact?.claimed ?? consumesMomentum }

    /// The adapter uses exactly the same start rules to capture the pointer's
    /// region and route candidate. In particular a provisional mayBegin owns
    /// its later began, while a real new began replaces an existing contact.
    func requiresStartContext(for event: Event) -> Bool {
        guard event.hasPreciseScrollingDeltas, event.momentumPhase == .none else { return false }
        switch event.phase {
        case .mayBegin:
            return contact?.isProvisionalStart != true || contact?.invalidated == true
        case .began:
            return contact?.isProvisionalStart != true || contact?.invalidated == true
        case .changed:
            return contact == nil
        default:
            return false
        }
    }

    static func fullscreenActivationDistance(height: CGFloat) -> CGFloat {
        let usableHeight = height.isFinite && height > 0 ? height : 600
        return min(160, max(100, usableHeight * 0.23))
    }

    /// Invalidate a candidate after focus/route/session/presentation changes.
    /// Claimed contact events are still drained, so cancellation cannot scroll
    /// the newly revealed page. A new began always establishes a fresh owner.
    @discardableResult
    mutating func invalidate() -> Output {
        if var current = contact {
            current.invalidated = true
            current.armed = false
            contact = current
        }
        if snapshot.action != nil {
            snapshot.phase = .cancelled
            snapshot.isArmed = false
        } else {
            snapshot = .idle
        }
        return Output(snapshot: snapshot, disposition: isClaimed ? .consume : .passThrough)
    }

    /// Explicit teardown. Unlike invalidation this drops the entire stream.
    mutating func reset() {
        contact = nil
        consumesMomentum = false
        snapshot = .idle
    }

    mutating func handle(_ event: Event, context: Context) -> Output {
        guard event.hasPreciseScrollingDeltas else {
            let cancelled = invalidate().snapshot
            reset()
            return Output(snapshot: cancelled, disposition: .passThrough)
        }

        if event.momentumPhase != .none {
            return handleMomentum(event.momentumPhase)
        }

        switch event.phase {
        case .none:
            // A wheel with no contact phases never starts or continues a gesture.
            let cancelled = invalidate().snapshot
            reset()
            return Output(snapshot: cancelled, disposition: .passThrough)

        case .mayBegin:
            if requiresStartContext(for: event) {
                begin(context, provisional: true)
            }

        case .began:
            if requiresStartContext(for: event) {
                begin(context, provisional: false)
            } else if var current = contact {
                current.isProvisionalStart = false
                contact = current
            }

        case .changed:
            if requiresStartContext(for: event) { begin(context, provisional: false) }

        case .stationary:
            guard contact != nil else { return currentOutput(disposition: .passThrough) }

        case .ended, .cancelled:
            guard contact != nil else {
                return currentOutput(disposition: consumesMomentum ? .consume : .passThrough)
            }
        }

        guard var current = contact else { return currentOutput(disposition: .passThrough) }
        if !current.invalidated, event.phase != .cancelled {
            update(&current, deltaX: event.deltaX, deltaY: event.deltaY)
        }

        let didArm = current.armed && !current.hasArmed
        current.hasArmed = current.hasArmed || current.armed
        contact = current
        if !current.invalidated { snapshot = presentation(for: current) }

        let disposition: Disposition = current.claimed ? .consume : .passThrough
        if event.phase == .ended || event.phase == .cancelled {
            let commit = event.phase == .ended && !current.invalidated && current.armed
                ? current.action : nil
            if current.action != nil {
                snapshot.phase = commit == nil ? .cancelled : .committed
                snapshot.isArmed = commit != nil
            } else {
                snapshot = .idle
            }
            consumesMomentum = current.claimed
            contact = nil
            return Output(snapshot: snapshot, disposition: disposition, commit: commit, didArm: didArm)
        }
        return Output(snapshot: snapshot, disposition: disposition, didArm: didArm)
    }

    private mutating func begin(_ context: Context, provisional: Bool) {
        contact = Contact(context: context, isProvisionalStart: provisional)
        consumesMomentum = false
        snapshot = Snapshot(phase: .detecting)
    }

    private mutating func handleMomentum(_ phase: EventPhase) -> Output {
        // Contact unexpectedly followed by inertia without a release: cancel it,
        // never convert momentum into a release/commit or use it for progress.
        if let current = contact {
            consumesMomentum = current.claimed
            if current.action != nil {
                snapshot.phase = .cancelled
                snapshot.isArmed = false
            } else {
                snapshot = .idle
            }
            contact = nil
        }
        let disposition: Disposition = consumesMomentum ? .consume : .passThrough
        if phase == .ended || phase == .cancelled { consumesMomentum = false }
        return currentOutput(disposition: disposition)
    }

    private func currentOutput(disposition: Disposition) -> Output {
        Output(snapshot: snapshot, disposition: disposition)
    }

    private func update(_ current: inout Contact, deltaX: CGFloat, deltaY: CGFloat) {
        // Malformed/synthetic deltas must not poison subsequent finite movement.
        current.x = min(1_000_000, max(-1_000_000, current.x + (deltaX.isFinite ? deltaX : 0)))
        current.y = min(1_000_000, max(-1_000_000, current.y + (deltaY.isFinite ? deltaY : 0)))

        if current.axis == .undecided {
            let x = abs(current.x)
            let y = abs(current.y)
            guard max(x, y) >= Self.axisThreshold else { return }
            if x > y * Self.axisDominanceRatio {
                current.axis = .horizontal
            } else if y > x * Self.axisDominanceRatio {
                current.axis = .vertical
            } else {
                // A deliberate diagonal remains undecided, rather than becoming
                // a permanently vertical gesture after its first few pixels.
                return
            }
            selectAction(&current)
        }

        guard current.claimed, current.available else { return }
        let distance = projectedDistance(current)
        if current.armed {
            if distance < current.threshold * Self.disarmRatio { current.armed = false }
        } else if distance >= current.threshold {
            current.armed = true
        }
    }

    private func selectAction(_ current: inout Contact) {
        switch (current.context.mode, current.axis) {
        case (.history, .horizontal):
            guard current.context.allowsHorizontalNavigation else { return }
            current.direction = current.x > 0 ? 1 : -1
            current.action = current.direction > 0 ? .back : .forward
            current.available = current.direction > 0 ? current.context.canGoBack : current.context.canGoForward
            current.threshold = Self.horizontalActivationDistance

        case (.fullscreen, .vertical):
            guard current.context.allowsFullscreenDismissal,
                  !current.context.verticalContentOwnsGesture,
                  current.y > 0 else { return }
            current.direction = 1
            current.action = .dismissFullscreen
            current.available = true
            current.threshold = Self.fullscreenActivationDistance(height: current.context.fullscreenHeight)

        default:
            return
        }
        current.claimed = true
    }

    private func projectedDistance(_ current: Contact) -> CGFloat {
        let movement = current.axis == .horizontal ? current.x * current.direction : current.y
        // The selected action is fixed. Reversal through zero cannot arm the
        // opposite history entry or turn an upward contact into dismissal.
        return max(0, movement)
    }

    private func presentation(for current: Contact) -> Snapshot {
        guard current.claimed else {
            return Snapshot(axis: current.axis, phase: current.axis == .undecided ? .detecting : .passingThrough)
        }
        let distance = projectedDistance(current)
        let offset: CGFloat
        if !current.available {
            offset = min(18, distance)
        } else if current.action == .dismissFullscreen {
            let height = current.context.fullscreenHeight
            offset = min(height.isFinite && height > 0 ? height : 600, distance)
        } else {
            offset = distance
        }
        return Snapshot(
            action: current.action,
            axis: current.axis,
            phase: current.armed ? .armed : .pulling,
            offset: offset,
            progress: current.available ? min(1, distance / current.threshold) : 0,
            threshold: current.threshold,
            isAvailable: current.available,
            isArmed: current.armed
        )
    }
}
