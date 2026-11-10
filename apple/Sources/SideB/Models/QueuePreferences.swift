import Foundation

enum QueueRecommendationSelection: String, CaseIterable {
    case advance
    case playOnly = "play-only"

    static func resolve(_ raw: String?) -> Self { Self(rawValue: raw ?? "") ?? .advance }
    var labelKey: String { self == .advance ? "queue.selection.advance" : "queue.selection.playOnly" }
}

enum QueuePreferences {
    static let selectionKey = "sideb.queue.recommendationSelection.v1"
    static func selection(in defaults: UserDefaults) -> QueueRecommendationSelection {
        QueueRecommendationSelection.resolve(defaults.string(forKey: selectionKey))
    }
}
