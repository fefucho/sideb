import SwiftUI
import AppKit
import SideBCore

// MARK: - SearchView

struct SearchView: View {
    let initialQuery: String
    let rustCore: SideBCore
    var playerViewModel: PlayerViewModel
    @Bindable var router: NavigationRouter
    @Bindable var searchViewModel: SearchViewModel
    @FocusState private var isSearchBarFocused: Bool
    @State private var selectedSuggestion: String?
    @State private var hoveredRelatedSongID: String?
    @State private var lastPagePreviewQuery: String?
    @State private var previewOwner = UUID()
    
    init(
        initialQuery: String,
        rustCore: SideBCore,
        playerViewModel: PlayerViewModel,
        router: NavigationRouter,
        searchViewModel: SearchViewModel
    ) {
        self.initialQuery = initialQuery
        self.rustCore = rustCore
        self.playerViewModel = playerViewModel
        self.router = router
        self.searchViewModel = searchViewModel
    }
    
    var body: some View {
        let _ = L10n.revision
        ZStack(alignment: .top) {
            // The shell owns the background, including the titlebar and sidebar.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    // Cerrar dropdown topdown y retirar foco si se hace clic en el fondo
                    isSearchBarFocused = false
                    releasePagePreview()
                }
            
            VStack(spacing: 0) {
                // MARK: - 1. Cabecera Fija con Barra Superior y Chips
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("search.title"))
                        .font(.system(size: 38.4, weight: .bold))
                    topSearchBar
                        .zIndex(20)
                    
                    filterChipsBar
                    if searchViewModel.isOriginalSearch {
                        Text(L10n.text("search.correction.original_results")).font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 38.4)
                .padding(.top, 28)
                .padding(.bottom, 12)
                .zIndex(10)
                
                // MARK: - 2. Contenido de la Página de Búsqueda
                ZStack {
                    if (searchViewModel.isCommittedLoading && searchViewModel.committedResults == nil && searchViewModel.committedSongs.isEmpty && searchViewModel.committedVideos.isEmpty) || searchViewModel.isFilterLoading
                        || (searchViewModel.selectedFilter == .songs && searchViewModel.isSongsLoading && searchViewModel.filteredSongs.isEmpty)
                        || (searchViewModel.selectedFilter == .videos && searchViewModel.isVideosLoading && searchViewModel.committedVideos.isEmpty) {
                        loadingStateView
                    } else {
                        switch searchViewModel.selectedFilter {
                        case .all:
                            allResultsView
                        case .songs:
                            filteredResultsView(error: searchViewModel.partialErrors[.songs]) {
                                songsFilterView
                            }
                        case .videos:
                            filteredResultsView(error: searchViewModel.partialErrors[.videos]) {
                                videosFilterView
                            }
                        case .albums:
                            filteredResultsView(error: searchViewModel.partialErrors[.categories]) {
                                cardsGridView(cards: searchViewModel.filteredCards, kind: "album")
                            }
                        case .artists:
                            filteredResultsView(error: searchViewModel.partialErrors[.categories]) {
                                cardsGridView(cards: searchViewModel.filteredCards, kind: "artist")
                            }
                        case .playlists:
                            filteredResultsView(error: searchViewModel.partialErrors[.categories]) {
                                cardsGridView(cards: searchViewModel.filteredCards, kind: "playlist")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            restoreRouteQuery()
        }
        .onChange(of: initialQuery) { _, _ in restoreRouteQuery() }
        .onReceive(NotificationCenter.default.publisher(for: .sideBSongLibraryChanged)) { _ in
            if !searchViewModel.committedQuery.isEmpty {
                searchViewModel.commitSearch(query: searchViewModel.committedQuery, core: rustCore, force: true, preservingPreview: true)
            }
        }
        .onDisappear {
            releasePagePreview()
        }
    }
    
    // MARK: - Barra Superior de Búsqueda con Topdown Dropdown
    
    private var topSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            
            TextField(L10n.text("search.placeholder"), text: $searchViewModel.query)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .focused($isSearchBarFocused)
                .accessibilityIdentifier("search-page-field")
                .accessibilityLabel(L10n.text("navigation.search"))
                .onSubmit { commitPageQuery(selectedSuggestion ?? searchViewModel.query) }
                .onChange(of: searchViewModel.query) { _, newText in
                    // Solo disparar debounce rápido si el usuario está interactuando activamente con el campo
                    selectedSuggestion = nil
                    if isSearchBarFocused {
                        requestPagePreview(newText)
                    }
                }
                .onChange(of: isSearchBarFocused) { _, isFocused in
                    if isFocused {
                        requestPagePreview(searchViewModel.query)
                    } else {
                        selectedSuggestion = nil
                        releasePagePreview()
                    }
                }
                .onKeyPress(.upArrow) {
                    moveSuggestion(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSuggestion(1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    selectedSuggestion = nil
                    isSearchBarFocused = false
                    releasePagePreview()
                    return .handled
                }
            
            if searchViewModel.isQuickSearching {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else if !searchViewModel.query.isEmpty {
                Button {
                    searchViewModel.query = ""
                    isSearchBarFocused = true
                    requestPagePreview("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: SideBControlMetrics.actionHeight)
        .compatGlass(interactive: true, in: Capsule())
        .frame(maxWidth: 640)
        // MARK: - Topdown Dropdown Flotante Anclado Debajo de la Barra
        .overlay(alignment: .top) {
            if isSearchBarFocused && searchViewModel.isTopdownVisible && !searchViewModel.query.isEmpty {
                if let results = searchViewModel.quickResults,
                   searchViewModel.associatedQuickQuery == searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines) {
                    topdownDropdownView(results: results)
                        .padding(.top, SideBControlMetrics.actionHeight + 8)
                } else if searchViewModel.isQuickSearching {
                    topdownLoadingView
                        .padding(.top, SideBControlMetrics.actionHeight + 8)
                } else if let message = searchViewModel.quickErrorMessage {
                    searchErrorBanner(message)
                        .frame(maxWidth: .infinity)
                        .padding(.top, SideBControlMetrics.actionHeight + 8)
                }
            }
        }
    }
    
    // MARK: - Dropdown Topdown de Carga
    
    private var topdownLoadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.text("search.loading.quick"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
    
    // MARK: - Dropdown Topdown de Resultados Rápidos
    
    private func topdownDropdownView(results: SearchResultsRecord) -> some View {
        let results = SearchProjection.suggestions(results, budget: 8)
        let categories = searchViewModel.dynamicCategories(for: results)
        let totalItems = results.top.count
            + min(results.artists.count, 2)
            + min(results.songs.count, 3)
            + min(results.albums.count, 2)
            + min(results.playlists.count, 2)
        
        let calculatedHeight: CGFloat = categories.isEmpty 
            ? 44 
            : min(CGFloat(totalItems * 58 + categories.count * 26 + 12), 340)
        
        return VStack(alignment: .leading, spacing: 8) {
            if !searchViewModel.querySuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("search.suggestions.title")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10)
                    ForEach(searchViewModel.querySuggestions, id: \.self) { text in
                        Button {
                            commitPageQuery(text)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).frame(width: 42)
                                Text(text).font(.system(size: 15)).lineLimit(1)
                                Spacer()
                            }.padding(.horizontal, 10).frame(minHeight: 48).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .background(selectedSuggestion == text ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityAddTraits(selectedSuggestion == text ? .isSelected : [])
                    }
                }.padding(.horizontal, 8).padding(.top, 8)
            }
            if categories.isEmpty && searchViewModel.querySuggestions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(L10n.text("search.empty.quick"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            } else if !categories.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(categories) { category in
                            VStack(alignment: .leading, spacing: 3) {
                                if category != .topResult {
                                    Text(category.displayTitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10)
                                }

                                switch category {
                                case .topResult:
                                    ForEach(results.top, id: \.searchEntityKey) { hero in
                                        if ["song", "video"].contains(hero.kind.lowercased()) {
                                            let song = searchViewModel.song(for: hero, in: results)
                                            QuickResultSongRow(song: song, onFeatured: openQuickArtist,
                                                onArtist: quickArtistAction(song), onAlbum: quickAlbumAction(song),
                                                menuProvider: { quickSongMenu(song, origin: .searchSpotlight) }) {
                                                    isSearchBarFocused = false
                                                    searchViewModel.isTopdownVisible = false
                                                    playerViewModel.activateSearchMediaRadio(song)
                                                }.songContextMenu(song: song, player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                                        } else {
                                        let row = QuickResultCardRow(
                                            card: hero,
                                            isHero: true,
                                            isActive: isActiveCollection(hero),
                                            isPlaying: isActiveCollection(hero) && playerViewModel.isPlaying,
                                            isLoading: isCollectionLoading(hero),
                                            onPlay: quickCardPlayAction(hero, results: results),
                                            menuProvider: {
                                                ["song", "video"].contains(hero.kind.lowercased())
                                                    ? quickSongMenu(searchViewModel.song(for: hero, in: results), origin: .searchSpotlight)
                                                    : browseCardMenu(hero)
                                            }
                                        ) {
                                            isSearchBarFocused = false
                                            handleQuickSelect(hero, results: results)
                                        }
                                        if hero.kind.lowercased() == "song" {
                                            row.songContextMenu(song: searchViewModel.song(for: hero, in: results), player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                                        } else {
                                            row.browseCardContextMenu(card: hero, player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                                        }
                                        }

                                    }
                                case .artists:
                                    ForEach(Array(results.artists.prefix(2)), id: \.id) { a in
                                        QuickResultCardRow(card: a) {
                                            isSearchBarFocused = false
                                            searchViewModel.isTopdownVisible = false
                                            router.navigate(to: .artist(browseId: a.id))
                                        }
                                        .browseCardContextMenu(card: a, player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                                    }
                                case .songs:
                                    ForEach(Array(results.songs.prefix(3)), id: \.videoId) { s in
                                        QuickResultSongRow(
                                            song: s,
                                            onFeatured: openQuickArtist,
                                            onArtist: quickArtistAction(s),
                                            onAlbum: quickAlbumAction(s),
                                            menuProvider: { quickSongMenu(s, origin: .searchSpotlight) },
                                            onSelect: {
                                                isSearchBarFocused = false
                                                searchViewModel.isTopdownVisible = false
                                                playerViewModel.activateSearchMediaRadio(s)
                                            }
                                        )
                                        .songContextMenu(song: s, player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                                    }
                                case .albums:
                                    ForEach(Array(results.albums.prefix(2)), id: \.id) { alb in
                                        QuickResultCardRow(
                                            card: alb,
                                            isActive: isActiveCollection(alb),
                                            isPlaying: isActiveCollection(alb) && playerViewModel.isPlaying,
                                            isLoading: isCollectionLoading(alb),
                                            onPlay: collectionPlayAction(for: alb),
                                            menuProvider: { browseCardMenu(alb) }
                                        ) {
                                            isSearchBarFocused = false
                                            searchViewModel.isTopdownVisible = false
                                            router.navigate(to: .album(browseId: alb.id))
                                        }
                                        .browseCardContextMenu(card: alb, player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                                    }
                                case .playlists:
                                    ForEach(Array(results.playlists.prefix(2)), id: \.id) { pl in
                                        QuickResultCardRow(
                                            card: pl,
                                            isActive: isActiveCollection(pl),
                                            isPlaying: isActiveCollection(pl) && playerViewModel.isPlaying,
                                            isLoading: isCollectionLoading(pl),
                                            onPlay: collectionPlayAction(for: pl),
                                            menuProvider: { browseCardMenu(pl) }
                                        ) {
                                            isSearchBarFocused = false
                                            searchViewModel.isTopdownVisible = false
                                            router.navigate(to: .playlist(browseId: pl.id))
                                        }
                                        .browseCardContextMenu(card: pl, player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(height: calculatedHeight)
            }

            if let message = searchViewModel.quickErrorMessage {
                searchErrorBanner(message)
                    .padding(.horizontal, 10)
            }
            
            Divider().opacity(0.15)
            
            // Botón para Confirmar y Actualizar la Página Completa
            Button {
                commitPageQuery(searchViewModel.query)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text(L10n.text("search.submit.full_results"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
    
    private func moveSuggestion(_ delta: Int) {
        let suggestions = searchViewModel.querySuggestions
        guard !suggestions.isEmpty else { selectedSuggestion = nil; return }
        let current = selectedSuggestion.flatMap { suggestions.firstIndex(of: $0) } ?? -1
        let index = min(max(current + delta, -1), suggestions.count - 1)
        selectedSuggestion = index < 0 ? nil : suggestions[index]
    }

    private func handleQuickSelect(_ card: BrowseCardRecord, results: SearchResultsRecord) {
        searchViewModel.isTopdownVisible = false
        switch card.kind.lowercased() {
        case "artist":
            router.navigate(to: .artist(browseId: card.id))
        case "album":
            router.navigate(to: .album(browseId: card.id))
        case "playlist":
            router.navigate(to: .playlist(browseId: card.id))
        case "song", "video":
            playerViewModel.activateSearchMediaRadio(searchViewModel.song(for: card, in: results))
        default:
            commitPageQuery(card.title)
        }
    }

    private func restoreRouteQuery() {
        guard !initialQuery.isEmpty else { return }
        if searchViewModel.committedQuery != initialQuery
            || (searchViewModel.committedResults == nil && !searchViewModel.isCommittedLoading) {
            searchViewModel.commitSearch(query: initialQuery, core: rustCore)
        }
    }

    private func requestPagePreview(_ text: String) {
        guard isSearchBarFocused, lastPagePreviewQuery != text else { return }
        lastPagePreviewQuery = text
        searchViewModel.claimPreview(owner: previewOwner)
        searchViewModel.onQueryChanged(text, core: rustCore, owner: previewOwner)
    }

    private func releasePagePreview() {
        lastPagePreviewQuery = nil
        searchViewModel.cancelPreview(owner: previewOwner)
    }

    private func commitPageQuery(_ text: String, origin: SearchOrigin = .submit) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearchBarFocused = false
        selectedSuggestion = nil
        releasePagePreview()
        searchViewModel.commitSearch(query: query, core: rustCore, origin: origin)
        router.navigate(to: .search(query: query))
    }
    
    // MARK: - Barra de Chips de Filtro
    
    private var filterChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SideBControlMetrics.categorySpacing) {
                ForEach(SearchFilter.allCases) { filter in
                    Button {
                        searchViewModel.selectFilter(filter, core: rustCore)
                    } label: {
                        SideBControlLabel(title: filter.displayTitle, symbol: filter.icon)
                    }
                    .buttonStyle(SideBControlStyle(size: .category, selected: searchViewModel.selectedFilter == filter))
                    .accessibilityAddTraits(searchViewModel.selectedFilter == filter ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        .windowGestureRegion(.horizontalContent, active: !playerViewModel.isFullscreenPresented)
        .frame(height: SideBControlMetrics.categoryHeight + 8)
    }

    // MARK: - Vista "Todo" (Resultados Mixtos)
    
    private var allResultsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if !searchViewModel.committedQuery.isEmpty {
                    if let correction = searchViewModel.correction {
                        HStack(spacing: 10) {
                            Text(L10n.text(correction.applied ? "search.correction.showing" : "search.correction.suggested", args: [correction.query]))
                            Button(L10n.text(correction.applied ? "search.correction.original" : "search.correction.search")) {
                                searchViewModel.commitSearch(query: correction.applied ? searchViewModel.committedQuery : correction.query,
                                    core: rustCore, force: true, origin: correction.applied ? .navigationRestore : .submit,
                                    ignoreSpelling: correction.applied)
                            }.buttonStyle(.plain).foregroundStyle(.primary)
                        }.font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    let results = searchViewModel.committedResults.map { SearchProjection.make($0) }
                    if searchViewModel.isMixedLoading {
                        RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)).frame(height: 58)
                            .overlay(ProgressView().controlSize(.small)).accessibilityLabel(L10n.text("search.loading.catalog"))
                    }
                    if let results, let hero = results.top.first {
                        topResultSection(hero, results: results)
                    }

                    // Las canciones filtradas son la fuente principal; las del resultado mixto quedan como respaldo.
                    let occupied = Set((results?.top.filter { ["song", "video"].contains($0.kind) }.map { $0.kind + ":" + $0.id } ?? []) + (results?.topSongs.map { ($0.isVideo ? "video:" : "song:") + $0.videoId } ?? []))
                    var seenSongs = occupied
                    let todoSongs = (results?.songs.filter { !$0.isVideo } ?? []).filter { seenSongs.insert(($0.isVideo ? "video:" : "song:") + $0.videoId).inserted }
                    if !todoSongs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L10n.text("search.filter.songs"))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                Button(L10n.text("search.see_all.feminine")) {
                                    searchViewModel.selectFilter(.songs, core: rustCore)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .buttonStyle(.plain)
                            }
                            
                            let topSongs: [SongItemRecord] = Array(todoSongs.prefix(5))
                            VStack(spacing: 4) {
                                ForEach(topSongs, id: \.videoId) { song in
                                    songInlineRow(song: song)
                                }
                            }
                        }
                    }

                    if let results {
                        if !results.artists.isEmpty {
                            cardsSection(title: L10n.text("search.filter.artists"), cards: results.artists, kind: "artist")
                        }
                        if !results.albums.isEmpty {
                            cardsSection(title: L10n.text("search.filter.albums"), cards: results.albums, kind: "album")
                        }
                        if !results.playlists.isEmpty {
                            cardsSection(title: L10n.text("search.filter.playlists"), cards: results.playlists, kind: "playlist")
                        }
                    }
                    let todoVideos = searchViewModel.displayVideos(excluding: results)
                    if !todoVideos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L10n.text("search.filter.videos"))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button(L10n.text("search.see_all.masculine")) {
                                    searchViewModel.selectFilter(.videos, core: rustCore)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .buttonStyle(.plain)
                            }
                            VStack(spacing: 4) {
                                ForEach(Array(todoVideos.prefix(4)), id: \.videoId) { video in
                                    songInlineRow(song: video)
                                }
                            }
                        }
                    }
                    
                    ForEach([SearchPartialError.global, .songs, .categories, .videos], id: \.self) { error in
                        if let message = searchViewModel.partialErrors[error] {
                            searchErrorBanner(message, retry: { searchViewModel.retryBlock(error, core: rustCore) })
                        }
                    }
                    let hasMixedResults = results.map {
                        !$0.top.isEmpty || !$0.albums.isEmpty || !$0.artists.isEmpty || !$0.playlists.isEmpty
                    } ?? false
                    if !hasMixedResults,
                       searchViewModel.committedSongs.isEmpty,
                       searchViewModel.committedVideos.isEmpty,
                       searchViewModel.partialErrors.isEmpty {
                        noResultsView
                    }
                } else {
                    initialEmptyStateView
                }
            }
            .padding(.horizontal, 38.4)
            .padding(.vertical, 20)
            .padding(.bottom, 120) // Margen para la PlayerBar flotante
        }
    }
    
    // The primary result uses the same density and actions as its surrounding rows.
    @ViewBuilder
    private func topResultSection(_ card: BrowseCardRecord, results: SearchResultsRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if ["song", "video"].contains(card.kind.lowercased()) {
                songInlineRow(song: searchViewModel.song(for: card, in: results))
            } else {
                QuickResultCardRow(card: card, isHero: true,
                    isActive: isActiveCollection(card), isPlaying: playerViewModel.isPlaying,
                    isLoading: isCollectionLoading(card),
                    onPlay: card.kind.lowercased() == "artist" ? nil : { playerViewModel.activateMediaCollection(id: card.id, kind: card.kind) },
                    menuProvider: { browseCardMenu(card) }) { handleCardClick(card, results: results) }
                    .browseCardContextMenu(card: card, player: playerViewModel, router: router, core: rustCore, origin: .search)
            }
            ForEach(searchViewModel.relatedSongs(for: results), id: \.videoId) { song in
                songInlineRow(song: song)
            }
        }
    }

    private func relatedSongRows(_ songs: [SongItemRecord]) -> some View {
        VStack(spacing: 4) {
            ForEach(songs, id: \.videoId) { song in
                relatedSongRow(song)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relatedSongRow(_ song: SongItemRecord) -> some View {
        let artistText = song.artists.trimmingCharacters(in: .whitespacesAndNewlines)
        let typeText = song.isVideo ? L10n.text("search.filter.videos") : L10n.text("metadata.song")
        let row = HStack(spacing: 10) {
            MediaArtworkControls(
                isCollection: false,
                accessibilityTitle: song.title,
                onOpen: { playerViewModel.activateMediaRadio(song) },
                onPlay: { playerViewModel.activateMediaRadio(song) },
                menuProvider: { quickSongMenu(song) }
            ) {
                if let thumb = song.thumbnail,
                   let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 104) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 52, height: 52)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 52, height: 52)
                        .overlay(Image(systemName: song.isVideo ? "play.rectangle" : "music.note").foregroundStyle(.secondary))
                }
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                FeaturedTrackTitle(track: song, font: .system(size: 14, weight: playerViewModel.currentTrack?.videoId == song.videoId ? .semibold : .medium), color: .primary) { id, name in
                    if let id { router.navigate(to: .artist(browseId: id)) }
                    else { searchViewModel.commitSearch(query: name, core: rustCore, origin: .artistResolution); router.navigate(to: .search(query: name)) }
                }
                HStack(spacing: 4) {
                    Text(typeText).font(.system(size: 12)).foregroundStyle(.secondary).allowsHitTesting(false)
                    if !artistText.isEmpty {
                        Text("·").font(.system(size: 12)).foregroundStyle(.secondary).allowsHitTesting(false)
                        if let onArtist = quickArtistAction(song) {
                            Button(action: onArtist) {
                                Text(artistText).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .mediaCardFocusControl()
                        } else {
                            Text(artistText).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                .allowsHitTesting(false)
                        }
                    }
                    if let album = song.album, !album.isEmpty, let onAlbum = quickAlbumAction(song) {
                        Text("·").font(.system(size: 12)).foregroundStyle(.secondary).allowsHitTesting(false)
                        Button(action: onAlbum) {
                            Text(album).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .mediaCardFocusControl()
                    }
                    if let album = song.album, !album.isEmpty, quickAlbumAction(song) == nil {
                        Text("·").font(.system(size: 12)).foregroundStyle(.secondary).allowsHitTesting(false)
                        Text(album).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let duration = song.duration, !duration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(duration).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.tertiary).lineLimit(1).fixedSize().allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 62)
        .background(hoveredRelatedSongID == song.videoId ? Color.white.opacity(0.075) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .mediaCardActivation(label: L10n.text("app.playNamed", args: [song.title])) { playerViewModel.activateMediaRadio(song) }
        .mediaCardSurface()
        .onHover { hovering in hoveredRelatedSongID = hovering ? song.videoId : nil }

        return row.songContextMenu(song: song, player: playerViewModel, router: router, core: rustCore, origin: .search)
    }
    
    // MARK: - Filtro de Canciones (NativeTrackTableView a 120 FPS)
    
    private var songsFilterView: some View {
        nativeTrackTableView(tracks: searchViewModel.filteredSongs)
    }

    private var videosFilterView: some View {
        nativeTrackTableView(tracks: searchViewModel.committedVideos)
    }

    private func nativeTrackTableView(tracks: [SongItemRecord]) -> some View {
        Group {
            if tracks.isEmpty {
                noResultsView
            } else {
                NativeTrackTableView(
                    tracks: tracks,
                    currentTrackVideoId: playerViewModel.currentTrack?.videoId,
                    isPlaying: playerViewModel.isPlaying,
                    playerViewModel: playerViewModel,
                    router: router,
                    rustCore: rustCore,
                    hideAlbumColumn: false,
                    showAlbumInSubtitle: true,
                    rowHeight: 52.0,
                    likedVideoIds: playerViewModel.likedVideoIds,
                    menuOrigin: { _ in .search },
                    onPlayTrack: { index in
                        if index >= 0 && index < tracks.count {
                            playerViewModel.activateMediaRadio(tracks[index])
                        }
                    },
                    onLikeTrack: { track in
                        playerViewModel.toggleTrackLike(track)
                    },
                    onDislikeTrack: { track in
                        playerViewModel.dislikeTrack(track)
                    },
                    contentInsets: NSEdgeInsets(top: 10, left: 24, bottom: 120, right: 24)
                )
            }
        }
    }
    
    // MARK: - Secciones Horizontales de Tarjetas
    
    private func displayKind(_ raw: String) -> String {
        switch raw.lowercased() {
        case "song": return L10n.text("metadata.song")
        case "video": return L10n.text("search.filter.videos")
        case "album": return L10n.text("metadata.album")
        case "playlist", "mix": return L10n.text("metadata.playlist")
        case "artist": return L10n.text("search.filter.artists")
        default: return raw.capitalized
        }
    }

    private func cardsSection(title: String, cards: [BrowseCardRecord], kind: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(cards.prefix(12), id: \.id) { card in
                        browseCardItem(card: card)
                    }
                }
                .padding(.vertical, 4)
            }
            .windowGestureRegion(.horizontalContent, active: !playerViewModel.isFullscreenPresented)
        }
    }
    
    // MARK: - Grilla Completa de Tarjetas para Filtros Específicos
    
    private func cardsGridView(cards: [BrowseCardRecord], kind: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            if cards.isEmpty {
                noResultsView
            } else {
                let isArtist = kind == "artist"
                let columns = [GridItem(.adaptive(minimum: isArtist ? 130 : 150, maximum: 180), spacing: 20)]
                
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(cards, id: \.id) { card in
                        browseCardItem(card: card)
                    }
                }
                .padding(.horizontal, 38.4)
                .padding(.vertical, 20)
                .padding(.bottom, 120)
            }
        }
    }
    
    // MARK: - Item de Tarjeta Individual con Clic Derecho Universal
    
    @ViewBuilder
    private func browseCardItem(card: BrowseCardRecord) -> some View {
        let isArtist = card.kind.lowercased() == "artist"
        let cardSize: CGFloat = isArtist ? 130 : 144
        let isCollection = ["album", "playlist"].contains(card.kind.lowercased())
        let isActive = isActiveCollection(card)
        let artwork = Group {
            if let thumb = card.thumbnail,
               let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 288) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: cardSize, height: cardSize)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.12)
                }
                .frame(width: cardSize, height: cardSize)
                .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: AppTheme.artworkCardRadius, style: .continuous)))
                .overlay {
                    if isArtist {
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    } else {
                        RoundedRectangle(cornerRadius: AppTheme.artworkCardRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: isArtist ? cardSize / 2 : AppTheme.artworkCardRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: cardSize, height: cardSize)
                    .overlay(Image(systemName: isArtist ? "person.crop.circle" : "music.note").font(.system(size: 28)))
            }
        }

        let cardView = VStack(alignment: .leading, spacing: 7) {
            if isCollection {
                MediaArtworkControls(
                    isCollection: true,
                    isActive: isActive,
                    isPlaying: isActive && playerViewModel.isPlaying,
                    isLoading: isCollectionLoading(card),
                    showsIndicator: isActive,
                    accessibilityTitle: card.title,
                    onOpen: { handleCardClick(card) },
                    onPlay: { playerViewModel.activateMediaCollection(id: card.id, kind: card.kind) },
                    menuProvider: { browseCardMenu(card) }
                ) {
                    artwork
                }
                .frame(width: cardSize, height: cardSize)
            } else if isArtist {
                Button { handleCardClick(card) } label: { artwork }
                    .buttonStyle(.plain)
                    .mediaCardFocusControl()
            } else {
                MediaArtworkControls(
                    isCollection: false,
                    accessibilityTitle: card.title,
                    onOpen: { handleCardClick(card) },
                    onPlay: { handleCardClick(card) },
                    menuProvider: { browseCardMenu(card) }
                ) {
                    artwork
                }
                .frame(width: cardSize, height: cardSize)
            }

            Button { handleCardClick(card) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle = card.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .mediaCardFocusControl()
        }
        .frame(width: cardSize, alignment: .leading)
        .mediaCardActivation(label: L10n.text("search.open_card", args: [card.title])) { handleCardClick(card) }
        .mediaCardSurface()

        cardView.browseCardContextMenu(card: card, player: playerViewModel, router: router, core: rustCore, origin: .search)
    }

    private func browseCardMenu(_ card: BrowseCardRecord) -> NSMenu? {
        let factory = AppContextMenuFactory.shared
        switch card.kind.lowercased() {
        case "album":
            return factory.buildAlbumNSMenu(browseId: card.id, playlistId: nil, title: card.title,
                artist: card.subtitle, thumbnail: card.thumbnail, origin: .search,
                player: playerViewModel, router: router, core: rustCore)
        case "playlist":
            return factory.buildPlaylistNSMenu(id: card.id, title: card.title, subtitle: card.subtitle,
                thumbnail: card.thumbnail, origin: .search, player: playerViewModel,
                router: router, core: rustCore)
        case "song", "video":
            return factory.buildSongNSMenu(song: SongItemRecord(fromCard: card), player: playerViewModel,
                router: router, core: rustCore, origin: .search)
        default:
            return nil
        }
    }
    
    // MARK: - Fila de Canción Inline (para Vista "Todo")
    
    private func songInlineRow(song: SongItemRecord) -> some View {
        HStack(spacing: 12) {
            MediaArtworkControls(
                isCollection: false,
                accessibilityTitle: song.title,
                onOpen: { playerViewModel.activateMediaRadio(song) },
                onPlay: { playerViewModel.activateMediaRadio(song) },
                menuProvider: { quickSongMenu(song) }
            ) {
                if let thumb = song.thumbnail,
                   let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 96) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 42, height: 42)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous).fill(Color.white.opacity(0.06))
                    }
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06)).frame(width: 42, height: 42)
                }
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                FeaturedTrackTitle(track: song, font: .system(size: 15, weight: playerViewModel.currentTrack?.videoId == song.videoId ? .semibold : .medium), color: .primary) { id, name in
                    if let id { router.navigate(to: .artist(browseId: id)) }
                    else { searchViewModel.commitSearch(query: name, core: rustCore, origin: .artistResolution); router.navigate(to: .search(query: name)) }
                }
                HStack(spacing: 4) {
                    if let onArtist = quickArtistAction(song) {
                        Button(action: onArtist) { Text(song.artists).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
                            .buttonStyle(.plain)
                            .mediaCardFocusControl()
                    } else {
                        Text(song.artists).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    if let album = song.album, !album.isEmpty, let onAlbum = quickAlbumAction(song) {
                        Text("·").font(.system(size: 12)).foregroundStyle(.tertiary)
                        Button(action: onAlbum) { Text(album).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
                            .buttonStyle(.plain)
                            .mediaCardFocusControl()
                    }
                    if let album = song.album, !album.isEmpty, quickAlbumAction(song) == nil {
                        Text("·").font(.system(size: 12)).foregroundStyle(.tertiary).allowsHitTesting(false)
                        Text(album).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let dur = song.duration {
                Text(dur).font(.system(size: 12)).foregroundStyle(.tertiary).allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))
        .contentShape(Rectangle())
        .mediaCardActivation(label: L10n.text("app.playNamed", args: [song.title])) { playerViewModel.activateMediaRadio(song) }
        .mediaCardSurface()
        .songContextMenu(song: song, player: playerViewModel, router: router, core: rustCore, origin: .search)
    }
    
    // MARK: - Navegación de Tarjeta
    
    private func handleCardClick(_ card: BrowseCardRecord, results: SearchResultsRecord? = nil) {
        switch card.kind.lowercased() {
        case "artist":
            router.navigate(to: .artist(browseId: card.id))
        case "album":
            router.navigate(to: .album(browseId: card.id))
        case "playlist":
            router.navigate(to: .playlist(browseId: card.id))
        case "song", "video":
            let song = searchViewModel.song(for: card, in: results ?? searchViewModel.committedResults)
            playerViewModel.activateMediaRadio(song)
        default:
            searchViewModel.commitSearch(query: card.title, core: rustCore, force: true)
        }
    }

    private func isActiveCollection(_ card: BrowseCardRecord) -> Bool {
        MediaPlaybackIdentity.isCollectionActive(
            kind: card.kind,
            id: card.id,
            context: playerViewModel.queueManager.context
        )
    }

    private func isCollectionLoading(_ card: BrowseCardRecord) -> Bool {
        switch card.kind.lowercased() {
        case "album":
            return playerViewModel.loadingRecommendedAlbumID.map(MenuIDNormalizer.normalize) == MenuIDNormalizer.normalize(card.id)
        case "playlist":
            return playerViewModel.loadingRecommendedPlaylistID.map(MenuIDNormalizer.canonicalPlaylistId) == MenuIDNormalizer.canonicalPlaylistId(card.id)
        default:
            return false
        }
    }

    private func collectionPlayAction(for card: BrowseCardRecord) -> (() -> Void)? {
        guard ["album", "playlist"].contains(card.kind.lowercased()) else { return nil }
        return {
            isSearchBarFocused = false
            searchViewModel.isTopdownVisible = false
            playerViewModel.activateMediaCollection(id: card.id, kind: card.kind)
        }
    }

    private func quickCardPlayAction(_ card: BrowseCardRecord, results: SearchResultsRecord) -> (() -> Void)? {
        switch card.kind.lowercased() {
        case "album", "playlist":
            return collectionPlayAction(for: card)
        case "song", "video":
            return {
                isSearchBarFocused = false
                searchViewModel.isTopdownVisible = false
                playerViewModel.activateSearchMediaRadio(searchViewModel.song(for: card, in: results))
            }
        default:
            return nil
        }
    }

    private func openQuickArtist(id: String?, name: String) {
        isSearchBarFocused = false
        searchViewModel.isTopdownVisible = false
        if let id { router.navigate(to: .artist(browseId: id)) }
        else {
            searchViewModel.commitSearch(query: name, core: rustCore, origin: .artistResolution)
            router.navigate(to: .search(query: name))
        }
    }

    private func quickArtistAction(_ song: SongItemRecord) -> (() -> Void)? {
        guard let id = song.artistId, !id.isEmpty else { return nil }
        return {
            isSearchBarFocused = false
            searchViewModel.isTopdownVisible = false
            router.navigate(to: .artist(browseId: id))
        }
    }

    private func quickAlbumAction(_ song: SongItemRecord) -> (() -> Void)? {
        guard let id = song.albumId, !id.isEmpty else { return nil }
        return {
            isSearchBarFocused = false
            searchViewModel.isTopdownVisible = false
            router.navigate(to: .album(browseId: id))
        }
    }

    private func quickSongMenu(_ song: SongItemRecord, origin: MenuOrigin = .search) -> NSMenu? {
        AppContextMenuFactory.shared.buildSongNSMenu(
            song: song, player: playerViewModel, router: router, core: rustCore, origin: origin
        )
    }

    private func searchErrorBanner(_ message: String, retry: (() -> Void)? = nil) -> some View {
        HStack {
            Label(message, systemImage: "exclamationmark.circle")
            Spacer()
            if let retry { Button(L10n.text("common.retry"), action: retry).buttonStyle(SideBControlStyle()) }
        }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func filteredResultsView<Content: View>(error: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error {
                searchErrorBanner(error, retry: {
                    let block: SearchPartialError = searchViewModel.selectedFilter == .songs ? .songs : searchViewModel.selectedFilter == .videos ? .videos : .categories
                    searchViewModel.retryBlock(block, core: rustCore)
                })
                    .padding(.horizontal, 38.4)
                    .padding(.top, 10)
            }
            content()
        }
    }
    
    // MARK: - Estados Vacíos y de Carga
    
    private var loadingStateView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text(L10n.text("search.loading.catalog"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(.top, 40)
            
            Text(L10n.text("search.empty.query", args: [searchViewModel.committedQuery]))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Text(L10n.text("search.empty.try_another"))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }
    
    private var initialEmptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(.top, 60)
            
            Text(L10n.text("search.empty.prompt_title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Text(L10n.text("search.empty.prompt_description"))
                .font(.system(size: 12.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
