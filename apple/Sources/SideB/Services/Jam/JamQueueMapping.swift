import Foundation

/// Index bookkeeping between the Jam queue (every upcoming track, 0 = plays next) and the rows
/// mirrored into Side B's own queue (only the tracks that have a YouTube Music match).
/// "Row" always means a position among the upcoming mirrored rows (0 = plays next in the app).
/// Pure value logic so the translation of user edits into Jam indices can be tested on its own.
struct JamQueueMapping: Equatable {
    /// Jam indices of the matched tracks, ascending; `matchedJamIndices[row]` is that row's Jam index.
    private(set) var matchedJamIndices: [Int]
    private(set) var jamCount: Int

    /// `matched[i]` tells whether the Jam track at index `i` has a mirrored row.
    init(matched: [Bool]) {
        jamCount = matched.count
        matchedJamIndices = matched.enumerated().filter(\.element).map(\.offset)
    }

    var rowCount: Int { matchedJamIndices.count }

    func jamIndex(forRow row: Int) -> Int? {
        matchedJamIndices.indices.contains(row) ? matchedJamIndices[row] : nil
    }

    func row(forJamIndex index: Int) -> Int? {
        matchedJamIndices.firstIndex(of: index)
    }

    /// Jam index at which a track dropped before `row` must be inserted. A row at or past the end
    /// means "after everything".
    func insertionJamIndex(atRow row: Int) -> Int {
        guard row >= 0 else { return 0 }
        return jamIndex(forRow: row) ?? jamCount
    }

    /// Jam `move` for dragging the mirrored row `from` so that it ends at mirrored row `to`.
    /// The item takes the Jam slot of the row it displaces; unmatched tracks between keep their order.
    func move(fromRow from: Int, toRow to: Int) -> (from: Int, to: Int)? {
        guard from != to, let source = jamIndex(forRow: from), let target = jamIndex(forRow: to), source != target else { return nil }
        return (source, target)
    }

    /// Entry ids that survive reordering: the URI plus the number of earlier entries sharing it.
    static func entryIDs(for uris: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return uris.map { uri in
            let n = seen[uri, default: 0]
            seen[uri] = n + 1
            return "\(uri)#\(n)"
        }
    }
}

/// A change requested on the Jam queue. Spotify only acknowledges the request; whether it took
/// effect is decided by the next queue the plugin reports, via `isSatisfied`.
enum JamQueueEdit: Equatable {
    case add(uri: String)
    case insert(uri: String, index: Int)
    case move(from: Int, to: Int)
    case remove(index: Int)

    var action: String {
        switch self {
        case .add: "add"
        case .insert: "insert"
        case .move: "move"
        case .remove: "remove"
        }
    }

    /// Plugin command for this edit, built against the queue revision the indices refer to.
    func command(revision: String?, requestId: String) -> [String: Any] {
        var message: [String: Any] = ["type": "command", "action": action, "requestId": requestId]
        if let revision { message["revision"] = revision }
        switch self {
        case .add(let uri): message["uri"] = uri
        case .insert(let uri, let index): message["uri"] = uri; message["index"] = index
        case .move(let from, let to): message["from"] = from; message["to"] = to
        case .remove(let index): message["index"] = index
        }
        return message
    }

    /// False when the edit points outside `queue` (nothing is sent).
    func isValid(on queue: [String]) -> Bool {
        switch self {
        case .add(let uri): !uri.isEmpty
        case .insert(let uri, let index): !uri.isEmpty && (0...queue.count).contains(index)
        case .move(let from, let to): queue.indices.contains(from) && queue.indices.contains(to) && from != to
        case .remove(let index): queue.indices.contains(index)
        }
    }

    /// Whether `new` shows the effect of this edit applied to `old`. Deliberately tolerant of
    /// unrelated changes made by other participants in the meantime.
    func isSatisfied(old: [String], new: [String]) -> Bool {
        switch self {
        case .add(let uri):
            return count(of: uri, in: new) > count(of: uri, in: old)
        case .insert(let uri, let index):
            guard count(of: uri, in: new) > count(of: uri, in: old) else { return false }
            return new.indices.contains(index) ? new[index] == uri : new.last == uri
        case .move(let from, let to):
            guard old.indices.contains(from), new.indices.contains(to), new != old else { return false }
            return new[to] == old[from]
        case .remove(let index):
            guard old.indices.contains(index) else { return false }
            return count(of: old[index], in: new) < count(of: old[index], in: old)
        }
    }

    private func count(of uri: String, in list: [String]) -> Int { list.filter { $0 == uri }.count }
}
