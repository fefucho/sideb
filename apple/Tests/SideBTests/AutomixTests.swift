import Foundation
import AVFoundation
import SwiftUI
import Testing
import SideBCore
@testable import SideB

// PLAN-024: Automix del Mac. Sin red ni core: lógica pura, coordinador con anfitrión falso y el servicio de audio
// con archivos WAV locales (sin escuchar nada).

private func song(_ id: String, album: String? = nil, upload: Bool = false) -> AutomixSong {
    AutomixSong(videoID: id, isUpload: upload, albumID: album)
}

private func context(token: UUID = UUID(), current: AutomixSong = song("A"), next: AutomixSong? = song("B"),
                     jam: Bool = false, repeatOne: Bool = false, started: Bool = true, skipSameAlbum: Bool = true,
                     upcoming: [AutomixSong]? = nil, lookahead: Int = 1) -> AutomixContext {
    AutomixContext(token: token, current: current, next: next, jamActive: jam, repeatOne: repeatOne, hasStarted: started,
                   skipSameAlbum: skipSameAlbum, upcoming: upcoming ?? next.map { [$0] } ?? [], lookahead: lookahead)
}

private func transition(from: String = "A", to: String = "B", kind: String = "mix", cut: Double = 100,
                        overlapStart: Double = 8, overlapEnd: Double = 20, handover: Double = 14,
                        bOffset: Double = 90, bEntry: Double = 5, fileDuration: Double = 300,
                        path: String = "/tmp/transition.wav") -> AutomixTransition {
    AutomixTransition(requestID: "r", fromVideoID: from, toVideoID: to, kind: kind, filePath: path,
                      fileDuration: fileDuration, aCut: cut, overlapStart: overlapStart, overlapEnd: overlapEnd,
                      bOffset: bOffset, bEntry: bEntry, handover: handover, bpmFrom: 120, bpmTo: 124, bars: 8)
}

// MARK: - Elegibilidad

@Suite("Automix: elegibilidad")
struct AutomixEligibilityTests {
    @Test("Prepara con un siguiente conocido y distinto")
    func eligible() {
        #expect(AutomixEligibility.reason(context()) == nil)
        #expect(AutomixEligibility.reason(context(current: song("A", album: "X"), next: song("B", album: "Y"))) == nil)
        #expect(AutomixEligibility.reason(context(current: song("A", album: ""), next: song("B", album: ""))) == nil)
        #expect(AutomixEligibility.reason(context(current: song("A", album: nil), next: song("B", album: nil))) == nil)
    }

    @Test("Jam, repetición, sin siguiente, mismo tema y mismo álbum no preparan")
    func ineligible() {
        #expect(AutomixEligibility.reason(context(jam: true)) == .jam)
        #expect(AutomixEligibility.reason(context(repeatOne: true)) == .repeatOne)
        #expect(AutomixEligibility.reason(context(next: nil)) == .noNextTrack)
        #expect(AutomixEligibility.reason(context(next: song("A"))) == .sameTrack)
        #expect(AutomixEligibility.reason(context(current: song("A", album: "X"), next: song("B", album: "X"))) == .sameAlbum)
    }

    @Test("El Jam gana a las demás causas")
    func precedence() {
        #expect(AutomixEligibility.reason(context(next: nil, jam: true, repeatOne: true)) == .jam)
    }

    @Test("Los prefijos del core se clasifican; el mensaje crudo no se registra")
    func failures() {
        #expect(AutomixFailure(coreMessage: "automix:cancelled") == .cancelled)
        #expect(AutomixFailure(coreMessage: "automix:unsupported-format: ningún cliente") == .unsupportedFormat)
        #expect(AutomixFailure(coreMessage: "automix:too-long: 13 min") == .tooLong)
        #expect(AutomixFailure(coreMessage: "automix:bad-id: x") == .badID)
        #expect(AutomixFailure(coreMessage: "error sending request for url (https://rr.googlevideo.com/?sig=secret)") == .other)
        #expect(!AutomixFailure.other.logLabel.contains("http"))
        #expect(AutomixFailure.cancelled.reason == nil)
        #expect(AutomixFailure.unsupportedFormat.reason == .unsupportedFormat)
    }

    @Test("Un registro incoherente se rechaza")
    func consistency() {
        #expect(transition().isConsistent)
        #expect(!transition(fileDuration: .nan).isConsistent)
        #expect(!transition(kind: "wobble").isConsistent)
        #expect(!transition(overlapStart: 30, overlapEnd: 20).isConsistent)
        #expect(!transition(handover: 400).isConsistent)
        #expect(!transition(bOffset: 300).isConsistent)
    }
}

// MARK: - Mapa de tiempos y saltos

@Suite("Automix: mapa de tiempos del archivo")
struct AutomixTimelineTests {
    let timeline = transition().timeline

    @Test("Sesgo por etapa: antes del traspaso se muestra la canción anterior desde aCut; después, la siguiente")
    func bias() {
        #expect(timeline.bias(for: .none) == 0)
        // Segundo 10 del archivo = segundo 110 de la canción anterior.
        #expect(10 - timeline.bias(for: .inFile) == 110)
        // Segundo 120 del archivo = segundo 30 de la siguiente (bOffset 90).
        #expect(120 - timeline.bias(for: .handedOver) == 30)
        #expect(timeline.nextDuration == 210)
    }

    @Test("Confirmación: espera hasta 0,9 s antes del corte, empalma en el corte o poco después, abandona si no cabe el fundido")
    func commit() {
        #expect(timeline.commitDecision(position: 10) == .wait)
        #expect(timeline.commitDecision(position: 99.0) == .wait)
        // A menos de 0,9 s del corte ya se programa; si el punto de empalme (posición + 0,45 s) cae antes del corte, es el corte.
        #expect(timeline.commitDecision(position: 99.1) == .commit(fileSeconds: 0))
        #expect(timeline.commitDecision(position: 99.55) == .commit(fileSeconds: 0))
        // Pasado el corte (o encima) el empalme se aleja de «ahora» lo justo.
        if case .commit(let late) = timeline.commitDecision(position: 100) { #expect(abs(late - 0.45) < 1e-9) } else { Issue.record("debía confirmar") }
        if case .commit(let later) = timeline.commitDecision(position: 105) { #expect(abs(later - 5.45) < 1e-9) } else { Issue.record("debía confirmar") }
        // El fundido (50 ms) y el margen de 0,15 s deben caber antes de overlapStart (8 s): hasta file = 7.8 s.
        #expect(timeline.commitDecision(position: 107.3) != .giveUp)
        #expect(timeline.commitDecision(position: 107.4) == .giveUp)
        #expect(timeline.commitDecision(position: .nan) == .giveUp)
        #expect(timeline.fits(fileSeconds: 7.8) && !timeline.fits(fileSeconds: 7.9))
    }

    @Test("Fundido de 50 ms: ganancias complementarias que suman el volumen de salida")
    func crossfade() {
        #expect(AudioCrossfade.duration == 0.05)
        #expect(AudioCrossfade.progress(hostSeconds: 9.99, startSeconds: 10) == 0)
        #expect(abs(AudioCrossfade.progress(hostSeconds: 10.025, startSeconds: 10) - 0.5) < 1e-9)
        #expect(AudioCrossfade.progress(hostSeconds: 11, startSeconds: 10) == 1)
        for step in 0...20 {
            let gains = AudioCrossfade.gains(progress: Double(step) / 20, output: 0.8)
            #expect(abs(gains.new + gains.old - 0.8) < 1e-6)
        }
        let start = AudioCrossfade.gains(progress: 0, output: 1)
        #expect(start.new == 0 && start.old == 1)
        let end = AudioCrossfade.gains(progress: 1, output: 1)
        #expect(end.new == 1 && end.old == 0)
    }

    @Test("Saltos con el empalme armado")
    func seekArmed() {
        #expect(timeline.route(forSeek: 0, stage: .armed) == .direct)
        #expect(timeline.route(forSeek: 99, stage: .armed) == .direct)
        #expect(timeline.route(forSeek: 100, stage: .armed) == .intoFile)
        #expect(timeline.route(forSeek: 107.5, stage: .armed) == .intoFile)
        #expect(timeline.route(forSeek: 108, stage: .armed) == .disarmThenDirect)
    }

    @Test("Saltos con el archivo sonando y la interfaz aún en la canción anterior")
    func seekInFile() {
        #expect(timeline.route(forSeek: 99, stage: .inFile) == .restream)
        #expect(timeline.route(forSeek: 100, stage: .inFile) == .direct)
        #expect(timeline.route(forSeek: 107, stage: .inFile) == .direct)
        #expect(timeline.route(forSeek: 108, stage: .inFile) == .restream)
    }

    @Test("Saltos en la canción siguiente: antes de bEntry se resuelve de nuevo; después se mapea al archivo")
    func seekHandedOver() {
        #expect(timeline.route(forSeek: 0, stage: .handedOver) == .restream)
        #expect(timeline.route(forSeek: 5, stage: .handedOver) == .restream)
        #expect(timeline.route(forSeek: 5.2, stage: .handedOver) == .restream)
        #expect(timeline.route(forSeek: 5.25, stage: .handedOver) == .direct)
        #expect(timeline.route(forSeek: 120, stage: .handedOver) == .direct)
        #expect(timeline.route(forSeek: 209.5, stage: .handedOver) == .direct)
        #expect(timeline.route(forSeek: 210, stage: .handedOver) == .restream)
        #expect(timeline.route(forSeek: .nan, stage: .handedOver) == .restream)
        #expect(timeline.route(forSeek: 12, stage: .none) == .direct)
    }
}

// MARK: - Coordinador

@MainActor
private final class FakeHost: AutomixHost {
    var current: AutomixContext?
    var prepared: [AutomixRequest] = []
    var cancelled: [String] = []
    var armed: [AutomixTransition] = []
    var armOutcome: AutomixArmOutcome = .armed
    var disarmCount = 0
    var abortCount = 0
    var replaced: [AutomixTransition] = []
    var replaceOutcome: AutomixArmOutcome = .armed
    var settings = AutomixSettingsValue()
    var capability: AutomixCapabilityValue? = nil
    var power = AutomixPowerState()
    var prefetched: [[AutomixSong]] = []
    var prefetchAllow: [Bool] = []
    var prefetchCancels = 0
    var pairReady = false
    var pairReadyChecks = 0
    var position: Double?
    var canReplace = true
    private var pending: [String: CheckedContinuation<AutomixTransition, Error>] = [:]

    func automixContext() -> AutomixContext? { current }
    func automixPrepare(_ request: AutomixRequest) async throws -> AutomixTransition {
        prepared.append(request)
        return try await withCheckedThrowingContinuation { pending[request.requestID] = $0 }
    }
    func automixCancel(requestID: String) {
        cancelled.append(requestID)
        pending.removeValue(forKey: requestID)?.resume(throwing: AutomixFailure.cancelled)
    }
    func automixArm(_ transition: AutomixTransition) async -> AutomixArmOutcome { armed.append(transition); return armOutcome }
    func automixReplace(_ transition: AutomixTransition) async -> AutomixArmOutcome { replaced.append(transition); return replaceOutcome }
    func automixSettings() -> AutomixSettingsValue { settings }
    func automixCapability() -> AutomixCapabilityValue? { capability }
    func automixPower() -> AutomixPowerState { power }
    func automixPrefetch(_ items: [AutomixSong], allowStems: Bool) { prefetched.append(items); prefetchAllow.append(allowStems) }
    func automixPairReady(from: String, to: String) -> Bool { pairReadyChecks += 1; return pairReady }
    func automixPosition() -> Double? { position }
    func automixCanReplaceSplice() -> Bool { canReplace }
    func automixCancelPrefetch() { prefetchCancels += 1 }
    func automixDisarm() { disarmCount += 1 }
    func automixAbortMixing() { abortCount += 1 }
    func automixCacheDirectory() -> URL { URL(fileURLWithPath: "/tmp/automix-tests", isDirectory: true) }
    var modelReady: Bool? = true
    func automixModelReady() -> Bool? { modelReady }

    func complete(_ requestID: String, with transition: AutomixTransition) { pending.removeValue(forKey: requestID)?.resume(returning: transition) }
    func fail(_ requestID: String, _ failure: AutomixFailure) { pending.removeValue(forKey: requestID)?.resume(throwing: failure) }
    func settle() async { for _ in 0..<20 { await Task.yield() } }
}

@MainActor
@Suite("Automix: coordinador")
struct AutomixCoordinatorTests {
    private func make(enabled: Bool = true, _ context: AutomixContext? = context(), dropGrace: Duration = .milliseconds(30)) -> (AutomixCoordinator, FakeHost) {
        let host = FakeHost()
        host.current = context
        let coordinator = AutomixCoordinator(enabled: enabled, dropGrace: dropGrace, log: { _ in })
        coordinator.host = host
        return (coordinator, host)
    }

    @Test("Apagado no prepara nada; encendido sí, con id nuevo y la carpeta de caché")
    func enableDisable() async {
        let (coordinator, host) = make(enabled: false)
        coordinator.reconcile()
        #expect(coordinator.status == .off)
        #expect(host.prepared.isEmpty)
        coordinator.setEnabled(true)
        await host.settle()
        #expect(host.prepared.count == 1)
        #expect(coordinator.status == .preparing)
        let request = host.prepared[0]
        #expect(request.from.videoID == "A" && request.to.videoID == "B")
        #expect(!request.requestID.isEmpty)
        #expect(request.cacheDirectory.path == "/tmp/automix-tests")
        coordinator.setEnabled(false)
        #expect(coordinator.status == .off)
        #expect(host.cancelled == [request.requestID])
    }

    @Test("Pide la versión rápida en cuanto conoce el siguiente, sin esperar a que el tema suene; el archivo se entrega al empezar")
    func fastWithoutWaitingForStart() async {
        let token = UUID()
        let (coordinator, host) = make(context(token: token, started: false))
        coordinator.reconcile()
        await host.settle()
        #expect(host.prepared.count == 1)
        #expect(host.prepared[0].quality == "fast")
        #expect(coordinator.status == .preparing)
        host.complete(host.prepared[0].requestID, with: transition())
        await host.settle()
        #expect(host.armed.isEmpty, "el tema aún no suena: no se entrega al reproductor")
        #expect(coordinator.status == .ready(kind: "mix", bpm: 124))
        host.current = context(token: token, started: true)
        coordinator.reconcile()
        await host.settle()
        #expect(host.armed.count == 1, "al empezar a sonar se entrega")
        #expect(host.prepared.count == 1, "sin pedir otra preparación")
        #expect(coordinator.marker != nil)
    }

    @Test("Es idempotente: reevaluar lo mismo no pide otra preparación")
    func idempotent() async {
        let (coordinator, host) = make()
        for _ in 0..<5 { coordinator.reconcile() }
        await host.settle()
        #expect(host.prepared.count == 1)
    }

    @Test("Cambiar el siguiente tema cancela la preparación y pide otra")
    func nextTrackChanged() async {
        let token = UUID()
        let (coordinator, host) = make(context(token: token))
        coordinator.reconcile()
        await host.settle()
        let first = host.prepared[0].requestID
        host.current = context(token: token, next: song("C"))
        coordinator.reconcile()
        await host.settle()
        #expect(host.cancelled == [first])
        #expect(host.prepared.count == 2)
        #expect(host.prepared[1].to.videoID == "C")
        #expect(host.prepared[1].requestID != first)
    }

    @Test("Una respuesta de una petición descartada no se aplica")
    func staleResultDiscarded() async {
        let token = UUID()
        let (coordinator, host) = make(context(token: token))
        coordinator.reconcile()
        await host.settle()
        let first = host.prepared[0].requestID
        host.current = context(token: token, next: song("C"))
        coordinator.reconcile()
        await host.settle()
        host.complete(first, with: transition(to: "B")) // ya no hay quien espere: el fake la ignora
        await host.settle()
        #expect(host.armed.isEmpty)
        #expect(coordinator.status == .preparing)
    }

    @Test("Cambiar la pareja, un Jam, repetir un tema o el mismo álbum descartan; el mismo par con otro token NO")
    func invalidation() async {
        let token = UUID()
        let (coordinator, host) = make(context(token: token))
        coordinator.reconcile(); await host.settle()
        #expect(host.prepared.count == 1)
        // Otra ocurrencia de reproducción de la MISMA pareja (reinicio, salto): se conserva la petición, sin vaivén.
        host.current = context(token: UUID(), started: false)
        coordinator.reconcile(); await host.settle()
        #expect(host.cancelled.isEmpty)
        #expect(host.prepared.count == 1)
        #expect(coordinator.status == .preparing)

        // Otra pareja: se cancela y se pide la nueva.
        host.current = context(token: host.current!.token, next: song("C"))
        coordinator.reconcile(); await host.settle()
        #expect(host.cancelled.count == 1)
        #expect(host.prepared.count == 2)
        #expect(host.prepared[1].to.videoID == "C")

        host.current = context(token: host.current!.token, next: song("C"), jam: true)
        coordinator.reconcile(); await host.settle()
        #expect(coordinator.status == .unavailable(.jam))
        #expect(host.cancelled.count == 2)

        host.current = context(token: host.current!.token, next: song("C"), repeatOne: true)
        coordinator.reconcile()
        #expect(coordinator.status == .unavailable(.repeatOne))
        host.current = context(token: host.current!.token, current: song("A", album: "X"), next: song("B", album: "X"))
        coordinator.reconcile()
        #expect(coordinator.status == .unavailable(.sameAlbum))
        #expect(host.prepared.count == 2)
        // El ajuste del core manda: sin «no mezclar el mismo disco» sí se prepara.
        host.current = context(token: host.current!.token, current: song("A", album: "X"), next: song("B", album: "X"), skipSameAlbum: false)
        coordinator.reconcile(); await host.settle()
        #expect(coordinator.status == .preparing)
        #expect(host.prepared.count == 3)
    }

    @Test("Sin contexto o sin siguiente un momento: no se cancela al instante; sólo si dura más que la espera")
    func noContext() async throws {
        let (coordinator, host) = make()
        coordinator.reconcile(); await host.settle()
        host.current = nil
        coordinator.reconcile()
        #expect(coordinator.currentKey != nil, "la petición sigue en vuelo")
        #expect(host.cancelled.isEmpty)
        #expect(coordinator.hasPendingDrop)
        // La cola vuelve a la normalidad antes de la espera: nada se cancela ni se vuelve a pedir.
        host.current = context(token: UUID())
        coordinator.reconcile()
        try await Task.sleep(for: .milliseconds(80))
        #expect(host.cancelled.isEmpty && host.prepared.count == 1 && !coordinator.hasPendingDrop)
        // «Sin siguiente» transitorio (la cola se rehace): igual.
        host.current = context(next: nil, upcoming: [])
        coordinator.reconcile()
        #expect(host.cancelled.isEmpty && coordinator.hasPendingDrop)
        host.current = context(token: UUID())
        coordinator.reconcile()
        try await Task.sleep(for: .milliseconds(80))
        #expect(host.cancelled.isEmpty && host.prepared.count == 1)
        // Si dura, sí se cancela.
        host.current = nil
        coordinator.reconcile()
        try await Task.sleep(for: .milliseconds(120))
        #expect(host.cancelled.count == 1)
        #expect(coordinator.currentKey == nil)
        #expect(coordinator.status == .idle)
    }

    @Test("Lista: se entrega al reproductor y el estado dice tipo y tempo")
    func readyAndArmed() async {
        let (coordinator, host) = make()
        coordinator.reconcile(); await host.settle()
        host.complete(host.prepared[0].requestID, with: transition(kind: "cut"))
        await host.settle()
        #expect(host.armed.count == 1)
        #expect(coordinator.status == .ready(kind: "cut", bpm: 124))
        coordinator.spliceEntered()
        #expect(coordinator.status == .mixing(kind: "cut"))
        coordinator.didHandover()
        #expect(coordinator.status == .idle)
        #expect(coordinator.currentKey == nil)
    }

    @Test("Llegada tarde y fallo del reproductor")
    func armOutcomes() async {
        let (late, lateHost) = make()
        lateHost.armOutcome = .tooLate
        late.reconcile(); await lateHost.settle()
        lateHost.complete(lateHost.prepared[0].requestID, with: transition())
        await lateHost.settle()
        #expect(late.status == .unavailable(.tooLate))
        late.reconcile()
        #expect(lateHost.prepared.count == 1, "un plan fallido no se reintenta solo")

        let (broken, brokenHost) = make()
        brokenHost.armOutcome = .failed
        broken.reconcile(); await brokenHost.settle()
        brokenHost.complete(brokenHost.prepared[0].requestID, with: transition())
        await brokenHost.settle()
        #expect(broken.status == .unavailable(.failed))
        broken.setEnabled(false)
        broken.setEnabled(true)
        await brokenHost.settle()
        #expect(brokenHost.prepared.count == 2, "apagar y encender reintenta")
    }

    @Test("Un contrato incoherente o de otro par se descarta sin reproducirlo")
    func invalidContract() async {
        let (coordinator, host) = make()
        coordinator.reconcile(); await host.settle()
        host.complete(host.prepared[0].requestID, with: transition(to: "OTRO"))
        await host.settle()
        #expect(host.armed.isEmpty)
        #expect(coordinator.status == .unavailable(.failed))
    }

    @Test("Los fallos del core se traducen y la cancelación propia no muestra error")
    func coreFailures() async {
        for (failure, expected) in [(AutomixFailure.unsupportedFormat, AutomixUnavailableReason.unsupportedFormat),
                                    (.tooLong, .tooLong), (.badID, .failed), (.other, .failed)] {
            let (coordinator, host) = make()
            coordinator.reconcile(); await host.settle()
            host.fail(host.prepared[0].requestID, failure)
            await host.settle()
            #expect(coordinator.status == .unavailable(expected))
        }
        let (coordinator, host) = make()
        coordinator.reconcile(); await host.settle()
        host.fail(host.prepared[0].requestID, .cancelled)
        await host.settle()
        #expect(coordinator.status == .idle)
    }

    @Test("Con la mezcla sonando, un cambio del siguiente tema la abandona; un cambio de token no")
    func mixingAbort() async {
        let token = UUID()
        let (coordinator, host) = make(context(token: token))
        coordinator.reconcile(); await host.settle()
        host.complete(host.prepared[0].requestID, with: transition())
        await host.settle()
        coordinator.spliceEntered()
        host.current = context(token: token, next: song("C"))
        coordinator.reconcile()
        #expect(host.abortCount == 1)
        #expect(coordinator.status == .idle)

        let other = UUID()
        let (second, secondHost) = make(context(token: other))
        second.reconcile(); await secondHost.settle()
        secondHost.complete(secondHost.prepared[0].requestID, with: transition())
        await secondHost.settle()
        second.spliceEntered()
        secondHost.current = context(token: UUID(), started: false) // el usuario saltó
        second.reconcile()
        #expect(secondHost.abortCount == 0)
    }

    @Test("Textos de estado en ambos idiomas")
    func presentation() {
        for language in AppLanguage.allCases {
            let statuses: [AutomixCoordinator.Status] = [.off, .idle, .preparing, .ready(kind: "mix", bpm: 126.4),
                .ready(kind: "fade", bpm: 0), .mixing(kind: "cut"), .unavailable(.jam), .unavailable(.repeatOne),
                .unavailable(.noNextTrack), .unavailable(.sameTrack), .unavailable(.sameAlbum),
                .unavailable(.unsupportedFormat), .unavailable(.tooLong), .unavailable(.tooLate), .unavailable(.failed)]
            for status in statuses {
                let text = AutomixStatusPresentation.text(for: status, language: language)
                #expect(!text.isEmpty, "\(status) \(language)")
                #expect(!text.contains("automix."))
            }
        }
        #expect(AutomixStatusPresentation.text(for: .ready(kind: "mix", bpm: 126.4), language: .en) == "Ready: mix (126 bpm)")
    }
}

// MARK: - Marcador en la barra de progreso

@Suite("Automix: marcador en la barra de progreso")
struct AutomixProgressMarkerTests {
    @Test("La marca está en aCut + overlapStart de la canción actual")
    func position() throws {
        let marker = try #require(AutomixProgressMarker(transition: transition(cut: 100, overlapStart: 8)))
        #expect(marker.songSeconds == 108)
        #expect(marker.fraction(duration: 216) == 0.5)
        #expect(marker.fraction(duration: 432) == 0.25)
    }

    @Test("Sin duración válida o con la mezcla al final o después no hay marca")
    func outOfRange() {
        let marker = AutomixProgressMarker(songSeconds: 108)
        #expect(marker.fraction(duration: 0) == nil)
        #expect(marker.fraction(duration: .nan) == nil)
        #expect(marker.fraction(duration: .infinity) == nil)
        #expect(marker.fraction(duration: 108) == nil)
        #expect(marker.fraction(duration: 100) == nil)
        #expect(marker.fraction(duration: 108.001) != nil)
        #expect(AutomixProgressMarker(songSeconds: 0).fraction(duration: 200) == 0)
    }

    @Test("Geometría: la marca y el tramo teñido hasta el final suman el ancho de la barra")
    func layout() throws {
        let marker = AutomixProgressMarker(songSeconds: 150)
        let geometry = try #require(marker.layout(duration: 200, width: 400))
        #expect(geometry.tickX == 300)
        #expect(geometry.segmentWidth == 100)
        #expect(geometry.tickX + geometry.segmentWidth == 400)
        #expect(marker.layout(duration: 200, width: 0) == nil)
        #expect(marker.layout(duration: 100, width: 400) == nil)
        // Una canción que suena desde un archivo anterior (encadenada) usa su propia duración mostrada.
        let chained = try #require(AutomixProgressMarker(transition: transition(cut: 150, overlapStart: 6)))
        #expect(chained.songSeconds == 156)
        #expect(chained.layout(duration: 210, width: 210)?.tickX == 156)
    }

    @Test("Una transición con valores no finitos no produce marca")
    func invalid() {
        #expect(AutomixProgressMarker(transition: transition(cut: .nan)) == nil)
        #expect(AutomixProgressMarker(transition: transition(cut: -3, overlapStart: 1)) == nil)
    }

    @MainActor
    @Test("El marcador aparece con la transición lista y desaparece al cancelar, abandonar o traspasar")
    func lifecycle() async {
        func ready() async -> (AutomixCoordinator, FakeHost) {
            let host = FakeHost()
            host.current = context()
            let coordinator = AutomixCoordinator(enabled: true, log: { _ in })
            coordinator.host = host
            coordinator.reconcile(); await host.settle()
            #expect(coordinator.marker == nil, "preparando: todavía no hay marca")
            host.complete(host.prepared[0].requestID, with: transition(cut: 100, overlapStart: 8))
            await host.settle()
            return (coordinator, host)
        }
        // Lista: marca puesta.
        var (coordinator, host) = await ready()
        #expect(coordinator.marker?.songSeconds == 108)
        // Mezclando: sigue hasta el traspaso.
        coordinator.spliceEntered()
        #expect(coordinator.marker?.songSeconds == 108)
        coordinator.didHandover()
        #expect(coordinator.marker == nil)

        // Cancelada (el siguiente tema cambió).
        (coordinator, host) = await ready()
        host.current = context(token: host.current!.token, next: song("C"))
        coordinator.reconcile()
        #expect(coordinator.marker == nil)

        // Abandonada: el usuario saltó más allá del archivo.
        (coordinator, host) = await ready()
        coordinator.gaveUp()
        #expect(coordinator.marker == nil)

        // Apagada.
        (coordinator, host) = await ready()
        coordinator.setEnabled(false)
        #expect(coordinator.marker == nil)

        // Jam.
        (coordinator, host) = await ready()
        host.current = context(token: host.current!.token, jam: true)
        coordinator.reconcile()
        #expect(coordinator.marker == nil)

        // El reproductor no pudo cargar el archivo / llegó tarde: nunca hubo marca.
        let late = FakeHost()
        late.current = context()
        late.armOutcome = .tooLate
        let lateCoordinator = AutomixCoordinator(enabled: true, log: { _ in })
        lateCoordinator.host = late
        lateCoordinator.reconcile(); await late.settle()
        late.complete(late.prepared[0].requestID, with: transition())
        await late.settle()
        #expect(lateCoordinator.marker == nil)
        _ = host
    }
}

// MARK: - Servicio de audio con archivos locales

private func writeWAV(seconds: Double, to url: URL) throws {
    let rate = 44_100
    let samples = Int(Double(rate) * seconds)
    var data = Data()
    func le32(_ v: Int) { var x = UInt32(v).littleEndian; data.append(Data(bytes: &x, count: 4)) }
    func le16(_ v: Int) { var x = UInt16(v).littleEndian; data.append(Data(bytes: &x, count: 2)) }
    data.append(contentsOf: Array("RIFF".utf8)); le32(36 + samples * 2); data.append(contentsOf: Array("WAVEfmt ".utf8))
    le32(16); le16(1); le16(1); le32(rate); le32(rate * 2); le16(2); le16(16)
    data.append(contentsOf: Array("data".utf8)); le32(samples * 2)
    data.append(Data(count: samples * 2))
    try data.write(to: url)
}

@MainActor
private final class AudioProbe {
    var media: Double = 0
    var seekTargets: [Double] = []
    var ended = 0
    var entered = 0
    var handovers = 0
    var progress: [(Double, Double)] = []
}

@MainActor
@Suite("Automix: el límite del empalme no es el final de la canción")
struct AutomixAudioServiceTests {
    private func fixture() throws -> (AudioPlayerService, AudioProbe, URL, URL, () -> Void) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("automix-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let songURL = directory.appendingPathComponent("song.wav")
        let fileURL = directory.appendingPathComponent("transition.wav")
        try writeWAV(seconds: 2, to: songURL)
        try writeWAV(seconds: 2, to: fileURL)
        let suite = "AutomixAudio.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let probe = AudioProbe()
        let audio = AudioPlayerService(
            preferences: defaults, preferencePrefix: "test", isRendering: { _ in true },
            seekExecutor: { _, time, completion in probe.seekTargets.append(time.seconds); completion(true) },
            measuredTime: { _ in probe.media })
        audio.skipsSplicePrerollForTesting = true // estas pruebas ejercitan la máquina de estados, no el audio del sistema
        audio.onTrackDidEnd = { probe.ended += 1 }
        audio.onSpliceEntered = { probe.entered += 1 }
        audio.onPlaybackProgress = { probe.progress.append(($0, $1)) }
        let cleanup = { audio.stop(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        return (audio, probe, songURL, fileURL, cleanup)
    }

    private func start(_ audio: AudioPlayerService, song: URL, playbackID: UUID = UUID(), duration: Double = 200) {
        audio.play(urlString: song.absoluteString, expectedDuration: duration, playbackID: playbackID)
        audio.pause() // sin reproducir de verdad: el tiempo lo simula la prueba
        audio.isPlaying = true
        audio.duration = duration
    }

    private func drain() async { for _ in 0..<10 { await Task.yield() } }

    /// Da por hecho el cambio al reproductor del archivo (el reloj de host real lo prueba `AutomixTwoPlayerTests`).
    private func switchNow(_ audio: AudioPlayerService) async {
        audio.completeSwitchForTesting()
        await drain()
    }

    @Test("La preferencia está apagada por defecto, se guarda y avisa")
    func preference() throws {
        let suite = "AutomixPref.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let audio = AudioPlayerService(preferences: defaults, preferencePrefix: "test")
        #expect(audio.automixEnabled == false)
        var seen: [Bool] = []
        audio.onAutomixEnabledChanged = { seen.append($0) }
        audio.automixEnabled = true
        audio.automixEnabled = true
        #expect(seen == [true])
        #expect(AudioPlayerService(preferences: defaults, preferencePrefix: "test").automixEnabled)
        #expect(!AudioPlayerService(preferences: defaults, preferencePrefix: "other").automixEnabled)
        #expect(!(audio.avPlayer is AVQueuePlayer), "el empalme ya no usa una cola: dos AVPlayer")
    }

    @Test("Armar no toca el reproductor ni el elemento que suena; desarmar descarta el segundo reproductor")
    func armAndDisarm() async throws {
        let (audio, probe, songURL, fileURL, cleanup) = try fixture()
        defer { cleanup() }
        start(audio, song: songURL)
        probe.media = 40
        let player = audio.avPlayer
        let item = try #require(player.currentItem)
        let before = item.forwardPlaybackEndTime
        let volume = player.volume
        let plan = AudioSplice(asset: AVURLAsset(url: fileURL), nextVideoID: "B", timeline: transition().timeline)
        #expect(audio.armSplice(plan) == .armed)
        #expect(audio.spliceStage == .armed)
        #expect(audio.spliceNextVideoID == "B")
        await drain()
        #expect(audio.avPlayer === player && player.currentItem === item, "el reproductor y el elemento de la canción siguen siendo los mismos")
        #expect(item.forwardPlaybackEndTime == before, "no se toca forwardPlaybackEndTime")
        #expect(player.volume == volume && player.rate == 0 || player.rate == 1)
        let diagnostics = try #require(audio.spliceDiagnostics)
        #expect(["idle", "sin empalme", "prerolling", "prerolled"].contains(diagnostics.phase))
        audio.disarmSplice()
        #expect(audio.spliceStage == .none)
        #expect(audio.spliceDiagnostics == nil)
        #expect(audio.avPlayer === player && player.currentItem === item)
        #expect(audio.armSplice(AudioSplice(asset: AVURLAsset(url: fileURL), nextVideoID: "B", timeline: transition(cut: 30).timeline)) == .tooLate)
    }

    @Test("Con el archivo ya cargado, sustituirlo por otro (con otro corte si aún cabe) es posible; si el corte ya quedó atrás, no")
    func replace() async throws {
        let (audio, probe, songURL, fileURL, cleanup) = try fixture()
        defer { cleanup() }
        start(audio, song: songURL)
        probe.media = 40
        let plan = AudioSplice(asset: AVURLAsset(url: fileURL), nextVideoID: "B", timeline: transition().timeline)
        #expect(!audio.canReplaceSplice)
        #expect(audio.armSplice(plan) == .armed)
        #expect(audio.canReplaceSplice)
        #expect(audio.replaceSplice(plan) == .armed)
        // El plan de stems puede tener otro corte: se acepta si todavía cabe el fundido.
        #expect(audio.replaceSplice(AudioSplice(asset: AVURLAsset(url: fileURL), nextVideoID: "B", timeline: transition(cut: 101, overlapStart: 12, overlapEnd: 24).timeline)) == .armed)
        #expect(audio.spliceNextVideoID == "B")
        // Pero no si a esta altura el corte nuevo ya quedó atrás (la canción va por el segundo 40).
        #expect(audio.replaceSplice(AudioSplice(asset: AVURLAsset(url: fileURL), nextVideoID: "B", timeline: transition(cut: 20).timeline)) == .unavailable)
        #expect(audio.spliceStage == .armed)
    }

    @Test("Llegar al límite del empalme no es el fin del tema ni llama a playNext; el archivo toma el relevo")
    func boundaryIsNotEnd() async throws {
        let (audio, probe, songURL, fileURL, cleanup) = try fixture()
        defer { cleanup() }
        start(audio, song: songURL)
        probe.media = 99
        #expect(audio.armSplice(AudioSplice(asset: AVURLAsset(url: fileURL), nextVideoID: "B", timeline: transition().timeline)) == .armed)

        // Cerca de la duración mostrada (200 s): con el empalme armado no cuenta como final.
        probe.media = 199.9
        audio.samplePlaybackProgress()
        #expect(probe.ended == 0)

        probe.media = 99
        let old = audio.avPlayer
        await switchNow(audio) // el segundo reproductor toma el relevo
        #expect(probe.ended == 0)
        #expect(probe.entered == 1)
        #expect(audio.spliceStage == .inFile)
        #expect(audio.avPlayer !== old)
        #expect(old.currentItem == nil)
        #expect(!audio.hasReachedEnd)

        // Segundo 10 del archivo = segundo 110 de la canción anterior; el final mostrado no se dispara
        // aunque el archivo supere la duración de esa canción.
        probe.media = 10
        audio.samplePlaybackProgress()
        #expect(audio.currentTime == 110)
        #expect(probe.ended == 0)
        audio.duration = 105
        audio.samplePlaybackProgress()
        #expect(audio.currentTime == 105)
        #expect(probe.ended == 0)
    }

    @Test("Tras el traspaso, la canción siguiente carga en el mismo reproductor y suena: no queda pausado, mudo ni vacío")
    func nextSongAfterHandoverIsAudible() async throws {
        let (audio, probe, songURL, fileURL, cleanup) = try fixture()
        defer { cleanup() }
        start(audio, song: songURL)
        probe.media = 50
        #expect(audio.armSplice(AudioSplice(asset: AVURLAsset(url: fileURL), nextVideoID: "B", timeline: transition().timeline)) == .armed)
        await switchNow(audio)
        audio.onSpliceHandover = { audio.completeHandover(playbackID: UUID()) }
        probe.media = 14
        audio.samplePlaybackProgress()
        #expect(audio.spliceStage == .handedOver)
        let filePlayer = audio.avPlayer

        // The file ends; the next song loads into the service's player, which is the file's player.
        audio.play(urlString: songURL.absoluteString, playbackID: UUID())
        #expect(audio.spliceStage == .none)
        #expect(audio.avPlayer === filePlayer)
        #expect(audio.avPlayer.currentItem != nil, "the new song's item must not be emptied by the old splice")
        #expect(audio.avPlayer.volume > 0, "the new song must not be muted by the old splice")
    }

    @Test("Traspaso: al segundo handover se avisa; después el tiempo es el de la siguiente y su final sí cuenta")
    func handover() async throws {
        let (audio, probe, songURL, fileURL, cleanup) = try fixture()
        defer { cleanup() }
        start(audio, song: songURL)
        probe.media = 50
        #expect(audio.armSplice(AudioSplice(asset: AVURLAsset(url: fileURL), nextVideoID: "B", timeline: transition().timeline)) == .armed)
        await switchNow(audio)
        var handovers = 0
        let nextID = UUID()
        audio.onSpliceHandover = { handovers += 1; audio.completeHandover(playbackID: nextID) }

        probe.media = 13.9
        audio.samplePlaybackProgress()
        #expect(handovers == 0)
        probe.media = 14
        audio.samplePlaybackProgress()
        #expect(handovers == 1)
        #expect(audio.spliceStage == .handedOver)
        #expect(audio.duration == 210)
        #expect(audio.timeBias == 90)
        #expect(audio.currentTime == 0) // el segundo 14 del archivo es anterior a la entrada de la siguiente (negativo → 0)

        // En el archivo el segundo 120 es el segundo 30 de la siguiente.
        probe.media = 120
        audio.samplePlaybackProgress()
        #expect(audio.currentTime == 30)
        #expect(handovers == 1)
        #expect(probe.ended == 0)

        // Saltar a 60 de la siguiente: segundo 150 del archivo (item) sin tocar el reloj de la canción.
        #expect(audio.seekRoute(forSeconds: 60) == .direct)
        #expect(audio.seek(toSeconds: 60))
        #expect(abs((probe.seekTargets.last ?? 0) - 150) < 1e-6)
        await drain() // el salto se da por resuelto y vuelve a contar el final
        #expect(audio.seekRoute(forSeconds: 2) == .restream)

        // Final de la siguiente: segundo 300 del archivo = 210 de la canción.
        probe.media = 299.8
        audio.samplePlaybackProgress()
        #expect(probe.ended == 1)
    }

    @Test("Saltos antes del traspaso se mapean al archivo; con la cola armada se puede entrar en él")
    func seekMapping() async throws {
        let (audio, probe, songURL, fileURL, cleanup) = try fixture()
        defer { cleanup() }
        start(audio, song: songURL)
        probe.media = 50
        let plan = AudioSplice(asset: AVURLAsset(url: fileURL), nextVideoID: "B", timeline: transition().timeline)
        #expect(audio.seekRoute(forSeconds: 120) == .direct)
        #expect(audio.armSplice(plan) == .armed)
        #expect(audio.seekRoute(forSeconds: 30) == .direct)
        #expect(audio.seekRoute(forSeconds: 103) == .intoFile)
        #expect(audio.seekRoute(forSeconds: 150) == .disarmThenDirect)
        #expect(audio.seekIntoSplice(toSeconds: 103))
        let deadline = Date().addingTimeInterval(4)
        while audio.spliceStage != .inFile, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(audio.spliceStage == .inFile)
        #expect(probe.entered == 1)
        #expect(audio.spliceDiagnostics?.prerolledFileSeconds == 3) // 103 de la canción = segundo 3 del archivo
        #expect(audio.seekRoute(forSeconds: 90) == .restream)
    }

    @Test("Encadenado A→B→C: la canción que suena del archivo anterior se puede empalmar con su propio mapa")
    func chained() async throws {
        let (audio, probe, songURL, fileURL, cleanup) = try fixture()
        defer { cleanup() }
        start(audio, song: songURL)
        probe.media = 50
        #expect(audio.armSplice(AudioSplice(asset: AVURLAsset(url: fileURL), nextVideoID: "B", timeline: transition().timeline)) == .armed)
        await switchNow(audio)
        audio.onSpliceHandover = { audio.completeHandover(playbackID: UUID()) }
        probe.media = 20
        audio.samplePlaybackProgress()
        #expect(audio.spliceStage == .handedOver)

        // B suena del archivo con sesgo 90 (segundo 30 de B = 120 del elemento): se arma el siguiente empalme.
        probe.media = 120
        let second = transition(from: "B", to: "C", cut: 150, bOffset: 40, fileDuration: 260)
        let plan = AudioSplice(asset: AVURLAsset(url: fileURL), nextVideoID: "C", timeline: second.timeline)
        let player = audio.avPlayer
        #expect(audio.armSplice(plan) == .armed)
        #expect(audio.spliceStage == .armed)
        #expect(audio.avPlayer === player, "armar no toca al reproductor de B")
        // Desarmar devuelve el mapa de B.
        audio.disarmSplice()
        #expect(audio.spliceStage == .handedOver)
        #expect(audio.timeBias == 90)
        #expect(audio.armSplice(plan) == .armed)
        // Un tick del reloj de AVPlayer puede llegar mientras se cede el turno: que no alcance el traspaso (segundo 14 del archivo).
        probe.media = 5
        await switchNow(audio)
        #expect(audio.spliceStage == .inFile)
        #expect(audio.timeBias == -150)
        #expect(audio.spliceNextVideoID == "C")
        #expect(audio.avPlayer !== player)
        #expect(probe.ended == 0)
    }

    @Test("Un tema nuevo o stop() limpian el empalme y el mapa")
    func resets() async throws {
        let (audio, probe, songURL, fileURL, cleanup) = try fixture()
        defer { cleanup() }
        start(audio, song: songURL)
        probe.media = 50
        #expect(audio.armSplice(AudioSplice(asset: AVURLAsset(url: fileURL), nextVideoID: "B", timeline: transition().timeline)) == .armed)
        audio.play(urlString: songURL.absoluteString, expectedDuration: 100, playbackID: UUID())
        #expect(audio.spliceStage == .none)
        #expect(audio.timeBias == 0)
        audio.stop()
        #expect(audio.avPlayer.currentItem == nil)
    }
}

// MARK: - PlayerViewModel

@MainActor
@Suite("Automix: reproductor")
struct AutomixPlayerViewModelTests {
    private func track(_ id: String, album: String? = nil) -> SongItemRecord {
        SongItemRecord(videoId: id, title: "Tema \(id)", artists: "Artista", album: nil, duration: "3:30", thumbnail: nil,
                       artistId: nil, albumId: album, setVideoId: "occ-\(id)", isVideo: false, isUpload: false, library: nil)
    }

    private func makePlayer(probe: AudioProbe? = nil) throws -> (PlayerViewModel, AudioPlayerService, () -> Void) {
        let suite = "AutomixVM.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let audio = AudioPlayerService(preferences: defaults, preferencePrefix: "test", measuredTime: { _ in probe?.media ?? 0 })
        audio.skipsSplicePrerollForTesting = true
        let player = PlayerViewModel(rustCore: nil, audioService: audio)
        return (player, audio, { audio.stop(); defaults.removePersistentDomain(forName: suite) })
    }

    @Test("El contexto expone el siguiente conocido, el álbum, la repetición y no inventa uno si la cola no apunta al tema")
    func context() throws {
        let (player, _, cleanup) = try makePlayer()
        defer { cleanup() }
        #expect(player.automixContext() == nil)
        let songs = [track("A", album: "X"), track("B", album: "X"), track("C")]
        player.queueManager.replaceQueue(with: songs, startingAt: 0, context: .custom(title: "Cola"))
        player.currentTrack = songs[0]
        var automix = try #require(player.automixContext())
        #expect(automix.current == AutomixSong(videoID: "A", isUpload: false, albumID: "X"))
        #expect(automix.next?.videoID == "B")
        #expect(!automix.hasStarted && !automix.jamActive && !automix.repeatOne)
        #expect(AutomixEligibility.reason(automix) == .sameAlbum)

        player.queueManager.isRepeat = true
        automix = try #require(player.automixContext())
        #expect(automix.repeatOne)

        player.currentTrack = songs[2] // no es el de la cola
        automix = try #require(player.automixContext())
        #expect(automix.next == nil)
        player.queueManager.isRepeat = false
        player.queueManager.selectTrack(at: 2)
        player.currentTrack = songs[2]
        #expect(player.automixContext()?.next == nil, "el último tema no tiene siguiente conocido")
    }

    @Test("La preferencia del reproductor llega al coordinador y se persiste")
    func enabling() throws {
        let (player, audio, cleanup) = try makePlayer()
        defer { cleanup() }
        #expect(player.automixEnabled == false)
        #expect(player.automix.status == .off)
        player.automixEnabled = true
        #expect(audio.automixEnabled)
        #expect(player.automix.isEnabled)
        #expect(player.automix.status == .idle)
        player.automixEnabled = false
        #expect(player.automix.status == .off)
    }

    @Test("Traspaso: la cola avanza a la siguiente sin resolver su stream y el tiempo pasa a ser el suyo")
    func handoverAdvancesQueue() async throws {
        let probe = AudioProbe()
        let (player, audio, cleanup) = try makePlayer(probe: probe)
        defer { cleanup() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("automix-vm-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wav = directory.appendingPathComponent("a.wav")
        try writeWAV(seconds: 2, to: wav)

        let songs = [track("A"), track("B"), track("C")]
        player.queueManager.replaceQueue(with: songs, startingAt: 0, context: .custom(title: "Cola"))
        player.currentTrack = songs[0]
        let token = player.experimentalLyricsPlaybackIdentity
        audio.play(urlString: wav.absoluteString, expectedDuration: 200, playbackID: token)
        audio.pause()
        audio.isPlaying = true
        audio.duration = 200

        let plan = AudioSplice(asset: AVURLAsset(url: wav), nextVideoID: "B", timeline: transition().timeline)
        #expect(audio.armSplice(plan) == .armed)
        audio.completeSwitchForTesting()
        for _ in 0..<10 { await Task.yield() }
        #expect(audio.spliceStage == .inFile)
        #expect(player.currentTrack?.videoId == "A", "hasta el traspaso la interfaz sigue en la anterior")

        probe.media = 14
        audio.samplePlaybackProgress()
        #expect(player.currentTrack?.videoId == "B")
        #expect(player.queueManager.currentIndex == 1)
        #expect(player.queueManager.currentTrack?.videoId == "B")
        #expect(player.experimentalLyricsPlaybackIdentity != token)
        #expect(audio.spliceStage == .handedOver)
        #expect(audio.duration == 210)
        #expect(!player.isLoadingStream)
        #expect(player.errorMessage == nil)
        #expect(player.automixContext()?.next?.videoID == "C")
        #expect(player.automixContext()?.hasStarted == true)
    }

    @Test("Un Jam que empieza con el archivo sonando suelta todo el estado de Automix y respeta la preferencia")
    func jamStartsDuringTheFile() async throws {
        let probe = AudioProbe()
        let (player, audio, cleanup) = try makePlayer(probe: probe)
        defer { cleanup() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("automix-jam-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wav = directory.appendingPathComponent("a.wav")
        try writeWAV(seconds: 2, to: wav)

        player.automixEnabled = true
        let songs = [track("A"), track("B"), track("C")]
        player.queueManager.replaceQueue(with: songs, startingAt: 0, context: .custom(title: "Cola"))
        player.currentTrack = songs[0]
        audio.play(urlString: wav.absoluteString, expectedDuration: 200, playbackID: player.experimentalLyricsPlaybackIdentity)
        audio.pause()
        audio.isPlaying = true
        audio.duration = 200
        probe.media = 50
        #expect(audio.armSplice(AudioSplice(asset: AVURLAsset(url: wav), nextVideoID: "B", timeline: transition().timeline)) == .armed)
        audio.completeSwitchForTesting()
        for _ in 0..<10 { await Task.yield() }
        #expect(audio.spliceStage == .inFile)

        player.beginJamSession(editor: AutomixJamEditor(), control: { _ in })
        #expect(player.isJamSessionActive)
        #expect(audio.spliceStage == .none, "el Jam toma el control por la vía normal: sin archivo en cola ni mapa de tiempos")
        #expect(audio.timeBias == 0)
        #expect(audio.avPlayer.currentItem == nil)
        #expect(player.automix.currentKey == nil)
        #expect(player.automix.marker == nil)
        #expect(audio.automixEnabled, "la preferencia guardada no cambia")
        #expect(player.automix.isEnabled)

        // Con el Jam activo no se prepara nada aunque haya tema y siguiente.
        player.queueManager.mirrorSession(current: track("j0"), upcoming: [track("j1")], title: "Spotify Jam")
        player.currentTrack = track("j0")
        player.automix.reconcile()
        #expect(player.automix.currentKey == nil)
        #expect(AutomixEligibility.reason(try #require(player.automixContext())) == .jam)

        // Al terminar el Jam la preferencia sigue activa.
        player.endJamSession(restore: .discard)
        #expect(!player.isJamSessionActive)
        #expect(audio.automixEnabled)
        #expect(player.automix.status == .idle, "estado: \(AutomixCoordinator.describe(player.automix.status))")
    }

    @Test("Con un Jam, la presentación del estado es «no disponible en Jam» en ambos idiomas")
    func jamStatusText() {
        #expect(AutomixStatusPresentation.text(for: .unavailable(.jam), language: .es) == "No disponible en Jam")
        #expect(AutomixStatusPresentation.text(for: .unavailable(.jam), language: .en) == "Not available in Jam")
    }
}

@MainActor
private final class AutomixJamEditor: QueueSessionEditing {
    func sessionAppend(_ tracks: [SongItemRecord]) {}
    func sessionInsert(_ tracks: [SongItemRecord], atUpcomingRow row: Int) {}
    func sessionMove(fromUpcomingRow from: Int, toUpcomingRow to: Int) {}
    func sessionRemove(upcomingRow row: Int) {}
    func sessionRejected(_ reason: QueueSessionRejection) {}
}

// MARK: - Diagnóstico

@Suite("Automix: registro circular y saneado")
struct AutomixEventLogTests {
    private let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    @Test("Conserva los más recientes en orden y descarta los más antiguos al llenarse")
    func ringBuffer() {
        var log = AutomixEventLog(capacity: 3)
        for index in 1...5 { log.append(source: "t", message: "m\(index)") }
        #expect(log.entries.map(\.message) == ["m3", "m4", "m5"])
        #expect(log.entries.map(\.id) == [3, 4, 5], "los ids siguen creciendo aunque se descarte")
        #expect(log.lastID == 5)
        log.clear()
        #expect(log.entries.isEmpty && log.lastID == nil)
        log.append(source: "t", message: "otra")
        #expect(log.entries.first?.id == 6, "limpiar no reinicia los ids")
    }

    @Test("La capacidad por defecto es de 1000 y nunca se supera")
    func defaultCapacity() {
        var log = AutomixEventLog()
        for index in 0..<2500 { log.append(source: "t", message: "\(index)") }
        #expect(log.capacity == 1000)
        #expect(log.entries.count == 1000)
        #expect(log.entries.first?.message == "1500")
        #expect(log.entries.last?.message == "2499")
        #expect(AutomixEventLog(capacity: 0).capacity == 1)
    }

    @Test("Marca de tiempo con milisegundos y texto copiable de todo el registro")
    func formatting() {
        let date = Date(timeIntervalSince1970: 3_723.5) // 01:02:03.500 UTC
        #expect(AutomixEventLog.timestamp(date, calendar: utc) == "01:02:03.500")
        var log = AutomixEventLog(capacity: 10)
        log.append(source: "coord", message: "uno", date: date)
        log.append(source: "player", message: "dos", date: date.addingTimeInterval(0.5))
        #expect(log.text(calendar: utc) == "01:02:03.500 [coord] uno\n01:02:04.000 [player] dos")
    }

    @MainActor
    @Test("El almacén sanea antes de guardar y limpiar vacía el búfer")
    func store() {
        let store = AutomixDiagnostics(capacity: 5)
        store.record("vm", "falló https://rr1.googlevideo.com/videoplayback?sig=ABCDEF&key=x en el intento")
        #expect(store.log.entries.count == 1)
        #expect(!store.log.text().contains("googlevideo"))
        #expect(store.log.entries[0].message.contains("<url>"))
        store.clear()
        #expect(store.log.entries.isEmpty)
    }

    @Test("Nunca quedan URLs, cookies, cabeceras ni tokens largos")
    func sanitizer() {
        let samples = [
            "error sending request for url (https://rr3---sn-x.googlevideo.com/videoplayback?expire=1&sig=SECRET)",
            "Cookie: SAPISID=abc123; SID=zzz",
            "authorization: Bearer ya29.AAAA",
            "set-cookie=__Secure-3PSID=xyz",
            "x-goog-visitor-id: CgtBQkNERUZHSElK",
            "po_token=MnQ_" + String(repeating: "a", count: 80),
            "file:///Users/x/Library/Caches/a.wav no",
            "sig=abc"
        ]
        for sample in samples {
            let clean = AutomixLogSanitizer.sanitize(sample)
            for forbidden in ["googlevideo", "SECRET", "abc123", "zzz", "Bearer", "ya29", "xyz", "CgtBQ", "://", String(repeating: "a", count: 40)] {
                #expect(!clean.contains(forbidden), "\(forbidden) sobrevivió en: \(clean)")
            }
        }
        // Lo normal queda intacto.
        let plain = "petición 1A2B3C4D: dQw4w9WgXcQ → 9bZkp7q19f0; aCut 100.00, modelo listo"
        #expect(AutomixLogSanitizer.sanitize(plain) == plain)
        #expect(AutomixLogSanitizer.sanitize("request 8e1f6a52-1111-4222-8333-944455556666") == "request 8e1f6a52-1111-4222-8333-944455556666")
    }
}

@Suite("Automix: cuentas atrás y acciones de depuración")
struct AutomixCountdownTests {
    // cut 100, overlap 8…20, handover 14, fileDuration 300, bOffset 90
    let timeline = transition().timeline

    @Test("Con el empalme armado el archivo aún no suena: el segundo 0 del archivo es aCut")
    func armed() throws {
        // Elemento = canción a 70 s, sin sesgo.
        let c = try #require(AutomixCountdown.make(timeline: timeline, stage: .armed, itemSeconds: 70, timeBias: 0))
        #expect(c.fileSeconds == -30)
        #expect(c.untilCut == 30)
        #expect(c.untilOverlapStart == 38)
        #expect(c.untilOverlapEnd == 50)
        #expect(c.untilHandover == 44)
        #expect(c.untilFileEnd == 330)
        // Canción que suena de un archivo anterior (sesgo 40): el elemento está 40 s por delante de lo mostrado.
        let chained = try #require(AutomixCountdown.make(timeline: timeline, stage: .armed, itemSeconds: 110, timeBias: 40))
        #expect(chained.untilCut == 30)
    }

    @Test("Con el archivo sonando se mide sobre el tiempo del archivo y los hitos pasados son negativos")
    func inFile() throws {
        let c = try #require(AutomixCountdown.make(timeline: timeline, stage: .inFile, itemSeconds: 10, timeBias: -100))
        #expect(c.fileSeconds == 10)
        #expect(c.untilCut == -10)
        #expect(c.untilOverlapStart == -2)
        #expect(c.untilOverlapEnd == 10)
        #expect(c.untilHandover == 4)
        #expect(c.untilFileEnd == 290)
        let after = try #require(AutomixCountdown.make(timeline: timeline, stage: .handedOver, itemSeconds: 120, timeBias: 90))
        #expect(after.untilHandover == -106)
        #expect(after.untilFileEnd == 180)
    }

    @Test("Sin empalme o con valores no finitos no hay cuenta atrás")
    func none() {
        #expect(AutomixCountdown.make(timeline: timeline, stage: .none, itemSeconds: 5, timeBias: 0) == nil)
        #expect(AutomixCountdown.make(timeline: timeline, stage: .armed, itemSeconds: .nan, timeBias: 0) == nil)
        #expect(AutomixCountdown.make(timeline: timeline, stage: .inFile, itemSeconds: 1, timeBias: .infinity) == nil)
    }

    @Test("Saltar antes del corte: 10 s antes si la canción aún no llegó; nada si ya pasó")
    func jump() {
        #expect(AutomixDebugActions.jumpTarget(cut: 100, position: 20) == 90)
        #expect(AutomixDebugActions.jumpTarget(cut: 100, position: 95) == 90, "puede ser hacia atrás")
        #expect(AutomixDebugActions.jumpTarget(cut: 100, position: 100) == nil)
        #expect(AutomixDebugActions.jumpTarget(cut: 100, position: 140) == nil)
        #expect(AutomixDebugActions.jumpTarget(cut: 6, position: 1) == 0, "no baja de 0")
        #expect(AutomixDebugActions.jumpTarget(cut: .nan, position: 1) == nil)
    }
}

@MainActor
@Suite("Automix: acciones de depuración del coordinador")
struct AutomixCoordinatorDebugTests {
    private func make(_ ctx: AutomixContext?, enabled: Bool = true) -> (AutomixCoordinator, FakeHost, LogBox) {
        let host = FakeHost()
        host.current = ctx
        let box = LogBox()
        let coordinator = AutomixCoordinator(enabled: enabled, log: { box.lines.append($0) })
        coordinator.host = host
        return (coordinator, host, box)
    }

    @MainActor final class LogBox { var lines: [String] = [] }

    @Test("«Preparar ahora» fuerza una petición nueva; respeta ajuste, Jam y elegibilidad")
    func prepareNow() async {
        let (coordinator, host, log) = make(context(started: false))
        coordinator.reconcile(); await host.settle()
        #expect(host.prepared.count == 1, "la rápida ya se pidió sin esperar a que el tema suene")
        #expect(coordinator.prepareNow())
        await host.settle()
        #expect(host.prepared.count == 2)
        #expect(host.cancelled.count == 1)
        #expect(coordinator.request?.forced == true)
        #expect(coordinator.request?.phase == .preparing)
        #expect(log.lines.contains { $0.contains("forzada") })

        // Con un Jam no se fuerza nada.
        let (jam, jamHost, jamLog) = make(context(jam: true, started: false))
        #expect(!jam.prepareNow())
        #expect(jamHost.prepared.isEmpty)
        #expect(jamLog.lines.contains { $0.contains("Jam") })
        // Apagado, tampoco.
        let (off, offHost, _) = make(context(started: false), enabled: false)
        #expect(!off.prepareNow())
        #expect(offHost.prepared.isEmpty)
        // Mismo álbum, tampoco.
        let (album, albumHost, _) = make(context(current: song("A", album: "X"), next: song("B", album: "X"), started: false))
        #expect(!album.prepareNow())
        #expect(albumHost.prepared.isEmpty)
    }

    @Test("«Preparar ahora» reemplaza una petición anterior y la cancela")
    func prepareNowReplaces() async {
        let (coordinator, host, _) = make(context())
        coordinator.reconcile(); await host.settle()
        let first = host.prepared[0].requestID
        #expect(coordinator.prepareNow())
        await host.settle()
        #expect(host.cancelled == [first])
        #expect(host.prepared.count == 2)
    }

    @Test("«Cancelar preparación» cancela en el core, queda registrada y no se reintenta sola")
    func cancel() async {
        let (coordinator, host, log) = make(context())
        coordinator.reconcile(); await host.settle()
        #expect(coordinator.isPreparing)
        let id = host.prepared[0].requestID
        coordinator.cancelPreparation()
        await host.settle()
        #expect(host.cancelled == [id])
        #expect(coordinator.request?.phase == .cancelled)
        #expect(coordinator.request?.note == "cancelada a mano")
        #expect(!coordinator.isPreparing)
        #expect(coordinator.status == .idle)
        coordinator.reconcile()
        #expect(host.prepared.count == 1, "no vuelve a pedir por sí sola")
        #expect(log.lines.contains { $0.contains("cancelada a mano") })
        coordinator.cancelPreparation() // sin nada en curso: no hace nada
        #expect(host.cancelled.count == 1)
        #expect(coordinator.prepareNow(), "pero se puede pedir a mano")
    }

    @Test("La petición guarda id, hora, fase, mensaje crudo saneado y el registro entregado")
    func requestInfo() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let host = FakeHost(); host.current = context()
        let coordinator = AutomixCoordinator(enabled: true, now: { clock }, log: { _ in })
        coordinator.host = host
        coordinator.reconcile(); await host.settle()
        let request = try? #require(coordinator.request)
        #expect(request?.requestedAt == clock)
        #expect(request?.phase == .preparing)
        #expect(request?.requestID == host.prepared[0].requestID)
        clock = clock.addingTimeInterval(12.5)
        #expect(request?.elapsed(now: clock) == 12.5)
        host.fail(host.prepared[0].requestID, .other)
        await host.settle()
        #expect(coordinator.request?.phase == .failed)
        #expect(coordinator.request?.failureLabel == "other")
        #expect(coordinator.request?.finishedAt == clock)

        let (ok, okHost, _) = make(context())
        ok.reconcile(); await okHost.settle()
        okHost.complete(okHost.prepared[0].requestID, with: transition())
        await okHost.settle()
        #expect(ok.request?.phase == .ready)
        #expect(ok.request?.transition?.kind == "mix")
        #expect(ok.request?.note == "empalme armado (fast)")
    }

    @Test("Los cambios de estado y las razones de descarte quedan en el registro")
    func logging() async {
        let token = UUID()
        let (coordinator, host, log) = make(context(token: token))
        coordinator.reconcile(); await host.settle()
        host.current = context(token: token, next: song("C"))
        coordinator.reconcile(); await host.settle()
        #expect(log.lines.contains { $0.contains("estado:") && $0.contains("preparando") })
        #expect(log.lines.contains { $0.contains("cambió la pareja") })
        host.current = context(token: token, next: song("C"), jam: true)
        coordinator.reconcile()
        #expect(log.lines.contains { $0.contains("Jam activo") })
        #expect(!log.lines.joined().contains("http"))
    }
}

@MainActor
@Suite("Automix: ventana de diagnóstico")
struct AutomixDiagnosticsViewTests {
    @Test("La ventana y la pastilla se dibujan en claro y oscuro con el estado vacío y con datos")
    func renders() throws {
        let suite = "AutomixDiagView.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let player = PlayerViewModel(rustCore: nil, audioService: AudioPlayerService(preferences: defaults, preferencePrefix: "diag"))
        let song = SongItemRecord(videoId: "A", title: "Tema A", artists: "Artista", album: nil, duration: "3:30", thumbnail: nil,
                                  artistId: nil, albumId: "alb", setVideoId: "occ", isVideo: false, isUpload: false, library: nil)
        player.queueManager.replaceQueue(with: [song], startingAt: 0, context: .custom(title: "Cola"))
        player.currentTrack = song
        AutomixDiagnostics.shared.record("test", "línea de prueba")
        let snapshot = player.automixDiagnosticsSnapshot()
        #expect(snapshot.current?.videoID == "A")
        #expect(snapshot.current?.queueIndex == 0)
        #expect(snapshot.next == nil)
        #expect(snapshot.eligibility == "sin siguiente conocido")
        #expect(!snapshot.canPrepareNow && !snapshot.canCancel && snapshot.jumpTarget == nil)
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: AutomixDiagnosticsView(player: player).frame(width: 680, height: 820)
                .environment(\.colorScheme, scheme))
            #expect(renderer.nsImage != nil)
            let pill = ImageRenderer(content: AutomixPill(viewModel: player).environment(\.colorScheme, scheme))
            #expect(pill.nsImage != nil)
        }
    }
}

// MARK: - Ronda 2: calidad, mejora a stems, precarga y ajustes

@Suite("Automix: estrategia de calidad")
struct AutomixStrategyTests {
    private func settings(_ quality: String, battery: Bool = true) -> AutomixSettingsValue {
        var value = AutomixSettingsValue(); value.quality = quality; value.fastOnBattery = battery; return value
    }
    private func capability(recommended: Bool, factor: Double? = 5.6) -> AutomixCapabilityValue {
        var value = AutomixCapabilityValue(); value.stemsRecommended = recommended; value.realtimeFactor = factor; value.modelReady = true; return value
    }
    private let plugged = AutomixPowerState(onBattery: false, lowPower: false)

    @Test("«Siempre rápida» nunca pide stems; «siempre con stems» sí, con o sin capacidad medida")
    func fixedQualities() {
        #expect(!AutomixStrategy.wantsStems(settings: settings("fast"), capability: capability(recommended: true), power: plugged).wants)
        #expect(AutomixStrategy.wantsStems(settings: settings("stems"), capability: nil, power: plugged).wants)
        #expect(AutomixStrategy.wantsStems(settings: settings("stems"), capability: capability(recommended: false, factor: 0.5), power: plugged).wants)
    }

    @Test("«Automática» depende de que la Mac recomiende stems")
    func automatic() {
        #expect(AutomixStrategy.wantsStems(settings: settings("auto"), capability: capability(recommended: true), power: plugged).wants)
        #expect(!AutomixStrategy.wantsStems(settings: settings("auto"), capability: capability(recommended: false, factor: 1.1), power: plugged).wants)
        #expect(!AutomixStrategy.wantsStems(settings: settings("auto"), capability: capability(recommended: false, factor: nil), power: plugged).wants)
        #expect(!AutomixStrategy.wantsStems(settings: settings("auto"), capability: nil, power: plugged).wants)
        // Un valor desconocido se trata como automático.
        #expect(AutomixStrategy.wantsStems(settings: settings("otra"), capability: capability(recommended: true), power: plugged).wants)
    }

    @Test("Con batería o bajo consumo y el ajuste activo, sólo la rápida; sin el ajuste, no importa")
    func battery() {
        for power in [AutomixPowerState(onBattery: true, lowPower: false), AutomixPowerState(onBattery: false, lowPower: true), AutomixPowerState(onBattery: true, lowPower: true)] {
            #expect(!AutomixStrategy.wantsStems(settings: settings("auto"), capability: capability(recommended: true), power: power).wants)
            #expect(!AutomixStrategy.wantsStems(settings: settings("stems"), capability: nil, power: power).wants)
            #expect(AutomixStrategy.wantsStems(settings: settings("stems", battery: false), capability: nil, power: power).wants)
        }
        #expect(AutomixStrategy.wantsStems(settings: settings("auto"), capability: capability(recommended: true), power: AutomixPowerState(onBattery: false, lowPower: false)).wants)
        // El motivo queda en el registro.
        #expect(AutomixStrategy.wantsStems(settings: settings("stems"), capability: nil, power: AutomixPowerState(onBattery: true, lowPower: false)).reason.contains("batería"))
        #expect(AutomixStrategy.wantsStems(settings: settings("stems"), capability: nil, power: AutomixPowerState(onBattery: false, lowPower: true)).reason.contains("bajo consumo"))
        #expect(AutomixPowerState.current(lowPower: true).lowPower)
    }

    @Test("La precarga lleva el tema que suena y hasta `lookahead` siguientes")
    func prefetchItems() {
        let list = ["B", "C", "D", "E"].map { song($0) }
        #expect(AutomixPrefetchPlan.items(current: song("A"), upcoming: list, lookahead: 1).map(\.videoID) == ["A", "B"])
        #expect(AutomixPrefetchPlan.items(current: song("A"), upcoming: list, lookahead: 3).map(\.videoID) == ["A", "B", "C", "D"])
        #expect(AutomixPrefetchPlan.items(current: song("A"), upcoming: list, lookahead: 9).map(\.videoID) == ["A", "B", "C", "D"])
        #expect(AutomixPrefetchPlan.items(current: song("A"), upcoming: list, lookahead: 0).map(\.videoID) == ["A", "B"])
        #expect(AutomixPrefetchPlan.items(current: song("A"), upcoming: [song("B")], lookahead: 3).map(\.videoID) == ["A", "B"])
    }

    @Test("Los ajustes viajan al core sin perder ni salirse de rango, y los prefijos nuevos se clasifican")
    func settingsAndFailures() {
        var value = AutomixSettingsValue()
        value.quality = "stems"; value.compute = "cpu"; value.lookahead = 7; value.keepModelLoaded = true; value.fastOnBattery = false; value.skipSameAlbum = false
        let record = value.record
        #expect(record.lookahead == 3)
        let back = AutomixSettingsValue(record: record)
        #expect(back.quality == "stems" && back.compute == "cpu" && back.lookahead == 3 && back.keepModelLoaded && !back.fastOnBattery && !back.skipSameAlbum)
        #expect(AutomixSettingsValue().record.lookahead == 1)
        #expect(AutomixSettingsValue().quality == "auto")
        #expect(AutomixFailure(coreMessage: "automix:model-unavailable: descargando") == .modelUnavailable)
        #expect(AutomixFailure(coreMessage: "automix:bad-quality") == .badQuality)
        #expect(AutomixFailure(coreMessage: "automix:no-cache-dir") == .noCacheDir)
        #expect(AutomixFailure.modelUnavailable.logLabel == "model-unavailable")
    }

    @Test("El registro del core trae calidad, mismo corte, segundos separados y tiempo")
    func recordFields() {
        let record = AutomixTransitionRecord(requestId: "r", fromVideoId: "A", toVideoId: "B", kind: "mix", filePath: "/tmp/a.fast.wav",
            fileDurationSeconds: 200, aCutSeconds: 100, overlapStartSeconds: 8, overlapEndSeconds: 20, bOffsetSeconds: 90,
            bEntrySeconds: 5, handoverSeconds: 14, bpmFrom: 120, bpmTo: 124, bars: 8, stemsModel: true, quality: "stems",
            sameCutAsFast: true, separatedSeconds: 36.7, elapsedSeconds: 8.7, reused: true, detail: "d")
        let value = AutomixTransition(record: record)
        #expect(value.quality == "stems" && value.sameCutAsFast && value.stemsModel)
        #expect(value.separatedSeconds == 36.7 && value.elapsedSeconds == 8.7 && value.reused)
        #expect(value.isConsistent)
    }

    @Test("Textos de capacidad y de uso de disco, en los dos idiomas")
    func texts() {
        var measured = AutomixCapabilityValue(); measured.realtimeFactor = 5.6; measured.provider = "CoreML (CPUOnly MLProgram)"
        #expect(AutomixCapabilityText.line(measured, language: .es).hasPrefix("Este equipo: 5,6× tiempo real"))
        #expect(AutomixCapabilityText.line(measured, language: .en).hasPrefix("This computer: 5.6× real time"))
        #expect(AutomixCapabilityText.line(measured, language: .es).contains("CoreML"))
        let unmeasured = AutomixCapabilityValue()
        #expect(AutomixCapabilityText.line(unmeasured, language: .es) == "Este equipo: sin medir todavía")
        #expect(AutomixCapabilityText.line(nil, language: .en) == "This computer: no capability data")
        let usage = AutomixCacheUsageValue(audioBytes: 10 << 20, stemsBytes: 70 << 20, transitionsBytes: 20 << 20, modelBytes: 210 << 20)
        #expect(usage.total == 100 << 20)
        for language in AppLanguage.allCases {
            #expect(!AutomixCacheText.cacheLine(usage, language: language).contains("settings."))
            #expect(!AutomixCacheText.modelLine(usage, capability: nil, language: language).contains("settings."))
            #expect(!AutomixCacheText.modelLine(AutomixCacheUsageValue(), capability: nil, language: language).contains("settings."))
        }
    }
}

@MainActor
@Suite("Automix: coordinador con calidad y precarga")
struct AutomixCoordinatorQualityTests {
    private func make(_ ctx: AutomixContext? = context(), quality: String = "stems", power: AutomixPowerState = AutomixPowerState(),
                      capability: AutomixCapabilityValue? = nil) -> (AutomixCoordinator, FakeHost) {
        let host = FakeHost()
        host.current = ctx
        host.settings.quality = quality
        host.settings.fastOnBattery = true
        host.power = power
        host.capability = capability
        let coordinator = AutomixCoordinator(enabled: true, log: { _ in })
        coordinator.host = host
        return (coordinator, host)
    }

    private func fastReady(_ coordinator: AutomixCoordinator, _ host: FakeHost) async {
        coordinator.reconcile(); await host.settle()
        host.complete(host.prepared[0].requestID, with: transition())
        await host.settle()
    }

    @Test("Primero la rápida; con «siempre con stems» pide enseguida la de stems y la cambia si llega antes del empalme")
    func upgradeApplied() async {
        let (coordinator, host) = make()
        await fastReady(coordinator, host)
        #expect(host.prepared.map(\.quality) == ["fast", "stems"])
        #expect(host.armed.count == 1 && host.armed[0].quality == "fast")
        #expect(coordinator.request?.upgrade.hasPrefix("pedida") == true)
        #expect(coordinator.request?.requestedQuality == "fast")
        var stems = transition(); stems.quality = "stems"; stems.stemsModel = true; stems.separatedSeconds = 36.7; stems.elapsedSeconds = 8.7
        host.complete(host.prepared[1].requestID, with: stems)
        await host.settle()
        #expect(host.replaced.count == 1 && host.replaced[0].quality == "stems")
        #expect(coordinator.request?.transition?.quality == "stems")
        #expect(coordinator.request?.upgrade.hasPrefix("aplicada") == true)
        #expect(coordinator.status == .ready(kind: "mix", bpm: 124))
        #expect(coordinator.marker != nil)
    }

    @Test("Si el empalme ya se comprometió, la de stems llega tarde y se queda la rápida")
    func upgradeTooLate() async {
        let (coordinator, host) = make()
        host.replaceOutcome = .failed
        await fastReady(coordinator, host)
        var stems = transition(); stems.quality = "stems"
        host.complete(host.prepared[1].requestID, with: stems)
        await host.settle()
        #expect(host.replaced.count == 1)
        #expect(coordinator.request?.transition?.quality == "fast")
        #expect(coordinator.request?.upgrade.hasPrefix("omitida") == true)

        // Y si el archivo ya suena, ni se intenta sustituir.
        let (second, secondHost) = make()
        await fastReady(second, secondHost)
        second.spliceEntered()
        secondHost.complete(secondHost.prepared[1].requestID, with: stems)
        await secondHost.settle()
        #expect(secondHost.replaced.isEmpty)
        #expect(second.request?.transition?.quality == "fast")
        #expect(second.request?.upgrade.hasPrefix("omitida") == true)
    }

    @Test("Sin el modelo (o con cualquier fallo) se queda la rápida sin error visible")
    func upgradeFails() async {
        let (coordinator, host) = make()
        await fastReady(coordinator, host)
        host.fail(host.prepared[1].requestID, .modelUnavailable)
        await host.settle()
        #expect(coordinator.request?.upgrade == "falló: model-unavailable")
        #expect(coordinator.status == .ready(kind: "mix", bpm: 124))
        #expect(coordinator.request?.transition?.quality == "fast")
        #expect(host.replaced.isEmpty)
    }

    @Test("Una stems con otro corte y otro solape sustituye a la rápida y mueve la marca de la barra")
    func upgradeDifferentCut() async {
        let (coordinator, host) = make()
        host.position = 20
        await fastReady(coordinator, host)
        #expect(coordinator.marker?.songSeconds == 108)
        var stems = transition(cut: 104, overlapStart: 12, overlapEnd: 28, handover: 18, bOffset: 88); stems.quality = "stems"; stems.sameCutAsFast = false; stems.kind = "mix"
        host.complete(host.prepared[1].requestID, with: stems)
        await host.settle()
        #expect(host.replaced.count == 1 && host.replaced[0].aCut == 104)
        #expect(coordinator.request?.transition?.aCut == 104)
        #expect(coordinator.request?.upgrade.contains("corte nuevo 104.00") == true)
        #expect(coordinator.marker?.songSeconds == 116, "aCut 104 + solape 12: la marca se movió de 108 a 116")
        #expect(coordinator.status == .ready(kind: "mix", bpm: 124))
    }

    @Test("Con otro corte que queda a menos de 8 s o ya atrás, la mejora se abandona; con el mismo corte se aplica igual")
    func upgradeTooClose() async {
        for (position, cut, expectApplied) in [(95.0, 104.0, false),   // a 9 s: sí; ver abajo
                                               (97.5, 104.0, false),   // a 6,5 s < 8 s
                                               (110.0, 104.0, false),  // el corte ya quedó atrás
                                               (95.0, 100.0, true)] {  // mismo corte, aunque falten 5 s
            let (coordinator, host) = make()
            host.position = 20
            await fastReady(coordinator, host)
            host.position = position
            var stems = transition(cut: cut); stems.quality = "stems"; stems.sameCutAsFast = cut == 100
            host.complete(host.prepared[1].requestID, with: stems)
            await host.settle()
            if position == 95, cut == 104 {
                #expect(host.replaced.count == 1, "a 9 s del corte nuevo sí cabe")
            } else {
                #expect((host.replaced.count == 1) == expectApplied, "posición \(position), corte \(cut)")
                #expect(coordinator.request?.upgrade.hasPrefix(expectApplied ? "aplicada" : "omitida") == true)
                if !expectApplied { #expect(coordinator.request?.transition?.quality == "fast") }
            }
        }
    }

    @Test("Si el reproductor ya no admite cambiar el archivo (arranque programado), se queda la rápida")
    func upgradeCommitted() async {
        let (coordinator, host) = make()
        host.position = 20
        await fastReady(coordinator, host)
        host.canReplace = false
        var stems = transition(cut: 104); stems.quality = "stems"
        host.complete(host.prepared[1].requestID, with: stems)
        await host.settle()
        #expect(host.replaced.isEmpty)
        #expect(coordinator.request?.upgrade.hasPrefix("omitida") == true)
        #expect(coordinator.marker?.songSeconds == 108)
    }

    @Test("Con los stems permitidos y la pareja lista, la primera petición ya es la de stems (sin pedir la rápida)")
    func pairReadyFirst() async {
        let (coordinator, host) = make(quality: "auto")
        host.pairReady = true
        coordinator.reconcile(); await host.settle()
        #expect(host.prepared.map(\.quality) == ["stems"])
        #expect(coordinator.request?.pairReadyAtRequest == true)
        var stems = transition(); stems.quality = "stems"; stems.reused = true
        host.complete(host.prepared[0].requestID, with: stems)
        await host.settle()
        #expect(host.prepared.count == 1, "ya es stems: sin mejora que pedir")
        #expect(host.armed.count == 1 && host.armed[0].quality == "stems")
        #expect(coordinator.request?.upgrade.hasPrefix("no aplica") == true)
        #expect(coordinator.request?.transition?.reused == true)
        #expect(coordinator.strategy.pairReady == true && coordinator.strategy.allowStems == true)
    }

    @Test("Pareja lista pero stems no permitidos (siempre rápida, o batería): la primera petición es la rápida")
    func pairReadyButNotAllowed() async {
        for (quality, power) in [("fast", AutomixPowerState()), ("auto", AutomixPowerState(onBattery: true, lowPower: false)), ("auto", AutomixPowerState(onBattery: false, lowPower: true))] {
            let (coordinator, host) = make(quality: quality, power: power)
            host.pairReady = true
            coordinator.reconcile(); await host.settle()
            #expect(host.prepared.map(\.quality) == ["fast"], "\(quality) \(power)")
            #expect(coordinator.strategy.allowStems == false)
            #expect(host.prefetchAllow == [false], "la precarga tampoco separa con stems")
        }
    }

    @Test("Con la rápida lista y la pareja aún sin lista, se vigila y se pide stems cuando la precarga la deja lista")
    func pollingUpgrade() async {
        let (coordinator, host) = make(quality: "auto")
        host.position = 20
        await fastReady(coordinator, host)
        #expect(host.prepared.map(\.quality) == ["fast"])
        #expect(coordinator.request?.upgrade.hasPrefix("no pedida") == true)
        coordinator.pollOnce(); await host.settle()
        #expect(host.prepared.count == 1, "pareja no lista: nada")
        host.pairReady = true
        coordinator.pollOnce(); await host.settle()
        #expect(host.prepared.map(\.quality) == ["fast", "stems"])
        #expect(coordinator.request?.upgrade.hasPrefix("pedida") == true)
        coordinator.pollOnce(); await host.settle()
        #expect(host.prepared.count == 2, "no se vuelve a pedir")
        var stems = transition(); stems.quality = "stems"
        host.complete(host.prepared[1].requestID, with: stems)
        await host.settle()
        #expect(host.replaced.count == 1)
    }

    @Test("La vigilancia no pide stems si faltan menos de 8 s para el corte, si ya se comprometió o con batería")
    func pollingGuards() async {
        let (near, nearHost) = make(quality: "auto")
        nearHost.position = 20
        await fastReady(near, nearHost)
        nearHost.position = 95   // aCut 100: faltan 5 s
        nearHost.pairReady = true
        near.pollOnce(); await nearHost.settle()
        #expect(nearHost.prepared.count == 1)
        #expect(near.request?.upgrade.hasPrefix("omitida") == true)

        let (battery, batteryHost) = make(quality: "auto", power: AutomixPowerState(onBattery: true, lowPower: false))
        batteryHost.position = 20
        await fastReady(battery, batteryHost)
        batteryHost.pairReady = true
        battery.pollOnce(); await batteryHost.settle()
        #expect(batteryHost.prepared.count == 1)
    }

    @Test("No pide stems con «siempre rápida», con batería o sin capacidad suficiente en automático")
    func noUpgrade() async {
        for (quality, power, capability) in [
            ("fast", AutomixPowerState(), nil as AutomixCapabilityValue?),
            ("stems", AutomixPowerState(onBattery: true, lowPower: false), nil),
            ("stems", AutomixPowerState(onBattery: false, lowPower: true), nil),
            ("auto", AutomixPowerState(), nil),
            ("auto", AutomixPowerState(), { var c = AutomixCapabilityValue(); c.stemsRecommended = false; c.realtimeFactor = 1.0; return c }())
        ] {
            let (coordinator, host) = make(quality: quality, power: power, capability: capability)
            await fastReady(coordinator, host)
            #expect(host.prepared.map(\.quality) == ["fast"], "\(quality) \(power)")
            #expect(coordinator.request?.upgrade.hasPrefix("no pedida") == true)
        }
        var good = AutomixCapabilityValue(); good.stemsRecommended = true; good.realtimeFactor = 5.6
        let (auto, host) = make(quality: "auto", capability: good)
        await fastReady(auto, host)
        #expect(host.prepared.map(\.quality) == ["fast", "stems"])
    }

    @Test("Cambiar de tema o apagar cancela también la mejora en curso")
    func upgradeCancelled() async {
        let token = UUID()
        let (coordinator, host) = make(context(token: token))
        await fastReady(coordinator, host)
        let stemsID = host.prepared[1].requestID
        host.current = context(token: token, next: song("C"))
        coordinator.reconcile(); await host.settle()
        #expect(host.cancelled.contains(stemsID))
        #expect(host.disarmCount >= 1)
    }

    @Test("La precarga se pide con el tema y los siguientes, no se repite y se cancela con Jam, apagado o cambio de cuenta")
    func prefetch() async {
        let token = UUID()
        let (coordinator, host) = make(context(token: token, upcoming: [song("B"), song("C"), song("D")], lookahead: 2), quality: "fast")
        coordinator.reconcile(); await host.settle()
        #expect(host.prefetched.map { $0.map(\.videoID) } == [["A", "B", "C"]])
        coordinator.reconcile(); coordinator.reconcile()
        #expect(host.prefetched.count == 1)
        // La cola cambia: lista nueva.
        host.current = context(token: token, next: song("X"), upcoming: [song("X"), song("C")], lookahead: 2)
        coordinator.reconcile(); await host.settle()
        #expect(host.prefetched.last?.map(\.videoID) == ["A", "X", "C"])
        #expect(coordinator.prefetchItems?.map(\.videoID) == ["A", "X", "C"])
        coordinator.prefetchScheduled(error: nil)
        #expect(coordinator.prefetchStatus.contains("programada"))
        // Jam: se cancela.
        host.current = context(token: token, jam: true)
        coordinator.reconcile(); await host.settle()
        #expect(host.prefetchCancels == 1)
        #expect(coordinator.prefetchItems == nil)
        // Se retoma al terminar el Jam.
        host.current = context(token: token, upcoming: [song("B")])
        coordinator.reconcile(); await host.settle()
        #expect(host.prefetched.count == 3)
        // Cambio de cuenta.
        coordinator.cancelPrefetch(reason: "cambio de cuenta")
        #expect(host.prefetchCancels == 2)
        coordinator.cancelPrefetch(reason: "otra vez")
        #expect(host.prefetchCancels == 2, "sin precarga no hay nada que cancelar")
        // Apagado.
        coordinator.reconcile(); await host.settle()
        #expect(host.prefetched.count == 4)
        coordinator.setEnabled(false)
        #expect(host.prefetchCancels == 3)
    }

    @Test("Sin vaivén: misma pareja con otro token, cola que se rehace o repetidos reconcile no cancelan ni vuelven a pedir")
    func noChurn() async throws {
        let token = UUID()
        let (coordinator, host) = make(context(token: token), quality: "fast")
        coordinator.reconcile(); await host.settle()
        host.complete(host.prepared[0].requestID, with: transition())
        await host.settle()
        #expect(host.prepared.count == 1 && host.armed.count == 1)
        // Reinicio o salto del mismo tema (otro token): la petición ya renderizada se conserva y el archivo se vuelve a entregar.
        for _ in 0..<5 {
            host.current = context(token: UUID(), started: true)
            coordinator.reconcile(); await host.settle()
        }
        #expect(host.prepared.count == 1, "una sola petición para la pareja")
        #expect(host.cancelled.isEmpty)
        #expect(host.armed.count == 6, "se entrega de nuevo a cada ocurrencia, sin volver a preparar")
        // La cola se rehace un instante (siguiente desconocido) y vuelve.
        host.current = context(token: host.current!.token, next: nil, upcoming: [])
        coordinator.reconcile()
        host.current = context(token: host.current!.token)
        coordinator.reconcile(); await host.settle()
        #expect(host.prepared.count == 1 && host.cancelled.isEmpty)
    }

    @Test("Si el core cancela la petición (no nosotros), no se vuelve a pedir al instante; se reintenta con espera, dos veces como mucho")
    func coreCancelBackoff() async {
        let host = FakeHost()
        host.current = context()
        host.settings.quality = "fast"
        var clock = Date(timeIntervalSince1970: 1_000)
        let coordinator = AutomixCoordinator(enabled: true, now: { clock }, retryDelay: 10, log: { _ in })
        coordinator.host = host
        coordinator.reconcile(); await host.settle()
        host.fail(host.prepared[0].requestID, .cancelled)
        await host.settle()
        #expect(coordinator.status == .idle)
        for _ in 0..<10 { coordinator.reconcile(); await host.settle() }
        #expect(host.prepared.count == 1, "los reconcile repetidos no la piden otra vez")
        coordinator.pollOnce(); await host.settle()
        #expect(host.prepared.count == 1, "aún dentro de la espera")
        clock = clock.addingTimeInterval(11)
        coordinator.pollOnce(); await host.settle()
        #expect(host.prepared.count == 2, "primer reintento tras esperar")
        host.fail(host.prepared[1].requestID, .cancelled)
        await host.settle()
        clock = clock.addingTimeInterval(11)
        coordinator.pollOnce(); await host.settle()
        #expect(host.prepared.count == 3, "segundo reintento")
        host.fail(host.prepared[2].requestID, .cancelled)
        await host.settle()
        clock = clock.addingTimeInterval(60)
        coordinator.pollOnce(); await host.settle()
        #expect(host.prepared.count == 3, "no más de dos reintentos")
    }

    @Test("Si la petición directa de stems falla, se pide la rápida una sola vez y no se reintenta stems para esa pareja")
    func directStemsFallback() async {
        let token = UUID()
        let (coordinator, host) = make(context(token: token), quality: "auto")
        host.pairReady = true
        coordinator.reconcile(); await host.settle()
        #expect(host.prepared.map(\.quality) == ["stems"])
        host.fail(host.prepared[0].requestID, .modelUnavailable)
        await host.settle()
        #expect(host.prepared.map(\.quality) == ["stems", "fast"])
        host.complete(host.prepared[1].requestID, with: transition())
        await host.settle()
        #expect(coordinator.status == .ready(kind: "mix", bpm: 124))
        for _ in 0..<3 { coordinator.reconcile(); await host.settle() }
        #expect(host.prepared.count == 2)
    }

    @Test("La precarga lleva allowStems según ajuste y energía, y se vuelve a pedir si éste cambia")
    func prefetchAllowStems() async {
        let (coordinator, host) = make(context(upcoming: [song("B")]), quality: "auto")
        coordinator.reconcile(); await host.settle()
        #expect(host.prefetchAllow == [true])
        host.power = AutomixPowerState(onBattery: true, lowPower: false)
        coordinator.reconcile(); await host.settle()
        #expect(host.prefetchAllow == [true, false], "al pasar a batería se pide sin stems")
        coordinator.reconcile(); await host.settle()
        #expect(host.prefetchAllow.count == 2)
        host.settings.quality = "fast"
        host.power = AutomixPowerState()
        coordinator.pollOnce()
        #expect(host.prefetchAllow == [true, false, false].dropLast() + [false] || host.prefetchAllow.last == false)
    }

    @Test("Sin temas siguientes o con repetición no hay precarga")
    func noPrefetch() async {
        let (coordinator, host) = make(context(next: nil, upcoming: []), quality: "fast")
        coordinator.reconcile(); await host.settle()
        #expect(host.prefetched.isEmpty)
        host.current = context(repeatOne: true)
        coordinator.reconcile(); await host.settle()
        #expect(host.prefetched.isEmpty)
    }
}

// MARK: - Registro persistente, memoria y exportación

@Suite("Automix: registro persistente", .serialized)
struct AutomixPersistentLogTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("automix-log-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func entry(_ n: Int, source: String = "t", message: String? = nil) -> AutomixPersistedLine {
        AutomixPersistedLine(date: Date(timeIntervalSince1970: 1_000_000 + Double(n) + 0.25), source: source, message: message ?? "línea \(n)")
    }

    @Test("Cada línea se escribe en diagnostics.log con fecha completa y se vuelve a leer igual")
    func roundTrip() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = AutomixLogFile(directory: dir, timeZone: utc)
        for n in 0..<5 { file.append(entry(n)) }
        file.flush()
        let text = try String(contentsOf: file.currentURL, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 5)
        #expect(text.hasPrefix("1970-01-12 13:46:40.250 [t] línea 0\n"))
        let read = file.readLastEntries(limit: 100)
        #expect(read == (0..<5).map { entry($0) })
        #expect(file.readLastEntries(limit: 2) == [entry(3), entry(4)])
    }

    @Test("Rota al llegar al tope: queda el actual y un solo .1, sin perder el orden")
    func rotation() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = AutomixLogFile(directory: dir, maxBytes: 1_000, timeZone: utc)
        for n in 0..<60 { file.append(entry(n)) }
        file.flush()
        let manager = FileManager.default
        #expect(manager.fileExists(atPath: file.currentURL.path))
        #expect(manager.fileExists(atPath: file.previousURL.path))
        let current = (try manager.attributesOfItem(atPath: file.currentURL.path)[.size] as? NSNumber)?.intValue ?? 0
        let previous = (try manager.attributesOfItem(atPath: file.previousURL.path)[.size] as? NSNumber)?.intValue ?? 0
        #expect(current <= 1_000 && previous <= 1_000 && current > 0 && previous > 0)
        // Hay exactamente dos archivos (el actual y un .1): las rotaciones anteriores se descartan.
        #expect(try manager.contentsOfDirectory(atPath: dir.path).sorted() == ["diagnostics.log", "diagnostics.log.1"])
        // Lo que queda es el final del registro, completo y en orden.
        let read = file.readLastEntries(limit: 1_000)
        #expect(read.last == entry(59))
        let numbers = read.compactMap { Int($0.message.dropFirst(6)) }
        #expect(numbers == Array(numbers.first!...59))
        #expect(numbers.count < 60 && numbers.count > 10)
        #expect(file.fullText().split(separator: "\n").count == read.count)
    }

    @Test("Volver a abrir el archivo continúa donde se quedó (tamaño y rotación incluidos)")
    func reopen() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = AutomixLogFile(directory: dir, maxBytes: 600, timeZone: utc)
        for n in 0..<8 { first.append(entry(n)) }
        first.flush()
        let second = AutomixLogFile(directory: dir, maxBytes: 600, timeZone: utc)
        for n in 8..<40 { second.append(entry(n)) }
        second.flush()
        let numbers = second.readLastEntries(limit: 1_000).compactMap { Int($0.message.dropFirst(6)) }
        #expect(numbers.last == 39)
        #expect(numbers == Array(numbers.first!...39), "sin huecos ni repeticiones entre sesiones")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 2)
    }

    @Test("Las líneas ilegibles se saltan al recargar y `reset` borra los dos archivos")
    func unreadableAndReset() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = AutomixLogFile(directory: dir, timeZone: utc)
        file.append(entry(1))
        file.flush()
        let handle = try FileHandle(forWritingTo: file.currentURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("basura sin formato\n\n[x] sin fecha\n".utf8))
        try handle.close()
        file.append(entry(2))
        file.flush()
        #expect(file.readLastEntries(limit: 10) == [entry(1), entry(2)])
        file.reset()
        #expect(file.fullText().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.currentURL.path))
    }

    @Test("Un mensaje largo se conserva hasta 4 KB, en una línea y cortado en un límite de carácter")
    func entryCap() {
        let ok = String(repeating: "é", count: 1_500) // 3 000 B
        #expect(AutomixLogLimits.normalize(ok) == ok)
        let multi = "uno\ndos\r\ntres\rcuatro"
        #expect(AutomixLogLimits.normalize(multi) == "uno\\ndos\\ntres\\ncuatro")
        let long = String(repeating: "ñ", count: 5_000) // 10 000 B
        let cut = AutomixLogLimits.normalize(long)
        #expect(cut.hasPrefix(String(repeating: "ñ", count: 2_048)))
        #expect(cut.contains("…[truncado: 5904 B más]"))
        #expect(cut.utf8.count <= AutomixLogLimits.maxEntryBytes + 40)
        #expect(!cut.contains("\n"))
        #expect(AutomixLogLimits.normalize("x", maxBytes: 4) == "x")
    }

    @Test("Los fallos van al registro unificado como error y lo demás como aviso")
    func levels() {
        #expect(AutomixLogLevel.classify("sin transición (other) tras 3.1 s: error de red") == .error)
        #expect(AutomixLogLevel.classify("stems sin resultado (model-unavailable)") == .notice)
        #expect(AutomixLogLevel.classify("la precarga del archivo falló") == .error)
        #expect(AutomixLogLevel.classify("armar imposible: sin elemento observado") == .error)
        #expect(AutomixLogLevel.classify("estado: preparando → lista (mix, 124 bpm)") == .notice)
        #expect(AutomixLogLevel.classify("traspaso: la interfaz pasa a la siguiente canción") == .notice)
    }

    @MainActor
    @Test("El almacén escribe lo saneado en disco, un cierre no lo pierde y la sesión siguiente lo recarga en la ventana")
    func storePersistsAndReloads() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = AutomixDiagnostics(capacity: 50)
        first.configurePersistence(directory: dir, maxBytes: 1 << 20)
        first.record("coord", "petición 1A2B3C4D: A → B")
        first.record("vm", "falló https://rr1.googlevideo.com/videoplayback?sig=SECRETO&key=k con un mensaje\nen dos líneas")
        first.record("player", String(repeating: "x", count: 100) + " " + String(repeating: "mensaje largo de error ", count: 150))
        first.file?.flush()
        let disk = first.file?.fullText() ?? ""
        #expect(disk.contains("[coord] petición 1A2B3C4D: A → B"))
        #expect(!disk.contains("googlevideo") && !disk.contains("SECRETO"), "nada sin sanear llega al archivo")
        #expect(disk.contains("<url>"))
        #expect(!disk.contains("\\r"))
        #expect(disk.split(separator: "\n").allSatisfy { $0.utf8.count < 4_300 }, "tope por entrada")
        #expect(disk.contains("mensaje largo de error"), "el mensaje largo se conserva (no se trunca por debajo de 4 KB)")

        // «Cierre inesperado»: otro almacén sobre la misma carpeta recarga lo anterior.
        let second = AutomixDiagnostics(capacity: 50)
        second.configurePersistence(directory: dir, maxBytes: 1 << 20)
        let messages = second.log.entries.map(\.message)
        #expect(messages.contains("petición 1A2B3C4D: A → B"))
        #expect(messages.contains { $0.hasPrefix("falló <url>") })
        #expect(messages.last?.hasPrefix("inicio de sesión — 4 líneas recargadas") == true || messages.last?.hasPrefix("inicio de sesión —") == true)
        // Y las recargadas conservan fecha y origen.
        let reloaded = try #require(second.log.entries.first { $0.message.hasPrefix("petición") })
        #expect(reloaded.source == "coord")
        // Limpiar la ventana no borra el archivo.
        second.clear()
        second.file?.flush()
        #expect(second.log.entries.isEmpty)
        #expect((second.file?.fullText() ?? "").contains("petición 1A2B3C4D"))
    }
}

@Suite("Automix: memoria y exportación")
struct AutomixMemoryAndExportTests {
    @Test("La huella de la app es legible y el pico nunca baja de ella")
    func footprint() throws {
        let memory = try #require(AutomixMemory.current())
        #expect(memory.footprint > 10 << 20, "una app de pruebas ocupa más de 10 MB")
        #expect(memory.peak >= memory.footprint)
        #expect(AutomixMemory.gigabytes(3 << 30) == "3.00 GB")
    }

    @Test("Avisa al cruzar 2, 4 y 8 GB una sola vez por subida y se rearma al bajar")
    func thresholds() {
        var watcher = AutomixMemoryWatcher()
        let gb: UInt64 = 1 << 30
        #expect(watcher.update(footprint: gb).isEmpty)
        #expect(watcher.update(footprint: 2 * gb) == [2 * gb])
        #expect(watcher.update(footprint: 3 * gb).isEmpty, "no repite el de 2 GB")
        // Un salto grande cruza varios a la vez, en orden.
        #expect(watcher.update(footprint: 9 * gb) == [4 * gb, 8 * gb])
        #expect(watcher.update(footprint: 9 * gb).isEmpty)
        // Baja un 10 % por debajo de 8 GB y de 4 GB: se rearman.
        #expect(watcher.update(footprint: 3 * gb).isEmpty)
        #expect(watcher.update(footprint: 4 * gb) == [4 * gb])
        // Oscilar justo bajo el umbral no vuelve a avisar.
        #expect(watcher.update(footprint: 4 * gb - 1_000).isEmpty)
        #expect(watcher.update(footprint: 4 * gb).isEmpty)
        #expect(AutomixMemoryWatcher.defaultThresholds == [2 << 30, 4 << 30, 8 << 30])
    }

    @MainActor
    @Test("Al cruzar un umbral el almacén deja una línea con la huella, el pico y la fase de Automix; no repite")
    func thresholdLine() {
        let store = AutomixDiagnostics(capacity: 20)
        store.phaseProvider = { "coordinador preparando; empalme none" }
        var current = AutomixMemoryInfo(footprint: 1 << 30, peak: 1 << 30)
        store.memoryReader = { current }
        store.checkMemory()
        #expect(store.log.entries.isEmpty)
        current = AutomixMemoryInfo(footprint: 5 << 30, peak: 5 << 30)
        store.checkMemory()
        let lines = store.log.entries.map(\.message)
        #expect(lines.count == 2, "cruzó 2 y 4 GB a la vez")
        #expect(lines.allSatisfy { $0.contains("fase de Automix: coordinador preparando") && $0.contains("5.00 GB") })
        #expect(lines[0].contains("cruzó 2 GB") && lines[1].contains("cruzó 4 GB"))
        store.checkMemory()
        #expect(store.log.entries.count == 2)
        current = AutomixMemoryInfo(footprint: 12 << 30, peak: 12 << 30)
        store.checkMemory()
        #expect(store.log.entries.last?.message.contains("cruzó 8 GB") == true)
        store.memoryReader = { nil }
        store.checkMemory()
        #expect(store.log.entries.count == 3)
    }

    @MainActor
    @Test("La exportación lleva cabecera, el estado, todo el registro persistido y el del core, saneado")
    func export() throws {
        let suite = "AutomixExport.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let player = PlayerViewModel(rustCore: nil, audioService: AudioPlayerService(preferences: defaults, preferencePrefix: "export"))
        var snapshot = player.automixDiagnosticsSnapshot()
        snapshot.memory = AutomixMemoryInfo(footprint: 12 << 30, peak: 13 << 30)
        let text = AutomixDiagnosticsExport.render(
            header: ["Fecha: x", "App: 1 (2)"], snapshot: snapshot,
            persistedLog: "2026-11-16 10:00:00.000 [coord] uno\n2026-11-16 10:00:01.000 [vm] dos\n",
            coreLog: "1700000000 ok fast A→B 2.1s\n1700000001 error https://rr1.googlevideo.com/x?sig=ZZZ\n")
        #expect(text.contains("=== Diagnóstico de Automix"))
        #expect(text.contains("Fecha: x"))
        #expect(text.contains("=== Estado actual ==="))
        #expect(text.contains("Memoria: huella 12.00 GB"))
        #expect(text.contains("pico 13.00 GB"))
        #expect(text.contains("Estado del coordinador:"))
        #expect(text.contains("[coord] uno") && text.contains("[vm] dos"))
        #expect(text.contains("=== Registro del core (automix.log) ==="))
        #expect(text.contains("1700000000 ok fast A→B 2.1s"))
        #expect(!text.contains("googlevideo") && !text.contains("ZZZ"), "el registro del core también se sanea")
        // Sin core ni registro: lo dice, no falla.
        let empty = AutomixDiagnosticsExport.render(header: [], snapshot: snapshot, persistedLog: "", coreLog: nil)
        #expect(empty.contains("(vacío)") && empty.contains("(no existe o está vacío)"))
    }

    @Test("El .txt y la carpeta: nombre con marca de tiempo y lectura del automix.log del core")
    func files() throws {
        let utc = TimeZone(identifier: "UTC")!
        #expect(AutomixDiagnosticsFiles.stamp(Date(timeIntervalSince1970: 3_723), timeZone: utc) == "19700101-010203")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("automix-core-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(AutomixDiagnosticsFiles.readCoreLog(directory: dir) == nil)
        try "línea del core\n".write(to: dir.appendingPathComponent("automix.log"), atomically: true, encoding: .utf8)
        #expect(AutomixDiagnosticsFiles.readCoreLog(directory: dir) == "línea del core\n")
        #expect(AutomixDiagnosticsFiles.header(directory: dir).contains { $0.hasPrefix("Carpeta de registros: ") })
    }
}
