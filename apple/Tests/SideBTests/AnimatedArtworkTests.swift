import Foundation
import SideBCore
import Testing
@testable import SideB

@Suite("Carátulas animadas: identidad y cancelación")
@MainActor
struct AnimatedArtworkTests {
    private func track(_ id: String, album: String? = "Album", albumID: String? = "album-id") -> SongItemRecord {
        SongItemRecord(videoId: id, title: id, artists: "Artist", album: album, duration: "3:20",
                       thumbnail: nil, artistId: nil, albumId: albumID, setVideoId: nil,
                       isVideo: false, isUpload: false, library: nil, artistRuns: [])
    }

    private var active: AnimatedArtworkPolicy {
        AnimatedArtworkPolicy(enabled: true, presented: true, visible: true, playing: true)
    }

    @Test("El álbum conserva identidad entre pistas; sin álbum cada pista es independiente")
    func albumIdentity() {
        let session = UUID()
        #expect(AnimatedArtworkIdentity(track: track("one"), sessionID: session)
                == AnimatedArtworkIdentity(track: track("two"), sessionID: session))
        #expect(AnimatedArtworkIdentity(track: track("one", album: nil, albumID: nil), sessionID: session)
                != AnimatedArtworkIdentity(track: track("two", album: nil, albumID: nil), sessionID: session))
        #expect(AnimatedArtworkIdentity(track: track("one"), sessionID: session)
                != AnimatedArtworkIdentity(track: track("one"), sessionID: UUID()))
    }

    @Test("Metadata normalizada conserva edición y artista")
    func conservativeMetadataIdentity() {
        let session = UUID()
        #expect(AnimatedArtworkIdentity(track: track("one", album: " Álbum   Deluxe ", albumID: nil), sessionID: session)
                == AnimatedArtworkIdentity(track: track("two", album: "álbum deluxe", albumID: nil), sessionID: session))
        #expect(AnimatedArtworkIdentity(track: track("one", album: "Album Deluxe", albumID: nil), sessionID: session)
                != AnimatedArtworkIdentity(track: track("two", album: "Album", albumID: nil), sessionID: session))
    }

    @Test("Artista principal estructurado conserva álbum entre colaboraciones")
    func primaryArtistInsteadOfFeaturedDisplayString() {
        var one = track("one", albumID: nil)
        one.artists = "Baby Keem & Travis Scott"
        one.artistRuns = [.init(text: " ", id: nil), .init(text: "Baby Keem", id: "primary"),
                          .init(text: "Travis Scott", id: "guest")]
        var two = one
        two.videoId = "two"
        two.artists = "Baby Keem & Kendrick Lamar"
        two.artistRuns = [.init(text: "Baby Keem", id: "primary"), .init(text: "Kendrick Lamar", id: "guest-two")]
        let session = UUID()
        #expect(AnimatedArtworkIdentity.principalArtist(one) == "Baby Keem")
        #expect(AnimatedArtworkRequestFingerprint(track: one, storefront: "us").artist == "Baby Keem")
        #expect(AnimatedArtworkIdentity(track: one, sessionID: session)
                == AnimatedArtworkIdentity(track: two, sessionID: session))
        one.artistRuns = []
        #expect(AnimatedArtworkIdentity.principalArtist(one) == one.artists)
    }

    @Test("Primer frame oculto se conserva; sólo revela al volver elegible y rechaza callbacks antiguos")
    func readyPresentationRespectsPolicyAndRevision() {
        for suspension in 0..<3 {
            var policy = active
            if suspension == 0 { policy.playing = false }
            if suspension == 1 { policy.visible = false }
            if suspension == 2 { policy.flipped = true }
            var presentation = AnimatedArtworkPresentation()
            let revision = UUID()
            presentation.reset(revision: revision)
            let stale = presentation.receiveFrame(revision: UUID(), eligible: true)
            #expect(!stale)
            #expect(!presentation.hasFrame)
            let suspended = presentation.receiveFrame(revision: revision, eligible: policy.canPrepare)
            #expect(!suspended)
            #expect(presentation.hasFrame)
            #expect(!presentation.revealed)
            let stillSuspended = presentation.resume(eligible: policy.canPrepare)
            #expect(!stillSuspended)
            let resumed = presentation.resume(eligible: active.canPrepare)
            #expect(resumed)
            #expect(presentation.revealed)
            let repeated = presentation.resume(eligible: true)
            #expect(!repeated)
            presentation.reset(revision: UUID())
            let replaced = presentation.receiveFrame(revision: revision, eligible: true)
            #expect(!replaced)
            #expect(!presentation.hasFrame)
            #expect(!presentation.revealed)
        }
    }

    @Test("Enriquecer metadata tras ausencia permite nueva consulta sin cambiar albumID")
    func enrichedMetadataRetriesMissingAsset() async {
        let controller = AnimatedArtworkController(preparationDelay: .zero)
        let probe = Probe()
        var sparse = track("one", album: nil)
        sparse.title = ""
        let identity = AnimatedArtworkIdentity(track: sparse, sessionID: UUID())
        controller.update(identity: identity, policy: active,
                          fingerprint: .init(track: sparse, storefront: "us"), fetch: probe.fetch, release: probe.release)
        let first = controller.preparation
        await probe.waitForCall()
        probe.resolve(0)
        await first?.value
        let enriched = track("one")
        controller.update(identity: identity, policy: active,
                          fingerprint: .init(track: enriched, storefront: "us"), fetch: probe.fetch, release: probe.release)
        let second = controller.preparation
        await probe.waitForCall()
        #expect(probe.calls.count == 2)
        controller.update(identity: identity, policy: active,
                          fingerprint: .init(track: enriched, storefront: "us"), fetch: probe.fetch, release: probe.release)
        #expect(probe.calls.count == 2)
        probe.resolve(1)
        await second?.value
        controller.detach()
    }

    @Test("La duración de audio enriquece pistas sin metadata y descarta valores inválidos")
    func audioDurationEnrichesMetadataFingerprint() {
        var item = track("no-album", album: nil, albumID: nil)
        item.duration = nil
        let empty = AnimatedArtworkRequestFingerprint(track: item, storefront: "us")
        let measured = AnimatedArtworkRequestFingerprint(track: item, storefront: "us", audioDuration: 201.2)
        #expect(empty.duration == nil)
        #expect(measured.duration == 201)
        #expect(empty != measured)
        #expect(AnimatedArtworkRequestFingerprint(track: item, storefront: "us", audioDuration: .nan) == empty)
        item.duration = "3:20"
        #expect(AnimatedArtworkRequestFingerprint(track: item, storefront: "us", audioDuration: 210).duration == 200)
    }

    @Test("Asset HEVC inválido permite un solo intento H264 con lease separado")
    func hevcFallbackIsBoundedAndReleasesFirstLease() async {
        let controller = AnimatedArtworkController(preparationDelay: .zero)
        let probe = Probe()
        let identity = AnimatedArtworkIdentity(track: track("one"), sessionID: UUID())
        controller.update(identity: identity, policy: active, fetch: probe.fetch, release: probe.release)
        let first = controller.preparation
        await probe.waitForCall()
        probe.resolve(0, asset: invalidAsset(codec: "hevc"))
        await first?.value
        await probe.waitForCall()
        let fallback = controller.preparation
        #expect(probe.preferences == [true, false])
        #expect(probe.calls[0] != probe.calls[1])
        #expect(probe.released == [probe.calls[0]])
        // A backend ignoring the codec preference must not make the client retry forever.
        probe.resolve(1, asset: invalidAsset(codec: "hevc"))
        await fallback?.value
        #expect(probe.preferences == [true, false])
        #expect(probe.released == probe.calls)
        #expect(controller.preparation == nil)
        #expect(!controller.isReady)
        controller.detach()
    }

    @Test("Cambio de álbum durante fallback cancela lease y rechaza su fallo tardío")
    func staleFallbackCannotReplaceNewAlbum() async {
        let controller = AnimatedArtworkController(preparationDelay: .zero)
        let probe = Probe()
        let session = UUID()
        controller.update(identity: AnimatedArtworkIdentity(track: track("one"), sessionID: session),
                          policy: active, fetch: probe.fetch, release: probe.release)
        let first = controller.preparation
        await probe.waitForCall()
        probe.resolve(0, asset: invalidAsset(codec: "hvc1"))
        await first?.value
        await probe.waitForCall()
        let fallback = controller.preparation
        controller.update(identity: AnimatedArtworkIdentity(track: track("two", albumID: "other"), sessionID: session),
                          policy: active, fetch: probe.fetch, release: probe.release)
        let latest = controller.preparation
        await probe.waitForCall()
        let latestID = controller.requestID
        #expect(probe.released == Array(probe.calls.prefix(2)))
        probe.resolve(1, asset: invalidAsset(codec: "hevc"))
        await fallback?.value
        #expect(controller.requestID == latestID)
        #expect(probe.preferences == [true, false, true])
        probe.resolve(2)
        await latest?.value
        #expect(probe.released == probe.calls)
        controller.detach()
    }

    private func invalidAsset(codec: String) -> AnimatedArtworkAsset {
        AnimatedArtworkAsset(assetId: "invalid", localPath: "/nonexistent/\(UUID()).mp4",
                             codec: codec, width: 1080, height: 1080, frameRate: 60, sizeBytes: 1)
    }

    @Test("Pausa fría, flip, invisibilidad y restricciones no preparan")
    func eligibility() {
        var variants: [AnimatedArtworkPolicy] = []
        var paused = active; paused.playing = false; variants.append(paused)
        var hidden = active; hidden.visible = false; variants.append(hidden)
        var flipped = active; flipped.flipped = true; variants.append(flipped)
        var constrained = active; constrained.constrained = true; variants.append(constrained)
        var disabled = active; disabled.enabled = false; variants.append(disabled)
        var closed = active; closed.presented = false; variants.append(closed)
        for policy in variants {
            let controller = AnimatedArtworkController(preparationDelay: .zero)
            controller.update(identity: AnimatedArtworkIdentity(track: track("one"), sessionID: UUID()),
                              policy: policy, fetch: { _, _ in Issue.record("Unexpected motion lookup"); return nil },
                              release: { _ in })
            #expect(controller.requestID == nil)
            #expect(controller.layer.player == nil)
            controller.detach()
        }
    }

    @Test("Mismo álbum deduplica y un resultado vacío no se reintenta con cada update")
    func sameAlbumDoesNotRefetch() async {
        let controller = AnimatedArtworkController(preparationDelay: .zero)
        let probe = Probe()
        let session = UUID()
        let first = AnimatedArtworkIdentity(track: track("one"), sessionID: session)
        controller.update(identity: first, policy: active, fetch: probe.fetch, release: probe.release)
        let task = controller.preparation
        await probe.waitForCall()
        controller.update(identity: AnimatedArtworkIdentity(track: track("two"), sessionID: session),
                          policy: active, fetch: probe.fetch, release: probe.release)
        #expect(probe.calls.count == 1)
        probe.resolve(0)
        await task?.value
        controller.update(identity: first, policy: active, fetch: probe.fetch, release: probe.release)
        #expect(probe.calls.count == 1)
        #expect(probe.released == probe.calls)
        #expect(!controller.isReady)
        controller.detach()
    }

    @Test("Cambiar álbum cancela lease; respuesta antigua no cancela la petición nueva")
    func latestWins() async {
        let controller = AnimatedArtworkController(preparationDelay: .zero)
        let probe = Probe()
        let session = UUID()
        controller.update(identity: AnimatedArtworkIdentity(track: track("a"), sessionID: session),
                          policy: active, fetch: probe.fetch, release: probe.release)
        let oldTask = controller.preparation
        await probe.waitForCall()
        controller.update(identity: AnimatedArtworkIdentity(track: track("b", albumID: "other"), sessionID: session),
                          policy: active, fetch: probe.fetch, release: probe.release)
        let newTask = controller.preparation
        await probe.waitForCall()
        let currentRequest = controller.requestID
        #expect(probe.released == [probe.calls[0]])
        probe.resolve(0)
        await oldTask?.value
        #expect(controller.requestID == currentRequest)
        probe.resolve(1)
        await newTask?.value
        #expect(probe.released == probe.calls)
        controller.detach()
    }

    @Test("Apagar libera inmediatamente incluso si fetch ignora cancelación")
    func disableCancelsLease() async {
        let controller = AnimatedArtworkController(preparationDelay: .zero)
        let probe = Probe()
        let identity = AnimatedArtworkIdentity(track: track("one"), sessionID: UUID())
        controller.update(identity: identity, policy: active, fetch: probe.fetch, release: probe.release)
        let pending = controller.preparation
        await probe.waitForCall()
        var disabled = active
        disabled.enabled = false
        controller.update(identity: identity, policy: disabled, fetch: probe.fetch, release: probe.release)
        #expect(probe.released == probe.calls)
        #expect(controller.requestID == nil)
        probe.resolve(0)
        await pending?.value
        #expect(controller.layer.player == nil)
        #expect(!controller.isReady)
        controller.detach()
    }

    @Test("Vaciar espera cancelación síncrona de todos los leases y no recarga el mismo álbum")
    func cacheClearIsBarrier() async throws {
        let manager = AnimatedArtworkManager()
        let first = AnimatedArtworkController(preparationDelay: .zero, manager: manager)
        let second = AnimatedArtworkController(preparationDelay: .zero, manager: manager)
        let probe = Probe()
        let identity = AnimatedArtworkIdentity(track: track("one"), sessionID: UUID())
        first.update(identity: identity, policy: active, fetch: probe.fetch, release: probe.release)
        let oldFirst = first.preparation
        await probe.waitForCall()
        second.update(identity: identity, policy: active, fetch: probe.fetch, release: probe.release)
        let oldSecond = second.preparation
        await probe.waitForCall()
        let removed = try await manager.clear {
            #expect(Set(probe.released) == Set(probe.calls))
            #expect(probe.released.count == probe.calls.count)
            #expect(first.requestID == nil)
            #expect(second.requestID == nil)
            #expect(first.layer.player == nil)
            #expect(second.layer.player == nil)
            #expect(manager.isClearing)
            return 12
        }
        #expect(removed == 12)
        #expect(manager.cacheRevision == 1)
        #expect(!manager.isClearing)
        probe.resolve(0)
        probe.resolve(1)
        await oldFirst?.value
        await oldSecond?.value
        first.update(identity: identity, policy: active, fetch: probe.fetch, release: probe.release)
        second.update(identity: identity, policy: active, fetch: probe.fetch, release: probe.release)
        #expect(probe.calls.count == 2)
        #expect(first.preparation == nil)
        #expect(second.preparation == nil)
        first.detach()
        second.detach()
    }

    @Test("Fallo de borrado no deja la preferencia ocupada ni resucita un lease")
    func cacheClearFailure() async {
        enum Failure: Error { case disk }
        let manager = AnimatedArtworkManager()
        var stops = 0
        let id = manager.register { stops += 1 }
        do {
            _ = try await manager.clear { throw Failure.disk }
            Issue.record("Expected deletion failure")
        } catch {}
        #expect(stops == 1)
        #expect(manager.cacheRevision == 1)
        #expect(!manager.isClearing)
        manager.unregister(id)
    }

    @Test("Dos ventanas comparten el mismo borrado y su resultado real")
    func overlappingCacheClearSharesResult() async throws {
        let manager = AnimatedArtworkManager()
        var started: CheckedContinuation<Void, Never>?
        var finish: CheckedContinuation<UInt64, Never>?
        var calls = 0
        let first = Task { @MainActor in
            try await manager.clear {
                calls += 1
                return await withCheckedContinuation { continuation in
                    finish = continuation
                    started?.resume()
                    started = nil
                }
            }
        }
        if finish == nil { await withCheckedContinuation { started = $0 } }
        var second: Task<UInt64, Error>?
        await withCheckedContinuation { entered in
            second = Task { @MainActor in
                entered.resume()
                return try await manager.clear { calls += 1; return 0 }
            }
        }
        finish?.resume(returning: 42)
        let firstResult = try await first.value
        let secondResult = try await second!.value
        #expect(firstResult == 42)
        #expect(secondResult == 42)
        #expect(calls == 1)
        #expect(!manager.isClearing)
    }

    @Test("Un archivo inválido nunca revela un frame y libera su lease sin reintentar")
    func invalidFileKeepsStaticCover() async {
        let controller = AnimatedArtworkController(preparationDelay: .zero)
        let identity = AnimatedArtworkIdentity(track: track("one"), sessionID: UUID())
        var requests = 0
        var releases = 0
        let fetch: AnimatedArtworkController.Fetch = { _, _ in
            requests += 1
            return AnimatedArtworkAsset(assetId: "invalid", localPath: "/nonexistent/\(UUID()).mp4",
                                        codec: "h264", width: 1080, height: 1080, frameRate: 60, sizeBytes: 1)
        }
        controller.update(identity: identity, policy: active, fetch: fetch, release: { _ in releases += 1 })
        #expect(!controller.isReady)
        #expect(controller.layer.opacity == 0)
        let preparation = controller.preparation
        await preparation?.value
        #expect(requests == 1)
        #expect(releases == 1)
        #expect(!controller.isReady)
        #expect(controller.layer.opacity == 0)
        #expect(controller.layer.player == nil)
        controller.update(identity: identity, policy: active, fetch: fetch, release: { _ in releases += 1 })
        #expect(requests == 1)
        #expect(controller.preparation == nil)
        controller.detach()
    }

    @MainActor
    private final class Probe {
        var calls: [String] = []
        var released: [String] = []
        var preferences: [Bool] = []
        var pending: [CheckedContinuation<AnimatedArtworkAsset?, Error>] = []
        private var callWaiter: CheckedContinuation<Void, Never>?
        private var consumed = 0

        func fetch(_ id: String, _ preferHevc: Bool) async throws -> AnimatedArtworkAsset? {
            try await withCheckedThrowingContinuation { continuation in
                calls.append(id)
                preferences.append(preferHevc)
                pending.append(continuation)
                callWaiter?.resume()
                callWaiter = nil
            }
        }
        func release(_ id: String) { released.append(id) }
        func resolve(_ index: Int, asset: AnimatedArtworkAsset? = nil) { pending[index].resume(returning: asset) }
        func waitForCall() async {
            if calls.count <= consumed {
                await withCheckedContinuation { callWaiter = $0 }
            }
            consumed += 1
        }
    }
}
