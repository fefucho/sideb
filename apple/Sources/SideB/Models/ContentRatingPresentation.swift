import Foundation
import SideBCore

/// Stable names in local files; absent/future values never imply a clean version.
enum ContentRatingMetadata {
    static func decode(_ value: String?, legacyExplicit: Bool = false) -> ContentRating {
        switch value {
        case "explicit": return .explicit
        case "clean": return .clean
        default: return legacyExplicit ? .explicit : .unknown
        }
    }
    static func encode(_ rating: ContentRating) -> String {
        switch rating {
        case .explicit: return "explicit"
        case .clean: return "clean"
        case .unknown: return "unknown"
        }
    }
    static func merging(_ known: ContentRating, incoming: ContentRating) -> ContentRating {
        known == .unknown ? incoming : known
    }
    static func label(_ rating: ContentRating) -> String {
        L10n.text(rating == .explicit ? "home.explicit_content" : rating == .clean ? "content.clean" : "content.unknown")
    }
}

extension HomeItemRecord {
    var effectiveContentRating: ContentRating {
        contentRating == .unknown && explicit ? .explicit : contentRating
    }
    /// Legacy fixtures and synthetic entities have no positive clean evidence.
    public init(kind: String, id: String, title: String, subtitle: String?, thumbnail: String?, duration: String?, artists: String?, artistId: String?, album: String?, albumId: String?, artistRuns: [HomeArtistRunRecord], explicit: Bool) {
        self.init(kind: kind, id: id, title: title, subtitle: subtitle, thumbnail: thumbnail, duration: duration, artists: artists, artistId: artistId, album: album, albumId: albumId, artistRuns: artistRuns, explicit: explicit, contentRating: explicit ? .explicit : .unknown)
    }
}

extension SongItemRecord {
    public init(videoId: String, title: String, artists: String, album: String?, duration: String?, thumbnail: String?, artistId: String?, albumId: String?, setVideoId: String?, isVideo: Bool, isUpload: Bool, library: LibraryToggleRecord?, artistRuns: [HomeArtistRunRecord]) {
        self.init(videoId: videoId, title: title, artists: artists, album: album, duration: duration, thumbnail: thumbnail, artistId: artistId, albumId: albumId, setVideoId: setVideoId, isVideo: isVideo, isUpload: isUpload, library: library, artistRuns: artistRuns, contentRating: .unknown)
    }
}

extension BrowseCardRecord {
    public init(kind: String, id: String, title: String, subtitle: String?, thumbnail: String?, duration: String?) {
        self.init(kind: kind, id: id, title: title, subtitle: subtitle, thumbnail: thumbnail, duration: duration, contentRating: .unknown)
    }
}

extension AlbumDetailRecord {
    public init(browseId: String, title: String, artist: String?, artistId: String?, subtitle: String?, secondSubtitle: String?, description: String?, thumbnail: String?, playlistId: String?, inLibrary: Bool, items: [SongItemRecord], sections: [ArtistCarouselRecord]) {
        self.init(browseId: browseId, title: title, artist: artist, artistId: artistId, subtitle: subtitle, secondSubtitle: secondSubtitle, description: description, thumbnail: thumbnail, playlistId: playlistId, inLibrary: inLibrary, contentRating: .unknown, items: items, sections: sections)
    }
}
