import Foundation
import Observation
import SideBCore

/// Identity and metadata for the opt-in lyrics request. Playback identity deliberately
/// participates even when two queue occurrences contain the same video.
struct ExperimentalLyricsRequest: Equatable, Sendable {
    let playbackID: UUID
    let sessionID: UUID
    let videoID: String
    let title: String
    let artist: String
    let album: String?
    let durationSeconds: UInt64?

    init(playbackID: UUID, sessionID: UUID, videoID: String, title: String,
         artist: String, album: String?, durationSeconds: UInt64?) {
        self.playbackID = playbackID
        self.sessionID = sessionID
        self.videoID = videoID
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
    }

    init(track: SongItemRecord, playbackID: UUID, sessionID: UUID, audioDuration: Double? = nil) {
        self.init(playbackID: playbackID, sessionID: sessionID, videoID: track.videoId,
                  title: track.title, artist: track.artists, album: track.album,
                  durationSeconds: Self.effectiveDurationSeconds(metadata: track.duration, audioDuration: audioDuration))
    }

    static func effectiveDurationSeconds(metadata: String?, audioDuration: Double?) -> UInt64? {
        if let parsed = durationSeconds(metadata) { return parsed }
        guard let seconds = audioDuration, seconds.isFinite, seconds > 0,
              let rounded = UInt64(exactly: seconds.rounded()), rounded > 0 else { return nil }
        return rounded
    }

    static func durationSeconds(_ value: String?) -> UInt64? {
        guard let value else { return nil }
        let fields = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(fields.count), fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        var total: UInt64 = 0
        for (index, field) in fields.enumerated() {
            guard let number = UInt64(field), index == 0 || number < 60 else { return nil }
            let (scaled, multiplyOverflow) = total.multipliedReportingOverflow(by: 60)
            let (next, addOverflow) = scaled.addingReportingOverflow(number)
            guard !multiplyOverflow && !addOverflow else { return nil }
            total = next
        }
        return total > 0 ? total : nil
    }
}

/// Separate state for the temporary lyrics experiment. The classic lyrics request,
/// cache and presentation never pass through this controller.
@MainActor
@Observable
final class ExperimentalLyricsController {
    typealias Fetcher = @MainActor (ExperimentalLyricsRequest, Bool) async throws -> ExperimentalLyricsDocument?

    private(set) var document: ExperimentalLyricsDocument?
    private(set) var isLoading = false
    private(set) var errorKey: String?
    private(set) var activeRequest: ExperimentalLyricsRequest?

    @ObservationIgnored private var requestRevision = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Calling with nil is the inactive/default mode and performs no network request.
    /// Repeated renders of the same active request do not start duplicate fetches.
    @discardableResult
    func activate(_ request: ExperimentalLyricsRequest?, fetch: @escaping Fetcher) -> Task<Void, Never>? {
        guard let request else {
            deactivate()
            return nil
        }
        guard request != activeRequest else { return task }
        let preservesDocument = activeRequest?.playbackID == request.playbackID && activeRequest?.sessionID == request.sessionID
        task?.cancel()
        activeRequest = request
        if !preservesDocument { document = nil }
        return start(request, forceRefresh: false, fetch: fetch)
    }

    @discardableResult
    func refresh(fetch: @escaping Fetcher) -> Task<Void, Never>? {
        guard let request = activeRequest else { return nil }
        task?.cancel()
        return start(request, forceRefresh: true, fetch: fetch)
    }

    func deactivate() {
        requestRevision = UUID()
        task?.cancel()
        task = nil
        activeRequest = nil
        document = nil
        isLoading = false
        errorKey = nil
    }

    private func start(_ request: ExperimentalLyricsRequest, forceRefresh: Bool,
                       fetch: @escaping Fetcher) -> Task<Void, Never> {
        let revision = UUID()
        requestRevision = revision
        isLoading = true
        errorKey = nil
        let pending = Task { [weak self] in
            do {
                let document = try await fetch(request, forceRefresh)
                guard let self, !Task.isCancelled, self.requestRevision == revision,
                      self.activeRequest == request else { return }
                // A transient empty refresh must not erase the usable document.
                if let document { self.document = document }
                self.isLoading = false
                self.task = nil
            } catch {
                guard let self, !Task.isCancelled, self.requestRevision == revision,
                      self.activeRequest == request else { return }
                self.isLoading = false
                self.task = nil
                if !(error is CancellationError) {
                    self.errorKey = "lyrics.experimental.error"
                }
            }
        }
        task = pending
        return pending
    }

    static func fetch(_ request: ExperimentalLyricsRequest, forceRefresh: Bool,
                      core: SideBCore) async throws -> ExperimentalLyricsDocument? {
        let result = try await core.getKaraokeLyrics(
            videoId: request.videoID,
            title: request.title,
            artist: request.artist,
            album: request.album,
            durationSecs: request.durationSeconds,
            forceRefresh: forceRefresh
        )
        return result.map { result in
            ExperimentalLyricsDocument(
                provider: result.provider,
                instrumental: result.instrumental,
                lines: result.lines.map { line in
                    ExperimentalLyricLine(
                        // An initializer reference can select Double.init(bitPattern:)
                        // for UInt64. Preserve the numeric millisecond value explicitly.
                        startMS: line.timeMs.map { Double($0) },
                        endMS: line.endTimeMs.map { Double($0) },
                        text: line.text,
                        words: line.words.map {
                            ExperimentalLyricWord(text: $0.text, startMS: Double($0.startMs), endMS: Double($0.endMs))
                        },
                        translation: line.translation,
                        role: line.role,
                        agent: line.agent,
                        groupID: line.groupId,
                        section: line.section
                    )
                }
            )
        }
    }
}
