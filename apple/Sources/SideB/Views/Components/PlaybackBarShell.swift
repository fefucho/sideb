import SwiftUI

/// Symmetric space keeps the bar centered in the content column while the
/// independent trigger stays anchored to the window's trailing margin.
struct PlaybackBarShellLayout {
    static func showsBar(in mode: PlaybackPresentation) -> Bool { mode != .sidebar }
    static let buttonSize: CGFloat = 44
    static let margin: CGFloat = 20
    static let gap: CGFloat = 16
    static func barWidth(contentWidth: CGFloat) -> CGFloat {
        max(0, min(820, contentWidth - 2 * (margin + buttonSize + gap)))
    }
}

struct PlaybackBarShell<Content: View>: View {
    @Bindable var viewModel: PlayerViewModel
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var triggerFocused: Bool
    @State private var barInteractive = true
    @State private var restoreTriggerFocus = false

    private var visible: Bool { PlaybackBarShellLayout.showsBar(in: viewModel.playbackPresentation.mode) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                content()
                    .frame(width: PlaybackBarShellLayout.barWidth(contentWidth: proxy.size.width))
                    .windowGestureRegion(.excluded, active: visible)
                    .padding(.bottom, 20)
                Button { viewModel.togglePlaybackSidebar() } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .compatGlass(interactive: true, in: Circle())
                .focused($triggerFocused)
                .help(L10n.text("playbackSidebar.open"))
                .accessibilityLabel(L10n.text("playbackSidebar.open"))
                .windowGestureRegion(.excluded, active: visible)
                .padding(.trailing, 20)
                .padding(.bottom, 35)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            .offset(y: visible || reduceMotion ? 0 : 12)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.12).delay(visible ? 0.18 : 0), value: visible)
            .allowsHitTesting(visible && barInteractive)
            .accessibilityHidden(!visible || !barInteractive)
        }
        .onChange(of: viewModel.playbackPresentation.mode) { old, new in
            restoreTriggerFocus = old == .sidebar && new == .bar
            if new != .bar { triggerFocused = false }
        }
        .task(id: visible) {
            guard visible else { barInteractive = false; return }
            if restoreTriggerFocus {
                restoreTriggerFocus = false
                triggerFocused = true
            }
            if !reduceMotion {
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
            barInteractive = true
        }
    }
}
