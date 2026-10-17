import Foundation
import Testing
import SideBCore
@testable import SideB

private enum LibraryMutationFailure: Error { case expected }
private actor LibraryMutationGate {
    private var pending: CheckedContinuation<Void, Error>?
    private var waiter: CheckedContinuation<Void, Never>?
    func request() async throws {
        try await withCheckedThrowingContinuation { pending = $0; waiter?.resume(); waiter = nil }
    }
    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func fail() { pending?.resume(throwing: LibraryMutationFailure.expected); pending = nil }
}
private final class LibraryMutationCore: SideBCore, @unchecked Sendable {
    let gate = LibraryMutationGate()
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { true }
    override func likePlaylist(playlistId: String, like: Bool) async throws { try await gate.request() }
}
@Suite(.serialized) @MainActor struct LibraryMutationTests {
    private func card(_ id: String, kind: String) -> BrowseCardRecord {
        BrowseCardRecord(kind: kind, id: id, title: id, subtitle: nil, thumbnail: nil, duration: nil)
    }
    private func isolatedModel() -> (LibraryViewModel, UserDefaults, String) {
        let suite = "SideB.LibraryMutationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (LibraryViewModel(preferences: defaults), defaults, suite)
    }
    @Test func albumRollbackFromOldAccountCannotEnterNewAccount() async {
        let (model, defaults, suite) = isolatedModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        let core = LibraryMutationCore()
        model.configureAccount(identity: "account:a")
        model.handleAlbumToggled(browseId: "old", inLibrary: true, card: card("old", kind: "album"))
        let operation = Task { await model.toggleAlbumLibrary(core: core, browseId: "old", playlistId: nil,
            title: "old", subtitle: nil, thumbnail: nil, inLibrary: true) }
        await core.gate.waitForRequest()
        model.configureAccount(identity: "account:b")
        model.handleAlbumToggled(browseId: "new", inLibrary: true, card: card("new", kind: "album"))
        await core.gate.fail(); await operation.value
        #expect(model.albums.map(\.id) == ["new"])
        #expect(model.originalAlbums.map(\.id) == ["new"])
        #expect(AppContextMenuFactory.cachedUserAlbums.map(\.id) == ["new"])
    }
    @Test func playlistRollbackFromOldAccountCannotEnterNewAccount() async {
        let (model, defaults, suite) = isolatedModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        let core = LibraryMutationCore()
        model.configureAccount(identity: "account:a")
        model.handlePlaylistToggled(playlistId: "old", inLibrary: true, card: card("old", kind: "playlist"))
        let operation = Task { await model.togglePlaylistLibrary(core: core, playlistId: "old",
            title: "old", subtitle: nil, thumbnail: nil, inLibrary: true) }
        await core.gate.waitForRequest()
        model.configureAccount(identity: "account:b")
        model.handlePlaylistToggled(playlistId: "new", inLibrary: true, card: card("new", kind: "playlist"))
        await core.gate.fail(); await operation.value
        #expect(model.playlists.map(\.id) == ["new"])
        #expect(AppContextMenuFactory.cachedUserPlaylists.map(\.id) == ["new"])
    }
    @Test func failedPlaylistMutationStillRollsBackInSameAccount() async {
        let (model, defaults, suite) = isolatedModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        let core = LibraryMutationCore()
        model.configureAccount(identity: "account:a")
        model.handlePlaylistToggled(playlistId: "saved", inLibrary: true, card: card("saved", kind: "playlist"))
        let operation = Task { await model.togglePlaylistLibrary(core: core, playlistId: "saved",
            title: "saved", subtitle: nil, thumbnail: nil, inLibrary: true) }
        await core.gate.waitForRequest()
        #expect(model.playlists.isEmpty)
        await core.gate.fail(); await operation.value
        #expect(model.playlists.map(\.id) == ["saved"])
    }
    @Test func whitespaceQueryDoesNotDisableLibraryContinuation() {
        let (model, defaults, suite) = isolatedModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.libraryQuery = " \n\t "
        #expect(!model.hasLibraryQuery)
        #expect(model.matches("Anything"))
        model.libraryQuery = " Anything "
        #expect(model.hasLibraryQuery)
        #expect(model.matches("Anything"))
    }
}
