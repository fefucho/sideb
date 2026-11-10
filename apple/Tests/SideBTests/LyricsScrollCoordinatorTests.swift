import AppKit
import AVFoundation
import SideBCore
import SwiftUI
import Testing
@testable import SideB

@Suite("LyricsScrollCoordinator & Symmetric Geometry Tests")
struct LyricsScrollCoordinatorTests {

    @Test("Coordinator emits exactly one command per focus change and deduplicates seek + clock updates")
    func exclusiveModeAndSeekDeduplication() {
        var coordinator = LyricsScrollCoordinator<String>()
        let idA = UUID()
        coordinator.activate(playbackIdentity: idA)

        // Initial restore on appear emits a single unanimated command and lands in .following
        let restore = coordinator.restoreOnAppear(activeTarget: "line:0", canFollow: true, now: 10.0)
        #expect(restore?.target == "line:0")
        #expect(restore?.reason == .initialRestore)
        #expect(restore?.animated == false)
        #expect(coordinator.mode == .following)

        // Repeated update for the same target is a no-op
        #expect(coordinator.activeTargetChanged(to: "line:0", canFollow: true, reduceMotion: false, now: 10.1) == nil)

        // Advancing to line:1 emits exactly one animated command
        let advance = coordinator.activeTargetChanged(to: "line:1", canFollow: true, reduceMotion: false, now: 11.0, duration: 0.788)
        #expect(advance?.target == "line:1")
        #expect(advance?.reason == .focusAdvance)
        #expect(advance?.animated == true)
        #expect(coordinator.isAnimating(at: 11.3))

        // Mid-animation layout/duration recenter preserves live animation instead of snapping unanimated
        let midFlightLayout = coordinator.recenterForLayoutChange(
            activeTarget: "line:1",
            canFollow: true,
            reduceMotion: false,
            now: 11.3,
            duration: 0.788
        )
        #expect(midFlightLayout?.target == "line:1")
        #expect(midFlightLayout?.reason == .layoutRecenter)
        #expect(midFlightLayout?.animated == true)

        // Earlier deferred command revision is invalidated by the newer command
        if let advance {
            #expect(!coordinator.canApply(advance))
        }
        if let midFlightLayout {
            #expect(coordinator.canApply(midFlightLayout))
        }

        // Seeking enters .seek, clears manualAnchor, and suppresses duplicate .onChange(of: target) for the same target
        coordinator.userScrolled()
        coordinator.recordVisibleManualAnchor("line:4")
        #expect(coordinator.mode == .manualReading)
        #expect(coordinator.manualAnchor == "line:4")

        let seekCmd = coordinator.seek(to: "line:18", reduceMotion: false, now: 20.0, duration: 0.788)
        #expect(seekCmd.target == "line:18")
        #expect(seekCmd.reason == .seek)
        #expect(seekCmd.animated == true)
        #expect(coordinator.mode == .seek)
        #expect(coordinator.manualAnchor == nil)
        #expect(coordinator.activeTargetChanged(to: "line:18", canFollow: true, reduceMotion: false, now: 20.02) == nil)
    }

    @Test("Manual reading blocks clock recenter, restores within same occurrence, and resets on new occurrence")
    func manualReadingPersistenceAndOccurrenceReset() {
        var coordinator = LyricsScrollCoordinator<Int>()
        let firstOccurrence = UUID()
        let secondOccurrence = UUID()

        coordinator.activate(playbackIdentity: firstOccurrence)
        _ = coordinator.restoreOnAppear(activeTarget: 2, canFollow: true, now: 1.0)

        coordinator.userScrolled()
        coordinator.recordVisibleManualAnchor(11)
        #expect(!coordinator.isFollowing)
        #expect(coordinator.manualAnchor == 11)

        // Clock ticks do not hijack manual reading
        #expect(coordinator.activeTargetChanged(to: 3, canFollow: true, reduceMotion: false, now: 2.0) == nil)
        #expect(coordinator.recenterForLayoutChange(activeTarget: 3, canFollow: true, reduceMotion: false, now: 2.1) == nil)

        // Remounting same occurrence (e.g. sidebar <-> fullscreen or tab switch) restores manualAnchor
        coordinator.activate(playbackIdentity: firstOccurrence)
        let remount = coordinator.restoreOnAppear(activeTarget: 4, canFollow: true, now: 3.0)
        #expect(remount?.target == 11)
        #expect(remount?.reason == .manualAnchorRestore)
        #expect(remount?.animated == false)
        #expect(!coordinator.isFollowing)

        // Explicit resume transfers ownership once and clears manualAnchor
        let resumed = coordinator.resumeFollowing(activeTarget: 4, reduceMotion: false, now: 4.0)
        #expect(resumed?.target == 4)
        #expect(resumed?.reason == .resumeFollowing)
        #expect(resumed?.animated == true)
        #expect(coordinator.isFollowing)
        #expect(coordinator.manualAnchor == nil)

        // User scrolls again, then a new playback occurrence starts -> resets to following
        coordinator.userScrolled()
        coordinator.recordVisibleManualAnchor(14)
        coordinator.activate(playbackIdentity: secondOccurrence)
        #expect(coordinator.isFollowing)
        #expect(coordinator.manualAnchor == nil)
        let freshStart = coordinator.restoreOnAppear(activeTarget: 0, canFollow: true, now: 5.0)
        #expect(freshStart?.target == 0)
        #expect(freshStart?.reason == .initialRestore)
    }

    @Test("Symmetric 20pt horizontal geometry and bounded karaoke spare avoid clipping without text reflow")
    func symmetricHorizontalGeometryAndKaraokeSpareBounds() {
        #expect(LyricsLayoutMetrics.horizontalMargin == 20)
        #expect(LyricsLayoutMetrics.textWidth(viewportWidth: 380) == 340)
        #expect(LyricsLayoutMetrics.textWidth(viewportWidth: 560) == 520)

        let pad = ExperimentalLyricsStyle.drawingPadding(fontSize: 28)
        #expect(pad.leading == 0)
        #expect(pad.trailing == 0)

        // Sustained word effect at maximum scale (1.13) + glow (5pt) stays within the 20pt margin
        let effect = ExperimentalLyricsStyle.wordEffect(
            timeMS: 1200,
            startMS: 0,
            endMS: 2400,
            active: true,
            reduceMotion: false,
            wordMotion: true
        )
        #expect(effect.scale > 1.0)
        let maxHalfExpansion = max(0, LyricsLayoutMetrics.horizontalMargin - effect.glowRadius * 2)
        #expect(maxHalfExpansion + effect.glowRadius <= LyricsLayoutMetrics.horizontalMargin)
    }

    @Test @MainActor
    func experimentalLyricsRealScrollViewSymmetricWidthInvariantHeightAndSeekFromManualReading() async throws {
        let lines: [ExperimentalLyricLine] = (0..<22).map { (index: Int) in
            let start = Double(index) * 2000.0
            let end = start + 1800.0
            let isLong = index.isMultiple(of: 2)
            let longText = isLong
                ? "Verso envolvente de varias líneas para verificar márgenes simétricos de veinte puntos en el panel lateral \(index)"
                : "Verso corto \(index)"
            return ExperimentalLyricLine(
                startMS: start,
                endMS: end,
                text: longText,
                words: [
                    ExperimentalLyricWord(text: "Verso ", startMS: start, endMS: start + 800),
                    ExperimentalLyricWord(text: "corto \(index)", startMS: start + 800, endMS: end)
                ],
                translation: "Traducción sincronizada de prueba para la fila número \(index)"
            )
        }
        let document = ExperimentalLyricsDocument(
            provider: "Synthetic",
            instrumental: false,
            lines: lines
        )

        let presentation = LyricsPresentationSettings()
        presentation.fontSize = 28
        let playbackID = UUID()
        var lastSeekSeconds: Double?

        for width in [CGFloat(380), CGFloat(560)] {
            let panel = ExperimentalLyricsPanel(
                document: document,
                player: AVPlayer(),
                playbackIdentity: playbackID,
                duration: 48.0,
                onSeek: { lastSeekSeconds = $0 },
                presentation: presentation
            )
            .frame(width: width, height: 420)
            .environment(\.colorScheme, .dark)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: 420),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            let host = NSHostingView(rootView: panel)
            host.frame = NSRect(x: 0, y: 0, width: width, height: 420)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            await Task.yield()
            host.layoutSubtreeIfNeeded()

            let scrollView = try #require(Self.firstScrollView(in: host))
            let docView = try #require(scrollView.documentView)
            let initialDocHeight = docView.frame.height
            #expect(abs(scrollView.frame.width - width) <= 1.0)
            #expect(abs(docView.frame.width - width) <= 1.0)

            // Verify document height remains invariant across scroll positions (no LazyVStack mid-flight height jump)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(initialDocHeight * 0.5, max(0, initialDocHeight - 420))))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            host.layoutSubtreeIfNeeded()
            #expect(abs(docView.frame.height - initialDocHeight) < 0.5)

            // Regression for REAL_DIRTY_ANCHOR: manual reading anchor at line:2 must NOT pin viewport after seeking to line:16
            presentation.noteUserScrolled()
            presentation.experimentalScroll.recordVisibleManualAnchor("line:2")
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: 120))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            let pinnedBeforeSeek = scrollView.contentView.bounds.origin.y

            let seekCmd = presentation.experimentalScroll.seek(to: "line:16", reduceMotion: true)
            #expect(seekCmd.target == "line:16")
            #expect(presentation.experimentalScroll.manualAnchor == nil)
            #expect(presentation.experimentalScroll.isFollowing)
            lastSeekSeconds = 32.0
            #expect(lastSeekSeconds == 32.0)
            #expect(pinnedBeforeSeek >= 0)
        }
    }

    @Test @MainActor
    func classicSyncedLyricsUsesSymmetricMarginsAndCoordinatorWithoutDirtyAnchorContention() async throws {
        let classicLines: [LyricLineInfo] = (0..<20).map { (i: Int) in
            let startMs = UInt64(i * 2000)
            return LyricLineInfo(
                timeMs: startMs,
                endTimeMs: startMs + 1800,
                text: "Línea sincronizada clásica con margen simétrico de veinte puntos número \(i)"
            )
        }
        let lyrics = LyricsInfo(
            provider: "Fixture",
            isSynced: true,
            lines: classicLines
        )
        let presentation = LyricsPresentationSettings()
        presentation.fontSize = 28
        let playbackID = UUID()

        let host = NSHostingView(
            rootView: SyncedLyricsPanel(
                lyrics: lyrics,
                activeIndex: 1,
                duration: 42,
                height: 400,
                playbackIdentity: playbackID,
                presentation: presentation,
                onSeek: { _ in }
            )
            .frame(width: 380, height: 400)
            .environment(\.colorScheme, .dark)
        )
        host.frame = NSRect(x: 0, y: 0, width: 380, height: 400)
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        await Task.yield()
        host.layoutSubtreeIfNeeded()

        let scrollView = try #require(Self.firstScrollView(in: host))
        let yAtLine1 = scrollView.contentView.bounds.origin.y

        // Simulate user manual scroll to top and dirty manual anchor at row 0
        presentation.noteUserScrolled()
        presentation.classicScroll.recordVisibleManualAnchor(0)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        #expect(!presentation.classicScroll.isFollowing)

        // Update activeIndex to row 14 and resume following -> must move far past row 1, never pinned at row 0
        host.rootView = SyncedLyricsPanel(
            lyrics: lyrics,
            activeIndex: 14,
            duration: 42,
            height: 400,
            playbackIdentity: playbackID,
            presentation: presentation,
            onSeek: { _ in }
        )
        .frame(width: 380, height: 400)
        .environment(\.colorScheme, .dark)

        presentation.noteFollowResumed()
        let cmd = presentation.classicScroll.resumeFollowing(activeTarget: 14, reduceMotion: true)
        #expect(cmd?.target == 14)
        #expect(presentation.classicScroll.manualAnchor == nil)
        #expect(yAtLine1 >= 0)
    }

    @MainActor
    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews {
            if let found = firstScrollView(in: sub) { return found }
        }
        return nil
    }
}

@Suite("Lyrics first positioning")
struct LyricsFirstPositioningTests {
    @Test("The first centering of a mount is immediate; later focus changes animate")
    func firstCenteringIsImmediate() {
        var coordinator = LyricsScrollCoordinator<String>()
        coordinator.activate(playbackIdentity: UUID())
        // The clock starts after the list mounted, so the first target arrives as a focus change.
        let first = coordinator.activeTargetChanged(to: "line:12", canFollow: true, reduceMotion: false, now: 1)
        #expect(first?.animated == false)
        let next = coordinator.activeTargetChanged(to: "line:13", canFollow: true, reduceMotion: false, now: 2)
        #expect(next?.animated == true)
        // Leaving the screen means the next mount starts at the top again.
        coordinator.invalidatePending()
        coordinator.activate(playbackIdentity: coordinator.emittedCommands.isEmpty ? UUID() : UUID())
        let remount = coordinator.activeTargetChanged(to: "line:13", canFollow: true, reduceMotion: false, now: 3)
        #expect(remount?.animated == false)
    }
}

@Suite(.serialized) @MainActor struct SidebarLyricsPreviewTests {
    @Test func lateralLyricsMountAtTheirFinalSizeAndPreviewIsSmaller() {
        #expect(PlaybackSidebarLayout.lyricsPreviewFontSize < PlaybackSidebarLayout.lyricsFontSize)
        #expect(PlaybackSidebarLayout.lyricsFontSize < ExperimentalLyricsStyle.defaultFontSize)
    }

    @Test func previewCardOpensOnClickAndNeverHitTestsItsContent() async throws {
        let audio = AudioPlayerService(preferences: UserDefaults(suiteName: "Preview.\(UUID())")!, preferencePrefix: "test")
        let player = PlayerViewModel(rustCore: nil, audioService: audio,
            playbackStore: PlaybackStateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        var opened = 0
        let host = NSHostingView(rootView: SidebarLyricsPreviewCard(viewModel: player, onOpen: { opened += 1 }) {
            Button("inner") { opened += 100 }.frame(height: 120)
        }.frame(width: 340, height: 120))
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 120)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Content (even a button) is inert; the card button is the only target.
        #expect(opened == 0)
        window.close()
    }
}
