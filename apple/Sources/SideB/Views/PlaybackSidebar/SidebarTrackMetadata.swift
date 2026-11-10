import SwiftUI
import SideBCore

/// Shared by the cover group and the lyrics/queue footer. No playback clock or image work.
struct SidebarTrackMetadata: View {
    let viewModel: PlayerViewModel
    var router: NavigationRouter?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(viewModel.currentTrack?.title ?? L10n.text("player.noPlayback"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .help(viewModel.currentTrack?.title ?? L10n.text("player.noPlayback"))
                if let error = viewModel.errorMessage {
                    Button { viewModel.retryPlayback() } label: {
                        Label(error, systemImage: "arrow.clockwise")
                            .font(.system(size: 12)).lineLimit(1)
                    }
                    .buttonStyle(.plain).foregroundStyle(.yellow)
                    .accessibilityLabel(L10n.text("player.retryPlayback"))
                } else if let track = viewModel.currentTrack {
                    ContentRatedMetadata(rating: track.contentRating, fontSize: 13) {
                        HStack(spacing: 6) {
                            TrackArtistLinks(track: track, font: .system(size: 14, weight: .medium),
                                             color: .white.opacity(0.70), hoverColor: .white) { id, name in
                                if let browseID = id ?? (track.artistRuns.isEmpty ? track.artistId ?? viewModel.currentArtistBrowseId : nil) {
                                    router?.navigate(to: .artist(browseId: browseID))
                                } else { router?.navigate(to: .search(query: name)) }
                            }
                            .layoutPriority(1)
                            if let album = track.displayAlbum, !album.isEmpty {
                                Text("·").foregroundStyle(.white.opacity(0.4))
                                Button {
                                    if let id = track.albumId ?? viewModel.currentAlbumBrowseId {
                                        router?.navigate(to: .album(browseId: id))
                                    } else { router?.navigate(to: .search(query: "\(album) \(track.displayArtist)")) }
                                } label: {
                                    Text(album).font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.60)).lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                .help(L10n.text("player.viewAlbum", args: [album]))
                                .accessibilityLabel(L10n.text("player.viewAlbum", args: [album]))
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Button { viewModel.toggleCurrentTrackLike() } label: {
                Image(systemName: viewModel.isCurrentTrackLiked ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(viewModel.isCurrentTrackLiked ? Color.white : Color.white.opacity(0.70))
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentTrack == nil || viewModel.rustCore?.isLoggedIn() != true)
            .help(L10n.text(viewModel.isCurrentTrackLiked ? "detail.track.unlike" : "detail.track.like"))
            .accessibilityLabel(L10n.text(viewModel.isCurrentTrackLiked ? "detail.track.unlike" : "detail.track.like"))

            Menu { menuContents } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.70)).frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(width: 28, height: 44)
            .disabled(viewModel.currentTrack == nil)
            .help(L10n.text("common.moreOptions"))
            .accessibilityLabel(L10n.text("common.moreOptions"))
        }
        .frame(height: PlaybackSidebarLayout.metadataHeight, alignment: .top)
        .contextMenu { menuContents }
    }

    @ViewBuilder private var menuContents: some View {
        if let track = viewModel.currentTrack {
            SongMenuItems(song: track, player: viewModel, router: router, core: viewModel.rustCore, origin: .nowPlaying)
            Divider()
            Button { viewModel.dislikeTrack(track) } label: {
                Label(L10n.text("queue.track.dislikeRemove"), systemImage: "hand.thumbsdown")
            }
            .disabled(viewModel.rustCore?.isLoggedIn() != true)
        }
    }
}

/// Fixed lightweight metadata behind the native recommendation viewport; artwork/video stays in its persistent host.
struct SidebarArtworkMetadataHost: View {
    let viewModel: PlayerViewModel
    let router: NavigationRouter?
    let state: SidebarArtworkScrollState
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let layout = SidebarArtworkLayout(width: proxy.size.width, height: height, portrait: state.isPortrait)
            SidebarTrackMetadata(viewModel: viewModel, router: router)
                .frame(width: layout.metadataWidth)
                .position(x: proxy.size.width / 2, y: layout.metadataTop + PlaybackSidebarLayout.metadataHeight / 2)
        }
        .frame(height: height)
    }
}
