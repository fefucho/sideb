import Foundation
import SideBCore

/// What a provider category chip returns. The chip title identifies the type; the chip's `params`
/// request that type alone (the same request "Show all" already uses).
enum ProviderSearchChipKind: String, CaseIterable, Hashable {
    case songs, videos, albums, artists, communityPlaylists, episodes, profiles, featuredPlaylists, podcasts

    init?(chipTitle: String) {
        switch chipTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "songs": self = .songs
        case "videos": self = .videos
        case "albums": self = .albums
        case "artists": self = .artists
        case "community playlists": self = .communityPlaylists
        case "episodes": self = .episodes
        case "profiles": self = .profiles
        case "featured playlists": self = .featuredPlaylists
        case "podcasts": self = .podcasts
        default: return nil
        }
    }

    var category: ProviderSearchCategory {
        switch self {
        case .songs: return .songs
        case .videos: return .videos
        case .albums: return .albums
        case .artists: return .artists
        case .communityPlaylists, .featuredPlaylists: return .playlists
        case .episodes: return .episodes
        case .profiles: return .profiles
        case .podcasts: return .podcasts
        }
    }
}

/// A section of the Apple-Music-style results page.
enum ProviderSearchCategory: String, CaseIterable, Hashable {
    case songs, artists, albums, playlists, videos, profiles, podcasts, episodes

    var titleKey: String {
        switch self {
        case .songs: return "search.filter.songs"
        case .artists: return "search.filter.artists"
        case .albums: return "search.filter.albums"
        case .playlists: return "search.filter.playlists"
        case .videos: return "search.filter.videos"
        case .profiles: return "search.category.profiles"
        case .podcasts: return "search.category.podcasts"
        case .episodes: return "search.category.episodes"
        }
    }

    /// Songs and videos are rows (a grid of compact rows); everything else is a carousel of cards.
    var usesGrid: Bool { self == .songs || self == .videos }

    /// The type is not always in `kind`: profiles arrive as `artist` and podcasts as `playlist`
    /// (their subtitle starts with the provider's type word) and a video can arrive as a `song`
    /// whose payload says `isVideo`.
    static func of(_ card: BrowseCardRecord, song: SongItemRecord? = nil) -> ProviderSearchCategory? {
        let subtitle = (card.subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch card.kind {
        case "song": return song?.isVideo == true ? .videos : .songs
        case "video": return .videos
        case "album": return .albums
        case "artist": return subtitle.hasPrefix("profile") ? .profiles : .artists
        case "playlist":
            if subtitle.hasPrefix("podcast") { return .podcasts }
            return .playlists
        case "episode": return .episodes
        default: return nil
        }
    }

    /// Titles of provider shelves that already carry one category.
    init?(shelfTitle: String) {
        switch shelfTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "songs": self = .songs
        case "videos": self = .videos
        case "albums": self = .albums
        case "artists": self = .artists
        case "featured playlists", "community playlists", "playlists": self = .playlists
        case "profiles": self = .profiles
        case "podcasts": self = .podcasts
        case "episodes": self = .episodes
        default: return nil
        }
    }
}

/// Everything the projection needs besides the provider page itself.
struct ProviderSearchCategoryInput: Equatable {
    var chipPages: [ProviderSearchChipKind: SearchPageRecord] = [:]
    var pending: Set<ProviderSearchChipKind> = []
}

/// Fixed geometry: every category entry has a height known before it is drawn, so the native table
/// never has to measure (and mis-measure) them.
enum ProviderSearchCategoryLayout {
    static let gridRows = 3
    static let gridRowHeight: CGFloat = 58
    static let gridBottomGap: CGFloat = 8
    static var gridHeight: CGFloat { CGFloat(gridRows) * gridRowHeight + gridBottomGap }
    static let carouselHeight: CGFloat = 252
    static let loadingHeight: CGFloat = 72
    static let maxItems = 20

    /// Columns follow the available width, never the pixel: the grid always has `gridRows` rows.
    static func columns(for width: CGFloat) -> Int {
        if width >= 880 { return 3 }
        if width >= 560 { return 2 }
        return 1
    }
}

enum ProviderSearchCategoryProjection {
    /// Categories fetched for every search, in addition to those the mixed list already contains.
    private static let coreKinds: [ProviderSearchChipKind] = [.songs, .artists, .albums, .featuredPlaylists, .communityPlaylists]

    static func chipParams(in page: SearchPageRecord) -> [ProviderSearchChipKind: String] {
        var result: [ProviderSearchChipKind: String] = [:]
        for chip in page.chips {
            guard let kind = ProviderSearchChipKind(chipTitle: chip.title), let params = chip.params,
                  result[kind] == nil else { continue }
            result[kind] = params
        }
        return result
    }

    /// Chip requests to run, in the provider's chip order.
    static func fetchTargets(page: SearchPageRecord, showVideos: Bool) -> [(kind: ProviderSearchChipKind, params: String)] {
        let params = chipParams(in: page)
        let present = Set(mixedBuckets(in: page).keys)
        var wanted = Set(coreKinds)
        if showVideos { wanted.insert(.videos) }
        for kind in ProviderSearchChipKind.allCases where present.contains(kind.category) { wanted.insert(kind) }
        if !showVideos { wanted.remove(.videos) }
        var seen = Set<ProviderSearchChipKind>()
        var result: [(ProviderSearchChipKind, String)] = []
        for chip in page.chips {
            guard let kind = ProviderSearchChipKind(chipTitle: chip.title), wanted.contains(kind),
                  seen.insert(kind).inserted, let value = params[kind] else { continue }
            result.append((kind, value))
        }
        return result
    }

    private struct Entry { let card: BrowseCardRecord; let song: SongItemRecord? }

    /// Items of the provider's own page grouped by type, keeping their order. Titled shelves that are
    /// not a known category ("Listen again", personalized strips) are not search results and are skipped.
    private static func mixedBuckets(in page: SearchPageRecord) -> [ProviderSearchCategory: [Entry]] {
        var result: [ProviderSearchCategory: [Entry]] = [:]
        for section in page.sections where section.layout != "top" {
            let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, ProviderSearchCategory(shelfTitle: title) == nil { continue }
            let payloads = ProviderSearchProjection.songsByItemIndex(in: section)
            for (index, card) in section.items.enumerated() {
                guard let category = ProviderSearchCategory.of(card, song: payloads[index]) else { continue }
                result[category, default: []].append(Entry(card: card, song: payloads[index]))
            }
        }
        return result
    }

    private static func fetched(_ kinds: [ProviderSearchChipKind], category: ProviderSearchCategory,
                                input: ProviderSearchCategoryInput) -> [Entry]? {
        let loaded = kinds.compactMap { input.chipPages[$0] }
        guard !loaded.isEmpty else { return nil }
        var result: [Entry] = []
        var seen = Set<String>()
        for page in loaded {
            for section in page.sections {
                let payloads = ProviderSearchProjection.songsByItemIndex(in: section)
                for (index, card) in section.items.enumerated() where ProviderSearchCategory.of(card, song: payloads[index]) == category {
                    // Playlists come from two chips; the same playlist must not appear twice.
                    if category != .songs, category != .videos, !seen.insert(card.kind + ":" + card.id).inserted { continue }
                    result.append(Entry(card: card, song: payloads[index]))
                }
            }
        }
        return result
    }

    /// The page in category form: the principal block first, then one section per category.
    static func page(from page: SearchPageRecord, input: ProviderSearchCategoryInput) -> SearchPageRecord {
        let tops = page.sections.filter { $0.layout == "top" }
        let mixed = mixedBuckets(in: page)
        let params = chipParams(in: page)

        // Provider chip order is the provider's own ranking of the categories for this query.
        var order: [ProviderSearchCategory] = []
        for chip in page.chips {
            if let kind = ProviderSearchChipKind(chipTitle: chip.title), !order.contains(kind.category) { order.append(kind.category) }
        }
        for category in ProviderSearchCategory.allCases where !order.contains(category) { order.append(category) }

        var sections: [SearchSectionRecord] = []
        for category in order {
            let kinds = ProviderSearchChipKind.allCases.filter { $0.category == category }
            let isPending = !input.pending.isDisjoint(with: kinds)
            let entries = fetched(kinds, category: category, input: input) ?? mixed[category] ?? []
            guard !entries.isEmpty || isPending else { continue }
            let capped = Array(entries.prefix(ProviderSearchCategoryLayout.maxItems))
            let cards = capped.map(\.card)
            let songs = capped.compactMap { entry -> SongItemRecord? in
                guard entry.card.kind == "song" || entry.card.kind == "video" else { return nil }
                return entry.song ?? SongItemRecord(fromCard: entry.card)
            }
            let showAll = kinds.compactMap { params[$0] }.first
            sections.append(SearchSectionRecord(
                id: "category:\(category.rawValue)", title: L10n.text(category.titleKey),
                layout: capped.isEmpty ? "category-loading" : (category.usesGrid ? "category-grid" : "category-carousel"),
                items: cards, songs: songs, primaryItemIndex: nil, relatedItemIndices: [],
                moreQuery: nil, moreParams: capped.isEmpty ? nil : showAll, moreBrowseId: nil, actions: []))
        }
        return SearchPageRecord(chips: page.chips, correction: page.correction,
                                sections: tops + sections, continuation: nil)
    }
}
