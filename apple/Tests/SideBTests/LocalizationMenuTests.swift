import AppKit
import XCTest
import SideBCore
@testable import SideB

@MainActor
final class LocalizationMenuTests: XCTestCase {
    func testMissingReleaseNotesRetitleWhileOriginalMarkdownStaysUnchanged() throws {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        let url = try XCTUnwrap(URL(string: "https://example.test/update.zip"))
        let missing = ReleaseInfo(tagName: "v1", version: "1", releaseNotes: "", downloadURL: url, publishedAt: nil)
        let original = ReleaseInfo(tagName: "v1", version: "1", releaseNotes: "**Original notes**", downloadURL: url, publishedAt: nil)
        AppLanguageStore.shared.setLanguage(.es)
        let spanish = missing.displayReleaseNotes
        AppLanguageStore.shared.setLanguage(.en)
        XCTAssertNotEqual(missing.displayReleaseNotes, spanish)
        XCTAssertEqual(missing.displayReleaseNotes, L10n.text("update.no_release_notes"))
        XCTAssertEqual(missing.releaseNotes, "")
        XCTAssertEqual(original.displayReleaseNotes, "**Original notes**")
        XCTAssertEqual(original.releaseNotes, "**Original notes**")
    }

    func testMenuPresentationChangesWhileActionsTargetsAndFactsStayStable() {
        let previousLanguage = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previousLanguage) }
        AppLanguageStore.shared.setLanguage(.es)

        let likedList = BrowseCardRecord(
            kind: "playlist", id: "VLLM", title: "Nombre original", subtitle: nil,
            thumbnail: nil, duration: nil
        )
        let personalList = BrowseCardRecord(
            kind: "playlist", id: "PL123", title: "Me gusta sin ser la colección del sistema", subtitle: nil,
            thumbnail: nil, duration: nil
        )
        let song = SongItemRecord(
            videoId: "video-1", title: "Track", artists: "Artist", album: "Album",
            duration: "180", thumbnail: nil, artistId: "UCartist", albumId: "MPREalbum",
            setVideoId: nil, isVideo: false, isUpload: false, library: nil
        )
        let target = MenuTarget.song(song)
        let origin = MenuOrigin.home
        let facts = MenuFacts(
            isLoggedIn: true,
            inLibrary: .known(false),
            isOwned: .known(true),
            sortEditable: true,
            isSubscribed: .known(false),
            isCurrentPlayingTrack: false,
            isLiked: false,
            userPlaylists: [likedList, personalList]
        )
        let originalFacts = FactsSnapshot(facts)

        let spanishSections = MenuPolicy.resolveSections(target: target, origin: origin, facts: facts)
        let spanishQueueTitle = item(.addToQueue, in: spanishSections)?.title
        let spanishLikedTitle = item(.toggleLike, in: spanishSections)?.title
        let likedPlaylistItem = item(.addToPlaylist(playlistId: "VLLM", title: "Nombre original"), in: spanishSections)

        AppLanguageStore.shared.setLanguage(.en)
        let englishSections = MenuPolicy.resolveSections(target: target, origin: origin, facts: facts)
        let englishQueueTitle = item(.addToQueue, in: englishSections)?.title
        let englishLikedTitle = item(.toggleLike, in: englishSections)?.title
        let englishLikedPlaylistItem = item(.addToPlaylist(playlistId: "VLLM", title: "Nombre original"), in: englishSections)

        XCTAssertEqual(target, .song(song))
        XCTAssertEqual(origin, .home)
        XCTAssertEqual(FactsSnapshot(facts), originalFacts)
        XCTAssertEqual(spanishSections.map(\.kind), englishSections.map(\.kind))
        XCTAssertEqual(actionIDs(spanishSections), actionIDs(englishSections))
        XCTAssertNotEqual(spanishQueueTitle, englishQueueTitle)
        XCTAssertNotEqual(spanishLikedTitle, englishLikedTitle)
        XCTAssertEqual(likedPlaylistItem?.title, "Nombre original")
        XCTAssertEqual(englishLikedPlaylistItem?.title, "Nombre original")
        XCTAssertEqual(likedPlaylistItem?.systemImage, "heart.fill")
        XCTAssertEqual(englishLikedPlaylistItem?.systemImage, "heart.fill")

        // A translated playlist title must never make an ordinary playlist look like LM.
        let personalItem = item(.addToPlaylist(playlistId: "PL123", title: personalList.title), in: englishSections)
        XCTAssertEqual(personalItem?.systemImage, "music.note.list")
    }

    func testMountedNativeControlsRetitleWithoutChangingSelectedSegment() async {
        let previousLanguage = L10n.language
        var observer: AppKitLocalizationObserver?
        defer {
            observer = nil
            AppLanguageStore.shared.setLanguage(previousLanguage)
        }
        AppLanguageStore.shared.setLanguage(.es)

        let navigation = NativeNavigationBar(target: self, action: #selector(noop(_:)))
        navigation.control.selectedSegment = 2
        let historyView = HistoryToolbarView(router: NavigationRouter(), isDisabled: false)
        let history = NativeHistoryBar(target: HistoryToolbarView.Coordinator(historyView))
        let oldNavigationTitle = navigation.control.toolTip(forSegment: 0)
        let oldHistoryTitle = history.back.toolTip
        XCTAssertNotNil(history.back.superview)

        let updated = expectation(description: "Mounted AppKit labels updated")
        observer = AppKitLocalizationObserver {
            navigation.updateLocalization()
            history.updateLocalization()
            updated.fulfill()
        }
        observer?.start()
        AppLanguageStore.shared.setLanguage(.en)
        await fulfillment(of: [updated], timeout: 1)

        XCTAssertNotEqual(oldNavigationTitle, navigation.control.toolTip(forSegment: 0))
        XCTAssertNotEqual(oldHistoryTitle, history.back.toolTip)
        XCTAssertEqual(navigation.control.toolTip(forSegment: 0), L10n.text("navigation.home"))
        XCTAssertEqual(history.back.toolTip, L10n.text("navigation.back"))
        XCTAssertEqual(navigation.control.selectedSegment, 2)
    }

    func testMenuBarRetitlesStandardMenusByIdentityAndKeepsCommandTargets() {
        let previousLanguage = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previousLanguage) }
        AppLanguageStore.shared.setLanguage(.es)
        let menu = NSMenu()
        let appItem = NSMenuItem(title: "Side B", action: nil, keyEquivalent: "")
        menu.addItem(appItem)
        let keys = ["menu.file", "menu.song", "menu.view", "menu.controls", "menu.account"]
        let ownItems = keys.map { key in
            let item = NSMenuItem(title: L10n.text(key), action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: item.title)
            menu.addItem(item)
            return item
        }
        let edit = NSMenuItem(title: "OS edit title", action: nil, keyEquivalent: "")
        let editMenu = NSMenu()
        let commands = ["cut:", "copy:", "paste:"].map { selector in
            let command = NSMenuItem(title: selector, action: Selector(selector), keyEquivalent: "c")
            command.target = self
            editMenu.addItem(command)
            return command
        }
        edit.submenu = editMenu
        menu.addItem(edit)
        let windows = NSMenuItem(title: "OS window title", action: nil, keyEquivalent: "")
        windows.submenu = NSMenu()
        menu.addItem(windows)
        let help = NSMenuItem(title: "OS help title", action: nil, keyEquivalent: "")
        help.submenu = NSMenu()
        menu.addItem(help)

        for language in [AppLanguage.en, .es] {
            AppLanguageStore.shared.setLanguage(language)
            AppMenuBarOrganizer.normalize(mainMenu: menu, windowsMenu: windows.submenu, helpMenu: help.submenu)
            XCTAssertEqual(menu.items.map(ObjectIdentifier.init),
                           [appItem, ownItems[0], edit, ownItems[1], ownItems[2], ownItems[3], ownItems[4], windows, help].map(ObjectIdentifier.init))
            XCTAssertEqual(edit.title, L10n.text("menu.edit"))
            XCTAssertEqual(edit.submenu?.title, L10n.text("menu.edit"))
            XCTAssertEqual(windows.title, L10n.text("menu.window"))
            XCTAssertEqual(windows.submenu?.title, L10n.text("menu.window"))
            XCTAssertEqual(help.title, L10n.text("menu.help"))
            XCTAssertEqual(help.submenu?.title, L10n.text("menu.help"))
            XCTAssertEqual(ownItems.map(\.title), keys.map { L10n.text($0) })
            XCTAssertTrue(commands.allSatisfy { $0.target === self && $0.keyEquivalent == "c" })
            XCTAssertEqual(commands.compactMap(\.action), ["cut:", "copy:", "paste:"].map { Selector($0) })
        }
    }

    func testWrappedEditCommandsAndUnregisteredStandardMenusRetitleInPlace() {
        let previousLanguage = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previousLanguage) }
        AppLanguageStore.shared.setLanguage(.es)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Side B", action: nil, keyEquivalent: ""))
        let edit = NSMenuItem(title: "Opaque edit title", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu()
        let commands = ["x", "c", "v"].map { key in
            let item = NSMenuItem(title: key, action: #selector(noop(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = [.command]
            item.target = self
            edit.submenu?.addItem(item)
            return item
        }
        menu.addItem(edit)
        let windows = NSMenuItem(title: L10n.text("menu.window"), action: nil, keyEquivalent: "")
        windows.submenu = NSMenu()
        menu.addItem(windows)
        let help = NSMenuItem(title: L10n.text("menu.help"), action: nil, keyEquivalent: "")
        help.submenu = NSMenu()
        menu.addItem(help)
        let identity = menu.items.map(ObjectIdentifier.init)

        for language in [AppLanguage.en, .es] {
            AppLanguageStore.shared.setLanguage(language)
            AppMenuBarOrganizer.normalize(mainMenu: menu, windowsMenu: nil, helpMenu: nil)
            XCTAssertEqual(menu.items.map(ObjectIdentifier.init), identity)
            XCTAssertEqual(edit.title, L10n.text("menu.edit"))
            XCTAssertEqual(windows.title, L10n.text("menu.window"))
            XCTAssertEqual(help.title, L10n.text("menu.help"))
            XCTAssertEqual(commands.map(\.keyEquivalent), ["x", "c", "v"])
            XCTAssertTrue(commands.allSatisfy { $0.target === self && $0.action == #selector(noop(_:)) })
        }
    }

    func testNormalizationDoesNotEmitChangesForAlreadyTranslatedMenu() async {
        let previousLanguage = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previousLanguage) }
        AppLanguageStore.shared.setLanguage(.en)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Side B", action: nil, keyEquivalent: ""))
        let keys = ["menu.file", "menu.edit", "menu.song", "menu.view", "menu.controls", "menu.account", "menu.window", "menu.help"]
        for key in keys {
            let item = NSMenuItem(title: L10n.text(key), action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: item.title)
            menu.addItem(item)
        }
        let notification = expectation(description: "Idempotent normalization must not trigger menu notifications")
        notification.isInverted = true
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didChangeItemNotification, object: menu, queue: .main) { _ in
            notification.fulfill()
        }
        AppMenuBarOrganizer.normalize(mainMenu: menu, windowsMenu: nil, helpMenu: nil)
        await fulfillment(of: [notification], timeout: 0.05)
        NotificationCenter.default.removeObserver(observer)

        // A later system rewrite is repaired using the same items and actions.
        let edit = menu.items[2]
        edit.submenu?.title = L10n.text("menu.edit", language: .es)
        AppMenuBarOrganizer.normalize(mainMenu: menu, windowsMenu: nil, helpMenu: nil)
        XCTAssertTrue(menu.items[2] === edit)
        XCTAssertEqual(edit.title, "Edit")
        XCTAssertEqual(edit.submenu?.title, "Edit")
    }

    private func item(_ id: MenuActionId, in sections: [MenuSection]) -> MenuActionItem? {
        for section in sections {
            for item in section.items {
                if item.id == id { return item }
                if let nested = item.subitems?.first(where: { $0.id == id }) { return nested }
            }
        }
        return nil
    }

    private func actionIDs(_ sections: [MenuSection]) -> [MenuActionId] {
        sections.flatMap { section in section.items.flatMap(actionIDs) }
    }

    private func actionIDs(_ item: MenuActionItem) -> [MenuActionId] {
        [item.id] + (item.subitems ?? []).flatMap(actionIDs)
    }

    @objc private func noop(_ sender: NSSegmentedControl) {}

    private struct FactsSnapshot: Equatable {
        let isLoggedIn: Bool
        let inLibrary: TriStateStatus
        let isOwned: TriStateStatus
        let sortEditable: Bool
        let isSubscribed: TriStateStatus
        let isCurrentPlayingTrack: Bool
        let isLiked: Bool
        let userPlaylists: [BrowseCardRecord]

        @MainActor init(_ facts: MenuFacts) {
            isLoggedIn = facts.isLoggedIn
            inLibrary = facts.inLibrary
            isOwned = facts.isOwned
            sortEditable = facts.sortEditable
            isSubscribed = facts.isSubscribed
            isCurrentPlayingTrack = facts.isCurrentPlayingTrack
            isLiked = facts.isLiked
            userPlaylists = facts.userPlaylists
        }
    }
}
