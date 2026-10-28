import SwiftUI
import SideBCore

/// Only overflow edges fade; fitting categories keep their complete capsule.
/// Geometry publishes two booleans rather than a scroll offset on every frame.
struct SearchFilterChips: View {
    let chips: [SearchChipRecord]
    var gestureRegionActive = true
    let onSelect: (SearchChipRecord) -> Void
    @State private var overflow = SearchFilterChipOverflow()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SideBControlMetrics.categorySpacing) {
                ForEach(chips, id: \.id) { chip in
                    Button(chip.title) { onSelect(chip) }
                        .buttonStyle(SideBControlStyle(size: .category, selected: chip.selected))
                        .accessibilityAddTraits(chip.selected ? .isSelected : [])
                }
            }.padding(.vertical, 4)
        }
        .scrollClipDisabled()
        .modifier(SearchFilterScrollEdges())
        .onScrollGeometryChange(for: SearchFilterChipOverflow.self) { geometry in
            SearchFilterChipOverflow(leading: geometry.visibleRect.minX > 0.5,
                trailing: geometry.visibleRect.maxX < geometry.contentSize.width - 0.5)
        } action: { _, value in overflow = value }
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [overflow.leading ? .clear : .white, .white],
                    startPoint: .leading, endPoint: .trailing).frame(width: 24)
                Rectangle().fill(.white)
                LinearGradient(colors: [.white, overflow.trailing ? .clear : .white],
                    startPoint: .leading, endPoint: .trailing).frame(width: 24)
            }
        }
        .windowGestureRegion(.horizontalContent, active: gestureRegionActive)
        .frame(height: chips.isEmpty ? 0 : SideBControlMetrics.categoryHeight + 8)
        .accessibilityIdentifier("search-filter-chips")
    }
}

private struct SearchFilterChipOverflow: Equatable {
    var leading = false
    var trailing = false
}

private struct SearchFilterScrollEdges: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .horizontal)
        } else { content }
    }
}
