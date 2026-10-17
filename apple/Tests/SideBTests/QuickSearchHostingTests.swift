import AppKit
import SwiftUI
import SideBCore
import XCTest
@testable import SideB

private actor QuickSearchHostRequests {
    var submitted: [String] = []
    func catalog(_ query: String) -> SearchCatalogRecord {
        submitted.append(query)
        return SearchCatalogRecord(results: emptyQuickSearchResults(), correction: nil)
    }
}

private func emptyQuickSearchResults() -> SearchResultsRecord {
    SearchResultsRecord(topSongs: [], top: [], songs: [], albums: [], artists: [], playlists: [])
}

private final class QuickSearchHostCore: SideBCore, @unchecked Sendable {
    let requests = QuickSearchHostRequests()
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func searchSuggestions(query: String) async throws -> SearchSuggestionsRecord {
        SearchSuggestionsRecord(queries: [query + " first", query + " second"], results: emptyQuickSearchResults())
    }
    override func searchCatalog(query: String, recordHistory: Bool, ignoreSpelling: Bool) async throws -> SearchCatalogRecord {
        await requests.catalog(query)
    }
}

@MainActor
private final class QuickSearchHostState {
    var isPresented = true
    var draft = "sample"
    var selectionLabel: String?
}

@MainActor
final class QuickSearchHostingTests: XCTestCase {
    func testHostedContentKeepsSelectionAcrossUpdatesAndExecutesEveryKeyOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SearchRecentStore(directory: directory)
        let core = QuickSearchHostCore(), model = SearchViewModel(recentStore: store)
        // No core is needed by the player: this test submits textual suggestions only.
        let defaultsName = "QuickSearchHosting." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let player = PlayerViewModel(rustCore: nil,
            audioService: AudioPlayerService(preferences: defaults, preferencePrefix: "test"),
            playbackStore: PlaybackStateStore(directory: directory.appendingPathComponent("playback")), searchRecents: store)
        defer { player.audioService.stop() }
        let router = NavigationRouter(), state = QuickSearchHostState(), commands = QuickSearchCommandChannel()
        func content() -> AnyView {
            AnyView(QuickSearchContentView(
                isPresented: Binding(get: { state.isPresented }, set: { state.isPresented = $0 }),
                draft: Binding(get: { state.draft }, set: { state.draft = $0 }),
                searchViewModel: model, router: router, playerViewModel: player, rustCore: core,
                style: .anchored, commandChannel: commands,
                onSelectionLabelChange: { state.selectionLabel = $0 }).id("same-session"))
        }
        let host = NSHostingView(rootView: content())
        let window = NSWindow(contentRect: CGRect(x: -2000, y: -2000, width: 560, height: 500),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await pump(until: { model.associatedQuickQuery == "sample" })
        XCTAssertEqual(model.querySuggestions.count, 2)
        commands.commands.send(.moveDown)
        commands.commands.send(.moveDown)
        await pump(until: { state.selectionLabel == "sample second" })
        XCTAssertEqual(state.selectionLabel, "sample second", "Two key events in one render turn must both execute")
        host.rootView = content()
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        commands.commands.send(.submit)
        await pump(until: { !state.isPresented && !model.isCommittedLoading })
        XCTAssertFalse(state.isPresented)
        XCTAssertEqual(model.committedQuery, "sample second")
        XCTAssertEqual(router.currentPage, .search(query: "sample second"))
        let requests = await core.requests.submitted
        XCTAssertEqual(requests, ["sample second"])
        XCTAssertEqual(store.entries.count, 1)
        commands.commands.send(.submit)
        let afterRepeatedSubmit = await core.requests.submitted
        XCTAssertEqual(afterRepeatedSubmit, ["sample second"])
    }

    private func pump(until condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}
