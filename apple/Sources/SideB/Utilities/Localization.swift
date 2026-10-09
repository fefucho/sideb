import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case es, en

    var nativeName: String { self == .es ? "Español" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }
}

/// UI preference, independent of account, provider locale and playback state.
@Observable
final class AppLanguageStore: @unchecked Sendable {
    static let preferenceKey = "sideb.ui.language.v1"
    static let shared = AppLanguageStore(defaults: isolatedDefaults())

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let lock = NSRecursiveLock()
    @ObservationIgnored private var storedLanguage: AppLanguage
    @ObservationIgnored private var storedRevision = 0

    var language: AppLanguage {
        access(keyPath: \.language)
        return lock.withLock { storedLanguage }
    }

    var revision: Int {
        access(keyPath: \.revision)
        return lock.withLock { storedRevision }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        storedLanguage = defaults.string(forKey: Self.preferenceKey).flatMap(AppLanguage.init(rawValue:)) ?? .es
    }

    @MainActor func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        withMutation(keyPath: \.language) {
            lock.withLock { storedLanguage = language }
        }
        defaults.set(language.rawValue, forKey: Self.preferenceKey)
        withMutation(keyPath: \.revision) {
            lock.withLock { storedRevision &+= 1 }
        }
    }

    private static func isolatedDefaults() -> UserDefaults {
        let testing = ProcessInfo.processInfo.arguments.contains { $0.contains(".xctest") }
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if testing { return UserDefaults(suiteName: "com.fefucho.SideB.LocalizationTests.\(ProcessInfo.processInfo.processIdentifier)")! }
        if HomeLabConfiguration.enabled { return UserDefaults(suiteName: "com.fefucho.SideB.HomeLab.Localization")! }
        return .standard
    }
}

/// Keep messages as data, so an already-visible error can change language.
struct AppMessage: Equatable, Sendable {
    private let key: String?
    private let args: [String]
    private let verbatim: String?

    init(key: String, args: [String] = []) {
        self.key = key
        self.args = args
        verbatim = nil
    }

    init(verbatim: String) {
        key = nil
        args = []
        self.verbatim = verbatim
    }

    var text: String { key.map { L10n.text($0, args: args) } ?? verbatim ?? "" }
}

enum L10n {
    static var language: AppLanguage { AppLanguageStore.shared.language }
    static var revision: Int { AppLanguageStore.shared.revision }
    static var resourceURL: URL { resourceBundle.bundleURL }

    // Native SwiftPM's accessor searches beside .app and falls back to an absolute
    // build path. Prefer the signed resources inside the installed app explicitly.
    private static let resourceBundle = installedResourceBundle(in: Bundle.main.resourceURL) ?? Bundle.module

    static func installedResourceBundle(in resources: URL?) -> Bundle? {
        resources.flatMap { Bundle(url: $0.appendingPathComponent("SideB_SideB.bundle", isDirectory: true)) }
    }

    private static let bundles: [AppLanguage: Bundle] = {
        Dictionary(uniqueKeysWithValues: AppLanguage.allCases.compactMap { language in
            resourceBundle.url(forResource: language.rawValue, withExtension: "lproj")
                .flatMap(Bundle.init(url:)).map { (language, $0) }
        })
    }()

    static func text(_ key: String, args: [String] = [], language selected: AppLanguage? = nil) -> String {
        let selected = selected ?? language
        let format = lookup(key, language: selected)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: selected.locale, arguments: args.map { $0 as CVarArg })
    }

    static func songCount(_ count: Int, language: AppLanguage? = nil) -> String {
        plural("common.songCount", count: count, language: language)
    }

    static func trackCount(_ count: Int, language: AppLanguage? = nil) -> String {
        plural("common.trackCount", count: count, language: language)
    }

    private static func plural(_ key: String, count: Int, language selected: AppLanguage?) -> String {
        let selected = selected ?? language
        return String(format: lookup(key, language: selected), locale: selected.locale, arguments: [Int64(count)])
    }

    private static func lookup(_ key: String, language: AppLanguage) -> String {
        localizedFormat(key, language: language, bundles: bundles)
    }

    static func localizedFormat(_ key: String, language: AppLanguage, bundles: [AppLanguage: Bundle]) -> String {
        let spanish = bundles[.es]?.localizedString(forKey: key, value: nil, table: nil)
        let fallback = (spanish == key || spanish == nil) ? "No disponible" : spanish!
        return bundles[language]?.localizedString(forKey: key, value: fallback, table: nil) ?? fallback
    }

    /// Classify the untouched provider title; translate only its display label.
    static func providerHeading(_ raw: String) -> String {
        let additional = [
            "similar artists": "similar-artists", "artistas similares": "similar-artists",
            "songs for today": "songs-for-today", "canciones para hoy": "songs-for-today",
            "featured playlists": "featured-playlists", "listas destacadas": "featured-playlists",
            "more to listen": "more-to-listen", "más para escuchar": "more-to-listen",
            "more artists": "more-artists", "más artistas": "more-artists"
        ]
        if let family = additional[raw.lowercased()] { return text("provider.heading.\(family)") }
        let family = HomeRecommendationSettings.categoryKey(forTitle: raw)
        let known = ["quick-picks", "speed-dial", "recommended-albums", "mixes-for-you", "listen-again",
                     "new-releases", "forgotten-favorites", "from-library", "from-community"]
        return known.contains(family) ? text("provider.heading.\(family)") : raw
    }
}
