import Foundation
import Observation
import SideBCore

@MainActor
@Observable
final class AlbumDetailViewModel {
    var album: AlbumDetailRecord?
    var isLoading: Bool = false
    var errorMessage: String?

    init() {}

    func loadAlbum(core: SideBCore, browseId: String) async {
        self.isLoading = true
        self.errorMessage = nil
        do {
            let detail = try await core.getAlbum(browseId: browseId)
            self.album = detail
        } catch {
            print("[AlbumDetailViewModel] Error al cargar álbum \(browseId): \(error)")
            self.errorMessage = error.localizedDescription
        }
        self.isLoading = false
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
