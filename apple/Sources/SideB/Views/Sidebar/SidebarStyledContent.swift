import SwiftUI
import SideBCore

extension SidebarView {
    /// The same fixed navigation serves the list and grid presentations.
    var collectionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            styledNavigation
                .padding(.top, 8)
                .padding(.bottom, 10)
            styledQuickLinks
            styledLibraryHeader

            ScrollView(.vertical, showsIndicators: false) {
                styledLibrary
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
            .id(libraryViewModel.selectedTab)
            .accessibilityIdentifier("sidebar-collection-scroll")
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar-content")
    }

    private var styledNavigation: some View {
        VStack(spacing: 2) {
            styledNavigationButton("sidebar.home", icon: "house.fill", selected: !isSearchPresented && router.currentPage == .home) {
                navigate(to: .home)
            }
            styledNavigationButton("sidebar.library", icon: "books.vertical.fill", selected: !isSearchPresented && router.currentPage == .library) {
                navigate(to: .library)
            }
            styledNavigationButton("sidebar.explore", icon: "sparkles", selected: !isSearchPresented && isExploreSelected) {
                navigate(to: .explore(.discover))
            }
            styledNavigationButton("sidebar.search", icon: "magnifyingglass", selected: isSearchSelected) {
                playerViewModel?.dismissFullscreen()
                if let onOpenSearch { onOpenSearch() }
                else { navigate(to: .search(query: nil)) }
            }
        }
    }

    private func styledNavigationButton(_ titleKey: String, icon: String, selected: Bool,
                                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SidebarMetrics.size(11)) {
                Image(systemName: icon)
                    .font(.system(size: SidebarMetrics.size(14), weight: .semibold))
                    .frame(width: SidebarMetrics.size(20))
                Text(L10n.text(titleKey))
                    .font(.system(size: SidebarMetrics.size(13), weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
                if titleKey == "sidebar.search" {
                    Text("⌘K")
                        .font(.system(size: SidebarMetrics.size(9.5), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .padding(.horizontal, 4.5).padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 3.5))
                }
            }
            .foregroundStyle(selected ? Color.sidebAccentHighlight : Color.white)
            .padding(.horizontal, 10).padding(.vertical, SidebarMetrics.size(7))
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarHoverStyle(selected: selected))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("styled-\(titleKey)")
    }

    private var styledQuickLinks: some View {
        HStack(spacing: 4) {
            let liked = styledQuickLink("sidebar.liked", icon: "heart.fill", selected: isLikedMusicSelected) {
                navigate(to: .playlist(browseId: "LM"))
            }
            if let player = playerViewModel {
                liked.playlistCardContextMenu(id: "LM", title: L10n.text("sidebar.liked"),
                    subtitle: L10n.text("sidebar.collection"), thumbnail: nil, inLibrary: true,
                    origin: .sidebar, player: player, router: router, core: rustCore)
            } else { liked }
            styledQuickLink("sidebar.history", icon: "clock.arrow.circlepath",
                            selected: !isSearchPresented && router.currentPage == .history) {
                navigate(to: .history)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Color.white.opacity(0.10).frame(height: 0.5) }
        .overlay(alignment: .bottom) { Color.white.opacity(0.10).frame(height: 0.5) }
    }

    private func styledQuickLink(_ titleKey: String, icon: String, selected: Bool,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
                Text(L10n.text(titleKey)).font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(selected ? Color.sidebAccentHighlight : Color.white)
            .frame(maxWidth: .infinity).frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarHoverStyle(selected: selected))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("styled-\(titleKey)")
    }

    private var styledLibraryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(L10n.text("sidebar.your_collection"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { sidebarStyleRawValue = sidebarStyle.alternate.rawValue } label: {
                    Image(systemName: sidebarStyle == .collection ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white).frame(width: 28, height: 28)
                }
                .buttonStyle(SidebarHoverStyle())
                .help(sidebarStyle.switchLabel)
                .accessibilityLabel(sidebarStyle.switchLabel)
                .accessibilityValue(sidebarStyle.title)
                .accessibilityIdentifier("sidebar-layout-toggle")
                if accountViewModel.isLoggedIn {
                    Button { NotificationCenter.default.post(name: .sideBRequestCreatePlaylist, object: nil) } label: {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white).frame(width: 28, height: 28)
                    }
                    .buttonStyle(SidebarHoverStyle())
                    .help(L10n.text("sidebar.new_playlist"))
                    .accessibilityLabel(L10n.text("sidebar.new_playlist"))
                }
            }
            HStack(spacing: 2) {
                ForEach(LibraryTab.allCases) { tab in
                    let selected = libraryViewModel.selectedTab == tab
                    Button { libraryViewModel.selectedTab = tab } label: {
                        Text(tab.displayTitle)
                            .font(.system(size: SidebarMetrics.size(11), weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Color.sidebAccentHighlight : Color.white)
                            .padding(.horizontal, SidebarMetrics.size(9))
                            .padding(.vertical, SidebarMetrics.size(3.5))
                            .background(selected ? Color.white.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("sidebar-tab-\(tab == .playlists ? "playlists" : "albums")")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 9).padding(.top, 12)
    }

    @ViewBuilder private var styledLibrary: some View {
        if !accountViewModel.isLoggedIn {
            styledLibraryMessage(L10n.text("sidebar.sign_in_to_view"))
        } else if libraryViewModel.isLoading && currentListEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 14)
        } else if let error = libraryViewModel.errorMessage, currentListEmpty {
            VStack(spacing: 8) {
                styledLibraryMessage(L10n.text("sidebar.load_failed"))
                Button(L10n.text("sidebar.retry")) {
                    Task { await libraryViewModel.loadLibrary(core: rustCore) }
                }
                .font(.system(size: 12)).foregroundStyle(Color.white).buttonStyle(.plain)
            }
            .help(error).frame(maxWidth: .infinity)
        } else if currentListEmpty {
            styledLibraryMessage(L10n.text(libraryViewModel.selectedTab == .playlists ? "sidebar.no_playlists" : "sidebar.no_saved_albums"))
        } else if sidebarStyle == .covers {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      alignment: .leading, spacing: 18) { styledLibraryItems }
                .padding(.horizontal, 8)
        } else {
            LazyVStack(spacing: 2) { styledLibraryItems }
        }
    }

    private func styledLibraryMessage(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading).padding(9)
    }

    @ViewBuilder private var styledLibraryItems: some View {
        switch libraryViewModel.selectedTab {
        case .playlists:
            ForEach(libraryViewModel.playlists, id: \.id) { playlist in
                let item = SidebarCollectionCard(card: playlist, isCover: sidebarStyle == .covers,
                    isSelected: isPlaylistSelected(id: playlist.id)) { navigate(to: .playlist(browseId: playlist.id)) }
                if let player = playerViewModel {
                    item.playlistCardContextMenu(id: playlist.id, title: playlist.title, subtitle: playlist.subtitle,
                        thumbnail: playlist.thumbnail, inLibrary: true, origin: .sidebar,
                        player: player, router: router, core: rustCore)
                } else { item }
            }
        case .albums:
            ForEach(libraryViewModel.albums, id: \.id) { album in
                let item = SidebarCollectionCard(card: album, isCover: sidebarStyle == .covers,
                    isSelected: isAlbumSelected(id: album.id)) { navigate(to: .album(browseId: album.id)) }
                if let player = playerViewModel {
                    item.albumCardContextMenu(browseId: album.id, playlistId: nil, title: album.title,
                        artist: album.subtitle, thumbnail: album.thumbnail, inLibrary: true, origin: .sidebar,
                        player: player, router: router, core: rustCore)
                } else { item }
            }
        }
    }
}

private struct SidebarCollectionCard: View {
    let card: BrowseCardRecord
    let isCover: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isCover {
                    VStack(alignment: .leading, spacing: 8) {
                        artwork(edge: (ShellLayout.sidebarWidth - 52) / 2)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                                isSelected ? Color.sidebAccentHighlight : Color.clear, lineWidth: 2))
                        copy
                    }
                } else {
                    HStack(spacing: 10) {
                        artwork(edge: 34)
                        copy
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarHoverStyle(selected: !isCover && isSelected))
        .accessibilityLabel([card.displayTitle, card.subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help([card.displayTitle, card.subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — "))
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.displayTitle)
                .font(.system(size: isCover ? 12 : 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.sidebAccentHighlight : Color.white).lineLimit(1)
            if let subtitle = card.subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.system(size: isCover ? 10.5 : 11))
                    .foregroundStyle(Color.white.opacity(0.75)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func artwork(edge: CGFloat) -> some View {
        CachedAsyncImage(url: ImageURLHelper.optimizedThumbnailURL(from: card.thumbnail, targetPixelSize: isCover ? 256 : 96),
                         targetSize: CGSize(width: edge, height: edge)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.10))
                .overlay(Image(systemName: card.kind == "album" ? "opticaldisc" : "music.note.list")
                    .font(.system(size: isCover ? 24 : 14)).foregroundStyle(Color.white.opacity(0.8)))
        }
        .frame(width: edge, height: edge)
        .clipShape(RoundedRectangle(cornerRadius: isCover ? 6 : 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: isCover ? 6 : 4, style: .continuous)
            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

private struct SidebarHoverStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        SidebarHoverSurface(selected: selected, pressed: configuration.isPressed) { configuration.label }
    }
}

private struct SidebarHoverSurface<Content: View>: View {
    let selected: Bool
    let pressed: Bool
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        content()
            .background(Color.white.opacity(pressed ? 0.16 : selected ? 0.10 : hovering ? 0.07 : 0),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.white.opacity(0.10) : Color.clear, lineWidth: 0.5))
            .onHover { hovering = $0 }
    }
}
