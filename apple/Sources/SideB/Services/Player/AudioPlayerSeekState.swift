import Foundation

public enum AudioPlayerSeekPhase: Equatable, Sendable {
    case idle
    case pending
    case completed
    case failed
    case cancelled
}

/// Discrete changes to the actual AVPlayer seek request. A pending target is a fixed
/// preview, never a second media clock; completion/failure returns to measured time.
public struct AudioPlayerSeekSnapshot: Equatable, Sendable {
    public let revision: UInt64
    public let playbackID: UUID?
    public let phase: AudioPlayerSeekPhase
    public let targetSeconds: Double?
    public let mediaSeconds: Double?

    public static let idle = AudioPlayerSeekSnapshot()

    public init(revision: UInt64 = 0, playbackID: UUID? = nil,
                phase: AudioPlayerSeekPhase = .idle, targetSeconds: Double? = nil,
                mediaSeconds: Double? = nil) {
        self.revision = revision
        self.playbackID = playbackID
        self.phase = phase
        self.targetSeconds = targetSeconds
        self.mediaSeconds = mediaSeconds
    }

    public var pendingTargetSeconds: Double? { phase == .pending ? targetSeconds : nil }
}

/// Pure request ownership and pending-preview policy, shared by callbacks and the
/// service's existing progress observer. No output latency or post-seek floor is assumed.
struct AudioPlayerSeekState {
    struct Ticket: Equatable, Sendable {
        let requestID: UUID
        let itemGeneration: UUID
        let playbackID: UUID?
        let targetSeconds: Double
    }

    /// Application timeout for an unresolved preview, checked by observations and one
    /// cancellation deadline in the service (also effective while playback is paused).
    /// It does not imply a CoreAudio preroll or an accuracy tolerance.
    static let maximumPendingInterval: TimeInterval = 5

    private(set) var snapshot: AudioPlayerSeekSnapshot = .idle
    private(set) var pendingTicket: Ticket?
    private var pendingSince: TimeInterval?
    private var lastMeasuredSeconds: Double?

    mutating func begin(targetSeconds: Double, playbackID: UUID?, itemGeneration: UUID,
                        mediaSeconds: Double?, now: TimeInterval) -> Ticket {
        let ticket = Ticket(requestID: UUID(), itemGeneration: itemGeneration,
                            playbackID: playbackID, targetSeconds: targetSeconds)
        pendingTicket = ticket
        pendingSince = now
        rememberMedia(mediaSeconds)
        publish(playbackID: playbackID, phase: .pending, target: targetSeconds, media: lastMeasuredSeconds)
        return ticket
    }

    @discardableResult
    mutating func complete(_ ticket: Ticket, finished: Bool, mediaSeconds: Double?) -> Bool {
        guard pendingTicket == ticket else { return false }
        pendingTicket = nil
        pendingSince = nil
        rememberMedia(mediaSeconds)
        publish(playbackID: ticket.playbackID, phase: finished ? .completed : .failed,
                target: ticket.targetSeconds, media: lastMeasuredSeconds)
        return true
    }

    /// Cancellation invalidates the ticket even when another occurrence uses the same
    /// URL/target. Replacing an item or stopping cannot accept its eventual callback.
    mutating func reset(playbackID: UUID?, mediaSeconds: Double?) {
        let cancelled = pendingTicket != nil
        let target = pendingTicket?.targetSeconds
        pendingTicket = nil
        pendingSince = nil
        lastMeasuredSeconds = Self.validMediaSeconds(mediaSeconds)
        publish(playbackID: playbackID, phase: cancelled ? .cancelled : .idle,
                target: target, media: lastMeasuredSeconds)
    }

    mutating func sampledPosition(mediaSeconds: Double?, now: TimeInterval) -> Double? {
        rememberMedia(mediaSeconds)
        guard let pending = pendingTicket else { return Self.validMediaSeconds(mediaSeconds) }
        if let since = pendingSince, now.isFinite, since.isFinite,
           now - since >= Self.maximumPendingInterval {
            _ = complete(pending, finished: false, mediaSeconds: mediaSeconds)
            return lastMeasuredSeconds
        }
        return pending.targetSeconds
    }

    static func validMediaSeconds(_ seconds: Double?) -> Double? {
        guard let seconds, seconds.isFinite else { return nil }
        return max(0, seconds)
    }

    private mutating func rememberMedia(_ seconds: Double?) {
        if let seconds = Self.validMediaSeconds(seconds) { lastMeasuredSeconds = seconds }
    }

    private mutating func publish(playbackID: UUID?, phase: AudioPlayerSeekPhase,
                                  target: Double?, media: Double?) {
        snapshot = .init(revision: snapshot.revision &+ 1, playbackID: playbackID,
                         phase: phase, targetSeconds: target,
                         mediaSeconds: Self.validMediaSeconds(media))
    }
}

enum AudioPlayerSeekBounds {
    /// The finite duration already adopted by playback defines the song timeline.
    /// AVPlayer can expose a short, provisional range while its HTTP asset loads; it must
    /// not turn every lyric cue into a seek to the beginning. Only a stream without
    /// a finite duration uses seekable ranges as an available playback window.
    static func target(seconds: Double, duration: Double,
                       seekableRanges: [ClosedRange<Double>] = []) -> Double? {
        guard seconds.isFinite else { return nil }
        let validDuration = duration.isFinite && duration > 0 ? duration : nil
        let target = min(max(0, seconds), validDuration ?? .greatestFiniteMagnitude)
        if validDuration != nil { return target }
        let ranges = seekableRanges.compactMap { range -> ClosedRange<Double>? in
            guard range.lowerBound.isFinite, range.upperBound.isFinite,
                  range.upperBound > range.lowerBound, range.upperBound > 0 else { return nil }
            let lower = max(0, range.lowerBound)
            let upper = min(range.upperBound, validDuration ?? .greatestFiniteMagnitude)
            return upper >= lower ? lower...upper : nil
        }
        guard !ranges.isEmpty, !ranges.contains(where: { $0.contains(target) }) else { return target }
        return ranges.flatMap { [$0.lowerBound, $0.upperBound] }.min {
            let leftDistance = abs($0 - target)
            let rightDistance = abs($1 - target)
            return leftDistance != rightDistance ? leftDistance < rightDistance : $0 < $1
        }
    }
}
