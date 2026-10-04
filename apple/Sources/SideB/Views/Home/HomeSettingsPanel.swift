import SwiftUI
import UniformTypeIdentifiers

/// Window-local overlay; dynamic preferences belong to the current Home account.
enum HomeSettingsVisibility {
    static func canPresent(page: PageDestination, fullscreenPresented: Bool, searchPresented: Bool) -> Bool {
        page == .home && !fullscreenPresented && !searchPresented
    }
}

struct HomeSettingsPanel: View {
    var homeViewModel: HomeViewModel
    let titlebarHeight: CGFloat
    var toolbarBottom: CGFloat = 0
    let onClose: () -> Void
    private enum Control: Hashable { case close, collectionKind, search, row(String), up(String), down(String), reset(String) }
    @FocusState private var focusedControl: Control?
    @State private var categorySearch = ""
    @State private var draggingSource: String?
    @State private var draggingCategory: String?

    private var rules: [HomeRecommendationSourceRule] {
        homeViewModel.recommendationSettings.sources(for: homeViewModel.featuredCollectionKind)
    }
    private var filteredCategories: [HomeCategoryOption] {
        guard !categorySearch.isEmpty else { return homeViewModel.receivedCategories }
        return homeViewModel.receivedCategories.filter { $0.title.localizedStandardContains(categorySearch) }
    }
    private var headerInset: CGFloat {
        toolbarBottom > 0 ? max(10, toolbarBottom + 16 - ShellLayout.sidebarInset)
            : ShellLayout.sidebarHeaderInset(titlebarHeight: titlebarHeight) + 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: headerInset)
            HStack(alignment: .center, spacing: 10) {
                Text("Configuración de Inicio")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .focused($focusedControl, equals: .close)
                .help("Cerrar configuración de Inicio")
                .accessibilityLabel("Cerrar configuración de Inicio")
            }
            .padding(.horizontal, 16)
            Divider().opacity(0.2).padding(.horizontal, 16).padding(.vertical, 16)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Destacados").font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Picker("Destacados", selection: Binding(
                        get: { homeViewModel.featuredCollectionKind },
                        set: { homeViewModel.setFeaturedCollectionKind($0) }
                    )) {
                        Text("Álbumes").tag(HomeFeaturedCollectionKind.albums)
                        Text("Playlists").tag(HomeFeaturedCollectionKind.playlists)
                    }
                    .pickerStyle(.segmented)
                    .focused($focusedControl, equals: .collectionKind)
                    .labelsHidden()
                    .accessibilityLabel("Tipo de recomendaciones de Inicio")

                    Text("Las fuentes se usan de arriba abajo, hasta completar un máximo de seis páginas.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(rules) { rule in sourceRow(rule) }
                    if homeViewModel.allFeaturedSourcesDisabled {
                        Text("Activá una fuente para mostrar destacados de este tipo.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .accessibilityIdentifier("home-sources-disabled")
                    }
                    if let error = homeViewModel.supplementalError {
                        Text("No se pudo actualizar la biblioteca.").font(.system(size: 12)).help(error)
                        Button("Reintentar biblioteca") { homeViewModel.retrySupplemental() }
                            .focused($focusedControl, equals: .reset("retry"))
                    }
                    Button("Restaurar fuentes") {
                        var settings = homeViewModel.recommendationSettings
                        settings.setSources(HomeRecommendationSettings.default.sources(for: homeViewModel.featuredCollectionKind),
                            for: homeViewModel.featuredCollectionKind)
                        homeViewModel.setRecommendationSettings(settings)
                    }
                    .focused($focusedControl, equals: .reset("sources"))

                    Divider().padding(.vertical, 8)
                    Text("Categorías de Inicio").font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text("Ocultar un estante no impide que su fuente aporte destacados.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if homeViewModel.receivedCategories.count > 8 {
                        TextField("Buscar categoría", text: $categorySearch)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedControl, equals: .search)
                            .accessibilityLabel("Buscar categoría de Inicio")
                    }
                    ForEach(filteredCategories) { category in categoryRow(category) }
                    if homeViewModel.receivedCategories.isEmpty {
                        Text("Las categorías aparecerán cuando cargue Inicio.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    } else if filteredCategories.isEmpty {
                        Text("No hay categorías con ese nombre.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Button("Mostrar todas las categorías") {
                        var settings = homeViewModel.recommendationSettings
                        settings.hiddenCategoryKeys = []
                        homeViewModel.setRecommendationSettings(settings)
                    }
                    .focused($focusedControl, equals: .reset("visibility"))
                    Button("Usar orden de YouTube") { setCategoryOrder(.youtube) }
                        .focused($focusedControl, equals: .reset("youtube"))
                    Button("Restaurar orden de Side B") { setCategoryOrder(.sideB) }
                        .focused($focusedControl, equals: .reset("sideb"))
                    Text(orderDescription).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: ShellLayout.homeSettingsWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: ShellLayout.sidebarCornerRadius, style: .continuous))
        .compatGlass(in: RoundedRectangle(cornerRadius: ShellLayout.sidebarCornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ShellLayout.sidebarCornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        .accessibilityIdentifier("home-settings-panel")
        .background(HomeSettingsKeyboardFocusBridge(isControlFocused: focusedControl != nil))
        .onChange(of: homeViewModel.featuredCollectionKind) { _, _ in draggingSource = nil }
        .onExitCommand(perform: onClose)
    }

    private var orderDescription: String {
        switch homeViewModel.recommendationSettings.categoryOrderMode {
        case .sideB: "Orden de Side B"
        case .youtube: "Orden de YouTube"
        case .custom: "Orden personalizado"
        }
    }

    private func sourceRow(_ rule: HomeRecommendationSourceRule) -> some View {
        HStack(spacing: 6) {
            Toggle(rule.source.title, isOn: Binding(get: {
                rules.first(where: { $0.id == rule.id })?.enabled ?? false
            }, set: { enabled in
                var settings = homeViewModel.recommendationSettings
                var updated = rules
                if let index = updated.firstIndex(where: { $0.id == rule.id }) { updated[index].enabled = enabled }
                settings.setSources(updated, for: homeViewModel.featuredCollectionKind)
                homeViewModel.setRecommendationSettings(settings)
            }))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .focused($focusedControl, equals: .row("source-\(rule.id)"))
            Spacer(minLength: 0)
            moveButtons(id: "source-\(rule.id)", title: rule.source.title,
                index: rules.firstIndex(where: { $0.id == rule.id }) ?? 0, count: rules.count) { delta in
                moveSource(rule.id, delta: delta)
            }
            dragHandle(title: rule.source.title).onDrag {
                draggingSource = rule.id
                return NSItemProvider(object: NSString(string: "source:\(rule.id)"))
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.utf8PlainText], isTargeted: nil) { _ in
            guard let source = draggingSource else { return false }
            draggingSource = nil
            moveSource(source, before: rule.id)
            return true
        }
    }

    private func categoryRow(_ category: HomeCategoryOption) -> some View {
        HStack(spacing: 6) {
            Toggle(category.title, isOn: Binding(get: {
                homeViewModel.recommendationSettings.isCategoryVisible(key: category.id)
            }, set: { visible in
                var settings = homeViewModel.recommendationSettings
                settings.hiddenCategoryKeys.removeAll { $0 == category.id }
                if !visible { settings.hiddenCategoryKeys.append(category.id) }
                homeViewModel.setRecommendationSettings(settings)
            }))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .focused($focusedControl, equals: .row("category-\(category.id)"))
            Spacer(minLength: 0)
            moveButtons(id: "category-\(category.id)", title: category.title,
                index: homeViewModel.receivedCategories.firstIndex(where: { $0.id == category.id }) ?? 0,
                count: homeViewModel.receivedCategories.count) { delta in moveCategory(category.id, delta: delta) }
            dragHandle(title: category.title).onDrag {
                draggingCategory = category.id
                return NSItemProvider(object: NSString(string: "category:\(category.id)"))
            }
        }
        .padding(.vertical, 3)
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
            .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 16, height: 24)
            .help("Arrastrar para ordenar \(title)")
            .accessibilityLabel("Arrastrar para ordenar \(title); también podés usar Subir y Bajar")
    }

    private func moveButtons(id: String, title: String, index: Int, count: Int, move: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 1) {
            Button { move(-1) } label: { Image(systemName: "chevron.up").frame(width: 16, height: 20) }
                .disabled(index == 0).focused($focusedControl, equals: .up(id))
                .accessibilityLabel("Subir \(title)")
            Button { move(1) } label: { Image(systemName: "chevron.down").frame(width: 16, height: 20) }
                .disabled(index >= count - 1).focused($focusedControl, equals: .down(id))
                .accessibilityLabel("Bajar \(title)")
        }
        .buttonStyle(.plain)
        .font(.system(size: 10))
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

    private func setCategoryOrder(_ mode: HomeCategoryOrderMode) {
        var settings = homeViewModel.recommendationSettings
        settings.categoryOrderMode = mode
        settings.categoryOrder = []
        homeViewModel.setRecommendationSettings(settings)
    }
}

private struct HomeSettingsKeyboardFocusBridge: NSViewRepresentable {
    let isControlFocused: Bool
    func makeNSView(context: Context) -> PlaybackSpaceFocusView { PlaybackSpaceFocusView() }
    func updateNSView(_ view: PlaybackSpaceFocusView, context: Context) { view.isControlFocused = isControlFocused }
    static func dismantleNSView(_ view: PlaybackSpaceFocusView, coordinator: ()) { view.clearScope() }
}
