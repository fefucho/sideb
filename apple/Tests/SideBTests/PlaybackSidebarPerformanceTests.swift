import AppKit
import Foundation
import SwiftUI
import Testing
import SideBCore
@testable import SideB

private final class LyricsCountingCore: SideBCore, @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    func requests(for videoId: String) -> Int { lock.withLock { counts[videoId, default: 0] } }
    override func isLoggedIn() -> Bool { false }
    override func getSetting(key: String) -> String? { nil }
    override func getGeniusCached(track: GeniusTrackRecord) async -> GeniusResolutionRecord? { nil }
    override func getLyrics(videoId: String, title: String, artist: String, album: String?, durationSecs: UInt64?) async throws -> LyricsInfo? {
        lock.withLock { counts[videoId, default: 0] += 1 }
        return nil
    }
}

private func lyricsTrack(_ id: String) -> SongItemRecord {
    SongItemRecord(videoId: id, title: "Track \(id)", artists: "Artist", album: nil, duration: "3:00",
        thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil, isVideo: false, isUpload: false, library: nil)
}

@MainActor private func lyricsPlayer(_ core: SideBCore) -> PlayerViewModel {
    let audio = AudioPlayerService(preferences: UserDefaults(suiteName: "SidebarPerf.\(UUID())")!, preferencePrefix: "test")
    return PlayerViewModel(rustCore: core, audioService: audio,
        playbackStore: PlaybackStateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
}

@MainActor private func settleLyrics(_ player: PlayerViewModel) async {
    for _ in 0..<500 where player.isLoadingLyrics { try? await Task.sleep(for: .milliseconds(2)) }
}

@Suite(.serialized) @MainActor struct PlaybackSidebarPerformanceTests {
    @Test func emptyLyricsResultIsNotRequestedAgainWhenAPanelReappears() async {
        let core = LyricsCountingCore()
        let player = lyricsPlayer(core)
        let track = lyricsTrack("empty-lyrics")
        player.currentTrack = track

        player.loadLyricsIfNeeded(for: track)
        await settleLyrics(player)
        #expect(core.requests(for: "empty-lyrics") == 1)
        #expect(player.lyricsInfo == nil)

        // The mini preview mounts again every time the sidebar opens or its height crosses a threshold.
        for _ in 0..<5 { player.loadLyricsIfNeeded(for: track) }
        await settleLyrics(player)
        #expect(core.requests(for: "empty-lyrics") == 1)

        // A different track is still loaded, and an explicit load always retries.
        player.currentTrack = lyricsTrack("other")
        player.loadLyricsIfNeeded(for: lyricsTrack("other"))
        await settleLyrics(player)
        #expect(core.requests(for: "other") == 1)
        player.currentTrack = track
        player.loadLyrics(for: track)
        await settleLyrics(player)
        #expect(core.requests(for: "empty-lyrics") == 2)
    }

    @Test func startingANewLyricsLoadCancelsTheTaskInFlight() async {
        let core = LyricsCountingCore()
        let player = lyricsPlayer(core)
        player.currentTrack = lyricsTrack("second")
        player.loadLyrics(for: lyricsTrack("first"))
        player.loadLyrics(for: lyricsTrack("second"))
        await settleLyrics(player)
        #expect(player.lyricsInfo == nil)
        #expect(!player.isLoadingLyrics)
        #expect(core.requests(for: "second") == 1)
    }

    @Test func classicLyricsPanelIgnoresTheSeekClosureWhenDecidingToReevaluate() {
        let lyrics = LyricsInfo(provider: "Fixture", isSynced: true,
            lines: [LyricLineInfo(timeMs: 0, endTimeMs: 900, text: "uno"), LyricLineInfo(timeMs: 1000, endTimeMs: 1900, text: "dos")])
        let settings = LyricsPresentationSettings()
        let id = UUID()
        func panel(active: Int?, height: CGFloat = 300, presentation: LyricsPresentationSettings? = nil, onSeek: @escaping (Double) -> Void = { _ in }) -> SyncedLyricsPanel {
            SyncedLyricsPanel(lyrics: lyrics, activeIndex: active, duration: 10, height: height, playbackIdentity: id,
                              presentation: presentation ?? settings, onSeek: onSeek)
        }
        var seeks = 0
        #expect(panel(active: 1) == panel(active: 1, onSeek: { _ in seeks += 1 }))
        #expect(panel(active: 1) != panel(active: 0))
        #expect(panel(active: 1) != panel(active: 1, height: 301))
        #expect(panel(active: 1) != panel(active: 1, presentation: LyricsPresentationSettings()))
        #expect(seeks == 0)
    }

    @Test func scrollViewAppliesAccessibilityMaterialOnceAcrossManyScrollTicks() throws {
        let player = lyricsPlayer(LyricsCountingCore())
        let state = SidebarArtworkScrollState()
        let scroll = NativeSidebarScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 600))
        scroll.documentView = NSTableView()
        scroll.installHero(player: player, router: nil, state: state, height: 600)
        scroll.layoutHeroLayers()
        let material = try #require(scroll.subviews.compactMap { $0 as? NSVisualEffectView }.first)
        let initialState = material.state
        for offset in stride(from: 0, through: 300, by: 20) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.layoutHeroLayers()
        }
        #expect(material.state == initialState)
        #expect(material.frame.height <= 600)
        #expect(scroll.heroMetadata?.isHidden == false)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        scroll.layoutHeroLayers()
        #expect(scroll.heroMetadata?.isHidden == true)
    }
}

@Suite struct HomeResizeStabilityTests {
    @Test func featuredArtworkRequestDoesNotDependOnCardWidth() {
        let url = { (pixels: Int) in ImageURLHelper.optimizedThumbnailURL(from: "https://lh3.googleusercontent.com/abc=w544-h544", targetPixelSize: pixels) }
        // Same constant for every width: resizing can no longer mint new URLs/cache entries.
        #expect(HomeItemView.featuredArtworkPixels == 480)
        #expect(url(HomeItemView.featuredArtworkPixels) == url(HomeItemView.featuredArtworkPixels))
        #expect(HomeItemView.featuredArtworkTarget == CGSize(width: 240, height: 240))
    }
}
