import AppKit
import SideBCore
import Testing
@testable import SideB

@Suite("Genius lyric annotation layout")
@MainActor
struct GeniusLyricsLayoutTests {
    private func makeView(width: CGFloat) -> GeniusLyricsNSTextView {
        let view = GeniusLyricsNSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        view.isEditable = false
        view.isSelectable = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.textContainerInset = NSSize(width: 4, height: 8)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 2
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        return view
    }

    private var lines: [GeniusLyricLineRecord] {
        [
            GeniusLyricLineRecord(
                text: "[Produced by Just Blaze]", referentId: 1, isHeader: true,
                spans: [GeniusLyricSpanRecord(text: "[Produced by Just Blaze]", referentId: 1)]
            ),
            GeniusLyricLineRecord(
                text: "And the chapter that read at 25 I would live dormant like five in the morning",
                referentId: 2, isHeader: false,
                spans: [
                    GeniusLyricSpanRecord(text: "And the chapter that read at 25 I would live", referentId: 2),
                    GeniusLyricSpanRecord(text: " ", referentId: nil),
                    GeniusLyricSpanRecord(text: "dormant like five in the morning", referentId: 3)
                ]
            )
        ]
    }

    @Test("Blocks end at their glyphs and keep adjacent annotations separate")
    func wideLayout() {
        let view = makeView(width: 1100)
        view.setLyrics(lines, selectedReferentId: nil)
        let header = view.annotationHighlightRects(for: 1)
        let first = view.annotationHighlightRects(for: 2)
        let second = view.annotationHighlightRects(for: 3)
        #expect(header.count == 1)
        #expect(first.count == 1)
        #expect(second.count == 1)
        #expect(first[0].maxX < second[0].minX)
        #expect(second[0].maxX < view.bounds.maxX - 100)
        #expect(view.textStorage?.string.contains("live dormant") == true)
        #expect(view.hitTestReferent(at: NSPoint(x: first[0].midX, y: first[0].midY))?.0 == 2)
        #expect(view.hitTestReferent(at: NSPoint(x: second[0].midX, y: second[0].midY))?.0 == 3)
        #expect(view.hitTestReferent(at: NSPoint(x: header[0].midX, y: header[0].midY))?.0 == 1)
    }

    @Test("Wrapped annotations create separate blocks within the text container")
    func narrowLayout() {
        let view = makeView(width: 260)
        view.setLyrics(lines, selectedReferentId: nil)
        let first = view.annotationHighlightRects(for: 2)
        let second = view.annotationHighlightRects(for: 3)
        #expect(first.count > 1)
        #expect(!second.isEmpty)
        #expect((first + second).allSatisfy { $0.width > 0 && $0.maxX <= view.bounds.maxX })
        #expect(Set(first.map(\.minY)).count > 1)
    }

    @Test("Clicking each block sends its own annotation ID")
    func clickTargets() {
        let view = makeView(width: 1100)
        view.setLyrics(lines, selectedReferentId: nil)
        var selectedIDs: [Int64] = []
        view.onSelectAnnotation = { id, _ in selectedIDs.append(id) }
        for id: Int64 in [1, 2, 3] {
            guard let rect = view.annotationHighlightRects(for: id).first else {
                Issue.record("Could not lay out annotation \(id)")
                return
            }
            #expect(view.selectAnnotation(at: NSPoint(x: rect.midX, y: rect.midY)))
        }
        #expect(selectedIDs == [1, 2, 3])
    }

    @Test("Artwork tint redraws highlights while keeping text, selection and annotation geometry")
    func artworkTintRedraw() throws {
        let view = makeView(width: 560)
        view.setFrameSize(NSSize(width: 560, height: 160))
        view.drawsBackground = false
        view.setLyrics(lines, selectedReferentId: 2)
        view.setSelectedRange(NSRange(location: 4, length: 7))
        let text = view.string
        let rects = view.annotationHighlightRects(for: 2)
        func render(_ rgb: HomeAmbientRGB, name: String) throws -> Data {
            view.setAnnotationAppearance(palette: .from([rgb]), mode: .artwork)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            if let directory = ProcessInfo.processInfo.environment["SIDEB_PRESENTATION_QA"] {
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("genius-\(name).png"))
            }
            return data
        }
        let blue = try render(HomeAmbientRGB(red: 0.14, green: 0.31, blue: 0.82), name: "blue")
        let green = try render(HomeAmbientRGB(red: 0.20, green: 0.71, blue: 0.31), name: "green")
        #expect(blue != green)
        #expect(view.string == text)
        #expect(view.selectedRange() == NSRange(location: 4, length: 7))
        #expect(view.selectedReferentId == 2)
        #expect(view.annotationHighlightRects(for: 2) == rects)
    }
}
