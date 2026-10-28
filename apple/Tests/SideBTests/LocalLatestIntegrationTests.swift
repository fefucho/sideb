import AppKit
import SwiftUI
import SideBCore
import XCTest
@testable import SideB

/// Boundaries introduced by merging the local Mac viewports with latest's content metadata.
@MainActor final class LocalLatestIntegrationTests: XCTestCase {
    private func song(_ id: String = "same", rating: ContentRating = .unknown, occurrence: String? = nil) -> SongItemRecord {
        var song = SongItemRecord(videoId: id, title: "Song", artists: "Artist", album: "Album",
            duration: "3:00", thumbnail: nil, artistId: nil, albumId: nil, setVideoId: occurrence)
        song.contentRating = rating
        return song
    }
    private func card(_ id: String = "same", rating: ContentRating = .unknown) -> BrowseCardRecord {
        BrowseCardRecord(kind: "song", id: id, title: "Song", subtitle: "Artist", thumbnail: nil,
                         duration: "3:00", contentRating: rating)
    }
    private func section(_ cards: [BrowseCardRecord], songs: [SongItemRecord]) -> SearchSectionRecord {
        SearchSectionRecord(id: "top", title: "", layout: "top", items: cards, songs: songs,
            primaryItemIndex: 0, relatedItemIndices: [], moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: [])
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    func testProviderOccurrenceProjectionKeepsRatingAndPlaybackPayloadTogether() throws {
        let record = section([card(rating: .explicit), card(rating: .explicit), card("different", rating: .clean)],
            songs: [song(occurrence: "one"), song(rating: .clean, occurrence: "two"), song("unrelated", rating: .explicit)])
        let prepared = ProviderSearchPreparedSection(record: record, position: 0)
        XCTAssertEqual(prepared.songs[0]?.setVideoId, "one")
        XCTAssertEqual(prepared.songs[0]?.contentRating, .explicit)
        XCTAssertEqual(prepared.songs[1]?.setVideoId, "two")
        XCTAssertEqual(prepared.songs[1]?.contentRating, .clean)
        XCTAssertEqual(prepared.songs[2]?.videoId, "different")
        XCTAssertEqual(prepared.songs[2]?.contentRating, .clean)
        XCTAssertNil(prepared.songs[2]?.setVideoId)
    }

    func testPreviewAndCarouselOnlyEnrichTheSameRecording() throws {
        let entry = SearchSuggestionEntryRecord(id: "suggestion", kind: "song", query: nil, runs: [],
            feedbackToken: nil, card: card(rating: .explicit), song: song(occurrence: "original"))
        XCTAssertEqual(ProviderSearchProjection.song(for: entry)?.contentRating, .explicit)
        XCTAssertEqual(ProviderSearchProjection.results(entries: [entry]).topSongs.first?.setVideoId, "original")
        XCTAssertEqual(ProviderSearchProjection.results(entries: [entry]).topSongs.first?.contentRating, .explicit)
        XCTAssertEqual(ProviderSearchProjection.displayCard(card(), song: song(rating: .clean)).contentRating, .clean)
        XCTAssertEqual(ProviderSearchProjection.displayCard(card(), song: song("different", rating: .explicit)).contentRating, .unknown)
        XCTAssertEqual(ProviderSearchProjection.mergingRating(song(), from: card("different", rating: .clean)).contentRating, .unknown)
    }

    func testNewPrincipalAndRecycledRelatedRowKeepSecondaryBadgeThroughRatingChanges() throws {
        let player = PlayerViewModel()
        func content(_ rating: ContentRating) -> AnyView {
            let track = song(rating: rating)
            let record = section([card(rating: rating)], songs: [track])
            return AnyView(VStack(spacing: 24) {
                ProviderSearchPrincipalView(section: record,
                    roles: ProviderSearchSectionRoles(primaryIndex: 0, relatedIndices: []), width: 580,
                    isExpanded: false, actions: [], onAction: { _ in }, row: { _ in AnyView(EmptyView()) },
                    onToggleRelated: {}, onPlay: { _ in }, onOpen: {}, menuProvider: { nil }, primarySongPayload: track)
                RecommendedTrackRow(track: track, viewModel: player, router: nil).frame(width: 270)
            }.padding(12).preferredColorScheme(.dark))
        }
        let host = NSHostingView(rootView: content(.unknown))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 604, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.orderOut(nil) }
        for rating in [ContentRating.explicit, .unknown, .clean, .explicit] {
            host.rootView = content(rating)
            host.layoutSubtreeIfNeeded()
            for view in descendants(host) { view.layoutSubtreeIfNeeded() }
            let badges = descendants(host).compactMap { $0 as? NativeContentRatingBadge }
            XCTAssertEqual(badges.count, rating == .unknown ? 0 : 2)
            XCTAssertTrue(badges.allSatisfy { $0.rating == rating })
            if rating != .unknown {
                XCTAssertEqual(Set(badges.map(\.fontSize)), Set([CGFloat(11), CGFloat(13)]))
            }
        }
    }
}
