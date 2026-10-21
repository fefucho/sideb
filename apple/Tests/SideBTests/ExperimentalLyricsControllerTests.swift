import Foundation
import Testing
@testable import SideB

@Suite("Carga aislada de letras experimentales")
@MainActor
struct ExperimentalLyricsControllerTests {
    private func request(playback: UUID = UUID(), session: UUID = UUID(), video: String = "same-song") -> ExperimentalLyricsRequest {
        ExperimentalLyricsRequest(playbackID: playback, sessionID: session, videoID: video,
                                  title: "Song", artist: "Artist", album: "Album", durationSeconds: 200)
    }

    private func document(_ provider: String) -> ExperimentalLyricsDocument {
        ExperimentalLyricsDocument(provider: provider, instrumental: false, lines: [
            ExperimentalLyricLine(startMS: 1000, endMS: 3000, text: "Uno dos", words: [
                ExperimentalLyricWord(text: "Uno ", startMS: 1000, endMS: 2000),
                ExperimentalLyricWord(text: "dos", startMS: 2000, endMS: 3000)
            ], translation: nil)
        ])
    }

    @Test("El modo clásico no consulta el endpoint experimental")
    func inactiveDoesNotFetch() async {
        let controller = ExperimentalLyricsController()
        let probe = FetchProbe()
        let task = controller.activate(nil, fetch: probe.fetch)
        #expect(task == nil)
        #expect(probe.calls.isEmpty)
        #expect(controller.document == nil)
        #expect(!controller.isLoading)
    }

    @Test("La misma identidad no dispara peticiones por cada render")
    func deduplicatesSameRequest() async {
        let controller = ExperimentalLyricsController()
        let probe = FetchProbe()
        let key = request()
        let first = controller.activate(key, fetch: probe.fetch)
        await probe.waitForCount(1)
        _ = controller.activate(key, fetch: probe.fetch)
        #expect(probe.calls.count == 1)
        probe.resolve(0, with: document("first"))
        await first?.value
        _ = controller.activate(key, fetch: probe.fetch)
        #expect(probe.calls.count == 1)
        #expect(controller.document?.provider == "first")
        #expect(!controller.isLoading)
    }

    @Test("Repetir el mismo video como otra ocurrencia descarta su respuesta anterior")
    func playbackOccurrenceOwnsResult() async {
        let controller = ExperimentalLyricsController()
        let probe = FetchProbe()
        let session = UUID()
        let first = controller.activate(request(session: session), fetch: probe.fetch)
        await probe.waitForCount(1)
        let second = controller.activate(request(session: session), fetch: probe.fetch)
        await probe.waitForCount(2)
        probe.resolve(1, with: document("new occurrence"))
        await second?.value
        probe.resolve(0, with: document("old occurrence"))
        await first?.value
        #expect(controller.document?.provider == "new occurrence")
        #expect(!controller.isLoading)
    }

    @Test("El cambio de cuenta invalida datos incluso con el mismo video y token")
    func sessionOwnsResult() async {
        let controller = ExperimentalLyricsController()
        let probe = FetchProbe()
        let playback = UUID()
        let first = controller.activate(request(playback: playback), fetch: probe.fetch)
        await probe.waitForCount(1)
        let second = controller.activate(request(playback: playback), fetch: probe.fetch)
        await probe.waitForCount(2)
        probe.resolve(0, with: document("previous account"))
        await first?.value
        #expect(controller.document == nil)
        #expect(controller.isLoading)
        probe.resolve(1, with: document("current account"))
        await second?.value
        #expect(controller.document?.provider == "current account")
    }

    @Test("Actualizar conserva la letra usable y gana la última revisión")
    func refreshRevisionAndRetention() async {
        let controller = ExperimentalLyricsController()
        let probe = FetchProbe()
        let initial = controller.activate(request(), fetch: probe.fetch)
        await probe.waitForCount(1)
        probe.resolve(0, with: document("cached"))
        await initial?.value
        let earlier = controller.refresh(fetch: probe.fetch)
        await probe.waitForCount(2)
        #expect(controller.document?.provider == "cached")
        let latest = controller.refresh(fetch: probe.fetch)
        await probe.waitForCount(3)
        #expect(probe.calls[1].forceRefresh)
        #expect(probe.calls[2].forceRefresh)
        probe.resolve(2, with: document("fresh"))
        await latest?.value
        probe.resolve(1, with: document("stale refresh"))
        await earlier?.value
        #expect(controller.document?.provider == "fresh")
        #expect(!controller.isLoading)
    }

    @Test("Un error de actualización conserva texto y permite reintentar")
    func refreshErrorPreservesDocument() async {
        let controller = ExperimentalLyricsController()
        let probe = FetchProbe()
        let first = controller.activate(request(), fetch: probe.fetch)
        await probe.waitForCount(1)
        probe.resolve(0, with: document("usable"))
        await first?.value
        let refresh = controller.refresh(fetch: probe.fetch)
        await probe.waitForCount(2)
        probe.reject(1)
        await refresh?.value
        #expect(controller.document?.provider == "usable")
        #expect(controller.errorKey == "lyrics.experimental.error")
        #expect(!controller.isLoading)
        let retry = controller.refresh(fetch: probe.fetch)
        await probe.waitForCount(3)
        #expect(controller.errorKey == nil)
        probe.resolve(2, with: nil)
        await retry?.value
        #expect(controller.document?.provider == "usable")
    }

    @Test("Volver a las letras actuales cancela y no acepta respuestas tardías")
    func deactivationRejectsLateResult() async {
        let controller = ExperimentalLyricsController()
        let probe = FetchProbe()
        let pending = controller.activate(request(), fetch: probe.fetch)
        await probe.waitForCount(1)
        controller.deactivate()
        probe.resolve(0, with: document("too late"))
        await pending?.value
        #expect(controller.activeRequest == nil)
        #expect(controller.document == nil)
        #expect(!controller.isLoading)
        #expect(controller.errorKey == nil)
    }

    @Test("Duración válida sin overflow ni formatos mal formados")
    func durationParsing() {
        #expect(ExperimentalLyricsRequest.durationSeconds("3:20") == 200)
        #expect(ExperimentalLyricsRequest.durationSeconds("1:02:03") == 3723)
        #expect(ExperimentalLyricsRequest.durationSeconds("00:00") == nil)
        #expect(ExperimentalLyricsRequest.durationSeconds("3:99") == nil)
        #expect(ExperimentalLyricsRequest.durationSeconds("3::20") == nil)
        #expect(ExperimentalLyricsRequest.durationSeconds("18446744073709551615:59") == nil)
        #expect(ExperimentalLyricsRequest.durationSeconds(nil) == nil)
        #expect(ExperimentalLyricsRequest.effectiveDurationSeconds(metadata: "3:20", audioDuration: 201.4) == 200)
        #expect(ExperimentalLyricsRequest.effectiveDurationSeconds(metadata: nil, audioDuration: 200.7) == 201)
        #expect(ExperimentalLyricsRequest.effectiveDurationSeconds(metadata: "unknown", audioDuration: 200) == 200)
        #expect(ExperimentalLyricsRequest.effectiveDurationSeconds(metadata: nil, audioDuration: .nan) == nil)
        #expect(ExperimentalLyricsRequest.effectiveDurationSeconds(metadata: nil, audioDuration: .infinity) == nil)
        #expect(ExperimentalLyricsRequest.effectiveDurationSeconds(metadata: nil, audioDuration: -1) == nil)
        #expect(ExperimentalLyricsRequest.effectiveDurationSeconds(metadata: nil, audioDuration: Double(UInt64.max)) == nil)
    }
}

@MainActor
private final class FetchProbe {
    struct Call {
        let request: ExperimentalLyricsRequest
        let forceRefresh: Bool
        let continuation: CheckedContinuation<ExperimentalLyricsDocument?, Error>
    }
    var calls: [Call] = []

    func fetch(_ request: ExperimentalLyricsRequest, forceRefresh: Bool) async throws -> ExperimentalLyricsDocument? {
        try await withCheckedThrowingContinuation { continuation in
            calls.append(Call(request: request, forceRefresh: forceRefresh, continuation: continuation))
        }
    }

    func waitForCount(_ count: Int) async {
        for _ in 0..<1000 {
            if calls.count >= count { return }
            await Task.yield()
        }
        Issue.record("La petición experimental esperada no comenzó")
    }

    func resolve(_ index: Int, with document: ExperimentalLyricsDocument?) {
        calls[index].continuation.resume(returning: document)
    }

    func reject(_ index: Int) {
        calls[index].continuation.resume(throwing: URLError(.notConnectedToInternet))
    }
}
