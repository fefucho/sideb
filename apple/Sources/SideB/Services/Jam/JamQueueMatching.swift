import Foundation
import SideBCore

/// Outcome of one queue lookup. Only a search that actually completed can say "no match".
enum JamLookupResult {
    case matched(SongItemRecord, score: Double)
    /// The search completed and nothing was confident enough.
    case noMatch(candidateCount: Int, bestScore: Double?)
    /// The search threw (network, rate limit, cancellation, core not ready): nothing is known.
    case failed(String)
}

enum JamLookup {
    /// Decides what a finished search means. A thrown error (cancellation included) is never a
    /// "no match"; an empty successful result is.
    static func result(of search: Result<[JamMatcher.Candidate], Error>, override: String?) -> JamLookupResult {
        switch search {
        case .failure(let error):
            return .failed(error is CancellationError ? "cancelled" : String(describing: error))
        case .success(let ranked):
            if let best = ranked.first, best.isConfident || override == best.song.videoId {
                return .matched(best.song, score: best.score)
            }
            return .noMatch(candidateCount: ranked.count, bestScore: ranked.first?.score)
        }
    }
}

/// Chooses which Jam tracks to look up next: the nearest `eagerCount` as fast as the concurrency
/// allows, the rest one at a time at a low steady rate. Pure so the ordering can be tested.
enum JamMatchPlanner {
    static let eagerCount = 15
    static let maxConcurrent = 3
    /// Minimum gap between lookups of tracks beyond the eager window.
    static let backgroundInterval: TimeInterval = 1.5
    static let maxAttempts = 6

    /// Wait after the n-th failed attempt (1-based).
    static func backoff(afterAttempt attempt: Int) -> TimeInterval {
        [2, 5, 15, 30, 60][min(max(attempt, 1), 5) - 1]
    }

    struct Plan: Equatable {
        var start: [String] = []
        /// True when one of `start` is beyond the eager window.
        var startsBackground = false
        /// When to plan again if nothing else triggers it (a retry or the background pace).
        var wakeAfter: TimeInterval?
    }

    static func plan(queue: [String], settled: Set<String>, inFlight: Set<String>, attempts: [String: Int],
                     retryAt: [String: Date], lastBackgroundStart: Date, now: Date) -> Plan {
        var plan = Plan()
        var free = maxConcurrent - inFlight.count
        var seen = Set<String>()
        func wake(_ delay: TimeInterval) { plan.wakeAfter = min(plan.wakeAfter ?? delay, max(0.05, delay)) }
        for (position, uri) in queue.enumerated() {
            guard free > 0 else { break }
            guard seen.insert(uri).inserted, !settled.contains(uri), !inFlight.contains(uri) else { continue }
            guard attempts[uri, default: 0] < maxAttempts else { continue }
            if let due = retryAt[uri], due > now { wake(due.timeIntervalSince(now)); continue }
            if position >= eagerCount {
                if plan.startsBackground { break }
                let ready = lastBackgroundStart.addingTimeInterval(backgroundInterval)
                if ready > now { wake(ready.timeIntervalSince(now)); break }
                plan.startsBackground = true
            }
            plan.start.append(uri)
            free -= 1
        }
        return plan
    }
}
