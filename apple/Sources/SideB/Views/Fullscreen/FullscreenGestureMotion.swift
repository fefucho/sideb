import SwiftUI

/// Only this compositor modifier observes per-contact displacement. The page,
/// shell and player model observe the one-time reveal flag instead.
struct FullscreenGestureMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let presentation: WindowGesturePresentation

    func body(content: Content) -> some View {
        GeometryReader { viewport in
            content
                .frame(width: viewport.size.width, height: viewport.size.height)
                .offset(y: reduceMotion ? 0 : presentation.fullscreenOffset)
                .opacity(reduceMotion
                    ? max(0, 1 - presentation.fullscreenOffset / max(1, viewport.size.height)) : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Keep route content stable; the capsule is the horizontal movement feedback.
/// Per-frame gesture values never enter the feed's own view tree.
struct GesturePageVisibility: ViewModifier {
    let presentation: WindowGesturePresentation
    let fullscreenPresented: Bool

    func body(content: Content) -> some View {
        content
            .opacity(!fullscreenPresented || presentation.revealUnderlying ? 1 : 0)
            .environment(\.sideBGesturePreviewVisible, presentation.revealUnderlying)
            .allowsHitTesting(!fullscreenPresented)
            .accessibilityHidden(fullscreenPresented)
    }
}
