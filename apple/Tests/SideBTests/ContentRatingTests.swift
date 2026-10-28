import Foundation
import Testing
import AppKit
import SideBCore
@testable import SideB

@MainActor private func ratedSong(_ id: String = "version-a", _ rating: ContentRating = .unknown) -> SongItemRecord {
    var song = SongItemRecord(videoId: id, title: "Song", artists: "Artist", album: nil,
        duration: "3:00", thumbnail: nil, artistId: nil, albumId: "album-a", setVideoId: nil)
    song.contentRating = rating
    return song
}

@Test @MainActor func contentRatingsSurvivePlaybackAndRecentSnapshotsWithoutInventingClean() throws {
    for rating in [ContentRating.explicit, .clean, .unknown] {
        let song = ratedSong("version-a", rating)
        let saved = SavedPlaybackState.Track(song)
        let roundTrip = try JSONDecoder().decode(SavedPlaybackState.Track.self, from: JSONEncoder().encode(saved))
        #expect(roundTrip.song == song)
        let recent = SearchRecentStore.Track(song)
        #expect(try JSONDecoder().decode(SearchRecentStore.Track.self, from: JSONEncoder().encode(recent)).song == song)
    }
    let encoded = try JSONEncoder().encode(SavedPlaybackState.Track(ratedSong("version-a", .explicit)))
    var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacy.removeValue(forKey: "contentRating")
    let restored = try JSONDecoder().decode(SavedPlaybackState.Track.self, from: JSONSerialization.data(withJSONObject: legacy)).song
    #expect(restored.contentRating == .unknown)
    #expect(ContentRatingMetadata.decode(nil, legacyExplicit: true) == .explicit)
    #expect(ContentRatingMetadata.decode(nil, legacyExplicit: false) == .unknown)
    #expect(ContentRatingMetadata.decode("future-rating") == .unknown)
}

@Test @MainActor func radioRatingOnlyEnrichesTheSameAudioAndNeverDegradesKnownEvidence() {
    let seed = ratedSong("version-a", .explicit)
    #expect(PlaybackAlbumMetadata.merging(seed, radio: ratedSong()).contentRating == .explicit)
    #expect(PlaybackAlbumMetadata.merging(ratedSong(), radio: seed).contentRating == .explicit)
    #expect(PlaybackAlbumMetadata.merging(ratedSong(), radio: ratedSong("version-b", .clean)).contentRating == .unknown)
    #expect(PlaybackAlbumMetadata.merging(seed, radio: ratedSong("version-a", .clean)).contentRating == .explicit)
}

@Test @MainActor func albumHeaderNeverRatesAnUnmarkedTrackAndOtherVersionsStayIndependent() {
    var album = AlbumDetailRecord(browseId: "album-a", title: "Album", artist: "Artist", artistId: nil,
        subtitle: nil, secondSubtitle: nil, description: nil, thumbnail: nil, playlistId: nil,
        inLibrary: false, items: [ratedSong()], sections: [])
    album.contentRating = .explicit
    #expect(PlaybackAlbumMetadata.merging(ratedSong(), album: album).contentRating == .unknown)
    album.items = [ratedSong("version-a", .explicit)]
    #expect(PlaybackAlbumMetadata.merging(ratedSong(), album: album).contentRating == .explicit)
    #expect(PlaybackAlbumMetadata.merging(ratedSong("version-b"), album: album).contentRating == .unknown)
}

@Test @MainActor func recycledBadgeScalesWithSecondaryTextAndClearsThePreviousRating() {
    let badge = NativeContentRatingBadge(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    badge.rating = .explicit
    #expect(!badge.isHidden)
    #expect(badge.intrinsicContentSize == NSSize(width: 10, height: 10))
    #expect(badge.toolTip == ContentRatingMetadata.label(.explicit))
    badge.rating = .unknown
    #expect(badge.isHidden)
    #expect(badge.toolTip == ContentRatingMetadata.label(.unknown))
}

@Test @MainActor func homeCacheMigratesLegacyBadgeWithoutCallingUnmarkedCardsClean() throws {
    for explicit in [false, true] {
        let item = HomeItemRecord(kind: "song", id: "version-a", title: "Song", subtitle: "Artist",
            thumbnail: nil, duration: nil, artists: "Artist", artistId: nil, album: nil, albumId: nil,
            artistRuns: [], explicit: explicit)
        let cached = HomeCachedPage.Item(item)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(cached)) as? [String: Any])
        legacy.removeValue(forKey: "contentRating")
        let restored = try JSONDecoder().decode(HomeCachedPage.Item.self, from: JSONSerialization.data(withJSONObject: legacy)).record
        #expect(restored.contentRating == (explicit ? .explicit : .unknown))
        #expect(SongItemRecord(fromHomeItem: restored).contentRating == restored.contentRating)
    }
    let queue = QueueManager()
    queue.replaceQueue(with: [ratedSong("version-a", .explicit)], context: .custom(title: "Queue"))
    let occurrence = queue.currentOccurrenceID
    let token = queue.queueToken
    queue.updateCurrentMetadata(ratedSong(), occurrenceID: occurrence, queueToken: token)
    #expect(queue.currentTrack?.contentRating == .explicit)
    #expect(queue.currentOccurrenceID == occurrence)
}

@Test @MainActor func contentBadgeGeometryClampsAndKeepsTheSharedPathCentered() {
    let samples: [(CGFloat, CGFloat)] = [(8, 9), (11, 9), (11.5, 10), (12, 10), (13.5, 11), (14, 12), (32, 12)]
    for (fontSize, side) in samples {
        #expect(ContentRatingBadgeMetrics.side(for: fontSize) == side)
        #expect(ContentRatingBadgeMetrics.radius(for: side) == side * 3 / 14)
        let badge = NativeContentRatingBadge(frame: .zero)
        badge.fontSize = fontSize
        badge.rating = .explicit
        #expect(badge.intrinsicContentSize == NSSize(width: side, height: side))
        // The original glyph bounds x4…10/y3…11 remain centered after scaling.
        #expect(abs((4 * side / 14 + 10 * side / 14) / 2 - side / 2) < 0.0001)
        #expect(abs((3 * side / 14 + 11 * side / 14) / 2 - side / 2) < 0.0001)
    }
    #expect(ContentRatingBadgeMetrics.gap == 4)
}

@Test @MainActor func nativeSecondaryBadgeKeepsCreditsAndReleasesItsSpaceWhenReused() throws {
    let cell = NativeQueueTrackCellView(frame: NSRect(x: 0, y: 0, width: 576, height: 46))
    func configure(_ rating: ContentRating) {
        cell.configure(track: ratedSong("version-a", rating), index: 0, isCurrentTrack: true,
            isPlaying: false, isLiked: false, hideAlbum: true, showAlbumInSubtitle: true,
            isReorderable: false, rowHeight: 46)
        cell.layoutSubtreeIfNeeded()
    }
    configure(.explicit)
    let metadata = try #require(cell.subviews.first { $0 is NativeRatedMetadata } as? NativeRatedMetadata)
    let title = try #require(cell.subviews.first { $0.accessibilityIdentifier() == "NativeQueueTrackTitle" } as? NSTextField)
    let credits = try #require(metadata.arrangedSubviews.compactMap { $0 as? NSTextField }.first)
    #expect(title.superview === cell)
    #expect(credits.superview === metadata)
    #expect(metadata.badge.rating == .explicit)
    #expect(metadata.badge.fontSize == 11.5)
    #expect(metadata.spacing == 4)
    let titleRect = cell.convert(title.bounds, from: title)
    let creditRect = cell.convert(credits.bounds, from: credits)
    #expect(creditRect.minX >= titleRect.minX + 13)
    #expect(creditRect.maxY < titleRect.minY)
    let identity = title.stringValue
    configure(.unknown)
    #expect(metadata.badge.isHidden)
    #expect(title.stringValue == identity)
    #expect(abs(cell.convert(credits.bounds, from: credits).minX - titleRect.minX) < 0.1)
    configure(.clean)
    #expect(!metadata.badge.isHidden)
    cell.prepareForReuse()
    #expect(metadata.badge.rating == .unknown)
    #expect(metadata.badge.isHidden)
}
