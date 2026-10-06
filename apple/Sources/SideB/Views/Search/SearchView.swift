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
    @State private var hoveredRelatedSongID: String?
    
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
        ZStack(alignment: .top) {
            // Fondo oscuro uniforme de Side B
            Color.sidebDarkBackground
                .ignoresSafeArea()
                .onTapGesture {
                    // Cerrar dropdown topdown y retirar foco si se hace clic en el fondo
                    isSearchBarFocused = false
                    searchViewModel.isTopdownVisible = false
                }
            
            VStack(spacing: 0) {
                // MARK: - 1. Cabecera Fija con Barra Superior y Chips
                VStack(spacing: 12) {
                    topSearchBar
                        .zIndex(20)
                    
                    filterChipsBar
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .background(
                    Color.sidebDarkBackground.opacity(0.85)
                        .background(.ultraThinMaterial)
                )
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.15)
                }
                .zIndex(10)
                
                // MARK: - 2. Contenido de la Página de Búsqueda
                ZStack {
                    if searchViewModel.isCommittedLoading || searchViewModel.isFilterLoading {
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
            if !initialQuery.isEmpty {
                if searchViewModel.committedQuery != initialQuery || searchViewModel.committedResults == nil {
                    searchViewModel.query = initialQuery
                    searchViewModel.commitSearch(query: initialQuery, core: rustCore)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBSongLibraryChanged)) { _ in
            if !searchViewModel.committedQuery.isEmpty {
                searchViewModel.commitSearch(query: searchViewModel.committedQuery, core: rustCore, force: true)
            }
        }
        .onDisappear {
            searchViewModel.cancelPreview()
        }
    }
    
    // MARK: - Barra Superior de Búsqueda con Topdown Dropdown
    
    private var topSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            
            TextField("Buscar en YouTube Music...", text: $searchViewModel.query)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .focused($isSearchBarFocused)
                .onSubmit {
                    isSearchBarFocused = false
                    searchViewModel.isTopdownVisible = false
                    searchViewModel.commitSearch(query: searchViewModel.query, core: rustCore, force: true)
                }
                .onChange(of: searchViewModel.query) { _, newText in
                    // Solo disparar debounce rápido si el usuario está interactuando activamente con el campo
                    if isSearchBarFocused {
                        searchViewModel.onQueryChanged(newText, core: rustCore)
                    }
                }
                .onChange(of: isSearchBarFocused) { _, isFocused in
                    if isFocused {
                        let trimmed = searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            searchViewModel.onQueryChanged(trimmed, core: rustCore)
                        }
                    } else {
                        searchViewModel.isTopdownVisible = false
                        searchViewModel.cancelPreview()
                    }
                }
                .onKeyPress(.escape) {
                    isSearchBarFocused = false
                    searchViewModel.isTopdownVisible = false
                    return .handled
                }
            
            if searchViewModel.isQuickSearching {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else if !searchViewModel.query.isEmpty {
                Button {
                    searchViewModel.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .compatGlass(interactive: true, in: Capsule())
        .frame(maxWidth: 520)
        // MARK: - Topdown Dropdown Flotante Anclado Debajo de la Barra
        .overlay(alignment: .top) {
            if isSearchBarFocused && searchViewModel.isTopdownVisible && !searchViewModel.query.isEmpty {
                if let results = searchViewModel.quickResults,
                   searchViewModel.associatedQuickQuery == searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines) {
                    topdownDropdownView(results: results)
                        .padding(.top, 42)
                } else if searchViewModel.isQuickSearching {
                    topdownLoadingView
                        .padding(.top, 42)
                } else if let message = searchViewModel.quickErrorMessage {
                    searchErrorBanner(message)
                        .frame(width: 520)
                        .padding(.top, 42)
                }
            }
        }
    }
    
    // MARK: - Dropdown Topdown de Carga
    
    private var topdownLoadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Buscando respuestas rápidas...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 520)
        .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
    
    // MARK: - Dropdown Topdown de Resultados Rápidos
    
    private func topdownDropdownView(results: SearchResultsRecord) -> some View {
        let categories = searchViewModel.dynamicCategories(for: results)
        let relatedSongs = searchViewModel.relatedSongs(for: results)
        let totalItems = (results.top.isEmpty ? 0 : 1)
            + relatedSongs.count
            + min(results.artists.count, 2)
            + min(results.songs.count, 3)
            + min(results.albums.count, 2)
            + min(results.playlists.count, 2)
        
        let calculatedHeight: CGFloat = categories.isEmpty 
            ? 44 
            : min(CGFloat(totalItems * 48 + categories.count * 26 + 12), 340)
        
        return VStack(alignment: .leading, spacing: 8) {
            if categories.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("No se encontraron respuestas rápidas")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(categories) { category in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(category == .topResult ? .primary : .secondary)
                                    
                                    Text(category.rawValue.uppercased())
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(category == .topResult ? .primary : .secondary)
                                        .tracking(0.5)
                                }
                                .padding(.horizontal, 8)
                                
                                switch category {
                                case .topResult:
                                    if let hero = results.top.first {
                                        let row = QuickResultCardRow(
                                            card: hero,
                                            isHero: true,
                                            isActive: isActiveCollection(hero),
                                            isPlaying: isActiveCollection(hero) && playerViewModel.isPlaying,
                                            isLoading: isCollectionLoading(hero),
                                            onPlay: quickCardPlayAction(hero, results: results),
                                            menuProvider: {
                                                ["song", "video"].contains(hero.kind.lowercased())
                                                    ? quickSongMenu(searchViewModel.song(for: hero, in: results))
                                                    : browseCardMenu(hero)
                                            }
                                        ) {
                                            isSearchBarFocused = false
                                            handleQuickSelect(hero, results: results)
                                        }
                                        if hero.kind.lowercased() == "song" {
                                            row.songContextMenu(song: searchViewModel.song(for: hero, in: results), player: playerViewModel, router: router, core: rustCore, origin: .search)
                                        } else {
                                            row.browseCardContextMenu(card: hero, player: playerViewModel, router: router, core: rustCore, origin: .search)
                                        }
                                        ForEach(relatedSongs, id: \.videoId) { song in
                                            QuickResultSongRow(
                                            song: song,
                                                onArtist: quickArtistAction(song),
                                                onAlbum: quickAlbumAction(song),
                                                menuProvider: { quickSongMenu(song) },
                                                onSelect: {
                                                    isSearchBarFocused = false
                                                    searchViewModel.isTopdownVisible = false
                                                    playerViewModel.activateMediaRadio(song)
                                                }
                                            )
                                            .songContextMenu(song: song, player: playerViewModel, router: router, core: rustCore, origin: .search)
                                        }
                                    }
                                case .artists:
                                    ForEach(Array(results.artists.prefix(2)), id: \.id) { a in
                                        QuickResultCardRow(card: a) {
                                            isSearchBarFocused = false
                                            searchViewModel.isTopdownVisible = false
                                            router.navigate(to: .artist(browseId: a.id))
                                        }
                                        .browseCardContextMenu(card: a, player: playerViewModel, router: router, core: rustCore, origin: .search)
                                    }
                                case .songs:
                                    ForEach(Array(results.songs.prefix(3)), id: \.videoId) { s in
                                        QuickResultSongRow(
                                            song: s,
                                            onArtist: quickArtistAction(s),
                                            onAlbum: quickAlbumAction(s),
                                            menuProvider: { quickSongMenu(s) },
                                            onSelect: {
                                                isSearchBarFocused = false
                                                searchViewModel.isTopdownVisible = false
                                                playerViewModel.activateMediaRadio(s)
                                            }
                                        )
                                        .songContextMenu(song: s, player: playerViewModel, router: router, core: rustCore, origin: .search)
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
                                        .browseCardContextMenu(card: alb, player: playerViewModel, router: router, core: rustCore, origin: .search)
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
                                        .browseCardContextMenu(card: pl, player: playerViewModel, router: router, core: rustCore, origin: .search)
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
                isSearchBarFocused = false
                searchViewModel.isTopdownVisible = false
                searchViewModel.commitSearch(query: searchViewModel.query, core: rustCore, force: true)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("Presiona Enter para ver todos los resultados")
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
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
            playerViewModel.activateMediaRadio(searchViewModel.song(for: card, in: results))
        default:
            searchViewModel.commitSearch(query: card.title, core: rustCore, force: true)
        }
    }
    
    // MARK: - Barra de Chips de Filtro
    
    private var filterChipsBar: some View {
        HStack(spacing: 8) {
            ForEach(SearchFilter.allCases) { filter in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        searchViewModel.selectFilter(filter, core: rustCore)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 11, weight: .semibold))
                        
                        Text(filter.rawValue)
                            .font(.system(size: 11.5, weight: searchViewModel.selectedFilter == filter ? .semibold : .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        searchViewModel.selectedFilter == filter
                            ? Color.sidebAccent
                            : Color.white.opacity(0.08),
                        in: Capsule()
                    )
                    .foregroundStyle(searchViewModel.selectedFilter == filter ? Color.white : Color.primary.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Vista "Todo" (Resultados Mixtos)
    
    private var allResultsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if !searchViewModel.committedQuery.isEmpty {
                    let results = searchViewModel.committedResults
                    if let results, let hero = results.top.first {
                        topResultSection(hero, results: results)
                    }

                    // Las canciones filtradas son la fuente principal; las del resultado mixto quedan como respaldo.
                    let todoSongs = searchViewModel.committedSongs
                    if !todoSongs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Canciones")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                Button("Ver todas") {
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

                    if !searchViewModel.committedVideos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Videos")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button("Ver todos") {
                                    searchViewModel.selectFilter(.videos, core: rustCore)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .buttonStyle(.plain)
                            }
                            VStack(spacing: 4) {
                                ForEach(Array(searchViewModel.committedVideos.prefix(4)), id: \.videoId) { video in
                                    songInlineRow(song: video)
                                }
                            }
                        }
                    }
                    
                    if let results {
                        if !results.albums.isEmpty {
                            cardsSection(title: "Álbumes", cards: results.albums, kind: "album")
                        }
                        if !results.artists.isEmpty {
                            cardsSection(title: "Artistas", cards: results.artists, kind: "artist")
                        }
                        if !results.playlists.isEmpty {
                            cardsSection(title: "Playlists", cards: results.playlists, kind: "playlist")
                        }
                    }
                    ForEach(Array(searchViewModel.partialErrors.keys), id: \.self) { error in
                        if let message = searchViewModel.partialErrors[error] {
                            searchErrorBanner(message)
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
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .padding(.bottom, 120) // Margen para la PlayerBar flotante
        }
    }
    
    // MARK: - Tarjeta Hero / Top Result
    
    @ViewBuilder
    private func heroCardView(_ card: BrowseCardRecord, results: SearchResultsRecord) -> some View {
        if ["album", "playlist"].contains(card.kind.lowercased()) {
            collectionHeroCard(card, results: results)
        } else if ["song", "video"].contains(card.kind.lowercased()) {
            songHeroCard(card, results: results)
        } else {
            standardHeroCard(card, results: results)
        }
    }

    private func standardHeroCard(_ card: BrowseCardRecord, results: SearchResultsRecord) -> some View {
        let isArtist = card.kind.lowercased() == "artist"
        let subtitle = card.subtitle.flatMap { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        } ?? (isArtist ? "Artista" : card.kind.capitalized)
        
        let actionButton = Button {
            handleCardClick(card, results: results)
        } label: {
            HStack(spacing: 16) {
                if let thumb = card.thumbnail,
                   let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 180) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 80, height: 80)) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.secondary.opacity(0.12)
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous)))
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(isArtist ? "Ver discografía completa" : "Reproducir ahora")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                Spacer()
                Image(systemName: isArtist ? "arrow.right.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.primary)
                    .padding(.trailing, 8)
            }
            .padding(16)
            .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Mejor resultado")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
            
            if card.kind.lowercased() == "song" {
                actionButton.songContextMenu(song: searchViewModel.song(for: card, in: results), player: playerViewModel, router: router, core: rustCore, origin: .search)
            } else {
                actionButton.browseCardContextMenu(card: card, player: playerViewModel, router: router, core: rustCore, origin: .search)
            }
        }
    }

    private func collectionHeroCard(_ card: BrowseCardRecord, results: SearchResultsRecord) -> some View {
        let isActive = isActiveCollection(card)
        let artwork = Group {
            if let thumb = card.thumbnail,
               let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 180) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 80, height: 80)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.12)
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 80, height: 80)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
        }

        let hero = HStack(spacing: 16) {
            MediaArtworkControls(
                isCollection: true,
                isActive: isActive,
                isPlaying: isActive && playerViewModel.isPlaying,
                isLoading: isCollectionLoading(card),
                showsIndicator: isActive,
                accessibilityTitle: card.title,
                onOpen: { handleCardClick(card, results: results) },
                onPlay: { playerViewModel.activateMediaCollection(id: card.id, kind: card.kind) },
                menuProvider: { browseCardMenu(card) }
            ) { artwork }
                .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                Text(card.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                     ? card.subtitle! : card.kind.capitalized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                Text("Abrir detalle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }
            Spacer()
        }
        .padding(16)
        .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .mediaCardActivation(label: "Abrir \(card.title)") { handleCardClick(card, results: results) }
        .mediaCardSurface()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Mejor resultado")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
            hero.browseCardContextMenu(card: card, player: playerViewModel, router: router, core: rustCore, origin: .search)
        }
    }

    private func songHeroCard(_ card: BrowseCardRecord, results: SearchResultsRecord) -> some View {
        let song = searchViewModel.song(for: card, in: results)
        let artwork = Group {
            if let thumb = card.thumbnail,
               let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 180) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 80, height: 80)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius).fill(Color.white.opacity(0.08))
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius)
                    .fill(Color.white.opacity(0.08)).frame(width: 80, height: 80)
                    .overlay(Image(systemName: card.kind.lowercased() == "video" ? "play.rectangle" : "music.note")
                        .foregroundStyle(.secondary))
            }
        }

        let hero = HStack(spacing: 16) {
            MediaArtworkControls(
                isCollection: false,
                accessibilityTitle: card.title,
                onOpen: { playerViewModel.activateMediaRadio(song) },
                onPlay: { playerViewModel.activateMediaRadio(song) },
                menuProvider: { quickSongMenu(song) }
            ) { artwork }
                .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                HStack(spacing: 4) {
                    Text(card.kind.capitalized)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .allowsHitTesting(false)
                    if !song.artists.isEmpty {
                        Text("·").font(.system(size: 12)).foregroundStyle(.secondary)
                        if let onArtist = quickArtistAction(song) {
                            Button(action: onArtist) {
                                Text(song.artists).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .mediaCardFocusControl()
                        } else {
                            Text(song.artists).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                .allowsHitTesting(false)
                        }
                    }
                }
                if let album = song.album, !album.isEmpty, let onAlbum = quickAlbumAction(song) {
                    Button(action: onAlbum) { Text(album).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1) }
                        .buttonStyle(.plain)
                        .mediaCardFocusControl()
                }
            }
            Spacer()
        }
        .padding(16)
        .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .mediaCardActivation(label: "Reproducir \(song.title)") { playerViewModel.activateMediaRadio(song) }
        .mediaCardSurface()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Mejor resultado")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
            hero.songContextMenu(song: song, player: playerViewModel, router: router, core: rustCore, origin: .search)
        }
    }

    @ViewBuilder
    private func topResultSection(_ card: BrowseCardRecord, results: SearchResultsRecord) -> some View {
        let relatedSongs = searchViewModel.relatedSongs(for: results)
        if card.kind.lowercased() == "artist", !relatedSongs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mejor resultado")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) {
                        artistHeroCard(card, results: results, artworkSize: 104)
                            .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
                        relatedSongRows(relatedSongs)
                            .frame(minWidth: 315, maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 631)

                    VStack(alignment: .leading, spacing: 12) {
                        artistHeroCard(card, results: results, artworkSize: 84)
                        relatedSongRows(relatedSongs)
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
                }
            }
        } else if !relatedSongs.isEmpty {
            VStack(alignment: .leading, spacing: 24) {
                heroCardView(card, results: results)
                ForEach(relatedSongs, id: \.videoId) { song in
                    songInlineRow(song: song)
                }
            }
        } else {
            heroCardView(card, results: results)
        }
    }

    private func artistHeroCard(_ card: BrowseCardRecord, results: SearchResultsRecord, artworkSize: CGFloat) -> some View {
        let actionButton = Button {
            handleCardClick(card, results: results)
        } label: {
            HStack(spacing: 14) {
                if let thumb = card.thumbnail,
                   let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: Int(artworkSize * 2)) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: artworkSize, height: artworkSize)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle().fill(Color.white.opacity(0.08))
                    }
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: artworkSize, height: artworkSize)
                        .overlay {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: artworkSize * 0.36))
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(card.title)
                        .font(.system(size: artworkSize >= 100 ? 24 : 20, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let subtitle = card.subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text("Ver discografía completa")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)

        return actionButton
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            .browseCardContextMenu(card: card, player: playerViewModel, router: router, core: rustCore, origin: .search)
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
        let typeText = song.isVideo ? "Video" : "Canción"
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
                Text(song.title)
                    .font(.system(size: 14, weight: playerViewModel.currentTrack?.videoId == song.videoId ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
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
        .mediaCardActivation(label: "Reproducir \(song.title)") { playerViewModel.activateMediaRadio(song) }
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
                .padding(.horizontal, 24)
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
        .mediaCardActivation(label: "Abrir \(card.title)") { handleCardClick(card) }
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
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 40, height: 40)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous).fill(Color.white.opacity(0.06))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06)).frame(width: 40, height: 40)
                }
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 13, weight: playerViewModel.currentTrack?.videoId == song.videoId ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                HStack(spacing: 4) {
                    if let onArtist = quickArtistAction(song) {
                        Button(action: onArtist) { Text(song.artists).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                            .buttonStyle(.plain)
                            .mediaCardFocusControl()
                    } else {
                        Text(song.artists).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    if let album = song.album, !album.isEmpty, let onAlbum = quickAlbumAction(song) {
                        Text("·").font(.system(size: 11)).foregroundStyle(.tertiary)
                        Button(action: onAlbum) { Text(album).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                            .buttonStyle(.plain)
                            .mediaCardFocusControl()
                    }
                    if let album = song.album, !album.isEmpty, quickAlbumAction(song) == nil {
                        Text("·").font(.system(size: 11)).foregroundStyle(.tertiary).allowsHitTesting(false)
                        Text(album).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let dur = song.duration {
                Text(dur).font(.system(size: 11)).foregroundStyle(.tertiary).allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))
        .contentShape(Rectangle())
        .mediaCardActivation(label: "Reproducir \(song.title)") { playerViewModel.activateMediaRadio(song) }
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
                playerViewModel.activateMediaRadio(searchViewModel.song(for: card, in: results))
            }
        default:
            return nil
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

    private func quickSongMenu(_ song: SongItemRecord) -> NSMenu? {
        AppContextMenuFactory.shared.buildSongNSMenu(
            song: song, player: playerViewModel, router: router, core: rustCore, origin: .search
        )
    }

    private func searchErrorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func filteredResultsView<Content: View>(error: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error {
                searchErrorBanner(error)
                    .padding(.horizontal, 24)
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
            Text("Buscando en el catálogo...")
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
            
            Text("No se encontraron resultados para \"\(searchViewModel.committedQuery)\"")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Text("Verifica la ortografía o intenta buscar por otro artista o título.")
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
            
            Text("Explora el catálogo de música")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Text("Escribe en la barra superior para buscar canciones, artistas o álbumes.")
                .font(.system(size: 12.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
