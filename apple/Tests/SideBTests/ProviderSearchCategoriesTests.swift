import AppKit
import SwiftUI
import Testing
import SideBCore
@testable import SideB

@MainActor struct ProviderSearchCategoriesTests {
    private func card(_ kind: String, _ id: String, _ title: String, _ subtitle: String? = nil) -> BrowseCardRecord {
        BrowseCardRecord(kind: kind, id: id, title: title, subtitle: subtitle, thumbnail: nil, duration: kind == "song" ? "3:00" : nil)
    }
    private func song(_ id: String, set: String? = nil) -> SongItemRecord {
        SongItemRecord(videoId: id, title: "T-\(id)", artists: "A", album: nil, duration: "3:00", thumbnail: nil,
            artistId: nil, albumId: nil, setVideoId: set, isVideo: false, isUpload: false, library: nil)
    }
    private func section(_ id: String, title: String = "", layout: String = "list", items: [BrowseCardRecord],
                         songs: [SongItemRecord] = [], primary: UInt32? = nil, related: [UInt32] = []) -> SearchSectionRecord {
        SearchSectionRecord(id: id, title: title, layout: layout, items: items, songs: songs, primaryItemIndex: primary,
            relatedItemIndices: related, moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: [])
    }
    private func chips(_ titles: [String]) -> [SearchChipRecord] {
        titles.map { SearchChipRecord(id: $0, title: $0, params: "params-\($0)", selected: false) }
    }
    /// The shape YouTube Music returned for «kendrick lamar»: principal, a personalized shelf and one mixed list.
    private func kendrickPage() -> SearchPageRecord {
        SearchPageRecord(
            chips: chips(["Songs", "Artists", "Videos", "Albums", "Community playlists", "Profiles", "Featured playlists", "Podcasts"]),
            correction: nil,
            sections: [
                section("top", layout: "top", items: [card("artist", "UCk", "Kendrick Lamar", "Artist • 132M"), card("song", "s0", "N95")],
                        songs: [song("s0")], primary: 0, related: [1]),
                section("listen", title: "Listen again", items: [card("song", "s1", "Money Trees"), card("song", "s2", "DNA.")],
                        songs: [song("s1"), song("s2")]),
                section("mixed", items: [
                    card("artist", "UC1", "Travis Scott", "Artist • 95M monthly audience"),
                    card("album", "MPRE1", "GNX", "Album • Kendrick Lamar • 2024"),
                    card("album", "MPRE2", "DAMN.", "Album • Kendrick Lamar • 2017"),
                    card("artist", "UC2", "Ukoon$", "Profile • @Patee67"),
                    card("playlist", "VL1", "Kendrick Super Bowl Set", "Playlist • Pawkeshup"),
                    card("playlist", "MPSP1", "AllHitsPodcast", "Podcast"),
                ]),
            ], continuation: "more")
    }

    @Test func groupsTheMixedListByTypeKeepingThePrincipalAndDroppingPersonalizedShelves() {
        let result = ProviderSearchCategoryProjection.page(from: kendrickPage(), input: ProviderSearchCategoryInput())
        #expect(result.sections.map(\.id) == ["top", "category:artists", "category:albums", "category:playlists",
                                              "category:profiles", "category:podcasts"])
        #expect(result.sections[0].primaryItemIndex == 0, "the principal block is untouched")
        #expect(result.sections.flatMap(\.items).allSatisfy { $0.title != "Money Trees" && $0.title != "DNA." || $0.id == "s0" },
                "«Listen again» songs are not search results")
        #expect(result.sections[1].items.map(\.title) == ["Travis Scott"], "a profile is not an artist")
        #expect(result.sections[4].items.map(\.title) == ["Ukoon$"])
        #expect(result.sections[5].items.map(\.title) == ["AllHitsPodcast"], "a podcast is not a playlist")
        #expect(result.sections[3].items.map(\.title) == ["Kendrick Super Bowl Set"])
        #expect(result.continuation == nil)
        #expect(result.sections[1].layout == "category-carousel")
    }

    @Test func orderFollowsTheProviderChipsAndPendingCategoriesGetAPlaceholder() {
        var input = ProviderSearchCategoryInput()
        input.pending = [.songs]
        let result = ProviderSearchCategoryProjection.page(from: kendrickPage(), input: input)
        #expect(result.sections.map(\.id).prefix(3) == ["top", "category:songs", "category:artists"])
        #expect(result.sections[1].layout == "category-loading")
        #expect(result.sections[1].items.isEmpty)
    }

    @Test func aFetchedCategoryReplacesItsMixedItemsAndKeepsOccurrencePayloads() throws {
        let songsPage = SearchPageRecord(chips: [], correction: nil, sections: [
            section("s", title: "Songs", items: [card("song", "same", "First"), card("song", "same", "Second")],
                    songs: [song("same", set: "one"), song("same", set: "two")])
        ], continuation: nil)
        var input = ProviderSearchCategoryInput()
        input.chipPages[.songs] = songsPage
        let result = ProviderSearchCategoryProjection.page(from: kendrickPage(), input: input)
        let songs = try #require(result.sections.first { $0.id == "category:songs" })
        #expect(songs.layout == "category-grid")
        #expect(songs.items.map(\.title) == ["First", "Second"])
        #expect(songs.songs.map(\.setVideoId) == ["one", "two"], "duplicate video IDs keep their own payload")
        #expect(songs.moreParams == "params-Songs", "the heading action is the chip search")
    }

    @Test func playlistsMergeFeaturedAndCommunityWithoutDuplicates() throws {
        func page(_ ids: [String]) -> SearchPageRecord {
            SearchPageRecord(chips: [], correction: nil, sections: [
                section("p", items: ids.map { card("playlist", $0, "PL \($0)", "Playlist • x") })], continuation: nil)
        }
        var input = ProviderSearchCategoryInput()
        input.chipPages[.featuredPlaylists] = page(["a", "b"])
        input.chipPages[.communityPlaylists] = page(["b", "c"])
        let result = ProviderSearchCategoryProjection.page(from: kendrickPage(), input: input)
        let playlists = try #require(result.sections.first { $0.id == "category:playlists" })
        #expect(playlists.items.map(\.id) == ["b", "c", "a"], "community then featured, duplicates removed")
    }

    /// YouTube Music can deliver a video as a `song` card; only its payload says `isVideo`.
    @Test func aVideoDeliveredAsASongBelongsToVideosNotSongs() throws {
        var video = song("vid")
        video.isVideo = true
        let videosPage = SearchPageRecord(chips: [], correction: nil, sections: [
            section("v", title: "Videos", items: [card("song", "vid", "Official Video"), card("song", "clip", "Plain Song")],
                    songs: [video, song("clip")])
        ], continuation: nil)
        var input = ProviderSearchCategoryInput()
        input.chipPages[.videos] = videosPage
        let result = ProviderSearchCategoryProjection.page(from: kendrickPage(), input: input)
        let videos = try #require(result.sections.first { $0.id == "category:videos" })
        #expect(videos.items.map(\.id) == ["vid"], "only the video, in its own section")
        #expect(videos.layout == "category-grid")
        #expect(ProviderSearchCategory.of(card("song", "vid", "x"), song: video) == .videos)
        #expect(ProviderSearchCategory.of(card("song", "clip", "x"), song: song("clip")) == .songs)
    }

    @Test func fetchTargetsAreTheCoreCategoriesPlusThoseAlreadyPresentInProviderOrder() {
        let targets = ProviderSearchCategoryProjection.fetchTargets(page: kendrickPage(), showVideos: true)
        #expect(targets.map(\.kind) == [.songs, .artists, .videos, .albums, .communityPlaylists, .profiles, .featuredPlaylists, .podcasts])
        let withoutVideos = ProviderSearchCategoryProjection.fetchTargets(page: kendrickPage(), showVideos: false)
        #expect(!withoutVideos.map(\.kind).contains(.videos))
        #expect(targets.first?.params == "params-Songs")
    }

    @Test func snapshotUsesConstantHeightsAndHidesLoadMoreInCategoryView() {
        var input = ProviderSearchCategoryInput()
        input.chipPages[.songs] = SearchPageRecord(chips: [], correction: nil, sections: [
            section("s", items: (0..<12).map { card("song", "s\($0)", "Song \($0)") }, songs: (0..<12).map { song("s\($0)") })
        ], continuation: nil)
        let snapshot = ProviderSearchPageSnapshot()
        snapshot.prepare(page: kendrickPage(), revision: 1, expanded: [], loading: false, error: nil, loadingMore: false,
                         localization: "es", categories: input)
        let kinds = snapshot.entries.map(\.kind)
        #expect(kinds.contains(.grid) && kinds.contains(.carousel))
        #expect(snapshot.entries.first { $0.kind == .grid }?.height == ProviderSearchCategoryLayout.gridHeight)
        #expect(snapshot.entries.first { $0.kind == .carousel }?.height == ProviderSearchCategoryLayout.carouselHeight)
        #expect(!snapshot.entries.contains { "\($0.id)" == "more" }, "categories are complete; «Show all» replaces paging")

        snapshot.prepare(page: kendrickPage(), revision: 1, expanded: [], loading: false, error: nil, loadingMore: false, localization: "es")
        #expect(snapshot.entries.contains { "\($0.id)" == "more" }, "the provider list still pages")
    }

    @Test func columnsFollowTheWidthButTheGridAlwaysHasThreeRows() {
        #expect(ProviderSearchCategoryLayout.columns(for: 1_098) == 3)
        #expect(ProviderSearchCategoryLayout.columns(for: 618) == 2)
        #expect(ProviderSearchCategoryLayout.columns(for: 400) == 1)
        #expect(ProviderSearchCategoryLayout.gridRows == 3)
    }

    /// The row height is fixed, so the content must fit it; a taller card would overlap the next section.
    @Test func carouselCardsFitTheirFixedHeightEvenWithTwoLineTitleAndSubtitle() {
        for kind in ["album", "artist", "playlist"] {
            let long = card(kind, "x", "A very long title that needs two full lines in a narrow card",
                            "A very long subtitle that also needs two full lines in a narrow card")
            let view = ProviderSearchCarouselCard(card: long, isActive: false, isPlaying: false,
                onOpen: {}, onPlay: {}, menuProvider: { nil })
                .frame(width: 160)
                .padding(.vertical, 6)
                .fixedSize(horizontal: false, vertical: true)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 160, height: 1_000)
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize.height > 200, "the probe must really measure the card (\(host.fittingSize.height))")
            #expect(host.fittingSize.height <= ProviderSearchCategoryLayout.carouselHeight,
                    "\(kind) card needs \(host.fittingSize.height)pt but the row is \(ProviderSearchCategoryLayout.carouselHeight)pt")
        }
    }
}
