import Foundation
import Observation

/// Resultado de entregar la transición al reproductor.
enum AutomixArmOutcome: Equatable, Sendable {
    /// El archivo quedó cargado en un segundo reproductor, listo para empalmar en el corte.
    case armed
    /// Sin uso en el empalme de dos reproductores (se conserva por compatibilidad con las pruebas).
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
    /// Cambia el archivo armado por otro de la misma pareja y el mismo corte (la versión de stems), si el empalme
    /// aún no se comprometió.
    func automixReplace(_ transition: AutomixTransition) async -> AutomixArmOutcome
    func automixDisarm()
    /// La cola cambió su siguiente tema mientras el archivo ya sonaba: se abandona la mezcla.
    func automixAbortMixing()
    func automixCacheDirectory() -> URL
    /// `SideBCore.automixModelReady()`, o nil sin core (sólo diagnóstico).
    func automixModelReady() -> Bool?
    func automixSettings() -> AutomixSettingsValue
    func automixCapability() -> AutomixCapabilityValue?
    func automixPower() -> AutomixPowerState
    /// Precarga del core: `items[0]` es el tema que suena, el resto los siguientes. Vuelve enseguida.
    func automixPrefetch(_ items: [AutomixSong])
    func automixCancelPrefetch()
}

/// Decide cuándo pedir la transición, la descarta cuando deja de valer y refleja su estado para la UI.
/// No conoce AVFoundation ni el core: todo pasa por `AutomixHost`.
///
/// Estrategia (PLAN-024, ronda 2): en cuanto el siguiente tema es conocido se pide la versión `"fast"` (sin modelo,
/// segundos), sin esperar a que el tema actual haya sonado; después, si el ajuste y la capacidad lo recomiendan y no
/// se está con batería o bajo consumo, se pide `"stems"` y se cambia sólo si llega antes de que el empalme se comprometa.
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
    /// Lista de precarga vigente y su estado, para el diagnóstico.
    @ObservationIgnored private(set) var prefetchItems: [AutomixSong]?
    @ObservationIgnored private(set) var prefetchRequestedAt: Date?
    @ObservationIgnored private(set) var prefetchStatus = "sin precarga"

    @ObservationIgnored weak var host: (any AutomixHost)?
    @ObservationIgnored private(set) var isEnabled: Bool

    private enum Stage { case preparing, ready, mixing, failed }
    private struct Plan {
        var key: AutomixPlanKey
        var requestID: String
        var stage: Stage
        var task: Task<Void, Never>?
        /// Transición vigente (la rápida, o la de stems cuando la sustituye).
        var transition: AutomixTransition?
        /// El reproductor aceptó el archivo.
        var armed = false
        var arming = false
        var upgradeRequestID: String?
        var upgradeTask: Task<Void, Never>?
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
        guard isEnabled else {
            teardown(reason: "Automix apagado"); cancelPrefetch(reason: "Automix apagado"); status = .off; return
        }
        guard let host, let context = host.automixContext() else { teardown(reason: "sin tema o contexto"); status = .idle; return }
        reconcilePrefetch(context)

        let key = context.next.map { AutomixPlanKey(token: context.token, from: context.current.videoID, to: $0.videoID) }
        // Mismo plan: se conserva (también el fallido, que no se reintenta solo) mientras siga siendo elegible;
        // con el archivo ya sonando no hay vuelta atrás.
        if let plan, let key, plan.key == key, plan.stage == .mixing || AutomixEligibility.reason(context) == nil {
            armIfNeeded(context: context)
            return
        }

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
        // La versión rápida no necesita que el tema actual haya sonado: sólo conocer el siguiente.
        guard let next = context.next, let key else { status = .idle; return }
        start(key: key, from: context.current, to: next, host: host, forced: false)
    }

    /// Depuración: pide una transición ya. Respeta el ajuste, el Jam y la elegibilidad; descarta cualquier plan anterior.
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
        if request?.upgrade.hasPrefix("pedida") == true { request?.upgrade = "omitida: el traspaso ocurrió antes" }
        plan?.task?.cancel()
        if let upgrade = plan?.upgradeRequestID, plan?.stage != .failed { host?.automixCancel(requestID: upgrade) }
        plan?.upgradeTask?.cancel()
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
        log("el reproductor soltó el archivo (falló al cargar o al empalmar)")
        request?.note = "el archivo falló al cargar o al empalmar"
        var failed = current
        failed.stage = .failed
        failed.armed = false
        plan = failed
        status = .unavailable(.failed)
    }

    /// Descarta preparación y empalme en curso (salto, cambio de cola, cuenta, Jam, apagado).
    func teardown(reason: String = "descartada") {
        marker = nil
        guard let plan else { return }
        plan.task?.cancel()
        plan.upgradeTask?.cancel()
        if let upgrade = plan.upgradeRequestID {
            host?.automixCancel(requestID: upgrade)
            request?.upgrade = "cancelada: \(reason)"
        }
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

    // MARK: - Precarga

    private func reconcilePrefetch(_ context: AutomixContext) {
        guard !context.jamActive else { cancelPrefetch(reason: "Jam activo"); return }
        guard !context.repeatOne else { cancelPrefetch(reason: "repetición de un tema"); return }
        guard !context.upcoming.isEmpty else { cancelPrefetch(reason: "sin temas siguientes"); return }
        let items = AutomixPrefetchPlan.items(current: context.current, upcoming: context.upcoming, lookahead: context.lookahead)
        guard items != prefetchItems else { return }
        prefetchItems = items
        prefetchRequestedAt = now()
        prefetchStatus = "en curso"
        log("precarga: \(items.map(\.videoID).joined(separator: " → ")) (adelanto \(context.lookahead))")
        host?.automixPrefetch(items)
    }

    /// Cancela la precarga del core (apagado, Jam, cambio de cuenta).
    func cancelPrefetch(reason: String) {
        guard prefetchItems != nil else { return }
        prefetchItems = nil
        prefetchStatus = "cancelada: \(reason)"
        log("precarga cancelada: \(reason)")
        host?.automixCancelPrefetch()
    }

    /// La llamada `prefetchAutomix` volvió (o falló): sólo para el diagnóstico.
    func prefetchScheduled(error: String?) {
        prefetchStatus = error.map { "falló: \($0)" } ?? "programada en el core (corre en segundo plano)"
        if let error { log("precarga falló: \(error)") }
    }

    // MARK: - Preparación

    private func start(key: AutomixPlanKey, from: AutomixSong, to: AutomixSong, host: any AutomixHost, forced: Bool) {
        let requestID = UUID().uuidString
        let request = AutomixRequest(requestID: requestID, from: from, to: to, cacheDirectory: host.automixCacheDirectory(), quality: "fast")
        let started = now()
        let model = host.automixModelReady().map { $0 ? "listo" : "no descargado" } ?? "desconocido"
        log("petición \(Self.short(requestID)) [fast]: \(from.videoID) → \(to.videoID)\(forced ? " (forzada)" : ""); modelo \(model)")
        self.request = AutomixRequestInfo(requestID: requestID, from: from, to: to, requestedAt: started, finishedAt: nil,
                                          phase: .preparing, forced: forced, rawError: nil, failureLabel: nil,
                                          transition: nil, note: nil, requestedQuality: "fast", upgrade: "sin decidir")
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
            request?.upgrade = "no aplica"
            markFailed(.failed)
            return
        }
        log("lista \(Self.short(requestID)) [\(transition.quality)]: \(transition.kind) \(String(format: "%.0f", transition.displayBPM)) bpm, compases \(transition.bars), "
            + "modelo \(transition.stemsModel ? "sí" : "no"), aCut \(String(format: "%.2f", transition.aCut)), traspaso \(String(format: "%.2f", transition.handover)) "
            + "en archivo, core \(String(format: "%.1f", transition.elapsedSeconds)) s (separó \(String(format: "%.1f", transition.separatedSeconds)) s), "
            + "total \(String(format: "%.1f", seconds)) s — \(transition.detail)")
        request?.phase = .ready
        request?.transition = transition
        plan?.stage = .ready
        plan?.transition = transition
        status = .ready(kind: transition.kind, bpm: transition.displayBPM)

        // ¿Hay que intentar la versión de stems? Se decide con los ajustes y la capacidad de ahora.
        if let host {
            let decision = AutomixStrategy.wantsStems(settings: host.automixSettings(), capability: host.automixCapability(), power: host.automixPower())
            log("mejora a stems: \(decision.wants ? "sí" : "no") — \(decision.reason)")
            if decision.wants {
                startUpgrade(key: key, from: transition, host: host)
            } else {
                request?.upgrade = "no pedida: \(decision.reason)"
            }
        }
        if let host, let context = host.automixContext(), context.hasStarted { armIfNeeded(context: context) }
        else { log("el tema aún no suena: el archivo se entregará al reproductor cuando empiece") }
    }

    // MARK: - Entrega al reproductor

    private func armIfNeeded(context: AutomixContext) {
        guard context.hasStarted, var current = plan, current.stage == .ready, !current.armed, !current.arming,
              let transition = current.transition, let host else { return }
        current.arming = true
        plan = current
        let key = current.key
        let requestID = current.requestID
        Task { [weak self] in
            let outcome = await host.automixArm(transition)
            self?.armed(key: key, requestID: requestID, transition: transition, outcome: outcome)
        }
    }

    private func armed(key: AutomixPlanKey, requestID: String, transition: AutomixTransition, outcome: AutomixArmOutcome) {
        // El tema pudo cambiar mientras el reproductor cargaba el archivo.
        guard plan?.key == key else {
            if outcome == .armed || outcome == .enteredLate { host?.automixDisarm() }
            return
        }
        plan?.arming = false
        switch outcome {
        case .armed:
            plan?.armed = true
            request?.note = "empalme armado (\(plan?.transition?.quality ?? transition.quality))"
            marker = AutomixProgressMarker(transition: plan?.transition ?? transition)
        case .enteredLate:
            plan?.armed = true
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

    // MARK: - Mejora a stems

    private func startUpgrade(key: AutomixPlanKey, from fast: AutomixTransition, host: any AutomixHost) {
        guard plan?.key == key, plan?.upgradeRequestID == nil else { return }
        let requestID = UUID().uuidString
        let request = AutomixRequest(requestID: requestID, from: AutomixSong(videoID: key.from, isUpload: self.request?.from.isUpload ?? false),
                                     to: AutomixSong(videoID: key.to, isUpload: self.request?.to.isUpload ?? false),
                                     cacheDirectory: host.automixCacheDirectory(), quality: "stems")
        let started = now()
        log("petición \(Self.short(requestID)) [stems]: mejora de la versión rápida")
        self.request?.upgrade = "pedida (\(Self.short(requestID)))"
        self.request?.upgradeRequestedAt = started
        plan?.upgradeRequestID = requestID
        plan?.upgradeTask = Task { [weak self, weak host] in
            guard let host else { return }
            do {
                let transition = try await host.automixPrepare(request)
                await self?.finishUpgrade(key: key, requestID: requestID, transition: transition, fast: fast, started: started)
            } catch {
                self?.failUpgrade(key: key, requestID: requestID, error: error, started: started)
            }
        }
    }

    private func isCurrentUpgrade(_ key: AutomixPlanKey, _ requestID: String) -> Bool {
        plan?.key == key && plan?.upgradeRequestID == requestID
    }

    private func finishUpgrade(key: AutomixPlanKey, requestID: String, transition: AutomixTransition, fast: AutomixTransition, started: Date) async {
        guard isCurrentUpgrade(key, requestID) else { return }
        let seconds = now().timeIntervalSince(started)
        request?.upgradeFinishedAt = now()
        plan?.upgradeRequestID = nil
        guard transition.isConsistent, transition.fromVideoID == key.from, transition.toVideoID == key.to else {
            request?.upgrade = "descartada: contrato incoherente"
            log("stems descartada: contrato incoherente")
            return
        }
        guard transition.sameCutAsFast, abs(transition.aCut - fast.aCut) < 0.001, abs(transition.overlapStart - fast.overlapStart) < 0.001 else {
            request?.upgrade = "descartada: el corte cambió respecto de la rápida"
            log("stems descartada: no corta en el mismo sitio que la rápida")
            return
        }
        log("stems lista \(Self.short(requestID)): core \(String(format: "%.1f", transition.elapsedSeconds)) s, separó \(String(format: "%.1f", transition.separatedSeconds)) s, total \(String(format: "%.1f", seconds)) s")
        guard plan?.stage == .ready, let host else {
            request?.upgrade = "omitida: llegó tras el empalme"
            log("stems llegó tras el empalme (el archivo ya suena): se queda la rápida")
            return
        }
        if plan?.armed == true {
            let outcome = await host.automixReplace(transition)
            guard isCurrent(key, plan?.requestID ?? "") else { return }
            guard outcome == .armed else {
                request?.upgrade = "omitida: el empalme ya estaba comprometido"
                log("stems llegó con el empalme comprometido: se queda la rápida")
                return
            }
        }
        plan?.transition = transition
        request?.transition = transition
        request?.upgrade = "aplicada (\(String(format: "%.1f", seconds)) s tras pedirla)"
        request?.note = "empalme armado (stems)"
        log("la versión de stems sustituyó a la rápida antes de comprometer el empalme")
    }

    private func failUpgrade(key: AutomixPlanKey, requestID: String, error: Error, started: Date) {
        guard isCurrentUpgrade(key, requestID) else { return }
        let report = error as? AutomixFailureReport
        let failure = report?.failure ?? (error as? AutomixFailure) ?? .other
        let raw = AutomixLogSanitizer.sanitize(report?.message ?? "\(type(of: error))")
        plan?.upgradeRequestID = nil
        request?.upgradeFinishedAt = now()
        request?.upgrade = failure == .cancelled ? "cancelada" : "falló: \(failure.logLabel)"
        log("stems sin resultado (\(failure.logLabel)) tras \(String(format: "%.1f", now().timeIntervalSince(started))) s: \(raw) — se queda la rápida")
    }

    // MARK: - Fallos de la preparación rápida

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
        request?.upgrade = "no aplica"
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
