import Foundation

/// Voice linkage controls focus, but a late background must not pull an interlude
/// backward past a newer phrase. Insert waits by vocal chronology, not voice owner.
struct ExperimentalLyricsDisplayItem: Identifiable {
    let id: String
    let ordinal: Int
    let group: ExperimentalLyricsPresentationGroup?
    let interlude: ExperimentalLyricsInterlude?

    static func sequence(document: ExperimentalLyricsDocument, duration: Double) -> [Self] {
        let milliseconds = duration.isFinite && duration > 0 ? duration * 1000 : nil
        let waits = document.interludes(durationMS: milliseconds)
        let groups = document.presentationGroups
        let starts = groups.map { group in
            group.leadLineIndex.flatMap { document.lines[$0].effectiveStartMS }
                ?? group.lineIndices.compactMap { document.lines[$0].effectiveStartMS }.min()
        }
        var insertions: [Int: [ExperimentalLyricsInterlude]] = [:]
        for wait in waits {
            let position: Int
            switch wait.kind {
            case .intro: position = 0
            case .outro: position = groups.count
            case .interlude:
                position = starts.firstIndex { start in start.map { $0 >= wait.endMS } ?? false } ?? groups.count
            }
            insertions[position, default: []].append(wait)
        }
        var result: [Self] = []
        for position in 0...groups.count {
            for wait in insertions[position] ?? [] {
                result.append(.init(id: wait.id, ordinal: position - 1, group: nil, interlude: wait))
            }
            if position < groups.count {
                let group = groups[position]
                result.append(.init(id: "line:\(group.anchorLineIndex)", ordinal: position, group: group, interlude: nil))
            }
        }
        return result
    }
}
