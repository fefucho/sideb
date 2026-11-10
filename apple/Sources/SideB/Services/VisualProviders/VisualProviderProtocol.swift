import Foundation

struct VisualProviderAuth: Codable, Equatable {
    let type: String
    let loginUrl: String
    let targetHost: String
    let tokenUrl: String

    func validate() throws {
        guard type == "webview",
              let login = URL(string: loginUrl), login.scheme == "https",
              !targetHost.isEmpty, targetHost.count <= 100,
              let token = URL(string: tokenUrl), token.scheme == "https" else {
            throw VisualProviderFailure.invalid
        }
    }
}

/// Versioned JSON/stdio boundary. No Spotify types enter the player or the core.
struct VisualProviderManifest: Codable, Equatable {
    let protocolVersion: Int
    let id: String
    let name: String
    let version: String
    let executable: String
    let credentialLabel: String
    let auth: VisualProviderAuth?
    /// Optional: the platform the executable was built for ("macos-arm64"). Absent in older packages.
    let platform: String?

    #if arch(arm64)
    static let currentPlatform = "macos-arm64"
    #else
    static let currentPlatform = "macos-x64"
    #endif

    init(protocolVersion: Int, id: String, name: String, version: String, executable: String, credentialLabel: String, auth: VisualProviderAuth? = nil, platform: String? = nil) {
        self.protocolVersion = protocolVersion
        self.id = id
        self.name = name
        self.version = version
        self.executable = executable
        self.credentialLabel = credentialLabel
        self.auth = auth
        self.platform = platform
    }

    func validate() throws {
        guard protocolVersion == 1, Self.safeComponent(id), Self.safeComponent(executable),
              !name.isEmpty, name.count <= 100, version.count <= 40,
              credentialLabel.count <= 100 else { throw VisualProviderFailure.invalid }
        // A package for another platform fails here instead of as an unlaunchable executable.
        if let platform, platform != Self.currentPlatform { throw VisualProviderFailure.invalid }
        try auth?.validate()
    }
    static func safeComponent(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value != "." && value != ".." &&
        value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }
    }
}
struct VisualProviderRequest: Encodable {
    let protocolVersion = 1
    let requestId: String
    let credential: String
    let outputDirectory: String
    let track: Track
    struct Track: Encodable {
        let videoId: String
        let title: String
        let artist: String
        let album: String?
        let durationSeconds: UInt64?
        let explicit: Bool?
    }
}
struct VisualProviderReply: Decodable {
    let protocolVersion: Int
    let requestId: String
    let status: String
    let fileName: String?

    func validate(requestID: String) throws {
        guard protocolVersion == 1, requestId == requestID,
              ["ready", "absent", "authRequired", "rateLimited", "unresolved", "unsupported", "unavailable"].contains(status),
              status != "ready" || fileName == "visual.mp4" else { throw VisualProviderFailure.invalid }
    }
}
enum VisualProviderFailure: Error { case invalid, unavailable, cancelled, credential }
extension Notification.Name {
    static let visualProviderWillChange = Notification.Name("sideb.visualProvider.willChange")
}
