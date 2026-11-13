import SwiftUI

/// Keeps the frequently changing playback clock and scrubber interaction
/// within a dedicated view subtree.
struct PlayerBarProgressView: View {
    @Bindable var viewModel: PlayerViewModel
    var horizontalInset: CGFloat = 32
    var isStacked = false

    @State private var isHoveringScrubber = false
    @State private var isSeeking = false
    @State private var seekFraction = 0.0

    var body: some View {
        Group {
            if isStacked {
                VStack(spacing: 5) {
                    scrubberBarSection
                    HStack(spacing: 8) {
                        timeLabel(
                            isSeeking && viewModel.duration > 0
                                ? viewModel.formattedTime(at: seekFraction * viewModel.duration)
                                : viewModel.formattedElapsed,
                            alignment: .leading
                        )
                        Spacer(minLength: 0)
                        timeLabel(remainingText, alignment: .trailing)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    timeLabel(
                        isSeeking && viewModel.duration > 0
                            ? viewModel.formattedTime(at: seekFraction * viewModel.duration)
                            : viewModel.formattedElapsed,
                        alignment: .leading
                    )
                    scrubberBarSection
                    timeLabel(remainingText, alignment: .trailing)
                }
                .frame(height: 14)
                .padding(.horizontal, horizontalInset)
                .padding(.top, 2)
                .offset(y: 3)
            }
        }
    }

    /// Remaining time as "-0:38" (Apple Music style); follows the scrub position while dragging.
    private var remainingText: String {
        guard viewModel.duration.isFinite, viewModel.duration > 0 else { return viewModel.formattedDuration }
        guard isSeeking else { return viewModel.formattedRemaining }
        return "-" + viewModel.formattedTime(at: max(0, viewModel.duration * (1 - seekFraction)))
    }

    private func timeLabel(_ value: String, alignment: Alignment) -> some View {
        Text(value)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(isStacked ? 0.85 : 0.62))
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 40, alignment: alignment)
            .accessibilityLabel(value)
    }

    private var scrubberBarSection: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let activeFraction = isSeeking ? seekFraction : viewModel.progressFraction
            let clampedFraction = max(0.0, min(1.0, activeFraction))
            let fillWidth = width * clampedFraction

            let thickness: CGFloat = isHoveringScrubber || isSeeking ? 7 : 5

            ZStack(alignment: .leading) {
                // Pista completa atenuada, extremos redondeados.
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: thickness)

                // Parte transcurrida con el acento de Side B (sin thumb visible).
                Capsule()
                    .fill(Color.sidebAccentHighlight)
                    .frame(width: max(0, fillWidth), height: thickness)
            }
            .frame(height: proxy.size.height, alignment: .center)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHoveringScrubber = hovering
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isSeeking = true
                        seekFraction = max(0.0, min(1.0, value.location.x / max(1, width)))
                    }
                    .onEnded { value in
                        let fraction = max(0.0, min(1.0, value.location.x / max(1, width)))
                        viewModel.seek(toFraction: fraction)
                        isSeeking = false
                    }
            )
        }
        .frame(height: 14)
        .allowsHitTesting(viewModel.duration.isFinite && viewModel.duration > 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("playbackSidebar.position"))
        .accessibilityValue(viewModel.formattedElapsed + " / " + viewModel.formattedDuration)
        .accessibilityAdjustableAction { direction in
            guard viewModel.duration.isFinite, viewModel.duration > 0 else { return }
            let delta = direction == .increment ? 5.0 : -5.0
            viewModel.seek(toFraction: min(1, max(0, (viewModel.currentTime + delta) / viewModel.duration)))
        }
    }
}
