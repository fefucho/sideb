import Foundation
import SideBCore

/// What the quick search shows, in the order the keyboard walks it.
///
/// Empty field: one «Recent» list, local entries first (queries, opened artists/albums/playlists,
/// played songs) completed with the provider's own history, without duplicates.
/// Typing: the provider's first media entry as the top result, then text suggestions, then small
/// groups per type.
@MainActor struct QuickSearchPresentation {
    enum Style: Equatable { case recents, top, queries, media }

    struct Section: Identifiable {
        let id: String
        let title: String?
        let style: Style
        let entries: [SearchSuggestionEntryRecord]
    }

    static let localPrefix = "local:"
    static let maxRecents = 10
    static let maxLocal = 8
    static let maxPerGroup = 3
    static let maxQueries = 3

    let sections: [Section]
    /// Flat list in display order: arrow keys and Return follow it.
    var entries: [SearchSuggestionEntryRecord] { sections.flatMap(\.entries) }

    static func isLocal(_ entry: SearchSuggestionEntryRecord) -> Bool { entry.id.hasPrefix(localPrefix) }
    static func localKey(of entry: SearchSuggestionEntryRecord) -> String? {
        isLocal(entry) ? String(entry.id.dropFirst(localPrefix.count)) : nil
    }

    /// Local entries expressed as provider entries so rows, selection and activation are shared.
    static func suggestion(for entry: SearchRecentStore.Entry) -> SearchSuggestionEntryRecord? {
        let id = localPrefix + entry.key
        switch entry.kind {
        case "query":
            guard let query = entry.query else { return nil }
            return SearchSuggestionEntryRecord(id: id, kind: "history", query: query, runs: [],
                                               feedbackToken: nil, card: nil, song: nil)
        case "track":
            guard let track = entry.track else { return nil }
            return SearchSuggestionEntryRecord(id: id, kind: "history", query: nil, runs: [],
                                               feedbackToken: nil, card: nil, song: track.song)
        default:
            guard let card = entry.card else { return nil }
            return SearchSuggestionEntryRecord(id: id, kind: "history", query: nil, runs: [],
                                               feedbackToken: nil, card: card.record, song: nil)
        }
    }

    private static func isMedia(_ entry: SearchSuggestionEntryRecord) -> Bool { entry.card != nil || entry.song != nil }

    private static func category(of entry: SearchSuggestionEntryRecord) -> ProviderSearchCategory? {
        if let song = entry.song {
            return song.isVideo ? .videos : .songs
        }
        return entry.card.flatMap { ProviderSearchCategory.of($0) }
    }

    /// Identity used to drop a provider entry the user already has locally.
    private static func identity(_ entry: SearchSuggestionEntryRecord) -> String? {
        if let song = entry.song { return "song:" + song.videoId }
        if let card = entry.card {
            return card.kind == "song" || card.kind == "video" ? "song:" + card.id : card.kind + ":" + card.id
        }
        if let query = entry.query {
            let text = SearchRecentStore.normalizedQuery(query).lowercased()
            return text.isEmpty ? nil : "query:" + text
        }
        return nil
    }

    /// Categories worth a group in a dropdown; profiles, podcasts and episodes stay on the results page.
    private static let quickCategories: [ProviderSearchCategory] = [.songs, .artists, .albums, .playlists, .videos]

    private static func mediaEntry(_ section: SearchSectionRecord, _ index: Int,
                                   _ payloads: [Int: SongItemRecord]) -> SearchSuggestionEntryRecord {
        SearchSuggestionEntryRecord(id: "page:" + section.id + ":" + String(index), kind: "media", query: nil, runs: [],
                                    feedbackToken: nil, card: section.items[index], song: payloads[index])
    }

    /// Top result and groups from a full provider search: the principal block, the songs related to it,
    /// and the page's own categories (shelves such as «Listen again» are not results).
    private static func pageSections(_ page: SearchPageRecord, showVideos: Bool, topTitle: String,
                                     title: (ProviderSearchCategory) -> String) -> [Section] {
        var sections: [Section] = []
        var seen = Set<String>()
        var related: [SearchSuggestionEntryRecord] = []
        if let raw = page.sections.first(where: { $0.layout == "top" }),
           let top = SearchPreferences.section(raw, showVideos: showVideos),
           let roles = ProviderSearchProjection.roles(for: top) {
            let payloads = ProviderSearchProjection.songsByItemIndex(in: top)
            let primary = mediaEntry(top, roles.primaryIndex, payloads)
            if let key = identity(primary) { seen.insert(key) }
            sections.append(Section(id: "top", title: topTitle, style: .top, entries: [primary]))
            for index in roles.relatedIndices where ["song", "video"].contains(top.items[index].kind) {
                related.append(mediaEntry(top, index, payloads))
            }
        }
        var order: [ProviderSearchCategory] = []
        var groups: [ProviderSearchCategory: [SearchSuggestionEntryRecord]] = [:]
        let projected = ProviderSearchCategoryProjection.page(from: page, input: ProviderSearchCategoryInput())
        for section in projected.sections where section.layout.hasPrefix("category-") {
            guard let category = ProviderSearchCategory(rawValue: String(section.id.dropFirst("category:".count))),
                  quickCategories.contains(category),
                  let filtered = SearchPreferences.section(section, showVideos: showVideos) else { continue }
            let payloads = ProviderSearchProjection.songsByItemIndex(in: filtered)
            order.append(category)
            groups[category] = filtered.items.indices.map { mediaEntry(filtered, $0, payloads) }
        }
        if !related.isEmpty {
            if groups[.songs] == nil { order.insert(.songs, at: 0) }
            groups[.songs] = related + (groups[.songs] ?? [])
        }
        for category in order {
            var entries: [SearchSuggestionEntryRecord] = []
            for entry in groups[category] ?? [] {
                if let key = identity(entry), !seen.insert(key).inserted { continue }
                entries.append(entry)
                if entries.count == maxPerGroup(category) { break }
            }
            if !entries.isEmpty {
                sections.append(Section(id: "group:" + category.rawValue, title: title(category), style: .media, entries: entries))
            }
        }
        return sections
    }

    private static func maxPerGroup(_ category: ProviderSearchCategory) -> Int { category == .songs ? 4 : maxPerGroup }

    static func make(draft: String, local: [SearchRecentStore.Entry], remote: [SearchSuggestionEntryRecord],
                     page: SearchPageRecord? = nil, showVideos: Bool = true,
                     recentsTitle: String, queriesTitle: String, topTitle: String,
                     title: (ProviderSearchCategory) -> String) -> QuickSearchPresentation {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            let own = local.prefix(maxLocal).compactMap { suggestion(for: $0) }
            var seen = Set(own.compactMap(identity))
            var list = own
            for entry in remote where list.count < maxRecents {
                if let key = identity(entry), !seen.insert(key).inserted { continue }
                list.append(entry)
            }
            return QuickSearchPresentation(sections: list.isEmpty ? [] :
                [Section(id: "recents", title: recentsTitle, style: .recents, entries: list)])
        }

        // While typing, only completions of what is typed: the user's own history is for the empty field.
        var sections: [Section] = []
        let found = page.map { pageSections($0, showVideos: showVideos, topTitle: topTitle, title: title) } ?? []
        if !found.isEmpty {
            sections = found
        } else {
            let media = remote.filter(isMedia)
            if let top = media.first { sections.append(Section(id: "top", title: topTitle, style: .top, entries: [top])) }
            var order: [ProviderSearchCategory] = []
            var groups: [ProviderSearchCategory: [SearchSuggestionEntryRecord]] = [:]
            var other: [SearchSuggestionEntryRecord] = []
            for entry in media.dropFirst() {
                guard let category = category(of: entry) else { other.append(entry); continue }
                if groups[category] == nil { order.append(category) }
                if groups[category, default: []].count < maxPerGroup(category) { groups[category, default: []].append(entry) }
            }
            for category in order {
                sections.append(Section(id: "group:" + category.rawValue, title: title(category), style: .media,
                                        entries: groups[category] ?? []))
            }
            if !other.isEmpty { sections.append(Section(id: "group:other", title: nil, style: .media, entries: Array(other.prefix(maxPerGroup)))) }
        }
        let completions = remote.filter { !isMedia($0) && $0.kind != "history" }.prefix(maxQueries)
        if !completions.isEmpty {
            sections.append(Section(id: "queries", title: queriesTitle, style: .queries, entries: Array(completions)))
        }
        return QuickSearchPresentation(sections: sections)
    }
}
