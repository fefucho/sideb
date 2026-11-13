import Foundation
import SideBCore

/// A queue edit that was sent to the plugin and is waiting for the Jam's next state to show it.
struct PendingJamEdit {
    let requestId: String
    let edit: JamQueueEdit
    /// Jam queue (URIs) when the edit was sent.
    let old: [String]
    let continuation: CheckedContinuation<JamSessionController.EditOutcome, Never>
}

/// Queue edits made from Side B, sent to the Jam. Nothing here changes the local queue: Spotify only
/// acknowledges a request, so the change shows up when the next Jam state brings it back, and a
/// request whose effect does not arrive in time is reported as not applied.
extension JamSessionController: QueueSessionEditing {
    enum EditOutcome: Equatable {
        case confirmed
        case timedOut
        /// Localisation key of the failure.
        case failed(String)
    }

    /// How long a command may take to show up in the Jam's state.
    private static let confirmationTimeout: Duration = .seconds(3)
    private static let resolveTimeout: Duration = .seconds(8)

    // MARK: Public actions (also reached through the QueueManager hook)

    /// "Add to queue": translate each song to Spotify, then `add` it.
    func sessionAppend(_ tracks: [SongItemRecord]) {
        guard beginEdit() else { return }
        runInsertion(tracks, anchor: nil, atEnd: true)
    }

    /// "Play next" / drop at a position: translate, then `insert` at the Jam index behind `row`.
    func sessionInsert(_ tracks: [SongItemRecord], atUpcomingRow row: Int) {
        guard beginEdit() else { return }
        let index = queueMapping.insertionJamIndex(atRow: row)
        // The neighbour the track must stay in front of, so a queue that moves while the song is
        // being translated does not misplace it.
        let anchor = queue.indices.contains(index) ? queue[index].uri : nil
        runInsertion(tracks, anchor: (anchor, index), atEnd: false)
    }

    func sessionMove(fromUpcomingRow from: Int, toUpcomingRow to: Int) {
        guard beginEdit() else { return }
        guard let move = queueMapping.move(fromRow: from, toRow: to) else { post("jam.action.notEditable"); return endEdit() }
        let title = queue.indices.contains(move.from) ? queue[move.from].displayTitle : ""
        run(.move(from: move.from, to: move.to), title: title, success: "jam.action.moved")
    }

    func sessionRemove(upcomingRow row: Int) {
        guard beginEdit() else { return }
        guard let index = queueMapping.jamIndex(forRow: row), queue.indices.contains(index) else { post("jam.action.notEditable"); return endEdit() }
        run(.remove(index: index), title: queue[index].displayTitle, success: "jam.action.removed")
    }

    func sessionRejected(_ reason: QueueSessionRejection) {
        switch reason {
        case .shuffleRepeat: post("jam.action.shuffleRepeatInert")
        case .playRow: post("jam.action.playRowUnsupported")
        case .removeCurrent: post("jam.action.removeCurrentUnsupported")
        case .editPast: post("jam.action.notEditable")
        }
    }

    func post(_ key: String, _ args: [String] = []) {
        lastActionMessage = JamActionMessage(key: key, args: args)
    }

    // MARK: Flow

    /// Common preconditions; claims the single edit slot (the indices of a second edit made before
    /// the first lands would refer to a queue that no longer exists).
    private func beginEdit() -> Bool {
        guard phase == .live else { post("jam.action.notLive"); return false }
        guard canControl else { post("jam.action.noControl"); return false }
        guard editTask == nil, pendingEdit == nil else { post("jam.action.busy"); return false }
        // Marks the slot as taken until `run`/`runInsertion` replace it with the real task.
        editTask = Task {}
        return true
    }

    private func endEdit() { editTask = nil }

    private func run(_ edit: JamQueueEdit, title: String, success: String) {
        editTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.perform(edit)
            self.report(outcome, title: title, success: success)
            self.endEdit()
        }
    }

    private func report(_ outcome: EditOutcome, title: String, success: String) {
        switch outcome {
        case .confirmed: post(success, [title])
        case .timedOut: post("jam.action.notApplied", [title])
        case .failed(let key): post(key, [title])
        }
    }

    private func runInsertion(_ tracks: [SongItemRecord], anchor: (uri: String?, index: Int)?, atEnd: Bool) {
        let token = sessionToken
        editTask = Task { [weak self] in
            guard let self else { return }
            defer { self.endEdit() }
            var found: [(uri: String, title: String)] = []
            var missing: [String] = []
            for song in tracks {
                guard !Task.isCancelled, token == self.sessionToken else { return }
                if let resolved = await self.spotifyEquivalent(of: song) { found.append((resolved.uri, song.title)) }
                else { missing.append(song.title) }
            }
            guard !Task.isCancelled, token == self.sessionToken, self.phase == .live else { return }
            guard !found.isEmpty else {
                if missing.count == 1 { self.post("jam.action.noSpotifyMatch", missing) }
                else { self.post("jam.action.noSpotifyMatchMany", [String(missing.count)]) }
                return
            }
            // Re-anchor to where the neighbour is now.
            var base = self.queue.count
            if let anchor {
                if let uri = anchor.uri { base = self.queue.firstIndex { $0.uri == uri } ?? min(anchor.index, self.queue.count) }
            }
            var done = 0
            for (offset, item) in found.enumerated() {
                let edit: JamQueueEdit = atEnd ? .add(uri: item.uri) : .insert(uri: item.uri, index: base + offset)
                let outcome = await self.perform(edit)
                guard outcome == .confirmed else {
                    self.report(outcome, title: item.title, success: "")
                    return
                }
                done += 1
            }
            if !missing.isEmpty { self.post("jam.action.partialAdded", [String(done), String(tracks.count)]) }
            else if found.count == 1 { self.post(atEnd ? "jam.action.added" : "jam.action.inserted", [found[0].title]) }
            else { self.post(atEnd ? "jam.action.addedMany" : "jam.action.insertedMany", [String(found.count)]) }
        }
    }

    // MARK: Sending and confirming

    /// Sends one edit and waits for the Jam's state to show it (or for the failure/timeout).
    func perform(_ edit: JamQueueEdit) async -> EditOutcome {
        let current = queue.map(\.uri)
        guard phase == .live, process != nil else { return .failed("jam.action.notLive") }
        guard edit.isValid(on: current) else { return .failed("jam.action.notApplied") }
        let requestId = UUID().uuidString
        return await withCheckedContinuation { continuation in
            pendingEdit = PendingJamEdit(requestId: requestId, edit: edit, old: current, continuation: continuation)
            process?.send(edit.command(revision: queueRevision, requestId: requestId))
            note("Cola: \(edit.action) \(edit) (revisión \(queueRevision ?? "?"))")
            Task { [weak self] in
                try? await Task.sleep(for: Self.confirmationTimeout)
                self?.resolvePendingEdit(.timedOut, requestId: requestId)
            }
        }
    }

    /// Completes the waiting edit, if it is still `requestId` (nil = whichever is waiting).
    func resolvePendingEdit(_ outcome: EditOutcome, requestId: String? = nil) {
        guard let pending = pendingEdit, requestId == nil || pending.requestId == requestId else { return }
        pendingEdit = nil
        pending.continuation.resume(returning: outcome)
    }

    /// Called with every new Jam state: did the waiting edit show up?
    func evaluatePendingEdit() {
        guard let pending = pendingEdit, pending.edit.isSatisfied(old: pending.old, new: queue.map(\.uri)) else { return }
        resolvePendingEdit(.confirmed, requestId: pending.requestId)
    }

    /// `commandResult` only says whether Spotify accepted the request. A refusal fails the edit at
    /// once; an acceptance is not enough (the state decides).
    func handleCommandResult(_ event: JamEvent) {
        guard let pending = pendingEdit, event.ok == false else { return }
        let matches = event.requestId == pending.requestId || (event.requestId == nil && event.action == pending.edit.action)
        guard matches else { return }
        resolvePendingEdit(.failed(event.detail == "stale" ? "jam.action.stale" : "jam.action.rejected"), requestId: pending.requestId)
    }

    // MARK: YouTube Music -> Spotify

    /// Asks the plugin for the Spotify track that matches a YouTube Music song. Nil: no confident match.
    func spotifyEquivalent(of song: SongItemRecord) async -> JamResolved? {
        if let known = spotifyURIByVideo[song.videoId] { return known }
        if let hit = matchStates.first(where: { if case .matched(let s) = $0.value { return s.videoId == song.videoId }; return false }) {
            // This very song was matched from a Jam track: the Spotify side is already known.
            return JamResolved(uri: hit.key)
        }
        guard let process else { return nil }
        let requestId = UUID().uuidString
        // Many YouTube Music rows carry no duration: say so instead of sending 0.
        let seconds = song.duration.flatMap(JamMatcher.seconds) ?? 0
        let duration: Any = seconds > 0 ? Int(seconds * 1000) : NSNull()
        note("Buscando en Spotify: \(song.title) — \(song.artists) [\(song.duration ?? "sin duración")]")
        let resolved: JamResolved? = await withCheckedContinuation { continuation in
            pendingSpotifyResolves[requestId] = continuation
            process.send(["type": "resolve", "requestId": requestId, "title": song.title, "artist": song.artists,
                          "album": song.album ?? NSNull(), "durationMs": duration])
            Task { [weak self] in
                try? await Task.sleep(for: Self.resolveTimeout)
                if self?.pendingSpotifyResolves[requestId] != nil { self?.note("Spotify: el plugin no respondió a la búsqueda en 8 s") }
                self?.finishSpotifyResolve(requestId, nil)
            }
        }
        if let resolved {
            spotifyURIByVideo[song.videoId] = resolved
            note("Spotify: \(resolved.title ?? resolved.uri)")
        }
        return resolved
    }

    func completeSpotifyResolve(_ event: JamEvent) {
        guard let requestId = event.requestId else { return }
        if event.uri == nil { note("Spotify: sin coincidencia confiable") }
        finishSpotifyResolve(requestId, JamResolved(event: event))
    }

    private func finishSpotifyResolve(_ requestId: String, _ result: JamResolved?) {
        guard let continuation = pendingSpotifyResolves.removeValue(forKey: requestId) else { return }
        continuation.resume(returning: result)
    }
}
