import CoreGraphics
import Foundation

/// Shared horizontal and vertical layout metrics for synced and experimental lyrics.
enum LyricsLayoutMetrics {
    static let horizontalMargin: CGFloat = 20

    static func textWidth(viewportWidth: CGFloat) -> CGFloat {
        max(1, viewportWidth - horizontalMargin * 2)
    }

    static func verticalCenteringPadding(viewportHeight: CGFloat, canCenterActiveLine: Bool) -> CGFloat {
        canCenterActiveLine ? max(12, viewportHeight * 0.5) : 12
    }
}

/// Exclusive state machine owning programmatic lyric viewport scrolling.
/// Only one mode owns the viewport at any instant (`following`, `manualReading`,
/// `seek`, or `restoration`), preventing `.scrollPosition` anchor contention,
/// duplicate `scrollTo` emissions, and unanimated snaps mid-animation.
struct LyricsScrollCoordinator<Target: Hashable>: Equatable {
    enum Mode: String, Equatable, Sendable {
        case following
        case manualReading
        case seek
        case restoration
    }

    enum Reason: String, Equatable, Sendable {
        case initialRestore
        case manualAnchorRestore
        case focusAdvance
        case seek
        case resumeFollowing
        case layoutRecenter
    }

    struct Command: Equatable {
        let revision: UInt64
        let target: Target
        let reason: Reason
        let animated: Bool
        let modeAfter: Mode
    }

    private static var maxRecordedCommands: Int { 48 }

    private(set) var mode: Mode = .following
    private(set) var manualAnchor: Target?
    private(set) var lastCenteredTarget: Target?
    private(set) var revision: UInt64 = 0
    /// False until the first command of a mount. The list starts at its top, so the first
    /// centering must be immediate: animating it sweeps the whole lyric list into view.
    private(set) var hasPositioned = false
    private var playbackIdentity: UUID?
    private var animationDeadline: TimeInterval?
    private(set) var emittedCommands: [Command] = []

    var isFollowing: Bool {
        mode != .manualReading
    }

    func isAnimating(at now: TimeInterval) -> Bool {
        guard let deadline = animationDeadline else { return false }
        return now < deadline
    }

    mutating func activate(playbackIdentity: UUID) {
        if self.playbackIdentity != playbackIdentity {
            self.playbackIdentity = playbackIdentity
            hasPositioned = false
            mode = .following
            manualAnchor = nil
            lastCenteredTarget = nil
            animationDeadline = nil
            revision &+= 1
        } else {
            if mode != .manualReading {
                mode = .following
            }
            lastCenteredTarget = nil
            animationDeadline = nil
            revision &+= 1
        }
    }

    mutating func documentChanged(newOccurrence: Bool) {
        if newOccurrence {
            mode = .following
            manualAnchor = nil
            lastCenteredTarget = nil
            hasPositioned = false
        } else if mode != .manualReading {
            mode = .following
        }
        animationDeadline = nil
        revision &+= 1
    }

    /// Called when the list leaves the screen: the next mount starts at the top again.
    mutating func invalidatePending() {
        hasPositioned = false
        animationDeadline = nil
        revision &+= 1
    }

    mutating func userScrolled() {
        mode = .manualReading
        animationDeadline = nil
        revision &+= 1
    }

    mutating func recordVisibleManualAnchor(_ anchor: Target?) {
        guard mode == .manualReading, let anchor else { return }
        manualAnchor = anchor
    }

    mutating func clearCommandLog() {
        emittedCommands.removeAll(keepingCapacity: true)
    }

    mutating func restoreOnAppear(
        activeTarget: Target?,
        canFollow: Bool,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Command? {
        revision &+= 1
        animationDeadline = nil
        if mode == .manualReading {
            guard let anchor = manualAnchor else { return nil }
            return record(Command(
                revision: revision,
                target: anchor,
                reason: .manualAnchorRestore,
                animated: false,
                modeAfter: .manualReading
            ))
        }
        mode = .restoration
        guard canFollow, let target = activeTarget else {
            lastCenteredTarget = nil
            mode = .following
            return nil
        }
        lastCenteredTarget = target
        mode = .following
        return record(Command(
            revision: revision,
            target: target,
            reason: .initialRestore,
            animated: false,
            modeAfter: .following
        ))
    }

    mutating func activeTargetChanged(
        to target: Target?,
        canFollow: Bool,
        reduceMotion: Bool,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime,
        duration: TimeInterval = ExperimentalLyricsStyle.focusTransitionDuration
    ) -> Command? {
        guard canFollow, mode != .manualReading else { return nil }
        guard let target else {
            lastCenteredTarget = nil
            return nil
        }
        guard target != lastCenteredTarget else {
            if mode == .seek && !isAnimating(at: now) {
                mode = .following
            }
            return nil
        }
        revision &+= 1
        mode = .following
        lastCenteredTarget = target
        let animated = !reduceMotion && duration > 0 && hasPositioned
        animationDeadline = animated ? now + duration : nil
        return record(Command(
            revision: revision,
            target: target,
            reason: .focusAdvance,
            animated: animated,
            modeAfter: .following
        ))
    }

    mutating func seek(
        to target: Target,
        reduceMotion: Bool,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime,
        duration: TimeInterval = ExperimentalLyricsStyle.focusTransitionDuration
    ) -> Command {
        revision &+= 1
        manualAnchor = nil
        mode = .seek
        lastCenteredTarget = target
        let animated = !reduceMotion && duration > 0
        animationDeadline = animated ? now + duration : nil
        return record(Command(
            revision: revision,
            target: target,
            reason: .seek,
            animated: animated,
            modeAfter: .seek
        ))
    }

    mutating func resumeFollowing(
        activeTarget: Target?,
        reduceMotion: Bool,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime,
        duration: TimeInterval = ExperimentalLyricsStyle.focusTransitionDuration
    ) -> Command? {
        revision &+= 1
        manualAnchor = nil
        mode = .following
        guard let target = activeTarget else {
            lastCenteredTarget = nil
            animationDeadline = nil
            return nil
        }
        lastCenteredTarget = target
        let animated = !reduceMotion && duration > 0
        animationDeadline = animated ? now + duration : nil
        return record(Command(
            revision: revision,
            target: target,
            reason: .resumeFollowing,
            animated: animated,
            modeAfter: .following
        ))
    }

    mutating func recenterForLayoutChange(
        activeTarget: Target?,
        canFollow: Bool,
        reduceMotion: Bool,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime,
        duration: TimeInterval = ExperimentalLyricsStyle.focusTransitionDuration
    ) -> Command? {
        revision &+= 1
        guard canFollow, mode != .manualReading, let target = activeTarget else {
            animationDeadline = nil
            return nil
        }
        lastCenteredTarget = target
        let preserveLiveAnimation = !reduceMotion && isAnimating(at: now)
        if preserveLiveAnimation {
            animationDeadline = max(animationDeadline ?? now, now + duration * 0.5)
        } else {
            animationDeadline = nil
            if mode == .seek {
                mode = .following
            }
        }
        return record(Command(
            revision: revision,
            target: target,
            reason: .layoutRecenter,
            animated: preserveLiveAnimation,
            modeAfter: mode
        ))
    }

    func canApply(_ command: Command) -> Bool {
        if command.reason == .manualAnchorRestore {
            return mode == .manualReading && revision == command.revision
        }
        return mode != .manualReading && revision == command.revision
    }

    private mutating func record(_ command: Command) -> Command {
        hasPositioned = true
        if emittedCommands.count >= Self.maxRecordedCommands {
            emittedCommands.removeFirst(emittedCommands.count - Self.maxRecordedCommands + 1)
        }
        emittedCommands.append(command)
        return command
    }
}
