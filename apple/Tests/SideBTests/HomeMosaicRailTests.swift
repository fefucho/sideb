import AppKit
import SideBCore
import XCTest
@testable import SideB

@MainActor
final class HomeMosaicRailTests: XCTestCase {
    private func record(_ id: String, title: String? = nil, thumbnail: String? = nil) -> HomeItemRecord {
        HomeItemRecord(kind: "song", id: id, title: title ?? "Title \(id)", subtitle: "Artist", thumbnail: thumbnail, duration: nil,
                       artists: "Artist", artistId: "artist", album: nil, albumId: nil, artistRuns: [], explicit: false)
    }

    private func model(_ records: [HomeItemRecord], session: String = "s", playing: Bool = false,
                       trailing: CGFloat = 28, onVisible: @escaping ([String]) -> Void = { _ in }) -> HomeFeaturedNativeRail {
        HomeFeaturedNativeRail(records: records, usesMosaic: true,
            leadingInset: 28, trailingInset: trailing, session: session, playback: nil, playing: playing,
            onOpen: { _ in }, onPlay: { _ in }, menu: nil, onVisible: onVisible)
    }

    private func mounted(width: CGFloat = 900, count: Int = 27) -> (HomeFeaturedRailView, [HomeItemRecord]) {
        let view = HomeFeaturedRailView(frame: NSRect(x: 0, y: 0, width: width, height: 448))
        let records = (0..<count).map { record("song-\($0)") }
        view.apply(model(records))
        view.layoutSubtreeIfNeeded()
        view.collection.layoutSubtreeIfNeeded()
        return (view, records)
    }

    private func solidImage(red: UInt8, green: UInt8, blue: UInt8) -> NSImage {
        NSImage(cgImage: solidCGImage(red: red, green: green, blue: blue), size: NSSize(width: 32, height: 32))
    }

    // MARK: Geometría del carril

    func testCellFramesMatchMosaicMetricsPlusLeadingMargin() throws {
        let (view, records) = mounted()
        let expected = HomeMosaicLayout.make(ids: records.map(\.id))
        XCTAssertEqual(view.mosaicLayoutForTesting, expected)
        XCTAssertEqual(view.mosaicContentSizeForTesting.height, 448)
        XCTAssertEqual(view.mosaicContentSizeForTesting.width,
                       28 + HomeMosaicMetrics.contentWidth(columns: expected.columns) + 28, accuracy: 0.01)
        let visible = view.collection.indexPathsForVisibleItems()
        XCTAssertFalse(visible.isEmpty)
        XCTAssertLessThan(visible.count, records.count, "Sólo se montan las celdas cercanas al área visible")
        for path in visible {
            let cell = try XCTUnwrap(view.collection.item(at: path) as? HomeCollectionItem)
            let frame = HomeMosaicMetrics.frame(of: expected.cells[path.item]).offsetBy(dx: 28, dy: 0)
            XCTAssertEqual(cell.view.frame.origin.x, frame.minX, accuracy: 0.01)
            XCTAssertEqual(cell.view.frame.origin.y, frame.minY, accuracy: 0.01)
            XCTAssertEqual(cell.view.frame.size.width, frame.width, accuracy: 0.01)
            XCTAssertEqual(cell.view.frame.size.height, frame.height, accuracy: 0.01)
            XCTAssertEqual(cell.content.mosaicSize, expected.cells[path.item].size)
        }
        // En reposo la primera celda arranca a 28 pt.
        XCTAssertEqual(view.scrollOffsetForTesting, 0)
        XCTAssertEqual(try XCTUnwrap(view.collection.item(at: IndexPath(item: 0, section: 0))).view.frame.minX, 28, accuracy: 0.01)
        view.stop()
    }

    func testHeightStaysFixedWithFewerThanThreeSongs() {
        for count in 1...3 {
            let (view, _) = mounted(count: count)
            XCTAssertEqual(view.mosaicContentSizeForTesting.height, 448)
            view.stop()
        }
    }

    func testSameIDsDrawTheSameMosaicAndLayoutIsOnlyRecomputedWhenIDsChange() {
        let (view, records) = mounted()
        let first = view.mosaicLayoutForTesting
        var updated = records
        updated[0] = record("song-0", title: "Otro título")
        view.apply(model(updated, playing: true))
        XCTAssertEqual(view.mosaicLayoutForTesting, first)
        view.apply(model(Array(records.reversed())))
        XCTAssertEqual(view.mosaicLayoutForTesting, HomeMosaicLayout.make(ids: records.reversed().map(\.id)))
        view.stop()
    }

    func testMosaicKeepsAccessibleArrowsAndHasNoEdgeFades() {
        let (view, _) = mounted()
        XCTAssertFalse(view.subviews.contains { String(describing: type(of: $0)).contains("Fade") })
        XCTAssertTrue(view.arrowStateForTesting.previousHidden)
        XCTAssertFalse(view.arrowStateForTesting.nextHidden)
        let labels = view.subviews.compactMap { ($0 as? NSButton)?.accessibilityLabel() }
        XCTAssertTrue(labels.contains(L10n.text("home.shelf.previous")))
        XCTAssertTrue(labels.contains(L10n.text("home.shelf.next")))
        view.setScrollOffsetForTesting(200)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: view.collection.enclosingScrollView?.contentView)
        XCTAssertFalse(view.arrowStateForTesting.previousHidden)
        view.stop()
    }

    func testArrowsAdvanceBySnappedColumnsLikeHorizontalNavigation() {
        let (view, _) = mounted(width: 900)
        let maximum = view.mosaicContentSizeForTesting.width - 900
        // extent = 900 - 56 = 844 -> 5 columnas de 152.
        view.pressNextForTesting()
        XCTAssertEqual(view.scrollOffsetForTesting, min(maximum, 5 * 152), accuracy: 0.01)
        view.pressPreviousForTesting()
        XCTAssertEqual(view.scrollOffsetForTesting, 0, accuracy: 0.01)
        view.stop()
    }

    func testPagingPortMatchesHorizontalPageTarget() {
        XCTAssertEqual(HomeRailPaging.target(position: 0, extent: 844, maximum: 3000, direction: 1), 760)
        XCTAssertEqual(HomeRailPaging.target(position: 760, extent: 844, maximum: 3000, direction: -1), 0)
        XCTAssertEqual(HomeRailPaging.target(position: 2900, extent: 844, maximum: 3000, direction: 1), 3000)
        XCTAssertEqual(HomeRailPaging.target(position: 100, extent: 100, maximum: 3000, direction: 1), 200,
                       "Con un viewport menor que el paso avanza el ancho")
    }

    func testCollectionLayoutFiltersByRectAndIgnoresBoundsChanges() {
        let layout = HomeMosaicCollectionLayout()
        let mosaic = HomeMosaicLayout.make(ids: (0..<27).map(String.init))
        layout.update(mosaic: mosaic, leadingInset: 28, trailingInset: 0)
        XCTAssertFalse(layout.shouldInvalidateLayout(forBoundsChange: NSRect(x: 100, y: 0, width: 500, height: 448)))
        let all = layout.layoutAttributesForElements(in: NSRect(x: 0, y: 0, width: 100_000, height: 448))
        XCTAssertEqual(all.count, 27)
        let some = layout.layoutAttributesForElements(in: NSRect(x: 0, y: 0, width: 200, height: 448))
        XCTAssertTrue(some.allSatisfy { $0.frame.intersects(NSRect(x: 0, y: 0, width: 200, height: 448)) })
        XCTAssertLessThan(some.count, 27)
        XCTAssertEqual(layout.collectionViewContentSize.width, 28 + HomeMosaicMetrics.contentWidth(columns: mosaic.columns))
    }

    // MARK: Posición

    func testWidthZeroKeepsLastRealMeasureAndOffset() {
        let (view, records) = mounted()
        view.setScrollOffsetForTesting(300)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: view.collection.enclosingScrollView?.contentView)
        XCTAssertEqual(view.retainedOffset, 300, accuracy: 0.01)
        view.frame = NSRect(x: 0, y: 0, width: 0, height: 448)
        view.layoutSubtreeIfNeeded()
        view.apply(model(records, playing: true), active: false)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.retainedOffset, 300, accuracy: 0.01)
        XCTAssertEqual(view.scrollOffsetForTesting, 300, accuracy: 0.01)
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 448)
        view.apply(model(records), active: true)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.scrollOffsetForTesting, 300, accuracy: 0.01)
        view.stop()
    }

    func testRestoresOffsetWhenAppKitMovedItDuringZeroWidth() {
        let (view, records) = mounted()
        view.setScrollOffsetForTesting(300)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: view.collection.enclosingScrollView?.contentView)
        view.frame = NSRect(x: 0, y: 0, width: 0, height: 448)
        view.layoutSubtreeIfNeeded()
        // Simula que un ancho 0 desplazó el contenido sin que fuera una acción del usuario.
        view.setScrollOffsetForTesting(0)
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 448)
        view.apply(model(records))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.scrollOffsetForTesting, 300, accuracy: 0.01)
        view.stop()
    }

    func testNewListReturnsToStartSameListKeepsPositionNewSessionResets() {
        let (view, records) = mounted()
        view.setScrollOffsetForTesting(400)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: view.collection.enclosingScrollView?.contentView)
        var sameIDs = records
        sameIDs[3] = record("song-3", title: "Renombrada")
        view.apply(model(sameIDs, playing: true))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.scrollOffsetForTesting, 400, accuracy: 0.01, "Misma lista: conserva la posición")
        view.apply(model(Array(records.dropLast())))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.scrollOffsetForTesting, 0, accuracy: 0.01, "Lista distinta: vuelve al inicio")
        view.setScrollOffsetForTesting(400)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: view.collection.enclosingScrollView?.contentView)
        view.apply(model(Array(records.dropLast()), session: "otra"))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.scrollOffsetForTesting, 0, accuracy: 0.01, "Sesión nueva: vuelve al inicio")
        XCTAssertEqual(view.retainedOffset, 0, accuracy: 0.01)
        view.stop()
    }

    func testTrailingInsetChangeKeepsPosition() {
        let (view, records) = mounted()
        view.setScrollOffsetForTesting(300)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: view.collection.enclosingScrollView?.contentView)
        let wide = view.mosaicContentSizeForTesting.width
        view.apply(model(records, trailing: 0))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.mosaicContentSizeForTesting.width, wide - 28, accuracy: 0.01)
        XCTAssertEqual(view.scrollOffsetForTesting, 300, accuracy: 0.01)
        view.stop()
    }

    // MARK: Desmontaje

    func testDeferredWorkDoesNotActAfterStop() async throws {
        // Carril de colecciones: la publicación diferida de visibles no debe llegar tras stop().
        var published: [[String]] = []
        let rail = HomeFeaturedRailView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let albums = (0..<6).map { index -> HomeItemRecord in var item = record("a\(index)"); item.kind = "album"; return item }
        rail.apply(HomeFeaturedNativeRail(records: albums, leadingInset: 28, trailingInset: 28, session: "x", playback: nil,
            playing: false, onOpen: { _ in }, onPlay: { _ in }, menu: nil, onVisible: { published.append($0) }))
        rail.layoutSubtreeIfNeeded()
        rail.stop()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(published.isEmpty)
        XCTAssertTrue(rail.isStopped)

        // Mosaico: notificaciones de scroll y apply tardíos no cambian nada.
        let (view, records) = mounted()
        view.setScrollOffsetForTesting(200)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: view.collection.enclosingScrollView?.contentView)
        let retained = view.retainedOffset
        let updates = view.visibilityUpdateCount
        let reloads = view.reloadCount
        view.stop()
        view.setScrollOffsetForTesting(0)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: view.collection.enclosingScrollView?.contentView)
        view.apply(model(Array(records.dropLast())))
        view.layoutSubtreeIfNeeded()
        view.pressNextForTesting()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(view.retainedOffset, retained)
        XCTAssertEqual(view.visibilityUpdateCount, updates)
        XCTAssertEqual(view.reloadCount, reloads)
        XCTAssertEqual(view.scrollOffsetForTesting, 0)
    }

    func testSuspendedCellsAreReleasedWhenPageIsInactive() throws {
        let (view, records) = mounted()
        let path = try XCTUnwrap(view.collection.indexPathsForVisibleItems().first)
        let cell = try XCTUnwrap(view.collection.item(at: path) as? HomeCollectionItem)
        view.apply(model(records), active: false)
        XCTAssertNil(cell.content.currentMenuForTesting())
        view.stop()
    }

    // MARK: Celda

    private func songCell(_ size: HomeMosaicSize, id: String = "a", thumbnail: String? = nil,
                          context: QueueContext? = nil, playing: Bool = false) -> HomeItemView {
        let frame: NSRect = switch size {
        case .small: NSRect(x: 0, y: 0, width: 144, height: 144)
        case .wide: NSRect(x: 0, y: 0, width: 296, height: 144)
        case .large: NSRect(x: 0, y: 0, width: 296, height: 296)
        }
        let cell = HomeItemView(frame: frame)
        cell.featuredSong = true
        cell.mosaicSize = size
        cell.coverColorStore = HomeCoverColorStore()
        cell.coverSession = "session"
        cell.configure(record: record(id, thumbnail: thumbnail), style: .largeCard, currentTrackID: nil, isPlaying: playing,
                       queueContext: context, onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil })
        cell.applyFeaturedLayout(song: true, mosaicSize: size)
        cell.layoutSubtreeIfNeeded()
        return cell
    }

    func testTypographyAndPlayMetricsFollowMosaicSize() throws {
        let expected: [(HomeMosaicSize, CGFloat, NSFont.Weight, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            // tamaño, título, peso, artista, línea título, línea artista, margen, base, Play
            (.small, 13, .semibold, 11.5, 16, 15, 10, 9, 30),
            (.wide, 16, .bold, 12.5, 20, 16, 12, 11, 32),
            (.large, 22, .bold, 14, 27, 19, 16, 14, 40)
        ]
        for (size, titleSize, weight, artistSize, titleLine, artistLine, inset, bottom, play) in expected {
            let cell = songCell(size)
            let height = cell.bounds.height
            let titleFont = try XCTUnwrap(cell.featuredTitleFontForTesting)
            XCTAssertEqual(titleFont.pointSize, titleSize, "\(size)")
            let traits = titleFont.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
            XCTAssertEqual((traits?[.weight] as? CGFloat) ?? 0, NSFont.systemFont(ofSize: titleSize, weight: weight).fontDescriptor.object(forKey: .traits).flatMap { ($0 as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat } ?? 0, accuracy: 0.001, "\(size)")
            XCTAssertEqual(try XCTUnwrap(cell.featuredArtistFontForTesting).pointSize, artistSize, "\(size)")
            XCTAssertEqual(cell.featuredTitleFrameForTesting.height, titleLine, "\(size)")
            XCTAssertEqual(cell.featuredArtistFrameForTesting.height, artistLine, "\(size)")
            XCTAssertEqual(cell.featuredTitleFrameForTesting.minX, inset, "\(size)")
            XCTAssertEqual(cell.featuredArtistFrameForTesting.maxY, height - bottom, "\(size)")
            XCTAssertEqual(cell.featuredTitleFrameForTesting.maxY, cell.featuredArtistFrameForTesting.minY, "\(size)")
            XCTAssertEqual(cell.featuredPlayFrameForTesting.width, play, "\(size)")
            XCTAssertEqual(cell.bounds.width - cell.featuredPlayFrameForTesting.maxX, HomeMosaicCellStyle.make(size).playGap, "\(size)")
            XCTAssertEqual(cell.layer?.cornerRadius, 10)
            XCTAssertEqual(cell.featuredGradientFrameForTesting.height, height * (size == .large ? 0.52 : 0.72), accuracy: 0.01)
            XCTAssertTrue(cell.featuredTitleMaskedForTesting, "El título largo se desvanece, no usa elipsis")
        }
        XCTAssertEqual(HomeMosaicCellStyle.make(.large).titleTracking, -0.2)
        XCTAssertEqual(HomeMosaicCellStyle.make(.small).barsShift, 17.5)
        XCTAssertEqual(HomeMosaicCellStyle.make(.wide).barsShift, 19)
        XCTAssertEqual(HomeMosaicCellStyle.make(.large).barsShift, 21.5)
    }

    func testPlayAppearsOnHoverExceptLargeAndReservesTextSpace() {
        for size in [HomeMosaicSize.small, .wide, .large] {
            let cell = songCell(size)
            let reserve = HomeMosaicCellStyle.make(size).playReserve
            let rest = cell.featuredTitleFrameForTesting.width
            XCTAssertEqual(cell.featuredPlayVisibleForTesting, size == .large, "\(size)")
            cell.setHovered(true)
            cell.layoutSubtreeIfNeeded()
            XCTAssertTrue(cell.featuredPlayVisibleForTesting)
            let hovered = cell.featuredTitleFrameForTesting.width
            XCTAssertEqual(rest - hovered, size == .large ? 0 : reserve, accuracy: 0.01, "\(size)")
            XCTAssertEqual(cell.bounds.width - 2 * HomeMosaicCellStyle.make(size).inset - hovered, reserve, accuracy: 0.01, "\(size)")
            cell.setHovered(false)
            cell.layoutSubtreeIfNeeded()
            XCTAssertEqual(cell.featuredPlayVisibleForTesting, size == .large, "\(size)")
        }
    }

    func testInlineEqualizerIsNotSuppressedByHoverAndShiftsTitle() {
        for size in [HomeMosaicSize.small, .wide, .large] {
            let context = QueueContext.radio(seedVideoId: "a", title: "Radio", seedName: "Seed")
            let cell = songCell(size, context: context, playing: true)
            let metrics = HomeMosaicCellStyle.make(size)
            XCTAssertFalse(cell.equalizerOverlay.isHidden, "\(size)")
            XCTAssertTrue(cell.equalizerOverlay.isInlineForTesting)
            XCTAssertEqual(cell.equalizerOverlay.barCountForTesting, 3)
            XCTAssertEqual(cell.featuredTitleFrameForTesting.minX, metrics.inset + metrics.barsShift, accuracy: 0.01)
            XCTAssertEqual(cell.featuredEqualizerFrameForTesting.minX, metrics.inset, accuracy: 0.01)
            XCTAssertEqual(cell.featuredEqualizerFrameForTesting.width, metrics.barsWidth, accuracy: 0.01)
            XCTAssertEqual(cell.featuredEqualizerFrameForTesting.height, metrics.barHeight, accuracy: 0.01)
            cell.setHovered(true)
            cell.layoutSubtreeIfNeeded()
            XCTAssertFalse(cell.equalizerOverlay.isHidden, "El ecualizador en línea no se oculta con hover: \(size)")
            cell.updatePlayback(currentTrackID: nil, isPlaying: false, queueContext: context)
            XCTAssertFalse(cell.equalizerOverlay.isHidden, "En pausa se mantiene")
            XCTAssertTrue(cell.equalizerOverlay.barOpacitiesForTesting.allSatisfy { abs($0 - 0.5) < 0.001 }, "Pausa: barras al 50 %")
            cell.setFeedVisible(false)
            XCTAssertTrue(cell.equalizerOverlay.isHidden, "Fuera de pantalla respeta la suspensión")
        }
    }

    func testReduceMotionDisablesCoverZoom() {
        let cell = songCell(.small)
        cell.reducesMotion = { false }
        XCTAssertEqual(cell.featuredArtworkScaleForTesting, 1)
        cell.setHovered(true)
        XCTAssertEqual(cell.featuredArtworkScaleForTesting, 1.04, accuracy: 0.0001)
        XCTAssertNotNil(cell.layer, "El marco no cambia")
        XCTAssertEqual(cell.bounds.size, NSSize(width: 144, height: 144))
        cell.setHovered(false)
        XCTAssertEqual(cell.featuredArtworkScaleForTesting, 1)

        let still = songCell(.small)
        still.reducesMotion = { true }
        still.setHovered(true)
        XCTAssertEqual(still.featuredArtworkScaleForTesting, 1, "Con Reduce Motion no hay zoom")
    }

    // MARK: Regresiones de la etapa 2

    func testScrimIsPinnedToTheBottomEdgeOfTheCell() {
        // El eje Y de las subcapas de una vista volteada crece hacia abajo: el degradado termina en el borde inferior.
        for size in [HomeMosaicSize.small, .wide, .large] {
            let cell = songCell(size)
            let frame = cell.featuredGradientFrameForTesting
            XCTAssertEqual(frame.maxY, cell.bounds.height, accuracy: 0.01, "\(size)")
            XCTAssertEqual(frame.minX, 0)
            XCTAssertEqual(frame.width, cell.bounds.width, accuracy: 0.01)
            XCTAssertGreaterThan(frame.minY, 0, "No cubre toda la celda: arranca más abajo del borde superior")
        }
    }

    func testPlayIconSitsAboveTheWhiteCircleOnlyInTheMosaic() {
        for size in [HomeMosaicSize.small, .wide, .large] {
            XCTAssertTrue(songCell(size).playSymbolIsAboveCircleForTesting, "\(size)")
        }
        let plain = HomeItemView(frame: NSRect(x: 0, y: 0, width: 160, height: 254))
        plain.configure(record: record("p"), style: .largeCard, currentTrackID: nil, isPlaying: false,
                        onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil })
        plain.layoutSubtreeIfNeeded()
        XCTAssertFalse(plain.playSymbolIsAboveCircleForTesting, "En una celda no destacada el icono sigue debajo")
    }

    // MARK: Color de la carátula

    func testCachedCoverColorPaintsImmediatelyAndMissingUsesFallback() async throws {
        let store = HomeCoverColorStore()
        let cached = await store.color(url: "https://fixture.invalid/cached", session: "session",
                                       image: { solidCGImage(red: 200, green: 60, blue: 40) })
        let expected = try XCTUnwrap(cached)
        let cell = HomeItemView(frame: NSRect(x: 0, y: 0, width: 144, height: 144))
        cell.featuredSong = true
        cell.coverColorStore = store
        cell.coverSession = "session"
        cell.configure(record: record("a", thumbnail: "https://fixture.invalid/cached"), style: .largeCard, currentTrackID: nil,
                       isPlaying: false, onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil })
        XCTAssertEqual(cell.featuredScrimCoverForTesting, expected, "Con caché se pinta al configurar, sin esperar")
        cell.prepareForReuse()
        XCTAssertNil(cell.featuredScrimCoverForTesting)
        cell.configure(record: record("b", thumbnail: "https://fixture.invalid/missing"), style: .largeCard, currentTrackID: nil,
                       isPlaying: false, onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil })
        XCTAssertNil(cell.featuredScrimCoverForTesting, "Sin color se usa el de reserva")
        cell.layoutSubtreeIfNeeded()
        let alphas = cell.featuredGradientAlphasForTesting
        XCTAssertEqual(alphas.map { Double($0) }, HomeCoverScrim.stops.map(\.alpha).map { $0 }, accuracy: 0.001)
    }

    func testRecycledCellNeverPaintsThePreviousCoverColor() async throws {
        let store = HomeCoverColorStore()
        let red = solidImage(red: 210, green: 50, blue: 40), green = solidImage(red: 40, green: 190, blue: 60)
        // El color de A queda pendiente (lento) en la caché compartida; la celda se une a esa carga.
        let slow = Task { @MainActor in
            await store.color(url: "https://fixture.invalid/a", session: "session",
                              image: { try? await Task.sleep(for: .milliseconds(150)); return solidCGImage(red: 210, green: 50, blue: 40) })
        }
        await Task.yield()
        let cell = HomeItemView(frame: NSRect(x: 0, y: 0, width: 144, height: 144))
        cell.featuredSong = true
        cell.coverColorStore = store
        cell.coverSession = "session"
        cell.artworkLoader = { url, _ in url.lastPathComponent == "a" ? red : green }
        func bind(_ id: String) {
            cell.configure(record: record(id, thumbnail: "https://fixture.invalid/\(id)"), style: .largeCard, currentTrackID: nil,
                           isPlaying: false, onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil })
        }
        bind("a")
        try await Task.sleep(for: .milliseconds(30))
        cell.prepareForReuse()
        bind("b")
        try await Task.sleep(for: .milliseconds(300))
        let slowColor = await slow.value
        XCTAssertNotNil(slowColor)
        let shown = try XCTUnwrap(cell.featuredScrimCoverForTesting)
        XCTAssertGreaterThan(shown.green, shown.red, "Debe verse el color de B (verde), no el de A (rojo)")
        cell.prepareForReuse()
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}

private func solidCGImage(red: UInt8, green: UInt8, blue: UInt8) -> CGImage {
    let side = 32
    var pixels = [UInt8]()
    for _ in 0..<(side * side) { pixels += [red, green, blue, 255] }
    return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}
