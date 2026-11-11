import AppKit
import SideBCore
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class HomeCollectionRowTests: XCTestCase {
    private func album(_ id: String) -> HomeItemRecord {
        HomeItemRecord(kind: "album", id: id, title: "Album \(id)", subtitle: "Álbum • Artist • 2020", thumbnail: nil, duration: nil,
                       artists: "Artist", artistId: "UC", album: nil, albumId: nil, artistRuns: [], explicit: false)
    }

    private func model(_ records: [HomeItemRecord], session: String = "s", style: HomeAlbumCardStyle = .tinted, trailing: CGFloat = 28,
                       playing: Bool = false, onVisible: @escaping ([String]) -> Void = { _ in }) -> HomeFeaturedNativeRail {
        HomeFeaturedNativeRail(records: records, leadingInset: 28, trailingInset: trailing, albumCardStyle: style, session: session,
            playback: nil, playing: playing, onOpen: { _ in }, onPlay: { _ in }, menu: nil, onVisible: onVisible)
    }

    private func mounted(width: CGFloat = 900, count: Int = 20) -> (HomeFeaturedRailView, [HomeItemRecord]) {
        let records = (0..<count).map { album("a\($0)") }
        let view = HomeFeaturedRailView(frame: NSRect(x: 0, y: 0, width: width,
            height: HomeCollectionCardMetrics.railHeight(cardWidth: HomeCollectionRowLayout(width: width).cardWidth)))
        view.reducesMotion = { true }
        view.apply(model(records))
        settle(view)
        return (view, records)
    }

    private func settle(_ view: HomeFeaturedRailView) {
        view.layoutSubtreeIfNeeded()
        view.collection.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
    }

    private func scrollNotification(_ view: HomeFeaturedRailView, to x: CGFloat) {
        view.setScrollOffsetForTesting(x)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: view.collection.enclosingScrollView?.contentView)
    }

    private func resize(_ view: HomeFeaturedRailView, width: CGFloat, trailing: CGFloat = 28, records: [HomeItemRecord]) {
        view.frame = NSRect(x: 0, y: 0, width: width,
            height: HomeCollectionCardMetrics.railHeight(cardWidth: HomeCollectionRowLayout(width: width, trailingInset: trailing).cardWidth))
        view.apply(model(records, trailing: trailing))
        settle(view)
    }

    /// Posición horizontal de la tarjeta `index` dentro del carril.
    private func originX(_ view: HomeFeaturedRailView, _ index: Int) throws -> CGFloat {
        // Desde los atributos del layout: no depende de qué celdas se hayan creado ya.
        let attributes = try XCTUnwrap(view.collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: index, section: 0)))
        return view.scrollFrameForTesting.minX + attributes.frame.minX - view.scrollOffsetForTesting
    }

    // MARK: Cantidad y ancho

    func testCardCountAndWidthFollowTheRailWidth() throws {
        for width in [640.0, 900, 1400, 2000] {
            let (view, _) = mounted(width: CGFloat(width))
            let row = HomeCollectionRowLayout(width: CGFloat(width))
            let geometry = view.collectionGeometryForTesting
            XCTAssertEqual(row.cardWidth, HomeCollectionRowLayout.fixedCardWidth, accuracy: 0.001)
            XCTAssertEqual(geometry.itemSize.width, 220, accuracy: 0.001, "\(width)")
            XCTAssertEqual(geometry.itemSize.height, 220 + 121, accuracy: 0.001)
            let useful = CGFloat(width) - 56
            let expectedCount = min(8, max(2, Int(((useful + 24) / 244).rounded(.down))))
            XCTAssertEqual(row.count, expectedCount)
            XCTAssertEqual(geometry.insets.top, 8)
            XCTAssertEqual(geometry.insets.bottom, 48)
            view.stop()
        }
    }

    func testMarginsLiveInsideTheContentAndSideEdgesAreClipped() throws {
        let (view, _) = mounted()
        // Con margen a ambos lados se recortan 5 pt de cada uno; el margen interno es 28 − 5.
        XCTAssertEqual(view.scrollFrameForTesting, NSRect(x: 5, y: 0, width: 890, height: view.bounds.height))
        XCTAssertEqual(view.collectionGeometryForTesting.insets.left, 23)
        XCTAssertEqual(view.collectionGeometryForTesting.insets.right, 23)
        XCTAssertEqual(try originX(view, 0), 28, accuracy: 0.001, "En reposo la primera tarjeta arranca a 28 pt")
        let row = HomeCollectionRowLayout(width: 900)
        XCTAssertEqual(try originX(view, 1), 28 + row.stride, accuracy: 0.001)
        // Con el reproductor lateral abierto no se recorta ni se reserva el lado derecho.
        resize(view, width: 900, trailing: 0, records: (0..<20).map { album("a\($0)") })
        XCTAssertEqual(view.scrollFrameForTesting, NSRect(x: 5, y: 0, width: 895, height: view.bounds.height))
        XCTAssertEqual(view.collectionGeometryForTesting.insets.right, 0)
        view.stop()
    }

    func testCardIIsAtOffsetITimesStride() throws {
        let (view, _) = mounted()
        let stride = HomeCollectionRowLayout(width: 900).stride
        for index in [1, 3, 5] {
            scrollNotification(view, to: CGFloat(index) * stride)
            XCTAssertEqual(try originX(view, index), 28, accuracy: 0.001, "La tarjeta \(index) queda a 28 pt con offset i · paso")
            XCTAssertEqual(view.anchorIndex, index)
        }
        view.stop()
    }

    // MARK: Ancla

    func testAnchorSurvivesResizeAndSidebarToggle() throws {
        let (view, records) = mounted()
        let stride = HomeCollectionRowLayout(width: 900).stride
        scrollNotification(view, to: 4 * stride)
        XCTAssertEqual(view.anchorIndex, 4)
        for width in [1100.0, 700, 1500] {
            resize(view, width: CGFloat(width), records: records)
            let row = HomeCollectionRowLayout(width: CGFloat(width))
            XCTAssertEqual(view.collectionGeometryForTesting.itemSize.width, row.cardWidth, accuracy: 0.001)
            XCTAssertEqual(view.anchorIndex, 4, "\(width)")
            XCTAssertEqual(view.scrollOffsetForTesting, 4 * row.stride, accuracy: 0.5)
            XCTAssertEqual(try originX(view, 4), 28, accuracy: 0.5)
        }
        // Abrir el reproductor lateral cambia el margen derecho y el ancho de tarjeta.
        resize(view, width: 1500, trailing: 0, records: records)
        XCTAssertEqual(view.anchorIndex, 4)
        XCTAssertEqual(view.scrollOffsetForTesting, 4 * HomeCollectionRowLayout(width: 1500, trailingInset: 0).stride, accuracy: 0.5)
        view.stop()
    }

    func testResizeDoesNotReconfigureCellsOrRequestImagesAgain() throws {
        let (view, records) = mounted()
        let configured = view.configuredCount
        let reloads = view.reloadCount
        let before = view.collection.visibleItems().count
        for width in stride(from: 900.0, through: 925, by: 5) { resize(view, width: CGFloat(width), records: records) }
        XCTAssertEqual(view.reloadCount, reloads)
        // Sólo se configuran las celdas que entran a la vista, no las ya visibles en cada cuadro.
        XCTAssertLessThanOrEqual(view.configuredCount - configured, 2 * max(0, view.collection.visibleItems().count - before), "Una celda nueva se configura al crearse y al mostrarse")
        view.stop()
    }

    func testAnchorFollowsTheSameCardByIDWhenTheListChanges() throws {
        let (view, records) = mounted()
        let stride = HomeCollectionRowLayout(width: 900).stride
        scrollNotification(view, to: 3 * stride)
        XCTAssertEqual(view.anchorIndex, 3)
        // Entran dos tarjetas al inicio: a3 pasa a ser la 5.
        let inserted = [album("n1"), album("n2")] + records
        view.apply(model(inserted))
        settle(view)
        XCTAssertEqual(view.anchorIndex, 5)
        XCTAssertEqual(view.scrollOffsetForTesting, 5 * stride, accuracy: 0.5)
        // Si la tarjeta ancla desaparece, vuelve al inicio (como `alignCollectionAnchor`).
        view.apply(model(inserted.filter { $0.id != "a3" }))
        settle(view)
        XCTAssertEqual(view.anchorIndex, 0)
        XCTAssertEqual(view.scrollOffsetForTesting, 0, accuracy: 0.5)
        // Otra sesión: arriba del todo.
        scrollNotification(view, to: 2 * stride)
        view.apply(model(records, session: "otra"))
        settle(view)
        XCTAssertEqual(view.anchorIndex, 0)
        XCTAssertEqual(view.scrollOffsetForTesting, 0, accuracy: 0.5)
        view.stop()
    }

    func testWidthZeroKeepsTheLastRealMeasureAndTheAnchor() throws {
        let (view, records) = mounted()
        let stride = HomeCollectionRowLayout(width: 900).stride
        scrollNotification(view, to: 4 * stride)
        let geometry = view.collectionGeometryForTesting
        view.frame = NSRect(x: 0, y: 0, width: 0, height: view.bounds.height)
        view.layoutSubtreeIfNeeded()
        view.apply(model(records, playing: true), active: false)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.collectionGeometryForTesting.itemSize, geometry.itemSize)
        XCTAssertEqual(view.anchorIndex, 4)
        XCTAssertEqual(view.scrollOffsetForTesting, 4 * stride, accuracy: 0.5)
        // Un reflujo con ancho 0 que mueva el contenido tampoco cuenta como una acción del usuario.
        view.setScrollOffsetForTesting(0)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: view.collection.enclosingScrollView?.contentView)
        XCTAssertEqual(view.anchorIndex, 4)
        view.frame = NSRect(x: 0, y: 0, width: 900, height: view.bounds.height)
        view.apply(model(records), active: true)
        settle(view)
        XCTAssertEqual(view.scrollOffsetForTesting, 4 * stride, accuracy: 0.5)
        XCTAssertEqual(view.anchorIndex, 4)
        view.stop()
    }

    func testHostedWidthZeroIsNeverPublished() {
        let player = PlayerViewModel()
        let feed = HomeFeedTableView(featuredContent: { AnyView(Text("\($0)")) }, featuredHeight: { _ in 100 }, sections: [],
            isObscured: false, revision: 1, selectedChip: nil, hasMore: false, isLoadingMore: false, currentTrackID: nil,
            isPlaying: false, player: player, router: nil, onNavigate: { _ in }, onLoadMore: {})
        let coordinator = feed.makeCoordinator()
        coordinator.publishFeaturedWidth(1000)
        XCTAssertEqual(coordinator.featuredViewport.width, 1000)
        for bad in [0, -1, -300] as [CGFloat] {
            coordinator.publishFeaturedWidth(bad)
            XCTAssertEqual(coordinator.featuredViewport.width, 1000, "No se publica \(bad)")
        }
        coordinator.publishFeaturedWidth(1200)
        XCTAssertEqual(coordinator.featuredViewport.width, 1200)
    }

    // MARK: Encaje

    func testSnapSettlesAtTheStartOfTheNearestCardWhenCloseAndLeavesItOtherwise() throws {
        let (view, _) = mounted()
        let stride = HomeCollectionRowLayout(width: 900).stride
        scrollNotification(view, to: 2 * stride + 0.2 * stride)
        view.finishLiveScrollForTesting()
        XCTAssertEqual(view.scrollOffsetForTesting, 2 * stride, accuracy: 0.01)
        XCTAssertEqual(view.anchorIndex, 2)
        scrollNotification(view, to: 2 * stride - 0.25 * stride)
        view.finishLiveScrollForTesting()
        XCTAssertEqual(view.scrollOffsetForTesting, 2 * stride, accuracy: 0.01)
        // Lejos de un inicio no se pelea con el usuario.
        scrollNotification(view, to: 3 * stride + 0.5 * stride)
        view.finishLiveScrollForTesting()
        XCTAssertEqual(view.scrollOffsetForTesting, 3.5 * stride, accuracy: 0.01)
        view.stop()
    }

    func testSnapTargetIsPureAndClampedToTheContent() {
        XCTAssertEqual(HomeCollectionRowSnap.target(offset: 450, stride: 224, maximum: 3000), 448)
        XCTAssertNil(HomeCollectionRowSnap.target(offset: 448, stride: 224, maximum: 3000), "Ya está en un inicio")
        XCTAssertNil(HomeCollectionRowSnap.target(offset: 112, stride: 224, maximum: 3000))
        XCTAssertNil(HomeCollectionRowSnap.target(offset: 100, stride: 224, maximum: 0))
        XCTAssertNil(HomeCollectionRowSnap.target(offset: 2990, stride: 224, maximum: 3000), "Cerca del final no pasa del contenido")
    }

    func testSnapDoesNothingAfterStop() throws {
        let (view, _) = mounted()
        let stride = HomeCollectionRowLayout(width: 900).stride
        scrollNotification(view, to: stride + 0.2 * stride)
        view.stop()
        view.setScrollOffsetForTesting(stride + 0.2 * stride)
        view.finishLiveScrollForTesting()
        view.beginLiveScrollForTesting()
        XCTAssertEqual(view.scrollOffsetForTesting, 1.2 * stride, accuracy: 0.01)
    }

    // MARK: Flechas

    func testArrowsAdvanceByWholeCardsAndKeepTheirLabels() throws {
        let (view, _) = mounted()
        let row = HomeCollectionRowLayout(width: 900)
        let labels = view.subviews.compactMap { ($0 as? NSButton)?.accessibilityLabel() }
        XCTAssertTrue(labels.contains(L10n.text("home.shelf.previous")))
        XCTAssertTrue(labels.contains(L10n.text("home.shelf.next")))
        XCTAssertTrue(view.arrowStateForTesting.previousHidden)
        XCTAssertFalse(view.arrowStateForTesting.nextHidden)
        view.pressNextForTesting()
        // Como HorizontalNavigation.svelte: `⌊extent / paso⌋` tarjetas enteras (aquí 2 de 3).
        let pages = (844 / row.stride).rounded(.down)
        XCTAssertEqual(view.scrollOffsetForTesting, pages * row.stride, accuracy: 0.01)
        view.pressNextForTesting()
        XCTAssertEqual(view.scrollOffsetForTesting.truncatingRemainder(dividingBy: row.stride), 0, accuracy: 0.01)
        view.pressPreviousForTesting()
        XCTAssertEqual(view.scrollOffsetForTesting, pages * row.stride, accuracy: 0.01)
        XCTAssertFalse(view.subviews.contains { String(describing: type(of: $0)).contains("Fade") }, "Sin fundidos laterales")
        view.stop()
    }

    // MARK: Visibles

    func testVisibleCardsArePublishedAfterTheFirstLayoutEvenWhenEmptyOfScroll() async throws {
        var published: [[String]] = []
        let records = (0..<20).map { album("a\($0)") }
        let view = HomeFeaturedRailView(frame: NSRect(x: 0, y: 0, width: 900, height: HomeCollectionCardMetrics.railHeight(cardWidth: HomeCollectionRowLayout.fixedCardWidth)))
        view.apply(model(records, onVisible: { published.append($0) }))
        settle(view)
        try await Task.sleep(for: .milliseconds(50))
        let first = try XCTUnwrap(published.first)
        XCTAssertEqual(first, (0..<4).map { "album:a\($0)" })
        let stride = HomeCollectionRowLayout(width: 900).stride
        scrollNotification(view, to: 5 * stride)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(published.last, (5..<9).map { "album:a\($0)" })
        view.stop()
    }

    func testTrackerWaitsForTheFirstPublicationAndCancels() async throws {
        let tracker = HomeVisibleCollectionTracker()
        let waiting = Task { @MainActor in await tracker.firstPublication() }
        await Task.yield()
        tracker.publish(["x", "y"])
        let ids = await waiting.value
        XCTAssertEqual(ids, ["x", "y"])
        let later = await tracker.firstPublication()
        XCTAssertEqual(later, ["x", "y"], "Con una publicación previa no espera")
        let fresh = HomeVisibleCollectionTracker()
        let cancelled = Task { @MainActor in await fresh.firstPublication() }
        await Task.yield()
        cancelled.cancel()
        let result = await cancelled.value
        XCTAssertEqual(result, [], "Cancelar libera la espera")
    }

    // MARK: Detalles de toda la fila

    func testWholeRowIsRequestedVisibleFirstWithTwoAtATimeAndScrollingDoesNotRestart() async throws {
        let items = (0..<36).map { album("a\($0)") }
        let visible = ["album:a10", "album:a11", "album:a12"]
        let ordered = HomeCollectionRequestOrder.order(items, visible: visible, id: { "\($0.kind):\($0.id)" })
        XCTAssertEqual(ordered.prefix(3).map(\.id), ["a10", "a11", "a12"])
        XCTAssertEqual(Array(ordered.dropFirst(3).prefix(3)).map(\.id), ["a0", "a1", "a2"])

        actor Recorder {
            var order: [String] = []
            var active = 0, peak = 0
            func start(_ id: String) { order.append(id); active += 1; peak = max(peak, active) }
            func finish() { active -= 1 }
        }
        let recorder = Recorder()
        let model = HomeAlbumMetadataModel(limit: 48)
        await model.load(items: ordered, sessionKey: "s") { id in
            await recorder.start(id)
            try await Task.sleep(for: .milliseconds(5))
            await recorder.finish()
            return AlbumDetailRecord(browseId: id, title: id, artist: "A", artistId: nil, subtitle: nil,
                secondSubtitle: nil, description: nil, thumbnail: nil, playlistId: nil, inLibrary: false, items: [], sections: [])
        }
        let order = await recorder.order
        XCTAssertEqual(order.count, 36, "Se piden los detalles de toda la fila")
        XCTAssertEqual(Set(order.prefix(3)), ["a10", "a11", "a12"], "Las visibles van primero")
        let peak = await recorder.peak
        XCTAssertEqual(peak, 2, "Dos solicitudes simultáneas")
        XCTAssertEqual(model.details.count, 36, "El caché de 48 cubre las 36 colecciones")
    }

    func testMetadataRequestDependsOnTheWholeListNotOnTheVisibleOnes() {
        typealias Request = HomeFeaturedView.MetadataRequest
        let ids = (0..<36).map { "album:a\($0)" }
        let base = Request(session: "s", collectionIDs: ids, kind: .albums, coreIdentity: nil)
        XCTAssertEqual(base, Request(session: "s", collectionIDs: ids, kind: .albums, coreIdentity: nil))
        XCTAssertNotEqual(base, Request(session: "t", collectionIDs: ids, kind: .albums, coreIdentity: nil))
        XCTAssertNotEqual(base, Request(session: "s", collectionIDs: Array(ids.dropLast()), kind: .albums, coreIdentity: nil))
        XCTAssertNotEqual(base, Request(session: "s", collectionIDs: ids, kind: .playlists, coreIdentity: nil))
    }
}
