import SwiftUI
import SideBCore

// MARK: - MenuItemRowView

struct MenuItemRowView: View {
    let item: MenuActionItem
    let target: MenuTarget
    let facts: MenuFacts
    let executor: MenuActionExecutor

    var body: some View {
        Group {
            if let subitems = item.subitems {
                Menu {
                    if subitems.isEmpty {
                        Label(L10n.text("menu.no_options"), systemImage: "tray")
                    } else {
                        ForEach(subitems) { sub in
                            let subActionId = sub.id
                            Button(role: sub.isDestructive ? .destructive : nil) {
                                executor.execute(action: subActionId, target: target, facts: facts)
                            } label: {
                                if sub.systemImage.isEmpty {
                                    Text(sub.title)
                                } else {
                                    Label(sub.title, systemImage: sub.systemImage)
                                }
                            }
                            .disabled(!sub.isEnabled)
                        }
                    }
                } label: {
                    if item.systemImage.isEmpty {
                        Text(item.title)
                    } else {
                        Label(item.title, systemImage: item.systemImage)
                    }
                }
                .disabled(!item.isEnabled)
            } else {
                let actionId = item.id
                Button(role: item.isDestructive ? .destructive : nil) {
                    executor.execute(action: actionId, target: target, facts: facts)
                } label: {
                    if item.systemImage.isEmpty {
                        Text(item.title)
                    } else {
                        Label(item.title, systemImage: item.systemImage)
                    }
                }
                .disabled(!item.isEnabled)
            }
        }
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - MenuSectionContentView

/// Vista reutilizable en SwiftUI que renderiza fielmente las secciones puras de [MenuSection] (PLAN-007).
struct MenuSectionContentView: View {
    let sections: [MenuSection]
    let target: MenuTarget
    let facts: MenuFacts
    let executor: MenuActionExecutor

    init(
        sections: [MenuSection],
        target: MenuTarget,
        facts: MenuFacts,
        executor: MenuActionExecutor
    ) {
        self.sections = sections
        self.target = target
        self.facts = facts
        self.executor = executor
    }

    var body: some View {
        ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
            if index > 0 {
                Divider()
            }
            ForEach(section.items) { item in
                MenuItemRowView(
                    item: item,
                    target: target,
                    facts: facts,
                    executor: executor
                )
            }
        }
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - View Extensions

extension View {
    /// Aplica el menú contextual unificado de Side B con resolución perezosa en el momento del clic.
    func sideBContextMenu(
        target: MenuTarget,
        origin: MenuOrigin,
        facts: MenuFacts,
        player: PlayerViewModel?,
        router: NavigationRouter?,
        core: SideBCore?
    ) -> some View {
        self.contextMenu {
            let sections = MenuPolicy.resolveSections(target: target, origin: origin, facts: facts)
            let executor = MenuActionExecutor(player: player, router: router, core: core)
            MenuSectionContentView(
                sections: sections,
                target: target,
                facts: facts,
                executor: executor
            )
            .labelStyle(.titleAndIcon)
        }
    }
}

// MARK: - SideBEllipsisMenuButton

/// Apariencia común para las opciones de canciones, colecciones y reproductor.
struct SideBEllipsisLabel: View {
    var iconSize: CGFloat = 13

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.78))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }
}

/// Botón estándar «…» que despliega exactamente las mismas opciones que el clic secundario.
struct SideBEllipsisMenuButton: View {
    let target: MenuTarget
    let origin: MenuOrigin
    let facts: MenuFacts
    let player: PlayerViewModel?
    let router: NavigationRouter?
    let core: SideBCore?
    var iconSize: CGFloat = 13.0

    init(
        target: MenuTarget,
        origin: MenuOrigin,
        facts: MenuFacts,
        player: PlayerViewModel?,
        router: NavigationRouter?,
        core: SideBCore?,
        iconSize: CGFloat = 13.0
    ) {
        self.target = target
        self.origin = origin
        self.facts = facts
        self.player = player
        self.router = router
        self.core = core
        self.iconSize = iconSize
    }

    var body: some View {
        Menu {
            let sections = MenuPolicy.resolveSections(target: target, origin: origin, facts: facts)
            let executor = MenuActionExecutor(player: player, router: router, core: core)
            MenuSectionContentView(
                sections: sections,
                target: target,
                facts: facts,
                executor: executor
            )
            .labelStyle(.titleAndIcon)
        } label: {
            SideBEllipsisLabel(iconSize: iconSize)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(L10n.text("menu.more_options"))
    }
}
