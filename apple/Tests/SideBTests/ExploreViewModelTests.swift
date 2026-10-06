import Foundation
import Testing
import SideBCore
@testable import SideB

private enum ExploreTestError: Error { case offline }

private actor ExploreGate {
    private var country: String?
    private var requests: [(ExploreSource, CheckedContinuation<[BrowseCardRecord], Error>)] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func request(_ source: ExploreSource) async throws -> [BrowseCardRecord] {
        try await withCheckedThrowingContinuation { continuation in
            requests.append((source, continuation))
            let ready = waiters.filter { requests.count >= $0.0 }
            waiters.removeAll { requests.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }
    func wait(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func succeed(_ index: Int, _ cards: [BrowseCardRecord]) { requests[index].1.resume(returning: cards) }
    func fail(_ index: Int) { requests[index].1.resume(throwing: ExploreTestError.offline) }
    func count() -> Int { requests.count }
    func source(_ index: Int) -> ExploreSource { requests[index].0 }
    func setCountry(_ code: String?) { country = code }
    func detectedCountry() -> String? { country }
}

private final class ExploreCoreStub: SideBCore, @unchecked Sendable {
    let gate = ExploreGate()
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func getBrowseGrid(browseId: String, params: String?) async throws -> [BrowseCardRecord] {
        try await gate.request(.browse(browseId))
    }
    override func searchCards(query: String, category: String) async throws -> [BrowseCardRecord] {
        #expect(category == "playlists")
        return try await gate.request(.playlists(query))
    }
    override func detectMusicCountry() async throws -> String? { await gate.detectedCountry() }
    override func getCharts(countryCode: String) async throws -> ChartsPageRecord {
        let items = try await gate.request(.charts(countryCode))
        return .init(selectedCountry: countryCode,
            countries: ["ZZ", "UY", "AR", "US"].map { .init(code: $0, title: $0) }, items: items)
    }
}

private func exploreCard(_ id: String, kind: String = "playlist") -> BrowseCardRecord {
    .init(kind: kind, id: id, title: "Music \(id)", subtitle: nil, thumbnail: nil, duration: nil)
}

@Test @MainActor func exploreRejectsLateRouteAndKeepsNewestLoadingState() async {
    let core = ExploreCoreStub(), model = ExploreViewModel()
    model.prepareSession(1)
    let old = Task { await model.load(route: .releases, core: core) }
    await core.gate.wait(1)
    let current = Task { await model.load(route: .category("rock"), core: core) }
    await core.gate.wait(2)
    await core.gate.succeed(0, [exploreCard("old")])
    await old.value
    #expect(model.cards.isEmpty)
    #expect(model.isLoading)
    await core.gate.succeed(1, [exploreCard("rock")])
    await current.value
    #expect(model.cards.map(\.id) == ["rock"])
    #expect(!model.isLoading)
    #expect(await core.gate.source(1) == .playlists("rock"))
}

@Test @MainActor func exploreClearsAccountDataAndRejectsPreviousSession() async {
    let core = ExploreCoreStub(), model = ExploreViewModel()
    model.prepareSession(1)
    let old = Task { await model.load(route: .releases, core: core) }
    await core.gate.wait(1)
    model.prepareSession(2)
    await core.gate.succeed(0, [exploreCard("private-old")])
    await old.value
    #expect(model.cards.isEmpty)
    #expect(!model.isLoading)
    let fresh = Task { await model.load(route: .releases, core: core) }
    await core.gate.wait(2)
    await core.gate.succeed(1, [exploreCard("new")])
    await fresh.value
    model.prepareSession(3)
    #expect(model.cards.isEmpty)
    #expect(model.errorMessage == nil)
}

@Test @MainActor func exploreCachedReleasesReuseAndFailedRefreshRetainsMusic() async {
    let core = ExploreCoreStub(), model = ExploreViewModel()
    let first = Task { await model.load(route: .discover, core: core) }
    await core.gate.wait(1)
    await core.gate.succeed(0, [exploreCard("release", kind: "album")])
    await first.value
    await model.load(route: .genres, core: core)
    await model.load(route: .releases, core: core)
    #expect(await core.gate.count() == 1)
    #expect(model.cards.map(\.id) == ["release"])
    let refresh = Task { await model.load(route: .releases, core: core, force: true) }
    await core.gate.wait(2)
    #expect(model.cards.count == 1)
    await core.gate.fail(1)
    await refresh.value
    #expect(model.cards.map(\.id) == ["release"])
    #expect(model.errorMessage != nil)
    #expect(!model.isLoading)
}

@Test @MainActor func exploreCancelledRequestsCanReloadAndCardsHaveStableIdentity() async {
    let core = ExploreCoreStub(), model = ExploreViewModel()
    let cancelled = Task { await model.load(route: .charts, core: core) }
    await core.gate.wait(1)
    cancelled.cancel()
    await core.gate.succeed(0, [exploreCard("cancelled")])
    await cancelled.value
    #expect(model.cards.isEmpty)
    #expect(!model.isLoading)
    let retry = Task { await model.load(route: .charts, core: core) }
    await core.gate.wait(2)
    await core.gate.succeed(1, [exploreCard("same"), exploreCard("same"), exploreCard("same", kind: "album"), exploreCard("", kind: "album"), exploreCard("bad", kind: "unknown")])
    await retry.value
    #expect(model.chartSections.first?.cards.map(\.exploreIdentity) == ["playlist:same", "album:same"])
}

@Test @MainActor func exploreCacheEvictsOldCategoriesAndRemainsBounded() async {
    let core = ExploreCoreStub(), model = ExploreViewModel()
    for (index, category) in ExploreCategory.genres.prefix(9).enumerated() {
        let load = Task { await model.load(route: .category(category.id), core: core) }
        await core.gate.wait(index + 1)
        await core.gate.succeed(index, [exploreCard(category.id)])
        await load.value
    }
    await model.load(route: .category("rock"), core: core)
    #expect(await core.gate.count() == 9)
    let evicted = Task { await model.load(route: .category("pop"), core: core) }
    await core.gate.wait(10)
    await core.gate.succeed(9, [exploreCard("pop-new")])
    await evicted.value
    #expect(model.cards.map(\.id) == ["pop-new"])
}

@Test func explorePublicProviderContractsWhenLiveTestingEnabled() async throws {
    guard ProcessInfo.processInfo.environment["SIDEB_LIVE_EXPLORE"] == "1" else { return }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SideBExplore-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let core = try SideBCore(dataDir: directory.path)
    let releases = try await core.getBrowseGrid(browseId: "FEmusic_new_releases_albums", params: nil)
    #expect(!releases.isEmpty)
    #expect(releases.contains { $0.kind == "album" })
    let country = try await core.detectMusicCountry()
    #expect(country == nil || country?.count == 2)
    let global = try await core.getCharts(countryCode: "ZZ")
    let local = try await core.getCharts(countryCode: "UY")
    #expect(global.selectedCountry == "ZZ")
    #expect(local.selectedCountry == "UY")
    #expect(!global.items.isEmpty && !local.items.isEmpty)
    #expect(Set(global.items.map(\.id)) != Set(local.items.map(\.id)))
    #expect(global.countries.contains { $0.code == "UY" })
    #expect(global.countries.contains { $0.code == "AR" })
    let playlists = try await core.searchCards(query: "música para concentrarse", category: "playlists")
    #expect(!playlists.isEmpty)
    #expect(playlists.allSatisfy { $0.kind == "playlist" })
    print("Explore live: \(releases.count) releases, country \(country ?? "unavailable"), \(global.items.count) global / \(local.items.count) UY charts, \(global.countries.count) regions, \(playlists.count) focus playlists")
}

@Test @MainActor func exploreChartsShowsGlobalAndDetectedCountryAndKeepsGlobalOnLocalFailure() async {
    let core = ExploreCoreStub(), model = ExploreViewModel()
    await core.gate.setCountry("UY")
    let load = Task { await model.load(route: .charts, core: core) }
    await core.gate.wait(1)
    #expect(await core.gate.source(0) == .charts("ZZ"))
    await core.gate.succeed(0, [exploreCard("global")])
    await core.gate.wait(2)
    #expect(await core.gate.source(1) == .charts("UY"))
    #expect(model.chartSections.first?.code == "ZZ")
    await core.gate.fail(1)
    await load.value
    #expect(model.chartSections.first?.cards.map(\.id) == ["global"])
    #expect(model.errorMessage != nil)
    #expect(model.detectedCountry == "UY")
    #expect(model.chartCountries.contains { $0.code == "AR" })
}

@Test @MainActor func exploreCountrySwitchDoesNotAcceptLateResultsAndCacheSeparatesRegions() async {
    let core = ExploreCoreStub(), model = ExploreViewModel()
    let old = Task { await model.load(route: .chartCountry("UY"), core: core) }
    await core.gate.wait(1)
    let new = Task { await model.load(route: .chartCountry("AR"), core: core) }
    await core.gate.wait(2)
    await core.gate.succeed(1, [exploreCard("argentina")])
    await new.value
    await core.gate.succeed(0, [exploreCard("uruguay-old")])
    await old.value
    #expect(model.chartSections.first?.code == "AR")
    #expect(model.chartSections.first?.cards.map(\.id) == ["argentina"])
    let uruguay = Task { await model.load(route: .chartCountry("UY"), core: core) }
    await core.gate.wait(3)
    await core.gate.succeed(2, [exploreCard("uruguay")])
    await uruguay.value
    await model.load(route: .chartCountry("AR"), core: core)
    #expect(await core.gate.count() == 3)
    #expect(model.chartSections.first?.cards.map(\.id) == ["argentina"])
}

@Test @MainActor func exploreRefreshRedetectsCountryWhenNetworkChanges() async {
    let core = ExploreCoreStub(), model = ExploreViewModel()
    await core.gate.setCountry("UY")
    let first = Task { await model.load(route: .charts, core: core) }
    await core.gate.wait(1)
    await core.gate.succeed(0, [exploreCard("global")])
    await core.gate.wait(2)
    await core.gate.succeed(1, [exploreCard("uy")])
    await first.value
    #expect(model.chartSections.map(\.code) == ["ZZ", "UY"])
    await core.gate.setCountry("AR")
    let refresh = Task { await model.load(route: .charts, core: core, force: true) }
    await core.gate.wait(3)
    await core.gate.succeed(2, [exploreCard("global-fresh")])
    await core.gate.wait(4)
    #expect(await core.gate.source(3) == .charts("AR"))
    await core.gate.succeed(3, [exploreCard("ar")])
    await refresh.value
    #expect(model.chartSections.map(\.code) == ["ZZ", "AR"])
    #expect(model.detectedCountry == "AR")
}
