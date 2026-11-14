import SwiftUI

/// Asa de arrastre del borde izquierdo del panel Ahora suena. El ancho se actualiza en vivo (sin animacion) y se
/// persiste al soltar. Doble clic restablece el ancho por defecto; con foco, las flechas ajustan +-16 pt.
struct PlaybackSidebarResizeHandle: View {
    let width: CGFloat
    let maximum: CGFloat
    /// (ancho propuesto, `true` al terminar el gesto/ajuste y debe persistirse)
    let onResize: (CGFloat, Bool) -> Void
    @State private var startWidth: CGFloat?
    @FocusState private var focused: Bool

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(PlaybackSidebarLayout.minimumWidth, min(maximum, value)), max(PlaybackSidebarLayout.minimumWidth, maximum))
    }

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    let start = startWidth ?? width
                    startWidth = start
                    onResize(clamped(start - value.translation.width), false)
                }
                .onEnded { value in
                    let start = startWidth ?? width
                    startWidth = nil
                    onResize(clamped(start - value.translation.width), true)
                })
            .onTapGesture(count: 2) { onResize(PlaybackSidebarLayout.width, true) }
            .focusable()
            .focused($focused)
            .onKeyPress(.leftArrow) { onResize(clamped(width + PlaybackSidebarLayout.keyboardStep), true); return .handled }
            .onKeyPress(.rightArrow) { onResize(clamped(width - PlaybackSidebarLayout.keyboardStep), true); return .handled }
            .accessibilityElement()
            .accessibilityLabel(L10n.text("playbackSidebar.resize"))
            .accessibilityValue(L10n.text("playbackSidebar.resize.value", args: [String(Int(width.rounded()))]))
            .accessibilityHint(L10n.text("playbackSidebar.resize.hint"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onResize(clamped(width + PlaybackSidebarLayout.keyboardStep), true)
                case .decrement: onResize(clamped(width - PlaybackSidebarLayout.keyboardStep), true)
                @unknown default: break
                }
            }
            .help(L10n.text("playbackSidebar.resize"))
    }
}
