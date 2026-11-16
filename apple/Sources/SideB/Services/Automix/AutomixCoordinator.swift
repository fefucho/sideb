import Foundation
import Observation

/// Resultado de entregar la transición al reproductor.
enum AutomixArmOutcome: Equatable, Sendable {
    /// El archivo quedó en cola detrás de la canción actual; el cambio ocurre solo, en `aCut`.
    case armed
    /// El corte ya pasó pero el archivo aún es la canción tal cual: el reproductor entró en él.
    case enteredLate
    case tooLate
    case failed
}

/// Lo que el coordinador pide al reproductor. Lo implementa `PlayerViewModel`; las pruebas usan uno falso.
@MainActor
protocol AutomixHost: AnyObject {
    func automixContext() -> AutomixContext?
    func automixPrepare(_ request: AutomixRequest) async throws -> AutomixTransition
    func automixCancel(requestID: String)
    func automixArm(_ transition: AutomixTransition) async -> AutomixArmOutcome
    func automixDisarm()
    /// La cola cambió su siguiente tema mientras el archivo ya sonaba: se abandona la mezcla.
    func automixAbortMixing()
    func automixCacheDirectory() -> URL
    /// `SideBCore.automixModelReady()`, o nil sin core (sólo diagnóstico).
    func automixModelReady() -> Bool?
}

/// Decide cuándo pedir la transición, la descarta cuando deja de valer y refleja su estado para la UI.
/// No conoce AVFoundation ni el core: todo pasa por `AutomixHost`.
@MainActor
@Observable
final class AutomixCoordinator {
    enum Status: Equatable {
        case off
        /// Activado, sin nada que preparar todavía (sin tema sonando).
        case idle
        case preparing
        case ready(kind: String, bpm: Double)
        case unavailable(AutomixUnavailableReason)
        case mixing(kind: String)
    }

    private(set) var status: Status = .off {
        didSet { if status != oldValue { log("estado: \(Self.describe(oldValue)) → \(Self.describe(status))") } }
    }
    /// Dónde empieza la mezcla sobre la barra de progreso mientras haya una transición lista o sonando para la
    /// canción actual; nil si se cancela, se abandona o ya hubo traspaso.
    private(set) var marker: AutomixProgressMarker? {
        didSet {
            if marker != oldValue {
                log(marker.map { "marcador de la barra: segundo \(String(format: "%.2f", $0.songSeconds))" } ?? "marcador de la barra: quitado")
            }
        }
    }
    /// Última petición (también tras terminar), para el diagnóstico.
    @ObservationIgnored private(set) var request: AutomixRequestInfo?
    /// El plan en curso existe y está preparándose.
    var isPreparing: Bool { plan?.stage == .preparing }

    @ObservationIgnored weak var host: (any AutomixHost)?
    @ObservationIgnored private(set) var isEnabled: Bool

    private enum Stage { case preparing, ready, mixing, failed }
    private struct Plan {
        var key: AutomixPlanKey
        var requestID: String
        var stage: Stage
        var task: Task<Void, Never>?
    }
    @ObservationIgnored private var plan: Plan?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let log: @MainActor (String) -> Void

    init(enabled: Bool = false, now: @escaping () -> Date = Date.init,
         log: @escaping @MainActor (String) -> Void = { AutomixDiagnostics.shared.record("coord", $0) }) {
        self.isEnabled = enabled
        self.now = now
        self.log = log
        self.status = enabled ? .idle : .off
    }

    /// Clave del plan vigente (para pruebas).
    var currentKey: AutomixPlanKey? { plan?.key }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        marker = nil
        log("ajuste Automix: \(enabled ? "encendido" : "apagado")")
        // Apagar descarta todo; encender vuelve a evaluar desde cero (también reintenta un fallo anterior).
        teardown(reason: "cambió el ajuste")
        status = enabled ? .idle : .off
        reconcile()
    }

    /// Idempotente y barato: se llama en cada cambio de cola, de tema o de modo.
    func reconcile() {
        guard isEnabled else { teardown(reason: "Automix apagado"); status = .off; return }
        guard let host, let context = host.automixContext() else { teardown(reason: "sin tema o contexto"); status = .idle; return }

        let key = context.next.map { AutomixPlanKey(token: context.token, from: context.current.videoID, to: $0.videoID) }
        // Mismo plan: se conserva (también el fallido, que no se reintenta solo) mientras siga siendo elegible;
        // con el archivo ya sonando no hay vuelta atrás.
        if let plan, let key, plan.key == key, plan.stage == .mixing || AutomixEligibility.reason(context) == nil { return }

        // El archivo ya suena y la cola cambió su siguiente: no hay forma de «des-oír» la mezcla.
        if let plan, plan.stage == .mixing, plan.key.token == context.token, context.hasStarted {
            teardown(reason: "el siguiente tema cambió con la mezcla sonando")
            host.automixAbortMixing()
            status = .idle
            return
        }

        if let plan {
            let why: String
            if plan.key.token != context.token { why = "cambió el tema que suena" }
            else if plan.key.to != key?.to { why = "cambió el siguiente tema" }
            else if let reason = AutomixEligibility.reason(context) { why = "ya no es elegible (\(Self.describe(reason)))" }
            else { why = "contexto distinto" }
            teardown(reason: why)
        }
        if let reason = AutomixEligibility.reason(context) { status = .unavailable(reason); return }
        guard context.hasStarted, let next = context.next, let key else { status = .idle; return }
        start(key: key, from: context.current, to: next, host: host, forced: false)
    }

    /// Depuración: pide una transición ya, sin esperar a que el tema haya sonado. Respeta el ajuste, el Jam y la
    /// elegibilidad; descarta cualquier plan anterior.
    @discardableResult
    func prepareNow() -> Bool {
        guard isEnabled else { log("«Preparar ahora» ignorado: Automix está apagado"); return false }
        guard let host, let context = host.automixContext() else { log("«Preparar ahora» ignorado: no hay tema"); return false }
        if let reason = AutomixEligibility.reason(context) {
            log("«Preparar ahora» ignorado: \(Self.describe(reason))")
            status = .unavailable(reason)
            return false
        }
        guard let next = context.next else { return false }
        teardown(reason: "«Preparar ahora»")
        let key = AutomixPlanKey(token: context.token, from: context.current.videoID, to: next.videoID)
        start(key: key, from: context.current, to: next, host: host, forced: true)
        return true
    }

    /// Depuración: cancela la preparación en curso y no la reintenta sola para este par (volver a pedirla: «Preparar ahora»).
    func cancelPreparation() {
        guard var current = plan, current.stage == .preparing else { log("«Cancelar» ignorado: no hay preparación en curso"); return }
        current.task?.cancel()
        host?.automixCancel(requestID: current.requestID)
        current.stage = .failed
        current.task = nil
        plan = current
        request?.phase = .cancelled
        request?.finishedAt = now()
        request?.note = "cancelada a mano"
        log("preparación \(Self.short(current.requestID)) cancelada a mano")
        status = .idle
    }

    /// El archivo entró en reproducción: hasta el traspaso la UI sigue en la canción anterior.
    func spliceEntered() {
        guard var plan, plan.stage == .ready || plan.stage == .preparing else { return }
        guard case .ready(let kind, _) = status else { return }
        plan.stage = .mixing
        self.plan = plan
        log("el archivo ya suena (\(kind)); la interfaz sigue en la canción anterior")
        status = .mixing(kind: kind)
    }

    /// La UI ya muestra la siguiente canción; esta transición terminó su trabajo.
    func didHandover() {
        log("traspaso: la interfaz pasa a la siguiente canción")
        request?.note = "traspaso hecho"
        plan?.task?.cancel()
        plan = nil
        marker = nil
        status = isEnabled ? .idle : .off
    }

    /// El reproductor soltó el empalme porque el usuario saltó más allá de lo que el archivo cubre.
    func gaveUp() {
        guard let current = plan, current.stage == .ready else { return }
        log("empalme abandonado: el salto del usuario supera lo que el archivo reproduce igual que la canción")
        request?.note = "abandonado por un salto"
        markFailed(.tooLate)
    }

    /// El reproductor no pudo reproducir el archivo (formato, fichero borrado).
    func spliceFailed() {
        guard let current = plan else { return }
        marker = nil
        log("el reproductor soltó el archivo en cola (falló al cargar)")
        request?.note = "el archivo falló al cargar"
        var failed = current
        failed.stage = .failed
        plan = failed
        status = .unavailable(.failed)
    }

    /// Descarta preparación y empalme en curso (salto, cambio de cola, cuenta, Jam, apagado).
    func teardown(reason: String = "descartada") {
        marker = nil
        guard let plan else { return }
        plan.task?.cancel()
        switch plan.stage {
        case .preparing:
            host?.automixCancel(requestID: plan.requestID)
            request?.phase = .cancelled
            request?.finishedAt = now()
            request?.note = reason
            log("preparación \(Self.short(plan.requestID)) cancelada: \(reason)")
        case .ready, .mixing:
            host?.automixDisarm()
            request?.note = "descartada: \(reason)"
            log("transición \(Self.short(plan.requestID)) descartada (\(plan.stage == .mixing ? "sonando" : "lista")): \(reason)")
        case .failed: break
        }
        self.plan = nil
    }

    // MARK: - Preparación

    private func start(key: AutomixPlanKey, from: AutomixSong, to: AutomixSong, host: any AutomixHost, forced: Bool) {
        let requestID = UUID().uuidString
        let request = AutomixRequest(requestID: requestID, from: from, to: to, cacheDirectory: host.automixCacheDirectory())
        let started = now()
        let model = host.automixModelReady().map { $0 ? "listo" : "no descargado" } ?? "desconocido"
        log("petición \(Self.short(requestID)): \(from.videoID) → \(to.videoID)\(forced ? " (forzada)" : ""); modelo \(model)")
        self.request = AutomixRequestInfo(requestID: requestID, from: from, to: to, requestedAt: started, finishedAt: nil,
                                          phase: .preparing, forced: forced, rawError: nil, failureLabel: nil,
                                          transition: nil, note: nil)
        status = .preparing
        let task = Task { [weak self, weak host] in
            guard let host else { return }
            do {
                let transition = try await host.automixPrepare(request)
                await self?.finish(key: key, requestID: requestID, transition: transition, started: started)
            } catch {
                self?.fail(key: key, requestID: requestID, error: error, started: started)
            }
        }
        plan = Plan(key: key, requestID: requestID, stage: .preparing, task: task)
    }

    private func isCurrent(_ key: AutomixPlanKey, _ requestID: String) -> Bool {
        plan?.key == key && plan?.requestID == requestID
    }

    private func finish(key: AutomixPlanKey, requestID: String, transition: AutomixTransition, started: Date) async {
        // Una respuesta de una petición reemplazada o descartada no se aplica.
        guard isCurrent(key, requestID), plan?.stage == .preparing else { return }
        let seconds = now().timeIntervalSince(started)
        request?.finishedAt = now()
        guard transition.isConsistent, transition.fromVideoID == key.from, transition.toVideoID == key.to else {
            log("transición descartada: contrato incoherente (\(String(format: "%.1f", seconds)) s)")
            request?.phase = .failed
            request?.failureLabel = "contrato incoherente"
            request?.transition = transition
            markFailed(.failed)
            return
        }
        log("lista \(Self.short(requestID)): \(transition.kind) \(String(format: "%.0f", transition.displayBPM)) bpm, compases \(transition.bars), "
            + "modelo \(transition.stemsModel ? "sí" : "no"), aCut \(String(format: "%.2f", transition.aCut)), traspaso \(String(format: "%.2f", transition.handover)) "
            + "en archivo, preparada en \(String(format: "%.1f", seconds)) s — \(transition.detail)")
        request?.phase = .ready
        request?.transition = transition
        plan?.stage = .ready
        status = .ready(kind: transition.kind, bpm: transition.displayBPM)

        let outcome = await host?.automixArm(transition) ?? .failed
        // El tema pudo cambiar mientras el reproductor cargaba el archivo.
        guard isCurrent(key, requestID) else { if outcome == .armed || outcome == .enteredLate { host?.automixDisarm() }; return }
        switch outcome {
        case .armed:
            request?.note = "empalme armado"
            marker = AutomixProgressMarker(transition: transition)
        case .enteredLate:
            request?.note = "entrada tardía al archivo"
            marker = AutomixProgressMarker(transition: transition)
            spliceEntered()
        case .tooLate:
            request?.note = "llegó tarde: la reproducción ya pasó el punto de corte"
            log("llegó tarde: la reproducción ya pasó el punto de corte")
            markFailed(.tooLate)
        case .failed:
            request?.note = "el reproductor no pudo cargar el archivo"
            log("el reproductor no pudo armar el archivo")
            markFailed(.failed)
        }
    }

    private func fail(key: AutomixPlanKey, requestID: String, error: Error, started: Date) {
        guard isCurrent(key, requestID) else { return }
        let report = error as? AutomixFailureReport
        let failure = report?.failure ?? (error as? AutomixFailure) ?? .other
        let seconds = now().timeIntervalSince(started)
        let raw = AutomixLogSanitizer.sanitize(report?.message ?? "\(type(of: error))")
        log("sin transición (\(failure.logLabel)) tras \(String(format: "%.1f", seconds)) s: \(raw)")
        request?.finishedAt = now()
        request?.rawError = raw
        request?.failureLabel = failure.logLabel
        guard let reason = failure.reason else {
            // Cancelada por nosotros o reemplazada por una petición más nueva del mismo core.
            request?.phase = .cancelled
            if plan?.stage == .preparing { plan = nil; status = .idle }
            return
        }
        request?.phase = .failed
        markFailed(reason)
    }

    private func markFailed(_ reason: AutomixUnavailableReason) {
        marker = nil
        guard var plan else { return }
        plan.stage = .failed
        plan.task = nil
        self.plan = plan
        status = .unavailable(reason)
    }

    // MARK: - Texto de diagnóstico

    nonisolated static func short(_ requestID: String) -> String { String(requestID.prefix(8)) }

    nonisolated static func describe(_ reason: AutomixUnavailableReason) -> String {
        switch reason {
        case .jam: "Jam activo"
        case .repeatOne: "repetición de un tema"
        case .noNextTrack: "sin siguiente conocido"
        case .sameTrack: "el siguiente es el mismo tema"
        case .sameAlbum: "mismo álbum"
        case .unsupportedFormat: "formato no AAC"
        case .tooLong: "canción demasiado larga"
        case .tooLate: "llegó tarde"
        case .failed: "falló la preparación"
        }
    }

    nonisolated static func describe(_ status: Status) -> String {
        switch status {
        case .off: "apagado"
        case .idle: "activado, esperando"
        case .preparing: "preparando"
        case .ready(let kind, let bpm): "lista (\(kind), \(String(format: "%.0f", bpm)) bpm)"
        case .unavailable(let reason): "no disponible: \(describe(reason))"
        case .mixing(let kind): "mezclando (\(kind))"
        }
    }
}
