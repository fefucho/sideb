import Foundation

/// One scale for sidebar text, symbols, artwork and row spacing.
/// Real layout dimensions keep hit testing and scrolling aligned with the visuals.
enum SidebarMetrics {
    static let scale: CGFloat = 1.10

    static func size(_ base: CGFloat) -> CGFloat { base * scale }
}
