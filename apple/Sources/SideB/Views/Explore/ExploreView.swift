import SwiftUI
import SideBCore

struct ExploreView: View {
    let route: ExploreRoute
    let rustCore: SideBCore
    @Bindable var model: ExploreViewModel
    @Bindable var playerViewModel: PlayerViewModel
    let router: NavigationRouter
    let sessionRevision: Int
    var isObscured = false
    @State private var refreshRevision = 0
    @State private var previousRequest: RequestIdentity?

    private struct RequestIdentity: Hashable {
        let route: ExploreRoute
        let session: Int
        let refresh: Int
    }
    private var requestIdentity: RequestIdentity { .init(route: route, session: sessionRevision, refresh: refreshRevision) }

    var body: some View {
        Group {
            if route == .releases || isCategoryRoute {
                nativeCatalog(cards: model.cards, header: AnyView(catalogHeader),
                    headerIdentity: .init(route: route, session: sessionRevision, loading: model.isLoading,
                                          error: model.errorMessage, empty: model.cards.isEmpty))
            } else {
                scrollContent
            }
        }
        .task(id: requestIdentity) {
            let identity = requestIdentity
            let force = previousRequest.map {
                $0.route == identity.route && $0.session == identity.session && $0.refresh != identity.refresh
            } ?? false
            previousRequest = identity
            model.prepareSession(sessionRevision)
            await model.load(route: route, core: rustCore, force: force)
        }
    }

    private var isCategoryRoute: Bool { if case .category = route { return true }; return false }

    private var scrollContent: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header.id("explore-top")
                    tabs
                    switch route {
                    case .discover:
                        HStack(spacing: 16) {
                            shortcut(.releases, subtitle: "Recién llegados", hue: 0.02)
                            shortcut(.charts, subtitle: "Global y tu región", hue: 0.64)
                        }
                        music(title: "Álbumes y sencillos nuevos", preview: true)
                        categories(ExploreCategory.moods, title: "Para cada momento", destination: .moods)
                        categories(Array(ExploreCategory.genres.prefix(8)), title: "Explorá por género", destination: .genres)
                    case .releases: music(title: "Álbumes y sencillos nuevos")
                    case .charts, .chartCountry: chartContents
                    case .genres: categories(ExploreCategory.genres, title: "Todos los géneros")
                    case .moods: categories(ExploreCategory.moods, title: "Elegí tu momento")
                    case .category: music(title: "Playlists para explorar")
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 140)
                .frame(maxWidth: 1400, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .onChange(of: route) { _, _ in scroll.scrollTo("explore-top", anchor: .top) }
        }
    }

    private var catalogHeader: some View {
        VStack(alignment: .leading, spacing: 30) {
            header
            tabs
            VStack(alignment: .leading, spacing: 16) {
                musicHeader(title: route == .releases ? "Álbumes y sencillos nuevos" : "Playlists para explorar")
                musicStatus
            }
        }
        .padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 16)
        .frame(maxWidth: 1400, alignment: .leading).frame(maxWidth: .infinity, alignment: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("EXPLORAR", systemImage: "safari")
                .font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
            Text(route == .discover ? "Algo nuevo para escuchar." : route.title)
                .font(.system(size: route == .discover ? 36 : 32, weight: .bold)).accessibilityAddTraits(.isHeader)
            Text(headerSubtitle).font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerSubtitle: String {
        switch route {
        case .discover: return "Novedades, géneros y música para acompañar tu día."
        case .releases: return "Lo nuevo en YouTube Music, listo para descubrir."
        case .charts: return "Lo que suena en el mundo y cerca tuyo."
        case .chartCountry(let code): return "Las playlists de YouTube Charts para \(ExploreChartRegion.name(code))."
        case .genres: return "Tus sonidos de siempre y otros por conocer."
        case .moods: return "Una playlist para lo que estés haciendo."
        case .category(let id): return ExploreCategory.find(id)?.subtitle ?? "Encontrá algo nuevo para escuchar."
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExploreRoute.tabs, id: \.self) { tab in
                    Button { navigate(tab) } label: {
                        Label(tab.title, systemImage: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 15).padding(.vertical, 10)
                            .background(route.selectedTab == tab ? Color.white.opacity(0.14) : Color.white.opacity(0.04), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(route.selectedTab == tab ? 0.2 : 0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(route.selectedTab == tab ? .isSelected : [])
                }
            }.padding(2)
        }
        .windowGestureRegion(.horizontalContent, active: !playerViewModel.isFullscreenPresented)
    }

    private func shortcut(_ target: ExploreRoute, subtitle: String, hue: Double) -> some View {
        Button { navigate(target) } label: {
            HStack(spacing: 16) {
                Image(systemName: target.symbol).font(.system(size: 29, weight: .light))
                    .foregroundStyle(Color(hue: hue, saturation: 0.45, brightness: 1)).frame(width: 46)
                VStack(alignment: .leading, spacing: 5) {
                    Text(target.title).font(.system(size: 18, weight: .bold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(tileGradient(hue), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }

    private func categories(_ items: [ExploreCategory], title: String, destination: ExploreRoute? = nil) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title, destination: destination)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                ForEach(items) { category in
                    Button { navigate(.category(category.id)) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Image(systemName: category.symbol).font(.system(size: 26, weight: .light))
                                    .foregroundStyle(Color(hue: category.hue, saturation: 0.35, brightness: 1))
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer(minLength: 18)
                            Text(category.title).font(.system(size: 16, weight: .bold)).lineLimit(1)
                            Text(category.subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1).padding(.top, 5)
                        }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading).frame(height: 135)
                        .background(tileGradient(category.hue), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.07)))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(category.title), \(category.subtitle)")
                    .accessibilityHint("Abre playlists de \(category.title)")
                }
            }
        }
    }

    private func tileGradient(_ hue: Double) -> LinearGradient {
        LinearGradient(colors: [Color(hue: hue, saturation: 0.48, brightness: 0.32), Color(hue: hue, saturation: 0.25, brightness: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var chartContents: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Picker("Región", selection: Binding(get: { route }, set: { navigate($0) })) {
                    Text("Global y tu región").tag(ExploreRoute.charts)
                    Text("Global").tag(ExploreRoute.chartCountry("ZZ"))
                    ForEach(model.chartCountries.filter { $0.code != "ZZ" }.sorted {
                        ExploreChartRegion.name($0.code).localizedStandardCompare(ExploreChartRegion.name($1.code)) == .orderedAscending
                    }, id: \.code) { country in
                        Text(ExploreChartRegion.name(country.code)).tag(ExploreRoute.chartCountry(country.code))
                    }
                }
                .pickerStyle(.menu).fixedSize()
                .accessibilityLabel("País de los rankings")
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Button { refreshRevision &+= 1 } label: { Label("Actualizar", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).disabled(model.isLoading)
                    .help(route == .charts ? "Actualizar rankings y detectar de nuevo tu región" : "Actualizar rankings")
            }
            if route == .charts, let code = model.detectedCountry {
                Label("Región detectada: \(ExploreChartRegion.name(code))", systemImage: "location.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let message = model.regionMessage { Text(message).font(.system(size: 12)).foregroundStyle(.secondary) }
            if let error = model.errorMessage {
                HStack {
                    Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reintentar") { refreshRevision &+= 1 }.buttonStyle(.bordered)
                }
            }
            if model.chartSections.isEmpty, model.isLoading {
                ProgressView("Cargando rankings…").frame(maxWidth: .infinity, minHeight: 190)
            }
            ForEach(model.chartSections) { section in
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Rankings · \(ExploreChartRegion.name(section.code))")
                    if section.cards.isEmpty {
                        ContentUnavailableView("No hay rankings disponibles", systemImage: "chart.line.uptrend.xyaxis", description: Text("Probá con otra región."))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 230), spacing: 20)], alignment: .leading, spacing: 26) {
                            ForEach(section.cards, id: \.exploreIdentity) { mediaCard($0) }
                        }
                    }
                }
            }
        }
    }

    private func music(title: String, preview: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            musicHeader(title: title, preview: preview)
            musicStatus
            if !model.cards.isEmpty {
                nativeCatalog(cards: Array(model.cards.prefix(12)), axis: .horizontal)
                    .frame(height: 164 + HomeItemView.largeCardTextHeight + 6)
            }
        }
    }

    private func musicHeader(title: String, preview: Bool = false) -> some View {
        HStack {
            sectionHeader(title, destination: preview ? .releases : nil)
            if model.isLoading, !model.cards.isEmpty { ProgressView().controlSize(.small) }
            Button { refreshRevision &+= 1 } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).disabled(model.isLoading).help("Actualizar música").accessibilityLabel("Actualizar música")
        }
    }

    @ViewBuilder private var musicStatus: some View {
        if let error = model.errorMessage {
            HStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark").foregroundStyle(.secondary)
                Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Reintentar") { refreshRevision &+= 1 }.buttonStyle(.bordered)
            }
            .padding(16).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
        if model.isLoading, model.cards.isEmpty {
            ProgressView("Buscando música…").frame(maxWidth: .infinity, minHeight: 190)
        } else if model.cards.isEmpty, model.errorMessage == nil {
            ContentUnavailableView("Todavía no hay música aquí", systemImage: route.symbol,
                description: Text("Probá otra categoría o actualizá para volver a buscar."))
        }
    }

    private func nativeCatalog(cards: [BrowseCardRecord], axis: ExploreCatalogGridView.Axis = .vertical,
                               header: AnyView? = nil, headerIdentity: ExploreCatalogHeaderIdentity? = nil) -> some View {
        ExploreCatalogGridView(cards: cards, route: route, sessionRevision: sessionRevision, axis: axis,
            header: header, headerIdentity: headerIdentity, isObscured: isObscured,
            queueContext: playerViewModel.queueManager.context, isPlaying: playerViewModel.isPlaying,
            loadingAlbumID: playerViewModel.loadingRecommendedAlbumID,
            loadingPlaylistID: playerViewModel.loadingRecommendedPlaylistID,
            onOpen: openCard, onPlay: playCard, menuProvider: cardMenu)
    }

    private func openCard(_ card: BrowseCardRecord) {
        switch card.kind {
        case "album": router.navigate(to: .album(browseId: card.id))
        case "playlist": router.navigate(to: .playlist(browseId: card.id))
        case "artist": router.navigate(to: .artist(browseId: card.id))
        case "song", "video": playerViewModel.activateMediaRadio(SongItemRecord(fromCard: card))
        default: break
        }
    }

    private func playCard(_ card: BrowseCardRecord) {
        if card.kind == "album" || card.kind == "playlist" {
            playerViewModel.activateMediaCollection(id: card.id, kind: card.kind)
        } else { openCard(card) }
    }

    private func cardMenu(_ card: BrowseCardRecord) -> NSMenu? {
        let factory = AppContextMenuFactory.shared
        switch card.kind {
        case "album":
            return factory.buildAlbumNSMenu(browseId: card.id, playlistId: nil, title: card.title,
                artist: card.subtitle, thumbnail: card.thumbnail, origin: .recommendations,
                player: playerViewModel, router: router, core: rustCore)
        case "playlist":
            return factory.buildPlaylistNSMenu(id: card.id, title: card.title, subtitle: card.subtitle,
                thumbnail: card.thumbnail, origin: .recommendations, player: playerViewModel, router: router, core: rustCore)
        case "artist":
            return factory.buildArtistNSMenu(channelId: card.id, name: card.title, thumbnail: card.thumbnail,
                radioPlaylistId: nil, origin: .recommendations, player: playerViewModel, router: router, core: rustCore)
        case "song", "video":
            return factory.buildSongNSMenu(song: SongItemRecord(fromCard: card), player: playerViewModel,
                router: router, core: rustCore, origin: .recommendations)
        default: return nil
        }
    }

    private func mediaCard(_ card: BrowseCardRecord) -> some View {
        CatalogCardView(card: card, rustCore: rustCore, playerViewModel: playerViewModel, router: router, origin: .recommendations)
    }

    private func sectionHeader(_ title: String, destination: ExploreRoute? = nil) -> some View {
        HStack {
            Text(title).font(.system(size: 21, weight: .bold)).accessibilityAddTraits(.isHeader)
            Spacer()
            if let destination {
                Button { navigate(destination) } label: {
                    HStack(spacing: 5) { Text("Ver todo"); Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)) }
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).accessibilityLabel("Ver todo: \(title)")
            }
        }
    }

    private func navigate(_ route: ExploreRoute) { router.navigate(to: .explore(route)) }
}

extension BrowseCardRecord {
    var exploreIdentity: String { "\(kind):\(id)" }
}
