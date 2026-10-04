import Foundation
import SideBCore

enum HomeSectionStyle: Equatable {
    case largeCard
    case compactSong
}

struct HomeItemPresentation: Identifiable, Equatable {
    let id: String
    let sectionID: String
    let style: HomeSectionStyle
    let record: HomeItemRecord
}

struct HomeSectionPresentation: Identifiable, Equatable {
    let id: String
    let title: String
    let style: HomeSectionStyle
    let items: [HomeItemPresentation]
    let moreBrowseId: String?
    let moreParams: String?

    var isNavigableMore: Bool {
        guard let id = moreBrowseId, !id.isEmpty else { return false }
        return !id.hasPrefix("FE")
    }
}

struct HomeFeedCategoryDescriptor: Identifiable, Equatable, Sendable {
    let key: String
    let title: String

    var id: String { key }
}

enum HomePresentationFactory {
    static func categories(from records: [HomeSectionRecord]) -> [HomeFeedCategoryDescriptor] {
        var seen = Set<String>()
        return records.compactMap { record in
            let key = HomeRecommendationSettings.categoryKey(forTitle: record.title)
            guard seen.insert(key).inserted else { return nil }
            return HomeFeedCategoryDescriptor(key: key, title: record.title)
        }
    }

    static func sections(
        from records: [HomeSectionRecord],
        chip: String?,
        preserveProviderOrder: Bool = false
    ) -> [HomeSectionPresentation] {
        var identities: [String: Int] = [:]
        let rawSections = records.compactMap { section -> HomeSectionPresentation? in
            guard !section.items.isEmpty else { return nil }
            let identity = sectionIdentity(section)
            let occurrence = identities[identity, default: 0]
            identities[identity] = occurrence + 1
            let sectionID = "\(chip ?? "all")|\(identity)|\(occurrence)"
            let sectionStyle = style(for: section)
            var itemOccurrences: [String: Int] = [:]
            let items = section.items.map { record in
                let key = "\(record.kind)|\(record.id)"
                let itemOccurrence = itemOccurrences[key, default: 0]
                itemOccurrences[key] = itemOccurrence + 1
                return HomeItemPresentation(
                    id: "\(sectionID)|\(key)|\(itemOccurrence)",
                    sectionID: sectionID,
                    style: sectionStyle,
                    record: record
                )
            }
            return HomeSectionPresentation(
                id: sectionID,
                title: section.title,
                style: sectionStyle,
                items: items,
                moreBrowseId: section.moreBrowseId,
                moreParams: section.moreParams
            )
        }

        guard chip == nil, !preserveProviderOrder else { return rawSections }
        return rawSections.enumerated().sorted { left, right in
            let lhs = sectionPriority(for: left.element)
            let rhs = sectionPriority(for: right.element)
            return lhs == rhs ? left.offset < right.offset : lhs < rhs
        }.map(\.element)
    }

    private static func sectionIdentity(_ section: HomeSectionRecord) -> String {
        guard let first = section.items.first, let last = section.items.last else { return section.title }
        if let browseID = section.moreBrowseId, !browseID.isEmpty {
            return "more|\(browseID)|\(section.moreParams ?? "")|\(first.kind):\(first.id)|\(last.kind):\(last.id)"
        }
        return "items|\(first.kind):\(first.id)|\(last.kind):\(last.id)"
    }

    private static func sectionPriority(for section: HomeSectionPresentation) -> Int {
        switch normalized(section.title) {
        case "listen again", "vuelve a escucharlo", "volver a escuchar", "escuchar de nuevo": return 0
        case "forgotten favorites", "forgotten favourites", "favoritos olvidados": return 1
        case "albums for you", "albumes para ti", "álbumes para ti": return 2
        case "from your library", "de tu biblioteca", "de la biblioteca": return 3
        case "quick picks", "selecciones rapidas", "selecciones rápidas": return 5
        default: return 6
        }
    }

    private static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func style(for section: HomeSectionRecord) -> HomeSectionStyle {
        let title = normalized(section.title)
        let isListenAgain = ["listen again", "vuelve a escucharlo", "volver a escuchar", "escuchar de nuevo"].contains(title)
        let isForgottenFavorites = ["forgotten favorites", "forgotten favourites", "favoritos olvidados"].contains(title)
        if isListenAgain || isForgottenFavorites { return .largeCard }

        let allSongs = section.items.allSatisfy { $0.kind == "song" }
        let isQuickPicks = ["quick picks", "selecciones rapidas", "selecciones rápidas"].contains(title)
        if allSongs && (isQuickPicks || section.format == .compactSongs) { return .compactSong }
        return .largeCard
    }
}
