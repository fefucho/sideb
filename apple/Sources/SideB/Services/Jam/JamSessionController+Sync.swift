import AVFoundation
import Foundation

/// Position matching for the Jam mirror: a short correction window after a real change, then the
/// audio is left alone. The decisions live in `JamSyncEngine`; this file measures, applies the
/// engine's action to the player and logs. Kept apart from session/queue logic.
extension JamSessionController {
    /// Opens a short correction window; outside of it playback is left alone.
    func beginAdjusting() {
        isAdjusting = true
        syncEngine.begin()
        pausedSeekTries = 0
    }

    // MARK: Sync

    func syncTick() {
        guard phase == .live, let player, let anchor else { return }
        let target = anchor.livePositionSeconds(nowMs: nowMs()) + (nudgeMs + globalOffsetMs) / 1000
        liveSeconds = target
        let audio = player.audioService
        guard let matched, player.currentTrack?.videoId == matched.song.videoId,
              !player.isLoadingStream, audio.avPlayer.currentItem != nil, audio.duration > 0 else {
            driftMs = nil
            return
        }
        let actual = audio.avPlayer.currentTime().seconds
        guard actual.isFinite else { return }
        if anchor.paused || locallyPaused {
            if audio.isPlaying { audio.pause() }
            if !locallyPaused, isAdjusting, abs(actual - target) > 0.05, pausedSeekTries < 3,
               Date().timeIntervalSince(lastSeek) > 1 {
                lastSeek = Date()
                pausedSeekTries += 1
                audio.seek(toSeconds: target)
            } else if abs(actual - target) <= 0.05 || pausedSeekTries >= 3 {
                isAdjusting = false
                syncEngine.cancel()
            }
            driftMs = (actual - target) * 1000
            return
        }
        // This version is shorter than the Jam's: stay silent until the Jam moves on.
        if target >= audio.duration - 0.4 {
            if audio.isPlaying { audio.pause() }
            driftMs = nil
            return
        }
        if !audio.isPlaying {
            audio.resume()
            beginAdjusting()
        }
        let drift = actual - target
        driftMs = drift * 1000

        let now = ProcessInfo.processInfo.systemUptime
        syncEngine.setItem(matched.song.videoId)
        // Not advancing (buffering, or a seek still pending) is invisible to the engine.
        let advancing = audio.isPlaying && audio.avPlayer.timeControlStatus == .playing
            && audio.seekSnapshot.phase != .pending
        let wasAdjusting = syncEngine.isAdjusting
        let action = syncEngine.tick(drift: drift, now: now, advancing: advancing)
        if syncEngine.didReopen {
            note(String(format: "Desfase de %+.0f ms sostenido: se vuelve a ajustar", drift * 1000))
        }
        switch action {
        case .none:
            break
        case .seek(let compensation):
            lastSeek = Date()
            audio.avPlayer.rate = 1
            audio.seek(toSeconds: target + compensation)
        case .setRate(let rate):
            if audio.isPlaying { audio.avPlayer.rate = rate }
        case .lock:
            if audio.avPlayer.rate != 1, audio.isPlaying { audio.avPlayer.rate = 1 }
            if let summary = syncEngine.lastSummary { note("Sincronía fijada · \(summary.text)") }
        }
        isAdjusting = syncEngine.isAdjusting
        logSync(action: action, drift: drift, advancing: advancing, now: now, justOpened: !wasAdjusting && isAdjusting)
    }

    /// One JSONL line per engine decision plus one sample per second while live.
    private func logSync(action: JamSyncEngine.Action, drift: Double, advancing: Bool, now: Double, justOpened: Bool) {
        let decided = action != .none || justOpened
        guard decided || now - lastSyncSampleLog >= 1 else { return }
        if !decided { lastSyncSampleLog = now }
        var fields: [String: Any] = [
            "t": Date().timeIntervalSince1970,
            "spotify": spotifyTrack?.uri ?? "",
            "yt": matched?.song.videoId ?? "",
            "driftMs": (drift * 1000).rounded(),
            "rate": Double(player?.audioService.avPlayer.rate ?? 0),
            "mode": syncEngine.mode.rawValue,
            "advancing": advancing,
            "event": decided ? "decision" : "sample",
        ]
        switch action {
        case .none: fields["action"] = justOpened ? "open" : "none"
        case .seek(let compensation):
            fields["action"] = "seek"
            fields["compensationMs"] = (compensation * 1000).rounded()
        case .setRate(let rate):
            fields["action"] = "rate"
            fields["targetRate"] = Double(rate)
        case .lock:
            fields["action"] = "lock"
            if let summary = syncEngine.lastSummary {
                fields["window"] = ["durationS": (summary.duration * 100).rounded() / 100, "seeks": summary.seeks,
                                    "bursts": summary.bursts, "residualMs": summary.residualMs.rounded(),
                                    "reason": summary.reason.rawValue, "rateIneffective": summary.rateIneffective]
            }
        }
        if syncEngine.didReopen { fields["reopened"] = true }
        JamSyncLog.shared.write(fields)
    }
}
