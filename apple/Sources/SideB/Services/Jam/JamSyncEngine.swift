import Foundation

/// Pure state machine that decides how to bring the local audio onto the Jam's position.
///
/// It owns no clock and touches no player: every tick receives the measured drift, a monotonic
/// timestamp and whether the player is really advancing, and returns what the caller must do.
/// The shape of a correction is deliberately rigid: a short window after a real change, a seek
/// for big gaps, fixed-rate bursts for small ones, then LOCK (hands off) or give up. It never
/// keeps correcting for the whole track.
struct JamSyncEngine {
    /// Every threshold lives here so tuning is a one-place change.
    enum Tuning {
        /// |drift| (s) at or below which the position is considered matched.
        static let lockDrift = 0.025
        /// Residual (s) accepted when the budget is used up.
        static let acceptableResidual = 0.2
        /// |drift| (s) above which a seek is used instead of a rate burst.
        static let seekThreshold = 0.25
        /// Time (s) to wait after a seek before judging the result.
        static let seekSettle = 0.8
        static let maxSeeksPerWindow = 2
        /// Fixed rate offset of a burst (0.05 = 0.95x or 1.05x).
        static let burstRateDelta = 0.05
        static let burstMaxDuration = 3.0
        static let burstMinDuration = 0.15
        /// Time (s) at rate 1.0 after a burst before re-measuring.
        static let burstSettle = 0.3
        static let maxBurstsPerWindow = 2
        /// A burst that removes less than this fraction of the drift marks rate correction ineffective.
        static let minBurstImprovement = 0.4
        /// Window budget (s): afterwards the engine finalizes (accept or last seek).
        static let windowBudget = 6.0
        /// Absolute cap (s) of one window; it locks unconditionally here.
        static let hardCap = 8.0
        /// A locked engine reopens only for |drift| (s) above this sustained for `reopenSustain`.
        static let reopenDrift = 0.35
        static let reopenSustain = 1.5
        static let reopenCooldown = 20.0
        /// Number of drift samples whose median drives decisions.
        static let sampleCount = 3
        /// Learned seek landing bias is clamped to +/- this (s).
        static let maxSeekBias = 0.5
        /// Prior for the seek landing bias (s): a seek tends to land behind, so aim slightly ahead.
        static let initialSeekBias = -0.1
        /// Longest time step (s) a single tick may add to the engine clock.
        static let maxStep = 0.5
    }

    enum Action: Equatable {
        case none
        /// Seek to `target + compensation` (seconds).
        case seek(compensation: Double)
        /// Set the player rate and leave it unchanged until told otherwise.
        case setRate(Float)
        /// Rate back to 1.0; stop touching the audio.
        case lock
    }

    enum Mode: String, Equatable {
        case locked, measuring, seeking, burst, settling
    }

    enum LockReason: String, Equatable {
        case converged, accepted, finalSeek, hardCap
    }

    struct Summary: Equatable {
        var duration: Double
        var seeks: Int
        var bursts: Int
        var residualMs: Double
        var reason: LockReason
        var rateIneffective: Bool

        var text: String {
            String(format: "%.1f s · %d seek · %d ráfagas · residuo %+.0f ms (%@)%@",
                   duration, seeks, bursts, residualMs, reason.rawValue, rateIneffective ? " · velocidad inefectiva" : "")
        }
    }

    private(set) var mode: Mode = .locked
    private(set) var lastSummary: Summary?
    private(set) var rateIneffective = false
    /// Set by the tick that reopened a window on its own (sustained drift); cleared on the next tick.
    private(set) var didReopen = false
    private(set) var seekBias = Tuning.initialSeekBias
    var isAdjusting: Bool { mode != .locked }

    private var clock = 0.0
    private var lastNow: Double?
    private var samples: [Double] = []
    private var windowStart = -Double.infinity
    private var seeks = 0
    private var bursts = 0
    private var hasLearnedBias = false
    private var itemKey: String?
    private var strayStart: Double?
    private var rate: Float = 1
    private var needsRateReset = false
    private var seekUntil = 0.0
    private var seekCompensation = 0.0
    private var lockAfterSeek = false
    private var finalSeekDone = false
    private var burstUntil = 0.0
    private var burstStartAbs = 0.0
    private var settleUntil = 0.0

    /// Opens a correction window after a real change (new track, jump, resume, nudge).
    mutating func begin() {
        mode = .measuring
        samples.removeAll()
        windowStart = clock
        seeks = 0
        bursts = 0
        finalSeekDone = false
        lockAfterSeek = false
        strayStart = nil
        if rate != 1 { needsRateReset = true }
    }

    /// Forgets the window without a summary (e.g. playback paused). Keeps learned values.
    mutating func cancel() {
        mode = .locked
        samples.removeAll()
        strayStart = nil
        if rate != 1 { needsRateReset = true }
    }

    /// A different item resets the per-item rate verdict.
    mutating func setItem(_ key: String) {
        guard key != itemKey else { return }
        itemKey = key
        rateIneffective = false
    }

    mutating func tick(drift: Double, now: Double, advancing: Bool) -> Action {
        didReopen = false
        let dt = lastNow.map { min(max(now - $0, 0), Tuning.maxStep) } ?? 0
        lastNow = now
        // Time that is not audio advancing (buffering, pending seek) neither counts nor decides.
        guard advancing, drift.isFinite else { return .none }
        clock += dt
        samples.append(drift)
        if samples.count > Tuning.sampleCount { samples.removeFirst(samples.count - Tuning.sampleCount) }
        if needsRateReset {
            needsRateReset = false
            rate = 1
            return .setRate(1)
        }
        if mode == .locked { return tickLocked() }
        return tickWindow()
    }

    // MARK: Locked

    private mutating func tickLocked() -> Action {
        guard samples.count >= Tuning.sampleCount, abs(median) > Tuning.reopenDrift else {
            strayStart = nil
            return .none
        }
        if strayStart == nil { strayStart = clock }
        if let strayStart, clock - strayStart >= Tuning.reopenSustain, clock - windowStart >= Tuning.reopenCooldown {
            begin()
            didReopen = true
        }
        return .none
    }

    // MARK: Window

    private mutating func tickWindow() -> Action {
        let elapsed = clock - windowStart
        if elapsed >= Tuning.hardCap { return finish(.hardCap) }

        switch mode {
        case .seeking:
            guard clock >= seekUntil else { return .none }
            let residual = median
            // Where the seek really landed versus where it was asked to: reused by the next seek.
            let landing = residual - seekCompensation
            let blended = hasLearnedBias ? (seekBias * 0.5 + landing * 0.5) : landing
            seekBias = min(max(blended, -Tuning.maxSeekBias), Tuning.maxSeekBias)
            hasLearnedBias = true
            if lockAfterSeek { return finish(.finalSeek) }
            mode = .measuring
        case .burst:
            guard clock >= burstUntil || elapsed >= Tuning.windowBudget else { return .none }
            mode = .settling
            settleUntil = clock + Tuning.burstSettle
            samples.removeAll()
            rate = 1
            return .setRate(1)
        case .settling:
            guard clock >= settleUntil else { return .none }
            if let latest = samples.last, burstStartAbs > 0 {
                let improvement = (burstStartAbs - abs(latest)) / burstStartAbs
                if improvement < Tuning.minBurstImprovement { rateIneffective = true }
            }
            mode = .measuring
        case .measuring, .locked:
            break
        }
        return measure(elapsed: elapsed)
    }

    private mutating func measure(elapsed: Double) -> Action {
        guard samples.count >= Tuning.sampleCount else { return .none }
        let m = median
        if abs(m) <= Tuning.lockDrift { return finish(.converged) }

        let big = abs(m) > Tuning.seekThreshold
        let exhausted = big ? seeks >= Tuning.maxSeeksPerWindow
                            : (rateIneffective || bursts >= Tuning.maxBurstsPerWindow)
        if elapsed >= Tuning.windowBudget || exhausted {
            if abs(m) <= Tuning.acceptableResidual { return finish(.accepted) }
            if finalSeekDone { return finish(.accepted) }
            finalSeekDone = true
            lockAfterSeek = true
            return startSeek()
        }
        if big { return startSeek() }
        // Fixed-rate burst: one rate, held until the drift should be gone, never adjusted midway.
        let duration = min(Tuning.burstMaxDuration, max(Tuning.burstMinDuration, abs(m) / Tuning.burstRateDelta))
        bursts += 1
        burstStartAbs = abs(m)
        burstUntil = clock + duration
        mode = .burst
        rate = Float(m > 0 ? 1 - Tuning.burstRateDelta : 1 + Tuning.burstRateDelta)
        return .setRate(rate)
    }

    private mutating func startSeek() -> Action {
        seeks += 1
        seekCompensation = -seekBias
        seekUntil = clock + Tuning.seekSettle
        mode = .seeking
        samples.removeAll()
        rate = 1
        return .seek(compensation: seekCompensation)
    }

    private mutating func finish(_ reason: LockReason) -> Action {
        lastSummary = Summary(duration: clock - windowStart, seeks: seeks, bursts: bursts,
                              residualMs: (samples.isEmpty ? 0 : median) * 1000, reason: reason,
                              rateIneffective: rateIneffective)
        mode = .locked
        rate = 1
        samples.removeAll()
        strayStart = nil
        lockAfterSeek = false
        return .lock
    }

    private var median: Double {
        let sorted = samples.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}
