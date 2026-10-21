import AppKit
import AVFoundation
import SwiftUI
import Testing
@testable import SideB

@Suite("Letras experimentales: tiempos y texto reales")
struct ExperimentalLyricsDocumentTests {
    @Test("Reconciles provider words without spaces while preserving original whitespace")
    func spacesStayInOriginalText() {
        let line = ExperimentalLyricLine(startMS: 1000, endMS: 3000, text: "  Uno   dos\n", words: [
            .init(text: "Uno", startMS: 1000, endMS: 2000),
            .init(text: "dos", startMS: 2000, endMS: 3000)
        ])
        #expect(line.hasWordTiming)
        #expect(line.karaokeSegments?.map(\.text).joined() == "  Uno   dos\n")
        #expect(line.karaokeSegments?.compactMap(\.wordIndex) == [0, 1])
    }

    @Test("Keeps punctuation and repeated words attached to their actual positions")
    func punctuationAndRepeatedWords() {
        let line = ExperimentalLyricLine(startMS: 0, endMS: 3000, text: "sí, sí, así.", words: [
            .init(text: "sí, ", startMS: 0, endMS: 1000),
            .init(text: "sí, ", startMS: 1000, endMS: 2000),
            .init(text: "así.", startMS: 2000, endMS: 3000)
        ])
        #expect(line.hasWordTiming)
        #expect(line.karaokeSegments?.map(\.text).joined() == line.text)
        #expect(line.karaokeSegments?.compactMap(\.wordIndex) == [0, 1, 2])
    }

    @Test("Does not fabricate word timing when text differs or timing is invalid")
    func invalidWordsUseLineFallback() {
        let mismatch = ExperimentalLyricLine(startMS: 0, endMS: 1000, text: "Una versión distinta", words: [
            .init(text: "Una", startMS: 0, endMS: 1000)
        ])
        let emptyDuration = ExperimentalLyricLine(startMS: 0, endMS: 1000, text: "Una", words: [
            .init(text: "Una", startMS: 0, endMS: 0)
        ])
        let reversed = ExperimentalLyricLine(startMS: 0, endMS: 1000, text: "Una dos", words: [
            .init(text: "Una", startMS: 500, endMS: 600),
            .init(text: "dos", startMS: 100, endMS: 200)
        ])
        #expect(!mismatch.hasWordTiming)
        #expect(!emptyDuration.hasWordTiming)
        #expect(!reversed.hasWordTiming)
        #expect(mismatch.text == "Una versión distinta")
    }

    @Test("CJK, emoji and composed accents remain complete")
    func unicodeAndNoSpaces() {
        let text = "私は👩🏽‍🚀 café"
        let line = ExperimentalLyricLine(startMS: 10, endMS: 1000, text: text, words: [
            .init(text: "私", startMS: 10, endMS: 100),
            .init(text: "は", startMS: 100, endMS: 200),
            .init(text: "👩🏽‍🚀", startMS: 200, endMS: 500),
            .init(text: "café", startMS: 500, endMS: 1000)
        ])
        #expect(line.hasWordTiming)
        #expect(line.karaokeSegments?.map(\.text).joined() == text)
        #expect(line.words[2].text.count == 1)
    }

    @Test("A word uses its own duration, not an even fraction of the phrase")
    func wordProgress() {
        let word = ExperimentalLyricWord(text: "sostenida", startMS: 8000, endMS: 12000)
        #expect(word.progress(at: 7000) == 0)
        #expect(word.progress(at: 9000) == 0.25)
        #expect(word.progress(at: 10000) == 0.5)
        #expect(word.progress(at: 13000) == 1)
        #expect(word.progress(at: .nan) == 0)
    }

    @Test("Focus persists in gaps, while word animation stops at the line end")
    func gapFocusAndAnimation() {
        let first = ExperimentalLyricLine(startMS: 1000, endMS: 2000, text: "Uno", words: [.init(text: "Uno", startMS: 1000, endMS: 2000)])
        let second = ExperimentalLyricLine(startMS: 8000, endMS: 9000, text: "Dos", words: [.init(text: "Dos", startMS: 8000, endMS: 9000)])
        let doc = ExperimentalLyricsDocument(provider: "fixture", instrumental: false, lines: [first, second])
        #expect(doc.focusIndex(at: 0) == 0)
        #expect(doc.focusIndex(at: 5000) == 0)
        #expect(doc.activeWordLineIndices(at: 5000).isEmpty)
        #expect(doc.activeWordLineIndices(at: 8500) == [1])
        #expect(doc.focusIndex(at: 20000) == 1)
        #expect(doc.activeWordLineIndices(at: 20000).isEmpty)
    }

    @Test("Simultaneous timed lines can both render while one line owns scroll focus")
    func simultaneousLines() {
        let doc = ExperimentalLyricsDocument(provider: "fixture", instrumental: false, lines: [
            .init(startMS: 0, endMS: 3000, text: "Uno", words: [.init(text: "Uno", startMS: 0, endMS: 3000)]),
            .init(startMS: 1000, endMS: 4000, text: "Dos", words: [.init(text: "Dos", startMS: 1000, endMS: 4000)])
        ])
        #expect(doc.activeWordLineIndices(at: 1500) == [0, 1])
        #expect(doc.focusIndex(at: 1500) == 1)
    }

    @Test("Word timing is not cut off by an earlier provider line end")
    func wordOutlivesLineEnd() {
        let line = ExperimentalLyricLine(startMS: 1000, endMS: 1200, text: "Sostenida", words: [
            .init(text: "Sostenida", startMS: 1000, endMS: 4000)
        ])
        #expect(line.effectiveEndMS == 4000)
        #expect(line.contains(timeMS: 3500))
        #expect(line.hasChangingWord(at: 3500))
    }

    @Test("Plain lines have no pretend follow focus")
    func plainLines() {
        let doc = ExperimentalLyricsDocument(provider: "fixture", instrumental: false, lines: [
            .init(startMS: nil, endMS: nil, text: "Texto sin tiempos", translation: "Untimed text")
        ])
        #expect(!doc.hasWordTimings)
        #expect(!doc.hasLineTimings)
        #expect(doc.hasTranslations)
        #expect(doc.focusIndex(at: 5000) == nil)
    }
}

@Suite("Letras experimentales: reloj local y dibujo")
@MainActor
struct ExperimentalLyricsPresentationTests {
    @Test("Frame clock is disabled when paused, buffering, hidden, reading, or in a gap")
    func pulsePolicy() {
        #expect(ExperimentalLyricsClock.shouldPulse(visible: true, playing: true, animateWords: true, hasChangingWord: true))
        #expect(!ExperimentalLyricsClock.shouldPulse(visible: false, playing: true, animateWords: true, hasChangingWord: true))
        #expect(!ExperimentalLyricsClock.shouldPulse(visible: true, playing: false, animateWords: true, hasChangingWord: true))
        #expect(!ExperimentalLyricsClock.shouldPulse(visible: true, playing: true, animateWords: false, hasChangingWord: true))
        #expect(!ExperimentalLyricsClock.shouldPulse(visible: true, playing: true, animateWords: true, hasChangingWord: false))
    }

    @Test("Boundary times include a short segment after a gap and use the offset consistently")
    func shortWordBoundary() {
        let doc = ExperimentalLyricsDocument(provider: "fixture", instrumental: false, lines: [
            .init(startMS: 1000, endMS: 2000, text: "Uno", words: [.init(text: "Uno", startMS: 1000, endMS: 2000)]),
            .init(startMS: 8035, endMS: 8080, text: "Dos", words: [.init(text: "Dos", startMS: 8035, endMS: 8080)])
        ])
        #expect(ExperimentalLyricsClock.boundarySeconds(document: doc, offsetMS: 0) == [1, 2, 8.035, 8.08])
        #expect(ExperimentalLyricsClock.boundarySeconds(document: doc, offsetMS: 100) == [0.9, 1.9, 7.935, 7.98])
        #expect(doc.lines[1].hasChangingWord(at: 8050))
        #expect(!doc.lines[1].hasChangingWord(at: 8100))
    }

    @Test("Stopping detaches a panel clock without mutating playback")
    func clockLifecycle() {
        let player = AVPlayer()
        let clock = ExperimentalLyricsClock()
        let doc = ExperimentalLyricsDocument(provider: "fixture", instrumental: false, lines: [.init(startMS: 0, endMS: 1000, text: "Texto")])
        clock.start(player: player, document: doc)
        clock.setVisible(true)
        #expect(clock.focusIndex == 0)
        #expect(clock.positionMS == 0)
        clock.stop()
        #expect(player.currentItem == nil)
        #expect(player.rate == 0)
    }

    @Test("Native karaoke can render a synthetic Unicode phrase at narrow and normal widths")
    func nativeRendererWraps() throws {
        let line = ExperimentalLyricLine(startMS: 0, endMS: 6000, text: "Una frase larga, café 👩🏽‍🚀 y 私たち", words: [
            .init(text: "Una ", startMS: 0, endMS: 500),
            .init(text: "frase ", startMS: 500, endMS: 1000),
            .init(text: "larga, ", startMS: 1000, endMS: 2000),
            .init(text: "café ", startMS: 2000, endMS: 3000),
            .init(text: "👩🏽‍🚀 ", startMS: 3000, endMS: 4000),
            .init(text: "y ", startMS: 4000, endMS: 4500),
            .init(text: "私たち", startMS: 4500, endMS: 6000)
        ])
        #expect(line.hasWordTiming)
        var heights: [CGFloat] = []
        for width: CGFloat in [220, 560] {
            let root = ExperimentalKaraokeText(line: line, timeMS: 2500, active: true,
                                              reduceMotion: false, increasedContrast: false, fontSize: 29)
                .frame(width: width, alignment: .leading)
                .padding(10)
                .background(Color.black)
            let view = NSHostingView(rootView: root)
            let size = view.fittingSize
            #expect(size.width.isFinite && size.width > 0)
            #expect(size.height.isFinite && size.height > 0)
            heights.append(size.height)
            view.setFrameSize(size)
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            #expect(png.count > 200)
            if let output = ProcessInfo.processInfo.environment["SIDEB_PRESENTATION_QA"] {
                let url = URL(fileURLWithPath: output).appendingPathComponent("experimental-karaoke-\(Int(width)).png")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: url)
            }
        }
        #expect(heights[0] > heights[1])
        if let output = ProcessInfo.processInfo.environment["SIDEB_PRESENTATION_QA"] {
            try captureFullPanel(in: output, wordLine: line)
        }
    }

    @Test("Cambiar a un documento con menos líneas mientras el panel está montado no indexa fuera de rango")
    @MainActor
    func shrinkingDocumentTransitionDoesNotCrash() {
        let longLines: [ExperimentalLyricLine] = (0..<35).map { idx -> ExperimentalLyricLine in
            let startMS: Double = Double(idx) * 2000
            let endMS: Double = startMS + 1500
            return ExperimentalLyricLine(startMS: startMS, endMS: endMS, text: "Línea \(idx)")
        }
        let shortLines: [ExperimentalLyricLine] = (0..<5).map { idx -> ExperimentalLyricLine in
            let startMS: Double = Double(idx) * 2000
            let endMS: Double = startMS + 1500
            return ExperimentalLyricLine(startMS: startMS, endMS: endMS, text: "Corta \(idx)")
        }
        let longDoc = ExperimentalLyricsDocument(provider: "Long", instrumental: false, lines: longLines)
        let shortDoc = ExperimentalLyricsDocument(provider: "Short", instrumental: false, lines: shortLines)
        let player = AVPlayer()
        let firstID = UUID()
        let secondID = UUID()
        let bounds = NSRect(x: 0, y: 0, width: 420, height: 1200)
        let view = NSHostingView(rootView:
            ExperimentalLyricsPanel(document: longDoc, player: player, playbackIdentity: firstID,
                                    duration: 80, onSeek: { _ in })
                .frame(width: 420, height: 1200)
        )
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        view.setFrameSize(bounds.size)
        view.layoutSubtreeIfNeeded()

        view.rootView = ExperimentalLyricsPanel(document: shortDoc, player: player, playbackIdentity: secondID,
                                                duration: 15, onSeek: { _ in })
            .frame(width: 420, height: 1200)
        view.layoutSubtreeIfNeeded()
        #expect(shortDoc.lines.count == 5)
    }

    /// Opt-in visual QA only: synthetic text, no account and no media item/audio.
    private func captureFullPanel(in directory: String, wordLine: ExperimentalLyricLine) throws {
        let document = ExperimentalLyricsDocument(provider: "Fixture local · sin red", instrumental: false, lines: [
            .init(startMS: wordLine.startMS, endMS: wordLine.endMS, text: wordLine.text, words: wordLine.words,
                  translation: "A long phrase, coffee, an astronaut and all of us"),
            .init(startMS: 7000, endMS: 10000, text: "Otra línea mantiene su ritmo.", words: [
                .init(text: "Otra ", startMS: 7000, endMS: 7500),
                .init(text: "línea ", startMS: 7500, endMS: 8000),
                .init(text: "mantiene ", startMS: 8000, endMS: 8500),
                .init(text: "su ", startMS: 8500, endMS: 9000),
                .init(text: "ritmo.", startMS: 9000, endMS: 10000)
            ], translation: "Another line keeps its rhythm."),
            .init(startMS: 11000, endMS: 15000, text: "Esta frase sólo tiene tiempo por línea y sigue siendo legible.",
                  translation: "This phrase only has line timing and remains readable.")
        ])
        let player = AVPlayer()
        let root = ExperimentalLyricsPanel(document: document, player: player, playbackIdentity: UUID(),
                                           duration: 20, onSeek: { _ in })
            .padding(16)
            .frame(width: 420, height: 600)
            .background(Color(red: 0.055, green: 0.045, blue: 0.065))
            .environment(\.colorScheme, .dark)
        let view = NSHostingView(rootView: root)
        let bounds = NSRect(x: 0, y: 0, width: 420, height: 600)
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // Attach for native menu/control rendering, but never show a test window on screen.
        window.contentView = view
        defer { window.close() }
        view.setFrameSize(bounds.size)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: directory).appendingPathComponent("experimental-lyrics-panel-420.png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        #expect(player.currentItem == nil)
        #expect(player.rate == 0)
    }
}
