import Foundation
import AVFoundation
import Testing
import SideBCore
@testable import SideB

private enum HomeAlbumError: Error { case failed }
private actor HomeAlbumRequests {
    var pending: [String: CheckedContinuation<AlbumDetailRecord, Error>] = [:]
    func load(_ id: String) async throws -> AlbumDetailRecord {
        try await withCheckedThrowingContinuation { pending[id] = $0 }
    }
    func wait(_ id: String) async {
        while pending[id] == nil { await Task.yield() }
    }
    func finish(_ id: String, result: Result<AlbumDetailRecord, Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }
}
private final class HomeAlbumCore: SideBCore, @unchecked Sendable {
    let requests = HomeAlbumRequests()
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { false }
    override func getSetting(key: String) -> String? { nil }
    override func getGeniusCached(track: GeniusTrackRecord) async -> GeniusResolutionRecord? { nil }
    override func resolveStream(videoId: String, isUpload: Bool) async throws -> StreamPlaybackInfo { throw HomeAlbumError.failed }
    override func getLyrics(videoId: String, title: String, artist: String, album: String?, durationSecs: UInt64?) async throws -> LyricsInfo? { nil }
    override func getAlbum(browseId: String) async throws -> AlbumDetailRecord { try await requests.load(browseId) }
}
private func homeAlbum(_ id: String) -> AlbumDetailRecord {
    let songs = (0..<20).map { index in
        SongItemRecord(videoId: "\(id)-\(index)", title: "Track \(index)", artists: "Artist", album: nil,
            duration: nil, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
            isVideo: false, isUpload: false, library: nil)
    }
    return AlbumDetailRecord(browseId: id, title: id, artist: "Artist", artistId: nil, subtitle: nil,
        secondSubtitle: nil, description: nil, thumbnail: nil, playlistId: nil, inLibrary: false,
        items: songs, sections: [])
}
@MainActor private func homePlayer(_ core: SideBCore) -> PlayerViewModel {
    let audio = AudioPlayerService(preferences: UserDefaults(suiteName: "HomeAlbum.\(UUID())")!, preferencePrefix: "test")
    return PlayerViewModel(rustCore: core, audioService: audio,
        playbackStore: PlaybackStateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
}
@MainActor private func waitForHomeAlbum(_ player: PlayerViewModel) async {
    for _ in 0..<1000 where player.loadingRecommendedAlbumID != nil {
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(player.loadingRecommendedAlbumID == nil)
}

@Test @MainActor func homeAlbumLatestRequestWinsAndShuffleRestoresCanonicalSource() async {
    let core = HomeAlbumCore()
    let player = homePlayer(core)
    player.playRecommendedAlbum(browseId: "old")
    await core.requests.wait("old")
    player.playRecommendedAlbum(browseId: "new", shuffle: true)
    await core.requests.wait("new")
    await core.requests.finish("old", result: .success(homeAlbum("old")))
    await core.requests.finish("new", result: .success(homeAlbum("new")))
    await waitForHomeAlbum(player)
    #expect(player.currentAlbumBrowseId == "new")
    #expect(player.queueManager.isShuffle)
    #expect(player.queueManager.queue.count == 20)
    player.queueManager.setShuffle(false)
    #expect(player.queueManager.queue == homeAlbum("new").items)
    #expect(player.audioService.avPlayer.currentItem == nil)
    player.audioService.stop()
}

@Test @MainActor func homeAlbumFailurePreservesExistingAudioAndQueue() async {
    let core = HomeAlbumCore()
    let player = homePlayer(core)
    player.queueManager.replaceQueue(with: homeAlbum("existing").items)
    let token = player.queueManager.queueToken
    let item = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/home-album-fixture.m4a"))
    player.audioService.avPlayer.replaceCurrentItem(with: item)
    player.playRecommendedAlbum(browseId: "failed")
    await core.requests.wait("failed")
    await core.requests.finish("failed", result: .failure(HomeAlbumError.failed))
    await waitForHomeAlbum(player)
    #expect(player.queueManager.queueToken == token)
    #expect(player.audioService.avPlayer.currentItem === item)
    #expect(player.errorMessage?.contains("No se pudo cargar") == true)
    player.audioService.stop()
}

@Test @MainActor func homeAlbumPendingResponseCannotReplaceNewQueue() async {
    let core = HomeAlbumCore()
    let player = homePlayer(core)
    player.playRecommendedAlbum(browseId: "pending")
    await core.requests.wait("pending")
    player.queueManager.replaceQueue(with: homeAlbum("replacement").items)
    await core.requests.finish("pending", result: .success(homeAlbum("pending")))
    await waitForHomeAlbum(player)
    #expect(player.queueManager.queue == homeAlbum("replacement").items)
    #expect(player.currentAlbumBrowseId == nil)
}

@Test @MainActor func homeAlbumAccountChangeDiscardsPendingResult() async {
    let core = HomeAlbumCore()
    let player = homePlayer(core)
    player.switchPlaybackSession(to: "A")
    player.playRecommendedAlbum(browseId: "account-A")
    await core.requests.wait("account-A")
    player.switchPlaybackSession(to: "B")
    await core.requests.finish("account-A", result: .success(homeAlbum("account-A")))
    for _ in 0..<30 { await Task.yield() }
    #expect(player.loadingRecommendedAlbumID == nil)
    #expect(player.queueManager.queue.isEmpty)
    #expect(player.currentTrack == nil)
}

@Test @MainActor func returningToRadioOriginCancelsPendingCollectionWithoutResettingRadio() async {
    let core = HomeAlbumCore()
    let player = homePlayer(core)
    let songs = homeAlbum("radio").items
    player.queueManager.replaceQueue(with: songs, startingAt: 4,
        context: .radio(seedVideoId: songs[0].videoId, title: "Radio", seedName: songs[0].title))
    player.currentTrack = songs[4]
    let token = player.queueManager.queueToken
    let occurrence = player.queueManager.currentOccurrenceID
    player.activateMediaCollection(id: "pending-card", kind: "album")
    await core.requests.wait("pending-card")
    player.activateMediaRadio(songs[0])
    await core.requests.finish("pending-card", result: .success(homeAlbum("pending-card")))
    for _ in 0..<30 { await Task.yield() }
    #expect(player.queueManager.queueToken == token)
    #expect(player.queueManager.currentOccurrenceID == occurrence)
    #expect(player.currentTrack == songs[4])
    #expect(player.loadingRecommendedAlbumID == nil)
    player.audioService.stop()
}
