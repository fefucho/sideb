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

@Test func featuredLayoutMatchesPanelsAndBoundsArtworkAcrossWindowWidths() {
    for width: CGFloat in [640, 899, 900, 1100, 1600, 2500] {
        let layout = HomeFeaturedLayout(width: width, hasSongs: true, hasAlbums: true)
        #expect(layout.tile == HomeFeaturedLayout.songTileWidth)
        #expect(layout.albumColumnWidth == HomeFeaturedLayout.albumCardWidth)
        #expect(layout.totalHeight == HomeFeaturedLayout(width: 640, hasSongs: true, hasAlbums: true).totalHeight, "Row height must not change while resizing")
        #expect(layout.songWidth == width - 56)
        #expect(layout.albumCardHeight == layout.albumColumnWidth + HomeFeaturedLayout.albumTextHeight)
        #expect(layout.totalHeight == layout.songPanelHeight + layout.albumPanelHeight + 30 + HomeFeaturedLayout.bottomGap)
        #expect(layout.songPanelHeight == CGFloat(448))
        #expect(layout.albumPanelHeight == 46 + layout.albumCardHeight)
    }
    #expect(HomeFeaturedLayout.height(width: 1000, hasSongs: false, hasAlbums: false) == 0)
}

@Test func featuredPartialRecommendationsDoNotReserveEmptyGridRows() {
    for count in 1...27 {
        let layout = HomeFeaturedLayout(width: 700, hasSongs: true, hasAlbums: true, songCount: count, albumCount: 1)
        let rows = CGFloat(min(3, count))
        #expect(layout.songGridHeight == rows * 126 + (rows - 1) * 12)
        #expect(layout.albumContentHeight == layout.albumCardHeight)
    }
}

@Test func featuredVisibleMetadataRangeFollowsOffsetAndExcludesGaps() {
    let ids = (0..<36).map(String.init)
    #expect(HomeFeaturedRailViewport.visibleIDs(ids: ids, itemWidth: 180, rows: 1,
        spacing: 14, offset: 0, width: 400) == ["0", "1", "2"])
    #expect(HomeFeaturedRailViewport.visibleIDs(ids: ids, itemWidth: 180, rows: 1,
        spacing: 14, offset: 1940, width: 400) == ["10", "11", "12"])
    #expect(HomeFeaturedRailViewport.visibleIDs(ids: ids, itemWidth: 180, rows: 1,
        spacing: 14, offset: 181, width: 12).isEmpty)
    #expect(HomeFeaturedRailViewport.visibleIDs(ids: ids, itemWidth: 180, rows: 3,
        spacing: 12, offset: 192, width: 180) == ["3", "4", "5"])
    #expect(HomeFeaturedRailViewport.visibleIDs(ids: ids, itemWidth: 180, rows: 1,
        spacing: 14, offset: 0, width: 0).isEmpty)
}
