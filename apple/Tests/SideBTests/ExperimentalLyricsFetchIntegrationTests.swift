import Foundation
import SideBCore
import Testing
@testable import SideB

/// Exercise the actual UniFFI-record adapter; constructing a presentation model
/// directly would miss UInt64 optional conversion overloads in fetch.
enum ExperimentalLyricsFetchFixture {
    static let starts: [UInt64] = [3418, 5708, 7217, 8959, 10547, 219907]
    static let ends: [UInt64] = [6076, 8177, 9510, 10537, 12654, 221335]

    static func info(withWords: Bool) -> KaraokeLyricsInfo {
        let lines = starts.indices.map { index in
            let text = "Cue \(index)"
            return KaraokeLineInfo(
                timeMs: starts[index], endTimeMs: ends[index], text: text,
                words: withWords ? [KaraokeWordInfo(text: text, startMs: starts[index], endMs: ends[index])] : [],
                translation: index == 0 ? "Synthetic translation" : nil,
                role: index == 2 ? "background" : "lead", agent: "v\(index % 2)",
                groupId: "fixture:\(index)", section: "Synthetic section")
        }
        return KaraokeLyricsInfo(provider: "Synthetic numeric cues", isSynced: true, instrumental: false, lines: lines)
    }

    @MainActor
    static func document(withWords: Bool) async throws -> ExperimentalLyricsDocument {
        let request = ExperimentalLyricsRequest(playbackID: UUID(), sessionID: UUID(),
            videoID: "synthetic-cues", title: "Synthetic track", artist: "Fixture artist",
            album: nil, durationSeconds: 230)
        let result = try await ExperimentalLyricsController.fetch(request, forceRefresh: false,
            core: ExperimentalLyricsFetchCore(info: info(withWords: withWords)))
        return try #require(result)
    }
}

final class ExperimentalLyricsFetchCore: SideBCore, @unchecked Sendable {
    private let info: KaraokeLyricsInfo?

    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        info = nil
        super.init(unsafeFromRawPointer: pointer)
    }

    init(info: KaraokeLyricsInfo?) {
        self.info = info
        super.init(noPointer: .init())
    }

    override func getKaraokeLyrics(videoId: String, title: String, artist: String,
        album: String?, durationSecs: UInt64?, forceRefresh: Bool) async throws -> KaraokeLyricsInfo? {
        info
    }
}

@Suite("Letras experimentales: adaptación real de registros UInt64")
@MainActor
struct ExperimentalLyricsFetchIntegrationTests {
    @Test("Fetch conserva milisegundos numéricos, foco y seek con y sin palabras", arguments: [true, false])
    func numericTimingSurvivesFetch(withWords: Bool) async throws {
        let document = try await ExperimentalLyricsFetchFixture.document(withWords: withWords)
        #expect(document.lines.count == ExperimentalLyricsFetchFixture.starts.count)
        for index in document.lines.indices {
            let line = document.lines[index]
            let start = Double(ExperimentalLyricsFetchFixture.starts[index])
            let end = Double(ExperimentalLyricsFetchFixture.ends[index])
            #expect(line.startMS == start)
            #expect(line.endMS == end)
            #expect(line.effectiveStartMS == start)
            #expect(line.effectiveEndMS == end)
            #expect(line.hasWordTiming == withWords)
            #expect(line.groupID == "fixture:\(index)")
            #expect(line.agent == "v\(index % 2)")
            #expect(line.role == (index == 2 ? "background" : "lead"))
            #expect(line.section == "Synthetic section")
            if withWords {
                let word = try #require(line.words.first)
                #expect(word.startMS == start)
                #expect(word.endMS == end)
            } else {
                #expect(line.words.isEmpty)
            }
        }
        #expect(document.lines[0].translation == "Synthetic translation")
        #expect(document.focusIndex(at: 0) == 0)
        #expect(document.focusIndex(at: 9000) == 3)
        #expect(document.focusIndex(at: 220000) == 5)
        let laterCue = try #require(document.lines[5].effectiveStartMS)
        #expect(ExperimentalLyricsSeekTarget.audioSeconds(lineMS: laterCue, offsetMS: 0, duration: 230) == 219.907)
        let middleCue = try #require(document.lines[3].effectiveStartMS)
        #expect(ExperimentalLyricsSeekTarget.audioSeconds(lineMS: middleCue, offsetMS: 0, duration: 230) == 8.959)
    }

    @Test("Fetch distingue cero y ausencia sin inventar límites")
    func zeroAndMissingBounds() async throws {
        let makeLine: (UInt64?, UInt64?, String) -> KaraokeLineInfo = { start, end, text in
            KaraokeLineInfo(timeMs: start, endTimeMs: end, text: text, words: [], translation: nil,
                role: nil, agent: nil, groupId: nil, section: nil)
        }
        let core = ExperimentalLyricsFetchCore(info: KaraokeLyricsInfo(provider: "Synthetic edge cues",
            isSynced: true, instrumental: false, lines: [
                makeLine(0, 1000, "Zero cue"),
                makeLine(1000, nil, "Unknown end"),
                makeLine(nil, 0, "Zero end without start"),
                makeLine(nil, nil, "Untimed text")
            ]))
        let request = ExperimentalLyricsRequest(playbackID: UUID(), sessionID: UUID(), videoID: "synthetic-edges",
            title: "Synthetic edges", artist: "Fixture artist", album: nil, durationSeconds: nil)
        let result = try await ExperimentalLyricsController.fetch(request, forceRefresh: true, core: core)
        let document = try #require(result)
        #expect(document.lines[0].startMS == 0)
        #expect(document.lines[0].endMS == 1000)
        #expect(document.lines[0].effectiveEndMS == 1000)
        #expect(document.lines[1].startMS == 1000)
        #expect(document.lines[1].endMS == nil)
        #expect(document.lines[1].effectiveEndMS == nil)
        #expect(document.lines[2].startMS == nil)
        #expect(document.lines[2].endMS == 0)
        #expect(document.lines[2].effectiveEndMS == nil)
        #expect(document.lines[3].startMS == nil && document.lines[3].endMS == nil)
        #expect(document.focusIndex(at: 0) == 0)
        #expect(document.focusIndex(at: 1000) == 1)
    }
}
