import Foundation
import Testing
import SideBCore
@testable import SideB

@MainActor
private final class PlaylistCatalogGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.isWaiting = true
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private enum PlaylistFixtureError: Error {
    case failed
}

@MainActor
private func catalogSong(_ id: String) -> SongItemRecord {
    SongItemRecord(videoId: id, title: id, artists: "Artist", album: nil,
                   duration: nil, thumbnail: nil, artistId: nil, albumId: nil,
                   setVideoId: nil, isVideo: false, isUpload: false,
                   library: nil, artistRuns: [])
}

@MainActor
private func catalogDetail(
    id: String = "PL-test",
    title: String = "Playlist",
    items: [SongItemRecord] = [],
    continuation: String? = nil
) -> PlaylistDetailRecord {
    PlaylistDetailRecord(id: id, title: title, subtitle: nil, thumbnail: nil,
                         description: nil, items: items, continuation: continuation,
                         owned: false, inLibrary: false, privacy: nil,
                         collaborative: false, sort: nil, sortEditable: false)
}

@MainActor
@Test func playlistCatalogSharesPendingLoadAndCancelledWaiterDoesNotCancelIt() async throws {
    let catalog = PlaylistCatalog()
    let gate = PlaylistCatalogGate()
    var initialRequests = 0

    func load() async throws -> PlaylistDetailRecord {
        try await catalog.load(
            id: "PL-shared",
            fetchInitial: { _ in
                initialRequests += 1
                await gate.pause()
                return catalogDetail(id: "PL-shared", title: "Complete", items: [catalogSong("one")])
            },
            fetchPage: { _ in PlaylistContinuationRecord(items: [], continuation: nil) }
        )
    }

    let first = Task { @MainActor in try await load() }
    for _ in 0..<1_000 where !gate.isWaiting { await Task.yield() }
    #expect(gate.isWaiting)

    let second = Task { @MainActor in try await load() }
    let cancelled = Task { @MainActor in try await load() }
    await Task.yield()
    cancelled.cancel()
    gate.open()

    let firstValue = try await first.value
    let secondValue = try await second.value
    #expect(firstValue.items.map(\.videoId) == ["one"])
    #expect(secondValue.items.map(\.videoId) == ["one"])
    #expect(initialRequests == 1)

    do {
        _ = try await cancelled.value
        Issue.record("A cancelled waiter must not receive the shared result.")
    } catch is CancellationError {
        #expect(true)
    }
}

@MainActor
@Test func playlistCatalogInvalidationRejectsStaleLoadAndKeepsNewResult() async throws {
    let catalog = PlaylistCatalog()
    let gate = PlaylistCatalogGate()
    let stale = Task { @MainActor in
        try await catalog.load(
            id: "PL-generation",
            fetchInitial: { _ in
                await gate.pause()
                return catalogDetail(id: "PL-generation", title: "Stale")
            },
            fetchPage: { _ in PlaylistContinuationRecord(items: [], continuation: nil) }
        )
    }

    for _ in 0..<1_000 where !gate.isWaiting { await Task.yield() }
    #expect(gate.isWaiting)
    catalog.invalidate("PL-generation")

    let current = try await catalog.load(
        id: "PL-generation",
        fetchInitial: { _ in catalogDetail(id: "PL-generation", title: "Current") },
        fetchPage: { _ in PlaylistContinuationRecord(items: [], continuation: nil) }
    )
    gate.open()

    do {
        _ = try await stale.value
        Issue.record("An invalidated request must not return its stale result.")
    } catch {
        #expect(error.localizedDescription.contains("obsoleta") || error is CancellationError)
    }
    #expect(current.title == "Current")
    #expect(catalog.cached(id: "PL-generation")?.title == "Current")
}

@MainActor
@Test func playlistCatalogLoadsEveryPageAndPreservesDuplicateOccurrences() async throws {
    let catalog = PlaylistCatalog()
    let firstPage = (0..<1_000).map { catalogSong($0 == 4 ? "duplicate" : "first-\($0)") }
    let secondPage = (0..<1_000).map { catalogSong($0 == 7 ? "duplicate" : "second-\($0)") }
    let finalPage = (0..<1_005).map { catalogSong("last-\($0)") }
    var pageRequests = 0

    let result = try await catalog.load(
        id: "PL-large",
        initial: catalogDetail(id: "PL-large", items: firstPage, continuation: "page-1"),
        fetchInitial: { _ in Issue.record("An initial record should avoid a duplicate first-page request"); return catalogDetail() },
        fetchPage: { token in
            pageRequests += 1
            if token == "page-1" {
                return PlaylistContinuationRecord(items: secondPage, continuation: "page-2")
            }
            return PlaylistContinuationRecord(items: finalPage, continuation: nil)
        }
    )

    #expect(result.items.count == 3_005)
    #expect(result.items.filter { $0.videoId == "duplicate" }.count == 2)
    #expect(result.items.first?.videoId == "first-0")
    #expect(result.items.last?.videoId == "last-1004")
    #expect(result.continuation == nil)
    #expect(pageRequests == 2)
    #expect(catalog.cached(id: "PL-large") == result)
}

@MainActor
@Test func playlistCatalogUsesAliasesForLikedSongsAndVLIdentifiers() async throws {
    let catalog = PlaylistCatalog()
    var initialRequests = 0
    var fetchedPlaylistID: String?

    let liked = try await catalog.load(
        id: "LM",
        fetchInitial: { id in
            initialRequests += 1
            return catalogDetail(id: id, title: "Liked")
        },
        fetchPage: { _ in PlaylistContinuationRecord(items: [], continuation: nil) }
    )
    let likedAlias = try await catalog.load(
        id: "VLLM",
        fetchInitial: { _ in
            initialRequests += 1
            return catalogDetail(title: "Unexpected duplicate")
        },
        fetchPage: { _ in PlaylistContinuationRecord(items: [], continuation: nil) }
    )
    #expect(likedAlias == liked)
    #expect(initialRequests == 1)

    _ = try await catalog.load(
        id: "VLPL-prefixed",
        fetchInitial: { id in
            initialRequests += 1
            fetchedPlaylistID = id
            return catalogDetail(id: id, title: "VL playlist")
        },
        fetchPage: { _ in PlaylistContinuationRecord(items: [], continuation: nil) }
    )
    let unprefixed = try await catalog.load(
        id: "PL-prefixed",
        fetchInitial: { _ in
            initialRequests += 1
            return catalogDetail(title: "Unexpected VL duplicate")
        },
        fetchPage: { _ in PlaylistContinuationRecord(items: [], continuation: nil) }
    )
    #expect(unprefixed.title == "VL playlist")
    #expect(initialRequests == 2)
    #expect(fetchedPlaylistID == "PL-prefixed")
}

@MainActor
@Test func playlistCatalogReplacesCacheWhenProvidedInitialHasDifferentOrderAndDuplicates() async throws {
    let catalog = PlaylistCatalog()
    let canonical = [catalogSong("a"), catalogSong("duplicate"), catalogSong("b"), catalogSong("duplicate")]
    _ = try await catalog.load(
        id: "PL-prefix-mismatch",
        initial: catalogDetail(id: "PL-prefix-mismatch", items: canonical),
        fetchInitial: { _ in catalogDetail() },
        fetchPage: { _ in PlaylistContinuationRecord(items: [], continuation: nil) }
    )

    let supplied = [catalogSong("duplicate"), catalogSong("a"), catalogSong("duplicate")]
    let result = try await catalog.load(
        id: "PL-prefix-mismatch",
        initial: catalogDetail(id: "PL-prefix-mismatch", items: supplied, continuation: "remaining"),
        fetchInitial: { _ in
            Issue.record("A supplied initial record must avoid fetching the first page.")
            return catalogDetail()
        },
        fetchPage: { token in
            #expect(token == "remaining")
            return PlaylistContinuationRecord(items: [catalogSong("b"), catalogSong("duplicate")], continuation: nil)
        }
    )

    #expect(result.items.map(\.videoId) == ["duplicate", "a", "duplicate", "b", "duplicate"])
    #expect(result.items.filter { $0.videoId == "duplicate" }.count == 3)
    #expect(catalog.cached(id: "PL-prefix-mismatch") == result)
}

@MainActor
@Test func playlistCatalogChecksSuppliedInitialAgainstSharedPendingResult() async throws {
    let catalog = PlaylistCatalog()
    let gate = PlaylistCatalogGate()
    let canonical = Task { @MainActor in
        try await catalog.load(
            id: "PL-pending-mismatch",
            fetchInitial: { _ in
                await gate.pause()
                return catalogDetail(id: "PL-pending-mismatch", items: [catalogSong("canonical"), catalogSong("duplicate")])
            },
            fetchPage: { _ in PlaylistContinuationRecord(items: [], continuation: nil) }
        )
    }

    for _ in 0..<1_000 where !gate.isWaiting { await Task.yield() }
    #expect(gate.isWaiting)
    let supplied = [catalogSong("duplicate"), catalogSong("duplicate")]
    let waiter = Task { @MainActor in
        try await catalog.load(
            id: "PL-pending-mismatch",
            initial: catalogDetail(id: "PL-pending-mismatch", items: supplied),
            fetchInitial: { _ in catalogDetail() },
            fetchPage: { _ in PlaylistContinuationRecord(items: [], continuation: nil) }
        )
    }
    await Task.yield()
    gate.open()

    // The new canonical prefix may invalidate the older waiter before it resumes.
    do {
        let canonicalResult = try await canonical.value
        #expect(canonicalResult.items.map(\.videoId) == ["canonical", "duplicate"])
    } catch {
        #expect(error.localizedDescription.contains("obsoleta"))
    }
    let suppliedResult = try await waiter.value
    #expect(suppliedResult.items.map(\.videoId) == ["duplicate", "duplicate"])
    #expect(catalog.cached(id: "PL-pending-mismatch") == suppliedResult)
}

@MainActor
@Test func playlistCatalogRejectsRepeatedContinuationAndDoesNotCachePartial() async throws {
    let catalog = PlaylistCatalog()
    var pageRequests = 0

    do {
        _ = try await catalog.load(
            id: "PL-cycle",
            initial: catalogDetail(id: "PL-cycle", continuation: "same"),
            fetchInitial: { _ in catalogDetail() },
            fetchPage: { token in
                pageRequests += 1
                return PlaylistContinuationRecord(items: [catalogSong("partial")], continuation: token)
            }
        )
        Issue.record("Repeated continuation tokens must fail.")
    } catch {
        #expect(error.localizedDescription.contains("repetida"))
    }

    #expect(pageRequests == 1)
    #expect(catalog.cached(id: "PL-cycle") == nil)
}

@MainActor
@Test func playlistCatalogNetworkFailureIsNotCachedAndCanBeRetried() async throws {
    let catalog = PlaylistCatalog()
    var pageRequests = 0
    let initial = catalogDetail(id: "PL-retry", items: [catalogSong("first")], continuation: "next")

    do {
        _ = try await catalog.load(
            id: "PL-retry",
            initial: initial,
            fetchInitial: { _ in catalogDetail() },
            fetchPage: { _ in
                pageRequests += 1
                throw PlaylistFixtureError.failed
            }
        )
        Issue.record("A failed continuation must fail the full catalog load.")
    } catch {
        #expect(error.localizedDescription.contains("No se pudo completar"))
    }
    #expect(catalog.cached(id: "PL-retry") == nil)

    let retried = try await catalog.load(
        id: "PL-retry",
        initial: initial,
        fetchInitial: { _ in catalogDetail() },
        fetchPage: { _ in
            pageRequests += 1
            return PlaylistContinuationRecord(items: [catalogSong("second")], continuation: nil)
        }
    )
    #expect(pageRequests == 2)
    #expect(retried.items.map(\.videoId) == ["first", "second"])
    #expect(catalog.cached(id: "PL-retry") == retried)
}

@MainActor
@Test func playlistCatalogStopsAfterFiveHundredPages() async throws {
    let catalog = PlaylistCatalog()
    var pageRequests = 0
    do {
        _ = try await catalog.load(
            id: "PL-page-limit",
            initial: catalogDetail(id: "PL-page-limit", continuation: "page-0"),
            fetchInitial: { _ in catalogDetail() },
            fetchPage: { _ in
                pageRequests += 1
                return PlaylistContinuationRecord(items: [], continuation: "page-\(pageRequests)")
            }
        )
        Issue.record("More than 500 continuation pages must fail.")
    } catch {
        #expect(error.localizedDescription.contains("500 páginas"))
    }
    #expect(pageRequests == 500)
    #expect(catalog.cached(id: "PL-page-limit") == nil)
}
