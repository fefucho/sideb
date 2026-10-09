import Foundation
import Observation
import SideBCore

@MainActor
@Observable
final class ArtistDetailViewModel {
    var artist: ArtistDetailRecord?
    var isLoading: Bool = false
    private var errorDescriptor: AppMessage?
    var errorMessage: String? {
        get { errorDescriptor?.text }
        set { errorDescriptor = newValue.map { AppMessage(verbatim: $0) } }
    }

    init() {}

    func loadArtist(core: SideBCore, browseId: String) async {
        self.isLoading = true
        self.errorMessage = nil
        do {
            let detail = try await core.getArtist(browseId: browseId)
            self.artist = detail
        } catch {
            print("[ArtistDetailViewModel] Error al cargar artista \(browseId): \(error)")
            self.errorDescriptor = AppMessage(verbatim: error.localizedDescription)
        }
        self.isLoading = false
    }

    func toggleSubscription(core: SideBCore) async {
        guard let a = artist else { return }
        let newStatus = !a.subscribed
        do {
            try await core.subscribeArtist(channelId: a.channelId, subscribe: newStatus)
            if var current = self.artist {
                current.subscribed = newStatus
                self.artist = current
            }
        } catch {
            print("[ArtistDetailViewModel] Error al actualizar suscripción: \(error)")
        }
    }

    func startRadio(core: SideBCore, player: PlayerViewModel) {
        guard let a = artist else { return }
        player.startRadioForCollection(
            id: a.channelId,
            title: a.name,
            prefix: "RDAMVM",
            directRadioId: a.radioPlaylistId,
            fallbackTracks: a.topSongs
        )
    }

    func shuffleTopSongs(player: PlayerViewModel) {
        guard let a = artist, !a.topSongs.isEmpty else { return }
        player.playCollection(
            tracks: a.topSongs,
            title: "\(a.name) (Aleatorio)",
            artistBrowseId: a.channelId,
            shuffle: true
        )
        player.queueManager.setContextLocalizationKey("player.shuffledArtist", args: [a.name])
    }

    func playTopSong(at index: Int, player: PlayerViewModel) {
        guard let a = artist, index >= 0, index < a.topSongs.count else { return }
        let song = a.topSongs[index]
        player.playWithRadio(song)
    }
}
