import AppKit
import Foundation
import SideBCore

// MARK: - MenuActionExecutor

/// Ejecutor centralizado y único para todas las acciones de menú contextual (PLAN-007).
/// Se encarga de la invocación de AVPlayer/QueueManager, comunicación con Core/UniFFI,
/// navegación de páginas, feedback nativo de compartir y manejo explícito de errores con rollback.
@MainActor
final class MenuActionExecutor {
    private weak var player: PlayerViewModel?
    private weak var router: NavigationRouter?
    private let core: SideBCore?

    init(
        player: PlayerViewModel?,
        router: NavigationRouter?,
        core: SideBCore?
    ) {
        self.player = player
        self.router = router
        self.core = core
    }

    // MARK: - Ejecución Central

    func execute(
        action: MenuActionId,
        target: MenuTarget,
        facts: MenuFacts
    ) {
        print("[MenuActionExecutor] Ejecutando acción: \(action) sobre \(target)")
        switch action {
        // --- 1. Reproducción ---
        case .play:
            executePlay(target: target)
        case .shuffle:
            executeShuffle(target: target)
        case .startMix:
            executeStartMix(target: target)
        case .playNext:
            executePlayNext(target: target)
        case .addToQueue:
            executeAddToQueue(target: target)

        // --- 2. Colección ---
        case .toggleLike:
            if case .song(let song) = target, let player {
                player.toggleTrackLike(song)
            }
        case .toggleLibrary(let inLibrary):
            executeToggleLibrary(target: target, inLibrary: inLibrary)
        case .addToPlaylist(let playlistId, _):
            if case .song(let song) = target {
                executeAddSongToPlaylist(song: song, playlistId: playlistId)
            }
        case .createPlaylistAndAdd:
            if case .song(let song) = target {
                NotificationCenter.default.post(
                    name: .sideBRequestCreatePlaylist,
                    object: nil,
                    userInfo: ["videoId": song.videoId]
                )
            }
        case .toggleSubscription(let subscribed):
            if case .artist(let channelId, _, _, _) = target {
                executeToggleSubscription(channelId: channelId, subscribed: subscribed)
            }

        // --- 3. Navegación ---
        case .goToAlbum(let browseId):
            router?.navigate(to: .album(browseId: browseId))
        case .goToArtist(let channelId):
            router?.navigate(to: .artist(browseId: channelId))
        case .goToPlaylist(let id):
            let canonicalId = MenuIDNormalizer.canonicalPlaylistId(id)
            router?.navigate(to: .playlist(browseId: canonicalId))

        // --- 4. Compartir ---
        case .share:
            executeShare(target: target)

        // --- 5. Edición y Destructivas ---
        case .editDetails:
            facts.onEditPlaylist?()
        case .sort(let value, _):
            facts.onSortPlaylist?(value)
        case .removeFromPlaylist:
            facts.onRemoveFromPlaylist?()
        case .removeFromQueue(let index):
            if let customCallback = facts.onRemoveFromQueue {
                customCallback(index)
            } else if let player {
                player.removeQueueTrack(at: index)
            }
        case .deletePlaylist:
            executeDeletePlaylist(target: target, facts: facts)
        }
    }

    // MARK: - Handlers de Reproducción

    private func executePlay(target: MenuTarget) {
        guard let player else { return }
        switch target {
        case .song(let song):
            player.playWithRadio(song)
        case .album(let browseId, _, _, _, _, _):
            let queueToken = player.queueManager.queueToken
            Task {
                guard let core, let album = try? await core.getAlbum(browseId: browseId), !album.items.isEmpty else {
                    return
                }
                guard !Task.isCancelled, player.queueManager.queueToken == queueToken else { return }
                player.playAlbum(
                    browseId: album.browseId,
                    title: album.title,
                    tracks: album.items,
                    startingAt: 0,
                    artistBrowseId: album.artistId
                )
            }
        case .playlist(let id, _, _, _, _):
            let canonicalId = MenuIDNormalizer.canonicalPlaylistId(id)
            let queueToken = player.queueManager.queueToken
            Task {
                guard let core else { return }
                let pl: PlaylistDetailRecord
                do { pl = try await PlaylistCatalog.shared.load(id: canonicalId, core: core) }
                catch { return }
                guard !Task.isCancelled, player.queueManager.queueToken == queueToken, !pl.items.isEmpty else { return }
                player.playPlaylist(
                    browseId: pl.id,
                    title: pl.title,
                    tracks: pl.items,
                    startingAt: 0,
                    continuation: pl.continuation
                )
            }
        case .radioMix(let id, let title, _, _):
            let canonicalId = MenuIDNormalizer.canonicalPlaylistId(id)
            player.startRadioForCollection(id: canonicalId, title: title)
        case .artist(let channelId, let name, _, let radioId):
            player.startRadioForCollection(
                id: channelId,
                title: name,
                prefix: "RDAMVM",
                directRadioId: radioId
            )
        }
    }

    private func executeShuffle(target: MenuTarget) {
        guard let player else { return }
        switch target {
        case .song:
            break
        case .album(let browseId, _, _, _, _, _):
            let queueToken = player.queueManager.queueToken
            Task {
                guard let core, let album = try? await core.getAlbum(browseId: browseId), !album.items.isEmpty else {
                    return
                }
                guard !Task.isCancelled, player.queueManager.queueToken == queueToken else { return }
                player.playAlbum(
                    browseId: album.browseId,
                    title: album.title,
                    tracks: album.items,
                    startingAt: 0,
                    artistBrowseId: album.artistId,
                    shuffle: true
                )
            }
        case .playlist(let id, _, _, _, _):
            let canonicalId = MenuIDNormalizer.canonicalPlaylistId(id)
            let queueToken = player.queueManager.queueToken
            Task {
                guard let core else { return }
                do {
                    let playlist = try await PlaylistCatalog.shared.load(id: canonicalId, core: core)
                    guard !Task.isCancelled, player.queueManager.queueToken == queueToken, !playlist.items.isEmpty else { return }
                    player.playPlaylist(
                        browseId: playlist.id,
                        title: playlist.title,
                        tracks: playlist.items,
                        startingAt: 0,
                        continuation: playlist.continuation,
                        shuffle: true
                    )
                } catch {
                    Self.showErrorAlert(title: L10n.text("menu.error_shuffle_playlist"), detail: error.localizedDescription)
                }
            }
        case .radioMix, .artist:
            break
        }
    }

    private func executeStartMix(target: MenuTarget) {
        guard let player else { return }
        switch target {
        case .song(let song):
            player.playWithRadio(song)
        case .album(let browseId, let playlistId, let title, _, _, _):
            let targetId = MenuIDNormalizer.canonicalPlaylistId(playlistId ?? browseId)
            let canonicalId = MenuIDNormalizer.canonicalPlaylistId(targetId)
            player.startRadioForCollection(id: canonicalId, title: title, prefix: "RDAMPL")
        case .playlist(let id, let title, _, _, _):
            let canonicalId = MenuIDNormalizer.canonicalPlaylistId(id)
            player.startRadioForCollection(id: canonicalId, title: title, prefix: "RDAMPL")
        case .radioMix(let id, let title, _, _):
            let canonicalId = MenuIDNormalizer.canonicalPlaylistId(id)
            player.startRadioForCollection(id: canonicalId, title: title)
        case .artist(let channelId, let name, _, let radioId):
            player.startRadioForCollection(
                id: channelId,
                title: name,
                prefix: "RDAMVM",
                directRadioId: radioId
            )
        }
    }

    private func executePlayNext(target: MenuTarget) {
        guard let player else { return }
        switch target {
        case .song(let song):
            player.playNext(song: song)
        case .album(let browseId, _, _, _, _, _):
            let queueToken = player.queueManager.queueToken
            Task {
                guard let core, let album = try? await core.getAlbum(browseId: browseId) else { return }
                guard !Task.isCancelled, player.queueManager.queueToken == queueToken else { return }
                player.playNext(tracks: album.items)
            }
        case .playlist(let id, _, _, _, _):
            let canonicalId = MenuIDNormalizer.canonicalPlaylistId(id)
            let queueToken = player.queueManager.queueToken
            Task {
                guard let core else { return }
                do {
                    let playlist = try await PlaylistCatalog.shared.load(id: canonicalId, core: core)
                    guard !Task.isCancelled, player.queueManager.queueToken == queueToken else { return }
                    player.playNext(tracks: playlist.items)
                } catch {
                    Self.showErrorAlert(title: L10n.text("menu.error_play_next_playlist"), detail: error.localizedDescription)
                }
            }
        case .radioMix, .artist:
            break
        }
    }

    private func executeAddToQueue(target: MenuTarget) {
        guard let player else { return }
        switch target {
        case .song(let song):
            player.addToQueue(song: song)
        case .album(let browseId, _, _, _, _, _):
            let queueToken = player.queueManager.queueToken
            Task {
                guard let core, let album = try? await core.getAlbum(browseId: browseId) else { return }
                guard !Task.isCancelled, player.queueManager.queueToken == queueToken else { return }
                player.addToQueue(tracks: album.items)
            }
        case .playlist(let id, _, _, _, _):
            let canonicalId = MenuIDNormalizer.canonicalPlaylistId(id)
            let queueToken = player.queueManager.queueToken
            Task {
                guard let core else { return }
                do {
                    let playlist = try await PlaylistCatalog.shared.load(id: canonicalId, core: core)
                    guard !Task.isCancelled, player.queueManager.queueToken == queueToken else { return }
                    player.addToQueue(tracks: playlist.items)
                } catch {
                    Self.showErrorAlert(title: L10n.text("menu.error_queue_playlist"), detail: error.localizedDescription)
                }
            }
        case .radioMix, .artist:
            break
        }
    }

    // MARK: - Handlers de Colección

    private func executeToggleLibrary(target: MenuTarget, inLibrary: Bool) {
        guard let core else { return }
        let newStatus = !inLibrary

        switch target {
        case .song(let song):
            guard let library = song.library,
                  let token = inLibrary ? library.removeToken : library.addToken,
                  !token.isEmpty else { return }
            Task {
                do {
                    try await core.applySongLibraryAction(token: token)
                    PlaylistCatalog.shared.invalidate("LM")
                    NotificationCenter.default.post(name: .sideBSongLibraryChanged, object: nil)
                } catch {
                    Self.showErrorAlert(
                        title: L10n.text("menu.error_update_library"),
                        detail: error.localizedDescription
                    )
                }
            }

        case .album(let browseId, let playlistId, let title, let artist, _, let thumbnail):
            let targetId = playlistId ?? browseId
            let card = BrowseCardRecord(
                kind: "album",
                id: browseId,
                title: title,
                subtitle: artist,
                thumbnail: thumbnail,
                duration: nil
            )
            // Actualización optimista
            NotificationCenter.default.post(
                name: .sideBLibraryAlbumToggled,
                object: nil,
                userInfo: ["browseId": browseId, "inLibrary": newStatus, "card": card]
            )
            Task {
                do {
                    try await core.likePlaylist(playlistId: targetId, like: newStatus)
                    PlaylistCatalog.shared.invalidate(targetId)
                    NotificationCenter.default.post(name: .sideBSongLibraryChanged, object: nil)
                } catch {
                    // Rollback optimista ante fallo
                    NotificationCenter.default.post(
                        name: .sideBLibraryAlbumToggled,
                        object: nil,
                        userInfo: ["browseId": browseId, "inLibrary": inLibrary, "card": card]
                    )
                    Self.showErrorAlert(
                        title: L10n.text("menu.error_update_album_library"),
                        detail: error.localizedDescription
                    )
                }
            }

        case .playlist(let id, let title, let subtitle, let thumbnail, _),
             .radioMix(let id, let title, let subtitle, let thumbnail):
            let canonicalId = MenuIDNormalizer.canonicalPlaylistId(id)
            let card = BrowseCardRecord(
                kind: "playlist",
                id: canonicalId,
                title: title,
                subtitle: subtitle,
                thumbnail: thumbnail,
                duration: nil
            )
            NotificationCenter.default.post(
                name: .sideBLibraryPlaylistToggled,
                object: nil,
                userInfo: ["playlistId": canonicalId, "inLibrary": newStatus, "card": card]
            )
            Task {
                do {
                    try await core.likePlaylist(playlistId: canonicalId, like: newStatus)
                    PlaylistCatalog.shared.invalidate(canonicalId)
                } catch {
                    NotificationCenter.default.post(
                        name: .sideBLibraryPlaylistToggled,
                        object: nil,
                        userInfo: ["playlistId": canonicalId, "inLibrary": inLibrary, "card": card]
                    )
                    Self.showErrorAlert(
                        title: L10n.text("menu.error_update_playlist_library"),
                        detail: error.localizedDescription
                    )
                }
            }

        case .artist:
            break
        }
    }

    private func executeAddSongToPlaylist(song: SongItemRecord, playlistId: String) {
        guard let core else { return }
        let canonicalId = MenuIDNormalizer.canonicalPlaylistId(playlistId)
        Task {
            do {
                try await core.addToPlaylist(playlistId: canonicalId, videoId: song.videoId)
                PlaylistCatalog.shared.invalidate(canonicalId)
                NotificationCenter.default.post(name: .sideBPlaylistsChanged, object: nil)
            } catch {
                Self.showErrorAlert(
                    title: L10n.text("menu.error_add_song"),
                    detail: error.localizedDescription
                )
            }
        }
    }

    private func executeToggleSubscription(channelId: String, subscribed: Bool) {
        guard let core else { return }
        Task {
            do {
                try await core.subscribeArtist(channelId: channelId, subscribe: !subscribed)
            } catch {
                Self.showErrorAlert(
                    title: L10n.text("menu.error_update_subscription"),
                    detail: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Handlers de Compartir

    private func executeShare(target: MenuTarget) {
        let url: URL?
        switch target {
        case .song(let song):
            url = MenuIDNormalizer.songShareURL(videoId: song.videoId)
        case .album(let browseId, let playlistId, _, _, _, _):
            url = MenuIDNormalizer.collectionShareURL(id: playlistId ?? browseId)
        case .playlist(let id, _, _, _, _), .radioMix(let id, _, _, _):
            url = MenuIDNormalizer.collectionShareURL(id: id)
        case .artist(let channelId, _, _, _):
            url = MenuIDNormalizer.artistShareURL(channelId: channelId)
        }

        guard let shareURL = url else { return }
        Self.shareURL(shareURL)
    }

    public static func shareURL(_ url: URL) {
        // 1. Copiar al portapapeles siempre para comodidad en macOS
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)

        // 2. Desplegar selector nativo de compartir
        let picker = NSSharingServicePicker(items: [url])
        let mouseLoc = NSEvent.mouseLocation
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.contains(mouseLoc) }),
            let contentView = window.contentView {
            let winPt = window.convertPoint(fromScreen: mouseLoc)
            let viewPt = contentView.convert(winPt, from: nil)
            let rect = NSRect(origin: viewPt, size: CGSize(width: 1, height: 1))
            picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        }
    }

    // MARK: - Handlers de Eliminación / Destructivas

    private func executeDeletePlaylist(target: MenuTarget, facts: MenuFacts) {
        guard case .playlist(let id, let title, _, _, _) = target else { return }
        let canonicalId = MenuIDNormalizer.canonicalPlaylistId(id)

        // La vista de detalle ya presenta su propio diálogo de confirmación.
        if let customCallback = facts.onDeletePlaylist {
            customCallback()
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.text("menu.delete_playlist_question")
        alert.informativeText = L10n.text("menu.confirm_delete_playlist", args: [title])
        alert.alertStyle = .critical
        alert.addButton(withTitle: L10n.text("menu.delete"))
        alert.addButton(withTitle: L10n.text("menu.cancel"))

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        if let core {
            Task {
                do {
                    try await core.deletePlaylist(playlistId: canonicalId)
                    PlaylistCatalog.shared.invalidate(canonicalId)
                    NotificationCenter.default.post(name: .sideBPlaylistsChanged, object: nil)
                    router?.goBack()
                } catch {
                    Self.showErrorAlert(
                        title: L10n.text("menu.error_delete_playlist"),
                        detail: error.localizedDescription
                    )
                }
            }
        }
    }

    // MARK: - Error Feedback

    public static func showErrorAlert(title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("menu.accept"))
        alert.runModal()
    }
}
