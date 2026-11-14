import AppKit
import SwiftUI

/// Sombra del panel como capa de Core Animation con `shadowPath` explicito: cambiar el ancho en vivo solo actualiza el
/// path (coste O(1), sin pase offscreen de SwiftUI por tick). Se actualiza en `layout()` sin acciones implicitas.
struct PlaybackPanelShadow: NSViewRepresentable {
    func makeNSView(context: Context) -> PlaybackPanelShadowView { PlaybackPanelShadowView() }
    func updateNSView(_ nsView: PlaybackPanelShadowView, context: Context) {}
}

final class PlaybackPanelShadowView: NSView {
    static let cornerRadius: CGFloat = 16
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -6)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
        CATransaction.commit()
    }
}
