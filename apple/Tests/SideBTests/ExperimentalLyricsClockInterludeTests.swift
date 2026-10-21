import AppKit
import AVFoundation
import SwiftUI
import Testing
@testable import SideB

@Suite("Letras Octave: integración del reloj y esperas")
@MainActor
struct ExperimentalLyricsClockInterludeTests {
    private var document: ExperimentalLyricsDocument {
        .init(provider: "Fixture local", instrumental: false, lines: [
            .init(startMS: 8000, endMS: 10000, text: "Luz", words: [
                .init(text: "Luz", startMS: 8000, endMS: 10000)
            ]),
            .init(startMS: 18000, endMS: 20000, text: "Vuelve", words: [
                .init(text: "Vuelve", startMS: 18000, endMS: 20000)
            ])
        ])
    }

    @Test("A changing wait can run without a word; pause, invisibility and static mode stop it")
    func waitPulsePolicy() {
        #expect(ExperimentalLyricsClock.shouldPulse(visible: true, playing: true,
            animateWords: false, hasChangingWord: false, hasChangingInterlude: true))
        #expect(!ExperimentalLyricsClock.shouldPulse(visible: true, playing: false,
            animateWords: true, hasChangingWord: false, hasChangingInterlude: true))
        #expect(!ExperimentalLyricsClock.shouldPulse(visible: false, playing: true,
            animateWords: true, hasChangingWord: false, hasChangingInterlude: true))
        #expect(!ExperimentalLyricsClock.shouldPulse(visible: true, playing: true,
            animateWords: true, hasChangingWord: false, hasChangingInterlude: true, animateInterludes: false))
        #expect(ExperimentalLyricsClock.shouldPulse(visible: true, playing: true,
            animateWords: true, hasChangingWord: true, hasChangingInterlude: false, animateInterludes: false))
        #expect(!ExperimentalLyricsClock.shouldPulse(visible: true, playing: true,
            animateWords: true, hasChangingWord: true, hasVisibleChangingWord: false))
        #expect(!ExperimentalLyricsClock.shouldPulse(visible: true, playing: true,
            animateWords: false, hasChangingWord: false, hasChangingInterlude: true,
            hasVisibleInterlude: false))
        #expect(!ExperimentalLyricsClock.shouldPulse(visible: true, playing: true,
            animateWords: true, hasChangingWord: true, seeking: true))
    }

    @Test("Completed focus is derived at lyric boundaries, including offset and outro")
    func completedFocusBoundaries() {
        let timed = ExperimentalLyricsDocument(provider: "Rangos", instrumental: false, lines: [
            .init(startMS: 1000, endMS: 2000, text: "Primera", words: [
                .init(text: "Primera", startMS: 1000, endMS: 2000)
            ]),
            .init(startMS: 8000, endMS: 9000, text: "Última", words: [
                .init(text: "Última", startMS: 8000, endMS: 9000)
            ])
        ])
        #expect(ExperimentalLyricsClock.completedFocusIndex(document: timed, at: 0) == nil)
        #expect(ExperimentalLyricsClock.completedFocusIndex(document: timed, at: 1999) == nil)
        #expect(ExperimentalLyricsClock.completedFocusIndex(document: timed, at: 2000) == 0)
        #expect(ExperimentalLyricsClock.completedFocusIndex(document: timed, at: 7500) == 0)
        #expect(ExperimentalLyricsClock.completedFocusIndex(document: timed, at: 8000) == nil)
        #expect(ExperimentalLyricsClock.completedFocusIndex(document: timed, at: 9000) == 1)
        #expect(ExperimentalLyricsClock.completedFocusIndex(document: timed, at: 30000) == 1)
        #expect(ExperimentalLyricsClock.completedFocusIndex(document: timed, at: 1500 + 500) == 0)
        #expect(ExperimentalLyricsClock.completedFocusIndex(document: timed, at: 2500 - 500) == 0)
        #expect(ExperimentalLyricsClock.completedFocusIndex(document: timed, at: 500 - 500) == nil)
    }

    @Test("Visible group identity survives a same-ID clock restart and stop clears it")
    func visibleGroupIdentityLifecycle() {
        let player = AVPlayer()
        let clock = ExperimentalLyricsClock()
        clock.setPresentationGroupVisible(id: "line:0", visible: true)
        clock.start(player: player, document: document, duration: 30)
        #expect(clock.visiblePresentationGroupIDs == ["line:0"])
        clock.start(player: player, document: document, duration: 30)
        #expect(clock.visiblePresentationGroupIDs == ["line:0"])
        let introID = clock.interludes.first?.id ?? ""
        #expect(!introID.isEmpty)
        clock.setInterludeVisible(id: introID, visible: true)
        #expect(clock.visibleInterludeIDs == [introID])
        clock.start(player: player, document: document, duration: 30)
        #expect(clock.visibleInterludeIDs == [introID])
        clock.stop()
        #expect(clock.visiblePresentationGroupIDs.isEmpty)
        #expect(clock.visibleInterludeIDs.isEmpty)
        #expect(clock.completedFocusIndex == nil)
    }

    @Test("Any visible active voice in a presentation group keeps karaoke sampling eligible")
    func simultaneousVoiceVisibilityPolicy() {
        let voices = ExperimentalLyricsDocument(provider: "Dúo", instrumental: false, lines: [
            .init(startMS: 0, endMS: 3000, text: "Principal", words: [
                .init(text: "Principal", startMS: 0, endMS: 3000)
            ], groupID: "duo"),
            .init(startMS: 500, endMS: 2500, text: "Fondo", words: [
                .init(text: "Fondo", startMS: 500, endMS: 2500)
            ], role: "background", groupID: "duo")
        ])
        #expect(ExperimentalLyricsClock.hasVisibleChangingWord(document: voices,
            activeLineIndices: [0, 1], visiblePresentationGroupIDs: ["line:0"], at: 1000))
        #expect(!ExperimentalLyricsClock.hasVisibleChangingWord(document: voices,
            activeLineIndices: [0, 1], visiblePresentationGroupIDs: [], at: 1000))
        #expect(!ExperimentalLyricsClock.hasVisibleChangingWord(document: voices,
            activeLineIndices: [0, 1], visiblePresentationGroupIDs: ["line:0"], at: 3000))
    }

    @Test("Wait boundaries include intro and track end using the same offset as vocal words")
    func interludeBoundaries() {
        let waits = document.interludes(durationMS: 30000)
        #expect(waits.map(\.kind) == [.intro, .interlude, .outro])
        #expect(ExperimentalLyricsClock.boundarySeconds(document: document, offsetMS: 0, interludes: waits)
            == [0, 8, 10, 18, 20, 30])
        #expect(ExperimentalLyricsClock.boundarySeconds(document: document, offsetMS: 100, interludes: waits)
            == [7.9, 9.9, 17.9, 19.9, 29.9])
    }

    @Test("Duration and offset changes recompute waits without changing the player's media time")
    func updateWaitsFromClock() {
        let player = AVPlayer()
        let clock = ExperimentalLyricsClock()
        clock.start(player: player, document: document, duration: 30)
        #expect(clock.interludes.last?.endMS == 30000)
        #expect(clock.activeInterludeID == clock.interludes.first?.id)
        clock.configure(animateWords: true, offsetMS: 10000)
        #expect(clock.completedFocusIndex == 0)
        #expect(clock.activeLineIndices.isEmpty)
        clock.configure(animateWords: true, offsetMS: 9000)
        #expect(clock.completedFocusIndex == nil)
        #expect(clock.activeInterludeID == nil)
        #expect(clock.focusIndex == 0)
        #expect(clock.activeLineIndices == [0])
        #expect(clock.activeWordLineIndices == [0])
        let fallback = ExperimentalLyricsDocument(provider: "Sólo líneas", instrumental: false, lines: [
            .init(startMS: 8000, endMS: 11000, text: "Coros", role: "background", groupID: "fondo")
        ])
        clock.start(player: player, document: fallback, duration: 30)
        clock.configure(animateWords: true, offsetMS: 9000)
        #expect(clock.activeLineIndices == [0])
        #expect(clock.activeWordLineIndices.isEmpty)
        clock.updateDuration(40)
        #expect(clock.interludes.last?.endMS == 40000)
        clock.updateDuration(.nan)
        #expect(!clock.interludes.contains { $0.kind == .outro })
        #expect(player.currentItem == nil)
        #expect(!player.currentTime().isValid || player.currentTime().seconds == 0)
        #expect(player.rate == 0)
        clock.stop()
        #expect(clock.activeInterludeID == nil)
        #expect(clock.interludes.isEmpty)
    }

    @Test("A new document drops the previous intro and voice groups")
    func newDocumentResetsWaitingState() {
        let player = AVPlayer()
        let clock = ExperimentalLyricsClock()
        clock.start(player: player, document: document, duration: 30)
        #expect(clock.activeInterludeID != nil)
        let replacement = ExperimentalLyricsDocument(provider: "Sin tiempos", instrumental: false,
                                                     lines: [.init(startMS: nil, endMS: nil, text: "Lectura completa")])
        clock.start(player: player, document: replacement)
        #expect(clock.activeInterludeID == nil)
        #expect(clock.interludes.isEmpty)
        #expect(clock.focusIndex == nil)
        clock.stop()
    }

    @Test("Native panel renders rich voice groups and the three-dot indicator using synthetic text")
    func richPanelRendering() async throws {
        let fixture = ExperimentalLyricsDocument(provider: "Fixture local · sin red", instrumental: false, lines: [
            .init(startMS: 0, endMS: 6000, text: "Una luz recorre la ciudad", words: [
                .init(text: "Una ", startMS: 0, endMS: 400),
                .init(text: "luz ", startMS: 400, endMS: 2400),
                .init(text: "recorre ", startMS: 2400, endMS: 3400),
                .init(text: "la ", startMS: 3400, endMS: 4000),
                .init(text: "ciudad", startMS: 4000, endMS: 6000)
            ], agent: "v1", groupID: "g1"),
            .init(startMS: 1000, endMS: 5000, text: "(Vuelve a brillar)", words: [
                .init(text: "(Vuelve ", startMS: 1000, endMS: 2200),
                .init(text: "a ", startMS: 2200, endMS: 2600),
                .init(text: "brillar)", startMS: 2600, endMS: 5000)
            ], role: "background", agent: "v2", groupID: "g1"),
            .init(startMS: 13000, endMS: 17000, text: "Cada frase encuentra su lugar", words: [
                .init(text: "Cada ", startMS: 13000, endMS: 13500),
                .init(text: "frase ", startMS: 13500, endMS: 14200),
                .init(text: "encuentra ", startMS: 14200, endMS: 15500),
                .init(text: "su ", startMS: 15500, endMS: 16000),
                .init(text: "lugar", startMS: 16000, endMS: 17000)
            ], agent: "v1", groupID: "g2")
        ])
        for width: CGFloat in [330, 447, 600] {
            let player = AVPlayer()
            let panel = ExperimentalLyricsPanel(document: fixture, player: player, playbackIdentity: UUID(),
                                                duration: 25, onSeek: { _ in })
                .frame(width: width, height: 640)
                .background(Color(red: 0.10, green: 0.12, blue: 0.07))
                .environment(\.colorScheme, .dark)
            try await capture(panel, size: .init(width: width, height: 640), name: "octave-panel-\(Int(width))")
            #expect(player.currentItem == nil && player.rate == 0)
        }
        let indicator = ExperimentalLyricsInterludeIndicator(progress: 0.48, increasedContrast: false)
            .padding(24).frame(width: 180, height: 90, alignment: .leading)
            .background(Color(red: 0.10, green: 0.12, blue: 0.07))
        try await capture(indicator, size: .init(width: 180, height: 90), name: "octave-interlude")
    }

    private func capture<V: View>(_ root: V, size: CGSize, name: String) async throws {
        let view = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        view.setFrameSize(size)
        view.layoutSubtreeIfNeeded()
        // Let onAppear, media sampling and the deferred initial scroll settle.
        try await Task.sleep(for: .milliseconds(80))
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(png.count > 200)
        if let output = ProcessInfo.processInfo.environment["SIDEB_PRESENTATION_QA"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }
}
