import SwiftUI

/// Keeps the frequently changing playback clock and scrubber interaction
/// within a dedicated view subtree.
struct PlayerBarProgressView: View {
    @Bindable var viewModel: PlayerViewModel

    @State private var isHoveringScrubber = false
    @State private var isSeeking = false
    @State private var seekFraction = 0.0

    var body: some View {
        HStack(spacing: 8) {
            timeLabel(
                isSeeking && viewModel.duration > 0
                    ? viewModel.formattedTime(at: seekFraction * viewModel.duration)
                    : viewModel.formattedElapsed,
                alignment: .leading
            )
            scrubberBarSection
            timeLabel(viewModel.formattedDuration, alignment: .trailing)
        }
        .frame(height: 14)
        .padding(.horizontal, 32)
        .padding(.top, 2)
        .offset(y: 3)
    }

    private func timeLabel(_ value: String, alignment: Alignment) -> some View {
        Text(value)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.62))
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

            ZStack(alignment: .leading) {
                // Rail no transcurrido (gris translúcido ultra fino)
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: isHoveringScrubber ? 3.5 : 2.5)

                // Rail transcurrido (Acento Side B calibrado)
                Capsule()
                    .fill(Color.sidebAccentHighlight)
                    .frame(width: max(0, fillWidth), height: isHoveringScrubber ? 3.5 : 2.5)

                // Cabezal Playhead Vertical (píldora vertical de precisión)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white)
                    .frame(width: isHoveringScrubber ? 3.0 : 2.5, height: isHoveringScrubber ? 10.5 : 9.0)
                    .shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 0.5)
                    .offset(x: max(0, min(width - 2.5, fillWidth - 1.25)))
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
    }
}
