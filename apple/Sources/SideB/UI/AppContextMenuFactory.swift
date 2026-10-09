import AppKit
import SwiftUI
import SideBCore

// MARK: - AppContextMenuFactory

/// Fábrica universal de menús contextuales nativos para Side B (PLAN-007).
/// Canaliza las peticiones de AppKit y SwiftUI a través de MenuPolicy puro y MenuActionExecutor.
@MainActor
final class AppContextMenuFactory {
    static let shared = AppContextMenuFactory()
    public static var cachedUserPlaylists: [BrowseCardRecord] = []
    public static var cachedUserAlbums: [BrowseCardRecord] = []

    private init() {}

    static func addSong(_ song: SongItemRecord, to playlistId: String, core: SideBCore) {
        Task {
            do {
                try await core.addToPlaylist(playlistId: playlistId, videoId: song.videoId)
                NotificationCenter.default.post(name: .sideBPlaylistsChanged, object: nil)
            } catch {
                showError(L10n.text("menu.error_add_song"), detail: error.localizedDescription)
            }
        }
    }

    static func applyLibraryAction(token: String, core: SideBCore) {
        Task {
            do {
                try await core.applySongLibraryAction(token: token)
                NotificationCenter.default.post(name: .sideBSongLibraryChanged, object: nil)
            } catch {
                showError(L10n.text("menu.error_update_library"), detail: error.localizedDescription)
            }
        }
    }

    private static func showError(_ title: String, detail: String) {
        MenuActionExecutor.showErrorAlert(title: title, detail: detail)
    }

    // MARK: - Helper de Compartir

    static func shareURL(_ url: URL) {
        MenuActionExecutor.shareURL(url)
    }

    static func isCurrentPlayingOccurrence(origin: MenuOrigin, player: PlayerViewModel) -> Bool {
        switch origin {
        case .nowPlaying:
            return true
        case .queue(let index):
            return index == player.queueManager.currentIndex
        default:
            return false
        }
    }

    // MARK: - AppKit NSMenu para Canciones

    func buildSongNSMenu(
        song: SongItemRecord,
        player: PlayerViewModel,
        router: NavigationRouter?,
        core: SideBCore?,
        origin: MenuOrigin? = nil,
        playlistContext: (playlistId: String, isOwned: Bool)? = nil,
        onRemoveFromPlaylist: (@MainActor @Sendable (SongItemRecord) -> Void)? = nil
    ) -> NSMenu {
        let resolvedOrigin: MenuOrigin
        if let origin {
            resolvedOrigin = origin
        } else if let ctx = playlistContext {
            resolvedOrigin = .playlist(id: ctx.playlistId)
        } else {
            resolvedOrigin = router?.currentPage.asMenuOrigin ?? .home
        }

        let isLiked = player.likedVideoIds.contains(song.videoId)
        let isCurrentPlaying = Self.isCurrentPlayingOccurrence(origin: resolvedOrigin, player: player)

        let isOwned: TriStateStatus
        if let ctx = playlistContext {
            isOwned = .known(ctx.isOwned)
        } else {
            isOwned = .unknown
        }

        let facts = MenuFacts(
            isLoggedIn: core?.isLoggedIn() ?? false,
            isOwned: isOwned,
            isCurrentPlayingTrack: isCurrentPlaying,
            isLiked: isLiked,
            userPlaylists: Self.cachedUserPlaylists,
            onRemoveFromPlaylist: {
                onRemoveFromPlaylist?(song)
            }
        )

        // Pre-carga asíncrona de playlists si la caché está vacía
        if Self.cachedUserPlaylists.isEmpty, let core {
            Task { @MainActor in
                if let userPlaylists = try? await core.getLibraryPlaylists() {
                    Self.cachedUserPlaylists = userPlaylists
                }
            }
        }

        let executor = MenuActionExecutor(player: player, router: router, core: core)
        let target = MenuTarget.song(song)
        let sections = MenuPolicy.resolveSections(target: target, origin: resolvedOrigin, facts: facts)
        return AppKitMenuAdapter.buildNSMenu(sections: sections, target: target, facts: facts, executor: executor)
    }

    // MARK: - AppKit NSMenu para Álbumes

    func buildAlbumNSMenu(
        browseId: String,
        playlistId: String?,
        title: String,
        artist: String?,
        thumbnail: String?,
        inLibrary: Bool? = nil,
        origin: MenuOrigin? = nil,
        player: PlayerViewModel,
        router: NavigationRouter?,
        core: SideBCore?
    ) -> NSMenu {
        let resolvedOrigin = origin ?? (router?.currentPage.asMenuOrigin ?? .home)
        let inLibStatus: TriStateStatus
        if let inLibrary {
            inLibStatus = .known(inLibrary)
        } else if Self.cachedUserAlbums.contains(where: { $0.id == browseId }) {
            inLibStatus = .known(true)
        } else {
            inLibStatus = .unknown
        }

        let facts = MenuFacts(
            isLoggedIn: core?.isLoggedIn() ?? false,
            inLibrary: inLibStatus,
            userPlaylists: Self.cachedUserPlaylists
        )

        let target = MenuTarget.album(
            browseId: browseId,
            playlistId: playlistId,
            title: title,
            artist: artist,
            artistId: nil,
            thumbnail: thumbnail
        )
        let executor = MenuActionExecutor(player: player, router: router, core: core)
        let sections = MenuPolicy.resolveSections(target: target, origin: resolvedOrigin, facts: facts)
        return AppKitMenuAdapter.buildNSMenu(sections: sections, target: target, facts: facts, executor: executor)
    }

    // MARK: - AppKit NSMenu para Playlists

    func buildPlaylistNSMenu(
        id: String,
        title: String,
        subtitle: String?,
        thumbnail: String?,
        inLibrary: Bool? = nil,
        isOwned: Bool? = nil,
        sortEditable: Bool = false,
        origin: MenuOrigin? = nil,
        player: PlayerViewModel,
        router: NavigationRouter?,
        core: SideBCore?,
        onEdit: (@MainActor @Sendable () -> Void)? = nil,
        onDelete: (@MainActor @Sendable () -> Void)? = nil,
        onSort: (@MainActor @Sendable (String) -> Void)? = nil
    ) -> NSMenu {
        let resolvedOrigin = origin ?? (router?.currentPage.asMenuOrigin ?? .home)
        let inLibStatus: TriStateStatus
        if let inLibrary {
            inLibStatus = .known(inLibrary)
        } else if Self.cachedUserPlaylists.contains(where: { $0.id == id }) {
            inLibStatus = .known(true)
        } else {
            inLibStatus = .unknown
        }

        let isOwnedStatus: TriStateStatus
        if let isOwned {
            isOwnedStatus = .known(isOwned)
        } else {
            isOwnedStatus = .unknown
        }

        let isMix = MenuIDNormalizer.isDynamicRadioMix(id: id)
        let facts = MenuFacts(
            isLoggedIn: core?.isLoggedIn() ?? false,
            inLibrary: inLibStatus,
            isOwned: isOwnedStatus,
            sortEditable: sortEditable,
            userPlaylists: Self.cachedUserPlaylists,
            onEditPlaylist: onEdit,
            onDeletePlaylist: onDelete,
            onSortPlaylist: onSort
        )

        let target = MenuTarget.playlist(
            id: id,
            title: title,
            subtitle: subtitle,
            thumbnail: thumbnail,
            isRadioMix: isMix
        )
        let executor = MenuActionExecutor(player: player, router: router, core: core)
        let sections = MenuPolicy.resolveSections(target: target, origin: resolvedOrigin, facts: facts)
        return AppKitMenuAdapter.buildNSMenu(sections: sections, target: target, facts: facts, executor: executor)
    }

    // MARK: - AppKit NSMenu para Artistas

    func buildArtistNSMenu(
        channelId: String,
        name: String,
        thumbnail: String?,
        radioPlaylistId: String?,
        subscribed: Bool? = nil,
        origin: MenuOrigin? = nil,
        player: PlayerViewModel,
        router: NavigationRouter?,
        core: SideBCore?
    ) -> NSMenu {
        let resolvedOrigin = origin ?? (router?.currentPage.asMenuOrigin ?? .home)
        let subStatus: TriStateStatus
        if let subscribed {
            subStatus = .known(subscribed)
        } else {
            subStatus = .unknown
        }

        let facts = MenuFacts(
            isLoggedIn: core?.isLoggedIn() ?? false,
            isSubscribed: subStatus,
            userPlaylists: Self.cachedUserPlaylists
        )

        let target = MenuTarget.artist(
            channelId: channelId,
            name: name,
            thumbnail: thumbnail,
            radioPlaylistId: radioPlaylistId
        )
        let executor = MenuActionExecutor(player: player, router: router, core: core)
        let sections = MenuPolicy.resolveSections(target: target, origin: resolvedOrigin, facts: facts)
        return AppKitMenuAdapter.buildNSMenu(sections: sections, target: target, facts: facts, executor: executor)
    }
}

// MARK: - ActionMenuItem (NSMenuItem que retiene y ejecuta closures fuertemente)

final class ActionMenuItem: NSMenuItem {
    private var actionTarget: NSMenuItemActionTarget?

    convenience init(title: String, systemImageName: String? = nil, action: @escaping () -> Void) {
        self.init(title: title, action: #selector(NSMenuItemActionTarget.onAction(_:)), keyEquivalent: "")
        if let icon = systemImageName, !icon.isEmpty {
            self.image = AppKitMenuAdapter.menuSymbol(named: icon)
            if #available(macOS 27.0, *) {
                self.preferredImageVisibility = .visible
            }
        }
        let target = NSMenuItemActionTarget(action: action)
        self.actionTarget = target
        self.target = target
    }
}

// MARK: - NSMenuItemActionTarget (Ejecuta closures para NSMenuItem)

private final class NSMenuItemActionTarget: NSObject, NSMenuItemValidation {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init()
    }

    @objc func onAction(_ sender: Any?) {
        action()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return menuItem.isEnabled
    }
}

// MARK: - NativeContextMenuOverlay (Cero Overhead en Scroll a 120 FPS)

/// Overlay transparente de AppKit que intercepta única y exclusivamente el clic secundario
/// (clic derecho o Control+Clic) para desplegar el NSMenu nativo bajo demanda.
public struct NativeContextMenuOverlay: NSViewRepresentable {
    private let menuProvider: () -> NSMenu?

    public init(menuProvider: @escaping () -> NSMenu?) {
        self.menuProvider = menuProvider
    }

    public func makeNSView(context: Context) -> NativeContextMenuNSView {
        let view = NativeContextMenuNSView()
        view.menuBuilder = menuProvider
        return view
    }

    public func updateNSView(_ nsView: NativeContextMenuNSView, context: Context) {
        nsView.menuBuilder = menuProvider
    }
}

public final class NativeContextMenuNSView: NSView {
    var menuBuilder: (() -> NSMenu?)?

    public override func layout() {}
    public override var isOpaque: Bool { false }
    public override func draw(_ dirtyRect: NSRect) {}
    public override var wantsDefaultClipping: Bool { false }
    public override var wantsUpdateLayer: Bool { true }
    public override func updateLayer() {}

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let currentEvent = NSApp.currentEvent else { return nil }
        if currentEvent.type == .rightMouseDown ||
           (currentEvent.type == .leftMouseDown && currentEvent.modifierFlags.contains(.control)) {
            return super.hitTest(point) == nil ? nil : self
        }
        return nil
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        return menuBuilder?()
    }

    public override func rightMouseDown(with event: NSEvent) {
        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    public override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            if let menu = menu(for: event) {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
                return
            }
        }
        super.mouseDown(with: event)
    }
}

// MARK: - SwiftUI Context Menu Modifiers (PLAN-007)

struct SongMenuItems: View {
    let song: SongItemRecord
    let player: PlayerViewModel
    let router: NavigationRouter?
    let core: SideBCore?
    var origin: MenuOrigin? = nil
    var playlistContext: (playlistId: String, isOwned: Bool)? = nil
    var onRemoveFromPlaylist: (@MainActor @Sendable () -> Void)? = nil

    private var resolvedOrigin: MenuOrigin {
        if let origin {
            return origin
        } else if let ctx = playlistContext {
            return .playlist(id: ctx.playlistId)
        } else {
            return router?.currentPage.asMenuOrigin ?? .home
        }
    }

    var body: some View {
        let isLiked = player.likedVideoIds.contains(song.videoId)
        let isCurrentPlaying = AppContextMenuFactory.isCurrentPlayingOccurrence(origin: resolvedOrigin, player: player)
        let isOwned: TriStateStatus = playlistContext.map { .known($0.isOwned) } ?? .unknown

        let facts = MenuFacts(
            isLoggedIn: core?.isLoggedIn() ?? false,
            isOwned: isOwned,
            isCurrentPlayingTrack: isCurrentPlaying,
            isLiked: isLiked,
            userPlaylists: AppContextMenuFactory.cachedUserPlaylists,
            onRemoveFromPlaylist: onRemoveFromPlaylist
        )

        let executor = MenuActionExecutor(player: player, router: router, core: core)
        let sections = MenuPolicy.resolveSections(target: .song(song), origin: resolvedOrigin, facts: facts)
        MenuSectionContentView(
            sections: sections,
            target: .song(song),
            facts: facts,
            executor: executor
        )
        .labelStyle(.titleAndIcon)
    }
}

extension View {
    @ViewBuilder
    func browseCardContextMenu(
        card: BrowseCardRecord,
        player: PlayerViewModel,
        router: NavigationRouter?,
        core: SideBCore?,
        origin: MenuOrigin? = nil,
        fallbackArtist: String? = nil,
        knownArtistId: String? = nil
    ) -> some View {
        let resolvedOrigin = origin ?? (router?.currentPage.asMenuOrigin ?? .home)
        switch card.kind.lowercased() {
        case "song", "video":
            let song = SongItemRecord(fromCard: card, fallbackArtist: fallbackArtist, knownArtistId: knownArtistId)
            let isLiked = player.likedVideoIds.contains(song.videoId)
            let isCurrent = AppContextMenuFactory.isCurrentPlayingOccurrence(origin: resolvedOrigin, player: player)
            let facts = MenuFacts(
                isLoggedIn: core?.isLoggedIn() ?? false,
                isCurrentPlayingTrack: isCurrent,
                isLiked: isLiked,
                userPlaylists: AppContextMenuFactory.cachedUserPlaylists
            )
            self.sideBContextMenu(
                target: .song(song),
                origin: resolvedOrigin,
                facts: facts,
                player: player,
                router: router,
                core: core
            )
        case "album":
            let target = MenuTarget.album(
                browseId: card.id,
                playlistId: nil,
                title: card.title,
                artist: card.subtitle,
                artistId: knownArtistId,
                thumbnail: card.thumbnail
            )
            let inLib = AppContextMenuFactory.cachedUserAlbums.contains(where: { $0.id == card.id })
            let facts = MenuFacts(
                isLoggedIn: core?.isLoggedIn() ?? false,
                inLibrary: inLib ? .known(true) : .unknown,
                userPlaylists: AppContextMenuFactory.cachedUserPlaylists
            )
            self.sideBContextMenu(
                target: target,
                origin: resolvedOrigin,
                facts: facts,
                player: player,
                router: router,
                core: core
            )
        case "artist":
            let target = MenuTarget.artist(
                channelId: card.id,
                name: card.title,
                thumbnail: card.thumbnail,
                radioPlaylistId: nil
            )
            let facts = MenuFacts(
                isLoggedIn: core?.isLoggedIn() ?? false,
                userPlaylists: AppContextMenuFactory.cachedUserPlaylists
            )
            self.sideBContextMenu(
                target: target,
                origin: resolvedOrigin,
                facts: facts,
                player: player,
                router: router,
                core: core
            )
        default:
            let isMix = MenuIDNormalizer.isDynamicRadioMix(id: card.id)
            let target = MenuTarget.playlist(
                id: card.id,
                title: card.title,
                subtitle: card.subtitle,
                thumbnail: card.thumbnail,
                isRadioMix: isMix
            )
            let inLib = AppContextMenuFactory.cachedUserPlaylists.contains(where: { $0.id == card.id })
            let facts = MenuFacts(
                isLoggedIn: core?.isLoggedIn() ?? false,
                inLibrary: inLib ? .known(true) : .unknown,
                userPlaylists: AppContextMenuFactory.cachedUserPlaylists
            )
            self.sideBContextMenu(
                target: target,
                origin: resolvedOrigin,
                facts: facts,
                player: player,
                router: router,
                core: core
            )
        }
    }

    /// Menú contextual unificado para canciones mostradas con SwiftUI.
    func songContextMenu(
        song: SongItemRecord,
        player: PlayerViewModel,
        router: NavigationRouter?,
        core: SideBCore?,
        origin: MenuOrigin? = nil,
        playlistContext: (playlistId: String, isOwned: Bool)? = nil,
        onRemoveFromPlaylist: (@MainActor @Sendable () -> Void)? = nil
    ) -> some View {
        self.contextMenu {
            SongMenuItems(
                song: song,
                player: player,
                router: router,
                core: core,
                origin: origin,
                playlistContext: playlistContext,
                onRemoveFromPlaylist: onRemoveFromPlaylist
            )
            .labelStyle(.titleAndIcon)
        }
    }

    /// Menú contextual de Álbum
    func albumCardContextMenu(
        browseId: String,
        playlistId: String?,
        title: String,
        artist: String?,
        thumbnail: String?,
        inLibrary: Bool? = nil,
        origin: MenuOrigin? = nil,
        player: PlayerViewModel,
        router: NavigationRouter?,
        core: SideBCore?
    ) -> some View {
        let resolvedOrigin = origin ?? (router?.currentPage.asMenuOrigin ?? .home)
        let inLibStatus: TriStateStatus
        if let inLibrary {
            inLibStatus = .known(inLibrary)
        } else if AppContextMenuFactory.cachedUserAlbums.contains(where: { $0.id == browseId }) {
            inLibStatus = .known(true)
        } else {
            inLibStatus = .unknown
        }

        let facts = MenuFacts(
            isLoggedIn: core?.isLoggedIn() ?? false,
            inLibrary: inLibStatus,
            userPlaylists: AppContextMenuFactory.cachedUserPlaylists
        )
        let target = MenuTarget.album(
            browseId: browseId,
            playlistId: playlistId,
            title: title,
            artist: artist,
            artistId: nil,
            thumbnail: thumbnail
        )
        return self.sideBContextMenu(
            target: target,
            origin: resolvedOrigin,
            facts: facts,
            player: player,
            router: router,
            core: core
        )
    }

    /// Menú contextual de Playlist
    func playlistCardContextMenu(
        id: String,
        title: String,
        subtitle: String?,
        thumbnail: String?,
        inLibrary: Bool? = nil,
        isOwned: Bool? = nil,
        sortEditable: Bool = false,
        origin: MenuOrigin? = nil,
        player: PlayerViewModel,
        router: NavigationRouter?,
        core: SideBCore?,
        onEdit: (@MainActor @Sendable () -> Void)? = nil,
        onDelete: (@MainActor @Sendable () -> Void)? = nil,
        onSort: (@MainActor @Sendable (String) -> Void)? = nil
    ) -> some View {
        let resolvedOrigin = origin ?? (router?.currentPage.asMenuOrigin ?? .home)
        let inLibStatus: TriStateStatus
        if let inLibrary {
            inLibStatus = .known(inLibrary)
        } else if AppContextMenuFactory.cachedUserPlaylists.contains(where: { $0.id == id }) {
            inLibStatus = .known(true)
        } else {
            inLibStatus = .unknown
        }

        let isOwnedStatus: TriStateStatus
        if let isOwned {
            isOwnedStatus = .known(isOwned)
        } else {
            isOwnedStatus = .unknown
        }

        let isMix = MenuIDNormalizer.isDynamicRadioMix(id: id)
        let facts = MenuFacts(
            isLoggedIn: core?.isLoggedIn() ?? false,
            inLibrary: inLibStatus,
            isOwned: isOwnedStatus,
            sortEditable: sortEditable,
            userPlaylists: AppContextMenuFactory.cachedUserPlaylists,
            onEditPlaylist: onEdit,
            onDeletePlaylist: onDelete,
            onSortPlaylist: onSort
        )
        let target = MenuTarget.playlist(
            id: id,
            title: title,
            subtitle: subtitle,
            thumbnail: thumbnail,
            isRadioMix: isMix
        )
        return self.sideBContextMenu(
            target: target,
            origin: resolvedOrigin,
            facts: facts,
            player: player,
            router: router,
            core: core
        )
    }

    /// Menú contextual de Artista
    func artistCardContextMenu(
        channelId: String,
        name: String,
        thumbnail: String?,
        radioPlaylistId: String?,
        subscribed: Bool? = nil,
        origin: MenuOrigin? = nil,
        player: PlayerViewModel,
        router: NavigationRouter?,
        core: SideBCore?
    ) -> some View {
        let resolvedOrigin = origin ?? (router?.currentPage.asMenuOrigin ?? .home)
        let subStatus: TriStateStatus
        if let subscribed {
            subStatus = .known(subscribed)
        } else {
            subStatus = .unknown
        }

        let facts = MenuFacts(
            isLoggedIn: core?.isLoggedIn() ?? false,
            isSubscribed: subStatus,
            userPlaylists: AppContextMenuFactory.cachedUserPlaylists
        )
        let target = MenuTarget.artist(
            channelId: channelId,
            name: name,
            thumbnail: thumbnail,
            radioPlaylistId: radioPlaylistId
        )
        return self.sideBContextMenu(
            target: target,
            origin: resolvedOrigin,
            facts: facts,
            player: player,
            router: router,
            core: core
        )
    }
}
