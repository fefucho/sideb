import SwiftUI
import SideBCore

// MARK: - SearchFilter

public enum SearchFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Todo"
    case songs = "Canciones"
    case videos = "Videos"
    case albums = "Álbumes"
    case artists = "Artistas"
    case playlists = "Playlists"

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
    @ObservationIgnored private var queryGeneration: UInt = 0
    @ObservationIgnored private var filterGeneration: UInt = 0

    public init() {}

    // MARK: Preview

    public func onQueryChanged(_ newQuery: String, core: SideBCore) {
        query = newQuery
        quickErrorMessage = nil
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        debounceTask?.cancel()
        previewGeneration &+= 1
        let generation = previewGeneration

        guard !trimmed.isEmpty else {
            quickResults = nil
            associatedQuickQuery = ""
            isQuickSearching = false
            isTopdownVisible = false
            return
        }

        if trimmed == associatedQuickQuery, quickResults != nil {
            isQuickSearching = false
            isTopdownVisible = true
            return
        }

        if trimmed != associatedQuickQuery { quickResults = nil }
        isQuickSearching = true
        isTopdownVisible = true
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, generation == previewGeneration else { return }
            do {
                let results = try await core.searchAll(query: trimmed, recordHistory: false)
                guard !Task.isCancelled, generation == previewGeneration else { return }
                quickResults = results
                associatedQuickQuery = trimmed
                quickErrorMessage = nil
                isQuickSearching = false
                isTopdownVisible = true
            } catch {
                guard !Task.isCancelled, generation == previewGeneration else { return }
                quickError = AppMessage(key: "search.error.quick")
                isQuickSearching = false
            }
        }
    }

    /// Invalidates a pending preview when the dropdown is dismissed or a search is submitted.
    public func cancelPreview() {
        debounceTask?.cancel()
        debounceTask = nil
        previewGeneration &+= 1
        quickErrorMessage = nil
        isQuickSearching = false
        isTopdownVisible = false
    }

    // MARK: Full search

    public func commitSearch(query text: String, core: SideBCore, force: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        cancelPreview()
        if committedQuery == trimmed, !force, committedResults != nil, !isCommittedLoading { return }
        if committedQuery == trimmed, isCommittedLoading, !force { return }

        queryGeneration &+= 1
        let generation = queryGeneration
        filterGeneration &+= 1
        commitTask?.cancel()
        filterTask?.cancel()

        committedQuery = trimmed
        query = trimmed
        committedResults = nil
        committedSongs = []
        committedVideos = []
        filteredSongs = []
        filteredCards = []
        errorMessage = nil
        partialErrors = [:]
        isCommittedLoading = true
        isFilterLoading = false

        commitTask = Task {
            async let mixed = capture { try await core.searchAll(query: trimmed, recordHistory: true) }
            async let songs = capture { try await core.searchSongs(query: trimmed, recordHistory: false) }
            async let videos = capture { try await core.searchVideos(query: trimmed) }

            let (mixedResult, songsResult, videosResult) = await (mixed, songs, videos)
            guard !Task.isCancelled, generation == queryGeneration, committedQuery == trimmed else { return }

            switch mixedResult {
            case .success(let results): committedResults = results
            case .failure:
                let message = AppMessage(key: "search.error.global")
                searchError = message
                partialErrorMessages[.global] = message
            }

            switch songsResult {
            case .success(let songs): committedSongs = songs
            case .failure:
                partialErrorMessages[.songs] = AppMessage(key: "search.error.songs")
                committedSongs = (committedResults?.songs ?? []).filter { !$0.isVideo }
            }

            switch videosResult {
            case .success(let videos): committedVideos = videos
            case .failure: partialErrorMessages[.videos] = AppMessage(key: "search.error.videos")
            }

            if selectedFilter == .songs { filteredSongs = committedSongs }
            isCommittedLoading = false
        }
        if selectedFilter == .albums || selectedFilter == .artists || selectedFilter == .playlists {
            loadCards(for: selectedFilter, query: trimmed, core: core, generation: filterGeneration)
        }
    }

    // MARK: Filters

    public func selectFilter(_ filter: SearchFilter, core: SideBCore) {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
        filterGeneration &+= 1
        let generation = filterGeneration
        filterTask?.cancel()
        isFilterLoading = false
        filteredCards = []

        guard !committedQuery.isEmpty else {
            filteredSongs = []
            return
        }

        switch filter {
        case .all:
            filteredSongs = []
        case .songs:
            filteredSongs = committedSongs
        case .videos:
            filteredSongs = []
        case .albums, .artists, .playlists:
            loadCards(for: filter, query: committedQuery, core: core, generation: generation)
        }
    }

    private func loadCards(for filter: SearchFilter, query: String, core: SideBCore, generation: UInt) {
        guard let category = categoryName(for: filter) else { return }
        filterTask?.cancel()
        isFilterLoading = true
        filterTask = Task {
            do {
                let cards = try await core.searchCards(query: query, category: category)
                guard !Task.isCancelled, generation == filterGeneration,
                      queryGeneration > 0, committedQuery == query, selectedFilter == filter else { return }
                filteredCards = cards
                partialErrorMessages[.categories] = nil
            } catch {
                guard !Task.isCancelled, generation == filterGeneration,
                      committedQuery == query, selectedFilter == filter else { return }
                partialErrorMessages[.categories] = AppMessage(key: "search.error.category")
            }
            guard !Task.isCancelled, generation == filterGeneration,
                  committedQuery == query, selectedFilter == filter else { return }
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
        let byID = Dictionary(results.topSongs.map { ($0.videoId, $0) }, uniquingKeysWith: { first, _ in first })
        return Array(results.top.dropFirst().compactMap { byID[$0.id] }.prefix(3))
    }

    public func song(for card: BrowseCardRecord, in results: SearchResultsRecord?) -> SongItemRecord {
        if let song = results?.topSongs.first(where: { $0.videoId == card.id }) { return song }
        return SongItemRecord(fromCard: card)
    }

    // MARK: Categories

    public func dynamicCategories(for results: SearchResultsRecord) -> [SearchCategory] {
        var order: [SearchCategory] = []
        let primaryKind = results.top.first?.kind.lowercased()
        if !results.top.isEmpty { order.append(.topResult) }

        switch primaryKind {
        case "artist":
            if !results.artists.isEmpty { order.append(.artists) }
            if !results.songs.isEmpty { order.append(.songs) }
            if !results.albums.isEmpty { order.append(.albums) }
            if !results.playlists.isEmpty { order.append(.playlists) }
        case "song":
            if !results.songs.isEmpty { order.append(.songs) }
            if !results.artists.isEmpty { order.append(.artists) }
            if !results.albums.isEmpty { order.append(.albums) }
            if !results.playlists.isEmpty { order.append(.playlists) }
        case "album":
            if !results.albums.isEmpty { order.append(.albums) }
            if !results.songs.isEmpty { order.append(.songs) }
            if !results.artists.isEmpty { order.append(.artists) }
            if !results.playlists.isEmpty { order.append(.playlists) }
        default:
            if !results.artists.isEmpty { order.append(.artists) }
            if !results.songs.isEmpty { order.append(.songs) }
            if !results.albums.isEmpty { order.append(.albums) }
            if !results.playlists.isEmpty { order.append(.playlists) }
        }
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
        quickResults = nil
        associatedQuickQuery = ""
        quickErrorMessage = nil
        committedResults = nil
        committedSongs = []
        committedVideos = []
        filteredSongs = []
        filteredCards = []
        selectedFilter = .all
        isQuickSearching = false
        isTopdownVisible = false
        isCommittedLoading = false
        isFilterLoading = false
        errorMessage = nil
        partialErrorMessages = [:]
    }
}

private func capture<Value>(_ operation: () async throws -> Value) async -> Result<Value, Error> {
    do { return .success(try await operation()) }
    catch { return .failure(error) }
}
