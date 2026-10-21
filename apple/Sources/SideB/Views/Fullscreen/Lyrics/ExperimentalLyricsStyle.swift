import AppKit
import SwiftUI
import Observation

/// Shared presentation values. These never assign or infer timing for a word.
enum ExperimentalLyricsStyle {
    static let defaultFontSize: CGFloat = 36
    static let tracking: CGFloat = -0.18
    static let lineHeightMultiple: CGFloat = 1.25
    static let focusTransitionDuration: Double = 0.788
    static let maximumSweepFeather: CGFloat = 30
    static let maximumWordScale: CGFloat = 1.13
    static let maximumWordLift: CGFloat = 2
    static let maximumGlowRadius: CGFloat = 5

    // Sample native font metrics once rather than asking AppKit on every frame.
    // The extra spacing fills the difference from the target baseline distance.
    private static let nativeLineHeightRatio: CGFloat = {
        let font = NSFont.systemFont(ofSize: defaultFontSize, weight: .bold)
        return (font.ascender - font.descender + font.leading) / defaultFontSize
    }()

    static func targetLineHeight(fontSize: CGFloat) -> CGFloat {
        max(0, fontSize) * lineHeightMultiple
    }

    static func lineSpacing(fontSize: CGFloat) -> CGFloat {
        max(0, targetLineHeight(fontSize: fontSize) - ceil(max(0, fontSize) * nativeLineHeightRatio))
    }

    static func activeBaseOpacity(increasedContrast: Bool) -> Double {
        increasedContrast ? 0.86 : 0.70
    }

    static func contextOpacity(increasedContrast: Bool) -> Double {
        increasedContrast ? 0.78 : 0.40
    }

    static func contextScale(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : 0.98
    }

    /// Blur plateaus at three rows away, so farther rows share the same visual state.
    static func visualDistance(_ distance: Int) -> Int {
        min(3, max(0, distance))
    }

    static func contextBlur(distance: Int, increasedContrast: Bool, reduceMotion: Bool, isFollowing: Bool = true) -> CGFloat {
        guard isFollowing, distance > 0, !increasedContrast, !reduceMotion else { return 0 }
        switch distance {
        case 1: return 1.2
        case 2: return 2.1
        default: return 3
        }
    }

    /// Horizontal displayPadding causes SwiftUI's raster pass to reshape text into
    /// the expanded width. Keep it zero: the panel's real lateral inset gives runs
    /// their horizontal drawing room. Vertical room protects lift and shadow.
    static func drawingPadding(fontSize: CGFloat) -> EdgeInsets {
        EdgeInsets(top: 24, leading: 0, bottom: 24, trailing: 0)
    }

    static func wordProgress(timeMS: Double, startMS: Double, endMS: Double) -> Double {
        guard timeMS.isFinite, startMS.isFinite, endMS.isFinite, endMS > startMS else { return 0 }
        return min(1, max(0, (timeMS - startMS) / (endMS - startMS)))
    }

    /// Only real sustained segments grow. Short syllables still fill at their own
    /// timestamps, with no scale or lift. Attack and release are bounded in time.
    static func wordEffect(timeMS: Double, startMS: Double, endMS: Double,
                           active: Bool, reduceMotion: Bool, wordMotion: Bool) -> ExperimentalLyricsWordEffect {
        guard active, !reduceMotion, wordMotion, timeMS.isFinite,
              startMS.isFinite, endMS.isFinite, endMS > startMS,
              timeMS > startMS, timeMS < endMS else { return .identity }
        let duration = endMS - startMS
        let elapsed = timeMS - startMS
        let remaining = endMS - timeMS
        let attack = min(240, duration * 0.24)
        let release = min(280, duration * 0.28)
        let envelope = smoothstep(elapsed / attack) * smoothstep(remaining / release)
        let sustain = smoothstep((duration - 700) / 1000) * envelope
        return ExperimentalLyricsWordEffect(
            scale: 1 + (maximumWordScale - 1) * sustain,
            lift: maximumWordLift * sustain,
            glowRadius: maximumGlowRadius,
            glowOpacity: 0.28 * envelope
        )
    }

    private static func smoothstep(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }
}

struct ExperimentalLyricsWordEffect: Equatable, Sendable {
    let scale: CGFloat
    let lift: CGFloat
    let glowRadius: CGFloat
    let glowOpacity: Double

    static let identity = Self(scale: 1, lift: 0, glowRadius: 0, glowOpacity: 0)
}

/// A continuous mask in the advance coordinates of ONE word, even when native
/// shaping splits it into several runs or it wraps across several visual lines.
struct ExperimentalLyricsWordSweep: Equatable, Sendable {
    let width: CGFloat
    let progress: Double
    let feather: CGFloat

    init(width: CGFloat, progress: Double) {
        self.width = width.isFinite ? max(0, width) : 0
        self.progress = progress.isFinite ? min(1, max(0, progress)) : 0
        self.feather = min(ExperimentalLyricsStyle.maximumSweepFeather, self.width * 0.5)
    }

    var fullyLitThrough: CGFloat { CGFloat(progress) * (width + feather) - feather }
    var fadesThrough: CGFloat { CGFloat(progress) * (width + feather) }

    func opacity(at distance: CGFloat) -> Double {
        guard width > 0, progress > 0 else { return 0 }
        guard progress < 1 else { return 1 }
        return Double(min(1, max(0, (fadesThrough - distance) / max(0.001, feather))))
    }

    /// Endpoint alphas preserve the same gradient when a run starts inside its soft
    /// edge. Clamping the edge independently per glyph would introduce visible steps.
    func stops(from start: CGFloat, to end: CGFloat) -> [ExperimentalLyricsMaskStop] {
        guard end > start else { return [] }
        var distances = [start, end]
        for edge in [fullyLitThrough, fadesThrough] where edge > start && edge < end {
            distances.append(edge)
        }
        return distances.sorted().map {
            ExperimentalLyricsMaskStop(location: ($0 - start) / (end - start), opacity: opacity(at: $0))
        }
    }
}

struct ExperimentalLyricsMaskStop: Equatable, Sendable {
    let location: CGFloat
    let opacity: Double
}


/// Presentation survives switching between rich lyrics and the line-only fallback.
/// Playback time remains owned by each renderer's local clock.
@MainActor @Observable
final class LyricsPresentationSettings {
    var fontSize: CGFloat = ExperimentalLyricsStyle.defaultFontSize
    var mode = ExperimentalLyricsMode.karaoke
    var followState = ExperimentalLyricsFollowState()
    private var playbackIdentity: UUID?

    func activate(_ identity: UUID) {
        guard playbackIdentity != identity else { return }
        playbackIdentity = identity
        followState.documentChanged(newOccurrence: true)
    }
}

enum ExperimentalLyricsMode: String, Hashable { case karaoke, reading }

enum LyricsPanelSelection {
    static func usesOriginal(prefersNew: Bool, hasNew: Bool, hasOriginal: Bool) -> Bool {
        !prefersNew || (!hasNew && hasOriginal)
    }
}

struct LyricsPhraseText: View {
    let text: String
    let fontSize: CGFloat
    let karaoke: Bool

    var body: some View {
        Text(text.isEmpty ? "♪" : text)
            .font(.system(size: fontSize, weight: karaoke ? .bold : .medium))
            .tracking(karaoke ? ExperimentalLyricsStyle.tracking : 0)
            .lineSpacing(ExperimentalLyricsStyle.lineSpacing(fontSize: fontSize))
            .padding(.vertical, karaoke ? ExperimentalLyricsStyle.lineSpacing(fontSize: fontSize) * 0.5 : 0)
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
    }
}

struct LyricsContextPresentation: ViewModifier {
    let karaoke: Bool
    let active: Bool
    let distance: Int
    let isFollowing: Bool
    let reduceMotion: Bool
    let increasedContrast: Bool

    func body(content: Content) -> some View {
        content
            .opacity(karaoke && !active ? ExperimentalLyricsStyle.contextOpacity(increasedContrast: increasedContrast) : 1)
            .blur(radius: karaoke && !active ? ExperimentalLyricsStyle.contextBlur(distance: distance,
                increasedContrast: increasedContrast, reduceMotion: reduceMotion, isFollowing: isFollowing) : 0)
            .scaleEffect(karaoke && !active ? ExperimentalLyricsStyle.contextScale(reduceMotion: reduceMotion) : 1, anchor: .leading)
            .animation(reduceMotion ? nil : .easeOut(duration: ExperimentalLyricsStyle.focusTransitionDuration), value: active)
            .animation(reduceMotion ? nil : .easeOut(duration: ExperimentalLyricsStyle.focusTransitionDuration), value: distance)
            .animation(nil, value: isFollowing)
    }
}

struct LyricsViewportMask: View {
    let height: CGFloat
    let increasedContrast: Bool

    var body: some View {
        if increasedContrast { Rectangle() }
        else {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: min(0.25, 48 / max(1, height))),
                .init(color: .white, location: max(0.75, 1 - 88 / max(1, height))),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct LyricsPresentationOptions: View {
    @Bindable var settings: LyricsPresentationSettings

    var body: some View {
        Picker(L10n.text("lyrics.experimental.options"), selection: $settings.mode) {
            Text(L10n.text("lyrics.experimental.mode.karaoke")).tag(ExperimentalLyricsMode.karaoke)
            Text(L10n.text("lyrics.experimental.mode.reading")).tag(ExperimentalLyricsMode.reading)
        }
        Section(L10n.text("lyrics.experimental.textSize")) {
            Button(L10n.text("lyrics.experimental.textSize.smaller")) { settings.fontSize = max(20, settings.fontSize - 2) }
                .disabled(settings.fontSize <= 20)
            Button(L10n.text("lyrics.experimental.textSize.larger")) { settings.fontSize = min(48, settings.fontSize + 2) }
                .disabled(settings.fontSize >= 48)
        }
    }
}
