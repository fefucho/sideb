import AVFoundation
import Foundation
import Testing
@testable import SideB

@Suite("Audio: ownership and bounds of asynchronous seeks")
struct AudioPlayerSeekStateTests {
    @Test("Consecutive requests reject old completions even for the same target")
    func consecutiveSeekOwnership() {
        var state = AudioPlayerSeekState()
        let playback = UUID()
        let generation = UUID()
        let first = state.begin(targetSeconds: 30, playbackID: playback, itemGeneration: generation,
                                mediaSeconds: 1, now: 0)
        let firstRevision = state.snapshot.revision
        let second = state.begin(targetSeconds: 30, playbackID: playback, itemGeneration: generation,
                                 mediaSeconds: 1, now: 0.1)
        #expect(first != second)
        #expect(state.snapshot.revision > firstRevision)
        #expect(state.complete(first, finished: true, mediaSeconds: 30) == false)
        #expect(state.snapshot.phase == .pending)
        #expect(state.snapshot.pendingTargetSeconds == 30)
        #expect(state.complete(second, finished: true, mediaSeconds: 29.97) == true)
        #expect(state.snapshot.phase == .completed)
        #expect(state.snapshot.mediaSeconds == 29.97)
        #expect(state.snapshot.pendingTargetSeconds == nil)
        #expect(state.sampledPosition(mediaSeconds: 29.98, now: 0.2) == 29.98)
    }

    @Test("A pending preview does not jump back to samples from before the seek")
    func pendingHasFixedPreview() {
        var state = AudioPlayerSeekState()
        _ = state.begin(targetSeconds: 60, playbackID: UUID(), itemGeneration: UUID(), mediaSeconds: 2, now: 1)
        let revision = state.snapshot.revision
        #expect(state.sampledPosition(mediaSeconds: 2.1, now: 1.1) == 60)
        #expect(state.sampledPosition(mediaSeconds: 2.2, now: 2) == 60)
        #expect(state.snapshot.revision == revision)
    }

    @Test("Failure returns to measured media time without a target floor")
    func failureIsNotACompletedSeek() {
        var state = AudioPlayerSeekState()
        let ticket = state.begin(targetSeconds: 60, playbackID: UUID(), itemGeneration: UUID(), mediaSeconds: 2, now: 1)
        #expect(state.complete(ticket, finished: false, mediaSeconds: 2.3) == true)
        #expect(state.snapshot.phase == .failed)
        #expect(state.snapshot.mediaSeconds == 2.3)
        #expect(state.snapshot.pendingTargetSeconds == nil)
        #expect(state.sampledPosition(mediaSeconds: 2.4, now: 1.2) == 2.4)
    }

    @Test("An unavailable completion timestamp retains the last real measurement")
    func invalidTimeNeverTurnsTheTargetIntoMediaTime() {
        var state = AudioPlayerSeekState()
        let ticket = state.begin(targetSeconds: 60, playbackID: UUID(), itemGeneration: UUID(), mediaSeconds: 2, now: 1)
        #expect(state.sampledPosition(mediaSeconds: 2.1, now: 1.1) == 60)
        #expect(state.complete(ticket, finished: false, mediaSeconds: .nan) == true)
        #expect(state.snapshot.mediaSeconds == 2.1)
        #expect(state.snapshot.pendingTargetSeconds == nil)
    }

    @Test("An observed timeout invalidates its eventual completion")
    func timeoutIsBoundedAndOwned() {
        var state = AudioPlayerSeekState()
        let ticket = state.begin(targetSeconds: 60, playbackID: UUID(), itemGeneration: UUID(), mediaSeconds: 2, now: 10)
        #expect(state.sampledPosition(mediaSeconds: 2.1, now: 14.999) == 60)
        #expect(state.sampledPosition(mediaSeconds: 2.2, now: 15) == 2.2)
        #expect(state.snapshot.phase == .failed)
        #expect(state.complete(ticket, finished: true, mediaSeconds: 60) == false)
        #expect(state.snapshot.mediaSeconds == 2.2)
    }

    @Test("Replacing an occurrence or item invalidates pending tickets")
    func replacementInvalidatesOldRequest() {
        var state = AudioPlayerSeekState()
        let oldPlayback = UUID()
        let nextPlayback = UUID()
        let old = state.begin(targetSeconds: 60, playbackID: oldPlayback, itemGeneration: UUID(), mediaSeconds: 2, now: 0)
        state.reset(playbackID: nextPlayback, mediaSeconds: 0)
        #expect(state.snapshot.phase == .cancelled)
        #expect(state.snapshot.playbackID == nextPlayback)
        #expect(state.snapshot.pendingTargetSeconds == nil)
        #expect(state.complete(old, finished: true, mediaSeconds: 60) == false)
        let next = state.begin(targetSeconds: 10, playbackID: nextPlayback, itemGeneration: UUID(), mediaSeconds: 0, now: 1)
        #expect(state.complete(old, finished: false, mediaSeconds: 2) == false)
        #expect(state.complete(next, finished: true, mediaSeconds: 10) == true)
        #expect(state.snapshot.mediaSeconds == 10)
    }

    @Test("Absolute seeks accept unknown duration and validate finite seconds")
    func unknownDurationAndInvalidInputs() {
        #expect(AudioPlayerSeekBounds.target(seconds: 42, duration: 0) == 42)
        #expect(AudioPlayerSeekBounds.target(seconds: 42, duration: .nan) == 42)
        #expect(AudioPlayerSeekBounds.target(seconds: 42, duration: .infinity) == 42)
        #expect(AudioPlayerSeekBounds.target(seconds: -5, duration: 0) == 0)
        #expect(AudioPlayerSeekBounds.target(seconds: 42, duration: 30) == 30)
        #expect(AudioPlayerSeekBounds.target(seconds: .nan, duration: 30) == nil)
        #expect(AudioPlayerSeekBounds.target(seconds: .infinity, duration: 30) == nil)
    }

    @Test("Seekable ranges clamp an unknown-duration stream and preserve holes")
    func seekableBounds() {
        let ranges = [10.0...20.0, 40.0...50.0]
        #expect(AudioPlayerSeekBounds.target(seconds: 0, duration: 0, seekableRanges: ranges) == 10)
        #expect(AudioPlayerSeekBounds.target(seconds: 15, duration: 0, seekableRanges: ranges) == 15)
        #expect(AudioPlayerSeekBounds.target(seconds: 25, duration: 0, seekableRanges: ranges) == 20)
        #expect(AudioPlayerSeekBounds.target(seconds: 36, duration: 0, seekableRanges: ranges) == 40)
        #expect(AudioPlayerSeekBounds.target(seconds: 100, duration: 0, seekableRanges: ranges) == 50)
        #expect(AudioPlayerSeekBounds.target(seconds: 100, duration: 45, seekableRanges: ranges) == 45)
        #expect(AudioPlayerSeekBounds.target(seconds: 20, duration: 0, seekableRanges: [0...0]) == 20)
    }

    @Test("A provisional range at the beginning cannot collapse every VOD lyric cue")
    func vodCuesIgnoreProvisionalSeekableWindow() {
        let cues = [8.0, 27.5, 63.125, 128.0, 179.0]
        for cue in cues {
            #expect(AudioPlayerSeekBounds.target(seconds: cue, duration: 180,
                                                 seekableRanges: [0...0.01]) == cue)
            #expect(AudioPlayerSeekBounds.target(seconds: cue, duration: 180,
                                                 seekableRanges: [0...4, 140...150]) == cue)
        }
        #expect(AudioPlayerSeekBounds.target(seconds: 240, duration: 180,
                                             seekableRanges: [0...0.01]) == 180)
    }
}

@Suite("Audio: service reconciliation after seeking")
@MainActor
struct AudioPlayerSeekTests {
    @Test("The service sends each VOD lyric cue to AVPlayer despite a provisional seekable range")
    func servicePreservesCuesOutsideProvisionalRange() {
        let fixture = makeFixture(item: ProvisionalSeekableItem(asset: AVMutableComposition()))
        defer { fixture.audio.stop() }
        fixture.audio.duration = 180
        let cues = [8.0, 27.5, 63.125, 128.0, 179.0]
        for cue in cues {
            #expect(fixture.audio.seek(toSeconds: cue))
            #expect(fixture.audio.seekSnapshot.targetSeconds == cue)
            #expect(fixture.audio.currentTime == cue)
        }
        #expect(fixture.probe.targets == cues)
    }

    @Test("The service accepts unknown duration with an item and holds pending samples")
    func serviceKeepsPendingTarget() async {
        let fixture = makeFixture()
        defer { fixture.audio.stop() }
        var effectiveProgress: [Double] = []
        fixture.audio.onPlaybackProgress = { seconds, _ in effectiveProgress.append(seconds) }
        #expect(fixture.audio.duration == 0)
        #expect(fixture.audio.seek(toSeconds: 42))
        #expect(fixture.probe.targets == [42])
        #expect(fixture.audio.currentTime == 42)
        fixture.probe.mediaSeconds = 2.1
        fixture.audio.samplePlaybackProgress()
        #expect(fixture.audio.currentTime == 42)
        #expect(effectiveProgress.isEmpty)
        fixture.probe.mediaSeconds = 41.98
        fixture.probe.completions[0](true)
        await drainCallbacks()
        #expect(fixture.audio.seekSnapshot.phase == .completed)
        #expect(fixture.audio.currentTime == 41.98)
        #expect(effectiveProgress == [41.98])
        fixture.probe.mediaSeconds = 42.05
        fixture.audio.samplePlaybackProgress()
        #expect(fixture.audio.currentTime == 42.05)
        #expect(!fixture.audio.isPlaying)
    }

    @Test("A superseded service callback cannot move currentTime to an old target")
    func serviceRejectsOldCallback() async {
        let fixture = makeFixture()
        defer { fixture.audio.stop() }
        #expect(fixture.audio.seek(toSeconds: 20))
        #expect(fixture.audio.seek(toSeconds: 60))
        fixture.probe.mediaSeconds = 20
        fixture.probe.completions[0](true)
        await drainCallbacks()
        #expect(fixture.audio.seekSnapshot.phase == .pending)
        #expect(fixture.audio.currentTime == 60)
        fixture.probe.mediaSeconds = 59.99
        fixture.probe.completions[1](true)
        await drainCallbacks()
        #expect(fixture.audio.seekSnapshot.phase == .completed)
        #expect(fixture.audio.currentTime == 59.99)
    }

    @Test("A callback from a replaced item cannot settle the replacement seek")
    func serviceRejectsReplacedItemCallback() async {
        let fixture = makeFixture()
        defer { fixture.audio.stop() }
        #expect(fixture.audio.seek(toSeconds: 20))
        fixture.audio.avPlayer.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        #expect(fixture.audio.seek(toSeconds: 60))
        fixture.probe.mediaSeconds = 20
        fixture.probe.completions[0](true)
        await drainCallbacks()
        #expect(fixture.audio.seekSnapshot.phase == .pending)
        #expect(fixture.audio.currentTime == 60)
        fixture.probe.mediaSeconds = 60
        fixture.probe.completions[1](true)
        await drainCallbacks()
        #expect(fixture.audio.seekSnapshot.phase == .completed)
        #expect(fixture.audio.currentTime == 60)
    }

    @Test("A pending target near the end cannot trigger the end sentinel")
    func pendingSeekIsNotTrackEnd() {
        let fixture = makeFixture()
        defer { fixture.audio.stop() }
        var ended = false
        fixture.audio.duration = 100
        fixture.audio.isPlaying = true
        fixture.audio.onTrackDidEnd = { ended = true }
        #expect(fixture.audio.seek(toSeconds: 99.9))
        fixture.audio.samplePlaybackProgress()
        #expect(fixture.audio.currentTime == 99.9)
        #expect(!ended)
        #expect(fixture.audio.isPlaying)
    }

    @Test("Interrupted seek restores measured position and preserves general pause state")
    func serviceHonorsFailureAndPause() async {
        let fixture = makeFixture()
        defer { fixture.audio.stop() }
        #expect(fixture.audio.seek(toSeconds: 60))
        fixture.probe.mediaSeconds = 2.2
        fixture.probe.completions[0](false)
        await drainCallbacks()
        #expect(fixture.audio.seekSnapshot.phase == .failed)
        #expect(fixture.audio.currentTime == 2.2)
        #expect(fixture.audio.avPlayer.rate == 0)
        #expect(!fixture.audio.isPlaying)
    }

    @Test("Stop clears the preview and rejects a late completion from the removed item")
    func stopInvalidatesPendingCompletion() async {
        let fixture = makeFixture()
        #expect(fixture.audio.seek(toSeconds: 60))
        let revision = fixture.audio.seekSnapshot.revision
        fixture.audio.stop()
        #expect(fixture.audio.seekSnapshot.revision > revision)
        #expect(fixture.audio.seekSnapshot.phase == .cancelled)
        fixture.probe.mediaSeconds = 60
        fixture.probe.completions[0](true)
        await drainCallbacks()
        #expect(fixture.audio.currentTime == 0)
        #expect(fixture.audio.avPlayer.currentItem == nil)
        #expect(fixture.audio.seekSnapshot.pendingTargetSeconds == nil)
    }

    @Test("Timeout reconciles the service to actual time and drops later callbacks")
    func serviceTimeoutReturnsToMeasuredTime() async {
        let fixture = makeFixture()
        defer { fixture.audio.stop() }
        #expect(fixture.audio.seek(toSeconds: 60))
        fixture.probe.now = AudioPlayerSeekState.maximumPendingInterval
        fixture.probe.mediaSeconds = 2.3
        fixture.audio.samplePlaybackProgress()
        #expect(fixture.audio.seekSnapshot.phase == .failed)
        #expect(fixture.audio.currentTime == 2.3)
        fixture.probe.mediaSeconds = 60
        fixture.probe.completions[0](true)
        await drainCallbacks()
        #expect(fixture.audio.currentTime == 2.3)
    }

    @Test("A paused seek expires without any media-time observer sample")
    func deadlineResolvesPausedSeek() async throws {
        let fixture = makeFixture()
        defer { fixture.audio.stop() }
        #expect(fixture.audio.seek(toSeconds: 60))
        #expect(fixture.audio.seekSnapshot.phase == .pending)
        fixture.probe.mediaSeconds = 2.4
        await fixture.probe.deadline.expire()
        // Expiring the gate resumes the service task; a fixed number of yields
        // does not guarantee its return to MainActor. Wait for its observable
        // result, with a real bounded deadline only for test synchronization.
        // Do not sample media time: that would exercise a different timeout path.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while fixture.audio.seekSnapshot.phase == .pending && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(fixture.audio.seekSnapshot.phase == .failed)
        #expect(fixture.audio.currentTime == 2.4)
        #expect(fixture.audio.avPlayer.rate == 0)
        #expect(!fixture.audio.isPlaying)
    }

    @Test("No item, nonfinite time and normalized unknown duration do not enqueue seeks")
    func serviceRejectsUnusableRequests() {
        let fixture = makeFixture()
        defer { fixture.audio.stop() }
        #expect(!fixture.audio.seek(toSeconds: .nan))
        #expect(!fixture.audio.seek(toSeconds: .infinity))
        #expect(!fixture.audio.seek(toFraction: 0.5))
        #expect(fixture.probe.targets.isEmpty)
        fixture.audio.stop()
        #expect(!fixture.audio.seek(toSeconds: 30))
        #expect(fixture.probe.targets.isEmpty)
    }

    private func makeFixture(item: AVPlayerItem = AVPlayerItem(asset: AVMutableComposition())) -> (audio: AudioPlayerService, probe: SeekProbe) {
        let probe = SeekProbe()
        let preferences = UserDefaults(suiteName: "AudioPlayerSeek.\(UUID())")!
        let player = AVPlayer(playerItem: item)
        let audio = AudioPlayerService(
            preferences: preferences, preferencePrefix: "fixture", player: player,
            seekExecutor: { _, time, completion in
                probe.targets.append(time.seconds)
                probe.completions.append(completion)
            },
            measuredTime: { _ in probe.mediaSeconds }, monotonicTime: { probe.now },
            waitForSeekDeadline: { try await probe.deadline.wait() }
        )
        return (audio, probe)
    }

    private func drainCallbacks() async {
        for _ in 0..<5 { await Task.yield() }
    }

    private final class SeekProbe {
        var mediaSeconds: Double = 2
        var now: TimeInterval = 0
        var targets: [Double] = []
        var completions: [@Sendable (Bool) -> Void] = []
        let deadline = SeekDeadlineGate()
    }
}

/// Simulates the transient window exposed by a partially loaded HTTP VOD item.
/// Unlike mocking only the bounds helper, this verifies the service's actual
/// CMTime argument sent to its AVPlayer seek executor for several distinct cues.
private final class ProvisionalSeekableItem: AVPlayerItem {
    override var seekableTimeRanges: [NSValue] {
        [NSValue(timeRange: CMTimeRange(start: .zero,
                                      duration: CMTime(seconds: 0.01, preferredTimescale: 1000)))]
    }
}

/// Controllable one-shot deadline, independent of playback timers and wall-clock sleeps.
private actor SeekDeadlineGate {
    private var expired = false
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    func wait() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if expired {
                    continuation.resume()
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func expire() {
        expired = true
        let pending = waiters.values
        waiters.removeAll()
        for continuation in pending { continuation.resume() }
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}
