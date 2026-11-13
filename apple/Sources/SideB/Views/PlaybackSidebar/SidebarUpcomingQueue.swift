import SwiftUI
import SideBCore

/// A bounded preview of committed queue occurrences. Reading it never promotes radio
/// recommendations, extends a source, or constructs a replacement playback queue.
struct SidebarUpcomingOccurrence: Identifiable {
    let id: String
    let index: Int
    let track: SongItemRecord

    @MainActor static func preview(in manager: QueueManager) -> [Self] {
        guard manager.queue.indices.contains(manager.currentIndex) else { return [] }
        let start = manager.currentIndex + 1
        let end = min(start + 2, manager.queue.count, manager.occurrenceIDs.count)
        guard start < end else { return [] }
        return (start..<end).map { Self(id: manager.occurrenceIDs[$0], index: $0, track: manager.queue[$0]) }
    }
}

struct SidebarUpcomingQueue: View {
    let viewModel: PlayerViewModel

    var body: some View {
        let manager = viewModel.queueManager
        let token = manager.queueToken
        let jam = JamQueueContext.current(for: viewModel)
        // During a Jam the preview follows the Jam order and cannot jump to a row.
        let jamRows = jam.map { SidebarJamPreviewRow.preview($0.entries) } ?? []
        let entries = jam == nil ? SidebarUpcomingOccurrence.preview(in: manager) : []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(jam?.title ?? L10n.text("playbackSidebar.upNext"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    viewModel.selectedSidebarPanel = .queue
                } label: {
                    HStack(spacing: 4) {
                        Text(L10n.text("playbackSidebar.viewQueue"))
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if entries.isEmpty && jamRows.isEmpty {
                Text(L10n.text("queue.empty"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            }
            ForEach(jamRows) { row in jamRow(row) }
            ForEach(entries) { entry in
                Button {
                    guard manager.queueToken == token,
                          manager.occurrenceIDs.indices.contains(entry.index),
                          manager.occurrenceIDs[entry.index] == entry.id else { return }
                    viewModel.playQueueIndex(entry.index)
                } label: {
                    HStack(spacing: 10) {
                        artwork(entry.track)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.track.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                            Text(entry.track.displayArtist).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let duration = entry.track.duration {
                            Text(duration).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    /// A Jam track: playable ones look like the normal rows but are not buttons; the others are
    /// dimmed and say why they will not play.
    private func jamRow(_ row: SidebarJamPreviewRow) -> some View {
        let playable = row.status == .matched
        let status = L10n.text(row.status == .unavailable ? "jam.queue.unavailable" : "jam.queue.resolving")
        return HStack(spacing: 10) {
            if let song = row.song { artwork(song) } else { placeholderArtwork(resolving: row.status == .resolving) }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.system(size: 12, weight: .medium)).foregroundStyle(playable ? .primary : .secondary)
                Text(playable ? row.artists : status).font(.system(size: 11))
                    .foregroundStyle(row.status == .unavailable ? Color(red: 0.95, green: 0.72, blue: 0.42).opacity(0.9) : .secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: row.marker.symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(row.marker == .addedByPerson ? Color.white.opacity(0.8) : Color(red: 0.52, green: 0.90, blue: 0.62))
                .help(row.marker.label)
                .accessibilityHidden(true)
            if let duration = row.duration {
                Text(duration).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .opacity(playable ? 1 : 0.62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([row.title, row.artists, playable ? "" : status, row.marker.label]
            .filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private func placeholderArtwork(resolving: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.white.opacity(0.06))
            .overlay {
                if resolving { ProgressView().controlSize(.mini) }
                else { Image(systemName: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(.secondary) }
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
    }

    private func artwork(_ track: SongItemRecord) -> some View {
        Group {
            if let thumbnail = track.thumbnail,
               let url = ImageURLHelper.optimizedThumbnailURL(from: thumbnail, targetPixelSize: 72) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 72, height: 72)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.white.opacity(0.08) }
            } else {
                Color.white.opacity(0.08).overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
    }
}
