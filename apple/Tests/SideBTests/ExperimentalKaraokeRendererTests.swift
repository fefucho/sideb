import AppKit
import SwiftUI
import Testing
@testable import SideB

@Suite("Karaoke: prepared text and physical word neighbours")
@MainActor
struct ExperimentalKaraokeRendererTests {
    @Test("Prepared text is reused and a refresh invalidates text and word timings")
    func preparedTextInvalidation() {
        let cache = ExperimentalKaraokeTextCache()
        func line(_ text: String, end: Double) -> ExperimentalLyricLine {
            .init(startMS: 0, endMS: end, text: text, words: [.init(text: text, startMS: 0, endMS: end)])
        }
        let original = line("office 👩🏽‍🚀", end: 1000)
        let first = cache.content(for: original)
        #expect(first === cache.content(for: original))
        let retimed = cache.content(for: line(original.text, end: 2000))
        #expect(first !== retimed)
        #expect(retimed.line.words[0].endMS == 2000)
        let edited = cache.content(for: line("مرحبًا", end: 2000))
        #expect(retimed !== edited)
        #expect(edited.line.text == "مرحبًا")
        #expect(first !== cache.content(for: original)) // bounded to one entry
    }

    @Test("Sorted neighbours equal exhaustive collision bounds, including nested and RTL anchors")
    func neighboursMatchExhaustiveReference() {
        var seed: UInt64 = 0x26
        func random(_ limit: UInt64) -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed % limit)
        }
        var cases: [[Int: CGRect]] = [[:], [0: CGRect(x: 0, y: 0, width: 100, height: 20)],
            [8: CGRect(x: 0, y: 0, width: 100, height: 20),
             4: CGRect(x: 10, y: 0, width: 5, height: 20),
             1: CGRect(x: 40, y: 0, width: 10, height: 20)],
            [2: CGRect(x: 0, y: 0, width: 20, height: 20),
             1: CGRect(x: 20, y: 0, width: 30, height: 20),
             0: CGRect(x: 80, y: 0, width: 25, height: 20)]]
        for count in [2, 6, 40, 200] {
            for _ in 0..<15 {
                var anchors: [Int: CGRect] = [:]
                for word in 0..<count {
                    anchors[word] = CGRect(x: random(1000) - 200, y: 0, width: random(180) + 1, height: 20)
                }
                cases.append(anchors)
            }
        }
        for anchors in cases {
            let actual = ExperimentalLyricsWordAnchors.maximumScales(anchors: anchors)
            #expect(actual.count == anchors.count)
            for (word, anchor) in anchors {
                var room: CGFloat = 24
                for (otherWord, other) in anchors where word != otherWord {
                    if other.maxX <= anchor.minX {
                        room = min(room, max(0, anchor.minX - other.maxX) * 0.45)
                    } else if other.minX >= anchor.maxX {
                        room = min(room, max(0, other.minX - anchor.maxX) * 0.45)
                    } else { room = 0 }
                }
                #expect(actual[word] == 1 + room / max(1, anchor.width * 0.5))
            }
        }
    }

    @Test("Native context keeps the custom renderer's exact fitting size across shaping and wrapping")
    func contextPreservesLayout() throws {
        let fixtures = [
            ["of", "fice ", "affine ", "café ", "👩🏽‍🚀 ", "私たち ", "مرحبًا ", "بالعالم"],
            ["私たちはひとつの長い言葉を複数の行に包んで読みます"],
            ["  Una\n", "segunda\n", "tercera\n", "cuarta\n", "quinta línea  "],
            ["مرحبا ", "office ", "بالعالم ", "123"]
        ]
        for segments in fixtures {
            let line = ExperimentalLyricLine(startMS: 0, endMS: Double(segments.count) * 3000,
                text: segments.joined(), words: segments.enumerated().map {
                    .init(text: $0.element, startMS: Double($0.offset) * 3000, endMS: Double($0.offset + 1) * 3000)
                })
            #expect(line.hasWordTiming)
            for fontSize: CGFloat in [24.48, 36, 52] {
                for width: CGFloat in [220, 420, 560] {
                    let native = ExperimentalKaraokeText(line: line, timeMS: 0, active: false,
                        reduceMotion: false, increasedContrast: false, fontSize: fontSize)
                    let active = ExperimentalKaraokeText(line: line, timeMS: 1500, active: true,
                        reduceMotion: false, increasedContrast: false, fontSize: fontSize)
                    let reference = ExperimentalKaraokeTextCache().content(for: line).text
                        .font(.system(size: fontSize, weight: .bold))
                        .tracking(ExperimentalLyricsStyle.tracking)
                        .lineSpacing(ExperimentalLyricsStyle.lineSpacing(fontSize: fontSize))
                        .foregroundStyle(.white)
                        .textRenderer(ExperimentalKaraokeRenderer(timeMS: 0, active: false, reduceMotion: false,
                            unsungOpacity: 0.7, wordMotion: true, fontSize: fontSize))
                        .multilineTextAlignment(.leading)
                        .padding(.vertical, ExperimentalLyricsStyle.lineSpacing(fontSize: fontSize) * 0.5)
                    let nativeSize = NSHostingView(rootView: native.frame(width: width, alignment: .leading)).fittingSize
                    let activeSize = NSHostingView(rootView: active.frame(width: width, alignment: .leading)).fittingSize
                    let referenceSize = NSHostingView(rootView: reference.frame(width: width, alignment: .leading)).fittingSize
                    #expect(nativeSize == referenceSize)
                    #expect(nativeSize == activeSize)
                    #expect(nativeSize.height > 0 && nativeSize.height.isFinite)
                    if fontSize == 36 {
                        func raster<V: View>(_ view: V) throws -> CGImage {
                            let renderer = ImageRenderer(content: view.frame(width: width, alignment: .leading).padding(24).background(Color.black))
                            renderer.scale = 2
                            return try #require(renderer.cgImage)
                        }
                        let nativeImage = try raster(native)
                        let referenceImage = try raster(reference)
                        #expect(nativeImage.width == referenceImage.width)
                        #expect(nativeImage.height == referenceImage.height)
                        let nativePixels = try #require(nativeImage.dataProvider?.data)
                        let referencePixels = try #require(referenceImage.dataProvider?.data)
                        #expect(nativePixels as Data == referencePixels as Data)
                    }
                }
            }
        }
    }
}
