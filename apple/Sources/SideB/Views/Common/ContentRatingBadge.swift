import AppKit
import SwiftUI
import SideBCore

enum ContentRatingBadgeMetrics {
    static let gap: CGFloat = 4
    static func side(for fontSize: CGFloat) -> CGFloat { min(12, max(9, (fontSize * 0.85).rounded())) }
    static func radius(for side: CGFloat) -> CGFloat { side * 3 / 14 }
}

/// Shared 14×14 path, scaled with secondary text; white .78 and dark glyph.
/// Drawing the glyph avoids the font baseline that displaced the previous E.
final class NativeContentRatingBadge: NSView {
    var rating: ContentRating = .unknown {
        didSet {
            isHidden = rating == .unknown
            let label = ContentRatingMetadata.label(rating)
            toolTip = label
            setAccessibilityLabel(label)
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }
    var fontSize: CGFloat = 12 {
        didSet {
            guard fontSize != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: ContentRatingBadgeMetrics.side(for: fontSize), height: ContentRatingBadgeMetrics.side(for: fontSize)) }
    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard rating != .unknown else { return }
        NSColor.white.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: ContentRatingBadgeMetrics.radius(for: bounds.width), yRadius: ContentRatingBadgeMetrics.radius(for: bounds.height)).fill()
        let points: [(CGFloat, CGFloat)]
        if rating == .explicit {
            points = [(4,3),(10,3),(10,4.5),(5.5,4.5),(5.5,6.25),(9.25,6.25),(9.25,7.75),(5.5,7.75),(5.5,9.5),(10,9.5),(10,11),(4,11)]
        } else if L10n.text("content.clean_glyph") == "L" {
            points = [(4,3),(5.5,3),(5.5,9.5),(10,9.5),(10,11),(4,11)]
        } else {
            points = [(10,3),(4,3),(4,11),(10,11),(10,9.5),(5.5,9.5),(5.5,4.5),(10,4.5)]
        }
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let position = NSPoint(x: bounds.minX + point.0 * bounds.width / 14, y: bounds.minY + point.1 * bounds.height / 14)
            if index == 0 { path.move(to: position) } else { path.line(to: position) }
        }
        path.close()
        NSColor(srgbRed: 28.0/255, green: 28.0/255, blue: 30.0/255, alpha: 1).setFill()
        path.fill()
    }
}

private struct ContentRatingBadgeRepresentable: NSViewRepresentable {
    let rating: ContentRating
    let fontSize: CGFloat
    func makeNSView(context: Context) -> NativeContentRatingBadge { NativeContentRatingBadge(frame: .zero) }
    func updateNSView(_ view: NativeContentRatingBadge, context: Context) { view.fontSize = fontSize; view.rating = rating }
}

struct ContentRatingBadge: View {
    let rating: ContentRating
    var fontSize: CGFloat = 12
    var body: some View {
        if rating != .unknown {
            ContentRatingBadgeRepresentable(rating: rating, fontSize: fontSize)
                .frame(width: ContentRatingBadgeMetrics.side(for: fontSize), height: ContentRatingBadgeMetrics.side(for: fontSize))
                .fixedSize()
                .help(ContentRatingMetadata.label(rating))
        }
    }
}

/// Wrap secondary credits without changing their links or truncation.
final class NativeRatedMetadata: NSStackView {
    let badge = NativeContentRatingBadge(frame: .zero)
    init(field: NSTextField, fontSize: CGFloat = 12) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = ContentRatingBadgeMetrics.gap
        distribution = .fill
        detachesHiddenViews = true
        badge.fontSize = fontSize
        badge.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(badge)
        addArrangedSubview(field)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A secondary line owns its badge; generic titles remain free of indicators.
struct ContentRatedMetadata<Content: View>: View {
    let rating: ContentRating
    var fontSize: CGFloat = 12
    let content: () -> Content
    init(rating: ContentRating, fontSize: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.rating = rating
        self.fontSize = fontSize
        self.content = content
    }
    var body: some View {
        HStack(alignment: .center, spacing: ContentRatingBadgeMetrics.gap) {
            ContentRatingBadge(rating: rating, fontSize: fontSize)
            content()
        }
        .help(ContentRatingMetadata.label(rating))
    }
}
