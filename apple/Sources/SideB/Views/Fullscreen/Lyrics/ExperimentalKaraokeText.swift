import SwiftUI

private struct ExperimentalWordTiming: TextAttribute {
    let index: Int
    let startMS: Double
    let endMS: Double
}

/// One composed Text preserves native shaping, wrapping, punctuation and Unicode.
/// Timing attaches to actual segments, without dividing the phrase into equal times.
struct ExperimentalKaraokeText: View {
    let line: ExperimentalLyricLine
    let timeMS: Double
    let active: Bool
    let reduceMotion: Bool
    let increasedContrast: Bool
    let fontSize: CGFloat
    var wordMotion: Bool = true

    // The reference is local to this mounted row. Memoization never publishes UI
    // state and never retains a Text.Layout across SwiftUI layout generations.
    @State private var contentCache = ExperimentalKaraokeTextCache()

    var body: some View {
        renderedText
            .multilineTextAlignment(.leading)
            .padding(.vertical, ExperimentalLyricsStyle.lineSpacing(fontSize: fontSize) * 0.5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.text.isEmpty ? "♪" : line.text)
    }

    @ViewBuilder
    private var renderedText: some View {
        let text = contentCache.content(for: line).text
            .font(.system(size: fontSize, weight: .bold))
            .tracking(ExperimentalLyricsStyle.tracking)
            .lineSpacing(ExperimentalLyricsStyle.lineSpacing(fontSize: fontSize))
            .foregroundStyle(.white)
        if active {
            text.textRenderer(ExperimentalKaraokeRenderer(
                timeMS: timeMS, active: active, reduceMotion: reduceMotion,
                unsungOpacity: ExperimentalLyricsStyle.activeBaseOpacity(increasedContrast: increasedContrast),
                wordMotion: wordMotion, fontSize: fontSize
            ))
        } else {
            // Keep the same attributed Text and typography when a voice becomes
            // contextual. Only the custom drawing pass is unnecessary here.
            text
        }
    }
}

/// A bounded one-entry cache, owned by a mounted lyric view rather than a global.
/// A refresh with changed text, segmentation or timings replaces it synchronously.
final class ExperimentalKaraokeTextCache {
    final class Content {
        let line: ExperimentalLyricLine
        let text: Text

        init(line: ExperimentalLyricLine, text: Text) {
            self.line = line
            self.text = text
        }
    }

    private var cached: Content?

    func content(for line: ExperimentalLyricLine) -> Content {
        if let cached, cached.line == line { return cached }
        let content = Content(line: line, text: Self.compose(line: line))
        cached = content
        return content
    }

    private static func compose(line: ExperimentalLyricLine) -> Text {
        guard let segments = line.karaokeSegments else { return Text(line.text.isEmpty ? "•••" : line.text) }
        return segments.reduce(Text("")) { result, segment in
            guard let index = segment.wordIndex else { return result + Text(segment.text) }
            let word = line.words[index]
            // Keep provider whitespace in the composed Text, but out of the word's
            // transform. This preserves a stable physical gap beside a sustained word.
            guard let first = segment.text.firstIndex(where: { !$0.isWhitespace }),
                  let last = segment.text.lastIndex(where: { !$0.isWhitespace }) else {
                return result + Text(segment.text)
            }
            let end = segment.text.index(after: last)
            return result + Text(String(segment.text[..<first]))
                + Text(String(segment.text[first..<end])).customAttribute(
                    ExperimentalWordTiming(index: index, startMS: word.startMS, endMS: word.endMS)
                ) + Text(String(segment.text[end...]))
        }
    }
}

/// Effects transform shaped runs, not strings or the layout. All fragments of a word
/// share its timing and sweep; fragments on one visual line share a transform origin.
struct ExperimentalKaraokeRenderer: TextRenderer {
    let timeMS: Double
    let active: Bool
    let reduceMotion: Bool
    let unsungOpacity: Double
    let wordMotion: Bool
    let fontSize: CGFloat

    var displayPadding: EdgeInsets { ExperimentalLyricsStyle.drawingPadding(fontSize: fontSize) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        guard active else {
            // Context opacity belongs to the row. Applying unsung opacity here would
            // dim word-timed context twice compared with a line-only fallback.
            for line in layout { for run in line { context.draw(run) } }
            return
        }
        let geometry = wordGeometry(layout: layout)
        for (lineIndex, line) in layout.enumerated() {
            for (runIndex, run) in line.enumerated() {
                let key = FragmentKey(line: lineIndex, run: runIndex)
                guard let timing = run[ExperimentalWordTiming.self], let fragment = geometry[key] else {
                    var base = context
                    base.opacity = geometry.isEmpty ? 1 : unsungOpacity
                    base.draw(run)
                    continue
                }
                let progress = ExperimentalLyricsStyle.wordProgress(timeMS: timeMS, startMS: timing.startMS, endMS: timing.endMS)
                let effect = ExperimentalLyricsStyle.wordEffect(timeMS: timeMS, startMS: timing.startMS,
                                                               endMS: timing.endMS, active: active,
                                                               reduceMotion: reduceMotion, wordMotion: wordMotion)
                var positioned = context
                // Bound the transform to drawing room even for an exceptionally wide
                // unbroken word. Its layout and timing remain intact.
                let spare = max(0, 24 - 2 * effect.glowRadius)
                let scale = min(effect.scale, fragment.maximumScale,
                                1 + spare / max(1, fragment.anchorBounds.width * 0.5))
                let anchor = CGPoint(x: fragment.anchorBounds.midX, y: fragment.anchorBounds.maxY)
                positioned.translateBy(x: anchor.x, y: anchor.y - effect.lift)
                positioned.scaleBy(x: scale, y: scale)
                positioned.translateBy(x: -anchor.x, y: -anchor.y)
                var base = positioned
                base.opacity = unsungOpacity
                base.draw(run)
                guard progress > 0 else { continue }
                var lit = positioned
                if effect.glowOpacity > 0 {
                    lit.addFilter(.shadow(color: .white.opacity(effect.glowOpacity), radius: effect.glowRadius))
                }
                guard progress < 1 else { lit.draw(run); continue }
                let sweep = ExperimentalLyricsWordSweep(width: fragment.wordWidth, progress: progress)
                let rect = run.typographicBounds.rect
                let overhang = max(4, fontSize * 0.2)
                let bounds = rect.insetBy(dx: -overhang, dy: -overhang)
                let stops = sweep.stops(from: fragment.advance - overhang,
                                        to: fragment.advance + rect.width + overhang)
                guard stops.contains(where: { $0.opacity > 0 }) else { continue }
                let rightToLeft = run.layoutDirection == .rightToLeft
                let start = CGPoint(x: rightToLeft ? bounds.maxX : bounds.minX, y: bounds.midY)
                let end = CGPoint(x: rightToLeft ? bounds.minX : bounds.maxX, y: bounds.midY)
                lit.drawLayer { layer in
                    layer.draw(run)
                    layer.blendMode = .destinationIn
                    layer.fill(Path(bounds), with: .linearGradient(
                        Gradient(stops: stops.map { .init(color: .white.opacity($0.opacity), location: $0.location) }),
                        startPoint: start, endPoint: end
                    ))
                }
            }
        }
    }

    private struct FragmentKey: Hashable {
        let line: Int
        let run: Int
    }

    private struct ShapedFragment {
        let key: FragmentKey
        let firstCharacter: Text.Layout.CharacterIndex?
        let bounds: CGRect
    }

    private struct FragmentGeometry {
        let wordWidth: CGFloat
        let advance: CGFloat
        let anchorBounds: CGRect
        let maximumScale: CGFloat
    }

    private func wordGeometry(layout: Text.Layout) -> [FragmentKey: FragmentGeometry] {
        var words: [Int: [ShapedFragment]] = [:]
        for (lineIndex, line) in layout.enumerated() {
            for (runIndex, run) in line.enumerated() {
                guard let timing = run[ExperimentalWordTiming.self], run.typographicBounds.rect.width > 0 else { continue }
                words[timing.index, default: []].append(ShapedFragment(
                    key: FragmentKey(line: lineIndex, run: runIndex),
                    firstCharacter: run.characterIndices.min(), bounds: run.typographicBounds.rect
                ))
            }
        }
        var lineAnchors: [Int: [Int: CGRect]] = [:]
        for (wordIndex, fragments) in words {
            for fragment in fragments {
                let previous = lineAnchors[fragment.key.line]?[wordIndex]
                lineAnchors[fragment.key.line, default: [:]][wordIndex] = previous.map { $0.union(fragment.bounds) } ?? fragment.bounds
            }
        }
        let lineScales = lineAnchors.mapValues { ExperimentalLyricsWordAnchors.maximumScales(anchors: $0) }
        var result: [FragmentKey: FragmentGeometry] = [:]
        for (wordIndex, fragments) in words {
            // Visual run order may differ for RTL or mixed-direction text. Native
            // character indices recover logical order without inspecting graphemes.
            let ordered = fragments.sorted {
                if let left = $0.firstCharacter, let right = $1.firstCharacter, left != right { return left < right }
                if $0.key.line != $1.key.line { return $0.key.line < $1.key.line }
                return $0.key.run < $1.key.run
            }
            let width = ordered.reduce(CGFloat.zero) { $0 + $1.bounds.width }
            var advance: CGFloat = 0
            for fragment in ordered {
                let anchors = lineAnchors[fragment.key.line] ?? [:]
                let anchor = anchors[wordIndex] ?? fragment.bounds
                result[fragment.key] = FragmentGeometry(wordWidth: width, advance: advance,
                    anchorBounds: anchor, maximumScale: lineScales[fragment.key.line]?[wordIndex] ?? 1)
                advance += fragment.bounds.width
            }
        }
        return result
    }
}
