import SwiftUI
import AppKit
import SideBCore

// MARK: - SpotlightSearchModal

struct SpotlightSearchModal: View {
    @Binding var isPresented: Bool
    @Bindable var searchViewModel: SearchViewModel
    @Bindable var router: NavigationRouter
    var playerViewModel: PlayerViewModel
    let rustCore: SideBCore
    
    @FocusState private var isFieldFocused: Bool
    
    var body: some View {
        GeometryReader { proxy in
            let totalHeight = proxy.size.height
            // PlayerBar mide 74pt de altura + 20pt de padding inferior en SideBApp = 94pt
            let playerBarTotalHeight: CGFloat = 94.0
            let availableHeight = max(280, totalHeight - playerBarTotalHeight)
            let hasQuery = !searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let modalHeight = min(hasQuery ? 540 : 220, max(180, availableHeight - 80))
            let modalWidth = min(max(proxy.size.width - 48, 360), 620)
            
            ZStack(alignment: .top) {
                // Fondo atenuado translúcido con clic para descartar (cubre toda la ventana)
                Color.black.opacity(0.45)
                    .frame(width: proxy.size.width, height: totalHeight)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }
                
                // Tarjeta Flotante Tipo Spotlight centrada simétricamente entre el borde superior y la PlayerBar
                VStack(spacing: 0) {
                    // Barra de Búsqueda Superior
                    searchFieldHeader
                    
                    Divider()
                        .opacity(0.18)
                    
                    // Área de Resultados Rápidos Dinámicos
                    resultsScrollView
                    
                    // Pie de página: Atajo para Búsqueda Completa
                    if !searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Divider()
                            .opacity(0.15)
                        
                        bottomCommitBar
                    }
                }
                .frame(width: modalWidth)
                .frame(height: modalHeight)
                .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.black.opacity(0.40), radius: 28, x: 0, y: 14)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .frame(height: availableHeight, alignment: .center)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                    removal: .scale(scale: 0.96).combined(with: .opacity)
                ))
            }
            .frame(width: proxy.size.width, height: totalHeight)
        }
        .defaultFocus($isFieldFocused, true)
        .onExitCommand {
            dismiss()
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .task {
            isFieldFocused = true
            // Respaldo de timing en AppKit para asegurar que el responder chain active el cursor
            try? await Task.sleep(for: .milliseconds(60))
            isFieldFocused = true
        }
        .onAppear {
            if !searchViewModel.query.isEmpty && searchViewModel.quickResults == nil {
                searchViewModel.onQueryChanged(searchViewModel.query, core: rustCore)
            }
        }
        .onDisappear {
            searchViewModel.cancelPreview()
        }
    }
    
    // MARK: - Cabecera de Entrada de Búsqueda
    
    private var searchFieldHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
            
            TextField("Buscar canciones, álbumes, artistas, playlists...", text: $searchViewModel.query)
                .font(.system(size: 16, weight: .regular))
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .onChange(of: isFieldFocused) { _, isFocused in
                    if !isFocused { searchViewModel.cancelPreview() }
                }
                .onSubmit {
                    commitAndNavigate()
                }
                .onChange(of: searchViewModel.query) { _, newText in
                    if isPresented && isFieldFocused {
                        searchViewModel.onQueryChanged(newText, core: rustCore)
                    }
                }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
            
            if searchViewModel.isQuickSearching {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
            } else if !searchViewModel.query.isEmpty {
                Button {
                    searchViewModel.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Atajo Esc para salir
            Text("ESC")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            isFieldFocused = true
        }
    }
    
    // MARK: - Resultados Rápidos con Categorías Dinámicas
    
    private var resultsScrollView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                let trimmed = searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if trimmed.isEmpty {
                    emptySearchPlaceholder
                } else if searchViewModel.isQuickSearching && (searchViewModel.quickResults == nil || searchViewModel.associatedQuickQuery != trimmed) {
                    searchLoadingPlaceholder
                } else if let results = searchViewModel.quickResults, searchViewModel.associatedQuickQuery == trimmed {
                    let categories = searchViewModel.dynamicCategories(for: results)
                    
                    if categories.isEmpty {
                        noResultsFoundView
                    } else {
                        ForEach(categories) { category in
                            categorySection(category: category, results: results)
                        }
                    }
                } else if searchViewModel.isQuickSearching {
                    searchLoadingPlaceholder
                } else if let message = searchViewModel.quickErrorMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                } else {
                    noResultsFoundView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
    
    // MARK: - Secciones de Categorías
    
    @ViewBuilder
    private func categorySection(category: SearchCategory, results: SearchResultsRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Cabecera de Categoría
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(category == .topResult ? .primary : .secondary)
                
                Text(category.rawValue.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(category == .topResult ? .primary : .secondary)
                    .tracking(0.6)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
            
            // Contenido por Categoría
            switch category {
            case .topResult:
                if let hero = results.top.first {
                    let row = QuickResultCardRow(card: hero, isHero: true,
                        isActive: MediaPlaybackIdentity.isCollectionActive(kind: hero.kind, id: hero.id, context: playerViewModel.queueManager.context),
                        isPlaying: playerViewModel.isPlaying,
                        onPlay: { playQuickCard(hero, results: results) },
                        menuProvider: { quickCardMenu(hero, results: results) }) {
                        handleCardSelected(hero, results: results)
                    }
                    if hero.kind.lowercased() == "song" {
                        row.songContextMenu(song: searchViewModel.song(for: hero, in: results), player: playerViewModel, router: router, core: rustCore, origin: .search)
                    } else {
                        row.browseCardContextMenu(card: hero, player: playerViewModel, router: router, core: rustCore, origin: .search)
                    }
                    ForEach(searchViewModel.relatedSongs(for: results), id: \.videoId) { song in
                        quickSongRow(song)
                        .songContextMenu(song: song, player: playerViewModel, router: router, core: rustCore, origin: .search)
                    }
                }
                
            case .artists:
                ForEach(Array(results.artists.prefix(5)), id: \.id) { artist in
                    QuickResultCardRow(card: artist) {
                        playerViewModel.dismissFullscreen()
                        dismiss()
                        router.navigate(to: .artist(browseId: artist.id))
                    }
                    .browseCardContextMenu(card: artist, player: playerViewModel, router: router, core: rustCore, origin: .search)
                }
                
            case .songs:
                ForEach(Array(results.songs.prefix(8)), id: \.videoId) { song in
                    quickSongRow(song)
                    .songContextMenu(song: song, player: playerViewModel, router: router, core: rustCore, origin: .search)
                }
                
            case .albums:
                ForEach(Array(results.albums.prefix(5)), id: \.id) { album in
                    QuickResultCardRow(card: album,
                        isActive: MediaPlaybackIdentity.isCollectionActive(kind: album.kind, id: album.id, context: playerViewModel.queueManager.context),
                        isPlaying: playerViewModel.isPlaying,
                        onPlay: { playerViewModel.activateMediaCollection(id: album.id, kind: album.kind) },
                        menuProvider: { quickCardMenu(album, results: results) }) {
                        playerViewModel.dismissFullscreen()
                        dismiss()
                        router.navigate(to: .album(browseId: album.id))
                    }
                    .browseCardContextMenu(card: album, player: playerViewModel, router: router, core: rustCore, origin: .search)
                }
                
            case .playlists:
                ForEach(Array(results.playlists.prefix(5)), id: \.id) { pl in
                    QuickResultCardRow(card: pl,
                        isActive: MediaPlaybackIdentity.isCollectionActive(kind: pl.kind, id: pl.id, context: playerViewModel.queueManager.context),
                        isPlaying: playerViewModel.isPlaying,
                        onPlay: { playerViewModel.activateMediaCollection(id: pl.id, kind: pl.kind) },
                        menuProvider: { quickCardMenu(pl, results: results) }) {
                        playerViewModel.dismissFullscreen()
                        dismiss()
                        router.navigate(to: .playlist(browseId: pl.id))
                    }
                    .browseCardContextMenu(card: pl, player: playerViewModel, router: router, core: rustCore, origin: .search)
                }
            }
        }
    }
    
    private func quickSongRow(_ song: SongItemRecord) -> some View {
        let artistID = (song.artistId ?? song.artistRuns.first(where: { $0.id != nil })?.id)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let albumID = song.albumId.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return QuickResultSongRow(song: song,
            onArtist: artistID.map { id in { openQuickDestination(.artist(browseId: id)) } },
            onAlbum: albumID.map { id in { openQuickDestination(.album(browseId: id)) } },
            menuProvider: { AppContextMenuFactory.shared.buildSongNSMenu(song: song, player: playerViewModel,
                router: router, core: rustCore, origin: .search) }) {
                playerViewModel.activateMediaRadio(song)
                dismiss()
            }
    }

    private func openQuickDestination(_ destination: PageDestination) {
        playerViewModel.dismissFullscreen()
        dismiss()
        router.navigate(to: destination)
    }

    private func playQuickCard(_ card: BrowseCardRecord, results: SearchResultsRecord) {
        if ["song", "video"].contains(card.kind.lowercased()) {
            playerViewModel.activateMediaRadio(searchViewModel.song(for: card, in: results))
        } else {
            playerViewModel.activateMediaCollection(id: card.id, kind: card.kind)
        }
    }

    private func quickCardMenu(_ card: BrowseCardRecord, results: SearchResultsRecord) -> NSMenu {
        switch card.kind.lowercased() {
        case "song", "video":
            return AppContextMenuFactory.shared.buildSongNSMenu(song: searchViewModel.song(for: card, in: results),
                player: playerViewModel, router: router, core: rustCore, origin: .search)
        case "album":
            return AppContextMenuFactory.shared.buildAlbumNSMenu(browseId: card.id, playlistId: nil,
                title: card.title, artist: card.subtitle, thumbnail: card.thumbnail,
                origin: .search, player: playerViewModel, router: router, core: rustCore)
        case "artist":
            return AppContextMenuFactory.shared.buildArtistNSMenu(channelId: card.id, name: card.title,
                thumbnail: card.thumbnail, radioPlaylistId: nil, origin: .search,
                player: playerViewModel, router: router, core: rustCore)
        default:
            return AppContextMenuFactory.shared.buildPlaylistNSMenu(id: card.id, title: card.title,
                subtitle: card.subtitle, thumbnail: card.thumbnail, origin: .search,
                player: playerViewModel, router: router, core: rustCore)
        }
    }

    // MARK: - Manejo de Clic en Tarjeta Top
    
    private func handleCardSelected(_ card: BrowseCardRecord, results: SearchResultsRecord) {
        playerViewModel.dismissFullscreen()
        switch card.kind.lowercased() {
        case "artist":
            dismiss()
            router.navigate(to: .artist(browseId: card.id))
        case "album":
            dismiss()
            router.navigate(to: .album(browseId: card.id))
        case "playlist":
            dismiss()
            router.navigate(to: .playlist(browseId: card.id))
        case "song", "video":
            playerViewModel.activateMediaRadio(searchViewModel.song(for: card, in: results))
            dismiss()
        default:
            dismiss()
            router.navigate(to: .search(query: card.title))
        }
    }
    
    // MARK: - Barra Inferior de Confirmación
    
    private var bottomCommitBar: some View {
        Button(action: commitAndNavigate) {
            HStack(spacing: 8) {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(4)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                
                Text("Ver todos los resultados para")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.secondary)
                
                Text("\"\(searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                Text("Enter")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Placeholders y Estados Vacíos
    
    private var emptySearchPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(.top, 16)
            
            Text("Busca artistas, canciones, álbumes y más")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text("Escribe para ver resultados rápidos categorizados en tiempo real")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }
    
    private var noResultsFoundView: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(.top, 16)
            
            Text("No se encontraron resultados rápidos")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text("Pulsa Enter para realizar una búsqueda completa en el catálogo")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
    }
    
    private var searchLoadingPlaceholder: some View {
        VStack(spacing: 12) {
            ForEach(0..<3) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 38, height: 38)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 140, height: 12)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.04))
                            .frame(width: 90, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Acciones
    
    private func dismiss() {
        searchViewModel.cancelPreview()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            isPresented = false
        }
    }
    
    private func commitAndNavigate() {
        let q = searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        playerViewModel.dismissFullscreen()
        dismiss()
        searchViewModel.commitSearch(query: q, core: rustCore)
        router.navigate(to: .search(query: q))
    }
}
