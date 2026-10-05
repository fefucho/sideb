import Testing
import AppKit
import SwiftUI
import SideBCore
@testable import SideB

func collectionDetailFixtureTrack(_ id: String = "song") -> SongItemRecord {
    SongItemRecord(videoId: id, title: "United In Grief", artists: "Kendrick Lamar", album: "Mr. Morale",
                   duration: "4:15", thumbnail: nil, artistId: "artist", albumId: "album",
                   setVideoId: "set-\(id)", isVideo: false, isUpload: false, library: nil, artistRuns: [])
}

@Test func collectionHeadersKeepPlaybackAndDropMappedToOccurrences() {
    let tracks = [collectionDetailFixtureTrack(), collectionDetailFixtureTrack(), collectionDetailFixtureTrack("third")]
    let projection = TrackTableRowProjection.make(sections: [TrackTableSection(tracks: tracks)],
                                                hasScrollingHeader: true, hasColumnLabels: true)
    #expect(projection.rows[0] == .scrollingHeader)
    #expect(projection.rows[1] == .columnLabels)
    #expect(TrackTableInteractionPolicy.playbackIndex(for: projection.rows[0], source: .row) == nil)
    #expect(TrackTableInteractionPolicy.playbackIndex(for: projection.rows[3], source: .row) == 1)
    #expect(TrackTableInteractionPolicy.dropDestination(proposedRow: 0, sourceIndex: 2, rows: projection.rows, trackCount: 3) == 0)
    #expect(TrackTableInteractionPolicy.dropDestination(proposedRow: 5, sourceIndex: 0, rows: projection.rows, trackCount: 3) == 2)
    #expect(TrackTableInteractionPolicy.dropDestination(proposedRow: 3, sourceIndex: 2, rows: projection.rows, trackCount: 3) == 1)
}

@Test func collectionColumnsFitAndGiveAlbumsMoreSongSpace() {
    for width: CGFloat in [600, 900, 1400] {
        let playlist = CollectionTrackColumnLayout.make(width: width, height: CollectionTrackMetrics.rowHeight, showsAlbum: true)
        let album = CollectionTrackColumnLayout.make(width: width, height: CollectionTrackMetrics.rowHeight, showsAlbum: false)
        #expect(playlist.artwork.width == 44)
        #expect(playlist.artwork.height == 44)
        #expect(playlist.artwork.midY == CollectionTrackMetrics.rowHeight / 2)
        #expect(playlist.artist.minX > playlist.song.maxX)
        #expect(playlist.album.minX > playlist.artist.maxX)
        #expect(playlist.duration.minX > playlist.album.maxX)
        #expect(playlist.like.minX > playlist.duration.maxX)
        #expect(playlist.menu.maxX <= width - 24)
        #expect(album.song.width > playlist.song.width)
        #expect(album.album.width == 0)
    }
}

@Test @MainActor func collectionScrollHeaderAndLabelsAreNonSelectableRowsOfTheSameTable() {
    let view = NativeTrackTableView(tracks: [collectionDetailFixtureTrack()], presentation: .collectionPlaylist,
                                    rowHeight: CollectionTrackMetrics.rowHeight, onPlayTrack: { _ in },
                                    scrollingHeader: AnyView(Text("Header")), scrollingHeaderHeight: 340)
    let table = NativeTrackTableViewInternal()
    let coordinator = view.makeCoordinator()
    #expect(coordinator.numberOfRows(in: table) == 3)
    #expect(!coordinator.tableView(table, shouldSelectRow: 0))
    #expect(!coordinator.tableView(table, shouldSelectRow: 1))
    #expect(coordinator.tableView(table, shouldSelectRow: 2))
    #expect(coordinator.tableView(table, heightOfRow: 0) == 340)
    #expect(CollectionTrackMetrics.rowHeight == 58)
    #expect(coordinator.tableView(table, heightOfRow: 2) == 58)
    #expect(coordinator.tableView(table, viewFor: nil, row: 0) is NativeTrackFooterCellView)
    #expect(coordinator.tableView(table, viewFor: nil, row: 1) is NativeCollectionColumnsCellView)
    #expect(coordinator.tableView(table, viewFor: nil, row: 2) is NativeCollectionTrackCellView)
}

@Test @MainActor func collectionCreditsAndActionsDoNotPropagatePlayback() async throws {
    let cell = NativeCollectionTrackCellView(showsAlbum: true)
    cell.frame = NSRect(x: 0, y: 0, width: 900, height: CollectionTrackMetrics.rowHeight)
    var played = 0, artists = 0, albums = 0, menus = 0, likes = 0
    cell.onPlay = { played += 1 }; cell.onArtist = { _ in artists += 1 }
    cell.onAlbum = { _ in albums += 1 }; cell.onMenu = { _ in menus += 1 }; cell.onLike = { _ in likes += 1 }
    cell.configure(track: collectionDetailFixtureTrack(), index: 0, isCurrentTrack: true, isPlaying: true, isLiked: false,
                   hideAlbum: false, showAlbumInSubtitle: false, isReorderable: true,
                   rowHeight: CollectionTrackMetrics.rowHeight)
    cell.layoutSubtreeIfNeeded()
    let menu = try #require(cell.subviews.first { $0.accessibilityIdentifier() == "CollectionTrackMenu" } as? NSButton)
    let like = try #require(cell.subviews.first { $0.accessibilityIdentifier() == "CollectionTrackLike" } as? NSButton)
    let play = try #require(cell.subviews.first { $0.accessibilityIdentifier() == "CollectionTrackPlay" } as? NSButton)
    #expect(cell.artist.accessibilityPerformPress())
    #expect(cell.album.accessibilityPerformPress())
    menu.performClick(nil); like.performClick(nil)
    for _ in 0..<5 { await Task.yield() }
    #expect(artists == 1 && albums == 1 && menus == 1 && likes == 1 && played == 0)
    cell.updateHover(isHovered: false); cell.updateCreditFocus(false); cell.updateSelection(isSelected: true)
    #expect(play.isHidden)
    cell.updateHover(isHovered: true)
    #expect(!play.isHidden)
    #expect(play.frame.width == 32)
    #expect(play.frame.height == 32)
    #expect(like.frame.width == 28 && like.frame.height == 28)
    #expect(menu.frame.width == 28 && menu.frame.height == 28)
    #expect(cell.artwork.frame.width == 44 && cell.artwork.frame.height == 44)
    #expect(cell.title.font?.pointSize == 15.5)
    #expect(cell.artist.font?.pointSize == 13.5 && cell.album.font?.pointSize == 13.5)
    #expect(cell.artist.showsHoverHighlight && cell.album.showsHoverHighlight)
    cell.artist.setCreditHovered(true); cell.album.setCreditHovered(true)
    #expect(cell.artist.textColor == .labelColor && cell.album.textColor == .labelColor)
    cell.artist.setCreditHovered(false); cell.album.setCreditHovered(false)
    #expect(cell.artist.textColor == .secondaryLabelColor && cell.album.textColor == .secondaryLabelColor)
    play.performClick(nil)
    #expect(played == 1)
    #expect(cell.title.frame.maxX < cell.artist.frame.minX)
    cell.prepareForReuse()
    #expect(cell.onPlay == nil && cell.onLike == nil && cell.onMenu == nil)
    #expect(play.isHidden)
}

@Test @MainActor func collectionBackgroundFollowsTheDocumentAndCannotInterceptTrackClicks() throws {
    var visibility: [Bool] = []
    let view = NativeTrackTableView(tracks: [collectionDetailFixtureTrack()], presentation: .collectionPlaylist,
                                   onPlayTrack: { _ in }, scrollingHeader: AnyView(Text("Header")),
                                   scrollingHeaderHeight: 340, scrollingBackground: { visible in
                                       visibility.append(visible)
                                       return AnyView(Color.red)
                                   })
    let coordinator = view.makeCoordinator()
    let table = NativeTrackTableViewInternal(frame: NSRect(x: 0, y: 0, width: 900, height: 1500))
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 200))
    scroll.documentView = table
    coordinator.tableView = table
    coordinator.updateScrollingBackground()
    let host = try #require(table.subviews.first as? CollectionBackgroundHostingView)
    #expect(host.frame == NSRect(x: 0, y: 0, width: 900, height: 480))
    #expect(host.hitTest(NSPoint(x: 100, y: 100)) == nil)
    #expect(visibility.last == true)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
    coordinator.updateScrollingBackground()
    #expect(visibility.last == false)
    #expect(table.subviews.first === host)
    #expect(host.frame.origin == .zero)
}

@Test @MainActor func collectionFilteringAndClearingKeepTheHeaderAndRowCacheConsistent() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    for presentation: TrackTablePresentation in [.collectionAlbum, .collectionPlaylist] {
        func view(_ tracks: [SongItemRecord], height: CGFloat) -> NativeTrackTableView {
            NativeTrackTableView(tracks: tracks, presentation: presentation,
                                 rowHeight: CollectionTrackMetrics.rowHeight, onPlayTrack: { _ in },
                                 scrollingHeader: AnyView(Text("Header")), scrollingHeaderHeight: height)
        }
        let all = (0..<94).map { collectionDetailFixtureTrack("song-\($0)") }
        let coordinator = view(all, height: 340).makeCoordinator()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let table = NativeTrackTableViewInternal(frame: scroll.bounds)
        table.headerView = nil
        table.style = .plain
        table.rowHeight = CollectionTrackMetrics.rowHeight
        table.addTableColumn(NSTableColumn(identifier: .init("track")))
        table.dataSource = coordinator; table.delegate = coordinator
        table.coordinator = coordinator; coordinator.tableView = table
        scroll.documentView = table
        window.contentView = scroll
        table.reloadData()
        let header = try #require(table.view(atColumn: 0, row: 0, makeIfNecessary: true))
        let prefix = presentation == .collectionPlaylist ? 2 : 1
        for tracks in [[all[47]], [], all, [], [all[0], all[0]], all] {
            let next = view(tracks, height: tracks.isEmpty ? 400 : 340)
            coordinator.replaceCollectionRows(with: next, in: table)
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: 0))
            table.layoutSubtreeIfNeeded()
            #expect(table.numberOfRows == tracks.count + prefix)
            #expect(coordinator.numberOfRows(in: table) == table.numberOfRows)
            #expect(table.view(atColumn: 0, row: 0, makeIfNecessary: true) === header)
            #expect(coordinator.parent.tracks == tracks)
        }
        coordinator.detachScrollingBackground()
    }
}
