import SwiftUI

/// Pure geometry for the content frame so it can be tested without a view hierarchy.
enum ContentEdgeFrameMetrics {
    /// Fade length as a fraction of the frame width, never more than half of it.
    static func fadeFraction(width: CGFloat, fade: CGFloat) -> CGFloat {
        guard width > 0, fade > 0 else { return 0 }
        return min(0.5, fade / width)
    }

    /// Fracciones de desvanecimiento (izquierda, derecha). Con la sidebar nativa expandida (`flushLeading`) el borde
    /// izquierdo es un corte recto y limpio, sin desvanecimiento; el derecho se conserva.
    static func fadeFractions(width: CGFloat, fade: CGFloat, flushLeading: Bool) -> (leading: CGFloat, trailing: CGFloat) {
        let fraction = fadeFraction(width: width, fade: fade)
        return (flushLeading ? 0 : fraction, fraction)
    }

    /// Esquinas izquierdas rectas cuando el contenido lindera con la sidebar nativa.
    static func leadingCornerRadius(_ radius: CGFloat, flushLeading: Bool) -> CGFloat { flushLeading ? 0 : radius }
}

/// Presents the page area as a sibling panel of the floating sidebars instead of a bare clipped rectangle:
/// rounded corners, an optional hairline border (user setting, `ContentBorderStyle`) and a soft alpha fade on the
/// left/right edges so shelves that bleed to the edge dissolve instead of being cut. The fade is an alpha mask
/// (one compositing pass), never a stack of blurs. There is deliberately no inner shadow: it made the page look sunken.
struct ContentEdgeFrame: ViewModifier {
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(HomeAppearance.contentBorderKey, store: HomeAppearance.preferences) private var borderRaw = ContentBorderStyle.default.rawValue

    func body(content: Content) -> some View {
        let radius = ShellLayout.contentCornerRadius
        let simple = reduceTransparency || contrast == .increased
        // leadingInset == 0 significa sidebar nativa expandida: el contenido se corta recto contra su borde.
        let flush = leadingInset == 0
        let left = ContentEdgeFrameMetrics.leadingCornerRadius(radius, flushLeading: flush)
        let shape = UnevenRoundedRectangle(topLeadingRadius: left, bottomLeadingRadius: left,
                                           bottomTrailingRadius: radius, topTrailingRadius: radius, style: .continuous)
        content
            .mask {
                GeometryReader { proxy in
                    let fractions = simple ? (leading: CGFloat(0), trailing: CGFloat(0))
                        : ContentEdgeFrameMetrics.fadeFractions(width: proxy.size.width, fade: ShellLayout.contentEdgeFade, flushLeading: flush)
                    shape.fill(
                        LinearGradient(stops: [
                            .init(color: .black.opacity(fractions.leading > 0 ? 0 : 1), location: 0),
                            .init(color: .black, location: fractions.leading),
                            .init(color: .black, location: 1 - fractions.trailing),
                            .init(color: .black.opacity(fractions.trailing > 0 ? 0 : 1), location: 1)
                        ], startPoint: .leading, endPoint: .trailing)
                    )
                }
            }
            .overlay {
                shape.strokeBorder(.white.opacity(ContentBorderStyle.resolve(borderRaw).strokeOpacity(highContrast: simple)), lineWidth: 0.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, ShellLayout.contentFrameInset)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
    }
}

extension View {
    /// Extiende el viewport de un scroll horizontal hasta el borde izquierdo del detalle (contra la sidebar nativa)
    /// anulando el margen de la pagina; ese margen debe reponerse como padding inicial DENTRO del contenido.
    func leadingBleed(_ inset: CGFloat) -> some View { padding(.leading, -inset) }

    func contentEdgeFrame(leadingInset: CGFloat = 0, trailingInset: CGFloat = 0) -> some View {
        modifier(ContentEdgeFrame(leadingInset: leadingInset, trailingInset: trailingInset))
    }
}
