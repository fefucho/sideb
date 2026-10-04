import Foundation
import AVFoundation
import Testing
import SideBCore
@testable import SideB

private enum PlaylistPlaybackLatencyError: Error { case failed }

private actor PlaylistPlaybackLatencyRequests<Value: Sendable> {
    private var pending: [String: CheckedContinuation<Value, Error>] = [:]

    func load(_ key: String) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            pending[key] = continuation
        }
    }

    func wait(_ key: String) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while pending[key] == nil, ContinuousClock.now < deadline { await Task.yield() }
        #expect(pending[key] != nil)
    }

    func finish(_ key: String, with result: Result<Value, Error>) {
        pending.removeValue(forKey: key)?.resume(with: result)
    }

    func resumeAll(with result: Value) {
        let continuations = Array(pending.values)
        pending.removeAll()
        continuations.forEach { $0.resume(returning: result) }
    }
}

private actor PlaylistPlaybackLatencyStreamLog {
    private var resolved: Set<String> = []

    func record(_ videoID: String) {
        resolved.insert(videoID)
    }

    func wait(_ videoID: String) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !resolved.contains(videoID), ContinuousClock.now < deadline { await Task.yield() }
        #expect(resolved.contains(videoID))
    }
}

private final class PlaylistPlaybackLatencyCore: SideBCore, @unchecked Sendable {
    let pages = PlaylistPlaybackLatencyRequests<PlaylistContinuationRecord>()
    let streams = PlaylistPlaybackLatencyStreamLog()

    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        super.init(unsafeFromRawPointer: pointer)
    }

    init() { super.init(noPointer: .init()) }

    override func isLoggedIn() -> Bool { false }
    override func getSetting(key: String) -> String? { nil }
    override func getGeniusCached(track: GeniusTrackRecord) async -> GeniusResolutionRecord? { nil }
    override func getLyrics(videoId: String, title: String, artist: String, album: String?, durationSecs: UInt64?) async throws -> LyricsInfo? { nil }

    override func getPlaylistContinuation(token: String) async throws -> PlaylistContinuationRecord {
        try await pages.load(token)
    }

    override func resolveStream(videoId: String, isUpload: Bool) async throws -> StreamPlaybackInfo {
        await streams.record(videoId)
        return StreamPlaybackInfo(videoId: videoId, streamUrl: URL(fileURLWithPath: "/tmp/sideb-playlist-latency-\(videoId).m4a").absoluteString,
            itag: 140, loudnessDb: nil, expiresInSeconds: 3_600, isVideo: false, streamClient: "test",
            title: videoId, artists: "Artist", duration: "120", thumbnail: nil, headers: [:])
    }
}

private func latencyTrack(_ id: String) -> SongItemRecord {
    SongItemRecord(videoId: id, title: id, artists: "Artist", album: nil, duration: nil,
        thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
        isVideo: false, isUpload: false, library: nil)
}

@MainActor private func latencyPlayer(_ core: SideBCore) -> PlayerViewModel {
    let audio = AudioPlayerService(preferences: UserDefaults(suiteName: "PlaylistLatency.\(UUID())")!, preferencePrefix: "test")
    return PlayerViewModel(rustCore: core, audioService: audio,
        playbackStore: PlaybackStateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        playlistCatalog: PlaylistCatalog())
}

@MainActor private func waitForLatencyPlayback(_ player: PlayerViewModel, videoID: String) async {
    for _ in 0..<1_000 where player.streamInfo?.videoId != videoID || player.audioService.avPlayer.currentItem == nil {
        await Task.yield()
    }
    #expect(player.currentTrack?.videoId == videoID)
    #expect(player.streamInfo?.videoId == videoID)
    #expect(player.audioService.avPlayer.currentItem != nil)
}

@MainActor private func stopLatencyPlayback(_ player: PlayerViewModel, core: PlaylistPlaybackLatencyCore) async {
    await core.pages.resumeAll(with: PlaylistContinuationRecord(items: [], continuation: nil))
    player.audioService.stop()
}

@Test @MainActor func playlistStartsFromLoadedPrefixAndLatePagePreservesActiveAudioAndOccurrence() async {
    let core = PlaylistPlaybackLatencyCore()
    let player = latencyPlayer(core)
    let originalItem = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/playlist-latency-old.m4a"))
    player.audioService.avPlayer.replaceCurrentItem(with: originalItem)
    let prefix = [latencyTrack("prefix-0"), latencyTrack("prefix-1"), latencyTrack("prefix-2")]

    player.playPlaylist(browseId: "PL-latency", title: "Latency", tracks: prefix,
        startingAt: 1, continuation: "page-1")
    await core.pages.wait("page-1")
    await core.streams.wait("prefix-1")
    await waitForLatencyPlayback(player, videoID: "prefix-1")

    let token = player.queueManager.queueToken
    let occurrence = player.queueManager.currentOccurrenceID
    let activeItem = player.audioService.avPlayer.currentItem
    player.audioService.duration = 180
    player.audioService.currentTime = 42.5
    let activeDuration = player.audioService.duration
    let activeTime = player.audioService.currentTime
    player.activateMediaCollection(id: "PL-latency", kind: "playlist")
    #expect(player.isLoadingPlaylistContinuation)
    player.activateMediaCollection(id: "PL-latency", kind: "playlist")
    #expect(player.isLoadingPlaylistContinuation)
    #expect(player.queueManager.currentIndex == 1)
    #expect(player.streamInfo?.videoId == "prefix-1")
    #expect(activeItem !== originalItem)

    await core.pages.finish("page-1", with: .success(PlaylistContinuationRecord(
        items: [latencyTrack("suffix-0"), latencyTrack("suffix-1")], continuation: nil)))
    for _ in 0..<30 where player.queueManager.queue.count < 5 { await Task.yield() }

    #expect(player.queueManager.queue.map(\.videoId) == ["prefix-0", "prefix-1", "prefix-2", "suffix-0", "suffix-1"])
    #expect(player.queueManager.queueToken == token)
    #expect(player.queueManager.currentOccurrenceID == occurrence)
    #expect(player.queueManager.currentTrack?.videoId == "prefix-1")
    #expect(player.audioService.avPlayer.currentItem === activeItem)
    #expect(player.audioService.duration == activeDuration)
    #expect(player.audioService.currentTime == activeTime)
    #expect(player.streamInfo?.videoId == "prefix-1")
    await stopLatencyPlayback(player, core: core)
}

@Test @MainActor func playlistPageCompletionKeepsTrackSelectedWhileContinuationIsPending() async {
    let core = PlaylistPlaybackLatencyCore()
    let player = latencyPlayer(core)
    player.playPlaylist(browseId: "PL-advance", title: "Advance", tracks: [
        latencyTrack("first"), latencyTrack("second"), latencyTrack("third")
    ], continuation: "advance-page")
    await core.pages.wait("advance-page")
    await core.streams.wait("first")
    await waitForLatencyPlayback(player, videoID: "first")

    player.playNext(isManualSkip: false)
    await core.streams.wait("second")
    await waitForLatencyPlayback(player, videoID: "second")
    let token = player.queueManager.queueToken
    let occurrence = player.queueManager.currentOccurrenceID
    let item = player.audioService.avPlayer.currentItem

    await core.pages.finish("advance-page", with: .success(PlaylistContinuationRecord(
        items: [latencyTrack("fourth")], continuation: nil)))
    for _ in 0..<30 where player.queueManager.queue.count < 4 { await Task.yield() }

    #expect(player.queueManager.queue.map(\.videoId) == ["first", "second", "third", "fourth"])
    #expect(player.queueManager.queueToken == token)
    #expect(player.queueManager.currentOccurrenceID == occurrence)
    #expect(player.queueManager.currentTrack?.videoId == "second")
    #expect(player.audioService.avPlayer.currentItem === item)
    #expect(player.streamInfo?.videoId == "second")
    await stopLatencyPlayback(player, core: core)
}

@Test @MainActor func playlistContinuationCannotAppendAfterQueueReplacementOrAccountChange() async {
    let core = PlaylistPlaybackLatencyCore()
    let player = latencyPlayer(core)
    player.playPlaylist(browseId: "PL-replaced", title: "Old", tracks: [latencyTrack("old-prefix")], continuation: "stale-page")
    await core.pages.wait("stale-page")
    player.playCollection(tracks: [latencyTrack("replacement")], title: "Replacement")
    let replacementToken = player.queueManager.queueToken
    await core.pages.finish("stale-page", with: .success(PlaylistContinuationRecord(items: [latencyTrack("stale-tail")], continuation: nil)))
    for _ in 0..<30 { await Task.yield() }
    #expect(player.queueManager.queue.map(\.videoId) == ["replacement"])
    #expect(player.queueManager.queueToken == replacementToken)
    #expect(player.currentPlaylistBrowseId == nil)

    player.switchPlaybackSession(to: "account-A")
    player.playPlaylist(browseId: "PL-account", title: "Account", tracks: [latencyTrack("account-prefix")], continuation: "account-page")
    await core.pages.wait("account-page")
    player.switchPlaybackSession(to: "account-B")
    await core.pages.finish("account-page", with: .success(PlaylistContinuationRecord(items: [latencyTrack("private-tail")], continuation: nil)))
    for _ in 0..<30 { await Task.yield() }
    #expect(!player.queueManager.queue.contains(where: { $0.videoId == "private-tail" }))
    #expect(player.currentPlaylistBrowseId == nil)
    await stopLatencyPlayback(player, core: core)
}

@Test @MainActor func playlistPageFailureLeavesEarlyPlaybackAndContinuationAvailable() async {
    let core = PlaylistPlaybackLatencyCore()
    let player = latencyPlayer(core)
    let prefix = [latencyTrack("failure-first"), latencyTrack("failure-second")]
    player.playPlaylist(browseId: "PL-failure", title: "Failure", tracks: prefix, continuation: "retry-page")
    await core.pages.wait("retry-page")
    await core.streams.wait("failure-first")
    await waitForLatencyPlayback(player, videoID: "failure-first")
    let token = player.queueManager.queueToken
    let occurrence = player.queueManager.currentOccurrenceID
    let item = player.audioService.avPlayer.currentItem

    await core.pages.finish("retry-page", with: .failure(PlaylistPlaybackLatencyError.failed))
    for _ in 0..<1_000 where player.isLoadingPlaylistContinuation { await Task.yield() }

    #expect(player.queueManager.queue.map(\.videoId) == prefix.map(\.videoId))
    #expect(player.queueManager.queueToken == token)
    #expect(player.queueManager.currentOccurrenceID == occurrence)
    #expect(player.audioService.avPlayer.currentItem === item)
    #expect(player.streamInfo?.videoId == "failure-first")
    #expect(player.queueManager.continuationToken == "retry-page")
    #expect(!player.isLoadingPlaylistContinuation)
    player.extendPlaylistIfNeeded()
    await core.pages.wait("retry-page")
    await core.pages.finish("retry-page", with: .success(PlaylistContinuationRecord(
        items: [latencyTrack("retried-tail")], continuation: nil)))
    for _ in 0..<1_000 where player.isLoadingPlaylistContinuation { await Task.yield() }
    #expect(player.queueManager.queue.map(\.videoId) == ["failure-first", "failure-second", "retried-tail"])
    #expect(player.queueManager.currentOccurrenceID == occurrence)
    #expect(player.audioService.avPlayer.currentItem === item)
    #expect(player.queueManager.continuationToken == nil)
    await stopLatencyPlayback(player, core: core)
}

@Test @MainActor func shuffledPlaylistWaitsForAllPagesAndTurningShuffleOffRestoresCompleteSource() async {
    let core = PlaylistPlaybackLatencyCore()
    let player = latencyPlayer(core)
    let previous = [latencyTrack("previous")]
    player.queueManager.replaceQueue(with: previous)
    let oldToken = player.queueManager.queueToken
    player.playPlaylist(browseId: "PL-shuffle", title: "Shuffle", tracks: [latencyTrack("shuffle-a"), latencyTrack("shuffle-b")],
        continuation: "shuffle-page", shuffle: true)
    await core.pages.wait("shuffle-page")

    #expect(player.queueManager.queueToken == oldToken)
    #expect(player.audioService.avPlayer.currentItem == nil)
    await core.pages.finish("shuffle-page", with: .success(PlaylistContinuationRecord(
        items: [latencyTrack("shuffle-c"), latencyTrack("shuffle-d")], continuation: nil)))
    for _ in 0..<1_000 where player.queueManager.queueToken == oldToken { await Task.yield() }

    #expect(player.queueManager.queueToken != oldToken)
    #expect(player.queueManager.queue.count == 4)
    #expect(player.queueManager.isShuffle)
    #expect(player.queueManager.queue.contains(where: { $0.videoId == "shuffle-c" }))
    let shuffledCurrentID = player.currentTrack?.videoId ?? ""
    await core.streams.wait(shuffledCurrentID)
    await waitForLatencyPlayback(player, videoID: shuffledCurrentID)
    #expect(player.audioService.avPlayer.currentItem != nil)
    player.queueManager.setShuffle(false)
    #expect(player.queueManager.queue.map(\.videoId) == ["shuffle-a", "shuffle-b", "shuffle-c", "shuffle-d"])
    await stopLatencyPlayback(player, core: core)
}
