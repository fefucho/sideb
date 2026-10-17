import Foundation
import Testing
import SideBCore
@testable import SideB

@MainActor struct LibraryPreferencesTests {
    private func card(_ id: String, title: String = "Card", kind: String = "album", artist: String? = nil) -> BrowseCardRecord {
        BrowseCardRecord(kind: kind, id: id, title: title, subtitle: artist, thumbnail: nil, duration: nil)
    }
    @Test func preferencesAndPinsArePartitionedByAccount() {
        let suite = "SideB.LibraryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = LibraryViewModel(preferences: defaults)
        model.configureAccount(identity: "channel:a")
        model.selectedPageTab = .albums; model.collectionList = true; model.libraryOrder = "name"
        model.togglePin(card("same")); model.togglePin(card("same", kind: "playlist"))
        model.movePin(card("same", kind: "playlist"), by: -1)
        model.playlists = [card("private", kind: "playlist")]; model.libraryQuery = "private"
        model.collectionScrollOffsets["albums"] = 240
        model.configureAccount(identity: "channel:b")
        #expect(model.pins.isEmpty); #expect(model.playlists.isEmpty); #expect(model.libraryQuery.isEmpty)
        #expect(model.collectionScrollOffsets.isEmpty); #expect(model.selectedPageTab == .all)
        model.configureAccount(identity: "channel:a")
        #expect(model.selectedPageTab == .albums); #expect(model.collectionList); #expect(model.libraryOrder == "name")
        #expect(model.pins.map(\.key) == ["playlist:same", "album:same"])
        model.clear(); model.configureAccount(identity: "channel:a")
        #expect(model.pins.count == 2)
    }
    @Test func originalOrderSurvivesSortAndPinsSurviveAbsentRemoteCards() {
        let model = LibraryViewModel()
        let cards = [card("b", title: "Beta", artist: "Zed"), card("a", title: "Alpha", artist: "Ada")]
        model.albums = cards; model.libraryOrder = "name"
        #expect(model.presentedCards(cards).map(\.id) == ["a", "b"])
        model.libraryOrder = "original"
        #expect(model.presentedCards(cards).map(\.id) == ["b", "a"])
        model.libraryQuery = " Zed "
        #expect(model.presentedCards(cards).map(\.id) == ["b"])
        model.togglePin(cards[0]); model.albums = []
        #expect(model.pinnedCards.first?.id == "b")
    }
    @Test func corruptPreferencesFallBackToAll() {
        let suite = "SideB.LibraryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "sideb.library.v1:channel:a")
        let model = LibraryViewModel(preferences: defaults)
        model.configureAccount(identity: "channel:a")
        #expect(model.selectedPageTab == .all); #expect(model.pins.isEmpty)
    }
    @Test func playlistPrefixesAndMixAliasesUseOnePinIdentity() {
        let model = LibraryViewModel()
        model.togglePin(card("VLPL123", kind: "playlist"))
        #expect(model.pins.first?.key == "playlist:PL123")
        model.playlists = [card("PL123", title: "Fresh", kind: "playlist")]
        #expect(model.pinnedCards.first?.title == "Fresh")
        model.togglePin(card(" PL123 ", kind: "mix"))
        #expect(model.pins.isEmpty)
        #expect(LibraryPin.key(card("PL123", kind: "album")) != LibraryPin.key(card("PL123", kind: "playlist")))
    }

}
