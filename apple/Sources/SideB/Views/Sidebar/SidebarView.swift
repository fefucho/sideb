import SwiftUI
import SideBCore

// MARK: - SidebarView

struct SidebarView: View {
    @AppStorage(SidebarStyle.preferenceKey, store: HomeAppearance.preferences)
    var sidebarStyleRawValue = SidebarStyle.collection.rawValue
    var sidebarStyle: SidebarStyle { SidebarStyle.resolve(sidebarStyleRawValue) }
    @Binding var isExpanded: Bool
    var titlebarHeight: CGFloat = 0
    @Bindable var router: NavigationRouter
    @Bindable var accountViewModel: AccountViewModel
    @Bindable var libraryViewModel: LibraryViewModel
    let rustCore: SideBCore
    let cookieStorage: CookieStorage
    var playerViewModel: PlayerViewModel? = nil
    var isSearchPresented: Bool = false
    var onOpenSearch: (() -> Void)? = nil
    var onNavigate: ((PageDestination) -> Void)? = nil
    var onOpenLogin: () -> Void
    var onLogout: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: ShellLayout.sidebarHeaderInset(titlebarHeight: titlebarHeight))

            collectionContent

            Spacer(minLength: 0)

            // Pie de barra lateral: Perfil de usuario / Modo Invitado
            Divider()
                .opacity(0.2)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            SidebarProfileView(
                accountViewModel: accountViewModel,
                rustCore: rustCore,
                cookieStorage: cookieStorage,
                onOpenLogin: onOpenLogin,
                onLogout: onLogout
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(width: ShellLayout.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .compatGlass(in: RoundedRectangle(cornerRadius: ShellLayout.sidebarCornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ShellLayout.sidebarCornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
    }

    // MARK: - Navegación Segura (Cierre de Fullscreen)

    func navigate(to destination: PageDestination) {
        playerViewModel?.dismissFullscreen()
        if let onNavigate { onNavigate(destination) }
        else { router.navigate(to: destination) }
    }
    
    // MARK: - Helpers de Selección

    var isLikedMusicSelected: Bool {
        guard !isSearchPresented else { return false }
        if case .playlist(let id) = router.currentPage, id == "LM" {
            return true
        }
        return false
    }

    func isPlaylistSelected(id: String) -> Bool {
        guard !isSearchPresented else { return false }
        if case .playlist(let selId) = router.currentPage, selId == id {
            return true
        }
        return false
    }

    func isAlbumSelected(id: String) -> Bool {
        guard !isSearchPresented else { return false }
        if case .album(let selId) = router.currentPage, selId == id {
            return true
        }
        return false
    }

    var isExploreSelected: Bool {
        !isSearchSelected && MainNavigationDestination.selected(history: router.history, currentIndex: router.currentIndex) == .explore
    }

    var isSearchSelected: Bool {
        if isSearchPresented { return true }
        if case .search = router.currentPage {
            return true
        }
        return false
    }

    var currentListEmpty: Bool {
        switch libraryViewModel.selectedTab {
        case .playlists:
            return libraryViewModel.playlists.isEmpty
        case .albums:
            return libraryViewModel.albums.isEmpty
        }
    }

}
