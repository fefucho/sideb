import Foundation
import SideBCore

/// A bounded projection of the provider's feed, computed only when that feed changes.
struct HomeFeaturedPresentation: Equatable {
    let songs: [HomeItemRecord]
    let collections: [HomeItemRecord]
    let collectionKind: HomeFeaturedCollectionKind
    let remainingSections: [HomeSectionPresentation]
    var collectionSources: [String: HomeRecommendationSource] = [:]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.songs == rhs.songs && lhs.collections == rhs.collections
            && lhs.collectionKind == rhs.collectionKind && lhs.remainingSections == rhs.remainingSections
    }

    static let empty = HomeFeaturedPresentation(songs: [], collections: [], collectionKind: .albums, remainingSections: [])

    var ambientThumbnails: [String] {
        func uniqueThumbnails(in records: [HomeItemRecord]) -> [String] {
            var seen = Set<String>()
            return records.compactMap(\.thumbnail)
                .filter { !$0.isEmpty && seen.insert($0).inserted }
        }

        let collectionCandidates = Array(uniqueThumbnails(in: collections).prefix(2))
        let songCandidates = Array(uniqueThumbnails(in: songs).prefix(2))
        var seen = Set<String>()
        return (collectionCandidates + songCandidates + uniqueThumbnails(in: collections + songs))
            .filter { seen.insert($0).inserted }
            .prefix(4)
            .map { $0 }
    }

    static func make(
        from sections: [HomeSectionPresentation],
        collectionKind: HomeFeaturedCollectionKind = .albums,
        settings: HomeRecommendationSettings = .default,
        capacity: Int = 2,
        supplemental: [HomeRecommendationSource: [HomeItemRecord]] = [:],
        shelfSections: [HomeSectionPresentation]? = nil
    ) -> Self {
        let songs = select(kind: "song", limit: 27, from: sections)
        let pageCapacity = [2, 4, 6].contains(capacity) ? capacity : 2
        let selection = selectCollections(
            from: sections,
            collectionKind: collectionKind,
            settings: settings,
            limit: pageCapacity * 6,
            supplemental: supplemental
        )
        let collections = selection.records
        let featured = Set((songs + collections).map {
            "\($0.kind)|\(HomeRecommendationSettings.canonicalCollectionID($0.id, kind: $0.kind))"
        })
        let sectionSource = orderedShelfSections(shelfSections ?? sections, settings: settings)
        let hidden = Set(settings.hiddenCategoryKeys)
        let remainder = sectionSource.compactMap { section -> HomeSectionPresentation? in
            guard !hidden.contains(HomeRecommendationSettings.categoryKey(forTitle: section.title)) else { return nil }
            let items = section.items.filter {
                !featured.contains("\($0.record.kind)|\(HomeRecommendationSettings.canonicalCollectionID($0.record.id, kind: $0.record.kind))")
            }
            guard !items.isEmpty else { return nil }
            return HomeSectionPresentation(id: section.id, title: section.title, style: section.style,
                items: items, moreBrowseId: section.moreBrowseId, moreParams: section.moreParams)
        }
        return Self(songs: songs, collections: collections, collectionKind: collectionKind, remainingSections: remainder, collectionSources: selection.sources)
    }

    private static func selectCollections(
        from sections: [HomeSectionPresentation],
        collectionKind: HomeFeaturedCollectionKind,
        settings: HomeRecommendationSettings,
        limit: Int,
        supplemental: [HomeRecommendationSource: [HomeItemRecord]]
    ) -> (records: [HomeItemRecord], sources: [String: HomeRecommendationSource]) {
        let wantedKind = collectionKind.recordKind
        let rules = settings.sources(for: collectionKind)
        var seen = Set<String>()
        var selected: [HomeItemRecord] = []
        var sources: [String: HomeRecommendationSource] = [:]

        func append(_ candidates: [HomeItemRecord], source: HomeRecommendationSource) -> Bool {
            for record in candidates where record.kind == wantedKind {
                let canonicalID = HomeRecommendationSettings.canonicalCollectionID(record.id, kind: record.kind)
                guard !canonicalID.isEmpty, seen.insert(canonicalID).inserted else { continue }
                selected.append(record)
                sources["\(wantedKind)|\(canonicalID)"] = source
                if selected.count == limit { return true }
            }
            return false
        }

        for rule in rules where rule.enabled {
            if rule.source.isSupplemental {
                if append(supplemental[rule.source] ?? [], source: rule.source) { break }
                continue
            }
            let candidates = sections.lazy
                .filter { HomeRecommendationSettings.source(forTitle: $0.title) == rule.source }
                .flatMap(\.items)
                .map(\.record)
            if append(Array(candidates), source: rule.source) { break }
        }
        return (selected, sources)
    }

    private static func orderedShelfSections(
        _ sections: [HomeSectionPresentation], settings: HomeRecommendationSettings
    ) -> [HomeSectionPresentation] {
        guard settings.categoryOrderMode == .custom else { return sections }
        let ranks = Dictionary(settings.categoryOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        return sections.enumerated().sorted { lhs, rhs in
            let lhsRank = ranks[HomeRecommendationSettings.categoryKey(forTitle: lhs.element.title)] ?? Int.max
            let rhsRank = ranks[HomeRecommendationSettings.categoryKey(forTitle: rhs.element.title)] ?? Int.max
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }.map(\.element)
    }

    private static func select(kind: String, limit: Int, from sections: [HomeSectionPresentation]) -> [HomeItemRecord] {
        let ranked = sections.enumerated().sorted {
            let lhs = priority($0.element.title, kind: kind)
            let rhs = priority($1.element.title, kind: kind)
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }
        var seen = Set<String>()
        var selected: [HomeItemRecord] = []
        for entry in ranked {
            for item in entry.element.items {
                let record = item.record
                guard record.kind == kind, !record.id.isEmpty,
                      seen.insert(record.id).inserted else { continue }
                selected.append(record)
                if selected.count == limit { return selected }
            }
        }
        return selected
    }

    private static func priority(_ title: String, kind: String) -> Int {
        if kind != "song" { return 10 }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        if kind == "song", ["speed dial", "marcacion rapida", "quick picks", "selecciones rapidas"].contains(normalized) { return 0 }
        if kind == "album", ["albums for you", "albumes para ti", "recommended albums", "albumes recomendados"].contains(normalized) { return 0 }
        if kind == "playlist", ["mixed for you", "mixes for you", "your mixes", "personalized mixes",
                                "mixes para ti", "tus mixes", "mixes personalizados", "hecho para ti"].contains(normalized) { return 0 }
        if ["listen again", "vuelve a escucharlo", "volver a escuchar", "escuchar de nuevo"].contains(normalized) { return 1 }
        if ["forgotten favorites", "forgotten favourites", "favoritos olvidados"].contains(normalized) { return 2 }
        if ["from your library", "de tu biblioteca", "de la biblioteca"].contains(normalized) { return 3 }
        return 4
    }
}
