import AppKit
import SwiftUI

/// Regions protect fullscreen dismissal from scrolling panels and controls.
/// History uses the window viewport, with explicit Home horizontal exceptions.
enum WindowGestureRegion: Sendable {
    case content
    case excluded
    case horizontalContent
    case verticalContent
}

struct WindowGestureRouting: Equatable {
    var isInContent = false
    var isExcluded = false
    var ownsHorizontal = false
    var ownsVertical = false

    var allowsHistory: Bool { isInContent }
    var allowsFullscreenDismissal: Bool {
        isInContent && !isExcluded && !ownsHorizontal && !ownsVertical
    }
}

/// Non-hittable markers keep SwiftUI regions inspectable without intercepting
/// clicks, text selection, scrolling or accessibility focus.
@MainActor
final class WindowGestureRegionView: NSView {
    var region: WindowGestureRegion = .content
    var isRegionActive = true

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
}

@MainActor
enum WindowGestureRegions {
    /// Base window eligibility. Home's explicitly reserved horizontal regions
    /// are checked separately; generic controls/scroll views do not veto history.
    static func allowsHistory(at point: NSPoint, in root: NSView) -> Bool {
        !root.isHidden && root.alphaValue > 0.01 && root.bounds.contains(point)
    }

    /// Only explicit horizontal markers and native owners reserve Home input.
    /// An ancestor vertical scroll, a control or a whole shelf row never does.
    /// Foreground shell markers prevent an underlying carousel from claiming
    /// an event over the player, sidebar or navigation header.
    static func horizontalContentOwnsHistoryGesture(at point: NSPoint, in root: NSView) -> Bool {
        var regions = WindowGestureRouting()
        collectMarkers(at: point, in: root, includeLegacyOwners: true, into: &regions)
        return regions.ownsHorizontal && !regions.isExcluded
    }

    static func routing(at point: NSPoint, in root: NSView,
                        includeNativeFallback: Bool = true) -> WindowGestureRouting {
        var result = WindowGestureRouting(isInContent: allowsHistory(at: point, in: root))
        collectMarkers(at: point, in: root, includeLegacyOwners: includeNativeFallback, into: &result)

        // Fullscreen declares its panels semantically. Its transparent artwork
        // and background can hit through to a retained native page underneath;
        // that page must never provide an owner for the foreground interaction.
        guard includeNativeFallback else { return result }

        // Native fallback follows the actual responder branch. Inspecting every
        // scroll view geometrically would include a page revealed underneath
        // the fullscreen surface and incorrectly give it the foreground gesture.
        let hitPoint = root.superview.map { root.convert(point, to: $0) } ?? point
        var target = root.hitTest(hitPoint)
        while let current = target {
            if isInteractiveControl(current) { result.isExcluded = true }
            if let scroll = current as? NSScrollView {
                includeAxes(of: scroll, into: &result)
            }
            if current === root { break }
            target = current.superview
        }

        return result
    }

    private static func collectMarkers(at point: NSPoint, in view: NSView,
                                       includeLegacyOwners: Bool,
                                       into result: inout WindowGestureRouting) {
        guard !view.isHidden, view.alphaValue > 0.01, view.bounds.contains(point) else { return }
        if let marker = view as? WindowGestureRegionView, marker.isRegionActive {
            switch marker.region {
            case .content: result.isInContent = true
            case .excluded: result.isExcluded = true
            case .horizontalContent: result.ownsHorizontal = true
            case .verticalContent: result.ownsVertical = true
            }
        }
        if includeLegacyOwners, let owner = view as? HorizontalNavigationGestureOwner,
           owner.ownsHorizontalNavigationGesture {
            result.ownsHorizontal = true
        }
        for child in view.subviews.reversed() {
            collectMarkers(at: child.convert(point, from: view), in: child,
                           includeLegacyOwners: includeLegacyOwners, into: &result)
        }
    }

    private static func isInteractiveControl(_ view: NSView) -> Bool {
        if let slider = view as? NSSlider { return slider.isEnabled }
        if let text = view as? NSTextView {
            return text.isEditable || (text.isSelectable && text.selectedRange().length > 0)
        }
        if let field = view as? NSTextField {
            return field.isEditable
        }
        return false
    }

    private static func includeAxes(of scroll: NSScrollView, into result: inout WindowGestureRouting) {
        guard let document = scroll.documentView else { return }
        var size = document.bounds.size
        var isExplicitHorizontalCollection = false
        if let collection = document as? NSCollectionView,
           let layout = collection.collectionViewLayout {
            let layoutSize = layout.collectionViewContentSize
            size.width = max(size.width, layoutSize.width)
            size.height = max(size.height, layoutSize.height)
            if let flow = layout as? NSCollectionViewFlowLayout {
                isExplicitHorizontalCollection = flow.scrollDirection == .horizontal
            }
        }
        let clip = scroll.contentView.bounds.size

        // Un scrollview sólo posee el eje horizontal si es genuinamente un scroll horizontal:
        // 1. Un carrusel puramente horizontal (horizontal allowed, vertical none)
        // 2. Un NSCollectionView con scrollDirection explícitamente horizontal
        // 3. Un scrollview con scroller horizontal explícito y sin scroller vertical
        let isDedicatedHorizontalScroll =
            (scroll.horizontalScrollElasticity == .allowed && scroll.verticalScrollElasticity == .none) ||
            isExplicitHorizontalCollection ||
            (scroll.hasHorizontalScroller && !scroll.hasVerticalScroller && size.width > clip.width + 2)

        let isDedicatedVerticalScroll = scroll.hasVerticalScroller ||
            scroll.verticalScrollElasticity == .allowed ||
            size.height > clip.height + 2

        result.ownsHorizontal = result.ownsHorizontal || isDedicatedHorizontalScroll
        result.ownsVertical = result.ownsVertical || isDedicatedVerticalScroll
    }
}

private struct WindowGestureRegionMarker: NSViewRepresentable {
    let region: WindowGestureRegion
    let active: Bool

    func makeNSView(context: Context) -> WindowGestureRegionView {
        let view = WindowGestureRegionView()
        view.region = region
        view.isRegionActive = active
        return view
    }

    func updateNSView(_ view: WindowGestureRegionView, context: Context) {
        view.region = region
        view.isRegionActive = active
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WindowGestureRegionView,
                     context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

extension View {
    func windowGestureRegion(_ region: WindowGestureRegion, active: Bool = true) -> some View {
        background(WindowGestureRegionMarker(region: region, active: active))
    }
}

private struct SideBGesturePreviewVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Exposes the retained native viewport while its work stays suspended.
    var sideBGesturePreviewVisible: Bool {
        get { self[SideBGesturePreviewVisibleKey.self] }
        set { self[SideBGesturePreviewVisibleKey.self] = newValue }
    }
}
