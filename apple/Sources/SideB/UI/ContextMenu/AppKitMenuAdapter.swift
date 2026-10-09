import AppKit
import Foundation

// MARK: - AppKitMenuAdapter

/// Adaptador de presentación que traduce el modelo puro [MenuSection] a un NSMenu nativo (PLAN-007).
@MainActor
enum AppKitMenuAdapter {

    static func buildNSMenu(
        sections: [MenuSection],
        target: MenuTarget,
        facts: MenuFacts,
        executor: MenuActionExecutor
    ) -> NSMenu {
        let title: String
        switch target {
        case .song(let s):
            title = s.title
        case .album(_, _, let t, _, _, _):
            title = t
        case .playlist(_, let t, _, _, _):
            title = t
        case .radioMix(_, let t, _, _):
            title = t
        case .artist(_, let n, _, _):
            title = n
        }

        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        var addedAnySection = false

        for section in sections where !section.items.isEmpty {
            if addedAnySection {
                menu.addItem(NSMenuItem.separator())
            }
            addedAnySection = true

            for item in section.items {
                let menuItem = makeMenuItem(
                    item: item,
                    target: target,
                    facts: facts,
                    executor: executor
                )
                menu.addItem(menuItem)
            }
        }

        return menu
    }

    /// Genera una imagen template estandarizada a 16x16pt para menús nativos de macOS,
    /// garantizando alineación visual uniforme, nitidez y respuesta al modo oscuro/claro y acentos de selección.
    nonisolated static func menuSymbol(named name: String) -> NSImage? {
        guard !name.isEmpty, let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let configured = base.withSymbolConfiguration(config) ?? base

        let canvasSize = NSSize(width: 16, height: 16)
        let canvas = NSImage(size: canvasSize, flipped: false) { _ in
            let aspectWidth = canvasSize.width / max(configured.size.width, 1)
            let aspectHeight = canvasSize.height / max(configured.size.height, 1)
            let scale = min(min(aspectWidth, aspectHeight), 1.0)
            let drawWidth = configured.size.width * scale
            let drawHeight = configured.size.height * scale
            let drawRect = NSRect(
                x: (canvasSize.width - drawWidth) / 2.0,
                y: (canvasSize.height - drawHeight) / 2.0,
                width: drawWidth,
                height: drawHeight
            )
            configured.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        canvas.isTemplate = true
        return canvas
    }

    private static func makeMenuItem(
        item: MenuActionItem,
        target: MenuTarget,
        facts: MenuFacts,
        executor: MenuActionExecutor
    ) -> NSMenuItem {
        if let subitems = item.subitems {
            let parentItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            if !item.systemImage.isEmpty {
                parentItem.image = menuSymbol(named: item.systemImage)
                if #available(macOS 27.0, *) {
                    parentItem.preferredImageVisibility = .visible
                }
            }
            let submenu = NSMenu(title: item.title)
            submenu.autoenablesItems = false

            if subitems.isEmpty {
                let emptyItem = NSMenuItem(title: L10n.text("menu.no_options"), action: nil, keyEquivalent: "")
                emptyItem.image = menuSymbol(named: "tray")
                if #available(macOS 27.0, *) {
                    emptyItem.preferredImageVisibility = .visible
                }
                emptyItem.isEnabled = false
                submenu.addItem(emptyItem)
            } else {
                for sub in subitems {
                    let subMenuItem = makeMenuItem(
                        item: sub,
                        target: target,
                        facts: facts,
                        executor: executor
                    )
                    submenu.addItem(subMenuItem)
                }
            }

            parentItem.submenu = submenu
            parentItem.isEnabled = item.isEnabled
            return parentItem
        } else {
            let menuItem = ActionMenuItem(title: item.title, systemImageName: item.systemImage) {
                executor.execute(action: item.id, target: target, facts: facts)
            }
            if !item.systemImage.isEmpty {
                if #available(macOS 27.0, *) {
                    menuItem.preferredImageVisibility = .visible
                }
            }
            menuItem.isEnabled = item.isEnabled
            return menuItem
        }
    }
}
