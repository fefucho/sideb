import SwiftUI
import SideBCore

/// One provider entry with its original payload. Presentation chooses the visible entries.
struct ProviderSearchSuggestionRow: View {
    let entry: SearchSuggestionEntryRecord
    let selected: Bool
    let removing: Bool
    var player: PlayerViewModel
    var router: NavigationRouter
    let core: SideBCore
    let onActivate: () -> Void
    let onRemove: () -> Void
    var onNavigate: ((PageDestination) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let card = mediaCard {
                mediaRow(card)
            } else {
                Button(action: onActivate) {
                    HStack(spacing: 12) {
                        Image(systemName: entry.kind == "history" ? "clock.arrow.circlepath" : "magnifyingglass")
                            .foregroundStyle(.secondary).frame(width: 42)
                        styledText.font(.system(size: 15)).lineLimit(2)
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 10).frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if entry.kind == "history", entry.feedbackToken != nil {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 11)).frame(width: 28, height: 28)
                }.buttonStyle(.plain).disabled(removing)
                    .accessibilityLabel(L10n.text("search.provider.remove_history"))
                    .help(L10n.text("search.provider.remove_history"))
            }
        }
        .background(selected ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .id(entry.id)
    }

    private func navigate(_ destination: PageDestination) {
        if let onNavigate { onNavigate(destination) }
        else { router.navigate(to: destination) }
    }

    private var mediaCard: BrowseCardRecord? {
        if let card = entry.card { return ProviderSearchProjection.displayCard(card, song: entry.song) }
        return entry.song.map { song in
            BrowseCardRecord(kind: song.isVideo ? "video" : "song", id: song.videoId,
                title: song.title, subtitle: song.artists, thumbnail: song.thumbnail, duration: song.duration, contentRating: song.contentRating)
        }
    }

    private var styledText: Text {
        guard !entry.runs.isEmpty else { return Text(entry.query ?? "") }
        return entry.runs.reduce(Text("")) { text, run in
            text + Text(run.text).fontWeight(run.bold ? .semibold : .regular)
        }
    }

    @ViewBuilder private func mediaRow(_ card: BrowseCardRecord) -> some View {
        if let song = ProviderSearchProjection.song(for: entry) {
            QuickResultSongRow(song: song, onFeatured: { id, name in
                if let id { navigate(.artist(browseId: id)) }
                else { navigate(.search(query: name)) }
            }, onArtist: song.artistId.map { id in { navigate(.artist(browseId: id)) } },
                onAlbum: song.albumId.map { id in { navigate(.album(browseId: id)) } },
                menuProvider: { AppContextMenuFactory.shared.buildSongNSMenu(song: song, player: player,
                    router: router, core: core, origin: .search) }, onSelect: onActivate)
                .songContextMenu(song: song, player: player, router: router, core: core, origin: .search)
        } else {
            QuickResultCardRow(card: card,
                isActive: MediaPlaybackIdentity.isCollectionActive(kind: card.kind, id: card.id, context: player.queueManager.context),
                isPlaying: player.isPlaying,
                onPlay: ["album", "playlist"].contains(card.kind) ? { player.activateMediaCollection(id: card.id, kind: card.kind) } : nil,
                onSelect: onActivate)
                .browseCardContextMenu(card: card, player: player, router: router, core: core, origin: .search)
        }
    }
}
