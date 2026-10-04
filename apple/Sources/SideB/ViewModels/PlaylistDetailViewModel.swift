import Foundation
import Observation
import SideBCore

@MainActor
@Observable
final class PlaylistDetailViewModel {
    var playlist: PlaylistDetailRecord?
    var inLibrary: Bool = false
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var isMovingTrack: Bool = false
    var errorMessage: String?
    public static var recentlyLikedTracks: [SongItemRecord] = []
    @ObservationIgnored private var loadGeneration: UInt = 0

    init() {}

    func loadPlaylist(core: SideBCore, playlistId: String, forceRefresh: Bool = false) async {
        if forceRefresh { PlaylistCatalog.shared.invalidate(playlistId) }
        loadGeneration &+= 1
        let generation = loadGeneration
        self.isLoading = self.playlist == nil
        self.errorMessage = nil
        do {
            var detail = try await core.getPlaylist(playlistId: playlistId)
            guard generation == loadGeneration else { return }
            let isUserCached = AppContextMenuFactory.cachedUserPlaylists.contains(where: { $0.id == playlistId || $0.id == detail.id })
            self.inLibrary = detail.inLibrary || detail.owned || isUserCached
            // Si es la lista de Tus Me Gusta ("LM" / "VLLM"), fusionar al frente las pistas recientemente gustadas en sesión
            if playlistId == "LM" || playlistId == "VLLM" {
                for recent in Self.recentlyLikedTracks.reversed() {
                    if !detail.items.contains(where: { $0.videoId == recent.videoId }) {
                        detail.items.insert(recent, at: 0)
                    }
                }
            }
            self.playlist = detail
        } catch {
            guard generation == loadGeneration else { return }
            print("[PlaylistDetailViewModel] Error al cargar playlist \(playlistId): \(error)")
            self.errorMessage = error.localizedDescription
        }
        self.isLoading = false
    }

    func handleLibraryPlaylistToggled(playlistId: String, inLibrary: Bool) {
        if let pl = self.playlist, pl.id == playlistId {
            self.inLibrary = inLibrary
        }
    }

    func handleLikedTrackToggled(track: SongItemRecord, isLiked: Bool) {
        guard var current = self.playlist, current.id == "LM" || current.id == "VLLM" else { return }
        if isLiked {
            if !current.items.contains(where: { $0.videoId == track.videoId }) {
                current.items.insert(track, at: 0)
                Self.recentlyLikedTracks.removeAll(where: { $0.videoId == track.videoId })
                Self.recentlyLikedTracks.insert(track, at: 0)
            }
        } else {
            current.items.removeAll(where: { $0.videoId == track.videoId })
            Self.recentlyLikedTracks.removeAll(where: { $0.videoId == track.videoId })
        }
        self.playlist = current
    }

    func loadMore(core: SideBCore) async {
        guard let continuation = playlist?.continuation, !continuation.isEmpty, !isLoadingMore else { return }
        let playlistID = playlist?.id
        let generation = loadGeneration
        isLoadingMore = true
        do {
            let res = try await core.getPlaylistContinuation(token: continuation)
            guard generation == loadGeneration else { return }
            guard res.continuation != continuation else {
                errorMessage = "La playlist devolvió una continuación repetida"
                isLoadingMore = false
                return
            }
            if var current = self.playlist,
               current.id == playlistID, current.continuation == continuation {
                current.items.append(contentsOf: res.items)
                current.continuation = res.continuation
                self.playlist = current
            }
        } catch {
            print("[PlaylistDetailViewModel] Error al cargar continuación: \(error)")
        }
        isLoadingMore = false
    }

    func toggleLibrary(core: SideBCore) async {
        guard let pl = playlist else { return }
        let newStatus = !inLibrary
        self.inLibrary = newStatus

        let card = BrowseCardRecord(
            kind: "playlist",
            id: pl.id,
            title: pl.title,
            subtitle: pl.subtitle,
            thumbnail: pl.thumbnail,
            duration: nil
        )
        NotificationCenter.default.post(
            name: .sideBLibraryPlaylistToggled,
            object: nil,
            userInfo: ["playlistId": pl.id, "inLibrary": newStatus, "card": card]
        )

        do {
            try await core.likePlaylist(playlistId: pl.id, like: newStatus)
        } catch {
            print("[PlaylistDetailViewModel] Error al actualizar biblioteca: \(error)")
            self.inLibrary = !newStatus
            NotificationCenter.default.post(
                name: .sideBLibraryPlaylistToggled,
                object: nil,
                userInfo: ["playlistId": pl.id, "inLibrary": !newStatus, "card": card]
            )
        }
    }

    func setSort(_ sort: String, core: SideBCore) async throws {
        guard let playlist, playlist.owned, playlist.sortEditable else { return }
        PlaylistCatalog.shared.invalidate(playlist.id)
        try await core.setPlaylistSort(playlistId: playlist.id, sort: sort)
        await loadPlaylist(core: core, playlistId: playlist.id, forceRefresh: true)
    }

    func moveTrack(from source: Int, to destination: Int, core: SideBCore) async throws {
        guard !isMovingTrack, var playlist, playlist.owned,
              playlist.sort == nil || playlist.sort == "default",
              source >= 0, source < playlist.items.count,
              destination >= 0, destination < playlist.items.count,
              source != destination,
              let setVideoId = playlist.items[source].setVideoId, !setVideoId.isEmpty else { return }

        let original = playlist.items
        let moved = playlist.items.remove(at: source)
        playlist.items.insert(moved, at: destination)
        let successor = playlist.items.dropFirst(destination + 1).first?.setVideoId
        self.playlist = playlist
        PlaylistCatalog.shared.invalidate(playlist.id)
        isMovingTrack = true
        defer { isMovingTrack = false }
        do {
            try await core.movePlaylistTrack(
                playlistId: playlist.id,
                setVideoId: setVideoId,
                successorSetVideoId: successor
            )
            await loadPlaylist(core: core, playlistId: playlist.id, forceRefresh: true)
        } catch {
            playlist.items = original
            self.playlist = playlist
            throw error
        }
    }

    func removeTrack(track: SongItemRecord, core: SideBCore) async throws {
        guard var pl = playlist, pl.owned,
              let setVideoId = track.setVideoId, !setVideoId.isEmpty else { return }
        PlaylistCatalog.shared.invalidate(pl.id)
        try await core.removeFromPlaylist(
            playlistId: pl.id, videoId: track.videoId, setVideoId: setVideoId
        )
        PlaylistCatalog.shared.invalidate(pl.id)
        pl.items.removeAll { $0.setVideoId == setVideoId }
        self.playlist = pl
        NotificationCenter.default.post(
            name: .sideBPlaylistTrackRemoved, object: nil,
            userInfo: ["playlistId": pl.id, "videoId": track.videoId]
        )
    }

    func playAll(player: PlayerViewModel) {
        guard let items = playlist?.items, !items.isEmpty, let pl = playlist else { return }
        player.playPlaylist(browseId: pl.id, title: pl.title, tracks: items, startingAt: 0, continuation: pl.continuation)
    }

    func shuffle(player: PlayerViewModel) {
        guard let items = playlist?.items, !items.isEmpty, let pl = playlist else { return }
        player.playPlaylist(browseId: pl.id, title: pl.title, tracks: items, startingAt: 0, continuation: pl.continuation, shuffle: true)
    }

    func playTrack(at index: Int, player: PlayerViewModel) {
        guard let items = playlist?.items, index >= 0, index < items.count, let pl = playlist else { return }
        player.playPlaylist(browseId: pl.id, title: pl.title, tracks: items, startingAt: index, continuation: pl.continuation)
    }
}
