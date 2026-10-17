import Foundation

/// Keep the floating panel's outer inset and titlebar compensation together.
/// Window controls retain native actions and align with the expanded panel header.
enum ShellLayout {
    static let sidebarInset: CGFloat = 6
    static let sidebarWidth: CGFloat = 230
    static let sidebarCornerRadius: CGFloat = 10
    static let navigationTopInset: CGFloat = 18
    static let navigationBottomInset: CGFloat = 18
    static let navigationContentSpacing: CGFloat = 8
    static let navigationControlHeight: CGFloat = 36
    static let navigationSurfaceHeight: CGFloat = 42
    static let toolbarHostHeight = navigationTopInset + navigationSurfaceHeight + navigationBottomInset
    static let searchCollapsedWidth: CGFloat = 42
    static let searchExpandedWidth: CGFloat = 298
    static let destinationsSurfaceWidth: CGFloat = 246
    static let historySurfaceWidth: CGFloat = 76
    static let navigationClusterGap: CGFloat = 10
    static let navigationMinimumWidth: CGFloat = 420
    static let homeSettingsWidth: CGFloat = 292

    static let navigationRowCenter: CGFloat = navigationTopInset + navigationSurfaceHeight / 2

    /// Both groups are laid out in one actual toolbar viewport, including the fallback.
    static func navigationFrames(bounds: CGRect, menuSize: CGSize, historySize: CGSize,
                                 requestedCenter: CGPoint, historyCenterX: CGFloat? = nil) -> (menu: CGRect, history: CGRect) {
        let height = max(menuSize.height, historySize.height)
        let centerY = min(max(requestedCenter.y, bounds.minY + height / 2), bounds.maxY - height / 2)
        let desiredHistoryCenterX = historyCenterX ?? (bounds.maxX - historySize.width / 2)
        let historyMinimumCenterX = bounds.minX + menuSize.width + 16 + historySize.width / 2
        let historyMaximumCenterX = bounds.maxX - historySize.width / 2
        let historyCenterX = min(max(desiredHistoryCenterX, historyMinimumCenterX), historyMaximumCenterX)
        let history = CGRect(x: historyCenterX - historySize.width / 2, y: centerY - historySize.height / 2,
                             width: historySize.width, height: historySize.height)
        let latestMenuCenter = history.minX - 16 - menuSize.width / 2
        let centerX = min(max(requestedCenter.x, bounds.minX + menuSize.width / 2), latestMenuCenter)
        let menu = CGRect(x: centerX - menuSize.width / 2, y: centerY - menuSize.height / 2,
                          width: menuSize.width, height: menuSize.height)
        return (menu, history)
    }

    /// Rectangles share the measuring view's local coordinate space.
    static func topClearance(
        bounds: CGRect,
        contentLayoutRect: CGRect,
        windowControlsRect: CGRect?,
        isFlipped: Bool
    ) -> CGFloat {
        let contentInset = isFlipped
            ? contentLayoutRect.minY - bounds.minY
            : bounds.maxY - contentLayoutRect.maxY
        let controlsInset: CGFloat
        if let controls = windowControlsRect {
            controlsInset = isFlipped
                ? controls.maxY - bounds.minY
                : bounds.maxY - controls.minY
        } else {
            controlsInset = 0
        }
        return max(0, max(contentInset, controlsInset))
    }

    static func sameControlFrame(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5 && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }

    /// Offset in top-leading coordinates, independent of AppKit's Y direction.
    static func controlsOffset(closeRect: CGRect, bounds: CGRect, isFlipped: Bool) -> CGSize {
        let centerFromTop = isFlipped ? closeRect.midY - bounds.minY : bounds.maxY - closeRect.midY
        let target = sidebarInset + 22
        return CGSize(width: target - (closeRect.midX - bounds.minX), height: target - centerFromTop)
    }

    static func translatedControl(_ rect: CGRect, offset: CGSize, isFlipped: Bool) -> CGRect {
        rect.offsetBy(dx: offset.width, dy: isFlipped ? offset.height : -offset.height)
    }

    /// Outer inset remains fixed to the panel shell rather than shifting with the scroll view.
    static func sidebarReserveWidth(expanded: Bool) -> CGFloat {
        expanded ? sidebarWidth + sidebarInset * 2 : 0
    }

    static func sidebarHeaderInset(titlebarHeight: CGFloat) -> CGFloat {
        max(10, titlebarHeight + 4)
    }

    static func toolbarControlFrame(
        size: CGSize,
        windowBounds: CGRect,
        hostRect: CGRect,
        isFlipped: Bool,
        topInset: CGFloat,
        leadingInset: CGFloat? = nil,
        trailingInset: CGFloat? = nil
    ) -> CGRect {
        let originX: CGFloat
        if let leadingInset {
            originX = windowBounds.minX + leadingInset
        } else if let trailingInset {
            originX = windowBounds.maxX - trailingInset - size.width
        } else {
            originX = hostRect.midX - size.width / 2
        }

        let originY = isFlipped
            ? windowBounds.minY + topInset
            : windowBounds.maxY - topInset - size.height

        return CGRect(origin: CGPoint(x: originX, y: originY), size: size)
    }
}
