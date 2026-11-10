import AppKit
import SideBCore
import SwiftUI
import Testing
@testable import SideB

@Suite("NowPlayingSidebarArtwork Tests")
struct NowPlayingSidebarArtworkTests {

    @Test("Square poster stays inside the body below the header at every window height")
    func squarePosterFitsBodyWithoutCroppingOrStretching() {
        for width: CGFloat in [350, 380, 420] {
            for height: CGFloat in [260, 380, 600] {
                let layout = SidebarArtworkLayout(width: width, height: height, portrait: false)
                #expect(layout.cardSide <= width - 40)
                #expect(layout.cardTop >= 58)
                #expect(layout.cardTop <= 70)
                #expect(layout.cardTop + layout.cardSide <= height)
                #expect(layout.metadataTop - (layout.cardTop + layout.cardSide) == 16)
                #expect(layout.metadataTop + PlaybackSidebarLayout.metadataHeight <= height)
                #expect(layout.metadataWidth == layout.cardSide)
                #expect(layout.videoWidth == layout.cardSide && layout.videoHeight == layout.cardSide)
            }
        }
    }
    @Test("Ready portrait occupies the whole hero from its top; poster remains square")
    func portraitUsesAvailableViewport() {
        let layout = SidebarArtworkLayout(width: 380, height: 600, portrait: true)
        #expect(layout.videoTop == 0)
        #expect(layout.videoWidth == 380 && layout.videoHeight == 600)
        #expect(layout.cardSide == 340)
    }

    @Test("ImageURLHelper provides 300px thumbnail for static blur layer and 96px for compact thumbnails")
    func blurURLGeneration() {
        let googleCdnUrl = "https://lh3.googleusercontent.com/sample_hash=w544-h544"
        let blur300Url = ImageURLHelper.optimizedThumbnailURL(from: googleCdnUrl, targetPixelSize: 300)
        #expect(blur300Url?.absoluteString.contains("=w300-h300") == true)

        let blur96Url = ImageURLHelper.optimizedThumbnailURL(from: googleCdnUrl, targetPixelSize: 96)
        #expect(blur96Url?.absoluteString.contains("=w96-h96") == true)

        let maxQualityUrl = ImageURLHelper.maxQualityArtworkURL(from: googleCdnUrl)
        #expect(maxQualityUrl?.absoluteString.contains("=w1200-h1200") == true)
    }

    @MainActor
    private func makeTestPlayer(suite: String) throws -> (PlayerViewModel, URL, UserDefaults) {
        let prefs = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let player = PlayerViewModel(
            rustCore: nil,
            audioService: AudioPlayerService(preferences: prefs, preferencePrefix: "sidebar_hero_test"),
            playbackStore: PlaybackStateStore(directory: directory)
        )
        return (player, directory, prefs)
    }

    @Test @MainActor
    func heroArtworkInstantiatesAndRendersFallbackWithoutTrack() throws {
        let suite = "NowPlayingSidebarHero.\(UUID())"
        let (player, directory, prefs) = try makeTestPlayer(suite: suite)
        defer {
            prefs.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        #expect(player.currentTrack == nil)
        let hero = NowPlayingSidebarArtwork(viewModel: player, height: 500, tint: .blue)
        let host = NSHostingView(rootView: hero.frame(width: 380, height: 500))
        host.frame = CGRect(x: 0, y: 0, width: 380, height: 500)
        host.layoutSubtreeIfNeeded()

        #expect(host.fittingSize.width <= 381)
        #expect(host.fittingSize.height <= 501)
    }

    @Test @MainActor
    func heroArtworkConformsToAgreedAPIAndOccupiesSuppliedHeight() throws {
        let suite = "NowPlayingSidebarHeroTrack.\(UUID())"
        let (player, directory, prefs) = try makeTestPlayer(suite: suite)
        defer {
            prefs.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        let track = SongItemRecord(
            videoId: "hero-track-123",
            title: "Test Track",
            artists: "Test Artist",
            album: "Test Album",
            duration: "3:45",
            thumbnail: "https://lh3.googleusercontent.com/test=w544-h544",
            artistId: "artist-1",
            albumId: "album-1",
            setVideoId: nil
        )
        player.currentTrack = track
        player.togglePlaybackSidebar(.artwork)

        let testHeight: CGFloat = 460
        let hero = NowPlayingSidebarArtwork(viewModel: player, height: testHeight, tint: .purple)
        let host = NSHostingView(rootView: hero.frame(width: 380, height: testHeight))
        host.frame = CGRect(x: 0, y: 0, width: 380, height: testHeight)
        host.layoutSubtreeIfNeeded()

        #expect(hero.height == testHeight)
        #expect(hero.tint == .purple)
        #expect(hero.bottomTint == .purple)
        #expect(hero.isHeroVisible == true)
        #expect(hero.scrollProgress == 0)
        #expect(host.frame.height == testHeight)
    }

    @Test @MainActor
    func heroArtworkAcceptsBottomTintAndProgressiveParameters() throws {
        let suite = "NowPlayingSidebarHeroParams.\(UUID())"
        let (player, directory, prefs) = try makeTestPlayer(suite: suite)
        defer {
            prefs.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        let hero = NowPlayingSidebarArtwork(
            viewModel: player,
            height: 480,
            tint: .blue,
            bottomTint: .indigo,
            isHeroVisible: false,
            scrollProgress: 0.75
        )
        #expect(hero.height == 480)
        #expect(hero.tint == .blue)
        #expect(hero.bottomTint == .indigo)
        #expect(hero.isHeroVisible == false)
        #expect(hero.scrollProgress == 0.75)
    }

    @Test @MainActor
    func sidebarArtworkScrollStateQuantizesProgressAndTogglesHeroVisibility() {
        let state = SidebarArtworkScrollState()
        let session = UUID()
        let playback = UUID()
        let occurrence = SidebarArtworkOccurrenceKey(
            sessionID: session,
            playbackID: playback,
            videoID: "v-1",
            occurrenceID: "o-1"
        )
        let recKey = RecommendedRequestState.Key(videoID: "v-1", artistID: "a-1", albumID: nil, account: session)
        state.synchronizeOccurrence(occurrence)

        #expect(state.quantizedProgress == 0)
        #expect(state.isHeroVisible == true)

        let upperHeight: CGFloat = 500

        // At y = 0
        state.evaluateScroll(offsetY: 0, hasTrack: true, recommendationKey: recKey, upperHeight: upperHeight) {}
        #expect(state.quantizedProgress == 0.0)
        #expect(state.isHeroVisible == true)

        // Sub-step scroll (4pt on 500 = 0.008, rounds to 0.00)
        state.evaluateScroll(offsetY: 4, hasTrack: true, recommendationKey: recKey, upperHeight: upperHeight) {}
        #expect(state.quantizedProgress == 0.0)

        // 10pt on 500 = 0.02
        state.evaluateScroll(offsetY: 10, hasTrack: true, recommendationKey: recKey, upperHeight: upperHeight) {}
        #expect(abs(state.quantizedProgress - 0.02) < 0.001)
        #expect(state.isHeroVisible == true)

        // Halfway (250pt on 500 = 0.50)
        state.evaluateScroll(offsetY: 250, hasTrack: true, recommendationKey: recKey, upperHeight: upperHeight) {}
        #expect(abs(state.quantizedProgress - 0.50) < 0.001)
        #expect(!state.isHeroMotionActive, "Video pauses under the compositor material without fading the hero")
        #expect(state.isHeroVisible == true)

        // 485pt on 500 = 0.97 (progress < 0.98 -> hero visible)
        state.evaluateScroll(offsetY: 485, hasTrack: true, recommendationKey: recKey, upperHeight: upperHeight) {}
        #expect(state.isHeroVisible == true)

        // Remain visible until the advancing feed fully covers the hero.
        state.evaluateScroll(offsetY: 495, hasTrack: true, recommendationKey: recKey, upperHeight: upperHeight) {}
        #expect(state.isHeroVisible == true)
        state.evaluateScroll(offsetY: 500, hasTrack: true, recommendationKey: recKey, upperHeight: upperHeight) {}
        #expect(state.isHeroVisible == false)

        // Beyond upperHeight (750pt on 500 -> clamped progress 1.0, hero hidden)
        state.evaluateScroll(offsetY: 750, hasTrack: true, recommendationKey: recKey, upperHeight: upperHeight) {}
        #expect(abs(state.quantizedProgress - 1.0) < 0.001)
        #expect(state.isHeroVisible == false)

        // Reset occurrence restores progress to 0 and hero visibility to true
        let occurrence2 = SidebarArtworkOccurrenceKey(
            sessionID: session,
            playbackID: playback,
            videoID: "v-2",
            occurrenceID: "o-2"
        )
        state.synchronizeOccurrence(occurrence2)
        #expect(state.quantizedProgress == 0)
        #expect(state.isHeroVisible == true)
        #expect(state.isHeroMotionActive)
    }

    @Test @MainActor
    func sidebarPanelSwitchBetweenArtworkAndLyricsPreservesSidebarPresentation() throws {
        let suite = "NowPlayingSidebarPanelSwitch.\(UUID())"
        let (player, directory, prefs) = try makeTestPlayer(suite: suite)
        defer {
            prefs.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        let track = SongItemRecord(
            videoId: "switch-test-1",
            title: "Switch Title",
            artists: "Switch Artist",
            album: "Switch Album",
            duration: "3:00",
            thumbnail: "https://lh3.googleusercontent.com/switch=w544-h544",
            artistId: "artist-switch",
            albumId: "album-switch",
            setVideoId: nil
        )
        player.currentTrack = track
        player.togglePlaybackSidebar(.artwork)

        #expect(player.isPlaybackSidebarPresented)
        #expect(player.selectedSidebarPanel == .artwork)

        // Switching to lyrics keeps sidebar presentation open
        player.selectedSidebarPanel = .lyrics
        #expect(player.isPlaybackSidebarPresented)
        #expect(player.selectedSidebarPanel == .lyrics)

        // Switching back to artwork keeps the same presentation identity
        player.selectedSidebarPanel = .artwork
        #expect(player.isPlaybackSidebarPresented)
        #expect(player.selectedSidebarPanel == .artwork)
        #expect(player.currentTrack?.videoId == "switch-test-1")
    }
}
