import SwiftUI
import AppKit
import SideBCore

/// Inicio nuevo: estado y controles ligeros en SwiftUI, feed reciclable en AppKit.
struct HomeView: View {
    @Bindable var playerViewModel: PlayerViewModel
    @Bindable var homeViewModel: HomeViewModel
    let sessionRevision: Int
    var accountName: String?
    var accountThumbnail: String?
    var topContentInset: CGFloat = 0
    var router: NavigationRouter?
    var onNavigate: ((PageDestination) -> Void)?

    var body: some View {
        let songCount = homeViewModel.featured.songs.count
        return feed
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: sessionRevision) {
            guard sessionRevision > 0, homeViewModel.sections.isEmpty,
                  let core = playerViewModel.rustCore else { return }
            await homeViewModel.loadHomeFeed(core: core)
        }
        .onGeometryChange(for: Int.self) { geometry in
            HomeFeaturedLayout(width: geometry.size.width, hasSongs: songCount > 0,
                hasAlbums: true, songCount: songCount, albumCount: 36).albumsPerPage
        } action: { homeViewModel.setFeaturedCapacity($0) }
        .onChange(of: router?.refreshTrigger) { _, _ in refresh() }
    }

    private var feed: some View {
        Group {
            if homeViewModel.sections.isEmpty {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        scrollHeader
                            .padding(.top, topContentInset)
                        if let error = homeViewModel.errorMessage {
                            errorView(error)
                                .frame(minHeight: 240)
                        } else {
                            ProgressView("Cargando recomendaciones…")
                                .frame(maxWidth: .infinity, minHeight: 240)
                                .accessibilityLabel("Cargando Inicio")
                        }
                    }
                }
            } else {
                HomeFeedTableView(
                    headerContent: hasFeatured ? nil : AnyView(scrollHeader),
                    headerHeight: hasFeatured ? 0 : scrollHeaderHeight,
                    featuredContent: hasFeatured ? featuredContent : nil,
                    featuredHeight: hasFeatured ? { width in
                        scrollHeaderHeight + HomeFeaturedLayout.height(width: width, hasSongs: !homeViewModel.featured.songs.isEmpty,
                                                  hasAlbums: !homeViewModel.featured.collections.isEmpty,
                                                  songCount: homeViewModel.featured.songs.count,
                                                  albumCount: homeViewModel.featured.collections.count)
                    } : nil,
                    topContentInset: topContentInset,
                    sections: homeViewModel.featured.remainingSections,
                    isObscured: playerViewModel.isFullscreenPresented,
                    revision: homeViewModel.contentRevision,
                    selectedChip: homeViewModel.selectedChipParams,
                    hasMore: homeViewModel.continuationToken != nil,
                    isLoadingMore: homeViewModel.isLoadingMore,
                    loadMoreMessage: homeViewModel.loadMoreMessage,
                    currentTrackID: playerViewModel.currentTrack?.videoId,
                    currentAlbumBrowseId: playerViewModel.currentAlbumBrowseId,
                    currentPlaylistBrowseId: playerViewModel.currentPlaylistBrowseId,
                    isPlaying: playerViewModel.isPlaying,
                    queueContext: playerViewModel.queueManager.context,
                    player: playerViewModel,
                    router: router,
                    onNavigate: navigate,
                    onLoadMore: loadMore
                )
                .overlay(alignment: .top) { statusBanner }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hasFeatured: Bool {
        !homeViewModel.featured.songs.isEmpty || !homeViewModel.featured.collections.isEmpty
    }

    private var scrollHeaderHeight: CGFloat { homeViewModel.chips.isEmpty ? 112 : 158 }

    private var scrollHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.frame(height: 88, alignment: .top)
            if !homeViewModel.chips.isEmpty { chips }
        }
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: scrollHeaderHeight, alignment: .top)
    }

    private var featuredContent: (CGFloat) -> AnyView {
        // Snapshot the observable inputs here so native row builders never hide dependencies.
        let featured = homeViewModel.featured
        let loading = featured.collectionKind == .albums
            ? playerViewModel.loadingRecommendedAlbumID : playerViewModel.loadingRecommendedPlaylistID
        let key = "\(sessionRevision)|\(homeViewModel.selectedChipParams ?? "all")|\(featured.collectionKind.rawValue)|\(homeViewModel.selectionRevision)"
        let core = playerViewModel.rustCore
        let playbackContext = playerViewModel.queueManager.context
        let isPlaying = playerViewModel.isPlaying
        let intro = AnyView(scrollHeader)
        let introHeight = scrollHeaderHeight
        return { width in
            AnyView(VStack(alignment: .leading, spacing: 0) {
                intro
                HomeFeaturedView(
                    songs: featured.songs, collections: featured.collections, collectionKind: featured.collectionKind, width: width,
                    resetKey: key, metadataSessionKey: String(sessionRevision), loadingCollectionID: loading, core: core,
                    onSong: { playerViewModel.activateMediaRadio(SongItemRecord(fromHomeItem: $0)) },
                    onCollection: { item in
                        if item.kind == "playlist" { navigate(.playlist(browseId: item.id)) }
                        else { navigate(.album(browseId: item.id)) }
                    },
                    onArtist: { item in
                        if let id = item.artistId, !id.isEmpty { navigate(.artist(browseId: id)) }
                    },
                    onPlayCollection: { item, shuffle in
                        playerViewModel.activateMediaCollection(id: item.id, kind: item.kind)
                    }, menuProvider: featuredMenu, playbackContext: playbackContext, isPlaying: isPlaying
                )
            }.frame(width: width, height: introHeight + HomeFeaturedLayout.height(
                width: width, hasSongs: !featured.songs.isEmpty, hasAlbums: !featured.collections.isEmpty,
                songCount: featured.songs.count, albumCount: featured.collections.count), alignment: .topLeading))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            if let url = ImageURLHelper.optimizedThumbnailURL(from: accountThumbnail, targetPixelSize: 88) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 44, height: 44)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.white.opacity(0.06))
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting)
                    .font(.system(size: 27, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
                Text(homeViewModel.allFeaturedSourcesDisabled ? "Activá fuentes desde Configuración de Inicio." : "Tu próximo lado B empieza acá")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation = hour < 12 ? "Buen día" : hour < 20 ? "Buenas tardes" : "Buenas noches"
        let name = accountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? salutation : "\(salutation), \(name)"
    }

    private func featuredMenu(_ item: HomeItemRecord) -> NSMenu? {
        let factory = AppContextMenuFactory.shared
        if item.kind == "song" {
            return factory.buildSongNSMenu(song: SongItemRecord(fromHomeItem: item), player: playerViewModel,
                router: router, core: playerViewModel.rustCore, origin: .home)
        }
        if item.kind == "playlist" {
            return factory.buildPlaylistNSMenu(id: item.id, title: item.title, subtitle: item.subtitle,
                thumbnail: item.thumbnail, inLibrary: nil, origin: .home,
                player: playerViewModel, router: router, core: playerViewModel.rustCore)
        }
        return factory.buildAlbumNSMenu(browseId: item.id, playlistId: nil, title: item.title,
            artist: item.artists ?? item.subtitle, thumbnail: item.thumbnail, inLibrary: nil,
            origin: .home, player: playerViewModel, router: router, core: playerViewModel.rustCore)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Todos", params: nil)
                ForEach(homeViewModel.chips, id: \.params) { value in
                    chip(title: value.title, params: value.params)
                }
            }
            .padding(.horizontal, 28)
        }
        .frame(height: 42)
        .padding(.bottom, 4)
    }

    private func chip(title: String, params: String?) -> some View {
        let selected = homeViewModel.selectedChipParams == params
        return Button(title) {
            guard !selected, let core = playerViewModel.rustCore else { return }
            Task { await homeViewModel.loadHomeFeed(core: core, chipParams: params) }
        }
        .font(.system(size: 13, weight: selected ? .semibold : .medium))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(selected ? Color.sidebAccent : Color.primary.opacity(0.07), in: Capsule())
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private var statusBanner: some View {
        if homeViewModel.isLoadingChip || homeViewModel.isRefreshing || homeViewModel.isShowingSavedFeed ||
            homeViewModel.errorMessage != nil || playerViewModel.errorMessage != nil {
            HStack(spacing: 8) {
                if homeViewModel.isLoadingChip || homeViewModel.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                if homeViewModel.isLoadingChip {
                    Text("Cambiando recomendaciones…")
                } else if let error = homeViewModel.errorMessage {
                    Text(homeViewModel.isShowingSavedFeed ? "No se pudo actualizar · Contenido guardado" : "Sin conexión · se muestran las últimas recomendaciones")
                        .help(error)
                    Button {
                        refresh()
                    } label: {
                        Text("Reintentar")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                } else if let playbackError = playerViewModel.errorMessage {
                    Text(playbackError).lineLimit(2)
                    Button("Cerrar") { playerViewModel.errorMessage = nil }
                        .buttonStyle(.plain)
                } else if homeViewModel.isShowingSavedFeed {
                    if homeViewModel.isRefreshing {
                        Text("Recomendaciones guardadas · actualizando")
                    } else {
                        Text("Recomendaciones guardadas")
                    }
                } else {
                    Text("Actualizando recomendaciones…")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
        }
    }

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label("No se pudo cargar Inicio", systemImage: "wifi.exclamationmark")
        } description: {
            Text(error)
        } actions: {
            Button("Reintentar") { refresh() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refresh() {
        guard let core = playerViewModel.rustCore else { return }
        Task {
            await homeViewModel.loadHomeFeed(core: core, chipParams: homeViewModel.selectedChipParams)
        }
    }

    private func loadMore() {
        guard let core = playerViewModel.rustCore else { return }
        Task { await homeViewModel.loadMoreContent(core: core) }
    }

    private func navigate(_ destination: PageDestination) {
        if let onNavigate { onNavigate(destination) }
        else { router?.navigate(to: destination) }
    }
}
