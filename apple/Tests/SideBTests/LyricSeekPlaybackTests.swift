import AVFoundation
import Foundation
import SideBCore
import Testing
@testable import SideB

private enum LyricSeekTestError: Error { case expected }
private actor LyricSeekRequests {
    private var requests: [CheckedContinuation<StreamPlaybackInfo, Error>] = []
    var count: Int { requests.count }
    func resolve() async throws -> StreamPlaybackInfo {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }
    func waitForCount(_ count: Int) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while requests.count < count && ContinuousClock.now < deadline { await Task.yield() }
        #expect(requests.count >= count)
    }
    func completeFirst(url: URL? = nil) {
        guard !requests.isEmpty else { return }
        let continuation = requests.removeFirst()
        if let url {
            continuation.resume(returning: .init(videoId: "track", streamUrl: url.absoluteString,
                itag: 140, loudnessDb: nil, expiresInSeconds: 300, isVideo: false, streamClient: "fixture",
                title: "track", artists: "fixture", duration: "20", thumbnail: nil, headers: [:]))
        } else { continuation.resume(throwing: LyricSeekTestError.expected) }
    }
}
private final class LyricSeekCore: SideBCore, @unchecked Sendable {
    let requests = LyricSeekRequests()
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func resolveStream(videoId: String, isUpload: Bool) async throws -> StreamPlaybackInfo { try await requests.resolve() }
    override func isLoggedIn() -> Bool { false }
    override func getSetting(key: String) -> String? { nil }
    override func getLyrics(videoId: String, title: String, artist: String, album: String?, durationSecs: UInt64?) async throws -> LyricsInfo? { nil }
    override func getGeniusCached(track: GeniusTrackRecord) async -> GeniusResolutionRecord? { nil }
    override func recordPlayback(videoId: String, songJson: String?, playlistId: String?) async throws {}
}

@Suite("Seek de letras: reproducción restaurada y ocurrencias")
@MainActor
struct LyricSeekPlaybackTests {
    private func song(_ id: String = "track") -> SongItemRecord {
        .init(videoId: id, title: id, artists: "fixture", album: nil, duration: nil, thumbnail: nil,
              artistId: nil, albumId: nil, setVideoId: nil, isVideo: false, isUpload: false, library: nil)
    }
    private func player(_ core: SideBCore?, directory: URL) -> PlayerViewModel {
        let audio = AudioPlayerService(preferences: UserDefaults(suiteName: "LyricSeek.\(UUID())")!, preferencePrefix: "fixture")
        audio.volume = 0
        return PlayerViewModel(rustCore: core, audioService: audio,
                               playbackStore: PlaybackStateStore(directory: directory))
    }
    private func waitForResolution(_ player: PlayerViewModel) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while player.isLoadingStream && ContinuousClock.now < deadline { await Task.yield() }
        #expect(!player.isLoadingStream)
    }

    @Test("Invalid cues and an unavailable backend never queue a fabricated seek")
    func invalidCues() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vm = player(nil, directory: directory)
        defer { vm.audioService.stop() }
        #expect(!vm.seekToLyric(seconds: 8))
        vm.currentTrack = song()
        for cue in [Double.nan, .infinity, -1, 8] { #expect(!vm.seekToLyric(seconds: cue)) }
        #expect(vm.pendingLyricSeek == nil)
    }

    @Test("Restored track resolves once and the latest clicked cue wins without requiring duration")
    func queuedCue() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let core = LyricSeekCore(), vm = player(core, directory: directory)
        defer { vm.audioService.stop() }
        vm.currentTrack = song()
        #expect(vm.seekToLyric(seconds: 8))
        await core.requests.waitForCount(1)
        let identity = vm.experimentalLyricsPlaybackIdentity
        #expect(vm.seekToLyric(seconds: 12))
        #expect(vm.experimentalLyricsPlaybackIdentity == identity)
        #expect(vm.pendingLyricSeek?.seconds == 12)
        #expect(await core.requests.count == 1)
        await core.requests.completeFirst()
        await waitForResolution(vm)
        #expect(vm.pendingLyricSeek == nil)
    }

    @Test("Same song as a new occurrence discards the old queued cue and stale completion")
    func repeatedOccurrence() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let core = LyricSeekCore(), vm = player(core, directory: directory)
        defer { vm.audioService.stop() }
        vm.currentTrack = song()
        #expect(vm.seekToLyric(seconds: 8))
        await core.requests.waitForCount(1)
        let old = vm.experimentalLyricsPlaybackIdentity
        vm.playSongNow(song())
        await core.requests.waitForCount(2)
        #expect(vm.experimentalLyricsPlaybackIdentity != old)
        #expect(vm.pendingLyricSeek == nil)
        await core.requests.completeFirst()
        await core.requests.completeFirst()
        await waitForResolution(vm)
        #expect(vm.pendingLyricSeek == nil)
    }

    @Test("Account switch clears the deferred cue and rejects the old resolution")
    func sessionChange() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let core = LyricSeekCore(), vm = player(core, directory: directory)
        defer { vm.audioService.stop() }
        vm.switchPlaybackSession(to: "fixture:A")
        vm.currentTrack = song()
        #expect(vm.seekToLyric(seconds: 8))
        await core.requests.waitForCount(1)
        vm.switchPlaybackSession(to: "fixture:B")
        #expect(vm.pendingLyricSeek == nil)
        await core.requests.completeFirst()
        await Task.yield()
        #expect(vm.currentTrack == nil)
        #expect(vm.audioService.avPlayer.currentItem == nil)
    }

    @Test("Deferred cue reaches the resolved item; seeking a paused item preserves pause")
    func resolvedCueAndPause() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("silence.caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160000))
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
        let core = LyricSeekCore(), vm = player(core, directory: directory.appendingPathComponent("state"))
        defer { vm.audioService.stop() }
        vm.currentTrack = song()
        #expect(vm.seekToLyric(seconds: 8))
        await core.requests.waitForCount(1)
        await core.requests.completeFirst(url: url)
        await waitForResolution(vm)
        #expect(vm.pendingLyricSeek == nil)
        #expect(vm.audioService.seekSnapshot.targetSeconds == 8)
        try await waitForActualSeek(vm, seconds: 8)
        vm.audioService.pause()
        // Exercise different lines in both directions. A requested-target snapshot
        // alone passed the old test even if the AVPlayer stayed at the beginning.
        for cue in [12.0, 3.25, 17.5, 8.0] {
            #expect(vm.seekToLyric(seconds: cue))
            #expect(vm.audioService.seekSnapshot.targetSeconds == cue)
            try await waitForActualSeek(vm, seconds: cue)
            #expect(!vm.audioService.isPlaying)
            #expect(vm.audioService.avPlayer.rate == 0)
        }
    }

    private func waitForActualSeek(_ vm: PlayerViewModel, seconds: Double) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while vm.audioService.seekSnapshot.phase == .pending && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(vm.audioService.seekSnapshot.phase == .completed)
        #expect(abs(vm.audioService.avPlayer.currentTime().seconds - seconds) < 0.25)
        #expect(abs(vm.audioService.currentTime - seconds) < 0.25)
    }
}
