import SwiftUI
import SideBCore

struct HistoryView: View {
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    @Bindable var libraryViewModel: LibraryViewModel
    var router: NavigationRouter? = nil

    private var historySections: [TrackTableSection] {
        libraryViewModel.historyGroups.map { group in
            TrackTableSection(
                id: group.title,
                title: normalizeDateTitle(group.title),
                tracks: group.items
            )
        }
    }

    private var allHistoryTracks: [SongItemRecord] {
        libraryViewModel.historyGroups.flatMap(\.items)
    }

    private func normalizeDateTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "today" || lower == "hoy" {
            return L10n.text("history.today")
        }
        if lower == "yesterday" || lower == "ayer" {
            return L10n.text("history.yesterday")
        }

        var result = trimmed
        let dayReplacements: [(String, String, String)] = [
            ("Monday", "Lunes", "history.day.monday"), ("Tuesday", "Martes", "history.day.tuesday"),
            ("Wednesday", "Miércoles", "history.day.wednesday"), ("Thursday", "Jueves", "history.day.thursday"),
            ("Friday", "Viernes", "history.day.friday"), ("Saturday", "Sábado", "history.day.saturday"),
            ("Sunday", "Domingo", "history.day.sunday")
        ]
        for (en, es, key) in dayReplacements {
            if result.contains(en) || result.contains(es) {
                result = result.replacingOccurrences(of: en, with: L10n.text(key))
                result = result.replacingOccurrences(of: es, with: L10n.text(key))
            }
        }

        let monthReplacements: [(String, String, String)] = [
            ("January", "enero", "history.month.january"), ("February", "febrero", "history.month.february"),
            ("March", "marzo", "history.month.march"), ("April", "abril", "history.month.april"),
            ("May", "mayo", "history.month.may"), ("June", "junio", "history.month.june"),
            ("July", "julio", "history.month.july"), ("August", "agosto", "history.month.august"),
            ("September", "septiembre", "history.month.september"), ("October", "octubre", "history.month.october"),
            ("November", "noviembre", "history.month.november"), ("December", "diciembre", "history.month.december")
        ]
        for (en, es, key) in monthReplacements {
            if result.contains(en) || result.contains(es) {
                result = result.replacingOccurrences(of: en, with: L10n.text(key))
                result = result.replacingOccurrences(of: es, with: L10n.text(key))
            }
        }
        return result
    }

    var body: some View {
        let _ = L10n.revision
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("library.eyebrow").uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                Text(L10n.text("history.title"))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)

                Text(L10n.text("history.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 14)

            Divider()
                .opacity(0.2)
                .padding(.horizontal, 32)
                .padding(.bottom, 8)

            if (libraryViewModel.isLoading || libraryViewModel.isHistoryLoading) && libraryViewModel.historyGroups.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let error = libraryViewModel.historyErrorMessage, allHistoryTracks.isEmpty {
                DetailErrorStateView(
                    title: L10n.text("history.error.load"),
                    message: error,
                    onRetry: {
                        Task {
                            await libraryViewModel.loadHistory(core: rustCore)
                        }
                    }
                )
            } else if allHistoryTracks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text(L10n.text("history.empty"))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NativeTrackTableView(
                    sections: historySections,
                    currentTrackVideoId: playerViewModel.currentTrack?.videoId,
                    isPlaying: playerViewModel.isPlaying,
                    playerViewModel: playerViewModel,
                    router: router,
                    rustCore: rustCore,
                    likedVideoIds: playerViewModel.likedVideoIds,
                    onPlayTrack: { index in
                        if playerViewModel.queueManager.context == .custom(title: "Historial"),
                           playerViewModel.queueManager.queue == allHistoryTracks,
                           playerViewModel.queueManager.currentIndex == index {
                            playerViewModel.togglePlayPause()
                            return
                        }
                        playerViewModel.playCollection(
                            tracks: allHistoryTracks,
                            title: "Historial",
                            startingAt: index
                        )
                        playerViewModel.queueManager.setContextLocalizationKey("history.title")
                    },
                    onLikeTrack: { track in
                        playerViewModel.toggleTrackLike(track)
                    },
                    onDislikeTrack: { track in
                        playerViewModel.dislikeTrack(track)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await libraryViewModel.loadHistory(core: rustCore)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBPlaybackRecorded)) { notification in
            if let track = notification.userInfo?["track"] as? SongItemRecord {
                libraryViewModel.prependPlayedTrack(track)
            }
        }
    }
}
