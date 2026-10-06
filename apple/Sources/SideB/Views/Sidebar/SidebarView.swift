import SwiftUI
import SideBCore

// MARK: - SidebarView

struct SidebarView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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

            // Área scrolleable de navegación y biblioteca
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Sección 1: Descubrir
                    VStack(spacing: 2) {
                        sidebarRow(
                            title: "Inicio",
                            icon: "house.fill",
                            isSelected: !isSearchPresented && router.currentPage == .home
                        ) {
                            navigate(to: .home)
                        }

                        sidebarRow(title: "Explorar", icon: "sparkles", isSelected: !isSearchPresented && isExploreSelected) {
                            navigate(to: .explore(.discover))
                        }

                        sidebarRow(
                            title: "Buscar",
                            icon: "magnifyingglass",
                            shortcutBadge: "⌘K",
                            isSelected: isSearchSelected
                        ) {
                            playerViewModel?.dismissFullscreen()
                            if let onOpenSearch = onOpenSearch {
                                onOpenSearch()
                            } else {
                                navigate(to: .search(query: nil))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    
                    // Sección 2: Colección (Tus Me Gusta e Historial)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("COLECCIÓN")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .tracking(0.8)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 2)
                        
                        let likedRow = sidebarRow(
                            title: "Tus Me Gusta",
                            icon: "heart.fill",
                            isSelected: isLikedMusicSelected
                        ) {
                            navigate(to: .playlist(browseId: "LM"))
                        }

                        if let player = playerViewModel {
                            likedRow.playlistCardContextMenu(
                                id: "LM",
                                title: "Tus Me Gusta",
                                subtitle: "Colección",
                                thumbnail: nil,
                                inLibrary: true,
                                origin: .sidebar,
                                player: player,
                                router: router,
                                core: rustCore
                            )
                        } else {
                            likedRow
                        }

                        sidebarRow(
                            title: "Biblioteca",
                            icon: "books.vertical.fill",
                            isSelected: !isSearchPresented && router.currentPage == .library
                        ) {
                            navigate(to: .library)
                        }
                        
                        sidebarRow(
                            title: "Historial",
                            icon: "clock.arrow.circlepath",
                            isSelected: !isSearchPresented && router.currentPage == .history
                        ) {
                            navigate(to: .history)
                        }

                    }
                    .padding(.horizontal, 10)
                    
                    // Switcher de Cápsula [ Playlists | Álbumes ] y Lista
                    VStack(alignment: .leading, spacing: 6) {
                        // Switcher segmentado estilo macOS moderno + botón (+)
                        HStack {
                            HStack(spacing: 2) {
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        libraryViewModel.selectedTab = .playlists
                                    }
                                } label: {
                                    Text("Playlists")
                                        .font(.system(size: 11, weight: libraryViewModel.selectedTab == .playlists ? .semibold : .medium))
                                        .foregroundStyle(libraryViewModel.selectedTab == .playlists ? .primary : .secondary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 3.5)
                                        .background(
                                            libraryViewModel.selectedTab == .playlists
                                                ? Color.primary.opacity(0.12)
                                                : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        libraryViewModel.selectedTab = .albums
                                    }
                                } label: {
                                    Text("Álbumes")
                                        .font(.system(size: 11, weight: libraryViewModel.selectedTab == .albums ? .semibold : .medium))
                                        .foregroundStyle(libraryViewModel.selectedTab == .albums ? .primary : .secondary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 3.5)
                                        .background(
                                            libraryViewModel.selectedTab == .albums
                                                ? Color.primary.opacity(0.12)
                                                : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(2)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                            Spacer()

                            if accountViewModel.isLoggedIn {
                                Button {
                                    NotificationCenter.default.post(name: .sideBRequestCreatePlaylist, object: nil)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Nueva playlist")
                                .accessibilityLabel("Nueva playlist")
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 4)

                        // Lista según pestaña seleccionada
                        if !accountViewModel.isLoggedIn {
                            Text("Inicia sesión para ver tu música guardada")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        } else if libraryViewModel.isLoading && currentListEmpty {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 10)
                        } else if let error = libraryViewModel.errorMessage, currentListEmpty {
                            VStack(spacing: 4) {
                                Text("No se pudo cargar")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Button("Reintentar") {
                                    Task { await libraryViewModel.loadLibrary(core: rustCore) }
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                            .help(error)
                        } else {
                            VStack(spacing: 2) {
                                switch libraryViewModel.selectedTab {
                                case .playlists:
                                    if libraryViewModel.playlists.isEmpty {
                                        Text("No tienes playlists")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                    } else {
                                        ForEach(libraryViewModel.playlists, id: \.id) { playlist in
                                            let row = sidebarItemRow(
                                                title: playlist.title,
                                                icon: "music.note.list",
                                                thumbnailURL: playlist.thumbnail,
                                                isSelected: isPlaylistSelected(id: playlist.id)
                                            ) {
                                                navigate(to: .playlist(browseId: playlist.id))
                                            }

                                            if let player = playerViewModel {
                                                row.playlistCardContextMenu(
                                                    id: playlist.id,
                                                    title: playlist.title,
                                                    subtitle: playlist.subtitle,
                                                    thumbnail: playlist.thumbnail,
                                                    inLibrary: true,
                                                    origin: .sidebar,
                                                    player: player,
                                                    router: router,
                                                    core: rustCore
                                                )
                                            } else {
                                                row
                                            }
                                        }
                                    }
                                case .albums:
                                    if libraryViewModel.albums.isEmpty {
                                        Text("No tienes álbumes guardados")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                    } else {
                                        ForEach(libraryViewModel.albums, id: \.id) { album in
                                            let row = sidebarItemRow(
                                                title: album.title,
                                                icon: "opticaldisc",
                                                thumbnailURL: album.thumbnail,
                                                isSelected: isAlbumSelected(id: album.id)
                                            ) {
                                                navigate(to: .album(browseId: album.id))
                                            }

                                            if let player = playerViewModel {
                                                row.albumCardContextMenu(
                                                    browseId: album.id,
                                                    playlistId: nil,
                                                    title: album.title,
                                                    artist: album.subtitle,
                                                    thumbnail: album.thumbnail,
                                                    inLibrary: true,
                                                    origin: .sidebar,
                                                    player: player,
                                                    router: router,
                                                    core: rustCore
                                                )
                                            } else {
                                                row
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            
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

    private func navigate(to destination: PageDestination) {
        playerViewModel?.dismissFullscreen()
        if let onNavigate { onNavigate(destination) }
        else { router.navigate(to: destination) }
    }
    
    // MARK: - Helpers de Selección

    private var isLikedMusicSelected: Bool {
        guard !isSearchPresented else { return false }
        if case .playlist(let id) = router.currentPage, id == "LM" {
            return true
        }
        return false
    }

    private func isPlaylistSelected(id: String) -> Bool {
        guard !isSearchPresented else { return false }
        if case .playlist(let selId) = router.currentPage, selId == id {
            return true
        }
        return false
    }

    private func isAlbumSelected(id: String) -> Bool {
        guard !isSearchPresented else { return false }
        if case .album(let selId) = router.currentPage, selId == id {
            return true
        }
        return false
    }

    private var isExploreSelected: Bool {
        MainNavigationDestination.selected(history: router.history, currentIndex: router.currentIndex, searchPresented: false) == .explore
    }

    private var isSearchSelected: Bool {
        if isSearchPresented { return true }
        if case .search = router.currentPage {
            return true
        }
        return false
    }

    private var currentListEmpty: Bool {
        switch libraryViewModel.selectedTab {
        case .playlists:
            return libraryViewModel.playlists.isEmpty
        case .albums:
            return libraryViewModel.albums.isEmpty
        }
    }

    // MARK: - Filas de Navegación

    @ViewBuilder
    private func sidebarRow(
        title: String,
        icon: String,
        shortcutBadge: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.sidebAccentHighlight : Color.primary.opacity(0.68))
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.sidebAccentHighlight : Color.primary)
                
                Spacer()

                if let badge = shortcutBadge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary.opacity(0.65))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.08) : Color.clear, lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sidebarItemRow(
        title: String,
        icon: String,
        thumbnailURL: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                // Miniatura 22x22 ultra-ligera (Google CDN 48px ~1KB) con ImageCache sincrónico a 120 FPS
                if let thumb = thumbnailURL, let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 48) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 22, height: 22)) { img in
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        itemPlaceholder(icon: icon, isSelected: isSelected)
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                } else {
                    itemPlaceholder(icon: icon, isSelected: isSelected)
                }

                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.sidebAccentHighlight : Color.primary.opacity(0.9))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.08) : Color.clear, lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func itemPlaceholder(icon: String, isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            Image(systemName: icon)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
        }
        .frame(width: 22, height: 22)
    }
}
