import Foundation
import Security
import CryptoKit

/// Maneja el guardado de la cookie de sesión (un String)
/// siguiendo las reglas del AGENTS.md (Keychain en release/production, Archivo en debug local).
@MainActor
final class CookieStorage {
    private let servicePrefix = HomeLabConfiguration.enabled
        ? "com.fefucho.SideB.HomeLab.auth" : "com.fefucho.SideB.auth"
    private let cookieKey = "sessionCookie"

    private var shouldUseKeychain: Bool {
        #if DEBUG
            return ProcessInfo.processInfo.environment["SIDEB_DEBUG_COOKIE_STORAGE"] != "file"
        #else
            return true
        #endif
    }

    private var debugFileUrl: URL? {
        let dir = HomeLabConfiguration.appSupportURL
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("cookies.dat")
    }

    /// Sanea una cadena de cookies deduplicando pares clave-valor (priorizando los de YouTube)
    /// y eliminando cookies exclusivas de Google Accounts que rompen la autenticación de YouTube Music.
    static func sanitizeCookieString(_ raw: String) -> String {
        let excludedGoogleKeys: Set<String> = [
            "NID", "ACCOUNT_CHOOSER", "SMSV", "__Host-GAPS", "OTZ", "LSID", "__Host-1PLSID", "__Host-3PLSID"
        ]
        let parts = raw.components(separatedBy: ";")
        var cookieDict: [String: String] = [:]

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eqIdx])
            let value = String(trimmed[trimmed.index(after: eqIdx)...])

            if excludedGoogleKeys.contains(key) {
                continue
            }
            // Al sobreescribir secuencialmente, la última ocurrencia (que proviene de YouTube) prevalece
            cookieDict[key] = value
        }

        return cookieDict.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    func saveSessionCookie(_ cookie: String) throws {
        let sanitized = Self.sanitizeCookieString(cookie)
        if self.shouldUseKeychain {
            do {
                try self.saveToKeychain(key: self.cookieKey, value: sanitized)
                return
            } catch {
                print("[CookieStorage] Keychain save failed: \(error). Using protected file storage as fallback.")
            }
        }
        try self.saveToFile(sanitized)
    }

    func getSessionCookie() -> String? {
        var rawCookie: String?
        if self.shouldUseKeychain {
            if let value = self.getFromKeychain(key: self.cookieKey), !value.isEmpty {
                rawCookie = value
            }
        }
        if rawCookie == nil {
            rawCookie = self.getFromFile()
        }

        guard let cookie = rawCookie, !cookie.isEmpty else { return nil }
        let sanitized = Self.sanitizeCookieString(cookie)

        // Si la cookie contenía duplicados o basura de Google, actualizamos el almacenamiento con la versión limpia
        if sanitized != cookie {
            try? self.saveSessionCookie(sanitized)
        }

        return sanitized
    }

    /// Clave de caché estable para la sesión, sin guardar la cookie en el feed.
    func homeCacheIdentity() -> String {
        guard let cookie = getSessionCookie(), !cookie.isEmpty else { return "guest" }
        let canonical = cookie.components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: ";")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Account-bound identity for playback guards; reads credentials without rewriting them.
    func playbackCacheIdentity() -> String {
        let raw = (shouldUseKeychain ? getFromKeychain(key: cookieKey) : nil) ?? getFromFile()
        return Self.playbackFingerprint(forCookieString: raw)
    }

    func legacyPlaybackCacheIdentity() -> String {
        guard let raw = (shouldUseKeychain ? getFromKeychain(key: cookieKey) : nil) ?? getFromFile(), !raw.isEmpty else { return "guest" }
        let canonical = Self.sanitizeCookieString(raw).split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.sorted().joined(separator: ";")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func playbackFingerprint(forCookieString raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "guest" }
        let pairs = raw.split(separator: ";").compactMap { part -> (String,String)? in
            let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let split = value.firstIndex(of: "=") else { return nil }
            return (String(value[..<split]), String(value[value.index(after: split)...]))
        }
        let values = Dictionary(pairs, uniquingKeysWith: { _, last in last })
        let token = ["SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID"].compactMap { values[$0] }.first
        let canonical = token ?? pairs.map { $0.0 + "=" + $0.1 }.sorted().joined(separator: ";")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func removeSessionCookie() {
        self.deleteFromKeychain(key: self.cookieKey)
        if let url = self.debugFileUrl {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - File Storage (Sandbox-safe for local dev)

    private func saveToFile(_ cookie: String) throws {
        guard let url = self.debugFileUrl else { return }
        try cookie.write(to: url, atomically: true, encoding: .utf8)
    }

    private func getFromFile() -> String? {
        guard let url = self.debugFileUrl else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Keychain Storage

    private func saveToKeychain(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw CookieStorageError.encodingFailed
        }

        let account = "\(self.servicePrefix).\(key)"

        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: self.servicePrefix,
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrLabel as String: "Side B",
            kSecAttrDescription as String: "Sesión de Side B (YouTube Music)",
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = updateQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            addQuery[kSecAttrLabel as String] = "Side B"
            addQuery[kSecAttrDescription as String] = "Sesión de Side B (YouTube Music)"

            #if os(macOS)
            var access: SecAccess?
            if SecAccessCreate("Side B" as CFString, nil, &access) == errSecSuccess, let access {
                addQuery[kSecAttrAccess as String] = access
            }
            #endif

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CookieStorageError.saveFailed(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CookieStorageError.saveFailed(status: updateStatus)
        }
    }

    private func getFromKeychain(key: String) -> String? {
        let account = "\(self.servicePrefix).\(key)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: self.servicePrefix,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    private func deleteFromKeychain(key: String) {
        let account = "\(self.servicePrefix).\(key)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: self.servicePrefix,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

enum CookieStorageError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Failed to encode cookie for storage."
        case let .saveFailed(status):
            "Storage save failed with status: \(status)"
        }
    }
}
