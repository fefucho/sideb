import Foundation
import Observation
import SideBCore

struct HomePlaylistMetadata: Equatable {
    let title: String
    let creator: String?
    let creatorID: String?
    let summary: String

    static func make(item: HomeItemRecord, playlist: PlaylistDetailRecord?) -> Self {
        let title = clean(playlist?.title) ?? clean(item.title) ?? ""
        let creator = cleanCreator(item.artists)
            ?? cleanCreator(item.artistRuns.map(\.text).joined(separator: " • "))
            ?? cleanCreator(item.subtitle)
            ?? cleanCreator(playlist?.subtitle)
        // A display subtitle is not an artist identity. Only use a real channel link.
        let creatorID = channelID(item.artistId)
            ?? item.artistRuns.first(where: {
                cleanCreator($0.text) == creator && channelID($0.id) != nil
            }).flatMap { channelID($0.id) }

        var parts = ["Playlist"]
        let providerSubtitles = [playlist?.subtitle, item.subtitle].compactMap(clean)
        let providerCount = providerSubtitles.lazy.compactMap(trackCount).first
        let isComplete = playlist.map { clean($0.continuation) == nil } ?? false
        let knownCount = providerCount ?? (isComplete && playlist?.items.isEmpty == false ? playlist?.items.count : nil)
        if let knownCount { parts.append(knownCount == 1 ? "1 canción" : "\(knownCount) canciones") }

        let providerDuration = providerSubtitles.lazy.compactMap {
            HomeCollectionMetadataFormatting.providerDuration($0, acceptsBareSeconds: false)
        }.first
        if let duration = providerDuration ?? completeDuration(playlist, isComplete: isComplete) {
            parts.append(duration)
        }
        return Self(title: title, creator: creator, creatorID: creatorID, summary: parts.joined(separator: " • "))
    }

    private static func completeDuration(_ playlist: PlaylistDetailRecord?, isComplete: Bool) -> String? {
        guard isComplete, let playlist, !playlist.items.isEmpty else { return nil }
        let durations = playlist.items.map { HomeCollectionMetadataFormatting.seconds(from: $0.duration) }
        guard durations.allSatisfy({ $0 != nil }) else { return nil }
        return HomeCollectionMetadataFormatting.formatDuration(durations.reduce(0) { $0 + ($1 ?? 0) })
    }

    private static func trackCount(_ value: String) -> Int? {
        let pattern = #"(?i)(?<![\d.,])\d+(?:[.,\s]\d{3})*\s+(?:songs?|tracks?|canci[oó]n(?:es)?|pistas?)\b"#
        guard let range = value.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = value[range].prefix(while: { $0.isNumber || $0 == "," || $0 == "." || $0.isWhitespace })
            .filter(\.isNumber)
        return Int(digits)
    }

    private static func cleanCreator(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let remaining = raw.components(separatedBy: CharacterSet(charactersIn: "•·"))
            .compactMap(clean)
            .filter { component in
                let value = component.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                if ["playlist", "lista de reproduccion", "mix"].contains(value) { return false }
                if value.range(of: #"^(?:19|20)\d{2}$"#, options: .regularExpression) != nil { return false }
                if trackCount(value) != nil { return false }
                if HomeCollectionMetadataFormatting.providerDuration(value, acceptsBareSeconds: false) != nil { return false }
                if value.range(of: #"(?i)^\d+(?:[.,]\d+)?\s*[kmb]?\s+(?:views?|visualizaciones?|reproducciones?|subscribers?|suscriptores?)$"#, options: .regularExpression) != nil { return false }
                return true
            }
        return clean(remaining.joined(separator: " • "))
    }

    private static func channelID(_ value: String?) -> String? {
        guard let value = clean(value), value.hasPrefix("UC") else { return nil }
        return value
    }

    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

/// Fetches first-page metadata for visible cards, never a playlist's complete catalog.
@MainActor @Observable
final class HomePlaylistMetadataModel {
    private(set) var details: [String: HomePlaylistMetadata] = [:]
    private var cachedPlaylists: [String: PlaylistDetailRecord] = [:]
    private var lru: [String] = []
    private var sessionKey: String?
    private var generation = 0
    @ObservationIgnored private let requestLimiter = HomeCollectionMetadataRequestLimiter()

    func display(for item: HomeItemRecord, sessionKey requestedSessionKey: String? = nil) -> HomePlaylistMetadata {
        if let requestedSessionKey, requestedSessionKey != sessionKey {
            return HomePlaylistMetadata.make(item: item, playlist: nil)
        }
        // Reapply the current Home credit/title fallback even when the detail is cached.
        return HomePlaylistMetadata.make(item: item, playlist: cachedPlaylists[item.id])
    }

    func load(items: [HomeItemRecord], core: SideBCore?, sessionKey: String) async {
        await load(items: items, sessionKey: sessionKey) { id in
            guard let core else { throw MetadataLoadError.unavailable }
            return try await core.getPlaylist(playlistId: id)
        }
    }

    func load(items: [HomeItemRecord], sessionKey: String,
              fetch: @escaping @Sendable (String) async throws -> PlaylistDetailRecord) async {
        guard !Task.isCancelled else { return }
        if self.sessionKey != sessionKey {
            self.sessionKey = sessionKey
            cachedPlaylists.removeAll()
            details.removeAll()
            lru.removeAll()
        }
        generation += 1
        let requestGeneration = generation
        var seen = Set<String>()
        let visibleItems = Array(items.filter { $0.kind == "playlist" && !$0.id.isEmpty && seen.insert($0.id).inserted }.prefix(6))
        for item in visibleItems where cachedPlaylists[item.id] != nil {
            touch(item.id)
            details[item.id] = HomePlaylistMetadata.make(item: item, playlist: cachedPlaylists[item.id])
        }
        let missing = visibleItems.filter { cachedPlaylists[$0.id] == nil }
        guard !missing.isEmpty else { return }
        let limiter = requestLimiter

        await withTaskGroup(of: (HomeItemRecord, PlaylistDetailRecord?).self) { group in
            var nextIndex = 0
            var activeCount = 0
            func addNext() {
                let item = missing[nextIndex]
                nextIndex += 1
                activeCount += 1
                group.addTask {
                    guard !Task.isCancelled else { return (item, nil) }
                    return (item, try? await limiter.fetch {
                        try await fetch(item.id)
                    })
                }
            }
            while nextIndex < min(2, missing.count) { addNext() }
            while activeCount > 0, let (item, playlist) = await group.next() {
                activeCount -= 1
                guard !Task.isCancelled, generation == requestGeneration else {
                    group.cancelAll()
                    return
                }
                if let playlist {
                    cachedPlaylists[item.id] = playlist
                    touch(item.id)
                    details[item.id] = HomePlaylistMetadata.make(item: item, playlist: playlist)
                }
                if nextIndex < missing.count { addNext() }
            }
        }
    }

    private func touch(_ id: String) {
        lru.removeAll { $0 == id }
        lru.append(id)
        while lru.count > 6 {
            let evicted = lru.removeFirst()
            cachedPlaylists.removeValue(forKey: evicted)
            details.removeValue(forKey: evicted)
        }
    }

    private enum MetadataLoadError: Error { case unavailable }
}

/// A cancelled SwiftUI page may still be waiting for Core's first-page request.
/// Share permits across page loads so changing pages never starts extra requests.
actor HomeCollectionMetadataRequestLimiter {
    private var activeCount = 0
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []

    func fetch<Value>(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if activeCount < 2 {
                    activeCount += 1
                    continuation.resume()
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func release() {
        activeCount -= 1
        if !waiters.isEmpty {
            let (_, continuation) = waiters.removeFirst()
            activeCount += 1
            continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }
}
