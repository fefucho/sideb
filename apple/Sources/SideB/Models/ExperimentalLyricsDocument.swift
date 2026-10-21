import Foundation

/// Presentation-only, independent of the classic lyrics records and their cache.
struct ExperimentalLyricWord: Equatable, Sendable {
    let text: String
    let startMS: Double
    let endMS: Double

    var isValid: Bool {
        !text.isEmpty && startMS.isFinite && endMS.isFinite && startMS >= 0 && endMS > startMS
    }

    func progress(at timeMS: Double) -> Double {
        guard isValid, timeMS.isFinite else { return 0 }
        return min(1, max(0, (timeMS - startMS) / (endMS - startMS)))
    }
}

struct ExperimentalLyricSegment: Equatable, Sendable {
    let text: String
    let wordIndex: Int?
}

struct ExperimentalLyricLine: Equatable, Sendable {
    let startMS: Double?
    let endMS: Double?
    let text: String
    let words: [ExperimentalLyricWord]
    let translation: String?
    /// Provider metadata is kept verbatim. Parentheses alone never establish a voice role.
    let role: String?
    let agent: String?
    let groupID: String?
    let section: String?
    /// Prepared once, never by the animation frame. Nil means honest line-level fallback.
    let karaokeSegments: [ExperimentalLyricSegment]?
    let effectiveStartMS: Double?
    let effectiveEndMS: Double?

    init(startMS: Double?, endMS: Double?, text: String,
         words: [ExperimentalLyricWord] = [], translation: String? = nil,
         role: String? = nil, agent: String? = nil, groupID: String? = nil,
         section: String? = nil) {
        self.startMS = startMS.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.endMS = endMS.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.text = text
        self.words = words
        self.translation = translation
        self.role = role
        self.agent = agent
        self.groupID = groupID
        self.section = section
        self.karaokeSegments = Self.reconcile(text: text, words: words)
        // Frame sampling must not filter/map every word in the entire document.
        let validWords = words.filter(\.isValid)
        let effectiveStart = self.startMS ?? validWords.map(\.startMS).min()
        self.effectiveStartMS = effectiveStart
        if let effectiveStart {
            self.effectiveEndMS = [self.endMS, validWords.map(\.endMS).max()]
                .compactMap { $0 }.filter { $0 > effectiveStart }.max()
        } else {
            self.effectiveEndMS = nil
        }
    }

    var isBackground: Bool {
        role?.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("background") == .orderedSame
    }

    var hasWordTiming: Bool { karaokeSegments != nil }

    func contains(timeMS: Double) -> Bool {
        guard timeMS.isFinite, let start = effectiveStartMS, let end = effectiveEndMS else { return false }
        return timeMS >= start && timeMS < end
    }

    func hasChangingWord(at timeMS: Double) -> Bool {
        hasWordTiming && words.contains { $0.isValid && timeMS >= $0.startMS && timeMS < $0.endMS }
    }

    /// Permit omitted spaces between provider words, but never discard or invent lyric text.
    /// A mismatch (including punctuation or incompatible edits) uses the original full line.
    private static func reconcile(text: String, words: [ExperimentalLyricWord]) -> [ExperimentalLyricSegment]? {
        guard !words.isEmpty, words.allSatisfy(\.isValid) else { return nil }
        var previousStart = -Double.infinity
        var cursor = text.startIndex
        var segments: [ExperimentalLyricSegment] = []
        for (index, word) in words.enumerated() {
            guard word.startMS >= previousStart,
                  let range = text.range(of: word.text, range: cursor..<text.endIndex) else { return nil }
            let gap = String(text[cursor..<range.lowerBound])
            guard gap.allSatisfy(\.isWhitespace) else { return nil }
            if !gap.isEmpty { segments.append(.init(text: gap, wordIndex: nil)) }
            segments.append(.init(text: String(text[range]), wordIndex: index))
            cursor = range.upperBound
            previousStart = word.startMS
        }
        let trailing = String(text[cursor...])
        guard trailing.allSatisfy(\.isWhitespace) else { return nil }
        if !trailing.isEmpty { segments.append(.init(text: trailing, wordIndex: nil)) }
        return segments
    }
}

enum ExperimentalLyricsInterludeKind: String, Equatable, Sendable {
    case intro
    case interlude
    case outro
}

/// A proven gap in all known voices. Times use the document's unshifted media timeline;
/// playback and the user's offset are applied by the clock before querying this value.
struct ExperimentalLyricsInterlude: Identifiable, Equatable, Sendable {
    let startMS: Double
    let endMS: Double
    let kind: ExperimentalLyricsInterludeKind
    /// The preceding vocal group's anchor; an intro has no preceding lyric.
    let anchorLineIndex: Int?

    /// Bit patterns keep identity deterministic across recomputation and locales.
    var id: String {
        "\(kind.rawValue):\(String(startMS.bitPattern, radix: 16)):\(String(endMS.bitPattern, radix: 16)):\(anchorLineIndex.map(String.init) ?? "intro")"
    }

    func progress(at timeMS: Double) -> Double {
        guard timeMS.isFinite, startMS.isFinite, endMS.isFinite,
              startMS >= 0, endMS > startMS else { return 0 }
        return min(1, max(0, (timeMS - startMS) / (endMS - startMS)))
    }

    func contains(timeMS: Double) -> Bool {
        timeMS.isFinite && startMS.isFinite && endMS.isFinite && startMS >= 0 &&
            endMS > startMS && timeMS >= startMS && timeMS < endMS
    }
}

/// Explicit provider groups keep background voices beside their lead while retaining
/// every source row and its independent word times. Ungrouped rows remain separate.
struct ExperimentalLyricsPresentationGroup: Identifiable, Equatable, Sendable {
    let id: Int
    let leadLineIndex: Int?
    let backgroundLineIndices: [Int]
    let lineIndices: [Int]
    let anchorLineIndex: Int
}

struct ExperimentalLyricsDocument: Equatable, Sendable {
    let provider: String
    let instrumental: Bool
    let lines: [ExperimentalLyricLine]
    let presentationGroups: [ExperimentalLyricsPresentationGroup]
    private let presentationAnchors: [Int]

    init(provider: String, instrumental: Bool, lines: [ExperimentalLyricLine]) {
        self.provider = provider
        self.instrumental = instrumental
        self.lines = lines
        self.presentationGroups = Self.makePresentationGroups(lines: lines)
        var anchors = Array(lines.indices)
        for group in presentationGroups {
            for index in group.lineIndices { anchors[index] = group.anchorLineIndex }
        }
        self.presentationAnchors = anchors
    }

    var hasWordTimings: Bool { lines.contains(where: \.hasWordTiming) }
    var hasLineTimings: Bool { lines.contains { $0.effectiveStartMS != nil } }
    var hasTranslations: Bool { lines.contains { !($0.translation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) } }

    func presentationAnchorIndex(for lineIndex: Int) -> Int? {
        guard presentationAnchors.indices.contains(lineIndex) else { return nil }
        return presentationAnchors[lineIndex]
    }

    /// A group's lead owns scroll focus. Its later background entries cannot move focus
    /// back from a newer lead, although every voice keeps animating on its own timestamps.
    /// Follow focus can persist through gaps; word fill only advances inside its own times.
    func focusIndex(at timeMS: Double) -> Int? {
        guard timeMS.isFinite else { return nil }
        var first: (index: Int, time: Double)?
        var latest: (index: Int, time: Double)?
        for group in presentationGroups {
            let leadStart = group.leadLineIndex.flatMap { lines[$0].effectiveStartMS }
            guard let start = leadStart ?? group.lineIndices.compactMap({ lines[$0].effectiveStartMS }).min() else { continue }
            let index = group.anchorLineIndex
            if first == nil || start < first!.time { first = (index, start) }
            if start <= timeMS && (latest == nil || start >= latest!.time) { latest = (index, start) }
        }
        return latest?.index ?? first?.index
    }

    func activeWordLineIndices(at timeMS: Double) -> Set<Int> {
        Set(lines.indices.filter { lines[$0].hasWordTiming && lines[$0].contains(timeMS: timeMS) })
    }

    /// Infer waits only where vocal coverage is known. Complete reconciled word timing
    /// is more precise than a padded provider line end. Otherwise an explicit line end
    /// is required: a following line's start never stands in for a missing end.
    ///
    /// Missing bounds are uncertainty barriers, not silence: an unknown end blocks from
    /// the supplied start onward; an unknown start blocks through the supplied end;
    /// entirely untimed vocal text prevents inference. This intentionally omits some
    /// possible waits rather than displaying dots while an unbounded voice may sing.
    func interludes(durationMS: Double?, minimumGapMS: Double = 5000) -> [ExperimentalLyricsInterlude] {
        guard !instrumental, minimumGapMS.isFinite, minimumGapMS >= 0 else { return [] }
        var coverage: [VocalCoverage] = []
        for (index, line) in lines.enumerated() {
            let hasVocalText = !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                line.words.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard hasVocalText else { continue }
            let validWords = line.words.filter(\.isValid)
            coverage.append(contentsOf: validWords.map {
                VocalCoverage(startMS: $0.startMS, endMS: $0.endMS, lineIndex: index)
            })
            if line.hasWordTiming { continue }

            if let start = line.startMS, let end = line.endMS, end > start {
                coverage.append(.init(startMS: start, endMS: end, lineIndex: index))
            } else if let start = line.startMS {
                coverage.append(.init(startMS: start, endMS: .infinity, lineIndex: index))
            } else if let end = line.endMS, end > 0 {
                coverage.append(.init(startMS: 0, endMS: end, lineIndex: index))
            } else {
                return []
            }
        }
        guard !coverage.isEmpty else { return [] }
        coverage.sort {
            if $0.startMS != $1.startMS { return $0.startMS < $1.startMS }
            if $0.endMS != $1.endMS { return $0.endMS > $1.endMS }
            return $0.lineIndex < $1.lineIndex
        }
        var merged: [VocalCoverage] = []
        for interval in coverage {
            if let previous = merged.last, interval.startMS <= previous.endMS {
                if interval.endMS > previous.endMS {
                    merged[merged.count - 1] = .init(startMS: previous.startMS, endMS: interval.endMS,
                                                   lineIndex: interval.lineIndex)
                }
            } else {
                merged.append(interval)
            }
        }

        var result: [ExperimentalLyricsInterlude] = []
        func append(start: Double, end: Double, kind: ExperimentalLyricsInterludeKind, anchor: Int?) {
            guard start.isFinite, end.isFinite, end > start, end - start >= minimumGapMS else { return }
            result.append(.init(startMS: start, endMS: end, kind: kind, anchorLineIndex: anchor))
        }
        if let first = merged.first { append(start: 0, end: first.startMS, kind: .intro, anchor: nil) }
        for (previous, next) in zip(merged, merged.dropFirst()) {
            append(start: previous.endMS, end: next.startMS, kind: .interlude,
                   anchor: presentationAnchorIndex(for: previous.lineIndex))
        }
        if let durationMS, durationMS.isFinite, durationMS > 0, let last = merged.last {
            append(start: last.endMS, end: durationMS, kind: .outro,
                   anchor: presentationAnchorIndex(for: last.lineIndex))
        }
        return result
    }

    private struct VocalCoverage {
        let startMS: Double
        let endMS: Double
        let lineIndex: Int
    }

    private static func makePresentationGroups(lines: [ExperimentalLyricLine]) -> [ExperimentalLyricsPresentationGroup] {
        var memberships: [[Int]] = []
        var grouped: [String: Int] = [:]
        for (index, line) in lines.enumerated() {
            if let groupID = line.groupID, !groupID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let groupIndex = grouped[groupID] {
                    memberships[groupIndex].append(index)
                } else {
                    grouped[groupID] = memberships.count
                    memberships.append([index])
                }
            } else {
                memberships.append([index])
            }
        }
        return memberships.map { members in
            let leads = members.filter { !lines[$0].isBackground }
            let backgrounds = members.filter { lines[$0].isBackground }.sorted {
                let firstTime = lines[$0].effectiveStartMS ?? .infinity
                let secondTime = lines[$1].effectiveStartMS ?? .infinity
                return firstTime != secondTime ? firstTime < secondTime : $0 < $1
            }
            let anchor = leads.first ?? backgrounds[0]
            return .init(id: anchor, leadLineIndex: leads.first,
                         backgroundLineIndices: backgrounds, lineIndices: leads + backgrounds,
                         anchorLineIndex: anchor)
        }
    }
}
