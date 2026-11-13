import Foundation
import Observation
import WebKit

/// A stored web login that is renewed silently: it owns the keychain item, the "saved at" timestamp,
/// the in-memory copy, silent renewal and (when it has a fixed auth configuration) the interactive login.
/// Consumers (the Canvas provider host, the Jam) borrow the credential; none of them owns it.
@MainActor @Observable
final class CredentialSession {
    enum Event { case signedIn, signedOut, renewed }

    /// Whether a credential is stored. Observable: UI follows sign-in/out from any consumer.
    private(set) var hasCredential: Bool
    /// The last interactive login produced a token that could not be stored.
    private(set) var loginFailed = false

    /// Web Player tokens last about an hour; renew quietly before that instead of failing a request first.
    static let maxCredentialAge: TimeInterval = 50 * 60

    @ObservationIgnored private let credentials: any VisualProviderCredentials
    @ObservationIgnored private let tokenSource: any VisualProviderTokenSource
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let savedAtKey: String
    @ObservationIgnored private let fixedAuth: VisualProviderAuth?
    @ObservationIgnored private let webSessionCleaner: () async -> Void
    @ObservationIgnored private var cached: String?
    @ObservationIgnored private var readAttempted = false
    /// The last token a consumer reported as refused. A "new" token equal to it is not a recovery.
    @ObservationIgnored private var rejected: String?
    @ObservationIgnored private var nextProactiveRefresh = Date.distantPast
    @ObservationIgnored private var recoveryTask: Task<String?, Never>?
    /// Bumped by sign-in/out so a renewal that finishes afterwards cannot resurrect an old session.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var subscribers: [UUID: (Event) -> Bool] = [:]

    init(credentials: any VisualProviderCredentials, tokenSource: any VisualProviderTokenSource, preferences: UserDefaults,
         savedAtKey: String, auth: VisualProviderAuth? = nil, webSessionCleaner: @escaping () async -> Void = {}) {
        self.credentials = credentials
        self.tokenSource = tokenSource
        self.preferences = preferences
        self.savedAtKey = savedAtKey
        self.fixedAuth = auth
        self.webSessionCleaner = webSessionCleaner
        hasCredential = credentials.exists
    }

    /// Calls `handler` synchronously for each event until it returns false (its owner is gone).
    func subscribe(_ handler: @escaping (Event) -> Bool) {
        subscribers[UUID()] = handler
    }
    private func emit(_ event: Event) {
        for (id, handler) in subscribers where !handler(event) { subscribers[id] = nil }
    }

    private func loadIfNeeded() {
        guard !readAttempted else { return }
        cached = credentials.read()
        readAttempted = true
        if cached == nil { hasCredential = false }
    }

    /// The stored token, read from the keychain once and then kept in memory (FIX-310).
    func currentCredential() -> String? {
        loadIfNeeded()
        return cached
    }

    /// A working credential for a consumer that is not the provider itself (the Jam). Never prompts: without a
    /// stored login it returns nil instead of silently signing in again.
    func credential(forceRenew: Bool = false, auth: VisualProviderAuth? = nil) async -> String? {
        loadIfNeeded()
        guard hasCredential else { return nil }
        if forceRenew { return await recover(auth: auth) }
        await refreshIfStale(auth: auth)
        return cached
    }

    func noteRejected(_ token: String) { rejected = token }

    /// Replaces the stored token with the result of the interactive login or a pasted token.
    func save(_ value: String) throws {
        let token = Self.sanitized(value)
        guard let token else { throw VisualProviderFailure.credential }
        try credentials.save(token)
        store(token)
        loginFailed = false
        generation &+= 1
        emit(.signedIn)
    }

    /// Clears the stored login and, when the session owns a web login, the web session that could renew it.
    func signOut() async throws {
        recoveryTask?.cancel(); recoveryTask = nil
        generation &+= 1
        try credentials.delete()
        cached = nil
        readAttempted = true
        rejected = nil
        nextProactiveRefresh = .distantPast
        preferences.removeObject(forKey: savedAtKey)
        hasCredential = false
        loginFailed = false
        emit(.signedOut)
        await webSessionCleaner()
    }

    /// One recovery at a time: concurrent requests share the same web view attempt.
    @discardableResult
    func recover(auth: VisualProviderAuth? = nil) async -> String? {
        guard let auth = fixedAuth ?? auth, auth.type == "webview" else { return nil }
        if let running = recoveryTask { return await running.value }
        let rejectedToken = rejected
        let started = generation
        let source = tokenSource
        let task = Task { @MainActor [weak self] () -> String? in
            let token = await source.acquire(auth: auth, rejecting: rejectedToken)
            guard let self else { return nil }
            self.recoveryTask = nil
            guard !Task.isCancelled, started == self.generation, let token, token != rejectedToken,
                  let clean = Self.sanitized(token), (try? self.credentials.save(clean)) != nil else { return nil }
            self.store(clean)
            self.emit(.renewed)
            return clean
        }
        recoveryTask = task
        return await task.value
    }

    /// Renews quietly once the stored token is old. A failure is retried later, not on every request.
    func refreshIfStale(auth: VisualProviderAuth? = nil) async {
        guard hasCredential, Date() >= nextProactiveRefresh,
              let savedAt = preferences.object(forKey: savedAtKey) as? Date,
              Date().timeIntervalSince(savedAt) > Self.maxCredentialAge else { return }
        nextProactiveRefresh = Date().addingTimeInterval(300)
        _ = await recover(auth: auth)
    }

    /// The interactive login (a window with the provider's own login page). Needs a fixed auth configuration.
    func signIn(providerName: String) {
        guard let auth = fixedAuth else { return }
        loginFailed = false
        VisualProviderLoginWindowManager.shared.show(auth: auth, providerName: providerName) { [weak self] token in
            guard let self else { return }
            do { try self.save(token) } catch { self.loginFailed = true }
        }
    }

    private func store(_ token: String) {
        cached = token
        readAttempted = true
        rejected = nil
        preferences.set(Date(), forKey: savedAtKey)
        hasCredential = true
    }

    private static func sanitized(_ value: String) -> String? {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= 8192, token.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return nil }
        return token
    }
}

/// The Spotify Web Player session: a host-level concept shared by every feature that talks to Spotify
/// (Spotify Canvas, Spotify Jam). It does not depend on any plugin being installed or enabled.
enum SpotifySession {
    /// Same values the Spotify Canvas manifest declares (`extensions/spotify-canvas/package/manifest.*.json`).
    nonisolated static let auth = VisualProviderAuth(
        type: "webview",
        loginUrl: "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F",
        targetHost: "open.spotify.com",
        tokenUrl: "https://open.spotify.com/get_access_token?reason=transport&productType=web_player")
    nonisolated static let displayName = "Spotify"
    /// Same "saved at" key the Canvas host has always used, so an existing login keeps its age.
    nonisolated static let savedAtKey = "sideb.visualProvider.credentialSavedAt.v1"

    /// The single instance of the app: the pre-existing keychain item, so earlier sign-ins are kept.
    @MainActor static let shared = CredentialSession(
        credentials: KeychainVisualProviderCredentials(), tokenSource: WebViewVisualProviderTokenSource(),
        preferences: HomeAppearance.preferences, savedAtKey: savedAtKey, auth: auth,
        webSessionCleaner: clearWebSession)

    /// Whether a provider's auth descriptor is Spotify's Web Player login. Only then does it use the shared session.
    nonisolated static func matches(_ candidate: VisualProviderAuth?) -> Bool {
        guard let candidate, candidate.type == auth.type,
              candidate.targetHost == auth.targetHost,
              URL(string: candidate.tokenUrl)?.host == URL(string: auth.tokenUrl)?.host,
              let loginHost = URL(string: candidate.loginUrl)?.host,
              loginHost == "spotify.com" || loginHost.hasSuffix(".spotify.com") else { return false }
        return true
    }

    /// Without the web cookies the silent renewal would just sign the user in again.
    @MainActor private static func clearWebSession() async {
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let spotify = records.filter { $0.displayName.lowercased().contains("spotify") }
        guard !spotify.isEmpty else { return }
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: spotify)
    }
}
