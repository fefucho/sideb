import Foundation

/// The collection shown beside Speed Dial. This preference changes the local
/// projection of Home, leaving the provider's complete feed available.
enum HomeFeaturedCollectionKind: String, CaseIterable, Codable, Sendable {
    case albums
    case playlists

    var title: String {
        switch self {
        case .albums: return L10n.text("home.collection.albums")
        case .playlists: return L10n.text("home.collection.playlists")
        }
    }

    var recordKind: String {
        switch self {
        case .albums: return "album"
        case .playlists: return "playlist"
        }
    }
}
