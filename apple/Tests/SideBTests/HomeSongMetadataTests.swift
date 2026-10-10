import Foundation
import Testing
import AVFoundation
import SideBCore
@testable import SideB

private func quickSongItem(_ count: String = "337M plays", albumID: String? = "MPRE-blonde") -> HomeItemRecord {
    HomeItemRecord(kind: "song", id: "pink-white", title: "Pink + White",
        subtitle: "Frank Ocean • \(count)", thumbnail: nil, duration: "3:04", artists: "Frank Ocean",
        artistId: "UCfrank", album: count, albumId: albumID,
        artistRuns: [.init(text: "Frank Ocean", id: "UCfrank")], explicit: true)
}

private func canonicalQuickAlbum(_ name: String = "Blonde", id: String = "MPRE-blonde", video: String = "pink-white") -> AlbumDetailRecord {
    let song = SongItemRecord(videoId: video, title: "Pink + White", artists: "Frank Ocean", album: name,
        duration: "3:04", thumbnail: nil, artistId: "UCfrank", albumId: id, setVideoId: nil,
        isVideo: false, isUpload: false, library: nil)
    return AlbumDetailRecord(browseId: id, title: name, artist: "Frank Ocean", artistId: "UCfrank",
        subtitle: "2016", secondSubtitle: nil, description: nil, thumbnail: nil, playlistId: nil,
        inLibrary: false, items: [song], sections: [])
}

@Test @MainActor func quickAccessStatisticsNeverNameAlbumEvenWithItsDestination() {
    for count in ["337M plays", "337M views", "337 M reproducciones", "1,2 millones de vistas", "3:04"] {
        let item = quickSongItem(count)
        let song = SongItemRecord(fromHomeItem: item)
        #expect(song.album == nil)
        #expect(song.displayAlbum == nil)
        #expect(song.albumId == "MPRE-blonde")
        #expect(song.artists == "Frank Ocean")
        #expect(song.artistRuns == item.artistRuns)
        #expect(song.duration == "3:04")
        #expect(HomeItemView.cleanAlbumName(from: item) == nil)
    }
}

@Test @MainActor func quickAccessPreservesCreditsRealNamesAndLegacyAlbumFallback() {
    var item = quickSongItem()
    item.artists = "Frank Ocean • Guest"
    item.artistRuns = []
    item.album = "Blonde"
    #expect(SongItemRecord(fromHomeItem: item).artists == "Frank Ocean, Guest")
    #expect(SongItemRecord(fromHomeItem: item).album == "Blonde")
    #expect(HomeItemView.cleanAlbumName(from: item) == "Blonde")
    let card = BrowseCardRecord(kind: "song", id: "pink-white", title: "Pink + White",
        subtitle: "Song • Frank Ocean • 337M views", thumbnail: nil, duration: "3:04")
    #expect(SongItemRecord(fromCard: card).artists == "Frank Ocean")
    #expect(SongItemRecord(fromCard: card).displayAlbum == nil)
    var song = canonicalQuickAlbum().items[0]
    song.album = nil
    song.artists = "Frank Ocean • Blonde"
    #expect(song.displayAlbum == "Blonde")
    song.artists = "Frank Ocean • 337M plays"
    #expect(song.displayAlbum == nil)
    song.album = "100 Plays" // Explicit canonical data is never a subtitle statistic.
    #expect(song.displayAlbum == "100 Plays")
}

@Test func quickAccessCollaboratorsAndFragmentedCountersCannotCreateFallbackAlbums() {
    var item = quickSongItem()
    item.artistRuns = []
    item.artists = "Frank Ocean • Guest"
    let unlinked = SongItemRecord(fromHomeItem: item)
    #expect(unlinked.displayArtist == "Frank Ocean, Guest")
    #expect(unlinked.displayAlbum == nil)
    item.artistRuns = [.init(text: "Frank Ocean", id: "UCfrank"), .init(text: " • ", id: nil),
        .init(text: "Guest", id: "UCguest"), .init(text: " • ", id: nil),
        .init(text: "337M", id: nil), .init(text: " plays", id: nil)]
    let linked = SongItemRecord(fromHomeItem: item)
    #expect(linked.displayArtist == "Frank Ocean, Guest")
    #expect(linked.displayAlbum == nil)
    #expect(linked.artistRuns.map(\.text) == ["Frank Ocean", ", ", "Guest"])
    #expect(linked.artistRuns.compactMap(\.id) == ["UCfrank", "UCguest"])
    item.artistRuns = [.init(text: "Views", id: "UCviews"), .init(text: " & ", id: nil),
        .init(text: "100 Plays", id: "UCplays")]
    #expect(SongItemRecord(fromHomeItem: item).artistRuns == item.artistRuns)
    #expect(SongItemRecord(fromHomeItem: item).artists == "Views & 100 Plays")
}

@Test func albumEnrichmentRequiresMatchingVideoAndDestinationAndPreservesAllOtherFields() {
    var seed = SongItemRecord(fromHomeItem: quickSongItem())
    seed.setVideoId = "provider-occurrence"
    seed.isVideo = true
    seed.isUpload = true
    seed.library = LibraryToggleRecord(inLibrary: true, addToken: "fixture-add", removeToken: "fixture-remove")
    let album = canonicalQuickAlbum("100 Plays")
    var expected = seed
    expected.album = "100 Plays"
    #expect(PlaybackAlbumMetadata.merging(seed, album: album) == expected)
    #expect(PlaybackAlbumMetadata.merging(seed, radio: album.items[0]) == seed)
    #expect(PlaybackAlbumMetadata.merging(seed, radio: canonicalQuickAlbum().items[0]).album == "Blonde")
    #expect(PlaybackAlbumMetadata.merging(seed, album: canonicalQuickAlbum(id: "MPRE-other")) == seed)
    #expect(PlaybackAlbumMetadata.merging(seed, album: canonicalQuickAlbum(video: "other-video")) == seed)
    #expect(PlaybackAlbumMetadata.merging(seed, radio: canonicalQuickAlbum(id: "MPRE-other").items[0]) == seed)
    #expect(PlaybackAlbumMetadata.merging(expected, album: canonicalQuickAlbum()) == expected)
    #expect(PlaybackAlbumMetadata.merging(expected, radio: canonicalQuickAlbum().items[0]) == expected)
    var missingDestination = seed
    missingDestination.albumId = nil
    let ambiguousRadio = canonicalQuickAlbum("337M views").items[0]
    let knownDestination = PlaybackAlbumMetadata.merging(missingDestination, radio: ambiguousRadio)
    #expect(knownDestination.album == nil)
    #expect(knownDestination.albumId == "MPRE-blonde")
}

private enum QuickMetadataError: Error { case unavailable }
private actor QuickMetadataRequests {
    private var next = 0
    private var pending: [Int: CheckedContinuation<AlbumDetailRecord, Error>] = [:]
    var startedCount: Int { next }
    func load() async throws -> AlbumDetailRecord {
        let index = next; next += 1
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func waitFor(_ index: Int) async {
        let clock = ContinuousClock(); let deadline = clock.now.advanced(by: .seconds(2))
        while pending[index] == nil, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(pending[index] != nil)
    }
    func finish(_ index: Int, _ result: Result<AlbumDetailRecord, Error>) {
        pending.removeValue(forKey: index)?.resume(with: result)
    }
}

private actor QuickRadioRequests {
    private var pending: CheckedContinuation<NextResultRecord, Error>?
    func load() async throws -> NextResultRecord {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func wait() async {
        let clock = ContinuousClock(); let deadline = clock.now.advanced(by: .seconds(2))
        while pending == nil, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(pending != nil)
    }
    func finish(_ songs: [SongItemRecord]) {
        let request = pending; pending = nil
        request?.resume(returning: NextResultRecord(items: songs, lyricsBrowseId: nil, relatedBrowseId: nil,
            automixPlaylistId: nil, continuation: nil))
    }
}

private final class QuickMetadataCore: SideBCore, @unchecked Sendable {
    let requests = QuickMetadataRequests()
    let radioRequests = QuickRadioRequests()
    let holdRadio: Bool
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { holdRadio = false; super.init(unsafeFromRawPointer: pointer) }
    init(holdRadio: Bool = false) { self.holdRadio = holdRadio; super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { false }
    override func getSetting(key: String) -> String? { nil }
    override func getGeniusCached(track: GeniusTrackRecord) async -> GeniusResolutionRecord? { nil }
    override func resolveStream(videoId: String, isUpload: Bool) async throws -> StreamPlaybackInfo { throw QuickMetadataError.unavailable }
    override func getLyrics(videoId: String, title: String, artist: String, album: String?, durationSecs: UInt64?) async throws -> LyricsInfo? { nil }
    override func getRadio(videoId: String) async throws -> NextResultRecord {
        if holdRadio { return try await radioRequests.load() }
        return NextResultRecord(items: [], lyricsBrowseId: nil, relatedBrowseId: nil, automixPlaylistId: nil, continuation: nil)
    }
    override func getAlbum(browseId: String) async throws -> AlbumDetailRecord { try await requests.load() }
}

@MainActor private func quickMetadataPlayer(_ core: SideBCore) -> PlayerViewModel {
    let audio = AudioPlayerService(preferences: UserDefaults(suiteName: "QuickMetadata.\(UUID())")!, preferencePrefix: "test")
    return PlayerViewModel(rustCore: core, audioService: audio,
        playbackStore: PlaybackStateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
}

@MainActor private func waitForQuickStream(_ player: PlayerViewModel) async {
    let clock = ContinuousClock(); let deadline = clock.now.advanced(by: .seconds(2))
    while player.isLoadingStream, clock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
    #expect(!player.isLoadingStream)
}

@Test @MainActor func radioStatisticsCannotBlockCanonicalAlbumInEitherArrivalOrder() async {
    for radioFirst in [true, false] {
        let core = QuickMetadataCore(holdRadio: true); let player = quickMetadataPlayer(core)
        let seed = SongItemRecord(fromHomeItem: quickSongItem())
        player.playWithRadio(seed)
        await core.requests.waitFor(0); await core.radioRequests.wait()
        let albumTask = player.albumMetadataTask; let radioTask = player.radioTask
        let occurrence = player.queueManager.currentOccurrenceID
        let statistic = canonicalQuickAlbum("337M views").items[0]
        if radioFirst {
            await core.radioRequests.finish([statistic]); await radioTask?.value
            #expect(player.currentTrack?.album == nil)
            await core.requests.finish(0, .success(canonicalQuickAlbum("100 Plays")))
            await albumTask?.value
        } else {
            await core.requests.finish(0, .success(canonicalQuickAlbum("100 Plays"))); await albumTask?.value
            await core.radioRequests.finish([statistic])
            await radioTask?.value
        }
        #expect(player.currentTrack?.album == "100 Plays")
        #expect(player.queueManager.currentTrack?.album == "100 Plays")
        #expect(player.queueManager.currentOccurrenceID == occurrence)
        #expect(await core.requests.startedCount == 1)
    }
}

@Test @MainActor func oldRadioCannotEnrichNewPlaybackTokenOfTheSameVideo() async {
    let core = QuickMetadataCore(holdRadio: true); let player = quickMetadataPlayer(core)
    let song = canonicalQuickAlbum().items[0]
    player.playWithRadio(song)
    await core.radioRequests.wait()
    let oldRadioTask = player.radioTask
    player.playSongNow(song)
    let order = player.queueManager.orderSnapshot
    await core.radioRequests.finish(canonicalQuickAlbum(video: "unexpected-next").items)
    await oldRadioTask?.value
    #expect(player.currentTrack == song)
    #expect(player.queueManager.orderSnapshot == order)
    #expect(player.queueManager.queue == [song])
}

@Test @MainActor func albumCanonicalTitleUpdatesOnlyActiveOccurrenceWithoutReloadingAudio() async {
    let core = QuickMetadataCore(); let player = quickMetadataPlayer(core)
    let seed = SongItemRecord(fromHomeItem: quickSongItem())
    player.queueManager.replaceQueue(with: [seed, seed], startingAt: 1)
    player.playSongNow(seed)
    await core.requests.waitFor(0)
    let task = player.albumMetadataTask
    await waitForQuickStream(player)
    let audioItem = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/quick-metadata-fixture.m4a"))
    player.audioService.avPlayer.replaceCurrentItem(with: audioItem)
    let order = player.queueManager.orderSnapshot; let token = player.queueManager.queueToken
    await core.requests.finish(0, .success(canonicalQuickAlbum("100 Plays")))
    await task?.value
    #expect(player.currentTrack?.album == "100 Plays")
    #expect(player.currentTrack?.albumId == "MPRE-blonde")
    #expect(player.queueManager.queue[1].album == "100 Plays")
    #expect(player.queueManager.queue[0].album == nil)
    #expect(player.queueManager.orderSnapshot == order)
    #expect(player.queueManager.queueToken == token)
    #expect(player.audioService.avPlayer.currentItem === audioItem)
    player.audioService.stop()
}

@Test @MainActor func albumFailureKeepsDestinationAndCannotReintroduceCounter() async {
    let core = QuickMetadataCore(); let player = quickMetadataPlayer(core)
    player.playWithRadio(SongItemRecord(fromHomeItem: quickSongItem()))
    await core.requests.waitFor(0)
    let task = player.albumMetadataTask
    await waitForQuickStream(player)
    let order = player.queueManager.orderSnapshot; let streamError = player.errorMessage
    await core.requests.finish(0, .failure(QuickMetadataError.unavailable))
    await task?.value
    #expect(player.currentTrack?.displayAlbum == nil)
    #expect(player.currentAlbumBrowseId == "MPRE-blonde")
    #expect(player.currentTrack?.albumId == "MPRE-blonde")
    #expect(player.queueManager.orderSnapshot == order)
    #expect(player.errorMessage == streamError)
}

@Test @MainActor func lateAlbumCannotUpdateNewPlaybackOfTheSameVideo() async {
    let core = QuickMetadataCore(); let player = quickMetadataPlayer(core)
    let seed = SongItemRecord(fromHomeItem: quickSongItem())
    player.playWithRadio(seed)
    await core.requests.waitFor(0)
    let oldTask = player.albumMetadataTask
    player.playSongNow(seed) // Same queue/occurrence/video; only the playback token changes.
    await core.requests.waitFor(1)
    let occurrence = player.queueManager.currentOccurrenceID
    let newTask = player.albumMetadataTask
    await core.requests.finish(0, .success(canonicalQuickAlbum("OLD")))
    await oldTask?.value
    #expect(player.currentTrack?.album == nil)
    #expect(player.queueManager.currentTrack?.album == nil)
    await core.requests.finish(1, .success(canonicalQuickAlbum()))
    await newTask?.value
    #expect(player.currentTrack?.album == "Blonde")
    #expect(player.queueManager.currentOccurrenceID == occurrence)
}

@Test @MainActor func lateAlbumCannotCrossAccountOrQueueReplacement() async {
    let core = QuickMetadataCore(); let player = quickMetadataPlayer(core)
    let seed = SongItemRecord(fromHomeItem: quickSongItem())
    player.playWithRadio(seed)
    await core.requests.waitFor(0)
    let accountTask = player.albumMetadataTask
    player.clearAccountState()
    await core.requests.finish(0, .success(canonicalQuickAlbum("ACCOUNT A")))
    await accountTask?.value
    #expect(player.currentTrack?.album == nil)
    player.playWithRadio(seed)
    await core.requests.waitFor(1)
    let queueTask = player.albumMetadataTask
    player.queueManager.replaceQueue(with: [seed, seed], startingAt: 1)
    let replacementOrder = player.queueManager.orderSnapshot
    await core.requests.finish(1, .success(canonicalQuickAlbum("OLD QUEUE")))
    await queueTask?.value
    #expect(player.currentTrack?.album == nil)
    #expect(player.queueManager.orderSnapshot == replacementOrder)
    #expect(player.queueManager.queue.allSatisfy { $0.album == nil })
}
