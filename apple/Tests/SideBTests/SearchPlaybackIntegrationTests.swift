import Foundation
import AVFoundation
import Testing
import SideBCore
@testable import SideB

private enum SearchPlaybackError: Error { case unavailable }
private actor SearchStreamRequests {
    private var pending: [String: CheckedContinuation<StreamPlaybackInfo, Error>] = [:]
    func load(_ id: String) async throws -> StreamPlaybackInfo {
        try await withCheckedThrowingContinuation { pending[id] = $0 }
    }
    func wait(_ id: String) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while pending[id] == nil && ContinuousClock.now < deadline { await Task.yield() }
        #expect(pending[id] != nil)
    }
    func succeed(_ id: String, url: URL) {
        pending.removeValue(forKey: id)?.resume(returning: StreamPlaybackInfo(videoId: id, streamUrl: url.absoluteString,
            itag: 140, loudnessDb: nil, expiresInSeconds: 3_600, isVideo: false, streamClient: "test",
            title: id, artists: "Artist", duration: "5", thumbnail: nil, headers: [:]))
    }
    func fail(_ id: String) { pending.removeValue(forKey: id)?.resume(throwing: SearchPlaybackError.unavailable) }
}
private final class SearchPlaybackCore: SideBCore, @unchecked Sendable {
    let requests = SearchStreamRequests()
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { false }
    override func recordPlayback(videoId: String, songJson: String?, playlistId: String?) async throws {}
    override func getSetting(key: String) -> String? { nil }
    override func getGeniusCached(track: GeniusTrackRecord) async -> GeniusResolutionRecord? { nil }
    override func getLyrics(videoId: String, title: String, artist: String, album: String?, durationSecs: UInt64?) async throws -> LyricsInfo? { nil }
    override func getRadio(videoId: String) async throws -> NextResultRecord { throw SearchPlaybackError.unavailable }
    override func resolveStream(videoId: String, isUpload: Bool) async throws -> StreamPlaybackInfo { try await requests.load(videoId) }
}
@MainActor private func searchPlaybackSong(_ id: String) -> SongItemRecord {
    SongItemRecord(videoId: id, title: id, artists: "Artist", album: nil, duration: nil,
        thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil, isVideo: false, isUpload: false, library: nil)
}
@MainActor private func searchPlaybackPlayer(_ core: SearchPlaybackCore, directory: URL, store: SearchRecentStore) -> PlayerViewModel {
    PlayerViewModel(rustCore: core,
        audioService: AudioPlayerService(preferences: UserDefaults(suiteName: "SearchPlayback.\(UUID())")!, preferencePrefix: "test"),
        playbackStore: PlaybackStateStore(directory: directory.appendingPathComponent("playback")), searchRecents: store)
}
@MainActor private func waitForSearchStream(_ player: PlayerViewModel) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while player.isLoadingStream && ContinuousClock.now < deadline { await Task.yield() }
    #expect(!player.isLoadingStream)
}

@Test @MainActor func searchPlaybackFailureDoesNotCreateARecentAndOffersRecovery() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SearchRecentStore(directory: directory), core = SearchPlaybackCore()
    let player = searchPlaybackPlayer(core, directory: directory, store: store)
    defer { player.audioService.stop() }
    player.activateSearchMediaRadio(searchPlaybackSong("selected"))
    await core.requests.wait("selected")
    #expect(store.entries.isEmpty) // Resolving metadata does not mean playback started.
    await core.requests.fail("selected"); await waitForSearchStream(player)
    #expect(store.entries.isEmpty)
    #expect(store.unavailableTrack?.song.videoId == "selected")
}

@Test @MainActor func anotherPlaybackOriginInvalidatesThePendingSpotlightChoice() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SearchRecentStore(directory: directory), core = SearchPlaybackCore()
    let player = searchPlaybackPlayer(core, directory: directory, store: store)
    defer { player.audioService.stop() }
    player.activateSearchMediaRadio(searchPlaybackSong("spotlight"))
    await core.requests.wait("spotlight")
    player.playWithRadio(searchPlaybackSong("album"))
    await core.requests.wait("album")
    await core.requests.fail("spotlight"); await core.requests.fail("album")
    await waitForSearchStream(player)
    #expect(store.entries.isEmpty)
    #expect(store.unavailableTrack == nil)
    #expect(player.currentTrack?.videoId == "album")
}

@Test @MainActor func changingAccountRejectsAStreamFailureFromTheOldSpotlight() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SearchRecentStore(directory: directory), core = SearchPlaybackCore()
    let player = searchPlaybackPlayer(core, directory: directory, store: store)
    defer { player.audioService.stop() }
    player.switchPlaybackSession(to: "account:A")
    store.recordQuery("remember A")
    player.activateSearchMediaRadio(searchPlaybackSong("old"))
    await core.requests.wait("old")
    player.switchPlaybackSession(to: "account:B")
    await core.requests.fail("old")
    await Task.yield()
    #expect(store.entries.isEmpty)
    #expect(store.unavailableTrack == nil)
    #expect(player.currentTrack == nil)
    store.setAccount("account:A")
    #expect(store.entries.first?.query == "remember A")
}

@Test @MainActor func spotlightSuccessfulPlaybackPersistsSelectedSongWithoutQuery() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let audioURL = directory.appendingPathComponent("silence.caf")
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 220_500)!
    buffer.frameLength = buffer.frameCapacity
    buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
    try AVAudioFile(forWriting: audioURL, settings: format.settings).write(from: buffer)
    var uses = 0
    let store = SearchRecentStore(directory: directory.appendingPathComponent("recents"), now: {
        uses += 1; return Date(timeIntervalSince1970: Double(uses))
    }), core = SearchPlaybackCore()
    let player = searchPlaybackPlayer(core, directory: directory, store: store)
    player.audioService.volume = 0
    defer { player.audioService.stop() }
    player.activateSearchMediaRadio(searchPlaybackSong("selected"))
    await core.requests.wait("selected")
    #expect(store.entries.isEmpty)
    await core.requests.succeed("selected", url: audioURL)
    let deadline = ContinuousClock.now + .seconds(5)
    while store.entries.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    #expect(player.audioService.avPlayer.timeControlStatus == .playing)
    #expect(store.entries.count == 1)
    #expect(store.entries.first?.track?.song.videoId == "selected")
    #expect(SearchRecentStore(directory: directory.appendingPathComponent("recents")).entries.first?.track?.song.videoId == "selected")
    try await Task.sleep(for: .milliseconds(250))
    #expect(uses == 1) // Status/progress notifications must not continually reinsert it.
    player.audioService.pause()
    store.clear()
    player.activateSearchMediaRadio(searchPlaybackSong("selected"))
    let resumeDeadline = ContinuousClock.now + .seconds(2)
    while store.entries.isEmpty && ContinuousClock.now < resumeDeadline { try await Task.sleep(for: .milliseconds(20)) }
    #expect(store.entries.first?.track?.song.videoId == "selected")
    #expect(uses == 2)
    store.clear()
    player.playWithRadio(searchPlaybackSong("outside-search"))
    await core.requests.wait("outside-search")
    await core.requests.succeed("outside-search", url: audioURL)
    let autoplayDeadline = ContinuousClock.now + .seconds(2)
    while player.audioService.currentTime < 0.1 && ContinuousClock.now < autoplayDeadline { try await Task.sleep(for: .milliseconds(20)) }
    #expect(player.audioService.currentTime >= 0.1)
    #expect(store.entries.isEmpty)
}
