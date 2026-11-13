import Foundation
import Security

@MainActor protocol VisualProviderCredentials {
    var exists: Bool { get }
    func read() -> String?
    func save(_ value: String) throws
    func delete() throws
}

/// A separate namespace with no plaintext or YTM-session fallback. The default account is the one
/// item that has always held the Spotify session (see `SpotifySession`); never rename it.
@MainActor final class KeychainVisualProviderCredentials: VisualProviderCredentials {
    nonisolated static let spotifyAccount = "visual-provider"
    /// Token of a provider whose login is not Spotify's. It never shares the Spotify item.
    nonisolated static let otherProviderAccount = "visual-provider.other"
    private let account: String
    init(account: String = KeychainVisualProviderCredentials.spotifyAccount) { self.account = account }
    private var query: [String: Any] {
        [kSecClass as String:kSecClassGenericPassword,
         kSecAttrService as String:"\(HomeLabConfiguration.enabled ? "com.fefucho.SideB.HomeLab" : "com.fefucho.SideB").visual-provider",
         kSecAttrAccount as String:account]
    }
    var exists: Bool {
        var q = query; q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }
    func read() -> String? {
        var q = query; q[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func save(_ value: String) throws {
        let attrs: [String: Any] = [kSecValueData as String:Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = Data(value.utf8)
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw VisualProviderFailure.credential }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VisualProviderFailure.credential }
    }
}
