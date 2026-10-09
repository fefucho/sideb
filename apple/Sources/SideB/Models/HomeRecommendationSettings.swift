import Foundation
import SideBCore

/// A recommendation source that can be ordered and enabled independently for
/// album and playlist shelves.
enum HomeRecommendationSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case recommendedAlbums
    case mixesForYou
    case listenAgain
    case newReleases
    case forgottenFavorites
    case fromLibrary
    case fromCommunity
    case otherHome
    case libraryAlbums
    case recentAlbums
    case libraryPlaylists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommendedAlbums: L10n.text("settings.source.recommendedAlbums")
        case .mixesForYou: L10n.text("settings.source.mixesForYou")
        case .listenAgain: L10n.text("settings.source.listenAgain")
        case .newReleases: L10n.text("settings.source.newReleases")
        case .forgottenFavorites: L10n.text("settings.source.forgottenFavorites")
        case .fromLibrary: L10n.text("settings.source.fromLibrary")
        case .fromCommunity: L10n.text("settings.source.fromCommunity")
        case .otherHome: L10n.text("settings.source.otherHome")
        case .libraryAlbums: L10n.text("settings.source.libraryAlbums")
        case .recentAlbums: L10n.text("settings.source.recentAlbums")
        case .libraryPlaylists: L10n.text("settings.source.libraryPlaylists")
        }
    }

    var isSupplemental: Bool {
        switch self {
        case .libraryAlbums, .recentAlbums, .libraryPlaylists: true
        default: false
        }
    }
}

struct HomeRecommendationSourceRule: Codable, Equatable, Identifiable, Sendable {
    var source: HomeRecommendationSource
    var enabled: Bool

    var id: String { source.id }

    init(source: HomeRecommendationSource, enabled: Bool = true) {
        self.source = source
        self.enabled = enabled
    }
}

enum HomeCategoryOrderMode: String, Codable, CaseIterable, Sendable {
    case sideB
    case youtube
    case custom
}

/// Versioned, local configuration for featured sources and Home feed shelves.
/// Dynamic category keys use stable family IDs or normalized titles, never row IDs.
struct HomeRecommendationSettings: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let `default` = HomeRecommendationSettings()

    var albumSources: [HomeRecommendationSourceRule]
    var playlistSources: [HomeRecommendationSourceRule]
    var categoryOrderMode: HomeCategoryOrderMode
    var categoryOrder: [String]
    var hiddenCategoryKeys: [String]

    var version: Int { Self.currentVersion }

    init(
        albumSources: [HomeRecommendationSourceRule] = Self.defaultAlbumSources,
        playlistSources: [HomeRecommendationSourceRule] = Self.defaultPlaylistSources,
        categoryOrderMode: HomeCategoryOrderMode = .sideB,
        categoryOrder: [String] = [],
        hiddenCategoryKeys: [String] = []
    ) {
        self.albumSources = Self.uniqueRules(albumSources, allowed: Self.albumSourceSet)
        self.playlistSources = Self.uniqueRules(playlistSources, allowed: Self.playlistSourceSet)
        self.categoryOrderMode = categoryOrderMode
        self.categoryOrder = Self.uniqueKeys(categoryOrder)
        self.hiddenCategoryKeys = Self.uniqueKeys(hiddenCategoryKeys)
    }

    func sources(for kind: HomeFeaturedCollectionKind) -> [HomeRecommendationSourceRule] {
        kind == .albums ? albumSources : playlistSources
    }

    mutating func setSources(_ sources: [HomeRecommendationSourceRule], for kind: HomeFeaturedCollectionKind) {
        if kind == .albums {
            albumSources = Self.uniqueRules(sources, allowed: Self.albumSourceSet)
        } else {
            playlistSources = Self.uniqueRules(sources, allowed: Self.playlistSourceSet)
        }
    }

    func isCategoryVisible(key: String) -> Bool {
        !hiddenCategoryKeys.contains(key)
    }

    func orderedFeedRecords(_ records: [HomeSectionRecord]) -> [HomeSectionRecord] {
        guard categoryOrderMode == .custom, !records.isEmpty else { return records }
        let configured = Dictionary(categoryOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        return records.enumerated().sorted { lhs, rhs in
            let lhsKey = Self.categoryKey(forTitle: lhs.element.title)
            let rhsKey = Self.categoryKey(forTitle: rhs.element.title)
            let lhsRank = configured[lhsKey] ?? Int.max
            let rhsRank = configured[rhsKey] ?? Int.max
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }.map(\.element)
    }

    func visibleFeedRecords(_ records: [HomeSectionRecord]) -> [HomeSectionRecord] {
        guard !hiddenCategoryKeys.isEmpty else { return records }
        let hidden = Set(hiddenCategoryKeys)
        return records.filter { !hidden.contains(Self.categoryKey(forTitle: $0.title)) }
    }

    static func categoryKey(forTitle title: String) -> String {
        let normalized = normalize(title)
        if aliases[normalized] != nil { return aliases[normalized]! }
        return "custom:\(normalized)"
    }

    static func source(forTitle title: String) -> HomeRecommendationSource {
        switch categoryKey(forTitle: title) {
        case "recommended-albums": .recommendedAlbums
        case "mixes-for-you": .mixesForYou
        case "listen-again": .listenAgain
        case "new-releases": .newReleases
        case "forgotten-favorites": .forgottenFavorites
        case "from-library": .fromLibrary
        case "from-community": .fromCommunity
        default: .otherHome
        }
    }

    static func canonicalCollectionID(_ id: String, kind: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == "playlist" else { return trimmed }
        if trimmed == "LM" || trimmed == "VLLM" { return "LM" }
        return trimmed.hasPrefix("VL") ? String(trimmed.dropFirst(2)) : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case albumSources
        case playlistSources
        case categoryOrderMode
        case categoryOrder
        case hiddenCategoryKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        guard version <= Self.currentVersion else {
            self = Self()
            return
        }
        self.init(
            albumSources: try container.decodeIfPresent([HomeRecommendationSourceRule].self, forKey: .albumSources) ?? Self.defaultAlbumSources,
            playlistSources: try container.decodeIfPresent([HomeRecommendationSourceRule].self, forKey: .playlistSources) ?? Self.defaultPlaylistSources,
            categoryOrderMode: try container.decodeIfPresent(HomeCategoryOrderMode.self, forKey: .categoryOrderMode) ?? .sideB,
            categoryOrder: try container.decodeIfPresent([String].self, forKey: .categoryOrder) ?? [],
            hiddenCategoryKeys: try container.decodeIfPresent([String].self, forKey: .hiddenCategoryKeys) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(albumSources, forKey: .albumSources)
        try container.encode(playlistSources, forKey: .playlistSources)
        try container.encode(categoryOrderMode, forKey: .categoryOrderMode)
        try container.encode(categoryOrder, forKey: .categoryOrder)
        try container.encode(hiddenCategoryKeys, forKey: .hiddenCategoryKeys)
    }

    private static let defaultAlbumSources: [HomeRecommendationSourceRule] = [
        .init(source: .recommendedAlbums),
        .init(source: .listenAgain),
        .init(source: .forgottenFavorites),
        .init(source: .fromLibrary),
        .init(source: .newReleases),
        .init(source: .otherHome),
        .init(source: .libraryAlbums, enabled: false),
        .init(source: .recentAlbums, enabled: false)
    ]

    private static let defaultPlaylistSources: [HomeRecommendationSourceRule] = [
        .init(source: .mixesForYou),
        .init(source: .listenAgain),
        .init(source: .forgottenFavorites),
        .init(source: .fromLibrary),
        .init(source: .fromCommunity),
        .init(source: .otherHome),
        .init(source: .libraryPlaylists, enabled: false)
    ]

    private static let albumSourceSet: Set<HomeRecommendationSource> = Set([
        .recommendedAlbums, .listenAgain, .newReleases, .forgottenFavorites, .fromLibrary,
        .otherHome, .libraryAlbums, .recentAlbums
    ])
    private static let playlistSourceSet: Set<HomeRecommendationSource> = Set([
        .mixesForYou, .listenAgain, .forgottenFavorites, .fromLibrary, .fromCommunity,
        .otherHome, .libraryPlaylists
    ])

    private static func uniqueRules(
        _ rules: [HomeRecommendationSourceRule], allowed: Set<HomeRecommendationSource>
    ) -> [HomeRecommendationSourceRule] {
        var seen = Set<HomeRecommendationSource>()
        return rules.filter { allowed.contains($0.source) && seen.insert($0.source).inserted }
    }

    private static func uniqueKeys(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let aliases: [String: String] = {
        let groups: [String: [String]] = [
            "quick-picks": ["quick picks", "selecciones rapidas", "selecciones rápidas"],
            "speed-dial": ["speed dial", "marcacion rapida", "marcación rápida"],
            "recommended-albums": ["albums for you", "albumes para ti", "álbumes para ti", "recommended albums", "albumes recomendados", "álbumes recomendados"],
            "mixes-for-you": ["mixed for you", "mixes for you", "your mixes", "personalized mixes", "mixes para ti", "tus mixes", "mixes personalizados", "hecho para ti"],
            "listen-again": ["listen again", "vuelve a escucharlo", "volver a escuchar", "escuchar de nuevo"],
            "new-releases": ["new releases", "nuevos lanzamientos", "lanzamientos nuevos"],
            "forgotten-favorites": ["forgotten favorites", "forgotten favourites", "favoritos olvidados"],
            "from-library": ["from your library", "de tu biblioteca", "de la biblioteca"],
            "from-community": ["from the community", "de la comunidad", "de la comunidad de youtube music"]
        ]
        return groups.reduce(into: [:]) { result, group in
            for alias in group.value { result[normalize(alias)] = group.key }
        }
    }()
}
