import Testing
@testable import SideB

@Suite("Letras: orden de esperas con fondos tardíos")
struct ExperimentalLyricsSequenceTests {
    @Test("Outro follows every group even when the last singing voice belongs to an older phrase")
    func lateBackgroundOutro() throws {
        let document = ExperimentalLyricsDocument(provider: "fixture", instrumental: false, lines: [
            .init(startMS: 0, endMS: 3000, text: "Primera", groupID: "A"),
            .init(startMS: 5000, endMS: 10000, text: "Segunda", groupID: "B"),
            .init(startMS: 7000, endMS: 20000, text: "Fondo largo", role: "background", groupID: "A")
        ])
        let sequence = ExperimentalLyricsDisplayItem.sequence(document: document, duration: 30)
        #expect(sequence.compactMap(\.group).map(\.anchorLineIndex) == [0, 1])
        #expect(sequence.map { $0.interlude?.kind } == [nil, nil, .outro])
        #expect(sequence.last?.interlude?.anchorLineIndex == 0)
    }

    @Test("Interior wait stays before the next phrase after overlapping backgrounds have finished")
    func lateBackgroundInterlude() {
        let document = ExperimentalLyricsDocument(provider: "fixture", instrumental: false, lines: [
            .init(startMS: 0, endMS: 3000, text: "Primera", groupID: "A"),
            .init(startMS: 5000, endMS: 10000, text: "Segunda", groupID: "B"),
            .init(startMS: 7000, endMS: 20000, text: "Fondo largo", role: "background", groupID: "A"),
            .init(startMS: 30000, endMS: 32000, text: "Tercera", groupID: "C")
        ])
        let sequence = ExperimentalLyricsDisplayItem.sequence(document: document, duration: 34)
        #expect(sequence.map { $0.group?.anchorLineIndex } == [0, 1, nil, 3])
        #expect(sequence[2].interlude?.startMS == 20000)
        #expect(sequence[2].interlude?.endMS == 30000)
        #expect(sequence[2].interlude?.anchorLineIndex == 0)
    }

    @Test("Intro precedes the first phrase and unbounded voices do not invent display rows")
    func introAndUnknownEnd() {
        let document = ExperimentalLyricsDocument(provider: "fixture", instrumental: false, lines: [
            .init(startMS: 8000, endMS: nil, text: "Sin fin", groupID: "A")
        ])
        let sequence = ExperimentalLyricsDisplayItem.sequence(document: document, duration: 30)
        #expect(sequence.count == 2)
        #expect(sequence.first?.interlude?.kind == .intro)
        #expect(sequence.last?.group?.anchorLineIndex == 0)
        #expect(ExperimentalLyricsDisplayItem.sequence(document: .init(provider: "vacío", instrumental: false, lines: []), duration: 30).isEmpty)
    }
}
