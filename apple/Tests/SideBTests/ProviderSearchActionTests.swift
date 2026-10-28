import Foundation
import Testing
import SideBCore
@testable import SideB

private enum ProviderActionError: Error { case unavailable }

private actor ProviderActionGate {
    private var actions: [(String?, String?, String?, CheckedContinuation<NextResultRecord, Error>)] = []
    private var continuations: [(String, CheckedContinuation<NextResultRecord, Error>)] = []
    private var actionWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var continuationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func searchAction(videoId: String?, playlistId: String?, params: String?) async throws -> NextResultRecord {
        try await withCheckedThrowingContinuation { continuation in
            actions.append((videoId, playlistId, params, continuation))
            notify(&actionWaiters, count: actions.count)
        }
    }

    func nextContinuation(token: String) async throws -> NextResultRecord {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append((token, continuation))
            notify(&continuationWaiters, count: continuations.count)
        }
    }

    func waitForAction(_ count: Int) async {
        guard actions.count < count else { return }
        await withCheckedContinuation { actionWaiters.append((count, $0)) }
    }

    func waitForContinuation(_ count: Int) async {
        guard continuations.count < count else { return }
        await withCheckedContinuation { continuationWaiters.append((count, $0)) }
    }

    private func notify(_ waiters: inout [(Int, CheckedContinuation<Void, Never>)], count: Int) {
        let ready = waiters.filter { $0.0 <= count }
        waiters.removeAll { $0.0 <= count }
        ready.forEach { $0.1.resume() }
    }

    func actionArguments(_ index: Int) -> (String?, String?, String?) {
        (actions[index].0, actions[index].1, actions[index].2)
    }
    func continuationToken(_ index: Int) -> String { continuations[index].0 }
    func succeedAction(_ index: Int, _ result: NextResultRecord) { actions[index].3.resume(returning: result) }
    func failAction(_ index: Int) { actions[index].3.resume(throwing: ProviderActionError.unavailable) }
    func succeedContinuation(_ index: Int, _ result: NextResultRecord) { continuations[index].1.resume(returning: result) }
    func failContinuation(_ index: Int) { continuations[index].1.resume(throwing: ProviderActionError.unavailable) }
    func actionCount() -> Int { actions.count }
    func continuationCount() -> Int { continuations.count }
}

private final class ProviderActionCore: SideBCore, @unchecked Sendable {
    let gate = ProviderActionGate()
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { false }
    override func getSetting(key: String) -> String? { nil }
    override func getGeniusCached(track: GeniusTrackRecord) async -> GeniusResolutionRecord? { nil }
    override func getLyrics(videoId: String, title: String, artist: String, album: String?, durationSecs: UInt64?) async throws -> LyricsInfo? { nil }
    override func recordPlayback(videoId: String, songJson: String?, playlistId: String?) async throws {}
    override func getRadio(videoId: String) async throws -> NextResultRecord { throw ProviderActionError.unavailable }
    override func getRadioContinuation(lastVideoId: String, radioSeed: String?) async throws -> NextResultRecord { throw ProviderActionError.unavailable }
    override func searchAction(videoId: String?, playlistId: String?, params: String?) async throws -> NextResultRecord {
        try await gate.searchAction(videoId: videoId, playlistId: playlistId, params: params)
    }
    override func getNextContinuation(token: String) async throws -> NextResultRecord {
        try await gate.nextContinuation(token: token)
    }
    override func resolveStream(videoId: String, isUpload: Bool) async throws -> StreamPlaybackInfo {
        throw ProviderActionError.unavailable
    }
}

@MainActor private func providerActionSong(_ id: String, setVideoId: String?) -> SongItemRecord {
    SongItemRecord(videoId: id, title: id, artists: "Artist", album: nil, duration: nil,
        thumbnail: nil, artistId: nil, albumId: nil, setVideoId: setVideoId,
        isVideo: false, isUpload: false, library: nil)
}

@MainActor private struct ProviderActionFixture {
    let player: PlayerViewModel
    let preferencesSuite: String
    let directory: URL

    func cleanup() {
        player.audioService.stop()
        UserDefaults.standard.removePersistentDomain(forName: preferencesSuite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor private func providerActionPlayer(_ core: ProviderActionCore, suffix: String) -> ProviderActionFixture {
    let suite = "ProviderSearchAction.\(suffix)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SideB-ProviderAction-\(suffix)")
    let player = PlayerViewModel(rustCore: core,
        audioService: AudioPlayerService(preferences: UserDefaults(suiteName: suite)!, preferencePrefix: "test"),
        playbackStore: PlaybackStateStore(directory: directory))
    return ProviderActionFixture(player: player, preferencesSuite: suite, directory: directory)
}

@MainActor private func waitForProviderActionQueue(_ player: PlayerViewModel, count: Int) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while player.queueManager.queue.count < count && ContinuousClock.now < deadline { await Task.yield() }
    #expect(player.queueManager.queue.count >= count)
}

private func nextResult(_ items: [SongItemRecord], continuation: String?) -> NextResultRecord {
    NextResultRecord(items: items, lyricsBrowseId: nil, relatedBrowseId: nil,
        automixPlaylistId: nil, continuation: continuation)
}

@Test @MainActor func providerActionPreservesOpaqueParamsAndContinuationOccurrences() async {
    let core = ProviderActionCore(), fixture = providerActionPlayer(core, suffix: UUID().uuidString), player = fixture.player
    defer { fixture.cleanup() }
    let action = SearchActionRecord(title: "Shuffle", videoId: "repeat", playlistId: "RDopaque",
        browseId: nil, params: "opaque+shuffle%3D")

    player.activateProviderSearchAction(action, title: "Provider section")
    await core.gate.waitForAction(1)
    #expect(await core.gate.actionArguments(0).0 == "repeat")
    #expect(await core.gate.actionArguments(0).1 == "RDopaque")
    #expect(await core.gate.actionArguments(0).2 == "opaque+shuffle%3D")
    await core.gate.succeedAction(0, nextResult([providerActionSong("repeat", setVideoId: "set-first")], continuation: "cursor-1"))
    await waitForProviderActionQueue(player, count: 1)
    #expect(player.queueManager.continuationToken == "cursor-1")

    player.extendProviderActionIfNeeded()
    await core.gate.waitForContinuation(1)
    #expect(await core.gate.continuationToken(0) == "cursor-1")
    await core.gate.succeedContinuation(0, nextResult([
        providerActionSong("repeat", setVideoId: "set-second"),
        providerActionSong("repeat", setVideoId: "set-third")
    ], continuation: "cursor-2"))
    let deadline = ContinuousClock.now + .seconds(2)
    while player.isLoadingPlaylistContinuation && ContinuousClock.now < deadline { await Task.yield() }

    #expect(player.queueManager.queue.map(\.videoId) == ["repeat", "repeat", "repeat"])
    #expect(player.queueManager.queue.map(\.setVideoId) == ["set-first", "set-second", "set-third"])
    #expect(player.queueManager.continuationToken == "cursor-2")
}

@Test @MainActor func providerActionResponseCannotReplaceAChangedAccountOrQueue() async {
    do {
        let core = ProviderActionCore(), fixture = providerActionPlayer(core, suffix: UUID().uuidString), player = fixture.player
        defer { fixture.cleanup() }
        player.activateProviderSearchAction(SearchActionRecord(title: "Play", videoId: "private", playlistId: "RDmix",
            browseId: nil, params: "params"), title: "Private")
        await core.gate.waitForAction(1)
        player.switchPlaybackSession(to: "account:B")
        await core.gate.succeedAction(0, nextResult([providerActionSong("private", setVideoId: "private-set")], continuation: "private-cursor"))
        for _ in 0..<100 { await Task.yield() }
        #expect(player.queueManager.queue.isEmpty)
    }

    do {
        let core = ProviderActionCore(), fixture = providerActionPlayer(core, suffix: UUID().uuidString), player = fixture.player
        defer { fixture.cleanup() }
        player.activateProviderSearchAction(SearchActionRecord(title: "Play", videoId: "stale", playlistId: "RDmix",
            browseId: nil, params: "params"), title: "Old result")
        await core.gate.waitForAction(1)
        player.playCollection(tracks: [providerActionSong("replacement", setVideoId: nil)], title: "Replacement")
        await core.gate.succeedAction(0, nextResult([providerActionSong("stale", setVideoId: "stale-set")], continuation: "stale-cursor"))
        for _ in 0..<100 { await Task.yield() }
        #expect(player.queueManager.queue.map(\.videoId) == ["replacement"])
    }
}

@Test @MainActor func providerContinuationRejectsRetiredQueueAndAccountResponses() async {
    do {
        let core = ProviderActionCore(), fixture = providerActionPlayer(core, suffix: UUID().uuidString), player = fixture.player
        defer { fixture.cleanup() }
        player.activateProviderSearchAction(SearchActionRecord(title: "Play", videoId: "seed", playlistId: "RDmix",
            browseId: nil, params: nil), title: "Mix")
        await core.gate.waitForAction(1)
        await core.gate.succeedAction(0, nextResult([providerActionSong("seed", setVideoId: "seed-set")], continuation: "old-account"))
        await waitForProviderActionQueue(player, count: 1)
        player.extendProviderActionIfNeeded()
        await core.gate.waitForContinuation(1)
        player.switchPlaybackSession(to: "account:C")
        await core.gate.succeedContinuation(0, nextResult([providerActionSong("private-tail", setVideoId: "private-set")], continuation: nil))
        for _ in 0..<100 { await Task.yield() }
        #expect(player.queueManager.queue.isEmpty)
    }

    do {
        let core = ProviderActionCore(), fixture = providerActionPlayer(core, suffix: UUID().uuidString), player = fixture.player
        defer { fixture.cleanup() }
        player.activateProviderSearchAction(SearchActionRecord(title: "Play", videoId: "seed", playlistId: "RDmix",
            browseId: nil, params: nil), title: "Mix")
        await core.gate.waitForAction(1)
        await core.gate.succeedAction(0, nextResult([providerActionSong("seed", setVideoId: "seed-set")], continuation: "old-queue"))
        await waitForProviderActionQueue(player, count: 1)
        player.extendProviderActionIfNeeded()
        await core.gate.waitForContinuation(1)
        player.playCollection(tracks: [providerActionSong("replacement", setVideoId: nil)], title: "Replacement")
        await core.gate.succeedContinuation(0, nextResult([providerActionSong("stale-tail", setVideoId: "stale-set")], continuation: nil))
        for _ in 0..<100 { await Task.yield() }
        #expect(player.queueManager.queue.map(\.videoId) == ["replacement"])
    }
}

@Test @MainActor func providerContinuationFailureKeepsTokenAvailableForRetry() async {
    let core = ProviderActionCore(), fixture = providerActionPlayer(core, suffix: UUID().uuidString), player = fixture.player
    defer { fixture.cleanup() }
    player.activateProviderSearchAction(SearchActionRecord(title: "Play", videoId: "seed", playlistId: "RDmix",
        browseId: nil, params: "opaque"), title: "Mix")
    await core.gate.waitForAction(1)
    await core.gate.succeedAction(0, nextResult([providerActionSong("seed", setVideoId: "seed-set")], continuation: "retry-cursor"))
    await waitForProviderActionQueue(player, count: 1)

    player.extendProviderActionIfNeeded()
    await core.gate.waitForContinuation(1)
    await core.gate.failContinuation(0)
    let deadline = ContinuousClock.now + .seconds(2)
    while player.isLoadingPlaylistContinuation && ContinuousClock.now < deadline { await Task.yield() }
    #expect(player.queueManager.continuationToken == "retry-cursor")
    #expect(player.queueManager.queue.map(\.videoId) == ["seed"])

    player.extendProviderActionIfNeeded()
    await core.gate.waitForContinuation(2)
    #expect(await core.gate.continuationToken(1) == "retry-cursor")
    await core.gate.succeedContinuation(1, nextResult([providerActionSong("tail", setVideoId: "tail-set")], continuation: nil))
    let retryDeadline = ContinuousClock.now + .seconds(2)
    while player.isLoadingPlaylistContinuation && ContinuousClock.now < retryDeadline { await Task.yield() }
    #expect(player.queueManager.queue.map(\.videoId) == ["seed", "tail"])
    #expect(player.queueManager.continuationToken == nil)
    #expect(await core.gate.continuationCount() == 2)
}
