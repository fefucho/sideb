import AVFoundation
import AppKit
import Observation
import SwiftUI

/// Local clock: only active lyric rows read positionMS. The parent observes focus/active
/// sets, whose values change at boundaries rather than for every animation frame.
@MainActor
@Observable
final class ExperimentalLyricsClock {
    private(set) var positionMS: Double = 0
    private(set) var focusIndex: Int?
    private(set) var completedFocusIndex: Int?
    private(set) var activeWordLineIndices: Set<Int> = []
    private(set) var activeLineIndices: Set<Int> = []
    private(set) var interludes: [ExperimentalLyricsInterlude] = []
    private(set) var activeInterludeID: String?
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var document: ExperimentalLyricsDocument?
    @ObservationIgnored private var pulse: Timer?
    @ObservationIgnored private var periodicObserver: Any?
    @ObservationIgnored private var boundaryObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var animateWords = true
    @ObservationIgnored private var animateInterludes = true
    @ObservationIgnored private var offsetMS: Double = 0
    @ObservationIgnored private var durationMS: Double?
    @ObservationIgnored private var pulseInterval: TimeInterval?
    @ObservationIgnored private(set) var visiblePresentationGroupIDs: Set<String> = []
    @ObservationIgnored private(set) var visibleInterludeIDs: Set<String> = []
    @ObservationIgnored private var observationGeneration = UUID()
    @ObservationIgnored private var playbackIdentity: UUID?
    @ObservationIgnored private var seekSnapshot: AudioPlayerSeekSnapshot = .idle

    func start(player: AVPlayer, document: ExperimentalLyricsDocument, duration: Double = 0,
               playbackIdentity: UUID? = nil, seekSnapshot: AudioPlayerSeekSnapshot = .idle) {
        let retainedVisibleGroups = visiblePresentationGroupIDs
        let retainedVisibleInterludes = visibleInterludeIDs
        stop()
        self.player = player
        self.document = document
        let validGroups = Set(document.presentationGroups.map { "line:\($0.anchorLineIndex)" })
        visiblePresentationGroupIDs = retainedVisibleGroups.intersection(validGroups)
        let validInterludes = Set(document.interludes(durationMS: Self.validDurationMS(duration)).map(\.id))
        visibleInterludeIDs = retainedVisibleInterludes.intersection(validInterludes)
        self.playbackIdentity = playbackIdentity
        durationMS = Self.validDurationMS(duration)
        interludes = document.interludes(durationMS: durationMS)
        let generation = observationGeneration
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.observationGeneration == generation else { return }
                self.sample()
            }
        }
        periodicObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.observationGeneration == generation else { return }
                self.sample()
            }
        }
        installBoundaries()
        sample()
        reconcileSeek(seekSnapshot)
    }

    func stop() {
        observationGeneration = UUID()
        pulse?.invalidate()
        pulse = nil
        pulseInterval = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let periodicObserver { player?.removeTimeObserver(periodicObserver) }
        if let boundaryObserver { player?.removeTimeObserver(boundaryObserver) }
        periodicObserver = nil
        boundaryObserver = nil
        player = nil
        document = nil
        playbackIdentity = nil
        seekSnapshot = .idle
        positionMS = 0
        focusIndex = nil
        completedFocusIndex = nil
        activeWordLineIndices = []
        activeLineIndices = []
        activeInterludeID = nil
        interludes = []
        visiblePresentationGroupIDs = []
        visibleInterludeIDs = []
    }

    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        sample()
    }

    /// Visibility is keyed by stable presentation identity so a same-ID refresh can
    /// retain rows whose scroll visibility did not change during observer restart.
    func setPresentationGroupVisible(id: String, visible: Bool) {
        guard id.hasPrefix("line:") else { return }
        if let document {
            guard document.presentationGroups.contains(where: { "line:\($0.anchorLineIndex)" == id }) else { return }
        }
        let changed = visible
            ? visiblePresentationGroupIDs.insert(id).inserted
            : visiblePresentationGroupIDs.remove(id) != nil
        if changed { sample() }
    }

    func setInterludeVisible(id: String, visible: Bool) {
        guard !id.isEmpty else { return }
        if document != nil, !interludes.contains(where: { $0.id == id }) { return }
        let changed = visible
            ? visibleInterludeIDs.insert(id).inserted
            : visibleInterludeIDs.remove(id) != nil
        if changed { sample() }
    }

    func updateDuration(_ seconds: Double) {
        let next = Self.validDurationMS(seconds)
        guard durationMS != next else { return }
        durationMS = next
        interludes = document?.interludes(durationMS: next) ?? []
        visibleInterludeIDs.formIntersection(Set(interludes.map(\.id)))
        installBoundaries()
        sample()
    }

    private static func validDurationMS(_ seconds: Double) -> Double? {
        let milliseconds = seconds * 1000
        return milliseconds.isFinite && milliseconds > 0 ? milliseconds : nil
    }

    func configure(animateWords: Bool, offsetMS: Double, animateInterludes: Bool = true) {
        let changedOffset = self.offsetMS != offsetMS
        self.animateWords = animateWords
        self.animateInterludes = animateInterludes
        self.offsetMS = offsetMS.isFinite ? offsetMS : 0
        if changedOffset { installBoundaries() }
        sample()
    }

    static func shouldPulse(visible: Bool, playing: Bool, animateWords: Bool, hasChangingWord: Bool,
                            hasChangingInterlude: Bool = false, animateInterludes: Bool = true,
                            seeking: Bool = false, hasVisibleChangingWord: Bool = true,
                            hasVisibleInterlude: Bool = true) -> Bool {
        visible && playing && !seeking &&
            ((animateWords && hasChangingWord && hasVisibleChangingWord) ||
             (animateInterludes && hasChangingInterlude && hasVisibleInterlude))
    }

    static func completedFocusIndex(document: ExperimentalLyricsDocument, at lyricMS: Double) -> Int? {
        guard let index = document.focusIndex(at: lyricMS), document.lines.indices.contains(index),
              let end = document.lines[index].effectiveEndMS, lyricMS >= end else { return nil }
        return index
    }

    static func hasVisibleChangingWord(document: ExperimentalLyricsDocument, activeLineIndices: Set<Int>,
                                       visiblePresentationGroupIDs: Set<String>, at lyricMS: Double) -> Bool {
        activeLineIndices.contains { index in
            guard document.lines.indices.contains(index),
                  let anchor = document.presentationAnchorIndex(for: index),
                  visiblePresentationGroupIDs.contains("line:\(anchor)") else { return false }
            return document.lines[index].hasChangingWord(at: lyricMS)
        }
    }

    /// Immediate feedback for a lyric click. This is a single update, never a held
    /// floor or a simulated clock. Only the service's real pending seek may hold it.
    func notifySeek(toAudioSeconds seconds: Double) {
        guard seconds.isFinite, player != nil, document != nil else { return }
        updatePosition(seconds: max(0, seconds), playing: false)
    }

    /// The service covers lyric, slider and keyboard seeks with the same occurrence
    /// and revision. Completion/failure returns directly to sampled media time.
    func reconcileSeek(_ snapshot: AudioPlayerSeekSnapshot) {
        guard let player, document != nil, snapshot.revision >= seekSnapshot.revision else { return }
        if let playbackIdentity, snapshot.playbackID != playbackIdentity {
            // stop/reset has no occurrence after removing its item. It may release a
            // preview, while an unidentified completion cannot author a new position.
            guard snapshot.playbackID == nil, snapshot.phase == .idle || snapshot.phase == .cancelled else { return }
        }
        seekSnapshot = snapshot
        if snapshot.phase != .pending, let seconds = snapshot.mediaSeconds, seconds.isFinite {
            updatePosition(seconds: max(0, seconds), playing: player.timeControlStatus == .playing)
        } else { sample() }
    }

    func sample() {
        guard let player, document != nil else { return }
        let pending = seekSnapshot.pendingTargetSeconds
        let seconds = pending ?? player.currentTime().seconds
        updatePosition(seconds: seconds, playing: player.timeControlStatus == .playing && pending == nil)
    }

    private func updatePosition(seconds: Double, playing: Bool) {
        guard let document else { return }
        let rawMS = seconds.isFinite ? max(0, seconds * 1000) : 0
        if positionMS != rawMS { positionMS = rawMS }
        let lyricMS = rawMS + offsetMS
        let nextFocus = document.focusIndex(at: lyricMS)
        if nextFocus != focusIndex { focusIndex = nextFocus }
        let nextCompletedFocus = Self.completedFocusIndex(document: document, at: lyricMS)
        if nextCompletedFocus != completedFocusIndex { completedFocusIndex = nextCompletedFocus }
        let nextLines = Set(document.lines.indices.filter { document.lines[$0].contains(timeMS: lyricMS) })
        if nextLines != activeLineIndices { activeLineIndices = nextLines }
        let nextActive = Set(nextLines.filter { document.lines[$0].hasWordTiming })
        if nextActive != activeWordLineIndices { activeWordLineIndices = nextActive }
        let nextInterludeID = interludes.first { $0.contains(timeMS: lyricMS) }?.id
        if nextInterludeID != activeInterludeID { activeInterludeID = nextInterludeID }
        let changing = nextActive.contains { document.lines[$0].hasChangingWord(at: lyricMS) }
        let visibleChanging = Self.hasVisibleChangingWord(document: document, activeLineIndices: nextActive,
                                                          visiblePresentationGroupIDs: visiblePresentationGroupIDs,
                                                          at: lyricMS)
        let visibleInterlude = nextInterludeID.map(visibleInterludeIDs.contains) ?? false
        let shouldRun = Self.shouldPulse(visible: isVisible, playing: playing,
                                        animateWords: animateWords, hasChangingWord: changing,
                                        hasChangingInterlude: nextInterludeID != nil, animateInterludes: animateInterludes,
                                        seeking: seekSnapshot.phase == .pending,
                                        hasVisibleChangingWord: visibleChanging,
                                        hasVisibleInterlude: visibleInterlude)
        if shouldRun {
            let interval = ProcessInfo.processInfo.isLowPowerModeEnabled || !visibleChanging ? 1.0 / 30 : 1.0 / 60
            guard pulse == nil || pulseInterval != interval else { return }
            pulse?.invalidate()
            let generation = observationGeneration
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.observationGeneration == generation else { return }
                    self.sample()
                }
            }
            timer.tolerance = interval * 0.1
            RunLoop.main.add(timer, forMode: .common)
            pulse = timer
            pulseInterval = interval
        } else if !shouldRun {
            pulse?.invalidate()
            pulse = nil
            pulseInterval = nil
        }
    }

    static func boundarySeconds(document: ExperimentalLyricsDocument, offsetMS: Double,
                                interludes: [ExperimentalLyricsInterlude] = []) -> [Double] {
        let offset = offsetMS.isFinite ? offsetMS : 0
        let vocalTimes = document.lines.flatMap { line -> [Double] in
            [line.effectiveStartMS, line.effectiveEndMS].compactMap { $0 } + line.words.filter(\.isValid).flatMap { [$0.startMS, $0.endMS] }
        }
        return Set(vocalTimes + interludes.flatMap { [$0.startMS, $0.endMS] })
            .map { ($0 - offset) / 1000 }.filter { $0.isFinite && $0 >= 0 }.sorted()
    }

    private func installBoundaries() {
        if let boundaryObserver { player?.removeTimeObserver(boundaryObserver) }
        boundaryObserver = nil
        guard let player, let document else { return }
        let times = Self.boundarySeconds(document: document, offsetMS: offsetMS, interludes: interludes)
        guard !times.isEmpty else { return }
        let generation = observationGeneration
        boundaryObserver = player.addBoundaryTimeObserver(forTimes: times.map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }, queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.observationGeneration == generation else { return }
                self.sample()
            }
        }
    }
}

/// Window-specific visibility; an inactive app can remain visible and keep playing.
struct ExperimentalLyricsVisibility: NSViewRepresentable {
    let onVisibility: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView { VisibilityView() }
    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onVisibility = onVisibility
        view.reportVisibility()
    }
    static func dismantleNSView(_ view: VisibilityView, coordinator: ()) { view.detach() }

    final class VisibilityView: NSView {
        var onVisibility: ((Bool) -> Void)?
        private var observations: [NSObjectProtocol] = []
        private var reportGeneration = UUID()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            clearObservations()
            if let window {
                let center = NotificationCenter.default
                for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                             NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                    observations.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.reportVisibility() }
                    })
                }
                for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                    observations.append(center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.reportVisibility() }
                    })
                }
            }
            reportVisibility()
        }

        func reportVisibility() {
            let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
            reportGeneration = UUID()
            let generation = reportGeneration
            // NSViewRepresentable update must not synchronously mutate SwiftUI state.
            Task { @MainActor [weak self] in
                guard let self, self.reportGeneration == generation else { return }
                self.onVisibility?(visible && !NSApp.isHidden)
            }
        }

        func detach() {
            reportGeneration = UUID()
            clearObservations()
            onVisibility?(false)
            onVisibility = nil
        }

        private func clearObservations() {
            observations.forEach(NotificationCenter.default.removeObserver)
            observations.removeAll()
        }
    }
}
