import Foundation
import Testing
import SideBCore
@testable import SideB

private actor RecommendationIntegrationCalls {
    private(set) var homePageCount = 0
    private(set) var continuationTokens: [String] = []

    func recordHomePage() { homePageCount += 1 }
    func recordContinuation(_ token: String) { continuationTokens.append(token) }
    func snapshot() -> (Int, [String]) { (homePageCount, continuationTokens) }
}

private final class HomeRecommendationIntegrationCore: SideBCore, @unchecked Sendable {
    private let initialPage: HomePageRecord
    private let continuationPages: [String: HomePageRecord]
    private let calls = RecommendationIntegrationCalls()

    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        initialPage = HomePageRecord(chips: [], sections: [], continuation: nil)
        continuationPages = [:]
        super.init(unsafeFromRawPointer: pointer)
    }

    init(page: HomePageRecord, continuations: [String: HomePageRecord] = [:]) {
        initialPage = page
        continuationPages = continuations
        super.init(noPointer: .init())
    }

    override func isLoggedIn() -> Bool { true }

    override func getHomePage(chipParams: String?) async throws -> HomePageRecord {
        await calls.recordHomePage()
        return initialPage
    }

    override func getHomeContinuation(token: String) async throws -> HomePageRecord {
        await calls.recordContinuation(token)
        return continuationPages[token] ?? HomePageRecord(chips: [], sections: [], continuation: nil)
    }

    func requestSnapshot() async -> (homePages: Int, continuationTokens: [String]) {
        let result = await calls.snapshot()
        return (result.0, result.1)
    }
}

private func integrationItem(_ kind: String, _ id: String, thumbnail: String? = nil) -> HomeItemRecord {
    HomeItemRecord(kind: kind, id: id, title: id, subtitle: nil, thumbnail: thumbnail,
        duration: nil, artists: nil, artistId: nil, album: nil, albumId: nil,
        artistRuns: [], explicit: false)
}

private func integrationSection(
    _ title: String,
    _ items: [HomeItemRecord],
    browseID: String? = nil
) -> HomeSectionRecord {
    HomeSectionRecord(title: title, format: .largeCards, items: items,
        moreBrowseId: browseID, moreParams: nil)
}

@MainActor private func recommendationIntegrationModel(_ preferences: UserDefaults) -> HomeViewModel {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sideb-home-recommendation-tests-\(UUID().uuidString)", isDirectory: true)
    return HomeViewModel(cacheStore: HomeFeedCacheStore(directory: directory), preferences: preferences)
}

private func integrationSong(_ id: String, albumID: String?, album: String?, thumbnail: String?) -> SongItemRecord {
    SongItemRecord(videoId: id, title: id, artists: "Artista", album: album, duration: nil,
        thumbnail: thumbnail, artistId: nil, albumId: albumID, setVideoId: nil,
        isVideo: false, isUpload: false, library: nil, artistRuns: [])
}

@Test @MainActor func homeRecommendationSettingsAreIsolatedPerAccountAndRestoreOnReturn() throws {
    let suite = "SideBHomeRecommendationAccounts.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }

    let model = recommendationIntegrationModel(preferences)
    model.prepareSession(identity: "account-a", purgePrevious: false)
    var accountA = HomeRecommendationSettings.default
    accountA.albumSources = [.init(source: .recentAlbums)]
    accountA.categoryOrderMode = .custom
    accountA.categoryOrder = ["listen-again", "custom:account a"]
    accountA.hiddenCategoryKeys = ["listen-again"]
    model.setRecommendationSettings(accountA)

    model.prepareSession(identity: "account-b", purgePrevious: false)
    #expect(model.recommendationSettings == HomeRecommendationSettings.default)
    var accountB = HomeRecommendationSettings.default
    accountB.albumSources = [.init(source: .libraryAlbums)]
    accountB.categoryOrderMode = .youtube
    accountB.categoryOrder = ["new-releases"]
    accountB.hiddenCategoryKeys = ["new-releases"]
    model.setRecommendationSettings(accountB)

    model.prepareSession(identity: "account-a", purgePrevious: false)
    #expect(model.recommendationSettings == accountA)
    #expect(model.recommendationSettings.sources(for: .albums).map(\.source) == [.recentAlbums])
    #expect(model.recommendationSettings.hiddenCategoryKeys == ["listen-again"])
    #expect(model.receivedCategories.isEmpty)
    #expect(model.featured.collections.isEmpty)

    model.prepareSession(identity: "account-b", purgePrevious: false)
    #expect(model.recommendationSettings == accountB)
    #expect(model.recommendationSettings.hiddenCategoryKeys == ["new-releases"])
}

@Test @MainActor func homeRecommendationCapacityExcludesOnlyTheExposedSixPages() async throws {
    let suite = "SideBHomeRecommendationCapacity.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let records = (0..<40).map { integrationItem("album", "capacity-\($0)") }
    let model = recommendationIntegrationModel(preferences)
    model.prepareSession(identity: "capacity-account", purgePrevious: false)
    let core = HomeRecommendationIntegrationCore(page: HomePageRecord(
        chips: [], sections: [integrationSection("Albums for you", records)], continuation: nil))
    await model.loadHomeFeed(core: core)

    for (capacity, expected) in [(2, 12), (4, 24), (6, 36)] {
        model.setFeaturedCapacity(capacity)
        #expect(model.featured.collections.count == expected)
        let exposedIDs = Set(model.featured.collections.map(\.id))
        let remainingIDs = model.featured.remainingSections.flatMap(\.items)
            .filter { $0.record.kind == "album" }.map(\.record.id)
        #expect(exposedIDs.count == expected)
        #expect(remainingIDs.count == 40 - expected)
        #expect(exposedIDs.isDisjoint(with: remainingIDs))
    }
}

@Test @MainActor func homeRecommendationCategoryOrderAndVisibilityDoNotChangeSourcePriority() async throws {
    let suite = "SideBHomeRecommendationCategories.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = recommendationIntegrationModel(preferences)
    model.prepareSession(identity: "category-account", purgePrevious: false)
    let page = HomePageRecord(chips: [], sections: [
        integrationSection("New releases", [integrationItem("album", "release"), integrationItem("artist", "release-shelf")]),
        integrationSection("Listen again", [integrationItem("album", "recent"), integrationItem("artist", "recent-shelf")]),
        integrationSection("Albums for you", [integrationItem("album", "recommended"), integrationItem("artist", "recommended-shelf")]),
        integrationSection("Jazz nuevo", [integrationItem("album", "other"), integrationItem("artist", "jazz-shelf")])
    ], continuation: nil)
    await model.loadHomeFeed(core: HomeRecommendationIntegrationCore(page: page))

    var settings = HomeRecommendationSettings.default
    settings.albumSources = [
        .init(source: .recommendedAlbums), .init(source: .listenAgain),
        .init(source: .newReleases), .init(source: .otherHome)
    ]
    settings.categoryOrderMode = .custom
    settings.categoryOrder = ["custom:jazz nuevo", "new-releases", "recommended-albums", "listen-again"]
    settings.hiddenCategoryKeys = ["listen-again"]
    model.setRecommendationSettings(settings)

    #expect(model.featured.collections.map(\.id) == ["recommended", "recent", "release", "other"])
    #expect(model.featured.remainingSections.map(\.title) == ["Jazz nuevo", "New releases", "Albums for you"])
    #expect(model.featured.remainingSections.flatMap(\.items).map(\.record).contains(integrationItem("artist", "recent-shelf")) == false)
    #expect(model.receivedCategories.map(\.id) == ["custom:jazz nuevo", "new-releases", "recommended-albums", "listen-again"])
}

@Test @MainActor func allFeaturedSourcesOffDoesNotFallBackToAnotherCollectionSource() async throws {
    let suite = "SideBHomeRecommendationDisabled.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = recommendationIntegrationModel(preferences)
    model.prepareSession(identity: "disabled-account", purgePrevious: false)
    let page = HomePageRecord(chips: [], sections: [
        integrationSection("Albums for you", [integrationItem("album", "recommended")]),
        integrationSection("Listen again", [integrationItem("album", "recent")]),
        integrationSection("Unclassified", [integrationItem("album", "other")])
    ], continuation: nil)
    await model.loadHomeFeed(core: HomeRecommendationIntegrationCore(page: page))

    var settings = HomeRecommendationSettings.default
    settings.setSources(settings.sources(for: .albums).map {
        HomeRecommendationSourceRule(source: $0.source, enabled: false)
    }, for: .albums)
    model.setRecommendationSettings(settings)
    #expect(model.allFeaturedSourcesDisabled)
    #expect(model.featured.collections.isEmpty)
    #expect(model.featured.remainingSections.flatMap(\.items).map(\.record).filter { $0.kind == "album" }.count == 3)
}

@Test @MainActor func recentAlbumSupplementalUsesAlbumArtworkAndDeduplicatesHistoryWithoutVideoThumbnails() async throws {
    let suite = "SideBHomeRecommendationHistory.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = recommendationIntegrationModel(preferences)
    model.prepareSession(identity: "history-account", purgePrevious: false)
    var settings = HomeRecommendationSettings.default
    settings.albumSources = [.init(source: .recentAlbums), .init(source: .libraryAlbums)]
    model.setRecommendationSettings(settings)
    model.updateSupplemental(
        albums: [
            BrowseCardRecord(kind: "album", id: "saved-album", title: "Portada real", subtitle: nil,
                thumbnail: "album-cover", duration: nil),
            BrowseCardRecord(kind: "album", id: "library-only", title: "Biblioteca", subtitle: nil,
                thumbnail: "library-cover", duration: nil)
        ],
        playlists: [],
        history: [HistoryGroupRecord(title: "Hoy", items: [
            integrationSong("song-1", albumID: "saved-album", album: "Portada real", thumbnail: "video-image"),
            integrationSong("song-2", albumID: "saved-album", album: "Duplicado", thumbnail: "other-video-image"),
            integrationSong("song-3", albumID: "missing-album", album: "Sin portada", thumbnail: "video-only")
        ])]
    )

    #expect(model.featured.collections.map(\.id) == ["saved-album", "missing-album", "library-only"])
    #expect(model.featured.collections.map(\.thumbnail) == ["album-cover", nil, "library-cover"])
    #expect(model.featured.collections.map(\.title) == ["Portada real", "Sin portada", "Biblioteca"])
    #expect(model.featured.collections.allSatisfy { $0.thumbnail != "video-image" && $0.thumbnail != "video-only" })
}

@Test @MainActor func loadMoreSkipsThreeHiddenPagesWithoutRevisionThenPublishesVisiblePage() async throws {
    let suite = "SideBHomeRecommendationHiddenPages.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = recommendationIntegrationModel(preferences)
    model.prepareSession(identity: "hidden-pages-account", purgePrevious: false)
    var settings = HomeRecommendationSettings.default
    settings.setSources(settings.sources(for: .albums).map {
        HomeRecommendationSourceRule(source: $0.source, enabled: false)
    }, for: .albums)
    settings.hiddenCategoryKeys = [
        "custom:hidden one", "custom:hidden two", "custom:hidden three", "custom:hidden four"
    ]
    model.setRecommendationSettings(settings)

    func hiddenPage(_ title: String, _ item: String, next: String?) -> HomePageRecord {
        HomePageRecord(chips: [], sections: [integrationSection(title, [integrationItem("artist", item)], browseID: item)], continuation: next)
    }
    let core = HomeRecommendationIntegrationCore(
        page: hiddenPage("Hidden one", "hidden-1", next: "c1"),
        continuations: [
            "c1": hiddenPage("Hidden two", "hidden-2", next: "c2"),
            "c2": hiddenPage("Hidden three", "hidden-3", next: "c3"),
            "c3": hiddenPage("Hidden four", "hidden-4", next: "c4"),
            "c4": hiddenPage("Visible after hidden", "visible-1", next: nil)
        ]
    )
    await model.loadHomeFeed(core: core)
    let revisionBefore = model.contentRevision

    await model.loadMoreContent(core: core)
    let afterHiddenBatch = await core.requestSnapshot()
    #expect(afterHiddenBatch.continuationTokens == ["c1", "c2", "c3"])
    #expect(model.continuationToken == "c4")
    #expect(model.contentRevision == revisionBefore)
    #expect(model.featured.remainingSections.isEmpty)

    await model.loadMoreContent(core: core)
    let afterVisiblePage = await core.requestSnapshot()
    #expect(afterVisiblePage.continuationTokens == ["c1", "c2", "c3", "c4"])
    #expect(model.contentRevision == revisionBefore + 1)
    #expect(model.featured.remainingSections.map(\.title) == ["Visible after hidden"])
}

@Test @MainActor func disabledSourcesDoNotStartPriorityPrefetch() async throws {
    let suite = "SideBHomeRecommendationNoPrefetch.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = recommendationIntegrationModel(preferences)
    model.prepareSession(identity: "no-prefetch-account", purgePrevious: false)
    var settings = HomeRecommendationSettings.default
    settings.setSources(settings.sources(for: .albums).map {
        HomeRecommendationSourceRule(source: $0.source, enabled: false)
    }, for: .albums)
    model.setRecommendationSettings(settings)
    let core = HomeRecommendationIntegrationCore(page: HomePageRecord(
        chips: [], sections: [integrationSection("Unclassified", [integrationItem("album", "generic")])],
        continuation: "should-not-prefetch"))

    await model.loadHomeFeed(core: core)
    let calls = await core.requestSnapshot()
    #expect(calls.homePages == 1)
    #expect(calls.continuationTokens.isEmpty)
    #expect(model.featured.collections.isEmpty)
    #expect(model.allFeaturedSourcesDisabled)
}
