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
    var isChangingOrder: Bool = false
    var errorMessage: String?
    var searchQuery: String = ""
    var selectedOrder: DetailTrackOrder = .custom
    var isCompletingCatalog: Bool = false
    public static var recentlyLikedTracks: [SongItemRecord] = []
    @ObservationIgnored private var loadGeneration: UInt = 0
    @ObservationIgnored private var projectionGeneration: UInt = 0
    @ObservationIgnored private var orderMutationID: UUID?
    @ObservationIgnored private var moveMutationID: UUID?
    @ObservationIgnored private var catalogTracks: [SongItemRecord]?
    @ObservationIgnored private var catalogPlaylistID: String?
    @ObservationIgnored private var projectionCacheTracks: [SongItemRecord]?
    @ObservationIgnored private var projectionCacheQuery: String?
    @ObservationIgnored private var projectionCacheOrder: DetailTrackOrder?
    @ObservationIgnored private var cachedDisplayedEntries: [DetailTrackEntry] = []

    private var sourceTracks: [SongItemRecord] {
        guard let playlist, catalogPlaylistID == playlist.id, let catalogTracks else { return playlist?.items ?? [] }
        return catalogTracks
    }

    var displayedEntries: [DetailTrackEntry] {
        let tracks = sourceTracks
        if projectionCacheTracks == tracks, projectionCacheQuery == searchQuery, projectionCacheOrder == selectedOrder {
            return cachedDisplayedEntries
        }
        let result = DetailTrackProjection.make(tracks: tracks, query: searchQuery, order: selectedOrder)
        projectionCacheTracks = tracks
        projectionCacheQuery = searchQuery
        projectionCacheOrder = selectedOrder
        cachedDisplayedEntries = result
        return result
    }
    var displayedTracks: [SongItemRecord] { displayedEntries.map(\.track) }
    var canReorderDisplayedTracks: Bool {
        guard let playlist, playlist.owned, playlist.sortEditable,
              MenuIDNormalizer.canonicalPlaylistId(playlist.id) != "LM",
              (playlist.sort == nil || playlist.sort == "default"),
              playlist.continuation?.isEmpty != false,
              searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              selectedOrder == .custom, !isMovingTrack, !isChangingOrder,
              !isLoadingMore, !isCompletingCatalog,
              !displayedEntries.isEmpty else { return false }
        let ids = displayedEntries.compactMap { $0.track.setVideoId }.filter { !$0.isEmpty }
        return ids.count == displayedEntries.count && Set(ids).count == ids.count
    }

    @ObservationIgnored private let playlistCatalog: PlaylistCatalog

    init(playlistCatalog: PlaylistCatalog = .shared) { self.playlistCatalog = playlistCatalog }

    var needsCompletePlaybackOrder: Bool {
        switch selectedOrder {
        case .title, .artist, .album, .duration: playlist?.continuation?.isEmpty == false
        default: false
        }
    }

    private var playbackEntries: [DetailTrackEntry] {
        DetailTrackProjection.make(tracks: sourceTracks, query: "", order: selectedOrder)
    }

    func resetForSession() {
        loadGeneration &+= 1; projectionGeneration &+= 1
        playlist = nil; catalogTracks = nil; catalogPlaylistID = nil
        searchQuery = ""; selectedOrder = .custom; errorMessage = nil
        isCompletingCatalog = false; isLoadingMore = false; inLibrary = false
        isChangingOrder = false; orderMutationID = nil
        isMovingTrack = false; moveMutationID = nil
    }

    func loadPlaylist(core: SideBCore, playlistId: String, forceRefresh: Bool = false) async {
        if let current = self.playlist,
           MenuIDNormalizer.canonicalPlaylistId(current.id) != MenuIDNormalizer.canonicalPlaylistId(playlistId) {
            resetForSession()
        }
        projectionGeneration &+= 1
        catalogTracks = nil
        catalogPlaylistID = nil
        isCompletingCatalog = false
        isLoadingMore = false
        if forceRefresh { playlistCatalog.invalidate(playlistId) }
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
            if self.playlist == nil {
                switch detail.sort {
                case "newest": selectedOrder = .recentlyAdded
                case "oldest": selectedOrder = .oldestAdded
                case "title": selectedOrder = .title
                case "artist": selectedOrder = .artist
                case "album": selectedOrder = .album
                default: break
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
        catalogTracks = nil
        catalogPlaylistID = nil
    }

    func loadMore(core: SideBCore) async {
        guard !isCompletingCatalog, !isMovingTrack else { return }
        guard let continuation = playlist?.continuation, !continuation.isEmpty, !isLoadingMore else { return }
        let playlistID = playlist?.id
        let generation = loadGeneration
        isLoadingMore = true
        defer { if generation == loadGeneration { isLoadingMore = false } }
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
            guard generation == loadGeneration, playlist?.id == playlistID else { return }
            print("[PlaylistDetailViewModel] Error al cargar continuación: \(error)")
            errorMessage = "No se pudieron cargar más canciones: \(error.localizedDescription)"
        }
    }

    func toggleLibrary(core: SideBCore) async {
        guard let pl = playlist else { return }
        let generation = loadGeneration
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
            guard generation == loadGeneration, playlist?.id == pl.id else { return }
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
        guard let playlist, playlist.owned, playlist.sortEditable,
              MenuIDNormalizer.canonicalPlaylistId(playlist.id) != "LM",
              !isChangingOrder, !isMovingTrack else { return }
        let playlistID = playlist.id
        let generation = loadGeneration
        let mutationID = UUID()
        orderMutationID = mutationID
        isChangingOrder = true
        defer {
            if orderMutationID == mutationID { isChangingOrder = false; orderMutationID = nil }
        }
        playlistCatalog.invalidate(playlist.id)
        try await core.setPlaylistSort(playlistId: playlistID, sort: sort)
        guard generation == loadGeneration, self.playlist?.id == playlistID else { return }
        await loadPlaylist(core: core, playlistId: playlistID, forceRefresh: true)
    }

    func sortIsAvailable(_ order: DetailTrackOrder) -> Bool {
        guard !isChangingOrder, !isMovingTrack else { return false }
        return switch order {
        case .recentlyAdded, .oldestAdded:
            playlist?.owned == true && playlist?.sortEditable == true &&
                playlist.map { MenuIDNormalizer.canonicalPlaylistId($0.id) != "LM" } == true
        case .custom, .title, .artist, .album, .duration: true
        }
    }

    func selectOrder(_ order: DetailTrackOrder, core: SideBCore) async throws {
        guard sortIsAvailable(order) else { return }
        if order == .recentlyAdded || order == .oldestAdded || order == .custom {
            let oldOrder = selectedOrder
            selectedOrder = order
            let serverSort: String? = switch order {
            case .custom: "default"
            case .recentlyAdded: "newest"
            case .oldestAdded: "oldest"
            default: nil
            }
            if let serverSort {
                do { try await setSort(serverSort, core: core) }
                catch { selectedOrder = oldOrder; throw error }
            }
        } else {
            selectedOrder = order
        }
        await prepareDisplayedTracks(core: core)
    }

    func prepareDisplayedTracks(core: SideBCore) async {
        projectionGeneration &+= 1
        let generation = projectionGeneration
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled, generation == projectionGeneration,
              let snapshot = playlist else { return }
        let completesManualOrder = snapshot.owned && snapshot.sortEditable && selectedOrder == .custom &&
            MenuIDNormalizer.canonicalPlaylistId(snapshot.id) != "LM" && (snapshot.sort == nil || snapshot.sort == "default")
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedOrder != .custom || completesManualOrder,
              snapshot.continuation?.isEmpty == false else {
            isCompletingCatalog = false
            return
        }

        // The normal incremental pager owns its continuation while it is active.
        while isLoadingMore {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled, generation == projectionGeneration else { return }
        }
        guard generation == projectionGeneration, loadGeneration > 0 else { return }
        let expectedLoad = loadGeneration
        isCompletingCatalog = true
        errorMessage = nil
        defer { if generation == projectionGeneration { isCompletingCatalog = false } }
        do {
            let complete = try await playlistCatalog.load(id: snapshot.id, core: core, initial: snapshot)
            guard !Task.isCancelled, generation == projectionGeneration,
                  expectedLoad == loadGeneration, playlist?.id == snapshot.id,
                  !isLoadingMore, playlist?.continuation == snapshot.continuation,
                  snapshot.items == Array(complete.items.prefix(snapshot.items.count)) else { return }
            if var current = playlist {
                current.items = complete.items
                current.continuation = nil
                playlist = current
            }
            catalogTracks = complete.items
            catalogPlaylistID = snapshot.id
        } catch {
            guard !Task.isCancelled, generation == projectionGeneration,
                  expectedLoad == loadGeneration, playlist?.id == snapshot.id else { return }
            errorMessage = "No se pudo completar la playlist: \(error.localizedDescription)"
        }
    }

    func playDisplayedTrack(at index: Int, player: PlayerViewModel) {
        guard let entry = displayedEntries[safe: index], let pl = playlist else { return }
        guard !needsCompletePlaybackOrder, !isChangingOrder else {
            errorMessage = "Completando la playlist para reproducir el orden elegido…"
            return
        }
        let entries = playbackEntries
        guard let sourceIndex = entries.firstIndex(where: { $0.originalIndex == entry.originalIndex }) else { return }
        player.playPlaylist(browseId: pl.id, title: pl.title, tracks: entries.map(\.track),
                            startingAt: sourceIndex, continuation: pl.continuation)
    }

    func moveDisplayedTrack(from source: Int, to destination: Int, core: SideBCore) async throws {
        guard canReorderDisplayedTracks,
              let sourceEntry = displayedEntries[safe: source],
              let destinationEntry = displayedEntries[safe: destination],
              let pl = playlist,
              let sourceID = sourceEntry.track.setVideoId,
              let destinationID = destinationEntry.track.setVideoId,
              let canonicalSource = pl.items.firstIndex(where: { $0.setVideoId == sourceID }),
              let canonicalDestination = pl.items.firstIndex(where: { $0.setVideoId == destinationID }) else { return }
        try await moveTrack(from: canonicalSource, to: canonicalDestination, core: core)
    }

    func moveTrack(from source: Int, to destination: Int, core: SideBCore) async throws {
        guard !isMovingTrack, !isChangingOrder, var playlist, playlist.owned, playlist.sortEditable,
              MenuIDNormalizer.canonicalPlaylistId(playlist.id) != "LM",
              playlist.sort == nil || playlist.sort == "default",
              playlist.continuation?.isEmpty != false,
              source >= 0, source < playlist.items.count,
              destination >= 0, destination < playlist.items.count,
              source != destination,
              let setVideoId = playlist.items[source].setVideoId, !setVideoId.isEmpty else { return }

        let original = playlist.items
        let playlistID = playlist.id
        let generation = loadGeneration
        let moved = playlist.items.remove(at: source)
        playlist.items.insert(moved, at: destination)
        let successor = playlist.items.dropFirst(destination + 1).first?.setVideoId
        self.playlist = playlist
        playlistCatalog.invalidate(playlist.id)
        catalogTracks = nil
        catalogPlaylistID = nil
        let mutationID = UUID()
        moveMutationID = mutationID
        isMovingTrack = true
        defer {
            if moveMutationID == mutationID { isMovingTrack = false; moveMutationID = nil }
        }
        do {
            try await core.movePlaylistTrack(
                playlistId: playlistID,
                setVideoId: setVideoId,
                successorSetVideoId: successor
            )
            guard generation == loadGeneration, self.playlist?.id == playlistID else { return }
            await loadPlaylist(core: core, playlistId: playlistID, forceRefresh: true)
        } catch {
            if generation == loadGeneration, self.playlist?.id == playlistID {
                playlist.items = original
                self.playlist = playlist
            }
            throw error
        }
    }

    func removeTrack(track: SongItemRecord, core: SideBCore) async throws {
        guard var pl = playlist, pl.owned,
              MenuIDNormalizer.canonicalPlaylistId(pl.id) != "LM",
              let setVideoId = track.setVideoId, !setVideoId.isEmpty else { return }
        let playlistID = pl.id
        let generation = loadGeneration
        playlistCatalog.invalidate(pl.id)
        catalogTracks = nil
        catalogPlaylistID = nil
        try await core.removeFromPlaylist(
            playlistId: playlistID, videoId: track.videoId, setVideoId: setVideoId
        )
        guard generation == loadGeneration, self.playlist?.id == playlistID else { return }
        playlistCatalog.invalidate(pl.id)
        pl.items.removeAll { $0.setVideoId == setVideoId }
        self.playlist = pl
        catalogTracks = nil
        catalogPlaylistID = nil
        NotificationCenter.default.post(
            name: .sideBPlaylistTrackRemoved, object: nil,
            userInfo: ["playlistId": pl.id, "videoId": track.videoId]
        )
    }

    func playAll(player: PlayerViewModel) {
        guard let pl = playlist, !needsCompletePlaybackOrder, !isChangingOrder else { return }
        let tracks = playbackEntries.map(\.track)
        guard !tracks.isEmpty else { return }
        player.playPlaylist(browseId: pl.id, title: pl.title, tracks: tracks, startingAt: 0, continuation: pl.continuation)
    }

    func shuffle(player: PlayerViewModel) {
        guard let pl = playlist, !needsCompletePlaybackOrder, !isChangingOrder else { return }
        let tracks = playbackEntries.map(\.track)
        guard !tracks.isEmpty else { return }
        player.playPlaylist(browseId: pl.id, title: pl.title, tracks: tracks, startingAt: 0, continuation: pl.continuation, shuffle: true)
    }

    func playTrack(at index: Int, player: PlayerViewModel) {
        guard let items = playlist?.items, index >= 0, index < items.count, let pl = playlist else { return }
        player.playPlaylist(browseId: pl.id, title: pl.title, tracks: items, startingAt: index, continuation: pl.continuation)
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
