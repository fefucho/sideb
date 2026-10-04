import AppKit
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
        return WindowAlignedToolbarContainer(contentView: button, topInset: 17, leadingInset: 105)
    }

    func updateNSView(_ view: WindowAlignedToolbarContainer, context: Context) {
        context.coordinator.parent = self
        let label = isExpanded ? "Ocultar barra lateral" : "Mostrar barra lateral"
        context.coordinator.button?.toolTip = label
        context.coordinator.button?.setAccessibilityLabel(label)
    }

    final class Coordinator: NSObject {
        var parent: SidebarToolbarToggle
        weak var button: NSButton?
        init(_ parent: SidebarToolbarToggle) { self.parent = parent }
        @objc func toggle() { parent.isExpanded.toggle() }
    }
}

private final class SidebarHeaderButton: NSButton {
    override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 22) }
    override var fittingSize: NSSize { intrinsicContentSize }
}
