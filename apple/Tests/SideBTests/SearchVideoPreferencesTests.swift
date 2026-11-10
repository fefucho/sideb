import Foundation
import Testing
import SideBCore
@testable import SideB

@MainActor struct SearchVideoPreferencesTests {
    private func song(_ video: Bool, _ occurrence: String) -> SongItemRecord {
        SongItemRecord(videoId: "same", title: occurrence, artists: "Artist", album: nil,
            duration: nil, thumbnail: nil, artistId: nil, albumId: nil,
            setVideoId: occurrence, isVideo: video, isUpload: false, library: nil)
    }
    private func section() -> SearchSectionRecord {
        SearchSectionRecord(id: "mixed", title: "Results", layout: "top",
            items: [BrowseCardRecord(kind: "artist", id: "artist", title: "Artist", subtitle: nil, thumbnail: nil, duration: nil)] +
                ["video", "song", "song"].map { BrowseCardRecord(kind: $0, id: "same", title: $0, subtitle: nil, thumbnail: nil, duration: nil) },
            songs: [song(true, "video"), song(false, "first"), song(false, "second")],
            primaryItemIndex: 0, relatedItemIndices: [1, 2, 3],
            moreQuery: "query", moreParams: "opaque", moreBrowseId: nil, actions: [])
    }

    @Test func preferenceDefaultsToShowingVideosAndPersists() throws {
        let name = "SearchVideoPreferencesTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = SearchPreferences(defaults: defaults)
        #expect(preferences.showVideos)
        preferences.showVideos = false
        #expect(!SearchPreferences(defaults: defaults).showVideos)
    }

    @Test func mixedSectionsKeepDuplicateSongPayloadsAndRemapPrincipalRoles() throws {
        let filtered = try #require(SearchPreferences.section(section(), showVideos: false))
        #expect(filtered.items.map(\.kind) == ["artist", "song", "song"])
        #expect(filtered.songs.map(\.setVideoId) == ["first", "second"])
        #expect(filtered.primaryItemIndex == 0)
        #expect(filtered.relatedItemIndices == [1, 2])
        #expect(filtered.moreParams == "opaque")
        #expect(ProviderSearchProjection.song(for: 2, in: filtered)?.setVideoId == "second")
        var videoPrincipal = section()
        videoPrincipal.primaryItemIndex = 1
        #expect(SearchPreferences.section(videoPrincipal, showVideos: false)?.primaryItemIndex == nil)
        var videosOnly = section()
        videosOnly.items = [videosOnly.items[1]]
        videosOnly.songs = [song(true, "video")]
        #expect(SearchPreferences.section(videosOnly, showVideos: false) == nil)
        var actionOnly = section()
        actionOnly.items = []
        actionOnly.songs = []
        #expect(SearchPreferences.section(actionOnly, showVideos: false) == actionOnly)
    }

    @Test func snapshotUpdatesOnToggleAndRestoresRawVideosWithoutRefetching() {
        let page = SearchPageRecord(chips: [], correction: nil, sections: [section()], continuation: "next")
        let snapshot = ProviderSearchPageSnapshot()
        func prepare(_ shows: Bool) {
            snapshot.prepare(page: page, revision: 1, expanded: [], loading: false,
                error: nil, loadingMore: false, localization: "es", showVideos: shows)
        }
        prepare(true)
        #expect(snapshot.sections.first?.record.items.count == 4)
        prepare(false)
        #expect(snapshot.sections.first?.record.items.count == 3)
        #expect(snapshot.entries.last?.id == AnyHashable("more"))
        prepare(false)
        #expect(snapshot.projectionCount == 2)
        prepare(true)
        #expect(snapshot.sections.first?.record.items.count == 4)
    }

    @Test func suggestionsFilterBothKindsOfVideoMetadataAndKeepQueries() {
        let video = SearchSuggestionEntryRecord(id: "v", kind: "media", query: nil, runs: [],
            feedbackToken: nil, card: nil, song: song(true, "video"))
        let query = SearchSuggestionEntryRecord(id: "q", kind: "text", query: "video games", runs: [],
            feedbackToken: nil, card: nil, song: nil)
        #expect(!SearchPreferences.includes(video, showVideos: false))
        #expect(SearchPreferences.includes(video, showVideos: true))
        #expect(SearchPreferences.includes(query, showVideos: false))
        var cardOnly = video
        cardOnly.song = nil
        cardOnly.card = section().items[1]
        #expect(!SearchPreferences.includes(cardOnly, showVideos: false))
    }
}
