import Foundation
import Observation
import SideBCore

// UniFFI records contain only immutable values at this boundary. State is published on MainActor.
extension GeniusTrackRecord: @unchecked Sendable {}
extension GeniusResolutionRecord: @unchecked Sendable {}
extension GeniusAnnotationsRecord: @unchecked Sendable {}
extension GeniusLyricsRecord: @unchecked Sendable {}
extension GeniusCandidateRecord: @unchecked Sendable {}
extension GeniusLyricLineRecord: @unchecked Sendable {}
extension GeniusLyricSpanRecord: @unchecked Sendable {}
extension GeniusAnnotationRecord: @unchecked Sendable {}

@MainActor
@Observable
final class GeniusViewModel {
    enum Phase {
        case idle
        case loading
        case matched
        case ambiguous
        case notFound
        case error
    }

    private(set) var phase: Phase = .idle
    private(set) var resolution: GeniusResolutionRecord?
    private(set) var annotations: [GeniusAnnotationRecord] = []
    private(set) var lyrics: [GeniusLyricLineRecord] = []
    private(set) var nextAnnotationPage: UInt32?
    private(set) var isLoadingAnnotations = false
    private(set) var isLoadingLyrics = false
    private(set) var isSearching = false
    private(set) var searchResults: [GeniusCandidateRecord] = []
    private var errorDescriptor: AppMessage?
    private(set) var errorMessage: String? {
        get { errorDescriptor?.text }
        set { errorDescriptor = newValue.map { AppMessage(verbatim: $0) } }
    }
    private(set) var automaticFetchEnabled = false
    private(set) var isReportingMiss = false
    private(set) var missReportSaved = false
    private var missReportDescriptor: AppMessage?
    private(set) var missReportError: String? {
        get { missReportDescriptor?.text }
        set { missReportDescriptor = newValue.map { AppMessage(verbatim: $0) } }
    }
    var selectedAnnotation: GeniusAnnotationRecord?

    @ObservationIgnored private var core: SideBCore?
    @ObservationIgnored private var track: GeniusTrackRecord?
    @ObservationIgnored private var identity = UUID()
    @ObservationIgnored private var cacheTask: Task<Void, Never>?
    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var annotationsTask: Task<Void, Never>?
    @ObservationIgnored private var lyricsTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var waitingForPlayback = false
    @ObservationIgnored private var openedEarly = false

    func prepare(for song: SongItemRecord, core: SideBCore?, identity: UUID) {
        reset()
        self.core = core
        self.identity = identity
        automaticFetchEnabled = core?.getSetting(key: "genius_auto_fetch") == "true"
        self.track = GeniusTrackRecord(
            videoId: song.videoId,
            title: song.title,
            artists: song.artists,
            album: song.album,
            durationSeconds: Self.durationSeconds(song.duration),
            isUpload: song.isUpload
        )
        guard let core, let track else { return }
        phase = .loading
        cacheTask = Task { [weak self] in
            let cached = await core.getGeniusCached(track: track)
            guard let self, self.identity == identity, !Task.isCancelled,
                  self.resolution == nil, let cached else { return }
            self.apply(cached)
            guard let song = cached.song else { return }
            let cachedAnnotations = await core.getGeniusCachedAnnotations(songId: song.id, page: 1)
            guard self.identity == identity, !Task.isCancelled else { return }
            if let cachedAnnotations {
                self.annotations = cachedAnnotations.items
                self.nextAnnotationPage = cachedAnnotations.nextPage
            }
            let cachedLyrics = await core.getGeniusCachedLyrics(songId: song.id)
            guard self.identity == identity, !Task.isCancelled else { return }
            self.lyrics = cachedLyrics?.lines ?? []
        }
    }

    func playbackStarted(identity: UUID) {
        guard self.identity == identity, automaticFetchEnabled else { return }
        if openedEarly { return }
        waitingForPlayback = true
        lookupTask?.cancel()
        lookupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, self.identity == identity else { return }
            self.waitingForPlayback = false
            await self.resolve(force: false, identity: identity)
        }
    }

    func ensureNow() {
        guard track != nil, core != nil else { return }
        let identity = self.identity
        if waitingForPlayback || (resolution == nil && lookupTask == nil) {
            openedEarly = true
            lookupTask?.cancel()
            waitingForPlayback = false
            lookupTask = Task { [weak self] in
                await self?.resolve(force: false, identity: identity)
            }
        } else if resolution?.song != nil && (annotations.isEmpty || lyrics.isEmpty) {
            openedEarly = true
            loadContents(for: resolution?.song, force: false, identity: identity)
        }
    }

    func refresh() {
        guard core != nil, track != nil else { return }
        let identity = self.identity
        openedEarly = true
        lookupTask?.cancel()
        lookupTask = Task { [weak self] in
            await self?.resolve(force: true, identity: identity)
        }
    }

    func setAutomaticFetchEnabled(_ enabled: Bool) {
        automaticFetchEnabled = enabled
        core?.setSetting(key: "genius_auto_fetch", value: enabled ? "true" : "false")
        if enabled {
            ensureNow()
        } else if !openedEarly {
            lookupTask?.cancel()
            waitingForPlayback = false
        }
    }

    func search(_ query: String) {
        guard let core else { return }
        let identity = self.identity
        searchTask?.cancel()
        isSearching = true
        searchTask = Task { [weak self] in
            do {
                let results = try await core.searchGenius(query: query)
                guard let self, self.identity == identity, !Task.isCancelled else { return }
                self.searchResults = results
                self.isSearching = false
            } catch {
                guard let self, self.identity == identity, !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isSearching = false
            }
        }
    }

    func choose(_ candidate: GeniusCandidateRecord) {
        guard let core, let track else { return }
        let identity = self.identity
        lookupTask?.cancel()
        lookupTask = Task { [weak self] in
            do {
                let result = try await core.chooseGenius(track: track, songId: candidate.id)
                guard let self, self.identity == identity, !Task.isCancelled else { return }
                self.apply(result)
                self.loadContents(for: result.song, force: false, identity: identity)
            } catch {
                guard let self, self.identity == identity, !Task.isCancelled else { return }
                self.phase = .error
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func clearChoice() {
        guard let core, let track else { return }
        cacheTask?.cancel()
        lookupTask?.cancel()
        annotationsTask?.cancel()
        lyricsTask?.cancel()
        searchTask?.cancel()
        cacheTask = nil
        lookupTask = nil
        annotationsTask = nil
        lyricsTask = nil
        searchTask = nil
        core.clearGeniusChoice(track: track)
        let previousCandidates = searchResults.isEmpty ? (resolution?.candidates ?? []) : searchResults
        resolution = nil
        annotations = []
        lyrics = []
        nextAnnotationPage = nil
        selectedAnnotation = nil
        searchResults = previousCandidates
        isLoadingAnnotations = false
        isLoadingLyrics = false
        isSearching = false
        errorMessage = nil
        phase = .idle
    }

    func reportCurrentMiss() {
        guard let core, let track, !isReportingMiss, !missReportSaved else { return }
        let status: GeniusMatchStatusRecord
        switch phase {
        case .ambiguous: status = .ambiguous
        case .notFound: status = .notFound
        default: return
        }
        let candidateIDs = (resolution?.candidates ?? []).map(\.id)
        let identity = self.identity
        isReportingMiss = true
        missReportError = nil
        Task { [weak self] in
            do {
                try core.reportGeniusMiss(track: track, status: status, candidateIds: candidateIDs)
                guard let self, self.identity == identity else { return }
                self.missReportSaved = true
                self.isReportingMiss = false
            } catch {
                guard let self, self.identity == identity else { return }
                self.missReportDescriptor = AppMessage(key: "genius.error.saveTrack")
                self.isReportingMiss = false
            }
        }
    }

    func loadMoreAnnotations() {
        guard let page = nextAnnotationPage, let song = resolution?.song, let core,
              !isLoadingAnnotations else { return }
        let identity = self.identity
        isLoadingAnnotations = true
        annotationsTask = Task { [weak self] in
            do {
                let result = try await core.getGeniusAnnotations(songId: song.id, page: page, force: false)
                guard let self, self.identity == identity, !Task.isCancelled else { return }
                let existing = Set(self.annotations.map(\.id))
                self.annotations.append(contentsOf: result.items.filter { !existing.contains($0.id) })
                self.nextAnnotationPage = result.nextPage
                self.isLoadingAnnotations = false
            } catch {
                guard let self, self.identity == identity, !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isLoadingAnnotations = false
            }
        }
    }

    func annotation(for line: GeniusLyricLineRecord) -> GeniusAnnotationRecord? {
        guard let id = line.referentId else { return nil }
        return annotation(for: id)
    }

    func annotation(for id: Int64) -> GeniusAnnotationRecord? {
        return annotations.first { $0.referentId == id || $0.id == id }
    }

    func reset() {
        cacheTask?.cancel()
        lookupTask?.cancel()
        annotationsTask?.cancel()
        lyricsTask?.cancel()
        searchTask?.cancel()
        cacheTask = nil
        lookupTask = nil
        annotationsTask = nil
        lyricsTask = nil
        searchTask = nil
        identity = UUID()
        waitingForPlayback = false
        openedEarly = false
        track = nil
        core = nil
        phase = .idle
        resolution = nil
        annotations = []
        lyrics = []
        nextAnnotationPage = nil
        isLoadingAnnotations = false
        isLoadingLyrics = false
        isSearching = false
        searchResults = []
        errorMessage = nil
        automaticFetchEnabled = false
        isReportingMiss = false
        missReportSaved = false
        missReportError = nil
        selectedAnnotation = nil
    }

    private func resolve(force: Bool, identity: UUID) async {
        guard let core, let track, self.identity == identity else { return }
        if resolution == nil { phase = .loading }
        errorMessage = nil
        do {
            let result = try await core.resolveGenius(track: track, force: force)
            guard self.identity == identity, !Task.isCancelled else { return }
            apply(result)
            loadContents(for: result.song, force: force, identity: identity)
        } catch {
            guard self.identity == identity, !Task.isCancelled else { return }
            phase = .error
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ result: GeniusResolutionRecord) {
        resolution = result
        switch result.status {
        case .matched: phase = .matched
        case .ambiguous: phase = .ambiguous
        case .notFound: phase = .notFound
        }
    }

    private func loadContents(for song: GeniusSongRecord?, force: Bool, identity: UUID) {
        guard let core, let song else { return }
        annotationsTask?.cancel()
        lyricsTask?.cancel()
        isLoadingAnnotations = true
        isLoadingLyrics = song.url != nil
        annotationsTask = Task { [weak self] in
            do {
                let first = try await core.getGeniusAnnotations(songId: song.id, page: 1, force: force)
                guard let self, self.identity == identity, !Task.isCancelled else { return }
                self.annotations = first.items
                self.nextAnnotationPage = first.nextPage
                if let page = first.nextPage {
                    let second = try await core.getGeniusAnnotations(songId: song.id, page: page, force: force)
                    guard self.identity == identity, !Task.isCancelled else { return }
                    let existing = Set(self.annotations.map(\.id))
                    self.annotations.append(contentsOf: second.items.filter { !existing.contains($0.id) })
                    self.nextAnnotationPage = second.nextPage
                }
                self.isLoadingAnnotations = false
            } catch {
                guard let self, self.identity == identity, !Task.isCancelled else { return }
                self.isLoadingAnnotations = false
                self.errorMessage = error.localizedDescription
            }
        }
        guard let url = song.url else { isLoadingLyrics = false; return }
        lyricsTask = Task { [weak self] in
            do {
                let result = try await core.getGeniusLyrics(songId: song.id, songUrl: url, force: force)
                guard let self, self.identity == identity, !Task.isCancelled else { return }
                self.lyrics = result.lines
                self.isLoadingLyrics = false
            } catch {
                guard let self, self.identity == identity, !Task.isCancelled else { return }
                self.isLoadingLyrics = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private static func durationSeconds(_ value: String?) -> UInt64? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { UInt64($0) }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        return nil
    }
}
