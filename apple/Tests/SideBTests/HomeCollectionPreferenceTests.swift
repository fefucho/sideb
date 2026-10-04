import Foundation
import Testing
import SideBCore
@testable import SideB

private func preferenceItem(_ kind: String, _ id: String) -> HomeItemRecord {
    HomeItemRecord(kind: kind, id: id, title: id, subtitle: nil, thumbnail: "cover-\(id)",
        duration: nil, artists: nil, artistId: nil, album: nil, albumId: nil, artistRuns: [], explicit: false)
}

private func preferenceSection(_ title: String, _ items: [HomeItemRecord]) -> HomeSectionRecord {
    HomeSectionRecord(title: title, format: .largeCards, items: items, moreBrowseId: nil, moreParams: nil)
}

private actor CollectionFeedStub {
    private var pageCount = 0
    private var continuationCount = 0
    let prefix: String

    init(prefix: String) { self.prefix = prefix }

    func page() -> HomePageRecord {
        pageCount += 1
        // Cover all preload priorities so tests exercise manual pagination only.
        return HomePageRecord(chips: [HomeChipRecord(title: "Focus", params: "focus")], sections: [
            preferenceSection("Mixed for you", [preferenceItem("playlist", "\(prefix)-mix")]),
            preferenceSection("Listen again", [preferenceItem("song", "\(prefix)-recent"), preferenceItem("album", "\(prefix)-recent-album")]),
            preferenceSection("Forgotten favorites", [preferenceItem("playlist", "\(prefix)-forgotten")]),
            preferenceSection("Albums for you", [preferenceItem("album", "\(prefix)-album")]),
            preferenceSection("From your library", [preferenceItem("album", "\(prefix)-library")]),
            preferenceSection("Quick picks", [preferenceItem("song", "\(prefix)-quick")]),
        ], continuation: "next-\(prefix)")
    }

    func continuation() -> HomePageRecord {
        continuationCount += 1
        return HomePageRecord(chips: [], sections: [
            preferenceSection("More recommendations", [preferenceItem("playlist", "\(prefix)-more"), preferenceItem("album", "\(prefix)-more-album")]),
        ], continuation: nil)
    }

    func counts() -> (pages: Int, continuations: Int) { (pageCount, continuationCount) }
}

private final class CollectionCoreStub: SideBCore, @unchecked Sendable {
    let feed: CollectionFeedStub

    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        feed = CollectionFeedStub(prefix: "unused")
        super.init(unsafeFromRawPointer: pointer)
    }

    init(prefix: String = "account-a") {
        feed = CollectionFeedStub(prefix: prefix)
        super.init(noPointer: .init())
    }

    override func isLoggedIn() -> Bool { true }
    override func getHomePage(chipParams: String?) async throws -> HomePageRecord { await feed.page() }
    override func getHomeContinuation(token: String) async throws -> HomePageRecord { await feed.continuation() }
}

@MainActor private func preferenceModel(_ preferences: UserDefaults) -> HomeViewModel {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sideb-home-collection-tests-\(UUID().uuidString)", isDirectory: true)
    let model = HomeViewModel(cacheStore: HomeFeedCacheStore(directory: directory), preferences: preferences)
    model.prepareSession(identity: "collection-test-account", purgePrevious: false)
    return model
}

@Test @MainActor func homeCollectionPreferenceDefaultsToAlbumsAndRejectsUnknownValues() throws {
    let suite = "SideBHomeCollection.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let initial = preferenceModel(preferences)
    #expect(initial.featuredCollectionKind == .albums)
    #expect(initial.featured == .empty)

    preferences.set("unsupported", forKey: "sideb.home.featuredCollectionKind")
    #expect(preferenceModel(preferences).featuredCollectionKind == .albums)
}

@Test @MainActor func homeCollectionPreferencePersistsAndRepeatingItDoesNotRebuild() throws {
    let suite = "SideBHomeCollection.\(UUID().uuidString)"
    let otherSuite = "SideBHomeCollection.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    let otherPreferences = try #require(UserDefaults(suiteName: otherSuite))
    defer {
        preferences.removePersistentDomain(forName: suite)
        otherPreferences.removePersistentDomain(forName: otherSuite)
    }
    let model = preferenceModel(preferences)
    let originalRevision = model.contentRevision
    model.setFeaturedCollectionKind(.playlists)
    #expect(model.contentRevision == originalRevision + 1)
    #expect(model.featured.collectionKind == .playlists)
    #expect(model.featured.collections.isEmpty)
    model.setFeaturedCollectionKind(.playlists)
    #expect(model.contentRevision == originalRevision + 1)
    #expect(preferenceModel(preferences).featuredCollectionKind == .playlists)
    #expect(preferenceModel(otherPreferences).featuredCollectionKind == .albums)

    model.setFeaturedCollectionKind(.albums)
    #expect(model.contentRevision == originalRevision + 2)
    #expect(preferenceModel(preferences).featuredCollectionKind == .albums)
}

@Test @MainActor func homeCollectionSwitchChangesOnlyProjectionAndNeverRequestsNetwork() async throws {
    let suite = "SideBHomeCollection.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = preferenceModel(preferences)
    let core = CollectionCoreStub()
    await model.loadHomeFeed(core: core, chipParams: "focus")
    let originalSections = model.sections
    let originalFeatured = model.featured
    let originalRevision = model.contentRevision
    let originalChips = model.chips
    let originalToken = model.continuationToken
    let requestsBefore = await core.feed.counts()
    model.errorMessage = "Prior feed error"
    model.isLoadingMore = true
    model.isShowingSavedFeed = true

    model.setFeaturedCollectionKind(.playlists)
    #expect(model.featured.collections.map(\.id) == ["account-a-mix", "account-a-forgotten"])
    #expect(model.sections == originalSections)
    #expect(model.featured.songs == originalFeatured.songs)
    #expect(model.continuationToken == originalToken)
    #expect(model.selectedChipParams == "focus")
    #expect(model.chips == originalChips)
    #expect(model.isLoadingMore)
    #expect(model.isShowingSavedFeed)
    #expect(!model.isLoading && !model.isLoadingChip && !model.isRefreshing)
    #expect(model.errorMessage == "Prior feed error")
    #expect(model.contentRevision == originalRevision + 1)
    let requestsAfter = await core.feed.counts()
    #expect(requestsAfter.pages == requestsBefore.pages)
    #expect(requestsAfter.continuations == requestsBefore.continuations)

    model.setFeaturedCollectionKind(.albums)
    #expect(model.featured == originalFeatured)
    #expect(model.sections == originalSections)
    #expect(model.continuationToken == originalToken)
}

@Test @MainActor func homeCollectionChoiceSurvivesPaginationRefreshAndChipChanges() async throws {
    let suite = "SideBHomeCollection.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = preferenceModel(preferences)
    let core = CollectionCoreStub()
    model.setFeaturedCollectionKind(.playlists)
    await model.loadHomeFeed(core: core)
    #expect(model.featured.collectionKind == .playlists)
    #expect(model.chips.map(\.params) == ["focus"])
    await model.loadMoreContent(core: core)
    #expect(model.featured.collections.map(\.id) == ["account-a-mix", "account-a-forgotten", "account-a-more"])
    #expect(model.continuationToken == nil)
    #expect(model.loadMoreMessage == "No hay más recomendaciones por ahora.")
    model.setFeaturedCollectionKind(.albums)
    #expect(model.loadMoreMessage == "No hay más recomendaciones por ahora.")
    #expect(model.featured.collections.map(\.id) == ["account-a-album", "account-a-recent-album", "account-a-library", "account-a-more-album"])
    model.setFeaturedCollectionKind(.playlists)

    await model.loadHomeFeed(core: core)
    #expect(model.featured.collectionKind == .playlists)
    #expect(model.featured.collections.map(\.id) == ["account-a-mix", "account-a-forgotten"])
    await model.loadHomeFeed(core: core, chipParams: "focus")
    #expect(model.selectedChipParams == "focus")
    #expect(model.featuredCollectionKind == .playlists)
    #expect(model.featured.collectionKind == .playlists)
    await model.loadHomeFeed(core: core)
    #expect(model.selectedChipParams == nil)
    #expect(model.featured.collectionKind == .playlists)
    let counts = await core.feed.counts()
    #expect(counts.pages == 4)
    #expect(counts.continuations == 1)
}

@Test @MainActor func homeCollectionChoiceSurvivesAccountChangeWithoutKeepingPrivateCards() async throws {
    let suite = "SideBHomeCollection.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = preferenceModel(preferences)
    model.setFeaturedCollectionKind(.playlists)
    await model.loadHomeFeed(core: CollectionCoreStub())
    #expect(!model.featured.collections.isEmpty)

    model.prepareSession(identity: "account-b")
    #expect(model.featuredCollectionKind == .playlists)
    #expect(model.featured.collectionKind == .playlists)
    #expect(model.featured.collections.isEmpty)
    #expect(model.featured.songs.isEmpty)
    #expect(model.sections.isEmpty)
    #expect(model.chips.isEmpty)
    #expect(model.continuationToken == nil)
    await model.loadHomeFeed(core: CollectionCoreStub(prefix: "account-b"))
    #expect(model.featured.collections.map(\.id) == ["account-b-mix", "account-b-forgotten"])
    #expect(!model.sections.flatMap(\.items).contains { $0.record.id.hasPrefix("account-a") })
}
