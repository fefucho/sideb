import SwiftUI

/// Asa de arrastre del borde izquierdo del panel Ahora suena. El ancho cambia EN VIVO con el cursor, pero solo el panel
/// lo observa (`PlaybackPanelResizeModel`); la reserva de la pagina y UserDefaults se actualizan una vez al soltar.
/// Doble clic y flechas (+-16 pt) aplican el ancho de inmediato. Sin indicador visual (ni guia, ni hover, ni anillo de foco): solo cursor, accesibilidad y teclado.
struct PlaybackSidebarResizeHandle: View {
    let width: CGFloat
    let maximum: CGFloat
    let resize: PlaybackPanelResizeModel
    /// Siempre es un ancho final (se aplica a la pagina y se persiste).
    let onResize: (CGFloat, Bool) -> Void
    @State private var drag: PlaybackSidebarResizeDrag?
    @FocusState private var focused: Bool

    private func clamped(_ value: CGFloat) -> CGFloat {
        PlaybackSidebarResizeDrag(startWidth: width, maximum: maximum).target(translation: width - value)
    }

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
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
                        resize.finish()
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
