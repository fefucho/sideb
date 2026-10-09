import Foundation
import Observation
import SideBCore

enum LibraryLoadErrorSection: String, CaseIterable, Sendable {
    case playlists, albums, history
}

struct LibraryLoadFailure: Equatable, Sendable {
    let section: LibraryLoadErrorSection
    let detail: String
    let message: AppMessage

    init(section: LibraryLoadErrorSection, detail: String) {
        self.section = section
        self.detail = detail
        self.message = AppMessage(key: "library.load_error.\(section.rawValue)", args: [detail])
    }
}

enum LibraryTab: String, CaseIterable, Identifiable {
    case playlists = "Playlists"
    case albums = "Álbumes"

    var id: String { self.rawValue }
    var displayTitle: String { self == .playlists ? L10n.text("library.tab.playlists") : L10n.text("library.tab.albums") }
}

enum LibraryPageTab: String, CaseIterable, Identifiable {
    case songs = "Canciones"
    case playlists = "Playlists"
    case albums = "Álbumes"
    case artists = "Artistas"

    var id: String { rawValue }
    var displayTitle: String {
        switch self {
        case .songs: return L10n.text("search.filter.songs")
        case .playlists: return L10n.text("library.tab.playlists")
        case .albums: return L10n.text("library.tab.albums")
        case .artists: return L10n.text("search.filter.artists")
        }
    }
}

@MainActor
@Observable
final class LibraryViewModel {
    var playlists: [BrowseCardRecord] = []
    var albums: [BrowseCardRecord] = []
    var artists: [BrowseCardRecord] = []
    var songs: [SongItemRecord] = []
    var songsContinuation: String?
    var isSongsLoading = false
    var isSongsLoadingMore = false
    var isArtistsLoading = false
    var songsErrorDescriptor: AppMessage?
    var artistsErrorDescriptor: AppMessage?
    var playlistsErrorDescriptor: AppMessage?
    var albumsErrorDescriptor: AppMessage?
    var songsErrorMessage: String? {
        get { songsErrorDescriptor?.text }
        set { songsErrorDescriptor = newValue.map(AppMessage.init(verbatim:)) }
    }
    var artistsErrorMessage: String? {
        get { artistsErrorDescriptor?.text }
        set { artistsErrorDescriptor = newValue.map(AppMessage.init(verbatim:)) }
    }
    var playlistsErrorMessage: String? {
        get { playlistsErrorDescriptor?.text }
        set { playlistsErrorDescriptor = newValue.map(AppMessage.init(verbatim:)) }
    }
    var albumsErrorMessage: String? {
        get { albumsErrorDescriptor?.text }
        set { albumsErrorDescriptor = newValue.map(AppMessage.init(verbatim:)) }
    }
    var historyGroups: [HistoryGroupRecord] = []
    var selectedTab: LibraryTab = .playlists
    var selectedPageTab: LibraryPageTab = .songs
    var isLoading: Bool = false
    private var libraryLoadFailures: [LibraryLoadFailure] = []
    private var manualErrorDescriptor: AppMessage?
    var errorDescriptor: AppMessage? {
        get { Self.aggregateLoadErrorDescriptor(libraryLoadFailures) ?? manualErrorDescriptor }
        set {
            manualErrorDescriptor = newValue
            libraryLoadFailures = []
        }
    }
    var errorMessage: String? {
        get { errorDescriptor?.text }
        set { errorDescriptor = newValue.map(AppMessage.init(verbatim:)) }
    }
    var isHistoryLoading: Bool = false
    var historyErrorDescriptor: AppMessage?
    var historyErrorMessage: String? {
        get { historyErrorDescriptor?.text }
        set { historyErrorDescriptor = newValue.map(AppMessage.init(verbatim:)) }
    }
    var rustCore: SideBCore? = nil
    @ObservationIgnored private var sessionGeneration: UInt = 0
    @ObservationIgnored private var libraryGeneration: UInt = 0

    init() {
        setupNotificationObservers()
    }

    static func aggregateLoadErrorDescriptor(_ failures: [LibraryLoadFailure]) -> AppMessage? {
        let ordered = LibraryLoadErrorSection.allCases.compactMap { section in
            failures.first(where: { $0.section == section })
        }
        guard !ordered.isEmpty else { return nil }
        let key = "library.load_errors." + ordered.map { $0.section.rawValue }.joined(separator: "_")
        return AppMessage(key: key, args: ordered.map(\.detail))
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .sideBLibraryAlbumToggled,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self,
                  let info = notif.userInfo,
                  let browseId = info["browseId"] as? String,
                  let inLibrary = info["inLibrary"] as? Bool else { return }
            let card = info["card"] as? BrowseCardRecord
            let tracks = info["tracks"] as? [SongItemRecord]
            MainActor.assumeIsolated {
                self.handleAlbumToggled(browseId: browseId, inLibrary: inLibrary, card: card, tracks: tracks)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .sideBLibraryPlaylistToggled,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self,
                  let info = notif.userInfo,
                  let playlistId = info["playlistId"] as? String,
                  let inLibrary = info["inLibrary"] as? Bool else { return }
            let card = info["card"] as? BrowseCardRecord
            MainActor.assumeIsolated {
                self.handlePlaylistToggled(playlistId: playlistId, inLibrary: inLibrary, card: card)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .sideBPlaybackRecorded,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self,
                  let track = notif.userInfo?["track"] as? SongItemRecord else { return }
            MainActor.assumeIsolated {
                self.prependPlayedTrack(track)
            }
        }
    }

    /// Sincroniza la lista de álbumes y canciones en memoria de forma reactiva instantánea
    func handleAlbumToggled(browseId: String, inLibrary: Bool, card: BrowseCardRecord?, tracks: [SongItemRecord]? = nil) {
        if inLibrary {
            if !self.albums.contains(where: { $0.id == browseId }) {
                let newCard = card ?? BrowseCardRecord(kind: "album", id: browseId, title: "", subtitle: nil, thumbnail: nil, duration: nil)
                self.albums.append(newCard)
                self.albums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }
            if let newTracks = tracks, !newTracks.isEmpty {
                let existingIds = Set(self.songs.map { $0.videoId })
                let tracksToAdd = newTracks.filter { !existingIds.contains($0.videoId) }
                self.songs.insert(contentsOf: tracksToAdd, at: 0)
            }
        } else {
            self.albums.removeAll(where: { $0.id == browseId })
            if let removedTracks = tracks, !removedTracks.isEmpty {
                let idsToRemove = Set(removedTracks.map { $0.videoId })
                self.songs.removeAll(where: { idsToRemove.contains($0.videoId) || $0.albumId == browseId })
            } else {
                self.songs.removeAll(where: { $0.albumId == browseId })
            }
        }
        AppContextMenuFactory.cachedUserAlbums = self.albums

        if let core = self.rustCore {
            Task {
                await self.loadSongs(core: core)
            }
        }
    }

    /// Sincroniza la lista de playlists en memoria de forma reactiva instantánea
    func handlePlaylistToggled(playlistId: String, inLibrary: Bool, card: BrowseCardRecord?) {
        if inLibrary {
            if !self.playlists.contains(where: { $0.id == playlistId }) {
                let newCard = card ?? BrowseCardRecord(kind: "playlist", id: playlistId, title: "", subtitle: nil, thumbnail: nil, duration: nil)
                self.playlists.insert(newCard, at: 0)
            }
        } else {
            self.playlists.removeAll(where: { $0.id == playlistId })
        }
        AppContextMenuFactory.cachedUserPlaylists = self.playlists
    }

    /// Alterna el guardado de un álbum desde la biblioteca con rollback en caso de fallo
    func toggleAlbumLibrary(core: SideBCore, browseId: String, playlistId: String?, title: String, subtitle: String?, thumbnail: String?, inLibrary: Bool) async {
        let newStatus = !inLibrary
        let card = BrowseCardRecord(kind: "album", id: browseId, title: title, subtitle: subtitle, thumbnail: thumbnail, duration: nil)
        handleAlbumToggled(browseId: browseId, inLibrary: newStatus, card: card)
        NotificationCenter.default.post(
            name: .sideBLibraryAlbumToggled,
            object: nil,
            userInfo: ["browseId": browseId, "inLibrary": newStatus, "card": card]
        )
        do {
            let pid = playlistId ?? browseId
            try await core.likePlaylist(playlistId: pid, like: newStatus)
            NotificationCenter.default.post(name: .sideBSongLibraryChanged, object: nil)
        } catch {
            print("[LibraryViewModel] Error al alternar álbum en biblioteca: \(error)")
            handleAlbumToggled(browseId: browseId, inLibrary: inLibrary, card: card)
            NotificationCenter.default.post(
                name: .sideBLibraryAlbumToggled,
                object: nil,
                userInfo: ["browseId": browseId, "inLibrary": inLibrary, "card": card]
            )
        }
    }

    /// Recarga la pestaña seleccionada actualmente de la biblioteca
    func reloadSelectedPageTab(core: SideBCore) async {
        switch selectedPageTab {
        case .songs:
            await loadSongs(core: core)
        case .artists:
            await loadArtists(core: core)
        case .playlists, .albums:
            await loadLibrary(core: core)
        }
    }

    /// Alterna el guardado de una playlist desde la biblioteca con rollback en caso de fallo
    func togglePlaylistLibrary(core: SideBCore, playlistId: String, title: String, subtitle: String?, thumbnail: String?, inLibrary: Bool) async {
        let newStatus = !inLibrary
        let card = BrowseCardRecord(kind: "playlist", id: playlistId, title: title, subtitle: subtitle, thumbnail: thumbnail, duration: nil)
        handlePlaylistToggled(playlistId: playlistId, inLibrary: newStatus, card: card)
        NotificationCenter.default.post(
            name: .sideBLibraryPlaylistToggled,
            object: nil,
            userInfo: ["playlistId": playlistId, "inLibrary": newStatus, "card": card]
        )
        do {
            try await core.likePlaylist(playlistId: playlistId, like: newStatus)
        } catch {
            print("[LibraryViewModel] Error al alternar playlist en biblioteca: \(error)")
            handlePlaylistToggled(playlistId: playlistId, inLibrary: inLibrary, card: card)
            NotificationCenter.default.post(
                name: .sideBLibraryPlaylistToggled,
                object: nil,
                userInfo: ["playlistId": playlistId, "inLibrary": inLibrary, "card": card]
            )
        }
    }

    /// Carga la biblioteca completa (playlists, álbumes e historial) desde Rust Core de forma desacoplada.
    func loadLibrary(core: SideBCore) async {
        guard core.isLoggedIn() else {
            self.clear()
            return
        }

        libraryGeneration &+= 1
        let generation = libraryGeneration
        let session = sessionGeneration

        self.isLoading = true
        self.errorMessage = nil

        async let fetchedPlaylists: Result<[BrowseCardRecord], Error> = {
            do { return .success(try await core.getLibraryPlaylists()) }
            catch { return .failure(error) }
        }()
        async let fetchedAlbums: Result<[BrowseCardRecord], Error> = {
            do { return .success(try await core.getLibraryAlbums()) }
            catch { return .failure(error) }
        }()
        async let fetchedHistory: Result<[HistoryGroupRecord], Error> = {
            do { return .success(try await core.getHistory()) }
            catch { return .failure(error) }
        }()

        let (pRes, aRes, hRes) = await (fetchedPlaylists, fetchedAlbums, fetchedHistory)
        guard generation == libraryGeneration, session == sessionGeneration, core.isLoggedIn() else { return }
        var failures: [LibraryLoadFailure] = []

        switch pRes {
        case .success(let p):
            self.playlists = p
            self.playlistsErrorMessage = nil
            AppContextMenuFactory.cachedUserPlaylists = p
        case .failure(let err):
            print("[LibraryViewModel] Error al cargar playlists: \(err)")
            self.playlistsErrorMessage = err.localizedDescription
            failures.append(LibraryLoadFailure(section: .playlists, detail: err.localizedDescription))
        }

        switch aRes {
        case .success(let a):
            let sortedAlbums = a.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            self.albums = sortedAlbums
            self.albumsErrorMessage = nil
            AppContextMenuFactory.cachedUserAlbums = sortedAlbums
        case .failure(let err):
            print("[LibraryViewModel] Error al cargar álbumes: \(err)")
            self.albumsErrorMessage = err.localizedDescription
            failures.append(LibraryLoadFailure(section: .albums, detail: err.localizedDescription))
        }

        switch hRes {
        case .success(let h):
            self.historyGroups = h
            self.historyErrorMessage = nil
        case .failure(let err):
            print("[LibraryViewModel] Error al cargar historial: \(err)")
            self.historyErrorMessage = err.localizedDescription
            failures.append(LibraryLoadFailure(section: .history, detail: err.localizedDescription))
        }

        libraryLoadFailures = failures
        manualErrorDescriptor = nil
        self.isLoading = false
    }

    /// Recarga el historial de reproducción de forma aislada (remoto si hay sesión o local offline de los últimos 30 días).
    func loadHistory(core: SideBCore) async {
        let generation = sessionGeneration
        self.isHistoryLoading = true
        do {
            let h = try await core.getHistory()
            guard generation == sessionGeneration else { return }
            self.historyGroups = h
            self.historyErrorMessage = nil
        } catch {
            guard generation == sessionGeneration else { return }
            print("[LibraryViewModel] Error al recargar historial: \(error)")
            self.historyErrorMessage = error.localizedDescription
        }
        self.isHistoryLoading = false
    }

    func loadSongs(core: SideBCore, targetInitialCount: Int = 100) async {
        guard core.isLoggedIn(), !isSongsLoading else { return }
        let generation = sessionGeneration
        isSongsLoading = true
        songsErrorMessage = nil
        do {
            let page = try await core.getLibrarySongs()
            guard generation == sessionGeneration, core.isLoggedIn() else { return }
            
            var accumulated = page.items
            var currentContinuation = page.continuation

            // Si la lista estaba vacía, mostramos la primera página (25) de inmediato sin demoras
            if songs.isEmpty {
                songs = page.items
                songsContinuation = page.continuation
            }

            // Cargar automáticamente en segundo plano hasta alcanzar targetInitialCount (100 canciones, igual que Likeadas)
            // o preservar la cantidad que el usuario ya hubiera cargado haciendo scroll.
            let minTarget = max(targetInitialCount, songs.count)
            while accumulated.count < minTarget,
                  let token = currentContinuation,
                  !token.isEmpty {
                do {
                    let nextPage = try await core.getPlaylistContinuation(token: token)
                    guard generation == sessionGeneration, core.isLoggedIn() else { return }
                    let seen = Set(accumulated.map { $0.setVideoId ?? $0.videoId })
                    let newItems = nextPage.items.filter { !seen.contains($0.setVideoId ?? $0.videoId) }
                    if newItems.isEmpty {
                        currentContinuation = nil
                        break
                    }
                    accumulated.append(contentsOf: newItems)
                    currentContinuation = nextPage.continuation == token ? nil : nextPage.continuation
                    
                    // Si partió de lista vacía, ir actualizando progresivamente
                    if songs.count < accumulated.count {
                        songs = accumulated
                        songsContinuation = currentContinuation
                    }
                } catch {
                    break
                }
            }

            songs = accumulated
            songsContinuation = currentContinuation
        } catch {
            guard generation == sessionGeneration else { return }
            songsErrorMessage = error.localizedDescription
        }
        isSongsLoading = false
    }

    func loadMoreSongs(core: SideBCore, batchPages: Int = 2) async {
        guard core.isLoggedIn(), !isSongsLoadingMore,
              var continuation = songsContinuation, !continuation.isEmpty else { return }
        let generation = sessionGeneration
        isSongsLoadingMore = true
        for _ in 0..<batchPages {
            guard !continuation.isEmpty else { break }
            do {
                let page = try await core.getPlaylistContinuation(token: continuation)
                guard generation == sessionGeneration, core.isLoggedIn(),
                      songsContinuation == continuation else { break }
                let seen = Set(songs.map { $0.setVideoId ?? $0.videoId })
                let newItems = page.items.filter { !seen.contains($0.setVideoId ?? $0.videoId) }
                if newItems.isEmpty {
                    songsContinuation = nil
                    break
                }
                songs.append(contentsOf: newItems)
                let nextToken = page.continuation == continuation ? nil : page.continuation
                songsContinuation = nextToken
                continuation = nextToken ?? ""
                songsErrorMessage = nil
            } catch {
                guard generation == sessionGeneration else { break }
                songsErrorMessage = error.localizedDescription
                break
            }
        }
        isSongsLoadingMore = false
    }

    func loadArtists(core: SideBCore) async {
        guard core.isLoggedIn(), !isArtistsLoading else { return }
        let generation = sessionGeneration
        isArtistsLoading = true
        artistsErrorMessage = nil
        do {
            let result = try await core.getLibraryArtists()
            guard generation == sessionGeneration, core.isLoggedIn() else { return }
            artists = result
        } catch {
            guard generation == sessionGeneration else { return }
            artistsErrorMessage = error.localizedDescription
        }
        isArtistsLoading = false
    }


    /// Incorpora una pista recién reproducida al grupo más reciente de forma instantánea.
    func prependPlayedTrack(_ track: SongItemRecord) {
        if self.historyGroups.isEmpty {
            self.historyGroups = [
                HistoryGroupRecord(title: "Hoy", items: [track])
            ]
        } else {
            var firstGroup = self.historyGroups[0]
            firstGroup.items.removeAll(where: { $0.videoId == track.videoId })
            firstGroup.items.insert(track, at: 0)
            self.historyGroups[0] = firstGroup
        }
    }

    /// Limpia los datos locales de la biblioteca al cerrar sesión.
    func clear() {
        sessionGeneration &+= 1
        libraryGeneration &+= 1
        self.playlists = []
        self.albums = []
        self.artists = []
        self.songs = []
        self.songsContinuation = nil
        self.isSongsLoading = false
        self.isSongsLoadingMore = false
        self.isArtistsLoading = false
        self.songsErrorMessage = nil
        self.artistsErrorMessage = nil
        self.playlistsErrorMessage = nil
        self.albumsErrorMessage = nil
        self.historyGroups = []
        self.errorMessage = nil
        self.historyErrorMessage = nil
        self.isLoading = false
        self.isHistoryLoading = false
        AppContextMenuFactory.cachedUserPlaylists = []
        AppContextMenuFactory.cachedUserAlbums = []
    }
}
