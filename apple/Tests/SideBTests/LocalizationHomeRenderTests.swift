import AppKit
import SideBCore
import XCTest
@testable import SideB

@MainActor
final class LocalizationHomeRenderTests: XCTestCase {
    func testLibraryPlaceholderNamesStayOutOfCachedRecords() throws {
        let previous = L10n.language
        let albums = AppContextMenuFactory.cachedUserAlbums
        let playlists = AppContextMenuFactory.cachedUserPlaylists
        defer {
            AppLanguageStore.shared.setLanguage(previous)
            AppContextMenuFactory.cachedUserAlbums = albums
            AppContextMenuFactory.cachedUserPlaylists = playlists
        }
        AppLanguageStore.shared.setLanguage(.es)
        let library = LibraryViewModel()
        library.handleAlbumToggled(browseId: "missing-album", inLibrary: true, card: nil)
        library.handlePlaylistToggled(playlistId: "missing-playlist", inLibrary: true, card: nil)
        let album = try XCTUnwrap(library.albums.first)
        let playlist = try XCTUnwrap(library.playlists.first)
        XCTAssertEqual(album.displayTitle, "Álbum")
        XCTAssertEqual(playlist.displayTitle, "Lista de reproducción")
        AppLanguageStore.shared.setLanguage(.en)
        XCTAssertEqual(album.displayTitle, "Album")
        XCTAssertEqual(playlist.displayTitle, "Playlist")
        XCTAssertEqual(album.title, "")
        XCTAssertEqual(playlist.title, "")
        XCTAssertEqual(library.albums, [album])
        XCTAssertEqual(library.playlists, [playlist])
        XCTAssertEqual(album.id, "missing-album")
        XCTAssertEqual(playlist.id, "missing-playlist")
    }

    func testMissingAlbumAndArtistNamesRetitleWithoutReplacingArtworkOrRecord() throws {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        AppLanguageStore.shared.setLanguage(.es)
        let record = HomeItemRecord(kind: "album", id: "album-id", title: "", subtitle: nil,
            thumbnail: nil, duration: nil, artists: nil, artistId: nil, album: nil,
            albumId: nil, artistRuns: [], explicit: false)
        let metadata = HomeAlbumMetadata.make(item: record, album: nil)
        let card = HomeItemView(frame: NSRect(x: 0, y: 0, width: 140, height: 234))
        card.configure(record: record, style: .largeCard, currentTrackID: nil, isPlaying: false,
            onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil })
        let title = try XCTUnwrap(card.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Álbum" })
        let artist = try XCTUnwrap(card.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Varios artistas" })
        let images = card.subviews.compactMap { $0 as? NSImageView }
        let artwork = images.map(\.image)
        XCTAssertEqual(metadata.title, "Álbum")
        AppLanguageStore.shared.setLanguage(.en)
        card.refreshLocalization(currentTrackID: nil, currentAlbumBrowseId: nil,
            currentPlaylistBrowseId: nil, isPlaying: false, queueContext: nil)
        XCTAssertEqual(title.stringValue, "Album")
        XCTAssertEqual(artist.stringValue, "Various artists")
        XCTAssertEqual(metadata.title, "Album")
        XCTAssertTrue(zip(images, artwork).allSatisfy { $0.image === $1 })
        XCTAssertEqual(record.title, "")
        XCTAssertEqual(record.id, "album-id")
        let original = HomeItemRecord(kind: "album", id: "named", title: "Álbum", subtitle: nil,
            thumbnail: nil, duration: nil, artists: nil, artistId: nil, album: nil,
            albumId: nil, artistRuns: [], explicit: false)
        XCTAssertEqual(HomeAlbumMetadata.make(item: original, album: nil).title, "Álbum")
    }

    func testShelfHeaderKeepsImagesAndActionsWhenLanguageChanges() throws {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        AppLanguageStore.shared.setLanguage(.es)
        let header = HomeSectionHeaderView(frame: NSRect(x: 0, y: 0, width: 500, height: 36))
        var opened = 0
        header.configure(title: "Original shelf", showsMore: true, showsArrows: true,
            previous: {}, next: {}, action: { opened += 1 })
        let more = try XCTUnwrap(header.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Ver todo" })
        let buttons = header.subviews.compactMap { $0 as? NSButton }
        let images = buttons.map(\.image)
        AppLanguageStore.shared.setLanguage(.en)
        header.refreshLocalization()
        XCTAssertEqual(more.title, "See all")
        XCTAssertEqual(more.accessibilityLabel(), "See all: Original shelf")
        XCTAssertTrue(zip(buttons, images).allSatisfy { $0.image === $1 })
        more.performClick(nil)
        XCTAssertEqual(opened, 1)
    }
}
