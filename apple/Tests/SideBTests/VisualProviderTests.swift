import Foundation
import Testing
import SideBCore
@testable import SideB

@MainActor private final class MemoryVisualCredentials: VisualProviderCredentials {
    var value: String?
    var reads = 0
    var exists: Bool { value != nil }
    func read() -> String? { reads += 1; return value }
    func save(_ value: String) throws { self.value = value }
    func delete() throws { value = nil }
}

@MainActor private final class FakeTokenSource: VisualProviderTokenSource {
    var tokens: [String?]
    var calls: [String?] = []
    var delay: Duration = .zero
    init(_ tokens: [String?]) { self.tokens = tokens }
    func acquire(auth: VisualProviderAuth, rejecting rejected: String?) async -> String? {
        calls.append(rejected)
        if delay > .zero { try? await Task.sleep(for: delay) }
        return tokens.isEmpty ? nil : tokens.removeFirst()
    }
}

@MainActor @Suite(.serialized) struct VisualProviderTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sideb-visual-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }
    private func track(_ id: String = "track") -> SongItemRecord {
        SongItemRecord(videoId: id, title: "Song", artists: "Artist", album: "Album", duration: "3:00", thumbnail: nil,
            artistId: nil, albumId: "same-album", setVideoId: nil, isVideo: false, isUpload: false, library: nil)
    }
    private let fixtureAuth = VisualProviderAuth(type: "webview", loginUrl: "https://example.com/login", targetHost: "example.com", tokenUrl: "https://example.com/token")
    /// `acceptedToken`: the worker answers `absent` only for that credential and `authRequired` otherwise.
    private func package(at directory: URL, status: String, acceptedToken: String? = nil, auth: VisualProviderAuth? = nil, id: String = "fixture", version: String = "1", platform: String? = nil) throws {
        let manifest = VisualProviderManifest(protocolVersion: 1, id: id, name: "Fixture", version: version, executable: "worker", credentialLabel: "Token", auth: auth, platform: platform)
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
        let statusExpression = acceptedToken.map { "'absent' if r['credential']=='\($0)' else 'authRequired'" } ?? "'\(status)'"
        let script = "#!/usr/bin/python3\nimport json,sys\nr=json.load(sys.stdin)\nprint(json.dumps({'protocolVersion':1,'requestId':r['requestId'],'status':\(statusExpression)}))\n"
        try Data(script.utf8).write(to: directory.appendingPathComponent("worker"))
        try FileManager.default.setAttributes([.posixPermissions:0o700], ofItemAtPath: directory.appendingPathComponent("worker").path)
    }

    @Test func appleWinsAndFullscreenNeverCallsTheOptionalProvider() async throws {
        let apple = AnimatedArtworkAsset(assetId: "apple", localPath: "/fixture", codec: "h264", width: 100, height: 100, frameRate: 30, sizeBytes: 1)
        var secondaryCalls = 0
        let first = try await VisualProviderRouting.resolve(verticalPlayer: true, extensionEnabled: true, primary: { apple }, secondary: { secondaryCalls += 1; return nil })
        #expect(first?.assetId == "apple" && secondaryCalls == 0)
        _ = try await VisualProviderRouting.resolve(verticalPlayer: false, extensionEnabled: true, primary: { nil }, secondary: { secondaryCalls += 1; return nil })
        #expect(secondaryCalls == 0)
        _ = try await VisualProviderRouting.resolve(verticalPlayer: true, extensionEnabled: false, primary: { nil }, secondary: { secondaryCalls += 1; return nil })
        #expect(secondaryCalls == 0)
        _ = try await VisualProviderRouting.resolve(verticalPlayer: true, extensionEnabled: true, primary: { nil }, secondary: { secondaryCalls += 1; return nil })
        #expect(secondaryCalls == 1)
        _ = try await VisualProviderRouting.resolve(verticalPlayer: true, extensionEnabled: true, primary: { throw VisualProviderFailure.unavailable }, secondary: { secondaryCalls += 1; return nil })
        #expect(secondaryCalls == 2)
    }

    @Test func cancellationOfAppleMustNotStartTheFallback() async throws {
        var secondaryCalled = false
        let task = Task {
            try await VisualProviderRouting.resolve(verticalPlayer: true, extensionEnabled: true, primary: {
                try await Task.sleep(for: .seconds(60)); return nil
            }, secondary: { secondaryCalled = true; return nil })
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled routing returned a result") } catch {}
        #expect(!secondaryCalled)
    }

    @Test func noProviderMeansNoCredentialAccessOrFilesystemWrites() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: "VisualProviderTests.\(UUID())")!
        let credentials = MemoryVisualCredentials()
        let root = dir.appendingPathComponent("host")
        let host = VisualProviderHost(root: root, preferences: defaults, credentials: credentials)
        #expect(!host.enabled && host.manifest == nil)
        #expect(try await host.prepare(track: track(), duration: 180, requestID: "one") == nil)
        #expect(credentials.reads == 0)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func installIsOptInAndExpiredSessionStopsRequestsUntilReplaced() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try package(at: source, status: "authRequired")
        let defaults = UserDefaults(suiteName: "VisualProviderTests.\(UUID())")!
        let credentials = MemoryVisualCredentials()
        let host = VisualProviderHost(root: dir.appendingPathComponent("host"), preferences: defaults, credentials: credentials)
        try await host.install(from: source)
        #expect(!host.enabled && !host.hasCredential)
        try host.saveCredential("fixture-secret")
        host.enabled = true
        let salt = host.identitySalt
        #expect(try await host.prepare(track: track(), duration: 180, requestID: "one") == nil)
        #expect(host.statusKey == "visualProvider.status.authRequired")
        #expect(try await host.prepare(track: track("two"), duration: 180, requestID: "two") == nil)
        #expect(credentials.reads == 0, "A freshly saved credential is reused from memory across track changes")
        try host.saveCredential("replacement")
        #expect(host.identitySalt != salt)
        try await host.uninstall()
        #expect(credentials.value == nil && !host.enabled && host.manifest == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("host/Installed").path))
    }

    @Test func protocolRejectsTraversalAndNeverAcceptsErrorsAsReady() throws {
        for name in ["../worker", "/bin/sh", "a/b", "..", ""] {
            #expect(throws: (any Error).self) {
                try VisualProviderManifest(protocolVersion: 1, id: "provider", name: "Provider", version: "1", executable: name, credentialLabel: "Token").validate()
            }
        }
        for json in [
            #"{"protocolVersion":2,"requestId":"r","status":"ready","fileName":"visual.mp4"}"#,
            #"{"protocolVersion":1,"requestId":"old","status":"ready","fileName":"visual.mp4"}"#,
            #"{"protocolVersion":1,"requestId":"r","status":"ready","fileName":"../visual.mp4"}"#,
            #"{"protocolVersion":1,"requestId":"r","status":"anything"}"#
        ] {
            let reply = try JSONDecoder().decode(VisualProviderReply.self, from: Data(json.utf8))
            #expect(throws: (any Error).self) { try reply.validate(requestID: "r") }
        }
    }

    @Test func authValidationAndDecoding() throws {
        let validAuth = VisualProviderAuth(type: "webview", loginUrl: "https://example.com/login", targetHost: "example.com", tokenUrl: "https://example.com/token")
        #expect(throws: Never.self) { try validAuth.validate() }

        let invalidAuthType = VisualProviderAuth(type: "oauth", loginUrl: "https://example.com/login", targetHost: "example.com", tokenUrl: "https://example.com/token")
        #expect(throws: (any Error).self) { try invalidAuthType.validate() }

        let invalidAuthUrl = VisualProviderAuth(type: "webview", loginUrl: "http://insecure.com/login", targetHost: "insecure.com", tokenUrl: "https://insecure.com/token")
        #expect(throws: (any Error).self) { try invalidAuthUrl.validate() }

        let manifestWithAuth = VisualProviderManifest(protocolVersion: 1, id: "provider", name: "Provider", version: "1", executable: "worker", credentialLabel: "Token", auth: validAuth)
        #expect(throws: Never.self) { try manifestWithAuth.validate() }

        let data = try JSONEncoder().encode(manifestWithAuth)
        let decoded = try JSONDecoder().decode(VisualProviderManifest.self, from: data)
        #expect(decoded.auth == validAuth)
    }

    @Test func pluginIdentityIsPerTrackAndTheExistingAlbumIdentityIsPreserved() {
        let session = UUID()
        #expect(AnimatedArtworkIdentity(track: track("a"), sessionID: session) == AnimatedArtworkIdentity(track: track("b"), sessionID: session))
        #expect(AnimatedArtworkIdentity(track: track("a"), sessionID: session, visualProviderSalt: "p:1") != AnimatedArtworkIdentity(track: track("b"), sessionID: session, visualProviderSalt: "p:1"))
        #expect(AnimatedArtworkIdentity(track: track(), sessionID: session, visualProviderSalt: "p:1") != AnimatedArtworkIdentity(track: track(), sessionID: session, visualProviderSalt: "p:2"))
        #expect(VisualProviderHost.validDimensions(CGSize(width:405,height:720), fps:30))
        #expect(VisualProviderHost.validDimensions(CGSize(width:720,height:1280), fps:23.976))
        #expect(VisualProviderHost.validDimensions(CGSize(width:1080,height:1920), fps:30))
        #expect(!VisualProviderHost.validDimensions(CGSize(width:1080,height:1921), fps:30))
        #expect(!VisualProviderHost.validDimensions(CGSize(width:720,height:720), fps:30))
    }

    @Test func cancellationWaitsForProcessExitBeforeRemovingItsPrivateDirectory() async throws {
        let dir = try directory()
        let script = dir.appendingPathComponent("wait")
        try Data("#!/bin/sh\nexec /bin/sleep 60\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions:0o700], ofItemAtPath: script.path)
        let job = VisualProviderJob(directory: dir)
        let task = Task.detached { try job.run(executable: script, input: Data()) }
        try await Task.sleep(for: .milliseconds(100))
        job.cancel()
        do { _ = try await task.value; Issue.record("Cancelled provider returned a result") } catch {}
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func stdoutLimitTerminatesAProviderThatKeepsWriting() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let job = VisualProviderJob(directory: dir)
        do {
            _ = try await Task.detached { try job.run(executable: URL(fileURLWithPath:"/usr/bin/yes"), input: Data()) }.value
            Issue.record("Unbounded provider output was accepted")
        } catch {}
        job.cancel()
    }

    @Test func visualProviderCacheSizeAndClear() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: "VisualProviderTests.\(UUID())")!
        let credentials = MemoryVisualCredentials()
        let root = dir.appendingPathComponent("host")
        let host = VisualProviderHost(root: root, preferences: defaults, credentials: credentials)

        let initialSize = await host.cacheSize()
        #expect(initialSize == 0)

        // Populate a fake cached file in Cache/fixture/test.mp4
        let cacheFolder = root.appendingPathComponent("Cache/fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        let fakeData = Data(repeating: 42, count: 1024)
        try fakeData.write(to: cacheFolder.appendingPathComponent("test.mp4"))

        let populatedSize = await host.cacheSize()
        #expect(populatedSize == 1024)

        let clearedSize = await host.clearCache()
        #expect(clearedSize == 1024)
        #expect(await host.cacheSize() == 0)
    }

    private func installedHost(_ dir: URL, source: FakeTokenSource, acceptedToken: String?) async throws -> (VisualProviderHost, MemoryVisualCredentials) {
        let package = dir.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        try self.package(at: package, status: "authRequired", acceptedToken: acceptedToken, auth: fixtureAuth)
        let credentials = MemoryVisualCredentials()
        let host = VisualProviderHost(root: dir.appendingPathComponent("host"), preferences: UserDefaults(suiteName: "VisualProviderTests.\(UUID())")!,
                                      credentials: credentials, tokenSource: source)
        try await host.install(from: package)
        try host.saveCredential("old")
        host.enabled = true
        return (host, credentials)
    }

    @Test func rejectedTokenIsReplacedInTheBackgroundAndTheRequestRetried() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = FakeTokenSource(["fresh"])
        let (host, credentials) = try await installedHost(dir, source: source, acceptedToken: "fresh")
        let revision = host.revision
        #expect(try await host.prepare(track: track(), duration: 180, requestID: "one") == nil)
        #expect(source.calls == ["old"], "The refused token is passed so it can never be returned again")
        #expect(credentials.value == "fresh")
        #expect(host.statusKey == "visualProvider.status.absent")
        #expect(host.revision == revision, "A silent renewal must not detach running players")
        // Next track uses the new token without another renewal.
        #expect(try await host.prepare(track: track("two"), duration: 180, requestID: "two") == nil)
        #expect(source.calls.count == 1)
    }

    @Test func recoveryReturningTheSameRejectedTokenKeepsTheProviderBlockedUntilSomethingWorks() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = FakeTokenSource(["old", nil])
        let (host, credentials) = try await installedHost(dir, source: source, acceptedToken: "fresh")
        #expect(try await host.prepare(track: track(), duration: 180, requestID: "one") == nil)
        #expect(host.statusKey == "visualProvider.status.authRequired")
        #expect(credentials.value == "old")
        let reads = source.calls.count
        #expect(try await host.prepare(track: track("two"), duration: 180, requestID: "two") == nil)
        #expect(source.calls.count == reads, "A blocked provider does not hammer the web view per track")
        // A later background pass that finds a working token unblocks it and makes consumers re-query.
        source.tokens = ["fresh"]
        let revision = host.revision
        #expect(await host.recoverCredential() == "fresh")
        #expect(host.revision != revision)
        #expect(try await host.prepare(track: track("three"), duration: 180, requestID: "three") == nil)
        #expect(host.statusKey == "visualProvider.status.absent")
    }

    @Test func concurrentRecoveriesShareOneWebViewAttempt() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = FakeTokenSource(["fresh", "other"])
        source.delay = .milliseconds(150)
        let (host, _) = try await installedHost(dir, source: source, acceptedToken: "fresh")
        async let a = host.recoverCredential()
        async let b = host.recoverCredential()
        let results = await [a, b]
        #expect(results == ["fresh", "fresh"])
        #expect(source.calls.count == 1)
    }

    @Test func providersWithoutAnAuthDescriptorNeverTouchTheTokenSource() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let package = dir.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        try self.package(at: package, status: "authRequired")
        let source = FakeTokenSource(["fresh"])
        let host = VisualProviderHost(root: dir.appendingPathComponent("host"), preferences: UserDefaults(suiteName: "VisualProviderTests.\(UUID())")!,
                                      credentials: MemoryVisualCredentials(), tokenSource: source)
        try await host.install(from: package)
        try host.saveCredential("manual")
        host.enabled = true
        #expect(try await host.prepare(track: track(), duration: 180, requestID: "one") == nil)
        #expect(source.calls.isEmpty && host.statusKey == "visualProvider.status.authRequired")
    }

    // MARK: Factory-installed provider (bundled in the app, removable)

    private func bundledPackage(in dir: URL, name: String = "bundled", version: String = "1", id: String = "fixture", platform: String? = VisualProviderManifest.currentPlatform) throws -> URL {
        let url = dir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try package(at: url, status: "absent", auth: fixtureAuth, id: id, version: version, platform: platform)
        return url
    }
    private func launch(_ dir: URL, defaults: UserDefaults, credentials: MemoryVisualCredentials, bundled: URL?) async -> VisualProviderHost {
        let host = VisualProviderHost(root: dir.appendingPathComponent("host"), preferences: defaults, credentials: credentials, bundledPackage: bundled)
        host.provisionBundledProvider()
        await host.provisioning?.value
        return host
    }

    @Test func bundledProviderIsPlacedOnFirstLaunchWithoutActivatingOrTouchingCredentials() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let bundled = try bundledPackage(in: dir)
        // The downloaded app carries the quarantine flag; the preinstalled copy must still be runnable.
        #expect(setxattr(bundled.appendingPathComponent("worker").path, "com.apple.quarantine", "0081;00000000;Test;", 19, 0, 0) == 0)
        let credentials = MemoryVisualCredentials()
        let host = await launch(dir, defaults: UserDefaults(suiteName: "VisualProviderTests.\(UUID())")!, credentials: credentials, bundled: bundled)
        #expect(host.manifest?.id == "fixture" && host.manifest?.version == "1")
        #expect(!host.enabled && !host.hasCredential && host.identitySalt == nil)
        #expect(host.statusKey == "visualProvider.status.tokenRequired")
        #expect(credentials.reads == 0 && credentials.value == nil)
        let installed = dir.appendingPathComponent("host/Installed")
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: installed.path)) == ["manifest.json", "worker"])
        #expect(getxattr(installed.appendingPathComponent("worker").path, "com.apple.quarantine", nil, 0, 0, 0) < 0)
        #expect(try FileManager.default.attributesOfItem(atPath: installed.appendingPathComponent("worker").path)[.posixPermissions] as? Int == 0o700)
        // The app payload itself is left as shipped.
        #expect(FileManager.default.fileExists(atPath: bundled.appendingPathComponent("worker").path))
    }

    @Test func provisioningWithoutABundleOrWithAnInvalidOneDoesNothing() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let none = await launch(dir, defaults: UserDefaults(suiteName: "VisualProviderTests.\(UUID())")!, credentials: MemoryVisualCredentials(), bundled: nil)
        #expect(none.manifest == nil && none.provisioning == nil)
        let foreign = try bundledPackage(in: dir, name: "foreign", platform: "windows-x64")
        let host = await launch(dir, defaults: UserDefaults(suiteName: "VisualProviderTests.\(UUID())")!, credentials: MemoryVisualCredentials(), bundled: foreign)
        #expect(host.manifest == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("host/Installed").path))
    }

    @Test func uninstallingDeletesTheProviderForGoodAndOnlyAManualInstallBringsItBack() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let bundled = try bundledPackage(in: dir)
        let defaults = UserDefaults(suiteName: "VisualProviderTests.\(UUID())")!
        let credentials = MemoryVisualCredentials()
        let first = await launch(dir, defaults: defaults, credentials: credentials, bundled: bundled)
        try first.saveCredential("token"); first.enabled = true
        try await first.uninstall()
        #expect(first.manifest == nil && !first.enabled && credentials.value == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("host/Installed").path))

        // Next launches do not reinstall it, however many times.
        for _ in 0..<2 {
            let relaunched = await launch(dir, defaults: defaults, credentials: credentials, bundled: bundled)
            #expect(relaunched.manifest == nil && !relaunched.enabled)
            #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("host/Installed").path))
        }

        // The manual installer still works and counts as a new decision to have the provider.
        let relaunched = await launch(dir, defaults: defaults, credentials: credentials, bundled: bundled)
        try await relaunched.install(from: bundled)
        #expect(relaunched.manifest?.id == "fixture" && !relaunched.enabled)
        let again = await launch(dir, defaults: defaults, credentials: credentials, bundled: bundled)
        #expect(again.manifest?.id == "fixture")
        try await again.uninstall()
        let final = await launch(dir, defaults: defaults, credentials: credentials, bundled: bundled)
        #expect(final.manifest == nil)
    }

    @Test func aNewerBundledVersionUpgradesInPlaceKeepingLoginAndActivationButNeverDowngrades() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: "VisualProviderTests.\(UUID())")!
        let credentials = MemoryVisualCredentials()
        let v1 = try bundledPackage(in: dir, name: "v1", version: "0.2.0")
        let first = await launch(dir, defaults: defaults, credentials: credentials, bundled: v1)
        try first.saveCredential("token"); first.enabled = true

        let same = await launch(dir, defaults: defaults, credentials: credentials, bundled: v1)
        #expect(same.manifest?.version == "0.2.0" && same.enabled && same.hasCredential)

        let v2 = try bundledPackage(in: dir, name: "v2", version: "0.10.0")
        let upgraded = await launch(dir, defaults: defaults, credentials: credentials, bundled: v2)
        #expect(upgraded.manifest?.version == "0.10.0" && upgraded.enabled && upgraded.hasCredential)
        #expect(credentials.value == "token")

        let older = await launch(dir, defaults: defaults, credentials: credentials, bundled: v1)
        #expect(older.manifest?.version == "0.10.0")
    }

    @Test func aDifferentManuallyInstalledProviderIsNotReplacedByTheBundledOne() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: "VisualProviderTests.\(UUID())")!
        let other = dir.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false)
        try package(at: other, status: "absent", id: "other")
        let manual = await launch(dir, defaults: defaults, credentials: MemoryVisualCredentials(), bundled: nil)
        try await manual.install(from: other)
        let host = await launch(dir, defaults: defaults, credentials: MemoryVisualCredentials(), bundled: try bundledPackage(in: dir))
        #expect(host.manifest?.id == "other")
    }

    @Test func versionComparisonIsNumericAndConservative() {
        #expect(VisualProviderHost.isNewer("0.2.0", than: "0.1.5"))
        #expect(VisualProviderHost.isNewer("0.10.0", than: "0.9.9"))
        #expect(VisualProviderHost.isNewer("1.0", than: "0.9.9"))
        #expect(!VisualProviderHost.isNewer("0.2.0", than: "0.2.0"))
        #expect(!VisualProviderHost.isNewer("0.2", than: "0.2.0"))
        #expect(!VisualProviderHost.isNewer("0.1.5", than: "0.2.0"))
        #expect(!VisualProviderHost.isNewer("beta", than: "0.2.0") && !VisualProviderHost.isNewer("1", than: ""))
    }

    @Test func packagedManifestsAreOneProtocolWithAPlatformSpecificExecutable() throws {
        // apple/Tests/SideBTests/<file> -> repository root.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let package = root.appendingPathComponent("extensions/spotify-canvas/package")
        guard FileManager.default.fileExists(atPath: package.path) else { return }
        let mac = try JSONDecoder().decode(VisualProviderManifest.self, from: Data(contentsOf: package.appendingPathComponent("manifest.macos-arm64.json")))
        let windows = try JSONDecoder().decode(VisualProviderManifest.self, from: Data(contentsOf: package.appendingPathComponent("manifest.windows-x64.json")))
        #expect(mac.executable == "sideb-spotify-canvas" && windows.executable == "sideb-spotify-canvas.exe")
        #expect(mac.id == windows.id && mac.version == windows.version && mac.auth == windows.auth && mac.protocolVersion == 1)
        #expect(throws: (any Error).self) { try windows.validate() }
        if VisualProviderManifest.currentPlatform == "macos-arm64" { #expect(throws: Never.self) { try mac.validate() } }
        // Manifests written before the field existed keep installing.
        #expect(throws: Never.self) { try VisualProviderManifest(protocolVersion: 1, id: "x", name: "X", version: "1", executable: "x", credentialLabel: "T").validate() }
    }
}
