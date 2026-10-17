import SwiftUI

/// Geometry belongs to the role of the control, never to the page displaying it.
enum SideBControlMetrics {
    static let categoryHeight: CGFloat = 48
    static let actionHeight: CGFloat = 40
    static let utilityHeight: CGFloat = 32
    static let categorySpacing: CGFloat = 10
    static let actionSpacing: CGFloat = 8
    static let groupInset: CGFloat = 4
    // Fullscreen remains a compact panel selector, like the native topbar.
    static let groupSegmentHeight: CGFloat = 32
    static let groupHeight = groupSegmentHeight + 2 * groupInset

    enum Size {
        case category, action, utility
        var height: CGFloat {
            switch self { case .category: categoryHeight; case .action: actionHeight; case .utility: utilityHeight }
        }
        var fontSize: CGFloat {
            switch self { case .category: 15.6; case .action: 14.4; case .utility: 12 }
        }
        var horizontalPadding: CGFloat {
            switch self { case .category: 20; case .action: 16; case .utility: 12 }
        }
    }
}

struct SideBControlLabel: View {
    let title: String
    var symbol: String? = nil
    var iconOnly = false

    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
            if !iconOnly { Text(title).lineLimit(1).fixedSize(horizontal: true, vertical: false) }
        }
        .accessibilityLabel(title)
    }
}

struct SideBControlStyle: ButtonStyle {
    var size: SideBControlMetrics.Size = .action
    var selected = false
    var iconOnly = false
    var prominent = false
    /// Visual state only: the Button caller must also use .disabled(loading) for keyboard and pointer actions.
    var loading = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(SideBControlSurface(size: size, selected: selected,
            iconOnly: iconOnly, prominent: prominent, pressed: configuration.isPressed, loading: loading))
    }
}

private struct SideBControlSurface: ViewModifier {
    let size: SideBControlMetrics.Size
    var selected = false
    var iconOnly = false
    var prominent = false
    var pressed = false
    var loading = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false
    @Environment(\.isFocused) private var focused

    func body(content: Content) -> some View {
        content
            .opacity(loading ? 0 : 1)
            .font(.system(size: iconOnly ? 16 : size.fontSize, weight: .semibold))
            .foregroundStyle(selected || prominent ? Color.white : Color.primary)
            .padding(.horizontal, iconOnly ? 0 : size.horizontalPadding)
            .frame(width: iconOnly ? size.height : nil, height: size.height)
            .background {
                Capsule().fill(Color.clear)
                    .compatGlass(interactive: isEnabled, tint: selected || prominent ? .sidebAccent : nil, in: Capsule())
                    // Keep selection explicit in opaque/inactive material, behind the label.
                    .overlay { Capsule().fill(Color.sidebAccent.opacity(selected || prominent ? 0.22 : 0)) }
                    .overlay { Capsule().fill(Color.white.opacity(isEnabled && hovered ? (pressed ? 0.04 : 0.09) : 0)) }
            }
            .overlay {
                Capsule().strokeBorder(selected || prominent ? Color.sidebAccentHighlight.opacity(0.8) : Color.primary.opacity(contrast == .increased ? 0.55 : 0.10),
                    lineWidth: selected || prominent || contrast == .increased ? 1 : 0.5)
                    .allowsHitTesting(false)
            }
            .overlay {
                if loading { ProgressView().controlSize(.small).accessibilityHidden(true).allowsHitTesting(false) }
            }
            .accessibilityValue(loading ? L10n.text("common.loading") : "")
            .overlay { Capsule().strokeBorder(Color.accentColor, lineWidth: focused && isEnabled ? 2 : 0).allowsHitTesting(false) }
            .brightness(isEnabled && pressed ? -0.05 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: pressed)
    }
}

extension View {
    /// Menus keep their native semantics; only the label receives the common geometry/material.
    func sidebControlLabel(size: SideBControlMetrics.Size = .action, selected: Bool = false,
                           iconOnly: Bool = false) -> some View {
        modifier(SideBControlSurface(size: size, selected: selected, iconOnly: iconOnly))
    }
}

struct SideBControlSegment<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let symbol: String
}
