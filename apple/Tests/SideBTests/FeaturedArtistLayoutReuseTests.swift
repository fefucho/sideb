import AppKit
import SideBCore
import Testing
@testable import SideB

private func layoutSong(_ title: String, artist: String = "Guest") -> SongItemRecord {
    SongItemRecord(videoId: "layout", title: title, artists: artist, album: nil, duration: nil,
        thumbnail: nil, artistId: "guest", albumId: nil, setVideoId: nil, isVideo: false,
        isUpload: false, library: nil, artistRuns: [.init(text: artist, id: "guest")])
}

@Test @MainActor func featuredLayoutReusesMeasurementAndButtonsUntilGeometryChanges() throws {
    let field = NativeTrackActionField(frame: NSRect(x: 0, y: 0, width: 400, height: 26))
    field.font = .systemFont(ofSize: 14)
    field.maximumNumberOfLines = 1
    let overlay = NativeFeaturedArtistOverlay(field: field)
    let track = layoutSong("Song (feat. Guest)")
    overlay.configure(track: track, isTitle: true) { _, _ in }
    let button = try #require(overlay.buttons.first)
    let count = overlay.measurementCount
    for _ in 0..<20 {
        overlay.configure(track: track, isTitle: true) { _, _ in }
        overlay.rebuild()
    }
    #expect(overlay.measurementCount == count)
    #expect(overlay.buttons.first === button)
    field.frame.size.width = 30
    overlay.rebuild()
    #expect(overlay.buttons.isEmpty)
    #expect(overlay.measurementCount == count + 1)
    field.frame.size.width = 400
    overlay.rebuild()
    #expect(!overlay.buttons.isEmpty)
    field.font = .systemFont(ofSize: 18)
    overlay.rebuild()
    #expect(overlay.measurementCount == count + 3)
    overlay.clear()
}

@Test @MainActor func featuredEmptyTitleNeverMeasuresTextOrKeepsOldTargets() {
    let field = NativeTrackActionField(frame: NSRect(x: 0, y: 0, width: 400, height: 26))
    let overlay = NativeFeaturedArtistOverlay(field: field)
    overlay.configure(track: layoutSong("Plain title"), isTitle: true) { _, _ in }
    for width in [300.0, 200, 400] { field.frame.size.width = width; overlay.rebuild() }
    #expect(overlay.measurementCount == 0)
    overlay.configure(track: layoutSong("Song (feat. Guest)"), isTitle: true) { _, _ in }
    #expect(!overlay.buttons.isEmpty)
    let count = overlay.measurementCount
    overlay.configure(track: layoutSong("Plain title"), isTitle: true) { _, _ in }
    #expect(overlay.buttons.isEmpty)
    #expect(overlay.measurementCount == count)
    overlay.clear()
    overlay.rebuild()
    #expect(overlay.measurementCount == count)
}

@Test @MainActor func featuredRebindUpdatesDestinationWithoutStaleGeometry() async throws {
    let field = NativeTrackActionField(frame: NSRect(x: 0, y: 0, width: 400, height: 26))
    let overlay = NativeFeaturedArtistOverlay(field: field)
    let track = layoutSong("Song")
    var oldCalls = 0
    var destination: String?
    overlay.configure(track: track, isTitle: false) { _, _ in oldCalls += 1 }
    let button = try #require(overlay.buttons.first)
    let count = overlay.measurementCount
    overlay.configure(track: track, isTitle: false) { id, _ in destination = id }
    #expect(overlay.buttons.first === button)
    #expect(overlay.measurementCount == count)
    button.activate?()
    await overlay.clickTask?.value
    #expect(oldCalls == 0)
    #expect(destination == "guest")
    overlay.configure(track: layoutSong("Song", artist: "Other"), isTitle: false) { _, _ in }
    #expect(field.stringValue == "Other")
    #expect(overlay.measurementCount == count + 1)
    overlay.clear()
}

@Test @MainActor func featuredClearRemovesTrackingAndDetachesInactiveOverlay() {
    let field = NativeTrackActionField(frame: NSRect(x: 0, y: 0, width: 400, height: 26))
    field.configureFeatured(track: layoutSong("Song (feat. Guest)"), isTitle: true) { _, _ in }
    let count = field.trackingAreas.count
    for _ in 0..<10 { field.updateTrackingAreas() }
    #expect(field.trackingAreas.count == count)
    field.clearFeatured()
    field.layout()
    #expect(field.subviews.compactMap { $0 as? NativeFeaturedArtistButton }.isEmpty)
    #expect(field.trackingAreas.isEmpty)
}

@Test @MainActor func featuredHiddenPageCancelsPendingNavigationAndDefersMeasurements() async throws {
    let field = NativeTrackActionField(frame: NSRect(x: 0, y: 0, width: 400, height: 26))
    let overlay = NativeFeaturedArtistOverlay(field: field)
    var destination: String?
    overlay.configure(track: layoutSong("Song"), isTitle: false) { id, _ in destination = id }
    let button = try #require(overlay.buttons.first)
    let count = overlay.measurementCount
    button.activate?()
    let pending = overlay.clickTask
    overlay.setVisible(false)
    #expect(button.isHidden)
    await pending?.value
    #expect(destination == nil)
    field.frame.size.width = 500
    overlay.rebuild()
    #expect(overlay.measurementCount == count)
    button.activate?()
    #expect(overlay.clickTask == nil)
    overlay.setVisible(true)
    #expect(!button.isHidden)
    #expect(overlay.measurementCount == count + 1)
    overlay.buttons.first?.activate?()
    await overlay.clickTask?.value
    #expect(destination == "guest")
    overlay.clear()
}

@Test @MainActor func featuredInlineAlbumIsPreservedExactlyOnceOnIdenticalUpdates() {
    let field = NativeTrackActionField(frame: NSRect(x: 0, y: 0, width: 400, height: 26))
    let overlay = NativeFeaturedArtistOverlay(field: field)
    let track = layoutSong("Song")
    for _ in 0..<5 {
        overlay.configure(track: track, isTitle: false, suffix: " • Album") { _, _ in }
        #expect(field.stringValue == "Guest • Album")
    }
    #expect(overlay.measurementCount == 1)
    overlay.configure(track: track, isTitle: false, suffix: "") { _, _ in }
    #expect(field.stringValue == "Guest")
    overlay.clear()
}
