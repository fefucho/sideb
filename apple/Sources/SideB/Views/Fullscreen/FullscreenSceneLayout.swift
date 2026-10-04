import SwiftUI

/// Geometry for a single presentation frame. Artwork and metadata share one block.
struct FullscreenSceneMetrics {
    let viewport: CGSize
    let topPadding: CGFloat = 52
    let bottomReservedHeight: CGFloat = 112
    let metadataSpacing: CGFloat = 16
    let metadataHeight: CGFloat = 68
    let availableContentHeight: CGFloat
    let horizontalPadding: CGFloat
    let columnSpacing: CGFloat
    let leftWidth: CGFloat
    let rightWidth: CGFloat
    let artworkSize: CGFloat
    let contentPanelHeight: CGFloat

    init(viewport: CGSize) {
        self.viewport = viewport
        availableContentHeight = max(200, viewport.height - topPadding - bottomReservedHeight)
        horizontalPadding = max(24, min(48, viewport.width * 0.035))
        columnSpacing = max(24, min(40, viewport.width * 0.028))
        let availableWidth = max(0, viewport.width - horizontalPadding * 2 - columnSpacing)
        let maxRight = max(300, availableWidth * 0.56)
        let minRight = min(340, maxRight)
        rightWidth = min(maxRight, max(minRight, min(600, availableWidth * 0.52)))
        leftWidth = max(100, availableWidth - rightWidth)
        artworkSize = max(100, min(leftWidth * 0.90,
                                  availableContentHeight - metadataSpacing - metadataHeight - 16))
        contentPanelHeight = max(80, availableContentHeight - 54)
    }

    var artworkBlockHeight: CGFloat { artworkSize + metadataSpacing + metadataHeight }

    static func typography(artworkWidth: CGFloat) -> (title: CGFloat, subtitle: CGFloat, action: CGFloat) {
        let amount = max(0, min(1, (artworkWidth - 300) / 200))
        return (21 + 7 * amount, 14.5 + 3 * amount, 20 + 2 * amount)
    }
}

/// The canvas stays window-sized. Only its foreground reservation changes with
/// sidebar progress, so the background cannot acquire a later, narrower proposal.
struct FullscreenSidebarGeometry {
    let canvasSize: CGSize
    let progress: CGFloat

    init(canvasSize: CGSize, progress: CGFloat) {
        self.canvasSize = canvasSize
        self.progress = max(0, min(1, progress))
    }

    var contentOffset: CGFloat { ShellLayout.sidebarReserveWidth(expanded: true) * progress }
    var contentSize: CGSize { CGSize(width: max(100, canvasSize.width - contentOffset), height: canvasSize.height) }
    var metrics: FullscreenSceneMetrics { FullscreenSceneMetrics(viewport: contentSize) }
    var isTransitioning: Bool { progress > 0 && progress < 1 }
}
