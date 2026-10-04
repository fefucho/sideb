import AppKit

/// Scroll view for Home feed content that must never expose a horizontal scroller.
/// AppKit may tile a scroll view again and recreate its scrollers, so enforce the
/// invariant at both the public setters and the end of tiling.
@MainActor
class HomeFeedScrollView: NSScrollView {
    var onViewportLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onViewportLayout?()
    }

    override var hasHorizontalScroller: Bool {
        get { false }
        set { if super.hasHorizontalScroller { super.hasHorizontalScroller = false } }
    }

    override var horizontalScroller: NSScroller? {
        get { nil }
        set { if super.horizontalScroller != nil { super.horizontalScroller = nil } }
    }

    override func tile() {
        super.tile()
        if super.hasHorizontalScroller { super.hasHorizontalScroller = false }
        if super.horizontalScroller != nil { super.horizontalScroller = nil }
    }
}
