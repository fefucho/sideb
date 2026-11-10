import Foundation
import Observation
import SideBCore

@MainActor @Observable
final class SearchPreferences {
    static let shared = SearchPreferences(defaults: HomeAppearance.preferences)
    static let showVideosKey = "sideb.search.showVideos.v1"
    private let defaults: UserDefaults
    var showVideos: Bool {
        didSet { defaults.set(showVideos, forKey: Self.showVideosKey) }
    }
    init(defaults: UserDefaults) {
        self.defaults = defaults
        showVideos = defaults.object(forKey: Self.showVideosKey) as? Bool ?? true
    }

    static func includes(_ entry: SearchSuggestionEntryRecord, showVideos: Bool) -> Bool {
        showVideos || (entry.card?.kind != "video" && entry.song?.isVideo != true)
    }

    /// Filter occurrences before rendering, preserving the exact payload and remapping roles.
    static func section(_ section: SearchSectionRecord, showVideos: Bool) -> SearchSectionRecord? {
        guard !showVideos else { return section }
        let payloads = ProviderSearchProjection.songsByItemIndex(in: section)
        let kept = section.items.indices.filter {
            section.items[$0].kind != "video" && payloads[$0]?.isVideo != true
        }
        guard kept.count != section.items.count else { return section }
        guard !kept.isEmpty else { return nil }
        var result = section
        result.items = kept.map { section.items[$0] }
        result.songs = kept.compactMap { payloads[$0] }
        let indices = Dictionary(uniqueKeysWithValues: kept.enumerated().map { ($0.element, UInt32($0.offset)) })
        result.primaryItemIndex = section.primaryItemIndex.flatMap { indices[Int($0)] }
        result.relatedItemIndices = section.relatedItemIndices.compactMap { indices[Int($0)] }
        // Provider actions can target media removed by this preference.
        result.actions = []
        return result
    }
}
