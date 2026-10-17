import SwiftUI
import AppKit
import Combine
import SideBCore

/// Commands from an external editor. A revision allows repeated presses of the same key.
struct QuickSearchCommand: Equatable {
    enum Kind: Equatable { case moveUp, moveDown, submit }
    let kind: Kind
    let revision: Int
}

/// Preserve every key press even when SwiftUI coalesces multiple state updates.
@MainActor
final class QuickSearchCommandChannel {
    let commands = PassthroughSubject<QuickSearchCommand.Kind, Never>()
}

/// Primary selection stays attached to an entity when provider results are replaced.
enum QuickSearchSelection {
    static func nextKey(in keys: [String], selected: String?, delta: Int) -> String? {
        guard !keys.isEmpty else { return nil }
        let current = selected.flatMap { keys.firstIndex(of: $0) } ?? -1
        let next = min(max(current + delta, -1), keys.count - 1)
        return next >= 0 ? keys[next] : nil
    }

    static func retainedKey(in keys: [String], selected: String?) -> String? {
        selected.flatMap { keys.contains($0) ? $0 : nil }
    }
}

/// Shared results, selection, and actions for both permanent quick-search entry points.
struct QuickSearchContentView: View {
    enum Style { case spotlight, anchored }
    @Binding var isPresented: Bool
    @Binding var draft: String
    @Bindable var searchViewModel: SearchViewModel
    @Bindable var router: NavigationRouter
    var playerViewModel: PlayerViewModel
    let rustCore: SideBCore
    var style: Style = .spotlight
    var command: QuickSearchCommand? = nil
    var commandChannel: QuickSearchCommandChannel? = nil
    var onSelectionLabelChange: ((String?) -> Void)? = nil
    var onRestoreFocus: (() -> Void)? = nil

    @State private var previewOwner = UUID()
    @State private var isActive = false
    @State private var recentStore = SearchRecentStore.shared
    @State private var selectedRecentKey: String?
    @State private var restoresFocusOnDismiss = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Group {
            switch style {
            case .spotlight: spotlightPresentation
            case .anchored:
                resultsContent
                    .onExitCommand { dismiss() }
                    .onKeyPress(.escape) { dismiss(); return .handled }
                    .onKeyPress(.upArrow) { selectRecent(delta: -1); return .handled }
                    .onKeyPress(.downArrow) { selectRecent(delta: 1); return .handled }
            }
        }
        .onAppear {
            isActive = true
            restoresFocusOnDismiss = false
            if isPresented {
                searchViewModel.claimPreview(owner: previewOwner)
                requestPreview()
            }
            onSelectionLabelChange?(keyboardSelectionLabel)
        }
        .onChange(of: isPresented) { _, presented in
            guard isActive else { return }
            if presented {
                restoresFocusOnDismiss = false
                searchViewModel.claimPreview(owner: previewOwner)
                requestPreview()
            } else {
                searchViewModel.cancelPreview(owner: previewOwner)
                selectedRecentKey = nil
            }
        }
        .onChange(of: draft) { _, _ in
            guard isActive, isPresented else { return }
            selectedRecentKey = nil
            requestPreview()
        }
        .onChange(of: keyboardActions.map(\.key)) { _, keys in
            selectedRecentKey = QuickSearchSelection.retainedKey(in: keys, selected: selectedRecentKey)
        }
        .onChange(of: keyboardSelectionLabel) { _, label in onSelectionLabelChange?(label) }
        .onChange(of: command) { _, command in
            guard isActive, isPresented, let command else { return }
            handleCommand(command.kind)
        }
        .onReceive(commandChannel?.commands.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { command in
            guard isActive, isPresented else { return }
            handleCommand(command)
        }
        .onDisappear {
            isActive = false
            searchViewModel.cancelPreview(owner: previewOwner)
            if !isPresented, restoresFocusOnDismiss { onRestoreFocus?() }
        }
    }

    private var resultsContent: some View {
        VStack(spacing: 0) {
            resultsScrollView
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider().opacity(0.15)
                bottomCommitBar
            }
        }
    }

    private var spotlightPresentation: some View {
        GeometryReader { proxy in
            let totalHeight = proxy.size.height
            // PlayerBar mide 74pt de altura + 20pt de padding inferior en SideBApp = 94pt
            let playerBarTotalHeight: CGFloat = 94.0
            let availableHeight = max(280, totalHeight - playerBarTotalHeight)
            let hasQuery = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let recentHeight = min(540, max(220, 96 + recentStore.entries.reduce(0) { $0 + ($1.kind == "track" ? 66 : 50) } + (recentStore.unavailableTrack == nil ? 0 : 86)))
            let modalHeight = min(hasQuery ? 540 : CGFloat(recentHeight), max(180, availableHeight - 80))
            let modalWidth = min(max(proxy.size.width - 48, 360), 780)

            ZStack(alignment: .top) {
                // Fondo atenuado translúcido con clic para descartar (cubre toda la ventana)
                Color.black.opacity(0.45)
                    .frame(width: proxy.size.width, height: totalHeight)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss(restoreFocus: true)
                    }

                // Tarjeta Flotante Tipo Spotlight centrada simétricamente entre el borde superior y la PlayerBar
                VStack(spacing: 0) {
                    // Barra de Búsqueda Superior
                    searchFieldHeader

                    Divider()
                        .opacity(0.18)

                    resultsContent
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
        .onKeyPress(.downArrow) { selectRecent(delta: 1); return .handled }
        .onKeyPress(.upArrow) { selectRecent(delta: -1); return .handled }
        .onExitCommand {
            dismiss(restoreFocus: true)
        }
        .onKeyPress(.escape) {
            dismiss(restoreFocus: true)
            return .handled
        }
        .task {
            isFieldFocused = true
            // Respaldo de timing en AppKit para asegurar que el responder chain active el cursor
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, isPresented else { return }
            isFieldFocused = true
        }
    }

    private var recentResults: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.text("search.recents.title")).font(.system(size: 12, weight: .semibold))
                Spacer()
                if !recentStore.entries.isEmpty { Button(L10n.text("search.recents.clear")) { recentStore.clear(); selectedRecentKey = nil }.buttonStyle(.plain) }
                if recentStore.canUndo { Button(L10n.text("common.undo")) { recentStore.undo() }.buttonStyle(.plain) }
            }.font(.system(size: 11)).padding(.horizontal, 8).padding(.bottom, 6)
            ForEach(recentStore.entries) { recent in
                HStack(spacing: 8) {
                    if let track = recent.track {
                        quickSongRow(track.song)
                    } else {
                        Button { activateRecent(recent) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass").frame(width: 42)
                                Text(recent.query ?? "").lineLimit(1)
                                Spacer()
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    Button { recentStore.remove(recent.key); selectedRecentKey = nil } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                        .buttonStyle(.plain).padding(8).accessibilityLabel(L10n.text("search.recents.remove"))
                }.padding(8).background(selectedRecentKey == recent.key ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8)).id(recent.key).accessibilityAddTraits(selectedRecentKey == recent.key ? .isSelected : [])
            }
        }
        .onKeyPress(.downArrow) { selectRecent(delta: 1); return .handled }
        .onKeyPress(.upArrow) { selectRecent(delta: -1); return .handled }
    }
    private enum Action {
        case recent(SearchRecentStore.Entry), suggestion(String), song(SongItemRecord), card(BrowseCardRecord, SearchResultsRecord)
        var key: String {
            switch self {
            case .recent(let entry): return entry.key
            case .suggestion(let text): return "query:" + text
            case .song(let song): return (song.isVideo ? "video:" : "song:") + song.videoId
            case .card(let card, _): return card.kind + ":" + card.id
            }
        }
    }
    private var keyboardActions: [Action] {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return recentStore.entries.map(Action.recent) }
        guard searchViewModel.associatedQuickQuery == draft.trimmingCharacters(in: .whitespacesAndNewlines), let source = searchViewModel.quickResults else { return [] }
        let results = SearchProjection.suggestions(source, budget: 8)
        return searchViewModel.querySuggestions.map(Action.suggestion) + results.top.map { card in
            ["song", "video"].contains(card.kind.lowercased())
                ? Action.song(searchViewModel.song(for: card, in: results)) : Action.card(card, results)
        }
    }
    private var keyboardSelectionLabel: String? {
        guard let selectedRecentKey, let action = keyboardActions.first(where: { $0.key == selectedRecentKey }) else { return nil }
        switch action {
        case .suggestion(let text): return text
        case .recent(let entry): return entry.query ?? entry.track.map { $0.title + " · " + $0.artists }
        case .song(let song): return song.title + " · " + song.artists
        case .card(let card, _): return card.title
        }
    }
    private func selectRecent(delta: Int) {
        selectedRecentKey = QuickSearchSelection.nextKey(in: keyboardActions.map(\.key), selected: selectedRecentKey, delta: delta)
    }
    private func activateSelected() -> Bool {
        guard let key = selectedRecentKey, let action = keyboardActions.first(where: { $0.key == key }) else { return false }
        switch action {
        case .recent(let entry): activateRecent(entry)
        case .song(let song): playerViewModel.activateSearchMediaRadio(song); dismiss()
        case .suggestion(let text): draft = text; commitAndNavigate()
        case .card(let card, let results): handleCardSelected(card, results: results)
        }
        return true
    }

    private func activateRecent(_ entry: SearchRecentStore.Entry) {
        if let track = entry.track { playerViewModel.activateSearchMediaRadio(track.song); dismiss() }
        else if let query = entry.query {
            playerViewModel.dismissFullscreen(); dismiss()
            searchViewModel.commitSearch(query: query, core: rustCore, origin: .recentQuery)
            router.navigate(to: .search(query: query))
        }
    }

    // MARK: - Cabecera de Entrada de Búsqueda

    private var searchFieldHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)

            TextField(L10n.text("search.spotlight.placeholder"), text: $draft)
                .font(.system(size: 16, weight: .regular))
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .accessibilityHint(keyboardSelectionLabel ?? L10n.text("search.spotlight.submit_hint"))
                .onSubmit { submitSelection() }
                .onKeyPress(.escape) {
                    dismiss(restoreFocus: true)
                    return .handled
                }

            if searchViewModel.isQuickSearching {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
            } else if !draft.isEmpty {
                Button {
                    draft = ""
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
        ScrollViewReader { scroll in
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)

                if trimmed.isEmpty {
                    if let unavailable = recentStore.unavailableTrack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("search.recents.unavailable")).font(.system(size: 12)).foregroundStyle(.secondary)
                            HStack {
                                Button(L10n.text("search.recents.search_track")) {
                                    let query = unavailable.title + " " + unavailable.artists
                                    dismiss(); searchViewModel.commitSearch(query: query, core: rustCore, origin: .submit)
                                    router.navigate(to: .search(query: query))
                                }
                                Button(L10n.text("search.recents.remove")) { recentStore.remove("track:" + (unavailable.isUpload ? "upload:" : "youtube:") + unavailable.videoId) }
                            }.buttonStyle(.plain).font(.system(size: 11))
                        }.padding(8)
                    }
                    if recentStore.entries.isEmpty && !recentStore.canUndo { emptySearchPlaceholder }
                    else { recentResults }
                } else if searchViewModel.isQuickSearching && (searchViewModel.quickResults == nil || searchViewModel.associatedQuickQuery != trimmed) {
                    searchLoadingPlaceholder
                } else if let results = searchViewModel.quickResults, searchViewModel.associatedQuickQuery == trimmed {
                    let results = SearchProjection.suggestions(results, budget: 8)
                    let categories = searchViewModel.dynamicCategories(for: results)

                    if !searchViewModel.querySuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.text("search.suggestions.title")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10)
                            ForEach(searchViewModel.querySuggestions, id: \.self) { text in
                                Button { draft = text; commitAndNavigate() } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).frame(width: 42)
                                        Text(text).font(.system(size: 15)).lineLimit(1)
                                        Spacer()
                                        Image(systemName: "arrow.up.left").font(.system(size: 12)).foregroundStyle(.tertiary)
                                    }.padding(.horizontal, 10).frame(minHeight: 48).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                .background(selectedRecentKey == "query:" + text ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                .id("query:" + text)
                            }
                        }
                    }
                    if categories.isEmpty && searchViewModel.querySuggestions.isEmpty {
                        noResultsFoundView
                    } else {
                        ForEach(categories) { category in
                            categorySection(category: category, results: results)
                        }
                    }
                } else if searchViewModel.isQuickSearching {
                    searchLoadingPlaceholder
                } else if let message = searchViewModel.quickErrorMessage {
                    HStack {
                        Label(message, systemImage: "exclamationmark.circle")
                        Button(L10n.text("common.retry")) { requestPreview() }.buttonStyle(.plain)
                    }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 8)
                } else {
                    noResultsFoundView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .onChange(of: selectedRecentKey) { _, key in if let key { scroll.scrollTo(key, anchor: .center) } }
        }
    }

    // MARK: - Secciones de Categorías

    @ViewBuilder
    private func categorySection(category: SearchCategory, results: SearchResultsRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if category != .topResult {
                Text(category.displayTitle)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.bottom, 2)
            }

            // Contenido por Categoría
            switch category {
            case .topResult:
                ForEach(results.top, id: \.searchEntityKey) { hero in
                    if ["song", "video"].contains(hero.kind.lowercased()) {
                        let song = searchViewModel.song(for: hero, in: results)
                        quickSongRow(song)
                            .songContextMenu(song: song, player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                    } else {
                    let row = QuickResultCardRow(card: hero, isHero: true,
                        isActive: MediaPlaybackIdentity.isCollectionActive(kind: hero.kind, id: hero.id, context: playerViewModel.queueManager.context),
                        isPlaying: playerViewModel.isPlaying,
                        onPlay: { playQuickCard(hero, results: results) },
                        menuProvider: { quickCardMenu(hero, results: results) }) {
                        handleCardSelected(hero, results: results)
                    }
                    .background(selectedRecentKey == hero.kind + ":" + hero.id ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .id(hero.kind + ":" + hero.id)
                    if hero.kind.lowercased() == "song" {
                        row.songContextMenu(song: searchViewModel.song(for: hero, in: results), player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                    } else {
                        row.browseCardContextMenu(card: hero, player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                    }
                    }

                }

            case .artists:
                ForEach(Array(results.artists.prefix(5)), id: \.id) { artist in
                    QuickResultCardRow(card: artist) {
                        playerViewModel.dismissFullscreen()
                        dismiss()
                        router.navigate(to: .artist(browseId: artist.id))
                    }
                    .browseCardContextMenu(card: artist, player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                    .background(selectedRecentKey == artist.kind + ":" + artist.id ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .id(artist.kind + ":" + artist.id)
                }

            case .songs:
                ForEach(Array(results.songs.prefix(8)), id: \.videoId) { song in
                    quickSongRow(song)
                    .songContextMenu(song: song, player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
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
                    .browseCardContextMenu(card: album, player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                    .background(selectedRecentKey == album.kind + ":" + album.id ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .id(album.kind + ":" + album.id)
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
                    .browseCardContextMenu(card: pl, player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
                    .background(selectedRecentKey == pl.kind + ":" + pl.id ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .id(pl.kind + ":" + pl.id)
                }
            }
        }
    }

    private func quickSongRow(_ song: SongItemRecord) -> some View {
        let artistID = (song.artistId ?? song.artistRuns.first(where: { $0.id != nil })?.id)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let albumID = song.albumId.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return QuickResultSongRow(song: song, onFeatured: { id, name in openQuickFeatured(id: id, name: name) },
            onArtist: artistID.map { id in { openQuickDestination(.artist(browseId: id)) } },
            onAlbum: albumID.map { id in { openQuickDestination(.album(browseId: id)) } },
            menuProvider: { AppContextMenuFactory.shared.buildSongNSMenu(song: song, player: playerViewModel,
                router: router, core: rustCore, origin: .searchSpotlight) }) {
                playerViewModel.activateSearchMediaRadio(song)
                dismiss()
            }
            .background(selectedRecentKey == (song.isVideo ? "video:" : "song:") + song.videoId ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .id((song.isVideo ? "video:" : "song:") + song.videoId)
    }

    private func openQuickFeatured(id: String?, name: String) {
        playerViewModel.dismissFullscreen(); dismiss()
        if let id { router.navigate(to: .artist(browseId: id)) }
        else { searchViewModel.commitSearch(query: name, core: rustCore, origin: .artistResolution); router.navigate(to: .search(query: name)) }
    }

    private func openQuickDestination(_ destination: PageDestination) {
        playerViewModel.dismissFullscreen()
        dismiss()
        router.navigate(to: destination)
    }

    private func playQuickCard(_ card: BrowseCardRecord, results: SearchResultsRecord) {
        if ["song", "video"].contains(card.kind.lowercased()) {
            playerViewModel.activateSearchMediaRadio(searchViewModel.song(for: card, in: results))
        } else {
            playerViewModel.activateMediaCollection(id: card.id, kind: card.kind)
        }
    }

    private func quickCardMenu(_ card: BrowseCardRecord, results: SearchResultsRecord) -> NSMenu {
        switch card.kind.lowercased() {
        case "song", "video":
            return AppContextMenuFactory.shared.buildSongNSMenu(song: searchViewModel.song(for: card, in: results),
                player: playerViewModel, router: router, core: rustCore, origin: .searchSpotlight)
        case "album":
            return AppContextMenuFactory.shared.buildAlbumNSMenu(browseId: card.id, playlistId: nil,
                title: card.title, artist: card.subtitle, thumbnail: card.thumbnail,
                origin: .searchSpotlight, player: playerViewModel, router: router, core: rustCore)
        case "artist":
            return AppContextMenuFactory.shared.buildArtistNSMenu(channelId: card.id, name: card.title,
                thumbnail: card.thumbnail, radioPlaylistId: nil, origin: .searchSpotlight,
                player: playerViewModel, router: router, core: rustCore)
        default:
            return AppContextMenuFactory.shared.buildPlaylistNSMenu(id: card.id, title: card.title,
                subtitle: card.subtitle, thumbnail: card.thumbnail, origin: .searchSpotlight,
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
            playerViewModel.activateSearchMediaRadio(searchViewModel.song(for: card, in: results))
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

                Text(L10n.text("search.spotlight.all_results_for"))
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.secondary)

                Text("\"\(draft.trimmingCharacters(in: .whitespacesAndNewlines))\"")
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

            Text(L10n.text("search.spotlight.prompt_title"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(L10n.text("search.spotlight.prompt_description"))
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

            Text(L10n.text("search.empty.quick"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(L10n.text("search.spotlight.submit_hint"))
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

    private func dismiss(restoreFocus: Bool = false) {
        restoresFocusOnDismiss = restoreFocus
        searchViewModel.cancelPreview(owner: previewOwner)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            isPresented = false
        }
    }

    private func requestPreview() {
        guard isActive, isPresented else { return }
        searchViewModel.onQueryChanged(draft, core: rustCore, updateDraft: false, owner: previewOwner)
    }

    private func handleCommand(_ command: QuickSearchCommand.Kind) {
        switch command {
        case .moveUp: selectRecent(delta: -1)
        case .moveDown: selectRecent(delta: 1)
        case .submit: submitSelection()
        }
    }

    private func submitSelection() {
        guard isActive, isPresented else { return }
        if !activateSelected() { commitAndNavigate() }
    }

    private func commitAndNavigate() {
        guard isActive, isPresented else { return }
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        playerViewModel.dismissFullscreen()
        dismiss()
        searchViewModel.commitSearch(query: q, core: rustCore, origin: .submit)
        router.navigate(to: .search(query: q))
    }
}
