import XCTest
@testable import SideB

final class AlbumCardStyleTests: XCTestCase {
    private func reset() { HomeAppearance.preferences.removeObject(forKey: HomeAppearance.albumCardStyleKey) }

    func testDefaultsToTinted() {
        reset()
        XCTAssertEqual(HomeAlbumCardStyle.current, .tinted)
    }

    func testReadsWhite() {
        HomeAppearance.preferences.set("white", forKey: HomeAppearance.albumCardStyleKey)
        defer { reset() }
        XCTAssertEqual(HomeAlbumCardStyle.current, .white)
    }

    func testUnknownValueFallsBackToTinted() {
        HomeAppearance.preferences.set("neon", forKey: HomeAppearance.albumCardStyleKey)
        defer { reset() }
        XCTAssertEqual(HomeAlbumCardStyle.current, .tinted)
    }

    @MainActor func testLocalizationKeysExistInSpanishAndEnglish() {
        let expected: [String: [AppLanguage: String]] = [
            "settings.albumCardStyle": [.es: "Tarjetas de álbumes", .en: "Album cards"],
            "settings.albumCardStyle.tinted": [.es: "Blanco teñido", .en: "Tinted white"],
            "settings.albumCardStyle.white": [.es: "Blanco", .en: "White"],
            "settings.albumCardStyle.hint": [
                .es: "Elegí cómo se ve el panel de texto de las tarjetas destacadas de Inicio.",
                .en: "Choose how the text panel of Home's featured cards looks."]
        ]
        for (key, values) in expected {
            for (language, text) in values {
                XCTAssertEqual(L10n.text(key, language: language), text, "\(key) \(language)")
            }
        }
    }
}
