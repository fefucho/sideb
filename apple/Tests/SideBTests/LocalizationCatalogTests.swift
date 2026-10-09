import Foundation
import Testing
import SideBCore
@testable import SideB

private actor CatalogFetchCounter {
    private(set) var value = 0
    func record() { value += 1 }
}

private func catalogPlaylistItem() -> HomeItemRecord {
    HomeItemRecord(kind: "playlist", id: "VLcached-playlist", title: "Original playlist title",
        subtitle: "2 songs", thumbnail: nil, duration: nil, artists: "Original creator",
        artistId: "UCcreator", album: nil, albumId: nil, artistRuns: [], explicit: false)
}

private func catalogPlaylistDetail() -> PlaylistDetailRecord {
    PlaylistDetailRecord(id: "VLcached-playlist", title: "Original playlist title", subtitle: "2 songs",
        thumbnail: nil, description: nil, items: [], continuation: nil, owned: false,
        inLibrary: false, privacy: nil, collaborative: false, sort: nil, sortEditable: false)
}

private func catalogAlbumItem() -> HomeItemRecord {
    HomeItemRecord(kind: "album", id: "MPREcached-album", title: "Original album title",
        subtitle: "2024", thumbnail: nil, duration: nil, artists: "Original artist",
        artistId: "UCartist", album: nil, albumId: nil, artistRuns: [], explicit: false)
}

private func catalogAlbumDetail() -> AlbumDetailRecord {
    let tracks = (0..<2).map { index in
        SongItemRecord(videoId: "track-\(index)", title: "Original song \(index)", artists: "Original artist",
            album: "Original album title", duration: "1:00", thumbnail: nil, artistId: "UCartist",
            albumId: "MPREcached-album", setVideoId: nil, isVideo: false, isUpload: false,
            library: nil, artistRuns: [])
    }
    return AlbumDetailRecord(browseId: "MPREcached-album", title: "Original album title", artist: "Original artist",
        artistId: "UCartist", subtitle: "2024", secondSubtitle: nil, description: nil, thumbnail: nil,
        playlistId: nil, inLibrary: false, items: tracks, sections: [])
}

@Test @MainActor func cachedCollectionSummariesChangeLanguageWithoutChangingProviderRecordsOrFetchingAgain() async {
    let previous = L10n.language
    defer { AppLanguageStore.shared.setLanguage(previous) }
    AppLanguageStore.shared.setLanguage(.es)

    let playlistModel = HomePlaylistMetadataModel()
    let playlistItem = catalogPlaylistItem()
    let playlistCounter = CatalogFetchCounter()
    await playlistModel.load(items: [playlistItem], sessionKey: "catalog-locale-test") { _ in
        await playlistCounter.record()
        return catalogPlaylistDetail()
    }
    let spanishPlaylist = playlistModel.display(for: playlistItem)
    #expect(spanishPlaylist.title == "Original playlist title")
    #expect(spanishPlaylist.summary == "Lista de reproducción • 2 canciones")

    AppLanguageStore.shared.setLanguage(.en)
    let englishPlaylist = playlistModel.display(for: playlistItem)
    #expect(englishPlaylist.title == "Original playlist title")
    #expect(englishPlaylist.summary == "Playlist • 2 songs")
    #expect(await playlistCounter.value == 1)
    #expect(playlistItem.id == "VLcached-playlist")
    #expect(playlistItem.title == "Original playlist title")

    AppLanguageStore.shared.setLanguage(.es)
    let albumModel = HomeAlbumMetadataModel()
    let albumItem = catalogAlbumItem()
    let albumCounter = CatalogFetchCounter()
    await albumModel.load(items: [albumItem], sessionKey: "catalog-locale-test") { _ in
        await albumCounter.record()
        return catalogAlbumDetail()
    }
    let spanishAlbum = albumModel.display(for: albumItem)
    #expect(spanishAlbum.title == "Original album title")
    #expect(spanishAlbum.summary == "Álbum • 2024 • 2 canciones • 2 min")

    AppLanguageStore.shared.setLanguage(.en)
    let englishAlbum = albumModel.display(for: albumItem)
    #expect(englishAlbum.title == "Original album title")
    #expect(englishAlbum.summary == "Album • 2024 • 2 songs • 2 min")
    #expect(await albumCounter.value == 1)
    #expect(albumItem.id == "MPREcached-album")
    #expect(albumItem.title == "Original album title")
}

@Test @MainActor func explorationLocaleChangesDisplayOnlyAndKeepsRegionRoutesAndQueriesStable() {
    let previous = L10n.language
    defer { AppLanguageStore.shared.setLanguage(previous) }
    AppLanguageStore.shared.setLanguage(.es)
    let localSource = ExploreRoute.chartCountry("UY").source
    let globalSource = ExploreRoute.chartCountry("ZZ").source
    let categorySource = ExploreRoute.category("rock").source
    let categoryQuery = ExploreCategory.find("rock")?.query

    AppLanguageStore.shared.setLanguage(.en)
    #expect(ExploreRoute.chartCountry("UY").source == localSource)
    #expect(ExploreRoute.chartCountry("ZZ").source == globalSource)
    #expect(ExploreRoute.category("rock").source == categorySource)
    #expect(ExploreRoute.category("rock").source == .playlists("rock"))
    #expect(ExploreCategory.find("rock")?.query == categoryQuery)
    #expect(ExploreChartRegion.name("UY") == Locale(identifier: "en").localizedString(forRegionCode: "UY"))
    #expect(ExploreChartRegion.name("ZZ") == "Global")
}

@Test func searchFilterDisplayTitlesDoNotChangeRawValuesOrIdentity() {
    #expect(SearchFilter.all.rawValue == "Todo")
    #expect(SearchFilter.songs.rawValue == "Canciones")
    #expect(SearchFilter.playlists.rawValue == "Playlists")
    #expect(SearchFilter.all.id == "Todo")
    #expect(SearchFilter.playlists.id == "Playlists")
    #expect(SearchCategory.playlists.id == "Playlists")
}

@Test @MainActor func homeProviderChipPresentationTranslatesOnlyExactKnownLabels() {
    let previous = L10n.language
    defer { AppLanguageStore.shared.setLanguage(previous) }
    let providerRecord = HomeChipRecord(title: "Relax", params: "mood:relax")
    AppLanguageStore.shared.setLanguage(.es)
    #expect(HomeView.localizedChipTitle(providerRecord.title) == "Relajación")
    #expect(HomeView.localizedChipTitle("Quick picks") == "Selecciones rápidas")
    #expect(HomeView.localizedChipTitle("Relaxing Mixes") == "Relaxing Mixes")
    #expect(providerRecord.title == "Relax")
    #expect(providerRecord.params == "mood:relax")

    AppLanguageStore.shared.setLanguage(.en)
    #expect(HomeView.localizedChipTitle(providerRecord.title) == "Relax")
    #expect(HomeView.localizedChipTitle("Quick picks") == "Quick picks")
}

@Test @MainActor func aggregatedLibraryErrorSectionLabelsFollowCurrentLanguage() {
    let previous = L10n.language
    defer { AppLanguageStore.shared.setLanguage(previous) }
    let descriptor = LibraryViewModel.aggregateLoadErrorDescriptor([
        LibraryLoadFailure(section: .albums, detail: "offline"),
        LibraryLoadFailure(section: .playlists, detail: "unavailable")
    ])

    AppLanguageStore.shared.setLanguage(.es)
    #expect(descriptor?.text == "Listas: unavailable\nÁlbumes: offline")
    AppLanguageStore.shared.setLanguage(.en)
    #expect(descriptor?.text == "Playlists: unavailable\nAlbums: offline")
}
