import AppKit
import Foundation
import Testing
import SideBCore
@testable import SideB

private func featuredRecord(_ kind: String, _ id: String) -> HomeItemRecord {
    HomeItemRecord(kind: kind, id: id, title: id, subtitle: nil, thumbnail: nil,
        duration: nil, artists: nil, artistId: nil, album: nil, albumId: nil, artistRuns: [], explicit: false)
}

private func featuredSections(_ records: [(String, [HomeItemRecord])]) -> [HomeSectionPresentation] {
    HomePresentationFactory.sections(from: records.map {
        HomeSectionRecord(title: $0.0, format: .largeCards, items: $0.1,
                          moreBrowseId: "VL-more", moreParams: "params")
    }, chip: nil)
}

@Test func featuredUsesPersonalizedPrioritiesAndCanonicalProviderOrder() {
    let sections = featuredSections([
        ("New releases", [featuredRecord("album", "generic")]),
        ("Listen again", [featuredRecord("song", "recent"), featuredRecord("album", "recent-album")]),
        ("Selecciones rápidas", [featuredRecord("song", "pick-2"), featuredRecord("song", "pick-1")]),
        ("Álbumes para ti", [featuredRecord("album", "recommended")])
    ])
    let result = HomeFeaturedPresentation.make(from: sections)
    #expect(result.songs.map(\.id) == ["pick-2", "pick-1", "recent"])
    #expect(result.collections.map(\.id) == ["recommended", "recent-album", "generic"])
    #expect(result.collectionKind == .albums)
}

@Test func featuredBoundsUniqueItemsAndPreservesUnselectedShelfActions() {
    let songs = (0..<40).map { featuredRecord("song", "song-\($0)") }
    let albums = (0..<10).map { featuredRecord("album", "album-\($0)") }
    let sections = featuredSections([
        ("Quick picks", songs + [songs[0], featuredRecord("song", "")]),
        ("Albums for you", albums),
        ("Listen again", [songs[0], albums[0], featuredRecord("playlist", "mix")])
    ])
    let result = HomeFeaturedPresentation.make(from: sections)
    #expect(result.songs.count == 27)
    #expect(result.collections.count == 10)
    #expect(Set(result.songs.map(\.id)).count == 27)
    let remaining = result.remainingSections.flatMap(\.items).map(\.record)
    #expect(!remaining.contains(songs[0]))
    #expect(!remaining.contains(albums[0]))
    #expect(remaining.contains(featuredRecord("playlist", "mix")))
    #expect(remaining.contains(songs[39]))
    #expect(result.remainingSections.allSatisfy { $0.moreBrowseId == "VL-more" && $0.moreParams == "params" })
}

@Test func featuredHandlesPartialAndMixedFeedsWithoutFabricatingCards() {
    let playlist = featuredRecord("playlist", "same-id")
    let song = featuredRecord("song", "same-id")
    let sections = featuredSections([("Custom recommendations", [playlist, song])])
    let result = HomeFeaturedPresentation.make(from: sections)
    #expect(result.songs == [song])
    #expect(result.collections.isEmpty)
    #expect(result.remainingSections.flatMap(\.items).map(\.record) == [playlist])
    #expect(HomeFeaturedPresentation.make(from: []).songs.isEmpty)
}

@Test func featuredPaletteKeepsOnlyDistinctAvailableCovers() {
    var first = featuredRecord("album", "a")
    first.thumbnail = "cover-a"
    var second = featuredRecord("album", "b")
    second.thumbnail = "cover-a"
    var song = featuredRecord("song", "s")
    song.thumbnail = "cover-b"
    let result = HomeFeaturedPresentation(songs: [song], collections: [first, second], collectionKind: .albums, remainingSections: [])
    #expect(result.ambientThumbnails == ["cover-a", "cover-b"])
}

@Test func featuredPaletteSamplesAlbumAndSongCoversBeforeFillingRemainingCandidates() {
    var firstAlbum = featuredRecord("album", "album-a")
    firstAlbum.thumbnail = "cover-album-a"
    var secondAlbum = featuredRecord("album", "album-b")
    secondAlbum.thumbnail = "cover-album-b"
    var firstSong = featuredRecord("song", "song-a")
    firstSong.thumbnail = "cover-song-a"
    var secondSong = featuredRecord("song", "song-b")
    secondSong.thumbnail = "cover-song-b"

    let result = HomeFeaturedPresentation(songs: [firstSong, secondSong], collections: [firstAlbum, secondAlbum], collectionKind: .albums, remainingSections: [])

    #expect(result.ambientThumbnails == ["cover-album-a", "cover-album-b", "cover-song-a", "cover-song-b"])
}

@Test func featuredPlaylistsPrioritizePersonalMixesAndPreserveProviderOrder() {
    let sections = featuredSections([
        ("New recommendations", [featuredRecord("playlist", "generic")]),
        ("From your library", [featuredRecord("playlist", "library")]),
        ("Listen again", [featuredRecord("playlist", "recent"), featuredRecord("album", "recent-album")]),
        ("Mixed for you", [featuredRecord("playlist", "mix-2"), featuredRecord("playlist", "mix-1")]),
        ("Forgotten favorites", [featuredRecord("playlist", "forgotten")])
    ])
    let result = HomeFeaturedPresentation.make(from: sections, collectionKind: .playlists)
    #expect(result.collections.map(\.id) == ["mix-2", "mix-1", "recent", "forgotten", "library", "generic"])
    #expect(result.collectionKind == .playlists)
    #expect(result.remainingSections.flatMap(\.items).map(\.record) == [featuredRecord("album", "recent-album")])
}

@Test func featuredPlaylistsBoundDeduplicatedCardsWithoutReplacingMissingPlaylists() {
    let mixes = (0..<9).map { featuredRecord("playlist", "mix-\($0)") }
    let album = featuredRecord("album", "mix-0")
    let song = featuredRecord("song", "mix-0")
    let sections = featuredSections([
        ("  MÍXES PERSONALIZADOS  ", [mixes[0], mixes[0], featuredRecord("playlist", "")] + Array(mixes.dropFirst())),
        ("Listen again", [mixes[0], album, song])
    ])
    let result = HomeFeaturedPresentation.make(from: sections, collectionKind: .playlists)
    #expect(result.collections == Array(mixes.prefix(9)))
    #expect(result.songs == [song])
    let remaining = result.remainingSections.flatMap(\.items).map(\.record)
    #expect(remaining.contains(album))
    #expect(!remaining.contains(mixes[8]))
    #expect(!remaining.contains(mixes[0]))
    #expect(result.remainingSections.allSatisfy { $0.moreBrowseId == "VL-more" && $0.moreParams == "params" })

    let noPlaylists = HomeFeaturedPresentation.make(
        from: featuredSections([("Albums for you", [album, song])]), collectionKind: .playlists)
    #expect(noPlaylists.collections.isEmpty)
    #expect(noPlaylists.collectionKind == .playlists)
    #expect(noPlaylists.remainingSections.flatMap(\.items).map(\.record) == [album])
}

@Test func featuredChangingModeRestoresTheOtherCollectionWithoutLosingItems() {
    let album = featuredRecord("album", "a")
    let playlist = featuredRecord("playlist", "p")
    let song = featuredRecord("song", "s")
    let sections = featuredSections([("Mixed feed", [album, playlist, song])])
    let albums = HomeFeaturedPresentation.make(from: sections)
    let playlists = HomeFeaturedPresentation.make(from: sections, collectionKind: .playlists)
    #expect(albums.collections == [album])
    #expect(playlists.collections == [playlist])
    #expect(albums.remainingSections.flatMap(\.items).map(\.record) == [playlist])
    #expect(playlists.remainingSections.flatMap(\.items).map(\.record) == [album])
    #expect(albums.songs == playlists.songs)
    #expect(HomeFeaturedPresentation.make(from: sections, collectionKind: .albums) == albums)
    #expect(sections.flatMap(\.items).map(\.record) == [album, playlist, song])
    #expect(HomeFeaturedPresentation.make(from: []) == .empty)
}

@Test func featuredPlaylistPaletteUsesPlaylistCoversWithTheSameBounds() {
    var playlist = featuredRecord("playlist", "mix")
    playlist.thumbnail = "cover-playlist"
    var song = featuredRecord("song", "s")
    song.thumbnail = "cover-song"
    let result = HomeFeaturedPresentation.make(
        from: featuredSections([("Mixed for you", [playlist, song])]), collectionKind: .playlists)
    #expect(result.ambientThumbnails == ["cover-playlist", "cover-song"])
}

@Test func featuredLayoutMatchesPanelsAndCollectionCardsFollowTheWidth() {
    var heights = Set<CGFloat>()
    for width: CGFloat in [640, 899, 900, 1100, 1600, 2500] {
        let layout = HomeFeaturedLayout(width: width, hasSongs: true, hasAlbums: true)
        let row = HomeCollectionRowLayout(width: width)
        #expect(layout.albumColumnWidth == row.cardWidth)
        #expect(layout.albumColumnWidth == HomeCollectionRowLayout.fixedCardWidth)
        #expect(layout.songWidth == width - 56)
        // Tarjeta = ancho + 121 de panel; el carril añade 8 pt de aire arriba y 48 abajo.
        #expect(layout.albumCardHeight == row.cardWidth + 121)
        #expect(layout.albumContentHeight == layout.albumCardHeight + 8 + 48)
        #expect(layout.songGridHeight == 448)
        #expect(layout.songPanelHeight == CGFloat(46 + 448))
        // Encabezado y carril van pegados: los 8 pt de aire superior son la separación de siempre.
        #expect(layout.albumPanelHeight == 38 + layout.albumContentHeight)
        #expect(layout.totalHeight == layout.songPanelHeight + layout.albumPanelHeight + 30)
        heights.insert(layout.totalHeight)
    }
    #expect(heights.count == 1, "La altura de la fila de colecciones con ancho fijo es constante")
    #expect(HomeFeaturedLayout.height(width: 1000, hasSongs: false, hasAlbums: false) == 0)
}

@Test func featuredLayoutLeavesFortyEightPointsBelowTheCardAndHonoursTheSidebarInset() {
    for width: CGFloat in [700, 1100, 1800] {
        let layout = HomeFeaturedLayout(width: width, hasSongs: false, hasAlbums: true)
        // Del borde inferior de la tarjeta al final del bloque (= la sección siguiente del feed): 48 pt.
        let cardBottom = HomeFeaturedLayout.headerHeight + 8 + layout.albumCardHeight
        #expect(layout.totalHeight - cardBottom == 48)
        let open = HomeFeaturedLayout(width: width, hasSongs: false, hasAlbums: true, trailingInset: 0)
        #expect(open.albumColumnWidth == HomeCollectionRowLayout(width: width, trailingInset: 0).cardWidth)
    }
}

@Test func featuredMosaicKeepsThreeRowsEvenWithFewSongs() {
    // El mosaico mide 448 aunque haya menos de tres canciones (Windows: `.space { height: 448px }`).
    for count in 1...27 {
        let layout = HomeFeaturedLayout(width: 700, hasSongs: true, hasAlbums: true, songCount: count, albumCount: 1)
        #expect(layout.songGridHeight == HomeMosaicMetrics.totalHeight)
        #expect(layout.songGridHeight == 448)
        #expect(layout.albumContentHeight == layout.albumCardHeight + 8 + 48)
    }
    #expect(HomeFeaturedLayout(width: 700, hasSongs: false, hasAlbums: true).songGridHeight == 0)
}

@Test func featuredVisibleMetadataRangeFollowsOffsetAndExcludesGaps() {
    let ids = (0..<36).map(String.init)
    func visible(offset: CGFloat, width: CGFloat = 900, leading: CGFloat = 28, trailing: CGFloat = 28) -> [String] {
        HomeCollectionRowViewport.visibleIDs(ids: ids, cardWidth: 200, spacing: 24, offset: offset, width: width,
                                             leadingInset: leading, trailingInset: trailing)
    }
    // En reposo: tarjetas 0...3 caben en 900 - 56 de área útil (paso 224).
    #expect(visible(offset: 0) == ["0", "1", "2", "3"])
    // Con la fila desplazada una tarjeta entera, la 0 sale y entra la 4.
    #expect(visible(offset: 224) == ["1", "2", "3", "4"])
    // A mitad de camino se ven, parcialmente, `count + 1` tarjetas.
    #expect(visible(offset: 112) == ["0", "1", "2", "3", "4"])
    // Sin reproductor lateral la última tarjeta llega hasta el borde.
    #expect(visible(offset: 0, trailing: 0).count >= 4)
    #expect(visible(offset: 0, width: 0).isEmpty)
}

@Test func collectionRequestOrderPutsVisibleCardsFirstThenTheRestInRowOrder() {
    let ids = ["a", "b", "c", "d", "e", "f"]
    #expect(HomeCollectionRequestOrder.order(ids, visible: ["d", "e"], id: { $0 }) == ["d", "e", "a", "b", "c", "f"])
    // Visibles en cualquier orden y con IDs ajenos: se respeta el orden de la fila.
    #expect(HomeCollectionRequestOrder.order(ids, visible: ["e", "zzz", "d"], id: { $0 }) == ["d", "e", "a", "b", "c", "f"])
    #expect(HomeCollectionRequestOrder.order(ids, visible: [], id: { $0 }) == ids)
}

@MainActor
@Test func homeNativeCollectionViewPreservesMosaicContentWidthOnResize() {
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    let collection = HomeNativeCollectionView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    let mosaicLayout = HomeMosaicCollectionLayout()
    let mosaic = HomeMosaicLayout(cells: [], columns: 10)
    mosaicLayout.update(mosaic: mosaic, leadingInset: 28, trailingInset: 28)
    collection.collectionViewLayout = mosaicLayout
    scroll.documentView = collection

    let contentWidth = mosaicLayout.collectionViewContentSize.width
    #expect(contentWidth > 400)

    // NSClipView shrinks the document view width down to clip bounds (400) during autoresizing
    collection.setFrameSize(NSSize(width: 400, height: 400))
    #expect(collection.frame.width == contentWidth)
    #expect(collection.frame.width >= contentWidth)
}
