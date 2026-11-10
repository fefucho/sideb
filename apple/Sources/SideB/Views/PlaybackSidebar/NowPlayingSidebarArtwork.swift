import AppKit
import SideBCore
import SwiftUI

/// Square artwork stays a card. Only a ready portrait video becomes immersive.
/// Scroll changes opacity/transport policy, never the video identity or decode clock.
public struct NowPlayingSidebarArtwork: View {
    public let viewModel: PlayerViewModel
    public let height: CGFloat
    public let tint: Color
    public let bottomTint: Color
    public let isHeroVisible: Bool
    public let scrollProgress: CGFloat
    public var onPortraitChanged: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var failedOriginalURL: URL?
    @State private var failedMaxQualityURL: URL?
    @State private var readyVideoSize: CGSize?
    @State private var videoPreview: NSImage?

    public init(viewModel: PlayerViewModel, height: CGFloat, tint: Color, bottomTint: Color? = nil,
                isHeroVisible: Bool = true, scrollProgress: CGFloat = 0, onPortraitChanged: @escaping (Bool) -> Void = { _ in }) {
        self.onPortraitChanged = onPortraitChanged
        self.viewModel = viewModel; self.height = height; self.tint = tint
        self.bottomTint = bottomTint ?? tint; self.isHeroVisible = isHeroVisible; self.scrollProgress = scrollProgress
    }
    private var track: SongItemRecord? { viewModel.currentTrack }
    private var originalURL: URL? { ImageURLHelper.originalArtworkURL(from: track?.thumbnail) }
    private var maxQualityURL: URL? { ImageURLHelper.maxQualityArtworkURL(from: track?.thumbnail, videoId: track?.videoId) }
    private var artworkURL: URL? {
        if let originalURL, failedOriginalURL != originalURL { return originalURL }
        if let maxQualityURL, failedMaxQualityURL != maxQualityURL { return maxQualityURL }
        return ImageURLHelper.fallbackThumbnailURL(from: track?.thumbnail, targetPixelSize: 760)
    }
    private var isTall: Bool { !reduceMotion && (readyVideoSize.map { $0.height > $0.width } ?? false) }
    private var isMotionVisible: Bool { !reduceMotion && isHeroVisible && scrollProgress <= 0.05 }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = SidebarArtworkLayout(width: proxy.size.width, height: height, portrait: isTall)
            ZStack(alignment: .top) {
                if isTall && !reduceTransparency {
                    blurredPortraitBackground(metrics: metrics)
                }
                // The immediate poster always stays square. It is replaced only
                // after AVPlayerLayer confirms that a video frame can be displayed.
                poster(side: metrics.cardSide)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(width: metrics.cardSide, height: metrics.cardSide)
                    .offset(y: metrics.cardTop)
                    .opacity(readyVideoSize == nil || reduceMotion ? 1 : 0)

                AnimatedArtworkView(
                    track: track, sessionID: viewModel.mediaSessionIdentity, core: viewModel.rustCore,
                    isPlaying: viewModel.isPlaying,
                    isPresented: viewModel.isPlaybackSidebarPresented,
                    isFlipped: false, audioDuration: viewModel.duration, preferTall: true,
                    suspended: !isMotionVisible || viewModel.selectedSidebarPanel != .artwork,
                    prepareWhilePaused: true,
                    surfaceStyle: .init(cornerRadius: isTall ? 0 : 12, bottomFade: isTall ? 0.32 : 0),
                    onFrameUnavailable: {
                        readyVideoSize = nil
                        videoPreview = nil
                    },
                    onFirstFrame: { readyVideoSize = $0 },
                    onPreviewResolved: { videoPreview = $0 }
                )
                .frame(width: metrics.videoWidth, height: metrics.videoHeight)
                .offset(y: metrics.videoTop)
                .opacity(readyVideoSize != nil && !reduceMotion ? 1 : 0)
            }
            .frame(width: proxy.size.width, height: max(0, height), alignment: .top)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(0, height))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(track.map { "\(L10n.text("detail.track.artwork")): \($0.title) — \($0.displayArtist)" } ?? L10n.text("player.noPlayback"))
        .accessibilityAddTraits(.isImage)
        .onChange(of: isTall, initial: true) { _, portrait in onPortraitChanged(portrait) }
        .onChange(of: track?.videoId) { _, _ in
            failedOriginalURL = nil
            failedMaxQualityURL = nil
            readyVideoSize = nil
            videoPreview = nil
        }
        .onChange(of: viewModel.mediaSessionIdentity) { _, _ in
            readyVideoSize = nil
            videoPreview = nil
        }
    }

    @ViewBuilder private func poster(side: CGFloat) -> some View {
        if let artworkURL {
            CachedAsyncImage(url: artworkURL, targetSize: CGSize(width: side, height: side), onFailure: {
                if artworkURL == originalURL { failedOriginalURL = originalURL }
                else if artworkURL == maxQualityURL { failedMaxQualityURL = maxQualityURL }
            }) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { placeholder }
        } else { placeholder }
    }
    private var placeholder: some View {
        Rectangle().fill(.white.opacity(0.04))
            .overlay { Image(systemName: "music.note").font(.system(size: 40)).foregroundStyle(.white.opacity(0.3)) }
    }
    @ViewBuilder private func blurredPortraitBackground(metrics: SidebarArtworkLayout) -> some View {
        Group {
            if let videoPreview {
                Image(nsImage: videoPreview).resizable().aspectRatio(contentMode: .fill)
            } else if let url = ImageURLHelper.optimizedThumbnailURL(from: track?.thumbnail, targetPixelSize: 96) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 96, height: 128)) {
                    $0.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }
            }
        }
        .frame(width: metrics.width, height: metrics.height)
        .scaleEffect(1.12)
        .blur(radius: 36, opaque: false)
        .overlay(tint.opacity(0.28))
        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                     .init(color: .black, location: 0.65),
                                     .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// All values are points; the shared image cache applies the backing scale.
struct SidebarArtworkLayout: Equatable {
    let width: CGFloat
    let height: CGFloat
    let portrait: Bool
    init(width: CGFloat, height: CGFloat, portrait: Bool) {
        self.width = max(0, width); self.height = max(0, height); self.portrait = portrait
    }
    var metadataWidth: CGFloat { portrait ? max(0, width - 40) : cardSide }
    var cardSide: CGFloat {
        max(0, min(width - 40, height - 58 - 12 - PlaybackSidebarLayout.metadataSpacing - PlaybackSidebarLayout.metadataHeight))
    }
    var cardTop: CGFloat {
        let blockHeight = cardSide + PlaybackSidebarLayout.metadataSpacing + PlaybackSidebarLayout.metadataHeight
        return 58 + min(12, max(0, height - 58 - blockHeight))
    }
    var metadataTop: CGFloat {
        portrait ? max(58, height - 16 - PlaybackSidebarLayout.metadataHeight)
            : cardTop + cardSide + PlaybackSidebarLayout.metadataSpacing
    }
    var videoWidth: CGFloat { portrait ? width : cardSide }
    var videoHeight: CGFloat { portrait ? height : cardSide }
    var videoTop: CGFloat { portrait ? 0 : cardTop }
}
