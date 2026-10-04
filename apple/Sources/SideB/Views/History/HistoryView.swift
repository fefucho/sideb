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
            return "Hoy"
        }
        if lower == "yesterday" || lower == "ayer" {
            return "Ayer"
        }

        var result = trimmed
        let dayReplacements: [String: String] = [
            "Monday": "Lunes", "Tuesday": "Martes", "Wednesday": "Miércoles",
            "Thursday": "Jueves", "Friday": "Viernes", "Saturday": "Sábado", "Sunday": "Domingo"
        ]
        for (en, es) in dayReplacements {
            if result.contains(en) {
                result = result.replacingOccurrences(of: en, with: es)
            }
        }

        let monthReplacements: [String: String] = [
            "January": "enero", "February": "febrero", "March": "marzo", "April": "abril",
            "May": "mayo", "June": "junio", "July": "julio", "August": "agosto",
            "September": "septiembre", "October": "octubre", "November": "noviembre", "December": "diciembre"
        ]
        for (en, es) in monthReplacements {
            if result.contains(en) {
                result = result.replacingOccurrences(of: en, with: es)
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("COLECCIÓN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                Text("Historial")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Tus reproducciones recientes ordenadas por día")
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
                    title: "No se pudo cargar el historial",
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
                    Text("No hay reproducciones recientes")
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
