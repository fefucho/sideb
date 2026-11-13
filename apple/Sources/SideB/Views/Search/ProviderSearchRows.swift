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
    /// Quick-search density. `.top` keeps the full-size row for the best result.
    var style: QuickSearchPresentation.Style = .recents

    @State private var isHovered = false
    private var compact: Bool { style != .top }
    private var isLocal: Bool { QuickSearchPresentation.isLocal(entry) }
    private var removable: Bool { entry.kind == "history" && (entry.feedbackToken != nil || isLocal) }

    var body: some View {
        HStack(spacing: 8) {
            if let card = mediaCard {
                mediaRow(card)
            } else {
                Button(action: onActivate) {
                    HStack(spacing: compact ? 10 : 12) {
                        Image(systemName: entry.kind == "history" ? "clock.arrow.circlepath" : "magnifyingglass")
                            .font(.system(size: compact ? 12 : 14))
                            .foregroundStyle(.secondary).frame(width: compact ? 32 : 42)
                        styledText.font(.system(size: compact ? 13 : 15)).lineLimit(2)
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 10).frame(minHeight: compact ? 32 : 48).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if removable {
                let visible = isHovered || selected
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24)
                }.buttonStyle(.plain).disabled(removing)
                    .foregroundStyle(.secondary)
                    .opacity(visible ? 1 : 0)
                    .padding(.trailing, 4)
                    .accessibilityLabel(L10n.text(isLocal ? "search.recents.remove" : "search.provider.remove_history"))
                    .help(L10n.text(isLocal ? "search.recents.remove" : "search.provider.remove_history"))
            }
        }
        .onHover { isHovered = $0 }
        .background(selected ? Color.white.opacity(0.12) : (style == .top ? Color.white.opacity(0.06) : Color.clear),
                    in: RoundedRectangle(cornerRadius: style == .top ? 10 : 8))
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
                    router: router, core: core, origin: .search) }, compact: compact, onSelect: onActivate)
                .songContextMenu(song: song, player: player, router: router, core: core, origin: .search)
        } else {
            QuickResultCardRow(card: card, isHero: style == .top,
                isActive: MediaPlaybackIdentity.isCollectionActive(kind: card.kind, id: card.id, context: player.queueManager.context),
                isPlaying: player.isPlaying,
                compact: compact,
                onPlay: ["album", "playlist"].contains(card.kind) ? { player.activateMediaCollection(id: card.id, kind: card.kind) } : nil,
                onSelect: onActivate)
                .browseCardContextMenu(card: card, player: player, router: router, core: core, origin: .search)
        }
    }
}
