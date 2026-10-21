import AppKit
import SwiftUI
import Testing
@testable import SideB

@Suite("Letras experimentales: estilo y barrido continuo")
struct ExperimentalLyricsStyleTests {
    @Test("Context remains legible and accessibility settings suppress visual motion")
    func accessibleContext() {
        #expect(ExperimentalLyricsStyle.defaultFontSize == 36)
        #expect(ExperimentalLyricsStyle.targetLineHeight(fontSize: 36) == 45)
        #expect(ExperimentalLyricsStyle.contextBlur(distance: 0, increasedContrast: false, reduceMotion: false) == 0)
        #expect(ExperimentalLyricsStyle.contextBlur(distance: 1, increasedContrast: false, reduceMotion: false) == 1.2)
        #expect(ExperimentalLyricsStyle.contextBlur(distance: 2, increasedContrast: false, reduceMotion: false) == 2.1)
        #expect(ExperimentalLyricsStyle.contextBlur(distance: 99, increasedContrast: false, reduceMotion: false) == 3)
        #expect(ExperimentalLyricsStyle.visualDistance(-4) == 0)
        #expect(ExperimentalLyricsStyle.visualDistance(0) == 0)
        #expect(ExperimentalLyricsStyle.visualDistance(1) == 1)
        #expect(ExperimentalLyricsStyle.visualDistance(2) == 2)
        #expect(ExperimentalLyricsStyle.visualDistance(3) == 3)
        #expect(ExperimentalLyricsStyle.visualDistance(20) == 3)
        #expect(ExperimentalLyricsStyle.contextBlur(distance: 3, increasedContrast: true, reduceMotion: false) == 0)
        #expect(ExperimentalLyricsStyle.contextBlur(distance: 3, increasedContrast: false, reduceMotion: true) == 0)
        #expect(ExperimentalLyricsStyle.contextScale(reduceMotion: true) == 1)
        #expect(ExperimentalLyricsStyle.contextOpacity(increasedContrast: true) > ExperimentalLyricsStyle.contextOpacity(increasedContrast: false))
        #expect(ExperimentalLyricsStyle.activeBaseOpacity(increasedContrast: true) > ExperimentalLyricsStyle.activeBaseOpacity(increasedContrast: false))
    }

    @Test("Manual browsing removes every context blur and return restores the follow effect")
    func manualBrowsingBlur() {
        var follow = ExperimentalLyricsFollowState()
        for distance in [1, 2, 3, 99] {
            #expect(ExperimentalLyricsStyle.contextBlur(distance: distance, increasedContrast: false,
                reduceMotion: false, isFollowing: follow.isFollowing) > 0)
        }
        follow.userScrolled()
        for distance in [0, 1, 2, 3, 99] {
            #expect(ExperimentalLyricsStyle.contextBlur(distance: distance, increasedContrast: false,
                reduceMotion: false, isFollowing: follow.isFollowing) == 0)
        }
        follow.resume()
        #expect(ExperimentalLyricsStyle.contextBlur(distance: 2, increasedContrast: false,
            reduceMotion: false, isFollowing: follow.isFollowing) == 2.1)
    }

    @Test("The original fallback is selected only while the preferred document is unavailable")
    func fallbackSelection() {
        #expect(LyricsPanelSelection.usesOriginal(prefersNew: true, hasNew: false, hasOriginal: true))
        #expect(!LyricsPanelSelection.usesOriginal(prefersNew: true, hasNew: true, hasOriginal: true))
        #expect(!LyricsPanelSelection.usesOriginal(prefersNew: true, hasNew: false, hasOriginal: false))
        #expect(LyricsPanelSelection.usesOriginal(prefersNew: false, hasNew: true, hasOriginal: true))
    }

    @Test("Switching renderers preserves manual reading and appearance within the same playback")
    @MainActor
    func sharedPresentation() {
        let settings = LyricsPresentationSettings()
        let first = UUID()
        settings.activate(first)
        settings.fontSize = 44
        settings.mode = .reading
        settings.followState.userScrolled()
        // A late rich document or an explicit renderer toggle uses this same identity.
        settings.activate(first)
        #expect(!settings.followState.isFollowing)
        #expect(settings.fontSize == 44 && settings.mode == .reading)
        let oldRequest = settings.followState.beginRequest()
        #expect(oldRequest == nil)
        settings.activate(UUID())
        #expect(settings.followState.isFollowing)
        #expect(settings.fontSize == 44 && settings.mode == .reading)
    }

    @Test("Sustained effects use real duration and settle at both word boundaries")
    func sustainedTiming() {
        let short = ExperimentalLyricsStyle.wordEffect(timeMS: 1200, startMS: 1000, endMS: 1400,
                                                        active: true, reduceMotion: false, wordMotion: true)
        let sustained = ExperimentalLyricsStyle.wordEffect(timeMS: 3000, startMS: 1000, endMS: 5000,
                                                            active: true, reduceMotion: false, wordMotion: true)
        #expect(short.scale == 1 && short.lift == 0)
        #expect(sustained.scale == ExperimentalLyricsStyle.maximumWordScale)
        #expect(sustained.lift == ExperimentalLyricsStyle.maximumWordLift)
        #expect(sustained.glowRadius == 5)
        for time in [Double.nan, 0, 1000, 5000, 6000] {
            #expect(ExperimentalLyricsStyle.wordEffect(timeMS: time, startMS: 1000, endMS: 5000,
                                                        active: true, reduceMotion: false, wordMotion: true) == .identity)
        }
        for (active, reduced, enabled) in [(false, false, true), (true, true, true), (true, false, false)] {
            #expect(ExperimentalLyricsStyle.wordEffect(timeMS: 3000, startMS: 1000, endMS: 5000,
                                                        active: active, reduceMotion: reduced, wordMotion: enabled) == .identity)
        }
        #expect(ExperimentalLyricsStyle.wordProgress(timeMS: 2000, startMS: 1000, endMS: 5000) == 0.25)
    }

    @Test("Soft edge remains continuous across shaped fragments and wraps")
    func maskContinuity() {
        let sweep = ExperimentalLyricsWordSweep(width: 120, progress: 0.5)
        #expect(sweep.feather == 30)
        #expect(sweep.opacity(at: 40) == 1)
        #expect(sweep.opacity(at: 60) == 0.5)
        #expect(sweep.opacity(at: 80) == 0)
        let first = sweep.stops(from: 0, to: 60)
        let continuation = sweep.stops(from: 60, to: 120)
        #expect(first.last?.opacity == continuation.first?.opacity)
        #expect(first.last?.opacity == 0.5)
        #expect(continuation.first?.location == 0)
        #expect(ExperimentalLyricsWordSweep(width: 10, progress: 0.5).feather == 5)
        #expect(ExperimentalLyricsWordSweep(width: 120, progress: 0).opacity(at: 0) == 0)
        #expect(ExperimentalLyricsWordSweep(width: 120, progress: 1).opacity(at: 120) == 1)
        #expect(ExperimentalLyricsWordSweep(width: .nan, progress: .nan).opacity(at: 0) == 0)
    }
}

@Suite("Letras experimentales: render del estilo Octave")
@MainActor
struct ExperimentalLyricsStylePresentationTests {
    @Test("Sustain animation never changes native layout for ligatures, RTL, emoji or wrapped words")
    func shapedTextDoesNotReflow() throws {
        let phrases = [
            ["office ", "affine ", "café ", "👩🏽‍🚀 ", "私たち ", "مرحبًا ", "بالعالم"],
            ["私たちはひとつの長い言葉を複数の行に包んで読みます"],
            ["Una\n", "segunda\n", "tercera\n", "cuarta\n", "quinta línea"]
        ]
        for (fixture, segments) in phrases.enumerated() {
            let line = ExperimentalLyricLine(startMS: 0, endMS: Double(segments.count) * 3000,
                text: segments.joined(), words: segments.enumerated().map { index, text in
                    .init(text: text, startMS: Double(index) * 3000, endMS: Double(index + 1) * 3000)
                })
            #expect(line.hasWordTiming)
            for width: CGFloat in [220, 420, 560] {
                var sizes: [CGSize] = []
                for (state, time, reduced) in [("start", 0.0, false), ("sustain", 1500.0, false), ("reduced", 1500.0, true), ("end", 3000.0, false)] {
                    let root = ExperimentalKaraokeText(line: line, timeMS: time, active: true,
                        reduceMotion: reduced, increasedContrast: false, fontSize: 36)
                        .frame(width: width, alignment: .leading)
                        .padding(24)
                        .background(Color.black)
                    let view = NSHostingView(rootView: root)
                    let size = view.fittingSize
                    #expect(size.width.isFinite && size.height.isFinite && size.height > 0)
                    sizes.append(size)
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                          backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = view
                    defer { window.close() }
                    view.setFrameSize(size)
                    view.layoutSubtreeIfNeeded()
                    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    #expect(png.count > 200)
                    if let output = ProcessInfo.processInfo.environment["SIDEB_PRESENTATION_QA"] {
                        let url = URL(fileURLWithPath: output).appendingPathComponent("octave-native-\(fixture)-\(Int(width))-\(state).png")
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try png.write(to: url)
                    }
                }
                #expect(sizes.allSatisfy { $0 == sizes.first })
            }
        }
    }
}
