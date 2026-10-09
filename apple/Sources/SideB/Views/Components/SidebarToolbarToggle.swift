import AppKit
import Observation
import SwiftUI

/// The native toolbar hosts the entire hit region at its fixed window anchor.
struct SidebarToolbarToggle: NSViewRepresentable {
    @Binding var isExpanded: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WindowAlignedToolbarContainer {
        let button = SidebarHeaderButton(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        button.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.toggle)
        context.coordinator.button = button
        context.coordinator.observeLocalization()
        return WindowAlignedToolbarContainer(contentView: button, topInset: 17, leadingInset: 105)
    }

    func updateNSView(_ view: WindowAlignedToolbarContainer, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateLocalization()
    }

    @MainActor final class Coordinator: NSObject {
        var parent: SidebarToolbarToggle
        weak var button: NSButton?
        var localizationObserver: AppKitLocalizationObserver?
        init(_ parent: SidebarToolbarToggle) { self.parent = parent }
        func updateLocalization() {
            let label = parent.isExpanded ? L10n.text("sidebar.hide") : L10n.text("sidebar.show")
            button?.toolTip = label
            button?.setAccessibilityLabel(label)
        }
        func observeLocalization() {
            localizationObserver = AppKitLocalizationObserver { [weak self] in self?.updateLocalization() }
            localizationObserver?.start()
        }
        @objc func toggle() { parent.isExpanded.toggle() }
    }
}

/// Observes the language revision and refreshes labels on existing AppKit controls.
@MainActor
final class AppKitLocalizationObserver {
    private let update: @MainActor () -> Void

    init(update: @escaping @MainActor () -> Void) {
        self.update = update
    }

    func start() { observeNextChange() }

    private func observeNextChange() {
        withObservationTracking {
            _ = L10n.revision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.update()
                self.observeNextChange()
            }
        }
    }
}

private final class SidebarHeaderButton: NSButton {
    override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 22) }
    override var fittingSize: NSSize { intrinsicContentSize }
}
