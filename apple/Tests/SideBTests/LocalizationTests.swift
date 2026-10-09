import XCTest
import Observation
@testable import SideB

@MainActor
final class LocalizationTests: XCTestCase {
    func testPreferenceDefaultsPersistsAndRejectsUnknownLanguage() {
        let name = "SideB.Localization.Fixture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppLanguageStore(defaults: defaults)
        XCTAssertEqual(store.language, .es)
        store.setLanguage(.en)
        XCTAssertEqual(store.revision, 1)
        XCTAssertEqual(AppLanguageStore(defaults: defaults).language, .en)
        store.setLanguage(.en)
        XCTAssertEqual(store.revision, 1)
        defaults.set("unsupported", forKey: AppLanguageStore.preferenceKey)
        XCTAssertEqual(AppLanguageStore(defaults: defaults).language, .es)
    }

    func testExplicitLanguageIgnoresSystemPreferredLanguage() {
        XCTAssertEqual(L10n.text("destination.home", language: .es), "Inicio")
        XCTAssertEqual(L10n.text("destination.home", language: .en), "Home")
        XCTAssertEqual(L10n.text("destination.searchQuery", args: ["AC/DC 100% 🎵"], language: .en), "Search: AC/DC 100% 🎵")
        XCTAssertEqual(L10n.text("missing.fixture.key", language: .en), "No disponible")
    }

    func testNativePlurals() {
        XCTAssertEqual(L10n.songCount(0, language: .es), "0 canciones")
        XCTAssertEqual(L10n.songCount(1, language: .es), "1 canción")
        XCTAssertEqual(L10n.songCount(2, language: .es), "2 canciones")
        XCTAssertEqual(L10n.songCount(0, language: .en), "0 songs")
        XCTAssertEqual(L10n.songCount(1, language: .en), "1 song")
        XCTAssertEqual(L10n.songCount(2, language: .en), "2 songs")
        XCTAssertEqual(L10n.trackCount(1, language: .en), "1 track")
    }

    func testMissingEnglishEntryFallsBackToSpanishWithoutExposingKey() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var bundles: [AppLanguage: Bundle] = [:]
        for language in AppLanguage.allCases {
            let folder = root.appendingPathComponent("\(language.rawValue).lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let entries = language == .es ? ["fixture.onlySpanish": "Texto de respaldo"] : ["fixture.english": "English"]
            let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
            try data.write(to: folder.appendingPathComponent("Localizable.strings"))
            bundles[language] = try XCTUnwrap(Bundle(url: folder))
        }
        XCTAssertEqual(L10n.localizedFormat("fixture.onlySpanish", language: .en, bundles: bundles), "Texto de respaldo")
        XCTAssertEqual(L10n.localizedFormat("fixture.missing", language: .en, bundles: bundles), "No disponible")
    }

    func testInstalledBundleIsResolvedInsideRelocatedAppResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Relocated.app/Contents/Resources")
        let bundleURL = resources.appendingPathComponent("SideB_SideB.bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let bundle = try XCTUnwrap(L10n.installedResourceBundle(in: resources))
        XCTAssertEqual(bundle.bundleURL.standardizedFileURL, bundleURL.standardizedFileURL)
        XCTAssertNil(L10n.installedResourceBundle(in: root.appendingPathComponent("missing")))
        XCTAssertNil(L10n.installedResourceBundle(in: nil))
    }

    func testLanguageChangeIsObservedWithoutReplacingState() {
        let name = "SideB.Localization.Observation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppLanguageStore(defaults: defaults)
        let changed = expectation(description: "Observable language")
        withObservationTracking { _ = store.language } onChange: { changed.fulfill() }
        store.setLanguage(.en)
        XCTAssertEqual(store.language, .en)
        wait(for: [changed], timeout: 1)
    }

    func testProviderClassificationKeepsOriginalIDsAndUnknownTitles() {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        AppLanguageStore.shared.setLanguage(.es)
        let identity = HomeRecommendationSettings.categoryKey(forTitle: "Listen again")
        XCTAssertEqual(L10n.providerHeading("Listen again"), "Volver a escuchar")
        AppLanguageStore.shared.setLanguage(.en)
        XCTAssertEqual(L10n.providerHeading("Listen again"), "Listen again")
        XCTAssertEqual(HomeRecommendationSettings.categoryKey(forTitle: "Listen again"), identity)
        XCTAssertEqual(L10n.providerHeading("My personal shelf 🎶"), "My personal shelf 🎶")
        let message = AppMessage(key: "app.startDetails", args: ["Network diagnostic"])
        XCTAssertEqual(message.text, "Couldn’t start Side B: Network diagnostic")
        AppLanguageStore.shared.setLanguage(.es)
        XCTAssertEqual(message.text, "No se pudo iniciar Side B: Network diagnostic")
    }

    func testAdditionalProviderHeadingsTranslateOnlyTheirPresentation() {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        let pairs = [
            ("Similar artists", "Artistas similares"),
            ("Songs for today", "Canciones para hoy"),
            ("Featured playlists", "Listas destacadas"),
            ("More to listen", "Más para escuchar"),
            ("More artists", "Más artistas")
        ]
        for (english, spanish) in pairs {
            let originalCategory = HomeRecommendationSettings.categoryKey(forTitle: english)
            AppLanguageStore.shared.setLanguage(.es)
            XCTAssertEqual(L10n.providerHeading(english), spanish)
            AppLanguageStore.shared.setLanguage(.en)
            XCTAssertEqual(L10n.providerHeading(spanish), english)
            XCTAssertEqual(HomeRecommendationSettings.categoryKey(forTitle: english), originalCategory)
        }
        XCTAssertEqual(L10n.providerHeading("More artists by Sofía 🎵"), "More artists by Sofía 🎵")
    }
}
