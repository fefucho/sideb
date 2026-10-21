import SwiftUI
import AVFoundation

@MainActor
struct ExperimentalLyricsPanel: View {
    let document: ExperimentalLyricsDocument
    let player: AVPlayer
    let playbackIdentity: UUID
    let duration: Double
    let seekSnapshot: AudioPlayerSeekSnapshot
    let onSeek: (Double) -> Void
    let onShowOriginalLyrics: () -> Void
    let onRefresh: () -> Void
    let isRefreshing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var clock = ExperimentalLyricsClock()
    @State private var presentation: LyricsPresentationSettings
    @State private var showTranslation = true
    @State private var wordMotion = true
    @State private var offsetMS: Double = 0
    @State private var cachedItems: (document: ExperimentalLyricsDocument, duration: Double, items: [ExperimentalLyricsDisplayItem])
    @State private var recenterRevision: UInt64 = 0

    init(document: ExperimentalLyricsDocument, player: AVPlayer, playbackIdentity: UUID,
         duration: Double, seekSnapshot: AudioPlayerSeekSnapshot = .idle, onSeek: @escaping (Double) -> Void,
         onShowOriginalLyrics: @escaping () -> Void = {}, onRefresh: @escaping () -> Void = {},
         isRefreshing: Bool = false, presentation: LyricsPresentationSettings? = nil) {
        self.document = document
        self.player = player
        self.playbackIdentity = playbackIdentity
        self.duration = duration
        self.seekSnapshot = seekSnapshot
        self.onSeek = onSeek
        self.onShowOriginalLyrics = onShowOriginalLyrics
        self.onRefresh = onRefresh
        self.isRefreshing = isRefreshing
        _presentation = State(initialValue: presentation ?? LyricsPresentationSettings())
        _cachedItems = State(initialValue: (document, duration, Self.items(document: document, duration: duration)))
    }

    private var mode: ExperimentalLyricsMode { presentation.mode }
    private var fontSize: CGFloat { presentation.fontSize }

    var body: some View {
        Group {
            if document.instrumental {
                VStack(spacing: 10) {
                    Image(systemName: "music.note").font(.system(size: 34))
                    Text(L10n.text("lyrics.experimental.instrumental")).font(.title3.weight(.semibold))
                    Text(L10n.text("lyrics.experimental.instrumental.detail")).font(.callout)
                }
                .foregroundStyle(.white.opacity(0.80))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                lyricsScroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            controls.padding(.trailing, 8)
        }
        .background(ExperimentalLyricsVisibility { clock.setVisible($0) }.frame(width: 0, height: 0))
        .onAppear { startClock() }
        .onDisappear {
            presentation.followState.invalidateRequests()
            clock.stop()
        }
        .onChange(of: lifecycleInput) { previous, next in
            let newOccurrence = previous.playbackIdentity != next.playbackIdentity
            presentation.followState.documentChanged(newOccurrence: newOccurrence)
            if newOccurrence { offsetMS = 0 }
            startClock()
        }
        .onChange(of: duration) { _, next in
            cachedItems = (document, next, Self.items(document: document, duration: next))
            clock.updateDuration(next)
            recenterRevision &+= 1
        }
        .onChange(of: seekSnapshot) { _, next in clock.reconcileSeek(next) }
        .onChange(of: mode) { _, _ in configureClock() }
        .onChange(of: offsetMS) { _, _ in configureClock() }
        .onChange(of: wordMotion) { _, _ in configureClock() }
        .onChange(of: reduceMotion) { _, _ in configureClock() }
    }

    private var controls: some View {
        LyricsOptionsMenu(
            isShowingNewLyrics: true,
            onToggleLyrics: onShowOriginalLyrics,
            onRefresh: onRefresh,
            isRefreshing: isRefreshing
        ) {
            Section {
                Text(L10n.text("lyrics.experimental.source", args: [document.provider]))
                Text(timingDescription)
            }
            LyricsPresentationOptions(settings: presentation)
            Toggle(L10n.text("lyrics.experimental.wordMotion"), isOn: $wordMotion)
                .help(L10n.text("lyrics.experimental.wordMotion.help"))
            if document.hasTranslations {
                Toggle(L10n.text("lyrics.experimental.translation"), isOn: $showTranslation)
            }
            if document.hasLineTimings {
                Section(L10n.text("lyrics.experimental.offset")) {
                    Text(String(format: "%+.1f s", offsetMS / 1000))
                    // Positive offset advances the lyric clock relative to the audio.
                    Button(L10n.text("lyrics.experimental.offset.earlier")) { offsetMS = min(5000, offsetMS + 100) }
                    Button(L10n.text("lyrics.experimental.offset.later")) { offsetMS = max(-5000, offsetMS - 100) }
                    Button(L10n.text("lyrics.experimental.offset.reset")) { offsetMS = 0 }
                        .disabled(offsetMS == 0)
                }
            }
        }
    }

    private var lyricsScroll: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = geometry.size.width >= 330 ? 32 : 20
            // Match the measured phrase width; the trailing room also protects
            // sustained-word drawing without adding an unused sharing action.
            let textWidth = max(1, geometry.size.width - horizontalPadding * 2 - (mode == .karaoke ? 48 : 0))
            ScrollViewReader { proxy in
                let currentItems = currentDisplayItems
                let isIntro = clock.interludes.contains { $0.id == clock.activeInterludeID && $0.kind == .intro }
                let rawFocused = isIntro ? nil : clock.focusIndex
                let focused = rawFocused.flatMap { document.lines.indices.contains($0) ? $0 : nil }
                let active = clock.activeLineIndices
                let target = scrollTarget
                let focusAnchor = focused.flatMap { document.presentationAnchorIndex(for: $0) }
                let focusOrdinal = currentItems.first { $0.group?.anchorLineIndex == focusAnchor }?.ordinal ?? (isIntro ? -1 : 0)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(currentItems) { item in
                            if let group = item.group {
                                lyricGroup(group,
                                           distance: ExperimentalLyricsStyle.visualDistance(abs(item.ordinal - focusOrdinal)),
                                           focused: focused, active: active,
                                           onSeek: { seek($0, target: item.id, using: proxy) })
                                    .frame(maxWidth: textWidth, alignment: .leading)
                                    .padding(.vertical, mode == .karaoke ? 10 : 8)
                                    .id(item.id)
                                    .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                                        clock.setPresentationGroupVisible(id: item.id, visible: isVisible)
                                    }
                            } else if let interlude = item.interlude {
                                ExperimentalLyricsInterludeRow(
                                    interlude: interlude, clock: clock,
                                    isActive: clock.activeInterludeID == interlude.id,
                                    offsetMS: offsetMS,
                                    staticPresentation: reduceMotion || !wordMotion || mode != .karaoke,
                                    increasedContrast: contrast == .increased
                                )
                                .id(item.id)
                                .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                                    clock.setInterludeVisible(id: interlude.id, visible: isVisible)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    // This centering belongs only to the temporary presentation.
                    .padding(.vertical, mode == .karaoke && document.hasLineTimings ? geometry.size.height / 2 : 12)
                }
                .scrollIndicators(.hidden)
                .mask { LyricsViewportMask(height: geometry.size.height, increasedContrast: contrast == .increased) }
                .onScrollPhaseChange { _, phase in
                    if document.hasLineTimings && (phase == .tracking || phase == .interacting) { presentation.followState.userScrolled() }
                }
                .overlay(alignment: .bottom) {
                    if document.hasLineTimings && !presentation.followState.isFollowing {
                        Button {
                            presentation.followState.resume()
                            center(target, using: proxy, animated: true)
                        } label: {
                            SideBControlLabel(title: L10n.text("fullscreen.returnToCurrentLyric"), symbol: "location.fill")
                        }
                        .buttonStyle(SideBControlStyle())
                        .padding(.bottom, 12)
                        .accessibilityLabel(L10n.text("fullscreen.resumeLyricsTracking"))
                    }
                }
                .onChange(of: target) { _, next in
                    scheduleCenter(next, using: proxy, animated: true)
                }
                .onChange(of: geometry.size) { _, _ in recenter(using: proxy) }
                .onChange(of: fontSize) { _, _ in recenter(using: proxy) }
                .onChange(of: showTranslation) { _, _ in recenter(using: proxy) }
                .onChange(of: mode) { _, _ in recenter(using: proxy) }
                .onChange(of: recenterRevision) { _, _ in recenter(using: proxy) }
                .onAppear { recenter(using: proxy) }
            }
        }
    }

    private func lyricGroup(_ group: ExperimentalLyricsPresentationGroup, distance: Int,
                            focused: Int?, active: Set<Int>, onSeek: @escaping (Double) -> Void) -> some View {
        let lines = document.lines
        let validIndices = group.lineIndices.filter { lines.indices.contains($0) }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(validIndices, id: \.self) { index in
                if lines.indices.contains(index) {
                    ExperimentalLyricsRow(
                        line: lines[index], lineIndex: index, clock: clock,
                        isFocused: index == focused, isAnimated: active.contains(index) || !document.hasLineTimings,
                        isPast: isPast(index, focused: focused), distance: distance,
                        backgroundVoice: group.backgroundLineIndices.contains(index),
                        karaoke: mode == .karaoke, offsetMS: offsetMS,
                        fontSize: fontSize, showTranslation: showTranslation,
                        reduceMotion: reduceMotion, increasedContrast: contrast == .increased,
                        wordMotion: wordMotion, isFollowing: presentation.followState.isFollowing, onSeek: onSeek
                    )
                }
            }
        }
    }

    private var scrollTarget: String? {
        if let waiting = clock.interludes.first(where: { $0.id == clock.activeInterludeID }) {
            return waiting.id
        }
        return clock.focusIndex.flatMap { document.presentationAnchorIndex(for: $0) }.map { "line:\($0)" }
    }

    private var timingDescription: String {
        if document.hasWordTimings { return L10n.text("lyrics.experimental.timing.words") }
        if document.hasLineTimings { return L10n.text("lyrics.experimental.timing.lines") }
        return L10n.text("lyrics.experimental.timing.plain")
    }

    private func isPast(_ index: Int, focused: Int?) -> Bool {
        guard let focused,
              document.lines.indices.contains(focused),
              document.lines.indices.contains(index),
              let focusStart = document.lines[focused].effectiveStartMS,
              let start = document.lines[index].effectiveStartMS else { return false }
        return start < focusStart
    }

    private func seek(_ lineMS: Double, target: String, using proxy: ScrollViewProxy) {
        guard let seconds = ExperimentalLyricsSeekTarget.audioSeconds(lineMS: lineMS, offsetMS: offsetMS, duration: duration) else { return }
        presentation.followState.resume()
        clock.notifySeek(toAudioSeconds: seconds)
        center(target, using: proxy, animated: true)
        onSeek(seconds)
    }

    private func center(_ target: String?, using proxy: ScrollViewProxy, animated: Bool) {
        guard let target else { return }
        if animated && !reduceMotion {
            withAnimation(.spring(response: ExperimentalLyricsStyle.focusTransitionDuration, dampingFraction: 0.96)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else { proxy.scrollTo(target, anchor: .center) }
    }

    private func recenter(using proxy: ScrollViewProxy) {
        scheduleCenter(scrollTarget, using: proxy, animated: false)
    }

    private func scheduleCenter(_ target: String?, using proxy: ScrollViewProxy, animated: Bool) {
        guard let request = presentation.followState.beginRequest() else { return }
        Task { @MainActor in
            await Task.yield()
            guard presentation.followState.canApply(request) else { return }
            center(target, using: proxy, animated: animated)
        }
    }

    private func startClock() {
        presentation.activate(playbackIdentity)
        cachedItems = (document, duration, Self.items(document: document, duration: duration))
        clock.start(player: player, document: document, duration: duration,
                    playbackIdentity: playbackIdentity, seekSnapshot: seekSnapshot)
        configureClock()
        recenterRevision &+= 1
    }

    private var currentDisplayItems: [ExperimentalLyricsDisplayItem] {
        if cachedItems.document == document && cachedItems.duration == duration {
            return cachedItems.items
        }
        return Self.items(document: document, duration: duration)
    }

    private func configureClock() {
        clock.configure(animateWords: mode == .karaoke, offsetMS: offsetMS,
                        animateInterludes: mode == .karaoke && !reduceMotion && wordMotion)
    }

    private static func items(document: ExperimentalLyricsDocument, duration: Double) -> [ExperimentalLyricsDisplayItem] {
        ExperimentalLyricsDisplayItem.sequence(document: document, duration: duration)
    }

    private var lifecycleInput: ExperimentalLyricsPanelInput {
        .init(document: document, playbackIdentity: playbackIdentity)
    }
}

private struct ExperimentalLyricsPanelInput: Equatable {
    let document: ExperimentalLyricsDocument
    let playbackIdentity: UUID
}

/// Manual scrolling wins until an explicit lyric click/return or a new occurrence.
/// Request generations also prevent a deferred resize/refresh from stealing it back.
struct ExperimentalLyricsFollowState {
    private(set) var isFollowing = true
    private var revision: UInt64 = 0

    mutating func userScrolled() { isFollowing = false; invalidateRequests() }
    mutating func resume() { isFollowing = true; invalidateRequests() }
    mutating func documentChanged(newOccurrence: Bool) {
        if newOccurrence { isFollowing = true }
        invalidateRequests()
    }
    mutating func invalidateRequests() { revision &+= 1 }
    mutating func beginRequest() -> UInt64? {
        guard isFollowing else { return nil }
        invalidateRequests()
        return revision
    }
    func canApply(_ request: UInt64) -> Bool { isFollowing && revision == request }
}

enum ExperimentalLyricsSeekTarget {
    static func audioSeconds(lineMS: Double, offsetMS: Double, duration: Double) -> Double? {
        guard lineMS.isFinite, lineMS >= 0, offsetMS.isFinite else { return nil }
        let seconds = max(0, (lineMS - offsetMS) / 1000)
        guard seconds.isFinite else { return nil }
        return duration.isFinite && duration > 0 ? min(duration, seconds) : seconds
    }
}

@MainActor
private struct ExperimentalLyricsRow: View {
    let line: ExperimentalLyricLine
    let lineIndex: Int
    let clock: ExperimentalLyricsClock
    let isFocused: Bool
    let isAnimated: Bool
    let isPast: Bool
    let distance: Int
    let backgroundVoice: Bool
    let karaoke: Bool
    let offsetMS: Double
    let fontSize: CGFloat
    let showTranslation: Bool
    let reduceMotion: Bool
    let increasedContrast: Bool
    let wordMotion: Bool
    let isFollowing: Bool
    let onSeek: (Double) -> Void

    private var rowFontSize: CGFloat { backgroundVoice ? max(18, fontSize * 0.68) : fontSize }
    private var active: Bool { isFocused || isAnimated }
    private var accessibleText: String {
        var text = backgroundVoice ? L10n.text("lyrics.experimental.voice.background") + ". " + line.text : line.text
        if showTranslation, let translation = line.translation { text += ". " + translation }
        return text
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 7) {
            if karaoke && line.hasWordTiming {
                // Only word-active rows subscribe to frame position. A completed focus
                // uses its fixed end timestamp while focus persists through a gap.
                let time = isAnimated
                    ? clock.positionMS + offsetMS
                    : (isPast ? Double.greatestFiniteMagnitude
                       : (isFocused && clock.completedFocusIndex == self.lineIndex ? line.effectiveEndMS ?? 0 : 0))
                ExperimentalKaraokeText(line: line, timeMS: time, active: active,
                                       reduceMotion: reduceMotion, increasedContrast: increasedContrast,
                                       fontSize: rowFontSize, wordMotion: wordMotion)
            } else {
                LyricsPhraseText(text: line.text, fontSize: rowFontSize, karaoke: karaoke)
            }
            if showTranslation, let translation = line.translation, !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(translation)
                    .font(.system(size: max(13, rowFontSize * 0.57)))
                    .foregroundStyle(.white.opacity(increasedContrast ? 0.95 : 0.80))
                    .multilineTextAlignment(.leading)
            }
        }
        .modifier(LyricsContextPresentation(karaoke: karaoke, active: active, distance: distance,
                                           isFollowing: isFollowing, reduceMotion: reduceMotion,
                                           increasedContrast: increasedContrast))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleText)

        if let start = line.effectiveStartMS {
            Button { onSeek(start) } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibleText)
                .accessibilityAddTraits(isFocused ? [.isSelected] : [])
                .accessibilityHint(L10n.text("fullscreen.goToLyricLine"))
        } else { content }
    }
}

@MainActor
private struct ExperimentalLyricsInterludeRow: View {
    let interlude: ExperimentalLyricsInterlude
    let clock: ExperimentalLyricsClock
    let isActive: Bool
    let offsetMS: Double
    let staticPresentation: Bool
    let increasedContrast: Bool

    var body: some View {
        // Reserve stable geometry so the row cannot collapse during a simultaneous
        // focus/scroll transition at the next vocal entrance. Hidden rows never tick.
        let progress = isActive && !staticPresentation ? interlude.progress(at: clock.positionMS + offsetMS) : 1
        ExperimentalLyricsInterludeIndicator(progress: progress, increasedContrast: increasedContrast)
            .opacity(isActive ? 1 : 0)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.text(accessibilityKey))
            .accessibilityHidden(!isActive)
    }

    private var accessibilityKey: String {
        switch interlude.kind {
        case .intro: "lyrics.experimental.wait.intro"
        case .interlude: "lyrics.experimental.wait.interlude"
        case .outro: "lyrics.experimental.wait.outro"
        }
    }
}

/// Stateless drawing keeps the indicator tied to the media clock and makes paused
/// and reduced-motion presentations independent of an animation timer.
struct ExperimentalLyricsInterludeIndicator: View {
    let progress: Double
    let increasedContrast: Bool

    var body: some View {
        let value = progress.isFinite ? min(1, max(0, progress)) : 0
        HStack(spacing: 10) {
            ForEach(0..<3) { index in
                let fill = min(1, max(0, value * 3 - Double(index)))
                Circle()
                    .fill(.white.opacity(increasedContrast ? 0.65 + 0.35 * fill : 0.22 + 0.78 * fill))
                    .frame(width: 14, height: 14)
                    .scaleEffect(0.52 + 0.48 * fill)
                    .shadow(color: .white.opacity(increasedContrast ? 0 : 0.45 * fill), radius: 16)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Overlay shared by loaded lyrics and the original/loading/empty states.
/// Its controls never take height away from the lyrics viewport.
struct LyricsOptionsMenu<Options: View>: View {
    let isShowingNewLyrics: Bool
    let onToggleLyrics: () -> Void
    let onRefresh: () -> Void
    let isRefreshing: Bool
    @ViewBuilder let options: () -> Options

    var body: some View {
        Menu {
            options()
            Section {
                if isShowingNewLyrics {
                    Button(L10n.text("lyrics.experimental.refresh"), action: onRefresh)
                        .disabled(isRefreshing)
                }
                Button(L10n.text(isShowingNewLyrics ? "lyrics.experimental.returnToCurrent" : "lyrics.experimental.tryNew"),
                       action: onToggleLyrics)
                    .disabled(isRefreshing && !isShowingNewLyrics)
                    .accessibilityIdentifier("lyrics.experimental.switch")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.text("lyrics.experimental.options"))
        .accessibilityLabel(L10n.text("lyrics.experimental.options"))
        .accessibilityIdentifier("lyrics.options")
        .windowGestureRegion(.excluded)
    }
}
