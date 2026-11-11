import SwiftUI
import UniformTypeIdentifiers
import SideBCore

private func settingsText(_ es: String, _ en: String) -> String {
    L10n.language == .es ? es : en
}

/// Secciones que agrupan las categorías en la barra lateral de Configuración.
enum SettingsSection: String, CaseIterable, Identifiable {
    case app
    case content
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: return settingsText("Aplicación", "App")
        case .content: return settingsText("Contenido", "Content")
        case .account: return settingsText("Cuenta", "Account")
        }
    }
}

/// Categorías del panel de configuración de Side B
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case playback
    case appearance
    case shortcuts
    case homeFeed
    case visualProviders
    case account

    var id: String { rawValue }

    var section: SettingsSection {
        switch self {
        case .general, .playback, .appearance, .shortcuts: return .app
        case .homeFeed, .visualProviders: return .content
        case .account: return .account
        }
    }

    var title: String {
        switch self {
        case .general: return L10n.text("settings.category.general")
        case .playback: return L10n.text("settings.category.playback")
        case .appearance: return L10n.text("settings.category.appearance")
        case .visualProviders: return L10n.text("settings.category.visualProviders")
        case .homeFeed: return L10n.text("settings.category.homeFeed")
        case .account: return L10n.text("settings.category.account")
        case .shortcuts: return L10n.text("settings.category.shortcuts")
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return settingsText(
                "Idioma de la interfaz, búsqueda y actualizaciones.",
                "Interface language, search and updates.")
        case .playback:
            return settingsText(
                "Cola de reproducción y contenido de la barra lateral.",
                "Playback queue and sidebar content.")
        case .appearance:
            return settingsText(
                "Barra lateral, fondos y carátulas animadas.",
                "Sidebar, backgrounds and animated artwork.")
        case .visualProviders:
            return settingsText(
                "Letras sincronizadas, créditos y material visual de proveedores externos.",
                "Synced lyrics, credits and visuals from external providers.")
        case .homeFeed:
            return settingsText(
                "Elegí y ordená las fuentes y categorías que aparecen en Inicio.",
                "Choose and order the sources and categories shown on Home.")
        case .account:
            return settingsText(
                "Tu sesión, privacidad y almacenamiento local.",
                "Your session, privacy and local storage.")
        case .shortcuts:
            return settingsText(
                "Atajos de teclado para controlar Side B.",
                "Keyboard shortcuts to control Side B.")
        }
    }

    /// Nombre de SF Symbol. Siempre contorno, sin relleno, para mantener un trazo uniforme.
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .playback: return "play.circle"
        case .appearance: return "circle.lefthalf.filled"
        case .shortcuts: return "command"
        case .homeFeed: return "house"
        case .visualProviders: return "quote.bubble"
        case .account: return "person.crop.circle"
        }
    }
}

/// Panel de Configuración: barra lateral por secciones y listas agrupadas al estilo de Música.
struct SettingsModalView: View {
    var homeViewModel: HomeViewModel
    var accountViewModel: AccountViewModel? = nil
    var playerViewModel: PlayerViewModel? = nil
    var cookieStorage: CookieStorage? = nil
    var rustCore: SideBCore? = nil
    var onLoginRequested: (() -> Void)? = nil
    let onClose: () -> Void

    @State private var selectedCategory: SettingsCategory = .general
    @State private var searchQuery: String = ""

    // App Preferences
    @AppStorage(HomeAppearance.solidBackgroundKey, store: HomeAppearance.preferences)
    private var useSolidHomeBackground = false

    @AppStorage(HomeAppearance.albumCardStyleKey, store: HomeAppearance.preferences)
    private var albumCardStyleRawValue = HomeAlbumCardStyle.tinted.rawValue

    @AppStorage(SidebarStyle.preferenceKey, store: HomeAppearance.preferences)
    private var sidebarStyleRawValue = SidebarStyle.collection.rawValue

    @AppStorage(HomeAppearance.animatedArtworkKey, store: HomeAppearance.preferences)
    private var animatedArtworkEnabled = true

    @AppStorage(QueuePreferences.selectionKey, store: HomeAppearance.preferences)
    private var queueSelectionRaw = QueueRecommendationSelection.advance.rawValue

    @AppStorage(SidebarBottomContentPreferences.preferenceKey, store: HomeAppearance.preferences)
    private var sidebarBottomContentRaw = SidebarBottomContent.queue.rawValue

    // States for Cache & Home customization
    @State private var animatedArtworkCacheBytes: UInt64?
    @State private var animatedArtworkCacheError = false
    @State private var isCheckingUpdates = false
    @State private var categoryFilterText = ""
    @State private var draggingSource: String?
    @State private var draggingCategory: String?

    private var matchingCategories: [SettingsCategory] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return SettingsCategory.allCases }
        return SettingsCategory.allCases.filter {
            $0.title.localizedStandardContains(query) || $0.subtitle.localizedStandardContains(query)
        }
    }

    private var rules: [HomeRecommendationSourceRule] {
        homeViewModel.recommendationSettings.sources(for: homeViewModel.featuredCollectionKind)
    }

    private var homeCategories: [HomeCategoryOption] {
        guard !categoryFilterText.isEmpty else { return homeViewModel.receivedCategories }
        return homeViewModel.receivedCategories.filter {
            L10n.providerHeading($0.title).localizedStandardContains(categoryFilterText)
        }
    }

    /// El feed de Inicio usa dos columnas, por eso admite más ancho que el resto.
    private var detailMaxWidth: CGFloat {
        selectedCategory == .homeFeed ? 980 : 720
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 244)

            Divider().opacity(0.25)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, maxWidth: 1240, minHeight: 520, maxHeight: 860)
        .compatGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.40), radius: 24, x: 0, y: 12)
        .onExitCommand(perform: onClose)
        .task(id: rustCore != nil) {
            guard let rustCore else { return }
            animatedArtworkCacheBytes = try? await AnimatedArtworkManager.shared.size(core: rustCore)
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.primary.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help(L10n.text("settings.close"))
                .accessibilityLabel(L10n.text("settings.close"))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            searchField
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SettingsSection.allCases) { section in
                        let items = matchingCategories.filter { $0.section == section }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 3)
                                ForEach(items) { category in
                                    SettingsSidebarItem(
                                        category: category,
                                        isSelected: selectedCategory == category
                                    ) {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                    }

                    if matchingCategories.isEmpty {
                        Text(settingsText("Sin resultados", "No results"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.12))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(L10n.text("settings.searchPlaceholder"), text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
    }

    // MARK: - Detail

    private var detailView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedCategory.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(selectedCategory.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                switch selectedCategory {
                case .general:
                    generalSettingsView
                case .playback:
                    playbackSettingsView
                case .appearance:
                    appearanceSettingsView
                case .visualProviders:
                    visualProvidersSettingsView
                case .homeFeed:
                    homeFeedSettingsView
                case .account:
                    accountSettingsView
                case .shortcuts:
                    shortcutsSettingsView
                }
            }
            .frame(maxWidth: detailMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 36)
            .padding(.top, 34)
            .padding(.bottom, 32)
        }
        .id(selectedCategory)
    }

    // MARK: - General

    private var generalSettingsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: settingsText("Idioma", "Language")) {
                SettingsRow(title: L10n.text("settings.language")) {
                    Picker(L10n.text("settings.language"), selection: Binding(
                        get: { L10n.language },
                        set: { AppLanguageStore.shared.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                            Text(verbatim: language.nativeName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsGroup(title: L10n.text("menu.search")) {
                SettingsRow(
                    title: L10n.text("settings.search.showVideos"),
                    subtitle: L10n.text("settings.search.showVideos.hint")
                ) {
                    SettingsSwitch(title: L10n.text("settings.search.showVideos"), isOn: Binding(
                        get: { SearchPreferences.shared.showVideos },
                        set: { SearchPreferences.shared.showVideos = $0 }
                    ))
                }
            }

            SettingsGroup(title: settingsText("Actualizaciones", "Updates")) {
                SettingsRow(
                    title: L10n.text("update.installed") + ": Side B " + UpdateService.shared.currentVersion,
                    subtitle: updateStatusSummary
                ) {
                    Button {
                        isCheckingUpdates = true
                        Task {
                            await UpdateService.shared.checkForUpdates(manual: true)
                            isCheckingUpdates = false
                        }
                    } label: {
                        if isCheckingUpdates {
                            ProgressView()
                                .controlSize(.small)
                                .frame(minWidth: 96)
                        } else {
                            Text(L10n.text("menu.check_updates"))
                        }
                    }
                    .disabled(isCheckingUpdates)
                }
            }
        }
    }

    private var updateStatusSummary: String {
        switch UpdateService.shared.state {
        case .idle, .upToDate:
            return L10n.language == .es ? "Tu aplicación está al día." : "Your application is up to date."
        case .checking:
            return L10n.language == .es ? "Buscando nuevas versiones..." : "Checking for newer versions..."
        case .available(let info):
            return L10n.language == .es ? "Nueva versión \(info.version) disponible." : "New version \(info.version) is available."
        case .failed(let msg):
            return msg
        default:
            return ""
        }
    }

    // MARK: - Reproducción

    private var playbackSettingsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(
                title: L10n.text("queue.settings.title"),
                footer: L10n.text("queue.selection.hint")
            ) {
                SettingsRow(title: L10n.text("queue.selection.label")) {
                    Picker(L10n.text("queue.selection.label"), selection: Binding(
                        get: { QueueRecommendationSelection.resolve(queueSelectionRaw).rawValue },
                        set: { queueSelectionRaw = $0 }
                    )) {
                        ForEach(QueueRecommendationSelection.allCases, id: \.rawValue) { mode in
                            Text(L10n.text(mode.labelKey)).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsGroup(
                title: L10n.text("settings.sidebarBottomContent.cardTitle"),
                footer: L10n.text("settings.sidebarBottomContent.hint")
            ) {
                SettingsRow(title: L10n.text("settings.sidebarBottomContent.label")) {
                    Picker(L10n.text("settings.sidebarBottomContent.label"), selection: Binding(
                        get: { SidebarBottomContent.resolve(sidebarBottomContentRaw).rawValue },
                        set: { sidebarBottomContentRaw = $0 }
                    )) {
                        ForEach(SidebarBottomContent.allCases) { option in
                            Text(L10n.text(option.labelKey)).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - Apariencia

    private var appearanceSettingsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: L10n.text("settings.appearance")) {
                SettingsRow(title: L10n.text("settings.sidebarLayout")) {
                    Picker(L10n.text("settings.sidebarLayout"), selection: Binding(
                        get: { SidebarStyle.resolve(sidebarStyleRawValue).rawValue },
                        set: { sidebarStyleRawValue = $0 }
                    )) {
                        ForEach(SidebarStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingsRow(
                    title: L10n.text("settings.homeBackground"),
                    subtitle: L10n.text("settings.homeBackground.hint")
                ) {
                    Picker(L10n.text("settings.homeBackground"), selection: $useSolidHomeBackground) {
                        Text(L10n.text("settings.homeBackground.ambient")).tag(false)
                        Text(L10n.text("settings.homeBackground.solid")).tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingsRow(
                    title: L10n.text("settings.albumCardStyle"),
                    subtitle: L10n.text("settings.albumCardStyle.hint")
                ) {
                    Picker(L10n.text("settings.albumCardStyle"), selection: Binding(
                        get: { HomeAlbumCardStyle(rawValue: albumCardStyleRawValue)?.rawValue ?? HomeAlbumCardStyle.tinted.rawValue },
                        set: { albumCardStyleRawValue = $0 }
                    )) {
                        Text(L10n.text("settings.albumCardStyle.tinted")).tag(HomeAlbumCardStyle.tinted.rawValue)
                        Text(L10n.text("settings.albumCardStyle.white")).tag(HomeAlbumCardStyle.white.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsGroup(title: L10n.text("settings.animatedArtwork")) {
                SettingsRow(
                    title: L10n.text("settings.animatedArtwork"),
                    subtitle: L10n.text("settings.animatedArtwork.hint")
                ) {
                    SettingsSwitch(title: L10n.text("settings.animatedArtwork"), isOn: $animatedArtworkEnabled)
                }

                SettingsRow(
                    title: settingsText("Caché de carátulas en disco", "Disk Artwork Cache"),
                    subtitle: animatedArtworkCacheError
                        ? L10n.text("settings.animatedArtwork.cacheFailure")
                        : animatedArtworkCacheSizeText
                ) {
                    Button(animatedArtworkCacheLabel) {
                        Task { await clearAnimatedArtworkCache() }
                    }
                    .disabled(rustCore == nil || AnimatedArtworkManager.shared.isClearing)
                }
            }
        }
    }

    private var animatedArtworkCacheSizeText: String {
        animatedArtworkCacheBytes.map { String(format: "%.1f MB", Double($0) / (1024 * 1024)) } ?? "—"
    }

    private var animatedArtworkCacheLabel: String {
        if AnimatedArtworkManager.shared.isClearing { return L10n.text("settings.animatedArtwork.cacheClearing") }
        let size = animatedArtworkCacheBytes.map { String(format: "%.1f", Double($0) / (1024 * 1024)) } ?? "—"
        return L10n.text("settings.animatedArtwork.clearCache", args: [size])
    }

    @MainActor
    private func clearAnimatedArtworkCache() async {
        guard let rustCore else { return }
        animatedArtworkCacheError = false
        do {
            animatedArtworkCacheBytes = try await AnimatedArtworkManager.shared.clear(core: rustCore)
            animatedArtworkCacheError = animatedArtworkCacheBytes != 0
        } catch {
            animatedArtworkCacheError = true
        }
    }

    // MARK: - Proveedores visuales

    private var visualProvidersSettingsView: some View {
        SettingsGroup {
            VisualProviderSettings()
        }
    }

    // MARK: - Inicio

    private var homeFeedSettingsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: L10n.text("settings.featured")) {
                SettingsRow(title: L10n.text("settings.featuredKind")) {
                    Picker(L10n.text("settings.featuredKind"), selection: Binding(
                        get: { homeViewModel.featuredCollectionKind },
                        set: { homeViewModel.setFeaturedCollectionKind($0) }
                    )) {
                        Text(L10n.text("settings.albums")).tag(HomeFeaturedCollectionKind.albums)
                        Text(L10n.text("settings.playlists")).tag(HomeFeaturedCollectionKind.playlists)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    sourcesGroup.frame(minWidth: 400, maxWidth: .infinity)
                    categoriesGroup.frame(minWidth: 400, maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 24) {
                    sourcesGroup
                    categoriesGroup
                }
            }
        }
    }

    private var sourcesGroup: some View {
        let currentRules = rules
        return SettingsGroup(
            title: settingsText("Fuentes de recomendación", "Recommendation Sources"),
            footer: L10n.text("settings.sourcesHint")
        ) {
            ForEach(Array(currentRules.enumerated()), id: \.element.id) { index, rule in
                sourceRow(rule, index: index, count: currentRules.count)
            }

            if homeViewModel.allFeaturedSourcesDisabled {
                Text(L10n.text("settings.enableSource"))
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button(L10n.text("settings.restoreSources")) {
                    var settings = homeViewModel.recommendationSettings
                    settings.setSources(
                        HomeRecommendationSettings.default.sources(for: homeViewModel.featuredCollectionKind),
                        for: homeViewModel.featuredCollectionKind
                    )
                    homeViewModel.setRecommendationSettings(settings)
                }
                .controlSize(.small)
            }
        }
    }

    private var categoriesGroup: some View {
        SettingsGroup(
            title: L10n.text("settings.categories"),
            footer: L10n.text("settings.categoriesHint") + "\n" + orderDescription
        ) {
            if homeViewModel.receivedCategories.count > 6 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(L10n.text("settings.searchCategory"), text: $categoryFilterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
            }

            ForEach(homeCategories) { category in
                categoryRow(category)
            }

            HStack(spacing: 8) {
                Button(L10n.text("settings.showAll")) {
                    var settings = homeViewModel.recommendationSettings
                    settings.hiddenCategoryKeys = []
                    homeViewModel.setRecommendationSettings(settings)
                }
                Button(L10n.text("settings.youtubeOrder")) {
                    setCategoryOrder(.youtube)
                }
                Button(L10n.text("settings.restoreOrder")) {
                    setCategoryOrder(.sideB)
                }
                Spacer()
            }
            .controlSize(.small)
        }
    }

    private var orderDescription: String {
        switch homeViewModel.recommendationSettings.categoryOrderMode {
        case .sideB: return L10n.text("settings.orderSideB")
        case .youtube: return L10n.text("settings.orderYouTube")
        case .custom: return L10n.text("settings.orderCustom")
        }
    }

    private func setCategoryOrder(_ mode: HomeCategoryOrderMode) {
        var settings = homeViewModel.recommendationSettings
        settings.categoryOrderMode = mode
        settings.categoryOrder = []
        homeViewModel.setRecommendationSettings(settings)
    }

    private func sourceRow(_ rule: HomeRecommendationSourceRule, index: Int, count: Int) -> some View {
        let title = rule.source.title
        return HStack(spacing: 10) {
            dragHandle(title: title).onDrag {
                draggingSource = rule.id
                return NSItemProvider(object: NSString(string: "source:\(rule.id)"))
            }

            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer(minLength: 8)

            moveButtons(id: "source-\(rule.id)", title: title, index: index, count: count) { delta in
                moveSource(rule.id, delta: delta)
            }

            SettingsSwitch(title: title, isOn: Binding(get: {
                rule.enabled
            }, set: { enabled in
                var settings = homeViewModel.recommendationSettings
                var updated = rules
                if let idx = updated.firstIndex(where: { $0.id == rule.id }) { updated[idx].enabled = enabled }
                settings.setSources(updated, for: homeViewModel.featuredCollectionKind)
                homeViewModel.setRecommendationSettings(settings)
            }))
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.utf8PlainText], isTargeted: nil) { _ in
            guard let source = draggingSource else { return false }
            draggingSource = nil
            moveSource(source, before: rule.id)
            return true
        }
    }

    private func categoryRow(_ category: HomeCategoryOption) -> some View {
        let heading = L10n.providerHeading(category.title)
        let allCategories = homeViewModel.receivedCategories
        let index = allCategories.firstIndex(where: { $0.id == category.id }) ?? 0
        return HStack(spacing: 10) {
            dragHandle(title: heading).onDrag {
                draggingCategory = category.id
                return NSItemProvider(object: NSString(string: "category:\(category.id)"))
            }

            Text(heading)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer(minLength: 8)

            moveButtons(id: "category-\(category.id)", title: heading, index: index, count: allCategories.count) { delta in
                moveCategory(category.id, delta: delta)
            }

            SettingsSwitch(title: heading, isOn: Binding(get: {
                homeViewModel.recommendationSettings.isCategoryVisible(key: category.id)
            }, set: { visible in
                var settings = homeViewModel.recommendationSettings
                settings.hiddenCategoryKeys.removeAll { $0 == category.id }
                if !visible { settings.hiddenCategoryKeys.append(category.id) }
                homeViewModel.setRecommendationSettings(settings)
            }))
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.utf8PlainText], isTargeted: nil) { _ in
            guard let source = draggingCategory else { return false }
            draggingCategory = nil
            moveCategory(source, before: category.id)
            return true
        }
    }

    private func dragHandle(title: String) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(width: 16, height: 24)
            .help(L10n.text("settings.drag", args: [title]))
            .accessibilityLabel(L10n.text("settings.dragAX", args: [title]))
    }

    private func moveButtons(id: String, title: String, index: Int, count: Int, move: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            Button { move(-1) } label: { Image(systemName: "chevron.up").frame(width: 20, height: 22) }
                .disabled(index == 0)
                .accessibilityLabel(L10n.text("settings.up", args: [title]))
            Button { move(1) } label: { Image(systemName: "chevron.down").frame(width: 20, height: 22) }
                .disabled(index >= count - 1)
                .accessibilityLabel(L10n.text("settings.down", args: [title]))
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    private func moveSource(_ id: String, delta: Int? = nil, before target: String? = nil) {
        var updated = rules
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        let destination = delta.map { min(max(index + $0, 0), updated.count - 1) }
            ?? target.flatMap { target in updated.firstIndex(where: { $0.id == target }) } ?? index
        guard destination != index else { return }
        let rule = updated.remove(at: index)
        updated.insert(rule, at: destination)
        var settings = homeViewModel.recommendationSettings
        settings.setSources(updated, for: homeViewModel.featuredCollectionKind)
        homeViewModel.setRecommendationSettings(settings)
    }

    private func moveCategory(_ id: String, delta: Int? = nil, before target: String? = nil) {
        var order = homeViewModel.receivedCategories.map(\.id)
        guard let index = order.firstIndex(of: id) else { return }
        let destination = delta.map { min(max(index + $0, 0), order.count - 1) }
            ?? target.flatMap { order.firstIndex(of: $0) } ?? index
        guard destination != index else { return }
        order.insert(order.remove(at: index), at: destination)
        var settings = homeViewModel.recommendationSettings
        order.append(contentsOf: settings.categoryOrder.filter { !order.contains($0) })
        settings.categoryOrderMode = .custom
        settings.categoryOrder = order
        homeViewModel.setRecommendationSettings(settings)
    }

    // MARK: - Cuenta

    private var accountSettingsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup {
                if let accountVM = accountViewModel, accountVM.isLoggedIn, let account = accountVM.account {
                    HStack(spacing: 14) {
                        if let thumb = account.thumbnail, let url = URL(string: thumb) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color.primary.opacity(0.12))
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 52))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name ?? "Usuario")
                                .font(.system(size: 15, weight: .semibold))
                            if let handle = account.handle {
                                Text(handle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            if let email = account.email {
                                Text(email)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        Button(L10n.text("account.sign_out")) {
                            if let core = rustCore, let storage = cookieStorage {
                                accountVM.logout(core: core, storage: storage)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.text("account.guest_mode"))
                                .font(.system(size: 14, weight: .semibold))
                            Text(settingsText(
                                "Iniciá sesión para sincronizar tus listas de reproducción, 'Me gusta' y recomendaciones.",
                                "Sign in to sync your playlists, likes, and personalized recommendations."))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button(L10n.text("account.sign_in_ellipsis")) {
                            onLoginRequested?()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            SettingsGroup(
                title: settingsText("Privacidad y almacenamiento", "Privacy & Storage"),
                footer: settingsText(
                    "Side B se conecta directamente a los servidores de streaming. Ningún dato de navegación ni credencial se envía a servidores de terceros.",
                    "Side B connects directly to streaming endpoints. No telemetry or credentials are sent to third parties.")
            ) {
                SettingsRow(title: settingsText("Almacenamiento de sesión", "Session Storage")) {
                    Text("Apple Keychain")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }

                SettingsRow(title: settingsText("Identificador de caché", "Cache Identifier")) {
                    Text(cookieStorage?.homeCacheIdentity() ?? "guest")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Atajos

    private var shortcutsSettingsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: settingsText("Reproducción", "Playback")) {
                shortcutRow(label: settingsText("Reproducir / Pausar", "Play / Pause"),
                            keys: [settingsText("Espacio", "Space")])
                shortcutRow(label: settingsText("Pista siguiente", "Next Track"), keys: ["⌘", "→"])
                shortcutRow(label: settingsText("Pista anterior", "Previous Track"), keys: ["⌘", "←"])
                shortcutRow(label: settingsText("Subir / Bajar volumen", "Volume Up / Down"), keys: ["⌘", "↑ / ↓"])
                shortcutRow(label: settingsText("Silenciar / Restaurar volumen", "Mute / Unmute"), keys: ["⌘", "M"])
            }

            SettingsGroup(title: settingsText("Navegación y ventana", "Navigation & Window")) {
                shortcutRow(label: settingsText("Abrir Configuración", "Open Settings"), keys: ["⌘", ","])
                shortcutRow(label: settingsText("Búsqueda rápida", "Quick Search"), keys: ["⌘", "K"])
                shortcutRow(label: settingsText("Nueva lista de reproducción", "New Playlist"), keys: ["⌘", "N"])
                shortcutRow(label: settingsText("Mostrar / Ocultar barra lateral", "Toggle Sidebar"), keys: ["⌘", "S"])
                shortcutRow(label: settingsText("Historial: Atrás", "History: Back"), keys: ["⌘", "["])
                shortcutRow(label: settingsText("Historial: Adelante", "History: Forward"), keys: ["⌘", "]"])
                shortcutRow(label: settingsText("Pantalla completa interactiva", "Interactive Fullscreen"), keys: ["⌘", "F"])
                shortcutRow(label: settingsText("Cerrar ventana / Cancelar", "Close Window / Dismiss"), keys: ["Esc"])
            }
        }
    }

    private func shortcutRow(label: String, keys: [String]) -> some View {
        SettingsRow(title: label) {
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    SettingsKeycap(key)
                }
            }
        }
    }
}

// MARK: - Sidebar item

private struct SettingsSidebarItem: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: category.icon)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)

                Text(category.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.12 : (isHovering ? 0.05 : 0)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Grouped list components

/// Grupo de filas con esquinas continuas y separadores finos entre filas.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }

            Group(subviews: content()) { rows in
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        rows[index]
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if index < rows.count - 1 {
                            Divider()
                                .opacity(0.45)
                                .padding(.leading, 14)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// Fila estándar: título (y descripción opcional) a la izquierda, control a la derecha.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            trailing()
        }
    }
}

/// Interruptor compacto con etiqueta accesible pero oculta.
struct SettingsSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

private struct SettingsKeycap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, label.count > 1 ? 7 : 0)
            .frame(minWidth: 24, minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.09))
            )
    }
}
