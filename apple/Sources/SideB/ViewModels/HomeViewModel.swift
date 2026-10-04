import Foundation
import CryptoKit
import Observation
import os
import SideBCore

@MainActor
@Observable
final class HomeViewModel {
    private struct FeedSnapshot {
        let records: [HomeSectionRecord]
        let continuation: String?
    }

    var chips: [HomeChipRecord] = []
    var selectedChipParams: String?
    var sections: [HomeSectionPresentation] = []
    private(set) var featured = HomeFeaturedPresentation.empty
    private(set) var featuredCollectionKind: HomeFeaturedCollectionKind
    private(set) var recommendationSettings = HomeRecommendationSettings()
    private(set) var receivedCategories: [HomeCategoryOption] = []
    private(set) var selectionRevision: UInt64 = 0
    private(set) var featuredCapacity = 2
    private(set) var supplementalError: String?
    @ObservationIgnored private var supplemental: [HomeRecommendationSource: [HomeItemRecord]] = [:]
    @ObservationIgnored private var didRequestSupplemental = false
    @ObservationIgnored private var forceSupplementalReload = false
    var continuationToken: String?
    var isLoading = false
    var isLoadingChip = false
    var isRefreshing = false
    var isLoadingMore = false
    var isShowingSavedFeed = false
    var errorMessage: String?
    private(set) var loadMoreMessage: String?
    private(set) var contentRevision: UInt64 = 0

    @ObservationIgnored private let signposter = OSSignposter(subsystem: "com.fefucho.SideB", category: .pointsOfInterest)
    @ObservationIgnored private let cacheStore: HomeFeedCacheStore
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var cacheTransition: Task<Void, Never>?
    @ObservationIgnored private var priorityPrefetchTask: Task<Void, Never>?
    @ObservationIgnored private var sessionKey = "guest"
    @ObservationIgnored private var sessionToken = UUID().uuidString
    @ObservationIgnored private var didHydrate = false
    @ObservationIgnored private var sectionRecords: [HomeSectionRecord] = []
    @ObservationIgnored private var snapshots: [String: FeedSnapshot] = [:]
    @ObservationIgnored private var snapshotOrder: [String] = []
    @ObservationIgnored private var requestGeneration: UInt64 = 0

    init(cacheStore: HomeFeedCacheStore = HomeFeedCacheStore(), preferences: UserDefaults? = nil) {
        self.cacheStore = cacheStore
        let preferences = preferences ?? (HomeLabConfiguration.enabled
            ? UserDefaults(suiteName: "com.fefucho.SideB.HomeLab.HomePreferences")!
            : .standard)
        self.preferences = preferences
        featuredCollectionKind = preferences.string(forKey: Self.collectionPreferenceKey)
            .flatMap(HomeFeaturedCollectionKind.init(rawValue:)) ?? .albums
        recommendationSettings = readSettings(for: sessionKey)
        featured = HomeFeaturedPresentation.make(from: [], collectionKind: featuredCollectionKind)
    }

    private static let collectionPreferenceKey = "sideb.home.featuredCollectionKind"

    func setFeaturedCollectionKind(_ kind: HomeFeaturedCollectionKind) {
        guard featuredCollectionKind != kind else { return }
        featuredCollectionKind = kind
        preferences.set(kind.rawValue, forKey: Self.collectionPreferenceKey)
        selectionRevision &+= 1
        rebuildProjection(forceRevision: true)
    }

    private func settingsKey(for identity: String) -> String {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "sideb.home.recommendations.v1.\(hash)"
    }

    private func readSettings(for identity: String) -> HomeRecommendationSettings {
        guard let data = preferences.data(forKey: settingsKey(for: identity)),
              let settings = try? JSONDecoder().decode(HomeRecommendationSettings.self, from: data) else { return HomeRecommendationSettings() }
        return settings
    }

    func setRecommendationSettings(_ settings: HomeRecommendationSettings) {
        guard settings != recommendationSettings else { return }
        let sourcesChanged = settings.sources(for: featuredCollectionKind) != recommendationSettings.sources(for: featuredCollectionKind)
        recommendationSettings = settings
        if let data = try? JSONEncoder().encode(settings) { preferences.set(data, forKey: settingsKey(for: sessionKey)) }
        if sourcesChanged { selectionRevision &+= 1 }
        rebuildProjection()
    }

    func setFeaturedCapacity(_ capacity: Int) {
        let capacity = [2, 4, 6].contains(capacity) ? capacity : 2
        guard capacity != featuredCapacity else { return }
        featuredCapacity = capacity
        rebuildProjection()
    }

    private func rebuildProjection(forceRevision: Bool = false) {
        let providerSections = HomePresentationFactory.sections(from: sectionRecords, chip: selectedChipParams)
        let shelfRecords = recommendationSettings.visibleFeedRecords(recommendationSettings.orderedFeedRecords(sectionRecords))
        let shelfSections = HomePresentationFactory.sections(from: shelfRecords, chip: selectedChipParams,
            preserveProviderOrder: recommendationSettings.categoryOrderMode != .sideB)
        let projected = HomeFeaturedPresentation.make(from: providerSections, collectionKind: featuredCollectionKind,
            settings: recommendationSettings, capacity: featuredCapacity, supplemental: supplemental, shelfSections: shelfSections)
        sections = providerSections
        var seen = Set<String>()
        let categoryOptions = recommendationSettings.categoryOrderMode == .sideB
            ? providerSections.map { HomeCategoryOption(id: HomeRecommendationSettings.categoryKey(forTitle: $0.title), title: $0.title) }
            : recommendationSettings.orderedFeedRecords(sectionRecords).map {
                HomeCategoryOption(id: HomeRecommendationSettings.categoryKey(forTitle: $0.title), title: $0.title)
            }
        receivedCategories = categoryOptions.filter { seen.insert($0.id).inserted }
        let visibleChanged = forceRevision || projected != featured
        featured = projected
        if visibleChanged { contentRevision &+= 1 }
    }

    /// Uses already loaded library/history lists; no collection catalogs are requested.
    func updateSupplemental(albums: [BrowseCardRecord], playlists: [BrowseCardRecord], history: [HistoryGroupRecord]) {
        func item(_ card: BrowseCardRecord) -> HomeItemRecord {
            HomeItemRecord(kind: card.kind, id: card.id, title: card.title, subtitle: card.subtitle,
                thumbnail: card.thumbnail, duration: card.duration, artists: nil, artistId: nil,
                album: nil, albumId: nil, artistRuns: [], explicit: false)
        }
        let albumCards = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let recent = history.flatMap(\.items).compactMap { song -> HomeItemRecord? in
            guard let id = song.albumId, !id.isEmpty, seen.insert(id).inserted else { return nil }
            if let card = albumCards[id] { return item(card) }
            return HomeItemRecord(kind: "album", id: id, title: song.album ?? "Álbum", subtitle: song.artists,
                thumbnail: nil, duration: nil, artists: song.artists, artistId: song.artistId,
                album: nil, albumId: nil, artistRuns: song.artistRuns, explicit: false)
        }
        let next: [HomeRecommendationSource: [HomeItemRecord]] = [
            .libraryAlbums: albums.map(item), .libraryPlaylists: playlists.map(item), .recentAlbums: recent
        ]
        guard next != supplemental else { return }
        supplemental = next
        rebuildProjection()
    }

    func loadSupplementalIfNeeded(core: SideBCore, library: LibraryViewModel) async {
        let externalSources: Set<HomeRecommendationSource> = [.libraryAlbums, .libraryPlaylists, .recentAlbums]
        guard recommendationSettings.sources(for: featuredCollectionKind).contains(where: { $0.enabled && externalSources.contains($0.source) }),
              !didRequestSupplemental, core.isLoggedIn(), !library.isLoading else { return }
        didRequestSupplemental = true
        let requestedSession = sessionToken
        supplementalError = nil
        if forceSupplementalReload || (library.albums.isEmpty && library.playlists.isEmpty && library.historyGroups.isEmpty) {
            forceSupplementalReload = false
            await library.loadLibrary(core: core)
            guard requestedSession == sessionToken, !Task.isCancelled else { return }
        }
        supplementalError = library.errorMessage
        updateSupplemental(albums: library.albums, playlists: library.playlists, history: library.historyGroups)
    }

    func retrySupplemental() {
        didRequestSupplemental = false
        forceSupplementalReload = true
        selectionRevision &+= 1
    }

    var allFeaturedSourcesDisabled: Bool {
        !recommendationSettings.sources(for: featuredCollectionKind).contains(where: \.enabled)
    }

    /// Se llama después de instalar la cookie en Core y antes de mostrar Inicio.
    func prepareSession(identity: String, purgePrevious: Bool = true) {
        priorityPrefetchTask?.cancel()
        priorityPrefetchTask = nil
        supplemental.removeAll()
        didRequestSupplemental = false
        supplementalError = nil
        forceSupplementalReload = false
        receivedCategories = []
        let oldKey = sessionKey
        let oldToken = sessionToken
        let previousTransition = cacheTransition
        sessionKey = identity
        recommendationSettings = readSettings(for: identity)
        selectionRevision &+= 1
        sessionToken = UUID().uuidString
        let newToken = sessionToken
        requestGeneration &+= 1
        didHydrate = false
        snapshots.removeAll()
        snapshotOrder.removeAll()
        sectionRecords = []
        chips = []
        selectedChipParams = nil
        sections = []
        featured = HomeFeaturedPresentation.make(from: [], collectionKind: featuredCollectionKind)
        continuationToken = nil
        isLoading = false
        isLoadingChip = false
        isRefreshing = false
        isLoadingMore = false
        isShowingSavedFeed = false
        errorMessage = nil
        loadMoreMessage = nil
        contentRevision &+= 1
        cacheTransition = Task { [cacheStore] in
            await previousTransition?.value
            if purgePrevious { await cacheStore.retire(oldKey, token: oldToken) }
            await cacheStore.activate(identity, token: newToken)
        }
    }

    func resetForAccountChange() { prepareSession(identity: "guest") }

    func loadHomeFeed(core: SideBCore, chipParams: String? = nil) async {
        priorityPrefetchTask?.cancel()
        priorityPrefetchTask = nil
        isLoadingMore = false
        loadMoreMessage = nil
        requestGeneration &+= 1
        let generation = requestGeneration
        let key = chipParams ?? ""
        let previousChip = selectedChipParams
        let changedChip = previousChip != chipParams

        if chipParams == nil, !didHydrate, sections.isEmpty {
            await hydrateSavedFeed(generation: generation)
            guard generation == requestGeneration else { return }
        }

        selectedChipParams = chipParams
        if let cached = snapshots[key] {
            apply(records: cached.records, continuation: cached.continuation, chip: chipParams)
        } else if changedChip {
            continuationToken = nil
            contentRevision &+= 1
        }
        isLoading = sections.isEmpty
        isLoadingChip = changedChip && !sections.isEmpty
        isRefreshing = !changedChip && !sections.isEmpty
        isLoadingMore = false
        errorMessage = nil

        do {
            let page = try await fetchHomePage(core: core, chipParams: chipParams)
            guard generation == requestGeneration, !Task.isCancelled else { return }
            if !HomeLabConfiguration.usesFixture && !core.isLoggedIn() && sessionKey != "guest" {
                let oldKey = sessionKey
                let oldToken = sessionToken
                sessionKey = "guest"
                recommendationSettings = readSettings(for: "guest")
                supplemental.removeAll()
                receivedCategories = []
                didRequestSupplemental = false
                selectionRevision &+= 1
                sessionToken = UUID().uuidString
                let newToken = sessionToken
                snapshots.removeAll()
                snapshotOrder.removeAll()
                cacheTransition = Task { [cacheStore] in
                    await cacheStore.retire(oldKey, token: oldToken)
                    await cacheStore.activate("guest", token: newToken)
                }
            }
            if chipParams == nil && !page.chips.isEmpty { chips = page.chips }
            let interval = signposter.beginInterval("HomeFeedPresent")
            apply(records: page.sections, continuation: page.continuation, chip: chipParams)
            signposter.endInterval("HomeFeedPresent", interval)
            remember(FeedSnapshot(records: page.sections, continuation: page.continuation), for: key)
            isShowingSavedFeed = false
            finishLoading()

            if chipParams == nil {
                await cacheTransition?.value
                guard generation == requestGeneration else { return }
                await cacheStore.save(HomeCachedPage(page), for: sessionKey, token: sessionToken)
                if let token = page.continuation {
                    startPriorityPrefetch(core: core, token: token, generation: generation, chip: chipParams)
                }
            }
        } catch {
            guard generation == requestGeneration else { return }
            if !Task.isCancelled {
                if changedChip && snapshots[key] == nil && !sections.isEmpty {
                    selectedChipParams = previousChip
                    continuationToken = snapshots[previousChip ?? ""]?.continuation
                }
                errorMessage = error.localizedDescription
            }
            finishLoading()
        }
    }

    func loadMoreContent(core: SideBCore) async {
        guard var token = continuationToken,
              !isLoadingMore, !isLoading, !isLoadingChip, !isRefreshing else { return }
        let generation = requestGeneration
        let key = selectedChipParams ?? ""
        loadMoreMessage = nil
        isLoadingMore = true
        defer {
            if generation == requestGeneration { isLoadingMore = false }
        }
        do {
            let visibleRevision = contentRevision
            var existing = Set(sectionRecords.map(Self.sectionSignature))
            var usedTokens = Set<String>()
            // Some pages only repeat shelves already prefetched. Advance to new
            // content within this click, with the same three-request cap as preload.
            for _ in 0..<3 {
                guard usedTokens.insert(token).inserted else { break }
                let page = try await fetchContinuation(core: core, token: token)
                guard generation == requestGeneration, continuationToken == token, !Task.isCancelled else { return }
                let fresh = page.sections.filter { existing.insert(Self.sectionSignature($0)).inserted }
                let next = page.continuation.flatMap {
                    $0.isEmpty || usedTokens.contains($0) ? nil : $0
                }
                if fresh.isEmpty {
                    continuationToken = next
                } else {
                    sectionRecords.append(contentsOf: fresh)
                    apply(records: sectionRecords, continuation: next, chip: selectedChipParams)
                }
                remember(FeedSnapshot(records: sectionRecords, continuation: next), for: key)
                guard let next else {
                    loadMoreMessage = "No hay más recomendaciones por ahora."
                    return
                }
                if contentRevision != visibleRevision { return }
                token = next
            }
            loadMoreMessage = "Esta tanda no trajo recomendaciones visibles nuevas. Podés cargar la siguiente."
        } catch {
            guard generation == requestGeneration, !Task.isCancelled else { return }
            loadMoreMessage = "No se pudieron cargar más recomendaciones. Volvé a intentarlo."
        }
    }

    private func hydrateSavedFeed(generation: UInt64) async {
        didHydrate = true
        if let cacheTransition { await cacheTransition.value }
        else { await cacheStore.activate(sessionKey, token: sessionToken) }
        let interval = signposter.beginInterval("HomeFeedHydrate")
        let cached = await cacheStore.load(for: sessionKey, token: sessionToken)
        signposter.endInterval("HomeFeedHydrate", interval)
        guard generation == requestGeneration, let cached else { return }
        let page = cached.page
        chips = page.chips
        apply(records: page.sections, continuation: nil, chip: nil)
        remember(FeedSnapshot(records: page.sections, continuation: nil), for: "")
        isShowingSavedFeed = true
    }

    private func apply(records: [HomeSectionRecord], continuation: String?, chip: String?) {
        sectionRecords = records
        continuationToken = continuation
        rebuildProjection()
    }

    private func finishLoading() {
        isLoading = false
        isLoadingChip = false
        isRefreshing = false
    }

    private func fetchHomePage(core: SideBCore, chipParams: String?) async throws -> HomePageRecord {
        let interval = signposter.beginInterval("HomeFeedFetch")
        defer { signposter.endInterval("HomeFeedFetch", interval) }
        if HomeLabConfiguration.usesFixture {
            try await Task.sleep(for: .milliseconds(700))
            return HomeBenchmarkFixture.page(chipParams: chipParams)
        }
        return try await core.getHomePage(chipParams: chipParams)
    }

    private func fetchContinuation(core: SideBCore, token: String) async throws -> HomePageRecord {
        let interval = signposter.beginInterval("HomeFeedContinuation")
        defer { signposter.endInterval("HomeFeedContinuation", interval) }
        if HomeLabConfiguration.usesFixture { return HomeBenchmarkFixture.page(continuation: true) }
        return try await core.getHomeContinuation(token: token)
    }

    private static func sectionSignature(_ section: HomeSectionRecord) -> String {
        let first = section.items.first.map { "\($0.kind):\($0.id)" } ?? ""
        let last = section.items.last.map { "\($0.kind):\($0.id)" } ?? ""
        if let browseID = section.moreBrowseId, !browseID.isEmpty {
            return "more|\(browseID)|\(section.moreParams ?? "")|\(first)|\(last)"
        }
        return "items|\(first)|\(last)"
    }

    private func startPriorityPrefetch(core: SideBCore, token: String, generation: UInt64, chip: String?) {
        guard chip == nil, !hasReceivedEnabledSources else { return }
        priorityPrefetchTask = Task { [weak self] in
            await self?.prefetchPrioritySections(core: core, token: token, generation: generation)
        }
    }

    private func prefetchPrioritySections(core: SideBCore, token initialToken: String, generation: UInt64) async {
        guard generation == requestGeneration, continuationToken == initialToken,
              !isLoadingMore, !Task.isCancelled else { return }
        let interval = signposter.beginInterval("HomePriorityPrefetch")
        isLoadingMore = true
        defer {
            signposter.endInterval("HomePriorityPrefetch", interval)
            if generation == requestGeneration { isLoadingMore = false }
        }

        // Three continuation requests cap background network work while covering the usual Home
        // response split. Stop sooner when every named priority section has arrived or after 12s.
        let maximumPages = 3
        let timeBudget: TimeInterval = 12
        let startedAt = Date()
        var token = initialToken
        var usedTokens = Set<String>()
        for _ in 0..<maximumPages {
            guard generation == requestGeneration, !Task.isCancelled,
                  Date().timeIntervalSince(startedAt) < timeBudget,
                  usedTokens.insert(token).inserted else { break }
            do {
                let page = try await fetchContinuation(core: core, token: token)
                guard generation == requestGeneration, !Task.isCancelled else { return }
                var existing = Set(sectionRecords.map(Self.sectionSignature))
                let fresh = page.sections.filter { existing.insert(Self.sectionSignature($0)).inserted }
                continuationToken = page.continuation
                if !fresh.isEmpty {
                    sectionRecords.append(contentsOf: fresh)
                    apply(records: sectionRecords, continuation: page.continuation, chip: nil)
                }

                guard let next = page.continuation, !next.isEmpty, next != token,
                      !usedTokens.contains(next) else {
                    continuationToken = nil
                    break
                }
                token = next
                if hasReceivedEnabledSources { break }
            } catch {
                break
            }
        }

        guard generation == requestGeneration, !Task.isCancelled else { return }
        let snapshot = FeedSnapshot(records: sectionRecords, continuation: continuationToken)
        remember(snapshot, for: "")
        await cacheStore.save(
            HomeCachedPage(HomePageRecord(chips: chips, sections: sectionRecords, continuation: nil)),
            for: sessionKey,
            token: sessionToken
        )
    }

    private var hasReceivedEnabledSources: Bool {
        let keys = Set(sectionRecords.map { HomeRecommendationSettings.categoryKey(forTitle: $0.title) })
        let required = recommendationSettings.sources(for: featuredCollectionKind).filter { $0.enabled }.compactMap { rule -> String? in
            switch rule.source {
            case .recommendedAlbums: return HomeRecommendationSettings.categoryKey(forTitle: "Albums for you")
            case .mixesForYou: return HomeRecommendationSettings.categoryKey(forTitle: "Mixed for you")
            case .listenAgain: return HomeRecommendationSettings.categoryKey(forTitle: "Listen again")
            case .forgottenFavorites: return HomeRecommendationSettings.categoryKey(forTitle: "Forgotten favorites")
            case .fromLibrary: return HomeRecommendationSettings.categoryKey(forTitle: "From your library")
            case .newReleases: return HomeRecommendationSettings.categoryKey(forTitle: "New releases")
            case .fromCommunity: return HomeRecommendationSettings.categoryKey(forTitle: "From the community")
            default: return nil
            }
        }
        return required.allSatisfy(keys.contains)
    }

    private func remember(_ snapshot: FeedSnapshot, for key: String) {
        snapshots[key] = snapshot
        snapshotOrder.removeAll { $0 == key }
        snapshotOrder.append(key)
        if snapshotOrder.count > 4 { snapshots.removeValue(forKey: snapshotOrder.removeFirst()) }
    }
}

struct HomeCategoryOption: Identifiable, Equatable {
    let id: String
    let title: String
}
