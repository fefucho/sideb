import AVFoundation
import Foundation
import SideBCore

/// Mirrors a Spotify Jam into Side B: each shared track is replaced by its YouTube Music
/// equivalent and kept at the Jam's live position. Playback controls are forwarded to the Jam;
/// local audio only ever follows the state that comes back.
@MainActor
@Observable
final class JamSessionController {
    enum Phase: Equatable {
        case idle, connecting, live
        case ended(String)
        case failed(String)
    }

    static let shared = JamSessionController()

    /// Reasons of `Phase.failed` produced by the host (the plugin's own error codes arrive as is).
    /// The UI maps both to localised text.
    enum Failure {
        static let pluginMissing = "pluginMissing"
        static let noSession = "noSession"
        static let startFailed = "startFailed"
    }

    private(set) var phase: Phase = .idle
    private(set) var members: [JamMember] = []
    private(set) var canControl = false
    var spotifyTrack: JamTrack?
    var queue: [JamTrack] = []
    var candidates: [JamMatcher.Candidate] = []
    var matched: JamMatcher.Candidate?
    private(set) var playback: JamPlaybackState?
    var driftMs: Double?
    var liveSeconds: Double = 0
    private(set) var notice: String?
    private(set) var log: [String] = []
    /// Added to every target position: compensates output latency (AirPlay, Bluetooth).
    var globalOffsetMs: Double = UserDefaults.standard.double(forKey: "sideb.jam.globalOffsetMs") {
        didSet { UserDefaults.standard.set(globalOffsetMs, forKey: "sideb.jam.globalOffsetMs"); beginAdjusting() }
    }
    /// True only for the few seconds after a real change, while the position is being matched.
    var isAdjusting = false

    var process: JamProcess?
    private var eventsTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var renewalTask: Task<Void, Never>?
    weak var player: PlayerViewModel?
    var rankings: [String: [JamMatcher.Candidate]] = [:]
    private var resolveGeneration = 0
    var lastSeek = Date.distantPast
    /// The timing reference actually followed. Jam updates that agree with it are ignored, so
    /// reporting jitter never moves the target once it is matched.
    var anchor: JamPlaybackState?
    // Sync engine state (driven from JamSessionController+Sync.swift).
    var syncEngine = JamSyncEngine()
    var lastSyncSampleLog = 0.0
    var pausedSeekTries = 0
    // End of sync engine state.
    // Queue mirror and edits (JamSessionController+Queue.swift, JamSessionController+Edits.swift).
    // Read-only for views; only the controller writes them.
    /// Every upcoming Jam track with its YouTube Music match and status.
    var queueEntries: [JamQueueEntry] = []
    /// Outcome of the last queue action, for a toast. `key` is a localisation key.
    var lastActionMessage: JamActionMessage?
    var queueRevision: String?
    @ObservationIgnored var matchStates: [String: JamMatchState] = [:]
    @ObservationIgnored var resolveInFlight = Set<String>()
    @ObservationIgnored var lookupTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var lookupAttempts: [String: Int] = [:]
    @ObservationIgnored var lookupRetryAt: [String: Date] = [:]
    @ObservationIgnored var lastBackgroundLookup = Date.distantPast
    @ObservationIgnored var pumpWakeTask: Task<Void, Never>?
    @ObservationIgnored var queueMapping = JamQueueMapping(matched: [])
    @ObservationIgnored var pendingEdit: PendingJamEdit?
    @ObservationIgnored var editTask: Task<Void, Never>?
    @ObservationIgnored var pendingSpotifyResolves: [String: CheckedContinuation<JamResolved?, Never>] = [:]
    @ObservationIgnored var spotifyURIByVideo: [String: JamResolved] = [:]
    /// Changes whenever a session starts or ends; late work from an older session checks it.
    @ObservationIgnored var sessionToken = UUID()
    var locallyPaused = false
    var overrides: [String: String] = (UserDefaults.standard.dictionary(forKey: "sideb.jam.overrides.v1") as? [String: String]) ?? [:]
    private var nudges: [String: Double] = (UserDefaults.standard.dictionary(forKey: "sideb.jam.nudges.v1") as? [String: Double]) ?? [:]

    var isActive: Bool { phase == .connecting || phase == .live }
    var hostName: String? { members.first(where: \.isHost)?.name }
    /// Per-match fine adjustment for versions whose audio starts at a different instant.
    var nudgeMs: Double {
        get { matched.flatMap { nudges[nudgeKey($0)] } ?? 0 }
        set {
            guard let matched else { return }
            nudges[nudgeKey(matched)] = newValue
            UserDefaults.standard.set(nudges, forKey: "sideb.jam.nudges.v1")
            beginAdjusting()
        }
    }

    private func nudgeKey(_ candidate: JamMatcher.Candidate) -> String { "\(spotifyTrack?.uri ?? ""):\(candidate.song.videoId)" }
    func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }
    func note(_ line: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        log.append("\(stamp)  \(line)")
        if log.count > 250 { log.removeFirst(log.count - 250) }
    }

    // MARK: Lifecycle

    func join(link: String, player: PlayerViewModel, manualCredential: String? = nil) {
        guard !isActive else { return }
        guard let executable = JamProcess.locateExecutable() else {
            phase = .failed(Failure.pluginMissing)
            return
        }
        self.player = player
        phase = .connecting
        notice = nil
        log.removeAll()
        resetQueueSession()
        let token = sessionToken
        note("Conectando…")
        Task {
            let manual = manualCredential?.trimmingCharacters(in: .whitespacesAndNewlines)
            let credential: String?
            if let manual, !manual.isEmpty { credential = manual } else { credential = await SpotifySession.shared.credential() }
            guard token == sessionToken, phase == .connecting else { return } // Left while connecting.
            guard let credential else {
                phase = .failed(Failure.noSession)
                return
            }
            do {
                let process = try JamProcess(executable: executable)
                self.process = process
                process.send(["type": "join", "credential": credential, "link": link])
                eventsTask = Task {
                    for await event in process.events {
                        guard token == sessionToken else { return }
                        handle(event)
                    }
                    if token == sessionToken { processExited() }
                }
            } catch {
                phase = .failed(Failure.startFailed)
            }
        }
    }

    /// Leaves the Jam at once. Side B's own session is restored according to `restore`.
    func leave(restore: PlayerViewModel.JamExitRestore = .loadPaused) {
        guard isActive else { return }
        note("Saliendo del Jam…")
        finish(.idle, restore: restore)
    }

    private func processExited() {
        if isActive { finish(.ended("El plugin terminó")) }
    }

    private func finish(_ final: Phase, restore: PlayerViewModel.JamExitRestore = .loadPaused) {
        guard isActive else { return }
        let wasLive = phase == .live
        syncTask?.cancel(); renewalTask?.cancel()
        syncTask = nil; renewalTask = nil
        eventsTask?.cancel(); eventsTask = nil
        sessionToken = UUID()
        teardownQueueSession()
        if let player {
            if player.audioService.isPlaying { player.audioService.avPlayer.rate = 1 }
            if wasLive { player.endJamSession(restore: restore) } else { player.jamControl = nil }
        }
        process?.stop()
        process = nil
        playback = nil
        anchor = nil
        isAdjusting = false
        driftMs = nil
        phase = final
        note("Sesión terminada: \(final)")
    }

    private func becomeLive() {
        guard let player else { return }
        phase = .live
        locallyPaused = false
        // Snapshots the user's own session, silences local playback and hands the queue to the Jam.
        player.beginJamSession(editor: self, control: { [weak self] control in self?.control(control) })
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.syncTick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        renewalTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25 * 60))
                guard !Task.isCancelled else { return }
                await self?.renewCredential(force: false)
            }
        }
    }

    private func renewCredential(force: Bool) async {
        guard let token = await SpotifySession.shared.credential(forceRenew: force) else {
            note("No se pudo renovar la sesión de Spotify")
            return
        }
        process?.send(["type": "credential", "credential": token])
        note("Sesión de Spotify renovada")
    }

    // MARK: Events

    private func handle(_ event: JamEvent) {
        guard isActive else { return }
        switch event.type {
        case "joined":
            members = event.members ?? []
            canControl = event.canControl ?? false
            note("Dentro del Jam de \(hostName ?? "?") · control=\(canControl) · anfitrión activo=\(event.hostActive ?? false)")
            if phase != .live { becomeLive() } // A re-join after a reconnect keeps the running session.
        case "members":
            members = event.members ?? members
        case "state":
            apply(event)
        case "notice":
            notice = event.code
            note("Aviso: \(event.code ?? "?")")
        case "session":
            note("Jam: \(event.reason ?? "?")")
        case "commandResult":
            note("Comando \(event.action ?? "?") → \(event.ok == true ? "ok" : "falló") \(event.detail ?? "")")
            handleCommandResult(event)
        case "resolved":
            completeSpotifyResolve(event)
        case "ended":
            finish(.ended(event.reason ?? "fin"))
        case "error":
            note("Error: \(event.code ?? "?")\(event.retryable == true ? " (reintentando)" : "")")
            if event.code == "authRequired", event.retryable == true {
                Task { await renewCredential(force: true) }
            } else if event.retryable != true, phase == .connecting {
                finish(.failed(event.code ?? "error"))
            }
        default:
            break
        }
    }

    private func apply(_ event: JamEvent) {
        guard phase == .live else { return }
        if let position = event.positionMs, let at = event.atLocalMs {
            let next = JamPlaybackState(positionMs: position, atLocalMs: at, paused: event.paused ?? false, durationMs: event.durationMs)
            if next != playback {
                if next.paused != playback?.paused { note(next.paused ? "Jam en pausa" : "Jam reproduciendo") }
                playback = next
                notice = nil
            }
            // Re-anchor only on a real change: another track, pause/resume, or a jump in position
            // (seek). A report that merely restates the same timeline keeps the current anchor.
            let now = nowMs()
            let sameTrack = event.track?.uri == spotifyTrack?.uri
            if let anchor, sameTrack, anchor.paused == next.paused,
               abs(anchor.livePositionSeconds(nowMs: now) - next.livePositionSeconds(nowMs: now)) < 0.6 {
                self.anchor?.durationMs = next.durationMs
            } else {
                anchor = next
                beginAdjusting()
            }
        }
        let newQueue = event.queue ?? []
        let queueChanged = newQueue != queue
        queue = newQueue
        queueRevision = event.queueRevision
        if event.track?.uri != spotifyTrack?.uri {
            spotifyTrack = event.track
            candidates = []
            matched = nil
            driftMs = nil
            if let track = event.track {
                note("Canción del Jam: \(track.displayTitle) — \(track.displayArtists)")
                resolveCurrent(track)
            } else {
                player?.audioService.pause()
            }
        }
        if queueChanged { queueDidChange() }
        evaluatePendingEdit()
    }

    // MARK: Matching

    /// Searches YouTube Music for `track`. A thrown error is returned as a failure, never as "no
    /// candidates"; only a completed search yields a (possibly empty) ranking.
    func ranking(for track: JamTrack) async -> Result<[JamMatcher.Candidate], Error> {
        if let known = rankings[track.uri] { return .success(known) }
        guard track.title != nil else { return .success([]) }
        guard let core = player?.rustCore else { return .failure(JamLookupError.coreNotReady) }
        let found: [SongItemRecord]
        do {
            found = try await core.searchSongs(query: JamMatcher.query(for: track), recordHistory: false)
        } catch {
            return .failure(error)
        }
        if Task.isCancelled { return .failure(CancellationError()) }
        var ranked = JamMatcher.rank(track: track, candidates: found)
        if let chosen = overrides[track.uri], let index = ranked.firstIndex(where: { $0.song.videoId == chosen }) {
            ranked.insert(ranked.remove(at: index), at: 0)
        }
        if !ranked.isEmpty { rankings[track.uri] = ranked }
        return .success(ranked)
    }

    private func resolveCurrent(_ track: JamTrack, attempt: Int = 1) {
        if attempt == 1 { resolveGeneration += 1 }
        let generation = resolveGeneration
        Task {
            let search = await ranking(for: track)
            guard generation == resolveGeneration, phase == .live, spotifyTrack?.uri == track.uri else { return }
            if case .failure(let error) = search {
                note("Búsqueda de la canción actual falló (\(attempt)): \(error)")
                guard attempt < JamMatchPlanner.maxAttempts else { return }
                try? await Task.sleep(for: .seconds(JamMatchPlanner.backoff(afterAttempt: attempt)))
                guard generation == resolveGeneration, phase == .live, spotifyTrack?.uri == track.uri else { return }
                resolveCurrent(track, attempt: attempt + 1)
                return
            }
            let ranked = (try? search.get()) ?? []
            candidates = ranked
            guard let best = ranked.first, best.isConfident || overrides[track.uri] == best.song.videoId else {
                note("Sin equivalente confiable en YouTube Music (\(ranked.count) candidatos)")
                player?.audioService.pause()
                return
            }
            play(best)
        }
    }

    private func play(_ candidate: JamMatcher.Candidate) {
        guard let player else { return }
        matched = candidate
        publishQueue() // The mirrored queue starts at the version that is about to play.
        lastSeek = .distantPast
        beginAdjusting()
        let delta = candidate.durationDelta.map { String(format: "%+.0f s", $0) } ?? "?"
        note("YouTube Music: \(candidate.song.title) — \(candidate.song.artists) · puntaje \(String(format: "%.1f", candidate.score)) · Δduración \(delta)")
        player.playSongNow(candidate.song)
    }

    /// Manual correction: the chosen version loads now and is synced to the live position at once.
    func choose(_ candidate: JamMatcher.Candidate) {
        guard phase == .live, let track = spotifyTrack else { return }
        overrides[track.uri] = candidate.song.videoId
        UserDefaults.standard.set(overrides, forKey: "sideb.jam.overrides.v1")
        if let index = candidates.firstIndex(where: { $0.id == candidate.id }) {
            candidates.insert(candidates.remove(at: index), at: 0)
            rankings[track.uri] = candidates
        }
        note("Versión elegida a mano")
        matchStates[track.uri] = .matched(candidate.song)
        play(candidate)
    }

    // MARK: Controls

    private func control(_ control: PlayerViewModel.JamControl) {
        guard phase == .live else { return }
        guard canControl else {
            if case .togglePlayPause = control { locallyPaused.toggle() }
            return
        }
        switch control {
        case .togglePlayPause: send(playback?.paused == true ? "resume" : "pause")
        case .next: send("next")
        case .previous: send("previous")
        case .seek(let fraction):
            let duration = playback?.durationMs ?? spotifyTrack?.durationMs ?? ((player?.audioService.duration ?? 0) * 1000)
            guard duration > 0 else { return }
            send("seek", extra: ["positionMs": Int(max(0, min(1, fraction)) * duration)])
        }
    }

    func send(_ action: String, extra: [String: Any] = [:]) {
        var message: [String: Any] = ["type": "command", "action": action]
        message.merge(extra) { $1 }
        process?.send(message)
    }

    func seek(bySeconds delta: Double) {
        guard let playback else { return }
        send("seek", extra: ["positionMs": Int(max(0, (playback.livePositionSeconds(nowMs: nowMs()) + delta) * 1000))])
    }
}

enum JamLookupError: Error { case coreNotReady }
