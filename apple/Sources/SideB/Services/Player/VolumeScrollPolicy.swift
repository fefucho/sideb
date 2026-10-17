import Foundation

/// Raw AppKit deltas: the operating system has already applied scroll direction.
/// One contact owns its complete tail, even after leaving the eligible surface.
struct VolumeScrollPolicy {
    enum Zone: Equatable { case capsule, fullscreen }
    typealias Phase = WindowGestureStateMachine.EventPhase
    struct Input {
        var x: Double = 0
        var y: Double = 0
        var precise = true
        var phase: Phase = .none
        var momentum: Phase = .none
        var modified = false
        var timestamp: TimeInterval = 0
    }
    struct Output {
        var consume = false
        var steps = 0
        var feedback: Zone?
        var finished = false
    }
    private enum Owner { case idle, candidate, outside, volume, draining }
    private var owner = Owner.idle
    private var zone: Zone?
    private var remainder = 0.0
    private var lastTime: TimeInterval?
    private var lastInputHadPhases = false
    var isOwned: Bool { owner == .volume || owner == .draining }
    var ownedZone: Zone? { owner == .volume ? zone : nil }
    func requiresPointerValidation(at timestamp: TimeInterval) -> Bool {
        guard owner == .volume || owner == .candidate else { return false }
        return lastInputHadPhases || timestamp - (lastTime ?? 0) <= 0.18
    }

    mutating func invalidate() {
        if isOwned { owner = .draining } else if owner != .idle { owner = .outside }
        remainder = 0
    }

    mutating func reset() { self = Self() }

    mutating func handle(_ input: Input, zone currentZone: Zone?, value: Float) -> Output {
        let terminal = input.phase == .ended || input.phase == .cancelled
        if input.momentum != .none {
            let consumed = isOwned
            if input.momentum == .ended || input.momentum == .cancelled { reset() }
            return .init(consume: consumed, finished: true)
        }
        let phased = input.phase != .none
        let fresh = input.phase == .began || input.phase == .mayBegin ||
            (!phased && (!input.precise || lastTime == nil || input.timestamp - (lastTime ?? 0) > 0.18))
        if fresh { reset() }
        if owner == .idle {
            zone = currentZone
            owner = currentZone == nil || input.modified ? .outside : .candidate
        }
        lastTime = input.timestamp
        lastInputHadPhases = phased
        if owner == .volume && (zone != currentZone || input.modified) { invalidate() }
        if owner == .candidate && (zone != currentZone || input.modified) { owner = .outside }
        if terminal {
            let consumed = isOwned
            remainder = 0
            // Keep ownership until momentum ends or a fresh contact starts.
            owner = consumed ? .draining : .outside
            return .init(consume: consumed, finished: true)
        }
        if owner == .draining { return .init(consume: true) }
        guard owner != .outside, input.x.isFinite, input.y.isFinite else {
            if isOwned { invalidate(); return .init(consume: true) }
            owner = .outside
            return .init()
        }
        let vertical = abs(input.y) > 1.25 * abs(input.x) && abs(input.y) > (input.precise ? 0.1 : 0)
        if owner == .candidate {
            guard vertical else {
                // A zero mayBegin waits for intent; a real horizontal contact stays outside.
                if abs(input.x) > 0.1 || abs(input.y) > 0.1 { owner = .outside }
                return .init()
            }
            owner = .volume
        }
        guard vertical else { return .init(consume: true) }
        let direction = input.y > 0 ? 1 : -1
        let atLimit = (value >= 1 && direction > 0) || (value <= 0 && direction < 0)
        if atLimit {
            remainder = 0
            if !input.precise && !phased { owner = .draining }
            return .init(consume: true, feedback: zone, finished: !input.precise)
        }
        if !input.precise {
            if !phased { owner = .draining }
            return .init(consume: true, steps: direction, feedback: zone, finished: true)
        }
        if remainder * input.y < 0 { remainder = 0 }
        remainder = min(800, max(-800, remainder + input.y))
        let steps = Int((remainder / 8).rounded(.towardZero))
        remainder -= Double(steps) * 8
        return .init(consume: true, steps: steps, feedback: zone)
    }

    static func adjusting(_ value: Float, by steps: Int) -> Float {
        guard value.isFinite else { return value }
        let result = Double(value) + Double(steps) * 0.01
        if result <= 0.000001 { return 0 }
        if result >= 0.999999 { return 1 }
        return Float(result)
    }
}
