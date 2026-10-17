import SwiftUI
import SideBCore

// MARK: - SearchFilter

public enum SearchFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Todo"
    case songs = "Canciones"
    case artists = "Artistas"
    case albums = "Álbumes"
    case playlists = "Playlists"
    case videos = "Videos"

    public var displayTitle: String {
        switch self {
        case .all: return L10n.text("search.filter.all")
        case .songs: return L10n.text("search.filter.songs")
        case .videos: return L10n.text("search.filter.videos")
        case .albums: return L10n.text("search.filter.albums")
        case .artists: return L10n.text("search.filter.artists")
        case .playlists: return L10n.text("search.filter.playlists")
        }
    }

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "sparkles"
        case .songs: return "music.note"
        case .videos: return "play.rectangle"
        case .albums: return "opticaldisc"
        case .artists: return "person.2.fill"
        case .playlists: return "music.note.list"
        }
    }
}

// MARK: - SearchCategory

public enum SearchCategory: String, Identifiable, Sendable {
    case topResult = "Mejor resultado"
    case artists = "Artistas"
    case songs = "Canciones"
    case albums = "Álbumes"
    case playlists = "Playlists"

    public var displayTitle: String {
        switch self {
        case .topResult: return L10n.text("search.category.top_result")
        case .artists: return L10n.text("search.filter.artists")
        case .songs: return L10n.text("search.filter.songs")
        case .albums: return L10n.text("search.filter.albums")
        case .playlists: return L10n.text("search.filter.playlists")
        }
    }

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .topResult: return "star.fill"
        case .artists: return "person.crop.circle.fill"
        case .songs: return "music.note"
        case .albums: return "opticaldisc"
        case .playlists: return "music.note.list"
        }
    }
}

public enum SearchPartialError: Hashable, Sendable {
    case global
    case songs
    case videos
    case categories
}

// MARK: - SearchViewModel

@MainActor
@Observable
public final class SearchViewModel {
    public var query = ""
    public var committedQuery = ""

    public var quickResults: SearchResultsRecord?
    public private(set) var querySuggestions: [String] = []
    public private(set) var correction: SearchCorrectionRecord?
    public private(set) var associatedQuickQuery = ""
    private var quickError: AppMessage?
    public var quickErrorMessage: String? {
        get { quickError?.text }
        set { quickError = newValue.map(AppMessage.init(verbatim:)) }
    }
    public var isQuickSearching = false
    public var isTopdownVisible = false

    public var committedResults: SearchResultsRecord?
    public private(set) var committedSongs: [SongItemRecord] = []
    public private(set) var committedVideos: [SongItemRecord] = []
    public private(set) var isMixedLoading = false
    public private(set) var isSongsLoading = false
    public private(set) var isVideosLoading = false
    public private(set) var isCommittedLoading = false
    private var searchError: AppMessage?
    public var errorMessage: String? {
        get { searchError?.text }
        set { searchError = newValue.map(AppMessage.init(verbatim:)) }
    }
    private var partialErrorMessages: [SearchPartialError: AppMessage] = [:]
    public var partialErrors: [SearchPartialError: String] {
        get { partialErrorMessages.mapValues(\.text) }
        set { partialErrorMessages = newValue.mapValues(AppMessage.init(verbatim:)) }
    }

    public var selectedFilter: SearchFilter = .all
    public var filteredSongs: [SongItemRecord] = []
    public var filteredCards: [BrowseCardRecord] = []
    public private(set) var isFilterLoading = false

    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var previewGeneration: UInt = 0
    @ObservationIgnored private var previewOwner: UUID?
    @ObservationIgnored private var queryGeneration: UInt = 0
    @ObservationIgnored private var filterGeneration: UInt = 0

    public private(set) var isOriginalSearch = false
    @ObservationIgnored private var loadedFilters = Set<SearchFilter>()
    @ObservationIgnored private var cardCache: [SearchFilter: [BrowseCardRecord]] = [:]
    private struct PreviewCacheEntry {
        let value: SearchSuggestionsRecord
        let date: Date
    }
    @ObservationIgnored private var previewCache: [String: PreviewCacheEntry] = [:]
    @ObservationIgnored private let recentStore: SearchRecentStore
    public init(recentStore: SearchRecentStore? = nil) { self.recentStore = recentStore ?? .shared }

    // MARK: Preview

    public func claimPreview(owner: UUID) {
        guard previewOwner != owner else { return }
        cancelPreview()
        previewOwner = owner
    }

    public func onQueryChanged(_ newQuery: String, core: SideBCore, updateDraft: Bool = true, owner: UUID? = nil) {
        if let owner {
            guard previewOwner == owner else { return }
        } else {
            // Legacy callers acquire their own request; a retired token cannot cancel it.
            previewOwner = nil
        }
        if updateDraft { query = newQuery }
        quickErrorMessage = nil
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        debounceTask?.cancel()
        previewGeneration &+= 1
        let generation = previewGeneration

        guard !trimmed.isEmpty else {
            quickResults = nil
            querySuggestions = []
            associatedQuickQuery = ""
            isQuickSearching = false
            isTopdownVisible = false
            return
        }

        quickResults = nil
        querySuggestions = []
        associatedQuickQuery = ""
        if let cached = previewCache[trimmed], Date().timeIntervalSince(cached.date) < 60 {
            applyPreview(cached.value, query: trimmed)
            return
        }
        isQuickSearching = true
        isTopdownVisible = true
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, generation == previewGeneration else { return }
            do {
                let results = try await core.searchSuggestions(query: trimmed)
                guard !Task.isCancelled, generation == previewGeneration else { return }
                // Entries are short lived, account scoped by clear(), and bounded by count and payload.
                let count = results.results.songs.count + results.results.topSongs.count + results.results.top.count
                    + results.results.artists.count + results.results.albums.count + results.results.playlists.count
                if count <= 100, results.queries.joined().utf8.count < 16_384 {
                    if previewCache.count >= 12, let oldest = previewCache.min(by: { $0.value.date < $1.value.date })?.key {
                        previewCache[oldest] = nil
                    }
                    previewCache[trimmed] = PreviewCacheEntry(value: results, date: Date())
                }
                applyPreview(results, query: trimmed)
            } catch {
                guard !Task.isCancelled, generation == previewGeneration else { return }
                quickError = AppMessage(key: "search.error.quick")
                isQuickSearching = false
            }
        }
    }

    private func applyPreview(_ response: SearchSuggestionsRecord, query: String) {
        quickResults = response.results
        querySuggestions = Array(response.queries.prefix(3))
        associatedQuickQuery = query
        quickErrorMessage = nil
        isQuickSearching = false
        isTopdownVisible = true
    }

    /// Invalidates a pending preview when the dropdown is dismissed or a search is submitted.
    public func cancelPreview() {
        previewOwner = nil
        debounceTask?.cancel()
        debounceTask = nil
        previewGeneration &+= 1
        quickErrorMessage = nil
        isQuickSearching = false
        isTopdownVisible = false
    }

    public func cancelPreview(owner: UUID) {
        guard previewOwner == owner else { return }
        cancelPreview()
    }

    // MARK: Full search

    public func commitSearch(query text: String, core: SideBCore, force: Bool = false, origin: SearchOrigin = .navigationRestore, ignoreSpelling: Bool? = nil, preservingPreview: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ignoresSpelling = ignoreSpelling ?? (trimmed == committedQuery && !origin.recordsHistory ? isOriginalSearch : false)

        if origin.recordsHistory { recentStore.recordQuery(trimmed) }
        // A background library refresh belongs to committed results, not the active editor.
        if !preservingPreview { cancelPreview() }
        if committedQuery == trimmed, ignoresSpelling == isOriginalSearch, !force,
           !origin.recordsHistory, committedResults != nil, !isCommittedLoading { return }
        if committedQuery == trimmed, ignoresSpelling == isOriginalSearch, isCommittedLoading, !force { return }

        queryGeneration &+= 1
        let generation = queryGeneration
        filterGeneration &+= 1
        commitTask?.cancel()
        filterTask?.cancel()

        committedQuery = trimmed
        isOriginalSearch = ignoresSpelling
        if !preservingPreview { query = trimmed }
        committedResults = nil
        correction = nil
        loadedFilters = []
        cardCache = [:]
        committedSongs = []
        committedVideos = []
        filteredSongs = []
        filteredCards = []
        errorMessage = nil
        partialErrors = [:]
        isMixedLoading = true; isSongsLoading = false; isVideosLoading = false
        isCommittedLoading = true
        isFilterLoading = false

        commitTask = Task {
            await loadMixed(query: trimmed, core: core, generation: generation, recordHistory: origin.recordsHistory, ignoreSpelling: ignoresSpelling)
            guard !Task.isCancelled, generation == queryGeneration else { return }
            isCommittedLoading = false
            loadSelectedFilter(core: core)
        }
    }

    private func loadMixed(query: String, core: SideBCore, generation: UInt, recordHistory: Bool, ignoreSpelling: Bool = false) async {
        defer { if generation == queryGeneration { isMixedLoading = false } }
        do {
            let catalog = try await core.searchCatalog(query: query, recordHistory: recordHistory, ignoreSpelling: ignoreSpelling)
            let results = catalog.results
            guard !Task.isCancelled, generation == queryGeneration else { return }
            committedResults = results
            correction = catalog.correction
            searchError = nil
            partialErrorMessages[.global] = nil
            let tracks = isOriginalSearch ? SearchProjection.originalSongs(results) : results.songs
            if !loadedFilters.contains(.videos), !isVideosLoading { committedVideos = tracks.filter(\.isVideo) }
            if !loadedFilters.contains(.songs), !isSongsLoading {
                committedSongs = tracks.filter { !$0.isVideo }
                if selectedFilter == .songs { filteredSongs = committedSongs }
            }
        } catch {
            guard !Task.isCancelled, generation == queryGeneration else { return }
            let message = AppMessage(key: "search.error.global"); searchError = message; partialErrorMessages[.global] = message
        }
    }
    private func loadSongs(query: String, core: SideBCore, generation: UInt) async {
        defer { if generation == queryGeneration { isSongsLoading = false } }
        do {
            let songs = try await core.searchSongs(query: query, recordHistory: false)
            guard !Task.isCancelled, generation == queryGeneration else { return }
            committedSongs = songs
            loadedFilters.insert(.songs)
        } catch {
            guard !Task.isCancelled, generation == queryGeneration else { return }
            partialErrorMessages[.songs] = AppMessage(key: "search.error.songs")
            committedSongs = committedResults?.songs.filter { !$0.isVideo } ?? []
        }
        if selectedFilter == .songs { filteredSongs = committedSongs }
    }
    private func loadVideos(query: String, core: SideBCore, generation: UInt) async {
        defer { if generation == queryGeneration { isVideosLoading = false } }
        do {
            let videos = try await core.searchVideos(query: query)
            guard !Task.isCancelled, generation == queryGeneration else { return }
            committedVideos = videos
            loadedFilters.insert(.videos)
        } catch {
            guard !Task.isCancelled, generation == queryGeneration else { return }
            partialErrorMessages[.videos] = AppMessage(key: "search.error.videos")
        }
    }

    public func retryBlock(_ block: SearchPartialError, core: SideBCore) {
        let query = committedQuery; guard !query.isEmpty else { return }
        let generation = queryGeneration
        partialErrorMessages[block] = nil
        switch block {
        case .global:
            guard !isMixedLoading else { return }; isMixedLoading = true
            Task { await loadMixed(query: query, core: core, generation: generation, recordHistory: false, ignoreSpelling: isOriginalSearch) }
        case .songs:
            guard !isSongsLoading else { return }; isSongsLoading = true
            Task { await loadSongs(query: query, core: core, generation: generation) }
        case .videos:
            guard !isVideosLoading else { return }; isVideosLoading = true
            Task { await loadVideos(query: query, core: core, generation: generation) }
        case .categories:
            filterGeneration &+= 1
            let effectiveQuery = correction?.applied == true ? correction!.query : query
            loadCards(for: selectedFilter, query: effectiveQuery, core: core, generation: filterGeneration)
        }
    }

    // MARK: Filters

    public func selectFilter(_ filter: SearchFilter, core: SideBCore) {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
        partialErrorMessages[.categories] = nil
        filterGeneration &+= 1
        filterTask?.cancel()
        isFilterLoading = false
        filteredCards = []

        guard !committedQuery.isEmpty else {
            filteredSongs = []
            return
        }

        loadSelectedFilter(core: core)
    }

    private func loadSelectedFilter(core: SideBCore) {
        let filter = selectedFilter
        guard !committedQuery.isEmpty, !isMixedLoading else { return }
        if isOriginalSearch {
            // The provider's opt-out exists only on mixed search. Keep its exact candidates
            // when filtering instead of silently issuing a newly corrected category search.
            switch filter {
            case .all: filteredSongs = []
            case .songs: filteredSongs = committedSongs
            case .videos: filteredSongs = []
            case .albums: filteredCards = committedResults.map { SearchProjection.originalCards($0, kind: "album") } ?? []
            case .artists: filteredCards = committedResults.map { SearchProjection.originalCards($0, kind: "artist") } ?? []
            case .playlists: filteredCards = committedResults.map { SearchProjection.originalCards($0, kind: "playlist") } ?? []
            }
            return
        }
        let query = correction?.applied == true ? correction!.query : committedQuery
        switch filter {
        case .all: filteredSongs = []
        case .songs:
            filteredSongs = committedSongs
            guard !loadedFilters.contains(.songs), !isSongsLoading else { return }
            isSongsLoading = true
            let generation = queryGeneration
            Task { await loadSongs(query: query, core: core, generation: generation) }
        case .videos:
            filteredSongs = []
            guard !loadedFilters.contains(.videos), !isVideosLoading else { return }
            isVideosLoading = true
            let generation = queryGeneration
            Task { await loadVideos(query: query, core: core, generation: generation) }
        case .albums, .artists, .playlists:
            if let cards = cardCache[filter] { filteredCards = cards; return }
            loadCards(for: filter, query: query, core: core, generation: filterGeneration)
        }
    }

    private func loadCards(for filter: SearchFilter, query: String, core: SideBCore, generation: UInt) {
        guard let category = categoryName(for: filter) else { return }
        let scopeQuery = committedQuery
        filterTask?.cancel()
        isFilterLoading = true
        filterTask = Task {
            do {
                let cards = try await core.searchCards(query: query, category: category)
                guard !Task.isCancelled, generation == filterGeneration,
                      queryGeneration > 0, committedQuery == scopeQuery, selectedFilter == filter else { return }
                filteredCards = cards
                cardCache[filter] = cards
                partialErrorMessages[.categories] = nil
            } catch {
                guard !Task.isCancelled, generation == filterGeneration,
                      committedQuery == scopeQuery, selectedFilter == filter else { return }
                partialErrorMessages[.categories] = AppMessage(key: "search.error.category")
            }
            guard !Task.isCancelled, generation == filterGeneration,
                  committedQuery == scopeQuery, selectedFilter == filter else { return }
            isFilterLoading = false
        }
    }

    private func categoryName(for filter: SearchFilter) -> String? {
        switch filter {
        case .albums: return "albums"
        case .artists: return "artists"
        case .playlists: return "playlists"
        case .all, .songs, .videos: return nil
        }
    }

    // MARK: Result helpers

    public func relatedSongs(for results: SearchResultsRecord) -> [SongItemRecord] {
        let hero = results.top.first
        var seen = Set<String>()
        return Array(results.topSongs.filter { song in
            guard !song.videoId.isEmpty, !(hero.map { ["song", "video"].contains($0.kind) && $0.id == song.videoId } ?? false) else { return false }
            return seen.insert(song.videoId).inserted
        }.prefix(3)).map { SearchProjection.associatedSong($0, in: results) }
    }

    public func displayVideos(excluding results: SearchResultsRecord?) -> [SongItemRecord] {
        var seen = Set(results?.top.filter { $0.kind == "video" }.map(\.id) ?? [])
        for song in results?.topSongs ?? [] where song.isVideo { seen.insert(song.videoId) }
        let videos = selectedFilter == .all ? (results?.songs.filter(\.isVideo) ?? []) : committedVideos
        return videos.filter { seen.insert($0.videoId).inserted }
    }

    public func song(for card: BrowseCardRecord, in results: SearchResultsRecord?) -> SongItemRecord {
        if let song = results?.topSongs.first(where: { $0.videoId == card.id }) { return song }
        if let song = results?.songs.first(where: { $0.videoId == card.id }) { return song }
        if let song = quickResults?.topSongs.first(where: { $0.videoId == card.id }) { return song }
        if let song = committedResults?.topSongs.first(where: { $0.videoId == card.id }) { return song }
        return SongItemRecord(fromCard: card)
    }

    // MARK: Categories

    public func dynamicCategories(for results: SearchResultsRecord) -> [SearchCategory] {
        var order: [SearchCategory] = []
        if !results.top.isEmpty { order.append(.topResult) }
        if !results.songs.isEmpty { order.append(.songs) }
        if !results.artists.isEmpty { order.append(.artists) }
        if !results.albums.isEmpty { order.append(.albums) }
        if !results.playlists.isEmpty { order.append(.playlists) }
        return order
    }

    // MARK: Reset

    public func clear() {
        queryGeneration &+= 1
        filterGeneration &+= 1
        cancelPreview()
        commitTask?.cancel()
        filterTask?.cancel()
        commitTask = nil
        filterTask = nil

        query = ""
        committedQuery = ""
        isOriginalSearch = false
        quickResults = nil
        querySuggestions = []
        previewCache = [:]
        associatedQuickQuery = ""
        quickErrorMessage = nil
        committedResults = nil
        correction = nil
        loadedFilters = []
        cardCache = [:]
        committedSongs = []
        committedVideos = []
        filteredSongs = []
        filteredCards = []
        selectedFilter = .all
        isQuickSearching = false
        isTopdownVisible = false
        isCommittedLoading = false
        isMixedLoading = false; isSongsLoading = false; isVideosLoading = false
        isFilterLoading = false
        errorMessage = nil
        partialErrorMessages = [:]
    }
}
