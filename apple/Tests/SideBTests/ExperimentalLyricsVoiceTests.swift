import Testing
@testable import SideB

@Suite("Letras experimentales: voces explícitas y grupos")
struct ExperimentalLyricsVoiceTests {
    @Test("Existing fixtures retain nil metadata and parentheses are ordinary lyric text")
    func defaultsDoNotInferVoiceRoles() {
        let line = ExperimentalLyricLine(startMS: 0, endMS: 1000, text: "(Una frase entre paréntesis)")
        #expect(line.role == nil)
        #expect(line.agent == nil)
        #expect(line.groupID == nil)
        #expect(line.section == nil)
        #expect(!line.isBackground)
        let document = makeDocument([line])
        #expect(document.presentationGroups.first?.leadLineIndex == 0)
    }

    @Test("Provider metadata stays intact and only an explicit background role is subordinate")
    func metadataIsPreserved() {
        let line = ExperimentalLyricLine(startMS: 0, endMS: 1000, text: "Respuesta", role: "background",
                                         agent: "v2", groupID: "verse-2", section: "Chorus")
        #expect(line.isBackground)
        #expect(line.role == "background")
        #expect(line.agent == "v2")
        #expect(line.groupID == "verse-2")
        #expect(line.section == "Chorus")
        #expect(!ExperimentalLyricLine(startMS: 0, endMS: 1000, text: "Otra voz", agent: "v2").isBackground)
    }

    @Test("Explicit groups put the lead first and retain independent ungrouped rows")
    func explicitGroupsAndIndependentRows() {
        let document = makeDocument([
            .init(startMS: 0, endMS: 500, text: "(Texto normal)"),
            .init(startMS: 1000, endMS: 4000, text: "Principal", groupID: "a"),
            .init(startMS: 1500, endMS: 2500, text: "Fondo sin vínculo", role: "background", agent: "v2"),
            .init(startMS: 3000, endMS: 4000, text: "Fondo tardío", role: "background", groupID: "a"),
            .init(startMS: 2000, endMS: 2500, text: "Fondo temprano", role: "background", groupID: "a"),
            .init(startMS: 5000, endMS: 6000, text: "Grupo vacío", groupID: " ")
        ])
        #expect(document.presentationGroups.map(\.id) == [0, 1, 2, 5])
        #expect(document.presentationGroups[1].leadLineIndex == 1)
        #expect(document.presentationGroups[1].backgroundLineIndices == [4, 3])
        #expect(document.presentationGroups[1].lineIndices == [1, 4, 3])
        #expect(document.presentationAnchorIndex(for: 3) == 1)
        #expect(document.presentationAnchorIndex(for: 4) == 1)
        #expect(document.presentationAnchorIndex(for: 2) == 2)
        #expect(document.presentationAnchorIndex(for: -1) == nil)
        #expect(document.presentationAnchorIndex(for: 6) == nil)
        #expect(document.presentationGroups.flatMap(\.lineIndices).sorted() == Array(document.lines.indices))
    }

    @Test("A background row appearing first still maps to its actual lead")
    func backgroundBeforeLeadInSource() {
        let document = makeDocument([
            timedLine("Respuesta", start: 1000, end: 2500, role: "background", groupID: "a"),
            timedLine("Principal", start: 0, end: 3000, groupID: "a")
        ])
        #expect(document.presentationGroups.first?.id == 1)
        #expect(document.presentationGroups.first?.lineIndices == [1, 0])
        #expect(document.presentationAnchorIndex(for: 0) == 1)
        #expect(document.focusIndex(at: 1500) == 1)
        #expect(document.activeWordLineIndices(at: 1500) == [0, 1])
    }

    @Test("A late background from the previous group cannot steal a newer lead's focus")
    func lateBackgroundKeepsIndependentAnimation() {
        let document = makeDocument([
            timedLine("Primera", start: 0, end: 3000, groupID: "a"),
            timedLine("Siguiente", start: 5000, end: 10000, groupID: "b"),
            timedLine("Respuesta", start: 7000, end: 9000, role: "background", groupID: "a")
        ])
        #expect(document.focusIndex(at: 2500) == 0)
        #expect(document.focusIndex(at: 4500) == 0)
        #expect(document.focusIndex(at: 8000) == 1)
        #expect(document.focusIndex(at: 12000) == 1)
        #expect(document.activeWordLineIndices(at: 8000) == [1, 2])
        #expect(document.lines[2].words[0].progress(at: 8000) == 0.5)
    }

    @Test("Background-only groups remain visible with a stable timed anchor")
    func backgroundOnlyGroupsAreNotDropped() {
        let document = makeDocument([
            timedLine("Tardía", start: 3000, end: 4000, role: "background", groupID: "a"),
            timedLine("Temprana", start: 1000, end: 2500, role: "background", groupID: "a"),
            timedLine("Principal", start: 6000, end: 7000)
        ])
        #expect(document.presentationGroups.count == 2)
        #expect(document.presentationGroups[0].leadLineIndex == nil)
        #expect(document.presentationGroups[0].anchorLineIndex == 1)
        #expect(document.presentationGroups[0].lineIndices == [1, 0])
        #expect(document.presentationAnchorIndex(for: 0) == 1)
        #expect(document.focusIndex(at: 2000) == 1)
        #expect(document.focusIndex(at: 6500) == 2)
        #expect(document.activeWordLineIndices(at: 2000) == [1])
    }

    @Test("Shared agent or section does not group unrelated voices")
    func agentAndSectionAreNotImplicitGroupIDs() {
        let document = makeDocument([
            .init(startMS: 0, endMS: 1000, text: "Una", agent: "v1", section: "Verse"),
            .init(startMS: 1000, endMS: 2000, text: "Dos", agent: "v1", section: "Verse"),
            .init(startMS: 2000, endMS: 3000, text: "Tres", role: "background", agent: "v1", groupID: "b", section: "Verse")
        ])
        #expect(document.presentationGroups.map(\.lineIndices) == [[0], [1], [2]])
    }

    @Test("Additional lead rows sharing a provider group are preserved")
    func multipleLeadRowsAreNotDiscarded() {
        let document = makeDocument([
            .init(startMS: 0, endMS: 2000, text: "Una voz", agent: "v1", groupID: "a"),
            .init(startMS: 1000, endMS: 3000, text: "Otra voz", agent: "v2", groupID: "a"),
            .init(startMS: 1500, endMS: 2500, text: "Respuesta", role: "background", groupID: "a")
        ])
        #expect(document.presentationGroups.first?.leadLineIndex == 0)
        #expect(document.presentationGroups.first?.lineIndices == [0, 1, 2])
        #expect(document.presentationGroups.first?.backgroundLineIndices == [2])
    }

    private func makeDocument(_ lines: [ExperimentalLyricLine]) -> ExperimentalLyricsDocument {
        .init(provider: "fixture", instrumental: false, lines: lines)
    }

    private func timedLine(_ text: String, start: Double, end: Double,
                           role: String? = nil, groupID: String? = nil) -> ExperimentalLyricLine {
        .init(startMS: start, endMS: end, text: text,
              words: [.init(text: text, startMS: start, endMS: end)], role: role, groupID: groupID)
    }
}
