import Foundation
import SideBCore
import Testing
@testable import SideB

private func song(_ id: String, _ title: String, _ artists: String, _ duration: String) -> SongItemRecord {
    SongItemRecord(videoId: id, title: title, artists: artists, album: nil, duration: duration,
                   thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil, isVideo: false, isUpload: false,
                   library: nil, artistRuns: [], contentRating: .unknown)
}

private func track(_ title: String, _ artists: [String], ms: Double) -> JamTrack {
    JamTrack(uri: "spotify:track:x", title: title, artists: artists, album: nil, durationMs: ms, isrc: nil, provider: nil)
}

private struct SearchFailure: Error {}

@Suite("Jam: queue lookup outcome")
struct JamLookupResultTests {
    @Test("A thrown error or a cancellation is a failure, never 'no match'")
    func errorsAreNotNoMatch() {
        for error in [SearchFailure() as Error, CancellationError(), JamLookupError.coreNotReady] {
            guard case .failed = JamLookup.result(of: .failure(error), override: nil) else {
                Issue.record("expected failed for \(error)")
                return
            }
        }
    }

    @Test("An empty but successful search is 'no match'")
    func emptyIsNoMatch() {
        guard case .noMatch(let count, let best) = JamLookup.result(of: .success([]), override: nil) else {
            Issue.record("expected noMatch"); return
        }
        #expect(count == 0)
        #expect(best == nil)
    }

    @Test("A low-score result is 'no match' with count and best score; an override wins")
    func lowScore() {
        let ranked = JamMatcher.rank(track: track("Sorry", ["Justin Bieber"], ms: 200786),
                                     candidates: [song("x", "Other", "Someone", "1:00")])
        guard case .noMatch(let count, let best) = JamLookup.result(of: .success(ranked), override: nil) else {
            Issue.record("expected noMatch"); return
        }
        #expect(count == 1)
        #expect(best != nil)
        guard case .matched = JamLookup.result(of: .success(ranked), override: "x") else {
            Issue.record("expected override match"); return
        }
    }

    @Test("Realistic rows from the reported Jam match confidently")
    func realisticRows() {
        let cases: [(JamTrack, SongItemRecord)] = [
            (track("Sorry", ["Justin Bieber"], ms: 200786), song("a", "Sorry", "Justin Bieber", "3:21")),
            (track("Hvnly (feat. JIHYO)", ["Jenevieve", "JIHYO"], ms: 160000), song("b", "Hvnly (feat. JIHYO)", "Jenevieve, JIHYO", "2:40")),
            (track("Obsessed (feat. Mariah Carey)", ["Gucci Mane", "Mariah Carey"], ms: 180000), song("c", "Obsessed (feat. Mariah Carey)", "Gucci Mane & Mariah Carey", "3:00")),
        ]
        for (spotify, ytm) in cases {
            let ranked = JamMatcher.rank(track: spotify, candidates: [ytm])
            guard case .matched(let found, _) = JamLookup.result(of: .success(ranked), override: nil) else {
                Issue.record("no match for \(spotify.displayTitle): \(ranked.first?.score ?? -99)"); continue
            }
            #expect(found.videoId == ytm.videoId)
        }
    }
}

@Suite("Jam: queue lookup planner")
struct JamMatchPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func uris(_ n: Int) -> [String] { (0..<n).map { "u\($0)" } }
    private func plan(_ queue: [String], settled: Set<String> = [], inFlight: Set<String> = [],
                      attempts: [String: Int] = [:], retryAt: [String: Date] = [:],
                      lastBackground: Date = .distantPast) -> JamMatchPlanner.Plan {
        JamMatchPlanner.plan(queue: queue, settled: settled, inFlight: inFlight, attempts: attempts,
                             retryAt: retryAt, lastBackgroundStart: lastBackground, now: now)
    }

    @Test("Nearest first, bounded by the concurrency limit")
    func nearestFirst() {
        #expect(plan(uris(200)).start == ["u0", "u1", "u2"])
        #expect(plan(uris(200), inFlight: ["u0", "u1"]).start == ["u2"])
        #expect(plan(uris(200), inFlight: ["u0", "u1", "u2"]).start.isEmpty)
    }

    @Test("Settled results are skipped, so a reordered queue redoes nothing")
    func cachedSurvivesReorder() {
        let queue = ["c", "a", "b", "d"]
        #expect(plan(queue, settled: ["a", "b", "c"]).start == ["d"])
        #expect(plan(queue.reversed(), settled: ["a", "b", "c"], inFlight: ["d"]).start.isEmpty)
    }

    @Test("Duplicates of one URI are looked up once")
    func duplicates() {
        #expect(plan(["a", "a", "b"]).start == ["a", "b"])
    }

    @Test("Beyond the eager window only one lookup starts, at the background pace")
    func backgroundPace() {
        let queue = uris(40)
        let settled = Set(queue.prefix(JamMatchPlanner.eagerCount))
        let first = plan(queue, settled: settled)
        #expect(first.start == ["u15"])
        #expect(first.startsBackground)
        let tooSoon = plan(queue, settled: settled, lastBackground: now.addingTimeInterval(-0.5))
        #expect(tooSoon.start.isEmpty)
        #expect(tooSoon.wakeAfter != nil)
    }

    @Test("A failed lookup waits for its backoff, then retries; attempts are bounded")
    func retries() {
        let queue = ["a", "b"]
        let waiting = plan(queue, retryAt: ["a": now.addingTimeInterval(5)])
        #expect(waiting.start == ["b"])
        #expect(waiting.wakeAfter == 5)
        #expect(plan(queue, retryAt: ["a": now.addingTimeInterval(-1)]).start == ["a", "b"])
        #expect(plan(queue, attempts: ["a": JamMatchPlanner.maxAttempts]).start == ["b"])
        #expect(JamMatchPlanner.backoff(afterAttempt: 1) < JamMatchPlanner.backoff(afterAttempt: 4))
    }
}
