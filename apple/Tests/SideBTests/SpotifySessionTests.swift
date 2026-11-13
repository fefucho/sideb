import Foundation
import Testing
import SideBCore
@testable import SideB

@MainActor private final class MemoryCredentials: VisualProviderCredentials {
    var value: String?
    var exists: Bool { value != nil }
    func read() -> String? { value }
    func save(_ value: String) throws { self.value = value }
    func delete() throws { value = nil }
}

@MainActor private final class ScriptedTokens: VisualProviderTokenSource {
    var tokens: [String?]
    var calls = 0
    var delay: Duration = .zero
    init(_ tokens: [String?] = []) { self.tokens = tokens }
    func acquire(auth: VisualProviderAuth, rejecting rejected: String?) async -> String? {
        calls += 1
        if delay > .zero { try? await Task.sleep(for: delay) }
        return tokens.isEmpty ? nil : tokens.removeFirst()
    }
}

@MainActor private final class Fixture {
    let dir: URL
    let spotifyCredentials = MemoryCredentials()
    let spotifyTokens = ScriptedTokens()
    let ownCredentials = MemoryCredentials()
    let ownTokens = ScriptedTokens()
    let session: CredentialSession
    var cleaned = 0
    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sideb-spotify-session-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let box = CleanCounter()
        counter = box
        session = CredentialSession(credentials: spotifyCredentials, tokenSource: spotifyTokens,
                                    preferences: UserDefaults(suiteName: "SpotifySessionTests.\(UUID())")!,
                                    savedAtKey: "saved", auth: SpotifySession.auth, webSessionCleaner: { box.count += 1 })
    }
    let counter: CleanCounter
    deinit { try? FileManager.default.removeItem(at: dir) }

    func host(bundled: URL? = nil) -> VisualProviderHost {
        VisualProviderHost(root: dir.appendingPathComponent("host"), preferences: UserDefaults(suiteName: "SpotifySessionTests.\(UUID())")!,
                           credentials: ownCredentials, tokenSource: ownTokens, spotifySession: session)
    }

    /// A worker that answers `absent` only for `accepted`, so it shows which credential the host handed over.
    func install(into host: VisualProviderHost, auth: VisualProviderAuth?, accepted: String) async throws {
        let package = dir.appendingPathComponent("package-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        let manifest = VisualProviderManifest(protocolVersion: 1, id: "fixture", name: "Fixture", version: "1", executable: "worker", credentialLabel: "Token", auth: auth)
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
        let script = "#!/usr/bin/python3\nimport json,sys\nr=json.load(sys.stdin)\nprint(json.dumps({'protocolVersion':1,'requestId':r['requestId'],'status':'absent' if r['credential']=='\(accepted)' else 'authRequired'}))\n"
        try Data(script.utf8).write(to: package.appendingPathComponent("worker"))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: package.appendingPathComponent("worker").path)
        try await host.install(from: package)
    }
}
@MainActor private final class CleanCounter { var count = 0 }

@MainActor @Suite(.serialized) struct SpotifySessionTests {
    private let otherAuth = VisualProviderAuth(type: "webview", loginUrl: "https://example.com/login", targetHost: "example.com", tokenUrl: "https://example.com/token")
    private func track() -> SongItemRecord {
        SongItemRecord(videoId: "t", title: "Song", artists: "Artist", album: "Album", duration: "3:00", thumbnail: nil,
            artistId: nil, albumId: "a", setVideoId: nil, isVideo: false, isUpload: false, library: nil)
    }

    @Test func theSessionWorksWithNoProviderInstalled() async throws {
        let f = try Fixture()
        let host = f.host()
        #expect(host.manifest == nil && !host.hasCredential)
        #expect(await f.session.credential() == nil, "Without a stored login nothing is renewed behind the user's back")
        #expect(f.spotifyTokens.calls == 0)
        try f.session.save("spotify-token")
        #expect(f.session.hasCredential && f.spotifyCredentials.value == "spotify-token")
        #expect(await f.session.credential() == "spotify-token")
        f.spotifyTokens.tokens = ["renewed"]
        #expect(await f.session.credential(forceRenew: true) == "renewed")
        #expect(f.spotifyCredentials.value == "renewed")
    }

    @Test func aStoredSpotifyLoginIsFoundByTheCanvasProviderWithoutAskingAgain() async throws {
        let f = try Fixture()
        try f.session.save("spotify-token")
        let host = f.host()
        try await f.install(into: host, auth: SpotifySession.auth, accepted: "spotify-token")
        #expect(host.hasCredential && host.usesSpotifySession && host.statusKey == "visualProvider.status.idle")
        host.enabled = true
        #expect(try await host.prepare(track: track(), duration: 180, requestID: "one") == nil)
        #expect(host.statusKey == "visualProvider.status.absent", "The provider received the shared Spotify token")
    }

    @Test func uninstallingCanvasKeepsTheSpotifySession() async throws {
        let f = try Fixture()
        let host = f.host()
        try await f.install(into: host, auth: SpotifySession.auth, accepted: "x")
        try host.saveCredential("spotify-token")
        #expect(f.spotifyCredentials.value == "spotify-token" && f.ownCredentials.value == nil, "A Spotify login lands in the Spotify item")
        try await host.uninstall()
        #expect(host.manifest == nil)
        #expect(f.session.hasCredential && f.spotifyCredentials.value == "spotify-token")
        #expect(await f.session.credential() == "spotify-token")
        #expect(f.counter.count == 0, "Uninstalling does not clear the web session either")
    }

    @Test func enablingOrDisablingCanvasNeverTouchesTheSession() async throws {
        let f = try Fixture()
        let host = f.host()
        try await f.install(into: host, auth: SpotifySession.auth, accepted: "x")
        try host.saveCredential("spotify-token")
        host.enabled = true; host.enabled = false
        let kept = await f.session.credential()
        #expect(f.session.hasCredential && kept == "spotify-token")
        #expect(f.spotifyTokens.calls == 0)
    }

    @Test func signingOutClearsTheSessionForCanvasAndTheJam() async throws {
        let f = try Fixture()
        let host = f.host()
        try await f.install(into: host, auth: SpotifySession.auth, accepted: "spotify-token")
        try f.session.save("spotify-token")
        host.enabled = true
        let revision = host.revision
        try await host.signOutOfSpotify()
        #expect(!f.session.hasCredential && f.spotifyCredentials.value == nil)
        #expect(!host.hasCredential && host.identitySalt == nil && host.statusKey == "visualProvider.status.tokenRequired")
        #expect(host.revision != revision, "Canvas consumers are told the credential is gone")
        let afterSignOut = await f.session.credential()
        #expect(afterSignOut == nil && f.spotifyTokens.calls == 0)
        #expect(f.counter.count == 1, "The web session is cleared so it cannot silently sign in again")
        #expect(try await host.prepare(track: track(), duration: 180, requestID: "one") == nil)
    }

    @Test func signingInAgainFromAnywhereReachesTheCanvasProvider() async throws {
        let f = try Fixture()
        let host = f.host()
        try await f.install(into: host, auth: SpotifySession.auth, accepted: "new")
        #expect(!host.hasCredential && host.statusKey == "visualProvider.status.tokenRequired")
        try f.session.save("new") // e.g. the Jam panel's sign-in
        #expect(host.hasCredential && host.statusKey == "visualProvider.status.idle")
    }

    @Test func aProviderWithAnotherLoginNeverReceivesTheSpotifyCredential() async throws {
        let f = try Fixture()
        try f.session.save("spotify-token")
        let host = f.host()
        try await f.install(into: host, auth: otherAuth, accepted: "spotify-token")
        #expect(!host.usesSpotifySession && !host.hasCredential, "Spotify's login does not count as the provider's")
        host.enabled = false
        #expect(try await host.prepare(track: track(), duration: 180, requestID: "one") == nil)
        #expect(host.statusKey != "visualProvider.status.absent")
        try host.saveCredential("own-token")
        #expect(f.ownCredentials.value == "own-token" && f.spotifyCredentials.value == "spotify-token")
        // Its renewal uses its own session and token source, and never overwrites Spotify's.
        f.ownTokens.tokens = ["own-renewed"]
        #expect(await host.recoverCredential() == "own-renewed")
        #expect(f.spotifyCredentials.value == "spotify-token" && f.spotifyTokens.calls == 0)
        // Uninstalling it removes its own token and leaves Spotify's.
        try await host.uninstall()
        #expect(f.ownCredentials.value == nil && f.spotifyCredentials.value == "spotify-token")
    }

    @Test func installingAnotherProviderDoesNotSignOutOfSpotify() async throws {
        let f = try Fixture()
        try f.session.save("spotify-token")
        let host = f.host()
        try await f.install(into: host, auth: otherAuth, accepted: "x")
        #expect(f.spotifyCredentials.value == "spotify-token" && f.counter.count == 0)
    }

    @Test func aRenewalFinishingAfterSignOutDoesNotBringTheSessionBack() async throws {
        let f = try Fixture()
        try f.session.save("spotify-token")
        f.spotifyTokens.tokens = ["late"]
        f.spotifyTokens.delay = .milliseconds(150)
        async let renewal = f.session.credential(forceRenew: true)
        try await Task.sleep(for: .milliseconds(30))
        try await f.session.signOut()
        #expect(await renewal == nil)
        #expect(!f.session.hasCredential && f.spotifyCredentials.value == nil)
    }

    @Test func onlySpotifyWebPlayerAuthSharesTheSession() throws {
        #expect(SpotifySession.matches(SpotifySession.auth))
        #expect(!SpotifySession.matches(nil) && !SpotifySession.matches(otherAuth))
        let lookalike = VisualProviderAuth(type: "webview", loginUrl: "https://accounts.spotify.com.evil.example/login", targetHost: "open.spotify.com", tokenUrl: SpotifySession.auth.tokenUrl)
        #expect(!SpotifySession.matches(lookalike))
        let otherHost = VisualProviderAuth(type: "webview", loginUrl: SpotifySession.auth.loginUrl, targetHost: "open.spotify.com.evil.example", tokenUrl: SpotifySession.auth.tokenUrl)
        #expect(!SpotifySession.matches(otherHost))
    }

    @Test func theBuiltInAuthMatchesTheCanvasManifest() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("extensions/spotify-canvas/package/manifest.macos-arm64.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let manifest = try JSONDecoder().decode(VisualProviderManifest.self, from: Data(contentsOf: url))
        #expect(manifest.auth == SpotifySession.auth && SpotifySession.matches(manifest.auth))
    }

    @Test func keychainItemsAreSeparateAndTheSpotifyOneKeepsItsName() {
        #expect(KeychainVisualProviderCredentials.spotifyAccount == "visual-provider", "Existing users stay signed in")
        #expect(KeychainVisualProviderCredentials.otherProviderAccount != KeychainVisualProviderCredentials.spotifyAccount)
    }
}
