import AppKit
import SwiftUI

/// A single lightweight host over the central viewport. Its progress is local;
/// rendering it does not load the destination or invalidate the page beneath it.
struct NavigationGestureIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let presentation: WindowGesturePresentation

    var body: some View {
        ZStack {
            if let snapshot = presentation.horizontal {
                capsule(snapshot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: snapshot.direction == .back ? .leading : .trailing)
                    .padding(.horizontal, 14)
                    .opacity(presentation.horizontalVisible ? 1 : 0)
                    .accessibilityHidden(!presentation.horizontalVisible)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: announcement) { _, text in GestureAccessibility.announce(text) }
    }

    private func capsule(_ snapshot: WindowGesturePresentation.HorizontalSnapshot) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: snapshot.progress)
                    .stroke(snapshot.armed ? AppTheme.accentHighlight : Color.primary.opacity(0.7),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: snapshot.direction == .back ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(snapshot.armed ? AppTheme.accentHighlight
                                     : Color.primary.opacity(snapshot.available ? 0.85 : 0.45))
            }
            .frame(width: 29, height: 29)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(action(snapshot))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(snapshot.armed ? AppTheme.accentHighlight : Color.secondary)
                Text(snapshot.available ? snapshot.title : unavailableTitle(snapshot))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(snapshot.available ? 0.9 : 0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 164, alignment: .leading)
        }
        .padding(.leading, 8)
        .padding(.trailing, 13)
        .frame(height: 44)
        .fixedSize(horizontal: true, vertical: true)
        .compatGlass(in: Capsule())
        .overlay(Capsule().stroke(AppTheme.cardBorder, lineWidth: AppTheme.cardBorderWidth))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .offset(x: reduceMotion ? 0 : min(snapshot.offset, snapshot.available ? 48 : 18) * 0.12
                * (snapshot.direction == .back ? 1 : -1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription(snapshot))
    }

    private func action(_ snapshot: WindowGesturePresentation.HorizontalSnapshot) -> String {
        guard snapshot.available else { return L10n.text(snapshot.direction == .back ? "fullscreen.gesture.back" : "fullscreen.gesture.forward") }
        if snapshot.armed { return L10n.text(snapshot.direction == .back ? "fullscreen.gesture.releaseToBack" : "fullscreen.gesture.releaseToForward") }
        return L10n.text(snapshot.direction == .back ? "fullscreen.gesture.back" : "fullscreen.gesture.forward")
    }

    private func unavailableTitle(_ snapshot: WindowGesturePresentation.HorizontalSnapshot) -> String {
        L10n.text(snapshot.direction == .back ? "fullscreen.gesture.noPreviousPage" : "fullscreen.gesture.noNextPage")
    }

    private func accessibilityDescription(_ snapshot: WindowGesturePresentation.HorizontalSnapshot) -> String {
        snapshot.available ? "\(action(snapshot)) a \(snapshot.title)" : unavailableTitle(snapshot)
    }

    /// Excludes progress/offset so VoiceOver never receives an announcement per delta.
    private var announcement: String? {
        guard presentation.horizontalVisible, let snapshot = presentation.horizontal else { return nil }
        return accessibilityDescription(snapshot)
    }
}

/// The moving surface supplies most of the feedback; this small cue only explains
/// release/cancellation. Keep it inside the fullscreen foreground motion host.
struct FullscreenDismissGestureIndicatorView: View {
    let presentation: WindowGesturePresentation

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
            Text(L10n.text(presentation.fullscreenArmed ? "fullscreen.gesture.releaseToClose" : "fullscreen.gesture.pullDownToClose"))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(presentation.fullscreenArmed ? AppTheme.accentHighlight : Color.secondary)
        .padding(.horizontal, 11)
        .frame(height: 27)
        .compatGlass(in: Capsule())
        .overlay(Capsule().stroke(AppTheme.cardBorder, lineWidth: AppTheme.cardBorderWidth))
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text(presentation.fullscreenArmed ? "fullscreen.gesture.releaseToCloseNowPlaying" : "fullscreen.gesture.pullDownToCloseNowPlaying"))
        .accessibilityHidden(!isVisible)
        .onChange(of: announcement) { _, text in GestureAccessibility.announce(text) }
    }

    private var isVisible: Bool {
        presentation.fullscreenStage == .pulling && presentation.revealUnderlying
    }

    private var announcement: String? {
        guard isVisible else { return nil }
        return L10n.text(presentation.fullscreenArmed ? "fullscreen.gesture.releaseToCloseNowPlaying" : "fullscreen.gesture.pullDownToCloseNowPlaying")
    }
}

@MainActor
private enum GestureAccessibility {
    static func announce(_ text: String?) {
        guard let text, let app = NSApp, app.keyWindow != nil, NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
