import Foundation
import Testing
import SideBCore
@testable import SideB

private enum SearchStubError: Error { case failed }

private actor SearchRequestGate {
    enum Route: Hashable { case mixed, suggestions, songs, videos, cards, remove, continuation }
    private var mixed: [(String, String?, Bool, Bool, CheckedContinuation<SearchPageRecord, Error>)] = []
    private var suggestions: [(String, CheckedContinuation<SearchSuggestionsPageRecord, Error>)] = []
    private var songs: [(String, Bool, CheckedContinuation<[SongItemRecord], Error>)] = []
    private var videos: [(String, CheckedContinuation<[SongItemRecord], Error>)] = []
    private var cards: [(String, String, CheckedContinuation<[BrowseCardRecord], Error>)] = []
    private var removals: [(String, CheckedContinuation<Void, Error>)] = []
    private var continuations: [(String, CheckedContinuation<SearchPageRecord, Error>)] = []
    private var waiters: [Route: [(Int, CheckedContinuation<Void, Never>)]] = [:]

    func requestMixed(query: String, params: String?, recordHistory: Bool, ignoreSpelling: Bool) async throws -> SearchPageRecord {
        try await withCheckedThrowingContinuation { continuation in
            mixed.append((query, params, recordHistory, ignoreSpelling, continuation))
            notify(.mixed, count: mixed.count)
        }
    }

    func requestSuggestions(query: String) async throws -> SearchSuggestionsPageRecord {
        try await withCheckedThrowingContinuation { continuation in
            suggestions.append((query, continuation)); notify(.suggestions, count: suggestions.count)
        }
    }
    func succeedSuggestions(_ index: Int, entries: [SearchSuggestionEntryRecord]) {
        suggestions[index].1.resume(returning: SearchSuggestionsPageRecord(entries: entries))
    }
    func succeedSuggestions(_ index: Int, queries: [String], results: SearchResultsRecord) {
        let textEntries = queries.enumerated().map { i, query in
            SearchSuggestionEntryRecord(id: "text-\(i)", kind: "text", query: query, runs: [], feedbackToken: nil, card: nil, song: nil)
        }
        let cards = results.top + results.albums + results.artists + results.playlists
        let cardEntries = cards.enumerated().map { i, item in
            SearchSuggestionEntryRecord(id: "media-\(i)", kind: "media", query: nil, runs: [], feedbackToken: nil, card: item, song: nil)
        }
        let songEntries = (results.topSongs + results.songs).enumerated().map { i, item in
            SearchSuggestionEntryRecord(id: "song-\(i)", kind: "media", query: nil, runs: [], feedbackToken: nil, card: nil, song: item)
        }
        succeedSuggestions(index, entries: textEntries + cardEntries + songEntries)
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

    func requestRemove(token: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            removals.append((token, continuation)); notify(.remove, count: removals.count)
        }
    }
    func requestContinuation(token: String) async throws -> SearchPageRecord {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append((token, continuation)); notify(.continuation, count: continuations.count)
        }
    }

    func wait(_ route: Route, count: Int) async {
        if requestCount(route) >= count { return }
        await withCheckedContinuation { continuation in
            waiters[route, default: []].append((count, continuation))
        }
    }

    func mixedCount() -> Int { mixed.count }
    func mixedQuery(_ index: Int) -> String { mixed[index].0 }
    func suggestionsQuery(_ index: Int) -> String { suggestions[index].0 }
    func songsQuery(_ index: Int) -> String { songs[index].0 }
    func mixedHistory(_ index: Int) -> Bool { mixed[index].2 }
    func ignoresSpelling(_ index: Int) -> Bool { mixed[index].3 }
    func succeedMixed(_ index: Int, _ value: SearchPageRecord) { mixed[index].4.resume(returning: value) }
    func succeedMixed(_ index: Int, _ value: SearchResultsRecord, correction: SearchPageCorrectionRecord? = nil) {
        let sections = [
            SearchSectionRecord(id: "top", title: "Top result", layout: "top", items: value.top, songs: value.topSongs,
                primaryItemIndex: nil, relatedItemIndices: [], moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: []),
            SearchSectionRecord(id: "songs", title: "Songs", layout: "list", items: [], songs: value.songs,
                primaryItemIndex: nil, relatedItemIndices: [], moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: []),
            SearchSectionRecord(id: "albums", title: "Albums", layout: "list", items: value.albums, songs: [],
                primaryItemIndex: nil, relatedItemIndices: [], moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: []),
            SearchSectionRecord(id: "artists", title: "Artists", layout: "list", items: value.artists, songs: [],
                primaryItemIndex: nil, relatedItemIndices: [], moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: []),
            SearchSectionRecord(id: "playlists", title: "Playlists", layout: "list", items: value.playlists, songs: [],
                primaryItemIndex: nil, relatedItemIndices: [], moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: [])
        ].filter { !$0.items.isEmpty || !$0.songs.isEmpty }
        mixed[index].4.resume(returning: SearchPageRecord(chips: [], correction: correction, sections: sections, continuation: nil))
    }
    func failMixed(_ index: Int) { mixed[index].4.resume(throwing: SearchStubError.failed) }
    func mixedParams(_ index: Int) -> String? { mixed[index].1 }
    func continuationToken(_ index: Int) -> String { continuations[index].0 }
    func succeedContinuation(_ index: Int, _ page: SearchPageRecord) { continuations[index].1.resume(returning: page) }
    func failContinuation(_ index: Int) { continuations[index].1.resume(throwing: SearchStubError.failed) }
    func succeedSongs(_ index: Int, _ value: [SongItemRecord]) { songs[index].2.resume(returning: value) }
    func failSongs(_ index: Int) { songs[index].2.resume(throwing: SearchStubError.failed) }
    func succeedVideos(_ index: Int, _ value: [SongItemRecord]) { videos[index].1.resume(returning: value) }
    func failVideos(_ index: Int) { videos[index].1.resume(throwing: SearchStubError.failed) }
    func succeedCards(_ index: Int, _ value: [BrowseCardRecord]) { cards[index].2.resume(returning: value) }
    func failCards(_ index: Int) { cards[index].2.resume(throwing: SearchStubError.failed) }
    func removeToken(_ index: Int) -> String { removals[index].0 }
    func succeedRemove(_ index: Int) { removals[index].1.resume() }
    func failRemove(_ index: Int) { removals[index].1.resume(throwing: SearchStubError.failed) }

    private func requestCount(_ route: Route) -> Int {
        switch route {
        case .mixed: mixed.count
        case .suggestions: suggestions.count
        case .songs: songs.count
        case .videos: videos.count
        case .cards: cards.count
        case .remove: removals.count
        case .continuation: continuations.count
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

    override func searchPage(query: String, params: String?, recordHistory: Bool, ignoreSpelling: Bool) async throws -> SearchPageRecord {
        try await gate.requestMixed(query: query, params: params, recordHistory: recordHistory, ignoreSpelling: ignoreSpelling)
    }
    override func searchSuggestionsPage(query: String) async throws -> SearchSuggestionsPageRecord {
        try await gate.requestSuggestions(query: query)
    }
    override func removeSearchSuggestion(token: String) async throws {
        try await gate.requestRemove(token: token)
    }
    override func searchPageContinuation(continuation: String) async throws -> SearchPageRecord {
        try await gate.requestContinuation(token: continuation)
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

private func suggestion(_ id: String, kind: String, query: String? = nil, token: String? = nil) -> SearchSuggestionEntryRecord {
    SearchSuggestionEntryRecord(id: id, kind: kind, query: query, runs: [], feedbackToken: token, card: nil, song: nil)
}

private func page(chips: [SearchChipRecord] = [], sections: [SearchSectionRecord] = [], continuation: String? = nil) -> SearchPageRecord {
    SearchPageRecord(chips: chips, correction: nil, sections: sections, continuation: continuation)
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
    #expect(store.entries.isEmpty)
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
    #expect(store.entries.isEmpty)
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

@Test @MainActor func emptyQueryLoadsProviderHistoryWithoutWritingLocalRecents() async {
    let core = SearchCoreStub(), store = modelStore()
    let model = SearchViewModel(recentStore: store)
    model.onQueryChanged("", core: core)
    await core.gate.wait(.suggestions, count: 1)
    #expect(await core.gate.count(.mixed) == 0)
    #expect(await core.gate.suggestionsQuery(0).isEmpty)
    await core.gate.succeedSuggestions(0, entries: [suggestion("history-1", kind: "history", query: "older search", token: "opaque-delete-token")])
    while model.isQuickSearching { await Task.yield() }
    #expect(model.providerSuggestions.map(\.id) == ["history-1"])
    #expect(model.querySuggestions == ["older search"])
    #expect(store.entries.isEmpty)
}

@Test @MainActor func providerSuggestionOrderAndAllTextEntriesArePreserved() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    let entries = [
        suggestion("history", kind: "history", query: "past query", token: "opaque"),
        suggestion("text-1", kind: "text", query: "one"),
        SearchSuggestionEntryRecord(id: "same-occurrence-id", kind: "media", query: nil, runs: [], feedbackToken: nil,
            card: card("same-occurrence-id", kind: "artist"), song: nil),
        SearchSuggestionEntryRecord(id: "same-occurrence-id", kind: "media", query: nil, runs: [], feedbackToken: nil,
            card: nil, song: song("same-occurrence-id")),
        suggestion("text-2", kind: "text", query: "two"),
        suggestion("text-3", kind: "text", query: "three"),
        suggestion("text-4", kind: "text", query: "four")
    ]
    model.onQueryChanged("q", core: core)
    await core.gate.wait(.suggestions, count: 1)
    await core.gate.succeedSuggestions(0, entries: entries)
    while model.isQuickSearching { await Task.yield() }
    #expect(model.providerSuggestions.map(\.id) == entries.map(\.id))
    #expect(model.querySuggestions == ["past query", "one", "two", "three", "four"])
    #expect(model.visibleProviderSuggestions.map(\.id) == ["history", "text-1", "same-occurrence-id", "same-occurrence-id", "text-2"])
    #expect(model.visibleProviderSuggestions.first?.feedbackToken == "opaque")
}

@Test @MainActor func shortQueryPreviewKeepsAllMediaButEmptyHistoryStaysComplete() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    let history = (0..<6).map { suggestion("history-\($0)", kind: "history", query: "past \($0)", token: "token-\($0)") }
    let media = SearchSuggestionEntryRecord(id: "song", kind: "media", query: nil, runs: [], feedbackToken: nil,
        card: nil, song: song("song", title: "Homecoming"))
    for (index, query) in ["homecoming", "   "].enumerated() {
        model.onQueryChanged(query, core: core)
        await core.gate.wait(.suggestions, count: index + 1)
        await core.gate.succeedSuggestions(index, entries: history + [media])
        while model.isQuickSearching { await Task.yield() }
        let visible = model.visibleProviderSuggestions
        #expect(visible.map(\.id) == (index == 0 ? Array(history.prefix(3)) : history).map(\.id) + ["song"])
        #expect(visible.last?.song?.title == "Homecoming")
        #expect(model.providerSuggestions.count == 7)
        #expect(await core.gate.count(.mixed) == 0)
        #expect(await core.gate.count(.remove) == 0)
    }
}

@Test @MainActor func providerHistoryRemovalRunsOnlyAfterExplicitSelection() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    let entry = suggestion("history", kind: "history", query: "remove me", token: "opaque-delete-token")
    model.onQueryChanged("", core: core)
    await core.gate.wait(.suggestions, count: 1)
    await core.gate.succeedSuggestions(0, entries: [entry])
    while model.isQuickSearching { await Task.yield() }
    #expect(await core.gate.count(.remove) == 0, "Displaying a token must never issue a delete")
    let removal = Task { await model.removeProviderSuggestion(entry, core: core) }
    await core.gate.wait(.remove, count: 1)
    #expect(await core.gate.removeToken(0) == "opaque-delete-token")
    await core.gate.succeedRemove(0)
    await removal.value
    while model.providerSuggestions.contains(where: { $0.id == entry.id }) { await Task.yield() }
}

@Test @MainActor func providerChipPassesOpaqueParamsToSearchAndDoesNotRecordHistory() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    let chip = SearchChipRecord(id: "songs", title: "Songs", params: "opaque-server-params", selected: false)
    model.commitSearch(query: "query", core: core, origin: .submit)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.succeedMixed(0, page(chips: [chip]))
    while model.isCommittedLoading { await Task.yield() }
    model.selectProviderChip(chip, core: core)
    await core.gate.wait(.mixed, count: 2)
    #expect(await core.gate.mixedParams(1) == "opaque-server-params")
    #expect(!(await core.gate.mixedHistory(1)))
    await core.gate.succeedMixed(1, page(chips: [SearchChipRecord(id: "songs", title: "Songs", params: "opaque-server-params", selected: true)]))
    while model.isCommittedLoading { await Task.yield() }
    #expect(model.providerPage?.chips.first?.selected == true)
}

@Test @MainActor func continuationFailureRetainsTokenAndRepeatedTokenStopsPaging() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    let first = SearchSectionRecord(id: "section", title: "Songs", layout: "list", items: [], songs: [song("same")],
        primaryItemIndex: nil, relatedItemIndices: [], moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: [])
    model.commitSearch(query: "query", core: core)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.succeedMixed(0, page(sections: [first], continuation: "cursor-1"))
    while model.isCommittedLoading { await Task.yield() }
    model.loadMore(core: core)
    await core.gate.wait(.continuation, count: 1)
    #expect(await core.gate.continuationToken(0) == "cursor-1")
    await core.gate.failContinuation(0)
    while model.isLoadingMore { await Task.yield() }
    #expect(model.providerPage?.continuation == "cursor-1")
    model.loadMore(core: core)
    await core.gate.wait(.continuation, count: 2)
    let repeated = SearchSectionRecord(id: "section", title: "Songs", layout: "list", items: [], songs: [song("same")],
        primaryItemIndex: nil, relatedItemIndices: [], moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: [])
    await core.gate.succeedContinuation(1, page(sections: [repeated], continuation: "cursor-1"))
    while model.isLoadingMore { await Task.yield() }
    #expect(model.providerPage?.sections.count == 2, "Repeated rows remain as distinct occurrences")
    #expect(model.providerPage?.sections.map { $0.songs.first?.videoId } == ["same", "same"])
    #expect(model.providerPage?.continuation == nil, "A consumed continuation must not be requested again")
    model.loadMore(core: core)
    #expect(await core.gate.count(.continuation) == 2)
}

@Test @MainActor func staleContinuationCannotReplaceTheNewSearchPage() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    model.commitSearch(query: "old", core: core)
    await core.gate.wait(.mixed, count: 1)
    await core.gate.succeedMixed(0, page(sections: [], continuation: "old-cursor"))
    while model.isCommittedLoading { await Task.yield() }
    model.loadMore(core: core)
    await core.gate.wait(.continuation, count: 1)
    model.commitSearch(query: "new", core: core)
    await core.gate.wait(.mixed, count: 2)
    await core.gate.succeedMixed(1, page(sections: [], continuation: nil))
    while model.isCommittedLoading { await Task.yield() }
    await core.gate.succeedContinuation(0, page(sections: [SearchSectionRecord(id: "stale", title: "Old", layout: "list",
        items: [], songs: [song("stale")], primaryItemIndex: nil, relatedItemIndices: [], moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: [])]))
    #expect(model.committedQuery == "new")
    #expect(model.providerPage?.sections.isEmpty == true)
    #expect(model.committedSongs.isEmpty)
}

@Test @MainActor func failedAndRetiredSuggestionRemovalKeepsSessionScopedState() async {
    let core = SearchCoreStub(), model = SearchViewModel(recentStore: modelStore())
    let entry = suggestion("history", kind: "history", query: "keep", token: "opaque")
    model.onQueryChanged("", core: core)
    await core.gate.wait(.suggestions, count: 1)
    await core.gate.succeedSuggestions(0, entries: [entry])
    while model.isQuickSearching { await Task.yield() }
    let failedRemoval = Task { await model.removeProviderSuggestion(entry, core: core) }
    await core.gate.wait(.remove, count: 1)
    await core.gate.failRemove(0)
    await failedRemoval.value
    #expect(model.providerSuggestions.map(\.id) == [entry.id])

    let retiredRemoval = Task { await model.removeProviderSuggestion(entry, core: core) }
    await core.gate.wait(.remove, count: 2)
    model.clear()
    await core.gate.succeedRemove(1)
    await retiredRemoval.value
    #expect(model.providerSuggestions.isEmpty)
    #expect(model.querySuggestions.isEmpty)
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
    #expect(model.providerSuggestions.isEmpty)
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
    #expect(store.entries.isEmpty)
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
    await core.gate.succeedMixed(0, results(), correction: SearchPageCorrectionRecord(query: "corrected", applied: true,
        params: nil, originalQuery: "typo", originalParams: nil))
    while model.isCommittedLoading { await Task.yield() }
    #expect(model.correction?.query == "corrected")
    #expect(model.query == "typo")
    #expect(store.entries.isEmpty)
    model.commitSearch(query: model.committedQuery, core: core, force: true, ignoreSpelling: true)
    await core.gate.wait(.mixed, count: 2)
    #expect(await core.gate.ignoresSpelling(1))
    #expect(!(await core.gate.mixedHistory(1)))
    await core.gate.succeedMixed(1, results())
    while model.isCommittedLoading { await Task.yield() }
    #expect(model.correction == nil)
    model.selectFilter(.songs, core: core)
    #expect(await core.gate.count(.songs) == 0)
    #expect(store.entries.isEmpty)
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
    await core.gate.succeedMixed(0, results(), correction: SearchPageCorrectionRecord(query: "corrected", applied: true,
        params: nil, originalQuery: "typo", originalParams: nil))
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
    #expect(store.entries.isEmpty)
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
    #expect(model.providerSuggestions.compactMap(\.song).map(\.videoId) == ["current"])
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
