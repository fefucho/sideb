import SwiftUI
import SideBCore

/// The permanent ⌘K/sidebar entry point; TopNav shares its results and actions.
struct SpotlightSearchModal: View {
    @Binding var isPresented: Bool
    @Bindable var searchViewModel: SearchViewModel
    @Bindable var router: NavigationRouter
    var playerViewModel: PlayerViewModel
    let rustCore: SideBCore
    var persistedDraft: Binding<String>? = nil
    var onRestoreFocus: (() -> Void)? = nil

    @State private var draft = ""

    var body: some View {
        QuickSearchContentView(
            isPresented: $isPresented,
            draft: persistedDraft ?? $draft,
            searchViewModel: searchViewModel,
            router: router,
            playerViewModel: playerViewModel,
            rustCore: rustCore,
            style: .spotlight,
            onRestoreFocus: onRestoreFocus
        )
    }
}
