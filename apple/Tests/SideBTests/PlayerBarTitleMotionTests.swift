import AppKit
import SideBCore
import Testing
@testable import SideB

@Test func playerTitleCycleUsesSharedTiming() {
    let short = PlayerTitleMotionCycle(overflow: 48)
    #expect(short.travelDuration == 3.5)
    #expect(short.offset(at: 0.9) == 0)
    #expect(short.offset(at: 2.75) == -24)
    #expect(short.offset(at: short.duration) == -48)
    let long = PlayerTitleMotionCycle(overflow: 240)
    #expect(long.travelDuration == 10)
    #expect(long.duration == 12.3)
}

@MainActor private func titleViewport(_ title: String, width: CGFloat = 120) -> NativePlayerTitleViewport {
    let view = NativePlayerTitleViewport(frame: CGRect(x: 0, y: 0, width: width, height: 24))
    view.field.font = .systemFont(ofSize: 14, weight: .semibold)
    view.field.maximumNumberOfLines = 1
    view.field.isBezeled = false; view.field.drawsBackground = false
    let track = SongItemRecord(videoId: "motion", title: title, artists: "Main", album: nil,
        duration: nil, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
        isVideo: false, isUpload: false, library: nil, artistRuns: [])
    view.field.configureFeatured(track: track, isTitle: true) { _, _ in }
    view.configure(identity: title, enabled: true, reduceMotion: false, active: true)
    return view
}

@Test @MainActor func playerTitlePausePreservesElapsedAndNativeGeometryThenResizeResets() {
    let title = "A long title with accents áéíóú and emoji 🎵 that must scroll"
    let view = titleViewport(title)
    defer { view.tearDown() }
    #expect(view.overflow > 1)
    view.advance(to: 2)
    let position = view.bounds.origin
    #expect(position.x > 0)
    view.setHovered(true)
    view.configure(identity: title, enabled: true, reduceMotion: false, active: true)
    #expect(view.bounds.origin == position)
    #expect(view.elapsed == 2)
    view.setHovered(false)
    #expect(view.elapsed == 2)
    view.setHovered(true)
    view.frame.size.width = 150
    view.needsLayout = true; view.layoutSubtreeIfNeeded()
    #expect(view.bounds.origin.x == 0)
    #expect(view.elapsed == 0)
    view.advance(to: 2)
    view.configure(identity: "another track", enabled: true, reduceMotion: false, active: true)
    #expect(view.bounds.origin.x == 0)
}

@Test @MainActor func playerTitleMovesCreditHitTargetsAndClipsInvisibleLinks() throws {
    let view = titleViewport("A deliberately very long title before the featured credit (feat. Guest)", width: 140)
    defer { view.tearDown() }
    let host = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
    host.addSubview(view)
    view.field.layoutSubtreeIfNeeded()
    let button = try #require(view.field.subviews.compactMap { $0 as? NativeFeaturedArtistButton }.first)
    view.showOffset(0)
    #expect(button.isHidden)
    view.setHovered(true)
    // A resolver/layout refresh must not restore an offscreen credit while paused.
    view.field.frame.size.height += 1
    view.field.needsLayout = true; view.field.layoutSubtreeIfNeeded()
    #expect(button.isHidden)
    view.field.frame.size.height -= 1
    view.field.needsLayout = true; view.field.layoutSubtreeIfNeeded()
    let initial = view.convert(button.bounds, from: button)
    view.showOffset(-view.overflow)
    let final = view.convert(button.bounds, from: button)
    // Document coordinates stay stable; their window positions move with native clip bounds.
    #expect(initial == final)
    #expect(view.bounds.origin.x > 0)
    #expect(view.bounds.contains(final))
    #expect(!button.isHidden)
    let point = host.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
    #expect(host.hitTest(point) === button)
    view.setHovered(true)
    #expect(view.bounds.contains(view.convert(button.bounds, from: button)))
}

@Test @MainActor func playerTitleReduceMotionAndShortTitlesStayStatic() {
    let view = titleViewport("Short", width: 200)
    defer { view.tearDown() }
    #expect(view.overflow == 0)
    #expect(view.bounds.origin.x == 0)
    view.configure(identity: "Short", enabled: true, reduceMotion: true, active: true)
    #expect(view.field.lineBreakMode == .byTruncatingTail)
    #expect(view.bounds.origin.x == 0)
    #expect(view.field.toolTip?.contains("Short") == true)
}
