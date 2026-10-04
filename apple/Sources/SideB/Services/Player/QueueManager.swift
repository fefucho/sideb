import SwiftUI
import SideBCore

// MARK: - Queue ordering metadata

public enum QueuePlacement: Codable, Equatable {
    case after(String)
    case before(String)
    case end
}

public struct QueueOrderSnapshot: Codable, Equatable {
    public var occurrenceIDs: [String]
    public var sourceRanks: [String: Int]
    public var placements: [String: QueuePlacement]
    public var currentOccurrenceID: String?
    public var visibleCount: Int
    public var nextSourceRank: Int

    public init(occurrenceIDs: [String], sourceRanks: [String: Int],
                placements: [String: QueuePlacement], currentOccurrenceID: String?,
                visibleCount: Int, nextSourceRank: Int) {
        self.occurrenceIDs = occurrenceIDs
        self.sourceRanks = sourceRanks
        self.placements = placements
        self.currentOccurrenceID = currentOccurrenceID
        self.visibleCount = visibleCount
        self.nextSourceRank = nextSourceRank
    }
}

// MARK: - QueueContext

/// Describe el origen y naturaleza de la cola activa de reproducción.
public enum QueueContext: Equatable {
    case radio(seedVideoId: String, title: String, seedName: String)
    case album(browseId: String, title: String)
    case playlist(browseId: String, title: String)
    case custom(title: String)

    public var iconName: String {
        switch self {
        case .radio: return "dot.radiowaves.left.and.right"
        case .album: return "record.circle"
        case .playlist: return "music.note.list"
        case .custom: return "list.bullet"
        }
    }
}

// MARK: - QueueManager

@MainActor
@Observable
public final class QueueManager {
    private static let playlistBatchSize = 100
    private static let playlistRefillThreshold = 10

    public private(set) var occurrenceIDs: [String] = []
    private var sourceRanks: [String: Int] = [:]
    private var nextSourceRank = 0
    private var placements: [String: QueuePlacement] = [:]
    private var visibleCount = 0
    private var mutationDepth = 0
    private var pendingNotification = false

    // MARK: - Estado de Cola
    public var onStateChange: (() -> Void)?
    public private(set) var queue: [SongItemRecord] = [] { didSet { stateChanged() } }
    public private(set) var currentIndex: Int = 0 { didSet { stateChanged() } }
    public var context: QueueContext? = nil { didSet { stateChanged() } }
    public var contextTitle: String = "Cola de reproducción" { didSet { stateChanged() } }
    public var radioSeed: String? = nil { didSet { stateChanged() } }
    public var continuationToken: String? = nil
    public private(set) var queueToken: UUID = UUID()

    // MARK: - Modos y Banderas
    public private(set) var isShuffle: Bool = false { didSet { stateChanged() } }
    public var isRepeat: Bool = false { didSet { stateChanged() } }
    public var isLoadingRadio: Bool = false
    public var isLoadingAutoplay: Bool = false

    public init() {}

    public var orderSnapshot: QueueOrderSnapshot {
        QueueOrderSnapshot(occurrenceIDs: occurrenceIDs, sourceRanks: sourceRanks,
                           placements: placements, currentOccurrenceID: currentOccurrenceID,
                           visibleCount: visibleCount, nextSourceRank: nextSourceRank)
    }

    public var currentOccurrenceID: String? {
        guard queue.indices.contains(currentIndex), occurrenceIDs.indices.contains(currentIndex) else { return nil }
        return occurrenceIDs[currentIndex]
    }

    public func toggleShuffle() { setShuffle(!isShuffle) }

    /// Cambia el orden sin reemplazar la cola ni perder la identidad de la actual.
    public func setShuffle(_ enabled: Bool, seed: UInt64? = nil) {
        guard enabled != isShuffle else { return }
        beginMutation(); defer { endMutation() }
        if enabled {
            isShuffle = true
            shufflePendingSource(seed: seed ?? Self.randomSeed())
        } else {
            isShuffle = false
            restoreSourceOrder()
        }
    }

    // MARK: - Propiedades Computadas

    /// Cola publicada a la interfaz. La cola autoritativa completa permanece en `queue`.
    public var tracks: [SongItemRecord] { Array(queue.prefix(visibleCount)) }

    public var currentTrack: SongItemRecord? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    public var upNextTracks: [SongItemRecord] {
        guard currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }

    public var previousTracks: [SongItemRecord] {
        guard currentIndex > 0, !queue.isEmpty else { return [] }
        return Array(queue[0..<currentIndex])
    }

    public var hasNext: Bool { isRepeat ? !queue.isEmpty : currentIndex < queue.count - 1 }
    public var hasPrevious: Bool { currentIndex > 0 }

    /// Indica si la reproducción se acerca al final de la cola activa (<= 2 pistas restantes)
    public var isNearTail: Bool {
        guard !queue.isEmpty else { return false }
        return (queue.count - 1 - currentIndex) <= 2
    }

    @discardableResult
    public func syncCurrentIndex(for videoId: String) -> Int? {
        if queue.indices.contains(currentIndex), queue[currentIndex].videoId == videoId {
            beginMutation(); defer { endMutation() }
            extendVisibleBatch()
            return currentIndex
        }
        guard let idx = queue.firstIndex(where: { $0.videoId == videoId }) else { return nil }
        beginMutation(); defer { endMutation() }
        currentIndex = idx
        extendVisibleBatch()
        return idx
    }

    // MARK: - Métodos de Ciclo de Vida y Reemplazo de Cola

    /// Reemplaza la cola previa de forma atómica con un nuevo lote de temas y contexto.
    public func replaceQueue(
        with items: [SongItemRecord],
        startingAt index: Int = 0,
        context: QueueContext? = nil,
        contextTitle: String? = nil,
        radioSeed: String? = nil,
        continuation: String? = nil,
        shuffle: Bool = false,
        shuffleSeed: UInt64? = nil
    ) {
        beginMutation(); defer { endMutation() }
        queueToken = UUID()
        queue = items
        occurrenceIDs = items.map { _ in UUID().uuidString }
        sourceRanks = Dictionary(uniqueKeysWithValues: occurrenceIDs.enumerated().map { ($0.element, $0.offset) })
        nextSourceRank = items.count
        placements.removeAll(keepingCapacity: true)
        currentIndex = items.isEmpty ? 0 : max(0, min(items.count - 1, index))
        self.context = context
        if let title = contextTitle { self.contextTitle = title }
        else {
            switch context {
            case .radio(_, let title, _): self.contextTitle = title
            case .album(_, let title): self.contextTitle = "Álbum: \(title)"
            case .playlist(_, let title): self.contextTitle = "Lista: \(title)"
            case .custom(let title): self.contextTitle = title
            case .none: self.contextTitle = "Cola de reproducción"
            }
        }
        self.radioSeed = radioSeed
        continuationToken = continuation
        isShuffle = shuffle
        visibleCount = initialVisibleCount(for: currentIndex)
        if shuffle, !items.isEmpty {
            // Initial shuffle chooses across the complete source. No entries are treated as history.
            var rng = ShuffleRandom(seed: shuffleSeed ?? Self.randomSeed())
            let first = rng.index(upperBound: queue.count)
            if first != 0 {
                queue.swapAt(0, first)
                occurrenceIDs.swapAt(0, first)
            }
            currentIndex = 0
            shuffleSuffix(after: 0, using: &rng)
            visibleCount = initialVisibleCount(for: 0)
        }
    }

    /// Restores metadata v2 over the separately persisted songs. A nil snapshot means a legacy save.
    @discardableResult
    public func restoreOrder(_ snapshot: QueueOrderSnapshot?, isShuffle: Bool) -> Bool {
        beginMutation(); defer { endMutation() }
        if let snapshot {
            guard validate(snapshot) else { return false }
            occurrenceIDs = snapshot.occurrenceIDs
            sourceRanks = snapshot.sourceRanks
            placements = snapshot.placements
            nextSourceRank = snapshot.nextSourceRank
            visibleCount = snapshot.visibleCount
            currentIndex = snapshot.currentOccurrenceID.flatMap { snapshot.occurrenceIDs.firstIndex(of: $0) } ?? 0
        } else {
            occurrenceIDs = queue.map { _ in UUID().uuidString }
            if isShuffle {
                // A legacy shuffled array has no defensible canonical ranks.
                sourceRanks.removeAll(keepingCapacity: true)
                placements = Dictionary(uniqueKeysWithValues: occurrenceIDs.map { ($0, .end) })
                nextSourceRank = 0
            } else {
                sourceRanks = Dictionary(uniqueKeysWithValues: occurrenceIDs.enumerated().map { ($0.element, $0.offset) })
                placements.removeAll(keepingCapacity: true)
                nextSourceRank = queue.count
            }
            visibleCount = initialVisibleCount(for: currentIndex)
        }
        self.isShuffle = isShuffle
        if !isShuffle { restoreSourceOrder() }
        return true
    }

    /// Añade temas recomendados de radio o automix deduplicando contra la cola y el lote.
    public func appendRadioTracks(_ tracks: [SongItemRecord], continuation: String? = nil) {
        beginMutation(); defer { endMutation() }
        var known = Set(queue.map(\.videoId))
        let fresh = tracks.filter { known.insert($0.videoId).inserted }
        appendSourceItems(fresh)
        if let continuation { continuationToken = continuation }
    }

    /// Añade ocurrencias de playlist preservando duplicados y el orden de origen.
    public func appendPlaylistTracks(_ tracks: [SongItemRecord], nextContinuation: String? = nil) {
        beginMutation(); defer { endMutation() }
        appendSourceItems(tracks)
        continuationToken = nextContinuation
        if isShuffle { shufflePendingSource(seed: Self.randomSeed()) }
        else { restoreSourceOrder() }
    }

    /// Completes a partially loaded source without replacing occurrences, manual placements or playback.
    func completePlaylistSource(_ remaining: [SongItemRecord]) {
        appendPlaylistTracks(remaining, nextContinuation: nil)
    }

    public func playNext(_ track: SongItemRecord) { playNext([track]) }

    public func playNext(_ tracks: [SongItemRecord]) {
        guard !tracks.isEmpty else { return }
        if queue.isEmpty {
            replaceManualQueue(with: tracks)
            return
        }
        beginMutation(); defer { endMutation() }
        let insertIndex = min(currentIndex + 1, queue.count)
        let anchor = currentOccurrenceID
        queue.insert(contentsOf: tracks, at: insertIndex)
        let ids = tracks.map { _ in UUID().uuidString }
        occurrenceIDs.insert(contentsOf: ids, at: insertIndex)
        var placementAnchor = anchor
        for id in ids {
            placements[id] = placementAnchor.map(QueuePlacement.after) ?? .end
            placementAnchor = id
        }
        if context == nil { context = .custom(title: "Cola manual") }
        visibleCount = min(queue.count, max(visibleCount + tracks.count, insertIndex + tracks.count))
    }

    public func addTrackToQueue(_ track: SongItemRecord) { addTracksToQueue([track]) }

    public func addTracksToQueue(_ tracks: [SongItemRecord]) {
        guard !tracks.isEmpty else { return }
        if queue.isEmpty {
            replaceManualQueue(with: tracks)
            return
        }
        beginMutation(); defer { endMutation() }
        appendManualItems(tracks)
        visibleCount = queue.count
    }

    @discardableResult
    public func removeTrack(at index: Int) -> SongItemRecord? {
        guard queue.indices.contains(index) else { return nil }
        beginMutation(); defer { endMutation() }
        let removedID = occurrenceIDs[index]
        detachDependents(of: removedID)
        let removed = queue.remove(at: index)
        occurrenceIDs.remove(at: index)
        sourceRanks.removeValue(forKey: removedID)
        placements.removeValue(forKey: removedID)
        if index < visibleCount { visibleCount -= 1 }
        if index < currentIndex { currentIndex -= 1 }
        else if currentIndex >= queue.count { currentIndex = max(0, queue.count - 1) }
        extendVisibleBatch()
        return removed
    }

    @discardableResult
    public func removeTrack(videoId: String) -> SongItemRecord? {
        guard let index = queue.firstIndex(where: { $0.videoId == videoId }) else { return nil }
        return removeTrack(at: index)
    }

    public func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard queue.indices.contains(sourceIndex), queue.indices.contains(destinationIndex), sourceIndex != destinationIndex else { return }
        beginMutation(); defer { endMutation() }
        let id = occurrenceIDs[sourceIndex]
        let activeID = currentOccurrenceID
        let item = queue.remove(at: sourceIndex)
        let occurrence = occurrenceIDs.remove(at: sourceIndex)
        queue.insert(item, at: destinationIndex)
        occurrenceIDs.insert(occurrence, at: destinationIndex)
        let targetID = occurrenceIDs.dropFirst(destinationIndex + 1).first
        if let targetID, anchorChainReaches(targetID, target: id) { detachDependents(of: id) }
        sourceRanks.removeValue(forKey: id)
        placements[id] = targetID.map(QueuePlacement.before) ?? .end
        if targetID == nil { visibleCount = queue.count }
        currentIndex = activeID.flatMap { occurrenceIDs.firstIndex(of: $0) } ?? 0
    }

    public func clearQueue() {
        beginMutation(); defer { endMutation() }
        queue.removeAll(); occurrenceIDs.removeAll(); sourceRanks.removeAll(); placements.removeAll()
        nextSourceRank = 0; visibleCount = 0; currentIndex = 0
        queueToken = UUID()
        context = nil; contextTitle = "Cola de reproducción"; radioSeed = nil; continuationToken = nil
        isShuffle = false
    }

    // MARK: - Compatibilidad Legada

    @available(*, deprecated, renamed: "replaceQueue(with:startingAt:)")
    public func setQueue(_ items: [SongItemRecord], startingAt index: Int = 0) { replaceQueue(with: items, startingAt: index) }

    @available(*, deprecated, renamed: "appendRadioTracks(_:)")
    public func appendTracks(_ tracks: [SongItemRecord]) { appendRadioTracks(tracks) }

    // MARK: - Navegación entre Pistas

    public func nextTrack(isManualSkip: Bool = false) -> SongItemRecord? {
        if isRepeat && !isManualSkip { return currentTrack }
        guard currentIndex + 1 < queue.count else {
            if isRepeat && !queue.isEmpty {
                beginMutation(); defer { endMutation() }
                currentIndex = 0
                extendVisibleBatch()
                return queue[0]
            }
            return nil
        }
        beginMutation(); defer { endMutation() }
        currentIndex += 1
        extendVisibleBatch()
        return queue[currentIndex]
    }

    public func previousTrack() -> SongItemRecord? {
        guard currentIndex > 0 else { return nil }
        beginMutation(); defer { endMutation() }
        currentIndex -= 1
        extendVisibleBatch()
        return queue[currentIndex]
    }

    public func selectTrack(at index: Int) -> SongItemRecord? {
        guard queue.indices.contains(index) else { return nil }
        beginMutation(); defer { endMutation() }
        currentIndex = index
        extendVisibleBatch()
        return queue[currentIndex]
    }

    // MARK: - Ordering implementation

    private func initialVisibleCount(for index: Int) -> Int {
        guard case .playlist(_, _)? = context else { return queue.count }
        return min(queue.count, max(0, index).saturatingAdd(Self.playlistBatchSize))
    }

    private func extendVisibleBatch() {
        guard case .playlist(_, _)? = context,
              currentIndex + Self.playlistRefillThreshold + 1 >= visibleCount else { return }
        let nextVisibleCount = min(queue.count, max(visibleCount + Self.playlistBatchSize, currentIndex + 1))
        guard nextVisibleCount != visibleCount else { return }
        visibleCount = nextVisibleCount
        stateChanged()
    }

    private func appendSourceItems(_ items: [SongItemRecord]) {
        guard !items.isEmpty else { return }
        let ids = items.map { _ in UUID().uuidString }
        queue.append(contentsOf: items)
        occurrenceIDs.append(contentsOf: ids)
        for id in ids { sourceRanks[id] = nextSourceRank; nextSourceRank += 1 }
        if context == nil { visibleCount = queue.count }
        else if case .playlist(_, _)? = context {
            visibleCount = min(queue.count, max(visibleCount, currentIndex.saturatingAdd(Self.playlistBatchSize)))
        } else { visibleCount = queue.count }
    }

    private func replaceManualQueue(with items: [SongItemRecord]) {
        beginMutation(); defer { endMutation() }
        replaceQueue(with: items, context: .custom(title: "Cola manual"))
        sourceRanks.removeAll(keepingCapacity: true)
        nextSourceRank = 0
        var anchor: String?
        for id in occurrenceIDs {
            placements[id] = anchor.map(QueuePlacement.after) ?? .end
            anchor = id
        }
    }

    private func appendManualItems(_ items: [SongItemRecord]) {
        let ids = items.map { _ in UUID().uuidString }
        queue.append(contentsOf: items); occurrenceIDs.append(contentsOf: ids)
        var anchor: String?
        for id in ids {
            placements[id] = anchor.map(QueuePlacement.after) ?? .end
            anchor = id
        }
    }

    private func shufflePendingSource(seed: UInt64) {
        guard queue.indices.contains(currentIndex) else { return }
        var rng = ShuffleRandom(seed: seed)
        shuffleSuffix(after: currentIndex, using: &rng)
    }

    private func shuffleSuffix(after index: Int, using rng: inout ShuffleRandom) {
        guard index + 1 < queue.count else { return }
        let positions = ((index + 1)..<queue.count).filter { sourceRanks[occurrenceIDs[$0]] != nil }
        guard positions.count > 1 else { return }
        var order = positions.map { ($0, queue[$0], occurrenceIDs[$0]) }
        for i in stride(from: order.count - 1, through: 1, by: -1) {
            order.swapAt(i, rng.index(upperBound: i + 1))
        }
        for (slot, item) in zip(positions, order) {
            queue[slot] = item.1; occurrenceIDs[slot] = item.2
        }
    }

    private func restoreSourceOrder() {
        guard !queue.isEmpty else { return }
        let oldIDs = occurrenceIDs
        let activeID = currentOccurrenceID
        let visibleExplicit = Set(occurrenceIDs.prefix(visibleCount).filter { placements[$0] != nil })
        let known = Set(occurrenceIDs)
        let sources = occurrenceIDs.filter { sourceRanks[$0] != nil }.sorted { sourceRanks[$0, default: 0] < sourceRanks[$1, default: 0] }
        var before: [String: [String]] = [:]
        var after: [String: [String]] = [:]
        var end: [String] = []
        for id in oldIDs where sourceRanks[id] == nil {
            switch placements[id] {
            case .before(let anchor) where known.contains(anchor): before[anchor, default: []].append(id)
            case .after(let anchor) where known.contains(anchor): after[anchor, default: []].append(id)
            default: end.append(id)
            }
        }
        var ordered: [String] = []; ordered.reserveCapacity(oldIDs.count)
        var emitted = Set<String>()
        for root in sources + end { Self.project(root, before: before, after: after, emitted: &emitted, result: &ordered) }
        for id in oldIDs where emitted.insert(id).inserted { ordered.append(id) }
        if ordered != oldIDs {
            let itemsByID = Dictionary(uniqueKeysWithValues: zip(oldIDs, queue))
            queue = ordered.compactMap { itemsByID[$0] }
            occurrenceIDs = ordered
        }
        currentIndex = activeID.flatMap { occurrenceIDs.firstIndex(of: $0) } ?? 0
        visibleCount = min(queue.count, max(visibleCount, currentIndex.saturatingAdd(Self.playlistBatchSize)))
        if let lastVisibleExplicit = occurrenceIDs.lastIndex(where: { visibleExplicit.contains($0) }) {
            visibleCount = max(visibleCount, lastVisibleExplicit + 1)
        }
    }

    /// Iterative depth-first projection avoids recursion limits for long manual chains.
    private static func project(_ root: String, before: [String: [String]], after: [String: [String]],
                                emitted: inout Set<String>, result: inout [String]) {
        enum Visit { case enter(String), emit(String), leave(String) }
        var stack: [Visit] = [.enter(root)]
        var visiting = Set<String>()
        while let visit = stack.popLast() {
            switch visit {
            case .enter(let id):
                guard !emitted.contains(id), visiting.insert(id).inserted else { continue }
                stack.append(.leave(id))
                if let children = after[id] {
                    for child in children.reversed() { stack.append(.enter(child)) }
                }
                stack.append(.emit(id))
                if let children = before[id] {
                    for child in children.reversed() { stack.append(.enter(child)) }
                }
            case .emit(let id):
                if emitted.insert(id).inserted { result.append(id) }
            case .leave(let id):
                visiting.remove(id)
            }
        }
    }

    private func detachDependents(of id: String) {
        let inherited = placements[id]
        let rank = sourceRanks[id]
        let ranked = sourceRanks.filter { $0.key != id }
        let predecessor = rank.flatMap { r in ranked.filter { $0.value < r }.max(by: { $0.value < $1.value })?.key }
        let successor = rank.flatMap { r in ranked.filter { $0.value > r }.min(by: { $0.value < $1.value })?.key }
        for key in Array(placements.keys) {
            guard let placement = placements[key] else { continue }
            let isAfter: Bool
            switch placement { case .after(let anchor) where anchor == id: isAfter = true
            case .before(let anchor) where anchor == id: isAfter = false
            default: continue }
            if let inherited { placements[key] = inherited }
            else if isAfter { placements[key] = predecessor.map(QueuePlacement.after) ?? successor.map(QueuePlacement.before) ?? .end }
            else { placements[key] = successor.map(QueuePlacement.before) ?? predecessor.map(QueuePlacement.after) ?? .end }
        }
    }

    private func anchorChainReaches(_ start: String, target: String) -> Bool {
        var id = start; var seen = Set<String>()
        while seen.insert(id).inserted {
            if id == target { return true }
            switch placements[id] { case .after(let a), .before(let a): id = a; default: return false }
        }
        return false
    }

    private func validate(_ snapshot: QueueOrderSnapshot) -> Bool {
        let ids = snapshot.occurrenceIDs
        let known = Set(ids)
        guard ids.count == queue.count, known.count == ids.count,
              !ids.contains(where: \.isEmpty),
              snapshot.visibleCount >= 0, snapshot.visibleCount <= ids.count,
              snapshot.nextSourceRank >= 0,
              (queue.isEmpty ? snapshot.currentOccurrenceID == nil : snapshot.currentOccurrenceID.map(known.contains) == true),
              (queue.isEmpty || snapshot.visibleCount >= ((snapshot.currentOccurrenceID.flatMap { ids.firstIndex(of: $0) } ?? ids.count) + 1)),
              snapshot.sourceRanks.keys.allSatisfy(known.contains),
              snapshot.placements.keys.allSatisfy(known.contains),
              Set(snapshot.sourceRanks.keys).union(snapshot.placements.keys) == known,
              snapshot.sourceRanks.values.allSatisfy({ $0 >= 0 && $0 < snapshot.nextSourceRank }),
              Set(snapshot.sourceRanks.values).count == snapshot.sourceRanks.count else { return false }
        for (id, placement) in snapshot.placements {
            guard snapshot.sourceRanks[id] == nil else { return false }
            switch placement {
            case .after(let anchor), .before(let anchor): guard known.contains(anchor), anchor != id else { return false }
            case .end: break
            }
        }
        // Reject anchor cycles; projection still has a stable orphan fallback for old damaged data.
        for start in snapshot.placements.keys {
            var cursor = start; var seen = Set<String>()
            anchorWalk: while seen.insert(cursor).inserted {
                guard let placement = snapshot.placements[cursor] else { break }
                switch placement { case .after(let anchor), .before(let anchor): cursor = anchor
                case .end: break anchorWalk }
                if cursor == start { return false }
            }
        }
        return true
    }

    private func beginMutation() { mutationDepth += 1 }
    private func endMutation() {
        mutationDepth -= 1
        if mutationDepth == 0, pendingNotification { pendingNotification = false; onStateChange?() }
    }
    private func stateChanged() {
        if mutationDepth > 0 { pendingNotification = true } else { onStateChange?() }
    }
    private static func randomSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max) }
}

private struct ShuffleRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9e37_79b9_7f4a_7c15 : seed }
    mutating func index(upperBound: Int) -> Int {
        guard upperBound > 1 else { return 0 }
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Int(state % UInt64(upperBound))
    }
}

private extension Int {
    func saturatingAdd(_ other: Int) -> Int {
        let (value, overflow) = addingReportingOverflow(other)
        return overflow ? Int.max : value
    }
}
