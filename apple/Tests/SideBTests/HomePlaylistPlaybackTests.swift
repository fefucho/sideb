import Foundation
import AVFoundation
import Testing
import SideBCore
@testable import SideB

private enum HomePlaylistPlaybackError: Error { case failed }

private actor HomeCollectionRequests<Value: Sendable> {
    private var pending: [String: CheckedContinuation<Value, Error>] = [:]
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    func load(_ id: String) async throws -> Value {
        try await withCheckedThrowingContinuation {
            pending[id] = $0
            waiters.removeValue(forKey: id)?.forEach { $0.resume() }
        }
    }
    func wait(_ id: String) async {
        guard pending[id] == nil else { return }
        await withCheckedContinuation { waiters[id, default: []].append($0) }
    }
    func finish(_ id: String, _ result: Result<Value, Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }
}

private final class HomePlaylistPlaybackCore: SideBCore, @unchecked Sendable {
    let playlists = HomeCollectionRequests<PlaylistDetailRecord>()
    let pages = HomeCollectionRequests<PlaylistContinuationRecord>()
    let albums = HomeCollectionRequests<AlbumDetailRecord>()
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { false }
    override func getSetting(key: String) -> String? { nil }
    override func getGeniusCached(track: GeniusTrackRecord) async -> GeniusResolutionRecord? { nil }
    override func resolveStream(videoId: String, isUpload: Bool) async throws -> StreamPlaybackInfo { throw HomePlaylistPlaybackError.failed }
    override func getLyrics(videoId: String, title: String, artist: String, album: String?, durationSecs: UInt64?) async throws -> LyricsInfo? { nil }
    override func getPlaylist(playlistId: String) async throws -> PlaylistDetailRecord { try await playlists.load(playlistId) }
    override func getPlaylistContinuation(token: String) async throws -> PlaylistContinuationRecord { try await pages.load(token) }
    override func getAlbum(browseId: String) async throws -> AlbumDetailRecord { try await albums.load(browseId) }
}

private func collectionTrack(_ id: String) -> SongItemRecord {
    SongItemRecord(videoId: id, title: id, artists: "Artist", album: nil,
        duration: nil, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
        isVideo: false, isUpload: false, library: nil)
}
private func recommendedPlaylist(_ id: String, tracks: [SongItemRecord], continuation: String? = nil) -> PlaylistDetailRecord {
    PlaylistDetailRecord(id: id, title: "Recommended playlist", subtitle: nil, thumbnail: nil,
        description: nil, items: tracks, continuation: continuation, owned: false, inLibrary: false,
        privacy: nil, collaborative: false, sort: nil, sortEditable: false)
}
private func recommendedAlbum(_ id: String) -> AlbumDetailRecord {
    AlbumDetailRecord(browseId: id, title: "Recommended album", artist: "Artist", artistId: nil,
        subtitle: nil, secondSubtitle: nil, description: nil, thumbnail: nil, playlistId: nil,
        inLibrary: false, items: [collectionTrack("album-track")], sections: [])
}
@MainActor private func recommendedCollectionPlayer(_ core: SideBCore) -> PlayerViewModel {
    let audio = AudioPlayerService(preferences: UserDefaults(suiteName: "HomePlaylist.\(UUID())")!, preferencePrefix: "test")
    return PlayerViewModel(rustCore: core, audioService: audio,
        playbackStore: PlaybackStateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        playlistCatalog: PlaylistCatalog())
}
@MainActor private func awaitRecommendedCollection(_ player: PlayerViewModel) async {
    for _ in 0..<1_000 where player.loadingRecommendedAlbumID != nil || player.loadingRecommendedPlaylistID != nil {
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(player.loadingRecommendedAlbumID == nil)
    #expect(player.loadingRecommendedPlaylistID == nil)
}

@Test @MainActor func homePlaylistWaitsForFullCatalogAndShuffleRestoresAllOccurrences() async {
    let core = HomePlaylistPlaybackCore()
    let player = recommendedCollectionPlayer(core)
    let initial = [collectionTrack("first"), collectionTrack("duplicate")]
    let tail = [collectionTrack("last"), collectionTrack("duplicate")]
    player.queueManager.replaceQueue(with: [collectionTrack("existing")])
    let originalToken = player.queueManager.queueToken
    player.playRecommendedPlaylist(browseId: "VLPL-recommended", shuffle: true)
    await core.playlists.wait("PL-recommended")
    await core.playlists.finish("PL-recommended", .success(recommendedPlaylist("PL-recommended", tracks: initial, continuation: "next")))
    await core.pages.wait("next")
    #expect(player.queueManager.queueToken == originalToken)
    #expect(player.loadingRecommendedPlaylistID == "VLPL-recommended")
    await core.pages.finish("next", .success(PlaylistContinuationRecord(items: tail, continuation: nil)))
    await awaitRecommendedCollection(player)
    #expect(player.currentPlaylistBrowseId == "VLPL-recommended")
    #expect(player.currentAlbumBrowseId == nil)
    #expect(player.queueManager.queue.count == 4)
    #expect(player.queueManager.isShuffle)
    player.queueManager.setShuffle(false)
    #expect(player.queueManager.queue == initial + tail)
    #expect(player.queueManager.queue.filter { $0.videoId == "duplicate" }.count == 2)
    #expect(player.audioService.avPlayer.currentItem == nil)
    player.audioService.stop()
}

@Test @MainActor func homePlaylistPageFailurePreservesExistingAudioAndQueue() async {
    let core = HomePlaylistPlaybackCore()
    let player = recommendedCollectionPlayer(core)
    player.queueManager.replaceQueue(with: [collectionTrack("existing")])
    let token = player.queueManager.queueToken
    let item = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/home-playlist-fixture.m4a"))
    player.audioService.avPlayer.replaceCurrentItem(with: item)
    player.playRecommendedPlaylist(browseId: "PL-failure")
    await core.playlists.wait("PL-failure")
    await core.playlists.finish("PL-failure", .success(recommendedPlaylist("PL-failure", tracks: [collectionTrack("partial")], continuation: "failed-page")))
    await core.pages.wait("failed-page")
    await core.pages.finish("failed-page", .failure(HomePlaylistPlaybackError.failed))
    await awaitRecommendedCollection(player)
    #expect(player.queueManager.queueToken == token)
    #expect(player.audioService.avPlayer.currentItem === item)
    #expect(player.errorMessage == PlaylistCatalogError.fetchFailed(HomePlaylistPlaybackError.failed.localizedDescription).appMessage.text)
    player.audioService.stop()
}

@Test @MainActor func homeAlbumSupersedesPendingPlaylistWithoutLosingLoadingState() async {
    let core = HomePlaylistPlaybackCore()
    let player = recommendedCollectionPlayer(core)
    player.playRecommendedPlaylist(browseId: "PL-old")
    await core.playlists.wait("PL-old")
    player.playRecommendedAlbum(browseId: "new-album")
    await core.albums.wait("new-album")
    await core.playlists.finish("PL-old", .success(recommendedPlaylist("PL-old", tracks: [collectionTrack("old")])))
    for _ in 0..<30 { await Task.yield() }
    #expect(player.loadingRecommendedPlaylistID == nil)
    #expect(player.loadingRecommendedAlbumID == "new-album")
    #expect(player.queueManager.queue.isEmpty)
    await core.albums.finish("new-album", .success(recommendedAlbum("new-album")))
    await awaitRecommendedCollection(player)
    #expect(player.currentAlbumBrowseId == "new-album")
    #expect(player.currentPlaylistBrowseId == nil)
    #expect(player.queueManager.queue.map(\.videoId) == ["album-track"])
    player.audioService.stop()
}

@Test @MainActor func homePlaylistPendingResponseCannotReplaceManuallyChangedQueue() async {
    let core = HomePlaylistPlaybackCore()
    let player = recommendedCollectionPlayer(core)
    player.playRecommendedPlaylist(browseId: "PL-pending")
    await core.playlists.wait("PL-pending")
    let replacement = [collectionTrack("replacement")]
    player.queueManager.replaceQueue(with: replacement)
    await core.playlists.finish("PL-pending", .success(recommendedPlaylist("PL-pending", tracks: [collectionTrack("stale")])))
    await awaitRecommendedCollection(player)
    #expect(player.queueManager.queue == replacement)
    #expect(player.currentPlaylistBrowseId == nil)
}

@Test @MainActor func homePlaylistAccountChangeDiscardsPendingPrivateCatalog() async {
    let core = HomePlaylistPlaybackCore()
    let player = recommendedCollectionPlayer(core)
    player.switchPlaybackSession(to: "A")
    player.playRecommendedPlaylist(browseId: "PL-account")
    await core.playlists.wait("PL-account")
    player.switchPlaybackSession(to: "B")
    await core.playlists.finish("PL-account", .success(recommendedPlaylist("PL-account", tracks: [collectionTrack("private-A")])))
    for _ in 0..<30 { await Task.yield() }
    #expect(player.loadingRecommendedPlaylistID == nil)
    #expect(player.queueManager.queue.isEmpty)
    #expect(player.currentTrack == nil)
    // A new request for the same ID must fetch B's data, not the stale A result.
    player.playRecommendedPlaylist(browseId: "PL-account")
    await core.playlists.wait("PL-account")
    await core.playlists.finish("PL-account", .success(recommendedPlaylist("PL-account", tracks: [collectionTrack("private-B")])))
    await awaitRecommendedCollection(player)
    #expect(player.queueManager.queue.map(\.videoId) == ["private-B"])
    player.audioService.stop()
}
