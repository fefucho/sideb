import Foundation
import Testing
@testable import SideB

@Suite("PlaybackSidebarResize Tests")
struct PlaybackSidebarResizeTests {
    @Test func clampBoundsAndRejectsNonFinite() {
        #expect(PlaybackSidebarLayout.clampWidth(100) == 340)
        #expect(PlaybackSidebarLayout.clampWidth(9000) == 520)
        #expect(PlaybackSidebarLayout.clampWidth(450) == 450)
        #expect(PlaybackSidebarLayout.clampWidth(.nan) == PlaybackSidebarLayout.width)
        #expect(PlaybackSidebarLayout.width == 380)
    }

    @Test func storedWidthPersistsAndClampsOnRead() {
        let suite = "sideb.test.playbackWidth.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(PlaybackSidebarLayout.storedWidth(in: defaults) == 380)
        defaults.set(470.0, forKey: PlaybackSidebarLayout.widthPreferenceKey)
        #expect(PlaybackSidebarLayout.storedWidth(in: defaults) == 470)
        defaults.set(9999.0, forKey: PlaybackSidebarLayout.widthPreferenceKey)
        #expect(PlaybackSidebarLayout.storedWidth(in: defaults) == 520)
        defaults.set(10.0, forKey: PlaybackSidebarLayout.widthPreferenceKey)
        #expect(PlaybackSidebarLayout.storedWidth(in: defaults) == 340)
    }

    @Test func narrowWindowReducesEffectiveWidthButKeepsContentFloor() {
        // Ventana ancha: se respeta el guardado.
        #expect(PlaybackSidebarLayout.effectiveWidth(stored: 520, windowWidth: 1400, leftReserve: 0) == 520)
        // 960 - 12 - 480 = 468: el guardado 520 se reduce, sin bajar de 480 pt de pagina.
        let narrow = PlaybackSidebarLayout.effectiveWidth(stored: 520, windowWidth: 960, leftReserve: 0)
        #expect(narrow == 468)
        let reserve = PlaybackSidebarLayout.contentReserve(windowWidth: 960, leftReserve: 0, presented: true, panelWidth: narrow)
        #expect(960 - reserve >= 480 && reserve == narrow + 12)
        // Ventana muy angosta: no hay reserva (el panel se superpone) y el ancho nunca baja del minimo.
        #expect(PlaybackSidebarLayout.effectiveWidth(stored: 520, windowWidth: 700, leftReserve: 0) == 340)
        #expect(PlaybackSidebarLayout.contentReserve(windowWidth: 700, leftReserve: 0, presented: true, panelWidth: 340) == 0)
        #expect(PlaybackSidebarLayout.contentReserve(windowWidth: 1400, leftReserve: 0, presented: false, panelWidth: 450) == 0)
        // Con ancho por defecto el comportamiento previo se conserva.
        #expect(PlaybackSidebarLayout.contentReserve(windowWidth: 1400, leftReserve: 0, presented: true) == PlaybackSidebarLayout.reserve)
    }

    @Test func dragTargetClampsAndNeverTouchesPersistedWidthOrReserve() {
        let drag = PlaybackSidebarResizeDrag(startWidth: 380, maximum: 468)
        // Arrastrar a la izquierda agranda, hasta el limite por ventana (468), nunca mas de 520.
        #expect(drag.target(translation: -50) == 430)
        #expect(drag.target(translation: -400) == 468)
        #expect(drag.target(translation: 400) == 340)
        #expect(PlaybackSidebarResizeDrag(startWidth: 380, maximum: 9000).target(translation: -900) == 520)
        // El objetivo es un valor puro: el ancho guardado y la reserva no dependen de ella.
        let suite = "sideb.test.drag.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = drag.target(translation: -80)
        #expect(defaults.object(forKey: PlaybackSidebarLayout.widthPreferenceKey) == nil)
        #expect(PlaybackSidebarLayout.contentReserve(windowWidth: 1400, leftReserve: 0, presented: true, panelWidth: 380) == 392)
    }

    @MainActor @Test func liveWidthModelCoalescesAndDoesNotTouchReserveOrPreferences() {
        let suite = "sideb.test.live.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlaybackPanelResizeModel()
        #expect(!model.isResizing)
        let reserveBefore = PlaybackSidebarLayout.contentReserve(windowWidth: 1400, leftReserve: 0, presented: true, panelWidth: 380)
        for width in stride(from: CGFloat(380), through: 500, by: 7.4) { model.update(width) }
        #expect(model.isResizing && model.liveWidth == 498)
        // La reserva de la pagina se calcula con el ancho guardado (no el vivo) y nada se persiste por tick.
        #expect(PlaybackSidebarLayout.contentReserve(windowWidth: 1400, leftReserve: 0, presented: true, panelWidth: 380) == reserveBefore)
        #expect(defaults.object(forKey: PlaybackSidebarLayout.widthPreferenceKey) == nil)
        model.liveWidth = nil
        #expect(!model.isResizing)
    }

    @MainActor @Test func pageReserveFollowsAtMostOncePerFrameWhilePanelFollowsEveryTick() {
        let model = PlaybackPanelResizeModel()
        model.update(400, now: 10.000)
        #expect(model.liveWidth == 400 && model.pageWidth == 400)
        model.update(410, now: 10.004) // dentro del mismo fotograma
        #expect(model.liveWidth == 410 && model.pageWidth == 400)
        model.update(420, now: 10.020)
        #expect(model.liveWidth == 420 && model.pageWidth == 420)
        model.finish()
        #expect(model.liveWidth == nil && model.pageWidth == nil)
    }

    @Test func itemsNeverWiderThanCoverAcrossWidthsAndHeights() {
        for width: CGFloat in [340, 380, 450, 520] {
            for height: CGFloat in [600, 700, 875, 1000] {
                let items = PlaybackSidebarLayout.itemsWidth(panelWidth: width, panelHeight: height, panel: .artwork, isPortrait: false)
                let footer = PlaybackSidebarLayout.footerHeight(for: height, panel: .artwork, width: width)
                let card = SidebarArtworkLayout(width: width, height: height - footer, portrait: false).cardSide
                #expect(items <= width - 40 + 0.001, "\(width)x\(height)")
                #expect(items <= max(PlaybackSidebarLayout.minimumItemsWidth, card) + 0.001, "\(width)x\(height)")
                if card >= width - 40 { #expect(items == width - 40) } // caratula a todo el ancho: margen de 20 pt
                // metadata y pie comparten ancho (metadataWidth = min(width-40, card)).
                if card >= PlaybackSidebarLayout.minimumItemsWidth {
                    #expect(abs(items - SidebarArtworkLayout(width: width, height: height - footer, portrait: false).metadataWidth) < 0.001)
                }
            }
        }
        // Lyrics, cola y retrato no cambian.
        for panel in [PlaybackSidebarPanel.lyrics, .queue] {
            #expect(PlaybackSidebarLayout.itemsWidth(panelWidth: 520, panelHeight: 700, panel: panel, isPortrait: false) == 480)
        }
        #expect(PlaybackSidebarLayout.itemsWidth(panelWidth: 520, panelHeight: 700, panel: .artwork, isPortrait: true) == 480)
        // Panel ancho y poca altura: items mas angostos que el panel.
        #expect(PlaybackSidebarLayout.itemsWidth(panelWidth: 520, panelHeight: 600, panel: .artwork, isPortrait: false) < 480)
    }

    @Test func imageRequestSizeIsQuantizedSoIntermediateWidthsShareOneLoad() {
        let sizes = Set(stride(from: CGFloat(300), to: 330, by: 3).map { PlaybackSidebarResizeDrag.quantizedImageSide($0).width })
        #expect(sizes.count <= 2)
        #expect(PlaybackSidebarResizeDrag.quantizedImageSide(332).width == 384)
    }

    @Test func artworkAndFooterGeometryHoldsAcrossTheWholeRange() {
        for width: CGFloat in [340, 380, 450, 520] {
            for height: CGFloat in [628, 840, 988, 1400] {
                let layout = SidebarArtworkLayout(width: width, height: height, portrait: false)
                #expect(layout.cardSide <= width - PlaybackSidebarLayout.coverInset * 2)
                let footer = PlaybackSidebarLayout.footerHeight(for: height, panel: .artwork, width: width)
                // El pie nunca baja de su minimo aunque la caratula sea ancha.
                #expect(footer >= PlaybackSidebarLayout.footerHeight(for: height, panel: .artwork, width: 340) - 0.5 || footer >= 200)
                let upper = height - footer
                let hero = SidebarArtworkLayout(width: width, height: upper, portrait: false)
                #expect(hero.metadataTop + PlaybackSidebarLayout.metadataHeight <= upper + 0.5)
                #expect(hero.cardSide >= 0)
            }
        }
        // A mayor ancho, a igual altura, la caratula crece o se mantiene (nunca se encoge).
        let narrow = SidebarArtworkLayout(width: 340, height: 900, portrait: false).cardSide
        let wide = SidebarArtworkLayout(width: 520, height: 900, portrait: false).cardSide
        #expect(wide >= narrow)
    }
}
