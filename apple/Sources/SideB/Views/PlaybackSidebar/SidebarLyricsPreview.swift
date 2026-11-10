import SwiftUI

/// Tappable frame around a small copy of the real lyrics renderer. The content is purely
/// visual (no hit testing, no controls); the whole card opens the full Lyrics tab.
struct SidebarLyricsPreviewCard<Content: View>: View {
    let viewModel: PlayerViewModel
    let onOpen: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(isHovered ? 0.20 : 0.08), lineWidth: 0.8)
                    )
                content()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if isHovered {
                    Text(L10n.text("playbackSidebar.lyricsPreview.showMore"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white))
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                        .padding(10)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { isHovered = hovering }
        }
        // The track normally loads its lyrics when playback starts; this only covers a
        // restored, never-played track and never repeats a finished request.
        .task(id: viewModel.currentTrack?.videoId) {
            if let track = viewModel.currentTrack { viewModel.loadLyricsIfNeeded(for: track) }
        }
        .accessibilityLabel(L10n.text("playbackSidebar.lyricsPreview.openLyrics"))
    }
}

struct SidebarLyricsPreviewStatus: View {
    let loading: Bool
    let hasTrack: Bool

    var body: some View {
        HStack(spacing: 8) {
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "quote.bubble").font(.system(size: 14)).foregroundStyle(.white.opacity(0.40))
            }
            Text(L10n.text(loading ? "playbackSidebar.lyricsPreview.searching"
                           : hasTrack ? "playbackSidebar.lyricsPreview.noLyrics" : "lyrics.experimental.noTrack"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
