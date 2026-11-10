import AppKit
import XCTest
import SideBCore
@testable import SideB

@MainActor
final class HomeFeaturedNativeTests: XCTestCase {
    private func record(_ id: String) -> HomeItemRecord {
        HomeItemRecord(kind: "song", id: id, title: "Title \(id)", subtitle: "Artist", thumbnail: nil, duration: nil, artists: "Artist", artistId: "artist", album: nil, albumId: nil, artistRuns: [], explicit: false)
    }
    func testLoadedImagesStayInsideContractAndRenderReviewPNG() throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 480))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        for (index, size) in [NSSize(width: 600, height: 600), NSSize(width: 1200, height: 600), NSSize(width: 600, height: 1200)].enumerated() {
            let cell = HomeItemView(frame: NSRect(x: 14 + index * 214, y: 340, width: 202, height: 126))
            cell.featuredSong = true
            cell.configure(record: record("\(index)"), style: .largeCard, currentTrackID: nil, isPlaying: false, onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil })
            cell.applyFeaturedLayout(song: true)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSColor.systemPurple.setFill(); NSRect(origin: .zero, size: size).fill()
            NSColor.systemOrange.setFill(); NSRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2).fill()
            NSGraphicsContext.restoreGraphicsState()
            let image = NSImage(cgImage: bitmap.cgImage!, size: size)
            root.addSubview(cell)
            cell.layoutSubtreeIfNeeded()
            cell.setArtwork(image)
            XCTAssertEqual(cell.featuredArtworkSizeForTesting, size)
            XCTAssertEqual(cell.bounds.height, 126)
            XCTAssertTrue(cell.layer!.masksToBounds)
            for view in cell.subviews where !view.isHidden { XCTAssertTrue(cell.bounds.contains(view.frame), "\(type(of: view)) \(view.frame)") }
        }
        for index in 0..<3 {
            let cell = HomeItemView(frame: NSRect(x: 14 + index * 214, y: 10, width: 180, height: 300))
            var item = record("album-\(index)"); item.kind = "album"
            cell.featuredCollection = true
            cell.configure(record: item, style: .largeCard, currentTrackID: nil, isPlaying: false, onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil })
            cell.applyFeaturedLayout(song: false, summary: "2026 · 12 canciones\n42 min")
            root.addSubview(cell)
            cell.layoutSubtreeIfNeeded()
            cell.setArtwork(NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in NSColor.systemTeal.setFill(); rect.fill(); return true })
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1320, pixelsHigh: 960, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = root.bounds.size
        root.cacheDisplay(in: root.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/sideb-home-native-review.png"))
    }
    func testReuseRejectsLateImageAndKeepsCurrentActionsAndMenu() async throws {
        let cell = HomeItemView(frame: NSRect(x: 0, y: 0, width: 202, height: 126))
        cell.featuredSong = true
        cell.artworkLoader = { url, _ in
            try? await Task.sleep(for: .milliseconds(url.lastPathComponent == "old" ? 60 : 5))
            let side = url.lastPathComponent == "old" ? 600 : 30
            return NSImage(cgImage: CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: CGDataProvider(data: Data(repeating: 255, count: side * side * 4) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!, size: NSSize(width: side, height: side))
        }
        var actions: [String] = []
        func bind(_ id: String) {
            var item = record(id); item.thumbnail = "https://fixture.invalid/" + id
            cell.configure(record: item, style: .largeCard, currentTrackID: nil, isPlaying: false,
                onCard: { actions.append(id) }, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { NSMenu(title: id) })
            cell.applyFeaturedLayout(song: true)
        }
        bind("old")
        await Task.yield()
        cell.prepareForReuse()
        bind("current")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(cell.featuredArtworkSizeForTesting, CGSize(width: 30, height: 30))
        XCTAssertEqual(cell.currentMenuForTesting()?.title, "current")
        cell.cardButton.performClick(nil)
        XCTAssertEqual(actions, ["current"])
        XCTAssertEqual(cell.artworkRequestCount, 2)
        print("Reuse fixture: image loader requests=\(cell.artworkRequestCount), stale image rejected")
    }
    func testImageCacheSharesConcurrentDownsampleAndMemoryResult() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cover.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        let cache = ImageCache(diskCacheURL: directory.appendingPathComponent("cache"))
        let size = CGSize(width: 202, height: 126)
        async let first = cache.image(for: url, targetSize: size)
        async let second = cache.image(for: url, targetSize: size)
        let (a, b) = await (first, second)
        let image = try XCTUnwrap(a)
        XCTAssertTrue(image === b)
        XCTAssertTrue(image === cache.imageFromMemoryCache(for: url, targetSize: size))
        XCTAssertEqual(image.size.width, 404)
        XCTAssertEqual(image.size.height, 202)
        print("ImageCache fixture: 2 concurrent logical requests share 1 downsample; 0 network requests (local PNG)")
    }
    func testRailIgnoresUnrelatedScrollAndRestoresSuspendedCells() throws {
        let view = HomeFeaturedRailView(frame: NSRect(x: 0, y: 0, width: 650, height: 402))
        let model = HomeFeaturedNativeRail(records: (0..<27).map { record("\($0)") }, rows: 3,
            itemWidth: 202, itemHeight: 126, session: "a", playback: nil, playing: false,
            onOpen: { _ in }, onPlay: { _ in }, menu: { NSMenu(title: $0.id) })
        view.apply(model)
        view.layoutSubtreeIfNeeded()
        view.collection.layoutSubtreeIfNeeded()
        let count = view.visibilityUpdateCount
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: NSClipView())
        XCTAssertEqual(view.visibilityUpdateCount, count)
        let path = try XCTUnwrap(view.collection.indexPathsForVisibleItems().first)
        let cell = try XCTUnwrap(view.collection.item(at: path) as? HomeCollectionItem)
        view.apply(model, active: false)
        XCTAssertNil(cell.content.currentMenuForTesting())
        view.apply(model, active: true)
        XCTAssertEqual(cell.content.currentMenuForTesting()?.title, model.records[path.item].id)
        view.collectionView(view.collection, didEndDisplaying: cell, forRepresentedObjectAt: path)
        XCTAssertNil(cell.content.currentMenuForTesting())
        view.collectionView(view.collection, willDisplay: cell, forRepresentedObjectAt: path)
        XCTAssertEqual(cell.content.currentMenuForTesting()?.title, model.records[path.item].id)
        view.stop()
    }

    func testNativeRailsRenderLoadedLocalImages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 600,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemTeal.setFill(); NSRect(x: 0, y: 0, width: 600, height: 600).fill()
        NSColor.systemOrange.setFill(); NSRect(x: 100, y: 100, width: 300, height: 300).fill()
        NSGraphicsContext.restoreGraphicsState()
        let fallback = directory.appendingPathComponent("fixture.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: fallback)
        let covers = ProcessInfo.processInfo.environment["SIDEB_HOME_REVIEW_COVERS"].map { URL(fileURLWithPath: $0) }
        let names = ["Bocanada", "Demon Days", "Random Access Memories", "After Hours", "AM"]
        let artists = ["Gustavo Cerati", "Gorillaz", "Daft Punk", "The Weeknd", "Arctic Monkeys"]
        let files = [5, 1, 2, 4, 3]
        let records = (0..<27).map { index -> HomeItemRecord in
            var item = record("\(index)")
            item.title = names[index % names.count]
            item.artists = artists[index % artists.count]
            let candidate = covers?.appendingPathComponent("\(files[index % files.count]).jpg")
            item.thumbnail = (candidate.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? fallback).absoluteString
            return item
        }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 704, height: 770))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let songs = HomeFeaturedRailView(frame: NSRect(x: 16, y: 352, width: 672, height: 402))
        let albums = HomeFeaturedRailView(frame: NSRect(x: 16, y: 16, width: 672, height: 300))
        root.addSubview(songs); root.addSubview(albums)
        songs.apply(HomeFeaturedNativeRail(records: records, rows: 3, itemWidth: 196, itemHeight: 126,
            session: "render", playback: nil, playing: false, onOpen: { _ in }, onPlay: { _ in }, menu: nil))
        let albumRecords = records.prefix(5).map { item in var copy = item; copy.kind = "album"; return copy }
        albums.apply(HomeFeaturedNativeRail(records: albumRecords, rows: 1, itemWidth: 180, itemHeight: 300,
            session: "render", playback: nil, playing: false, summary: { _ in "2016 · 17 canciones\n1 h 2 min" },
            onOpen: { _ in }, onPlay: { _ in }, menu: nil))
        root.layoutSubtreeIfNeeded()
        for _ in 0..<150 {
            let cells = (songs.collection.visibleItems() + albums.collection.visibleItems()).compactMap { $0 as? HomeCollectionItem }
            if !cells.isEmpty && cells.allSatisfy({ $0.content.featuredArtworkSizeForTesting != nil }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let cells = (songs.collection.visibleItems() + albums.collection.visibleItems()).compactMap { $0 as? HomeCollectionItem }
        XCTAssertFalse(cells.isEmpty)
        XCTAssertTrue(cells.allSatisfy { $0.content.featuredArtworkSizeForTesting != nil })
        // Allow the asynchronous palette work to settle before capturing the footer.
        try await Task.sleep(for: .milliseconds(100))
        root.layoutSubtreeIfNeeded()
        let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1408, pixelsHigh: 1540,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        output.size = root.bounds.size
        root.cacheDisplay(in: root.bounds, to: output)
        try XCTUnwrap(output.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/sideb-home-native-rail-review.png"))
        songs.stop(); albums.stop()
    }

    func testNativeCollectionBoundsAndPlaybackDoesNotReload() {
        let view = HomeFeaturedRailView(frame: NSRect(x: 0, y: 0, width: 650, height: 402))
        var model = HomeFeaturedNativeRail(records: (0..<270).map { record("\($0)") }, rows: 3, itemWidth: 202, itemHeight: 126, session: "a", playback: nil, playing: false, onOpen: { _ in }, onPlay: { _ in }, menu: nil)
        view.apply(model)
        view.layoutSubtreeIfNeeded()
        view.collection.layoutSubtreeIfNeeded()
        let reloads = view.reloadCount
        model.playing = true
        view.apply(model)
        XCTAssertEqual(view.reloadCount, reloads)
        XCTAssertLessThan(view.collection.visibleItems().count, 30)
        XCTAssertGreaterThan(view.collection.visibleItems().count, 0)
        print("Native fixture: visible cells=\(view.collection.visibleItems().count), configured=\(view.configuredCount), reloads=\(view.reloadCount), image requests=0 (nil URLs)")
        view.stop()
    }
}
