import Foundation
import SideBCore

@MainActor
final class PlaylistCatalog {
    static let shared = PlaylistCatalog()

    private struct InFlight {
        let generation: UUID
        let task: Task<PlaylistDetailRecord, Error>
    }

    private var completed: [String: PlaylistDetailRecord] = [:]
    private var inFlight: [String: InFlight] = [:]
    private var generations: [String: UUID] = [:]

    init() {}

    func load(
        id: String,
        core: SideBCore,
        initial: PlaylistDetailRecord? = nil
    ) async throws -> PlaylistDetailRecord {
        try await load(
            id: id,
            initial: initial,
            fetchInitial: { playlistID in
                try await core.getPlaylist(playlistId: playlistID)
            },
            fetchPage: { token in
                try await core.getPlaylistContinuation(token: token)
            }
        )
    }

    func load(
        id: String,
        initial: PlaylistDetailRecord? = nil,
        fetchInitial: @escaping @MainActor (String) async throws -> PlaylistDetailRecord,
        fetchPage: @escaping @MainActor (String) async throws -> PlaylistContinuationRecord
    ) async throws -> PlaylistDetailRecord {
        try Task.checkCancellation()
        let key = cacheKey(for: id)

        if let cached = completed[key] {
            try Task.checkCancellation()
            if let initial, !hasMatchingPrefix(initial.items, in: cached.items) {
                invalidate(id)
                return try await load(
                    id: id,
                    initial: initial,
                    fetchInitial: fetchInitial,
                    fetchPage: fetchPage
                )
            }
            return cached
        }

        if let current = inFlight[key] {
            let result = try await awaitResult(of: current, for: key)
            if let initial, !hasMatchingPrefix(initial.items, in: result.items) {
                invalidate(id)
                return try await load(
                    id: id,
                    initial: initial,
                    fetchInitial: fetchInitial,
                    fetchPage: fetchPage
                )
            }
            return result
        }

        let generation = UUID()
        generations[key] = generation
        let task = Task { @MainActor in
            do {
                let firstPage: PlaylistDetailRecord
                if let initial {
                    firstPage = initial
                } else {
                    do {
                        firstPage = try await fetchInitial(key)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        throw PlaylistCatalogError.fetchFailed(error.localizedDescription)
                    }
                }

                try Task.checkCancellation()
                var result = firstPage
                var nextToken = firstPage.continuation
                var seenTokens: Set<String> = []
                var pageCount = 0

                while let token = nextToken, !token.isEmpty {
                    guard seenTokens.insert(token).inserted else {
                        throw PlaylistCatalogError.repeatedContinuation(token)
                    }
                    guard pageCount < Self.maximumPages else {
                        throw PlaylistCatalogError.pageLimit(Self.maximumPages)
                    }

                    let page: PlaylistContinuationRecord
                    do {
                        page = try await fetchPage(token)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        throw PlaylistCatalogError.fetchFailed(error.localizedDescription)
                    }
                    try Task.checkCancellation()

                    result.items.append(contentsOf: page.items)
                    pageCount += 1
                    nextToken = page.continuation
                }

                try Task.checkCancellation()
                guard self.generations[key] == generation else {
                    throw PlaylistCatalogError.invalidated
                }

                result.continuation = nil
                self.completed[key] = result
                self.inFlight[key] = nil
                return result
            } catch {
                if self.generations[key] == generation {
                    self.inFlight[key] = nil
                }
                throw error
            }
        }

        let request = InFlight(generation: generation, task: task)
        inFlight[key] = request
        return try await awaitResult(of: request, for: key)
    }

    func invalidate(_ id: String) {
        let key = cacheKey(for: id)
        completed[key] = nil
        inFlight[key]?.task.cancel()
        inFlight[key] = nil
        generations[key] = UUID()
    }

    func invalidateAll() {
        for request in inFlight.values {
            request.task.cancel()
        }
        completed.removeAll()
        inFlight.removeAll()
        generations.removeAll()
    }

    func cached(id: String) -> PlaylistDetailRecord? {
        completed[cacheKey(for: id)]
    }

    private static let maximumPages = 500

    private func hasMatchingPrefix(_ prefix: [SongItemRecord], in items: [SongItemRecord]) -> Bool {
        prefix == Array(items.prefix(prefix.count))
    }

    private func awaitResult(of request: InFlight, for key: String) async throws -> PlaylistDetailRecord {
        do {
            let result = try await request.task.value
            try Task.checkCancellation()
            guard generations[key] == request.generation else {
                throw PlaylistCatalogError.invalidated
            }
            return result
        } catch {
            if Task.isCancelled { throw CancellationError() }
            guard generations[key] == request.generation else {
                throw PlaylistCatalogError.invalidated
            }
            throw error
        }
    }

    private func cacheKey(for id: String) -> String {
        // YouTube Music exposes liked songs as both LM and VLLM. The VL prefix
        // is also a transport form of the same playlist identifier.
        if id == "LM" || id == "VLLM" { return "LM" }
        if id.hasPrefix("VL") { return String(id.dropFirst(2)) }
        return id
    }
}

private enum PlaylistCatalogError: LocalizedError {
    case repeatedContinuation(String)
    case pageLimit(Int)
    case fetchFailed(String)
    case invalidated

    var errorDescription: String? {
        switch self {
        case .repeatedContinuation:
            return "La playlist devolvió una continuación repetida."
        case .pageLimit(let limit):
            return "La playlist superó el máximo de \(limit) páginas."
        case .fetchFailed(let message):
            return "No se pudo completar la playlist: \(message)"
        case .invalidated:
            return "La carga de la playlist quedó obsoleta y fue descartada."
        }
    }
}
