import Testing
@testable import SideB

@Suite("Jam: sync engine")
struct JamSyncEngineTests {
    /// Simulated player: position advances at `rate`; the Jam target advances at 1x.
    struct Sim {
        var engine = JamSyncEngine()
        var drift: Double
        var rate = 1.0
        var rateWorks = true
        var seekLanding = -0.12
        var noise = 0.0
        var now = 1000.0
        var adjustingTime = 0.0
        var maxAdjustingTime = 0.0
        var seeks = 0
        var bursts = 0
        var reopened = false
        private var tickIndex = 0

        init(drift: Double) { self.drift = drift }

        /// One 100 ms tick; returns the action the engine took.
        @discardableResult
        mutating func step(advancing: Bool = true) -> JamSyncEngine.Action {
            tickIndex += 1
            let jitter = noise == 0 ? 0 : noise * (tickIndex % 2 == 0 ? 1 : -1)
            let wasAdjusting = engine.isAdjusting
            let action = engine.tick(drift: drift + jitter, now: now, advancing: advancing)
            if engine.didReopen { reopened = true }
            switch action {
            case .none: break
            case .seek(let compensation):
                seeks += 1
                drift = compensation + seekLanding
            case .setRate(let value):
                if value != 1 { bursts += 1 }
                rate = Double(value)
            case .lock: rate = 1
            }
            if advancing {
                if rateWorks { drift += (rate - 1) * 0.1 }
                if wasAdjusting || engine.isAdjusting { adjustingTime += 0.1 }
                if !engine.isAdjusting { maxAdjustingTime = max(maxAdjustingTime, adjustingTime); adjustingTime = 0 }
            }
            now += 0.1
            return action
        }
    }

    @Test("Converges with a player where rate works")
    func convergesWhenRateWorks() {
        for start in [0.12, -0.12, 0.2, -0.3, 0.9] {
            var sim = Sim(drift: start)
            sim.engine.begin()
            for _ in 0..<120 { sim.step() }
            #expect(!sim.engine.isAdjusting)
            #expect(abs(sim.drift) <= 0.05, "start \(start) ended at \(sim.drift)")
            #expect(sim.rate == 1)
            #expect(sim.engine.lastSummary != nil)
        }
    }

    @Test("Gives up and locks when rate has no effect")
    func givesUpWhenRateIsIneffective() {
        var sim = Sim(drift: 0.15)
        sim.rateWorks = false
        sim.engine.begin()
        var ticks = 0
        while sim.engine.isAdjusting, ticks < 200 { sim.step(); ticks += 1 }
        #expect(!sim.engine.isAdjusting)
        #expect(Double(ticks) * 0.1 <= 8)
        #expect(sim.engine.rateIneffective)
        #expect(sim.engine.lastSummary?.reason == .accepted || sim.engine.lastSummary?.reason == .finalSeek)
        #expect(abs(sim.engine.lastSummary?.residualMs ?? 0) <= 200)
        #expect(sim.rate == 1)
        // Nothing further happens after the lock.
        for _ in 0..<100 { #expect(sim.step() == .none) }
    }

    @Test("A window never exceeds 8 s for a range of initial drifts, even if nothing works")
    func neverExceedsHardCap() {
        for start in stride(from: -2.0, through: 2.0, by: 0.05) {
            for worksRate in [true, false] {
                var sim = Sim(drift: start)
                sim.rateWorks = worksRate
                sim.seekLanding = 0.4   // seeks keep landing far off
                sim.engine.begin()
                for _ in 0..<150 { sim.step() }
                #expect(sim.maxAdjustingTime <= 8.0 + 1e-6, "start \(start) rateWorks \(worksRate): \(sim.maxAdjustingTime)")
                #expect(!sim.engine.isAdjusting)
            }
        }
    }

    @Test("Noise of 30 ms while locked never reopens a window")
    func noiseDoesNotReopen() {
        var sim = Sim(drift: 0.01)
        sim.engine.begin()
        for _ in 0..<30 { sim.step() }
        #expect(!sim.engine.isAdjusting)
        sim.noise = 0.03
        sim.drift = 0.02
        for _ in 0..<2000 { sim.step() }
        #expect(!sim.reopened)
        #expect(!sim.engine.isAdjusting)
    }

    @Test("A sustained large drift reopens a window, at most once every 20 s")
    func sustainedDriftReopens() {
        var sim = Sim(drift: 0.0)
        sim.engine.begin()
        for _ in 0..<30 { sim.step() }
        sim.rateWorks = false
        sim.drift = 0.6
        var reopens = 0
        for _ in 0..<400 {
            sim.step()
            if sim.engine.didReopen { reopens += 1 }
        }
        #expect(reopens >= 1)
        #expect(reopens <= 2)   // 40 s of simulated time
    }

    @Test("Buffering time is not counted and produces no actions")
    func bufferingIsNotCounted() {
        var sim = Sim(drift: 0.15)
        sim.engine.begin()
        sim.step()
        for _ in 0..<600 { #expect(sim.step(advancing: false) == .none) }   // 60 s stalled
        #expect(sim.engine.isAdjusting)
        for _ in 0..<120 { sim.step() }
        #expect(!sim.engine.isAdjusting)
        #expect((sim.engine.lastSummary?.duration ?? 99) < 8)
    }

    @Test("Seek landing bias is learned and kept across windows")
    func learnsSeekBias() {
        var sim = Sim(drift: 1.0)
        sim.seekLanding = -0.2
        sim.engine.begin()
        for _ in 0..<80 { sim.step() }
        #expect(abs(sim.engine.seekBias + 0.2) < 0.05)
        let learned = sim.engine.seekBias
        sim.drift = 1.0
        sim.engine.begin()
        var first: JamSyncEngine.Action = .none
        for _ in 0..<10 {
            let action = sim.step()
            if case .seek = action { first = action; break }
        }
        if case .seek(let compensation) = first { #expect(abs(compensation + learned) < 1e-9) } else { Issue.record("no seek") }
    }
}
