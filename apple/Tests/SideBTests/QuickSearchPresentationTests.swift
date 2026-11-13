import Foundation
import Testing
import SideBCore
@testable import SideB

@MainActor struct QuickSearchPresentationTests {
    private final class Clock { var seconds = 1_000.0 }

    private func store(_ clock: Clock) -> SearchRecentStore {
        SearchRecentStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("sideb-quick-" + UUID().uuidString),
                          now: { Date(timeIntervalSince1970: clock.seconds) })
    }
    private func card(_ kind: String, _ id: String, _ title: String? = nil, _ subtitle: String? = nil) -> BrowseCardRecord {
        BrowseCardRecord(kind: kind, id: id, title: title ?? "T \(id)", subtitle: subtitle ?? "S \(id)", thumbnail: nil, duration: nil)
    }
    private func query(_ id: String, _ text: String) -> SearchSuggestionEntryRecord {
        SearchSuggestionEntryRecord(id: id, kind: "history", query: text, runs: [], feedbackToken: "token", card: nil, song: nil)
    }
    private func completion(_ id: String, _ text: String) -> SearchSuggestionEntryRecord {
        SearchSuggestionEntryRecord(id: id, kind: "text", query: text, runs: [], feedbackToken: nil, card: nil, song: nil)
    }
    private func media(_ id: String, _ card: BrowseCardRecord) -> SearchSuggestionEntryRecord {
        SearchSuggestionEntryRecord(id: id, kind: "suggestion", query: nil, runs: [], feedbackToken: nil, card: card, song: nil)
    }
    private func make(_ draft: String, local: [SearchRecentStore.Entry] = [], remote: [SearchSuggestionEntryRecord] = [],
                      page: SearchPageRecord? = nil, showVideos: Bool = true) -> QuickSearchPresentation {
        QuickSearchPresentation.make(draft: draft, local: local, remote: remote, page: page, showVideos: showVideos,
            recentsTitle: "Recent",
            queriesTitle: "Searches", topTitle: "Top", title: { $0.rawValue })
    }

    @Test func emptyFieldShowsLocalRecentsFirstThenTheProviderHistoryWithoutDuplicates() {
        let clock = Clock(), store = store(clock)
        store.recordQuery("adhd"); clock.seconds += 1
        store.recordEntity(card("artist", "a1")); clock.seconds += 1
        store.recordEntity(card("album", "b1"))
        let result = make("  ", local: store.entries, remote: [
            query("r-adhd", "ADHD"), query("r-drake", "drake partynextdoor"),
            media("r-a1", card("artist", "a1")), media("r-album", card("album", "x"))])
        #expect(result.sections.map(\.id) == ["recents"])
        #expect(result.entries.map(\.id) == ["local:entity:album:b1", "local:entity:artist:a1", "local:query:adhd",
                                              "r-drake", "r-album"],
                "most recent local first; the provider's copies of the same query/artist are dropped")
        #expect(QuickSearchPresentation.localKey(of: result.entries[0]) == "entity:album:b1")
        #expect(QuickSearchPresentation.localKey(of: result.entries[3]) == nil)
        #expect(result.entries[0].card?.kind == "album", "a local entity reopens through its card")
    }

    @Test func recentsAreCappedAndAnEmptyListHasNoSection() {
        let clock = Clock(), store = store(clock)
        for index in 0..<12 { store.recordEntity(card("artist", "a\(index)")); clock.seconds += 1 }
        let remote = (0..<5).map { query("r\($0)", "remote \($0)") }
        let result = make("", local: store.entries, remote: remote)
        #expect(result.entries.count == QuickSearchPresentation.maxLocal + 2, "8 local + provider entries up to 10")
        #expect(make("", local: [], remote: []).sections.isEmpty)
    }

    @Test func typingShowsTheTopResultThenSmallGroupsThenOnlyCompletions() {
        let remote = [
            media("top", card("song", "s1")), completion("q1", "kend"), media("a1", card("artist", "a1")),
            media("s2", card("song", "s2")), media("s3", card("song", "s3")), media("s4", card("song", "s4")),
            media("s5", card("song", "s5")), media("s6", card("song", "s6")), media("b1", card("album", "b1")),
            query("h1", "kendrick lamar"), completion("q2", "kendrick h"),
            completion("q3", "kendrick l"), completion("q4", "kendrick x")]
        let result = make("kend", remote: remote)
        #expect(result.sections.map(\.id) == ["top", "group:artists", "group:songs", "group:albums", "queries"])
        #expect(result.sections[0].style == .top && result.sections[0].entries.map(\.id) == ["top"])
        #expect(result.sections[2].entries.map(\.id) == ["s2", "s3", "s4", "s5"], "four songs; the top result is not repeated")
        #expect(result.sections[4].entries.map(\.id) == ["q1", "q2", "q3"], "at most three completions")
        #expect(!result.entries.contains { $0.id == "h1" }, "the user's own history is for the empty field, not for typing")
        #expect(result.entries.map(\.id) == ["top", "a1", "s2", "s3", "s4", "s5", "b1", "q1", "q2", "q3"],
                "the keyboard walks the entries exactly as they are shown")
    }

    /// The shape YouTube Music answers for an artist: principal + related songs + a mixed list.
    private func artistPage() -> SearchPageRecord {
        func row(_ id: String, _ title: String) -> BrowseCardRecord { card("song", id, title) }
        func payload(_ id: String) -> SongItemRecord {
            SongItemRecord(videoId: id, title: "T-\(id)", artists: "A", album: nil, duration: "3:00", thumbnail: nil,
                artistId: nil, albumId: nil, setVideoId: nil, isVideo: false, isUpload: false, library: nil)
        }
        let top = SearchSectionRecord(id: "top", title: "", layout: "top",
            items: [card("artist", "UCk", "Kanye West"), row("r1", "Runaway"), row("r2", "FML"), row("r3", "Heartless")],
            songs: [payload("r1"), payload("r2"), payload("r3")],
            primaryItemIndex: 0, relatedItemIndices: [1, 2, 3], moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: [])
        let listen = SearchSectionRecord(id: "listen", title: "Listen again", layout: "list",
            items: [row("l1", "Personal pick")], songs: [payload("l1")], primaryItemIndex: nil, relatedItemIndices: [],
            moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: [])
        let mixed = SearchSectionRecord(id: "mixed", title: "", layout: "list",
            items: [card("artist", "UCk", "Kanye West"), card("artist", "UC2", "Kid Cudi"), card("album", "MPRE1", "Graduation"),
                    card("album", "MPRE2", "Donda"), card("album", "MPRE3", "Ye"), card("album", "MPRE4", "Vultures"),
                    card("artist", "UC3", "A profile", "Profile • @x")],
            songs: [], primaryItemIndex: nil, relatedItemIndices: [], moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: [])
        return SearchPageRecord(chips: [SearchChipRecord(id: "a", title: "Artists", params: "p", selected: false),
                                        SearchChipRecord(id: "b", title: "Albums", params: "p", selected: false)],
                                correction: nil, sections: [top, listen, mixed], continuation: "more")
    }

    /// YouTube drops the artist from the rows under an artist's top result; showing «Various artists»
    /// for Kanye West's own songs was wrong.
    @Test func songsUnderAnArtistsTopResultInheritThatArtistInsteadOfVariousArtists() throws {
        func song(_ id: String, artists: String) -> SongItemRecord {
            SongItemRecord(videoId: id, title: "T-\(id)", artists: artists, album: nil, duration: "3:00", thumbnail: nil,
                artistId: nil, albumId: nil, setVideoId: nil, isVideo: false, isUpload: false, library: nil)
        }
        func top(primary: BrowseCardRecord) -> SearchSectionRecord {
            SearchSectionRecord(id: "top", title: "", layout: "top",
                items: [primary, card("song", "a", "No artist"), card("song", "b", "Own artist")],
                songs: [song("a", artists: ""), song("b", artists: "Someone Else")],
                primaryItemIndex: 0, relatedItemIndices: [1, 2], moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: [])
        }
        let fromArtist = ProviderSearchProjection.songsByItemIndex(in: top(primary: card("artist", "UCk", "Kanye West")))
        #expect(fromArtist[1]?.artists == "Kanye West")
        #expect(fromArtist[1]?.artistId == "UCk")
        #expect(fromArtist[1]?.artistRuns.first?.id == "UCk", "the name links to the artist")
        #expect(fromArtist[1]?.displayArtist == "Kanye West")
        #expect(fromArtist[2]?.artists == "Someone Else", "a row that names its artist keeps it")

        let fromSong = ProviderSearchProjection.songsByItemIndex(in: top(primary: card("song", "p", "A song")))
        #expect(fromSong[1]?.artists == "", "only an artist's card implies the artist")
    }

    @Test func aFullSearchFillsTheTopResultAndSeveralSongsArtistsAndAlbums() {
        let remote = [media("top", card("artist", "UCk")), completion("c1", "kanye west"), query("h1", "kanye west runaway")]
        let result = make("kanye", remote: remote, page: artistPage())
        #expect(result.sections.map(\.id) == ["top", "group:songs", "group:artists", "group:albums", "queries"])
        #expect(result.sections[0].entries.first?.card?.title == "Kanye West")
        #expect(result.sections[1].entries.map { $0.song?.videoId } == ["r1", "r2", "r3"], "the principal's related songs")
        #expect(result.sections[2].entries.map { $0.card?.title } == ["Kid Cudi"], "the top result is not repeated; profiles are not artists")
        #expect(result.sections[3].entries.map { $0.card?.title } == ["Graduation", "Donda", "Ye"], "three albums at most")
        #expect(!result.entries.contains { $0.card?.title == "Personal pick" || $0.song?.title == "T-l1" },
                "«Listen again» is not a result")
        #expect(result.sections.last?.entries.map(\.id) == ["c1"], "completions only; the history entry is dropped")
    }

    @Test func hiddenVideosAreNotShownEvenFromTheFullSearch() {
        var page = artistPage()
        var video = page.sections[0]
        video.items[2] = card("video", "r2", "A music video")
        video.songs[1].isVideo = true
        page.sections[0] = video
        let result = make("kanye", page: page, showVideos: false)
        #expect(result.sections[1].entries.map { $0.song?.videoId } == ["r1", "r3"])
    }

    @Test func withoutAFullSearchYetTheSuggestionsAreShown() {
        let result = make("kanye", remote: [media("top", card("artist", "UCk")), media("s1", card("song", "s1"))], page: nil)
        #expect(result.sections.map(\.id) == ["top", "group:songs"])
    }

    @Test func aVideoDeliveredAsASongGetsItsOwnGroup() {
        var video = SongItemRecord(videoId: "v", title: "V", artists: "A", album: nil, duration: nil, thumbnail: nil,
            artistId: nil, albumId: nil, setVideoId: nil, isVideo: true, isUpload: false, library: nil)
        video.isVideo = true
        let entry = SearchSuggestionEntryRecord(id: "v", kind: "suggestion", query: nil, runs: [], feedbackToken: nil, card: nil, song: video)
        let result = make("x", remote: [media("top", card("album", "b")), entry])
        #expect(result.sections.map(\.id) == ["top", "group:videos"])
    }

    @Test func nothingIsShownWhileTheProviderHasNotAnswered() {
        #expect(make("kend", remote: []).sections.isEmpty)
    }
}
