import SwiftUI

/// Pure geometry for the content frame so it can be tested without a view hierarchy.
enum ContentEdgeFrameMetrics {
    /// Fade length as a fraction of the frame width, never more than half of it.
    static func fadeFraction(width: CGFloat, fade: CGFloat) -> CGFloat {
        guard width > 0, fade > 0 else { return 0 }
        return min(0.5, fade / width)
    }
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
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .mask {
                GeometryReader { proxy in
                    let fraction = simple ? 0 : ContentEdgeFrameMetrics.fadeFraction(width: proxy.size.width, fade: ShellLayout.contentEdgeFade)
                    shape.fill(
                        LinearGradient(stops: [
                            .init(color: .black.opacity(fraction > 0 ? 0 : 1), location: 0),
                            .init(color: .black, location: fraction),
                            .init(color: .black, location: 1 - fraction),
                            .init(color: .black.opacity(fraction > 0 ? 0 : 1), location: 1)
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
    func contentEdgeFrame(leadingInset: CGFloat = 0, trailingInset: CGFloat = 0) -> some View {
        modifier(ContentEdgeFrame(leadingInset: leadingInset, trailingInset: trailingInset))
    }
}
