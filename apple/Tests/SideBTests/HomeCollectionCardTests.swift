import AppKit
import SideBCore
import XCTest
@testable import SideB

/// Eje Y hacia abajo, como el del contenedor real de las celdas (`NSCollectionView`).
private final class FlippedRoot: NSView { override var isFlipped: Bool { true } }

@MainActor
final class HomeCollectionCardTests: XCTestCase {
    // MARK: Fixtures

    private func album(_ id: String = "al1", title: String = "Bocanada", subtitle: String? = "Álbum • Gustavo Cerati • 1999",
                       artists: String? = "Gustavo Cerati", artistId: String? = "UC1", thumbnail: String? = nil,
                       kind: String = "album") -> HomeItemRecord {
        HomeItemRecord(kind: kind, id: id, title: title, subtitle: subtitle, thumbnail: thumbnail, duration: nil,
                       artists: artists, artistId: artistId, album: nil, albumId: nil, artistRuns: [], explicit: false)
    }

    private func cgImage(top: NSColor, bottom: NSColor, side: Int = 64) -> CGImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        // El origen de NSGraphicsContext sobre un bitmap está abajo: `bottom` queda abajo en la imagen.
        bottom.setFill(); NSRect(x: 0, y: 0, width: side, height: side / 2).fill()
        top.setFill(); NSRect(x: 0, y: side / 2, width: side, height: side / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage!
    }

    private func cell(width: CGFloat = 200, style: HomeAlbumCardStyle = .tinted, record: HomeItemRecord? = nil,
                      summary: String = "Álbum • 1999 • 12 canciones • 52 min", parent: NSView? = FlippedRoot(),
                      loaded: CGImage? = nil) -> HomeItemView {
        let cell = HomeItemView(frame: NSRect(x: 0, y: 0, width: width, height: width + 121))
        parent?.addSubview(cell)
        cell.featuredCollection = true
        cell.albumCardStyle = style
        cell.coverWashStore = HomeCoverWashStore()
        cell.coverColorStore = HomeCoverColorStore()
        cell.coverSession = "session"
        cell.artworkLoader = { _, _ in loaded.map { NSImage(cgImage: $0, size: NSSize(width: 64, height: 64)) } }
        cell.reducesMotion = { true }
        cell.reducesTransparency = { false }
        cell.configure(record: record ?? album(), style: .largeCard, currentTrackID: nil, isPlaying: false,
                       onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil })
        cell.applyFeaturedLayout(song: false, summary: summary)
        cell.layoutSubtreeIfNeeded()
        return cell
    }

    // MARK: Panel

    func testPanelFramesFollowTheSpecAndTheCardIs121PointsTallerThanWide() {
        for width in [190.0, 224.0, 320.0] {
            let cell = cell(width: CGFloat(width))
            let w = CGFloat(width)
            XCTAssertEqual(HomeCollectionCardMetrics.panelHeight, 121)
            XCTAssertEqual(HomeCollectionCardMetrics.cardHeight(cardWidth: w), w + 121)
            // La portada se alarga un radio (14) bajo el panel para que la unión quede recta; la imagen sigue cuadrada.
            XCTAssertEqual(cell.collectionCoverFrameForTesting, NSRect(x: 0, y: 0, width: w, height: w + 14))
            XCTAssertEqual(cell.collectionArtworkFrameForTesting, CGRect(x: 0, y: 0, width: w, height: w))
            // El fondo del panel se alarga un radio hacia arriba (y negativo en la vista volteada) y el panel lo recorta recto:
            // sólo quedan redondas las esquinas de abajo.
            XCTAssertEqual(cell.collectionPanelSurfaceFrameForTesting, CGRect(x: 0, y: -14, width: w, height: 121 + 14))
            XCTAssertEqual(cell.collectionPanelFrameForTesting, NSRect(x: 0, y: w, width: w, height: 121))
            // Padding 12 arriba y 14 a los lados; etiqueta 14, 2 de margen, título 22, artista 19, 6 y resumen 32.
            XCTAssertEqual(cell.collectionBadgeFrameForTesting, NSRect(x: 14, y: w + 12, width: w - 28, height: 14))
            XCTAssertEqual(cell.collectionTitleFrameForTesting, NSRect(x: 14, y: w + 12 + 14 + 2, width: w - 28, height: 22))
            XCTAssertEqual(cell.collectionArtistLabelFrameForTesting, NSRect(x: 14, y: w + 50, width: w - 28, height: 19))
            XCTAssertEqual(cell.collectionSummaryFrameForTesting, NSRect(x: 14, y: w + 75, width: w - 28, height: 32))
            XCTAssertEqual(cell.collectionSummaryFrameForTesting.maxY + 14, w + 121, "14 de padding inferior")
            XCTAssertEqual(cell.collectionArtistLinkFrameForTesting.minX, 14)
            XCTAssertLessThanOrEqual(cell.collectionArtistLinkFrameForTesting.width, w - 28)
            XCTAssertEqual(cell.collectionArtistLinkFrameForTesting.height, 19)
        }
    }

    func testTypographyOfThePanel() throws {
        let cell = cell()
        let badge = cell.typeLabelForTesting
        let font = try XCTUnwrap(badge.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 10)
        XCTAssertEqual(try XCTUnwrap(badge.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat), 1.2, accuracy: 0.001)
        XCTAssertEqual(cell.featuredTitleFontForTesting?.pointSize, 17)
        XCTAssertEqual(cell.collectionArtistFontForTesting?.pointSize, 14)
        XCTAssertEqual(cell.collectionSummaryFontForTesting?.pointSize, 12)
        let weights = [font, cell.featuredTitleFontForTesting, cell.collectionArtistFontForTesting].compactMap { $0 }
            .map { ($0.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0 }
        XCTAssertGreaterThan(weights[0], weights[2], "La etiqueta es bold y el artista medium")
        XCTAssertEqual(weights[0], weights[1], accuracy: 0.001, "Etiqueta y título son bold")
    }

    func testFramesDoNotNeedMeasuringTextAndFollowTheWidth() {
        let cell = cell(width: 200)
        cell.frame = NSRect(x: 0, y: 0, width: 300, height: 421)
        cell.layoutSubtreeIfNeeded()
        XCTAssertEqual(cell.collectionPanelFrameForTesting, NSRect(x: 0, y: 300, width: 300, height: 121))
        XCTAssertEqual(cell.collectionSummaryFrameForTesting.width, 272)
    }

    // MARK: Etiqueta de tipo

    func testBadgeFollowsWindowsLogicAndKeys() {
        XCTAssertEqual(HomeCollectionBadge.releaseType(subtitle: "Single • Cerati • 2020"), .single)
        XCTAssertEqual(HomeCollectionBadge.releaseType(subtitle: "Sencillo • Cerati"), .single)
        XCTAssertEqual(HomeCollectionBadge.releaseType(subtitle: "EP · Cerati"), .ep)
        XCTAssertEqual(HomeCollectionBadge.releaseType(subtitle: "Álbum • Cerati"), .album)
        XCTAssertEqual(HomeCollectionBadge.releaseType(subtitle: " • Single"), .single, "Componentes vacíos se ignoran")
        XCTAssertEqual(HomeCollectionBadge.releaseType(subtitle: "Cerati • Single"), .album, "Sólo cuenta el primer componente")
        XCTAssertEqual(HomeCollectionBadge.releaseType(subtitle: nil), .album)
        XCTAssertEqual(HomeCollectionBadge.text(kind: "album", subtitle: "Single • X"), L10n.text("metadata.single"))
        XCTAssertEqual(HomeCollectionBadge.text(kind: "album", subtitle: "EP • X"), "EP")
        XCTAssertEqual(HomeCollectionBadge.text(kind: "album", subtitle: nil), L10n.text("detail.kind.album"))
        XCTAssertEqual(HomeCollectionBadge.text(kind: "playlist", subtitle: "Álbum"), L10n.text("detail.kind.playlist"))
        // Mayúsculas de Windows: «ÁLBUM» y «LISTA DE REPRODUCCIÓN» (mayúsculas), «Sencillo» no.
        XCTAssertEqual(L10n.text("detail.kind.album", language: .es), "ÁLBUM")
        XCTAssertEqual(L10n.text("detail.kind.playlist", language: .es), "LISTA DE REPRODUCCIÓN")
        XCTAssertEqual(L10n.text("metadata.single", language: .es), "Sencillo")
    }

    func testBadgeTextIsShownInTheCell() {
        XCTAssertEqual(cell(record: album(subtitle: "EP • Cerati")).collectionBadgeTextForTesting, "EP")
        XCTAssertEqual(cell(record: album(kind: "playlist")).collectionBadgeTextForTesting, L10n.text("detail.kind.playlist"))
    }

    // MARK: Acabados

    func testColorsPerFinish() throws {
        func rgba(_ color: NSColor?) -> [CGFloat] {
            let value = (color ?? .clear).usingColorSpace(.sRGB) ?? .clear
            return [value.redComponent, value.greenComponent, value.blueComponent, value.alphaComponent].map { ($0 * 1000).rounded() / 1000 }
        }
        func hex(_ value: UInt32, alpha: CGFloat = 1) -> [CGFloat] {
            [CGFloat((value >> 16) & 0xff) / 255, CGFloat((value >> 8) & 0xff) / 255, CGFloat(value & 0xff) / 255, alpha]
                .map { ($0 * 1000).rounded() / 1000 }
        }
        let white = cell(style: .white).collectionTextColorsForTesting
        XCTAssertEqual(rgba(white.title), hex(0x1d1d1f))
        XCTAssertEqual(rgba(white.artist), hex(0x3a3a3c))
        XCTAssertEqual(rgba(white.badge), hex(0x6e6e73))
        XCTAssertEqual(rgba(white.summary), hex(0x6e6e73))
        XCTAssertEqual(rgba(cell(style: .white).collectionPanelColorForTesting), hex(0xf5f5f7))
        let tinted = cell(style: .tinted).collectionTextColorsForTesting
        XCTAssertEqual(rgba(tinted.title), hex(0x1d1d1f))
        XCTAssertEqual(rgba(tinted.artist), [0, 0, 0, 0.79])
        XCTAssertEqual(rgba(tinted.badge), [0, 0, 0, 0.58])
        XCTAssertEqual(rgba(tinted.summary), [0, 0, 0, 0.58])
        XCTAssertFalse(HomeCollectionCardPalette.make(.white).washed)
        XCTAssertTrue(HomeCollectionCardPalette.make(.tinted).washed)
    }

    func testPanelIsLightEvenInDarkMode() throws {
        let cell = cell(style: .tinted)
        cell.appearance = NSAppearance(named: .darkAqua)
        cell.layoutSubtreeIfNeeded()
        let colors = cell.collectionTextColorsForTesting
        for color in [colors.badge, colors.title, colors.artist, colors.summary, cell.collectionPanelColorForTesting] {
            let value = try XCTUnwrap(color?.usingColorSpace(.sRGB))
            XCTAssertTrue(value.alphaComponent >= 0.5 && (value.redComponent < 0.5 || value.redComponent > 0.9))
        }
        XCTAssertGreaterThan(try XCTUnwrap(cell.collectionPanelColorForTesting?.usingColorSpace(.sRGB)).redComponent, 0.9)
        XCTAssertEqual(try XCTUnwrap(colors.title?.usingColorSpace(.sRGB)).redComponent, 0x1d / 255.0, accuracy: 0.002)
    }

    func testChangingTheFinishRepaintsTheCellWithoutReconfiguring() async throws {
        let cell = cell(style: .tinted, record: album(thumbnail: "https://fixture.invalid/a"), loaded: cgImage(top: .red, bottom: .blue))
        try await waitFor { cell.collectionWashForTesting != nil }
        XCTAssertNotNil(cell.collectionWashForTesting)
        let before = cell.collectionTextColorsForTesting.artist
        cell.albumCardStyle = .white
        XCTAssertNotEqual(before, cell.collectionTextColorsForTesting.artist)
        XCTAssertNil(cell.collectionWashForTesting, "El acabado blanco no lleva lavado")
        cell.albumCardStyle = .tinted
        XCTAssertNotNil(cell.collectionWashForTesting, "Vuelve a pintar el lavado en caché")
    }

    func testRailReconfiguresVisibleCellsWhenTheFinishChanges() throws {
        let rail = HomeFeaturedRailView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let records = (0..<6).map { album("a\($0)") }
        func model(_ style: HomeAlbumCardStyle) -> HomeFeaturedNativeRail {
            HomeFeaturedNativeRail(records: records, leadingInset: 28, trailingInset: 28, albumCardStyle: style,
                session: "s", playback: nil, playing: false, onOpen: { _ in }, onPlay: { _ in }, menu: nil)
        }
        rail.apply(model(.tinted))
        rail.layoutSubtreeIfNeeded()
        let cellItem = try XCTUnwrap(rail.collection.item(at: IndexPath(item: 0, section: 0)) as? HomeCollectionItem)
        XCTAssertEqual(cellItem.content.albumCardStyle, .tinted)
        let configured = rail.configuredCount
        rail.apply(model(.tinted))
        XCTAssertEqual(rail.configuredCount, configured, "Mismo acabado: nada que reconfigurar")
        rail.apply(model(.white))
        XCTAssertGreaterThan(rail.configuredCount, configured)
        XCTAssertEqual(cellItem.content.albumCardStyle, .white)
        rail.stop()
    }

    // MARK: Lavado teñido

    func testWashIsMirroredBlurredAndComputedOncePerCover() async throws {
        let image = cgImage(top: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), bottom: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        let wash = try XCTUnwrap(HomeCoverWashStore.render(image))
        XCTAssertEqual(wash.width, HomeCoverWashStore.side)
        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let rep = NSBitmapImageRep(cgImage: wash)
            let color = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            return (Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
        }
        // La imagen tiene rojo arriba y azul abajo: el lavado está espejado (azul arriba, rojo abajo).
        let topPixel = pixel(32, 6), bottomPixel = pixel(32, wash.height - 7)
        XCTAssertGreaterThan(topPixel.b, topPixel.r, "Arriba debe ser azul (espejado)")
        XCTAssertGreaterThan(bottomPixel.r, bottomPixel.b, "Abajo debe ser rojo (espejado)")
        // Muy desenfocado: el cambio brusco del centro es suave.
        XCTAssertGreaterThan(pixel(32, 28).r + pixel(32, 28).b, 60)

        let store = HomeCoverWashStore()
        let first = await store.wash(url: "u", session: "s", image: { image })
        let second = await store.wash(url: "u", session: "s", image: { image })
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
        XCTAssertEqual(store.renderCount, 1, "Se genera una vez por carátula")
        XCTAssertNotNil(store.cached(url: "u", session: "s"))
        XCTAssertNil(store.cached(url: "u", session: "otra"), "Otra sesión descarta la caché")
        for index in 0..<(HomeCoverWashStore.capacity + 8) {
            _ = await store.wash(url: "x\(index)", session: "otra", image: { image })
        }
        XCTAssertNil(store.cached(url: "x0", session: "otra"), "La caché está acotada")
        XCTAssertNotNil(store.cached(url: "x\(HomeCoverWashStore.capacity + 7)", session: "otra"))
    }

    func testRecycledCellNeverShowsThePreviousCoverWash() async throws {
        let store = HomeCoverWashStore()
        let red = cgImage(top: .red, bottom: .red), green = cgImage(top: .green, bottom: .green)
        // El lavado de A es lento y queda en vuelo en la caché compartida.
        let slow = Task { @MainActor in
            await store.wash(url: "https://fixture.invalid/a", session: "session", image: { try? await Task.sleep(for: .milliseconds(150)); return red })
        }
        await Task.yield()
        let cell = cell(record: album("a", thumbnail: "https://fixture.invalid/a"))
        cell.coverWashStore = store
        cell.artworkLoader = { url, _ in NSImage(cgImage: url.lastPathComponent == "a" ? red : green, size: NSSize(width: 64, height: 64)) }
        cell.configure(record: album("a2", thumbnail: "https://fixture.invalid/a"), style: .largeCard, currentTrackID: nil, isPlaying: false,
                       onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil })
        try await Task.sleep(for: .milliseconds(30))
        cell.prepareForReuse()
        cell.featuredCollection = true
        cell.coverWashStore = store
        cell.coverSession = "session"
        cell.configure(record: album("b", thumbnail: "https://fixture.invalid/b"), style: .largeCard, currentTrackID: nil, isPlaying: false,
                       onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil })
        cell.applyFeaturedLayout(song: false, summary: "")
        try await Task.sleep(for: .milliseconds(300))
        _ = await slow.value
        let shown = try XCTUnwrap(cell.collectionWashForTesting)
        let color = try XCTUnwrap(NSBitmapImageRep(cgImage: shown).colorAt(x: 32, y: 32)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(color.greenComponent, color.redComponent, "Debe verse el lavado de B (verde), no el de A (rojo)")
        cell.prepareForReuse()
        XCTAssertNil(cell.collectionWashForTesting, "Al reciclar el lavado se descarta")
    }

    func testStoppedRailDropsLateWash() async throws {
        let store = HomeCoverWashStore()
        let rail = HomeFeaturedRailView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let records = (0..<4).map { album("a\($0)", thumbnail: "https://fixture.invalid/\($0)") }
        rail.apply(HomeFeaturedNativeRail(records: records, leadingInset: 28, trailingInset: 28, session: "s", playback: nil,
            playing: false, onOpen: { _ in }, onPlay: { _ in }, menu: nil))
        rail.layoutSubtreeIfNeeded()
        let item = try XCTUnwrap(rail.collection.item(at: IndexPath(item: 0, section: 0)) as? HomeCollectionItem)
        item.content.coverWashStore = store
        item.content.artworkLoader = nil
        item.content.setArtwork(NSImage(cgImage: cgImage(top: .red, bottom: .red), size: NSSize(width: 64, height: 64)))
        rail.stop()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(item.content.collectionWashForTesting)
    }

    // MARK: Elevación, hover y controles

    func testHoverLiftsTheCardDimsTheCoverAndShowsTheControls() throws {
        let root = FlippedRoot()
        let cell = cell(parent: root)
        XCTAssertEqual(cell.collectionLiftForTesting, 0)
        XCTAssertEqual(cell.collectionDimOpacityForTesting, 0)
        XCTAssertNil(cell.collectionGlassForTesting.play)
        XCTAssertFalse(cell.featuredPlayVisibleForTesting)
        let frame = cell.frame
        let rest = cell.collectionShadowForTesting
        XCTAssertEqual(rest.opacity, 1)
        XCTAssertEqual(rest.radius, 15)

        cell.setHovered(true)
        cell.layoutSubtreeIfNeeded()
        XCTAssertEqual(cell.frame, frame, "Sube con una transformación, no con el marco")
        // En un contenedor con el eje Y hacia abajo subir es restar 4.
        XCTAssertEqual(cell.collectionLiftForTesting, -4)
        XCTAssertEqual(cell.collectionDimOpacityForTesting, 0.3, accuracy: 0.0001)
        XCTAssertGreaterThan(cell.collectionZPositionForTesting, 0, "Queda sobre sus vecinas")
        let lifted = cell.collectionShadowForTesting
        XCTAssertEqual(lifted.opacity, 0.8, accuracy: 0.0001)
        XCTAssertEqual(lifted.radius, 17)
        XCTAssertLessThan(lifted.box.width, rest.box.width, "La dispersión pasa de −16 a −18")
        XCTAssertGreaterThan(lifted.box.minY, rest.box.minY, "El desplazamiento pasa de 12 a 20 hacia abajo")
        let glass = cell.collectionGlassForTesting
        XCTAssertNotNil(glass.play)
        XCTAssertNotNil(glass.more)
        XCTAssertTrue(cell.featuredPlayVisibleForTesting)
        // Círculos de 38 pt a 12 pt de los bordes de la portada: Play abajo a la izquierda y menú abajo a la derecha.
        let width = cell.bounds.width
        XCTAssertEqual(cell.collectionPlayControlFrameForTesting, NSRect(x: 12, y: width - 12 - 38, width: 38, height: 38))
        XCTAssertEqual(cell.collectionMoreControlFrameForTesting, NSRect(x: width - 12 - 38, y: width - 12 - 38, width: 38, height: 38))
        XCTAssertEqual(glass.play?.frame, cell.collectionPlayControlFrameForTesting)
        XCTAssertEqual(glass.more?.frame, cell.collectionMoreControlFrameForTesting)

        cell.setHovered(false)
        XCTAssertEqual(cell.collectionLiftForTesting, 0)
        XCTAssertEqual(cell.collectionDimOpacityForTesting, 0)
        XCTAssertEqual(cell.collectionZPositionForTesting, 0)
        XCTAssertEqual(cell.collectionShadowForTesting.radius, 15)
        XCTAssertTrue(glass.play?.isHidden == true)
    }

    func testLiftGoesUpInAnUnflippedContainerToo() {
        let cell = cell(parent: NSView())
        cell.setHovered(true)
        XCTAssertEqual(cell.collectionLiftForTesting, 4)
    }

    func testShadowIsNeverTintedWithTheCover() throws {
        let cell = cell()
        cell.setArtwork(NSImage(cgImage: cgImage(top: .red, bottom: .red), size: NSSize(width: 64, height: 64)))
        cell.setHovered(true)
        let color = try XCTUnwrap(cell.layer?.shadowColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) })
        XCTAssertEqual([color.redComponent, color.greenComponent, color.blueComponent], [0, 0, 0])
    }

    func testRestShadowIsAnExplicitPathShrunkBySixteenAndShiftedDown() {
        let cell = cell(width: 200)
        let shadow = cell.collectionShadowForTesting
        XCTAssertEqual(shadow.box.width, 200 - 32, accuracy: 0.01)
        XCTAssertEqual(shadow.box.height, 321 - 32, accuracy: 0.01)
        XCTAssertEqual(shadow.box.minY, 16 + 12, accuracy: 0.01)
        XCTAssertFalse(cell.layer?.masksToBounds ?? true, "La sombra no puede quedar recortada por la celda")
    }

    func testMenuAndPlayAreStillTheClickTargetsAndTheCardIsClickableEverywhere() {
        var opened = 0, played = 0
        let cell = HomeItemView(frame: NSRect(x: 0, y: 0, width: 200, height: 321))
        cell.featuredCollection = true
        cell.coverWashStore = HomeCoverWashStore()
        cell.configure(record: album(), style: .largeCard, currentTrackID: nil, isPlaying: false, onCard: { opened += 1 },
            onCover: { opened += 1 }, onTitle: { opened += 1 }, onArtist: {}, onAlbum: {}, onDirectPlay: { played += 1 },
            menuProvider: { NSMenu(title: "menu") })
        cell.applyFeaturedLayout(song: false, summary: "x")
        cell.layoutSubtreeIfNeeded()
        let superview = FlippedRoot()
        superview.addSubview(cell)
        // Panel de texto, portada y título abren la colección.
        for point in [NSPoint(x: 100, y: 100), NSPoint(x: 190, y: 250), NSPoint(x: 100, y: 310)] {
            (cell.hitTest(point) as? NSButton)?.performClick(nil)
        }
        XCTAssertEqual(opened, 3)
        cell.setHovered(true)
        let play = cell.collectionPlayControlFrameForTesting
        (cell.hitTest(NSPoint(x: play.midX, y: play.midY)) as? NSButton)?.performClick(nil)
        XCTAssertEqual(played, 1)
        XCTAssertNotNil(cell.currentMenuForTesting())
    }

    func testArtistLinkOnlyCoversItsTextAndIsEnabledOnlyWithAnID() {
        let linked = cell(record: album(artistId: "UC1"))
        let link = linked.collectionArtistLinkFrameForTesting
        XCTAssertLessThan(link.width, 200 - 28, "El enlace ocupa el texto, no toda la fila")
        XCTAssertTrue(linked.artist.isEnabled)
        XCTAssertTrue(linked.hitTest(NSPoint(x: link.midX, y: link.midY)) === linked.artist)
        XCTAssertFalse(linked.hitTest(NSPoint(x: 190, y: link.midY)) === linked.artist)
        let plain = cell(record: album(artistId: nil))
        XCTAssertFalse(plain.artist.isEnabled, "Sin ID es texto sin enlace")
        XCTAssertFalse(plain.collectionArtistLabelFrameForTesting.isEmpty)
        let plainPlaylist = cell(record: album(artistId: nil, kind: "playlist"))
        XCTAssertFalse(plainPlaylist.collectionArtistLabelFrameForTesting.isEmpty)
        XCTAssertFalse(plainPlaylist.largeArtistLabelHiddenForTesting, "La lista muestra su creador aunque no haya enlace")
    }

    func testHoveringTheArtistLinkEmphasizesItOnTheLightPanel() throws {
        let cell = cell()
        let link = cell.collectionArtistLinkFrameForTesting
        let rest = try XCTUnwrap(cell.collectionTextColorsForTesting.artist?.usingColorSpace(.sRGB))
        cell.setHovered(true, localPoint: NSPoint(x: link.midX, y: link.midY))
        let hover = try XCTUnwrap(cell.collectionTextColorsForTesting.artist?.usingColorSpace(.sRGB))
        XCTAssertEqual(hover.redComponent, 0)
        XCTAssertEqual(hover.alphaComponent, 1)
        XCTAssertNotEqual(rest.alphaComponent, 1)
        XCTAssertTrue(cell.collectionArtistUnderlinedForTesting)
    }

    func testLoadingShowsASpinnerInPlaceOfPlay() {
        let cell = cell()
        cell.setLoading(true)
        XCTAssertTrue(cell.featuredPlayVisibleForTesting)
        XCTAssertNotNil(cell.collectionGlassForTesting.play, "El spinner va sobre el círculo de Play")
        XCTAssertTrue(cell.subviews.contains { $0 is NSProgressIndicator })
        cell.setLoading(false)
        XCTAssertFalse(cell.subviews.contains { $0 is NSProgressIndicator })
    }

    func testReduceMotionAppliesStatesWithoutAnimations() {
        let still = cell(parent: FlippedRoot())
        still.reducesMotion = { true }
        still.setHovered(true)
        XCTAssertEqual(still.collectionLiftForTesting, -4)
        XCTAssertTrue(still.collectionCardAnimationKeysForTesting.isEmpty)

        // Con movimiento y ventana la elevación se anima 180 ms.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let root = FlippedRoot(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        window.contentView = root
        let moving = cell(parent: root)
        moving.reducesMotion = { false }
        moving.setHovered(true)
        XCTAssertEqual(moving.collectionLiftForTesting, -4, "El estado final se aplica de inmediato")
        XCTAssertTrue(moving.collectionCardAnimationKeysForTesting.contains("lift"))
        XCTAssertTrue(moving.collectionCardAnimationKeysForTesting.contains("dim"))
        let animation = moving.layer?.animation(forKey: "lift")
        XCTAssertEqual(animation?.duration ?? 0, 0.18, accuracy: 0.0001)
        let timing = animation?.timingFunction
        var points = [Float](repeating: 0, count: 2)
        var control: [Float] = []
        for index in 1...2 { timing?.getControlPoint(at: index, values: &points); control += points }
        XCTAssertEqual(control, [0.2, 0.8, 0.2, 1])
        XCTAssertEqual(moving.coverDimDurationForTesting, 0.15, accuracy: 0.0001)
    }

    func testReduceTransparencyUsesOpaqueBlackCirclesWithoutBlur() {
        let cell = cell()
        cell.reducesTransparency = { true }
        cell.setHovered(true)
        guard let play = cell.collectionGlassForTesting.play else { return XCTFail("Falta el círculo") }
        XCTAssertTrue(play.isSolid)
        XCTAssertFalse(play.hasBlurForTesting)
        let color = play.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
        XCTAssertEqual(color?.alphaComponent ?? 0, 0.6, accuracy: 0.001)
        XCTAssertEqual(color?.redComponent ?? 1, 0)
        XCTAssertEqual(play.tintAlphaForTesting, 0)

        let clear = self.cell()
        clear.reducesTransparency = { false }
        clear.setHovered(true)
        XCTAssertFalse(clear.collectionGlassForTesting.play?.isSolid ?? true)
        XCTAssertTrue(clear.collectionGlassForTesting.play?.hasBlurForTesting ?? false)
        // Si cambia la preferencia con la tarjeta ya mostrada, el círculo se rehace.
        clear.reducesTransparency = { true }
        clear.setHovered(false); clear.setHovered(true)
        XCTAssertTrue(clear.collectionGlassForTesting.play?.isSolid ?? false)
    }

    func testCircleUnderThePointerBrightens() {
        let cell = cell()
        cell.setHovered(true)
        let play = cell.collectionPlayControlFrameForTesting
        let rest = cell.collectionGlassForTesting.play?.tintAlphaForTesting ?? 0
        cell.setHovered(true, localPoint: NSPoint(x: play.midX, y: play.midY))
        let over = cell.collectionGlassForTesting.play?.tintAlphaForTesting ?? 0
        XCTAssertGreaterThan(over, rest)
        let more = cell.collectionMoreControlFrameForTesting
        let moreRest = cell.collectionGlassForTesting.more?.tintAlphaForTesting ?? 0
        cell.setHovered(true, localPoint: NSPoint(x: more.midX, y: more.midY))
        XCTAssertGreaterThan(cell.collectionGlassForTesting.more?.tintAlphaForTesting ?? 0, moreRest)
        XCTAssertEqual(cell.collectionGlassForTesting.play?.tintAlphaForTesting ?? 1, rest, "Sólo el círculo bajo el puntero")
    }

    func testGlassCirclesAreCreatedLazilyOnlyForTheHoveredCard() throws {
        let rail = HomeFeaturedRailView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let records = (0..<4).map { album("a\($0)") }
        rail.apply(HomeFeaturedNativeRail(records: records, leadingInset: 28, trailingInset: 28, session: "s", playback: nil,
            playing: false, onOpen: { _ in }, onPlay: { _ in }, menu: nil))
        rail.layoutSubtreeIfNeeded()
        let cells = (0..<4).compactMap { rail.collection.item(at: IndexPath(item: $0, section: 0)) as? HomeCollectionItem }
        XCTAssertGreaterThanOrEqual(cells.count, 3)
        XCTAssertTrue(cells.allSatisfy { $0.content.collectionGlassForTesting.play == nil })
        cells[1].content.setHovered(true)
        XCTAssertNotNil(cells[1].content.collectionGlassForTesting.play)
        XCTAssertTrue(cells.enumerated().allSatisfy { $0.offset == 1 || $0.element.content.collectionGlassForTesting.play == nil })
        // Al reciclar se liberan.
        cells[1].content.prepareForReuse()
        XCTAssertNil(cells[1].content.collectionGlassForTesting.play)
        rail.stop()
    }

    func testRecycledCellStartsAtRest() {
        let cell = cell()
        cell.setHovered(true)
        cell.prepareForReuse()
        XCTAssertEqual(cell.collectionLiftForTesting, 0)
        XCTAssertEqual(cell.collectionDimOpacityForTesting, 0)
        XCTAssertEqual(cell.collectionZPositionForTesting, 0)
        XCTAssertNil(cell.collectionGlassForTesting.play)
    }

    // MARK: Resolución de portada

    func testArtworkRequestUsesTwoFixedSizesByKind() {
        XCTAssertEqual(HomeItemView.featuredArtworkRequest(song: true, collection: false, size: .small)?.pixels, 480)
        XCTAssertEqual(HomeItemView.featuredArtworkRequest(song: true, collection: false, size: .small)?.target, CGSize(width: 240, height: 240))
        for size in [HomeMosaicSize.wide, .large] {
            XCTAssertEqual(HomeItemView.featuredArtworkRequest(song: true, collection: false, size: size)?.pixels, 640)
            XCTAssertEqual(HomeItemView.featuredArtworkRequest(song: true, collection: false, size: size)?.target, CGSize(width: 320, height: 320))
        }
        XCTAssertEqual(HomeItemView.featuredArtworkRequest(song: false, collection: true, size: .small)?.pixels, 640)
        XCTAssertNil(HomeItemView.featuredArtworkRequest(song: false, collection: false, size: .small))
    }

    func testCollectionCellRequestsTheLargeCover() async throws {
        let cell = HomeItemView(frame: NSRect(x: 0, y: 0, width: 200, height: 321))
        cell.featuredCollection = true
        var requested: [(URL, CGSize)] = []
        cell.artworkLoader = { url, size in requested.append((url, size)); return nil }
        cell.configure(record: album(thumbnail: "https://lh3.googleusercontent.com/abc=w544-h544"), style: .largeCard, currentTrackID: nil,
                       isPlaying: false, onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil })
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(requested.first?.1, CGSize(width: 320, height: 320))
        XCTAssertTrue(requested.first?.0.absoluteString.contains("640") ?? false, "\(String(describing: requested.first?.0))")
    }

    // MARK: Renders de revisión

    /// Carátulas locales con colores distintos y una forma asimétrica para ver el espejado del lavado.
    private func writeCovers(_ directory: URL) throws -> [URL] {
        let palette: [(NSColor, NSColor)] = [(.systemOrange, .systemPurple), (.systemTeal, .systemIndigo), (.systemPink, .systemYellow), (.systemGreen, .black)]
        return try palette.enumerated().map { index, colors in
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 640, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSGradient(starting: colors.0, ending: colors.1)!.draw(in: NSRect(x: 0, y: 0, width: 640, height: 640), angle: 90)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 380, y: 380, width: 180, height: 180)).fill()
            NSGraphicsContext.restoreGraphicsState()
            let url = directory.appendingPathComponent("cover\(index).png")
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
            return url
        }
    }

    private func renderRail(style: HomeAlbumCardStyle, hover: Int? = nil, reduceTransparency: Bool = false, path: String,
                            width: CGFloat = 704) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let covers = try writeCovers(directory)
        let titles = ["Bocanada", "Demon Days con un título larguísimo que no entra", "Random Access Memories", "After Hours"]
        let subtitles = ["Álbum • Gustavo Cerati • 1999", "Single • Gorillaz • 2005", "EP • Daft Punk • 2013", "Álbum • The Weeknd • 2020"]
        let records = (0..<4).map { index in
            album("a\(index)", title: titles[index], subtitle: subtitles[index], artists: ["Gustavo Cerati", "Gorillaz", "Daft Punk", "The Weeknd"][index],
                  artistId: index == 2 ? nil : "UC\(index)", thumbnail: covers[index].absoluteString)
        }
        let height = HomeCollectionCardMetrics.railHeight(cardWidth: HomeCollectionRowLayout(width: width).cardWidth)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1).cgColor
        let rail = HomeFeaturedRailView(frame: root.bounds)
        root.addSubview(rail)
        rail.apply(HomeFeaturedNativeRail(records: records, leadingInset: 28, trailingInset: 28, albumCardStyle: style, session: "render",
            playback: nil, playing: false,
            summary: { _ in "Álbum • 1999 • 12 canciones • 52 min" }, onOpen: { _ in }, onPlay: { _ in }, menu: nil))
        rail.layoutSubtreeIfNeeded()
        var cells: [HomeCollectionItem] = []
        for _ in 0..<150 {
            cells = rail.collection.visibleItems().compactMap { $0 as? HomeCollectionItem }
            if !cells.isEmpty, cells.allSatisfy({ $0.content.featuredArtworkSizeForTesting != nil && (style == .white || $0.content.collectionWashForTesting != nil) }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(cells.isEmpty)
        if let hover, let cell = cells.first(where: { $0.content.collectionTitleFrameForTesting.minX >= 0 && rail.collection.indexPath(for: $0)?.item == hover }) {
            cell.content.reducesTransparency = { reduceTransparency }
            cell.content.setHovered(true)
            let play = cell.content.collectionPlayControlFrameForTesting
            cell.content.setHovered(true, localPoint: NSPoint(x: play.midX, y: play.midY))
        }
        root.layoutSubtreeIfNeeded()
        let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * 2, pixelsHigh: Int(height) * 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        output.size = root.bounds.size
        root.cacheDisplay(in: root.bounds, to: output)
        try XCTUnwrap(output.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        rail.stop()
    }

    func testRenderTintedWhiteHoverAndReducedTransparency() async throws {
        try await renderRail(style: .tinted, path: "/tmp/sideb-card-tinted.png")
        try await renderRail(style: .white, path: "/tmp/sideb-card-white.png")
        try await renderRail(style: .tinted, hover: 1, path: "/tmp/sideb-card-hover.png")
        try await renderRail(style: .tinted, hover: 1, reduceTransparency: true, path: "/tmp/sideb-card-reduced-transparency.png")
    }

    // MARK: Utilidades

    private func waitFor(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(3)) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    }
}
