import AppKit
import SwiftUI
import SideBCore

private struct SideBMenuContextKey: FocusedValueKey {
    typealias Value = AppMenuContext
}

extension FocusedValues {
    var sideBMenuContext: AppMenuContext? {
        get { self[SideBMenuContextKey.self] }
        set { self[SideBMenuContextKey.self] = newValue }
    }
}

private struct AppMenuContextEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppMenuContext? = nil
}

extension EnvironmentValues {
    var sideBMenuContext: AppMenuContext? {
        get { self[AppMenuContextEnvironmentKey.self] }
        set { self[AppMenuContextEnvironmentKey.self] = newValue }
    }
}

/// Estado de comandos perteneciente a una ventana, incluso cuando hay varias ventanas abiertas.
@MainActor
@Observable
final class AppMenuContext {
    var selectedSong: SongItemRecord?
    var player: PlayerViewModel?
    var router: NavigationRouter?
    var core: SideBCore?
    var account: AccountViewModel?
    var library: LibraryViewModel?
    var cookieStorage: CookieStorage?
    var sidebar: Binding<Bool>?
    var search: Binding<Bool>?
    var loginSheet: Binding<Bool>?
    var createPlaylistSheet: Binding<Bool>?
    var onLogout: (() -> Void)?

    var song: SongItemRecord? { selectedSong ?? player?.currentTrack }
    var isLoggedIn: Bool { account?.isLoggedIn == true }

    func select(_ song: SongItemRecord) { selectedSong = song }
    func clearSelection() { selectedSong = nil }

    func executeSong(_ action: MenuActionId) {
        guard let song, let player else { return }
        let facts = songFacts(for: song)
        MenuActionExecutor(player: player, router: router, core: core)
            .execute(action: action, target: .song(song), facts: facts)
    }

    func songFacts(for song: SongItemRecord) -> MenuFacts {
        MenuFacts(
            isLoggedIn: isLoggedIn,
            isCurrentPlayingTrack: player?.currentTrack?.videoId == song.videoId,
            isLiked: player?.likedVideoIds.contains(song.videoId) == true,
            userPlaylists: isLoggedIn ? (library?.playlists ?? []) : []
        )
    }

    func canExecuteSong(_ action: MenuActionId) -> Bool {
        switch action {
        case .toggleLike, .toggleLibrary, .addToPlaylist, .createPlaylistAndAdd:
            return isLoggedIn
        default:
            return true
        }
    }

    func logout() {
        guard let account, let core, let cookieStorage else { return }
        account.logout(core: core, storage: cookieStorage) { self.onLogout?() }
    }
}

struct SideBMenuCommands: Commands {
    @FocusedValue(\.sideBMenuContext) private var context

    var body: some Commands {
        let _ = L10n.revision
        CommandGroup(after: .appInfo) {
            Button(L10n.text("menu.check_updates")) {
                Task {
                    await UpdateService.shared.checkForUpdates(manual: true)
                }
            }
        }

        CommandGroup(replacing: .newItem) {}

        CommandMenu(L10n.text("menu.file")) {
            Button(L10n.text("menu.new_playlist_ellipsis")) {
                context?.createPlaylistSheet?.wrappedValue = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(context?.isLoggedIn != true)

            Divider()
            Button(L10n.text("menu.close")) { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
        }

        CommandMenu(L10n.text("menu.song")) {
            songCommands
        }

        CommandMenu(L10n.text("menu.view")) {
            Toggle(L10n.text("menu.sidebar"), isOn: Binding(
                get: { context?.sidebar?.wrappedValue ?? false },
                set: { context?.sidebar?.wrappedValue = $0 }
            ))
            .disabled(context?.sidebar == nil)

            Button(L10n.text("menu.search")) { context?.search?.wrappedValue = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(context?.search == nil)

            Divider()
            Toggle(L10n.text("menu.queue"), isOn: panelBinding(.queue))
                .disabled(context?.player?.currentTrack == nil)
            Toggle(L10n.text("menu.lyrics"), isOn: panelBinding(.lyrics))
                .disabled(context?.player?.currentTrack == nil)
            Toggle(L10n.text("menu.related"), isOn: panelBinding(.recommended))
                .disabled(context?.player?.currentTrack == nil)

            Divider()
            Button(NSApp.keyWindow?.styleMask.contains(.fullScreen) == true ? L10n.text("menu.exit_fullscreen") : L10n.text("menu.enter_fullscreen")) {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }

        CommandMenu(L10n.text("menu.controls")) {
            Button(context?.player?.isPlaying == true ? L10n.text("menu.pause") : L10n.text("menu.play")) {
                context?.player?.togglePlayPause()
            }
            .disabled(context?.player?.currentTrack == nil)

            Button(L10n.text("menu.next_track")) { context?.player?.playNext() }
                .disabled(context?.player?.queueManager.hasNext != true)
            Button(L10n.text("menu.previous_track")) {
                guard let player = context?.player else { return }
                if player.currentTime > 3 { player.seek(toFraction: 0) }
                else { player.playPrevious() }
            }
            .disabled(context?.player?.currentTrack == nil)

            Divider()
            Button(L10n.text("menu.volume_up")) {
                guard let player = context?.player else { return }
                player.volume = min(1, player.volume + 0.1)
            }
            Button(L10n.text("menu.volume_down")) {
                guard let player = context?.player else { return }
                player.volume = max(0, player.volume - 0.1)
            }
            Button(context?.player?.volume == 0 ? L10n.text("menu.unmute") : L10n.text("menu.mute")) {
                context?.player?.toggleMute()
            }

            Divider()
            Toggle(L10n.text("menu.shuffle"), isOn: Binding(
                get: { context?.player?.queueManager.isShuffle ?? false },
                set: { _ in context?.player?.queueManager.toggleShuffle() }
            ))
            .disabled(context?.player?.currentTrack == nil)
            Toggle(L10n.text("menu.repeat"), isOn: Binding(
                get: { context?.player?.queueManager.isRepeat ?? false },
                set: { context?.player?.queueManager.isRepeat = $0 }
            ))
            .disabled(context?.player?.currentTrack == nil)
        }

        CommandMenu(L10n.text("menu.account")) {
            if context?.isLoggedIn == true {
                Button(L10n.text("account.sign_out")) { context?.logout() }
            } else {
                Button(L10n.text("account.sign_in_ellipsis")) { context?.loginSheet?.wrappedValue = true }
            }
        }
    }

    private func panelBinding(_ panel: FullscreenPanel) -> Binding<Bool> {
        Binding(
            get: {
                context?.player?.isFullscreenPresented == true &&
                    context?.player?.selectedFullscreenPanel == panel
            },
            set: { enabled in
                guard let player = context?.player else { return }
                if enabled { player.toggleFullscreenPanel(panel) }
                else if player.selectedFullscreenPanel == panel { player.dismissFullscreen() }
            }
        )
    }

    @ViewBuilder
    private var songCommands: some View {
        if let context, let song = context.song {
            let facts = context.songFacts(for: song)
            let origin = context.selectedSong == nil ? MenuOrigin.nowPlaying : (context.router?.currentPage.asMenuOrigin ?? .home)
            let sections = MenuPolicy.resolveSections(target: .song(song), origin: origin, facts: facts)
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                if index > 0 { Divider() }
                ForEach(section.items) { item in
                    if let subitems = item.subitems {
                        Menu(item.title) {
                            ForEach(subitems) { subitem in
                                Button(subitem.title) { context.executeSong(subitem.id) }
                                    .disabled(!subitem.isEnabled || !context.canExecuteSong(subitem.id))
                            }
                        }
                    } else {
                        Button(item.title) { context.executeSong(item.id) }
                            .disabled(!item.isEnabled || !context.canExecuteSong(item.id))
                    }
                }
            }
        } else {
            Button(L10n.text("menu.no_song_selected")) {}
                .disabled(true)
        }
    }
}

/// SwiftUI coloca el CommandMenu de Visualización junto al menú nativo que AppKit
/// puede agregar. Ordenamos por identidad de menús estándar y títulos de nuestros
/// propios comandos, sin depender del idioma del sistema para los menús nativos.
@MainActor
enum AppMenuBarOrganizer {
    private static let localizedMenuKeys = [
        "menu.file", "menu.song", "menu.view", "menu.controls", "menu.account"
    ]

    static func normalize() {
        normalize(mainMenu: NSApp.mainMenu, windowsMenu: NSApp.windowsMenu, helpMenu: NSApp.helpMenu)
    }

    static func normalize(mainMenu: NSMenu?, windowsMenu: NSMenu?, helpMenu: NSMenu?) {
        guard let mainMenu else { return }

        let viewItems = mainMenu.items.filter { matchesMenuTitle($0.title, key: "menu.view") }
        if viewItems.count > 1, let automaticView = viewItems.first {
            mainMenu.removeItem(automaticView)
        }

        // Keep our command menu titles in sync when the app language changes.
        for key in localizedMenuKeys {
            retitle(findLocalizedMenu(key, in: mainMenu), key: key)
        }

        let editItem = findEditMenu(in: mainMenu) ?? findLocalizedMenu("menu.edit", in: mainMenu)
        retitle(editItem, key: "menu.edit")
        let windowsItem = findMenu(for: windowsMenu, in: mainMenu) ?? findLocalizedMenu("menu.window", in: mainMenu)
        retitle(windowsItem, key: "menu.window")
        let helpItem = findMenu(for: helpMenu, in: mainMenu) ?? findLocalizedMenu("menu.help", in: mainMenu)
        retitle(helpItem, key: "menu.help")

        let orderedItems = [
            findLocalizedMenu("menu.file", in: mainMenu),
            editItem,
            findLocalizedMenu("menu.song", in: mainMenu),
            findLocalizedMenu("menu.view", in: mainMenu),
            findLocalizedMenu("menu.controls", in: mainMenu),
            findLocalizedMenu("menu.account", in: mainMenu),
            windowsItem,
            helpItem
        ].compactMap { $0 }

        for (offset, item) in orderedItems.enumerated() {
            let targetIndex = offset + 1 // El menú de la aplicación permanece primero.
            guard mainMenu.index(of: item) != targetIndex else { continue }
            mainMenu.removeItem(item)
            mainMenu.insertItem(item, at: min(targetIndex, mainMenu.items.count))
        }
    }

    private static func findLocalizedMenu(_ key: String, in mainMenu: NSMenu) -> NSMenuItem? {
        mainMenu.items.first { matchesMenuTitle($0.title, key: key) }
    }

    private static func retitle(_ item: NSMenuItem?, key: String) {
        let title = L10n.text(key)
        guard let item else { return }
        if item.title != title { item.title = title }
        // AppKit displays the submenu title in the menu bar, not the item title.
        if let submenu = item.submenu, submenu.title != title { submenu.title = title }
    }

    private static func matchesMenuTitle(_ title: String, key: String) -> Bool {
        AppLanguage.allCases.contains { L10n.text(key, language: $0) == title }
    }

    private static func findMenu(for menu: NSMenu?, in mainMenu: NSMenu) -> NSMenuItem? {
        guard let menu else { return nil }
        return mainMenu.items.first { $0.submenu === menu }
    }

    private static func findEditMenu(in mainMenu: NSMenu) -> NSMenuItem? {
        let standardEditActions: Set<Selector> = [Selector(("cut:")), Selector(("copy:")), Selector(("paste:"))]
        return mainMenu.items.first { item in
            guard let submenu = item.submenu else { return false }
            let actions = Set(submenu.items.compactMap(\.action))
            let shortcuts = Set(submenu.items.filter { $0.keyEquivalentModifierMask == [.command] }.map { $0.keyEquivalent.lowercased() })
            // SwiftUI can wrap responder actions behind its own selectors.
            return standardEditActions.isSubset(of: actions) || Set(["x", "c", "v"]).isSubset(of: shortcuts)
        }
    }
}
