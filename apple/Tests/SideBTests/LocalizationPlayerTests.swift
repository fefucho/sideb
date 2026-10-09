import AppKit
import SideBCore
import XCTest
@testable import SideB

@MainActor
final class LocalizationPlayerTests: XCTestCase {
    private func track(_ id: String = "song", thumbnail: String? = nil) -> SongItemRecord {
        SongItemRecord(videoId: id, title: "United In Grief", artists: "Kendrick Lamar",
                       album: "Mr. Morale & The Big Steppers", duration: "4:15",
                       thumbnail: thumbnail, artistId: "artist", albumId: "album",
                       setVideoId: "set-\(id)", isVideo: false, isUpload: false,
                       library: nil, artistRuns: [])
    }

    private func descendant<T: NSView>(_ type: T.Type, id: String, in view: NSView) -> T? {
        if view.identifier?.rawValue == id || view.accessibilityIdentifier() == id,
           let match = view as? T { return match }
        for child in view.subviews {
            if let match = descendant(type, id: id, in: child) { return match }
        }
        return nil
    }

    func testMissingArtistIsPresentedInCurrentLanguageWithoutChangingSavedSong() throws {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        AppLanguageStore.shared.setLanguage(.es)
        let item = HomeItemRecord(kind: "song", id: "missing-artist", title: "Original title",
            subtitle: nil, thumbnail: nil, duration: nil, artists: nil, artistId: nil,
            album: "Original album", albumId: nil, artistRuns: [], explicit: false)
        let song = SongItemRecord(fromHomeItem: item)
        XCTAssertEqual(song.artists, "")
        let cell = NativeQueueTrackCellView(frame: NSRect(x: 0, y: 0, width: 576, height: 46))
        cell.configure(track: song, index: 0, isCurrentTrack: false, isPlaying: false,
            isLiked: false, hideAlbum: true, showAlbumInSubtitle: true, isReorderable: true, rowHeight: 46)
        let credits = try XCTUnwrap(descendant(NSTextField.self, id: "NativeQueueTrackCredits", in: cell))
        XCTAssertEqual(credits.stringValue, "Varios artistas • Original album")
        AppLanguageStore.shared.setLanguage(.en)
        cell.refreshLocalization()
        XCTAssertEqual(credits.stringValue, "Various artists • Original album")
        XCTAssertEqual(song.artists, "")
        XCTAssertEqual(song.title, "Original title")
        XCTAssertEqual(song.videoId, "missing-artist")
        let known = SongItemRecord(videoId: "known", title: "Song", artists: "Varios artistas",
            album: nil, duration: nil, thumbnail: nil, artistId: nil, albumId: nil,
            setVideoId: nil, isVideo: false, isUpload: false, library: nil)
        XCTAssertEqual(known.displayArtist, "Varios artistas")
    }

    func testConfiguredQueueCellRetitlesControlsWithoutChangingTrackOrRowState() throws {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        AppLanguageStore.shared.setLanguage(.es)

        let cell = NativeQueueTrackCellView(frame: NSRect(x: 0, y: 0, width: 576, height: 46))
        let song = track()
        cell.configure(track: song, index: 0, isCurrentTrack: true, isPlaying: true,
                       isLiked: true, hideAlbum: true, showAlbumInSubtitle: true,
                       isReorderable: true, rowHeight: 46)
        cell.refreshLocalization()
        cell.updateHover(isHovered: true)
        cell.updateSelection(isSelected: true)

        let index = try XCTUnwrap(descendant(NSTextField.self, id: "NativeQueueTrackIndex", in: cell))
        let artwork = try XCTUnwrap(descendant(NSImageView.self, id: "NativeQueueTrackArtwork", in: cell))
        let title = try XCTUnwrap(descendant(NSTextField.self, id: "NativeQueueTrackTitle", in: cell))
        let credits = try XCTUnwrap(descendant(NSTextField.self, id: "NativeQueueTrackCredits", in: cell))
        let like = try XCTUnwrap(descendant(NSButton.self, id: "NativeQueueTrackLike", in: cell))
        let dislike = try XCTUnwrap(descendant(NSButton.self, id: "NativeQueueTrackDislike", in: cell))
        let likeImage = try XCTUnwrap(like.image)
        let dislikeImage = try XCTUnwrap(dislike.image)
        let image = NSImage(size: NSSize(width: 44, height: 44))
        artwork.image = image
        let selectedState = like.isHidden
        let dislikeState = dislike.isHidden

        XCTAssertEqual(like.toolTip, "Quitar de Me gusta")
        XCTAssertEqual(like.accessibilityLabel(), "Quitar de Me gusta")
        XCTAssertEqual(dislike.toolTip, "No me gusta (quitar de la cola)")
        XCTAssertTrue(index.isHidden, "The current-track indicator should remain selected.")

        AppLanguageStore.shared.setLanguage(.en)
        cell.refreshLocalization()

        XCTAssertEqual(like.toolTip, "Unlike")
        XCTAssertEqual(like.accessibilityLabel(), "Unlike")
        XCTAssertEqual(dislike.toolTip, "Dislike (remove from queue)")
        XCTAssertEqual(dislike.accessibilityLabel(), "Dislike; remove from queue")
        XCTAssertTrue(like.image === likeImage)
        XCTAssertTrue(dislike.image === dislikeImage)
        XCTAssertTrue(index.isHidden)
        XCTAssertEqual(like.isHidden, selectedState)
        XCTAssertEqual(dislike.isHidden, dislikeState)
        XCTAssertTrue(artwork.image === image, "Retitling must keep the decoded artwork instance.")
        XCTAssertEqual(title.stringValue, song.title)
        XCTAssertEqual(credits.stringValue, "Kendrick Lamar • Mr. Morale & The Big Steppers")
    }

    func testCatalogErrorsAndMessagesResolveAgainAfterLanguageChange() {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        AppLanguageStore.shared.setLanguage(.es)

        let error = PlaylistCatalogError.pageLimit(7)
        let message = error.appMessage
        XCTAssertEqual(error.localizedDescription, "La lista superó el máximo de 7 páginas.")
        XCTAssertEqual(message.text, "La lista superó el máximo de 7 páginas.")

        AppLanguageStore.shared.setLanguage(.en)
        XCTAssertEqual(error.localizedDescription, "The playlist exceeded the maximum of 7 pages.")
        XCTAssertEqual(message.text, "The playlist exceeded the maximum of 7 pages.")
        if case .pageLimit(let limit) = error { XCTAssertEqual(limit, 7) }
        else { XCTFail("The catalog error case should remain unchanged.") }

        let playbackMessage = AppMessage(key: "player.error.resolveStream", args: ["network timeout"])
        XCTAssertEqual(playbackMessage.text, "Couldn’t resolve the stream: network timeout")
        AppLanguageStore.shared.setLanguage(.es)
        XCTAssertEqual(playbackMessage.text, "Error al resolver la transmisión: network timeout")
    }

    func testMountedTableRetitlesOnlyAvailableRowsAndPreservesScrollSelectionAndCells() throws {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        AppLanguageStore.shared.setLanguage(.es)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 190),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let source = NativeTrackTableView(tracks: (0..<32).map { track("song-\($0)") },
                                          rowHeight: 52, onPlayTrack: { _ in })
        let coordinator = source.makeCoordinator()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 190))
        scroll.hasVerticalScroller = true
        let table = NativeTrackTableViewInternal(frame: NSRect(x: 0, y: 0, width: 640, height: 32 * 52))
        table.headerView = nil
        table.rowHeight = 52
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("l10n-test")))
        table.dataSource = coordinator
        table.delegate = coordinator
        table.coordinator = coordinator
        coordinator.tableView = table
        scroll.documentView = table
        window.contentView = scroll
        table.reloadData()
        table.layoutSubtreeIfNeeded()

        let visibleRows = table.rows(in: table.visibleRect)
        XCTAssertGreaterThan(visibleRows.length, 0)
        let visibleRow = visibleRows.location
        let visibleCell = try XCTUnwrap(table.view(atColumn: 0, row: visibleRow, makeIfNecessary: true) as? NativeTrackCellView)
        let menu = try XCTUnwrap(descendant(NSButton.self, id: "NativeTrackMenu", in: visibleCell))
        let play = try XCTUnwrap(descendant(NSButton.self, id: "NativeTrackThumbnailPlay", in: visibleCell))
        let menuImage = try XCTUnwrap(menu.image)
        let playImage = try XCTUnwrap(play.image)
        XCTAssertEqual(menu.accessibilityLabel(), "Más opciones de la canción")
        XCTAssertEqual(menu.toolTip, "Más opciones de la canción")
        XCTAssertEqual(play.toolTip, "Reproducir canción")

        let selectedRow = min(max(0, visibleRow), table.numberOfRows - 1)
        table.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        let selected = table.selectedRow
        let offset = scroll.contentView.bounds.origin
        let visibleRowsBefore = table.rows(in: table.visibleRect)
        let offscreenCell = table.view(atColumn: 0, row: table.numberOfRows - 1, makeIfNecessary: false)
        XCTAssertNil(offscreenCell, "A far-offscreen row should not be instantiated for localization.")

        AppLanguageStore.shared.setLanguage(.en)
        coordinator.refreshVisibleLocalization(in: table)

        XCTAssertEqual(menu.accessibilityLabel(), "More song options")
        XCTAssertEqual(menu.toolTip, "More song options")
        XCTAssertEqual(play.toolTip, "Play song")
        XCTAssertTrue(menu.image === menuImage)
        XCTAssertTrue(play.image === playImage)
        XCTAssertTrue(table.view(atColumn: 0, row: visibleRow, makeIfNecessary: false) === visibleCell)
        XCTAssertEqual(table.selectedRow, selected)
        XCTAssertEqual(scroll.contentView.bounds.origin, offset)
        XCTAssertEqual(table.rows(in: table.visibleRect), visibleRowsBefore)
        XCTAssertNil(table.view(atColumn: 0, row: table.numberOfRows - 1, makeIfNecessary: false))
    }
}
