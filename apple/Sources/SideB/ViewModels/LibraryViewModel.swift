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
    case all = "Todo"
    case songs = "Canciones"
    case playlists = "Playlists"
    case albums = "Álbumes"
    case artists = "Artistas"

    var id: String { rawValue }
    var displayTitle: String {
        switch self {
        case .all: return L10n.text("library.tab.all")
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
    var originalAlbums: [BrowseCardRecord] = []
    var providerAlbums: [BrowseCardRecord] { originalAlbums.isEmpty ? albums : originalAlbums }
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
    var selectedPageTab: LibraryPageTab = .all { didSet { savePreferences() } }
    var collectionList = false { didSet { savePreferences() } }
    var libraryOrder = "original" { didSet { savePreferences() } }
    var effectiveLibraryOrder: String {
        libraryOrder == "artist" && selectedPageTab != .songs && selectedPageTab != .albums ? "original" : libraryOrder
    }
    var hasLibraryQuery: Bool { !libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var libraryQuery = ""
    var pins: [LibraryPin] = []
    @ObservationIgnored var collectionScrollOffsets: [String: CGFloat] = [:]
    var accountRevision: UInt = 0
    var isSearchingRest = false
    var searchedPages = 0
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var loadedSections: Set<LibraryPageTab> = []
    @ObservationIgnored private var songsGeneration: UInt = 0
    @ObservationIgnored private var preferenceAccount = "guest"
    @ObservationIgnored private var restoringPreferences = false
    @ObservationIgnored private var searchGeneration: UInt = 0
    @ObservationIgnored private var songTokens: Set<String> = []

    func configureAccount(identity: String) {
        guard identity != preferenceAccount else { return }
        clear()
        preferenceAccount = identity
        restoringPreferences = true
        let saved = preferences.data(forKey: "sideb.library.v1:\(identity)")
            .flatMap { try? JSONDecoder().decode(LibraryPreferences.self, from: $0) }
            .flatMap { $0.version == 1 ? $0 : nil }
        selectedPageTab = LibraryPageTab(rawValue: saved?.tab ?? "") ?? .all
        collectionList = saved?.list ?? false
        libraryOrder = ["original", "name", "artist"].contains(saved?.order ?? "") ? saved!.order : "original"
        var seen: Set<String> = []
        pins = Array((saved?.pins ?? []).filter { ["playlist", "album", "artist", "mix"].contains($0.kind) && !$0.id.isEmpty && seen.insert($0.key).inserted }.prefix(50))
        libraryQuery = ""
        collectionScrollOffsets = [:]
        restoringPreferences = false
    }
    private func savePreferences() {
        guard !restoringPreferences, preferenceAccount != "guest" else { return }
        let value = LibraryPreferences(version: 1, tab: selectedPageTab.rawValue, list: collectionList, order: libraryOrder, pins: pins)
        if let data = try? JSONEncoder().encode(value) { preferences.set(data, forKey: "sideb.library.v1:\(preferenceAccount)") }
    }
    func togglePin(_ card: BrowseCardRecord) {
        let key = LibraryPin.key(card)
        if pins.contains(where: { $0.key == key }) { pins.removeAll { $0.key == key } }
        else if pins.count < 50 { pins.append(LibraryPin(card)) }
        savePreferences()
    }
    func movePin(_ card: BrowseCardRecord, by delta: Int) {
        guard let index = pins.firstIndex(where: { $0.key == LibraryPin.key(card) }), pins.indices.contains(index + delta) else { return }
        pins.swapAt(index, index + delta); savePreferences()
    }
    var pinnedCards: [BrowseCardRecord] {
        let current = playlists + albums + artists
        return pins.map { pin in current.first(where: { LibraryPin.key($0) == pin.key }) ?? pin.card }
    }
    func matches(_ values: String?...) -> Bool {
        let query = libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || values.contains { $0?.localizedCaseInsensitiveContains(query) == true }
    }
    func presentedCards(_ cards: [BrowseCardRecord]) -> [BrowseCardRecord] {
        let filtered = cards.filter { matches($0.title, $0.subtitle) }
        guard effectiveLibraryOrder != "original" else { return filtered }
        return filtered.enumerated().sorted {
            let left = effectiveLibraryOrder == "artist" ? $0.element.subtitle ?? "" : $0.element.title
            let right = effectiveLibraryOrder == "artist" ? $1.element.subtitle ?? "" : $1.element.title
            let order = left.localizedStandardCompare(right)
            return order == .orderedSame ? $0.offset < $1.offset : order == .orderedAscending
        }.map(\.element)
    }
    var presentedSongs: [SongItemRecord] {
        let filtered = songs.filter { matches($0.title, $0.artists, $0.album) }
        guard libraryOrder != "original" else { return filtered }
        return filtered.enumerated().sorted {
            let left = libraryOrder == "artist" ? $0.element.artists : $0.element.title
            let right = libraryOrder == "artist" ? $1.element.artists : $1.element.title
            let order = left.localizedStandardCompare(right)
            return order == .orderedSame ? $0.offset < $1.offset : order == .orderedAscending
        }.map(\.element)
    }
    func cancelLibrarySearch() { searchGeneration &+= 1; isSearchingRest = false }
    func searchRemainingSongs(core: SideBCore) async {
        guard !isSearchingRest, !isSongsLoading, !isSongsLoadingMore else { return }
        searchGeneration &+= 1
        let generation = searchGeneration
        isSearchingRest = true; searchedPages = 0
        for _ in 0..<8 {
            guard generation == searchGeneration, let token = songsContinuation, songsErrorMessage == nil else { break }
            await loadMoreSongs(core: core, batchPages: 1)
            guard generation == searchGeneration else { return }
            if songsErrorMessage != nil { break }
            searchedPages += 1
            if songsContinuation == token { break }
        }
        if generation == searchGeneration { isSearchingRest = false }
    }
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

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        setupNotificationObservers()
    }

    func ensureSelectedPageTab(core: SideBCore) async {
        if selectedPageTab == .all {
            async let collections: Void = ensureCollections(core: core)
            async let people: Void = ensureArtists(core: core)
            _ = await (collections, people)
        } else if !loadedSections.contains(selectedPageTab) {
            await reloadSelectedPageTab(core: core)
        }
    }
    private func ensureCollections(core: SideBCore) async {
        guard !isLoading, !loadedSections.contains(.playlists) || !loadedSections.contains(.albums) else { return }
        await loadLibrary(core: core, includesHistory: false)
    }
    private func ensureArtists(core: SideBCore) async {
        guard !isArtistsLoading, !loadedSections.contains(.artists) else { return }
        await loadArtists(core: core)
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
                self.originalAlbums.append(newCard)
                self.albums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

            }
            if let newTracks = tracks, !newTracks.isEmpty {
                let existingIds = Set(self.songs.map { $0.videoId })
                let tracksToAdd = newTracks.filter { !existingIds.contains($0.videoId) }
                self.songs.insert(contentsOf: tracksToAdd, at: 0)
            }
        } else {
            self.albums.removeAll(where: { $0.id == browseId })
            self.originalAlbums.removeAll(where: { $0.id == browseId })
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
        let session = sessionGeneration
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
            guard session == sessionGeneration else { return }
            NotificationCenter.default.post(name: .sideBSongLibraryChanged, object: nil)
        } catch {
            guard session == sessionGeneration else { return }
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
        case .all:
            async let collections: Void = loadLibrary(core: core, includesHistory: false)
            async let people: Void = loadArtists(core: core)
            _ = await (collections, people)
        case .songs:
            await loadSongs(core: core)
        case .artists:
            await loadArtists(core: core)
        case .playlists, .albums:
            await loadLibrary(core: core, includesHistory: false)
        }
    }

    /// Alterna el guardado de una playlist desde la biblioteca con rollback en caso de fallo
    func togglePlaylistLibrary(core: SideBCore, playlistId: String, title: String, subtitle: String?, thumbnail: String?, inLibrary: Bool) async {
        let session = sessionGeneration
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
            guard session == sessionGeneration else { return }
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
    func loadLibrary(core: SideBCore, includesHistory: Bool = true) async {
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
        let existingHistory = historyGroups
        async let fetchedHistory: Result<[HistoryGroupRecord], Error> = {
            if !includesHistory { return .success(existingHistory) }
            do { return .success(try await core.getHistory()) }
            catch { return .failure(error) }
        }()

        let (pRes, aRes, hRes) = await (fetchedPlaylists, fetchedAlbums, fetchedHistory)
        guard generation == libraryGeneration, session == sessionGeneration, core.isLoggedIn() else { return }
        var failures: [LibraryLoadFailure] = []

        switch pRes {
        case .success(let p):
            self.playlists = p
            loadedSections.insert(.playlists)
            self.playlistsErrorMessage = nil
            AppContextMenuFactory.cachedUserPlaylists = p
        case .failure(let err):
            print("[LibraryViewModel] Error al cargar playlists: \(err)")
            self.playlistsErrorMessage = err.localizedDescription
            failures.append(LibraryLoadFailure(section: .playlists, detail: err.localizedDescription))
        }

        switch aRes {
        case .success(let a):
            self.originalAlbums = a
            let sortedAlbums = a.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            self.albums = sortedAlbums
            loadedSections.insert(.albums)
            self.albumsErrorMessage = nil
            AppContextMenuFactory.cachedUserAlbums = sortedAlbums
        case .failure(let err):
            print("[LibraryViewModel] Error al cargar álbumes: \(err)")
            self.albumsErrorMessage = err.localizedDescription
            failures.append(LibraryLoadFailure(section: .albums, detail: err.localizedDescription))
        }

        if includesHistory { switch hRes {
        case .success(let h):
            self.historyGroups = h
            self.historyErrorMessage = nil
        case .failure(let err):
            print("[LibraryViewModel] Error al cargar historial: \(err)")
            self.historyErrorMessage = err.localizedDescription
            failures.append(LibraryLoadFailure(section: .history, detail: err.localizedDescription))
        }

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
        cancelLibrarySearch()
        songsGeneration &+= 1
        let request = songsGeneration
        let generation = sessionGeneration
        isSongsLoading = true
        isSongsLoadingMore = false
        songsErrorMessage = nil
        do {
            let page = try await core.getLibrarySongs()
            guard request == songsGeneration, generation == sessionGeneration, core.isLoggedIn() else { return }
            
            var accumulated = page.items
            var currentContinuation = page.continuation
            songTokens = []
            var pages = 0

            // Si la lista estaba vacía, mostramos la primera página (25) de inmediato sin demoras
            if songs.isEmpty {
                songs = page.items
                songsContinuation = page.continuation
            }

            // Cargar automáticamente en segundo plano hasta alcanzar targetInitialCount (100 canciones, igual que Likeadas)
            // o preservar la cantidad que el usuario ya hubiera cargado haciendo scroll.
            let minTarget = max(targetInitialCount, songs.count)
            while accumulated.count < minTarget, pages < 10,
                  let token = currentContinuation,
                  !token.isEmpty {
                do {
                    pages += 1
                    let nextPage = try await core.getPlaylistContinuation(token: token)
                    guard request == songsGeneration, generation == sessionGeneration, core.isLoggedIn() else { return }
                    let seen = Set(accumulated.map { $0.setVideoId ?? $0.videoId })
                    let newItems = nextPage.items.filter { !seen.contains($0.setVideoId ?? $0.videoId) }
                    songTokens.insert(token)
                    accumulated.append(contentsOf: newItems)
                    currentContinuation = nextPage.continuation.flatMap { songTokens.contains($0) ? nil : $0 }
                    
                    // Si partió de lista vacía, ir actualizando progresivamente
                    if songs.count < accumulated.count {
                        songs = accumulated
                        songsContinuation = currentContinuation
                    }
                } catch {
                    guard request == songsGeneration, generation == sessionGeneration else { return }
                    songsErrorMessage = error.localizedDescription
                    break
                }
            }

            loadedSections.insert(.songs)
            songs = accumulated
            songsContinuation = currentContinuation
        } catch {
            guard request == songsGeneration, generation == sessionGeneration else { return }
            songsErrorMessage = error.localizedDescription
        }
        isSongsLoading = false
    }

    func loadMoreSongs(core: SideBCore, batchPages: Int = 2) async {
        guard core.isLoggedIn(), !isSongsLoading, !isSongsLoadingMore,
              var continuation = songsContinuation, !continuation.isEmpty else { return }
        let generation = sessionGeneration
        let request = songsGeneration
        isSongsLoadingMore = true
        for _ in 0..<batchPages {
            guard !continuation.isEmpty else { break }
            do {
                let page = try await core.getPlaylistContinuation(token: continuation)
                guard request == songsGeneration, generation == sessionGeneration, core.isLoggedIn(),
                      songsContinuation == continuation else { break }
                let seen = Set(songs.map { $0.setVideoId ?? $0.videoId })
                let newItems = page.items.filter { !seen.contains($0.setVideoId ?? $0.videoId) }
                songs.append(contentsOf: newItems)
                songTokens.insert(continuation)
                let nextToken = page.continuation.flatMap { songTokens.contains($0) ? nil : $0 }
                songsContinuation = nextToken
                continuation = nextToken ?? ""
                songsErrorMessage = nil
            } catch {
                guard request == songsGeneration, generation == sessionGeneration else { break }
                songsErrorMessage = error.localizedDescription
                break
            }
        }
        if request == songsGeneration, generation == sessionGeneration { isSongsLoadingMore = false }
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
            loadedSections.insert(.artists)
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
        accountRevision &+= 1
        songsGeneration &+= 1
        loadedSections = []
        preferenceAccount = "guest"
        selectedPageTab = .all
        collectionList = false
        libraryOrder = "original"
        searchedPages = 0
        cancelLibrarySearch()
        songTokens = []
        libraryQuery = ""
        pins = []
        collectionScrollOffsets = [:]
        libraryGeneration &+= 1
        self.playlists = []
        self.albums = []
        self.originalAlbums = []
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

struct LibraryPin: Codable, Equatable {
    let contentRating: String?
    let kind: String; let id: String; let title: String; let subtitle: String?; let thumbnail: String?
    var key: String { Self.key(card) }
    static func key(_ card: BrowseCardRecord) -> String {
        let kind = card.kind == "mix" ? "playlist" : card.kind
        let id = kind == "playlist" ? MenuIDNormalizer.canonicalPlaylistId(card.id) : card.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(kind):\(id)"
    }
    init(_ card: BrowseCardRecord) {
        kind = card.kind == "mix" ? "playlist" : card.kind
        id = kind == "playlist" ? MenuIDNormalizer.canonicalPlaylistId(card.id) : card.id.trimmingCharacters(in: .whitespacesAndNewlines)
        title = card.title; subtitle = card.subtitle; thumbnail = card.thumbnail
        contentRating = ContentRatingMetadata.encode(card.contentRating)
    }
    var card: BrowseCardRecord { BrowseCardRecord(kind: kind == "mix" ? "playlist" : kind, id: id, title: title, subtitle: subtitle, thumbnail: thumbnail, duration: nil, contentRating: ContentRatingMetadata.decode(contentRating)) }
}
private struct LibraryPreferences: Codable {
    let version: Int; let tab: String; let list: Bool; let order: String; let pins: [LibraryPin]
}
