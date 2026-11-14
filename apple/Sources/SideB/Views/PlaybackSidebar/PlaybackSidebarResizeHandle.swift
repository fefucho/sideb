import SwiftUI

/// Asa de arrastre del borde izquierdo del panel Ahora suena. El ancho cambia EN VIVO con el cursor, pero solo el panel
/// lo observa (`PlaybackPanelResizeModel`); la reserva de la pagina y UserDefaults se actualizan una vez al soltar.
/// Doble clic y flechas (+-16 pt) aplican el ancho de inmediato. Sin guia ni anillo de foco del sistema.
struct PlaybackSidebarResizeHandle: View {
    let width: CGFloat
    let maximum: CGFloat
    let resize: PlaybackPanelResizeModel
    /// Siempre es un ancho final (se aplica a la pagina y se persiste).
    let onResize: (CGFloat, Bool) -> Void
    @State private var drag: PlaybackSidebarResizeDrag?
    @State private var hovering = false
    @FocusState private var focused: Bool

    private func clamped(_ value: CGFloat) -> CGFloat {
        PlaybackSidebarResizeDrag(startWidth: width, maximum: maximum).target(translation: width - value)
    }

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            // Hover/foco de teclado neutros (sin color de acento).
            .overlay(alignment: .leading) {
                if resize.isResizing || hovering || focused {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(.white.opacity(resize.isResizing ? 0.3 : 0.2))
                        .frame(width: 2)
                        .padding(.leading, 3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onHover { hovering = $0 }
            .pointerStyle(.columnResize)
            .windowGestureRegion(.excluded)
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    let state = drag ?? PlaybackSidebarResizeDrag(startWidth: width, maximum: maximum)
                    if drag == nil { drag = state }
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { resize.update(state.target(translation: value.translation.width)) }
                }
                .onEnded { value in
                    let state = drag ?? PlaybackSidebarResizeDrag(startWidth: width, maximum: maximum)
                    drag = nil
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        onResize(state.target(translation: value.translation.width), true)
                        resize.liveWidth = nil
                    }
                })
            .onTapGesture(count: 2) { onResize(PlaybackSidebarLayout.width, true) }
            .focusable()
            .focusEffectDisabled()
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
