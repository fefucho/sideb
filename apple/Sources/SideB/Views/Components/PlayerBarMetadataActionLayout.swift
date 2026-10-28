import SwiftUI

/// The metadata's ideal native/SwiftUI size owns the action anchor. A marquee's
/// clip bounds never participate in this measurement, and unused space stays trailing.
struct PlayerBarMetadataActionLayout: Layout {
    static let actionWidth: CGFloat = 60
    static let gap: CGFloat = 10

    static func metadataWidth(ideal: CGFloat, available: CGFloat) -> CGFloat {
        min(max(0, ideal), max(0, available - actionWidth - gap))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let metadata = subviews[0].sizeThatFits(.unspecified)
        let actions = subviews[1].sizeThatFits(.unspecified)
        return CGSize(width: proposal.width ?? metadata.width + Self.gap + Self.actionWidth,
                      height: max(metadata.height, actions.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let ideal = subviews[0].sizeThatFits(.unspecified).width
        let width = Self.metadataWidth(ideal: ideal, available: bounds.width)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + width + Self.gap, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: Self.actionWidth, height: 46))
    }
}
