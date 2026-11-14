import SwiftUI

/// Asa de arrastre del borde izquierdo del panel Ahora suena (estilo NSSplitView sin "live resize").
/// Durante el arrastre NO cambia el ancho real ni la reserva (eso recomponia toda la ventana en cada tick): solo se
/// mueve una guia fina, con estado local a esta vista. El ancho se aplica y persiste UNA vez al soltar.
/// Doble clic y flechas (+-16 pt) aplican el ancho de inmediato.
struct PlaybackSidebarResizeHandle: View {
    let width: CGFloat
    let maximum: CGFloat
    /// Siempre es un ancho final (se aplica y se persiste).
    let onResize: (CGFloat, Bool) -> Void
    @State private var drag: PlaybackSidebarResizeDrag?
    @State private var guideWidth: CGFloat?
    @State private var hovering = false
    @FocusState private var focused: Bool

    private func clamped(_ value: CGFloat) -> CGFloat {
        PlaybackSidebarResizeDrag(startWidth: width, maximum: maximum).target(translation: width - value)
    }

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            // Guia neutra (sin color de acento): linea de 2 pt en la posicion objetivo; tambien hover y foco de teclado.
            .overlay(alignment: .leading) {
                let active = guideWidth != nil
                if active || hovering || focused {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(.white.opacity(active ? 0.4 : 0.25))
                        .frame(width: 2)
                        .offset(x: -((guideWidth ?? width) - width) + 3)
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
                    withTransaction(transaction) { guideWidth = state.target(translation: value.translation.width) }
                }
                .onEnded { value in
                    let state = drag ?? PlaybackSidebarResizeDrag(startWidth: width, maximum: maximum)
                    drag = nil
                    guideWidth = nil
                    onResize(state.target(translation: value.translation.width), true)
                })
            .onTapGesture(count: 2) { onResize(PlaybackSidebarLayout.width, true) }
            .focusable()
            .focusEffectDisabled() // sin anillo azul del sistema; el foco de teclado se indica con la linea neutra
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
