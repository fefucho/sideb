import Foundation
import Testing
import SideBCore
@testable import SideB

struct ProviderSearchProjectionPerformanceTests {
    private func card(_ kind: String, id: String, title: String) -> BrowseCardRecord {
        BrowseCardRecord(kind: kind, id: id, title: title, subtitle: "Artist", thumbnail: nil, duration: "3:00")
    }

    private func song(_ id: String, setVideoId: String?) -> SongItemRecord {
        SongItemRecord(videoId: id, title: "Payload \(setVideoId ?? "none")", artists: "Artist", album: nil,
            duration: "3:00", thumbnail: nil, artistId: nil, albumId: nil, setVideoId: setVideoId,
            isVideo: false, isUpload: false, library: nil)
    }

    private func section(items: [BrowseCardRecord], songs: [SongItemRecord]) -> SearchSectionRecord {
        SearchSectionRecord(id: "projection-fixture", title: "", layout: "list", items: items, songs: songs,
            primaryItemIndex: nil, relatedItemIndices: [], moreQuery: nil, moreParams: nil,
            moreBrowseId: nil, actions: [])
    }

    @Test func precomputedMapKeepsRepeatedOccurrencesAndIsConstantTimeToRead() {
        let count = 5_000
        let items = (0..<count).map { index in
            card(index.isMultiple(of: 3) ? "video" : "song", id: "repeat-\(index % 11)", title: "Card \(index)")
        }
        let songs = (0..<count).map { index in
            song("repeat-\(index % 11)", setVideoId: "opaque-\(index)")
        }
        let fixture = section(items: items, songs: songs)

        let start = ContinuousClock.now
        let projection = ProviderSearchProjection.songsByItemIndex(in: fixture)
        let projectedOccurrences = (0..<count).compactMap { projection[$0] }
        let elapsed = start.duration(to: .now)

        #expect(projection.count == count)
        #expect(projectedOccurrences.count == count)
        for index in [0, 1, 10, 11, 1_234, 4_999] {
            #expect(projection[index]?.setVideoId == "opaque-\(index)")
        }
        // Informational timing only; no machine-dependent performance threshold.
        print("ProviderSearchProjection: prepared and read \(count) occurrences in \(elapsed)")
    }

    @Test func mismatchUsesOnlyUniqueIDFallbackAndMissingPayloadUsesCardFallback() {
        let items = [
            card("song", id: "missing", title: "Card fallback"),
            card("album", id: "album", title: "Non-song"),
            card("video", id: "unique", title: "Unique fallback"),
            card("song", id: "duplicate", title: "Duplicate first"),
            card("video", id: "duplicate", title: "Duplicate second")
        ]
        // The first payload mismatches its ordinal. The second is uniquely recoverable by ID;
        // duplicate IDs must not be searched/rebound away from their occurrence positions.
        let songs = [song("other", setVideoId: "wrong-ordinal"),
            song("unrelated", setVideoId: "second-wrong-ordinal"),
            song("duplicate", setVideoId: "duplicate-first"),
            song("duplicate", setVideoId: "duplicate-second"),
            song("unique", setVideoId: "unique-payload")]
        let fixture = section(items: items, songs: songs)
        let projection = ProviderSearchProjection.songsByItemIndex(in: fixture)

        #expect(projection[0]?.title == "Card fallback")
        #expect(projection[1] == nil)
        #expect(projection[2]?.setVideoId == "unique-payload")
        #expect(projection[3]?.setVideoId == "duplicate-first")
        #expect(projection[4]?.setVideoId == "duplicate-second")
    }

    @Test func noPayloadsStillProducesSongFallbacksAndLegacyLookupMatchesMap() {
        let fixture = section(items: [
            card("artist", id: "artist", title: "Artist"),
            card("song", id: "song", title: "Fallback song"),
            card("video", id: "video", title: "Fallback video")
        ], songs: [])

        let projection = ProviderSearchProjection.songsByItemIndex(in: fixture)
        #expect(projection.count == 2)
        #expect(projection[0] == nil)
        #expect(projection[1]?.title == "Fallback song")
        #expect(projection[2]?.title == "Fallback video")
        #expect(ProviderSearchProjection.song(for: 1, in: fixture)?.title == projection[1]?.title)
        #expect(ProviderSearchProjection.song(for: 2, in: fixture)?.title == projection[2]?.title)
        #expect(ProviderSearchProjection.song(for: 3, in: fixture) == nil)
    }
}
