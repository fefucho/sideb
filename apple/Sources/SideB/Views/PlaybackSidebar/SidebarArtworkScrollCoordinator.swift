import AppKit
import SwiftUI

// MARK: - Sidebar Artwork + Recommendations Scroll Coordination

struct SidebarArtworkOccurrenceKey: Equatable {
    let sessionID: UUID
    let playbackID: UUID
    let videoID: String?
    let occurrenceID: String?
}

enum SidebarRecommendationScrollPolicy {
    /// Downward scroll threshold past the initial hero position required before
    /// fetching recommendations—never triggers at `offsetY == 0` on open, nor per pixel.
    static let activationOffset: CGFloat = 24
    static let contentActivationProgress: CGFloat = 0.35

    static func shouldTriggerFetch(
        offsetY: CGFloat,
        hasTrack: Bool,
        recommendationKey: RecommendedRequestState.Key?,
        lastRequestedKey: RecommendedRequestState.Key?
    ) -> Bool {
        guard hasTrack, offsetY >= activationOffset, let recommendationKey else { return false }
        return lastRequestedKey != recommendationKey
    }

    static func shouldActivateContent(
        offsetY: CGFloat,
        upperHeight: CGFloat
    ) -> Bool {
        let safeUpper = max(1.0, upperHeight)
        let progress = offsetY / safeUpper
        let thresholdOffset = max(0.0, safeUpper - 400.0)
        return offsetY >= activationOffset && (progress >= contentActivationProgress || offsetY >= thresholdOffset)
    }
}

@MainActor
@Observable
final class SidebarArtworkScrollState {
    @ObservationIgnored private(set) var occurrenceKey: SidebarArtworkOccurrenceKey?
    @ObservationIgnored var savedOffsetY: CGFloat = 0
    @ObservationIgnored var lastRequestedRecommendationKey: RecommendedRequestState.Key?

    var isPortrait = false
    @ObservationIgnored var quantizedProgress: CGFloat = 0
    var isHeroMotionActive = true
    var isHeroVisible: Bool = true
    var isRecommendationsActive: Bool = false

    @discardableResult
    func synchronizeOccurrence(_ key: SidebarArtworkOccurrenceKey) -> Bool {
        guard occurrenceKey != key else { return false }
        occurrenceKey = key
        savedOffsetY = 0
        lastRequestedRecommendationKey = nil
        quantizedProgress = 0
        isHeroVisible = true
        isHeroMotionActive = true
        isRecommendationsActive = false
        return true
    }

    func evaluateScroll(
        offsetY: CGFloat,
        hasTrack: Bool,
        recommendationKey: RecommendedRequestState.Key?,
        upperHeight: CGFloat = 500,
        onLoad: () -> Void
    ) {
        let clamped = max(0, offsetY)
        savedOffsetY = clamped

        let safeUpper = max(1.0, upperHeight)
        let rawProgress = min(max(clamped / safeUpper, 0.0), 1.0)
        let newQuantized = min(1.0, max(0.0, (rawProgress * 50.0).rounded() / 50.0))
        let newHeroVisible = clamped < safeUpper
        let motionActive = rawProgress <= 0.05
        if isHeroMotionActive != motionActive { isHeroMotionActive = motionActive }
        let shouldActivate = isRecommendationsActive || SidebarRecommendationScrollPolicy.shouldActivateContent(
            offsetY: clamped,
            upperHeight: safeUpper
        )

        if abs(newQuantized - quantizedProgress) > 0.001 {
            quantizedProgress = newQuantized
        }
        if newHeroVisible != isHeroVisible {
            isHeroVisible = newHeroVisible
        }
        if shouldActivate != isRecommendationsActive {
            isRecommendationsActive = shouldActivate
        }

        if SidebarRecommendationScrollPolicy.shouldTriggerFetch(
            offsetY: clamped,
            hasTrack: hasTrack,
            recommendationKey: recommendationKey,
            lastRequestedKey: lastRequestedRecommendationKey
        ) {
            lastRequestedRecommendationKey = recommendationKey
            onLoad()
        }
    }
}

struct NowPlayingSidebarArtworkHost: View {
    let viewModel: PlayerViewModel
    let state: SidebarArtworkScrollState
    let width: CGFloat
    let height: CGFloat
    let tint: Color
    let bottomTint: Color

    var body: some View {
        NowPlayingSidebarArtwork(
            viewModel: viewModel,
            height: height,
            tint: tint,
            bottomTint: bottomTint,
            isHeroVisible: state.isHeroVisible,
            scrollProgress: state.isHeroMotionActive ? 0 : 1,
            onPortraitChanged: { state.isPortrait = $0 }
        )
        .frame(width: width, height: height)
        .clipped()
    }
}
