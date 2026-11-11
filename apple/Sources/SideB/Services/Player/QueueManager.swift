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
    public var radioOccurrenceIDs: [String]? = nil
    public var stoppedAtEnd: Bool? = nil

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

public struct QueueRecommendationEntry: Identifiable, Equatable {
    public let id: String
    public let track: SongItemRecord
    public init(id: String, track: SongItemRecord) { self.id = id; self.track = track }
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

    private var occurrenceStructureRevision: UInt64 = 0
    private var cachedIndexRevision: UInt64 = .max
    private var cachedOccurrenceIndices: [String:Int] = [:]
    private var pendingDisplayLimit = 100
    public private(set) var occurrenceIDs: [String] = [] { didSet { occurrenceStructureRevision &+= 1 } }
    private var sourceRanks: [String: Int] = [:]
    private var nextSourceRank = 0
    private var placements: [String: QueuePlacement] = [:]
    private var visibleCount = 0
    private var mutationDepth = 0
    private var pendingNotification = false
    public private(set) var recommendationEntries: [QueueRecommendationEntry] = []
    public private(set) var presentationRevision: UInt64 = 0
    public private(set) var recommendationSessionID = UUID()
    public var radioCursorVideoID: String?
    public var radioContinuationToken: String?
    private var excludedRecommendations = Set<String>()
    private var recentVideoIDs: [String] = []
    private var recentlyInsertedOccurrenceIDs: [String] = []
    private var radioCommittedIDs = Set<String>()

    // MARK: - Estado de Cola
    public var onStateChange: (() -> Void)?
    public private(set) var queue: [SongItemRecord] = [] { didSet { stateChanged() } }
    public private(set) var currentIndex: Int = 0 { didSet { stateChanged() } }
    public var context: QueueContext? = nil { didSet { contextLocalizationKey = nil; contextLocalizationArguments = []; stateChanged() } }
    public var contextTitle: String = "Cola de reproducción" { didSet { stateChanged() } }
    private(set) var contextLocalizationKey: String?
    private(set) var contextLocalizationArguments: [String] = []

    /// Presentation metadata never changes context equality or queue occurrences.
    func setContextLocalizationKey(_ key: String?, args: [String] = []) {
        let allowed = ["queue.manual": 0, "history.title": 0, "player.shuffledArtist": 1]
        let next = key.flatMap { allowed[$0] == args.count ? $0 : nil }
        let nextArguments = next == nil ? [] : args
        guard contextLocalizationKey != next || contextLocalizationArguments != nextArguments else { return }
        contextLocalizationKey = next
        contextLocalizationArguments = nextArguments
        stateChanged()
    }

    var displayContextTitle: String {
        switch context {
        case .radio(_, _, let seedName): L10n.text("player.radioFor", args: [seedName])
        case .album(_, let title): L10n.text("queue.albumContext", args: [title])
        case .playlist(_, let title): L10n.text("queue.playlistContext", args: [title])
        case .custom(let title): contextLocalizationKey.map { L10n.text($0, args: contextLocalizationArguments) } ?? title
        case nil: L10n.text("queue.title")
        }
    }
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
        var snapshot = QueueOrderSnapshot(occurrenceIDs: occurrenceIDs, sourceRanks: sourceRanks,
                           placements: placements, currentOccurrenceID: currentOccurrenceID,
                           visibleCount: visibleCount, nextSourceRank: nextSourceRank)
        snapshot.radioOccurrenceIDs = radioCommittedIDs.isEmpty ? nil : radioCommittedIDs.sorted()
        snapshot.stoppedAtEnd = !queue.isEmpty && currentIndex == queue.count ? true : nil
        return snapshot
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
    public var visiblePendingIndices: [Int] {
        refreshOccurrenceIndicesIfNeeded()
        let upper = min(visibleCount, currentIndex.saturatingAdd(1).saturatingAdd(pendingDisplayLimit))
        var result = Set(currentIndex + 1 < upper ? Array((currentIndex + 1)..<upper) : [])
        for id in recentlyInsertedOccurrenceIDs.suffix(100) {
            if let index = cachedOccurrenceIndices[id], index >= upper, index > currentIndex { result.insert(index) }
        }
        return result.sorted()
    }
    public func revealMorePendingTracks() {
        let next = min(queue.count, max(visibleCount, currentIndex.saturatingAdd(1).saturatingAdd(pendingDisplayLimit + Self.playlistBatchSize)))
        pendingDisplayLimit += Self.playlistBatchSize
        guard next != visibleCount || next > currentIndex + 1 else { return }
        visibleCount = next
        stateChanged()
    }
    private func refreshOccurrenceIndicesIfNeeded() {
        guard cachedIndexRevision != occurrenceStructureRevision else { return }
        cachedOccurrenceIndices = Dictionary(uniqueKeysWithValues: occurrenceIDs.enumerated().map { ($0.element, $0.offset) })
        cachedIndexRevision = occurrenceStructureRevision
    }

    public var currentTrack: SongItemRecord? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    /// Refresh only the selected occurrence; duplicate videos, order and source identity stay intact.
    func updateCurrentMetadata(_ track: SongItemRecord, occurrenceID: String?, queueToken: UUID) {
        guard self.queueToken == queueToken, let occurrenceID,
              currentOccurrenceID == occurrenceID, queue.indices.contains(currentIndex),
              queue[currentIndex].videoId == track.videoId else { return }
        var enriched = track
        enriched.contentRating = ContentRatingMetadata.merging(queue[currentIndex].contentRating, incoming: track.contentRating)
        if queue[currentIndex] != enriched { queue[currentIndex] = enriched }
    }

    public var upNextTracks: [SongItemRecord] {
        guard currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }

    public var previousTracks: [SongItemRecord] {
        guard currentIndex > 0, !queue.isEmpty else { return [] }
        return Array(queue[0..<currentIndex])
    }

    public var hasNext: Bool { isRepeat ? !queue.isEmpty : currentIndex < queue.count - 1 || !recommendationEntries.isEmpty || radioContinuationToken != nil || isLoadingRadio || isLoadingAutoplay }
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
        shuffleSeed: UInt64? = nil,
        restoringCommittedQueue: Bool = false
    ) {
        beginMutation(); defer { endMutation() }
        queueToken = UUID()
        pendingDisplayLimit = 100
        recentlyInsertedOccurrenceIDs.removeAll()
        recommendationEntries.removeAll(); excludedRecommendations.removeAll(); recentVideoIDs.removeAll(); radioCommittedIDs.removeAll()
        recommendationSessionID = UUID(); radioCursorVideoID = nil; radioContinuationToken = nil
        let radio = !restoringCommittedQueue && { if case .radio? = context { return true }; return false }()
        let selectedIndex = items.isEmpty ? 0 : max(0, min(items.count - 1, index))
        let committedItems = radio ? (items.isEmpty ? [] : [items[selectedIndex]]) : items
        let rawReserved = radio && selectedIndex + 1 < items.count ? Array(items.dropFirst(selectedIndex + 1)) : []
        var initialKnown = Set(committedItems.map(\.videoId))
        let reserved = rawReserved.filter { initialKnown.insert($0.videoId).inserted }
        recommendationEntries = reserved.map { QueueRecommendationEntry(id: UUID().uuidString, track: $0) }
        queue = committedItems
        occurrenceIDs = committedItems.map { _ in UUID().uuidString }
        sourceRanks = Dictionary(uniqueKeysWithValues: occurrenceIDs.enumerated().map { ($0.element, $0.offset) })
        nextSourceRank = committedItems.count
        placements.removeAll(keepingCapacity: true)
        currentIndex = restoringCommittedQueue && index == items.count ? items.count : (radio ? 0 : selectedIndex)
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
        continuationToken = radio ? nil : continuation
        radioContinuationToken = radio ? continuation : nil
        if radio, let current = committedItems.last { radioCursorVideoID = current.videoId }
        isShuffle = shuffle
        visibleCount = initialVisibleCount(for: currentIndex)
        if shuffle, !items.isEmpty, !radio {
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
            radioCommittedIDs = Set(snapshot.radioOccurrenceIDs ?? []).intersection(snapshot.occurrenceIDs)
            nextSourceRank = snapshot.nextSourceRank
            visibleCount = snapshot.visibleCount
            currentIndex = snapshot.stoppedAtEnd == true ? queue.count : (snapshot.currentOccurrenceID.flatMap { snapshot.occurrenceIDs.firstIndex(of: $0) } ?? 0)
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
        var known = Set(queue.indices.contains(currentIndex) ? queue[currentIndex...].map(\.videoId) : [])
        known.formUnion(recommendationEntries.map { $0.track.videoId }); known.formUnion(recentVideoIDs)
        let fresh = tracks.filter { !excludedRecommendations.contains($0.videoId) && known.insert($0.videoId).inserted }
        recommendationEntries.append(contentsOf: fresh.map { QueueRecommendationEntry(id: UUID().uuidString, track: $0) })
        radioContinuationToken = continuation
        if let last = tracks.last { radioCursorVideoID = last.videoId }
        stateChanged()
    }

    /// Añade ocurrencias de playlist preservando duplicados y el orden de origen.
    public func appendPlaylistTracks(_ tracks: [SongItemRecord], nextContinuation: String? = nil) {
        beginMutation(); defer { endMutation() }
        let endManuals = occurrenceIDs.indices.filter { $0 > currentIndex && placements[occurrenceIDs[$0]] == .end }
        let insertion = endManuals.first ?? queue.count
        let oldVisible = visibleCount
        let publishedIDs = Set(occurrenceIDs.prefix(oldVisible))
        appendSourceItems(tracks)
        if insertion < queue.count {
            let newRange = (queue.count - tracks.count)..<queue.count
            let newItems = Array(queue[newRange]); let newIDs = Array(occurrenceIDs[newRange])
            queue.removeSubrange(newRange); occurrenceIDs.removeSubrange(newRange)
            queue.insert(contentsOf: newItems, at: insertion); occurrenceIDs.insert(contentsOf: newIDs, at: insertion)
        }
        visibleCount = min(queue.count, max(oldVisible, currentIndex + Self.playlistBatchSize))
        continuationToken = nextContinuation
        if !isShuffle { restoreSourceOrder() }
        else if !tracks.isEmpty {
            let positions = occurrenceIDs.indices.filter { $0 > currentIndex && sourceRanks[occurrenceIDs[$0]] != nil && !publishedIDs.contains(occurrenceIDs[$0]) }
            if positions.count > 1 {
                var rng = ShuffleRandom(seed: Self.randomSeed())
                for offset in stride(from: positions.count - 1, through: 1, by: -1) {
                    let other = rng.index(upperBound: offset + 1)
                    queue.swapAt(positions[offset], positions[other]); occurrenceIDs.swapAt(positions[offset], positions[other])
                }
            }
        }
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
        recentlyInsertedOccurrenceIDs.append(contentsOf: ids)
        if context == nil {
            context = .custom(title: "Cola manual")
            setContextLocalizationKey("queue.manual")
        }
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
        recentlyInsertedOccurrenceIDs.append(contentsOf: occurrenceIDs.suffix(tracks.count))
        visibleCount = min(queue.count, max(visibleCount, currentIndex + Self.playlistBatchSize))
    }

    public func enqueueRecommendation(id: String, next: Bool) {
        guard let i = recommendationEntries.firstIndex(where: { $0.id == id }) else { return }
        let entry = recommendationEntries.remove(at: i)
        if next { playNext(entry.track) } else { addTrackToQueue(entry.track) }
        stateChanged()
    }

    @discardableResult
    public func playRecommendation(id: String, advanceThrough: Bool = false) -> SongItemRecord? {
        guard let i = recommendationEntries.firstIndex(where: { $0.id == id }) else { return nil }
        beginMutation(); defer { endMutation() }
        let entries = advanceThrough ? Array(recommendationEntries.prefix(i + 1)) : [recommendationEntries[i]]
        if advanceThrough { recommendationEntries.removeFirst(i + 1) }
        else { recommendationEntries.remove(at: i) }
        let at = min(currentIndex + 1, queue.count)
        var anchor = currentOccurrenceID ?? (at > 0 ? occurrenceIDs[at - 1] : nil)
        let ids = entries.map { _ in UUID().uuidString }
        for (offset, occurrence) in ids.enumerated() {
            if isRadioContext {
                assignNextSourceRank(for: occurrence)
            } else {
                placements[occurrence] = anchor.map(QueuePlacement.after) ?? .end
            }
            if advanceThrough && offset < entries.count - 1 { radioCommittedIDs.insert(occurrence) }
            anchor = occurrence
        }
        queue.insert(contentsOf: entries.map(\.track), at: at)
        occurrenceIDs.insert(contentsOf: ids, at: at)
        currentIndex = at + entries.count - 1
        visibleCount = min(queue.count, max(visibleCount + entries.count, currentIndex + 1))
        if context == nil {
            context = .custom(title: "Cola manual")
            setContextLocalizationKey("queue.manual")
        }
        // Skipped proposals are navigation entries, not provider listens or recent playback.
        pruneRadioHistoryIfNeeded()
        stateChanged()
        return entries.last?.track
    }

    public func removeRecommendation(id: String) {
        guard let item = recommendationEntries.first(where: { $0.id == id }) else { return }
        recommendationEntries.removeAll { $0.id == id }; excludedRecommendations.insert(item.track.videoId); stateChanged()
    }

    public func excludeRecommendationVideo(_ videoID: String) {
        excludedRecommendations.insert(videoID); recommendationEntries.removeAll { $0.track.videoId == videoID }; stateChanged()
    }

    public func occurrenceIndex(id: String) -> Int? { refreshOccurrenceIndicesIfNeeded(); return cachedOccurrenceIndices[id] }

    @discardableResult
    public func advanceAfterRemovingCurrent() -> SongItemRecord? {
        guard queue.indices.contains(currentIndex) else { return promoteRecommendation() }
        beginMutation(); defer { endMutation() }
        let old = currentIndex, removedID = occurrenceIDs[old]
        detachDependents(of: removedID); queue.remove(at: old); occurrenceIDs.remove(at: old)
        sourceRanks.removeValue(forKey: removedID); placements.removeValue(forKey: removedID)
        radioCommittedIDs.remove(removedID)
        recentlyInsertedOccurrenceIDs.removeAll { $0 == removedID }
        if old < visibleCount { visibleCount -= 1 }
        currentIndex = min(old, queue.count)
        if old < queue.count { return queue[currentIndex] }
        return promoteRecommendation()
    }

    private func promoteRecommendation() -> SongItemRecord? {
        let known: Set<String> = queue.indices.contains(currentIndex) ? Set(queue[currentIndex...].map(\.videoId)) : []
        guard continuationToken == nil else { return nil }
        guard let i = recommendationEntries.firstIndex(where: { !known.contains($0.track.videoId) && !excludedRecommendations.contains($0.track.videoId) && !recentVideoIDs.contains($0.track.videoId) }) else {
            if !recommendationEntries.isEmpty { recommendationEntries.removeAll(); stateChanged() }
            return nil
        }
        if i > 0 { recommendationEntries.removeFirst(i) }
        let item = recommendationEntries.removeFirst()
        let anchor = currentOccurrenceID
        beginMutation(); defer { endMutation() }
        let id = UUID().uuidString; queue.append(item.track); occurrenceIDs.append(id)
        radioCommittedIDs.insert(id)
        if isRadioContext {
            assignNextSourceRank(for: id)
            visibleCount = queue.count
        } else {
            placements[id] = anchor.map(QueuePlacement.after) ?? .end
        }
        currentIndex = queue.count - 1
        if visibleCount < currentIndex + 1 { recentlyInsertedOccurrenceIDs.append(id) }
        recentVideoIDs.append(item.track.videoId); if recentVideoIDs.count > 30 { recentVideoIDs.removeFirst(recentVideoIDs.count - 30) }
        pruneRadioHistoryIfNeeded()
        stateChanged(); return item.track
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
        radioCommittedIDs.remove(removedID)
        if index < visibleCount { visibleCount -= 1 }
        recentlyInsertedOccurrenceIDs.removeAll { $0 == removedID }
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
        if targetID == nil { recentlyInsertedOccurrenceIDs.append(id) }
        currentIndex = activeID.flatMap { occurrenceIDs.firstIndex(of: $0) } ?? 0
    }

    /// Drops into the pending order. Previous/current entries are explicit repeats,
    /// so their original occurrence and the active audio keep their identity.
    @discardableResult
    public func placeQueueOccurrence(id: String, beforeID: String?) -> String? {
        guard let source = occurrenceIndex(id: id) else { return nil }
        let target: Int
        if let beforeID {
            guard let index = occurrenceIndex(id: beforeID), index > currentIndex else { return nil }
            target = index
        } else { target = queue.count }
        if source > currentIndex {
            let destination = target > source ? target - 1 : target
            moveTrack(from: source, to: destination)
            return id
        }
        beginMutation(); defer { endMutation() }
        let track = queue[source]
        addTrackToQueue(track)
        guard let added = occurrenceIDs.last else { return nil }
        if target < queue.count - 1 { moveTrack(from: queue.count - 1, to: target) }
        return added
    }

    public func clearQueue() {
        beginMutation(); defer { endMutation() }
        queue.removeAll(); occurrenceIDs.removeAll(); sourceRanks.removeAll(); placements.removeAll()
        nextSourceRank = 0; visibleCount = 0; currentIndex = 0
        queueToken = UUID()
        context = nil; contextTitle = "Cola de reproducción"; radioSeed = nil; continuationToken = nil
        radioCursorVideoID = nil; radioContinuationToken = nil; recommendationEntries.removeAll()
        excludedRecommendations.removeAll(); recentVideoIDs.removeAll(); recentlyInsertedOccurrenceIDs.removeAll()
        radioCommittedIDs.removeAll()
        recommendationSessionID = UUID()
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
            guard !isRepeat, let promoted = promoteRecommendation() else { return nil }
            return promoted
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

    private var isRadioContext: Bool {
        if case .radio? = context {
            return true
        }
        return false
    }

    private func assignNextSourceRank(for occurrenceID: String) {
        if sourceRanks[occurrenceID] != nil {
            placements.removeValue(forKey: occurrenceID)
            return
        }
        let rank = max(nextSourceRank, (sourceRanks.values.max() ?? -1) + 1)
        sourceRanks[occurrenceID] = rank
        nextSourceRank = rank + 1
        placements.removeValue(forKey: occurrenceID)
    }

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
        setContextLocalizationKey("queue.manual")
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
        if isRadioContext {
            guard queue.count > 1 else { return }
            if currentIndex > 0 {
                let activeTrack = queue.remove(at: currentIndex)
                let activeID = occurrenceIDs.remove(at: currentIndex)
                queue.insert(activeTrack, at: 0)
                occurrenceIDs.insert(activeID, at: 0)
                currentIndex = 0
                visibleCount = queue.count
            }
        }
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
        if isRadioContext && order.map(\.2) == positions.map({ occurrenceIDs[$0] }) {
            order.swapAt(0, order.count - 1)
        }
        for (slot, item) in zip(positions, order) {
            queue[slot] = item.1; occurrenceIDs[slot] = item.2
        }
    }

    private func restoreSourceOrder() {
        guard !queue.isEmpty else { return }
        let oldIDs = occurrenceIDs
        let activeID = currentOccurrenceID
        let stoppedAtEnd = !queue.isEmpty && currentIndex == queue.count
        let frozenPrefix = sourceRanks[currentOccurrenceID ?? ""] == nil ? Array(oldIDs.prefix(currentIndex + 1)) : []
        let frozen = Set(frozenPrefix)
        let known = Set(occurrenceIDs)
        let sources = occurrenceIDs.filter { sourceRanks[$0] != nil && !frozen.contains($0) }.sorted { sourceRanks[$0, default: 0] < sourceRanks[$1, default: 0] }
        var before: [String: [String]] = [:]
        var after: [String: [String]] = [:]
        var end: [String] = []
        for id in oldIDs where sourceRanks[id] == nil && !frozen.contains(id) {
            switch placements[id] {
            case .before(let anchor) where known.contains(anchor): before[anchor, default: []].append(id)
            case .after(let anchor) where known.contains(anchor): after[anchor, default: []].append(id)
            default: end.append(id)
            }
        }
        var ordered: [String] = []; ordered.reserveCapacity(oldIDs.count)
        var emitted = Set<String>()
        for root in frozenPrefix + sources + end { Self.project(root, before: before, after: after, emitted: &emitted, result: &ordered) }
        for id in oldIDs where emitted.insert(id).inserted { ordered.append(id) }
        if ordered != oldIDs {
            let itemsByID = Dictionary(uniqueKeysWithValues: zip(oldIDs, queue))
            queue = ordered.compactMap { itemsByID[$0] }
            occurrenceIDs = ordered
        }
        currentIndex = activeID.flatMap { occurrenceIDs.firstIndex(of: $0) } ?? (stoppedAtEnd ? queue.count : 0)
        if !stoppedAtEnd { visibleCount = min(queue.count, max(visibleCount, currentIndex.saturatingAdd(Self.playlistBatchSize))) }
    }

    private func pruneRadioHistoryIfNeeded() {
        let radioHistory = occurrenceIDs.prefix(currentIndex).filter { radioCommittedIDs.contains($0) }
        guard radioHistory.count > 220 else { return }
        let removeCount = radioHistory.count - 200
        for id in radioHistory.prefix(removeCount) {
            guard let index = occurrenceIDs.firstIndex(of: id) else { continue }
            let hasManualAnchor = placements.contains { key, placement in
                guard !radioCommittedIDs.contains(key) else { return false }
                switch placement { case .after(let anchor), .before(let anchor): return anchor == id; case .end: return false }
            }
            if hasManualAnchor { continue }
            detachDependents(of: id)
            queue.remove(at: index); occurrenceIDs.remove(at: index)
            sourceRanks.removeValue(forKey: id); placements.removeValue(forKey: id); radioCommittedIDs.remove(id)
            recentlyInsertedOccurrenceIDs.removeAll { $0 == id }
            if index < currentIndex { currentIndex -= 1 }
            if index < visibleCount { visibleCount -= 1 }
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
              (queue.isEmpty ? snapshot.currentOccurrenceID == nil : (snapshot.currentOccurrenceID.map(known.contains) == true || (snapshot.stoppedAtEnd == true && snapshot.currentOccurrenceID == nil))),
              (queue.isEmpty || snapshot.stoppedAtEnd == true || snapshot.visibleCount >= ((snapshot.currentOccurrenceID.flatMap { ids.firstIndex(of: $0) } ?? ids.count) + 1)),
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
        presentationRevision &+= 1
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
