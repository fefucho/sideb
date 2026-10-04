import Foundation
import Testing
import SideBCore
@testable import SideB

private func recommendationRecord(_ kind: String, _ id: String) -> HomeItemRecord {
    HomeItemRecord(kind: kind, id: id, title: id, subtitle: nil, thumbnail: nil,
        duration: nil, artists: nil, artistId: nil, album: nil, albumId: nil, artistRuns: [], explicit: false)
}

private func recommendationSections(_ records: [(String, [HomeItemRecord])]) -> [HomeSectionPresentation] {
    HomePresentationFactory.sections(from: records.map {
        HomeSectionRecord(title: $0.0, format: .largeCards, items: $0.1,
            moreBrowseId: "VL-more", moreParams: "params")
    }, chip: nil, preserveProviderOrder: true)
}

@Test func recommendationSettingsRoundTripWithVersionAndIndependentDefaults() throws {
    let defaults = HomeRecommendationSettings.default
    #expect(defaults.albumSources.map(\.source) == [
        .recommendedAlbums, .listenAgain, .forgottenFavorites, .fromLibrary,
        .newReleases, .otherHome, .libraryAlbums, .recentAlbums
    ])
    #expect(defaults.playlistSources.map(\.source) == [
        .mixesForYou, .listenAgain, .forgottenFavorites, .fromLibrary,
        .fromCommunity, .otherHome, .libraryPlaylists
    ])
    #expect(defaults.sources(for: .albums).first?.enabled == true)
    #expect(defaults.sources(for: .albums).first(where: { $0.source == .libraryAlbums })?.enabled == false)
    #expect(defaults.sources(for: .playlists).first(where: { $0.source == .libraryPlaylists })?.enabled == false)

    var settings = defaults
    settings.categoryOrderMode = .custom
    settings.categoryOrder = ["listen-again", "custom:lo nuevo"]
    settings.hiddenCategoryKeys = ["new-releases"]
    settings.setSources([
        .init(source: .libraryAlbums, enabled: true),
        .init(source: .recommendedAlbums, enabled: false)
    ], for: .albums)
    let encoded = try JSONEncoder().encode(settings)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["version"] as? Int == HomeRecommendationSettings.currentVersion)
    #expect(try JSONDecoder().decode(HomeRecommendationSettings.self, from: encoded) == settings)
}

@Test func recommendationCategoryKeysShareEnglishSpanishFamiliesAndGroupUnknownTitles() {
    #expect(HomeRecommendationSettings.categoryKey(forTitle: "  Vuelve a escucharlo  ") == "listen-again")
    #expect(HomeRecommendationSettings.categoryKey(forTitle: "Quick picks") == HomeRecommendationSettings.categoryKey(forTitle: "Selecciones rápidas"))
    #expect(HomeRecommendationSettings.categoryKey(forTitle: "Speed Dial") == HomeRecommendationSettings.categoryKey(forTitle: "Marcación rápida"))
    #expect(HomeRecommendationSettings.categoryKey(forTitle: "LISTEN AGAIN") == "listen-again")
    #expect(HomeRecommendationSettings.categoryKey(forTitle: "Álbumes para ti") == "recommended-albums")
    #expect(HomeRecommendationSettings.categoryKey(forTitle: "Albums for you") == "recommended-albums")
    #expect(HomeRecommendationSettings.categoryKey(forTitle: "  Música nueva  ") == "custom:musica nueva")
    #expect(HomePresentationFactory.categories(from: [
        HomeSectionRecord(title: "Jazz nuevo", format: .largeCards, items: [recommendationRecord("album", "a")], moreBrowseId: nil, moreParams: nil),
        HomeSectionRecord(title: " jazz nuevo ", format: .largeCards, items: [recommendationRecord("album", "b")], moreBrowseId: nil, moreParams: nil)
    ]).map(\.key) == ["custom:jazz nuevo"])
}

@Test func recommendationFeedModesOrderUnknownCategoriesAndKeepVisibilitySeparate() {
    let listen = HomeSectionRecord(title: "Listen again", format: .largeCards, items: [recommendationRecord("album", "a")], moreBrowseId: nil, moreParams: nil)
    let unknown = HomeSectionRecord(title: "Jazz nuevo", format: .largeCards, items: [recommendationRecord("album", "b")], moreBrowseId: nil, moreParams: nil)
    let releases = HomeSectionRecord(title: "New releases", format: .largeCards, items: [recommendationRecord("album", "c")], moreBrowseId: nil, moreParams: nil)
    let records = [releases, listen, unknown]

    var settings = HomeRecommendationSettings.default
    settings.categoryOrderMode = .youtube
    settings.hiddenCategoryKeys = ["listen-again"]
    #expect(settings.orderedFeedRecords(records).map(\.title) == records.map(\.title))
    #expect(settings.visibleFeedRecords(records).map(\.title) == ["New releases", "Jazz nuevo"])

    settings.categoryOrderMode = .custom
    settings.categoryOrder = ["custom:jazz nuevo", "listen-again"]
    #expect(settings.orderedFeedRecords(records).map(\.title) == ["Jazz nuevo", "Listen again", "New releases"])
    settings.categoryOrderMode = .sideB
    #expect(settings.orderedFeedRecords(records).map(\.title) == records.map(\.title))
}

@Test func featuredSourcesUseStrictOrderSupplementalCandidatesAndCanonicalDeduplication() {
    let sections = recommendationSections([
        ("Other albums", [recommendationRecord("album", "generic")]),
        ("New releases", [recommendationRecord("album", "release")]),
        ("Albums for you", [recommendationRecord("album", "VLsame"), recommendationRecord("album", "first")]),
        ("Listen again", [recommendationRecord("album", "same"), recommendationRecord("album", "recent")])
    ])
    var settings = HomeRecommendationSettings.default
    settings.albumSources = [
        .init(source: .recommendedAlbums),
        .init(source: .libraryAlbums),
        .init(source: .listenAgain),
        .init(source: .otherHome)
    ]
    let result = HomeFeaturedPresentation.make(
        from: sections,
        settings: settings,
        capacity: 2,
        supplemental: [.libraryAlbums: [recommendationRecord("album", "supplemental"), recommendationRecord("album", "first")]]
    )
    #expect(result.collections.map(\.id) == ["VLsame", "first", "supplemental", "same", "recent", "generic"])
    #expect(result.remainingSections.flatMap(\.items).map(\.record).contains(recommendationRecord("album", "same")) == false)
    #expect(result.remainingSections.flatMap(\.items).map(\.record).contains(recommendationRecord("album", "release")))
}

@Test func featuredOtherSourceCannotLeakKnownFamiliesAndDisabledSourcesStayOff() {
    let sections = recommendationSections([
        ("New releases", [recommendationRecord("album", "release")]),
        ("Albums for you", [recommendationRecord("album", "recommended")]),
        ("Unclassified", [recommendationRecord("album", "other")])
    ])
    var settings = HomeRecommendationSettings.default
    settings.albumSources = [.init(source: .otherHome)]
    let result = HomeFeaturedPresentation.make(from: sections, settings: settings, capacity: 2)
    #expect(result.collections.map(\.id) == ["other"])

    settings.albumSources = [.init(source: .libraryAlbums, enabled: false)]
    let disabled = HomeFeaturedPresentation.make(
        from: sections, settings: settings, capacity: 2,
        supplemental: [.libraryAlbums: [recommendationRecord("album", "external")]]
    )
    #expect(disabled.collections.isEmpty)
}

@Test func featuredPlaylistDedupeUsesCanonicalTransportIDs() {
    let sections = recommendationSections([
        ("Mixed for you", [recommendationRecord("playlist", "VLLM")]),
        ("Listen again", [recommendationRecord("playlist", "LM")])
    ])
    var settings = HomeRecommendationSettings.default
    settings.playlistSources = [.init(source: .mixesForYou), .init(source: .listenAgain)]
    let result = HomeFeaturedPresentation.make(from: sections, collectionKind: .playlists, settings: settings)
    #expect(result.collections.map(\.id) == ["VLLM"])
    #expect(!result.remainingSections.flatMap(\.items).contains(where: { $0.record.id == "LM" }))
}

@Test func hidingAFeedShelfDoesNotDisableItsFeaturedSource() {
    let hiddenRecommendation = recommendationRecord("album", "still-featured")
    let sections = recommendationSections([
        ("Listen again", [hiddenRecommendation, recommendationRecord("song", "song")]),
        ("Unclassified", [recommendationRecord("album", "other")])
    ])
    var settings = HomeRecommendationSettings.default
    settings.hiddenCategoryKeys = ["listen-again"]
    let result = HomeFeaturedPresentation.make(from: sections, settings: settings, capacity: 2)
    #expect(result.collections.first == hiddenRecommendation)
    #expect(!result.remainingSections.contains(where: { $0.title == "Listen again" }))
    #expect(result.songs == [recommendationRecord("song", "song")])
}

@Test func featuredCollectionCapacityProjectsAtMostSixPagesWithoutFabricatingCandidates() {
    let candidates = (0..<40).map { recommendationRecord("album", "album-\($0)") }
    let sections = recommendationSections([("Albums for you", candidates)])
    #expect(HomeFeaturedPresentation.make(from: sections, capacity: 2).collections.count == 12)
    #expect(HomeFeaturedPresentation.make(from: sections, capacity: 4).collections.count == 24)
    #expect(HomeFeaturedPresentation.make(from: sections, capacity: 6).collections.count == 36)
    #expect(HomeFeaturedPresentation.make(from: recommendationSections([("Albums for you", Array(candidates.prefix(3)))]), capacity: 6).collections.count == 3)
}
