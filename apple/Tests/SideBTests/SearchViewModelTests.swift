import Foundation
import Testing
import SideBCore
@testable import SideB

private enum SearchStubError: Error { case failed }

private actor SearchRequestGate {
    enum Route: Hashable { case mixed, suggestions, songs, videos, cards }
    private var mixed: [(String, Bool, CheckedContinuation<SearchResultsRecord, Error>)] = []
    private var spellingFlags: [Bool] = []
    private var suggestions: [(String, CheckedContinuation<SearchSuggestionsRecord, Error>)] = []
    private var songs: [(String, Bool, CheckedContinuation<[SongItemRecord], Error>)] = []
    private var videos: [(String, CheckedContinuation<[SongItemRecord], Error>)] = []
    private var cards: [(String, String, CheckedContinuation<[BrowseCardRecord], Error>)] = []
    private var waiters: [Route: [(Int, CheckedContinuation<Void, Never>)]] = [:]

    func requestMixed(query: String, recordHistory: Bool, ignoreSpelling: Bool) async throws -> SearchResultsRecord {
        try await withCheckedThrowingContinuation { continuation in
            mixed.append((query, recordHistory, continuation))
            spellingFlags.append(ignoreSpelling)
            notify(.mixed, count: mixed.count)
        }
    }

    func requestSuggestions(query: String) async throws -> SearchSuggestionsRecord {
        try await withCheckedThrowingContinuation { continuation in
            suggestions.append((query, continuation)); notify(.suggestions, count: suggestions.count)
        }
    }
    func succeedSuggestions(_ index: Int, queries: [String], results: SearchResultsRecord) {
        suggestions[index].1.resume(returning: SearchSuggestionsRecord(queries: queries, results: results))
    }
    func count(_ route: Route) -> Int { requestCount(route) }

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

    func ignoresSpelling(_ index: Int) -> Bool { spellingFlags[index] }
    func mixedCount() -> Int { mixed.count }
    func mixedQuery(_ index: Int) -> String { mixed[index].0 }
    func songsQuery(_ index: Int) -> String { songs[index].0 }
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
        case .suggestions: suggestions.count
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

    override func searchCatalog(query: String, recordHistory: Bool, ignoreSpelling: Bool) async throws -> SearchCatalogRecord {
        let value = try await gate.requestMixed(query: query, recordHistory: recordHistory, ignoreSpelling: ignoreSpelling)
        return SearchCatalogRecord(results: value, correction: query == "typo" && !ignoreSpelling ? SearchCorrectionRecord(query: "corrected", applied: true) : nil)
    }
    override func searchSuggestions(query: String) async throws -> SearchSuggestionsRecord {
        try await gate.requestSuggestions(query: query)
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

@MainActor private func modelStore() -> SearchRecentStore {
    SearchRecentStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("sideb-search-model-tests-" + UUID().uuidString))
}

@Test @MainActor func searchCommitUsesOneMixedRequestAndRecordsQueryOnce() async {
    let core = SearchCoreStub(), store = modelStore()
    let model = SearchViewModel(recentStore: store)
    model.commitSearch(query: "query", core: core, origin: .submit)
    await core.gate.wait(.mixed, count: 1)
    #expect(await core.gate.mixedHistory(0))
    #expect(await core.gate.count(.songs) == 0)
    #expect(await core.gate.count(.videos) == 0)
    #expect(store.entries.count == 1)
    await core.gate.succeedMixed(0, results(songs: [song("song"), song("video", isVideo: true)]))
    while model.isCommittedLoading { await Task.yield() }
    #expect(model.committedSongs.map(\.videoId) == ["song"])
    #expect(model.committedVideos.map(\.videoId) == ["video"])
    model.selectFilter(.songs, core: core)
    await core.gate.wait(.songs, count: 1)
    await core.gate.succeedSongs(0, [song("category")])
    while model.isSongsLoading { await Task.yield() }
    model.selectFilter(.all, core: core); model.selectFilter(.songs, core: core)
    #expect(await core.gate.count(.songs) == 1)
    #expect(store.entries.count == 1)
    #expect(model.filteredSongs.first?.videoId == "category")
}

@Test @MainActor func providerSuggestionsAreSeparateFromEntitiesAndTypingDoesNotRecordHistory() async {
    let core = SearchCoreStub(), store = modelStore()
    let model = SearchViewModel(recentStore: store)
    model.onQueryChanged("kany", core: core)
    await core.gate.wait(.suggestions, count: 1)
    #expect(await core.gate.count(.mixed) == 0)
    await core.gate.succeedSuggestions(0, queries: ["kanye west", "kany garcía"], results: results(top: [card("artist", kind: "artist")]))
    while model.isQuickSearching { await Task.yield() }
    #expect(model.querySuggestions == ["kanye west", "kany garcía"])
    #expect(model.query == "kany")
    #expect(model.quickResults?.top.first?.id == "artist")
    #expect(store.entries.isEmpty)
    model.cancelPreview(); model.onQueryChanged("kany", core: core)
    #expect(await core.gate.count(.suggestions) == 1)
    #expect(model.querySuggestions.count == 2)
}

@Test @MainActor func textOnlySuggestionsRemainAUsableResponse() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    model.onQueryChanged("run", core: core)
    await core.gate.wait(.suggestions, count: 1)
    await core.gate.succeedSuggestions(0, queries: ["runaway"], results: results())
    while model.isQuickSearching { await Task.yield() }
    #expect(model.querySuggestions == ["runaway"])
    #expect(model.associatedQuickQuery == "run")
    #expect(model.isTopdownVisible)
}

@Test @MainActor func latePreviewCannotReopenDropdownAfterCommit() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    model.onQueryChanged("same", core: core)
    await core.gate.wait(.suggestions, count: 1)
    model.commitSearch(query: "same", core: core, origin: .submit)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.succeedMixed(0, results())
    await core.gate.succeedSuggestions(0, queries: ["stale"], results: results())
    while model.isCommittedLoading { await Task.yield() }
    #expect(!model.isTopdownVisible)
    #expect(model.querySuggestions.isEmpty)
}

@Test @MainActor func newDraftImmediatelyClearsStaleRowsAndSuggestions() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    model.onQueryChanged("old", core: core)
    await core.gate.wait(.suggestions, count: 1)
    await core.gate.succeedSuggestions(0, queries: ["old query"], results: results(top: [card("old")]))
    while model.isQuickSearching { await Task.yield() }
    model.onQueryChanged("new", core: core)
    #expect(model.quickResults == nil)
    #expect(model.querySuggestions.isEmpty)
    model.cancelPreview()
}

@Test @MainActor func searchLateOlderQueryCannotReplaceNewResults() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    model.commitSearch(query: "old", core: core)
    await core.gate.wait(.mixed, count: 1)
    model.commitSearch(query: "new", core: core)
    await core.gate.wait(.mixed, count: 2)
    await core.gate.succeedMixed(1, results(songs: [song("new")]))
    while model.isCommittedLoading { await Task.yield() }
    await core.gate.succeedMixed(0, results(songs: [song("old")]))
    #expect(model.committedSongs.first?.videoId == "new")
}

@Test @MainActor func accountClearDiscardsPendingResponsesAndPreviewCache() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    model.onQueryChanged("account", core: core)
    await core.gate.wait(.suggestions, count: 1)
    await core.gate.succeedSuggestions(0, queries: ["private"], results: results())
    while model.isQuickSearching { await Task.yield() }
    model.commitSearch(query: "pending", core: core)
    await core.gate.wait(.mixed, count: 1)
    model.clear()
    await core.gate.succeedMixed(0, results(top: [card("stale")]))
    #expect(model.committedResults == nil)
    #expect(model.querySuggestions.isEmpty)
    #expect(model.committedSongs.isEmpty)
    #expect(model.selectedFilter == .all)
    model.onQueryChanged("account", core: core)
    await core.gate.wait(.suggestions, count: 2)
    await core.gate.succeedSuggestions(1, queries: ["fresh"], results: results())
    while model.isQuickSearching { await Task.yield() }
    #expect(model.querySuggestions == ["fresh"])
}

@Test @MainActor func categoryFailureKeepsMixedResultsAndRetryDoesNotRepeatCommit() async {
    let core = SearchCoreStub(), store = modelStore()
    let model = SearchViewModel(recentStore: store)
    model.commitSearch(query: "partial", core: core, origin: .submit)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.succeedMixed(0, results(songs: [song("fallback")]))
    while model.isCommittedLoading { await Task.yield() }
    model.selectFilter(.songs, core: core)
    await core.gate.wait(.songs, count: 1)
    await core.gate.failSongs(0)
    while model.isSongsLoading { await Task.yield() }
    #expect(model.filteredSongs.first?.videoId == "fallback")
    #expect(model.partialErrors[.songs] != nil)
    model.retryBlock(.songs, core: core)
    await core.gate.wait(.songs, count: 2)
    await core.gate.succeedSongs(1, [song("retried")])
    while model.isSongsLoading { await Task.yield() }
    #expect(await core.gate.count(.mixed) == 1)
    #expect(store.entries.count == 1)
    #expect(model.filteredSongs.first?.videoId == "retried")
}

@Test @MainActor func categorySwitchDiscardsOldResponseAndReusesCompletedCategory() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    model.commitSearch(query: "categories", core: core)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.succeedMixed(0, results())
    while model.isCommittedLoading { await Task.yield() }
    model.selectFilter(.albums, core: core)
    await core.gate.wait(.cards, count: 1)
    model.selectFilter(.artists, core: core)
    await core.gate.wait(.cards, count: 2)
    await core.gate.succeedCards(1, [card("artist", kind: "artist")])
    await core.gate.succeedCards(0, [card("album", kind: "album")])
    while model.isFilterLoading { await Task.yield() }
    #expect(model.filteredCards.first?.id == "artist")
    model.selectFilter(.all, core: core); model.selectFilter(.artists, core: core)
    #expect(await core.gate.count(.cards) == 2)
    #expect(model.filteredCards.first?.id == "artist")
}

@Test @MainActor func typedTopSongsFollowProviderOrderAndHeroCardKeepsMetadata() {
    let response = results(top: [card("hero")], topSongs: [song("third"), song("hero", title: "Typed hero"), song("second")])
    let model = SearchViewModel(recentStore: modelStore())
    #expect(model.relatedSongs(for: response).map(\.videoId) == ["third", "second"])
    #expect(model.song(for: card("hero"), in: response).title == "Typed hero")
}

@Test @MainActor func providerCorrectionKeepsOriginalQueryAndCanBeReversedWithoutNewHistory() async {
    let core = SearchCoreStub(), store = modelStore()
    let model = SearchViewModel(recentStore: store)
    model.commitSearch(query: "typo", core: core, origin: .submit)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.succeedMixed(0, results())
    while model.isCommittedLoading { await Task.yield() }
    #expect(model.correction?.query == "corrected")
    #expect(model.query == "typo")
    #expect(store.entries.first?.query == "typo")
    model.commitSearch(query: model.committedQuery, core: core, force: true, ignoreSpelling: true)
    await core.gate.wait(.mixed, count: 2)
    #expect(await core.gate.ignoresSpelling(1))
    #expect(!(await core.gate.mixedHistory(1)))
    await core.gate.succeedMixed(1, results())
    while model.isCommittedLoading { await Task.yield() }
    #expect(model.correction == nil)
    model.selectFilter(.songs, core: core)
    #expect(await core.gate.count(.songs) == 0)
    #expect(store.entries.count == 1)
}

@Test @MainActor func previewCacheEvictsOldestEntryAtItsBound() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    for index in 0..<13 {
        model.onQueryChanged("query-\(index)", core: core)
        await core.gate.wait(.suggestions, count: index + 1)
        await core.gate.succeedSuggestions(index, queries: ["suggestion-\(index)"], results: results())
        while model.isQuickSearching { await Task.yield() }
    }
    model.onQueryChanged("query-0", core: core)
    await core.gate.wait(.suggestions, count: 14)
    await core.gate.succeedSuggestions(13, queries: ["fresh"], results: results())
    while model.isQuickSearching { await Task.yield() }
    #expect(model.querySuggestions == ["fresh"])
}

@Test @MainActor func categoryWaitsForMixedCorrectionBeforeIssuingOneRequest() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    model.selectedFilter = .songs
    model.commitSearch(query: "typo", core: core)
    await core.gate.wait(.mixed, count: 1)
    #expect(await core.gate.count(.songs) == 0)
    await core.gate.succeedMixed(0, results())
    await core.gate.wait(.songs, count: 1)
    #expect(await core.gate.songsQuery(0) == "corrected")
    await core.gate.succeedSongs(0, [])
    while model.isSongsLoading { await Task.yield() }
}

@Test @MainActor func originalSearchSurvivesTechnicalRefreshAndLocalFilters() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    model.commitSearch(query: "typo", core: core, ignoreSpelling: true)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.succeedMixed(0, results(songs: [song("exact")]))
    while model.isCommittedLoading { await Task.yield() }
    model.selectFilter(.songs, core: core)
    #expect(model.filteredSongs.first?.videoId == "exact")
    model.commitSearch(query: "typo", core: core, force: true)
    await core.gate.wait(.mixed, count: 2)
    #expect(await core.gate.ignoresSpelling(1))
    await core.gate.succeedMixed(1, results(songs: [song("refreshed")]))
    while model.isCommittedLoading { await Task.yield() }
    #expect(model.isOriginalSearch)
    #expect(model.filteredSongs.first?.videoId == "refreshed")
    #expect(await core.gate.count(.songs) == 0)
}

@Test @MainActor func repeatedExplicitSubmitStillReachesProviderAndResetsOriginalPolicy() async {
    let core = SearchCoreStub(), store = modelStore()
    let model = SearchViewModel(recentStore: store)
    model.commitSearch(query: "typo", core: core, ignoreSpelling: true)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.succeedMixed(0, results())
    while model.isCommittedLoading { await Task.yield() }
    model.commitSearch(query: "typo", core: core, origin: .submit)
    await core.gate.wait(.mixed, count: 2)
    #expect(await core.gate.mixedHistory(1))
    #expect(!(await core.gate.ignoresSpelling(1)))
    await core.gate.succeedMixed(1, results())
    while model.isCommittedLoading { await Task.yield() }
    #expect(!model.isOriginalSearch)
    #expect(store.entries.count == 1)
}

@Test @MainActor func retiredSearchEditorCannotCancelOrReplaceTheCurrentPreview() async {
    let core = SearchCoreStub(), store = modelStore()
    let model = SearchViewModel(recentStore: store)
    let oldEditor = UUID(), currentEditor = UUID()
    model.claimPreview(owner: oldEditor)
    model.onQueryChanged("old", core: core, updateDraft: false, owner: oldEditor)
    await core.gate.wait(.suggestions, count: 1)
    model.claimPreview(owner: currentEditor)
    model.onQueryChanged("current", core: core, updateDraft: false, owner: currentEditor)
    await core.gate.wait(.suggestions, count: 2)
    model.cancelPreview(owner: oldEditor)
    #expect(model.isQuickSearching)
    await core.gate.succeedSuggestions(0, queries: ["wrong"], results: results(songs: [song("old")]))
    await core.gate.succeedSuggestions(1, queries: ["current text"], results: results(songs: [song("current")]))
    while model.isQuickSearching { await Task.yield() }
    #expect(model.associatedQuickQuery == "current")
    #expect(model.quickResults?.songs.map(\.videoId) == ["current"])
    model.onQueryChanged("stale input", core: core, owner: oldEditor)
    #expect(model.associatedQuickQuery == "current")
    #expect(model.query.isEmpty)
    #expect(await core.gate.count(.suggestions) == 2)
    #expect(store.entries.isEmpty)
}

@Test @MainActor func sessionClearRevokesOldPreviewOwnerWithoutBlockingNewEditor() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    let oldEditor = UUID(), newEditor = UUID()
    model.claimPreview(owner: oldEditor)
    model.clear()
    model.onQueryChanged("retired", core: core, owner: oldEditor)
    #expect(!model.isQuickSearching)
    #expect(model.query.isEmpty)
    model.claimPreview(owner: newEditor)
    model.onQueryChanged("new session", core: core, updateDraft: false, owner: newEditor)
    await core.gate.wait(.suggestions, count: 1)
    model.cancelPreview(owner: oldEditor)
    await core.gate.succeedSuggestions(0, queries: ["new session"], results: results())
    while model.isQuickSearching { await Task.yield() }
    #expect(model.associatedQuickQuery == "new session")
    #expect(model.isTopdownVisible)
    model.cancelPreview(owner: newEditor)
    #expect(!model.isTopdownVisible)
}

@Test @MainActor func committedLibraryRefreshPreservesAnActiveEditorPreviewAndOwnership() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    let editor = UUID()
    model.claimPreview(owner: editor)
    model.onQueryChanged("draft", core: core, owner: editor)
    await core.gate.wait(.suggestions, count: 1)
    model.commitSearch(query: "committed", core: core, force: true, preservingPreview: true)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.succeedMixed(0, results(songs: [song("saved")]))
    await core.gate.succeedSuggestions(0, queries: ["draft"], results: results())
    while model.isQuickSearching || model.isCommittedLoading { await Task.yield() }
    #expect(model.associatedQuickQuery == "draft")
    #expect(model.query == "draft")
    #expect(model.committedQuery == "committed")
    #expect(model.committedResults?.songs.first?.videoId == "saved")
    model.onQueryChanged("keep typing", core: core, updateDraft: false, owner: editor)
    await core.gate.wait(.suggestions, count: 2)
    await core.gate.succeedSuggestions(1, queries: ["keep typing"], results: results())
    while model.isQuickSearching { await Task.yield() }
    #expect(model.associatedQuickQuery == "keep typing")
}
