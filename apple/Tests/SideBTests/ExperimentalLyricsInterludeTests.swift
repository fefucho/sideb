import Testing
@testable import SideB

@Suite("Letras experimentales: esperas conservadoras")
struct ExperimentalLyricsInterludeTests {
    @Test("Intro, interior and outro accept exactly five seconds")
    func exactThresholdAndAnchors() {
        let document = makeDocument([
            .init(startMS: 5000, endMS: 6000, text: "Uno"),
            .init(startMS: 11000, endMS: 12000, text: "Dos")
        ])
        let gaps = document.interludes(durationMS: 17000)
        #expect(gaps.map(\.kind) == [.intro, .interlude, .outro])
        #expect(gaps.map(\.startMS) == [0, 6000, 12000])
        #expect(gaps.map(\.endMS) == [5000, 11000, 17000])
        #expect(gaps.map(\.anchorLineIndex) == [nil, 0, 1])
        #expect(makeDocument([
            .init(startMS: 4999, endMS: 6000, text: "Uno"),
            .init(startMS: 10999, endMS: 12000, text: "Dos")
        ]).interludes(durationMS: 16999).isEmpty)
    }

    @Test("Another voice crossing a lead gap prevents a false wait")
    func backgroundBridgesGap() {
        let document = makeDocument([
            .init(startMS: 0, endMS: 2000, text: "Principal", groupID: "a"),
            .init(startMS: 12000, endMS: 14000, text: "Siguiente", groupID: "b"),
            .init(startMS: 1500, endMS: 10000, text: "Fondo", role: "background", groupID: "a")
        ])
        #expect(document.interludes(durationMS: nil).isEmpty)
    }

    @Test("Word coverage detects a real pause inside a padded line")
    func actualWordsInsteadOfPaddedEnd() {
        let document = makeDocument([
            .init(startMS: 1000, endMS: 30000, text: "Uno dos", words: [
                .init(text: "Uno", startMS: 1000, endMS: 2000),
                .init(text: "dos", startMS: 9000, endMS: 10000)
            ])
        ])
        let gaps = document.interludes(durationMS: 20000)
        #expect(gaps.map(\.kind) == [.interlude, .outro])
        #expect(gaps.map(\.startMS) == [2000, 10000])
        #expect(gaps.map(\.endMS) == [9000, 20000])
        #expect(gaps.allSatisfy { $0.anchorLineIndex == 0 })
    }

    @Test("Incomplete provider words use a reliable full line interval")
    func partialWordsCannotInventSilence() {
        let document = makeDocument([
            .init(startMS: 0, endMS: 10000, text: "Una frase completa", words: [
                .init(text: "Una", startMS: 0, endMS: 1000)
            ]),
            .init(startMS: 15000, endMS: 16000, text: "Después")
        ])
        let gaps = document.interludes(durationMS: nil)
        #expect(gaps.count == 1)
        #expect(gaps.first?.startMS == 10000)
        #expect(gaps.first?.endMS == 15000)
    }

    @Test("An unknown end never borrows the next line's start")
    func openEndBlocksLaterInference() {
        let document = makeDocument([
            .init(startMS: 5000, endMS: nil, text: "No sabemos cuándo termina"),
            .init(startMS: 20000, endMS: 21000, text: "Después")
        ])
        let gaps = document.interludes(durationMS: 30000)
        #expect(gaps.map(\.kind) == [.intro])
        #expect(gaps.first?.endMS == 5000)
    }

    @Test("Partial word timing without a line end remains unbounded")
    func partialWordsWithoutEndBlockLaterInference() {
        let document = makeDocument([
            .init(startMS: 0, endMS: nil, text: "Una frase completa", words: [
                .init(text: "Una", startMS: 0, endMS: 1000)
            ]),
            .init(startMS: 10000, endMS: 11000, text: "Después")
        ])
        #expect(document.interludes(durationMS: 20000).isEmpty)
    }

    @Test("Entirely untimed vocal text prevents invented waits anywhere")
    func untimedVoiceBlocksInference() {
        let document = makeDocument([
            .init(startMS: 5000, endMS: 6000, text: "Uno"),
            .init(startMS: nil, endMS: nil, text: "Voz sin tiempos", role: "background"),
            .init(startMS: 15000, endMS: 16000, text: "Dos")
        ])
        #expect(document.interludes(durationMS: 25000).isEmpty)
    }

    @Test("An unknown start blocks earlier inference while its known end bounds later gaps")
    func unknownStartIsNotSilence() {
        let document = makeDocument([
            .init(startMS: nil, endMS: 5000, text: "Inicio desconocido"),
            .init(startMS: 10000, endMS: 11000, text: "Después")
        ])
        let gaps = document.interludes(durationMS: 16000)
        #expect(gaps.map(\.kind) == [.interlude, .outro])
        #expect(gaps.map(\.startMS) == [5000, 11000])
        #expect(gaps.map(\.endMS) == [10000, 16000])
    }

    @Test("Invalid or reversed ends retain uncertainty after the known start")
    func invalidEndsAreNotReliableBounds() {
        for end in [Double.nan, .infinity, -1, 3000] {
            let document = makeDocument([
                .init(startMS: 5000, endMS: end, text: "Uno"),
                .init(startMS: 20000, endMS: 21000, text: "Dos")
            ])
            #expect(document.interludes(durationMS: 30000).map(\.kind) == [.intro])
        }
    }

    @Test("Outro requires a finite positive duration after the last known voice")
    func durationMustBoundOutro() {
        let document = makeDocument([.init(startMS: 0, endMS: 1000, text: "Uno")])
        for duration: Double? in [nil, .nan, .infinity, -.infinity, -1, 0, 500, 5999] {
            #expect(document.interludes(durationMS: duration).isEmpty)
        }
        #expect(document.interludes(durationMS: 6000).map(\.kind) == [.outro])
        #expect(document.interludes(durationMS: 6000, minimumGapMS: .nan).isEmpty)
        #expect(document.interludes(durationMS: 6000, minimumGapMS: -1).isEmpty)
    }

    @Test("A word extending past a provider line end remains vocal coverage")
    func sustainedWordCannotBeClippedByLineEnd() {
        let document = makeDocument([
            .init(startMS: 0, endMS: 1000, text: "Sostenida", words: [
                .init(text: "Sostenida", startMS: 0, endMS: 8000)
            ]),
            .init(startMS: 13000, endMS: 14000, text: "Después")
        ])
        let gaps = document.interludes(durationMS: nil)
        #expect(gaps.count == 1)
        #expect(gaps.first?.startMS == 8000)
        #expect(gaps.first?.endMS == 13000)
    }

    @Test("The last background voice anchors its gap to its lead group")
    func backgroundEndUsesPresentationAnchor() {
        let document = makeDocument([
            .init(startMS: 0, endMS: 1000, text: "Principal", groupID: "a"),
            .init(startMS: 1000, endMS: 2000, text: "Fondo", role: "background", groupID: "a"),
            .init(startMS: 7000, endMS: 8000, text: "Siguiente", groupID: "b")
        ])
        let gaps = document.interludes(durationMS: 13000)
        #expect(gaps.map(\.anchorLineIndex) == [0, 2])
        #expect(gaps.map(\.startMS) == [2000, 8000])
    }

    @Test("Coverage uses temporal order without rewriting source line indices")
    func unorderedRowsHaveChronologicalWaits() {
        let document = makeDocument([
            .init(startMS: 20000, endMS: 21000, text: "Última"),
            .init(startMS: 5000, endMS: 6000, text: "Primera"),
            .init(startMS: 10000, endMS: 11000, text: "Segunda")
        ])
        let gaps = document.interludes(durationMS: 26000)
        #expect(gaps.map(\.startMS) == [0, 11000, 21000])
        #expect(gaps.map(\.endMS) == [5000, 20000, 26000])
        #expect(gaps.map(\.anchorLineIndex) == [nil, 2, 0])
    }

    @Test("Wait identity and progress are deterministic on the media timeline")
    func stableIdentityAndBoundedProgress() throws {
        let document = makeDocument([.init(startMS: 5000, endMS: 6000, text: "Uno")])
        let intro = try #require(document.interludes(durationMS: nil).first)
        #expect(intro.id == document.interludes(durationMS: nil).first?.id)
        #expect(intro.progress(at: -1) == 0)
        #expect(intro.progress(at: 2500) == 0.5)
        #expect(intro.progress(at: 5000) == 1)
        #expect(intro.progress(at: 10000) == 1)
        #expect(intro.progress(at: .nan) == 0)
        #expect(intro.contains(timeMS: 0))
        #expect(intro.contains(timeMS: 4999))
        #expect(!intro.contains(timeMS: 5000))
        #expect(!intro.contains(timeMS: .infinity))
    }

    @Test("Empty, instrumental and whitespace-only records have no invented vocal boundary")
    func noVocalBoundsNoWaits() {
        #expect(makeDocument([]).interludes(durationMS: 30000).isEmpty)
        #expect(makeDocument([.init(startMS: nil, endMS: nil, text: " \n")]).interludes(durationMS: 30000).isEmpty)
        #expect(ExperimentalLyricsDocument(provider: "fixture", instrumental: true, lines: [
            .init(startMS: 10000, endMS: 11000, text: "Metadata")
        ]).interludes(durationMS: 30000).isEmpty)
    }

    private func makeDocument(_ lines: [ExperimentalLyricLine]) -> ExperimentalLyricsDocument {
        .init(provider: "fixture", instrumental: false, lines: lines)
    }
}
