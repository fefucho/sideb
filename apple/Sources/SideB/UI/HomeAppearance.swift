import Foundation

/// Installation-wide appearance, independent of account and Home recommendations.
enum HomeAppearance {
    static let solidBackgroundKey = "sideb.home.solidBackground.v1"
    static let animatedArtworkKey = "sideb.artwork.animated.v1"
    static let albumCardStyleKey = "sideb.home.albumCardStyle.v1"

    static let preferences: UserDefaults = {
        let testing = ProcessInfo.processInfo.arguments.contains { $0.contains(".xctest") }
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if testing {
            return UserDefaults(suiteName: "com.fefucho.SideB.AppearanceTests.\(ProcessInfo.processInfo.processIdentifier)")!
        }
        if HomeLabConfiguration.enabled {
            return UserDefaults(suiteName: "com.fefucho.SideB.HomeLab.Appearance")!
        }
        return .standard
    }()
}

/// Finish of the text panel on Home's featured collection cards. Installation-wide, not per account.
enum HomeAlbumCardStyle: String, CaseIterable {
    case tinted, white

    static var current: Self {
        guard let raw = HomeAppearance.preferences.string(forKey: HomeAppearance.albumCardStyleKey) else { return .tinted }
        return Self(rawValue: raw) ?? .tinted
    }
}
