import AppKit
import SwiftUI
import SideBCore
import XCTest
@testable import SideB

@MainActor final class ArtistProfileLayoutTests: XCTestCase {
    func testResolvedSectionsSynthesizesDiscographyEndpointForAlbums() {
        let albumCard = BrowseCardRecord(
            kind: "album",
            id: "MPRE1",
            title: "Album 1",
            subtitle: "2024",
            thumbnail: nil,
            duration: nil
        )
        let albumsSection = ArtistCarouselRecord(
            title: "Albums",
            items: [albumCard],
            moreBrowseId: nil,
            moreParams: nil
        )
        let featuredOnSection = ArtistCarouselRecord(
            title: "Featured on",
            items: [BrowseCardRecord(kind: "playlist", id: "VL1", title: "Playlist 1", subtitle: nil, thumbnail: nil, duration: nil)],
            moreBrowseId: nil,
            moreParams: nil
        )
        let artist = ArtistDetailRecord(
            channelId: "UC123",
            name: "Artist Name",
            thumbnail: nil,
            description: nil,
            subscribers: nil,
            monthlyListeners: nil,
            subscribed: false,
            radioPlaylistId: nil,
            topSongs: [],
            topSongsId: nil,
            sections: [albumsSection, featuredOnSection]
        )

        let resolved = ArtistProfileViewport.resolvedSections(for: artist)
        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved[0].title, "Albums")
        XCTAssertEqual(resolved[0].moreBrowseId, "MPADUC123")
        XCTAssertEqual(resolved[0].moreParams, "ggMIegYIARoCAQI%3D")

        XCTAssertEqual(resolved[1].title, "Featured on")
        XCTAssertNil(resolved[1].moreBrowseId)
        XCTAssertNil(resolved[1].moreParams)
    }

    func testResolvedSectionsSynthesizesDiscographyEndpointForSingles() {
        let singleCard = BrowseCardRecord(
            kind: "album",
            id: "MPRE2",
            title: "Single 1",
            subtitle: "2024",
            thumbnail: nil,
            duration: nil
        )
        let singlesSection = ArtistCarouselRecord(
            title: "Singles & EPs",
            items: [singleCard],
            moreBrowseId: nil,
            moreParams: nil
        )
        let artist = ArtistDetailRecord(
            channelId: "UC123",
            name: "Artist Name",
            thumbnail: nil,
            description: nil,
            subscribers: nil,
            monthlyListeners: nil,
            subscribed: false,
            radioPlaylistId: nil,
            topSongs: [],
            topSongsId: nil,
            sections: [singlesSection]
        )

        let resolved = ArtistProfileViewport.resolvedSections(for: artist)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].title, "Singles & EPs")
        XCTAssertEqual(resolved[0].moreBrowseId, "MPADUC123")
        XCTAssertEqual(resolved[0].moreParams, "ggMIegYIAhoCAQI%3D")
    }

    func testResolvedSectionsLeavesExistingBrowseEndpointIntact() {
        let albumCard = BrowseCardRecord(
            kind: "album",
            id: "MPRE1",
            title: "Album 1",
            subtitle: "2024",
            thumbnail: nil,
            duration: nil
        )
        let albumsSection = ArtistCarouselRecord(
            title: "Albums",
            items: [albumCard],
            moreBrowseId: "CUSTOM_ID",
            moreParams: "CUSTOM_PARAMS"
        )
        let artist = ArtistDetailRecord(
            channelId: "UC123",
            name: "Artist Name",
            thumbnail: nil,
            description: nil,
            subscribers: nil,
            monthlyListeners: nil,
            subscribed: false,
            radioPlaylistId: nil,
            topSongs: [],
            topSongsId: nil,
            sections: [albumsSection]
        )

        let resolved = ArtistProfileViewport.resolvedSections(for: artist)
        XCTAssertEqual(resolved[0].moreBrowseId, "CUSTOM_ID")
        XCTAssertEqual(resolved[0].moreParams, "CUSTOM_PARAMS")
    }
}
