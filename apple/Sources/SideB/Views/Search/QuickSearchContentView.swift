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
        .onChange(of: keyboardActions.map(\.id)) { _, keys in
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
            let recentHeight = min(540, max(220, 96 + searchViewModel.visibleProviderSuggestions.count * 58))
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

    private var keyboardActions: [SearchSuggestionEntryRecord] {
        guard searchViewModel.associatedQuickQuery == draft.trimmingCharacters(in: .whitespacesAndNewlines) else { return [] }
        return searchViewModel.visibleProviderSuggestions
    }
    private var keyboardSelectionLabel: String? {
        keyboardActions.first { $0.id == selectedRecentKey }?.displayTitle
    }
    private func selectRecent(delta: Int) {
        selectedRecentKey = QuickSearchSelection.nextKey(in: keyboardActions.map(\.id), selected: selectedRecentKey, delta: delta)
    }
    private func activateSelected() -> Bool {
        guard let entry = keyboardActions.first(where: { $0.id == selectedRecentKey }) else { return false }
        activate(entry)
        return true
    }
    private func activate(_ entry: SearchSuggestionEntryRecord) {
        if let song = entry.song {
            playerViewModel.activateMediaRadio(song)
            dismiss()
        } else if let card = entry.card {
            playerViewModel.dismissFullscreen()
            dismiss()
            switch card.kind {
            case "artist": router.navigate(to: .artist(browseId: card.id))
            case "album": router.navigate(to: .album(browseId: card.id))
            case "playlist": router.navigate(to: .playlist(browseId: card.id))
            case "song", "video": playerViewModel.activateMediaRadio(SongItemRecord(fromCard: card))
            default: router.navigate(to: .search(query: card.title))
            }
        } else if let query = entry.query {
            draft = query
            commitAndNavigate()
        }
    }

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

    private var resultsScrollView: some View {
        ScrollViewReader { scroll in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if searchViewModel.isQuickSearching {
                        searchLoadingPlaceholder
                    } else if searchViewModel.associatedQuickQuery == draft.trimmingCharacters(in: .whitespacesAndNewlines) {
                        ForEach(searchViewModel.visibleProviderSuggestions, id: \.id) { entry in
                            ProviderSearchSuggestionRow(entry: entry, selected: selectedRecentKey == entry.id,
                                removing: searchViewModel.removingSuggestionIDs.contains(entry.id),
                                player: playerViewModel, router: router, core: rustCore,
                                onActivate: { activate(entry) },
                                onRemove: { Task { await searchViewModel.removeProviderSuggestion(entry, core: rustCore) } },
                                onNavigate: { destination in
                                    playerViewModel.dismissFullscreen(); dismiss(); router.navigate(to: destination)
                                })
                        }
                        if searchViewModel.visibleProviderSuggestions.isEmpty { emptySearchPlaceholder }
                    }
                    if let message = searchViewModel.quickErrorMessage {
                        HStack {
                            Label(message, systemImage: "exclamationmark.circle")
                            Button(L10n.text("common.retry")) { requestPreview() }.buttonStyle(.plain)
                        }.font(.system(size: 12)).foregroundStyle(.secondary).padding(8)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 14)
            }
            .onChange(of: selectedRecentKey) { _, key in if let key { scroll.scrollTo(key, anchor: .center) } }
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
