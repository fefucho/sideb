import Foundation
import SideBCore

/// Mirrors the whole Jam queue into Side B's own queue. Each Jam track is matched to YouTube Music
/// lazily (a few at a time, nearest first); the app queue and `queueEntries` update as matches
/// arrive. Tracks with no confident match stay out of the app queue but remain in `queueEntries`.
extension JamSessionController {
    func resetQueueSession() {
        sessionToken = UUID()
        queue = []
        queueRevision = nil
        queueEntries = []
        queueMapping = JamQueueMapping(matched: [])
        cancelLookups()
        matchStates = [:]
        spotifyTrack = nil
        matched = nil
        candidates = []
        lastActionMessage = nil
    }

    /// Ends anything that was waiting on the plugin.
    func teardownQueueSession() {
        editTask?.cancel()
        editTask = nil
        resolvePendingEdit(.failed("jam.action.notLive"))
        let waiting = pendingSpotifyResolves
        pendingSpotifyResolves = [:]
        for (_, continuation) in waiting { continuation.resume(returning: nil) }
        cancelLookups()
        queueEntries = []
        queueMapping = JamQueueMapping(matched: [])
    }

    private func cancelLookups() {
        for (_, task) in lookupTasks { task.cancel() }
        lookupTasks = [:]
        resolveInFlight = []
        lookupAttempts = [:]
        lookupRetryAt = [:]
        lastBackgroundLookup = .distantPast
        pumpWakeTask?.cancel()
        pumpWakeTask = nil
    }

    /// The Jam reported a different queue.
    func queueDidChange() {
        publishQueue()
        pumpMatches()
    }

    /// Starts lookups for the nearest unresolved tracks (see `JamMatchPlanner`). Settled results
    /// and in-flight lookups are keyed by Spotify URI, so reordering the queue redoes nothing.
    func pumpMatches() {
        guard phase == .live else { return }
        let plan = JamMatchPlanner.plan(
            queue: queue.map(\.uri), settled: Set(matchStates.keys), inFlight: resolveInFlight,
            attempts: lookupAttempts, retryAt: lookupRetryAt, lastBackgroundStart: lastBackgroundLookup, now: Date())
        if plan.startsBackground { lastBackgroundLookup = Date() }
        let byURI = Dictionary(queue.map { ($0.uri, $0) }, uniquingKeysWith: { first, _ in first })
        for uri in plan.start {
            guard let track = byURI[uri] else { continue }
            startLookup(track)
        }
        pumpWakeTask?.cancel()
        pumpWakeTask = nil
        if let delay = plan.wakeAfter {
            let token = sessionToken
            pumpWakeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, token == self.sessionToken else { return }
                self.pumpMatches()
            }
        }
    }

    private func startLookup(_ track: JamTrack) {
        let token = sessionToken
        resolveInFlight.insert(track.uri)
        lookupTasks[track.uri] = Task { [weak self] in
            guard let self else { return }
            let search = await self.ranking(for: track)
            // A cancelled or superseded lookup writes nothing.
            guard !Task.isCancelled, token == self.sessionToken else { return }
            self.resolveInFlight.remove(track.uri)
            self.lookupTasks[track.uri] = nil
            let label = "\(track.displayTitle) — \(track.displayArtists)"
            switch JamLookup.result(of: search, override: self.overrides[track.uri]) {
            case .matched(let song, let score):
                self.matchStates[track.uri] = .matched(song)
                self.note("Cola · \(label) → \(song.title) — \(song.artists) (puntaje \(String(format: "%.1f", score)))")
            case .noMatch(let count, let best):
                self.matchStates[track.uri] = .unavailable
                let top = best.map { String(format: "%.1f", $0) } ?? "–"
                self.note("Cola · \(label) → sin equivalente confiable (\(count) candidatos, mejor puntaje \(top))")
            case .failed(let reason):
                let attempt = self.lookupAttempts[track.uri, default: 0] + 1
                self.lookupAttempts[track.uri] = attempt
                self.lookupRetryAt[track.uri] = Date().addingTimeInterval(JamMatchPlanner.backoff(afterAttempt: attempt))
                self.note("Cola · \(label) → error de búsqueda (intento \(attempt)/\(JamMatchPlanner.maxAttempts)): \(reason)")
            }
            self.publishQueue()
            self.pumpMatches()
        }
    }

    /// Rebuilds `queueEntries` and the mirrored app queue from the Jam queue and the matches so far.
    func publishQueue() {
        let ids = JamQueueMapping.entryIDs(for: queue.map(\.uri))
        var entries: [JamQueueEntry] = []
        entries.reserveCapacity(queue.count)
        for (index, track) in queue.enumerated() {
            var song: SongItemRecord?
            var status = JamQueueEntry.Status.resolving
            switch matchStates[track.uri] {
            case .matched(let found): song = found; status = .matched
            case .unavailable: status = .unavailable
            case nil: break
            }
            entries.append(JamQueueEntry(id: ids[index], index: index, track: track, song: song, status: status))
        }
        if entries != queueEntries { queueEntries = entries }
        queueMapping = JamQueueMapping(matched: entries.map { $0.status == .matched })
        // The mirror needs what is playing; until it is matched the previous rows stay as they were.
        guard phase == .live, let player, let current = matched?.song else { return }
        player.queueManager.mirrorSession(current: current, upcoming: entries.compactMap(\.song), title: "Spotify Jam")
    }
}
