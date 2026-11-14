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
