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
        let entries = SidebarUpcomingOccurrence.preview(in: manager)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("playbackSidebar.upNext"))
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
            if entries.isEmpty {
                Text(L10n.text("queue.empty"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            }
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
