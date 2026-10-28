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
    @State private var scrollingHeaderHeight: CGFloat = 220
    
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
            
            // Each presentation owns one vertical viewport, including its header.
            // Track results keep their bounded NSTableView instead of expanding it
            // inside another vertical ScrollView.
            if trackErrorBlock != nil {
                nativeTrackTableView(tracks: searchViewModel.selectedFilter == .songs
                    ? searchViewModel.filteredSongs : searchViewModel.committedVideos)
            } else if usesProviderViewport {
                ProviderSearchPageView(page: searchViewModel.providerPage, model: searchViewModel,
                    player: playerViewModel, router: router, core: rustCore,
                    scrollingHeader: AnyView(pageHeader))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        pageHeader
                            .zIndex(10)
                        if isResultsLoading {
                            loadingStateView
                        } else if let page = searchViewModel.providerPage {
                            ProviderSearchPageView(page: page, model: searchViewModel, player: playerViewModel,
                                router: router, core: rustCore)
                        } else if searchViewModel.selectedFilter == .all {
                            allResultsContent
                        } else {
                            filteredResultsView(error: searchViewModel.partialErrors[.categories]) {
                                cardsGridView(cards: searchViewModel.filteredCards,
                                    kind: searchViewModel.selectedFilter == .artists ? "artist"
                                        : searchViewModel.selectedFilter == .albums ? "album" : "playlist")
                            }
                        }
                    }
                    .padding(.bottom, 120)
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
                searchViewModel.commitSearch(query: searchViewModel.committedQuery, core: rustCore, force: true, preservingPreview: true, params: searchViewModel.providerParams)
            }
        }
        .onDisappear {
            releasePagePreview()
        }
    }

    private var isResultsLoading: Bool {
        (searchViewModel.isCommittedLoading && searchViewModel.committedResults == nil
            && searchViewModel.committedSongs.isEmpty && searchViewModel.committedVideos.isEmpty)
            || searchViewModel.isFilterLoading
            || (searchViewModel.selectedFilter == .songs && searchViewModel.isSongsLoading && searchViewModel.filteredSongs.isEmpty)
            || (searchViewModel.selectedFilter == .videos && searchViewModel.isVideosLoading && searchViewModel.committedVideos.isEmpty)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("search.title"))
                .font(.system(size: 30, weight: .bold))
            topSearchBar
                .zIndex(20)
            filterChipsBar
            if searchViewModel.isOriginalSearch {
                Text(L10n.text("search.correction.original_results"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let block = trackErrorBlock, let message = searchViewModel.partialErrors[block] {
                searchErrorBanner(message, retry: { searchViewModel.retryBlock(block, core: rustCore) })
            }
        }
        .padding(.horizontal, usesProviderViewport ? 0 : (trackErrorBlock == nil ? 38.4 : 14.4))
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if abs(scrollingHeaderHeight - height) > 0.5 { scrollingHeaderHeight = height }
        }
    }

    private var trackErrorBlock: SearchPartialError? {
        searchViewModel.selectedFilter == .songs ? .songs : searchViewModel.selectedFilter == .videos ? .videos : nil
    }

    private var usesProviderViewport: Bool {
        !searchViewModel.committedQuery.isEmpty && searchViewModel.selectedFilter == .all
            && (searchViewModel.providerPage != nil || searchViewModel.isCommittedLoading
                || searchViewModel.isMixedLoading || searchViewModel.committedResults == nil)
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
                .onSubmit { submitProviderSelection() }
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
        .background {
            SearchPagePreviewAnchor(content: isSearchBarFocused && searchViewModel.isTopdownVisible
                ? AnyView(pageSearchPreview) : nil, onDismiss: {
                    selectedSuggestion = nil
                    isSearchBarFocused = false
                    releasePagePreview()
                })
        }
    }

    // The native anchor hosts this above the results, outside the header's
    // measured height, so opening suggestions never moves chips or rows.
    @ViewBuilder
    private var pageSearchPreview: some View {
        if isSearchBarFocused && searchViewModel.isTopdownVisible {
            VStack(spacing: 4) {
                if searchViewModel.isQuickSearching {
                    topdownLoadingView
                } else if searchViewModel.associatedQuickQuery == searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines) {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(searchViewModel.visibleProviderSuggestions, id: \.id) { entry in
                                ProviderSearchSuggestionRow(entry: entry, selected: selectedSuggestion == entry.id,
                                    removing: searchViewModel.removingSuggestionIDs.contains(entry.id),
                                    player: playerViewModel, router: router, core: rustCore,
                                    onActivate: { activateProviderSuggestion(entry) },
                                    onRemove: { Task { await searchViewModel.removeProviderSuggestion(entry, core: rustCore) } },
                                    onNavigate: { destination in
                                        isSearchBarFocused = false; releasePagePreview(); router.navigate(to: destination)
                                    })
                            }
                        }.padding(8)
                    }.frame(height: min(340, CGFloat(max(1, searchViewModel.visibleProviderSuggestions.count) * 58 + 16)))
                }
                if let message = searchViewModel.quickErrorMessage { searchErrorBanner(message) }
            }
            .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        }
    }

    private func submitProviderSelection() {
        if let entry = searchViewModel.visibleProviderSuggestions.first(where: { $0.id == selectedSuggestion }) {
            activateProviderSuggestion(entry)
        } else { commitPageQuery(searchViewModel.query) }
    }

    private func activateProviderSuggestion(_ entry: SearchSuggestionEntryRecord) {
        isSearchBarFocused = false
        selectedSuggestion = nil
        releasePagePreview()
        if let song = entry.song { playerViewModel.activateMediaRadio(song) }
        else if let card = entry.card { handleCardClick(card) }
        else if let query = entry.query { commitPageQuery(query) }
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
    
    private func moveSuggestion(_ delta: Int) {
        selectedSuggestion = QuickSearchSelection.nextKey(in: searchViewModel.visibleProviderSuggestions.map(\.id),
            selected: selectedSuggestion, delta: delta)
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
        SearchFilterChips(chips: searchViewModel.providerPage?.chips ?? [],
            gestureRegionActive: !playerViewModel.isFullscreenPresented,
            onSelect: { searchViewModel.selectProviderChip($0, core: rustCore) })
    }

    // MARK: - Vista "Todo" (Resultados Mixtos)
    
    private var allResultsContent: some View {
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
                ContentRatedMetadata(rating: song.contentRating, fontSize: 12) {
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
    
    // MARK: - Canciones y videos con cabecera dentro de la tabla virtualizada

    private func nativeTrackTableView(tracks: [SongItemRecord]) -> some View {
        let displayedTracks = isResultsLoading ? [] : tracks
        return NativeTrackTableView(
            tracks: displayedTracks,
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
                if index >= 0 && index < displayedTracks.count {
                    playerViewModel.activateMediaRadio(displayedTracks[index])
                }
            },
            onLikeTrack: { track in
                playerViewModel.toggleTrackLike(track)
            },
            onDislikeTrack: { track in
                playerViewModel.dislikeTrack(track)
            },
            contentInsets: NSEdgeInsets(top: 0, left: 24, bottom: 120, right: 24),
            scrollingHeader: AnyView(pageHeader),
            scrollingHeaderHeight: scrollingHeaderHeight,
            footer: displayedTracks.isEmpty ? AnyView(Group {
                if isResultsLoading { loadingStateView }
                else { noResultsView }
            }) : nil,
            footerHeight: 220
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Group {
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
                        ContentRatedMetadata(rating: card.contentRating, fontSize: 11) { Text(subtitle) }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if card.contentRating != .unknown {
                        ContentRatingBadge(rating: card.contentRating, fontSize: 11)
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
                ContentRatedMetadata(rating: song.contentRating, fontSize: 12) {
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
        .frame(maxWidth: .infinity, minHeight: 220)
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
