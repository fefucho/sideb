import Foundation
import Testing
import SideBCore
@testable import SideB

private enum SearchStubError: Error { case failed }

private actor SearchRequestGate {
    enum Route: Hashable { case mixed, songs, videos, cards }
    private var mixed: [(String, Bool, CheckedContinuation<SearchResultsRecord, Error>)] = []
    private var songs: [(String, Bool, CheckedContinuation<[SongItemRecord], Error>)] = []
    private var videos: [(String, CheckedContinuation<[SongItemRecord], Error>)] = []
    private var cards: [(String, String, CheckedContinuation<[BrowseCardRecord], Error>)] = []
    private var waiters: [Route: [(Int, CheckedContinuation<Void, Never>)]] = [:]

    func requestMixed(query: String, recordHistory: Bool) async throws -> SearchResultsRecord {
        try await withCheckedThrowingContinuation { continuation in
            mixed.append((query, recordHistory, continuation))
            notify(.mixed, count: mixed.count)
        }
    }

    func requestSongs(query: String, recordHistory: Bool) async throws -> [SongItemRecord] {
        try await withCheckedThrowingContinuation { continuation in
            songs.append((query, recordHistory, continuation))
            notify(.songs, count: songs.count)
        }
    }

    func requestVideos(query: String) async throws -> [SongItemRecord] {
        try await withCheckedThrowingContinuation { continuation in
            videos.append((query, continuation))
            notify(.videos, count: videos.count)
        }
    }

    func requestCards(query: String, category: String) async throws -> [BrowseCardRecord] {
        try await withCheckedThrowingContinuation { continuation in
            cards.append((query, category, continuation))
            notify(.cards, count: cards.count)
        }
    }

    func wait(_ route: Route, count: Int) async {
        if requestCount(route) >= count { return }
        await withCheckedContinuation { continuation in
            waiters[route, default: []].append((count, continuation))
        }
    }

    func mixedCount() -> Int { mixed.count }
    func mixedHistory(_ index: Int) -> Bool { mixed[index].1 }
    func succeedMixed(_ index: Int, _ value: SearchResultsRecord) { mixed[index].2.resume(returning: value) }
    func failMixed(_ index: Int) { mixed[index].2.resume(throwing: SearchStubError.failed) }
    func succeedSongs(_ index: Int, _ value: [SongItemRecord]) { songs[index].2.resume(returning: value) }
    func failSongs(_ index: Int) { songs[index].2.resume(throwing: SearchStubError.failed) }
    func succeedVideos(_ index: Int, _ value: [SongItemRecord]) { videos[index].1.resume(returning: value) }
    func failVideos(_ index: Int) { videos[index].1.resume(throwing: SearchStubError.failed) }
    func succeedCards(_ index: Int, _ value: [BrowseCardRecord]) { cards[index].2.resume(returning: value) }
    func failCards(_ index: Int) { cards[index].2.resume(throwing: SearchStubError.failed) }

    private func requestCount(_ route: Route) -> Int {
        switch route {
        case .mixed: mixed.count
        case .songs: songs.count
        case .videos: videos.count
        case .cards: cards.count
        }
    }

    private func notify(_ route: Route, count: Int) {
        let ready = waiters[route, default: []].filter { count >= $0.0 }
        waiters[route, default: []].removeAll { count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}

private final class SearchCoreStub: SideBCore, @unchecked Sendable {
    let gate = SearchRequestGate()

    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        super.init(unsafeFromRawPointer: pointer)
    }

    init() { super.init(noPointer: .init()) }

    override func searchAll(query: String, recordHistory: Bool) async throws -> SearchResultsRecord {
        try await gate.requestMixed(query: query, recordHistory: recordHistory)
    }

    override func searchSongs(query: String, recordHistory: Bool) async throws -> [SongItemRecord] {
        try await gate.requestSongs(query: query, recordHistory: recordHistory)
    }

    override func searchVideos(query: String) async throws -> [SongItemRecord] {
        try await gate.requestVideos(query: query)
    }

    override func searchCards(query: String, category: String) async throws -> [BrowseCardRecord] {
        try await gate.requestCards(query: query, category: category)
    }
}

private func song(_ id: String, title: String? = nil, isVideo: Bool = false) -> SongItemRecord {
    SongItemRecord(videoId: id, title: title ?? id, artists: "Artist \(id)", album: "Album \(id)", duration: "3:00",
                   thumbnail: "thumb-\(id)", artistId: "artist-\(id)", albumId: "album-\(id)", setVideoId: nil,
                   isVideo: isVideo, isUpload: false, library: nil, artistRuns: [])
}

private func card(_ id: String, kind: String = "song") -> BrowseCardRecord {
    BrowseCardRecord(kind: kind, id: id, title: "Card \(id)", subtitle: "Fallback Artist", thumbnail: "card-thumb", duration: "2:00")
}

private func results(top: [BrowseCardRecord] = [], topSongs: [SongItemRecord] = [], songs: [SongItemRecord] = []) -> SearchResultsRecord {
    SearchResultsRecord(topSongs: topSongs, top: top, songs: songs, albums: [], artists: [], playlists: [])
}

@Test @MainActor func searchCommitDoesNotReusePreviewAndRecordsHistoryOnce() async {
    let core = SearchCoreStub()
    let model = SearchViewModel()
    model.commitSearch(query: "query", core: core)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.wait(.songs, count: 1)
    await core.gate.wait(.videos, count: 1)

    #expect(await core.gate.mixedHistory(0))
    await core.gate.succeedMixed(0, results())
    await core.gate.succeedSongs(0, [song("song")])
    await core.gate.succeedVideos(0, [song("video", isVideo: true)])
    while model.isCommittedLoading { await Task.yield() }

    #expect(model.committedSongs.map(\.videoId) == ["song"])
    #expect(model.committedVideos.map(\.videoId) == ["video"])
}

@Test @MainActor func explicitPreviewAfterFullSearchStillRunsWithoutHistory() async {
    let core = SearchCoreStub()
    let model = SearchViewModel()
    model.commitSearch(query: "reopen", core: core)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.wait(.songs, count: 1)
    await core.gate.wait(.videos, count: 1)
    await core.gate.succeedMixed(0, results())
    await core.gate.succeedSongs(0, [])
    await core.gate.succeedVideos(0, [])
    while model.isCommittedLoading { await Task.yield() }

    model.onQueryChanged("reopen", core: core)
    try? await Task.sleep(for: .milliseconds(300))
    await core.gate.wait(.mixed, count: 2)
    #expect(!(await core.gate.mixedHistory(1)))
    await core.gate.succeedMixed(1, results(top: [card("preview")]))
    while model.isQuickSearching { await Task.yield() }

    #expect(model.quickResults?.top.first?.id == "preview")
}

@Test @MainActor func previewResponseCannotReopenDropdownAfterCommit() async {
    let core = SearchCoreStub()
    let model = SearchViewModel()
    model.onQueryChanged("same query", core: core)
    try? await Task.sleep(for: .milliseconds(300))
    await core.gate.wait(.mixed, count: 1)
    #expect(!(await core.gate.mixedHistory(0)))
    await core.gate.succeedMixed(0, results(top: [card("preview")]))
    while model.isQuickSearching { await Task.yield() }
    #expect(model.quickResults?.top.first?.id == "preview")

    model.commitSearch(query: "same query", core: core)
    await core.gate.wait(.mixed, count: 2)
    await core.gate.wait(.songs, count: 1)
    await core.gate.wait(.videos, count: 1)
    await core.gate.succeedMixed(1, results())
    await core.gate.succeedSongs(0, [])
    await core.gate.succeedVideos(0, [])
    while model.isCommittedLoading { await Task.yield() }

    #expect(await core.gate.mixedHistory(1))
    #expect(model.committedResults?.top.isEmpty == true)
    #expect(model.quickResults?.top.first?.id == "preview")
    #expect(!model.isTopdownVisible)
}

@Test @MainActor func searchLateOlderQueryCannotReplaceNewResults() async {
    let core = SearchCoreStub()
    let model = SearchViewModel()
    model.commitSearch(query: "old", core: core)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.wait(.songs, count: 1)
    await core.gate.wait(.videos, count: 1)
    model.commitSearch(query: "new", core: core, force: true)
    await core.gate.wait(.mixed, count: 2)
    await core.gate.wait(.songs, count: 2)
    await core.gate.wait(.videos, count: 2)

    await core.gate.succeedMixed(1, results())
    await core.gate.succeedSongs(1, [song("new-song")])
    await core.gate.succeedVideos(1, [])
    while model.isCommittedLoading { await Task.yield() }
    await core.gate.succeedMixed(0, results())
    await core.gate.succeedSongs(0, [song("old-song")])
    await core.gate.succeedVideos(0, [])

    #expect(model.committedQuery == "new")
    #expect(model.committedSongs.map(\.videoId) == ["new-song"])
}

@Test @MainActor func searchClearDiscardsPendingResponsesAndResetsEveryFilter() async {
    let core = SearchCoreStub()
    let model = SearchViewModel()
    model.selectedFilter = .videos
    model.commitSearch(query: "pending", core: core)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.wait(.songs, count: 1)
    await core.gate.wait(.videos, count: 1)
    model.clear()
    await core.gate.succeedMixed(0, results())
    await core.gate.succeedSongs(0, [song("stale")])
    await core.gate.succeedVideos(0, [song("stale-video", isVideo: true)])

    #expect(model.committedQuery.isEmpty)
    #expect(model.committedResults == nil)
    #expect(model.quickResults == nil)
    #expect(model.committedSongs.isEmpty)
    #expect(model.committedVideos.isEmpty)
    #expect(model.filteredSongs.isEmpty)
    #expect(model.filteredCards.isEmpty)
    #expect(model.selectedFilter == .all)
    #expect(!model.isCommittedLoading)
    #expect(!model.isFilterLoading)
}

@Test @MainActor func failedSectionsKeepOtherResultsAndSongsFallBackToMixedNonVideos() async {
    let core = SearchCoreStub()
    let model = SearchViewModel()
    model.commitSearch(query: "partial", core: core)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.wait(.songs, count: 1)
    await core.gate.wait(.videos, count: 1)
    await core.gate.succeedMixed(0, results(songs: [song("fallback-song"), song("mixed-video", isVideo: true)]))
    await core.gate.failSongs(0)
    await core.gate.failVideos(0)
    while model.isCommittedLoading { await Task.yield() }

    #expect(model.committedSongs.map(\.videoId) == ["fallback-song"])
    #expect(model.committedVideos.isEmpty)
    #expect(model.partialErrors[.songs] != nil)
    #expect(model.partialErrors[.videos] != nil)
    #expect(model.errorMessage == nil)
}

@Test @MainActor func mixedFailureDoesNotDiscardSongOrVideoSuccesses() async {
    let core = SearchCoreStub()
    let model = SearchViewModel()
    model.commitSearch(query: "independent", core: core)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.wait(.songs, count: 1)
    await core.gate.wait(.videos, count: 1)
    await core.gate.failMixed(0)
    await core.gate.succeedSongs(0, [song("song")])
    await core.gate.succeedVideos(0, [song("video", isVideo: true)])
    while model.isCommittedLoading { await Task.yield() }

    #expect(model.committedResults == nil)
    #expect(model.committedSongs.map(\.videoId) == ["song"])
    #expect(model.committedVideos.map(\.videoId) == ["video"])
    #expect(model.errorMessage != nil)
}

@Test @MainActor func filterChangeDuringSearchKeepsLatestCategoryResponse() async {
    let core = SearchCoreStub()
    let model = SearchViewModel()
    model.commitSearch(query: "categories", core: core)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.wait(.songs, count: 1)
    await core.gate.wait(.videos, count: 1)
    model.selectFilter(.albums, core: core)
    await core.gate.wait(.cards, count: 1)
    model.selectFilter(.artists, core: core)
    await core.gate.wait(.cards, count: 2)
    await core.gate.succeedCards(1, [card("artist", kind: "artist")])
    await core.gate.succeedCards(0, [card("album", kind: "album")])
    await core.gate.succeedMixed(0, results())
    await core.gate.succeedSongs(0, [])
    await core.gate.succeedVideos(0, [])
    while model.isCommittedLoading || model.isFilterLoading { await Task.yield() }

    #expect(model.selectedFilter == .artists)
    #expect(model.filteredCards.map(\.id) == ["artist"])
}

@Test @MainActor func categoryErrorSurvivesBaseSearchFinishingLater() async {
    let core = SearchCoreStub()
    let model = SearchViewModel()
    model.selectedFilter = .albums
    model.commitSearch(query: "category error", core: core)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.wait(.songs, count: 1)
    await core.gate.wait(.videos, count: 1)
    await core.gate.wait(.cards, count: 1)

    await core.gate.failCards(0)
    while model.isFilterLoading { await Task.yield() }
    #expect(model.partialErrors[.categories] != nil)

    await core.gate.succeedMixed(0, results())
    await core.gate.succeedSongs(0, [])
    await core.gate.succeedVideos(0, [])
    while model.isCommittedLoading { await Task.yield() }
    #expect(model.partialErrors[.categories] != nil)
}

@Test @MainActor func typedTopSongsFollowProviderOrderAndHeroCardKeepsMetadata() {
    let coreResults = results(
        top: [card("hero"), card("artist", kind: "artist"), card("related-2"), card("missing"), card("related-3"), card("related-4")],
        topSongs: [song("related-4"), song("hero", title: "Typed hero"), song("related-3"), song("related-2")]
    )
    let model = SearchViewModel()

    #expect(model.relatedSongs(for: coreResults).map(\.videoId) == ["related-2", "related-3", "related-4"])
    #expect(model.song(for: card("hero"), in: coreResults).title == "Typed hero")
    #expect(model.song(for: card("unknown"), in: coreResults).artists == "Fallback Artist")
}
