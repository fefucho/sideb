import Foundation
import AVFoundation
import Testing
import SideBCore
@testable import SideB

private enum DetailViewModelTestError: Error { case expected }

private actor DetailPendingPages {
    private var continuation: CheckedContinuation<PlaylistContinuationRecord, Error>?
    private var pending = false
    func load() async throws -> PlaylistContinuationRecord {
        pending = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func wait() async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !pending && ContinuousClock.now < deadline { await Task.yield() }
        #expect(pending)
    }
    func finish(_ value: PlaylistContinuationRecord) { pending = false; continuation?.resume(returning: value); continuation = nil }
}

private final class DetailViewModelCore: SideBCore, @unchecked Sendable {
    let pages = DetailPendingPages()
    var playlistResult: PlaylistDetailRecord?
    var moveCalls: [(playlistID: String, setID: String, successor: String?)] = []
    var sortCalls: [String] = []
    var rejectsMove = false
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init(playlist: PlaylistDetailRecord? = nil) { playlistResult = playlist; super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { false }
    override func getSetting(key: String) -> String? { nil }
    override func getGeniusCached(track: GeniusTrackRecord) async -> GeniusResolutionRecord? { nil }
    override func getPlaylist(playlistId: String) async throws -> PlaylistDetailRecord {
        guard let playlistResult else { throw DetailViewModelTestError.expected }
        return playlistResult
    }
    override func getPlaylistContinuation(token: String) async throws -> PlaylistContinuationRecord { try await pages.load() }
    override func setPlaylistSort(playlistId: String, sort: String) async throws {
        sortCalls.append(sort)
        playlistResult?.sort = sort
    }
    override func movePlaylistTrack(playlistId: String, setVideoId: String, successorSetVideoId: String?) async throws {
        moveCalls.append((playlistId, setVideoId, successorSetVideoId))
        if rejectsMove { throw DetailViewModelTestError.expected }
        guard var playlist = playlistResult,
              let source = playlist.items.firstIndex(where: { $0.setVideoId == setVideoId }) else { return }
        let track = playlist.items.remove(at: source)
        let destination = successorSetVideoId.flatMap { successor in playlist.items.firstIndex { $0.setVideoId == successor } } ?? playlist.items.count
        playlist.items.insert(track, at: destination)
        playlistResult = playlist
    }
    override func resolveStream(videoId: String, isUpload: Bool) async throws -> StreamPlaybackInfo { throw DetailViewModelTestError.expected }
    override func getLyrics(videoId: String, title: String, artist: String, album: String?, durationSecs: UInt64?) async throws -> LyricsInfo? { nil }
}

private func detailVMTrack(_ id: String, _ title: String, setID: String? = nil) -> SongItemRecord {
    SongItemRecord(videoId: id, title: title, artists: "Artist", album: nil, duration: nil,
                   thumbnail: nil, artistId: nil, albumId: nil, setVideoId: setID,
                   isVideo: false, isUpload: false, library: nil, artistRuns: [])
}

private func detailVMPlaylist(_ id: String, items: [SongItemRecord], continuation: String? = nil,
                              owned: Bool = false, editable: Bool = false) -> PlaylistDetailRecord {
    PlaylistDetailRecord(id: id, title: id, subtitle: nil, thumbnail: nil, description: nil,
                         items: items, continuation: continuation, owned: owned, inLibrary: false,
                         privacy: nil, collaborative: false, sort: nil, sortEditable: editable)
}

@MainActor private func detailVMPlayer(core: SideBCore) -> PlayerViewModel {
    let audio = AudioPlayerService(preferences: UserDefaults(suiteName: "DetailVM.\(UUID())")!, preferencePrefix: "test")
    return PlayerViewModel(rustCore: core, audioService: audio,
                           playbackStore: PlaybackStateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
                           playlistCatalog: PlaylistCatalog())
}

@Test @MainActor func playlistDetailSearchPlaybackKeepsFullSourceAndSelectedDuplicateOccurrence() {
    let core = DetailViewModelCore()
    let first = detailVMTrack("same-video", "First", setID: "occurrence-1")
    let target = detailVMTrack("same-video", "Needle", setID: "occurrence-2")
    let vm = PlaylistDetailViewModel(playlistCatalog: PlaylistCatalog())
    vm.playlist = detailVMPlaylist("PL-test", items: [first, target])
    vm.searchQuery = "needle"
    #expect(vm.displayedEntries.map(\.originalIndex) == [1])

    let player = detailVMPlayer(core: core)
    vm.playDisplayedTrack(at: 0, player: player)
    #expect(player.queueManager.queue.map(\.setVideoId) == ["occurrence-1", "occurrence-2"])
    #expect(player.queueManager.currentTrack?.setVideoId == "occurrence-2")
    #expect(player.queueManager.contextTitle == "Lista: PL-test")
    player.audioService.stop()
}

@Test @MainActor func playlistDetailOnlyAllowsReorderingOwnedEditableDefaultWithOccurrenceIds() {
    let vm = PlaylistDetailViewModel(playlistCatalog: PlaylistCatalog())
    vm.playlist = detailVMPlaylist("PL-own", items: [detailVMTrack("a", "A", setID: "one"), detailVMTrack("b", "B", setID: "two")], owned: true, editable: true)
    #expect(vm.canReorderDisplayedTracks)
    vm.playlist?.continuation = "more"
    #expect(!vm.canReorderDisplayedTracks)
    vm.playlist?.continuation = nil
    vm.searchQuery = "A"
    #expect(!vm.canReorderDisplayedTracks)
    vm.searchQuery = ""
    vm.playlist = detailVMPlaylist("LM", items: [detailVMTrack("a", "A", setID: "one")], owned: true, editable: true)
    #expect(!vm.canReorderDisplayedTracks)
    vm.playlist = detailVMPlaylist("PL-foreign", items: [detailVMTrack("a", "A", setID: "one")])
    #expect(!vm.canReorderDisplayedTracks)
    #expect(!vm.sortIsAvailable(.recentlyAdded))
}

@Test @MainActor func playlistDetailDiscardsCatalogCompletionAfterPlaylistRefresh() async {
    let first = detailVMTrack("a", "Alpha", setID: "a")
    let core = DetailViewModelCore(playlist: detailVMPlaylist("PL-old", items: [first], continuation: "old-page"))
    let vm = PlaylistDetailViewModel(playlistCatalog: PlaylistCatalog())
    await vm.loadPlaylist(core: core, playlistId: "PL-old")
    vm.searchQuery = "Alpha"
    let projection = Task { await vm.prepareDisplayedTracks(core: core) }
    await core.pages.wait()

    core.playlistResult = detailVMPlaylist("PL-new", items: [detailVMTrack("fresh", "Fresh")])
    await vm.loadPlaylist(core: core, playlistId: "PL-new")
    await core.pages.finish(PlaylistContinuationRecord(items: [detailVMTrack("stale", "Stale")], continuation: nil))
    await projection.value

    #expect(vm.playlist?.id == "PL-new")
    #expect(vm.displayedTracks.map(\.title) == ["Fresh"])
    #expect(!vm.isCompletingCatalog)
}

@Test @MainActor func playlistDetailChosenOrderAppliesToEntirePlaybackSourceDespiteFilter() {
    let vm = PlaylistDetailViewModel(playlistCatalog: PlaylistCatalog())
    vm.playlist = detailVMPlaylist("PL-order", items: [detailVMTrack("c", "Charlie"), detailVMTrack("a", "Alpha"), detailVMTrack("b", "Bravo")])
    vm.selectedOrder = .title
    vm.searchQuery = "Bravo"
    let player = detailVMPlayer(core: DetailViewModelCore())
    vm.playDisplayedTrack(at: 0, player: player)
    #expect(player.queueManager.queue.map(\.videoId) == ["a", "b", "c"])
    #expect(player.queueManager.currentIndex == 1)
    #expect(player.queueManager.currentTrack?.videoId == "b")
    player.audioService.stop()
}

@Test @MainActor func playlistDetailDoesNotPlayAPartialAlphabeticalOrder() {
    let vm = PlaylistDetailViewModel(playlistCatalog: PlaylistCatalog())
    vm.playlist = detailVMPlaylist("PL-partial", items: [detailVMTrack("a", "Alpha")], continuation: "more")
    vm.selectedOrder = .title
    let player = detailVMPlayer(core: DetailViewModelCore())
    #expect(vm.needsCompletePlaybackOrder)
    vm.playDisplayedTrack(at: 0, player: player)
    #expect(player.queueManager.queue.isEmpty)
    #expect(vm.errorMessage != nil)
}

@Test @MainActor func playlistDetailCompletesAllTracksAndKeepsTailEditableAfterClearingFilter() async {
    let first = detailVMTrack("a", "Alpha", setID: "first")
    let tail = detailVMTrack("b", "Bravo", setID: "tail")
    let core = DetailViewModelCore(playlist: detailVMPlaylist("PL-own-full", items: [first], continuation: "tail-page", owned: true, editable: true))
    let vm = PlaylistDetailViewModel(playlistCatalog: PlaylistCatalog())
    await vm.loadPlaylist(core: core, playlistId: "PL-own-full")
    vm.searchQuery = "Bravo"
    let load = Task { await vm.prepareDisplayedTracks(core: core) }
    await core.pages.wait()
    await core.pages.finish(PlaylistContinuationRecord(items: [tail], continuation: nil))
    await load.value
    #expect(vm.displayedTracks.map(\.videoId) == ["b"])
    #expect(vm.playlist?.continuation == nil)
    vm.searchQuery = ""
    #expect(vm.displayedTracks.map(\.setVideoId) == ["first", "tail"])
    #expect(vm.canReorderDisplayedTracks)
}

@Test @MainActor func playlistDetailMovesTheSelectedOccurrenceInYouTubeOrderAndRollsBackFailures() async throws {
    let tracks = [detailVMTrack("same", "First", setID: "first"),
                  detailVMTrack("same", "Second", setID: "second"),
                  detailVMTrack("c", "Third", setID: "third")]
    let core = DetailViewModelCore(playlist: detailVMPlaylist("PL-owned", items: tracks, owned: true, editable: true))
    let vm = PlaylistDetailViewModel(playlistCatalog: PlaylistCatalog())
    await vm.loadPlaylist(core: core, playlistId: "PL-owned")
    try await vm.moveDisplayedTrack(from: 1, to: 0, core: core)
    #expect(core.moveCalls.count == 1)
    #expect(core.moveCalls[0].playlistID == "PL-owned")
    #expect(core.moveCalls[0].setID == "second")
    #expect(core.moveCalls[0].successor == "first")
    #expect(vm.displayedTracks.map(\.setVideoId) == ["second", "first", "third"])
    core.rejectsMove = true
    do {
        try await vm.moveDisplayedTrack(from: 0, to: 2, core: core)
        Issue.record("A rejected provider move must throw")
    } catch DetailViewModelTestError.expected {}
    #expect(core.moveCalls.last?.successor == nil)
    #expect(vm.displayedTracks.map(\.setVideoId) == ["second", "first", "third"])
    #expect(!vm.isMovingTrack)
}

@Test @MainActor func playlistDetailDoesNotSendSortOrMovesForLikedOrForeignPlaylists() async throws {
    let tracks = [detailVMTrack("a", "A", setID: "first"), detailVMTrack("b", "B", setID: "second")]
    for id in ["LM", "VLLM", "PL-foreign"] {
        let core = DetailViewModelCore(playlist: detailVMPlaylist(id, items: tracks, owned: id != "PL-foreign", editable: true))
        let vm = PlaylistDetailViewModel(playlistCatalog: PlaylistCatalog())
        await vm.loadPlaylist(core: core, playlistId: id)
        try await vm.setSort("newest", core: core)
        try await vm.moveDisplayedTrack(from: 0, to: 1, core: core)
        try await vm.moveTrack(from: 0, to: 1, core: core)
        #expect(core.sortCalls.isEmpty)
        #expect(core.moveCalls.isEmpty)
        #expect(vm.displayedTracks.map(\.setVideoId) == ["first", "second"])
    }
}

@Test @MainActor func playlistDetailCompletesCustomOrderBeforeAllowingMovesPastTheLoadedTail() async throws {
    let first = detailVMTrack("a", "Alpha", setID: "first")
    let core = DetailViewModelCore(playlist: detailVMPlaylist("PL-own-paged", items: [first], continuation: "tail-page", owned: true, editable: true))
    let vm = PlaylistDetailViewModel(playlistCatalog: PlaylistCatalog())
    await vm.loadPlaylist(core: core, playlistId: "PL-own-paged")
    #expect(!vm.canReorderDisplayedTracks)
    let completion = Task { await vm.prepareDisplayedTracks(core: core) }
    await core.pages.wait()
    #expect(vm.isCompletingCatalog)
    await core.pages.finish(PlaylistContinuationRecord(items: [detailVMTrack("b", "Bravo", setID: "tail")], continuation: nil))
    await completion.value
    #expect(vm.displayedTracks.map(\.setVideoId) == ["first", "tail"])
    #expect(vm.canReorderDisplayedTracks)
}

@Test @MainActor func albumDetailFilterStartsAtTheOriginalTrackAndRetainsTheWholeAlbum() {
    let vm = AlbumDetailViewModel()
    let tracks = [detailVMTrack("a", "Alpha"), detailVMTrack("b", "Bravo"), detailVMTrack("c", "Charlie")]
    vm.album = AlbumDetailRecord(browseId: "MPRE-album", title: "Album", artist: "Artist", artistId: nil,
                                subtitle: nil, secondSubtitle: nil, description: nil, thumbnail: nil,
                                playlistId: nil, inLibrary: false, items: tracks, sections: [])
    vm.searchQuery = "Bravo"
    let player = detailVMPlayer(core: DetailViewModelCore())
    vm.playDisplayedTrack(at: 0, player: player)
    #expect(player.queueManager.queue.map(\.videoId) == ["a", "b", "c"])
    #expect(player.queueManager.currentIndex == 1)
    #expect(player.queueManager.contextTitle == "Álbum: Album")
    player.audioService.stop()
}

@Test @MainActor func albumDetailUsesItsKnownArtistLinkOnlyForMatchingCredits() {
    let vm = AlbumDetailViewModel()
    let matching = detailVMTrack("a", "Alpha")
    var featured = detailVMTrack("b", "Bravo")
    featured.artists = "Featured artist"
    vm.album = AlbumDetailRecord(browseId: "MPRE-album", title: "Album", artist: "Artist", artistId: "UC-real",
                                subtitle: nil, secondSubtitle: nil, description: nil, thumbnail: nil,
                                playlistId: nil, inLibrary: false, items: [matching, featured], sections: [])
    #expect(vm.displayedTracks[0].artistId == "UC-real")
    #expect(vm.displayedTracks[1].artistId == nil)
    #expect(vm.album?.items[0].artistId == nil)
    vm.album?.artistId = "UC-refreshed"
    #expect(vm.displayedTracks[0].artistId == "UC-refreshed")
}
