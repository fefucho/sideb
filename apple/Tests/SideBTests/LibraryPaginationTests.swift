import Foundation
import Testing
import SideBCore
@testable import SideB

private final class LibraryPageCore: SideBCore, @unchecked Sendable {
    let collectionCalls = LibraryCollectionCalls()
    var gate: LibraryPageGate?
    var requests: [String] = []
    var pages: [String: PlaylistContinuationRecord] = [:]
    var initial = PlaylistContinuationRecord(items: [], continuation: nil)
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { true }
    override func getLibraryPlaylists() async throws -> [BrowseCardRecord] { await collectionCalls.record("playlists"); return [] }
    override func getLibraryAlbums() async throws -> [BrowseCardRecord] { await collectionCalls.record("albums"); return [] }
    override func getLibraryArtists() async throws -> [BrowseCardRecord] { await collectionCalls.record("artists"); return [] }
    override func getHistory() async throws -> [HistoryGroupRecord] { await collectionCalls.record("history"); return [] }
    override func getLibrarySongs() async throws -> PlaylistContinuationRecord { initial }
    override func getPlaylistContinuation(token: String) async throws -> PlaylistContinuationRecord {
        requests.append(token)
        if let gate { return await gate.request() }
        return pages[token] ?? PlaylistContinuationRecord(items: [], continuation: nil)
    }
}
private actor LibraryCollectionCalls {
    var values: [String] = []
    func record(_ value: String) { values.append(value) }
}
private actor LibraryPageGate {
    var pending: CheckedContinuation<PlaylistContinuationRecord, Never>?
    var started: CheckedContinuation<Void, Never>?
    func request() async -> PlaylistContinuationRecord {
        await withCheckedContinuation { pending = $0; started?.resume(); started = nil }
    }
    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func resolve(_ page: PlaylistContinuationRecord) { pending?.resume(returning: page); pending = nil }
}
@MainActor struct LibraryPaginationTests {
    private func song(_ id: String) -> SongItemRecord {
        SongItemRecord(videoId: id, title: id, artists: "Artist", album: nil, duration: nil, thumbnail: nil,
                       artistId: nil, albumId: nil, setVideoId: nil, isVideo: false, isUpload: false, library: nil, artistRuns: [])
    }
    @Test func emptyContinuationPageDoesNotClaimTheLibraryEnded() async {
        let model = LibraryViewModel(); let core = LibraryPageCore()
        core.initial = PlaylistContinuationRecord(items: [song("first")], continuation: "empty")
        core.pages["empty"] = PlaylistContinuationRecord(items: [], continuation: "last")
        core.pages["last"] = PlaylistContinuationRecord(items: [song("second")], continuation: nil)
        await model.loadSongs(core: core, targetInitialCount: 2)
        #expect(model.songs.map(\.videoId) == ["first", "second"])
        #expect(core.requests == ["empty", "last"]); #expect(model.songsContinuation == nil)
    }
    @Test func searchingRemainingSongsStopsAtBudgetAndCanContinue() async {
        let model = LibraryViewModel(); let core = LibraryPageCore()
        core.initial = PlaylistContinuationRecord(items: [song("initial")], continuation: "0")
        for index in 0..<12 { core.pages[String(index)] = PlaylistContinuationRecord(items: [], continuation: index == 11 ? nil : String(index + 1)) }
        await model.loadSongs(core: core, targetInitialCount: 1)
        model.libraryQuery = "missing"
        await model.searchRemainingSongs(core: core)
        #expect(core.requests.count == 8); #expect(model.songsContinuation == "8")
        #expect(model.presentedSongs.isEmpty); #expect(!model.isSearchingRest)
        await model.searchRemainingSongs(core: core)
        #expect(core.requests.count == 12); #expect(model.songsContinuation == nil)
    }
    @Test func repeatedProviderTokenStopsAnInfiniteLoop() async {
        let model = LibraryViewModel(); let core = LibraryPageCore()
        core.initial = PlaylistContinuationRecord(items: [], continuation: "repeat")
        core.pages["repeat"] = PlaylistContinuationRecord(items: [], continuation: "repeat")
        await model.loadSongs(core: core)
        #expect(core.requests == ["repeat"]); #expect(model.songsContinuation == nil)
    }
    @Test func oldAccountContinuationCannotPopulateNextLibrary() async {
        let model = LibraryViewModel(); let core = LibraryPageCore(); let gate = LibraryPageGate()
        model.configureAccount(identity: "account:a")
        core.initial = PlaylistContinuationRecord(items: [song("old")], continuation: "pending")
        await model.loadSongs(core: core, targetInitialCount: 1)
        core.gate = gate
        let task = Task { await model.searchRemainingSongs(core: core) }
        await gate.waitForRequest()
        model.configureAccount(identity: "account:b")
        await gate.resolve(PlaylistContinuationRecord(items: [song("private")], continuation: "secret"))
        await task.value
        #expect(model.songs.isEmpty); #expect(model.songsContinuation == nil)
        #expect(!model.isSongsLoadingMore); #expect(!model.isSearchingRest)
    }

    @Test func allOnlyLoadsMissingSectionsAndDoesNotFetchHistoryForCollage() async {
        let model = LibraryViewModel(); let core = LibraryPageCore()
        await model.loadLibrary(core: core, includesHistory: false)
        await model.ensureSelectedPageTab(core: core)
        await model.ensureSelectedPageTab(core: core)
        let calls = await core.collectionCalls.values
        #expect(calls.sorted() == ["albums", "artists", "playlists"])
    }

}
