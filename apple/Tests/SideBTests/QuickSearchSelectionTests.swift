import Testing
@testable import SideB

@Test func quickSearchSelectionTraversesPrimaryActionsAndReturnsToEditor() {
    // Secondary controls such as Clear, Undo, Play, and menus never enter this list.
    let keys = ["query:artist", "song:first", "artist:second"]
    var selected: String?
    selected = QuickSearchSelection.nextKey(in: keys, selected: selected, delta: 1)
    #expect(selected == "query:artist")
    selected = QuickSearchSelection.nextKey(in: keys, selected: selected, delta: 1)
    #expect(selected == "song:first")
    selected = QuickSearchSelection.nextKey(in: keys, selected: selected, delta: -1)
    #expect(selected == "query:artist")
    selected = QuickSearchSelection.nextKey(in: keys, selected: selected, delta: -1)
    #expect(selected == nil)
    #expect(QuickSearchSelection.nextKey(in: keys, selected: nil, delta: -1) == nil)
    #expect(QuickSearchSelection.nextKey(in: keys, selected: keys.last, delta: 1) == keys.last)
}

@Test func quickSearchSelectionSurvivesReorderingButRejectsReplacedEntity() {
    let replacement = ["query:new", "album:new", "song:accepted"]
    let selected = QuickSearchSelection.retainedKey(in: replacement, selected: "song:accepted")
    #expect(selected == "song:accepted")
    #expect(QuickSearchSelection.nextKey(in: replacement, selected: selected, delta: -1) == "album:new")
    #expect(QuickSearchSelection.retainedKey(in: replacement, selected: "song:removed") == nil)
    #expect(QuickSearchSelection.retainedKey(in: [], selected: selected) == nil)
    #expect(QuickSearchSelection.nextKey(in: [], selected: selected, delta: 1) == nil)
    #expect(QuickSearchSelection.nextKey(in: replacement, selected: "song:removed", delta: 1) == "query:new")
}

@Test func quickSearchSelectionKeepsSongVideoAndRecentTrackNamespacesSeparate() {
    let keys = ["song:shared", "video:shared", "track:youtube:shared", "track:upload:shared"]
    #expect(QuickSearchSelection.nextKey(in: keys, selected: "song:shared", delta: 1) == "video:shared")
    #expect(QuickSearchSelection.nextKey(in: keys, selected: "track:youtube:shared", delta: 1) == "track:upload:shared")
    #expect(QuickSearchSelection.retainedKey(in: ["video:shared"], selected: "song:shared") == nil)
}
