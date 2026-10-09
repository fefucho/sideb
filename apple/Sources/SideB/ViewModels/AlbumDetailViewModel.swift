import Foundation
import Observation
import SideBCore

@MainActor
@Observable
final class AlbumDetailViewModel {
    var album: AlbumDetailRecord?
    var isLoading: Bool = false
    private var errorDescriptor: AppMessage?
    var errorMessage: String? {
        get { errorDescriptor?.text }
        set { errorDescriptor = newValue.map { AppMessage(verbatim: $0) } }
    }
    var searchQuery: String = ""
    @ObservationIgnored private var loadGeneration: UInt = 0
    @ObservationIgnored private var projectionCacheTracks: [SongItemRecord]?
    @ObservationIgnored private var projectionCacheQuery: String?
    @ObservationIgnored private var projectionCacheArtistID: String?
    @ObservationIgnored private var projectionCacheArtist: String?
    @ObservationIgnored private var cachedDisplayedEntries: [DetailTrackEntry] = []

    var displayedEntries: [DetailTrackEntry] {
        let tracks = album?.items ?? []
        if projectionCacheTracks == tracks, projectionCacheQuery == searchQuery,
           projectionCacheArtistID == album?.artistId, projectionCacheArtist == album?.artist {
            return cachedDisplayedEntries
        }
        let linkedTracks = tracks.map { track -> SongItemRecord in
            guard track.artistId?.isEmpty != false,
                  !track.artistRuns.contains(where: { $0.id?.isEmpty == false }),
                  let artistID = album?.artistId, !artistID.isEmpty,
                  let artist = album?.artist, !artist.isEmpty,
                  track.displayArtist.compare(artist, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else { return track }
            // Album rows sometimes omit the same artist's link already supplied by their header.
            var linked = track
            linked.artistId = artistID
            return linked
        }
        let result = DetailTrackProjection.make(tracks: linkedTracks, query: searchQuery, order: .custom)
        projectionCacheTracks = tracks
        projectionCacheQuery = searchQuery
        projectionCacheArtistID = album?.artistId
        projectionCacheArtist = album?.artist
        cachedDisplayedEntries = result
        return result
    }
    var displayedTracks: [SongItemRecord] { displayedEntries.map(\.track) }

    init() {}

    func playDisplayedTrack(at index: Int, player: PlayerViewModel) {
        guard let entry = displayedEntries[safe: index], let alb = album else { return }
        player.playAlbum(browseId: alb.browseId, title: alb.title, tracks: alb.items,
                         startingAt: entry.originalIndex, artistBrowseId: alb.artistId)
    }

    func resetForSession() {
        loadGeneration &+= 1
        album = nil; searchQuery = ""; errorMessage = nil
    }

    func loadAlbum(core: SideBCore, browseId: String) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        self.isLoading = true
        self.errorMessage = nil
        do {
            let detail = try await core.getAlbum(browseId: browseId)
            guard generation == loadGeneration else { return }
            self.album = detail
        } catch {
            guard generation == loadGeneration else { return }
            print("[AlbumDetailViewModel] Error al cargar álbum \(browseId): \(error)")
            self.errorDescriptor = AppMessage(verbatim: error.localizedDescription)
        }
        if generation == loadGeneration { self.isLoading = false }
    }

    func playAll(player: PlayerViewModel) {
        guard let items = album?.items, !items.isEmpty, let alb = album else { return }
        player.playAlbum(browseId: alb.browseId, title: alb.title, tracks: items, startingAt: 0, artistBrowseId: alb.artistId)
    }

    func shuffle(player: PlayerViewModel) {
        guard let items = album?.items, !items.isEmpty, let alb = album else { return }
        player.playAlbum(browseId: alb.browseId, title: alb.title, tracks: items, startingAt: 0, artistBrowseId: alb.artistId, shuffle: true)
    }

    func playTrack(at index: Int, player: PlayerViewModel) {
        guard let items = album?.items, index >= 0, index < items.count, let alb = album else { return }
        player.playAlbum(browseId: alb.browseId, title: alb.title, tracks: items, startingAt: index, artistBrowseId: alb.artistId)
    }

    func toggleLibrary(core: SideBCore) async {
        guard var alb = album else { return }
        let generation = loadGeneration
        let newStatus = !alb.inLibrary
        alb.inLibrary = newStatus
        self.album = alb

        let card = BrowseCardRecord(
            kind: "album",
            id: alb.browseId,
            title: alb.title,
            subtitle: alb.artist ?? alb.subtitle,
            thumbnail: alb.thumbnail,
            duration: nil
        )
        let tracks = alb.items
        NotificationCenter.default.post(
            name: .sideBLibraryAlbumToggled,
            object: nil,
            userInfo: [
                "browseId": alb.browseId,
                "inLibrary": newStatus,
                "card": card,
                "tracks": tracks
            ]
        )

        let targetId = MenuIDNormalizer.canonicalPlaylistId(alb.playlistId ?? alb.browseId)
        do {
            try await core.likePlaylist(playlistId: targetId, like: newStatus)
            PlaylistCatalog.shared.invalidate(targetId)
            NotificationCenter.default.post(name: .sideBSongLibraryChanged, object: nil)
        } catch {
            guard generation == loadGeneration else { return }
            print("[AlbumDetailViewModel] Error al cambiar estado en biblioteca: \(error)")
            if var current = self.album, current.browseId == alb.browseId {
                current.inLibrary = !newStatus
                self.album = current
                NotificationCenter.default.post(
                    name: .sideBLibraryAlbumToggled,
                    object: nil,
                    userInfo: [
                        "browseId": alb.browseId,
                        "inLibrary": !newStatus,
                        "card": card,
                        "tracks": tracks
                    ]
                )
            }
        }
    }

    func handleLibraryAlbumToggled(browseId: String, inLibrary: Bool) {
        if var current = self.album, current.browseId == browseId {
            current.inLibrary = inLibrary
            self.album = current
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
